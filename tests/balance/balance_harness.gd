extends SceneTree

# Run with: godot --headless --path . --script res://tests/balance/balance_harness.gd -- [--quick] [--gen=15,10,5]
# Experimental Processor balance sweep. Writes ignored outputs to res://balance_results/. Production balance is
# never changed: candidate values reach the simulation only through BalanceExperimentConfig, and the live
# complexity value is restored before exit. Each simulation runs once; cost growth and budgets only filter results.

const OUTPUT_DIR := "user://balance_results"
const COMPLEXITY_VALUES := [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50]
const QUICK_COMPLEXITY_VALUES := [0.10, 0.30]
const GROWTH_VALUES := [1.00, 1.10, 1.15, 1.20, 1.25, 1.30, 1.40]
const QUICK_GROWTH_VALUES := [1.00, 1.30]
const BUDGETS := [250, 500, 1000, 2500, 5000, 10000]
const QUICK_BUDGETS := [1000, 10000]
const CELL_LIMITS := [9, 15, 25, 45]
const QUICK_CELL_LIMITS := [9, 45]
const SIM_SECONDS := 300.0
const BOOSTED_DEPTHS := [1, 2, 3, 4, 5, 8, 10, 12, 15, 20, 25, 30, 35, 40, 43]
const QUICK_DEPTHS := [0, 2, 4, 8, 43]
const QUICK_BOOSTED_DEPTHS := [2, 4]
const BRANCH_SETS := [[1, 1], [2, 2], [3, 3], [5, 5], [2, 4], [3, 5], [5, 10]]
const QUICK_BRANCH_SETS := [[1, 1], [3, 3]]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var quick := args.has("--quick")
	var generators := _generators(args)
	var growths: Array = QUICK_GROWTH_VALUES if quick else GROWTH_VALUES
	var budgets: Array = QUICK_BUDGETS if quick else BUDGETS
	var cell_limits: Array = QUICK_CELL_LIMITS if quick else CELL_LIMITS
	var complexity_values: Array = QUICK_COMPLEXITY_VALUES if quick else COMPLEXITY_VALUES

	if LineBalance.PROCESSOR_MULTIPLIER != 2:
		printerr("Processor value must stay ×2 for this experiment.")
		quit(1)
		return

	var baseline := _baseline()
	var specs := _specs(quick)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var total := generators.size() * complexity_values.size() * specs.size()
	var progress := BalanceProgress.new(OUTPUT_DIR + "/progress.json", total, growths)
	var started := Time.get_ticks_msec()
	var sims: Array = []
	var rows: Array = []
	for generator_level in generators:
		for complexity in complexity_values:
			var config := BalanceExperimentConfig.new(complexity, 1.0)
			for spec in specs:
				var sim := BalanceRunner.measure(spec, config, generator_level, SIM_SECONDS)
				sims.append(sim)
				var new_rows := BalanceAnalysis.rows([sim], growths, budgets, cell_limits)
				rows.append_array(new_rows)
				progress.advance(sim, new_rows.size())
	var simulation_ms := Time.get_ticks_msec() - started
	BalanceExperimentConfig.restore_production()
	progress.finish()

	var analysis := BalanceAnalysis.tallies(rows)
	var marginal := BalanceAnalysis.marginal(sims, growths, complexity_values, generators[0])
	var boosters := BalanceAnalysis.booster_value(sims, complexity_values, _booster_depths(quick), generators[0], NodeDefinitions.get_cost(NodeDefinitions.Type.BOOSTER))
	var determinism := _determinism_check()

	var csv := FileAccess.open(OUTPUT_DIR + "/processor_balance_results.csv", FileAccess.WRITE)
	csv.store_string(BalanceAnalysis.csv_text(rows))
	csv.close()

	var summary := {
		"production_baseline": baseline,
		"simulations": sims.size(),
		"rows": rows.size(),
		"simulation_wall_ms": simulation_ms,
		"average_simulation_ms": float(simulation_ms) / maxf(sims.size(), 1.0),
		"determinism_passed": determinism,
		"invalid_simulations": _invalid_simulations(sims),
		"baseline_winners": analysis["baseline"],
		"winner_tallies": analysis["tallies"],
		"marginal_processor": marginal,
		"booster_value": boosters,
	}
	var summary_file := FileAccess.open(OUTPUT_DIR + "/processor_balance_summary.json", FileAccess.WRITE)
	summary_file.store_string(JSON.stringify(summary, "\t"))
	summary_file.close()

	_print_report(summary, generators[0])
	quit(0 if determinism else 1)


func _generators(args: PackedStringArray) -> Array:
	for arg in args:
		if arg.begins_with("--gen="):
			var values: Array = []
			for part in arg.trim_prefix("--gen=").split(","):
				values.append(int(part))
			return values
	return [15]


