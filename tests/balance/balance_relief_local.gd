extends SceneTree

# Phase 1B closeout: direct per-Processor metrics for representative depths (test-only, analysis only).
# Fixed legacy placement (deepest Processor, first free orthogonal cell). Control and Models A-D plus a no-Booster baseline.
# Per-second sampling. Processed units are integrated from the rolling processed rate (approximate, documented).
#
#   --script res://tests/balance/balance_relief_local.gd -- gen=10 seconds=900 depths=8,12,15,20,25,30

const OUTPUT_DIR := "user://balance_results/diag"
const STEP := 0.05
const SAMPLE_EVERY := 20
const WORK_BASE := 1.10
const MODELS := ["NONE", "CONTROL", "A", "B", "C", "D"]


func _init() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var generator_level := int(options.get("gen", "10"))
	var seconds := float(options.get("seconds", "900"))
	var depths := _ints(options.get("depths", "8,12,15,20,25,30"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var rows: Array = []
	var runs: Array = []
	for depth in depths:
		var cell := _legacy_cell(int(depth), generator_level)
		for model_id in MODELS:
			var result := _run(model_id, int(depth), generator_level, cell, seconds)
			runs.append(result["summary"])
			rows.append_array(result["rows"])
			print("LOCAL depth=%d model=%s bottleneck=%d paid300=%s paid900=%s" % [depth, model_id, result["summary"]["bottleneck_index"], result["summary"]["paid_300"], result["summary"]["paid_900"]])

	ComplexityRelief.active = {}
	BalanceExperimentConfig.restore_production()
	var csv := FileAccess.open("%s/local_gen%d_processors.csv" % [OUTPUT_DIR, generator_level], FileAccess.WRITE)
	csv.store_string("model,depth,processor_index,boosted,role,incoming_complexity,relief,effective_complexity,effective_capacity,processed_units,average_queue,peak_queue,average_utilisation,downstream_average_queue\n")
	for row in rows:
		csv.store_string("%s\n" % ",".join(PackedStringArray([str(row["model"]), str(row["depth"]), str(row["index"]), str(row["boosted"]), str(row["role"]), str(row["complexity"]), str(row["relief"]), str(row["effective_complexity"]), "%.6f" % row["capacity"], "%.3f" % row["processed"], "%.3f" % row["avg_queue"], "%.3f" % row["peak_queue"], "%.4f" % row["avg_util"], "%.3f" % row["downstream_queue"]])))
	csv.close()
	var file := FileAccess.open("%s/local_gen%d_runs.json" % [OUTPUT_DIR, generator_level], FileAccess.WRITE)
	file.store_string(JSON.stringify(runs, "\t"))
	file.close()
	quit(0)


func _legacy_cell(depth: int, generator_level: int) -> Vector2i:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(depth), generator_level)
	var processors := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)
	var deepest: Vector2i = manager.layout.get_node_cell(processors[-1])
	for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
		var neighbour: Vector2i = deepest + offset
		if manager.layout.contains_cell(neighbour) and manager.layout.is_cell_free(neighbour):
			return neighbour
	return Vector2i(-1, -1)


func _spec(model_id: String) -> Dictionary:
	if model_id == "CONTROL":
		return {"kind": "none", "stacks": true}
	for model in ComplexityRelief.phase1b_models():
		if model["id"] == model_id:
			return model["spec"]
	return {}


func _run(model_id: String, depth: int, generator_level: int, cell: Vector2i, seconds: float) -> Dictionary:
	var has_booster := model_id != "NONE"
	var spec := _spec(model_id) if has_booster else {}
	ComplexityRelief.active = spec
	var config := BalanceExperimentConfig.new(0.10, 1.0, WORK_BASE)
	config.apply()
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(depth), generator_level)
	if has_booster:
		manager.construct(NodeDefinitions.Type.BOOSTER, cell)
	var processors := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)
	var count := processors.size()

	var clock := {"now": 0.0, "first_payout": -1.0, "first_c5": -1.0, "first_c10": -1.0, "max_complexity": 0}
	manager.payout_received.connect(func(_amount: LargeNumber, _output: int, _complexity: int) -> void:
		if clock["first_payout"] < 0.0:
			clock["first_payout"] = clock["now"])

	var processed := PackedFloat64Array()
	processed.resize(count)
	var queue_sum := PackedFloat64Array()
	queue_sum.resize(count)
	var queue_peak := PackedFloat64Array()
	queue_peak.resize(count)
	var util_sum := PackedFloat64Array()
	util_sum.resize(count)
	var samples := 0
	var paid_300 := "0"
	var paid_900 := "0"
	var steps := int(round(seconds / STEP))
	for index in range(1, steps + 1):
		clock["now"] = index * STEP
		manager.step(STEP)
		if index % SAMPLE_EVERY == 0:
			samples += 1
			for position in range(count):
				var id: int = processors[position]
				processed[position] += manager.simulation.telemetry.processed_rate(id) * (STEP * SAMPLE_EVERY)
				var queued := manager.simulation.get_waiting_total(id).to_float()
				queue_sum[position] += queued
				queue_peak[position] = maxf(queue_peak[position], queued)
				util_sum[position] += manager.simulation.get_utilization(id)
		if index == int(round(300.0 / STEP)):
			paid_300 = BalanceRunner._snapshot(manager, clock)["paid"].to_text()
	paid_900 = BalanceRunner._snapshot(manager, clock)["paid"].to_text()

	var rows: Array = []
	var bottleneck := -1
	var worst_queue := -1.0
	for position in range(count):
		var id: int = processors[position]
		var node := manager.graph.get_node(id)
		var relief := 0
		var complexity: int = manager.simulation.get_incoming_complexity(id)
		if has_booster and node.boosted:
			relief = ComplexityRelief.relief_amount(complexity, spec)
		var average_queue := queue_sum[position] / maxf(samples, 1)
		if average_queue > worst_queue:
			worst_queue = average_queue
			bottleneck = position
		var downstream := 0.0
		if position + 1 < count:
			downstream = queue_sum[position + 1] / maxf(samples, 1)
		rows.append({
			"model": model_id, "depth": depth, "index": position, "boosted": node.boosted,
			"role": _role(position, count), "complexity": complexity, "relief": relief,
			"effective_complexity": maxi(complexity - relief, 0), "capacity": manager.simulation.get_effective_capacity(id),
			"processed": processed[position], "avg_queue": average_queue, "peak_queue": queue_peak[position],
			"avg_util": util_sum[position] / maxf(samples, 1), "downstream_queue": downstream,
		})
	ComplexityRelief.active = {}
	BalanceExperimentConfig.restore_production()
	return {"rows": rows, "summary": {
		"model": model_id, "depth": depth, "generator_level": generator_level, "seconds": seconds,
		"booster_cell": [cell.x, cell.y] if has_booster else [],
		"boosted_index": _boosted_index(rows), "bottleneck_index": bottleneck,
		"paid_300": paid_300, "paid_900": paid_900, "first_payout": clock["first_payout"],
	}}


func _boosted_index(rows: Array) -> int:
	for row in rows:
		if row["boosted"]:
			return int(row["index"])
	return -1


func _role(position: int, count: int) -> String:
	if position == count - 1:
		return "final"
	return "chain"


func _ints(text: String) -> Array:
	var values: Array = []
	for part in text.split(","):
		values.append(int(part))
	return values


func _options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		var parts := arg.split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() == 2 else "1"
	return options
