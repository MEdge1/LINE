extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_production_simulation.gd

const STEP := 0.05
const MAX_SECONDS := 10.0

var _failures := 0


func _init() -> void:
	_test_generator_produces_one_unit_per_second()
	_test_unit_is_processed_and_paid_at_output()
	_test_upgrade_spends_money_and_increases_rate()

	if _failures == 0:
		print("All production simulation tests passed.")
	else:
		printerr("%d production simulation assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _test_generator_produces_one_unit_per_second() -> void:
	var simulation := ProductionSimulation.new()

	simulation.step(1.0)

	_assert_equal(simulation.units.size(), 1, "one unit after one second at 1.00/sec")
	_assert_equal(simulation.units[0].leg, 0, "new unit starts on generator -> processor leg")


func _test_unit_is_processed_and_paid_at_output() -> void:
	var simulation := ProductionSimulation.new()
	var elapsed := 0.0

	while simulation.money == 0 and elapsed < MAX_SECONDS:
		simulation.step(STEP)
		elapsed += STEP

	_assert_equal(simulation.money, LineBalance.UNIT_START_VALUE * LineBalance.PROCESSOR_MULTIPLIER,
		"first unit is multiplied by the processor and paid at output")
	_assert_equal(simulation.units.size(), 2, "paid unit is removed; the two later units remain in flight")


func _test_upgrade_spends_money_and_increases_rate() -> void:
	var simulation := ProductionSimulation.new()

	_assert_equal(simulation.upgrade_generator(), false, "upgrade is rejected without funds")

	simulation.money = simulation.get_upgrade_cost()
	_assert_equal(simulation.upgrade_generator(), true, "upgrade succeeds with exact funds")
	_assert_equal(simulation.money, 0, "upgrade deducts its cost")
	_assert_equal(simulation.generator_level, 2, "upgrade increases generator level")
	_assert_equal(is_equal_approx(simulation.get_generator_rate(), 1.25), true,
		"level 2 generator produces 1.25/sec")
