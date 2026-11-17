extends SceneTree

# Phase 1B depth-30 diagnostic (test-only, analysis only). Fixed placement, identical topology and step for every model.
# Writes ignored outputs under user://balance_results/diag/.
#
#   --script res://tests/balance/balance_relief_diag.gd -- gen=10 depth=30 cell=4,3 seconds=3600

const OUTPUT_DIR := "user://balance_results/diag"
const STEP := 0.05
const SNAPSHOTS := [60.0, 300.0, 600.0, 900.0, 1800.0, 3600.0]
const WORK_BASE := 1.10
const BASE_CAPACITY := 1.0
const MODELS := ["CONTROL", "A", "B", "C", "D"]


func _init() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var generator_level := int(options.get("gen", "10"))
	var depth := int(options.get("depth", "30"))
	var cell := _cell(options.get("cell", "4,3"))
	var seconds := float(options.get("seconds", "3600"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var summary := {"generator_level": generator_level, "depth": depth, "cell": [cell.x, cell.y], "seconds": seconds, "models": {}}
	var monotonic_violations := 0
	var formula_violations := 0
	for model_id in MODELS:
		var spec := _spec(model_id)
		var run := _run(model_id, spec, generator_level, depth, cell, seconds)
		monotonic_violations += int(run["monotonic_violations"])
		formula_violations += int(run["formula_violations"])
		summary["models"][model_id] = run["summary"]

	summary["formula_violations"] = formula_violations
	summary["monotonic_violations"] = monotonic_violations
	summary["formula_table"] = _formula_table()
	var file := FileAccess.open("%s/depth%d_gen%d_summary.json" % [OUTPUT_DIR, depth, generator_level], FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	print("DIAG depth=%d gen=%d monotonic_violations=%d formula_violations=%d" % [depth, generator_level, monotonic_violations, formula_violations])
	quit(0 if monotonic_violations == 0 and formula_violations == 0 else 1)


func _spec(model_id: String) -> Dictionary:
	for model in ComplexityRelief.phase1b_models():
		if model["id"] == model_id:
			return model["spec"]
	return {}


func _run(model_id: String, spec: Dictionary, generator_level: int, depth: int, cell: Vector2i, seconds: float) -> Dictionary:
	ComplexityRelief.active = spec
	var config := BalanceExperimentConfig.new(0.10, 1.0, WORK_BASE)
	config.apply()
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(depth), generator_level)
	var placed := manager.construct(NodeDefinitions.Type.BOOSTER, cell)
	if placed != NetworkManager.PlacementResult.OK:
		push_error("Booster placement failed at %s" % str(cell))

	var processors := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)
	var boosted_index := -1
	for index in range(processors.size()):
		if manager.graph.get_node(processors[index]).boosted:
			boosted_index = index
	var boosted_id: int = processors[boosted_index] if boosted_index >= 0 else -1

	var clock := {"now": 0.0, "first_payout": -1.0, "first_c5": -1.0, "first_c10": -1.0, "max_complexity": 0}
	var timeline: Array = []
	var cumulative := {"value": LargeNumber.from_int(0)}
	manager.payout_received.connect(func(amount: LargeNumber, _output: int, complexity: int) -> void:
		var now: float = clock["now"]
		cumulative["value"] = cumulative["value"].add(amount)
		timeline.append({"t": now, "amount": amount.to_text(), "amount_float": amount.to_float(), "complexity": complexity, "cumulative": cumulative["value"].to_text(), "cumulative_float": cumulative["value"].to_float(), "count": timeline.size() + 1})
		if clock["first_payout"] < 0.0:
			clock["first_payout"] = now)

	var snapshot_steps := {}
	for moment in SNAPSHOTS:
		if moment <= seconds:
			snapshot_steps[int(round(moment / STEP))] = moment
	var snapshots := {}
	var monotonic_violations := 0
	var formula_violations := 0
	var capacity_samples := 0
	var steps := int(round(seconds / STEP))
	for index in range(1, steps + 1):
		clock["now"] = index * STEP
		manager.step(STEP)
		if boosted_id >= 0 and index % 20 == 0:
			var complexity: int = manager.simulation.get_incoming_complexity(boosted_id)
			var relief: int = ComplexityRelief.relief_amount(complexity, spec) if not spec.is_empty() else 0
			var effective_complexity := maxi(complexity - relief, 0)
			var generic := 1.0 + LineBalance.BOOSTER_BONUS
			var expected := NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR) * generic / pow(WORK_BASE, effective_complexity)
			var actual := manager.simulation.get_effective_capacity(boosted_id)
			if absf(actual - expected) > 1e-9 * maxf(expected, 1.0):
				formula_violations += 1
			var control := NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR) * generic / pow(WORK_BASE, complexity)
			if actual + 1e-12 < control:
				monotonic_violations += 1
			capacity_samples += 1
		if snapshot_steps.has(index):
			snapshots[str(snapshot_steps[index])] = _snapshot(manager, processors, boosted_id, timeline)

	ComplexityRelief.active = {}
	BalanceExperimentConfig.restore_production()
	var csv := FileAccess.open("%s/depth%d_gen%d_%s_payouts.csv" % [OUTPUT_DIR, depth, generator_level, model_id], FileAccess.WRITE)
	csv.store_string("t,amount,amount_float,complexity,cumulative,cumulative_float,count\n")
	for event in timeline:
		csv.store_string("%s,%s,%s,%d,%s,%s,%d\n" % [event["t"], event["amount"], event["amount_float"], event["complexity"], event["cumulative"], event["cumulative_float"], event["count"]])
	csv.close()

	return {
		"monotonic_violations": monotonic_violations,
		"formula_violations": formula_violations,
		"summary": {
			"boosted_processor_index": boosted_index,
			"capacity_samples": capacity_samples,
			"payouts": timeline.size(),
			"total_payout": cumulative["value"].to_text(),
			"snapshots": snapshots,
			"windows": _windows(timeline, seconds),
		},
	}