func _booster_depths(quick: bool) -> Array:
	return QUICK_BOOSTED_DEPTHS if quick else BOOSTED_DEPTHS


func _specs(quick: bool) -> Array:
	var depths: Array = []
	for depth in (QUICK_DEPTHS if quick else range(0, 44)):
		depths.append(depth)
	var branches: Array = QUICK_BRANCH_SETS if quick else BRANCH_SETS
	var specs: Array = []
	for depth in depths:
		specs.append(BalanceTopologies.sequential(depth))
	for depth in _booster_depths(quick):
		specs.append(BalanceTopologies.sequential(depth, true))
	for pair in branches:
		specs.append(BalanceTopologies.parallel(pair))
	for pair in branches:
		specs.append(BalanceTopologies.parallel(pair, true))
	return specs


# Production values read from the authoritative configuration at run time.
func _baseline() -> Dictionary:
	return {
		"processor_base_cost": NodeDefinitions.get_cost(NodeDefinitions.Type.PROCESSOR),
		"processor_value_multiplier": LineBalance.PROCESSOR_MULTIPLIER,
		"complexity_cost_per_level": LineBalance.COMPLEXITY_COST_PER_LEVEL,
		"booster_bonus": LineBalance.BOOSTER_BONUS,
		"generator_max_level": LineBalance.GENERATOR_MAX_LEVEL,
		"generator_rate_base": LineBalance.GENERATOR_BASE_RATE,
		"generator_rate_per_level": LineBalance.GENERATOR_RATE_PER_LEVEL,
		"buffer_capacity": LineBalance.BUFFER_CAPACITY,
		"travel_duration": LineBalance.TRAVEL_DURATION,
		"costs": {
			"generator": NodeDefinitions.get_cost(NodeDefinitions.Type.GENERATOR),
			"output": NodeDefinitions.get_cost(NodeDefinitions.Type.OUTPUT),
			"splitter": NodeDefinitions.get_cost(NodeDefinitions.Type.SPLITTER),
			"merger": NodeDefinitions.get_cost(NodeDefinitions.Type.MERGER),
			"booster": NodeDefinitions.get_cost(NodeDefinitions.Type.BOOSTER),
		},
		"capacities": {
			"processor": NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR),
			"output": NodeDefinitions.get_capacity(NodeDefinitions.Type.OUTPUT),
			"splitter": NodeDefinitions.get_capacity(NodeDefinitions.Type.SPLITTER),
			"merger": NodeDefinitions.get_capacity(NodeDefinitions.Type.MERGER),
		},
	}


# Re-runs representative candidates and requires identical authoritative output.
func _determinism_check() -> bool:
	var config := BalanceExperimentConfig.new(0.30, 1.0)
	for spec in [BalanceTopologies.sequential(10), BalanceTopologies.parallel([2, 4], true)]:
		var first := BalanceRunner.measure(spec, config, 15, SIM_SECONDS)
		var second := BalanceRunner.measure(spec, config, 15, SIM_SECONDS)
		if var_to_str(first) != var_to_str(second):
			printerr("DETERMINISM FAIL: %s" % BalanceTopologies.label(spec))
			return false
	return true


func _invalid_simulations(sims: Array) -> Array:
	var invalid: Array = []
	for sim in sims:
		for window in sim["windows"]:
			if not window["conserved"]:
				invalid.append("%s k%.2f L%d" % [sim["label"], sim["complexity_k"], sim["generator_level"]])
				break
	return invalid


func _print_report(summary: Dictionary, generator_level: int) -> void:
	print("BALANCE simulations=%d rows=%d wall_ms=%d avg_ms=%.0f determinism=%s invalid=%d" % [
		summary["simulations"], summary["rows"], summary["simulation_wall_ms"], summary["average_simulation_ms"],
		str(summary["determinism_passed"]), summary["invalid_simulations"].size(),
	])
	print("BALANCE live-control winners (k=0.10, growth 1.00, gen %d, 300 s):" % generator_level)
	for entry in summary["baseline_winners"]:
		if entry["objective"] == "revenue_per_sec" or entry["objective"] == "revenue_per_cost":
			print("  budget %5d cells %2d %-16s %-28s %.4f" % [entry["budget"], entry["cell_limit"], entry["objective"], entry["topology"], float(entry["value"])])
	print("BALANCE marginal Processor (k=0.10, growth 1.00):")
	for entry in summary["marginal_processor"]:
		if entry["complexity_k"] == 0.10 and entry["processor_cost_growth"] == 1.0 and entry["from_depth"] in [0, 1, 2, 3, 5, 8, 10, 20, 30, 42]:
			print("  depth %2d->%2d cost +%d  Δrev/s %.4f  Δrev per $ %.6f" % [entry["from_depth"], entry["from_depth"] + 1, entry["added_cost"], entry["delta_revenue_per_sec"], entry["revenue_per_added_dollar"]])
