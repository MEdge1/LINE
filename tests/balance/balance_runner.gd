class_name BalanceRunner
extends RefCounted

# Runs one candidate through the real simulation and records authoritative measurements. One run produces a
# window at each checkpoint it reaches (60, 300, 900 s) plus its own end. Each window reports payoff over
# [0, end], steady rates over its last 60 s, and payout-timing metrics. Each window checks conservation.

const STEP := 0.05
const SAMPLE_EVERY_STEPS := 20
const STEADY_SECONDS := 60.0
const WARMUP_SECONDS := 60.0
const CHECKPOINTS := [60, 300, 900]
const EPSILON := 0.0001


static func measure(spec: Dictionary, config: BalanceExperimentConfig, generator_level: int, seconds: float) -> Dictionary:
	return measure_built(BalanceTopologies.build(spec, generator_level), spec, config, generator_level, seconds)


# Runs an already-built network. Targeted experiments use this to change a network before measuring it.
static func measure_built(manager: NetworkManager, spec: Dictionary, config: BalanceExperimentConfig, generator_level: int, seconds: float) -> Dictionary:
	config.apply()
	var result: Dictionary = BalanceTopologies.describe(manager, spec)
	var clock := {"now": 0.0, "first_payout": -1.0, "first_c5": -1.0, "first_c10": -1.0, "max_complexity": 0}
	var payout_times: Array = []
	manager.payout_received.connect(func(_amount: LargeNumber, _output: int, complexity: int) -> void:
		var now: float = clock["now"]
		payout_times.append(now)
		if clock["first_payout"] < 0.0:
			clock["first_payout"] = now
		if complexity >= 5 and clock["first_c5"] < 0.0:
			clock["first_c5"] = now
		if complexity >= 10 and clock["first_c10"] < 0.0:
			clock["first_c10"] = now
		clock["max_complexity"] = maxi(int(clock["max_complexity"]), complexity))

	var ends := _checkpoint_seconds(seconds)
	var steps := int(round(seconds / STEP))
	var marks := {}
	for end in ends:
		var end_steps := int(round(float(end) / STEP))
		marks[end_steps] = true
		marks[end_steps - int(round(minf(STEADY_SECONDS, float(end)) / STEP))] = true
	var snapshots := {0: _snapshot(manager, clock)}
	var samples: Array = []
	for index in range(1, steps + 1):
		clock["now"] = index * STEP
		manager.step(STEP)
		if index % SAMPLE_EVERY_STEPS == 0:
			samples.append(_sample(manager, index * STEP))
		if marks.has(index):
			snapshots[index] = _snapshot(manager, clock)

	result["complexity_k"] = config.complexity_k
	result["complexity_model"] = config.complexity_model()
	result["work_base"] = config.work_base
	result["generator_level"] = generator_level
	result["seconds"] = seconds
	result["min_processor_capacity"] = _min_processor_capacity(manager)
	_add_deepest_stage(manager, result)
	var windows: Array = []
	for end in ends:
		var end_index := int(round(float(end) / STEP))
		var steady_index := end_index - int(round(minf(STEADY_SECONDS, float(end)) / STEP))
		windows.append(_window(snapshots, samples, payout_times, end_index, steady_index))
	result["windows"] = windows
	return result


# Checkpoints the run reaches, plus the run's own end so every run has a full window.
static func _checkpoint_seconds(seconds: float) -> Array:
	var ends: Array = []
	for checkpoint in CHECKPOINTS:
		if checkpoint <= seconds + EPSILON:
			ends.append(float(checkpoint))
	if ends.is_empty() or float(ends[-1]) < seconds - EPSILON:
		ends.append(seconds)
	return ends


# Deepest-stage work and speed. The deepest Processor of a chain is the last one built; its input carries
# complexity (depth - 1). Seconds per unit is the time its base capacity needs for one such unit.
static func _add_deepest_stage(manager: NetworkManager, result: Dictionary) -> void:
	var processors := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)
	var deepest_complexity := maxi(int(result["max_depth"]) - 1, 0)
	var deepest_capacity := 0.0
	if not processors.is_empty():
		deepest_capacity = manager.simulation.get_capacity(int(processors[-1])) * ComplexityModel.processing_modifier(deepest_complexity)
	result["work_multiplier_at_max_depth"] = 1.0 / ComplexityModel.processing_modifier(deepest_complexity)
	result["deepest_effective_capacity"] = deepest_capacity
	result["seconds_per_unit_at_deepest_stage"] = 1.0 / deepest_capacity if deepest_capacity > 0.0 else -1.0