func _snapshot(manager: NetworkManager, processors: Array, boosted_id: int, timeline: Array) -> Dictionary:
	var waiting: Array = []
	var utilisation: Array = []
	for id in processors:
		waiting.append(manager.simulation.get_waiting_total(id).to_float())
		utilisation.append(manager.simulation.get_utilization(id))
	var output := BalanceTopologies.output_id(manager)
	return {
		"payouts": timeline.size(),
		"waiting_per_processor": waiting,
		"utilisation_per_processor": utilisation,
		"boosted_waiting": waiting[processors.find(boosted_id)] if boosted_id >= 0 else -1.0,
		"output_waiting": manager.simulation.get_waiting_total(output).to_float(),
	}


# Stable metrics: revenue after the first payout, final-25% and final-300/900 s rates, and the payout interval.
func _windows(timeline: Array, seconds: float) -> Dictionary:
	var total := 0.0
	var by_moment := {}
	for moment in SNAPSHOTS:
		if moment > seconds:
			continue
		var sum := 0.0
		for event in timeline:
			if float(event["t"]) <= moment:
				sum += float(event["amount_float"])
		by_moment[str(moment)] = sum
	for event in timeline:
		total += float(event["amount_float"])
	var first := float(timeline[0]["t"]) if not timeline.is_empty() else -1.0
	var last := float(timeline[-1]["t"]) if not timeline.is_empty() else -1.0
	var interval := (last - first) / maxf(timeline.size() - 1, 1) if timeline.size() >= 2 else -1.0
	return {
		"revenue_by_moment": by_moment,
		"full_run_revenue": total,
		"full_run_rate": total / maxf(seconds, 1e-9),
		"time_first_payout": first,
		"average_payout_interval": interval,
		"final_25pct_rate": _rate_between(timeline, seconds * 0.75, seconds),
		"final_300_rate": _rate_between(timeline, seconds - 300.0, seconds),
		"final_900_rate": _rate_between(timeline, seconds - 900.0, seconds),
		"revenue_after_first_payout_rate": total / maxf(seconds - first, 1e-9) if first >= 0.0 else 0.0,
	}


func _rate_between(timeline: Array, start: float, end: float) -> float:
	var sum := 0.0
	for event in timeline:
		var time := float(event["t"])
		if time > start and time <= end:
			sum += float(event["amount_float"])
	return sum / maxf(end - start, 1e-9)


# Formula table: effective capacity for a boosted Processor at each incoming complexity, Control vs Models A-D.
func _formula_table() -> Dictionary:
	var table := {}
	for c in range(0, 41, 5):
		var row := {}
		for model_id in MODELS:
			var spec := _spec(model_id)
			var relief := ComplexityRelief.relief_amount(c, spec) if not spec.is_empty() else 0
			row[model_id] = {"relief": relief, "effective_complexity": maxi(c - relief, 0), "capacity": (1.0 + LineBalance.BOOSTER_BONUS) / pow(WORK_BASE, maxi(c - relief, 0))}
		table[str(c)] = row
	return table


func _cell(text: String) -> Vector2i:
	var parts := text.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


func _options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		var parts := arg.split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() == 2 else "1"
	return options
