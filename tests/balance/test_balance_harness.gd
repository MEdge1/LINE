extends SceneTree

# Run with: godot --headless --path . --script res://tests/balance/test_balance_harness.gd
# Verifies the balance harness itself: cost models, feasibility, routing cost, determinism, conservation,
# marginal consistency, CSV row count, exact LargeNumber text, winner selection, and production restoration.

var _failures := 0


func _init() -> void:
	_test_flat_processor_cost()
	_test_compound_processor_cost()
	_test_budget_and_cell_limits_reject_candidates()
	_test_topology_cost_includes_routing_nodes()
	_test_identical_runs_are_deterministic()
	_test_short_run_conserves_and_restores_production()
	_test_marginal_cost_is_the_added_processor()
	_test_csv_row_count_matches_candidates()
	_test_large_numbers_serialize_exactly()
	_test_winners_ignore_invalid_rows()
	_test_progress_estimates_remaining_time()
	_test_progress_checkpoint_is_atomic_and_marks_completion()
	_test_work_base_one_is_the_no_penalty_control()
	_test_exponential_work_multiplier_matches_the_formula()
	_test_first_processor_full_speed_and_second_one_level()
	_test_processor_doubles_value_and_adds_one_complexity()
	_test_deepest_stage_work_uses_incoming_complexity()
	_test_booster_multiplies_exponential_capacity()
	_test_high_complexity_unit_eventually_completes()
	_test_csv_header_carries_the_work_fields()
	_test_live_complexity_model_is_restored()

	if _failures == 0:
		print("All balance harness tests passed.")
	else:
		printerr("%d balance harness assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _test_flat_processor_cost() -> void:
	var flat := BalanceExperimentConfig.new(0.10, 1.0)
	_assert_equal(flat.processor_cost(1), 50, "a flat Processor costs its base every time")
	_assert_equal(flat.processor_cost(9), 50, "a flat Processor costs the same at the ninth purchase")
	_assert_equal(flat.processors_cost(4), 200, "flat cost totals base × count")


func _test_compound_processor_cost() -> void:
	var compound := BalanceExperimentConfig.new(0.10, 1.2)
	_assert_equal(compound.processor_cost(3), 72, "the third Processor costs base × growth²")
	_assert_equal(compound.processors_cost(3), 182, "compound cost sums each purchase")


func _test_budget_and_cell_limits_reject_candidates() -> void:
	var counts := {"cells_used": 10}
	_assert_equal(BalanceAnalysis.feasible(counts, 249, 248, 45), false, "a network over budget is rejected")
	_assert_equal(BalanceAnalysis.feasible(counts, 100, 1000, 9), false, "a network over the cell limit is rejected")
	_assert_equal(BalanceAnalysis.feasible(counts, 100, 1000, 10), true, "a network within budget and cells is accepted")


func _test_topology_cost_includes_routing_nodes() -> void:
	var config := BalanceExperimentConfig.new(0.10, 1.0)
	var manager := BalanceTopologies.build(BalanceTopologies.parallel([1, 1]), 15)
	var counts := BalanceTopologies.describe(manager, BalanceTopologies.parallel([1, 1]))
	# Generator 25 + Output 25 + Splitter 40 + Merger 40 + two Processors at 50 each.
	_assert_equal(BalanceTopologies.construction_cost(counts, config), 230, "a Splitter and Merger add their production costs")


func _test_identical_runs_are_deterministic() -> void:
	var config := BalanceExperimentConfig.new(0.30, 1.0)
	var first := BalanceRunner.measure(BalanceTopologies.sequential(3), config, 15, 10.0)
	var second := BalanceRunner.measure(BalanceTopologies.sequential(3), config, 15, 10.0)
	_assert_equal(var_to_str(first) == var_to_str(second), true, "two identical runs produce identical authoritative output")


func _test_short_run_conserves_and_restores_production() -> void:
	var config := BalanceExperimentConfig.new(0.30, 1.0)
	var result := BalanceRunner.measure(BalanceTopologies.parallel([2, 2], true), config, 15, 20.0)
	for window in result["windows"]:
		_assert_equal(window["conserved"], true, "a run conserves produced = paid + held + lost")
	_assert_equal(ComplexityModel.cost_per_level, 0.30, "a run applies its complexity value")
	BalanceExperimentConfig.restore_production()
	_assert_equal(ComplexityModel.cost_per_level, LineBalance.COMPLEXITY_COST_PER_LEVEL, "the live complexity value is restored after a run")


func _test_marginal_cost_is_the_added_processor() -> void:
	var config := BalanceExperimentConfig.new(0.10, 1.3)
	var added := config.processor_cost(4)
	_assert_equal(added, config.processors_cost(4) - config.processors_cost(3), "the marginal cost is the difference of cumulative costs")


func _test_csv_row_count_matches_candidates() -> void:
	var sim := BalanceRunner.measure(BalanceTopologies.sequential(1), BalanceExperimentConfig.new(0.10, 1.0), 15, 10.0)
	var rows := BalanceAnalysis.rows([sim], [1.0], [1000], [9, 45])
	var lines := BalanceAnalysis.csv_text(rows).strip_edges().split("\n")
	_assert_equal(rows.size(), 2, "two cell limits give two rows for the single 10 s window")
	_assert_equal(lines.size(), rows.size() + 1, "the CSV holds a header plus one line per row")


func _test_large_numbers_serialize_exactly() -> void:
	var text := "123456789012345678901234567890"
	_assert_equal(LargeNumber.from_text(text).to_text(), text, "large authoritative values round-trip without float conversion")


func _test_winners_ignore_invalid_rows() -> void:
	var rows := [
		_synthetic_row("invalid", 9.0, false),
		_synthetic_row("lower", 5.0, true),
		_synthetic_row("winner", 7.0, true),
	]
	var winners: Array = BalanceAnalysis.tallies(rows)["baseline"]
	var revenue_winner := ""
	for entry in winners:
		if entry["objective"] == "revenue_per_sec":
			revenue_winner = entry["topology"]
	_assert_equal(revenue_winner, "winner", "the highest conserved value wins and non-conserved rows never compete")


func _test_progress_estimates_remaining_time() -> void:
	_assert_equal(BalanceProgress.estimate_remaining(100.0, 25, 100), 300.0, "remaining time extrapolates the average time per simulation")
	_assert_equal(BalanceProgress.estimate_remaining(0.0, 0, 100), -1.0, "remaining time is unknown before the first simulation finishes")


func _test_progress_checkpoint_is_atomic_and_marks_completion() -> void:
	var path := "user://balance_progress_test.json"
	var progress := BalanceProgress.new(path, 2, [1.0])
	var fake := {"generator_level": 15, "complexity_k": 0.10, "windows": [{"conserved": true}, {"conserved": false}]}
	progress.advance(fake, 3)
	progress.advance(fake, 2)
	progress.finish()
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_assert_equal(parsed["complete"], true, "the checkpoint is marked complete when the run finishes")
	_assert_equal(parsed["completed_simulations"], 2, "the checkpoint counts completed simulations")
	_assert_equal(parsed["rows"], 5, "the checkpoint counts generated rows")
	_assert_equal(parsed["invalid_runs"], 2, "the checkpoint counts invalid runs")
	_assert_equal(FileAccess.file_exists(path + ".tmp"), false, "the atomic replace leaves no temporary file behind")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_work_base_one_is_the_no_penalty_control() -> void:
	BalanceExperimentConfig.new(0.10, 1.0, 1.0).apply()
	var no_penalty := true
	for complexity in range(0, 6):
		no_penalty = no_penalty and ComplexityModel.processing_modifier(complexity) == 1.0
	BalanceExperimentConfig.restore_production()
	_assert_equal(no_penalty, true, "work base 1.00 produces no complexity slowdown")


func _test_exponential_work_multiplier_matches_the_formula() -> void:
	BalanceExperimentConfig.new(0.10, 1.0, 1.5).apply()
	_assert_equal(1.0 / ComplexityModel.processing_modifier(0), 1.0, "incoming complexity 0 has work multiplier 1")
	_assert_equal(is_equal_approx(1.0 / ComplexityModel.processing_modifier(3), pow(1.5, 3)), true, "work multiplier equals base^complexity")
	_assert_equal(is_equal_approx(ComplexityModel.processing_modifier(2) * pow(1.5, 2), 1.0), true, "processing modifier is the reciprocal of the work multiplier")
	var monotone := true
	for complexity in range(0, 12):
		monotone = monotone and ComplexityModel.processing_modifier(complexity + 1) < ComplexityModel.processing_modifier(complexity)
	BalanceExperimentConfig.restore_production()
	_assert_equal(monotone, true, "a work base above 1 never increases capacity as complexity rises")


func _test_first_processor_full_speed_and_second_one_level() -> void:
	BalanceExperimentConfig.new(0.10, 1.0, 1.5).apply()
	var first := ComplexityModel.processing_modifier(0)
	var second := ComplexityModel.processing_modifier(1)
	BalanceExperimentConfig.restore_production()
	_assert_equal(first, 1.0, "the first Processor receives complexity 0 and runs at full capacity")
	_assert_equal(is_equal_approx(second, 1.0 / 1.5), true, "the second Processor pays exactly one level of work")


func _test_processor_doubles_value_and_adds_one_complexity() -> void:
	var result := BalanceRunner.measure(BalanceTopologies.sequential(1), BalanceExperimentConfig.new(0.10, 1.0, 1.5), 15, 60.0)
	var window: Dictionary = result["windows"][0]
	_assert_equal(window["max_complexity"], 1, "one Processor outputs complexity 1 (no off-by-one)")
	var revenue := LargeNumber.from_text(window["revenue_total"])
	var expected := LargeNumber.from_text(window["completed_total"]).multiply(LargeNumber.from_int(2))
	_assert_equal(revenue.compare(expected), 0, "every paid unit from one Processor pays exactly ×2 its value")
	BalanceExperimentConfig.restore_production()


func _test_deepest_stage_work_uses_incoming_complexity() -> void:
	var result := BalanceRunner.measure(BalanceTopologies.sequential(3), BalanceExperimentConfig.new(0.10, 1.0, 1.5), 15, 10.0)
	_assert_equal(is_equal_approx(float(result["work_multiplier_at_max_depth"]), pow(1.5, 2)), true, "the third Processor receives complexity 2")
	_assert_equal(is_equal_approx(float(result["seconds_per_unit_at_deepest_stage"]), pow(1.5, 2) / 4.0), true, "seconds per unit at the deepest stage follow its work multiplier")


func _test_booster_multiplies_exponential_capacity() -> void:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(1, true), 15)
	var processor: int = BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)[0]
	BalanceExperimentConfig.new(0.10, 1.0, 1.5).apply()
	var boosted := manager.simulation.get_effective_capacity(processor)
	BalanceExperimentConfig.restore_production()
	_assert_equal(is_equal_approx(boosted, NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR) * (1.0 + LineBalance.BOOSTER_BONUS)), true, "a Booster multiplies the first Processor's full capacity")


