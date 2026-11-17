extends SceneTree

# Run with: godot --headless --path . --script res://tests/balance/balance_investments.gd -- --name=investments --bases=1.00,1.20 [--gen=5,10,15]
# Alternative-investment tests at representative player states under a chosen work base. Compares the next
# purchase: another Processor, a Generator upgrade, one Booster (best placement for shallow states), a two-branch
# re-route of the same Processors (Splitter + Merger), or no purchase. Test-only; production is restored on exit.
# Writes user://balance_results/<name>.json.

const STATES := [[2, 9], [7, 9], [13, 15], [23, 25], [20, 45]]  # [existing Processor depth, cell limit]
const SEARCH_MAX_DEPTH := 8
const SECONDS := 300.0
const GROWTHS := [1.0, 1.3]
const OUTPUT_DIR := "user://balance_results"

var _alternatives: Array = []


func _init() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var run_name: String = options.get("name", "investments")
	var bases := _list(options.get("bases", "1.00"))
	var generators := _ints(options.get("gen", "5,10,15"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	for token in bases:
		var work := float(token)
		var config := BalanceExperimentConfig.new(0.10, 1.0, work)
		for generator_level in generators:
			for state in STATES:
				_compare(config, work, generator_level, int(state[0]), int(state[1]))
	BalanceExperimentConfig.restore_production()

	var file := FileAccess.open("%s/%s.json" % [OUTPUT_DIR, run_name], FileAccess.WRITE)
	file.store_string(JSON.stringify({"alternatives": _alternatives}, "\t"))
	file.close()
	print("INVESTMENTS %s records=%d production_restored=%s" % [run_name, _alternatives.size(), str(ComplexityModel.work_base == 0.0)])
	quit(0)


func _compare(config: BalanceExperimentConfig, work: float, generator_level: int, depth: int, cell_limit: int) -> void:
	var base := BalanceRunner.measure(BalanceTopologies.sequential(depth), config, generator_level, SECONDS)
	_record(work, generator_level, depth, cell_limit, "save", base, {}, true)

	if depth + 3 <= cell_limit:
		var plus := BalanceRunner.measure(BalanceTopologies.sequential(depth + 1), config, generator_level, SECONDS)
		_record(work, generator_level, depth, cell_limit, "processor", plus, _added_cost(plus, base), true)

	if generator_level < 15:
		var upgraded := BalanceRunner.measure(BalanceTopologies.sequential(depth), config, generator_level + 1, SECONDS)
		_record(work, generator_level, depth, cell_limit, "generator_upgrade", upgraded, _flat_cost(LineBalance.GENERATOR_UPGRADE_COST_PER_LEVEL * generator_level), true)

	if depth >= 1 and depth + 3 <= cell_limit:
		var booster := _best_booster(config, depth, generator_level)
		_record(work, generator_level, depth, cell_limit, "booster_one", booster, _added_cost(booster, base), true)

	if depth >= 2 and depth + 4 <= cell_limit:
		var split := BalanceRunner.measure(BalanceTopologies.parallel([depth / 2, depth - depth / 2]), config, generator_level, SECONDS)
		_record(work, generator_level, depth, cell_limit, "branch_split", split, _added_cost(split, base), true)


# Best single Booster. For shallow networks every legal orthogonal cell beside a Processor is tried; deeper
# networks use the deepest and nearest Processors (documented heuristic).
func _best_booster(config: BalanceExperimentConfig, depth: int, generator_level: int) -> Dictionary:
	var candidates := _booster_cells(depth, generator_level)
	if depth > SEARCH_MAX_DEPTH:
		candidates = candidates.slice(maxi(candidates.size() - 2, 0))
	var best: Dictionary = {}
	for cell in candidates:
		var manager := BalanceTopologies.build(BalanceTopologies.sequential(depth), generator_level)
		manager.construct(NodeDefinitions.Type.BOOSTER, cell)
		var result := BalanceRunner.measure_built(manager, BalanceTopologies.sequential(depth), config, generator_level, SECONDS)
		if best.is_empty() or float(result["windows"][1]["revenue_per_sec"]) > float(best["windows"][1]["revenue_per_sec"]):
			best = result
	return best


# Free orthogonal cells beside each Processor, in chain order.
func _booster_cells(depth: int, generator_level: int) -> Array:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(depth), generator_level)
	var cells: Array = []
	for processor in BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR):
		var cell: Vector2i = manager.layout.get_node_cell(processor)
		for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
			var neighbour: Vector2i = cell + offset
			if manager.layout.contains_cell(neighbour) and manager.layout.is_cell_free(neighbour) and not cells.has(neighbour):
				cells.append(neighbour)
	return cells


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


func _record(work: float, generator_level: int, depth: int, cell_limit: int, option: String, result: Dictionary, added_cost: Dictionary, available: bool) -> void:
	var window: Dictionary = result["windows"][1]
	_alternatives.append({
		"work_base": work,
		"generator_level": generator_level,
		"existing_depth": depth,
		"cell_limit": cell_limit,
		"option": option,
		"topology": result["label"],
		"cells_used": result["cells_used"],
		"added_cost": added_cost,
		"available": available,
		"revenue_per_sec": window["revenue_per_sec"],
		"steady_revenue_per_sec": window["steady_revenue_per_sec"],
		"revenue_total": window["revenue_total"],
		"completed_per_sec": window["completed_per_sec"],
		"average_queue": window["average_queue"],
		"peak_queue": window["peak_queue"],
		"average_bottlenecks": window["average_bottlenecks"],
		"time_first_payout": window["time_first_payout"],
		"conserved": window["conserved"],
	})


func _options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			options[parts[0]] = parts[1]
	return options


func _list(text: String) -> Array:
	var values: Array = []
	for part in text.split(","):
		values.append(part.strip_edges())
	return values


func _ints(text: String) -> Array:
	var values: Array = []
	for part in text.split(","):
		values.append(int(part))
	return values
