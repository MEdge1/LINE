extends SceneTree

# Run with: godot --headless --path . --script res://tests/balance/balance_targeted.gd
# Targeted follow-up experiments. Inspects representative parallel, Booster, and hybrid networks, then compares the
# next investment at representative player states: another Processor, a Generator upgrade, a Booster, or no purchase.
# Writes user://balance_results/targeted.json. Production balance is never changed.

const STATES := [[2, 9], [7, 9], [13, 15], [23, 25], [20, 45]]  # [existing Processor depth, cell limit]
const COMPLEXITY_VALUES := [0.10, 0.30]
const GENERATORS := [5, 10, 15]
const GROWTHS := [1.0, 1.3]
const SECONDS := 300.0
const BOOSTER_COST := 30
const OUTPUT := "user://balance_results/targeted.json"

var _inspection: Array = []
var _alternatives: Array = []


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://balance_results"))
	_inspect()
	_compare_investments()
	BalanceExperimentConfig.restore_production()

	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"inspection": _inspection, "alternatives": _alternatives}, "\t"))
	file.close()
	for line in _inspection:
		print(line)
	print("TARGETED alternatives=%d written to %s" % [_alternatives.size(), ProjectSettings.globalize_path(OUTPUT)])
	quit(0)


func _inspect() -> void:
	var specs := [
		BalanceTopologies.sequential(10),
		BalanceTopologies.sequential(10, true),
		BalanceTopologies.parallel([5, 5]),
		BalanceTopologies.parallel([5, 5], true),
		BalanceTopologies.parallel([2, 4], true),
		BalanceTopologies.parallel([5, 10], true),
	]
	for spec in specs:
		var manager := BalanceTopologies.build(spec, 15)
		var counts := BalanceTopologies.describe(manager, spec)
		var processors := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)
		var boosted_flags := 0
		var adjacent_processors := 0
		for processor in processors:
			if manager.graph.get_node(processor).boosted:
				boosted_flags += 1
			if _has_booster_neighbour(manager, processor):
				adjacent_processors += 1
		var booster_ids := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.BOOSTER)
		var boosters_touch_processor := true
		for booster in booster_ids:
			if not _has_processor_neighbour(manager, booster):
				boosters_touch_processor = false
		var generator: int = BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.GENERATOR)[0]
		var cost_low := BalanceTopologies.construction_cost(counts, BalanceExperimentConfig.new(0.10, 1.0))
		var cost_high := BalanceTopologies.construction_cost(counts, BalanceExperimentConfig.new(0.10, 1.3))
		_inspection.append("INSPECT %s cells=%d/%d processors=%d splitters=%d mergers=%d boosters=%d cost@1.00=%d cost@1.30=%d boosted_flags=%d processors_next_to_booster=%d boosters_touch_processor=%s generator_rate@15=%.2f" % [
			counts["label"], counts["cells_used"], 45, counts["processors"], counts["splitters"], counts["mergers"],
			counts["boosters"], cost_low, cost_high, boosted_flags, adjacent_processors, str(boosters_touch_processor),
			manager.simulation.get_generator_rate(generator),
		])


func _compare_investments() -> void:
	for complexity in COMPLEXITY_VALUES:
		for generator_level in GENERATORS:
			for state in STATES:
				var depth: int = state[0]
				var cell_limit: int = state[1]
				var config := BalanceExperimentConfig.new(complexity, 1.0)
				var base := BalanceRunner.measure(BalanceTopologies.sequential(depth), config, generator_level, SECONDS)
				_record(complexity, generator_level, depth, cell_limit, "save", base, {}, true)

				if depth + 3 <= cell_limit:
					var plus := BalanceRunner.measure(BalanceTopologies.sequential(depth + 1), config, generator_level, SECONDS)
					_record(complexity, generator_level, depth, cell_limit, "processor", plus, _added_cost(plus, base), true)

				if generator_level < 15:
					var upgraded := BalanceRunner.measure(BalanceTopologies.sequential(depth), config, generator_level + 1, SECONDS)
					var upgrade_cost: int = LineBalance.GENERATOR_UPGRADE_COST_PER_LEVEL * generator_level
					_record(complexity, generator_level, depth, cell_limit, "generator_upgrade", upgraded, _flat_cost(upgrade_cost), true)

				if depth >= 1 and depth + 3 <= cell_limit:
					var first := BalanceRunner.measure_built(_with_booster(depth, generator_level, 0), BalanceTopologies.sequential(depth), config, generator_level, SECONDS)
					var last := BalanceRunner.measure_built(_with_booster(depth, generator_level, -1), BalanceTopologies.sequential(depth), config, generator_level, SECONDS)
					var best := last if float(last["windows"][1]["revenue_per_sec"]) >= float(first["windows"][1]["revenue_per_sec"]) else first
					_record(complexity, generator_level, depth, cell_limit, "booster_one", best, _added_cost(best, base), true)


# Adds one Booster beside the processor at `index` (0 = nearest the Generator, -1 = deepest). Cells decide placement.
func _with_booster(depth: int, generator_level: int, index: int) -> NetworkManager:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(depth), generator_level)
	var processors := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)
	var target: int = processors[index]
	var cell: Vector2i = manager.layout.get_node_cell(target)
	for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
		var neighbour: Vector2i = cell + offset
		if manager.layout.contains_cell(neighbour) and manager.layout.is_cell_free(neighbour):
			manager.construct(NodeDefinitions.Type.BOOSTER, neighbour)
			break
	return manager


func _added_cost(after: Dictionary, before: Dictionary) -> Dictionary:
	var added := {}
	for growth in GROWTHS:
		var config := BalanceExperimentConfig.new(0.10, growth)
		added["%.2f" % growth] = BalanceTopologies.construction_cost(after, config) - BalanceTopologies.construction_cost(before, config)
	return added


func _flat_cost(cost: int) -> Dictionary:
	var added := {}
	for growth in GROWTHS:
		added["%.2f" % growth] = cost
	return added


func _record(complexity: float, generator_level: int, depth: int, cell_limit: int, option: String, result: Dictionary, added_cost: Dictionary, available: bool) -> void:
	var window: Dictionary = result["windows"][1]
	_alternatives.append({
		"complexity_k": complexity,
		"generator_level": generator_level,
		"existing_depth": depth,
		"cell_limit": cell_limit,
		"option": option,
		"cells_used": result["cells_used"],
		"added_cost": added_cost,
		"available": available,
		"revenue_per_sec": window["revenue_per_sec"],
		"steady_revenue_per_sec": window["steady_revenue_per_sec"],
		"completed_per_sec": window["completed_per_sec"],
		"average_queue": window["average_queue"],
		"average_bottlenecks": window["average_bottlenecks"],
		"time_first_payout": window["time_first_payout"],
		"revenue_total": window["revenue_total"],
		"conserved": window["conserved"],
	})


func _has_booster_neighbour(manager: NetworkManager, processor: int) -> bool:
	var cell: Vector2i = manager.layout.get_node_cell(processor)
	for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
		var other := manager.layout.get_node_at(cell + offset)
		if other != 0 and manager.graph.get_node(other).type == NodeDefinitions.Type.BOOSTER:
			return true
	return false


func _has_processor_neighbour(manager: NetworkManager, booster: int) -> bool:
	var cell: Vector2i = manager.layout.get_node_cell(booster)
	for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
		var other := manager.layout.get_node_at(cell + offset)
		if other != 0 and manager.graph.get_node(other).type == NodeDefinitions.Type.PROCESSOR:
			return true
	return false