func _test_high_complexity_unit_eventually_completes() -> void:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(1), 15)
	var processor: int = BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)[0]
	BalanceExperimentConfig.new(0.10, 1.0, 1.2).apply()
	manager.simulation.seed_queue(processor, LargeNumber.from_int(1), LargeNumber.from_int(1), false, 40)
	var top := {"complexity": -1}
	manager.payout_received.connect(func(_amount: LargeNumber, _output: int, complexity: int) -> void:
		top["complexity"] = maxi(int(top["complexity"]), complexity))
	for _index in range(8000):
		manager.step(0.05)
	BalanceExperimentConfig.restore_production()
	_assert_equal(int(top["complexity"]), 41, "a complexity-40 unit completes within 400 s without deadlock")


func _test_csv_header_carries_the_work_fields() -> void:
	var sim := BalanceRunner.measure(BalanceTopologies.sequential(2), BalanceExperimentConfig.new(0.10, 1.0, 1.2), 15, 10.0)
	var header := BalanceAnalysis.csv_text(BalanceAnalysis.rows([sim], [1.0], [1000], [45])).split("\n")[0]
	_assert_equal(header.contains("complexity_model") and header.contains("work_base") and header.contains("limit_class") and header.contains("first_payout_flag"), true, "the CSV header carries the work-model and playability fields")


func _test_live_complexity_model_is_restored() -> void:
	BalanceExperimentConfig.new(0.30, 1.0, 1.4).apply()
	BalanceExperimentConfig.restore_production()
	_assert_equal(ComplexityModel.work_base, 0.0, "the live model is restored to hyperbolic after the harness")
	_assert_equal(is_equal_approx(ComplexityModel.processing_modifier(1), 1.0 / (1.0 + LineBalance.COMPLEXITY_COST_PER_LEVEL)), true, "the live hyperbolic formula is unchanged")


func _synthetic_row(topology: String, value: float, conserved: bool) -> Dictionary:
	var row := {
		"generator_level": 15, "complexity_k": 0.10, "processor_cost_growth": 1.0, "budget": 1000,
		"cell_limit": 9, "duration": 300, "conserved": conserved, "family": "sequential", "topology": topology,
	}
	for objective in BalanceAnalysis.OBJECTIVES:
		row[objective] = value
	return row
