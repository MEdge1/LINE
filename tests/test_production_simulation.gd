extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_production_simulation.gd

const STEP := 0.05
const MAX_SECONDS := 20.0

var _failures := 0


func _init() -> void:
	_test_generator_to_output_pays_unprocessed_value()
	_test_processor_doubles_value_before_output()
	_test_chained_processors_compound()
	_test_unconnected_generator_produces_nothing()
	_test_held_production_drains_once_connected()
	_test_payouts_sum_to_money_earned()
	_test_upgrade_changes_rate_and_costs_currency()
	_test_upgrade_stops_at_max_level_without_spending()
	_test_dropping_node_state_removes_its_batches()

	if _failures == 0:
		print("All production simulation tests passed.")
	else:
		printerr("%d production simulation assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _assert_money(simulation: ProductionSimulation, expected: int, message: String) -> void:
	_assert_equal(simulation.money.to_text(), str(expected), message)


func _new_simulation(graph: NetworkGraph) -> ProductionSimulation:
	var simulation := ProductionSimulation.new(graph)
	simulation.money = LargeNumber.from_int(0)
	return simulation


# Builds a linear chain of node types, connecting each to the next.
func _chain(graph: NetworkGraph, types: Array) -> Array:
	var ids: Array = []
	for type in types:
		ids.append(graph.add_node(type))
	for index in range(ids.size() - 1):
		_assert_equal(graph.connect_nodes(ids[index], ids[index + 1]), NetworkGraph.Rejection.NONE, "chain connection is valid")
	return ids


func _held_count(simulation: ProductionSimulation) -> int:
	return simulation.in_flight.size() + simulation.get_waiting_batch_count()


func _run_until_money(simulation: ProductionSimulation, target: int) -> void:
	var elapsed := 0.0
	while simulation.money.compare(LargeNumber.from_int(target)) < 0 and elapsed < MAX_SECONDS:
		simulation.step(STEP)
		elapsed += STEP


func _test_generator_to_output_pays_unprocessed_value() -> void:
	var graph := NetworkGraph.new()
	_chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.OUTPUT])
	var simulation := _new_simulation(graph)

	_run_until_money(simulation, 1)

	_assert_money(simulation, LineBalance.UNIT_START_VALUE, "generator -> output pays the unprocessed value")


func _test_processor_doubles_value_before_output() -> void:
	var graph := NetworkGraph.new()
	_chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR, NodeDefinitions.Type.OUTPUT])
	var simulation := _new_simulation(graph)

	_run_until_money(simulation, 1)

	_assert_money(simulation, LineBalance.UNIT_START_VALUE * LineBalance.PROCESSOR_MULTIPLIER,
		"generator -> processor -> output pays the processed value")


func _test_chained_processors_compound() -> void:
	var graph := NetworkGraph.new()
	_chain(graph, [
		NodeDefinitions.Type.GENERATOR,
		NodeDefinitions.Type.PROCESSOR,
		NodeDefinitions.Type.PROCESSOR,
		NodeDefinitions.Type.OUTPUT,
	])
	var simulation := _new_simulation(graph)

	_run_until_money(simulation, 1)

	_assert_money(simulation, 4, "two processors compound the value to 4")


func _test_unconnected_generator_produces_nothing() -> void:
	var graph := NetworkGraph.new()
	graph.add_node(NodeDefinitions.Type.GENERATOR)
	var simulation := _new_simulation(graph)

	for _i in range(200):
		simulation.step(STEP)

	_assert_equal(_held_count(simulation), 0, "generator without a connection creates no resources")
	_assert_money(simulation, 0, "generator without a connection earns nothing")


