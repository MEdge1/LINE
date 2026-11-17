extends SceneTree

# Focused checks for the Booster-relief hook. Live behaviour (no active model) is covered by test_balance_harness.

var _failures := 0


func _init() -> void:
	_test_relief_formulas()
	_test_relief_never_goes_negative()
	_test_inactive_relief_leaves_work_complexity_alone()
	_test_relief_replaces_booster_bonus_only_while_active()
	_test_phase1b_formulas()
	_test_phase1b_models_stack_on_the_bonus()
	_test_short_relieved_run_conserves_and_restores()
	print("BOOSTER RELIEF TESTS failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		push_error("FAIL %s: expected %s, got %s" % [message, str(expected), str(actual)])


func _test_relief_formulas() -> void:
	_assert_equal(ComplexityRelief.effective(10, {"kind": "flat", "amount": 3}), 7, "flat relief subtracts its amount")
	_assert_equal(ComplexityRelief.effective(20, {"kind": "percent", "fraction": 0.15}), 17, "percent relief is floor(c × f) subtracted")
	_assert_equal(ComplexityRelief.effective(7, {"kind": "percent", "fraction": 0.5}), 4, "percent relief rounds down before subtracting")
	_assert_equal(ComplexityRelief.effective(10, {"kind": "minimum_plus", "minimum": 3, "fraction": 0.1}), 7, "minimum relief applies when it exceeds the percentage")
	_assert_equal(ComplexityRelief.effective(40, {"kind": "minimum_plus", "minimum": 2, "fraction": 0.25}), 30, "percentage relief applies when it exceeds the minimum")


func _test_relief_never_goes_negative() -> void:
	_assert_equal(ComplexityRelief.effective(2, {"kind": "flat", "amount": 5}), 0, "flat relief cannot make complexity negative")
	_assert_equal(ComplexityRelief.effective(0, {"kind": "percent", "fraction": 0.5}), 0, "zero complexity stays zero")
	_assert_equal(ComplexityRelief.effective(-3, {"kind": "flat", "amount": 1}), 0, "negative input is clamped to zero")


func _test_inactive_relief_leaves_work_complexity_alone() -> void:
	ComplexityRelief.active = {}
	_assert_equal(ComplexityRelief.work_complexity(9, true), 9, "no active model means work complexity is unchanged")


func _test_relief_replaces_booster_bonus_only_while_active() -> void:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(2, true), 5)
	var processor: int = BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)[0]
	var base := NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR)
	var live := manager.simulation.get_capacity(processor)
	_assert_equal(is_equal_approx(live, base * (1.0 + LineBalance.BOOSTER_BONUS)), true, "live boosted Processor keeps the +25% bonus")

	ComplexityRelief.active = {"kind": "percent", "fraction": 0.20}
	var relieved := manager.simulation.get_capacity(processor)
	ComplexityRelief.active = {}
	_assert_equal(is_equal_approx(relieved, base), true, "an active relief model replaces the Booster bonus on Processors")
	_assert_equal(is_equal_approx(manager.simulation.get_capacity(processor), live), true, "clearing the model restores the live bonus")



func _test_phase1b_formulas() -> void:
	var models := ComplexityRelief.phase1b_models()
	var by_id := {}
	for model in models:
		by_id[model["id"]] = model["spec"]
	_assert_equal(ComplexityRelief.relief_amount(20, by_id["A"]), 3, "Model A relief at 20 is floor(3.0)")
	_assert_equal(ComplexityRelief.effective(4, by_id["B"]), 2, "Model B minimum relief of 2 applies at complexity 4")
	_assert_equal(ComplexityRelief.effective(20, by_id["B"]), 16, "Model B relief at 20 is 4")
	_assert_equal(ComplexityRelief.effective(20, by_id["C"]), 15, "Model C relief at 20 is 5")
	_assert_equal(ComplexityRelief.effective(10, by_id["D"]), 7, "Model D minimum of 3 applies at complexity 10")
	_assert_equal(ComplexityRelief.effective(1, by_id["D"]), 0, "Model D never takes effective complexity below zero")
	_assert_equal(ComplexityRelief.replaces_bonus(), false, "no active model means the bonus is not replaced")


func _test_phase1b_models_stack_on_the_bonus() -> void:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(2, true), 5)
	var processor: int = BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)[0]
	var base := NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR)
	ComplexityRelief.active = {"kind": "minimum_plus", "minimum": 1, "fraction": 0.15, "stacks": true}
	var stacked := manager.simulation.get_capacity(processor)
	var replaces := ComplexityRelief.replaces_bonus()
	ComplexityRelief.active = {}
	_assert_equal(is_equal_approx(stacked, base * (1.0 + LineBalance.BOOSTER_BONUS)), true, "a stacking model keeps the +25% bonus")
	_assert_equal(replaces, false, "a stacking model does not replace the bonus")
func _test_short_relieved_run_conserves_and_restores() -> void:
	var config := BalanceExperimentConfig.new(0.10, 1.0, 1.10)
	var spec := BalanceTopologies.sequential(4, true)
	var manager := BalanceTopologies.build(spec, 15)
	ComplexityRelief.active = {"kind": "flat", "amount": 2}
	var result := BalanceRunner.measure_built(manager, spec, config, 15, 120.0)
	ComplexityRelief.active = {}
	BalanceExperimentConfig.restore_production()
	_assert_equal(bool(result["windows"][0]["conserved"]), true, "a relieved run conserves value")
	_assert_equal(ComplexityModel.work_base, 0.0, "production work base is restored after the run")
