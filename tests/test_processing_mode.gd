extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_processing_mode.gd
# Processing-balance modes: formulas, identical value and complexity, Booster arithmetic, live switching with
# conservation, progress preservation, save round trips, legacy saves, and reset. Automated defaults stay LIVE.

const TEST_PATH := "user://processing_mode_test.json"
const LIVE := ProcessingBalance.Mode.LIVE_HYPERBOLIC
const CANDIDATE := ProcessingBalance.Mode.EXPONENTIAL_CANDIDATE_1

var _failures := 0


func _init() -> void:
	SaveManager.path = TEST_PATH
	_test_formulas_match_each_mode()
	_test_complexity_zero_has_full_speed_in_both_modes()
	_test_value_and_output_complexity_are_identical_in_both_modes()
	_test_booster_multiplies_capacity_in_both_modes()
	_test_switching_keeps_resources_and_conserves_in_both_directions()
	_test_switching_preserves_unit_progress_fraction()
	_test_mode_round_trips_through_the_save()
	_test_save_without_the_field_loads_with_the_default_and_needs_saving()
	_test_unknown_mode_value_falls_back_to_the_default()
	_test_reset_keeps_the_selected_mode()
	_test_automated_sessions_default_to_live()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

	if _failures == 0:
		print("All processing mode tests passed.")
	else:
		printerr("%d processing mode assertion(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _assert_close(actual: float, expected: float, message: String) -> void:
	_assert_equal(is_equal_approx(actual, expected), true, "%s (expected %s, got %s)" % [message, expected, actual])


func _test_formulas_match_each_mode() -> void:
	_assert_close(ComplexityModel.processing_modifier(3, LIVE), 1.0 / (1.0 + 0.10 * 3), "LIVE uses the hyperbolic formula")
	_assert_close(ComplexityModel.processing_modifier(1, CANDIDATE), 1.0 / 1.10, "Candidate 1 complexity 1 is 1 / 1.10")
	for complexity in [2, 5, 10]:
		_assert_close(ComplexityModel.processing_modifier(complexity, CANDIDATE), 1.0 / pow(1.10, complexity), "Candidate 1 complexity %d is 1 / 1.10^%d" % [complexity, complexity])


func _test_complexity_zero_has_full_speed_in_both_modes() -> void:
	_assert_equal(ComplexityModel.processing_modifier(0, LIVE), 1.0, "the first Processor runs at full speed under LIVE")
	_assert_equal(ComplexityModel.processing_modifier(0, CANDIDATE), 1.0, "the first Processor runs at full speed under Candidate 1")


func _test_value_and_output_complexity_are_identical_in_both_modes() -> void:
	for mode in [LIVE, CANDIDATE]:
		var manager := BalanceTopologies.build(BalanceTopologies.sequential(2), 15)
		manager.simulation.processing_mode = mode
		var seen := {"complexity": -1, "value": ""}
		manager.payout_received.connect(func(amount: LargeNumber, _output: int, complexity: int) -> void:
			seen["complexity"] = complexity
			seen["value"] = amount.to_text())
		var money_before := manager.simulation.money
		for _index in range(1200):
			manager.step(0.05)
		var paid: LargeNumber = manager.simulation.paid_units
		var revenue: LargeNumber = manager.simulation.money.subtract(money_before)
		_assert_equal(seen["complexity"], 2, "two Processors output complexity 2 under %s" % ProcessingBalance.save_name(mode))
		_assert_equal(revenue.compare(paid.multiply(LargeNumber.from_int(4))), 0, "every paid unit is worth 2^2 under %s" % ProcessingBalance.save_name(mode))


func _test_booster_multiplies_capacity_in_both_modes() -> void:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(1, true), 15)
	var processor: int = BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)[0]
	var base := NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR) * (1.0 + LineBalance.BOOSTER_BONUS)
	_assert_close(manager.simulation.get_effective_capacity(processor), base, "a Booster multiplies capacity under LIVE")
	manager.simulation.processing_mode = CANDIDATE
	_assert_close(manager.simulation.get_effective_capacity(processor), base, "a Booster multiplies capacity under Candidate 1 at complexity 0")