# Held production must not stay stuck once a route exists, and draining must not release only one unit.
# The conservation ledger proves nothing is lost along the way.
func _test_held_production_drains_once_connected() -> void:
	var graph := NetworkGraph.new()
	var ids := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR])
	var simulation := _new_simulation(graph)

	for _i in range(200):
		simulation.step(STEP)
	_assert_equal(simulation.money.is_zero(), true, "generator -> processor with no output earns nothing")
	_assert_equal(simulation.paid_units.is_zero(), true, "no units are paid without an output")
	_assert_equal(simulation.get_held_units().compare(simulation.produced_units), 0, "all produced units are held")

	var output_id := graph.add_node(NodeDefinitions.Type.OUTPUT)
	_assert_equal(graph.connect_nodes(ids[1], output_id), NetworkGraph.Rejection.NONE, "processor connects to output")

	for _i in range(400):
		simulation.step(STEP)
	_assert_equal(simulation.paid_units.compare(LargeNumber.from_int(8)) > 0, true,
		"draining releases more than one unit at a time")
	_assert_equal(simulation.money.compare(simulation.paid_units.multiply(LargeNumber.from_int(LineBalance.PROCESSOR_MULTIPLIER))), 0,
		"each paid unit is worth the processed value")
	_assert_equal(_conservation_holds(simulation), true, "produced = paid + held + lost")


func _conservation_holds(simulation: ProductionSimulation) -> bool:
	var accounted := simulation.paid_units.add(simulation.get_held_units()).add(simulation.lost_units)
	return accounted.compare(simulation.produced_units) == 0


func _test_payouts_sum_to_money_earned() -> void:
	var graph := NetworkGraph.new()
	_chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR, NodeDefinitions.Type.OUTPUT])
	var simulation := _new_simulation(graph)

	var payouts: Array[String] = []
	simulation.payout_received.connect(func(amount: LargeNumber, _output_id: int) -> void: payouts.append(amount.to_text()))

	_run_until_money(simulation, 6)

	var total := LargeNumber.from_int(0)
	for text in payouts:
		total = total.add(LargeNumber.from_int(int(text)))

	_assert_equal(payouts.size() >= 3, true, "several payouts are emitted")
	_assert_equal(total.compare(simulation.money), 0, "emitted payouts add up to money earned")


func _test_upgrade_changes_rate_and_costs_currency() -> void:
	var graph := NetworkGraph.new()
	var generator_id := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var simulation := _new_simulation(graph)

	_assert_equal(simulation.upgrade_generator(generator_id), false, "upgrade is rejected without funds")

	simulation.money = simulation.get_upgrade_cost(generator_id)
	_assert_equal(simulation.upgrade_generator(generator_id), true, "upgrade succeeds with exact funds")
	_assert_money(simulation, 0, "upgrade deducts its cost")
	_assert_equal(graph.get_node(generator_id).level, 2, "upgrade increases generator level")
	_assert_equal(is_equal_approx(simulation.get_generator_rate(generator_id), 1.25), true,
		"level 2 generator produces 1.25/sec")


# Level 14 -> 15 succeeds. At 15 the upgrade is refused, costs nothing, and the rate stays at the cap.
func _test_upgrade_stops_at_max_level_without_spending() -> void:
	var graph := NetworkGraph.new()
	var generator_id := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var simulation := _new_simulation(graph)

	graph.get_node(generator_id).level = LineBalance.GENERATOR_MAX_LEVEL - 1
	simulation.money = LargeNumber.from_int(1000)
	_assert_equal(simulation.upgrade_generator(generator_id), true, "level 14 upgrades to level 15")
	_assert_equal(graph.get_node(generator_id).level, LineBalance.GENERATOR_MAX_LEVEL, "generator reaches the level cap")
	_assert_equal(simulation.is_at_max_level(generator_id), true, "level 15 is reported as max level")

	var money_at_cap := simulation.money.to_text()
	for _attempt in range(3):
		_assert_equal(simulation.upgrade_generator(generator_id), false, "upgrade is rejected at the level cap")
	_assert_equal(simulation.money.to_text(), money_at_cap, "repeated capped upgrades spend nothing")
	_assert_equal(graph.get_node(generator_id).level, LineBalance.GENERATOR_MAX_LEVEL, "capped upgrades change no level")
	_assert_equal(is_equal_approx(simulation.get_generator_rate(generator_id), 4.5), true,
		"level 15 generator reports 4.50/sec")


func _test_dropping_node_state_removes_its_batches() -> void:
	var graph := NetworkGraph.new()
	var ids := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.OUTPUT])
	var simulation := _new_simulation(graph)

	for _i in range(30):
		simulation.step(STEP)
	_assert_equal(simulation.in_flight.size() > 0, true, "batches are in flight before deletion")

	simulation.drop_node_state(ids[0])

	_assert_equal(simulation.in_flight.size(), 0, "batches tied to a deleted node are removed")
