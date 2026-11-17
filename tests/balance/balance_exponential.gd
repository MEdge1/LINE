extends SceneTree

# Run with: godot --headless --path . --script res://tests/balance/balance_exponential.gd -- --name=phase1 --bases=hyper,1.00,1.10 --gen=5,10,15 [--seconds=300] [--depths=0,1,...] [--growths=1.00] [--architectures]
# Exponential complexity-work experiment. Test-only: the live ComplexityModel and costs are restored before exit.
# Writes ignored outputs to user://balance_results/<name>.csv and <name>.json. Progress: user://balance_results/progress.json.
# "hyper" is the live hyperbolic model at k 0.10. Numeric bases switch to exponential work (1 / base^c).

const OUTPUT_DIR := "user://balance_results"
const BUDGETS := [250, 500, 1000, 2500, 5000, 10000]
const CELL_LIMITS := [9, 15, 25, 45]
const DEFAULT_DEPTHS := [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 20, 25, 30, 35, 40, 43]
const BALANCED := [[1, 1], [2, 2], [3, 3], [4, 4], [5, 5], [8, 8], [10, 10], [15, 15], [20, 20]]
const UNEQUAL := [[2, 4], [3, 5], [4, 8], [5, 10], [8, 12], [10, 15]]


func _init() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var run_name: String = options.get("name", "exponential")
	var bases: Array = _list(options.get("bases", "hyper,1.00"))
	var depths: Array = _ints(options.get("depths", ",".join(PackedStringArray(DEFAULT_DEPTHS.map(func(d: int) -> String: return str(d))))))
	var generators: Array = _ints(options.get("gen", "15"))
	var growths: Array = _floats(options.get("growths", "1.00"))
	var seconds := float(options.get("seconds", "300"))
	var architectures := options.has("architectures")
	var specs := _specs(depths, architectures)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var total := bases.size() * generators.size() * specs.size()
	var progress := BalanceProgress.new("%s/%s_progress.json" % [OUTPUT_DIR, run_name], total, growths)
	var started := Time.get_ticks_msec()
	var sims: Array = []
	var rows: Array = []
	for token in bases:
		var config := BalanceExperimentConfig.new(0.10, 1.0, _base_value(token))
		for generator_level in generators:
			for spec in specs:
				var sim := BalanceRunner.measure(spec, config, generator_level, seconds)
				sims.append(sim)
				var new_rows := BalanceAnalysis.rows([sim], growths, BUDGETS, CELL_LIMITS)
				rows.append_array(new_rows)
				progress.advance(sim, new_rows.size())
	BalanceExperimentConfig.restore_production()
	progress.finish()
	var wall_ms := Time.get_ticks_msec() - started

	var deterministic := _determinism_check(seconds)
	BalanceExperimentConfig.restore_production()
	var invalid: Array = []
	for sim in sims:
		for window in sim["windows"]:
			if not window["conserved"]:
				invalid.append("%s work_base=%.2f L%d" % [sim["label"], sim["work_base"], sim["generator_level"]])
				break

	var csv := FileAccess.open("%s/%s.csv" % [OUTPUT_DIR, run_name], FileAccess.WRITE)
	csv.store_string(BalanceAnalysis.csv_text(rows))
	csv.close()
	var summary := {
		"name": run_name,
		"bases": bases,
		"depths": depths,
		"generators": generators,
		"growths": growths,
		"seconds": seconds,
		"architectures": architectures,
		"simulations": sims.size(),
		"rows": rows.size(),
		"wall_ms": wall_ms,
		"average_simulation_ms": float(wall_ms) / maxf(sims.size(), 1.0),
		"determinism_passed": deterministic,
		"invalid_simulations": invalid,
		"production_restored": ComplexityModel.work_base == 0.0 and ComplexityModel.cost_per_level == LineBalance.COMPLEXITY_COST_PER_LEVEL,
	}
	var summary_file := FileAccess.open("%s/%s.json" % [OUTPUT_DIR, run_name], FileAccess.WRITE)
	summary_file.store_string(JSON.stringify(summary, "\t"))
	summary_file.close()
	print("EXPONENTIAL %s simulations=%d rows=%d wall_ms=%d determinism=%s invalid=%d production_restored=%s" % [
		run_name, sims.size(), rows.size(), wall_ms, str(deterministic), invalid.size(), str(summary["production_restored"]),
	])
	print("EXPONENTIAL output %s" % ProjectSettings.globalize_path("%s/%s.csv" % [OUTPUT_DIR, run_name]))
	quit(0 if deterministic and summary["production_restored"] else 1)


func _determinism_check(seconds: float) -> bool:
	var config := BalanceExperimentConfig.new(0.10, 1.0, 1.20)
	var spec := BalanceTopologies.sequential(10)
	var first := BalanceRunner.measure(spec, config, 15, minf(seconds, 300.0))
	var second := BalanceRunner.measure(spec, config, 15, minf(seconds, 300.0))
	return var_to_str(first) == var_to_str(second)


func _specs(depths: Array, architectures: bool) -> Array:
	var specs: Array = []
	for depth in depths:
		specs.append(BalanceTopologies.sequential(depth))
	if architectures:
		for depth in depths:
			if depth >= 1:
				specs.append(BalanceTopologies.sequential(depth, true))
		for pair in BALANCED + UNEQUAL:
			specs.append(BalanceTopologies.parallel(pair))
		for pair in BALANCED + UNEQUAL:
			specs.append(BalanceTopologies.parallel(pair, true))
	return specs


func _base_value(token: String) -> float:
	return 0.0 if token == "hyper" else float(token)


func _options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			options[parts[0]] = parts[1]
		elif arg.begins_with("--"):
			options[arg.trim_prefix("--")] = "1"
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


func _floats(text: String) -> Array:
	var values: Array = []
	for part in text.split(","):
		values.append(float(part))
	return values