func _test_switching_keeps_resources_and_conserves_in_both_directions() -> void:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(3), 15)
	var simulation := manager.simulation
	for _index in range(600):
		manager.step(0.05)
	var produced_before := simulation.produced_units.to_text()
	var paid_before := simulation.paid_units.to_text()
	var money_before := simulation.money.to_text()
	var waiting_before: String = manager.get_network_summary()["waiting"].to_text()

	simulation.set_processing_mode(CANDIDATE)
	_assert_equal(simulation.produced_units.to_text(), produced_before, "switching to Candidate 1 creates no resources")
	_assert_equal(simulation.paid_units.to_text(), paid_before, "switching to Candidate 1 pays nothing extra")
	_assert_equal(simulation.money.to_text(), money_before, "switching to Candidate 1 changes no money")
	_assert_equal(manager.get_network_summary()["waiting"].to_text(), waiting_before, "switching keeps every queued unit")
	for _index in range(600):
		manager.step(0.05)
	_assert_equal(_conserved(simulation), true, "conservation holds after switching to Candidate 1")

	simulation.set_processing_mode(LIVE)
	_assert_equal(_conserved(simulation), true, "conservation holds immediately after switching back to LIVE")
	for _index in range(600):
		manager.step(0.05)
	_assert_equal(_conserved(simulation), true, "conservation holds after switching back to LIVE and running on")


func _test_switching_preserves_unit_progress_fraction() -> void:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(1), 15)
	var simulation := manager.simulation
	var processor: int = BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)[0]
	simulation.seed_queue(processor, LargeNumber.from_int(1), LargeNumber.from_int(1), false, 2)
	var capacity := simulation.get_capacity(processor)
	simulation._budgets[processor] = 0.5 * ComplexityModel.unit_cost_seconds(capacity, 2, LIVE)
	simulation.set_processing_mode(CANDIDATE)
	_assert_close(float(simulation._budgets[processor]), 0.5 * ComplexityModel.unit_cost_seconds(capacity, 2, CANDIDATE), "a unit 50% complete stays 50% complete after switching")


func _test_mode_round_trips_through_the_save() -> void:
	for mode in [CANDIDATE, LIVE]:
		var session := GameSession.new_game(mode)
		var parsed := SaveManager.parse(JSON.stringify(SaveManager.serialize(session)))
		_assert_equal(parsed.has("error"), false, "a save with mode %s parses" % ProcessingBalance.save_name(mode))
		_assert_equal(parsed["session"].network.simulation.processing_mode, mode, "mode %s is restored from the save" % ProcessingBalance.save_name(mode))
		_assert_equal(parsed["legacy_mode"], false, "a save that carries the field is not legacy")


func _test_save_without_the_field_loads_with_the_default_and_needs_saving() -> void:
	var data := SaveManager.serialize(GameSession.new_game(CANDIDATE))
	data.erase("processing_balance_mode")
	var with_candidate := SaveManager.parse(JSON.stringify(data), CANDIDATE)
	_assert_equal(with_candidate["session"].network.simulation.processing_mode, CANDIDATE, "an old save takes the playtest default")
	_assert_equal(with_candidate["legacy_mode"], true, "an old save is flagged so it is written with the field")
	var with_live := SaveManager.parse(JSON.stringify(data), LIVE)
	_assert_equal(with_live["session"].network.simulation.processing_mode, LIVE, "an old save takes the default passed by the caller")


func _test_unknown_mode_value_falls_back_to_the_default() -> void:
	var data := SaveManager.serialize(GameSession.new_game(LIVE))
	data["processing_balance_mode"] = "SOMETHING_ELSE"
	var parsed := SaveManager.parse(JSON.stringify(data), CANDIDATE)
	_assert_equal(parsed.has("error"), false, "an unknown mode value does not reject the save")
	_assert_equal(parsed["session"].network.simulation.processing_mode, CANDIDATE, "an unknown mode value falls back to the default")
	_assert_equal(parsed["legacy_mode"], true, "an unknown mode value is re-saved with a valid value")


func _test_reset_keeps_the_selected_mode() -> void:
	SaveManager.write(GameSession.new_game(CANDIDATE))
	var fresh := SaveManager.reset_progress(CANDIDATE)
	_assert_equal(fresh.network.simulation.processing_mode, CANDIDATE, "Reset Progress keeps the Candidate 1 mode")
	var reloaded := SaveManager.load_or_new(LIVE)
	_assert_equal(reloaded["session"].network.simulation.processing_mode, CANDIDATE, "the kept mode is what the saved reset game loads with")


func _test_automated_sessions_default_to_live() -> void:
	_assert_equal(GameSession.new_game().network.simulation.processing_mode, LIVE, "an automated session without an explicit mode is LIVE")


func _conserved(simulation: ProductionSimulation) -> bool:
	var accounted := simulation.paid_units.add(simulation.get_held_units()).add(simulation.lost_units)
	return accounted.compare(simulation.produced_units) == 0