static func _window(snapshots: Dictionary, samples: Array, payout_times: Array, end_index: int, steady_index: int) -> Dictionary:
	var start: Dictionary = snapshots[0]
	var end: Dictionary = snapshots[end_index]
	var steady: Dictionary = snapshots[steady_index]
	var seconds := snappedf(end_index * STEP, 0.01)
	var steady_seconds := snappedf((end_index - steady_index) * STEP, 0.01)
	var revenue: LargeNumber = end["money"].subtract(start["money"])
	var completed: LargeNumber = end["paid"].subtract(start["paid"])
	var steady_revenue: LargeNumber = end["money"].subtract(steady["money"])
	var steady_completed: LargeNumber = end["paid"].subtract(steady["paid"])

	var queue := {"sum": 0.0, "peak": 0.0, "count": 0, "bottleneck_sum": 0.0, "bottleneck_peak": 0, "steady_sum": 0.0, "steady_count": 0}
	for sample in samples:
		var time: float = sample[0]
		if time > seconds + EPSILON:
			continue
		queue["sum"] = float(queue["sum"]) + float(sample[1])
		queue["peak"] = maxf(float(queue["peak"]), float(sample[1]))
		queue["bottleneck_sum"] = float(queue["bottleneck_sum"]) + int(sample[2])
		queue["bottleneck_peak"] = maxi(int(queue["bottleneck_peak"]), int(sample[2]))
		queue["count"] = int(queue["count"]) + 1
		if time > steady_index * STEP + EPSILON:
			queue["steady_sum"] = float(queue["steady_sum"]) + float(sample[1])
			queue["steady_count"] = int(queue["steady_count"]) + 1
	var count := maxi(int(queue["count"]), 1)

	var payouts := 0
	var warm_count := 0
	var warm_first := -1.0
	var warm_last := -1.0
	for time in payout_times:
		if time > seconds + EPSILON:
			break
		payouts += 1
		if time > WARMUP_SECONDS + EPSILON:
			warm_count += 1
			warm_first = warm_first if warm_first >= 0.0 else float(time)
			warm_last = float(time)
	var steady_samples: Array = []
	for sample in samples:
		if sample[0] > seconds + EPSILON:
			break
		if sample[0] > steady_index * STEP + EPSILON:
			steady_samples.append(sample)
	var queue_growth := 0.0
	if steady_samples.size() >= 2:
		var first_sample: Array = steady_samples[0]
		var last_sample: Array = steady_samples[-1]
		queue_growth = (float(last_sample[1]) - float(first_sample[1])) / maxf(float(last_sample[0]) - float(first_sample[0]), EPSILON)

	return {
		"seconds": seconds,
		"payouts": payouts,
		"average_payout_interval": (warm_last - warm_first) / (warm_count - 1) if warm_count >= 2 else -1.0,
		"queue_growth_per_sec": queue_growth,
		"revenue_total": revenue.to_text(),
		"completed_total": completed.to_text(),
		"revenue_per_sec": revenue.to_float() / maxf(seconds, EPSILON),
		"completed_per_sec": completed.to_float() / maxf(seconds, EPSILON),
		"steady_revenue_per_sec": steady_revenue.to_float() / maxf(steady_seconds, EPSILON),
		"steady_completed_per_sec": steady_completed.to_float() / maxf(steady_seconds, EPSILON),
		"average_queue": float(queue["sum"]) / count,
		"peak_queue": float(queue["peak"]),
		"average_bottlenecks": float(queue["bottleneck_sum"]) / count,
		"peak_bottlenecks": int(queue["bottleneck_peak"]),
		"bottlenecks_end": int(end["bottlenecks"]),
		"queue_end": float(end["waiting"]),
		"time_first_payout": float(end["first_payout"]),
		"time_first_c5": float(end["first_c5"]),
		"time_first_c10": float(end["first_c10"]),
		"max_complexity": int(end["max_complexity"]),
		"produced": end["produced"].to_text(),
		"paid": end["paid"].to_text(),
		"held": end["held"].to_text(),
		"lost": end["lost"].to_text(),
		"conserved": bool(end["conserved"]),
	}


static func _snapshot(manager: NetworkManager, clock: Dictionary) -> Dictionary:
	var simulation := manager.simulation
	var summary := manager.get_network_summary()
	var held := simulation.get_held_units()
	return {
		"money": simulation.money,
		"paid": simulation.paid_units,
		"produced": simulation.produced_units,
		"held": held,
		"lost": simulation.lost_units,
		"waiting": summary["waiting"].to_float(),
		"bottlenecks": int(summary["bottlenecks"]),
		"max_complexity": int(clock["max_complexity"]),
		"first_payout": float(clock["first_payout"]),
		"first_c5": float(clock["first_c5"]),
		"first_c10": float(clock["first_c10"]),
		"conserved": simulation.paid_units.add(held).add(simulation.lost_units).compare(simulation.produced_units) == 0,
	}


static func _sample(manager: NetworkManager, time: float) -> Array:
	var summary := manager.get_network_summary()
	return [time, summary["waiting"].to_float(), int(summary["bottlenecks"])]


static func _min_processor_capacity(manager: NetworkManager) -> float:
	var lowest := -1.0
	for id in BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR):
		var capacity := manager.simulation.get_effective_capacity(id)
		if lowest < 0.0 or capacity < lowest:
			lowest = capacity
	return maxf(lowest, 0.0)
