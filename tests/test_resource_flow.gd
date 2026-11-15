extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_resource_flow.gd
# Prints stress-scenario measurements; asserts only correctness and bounds, not timings.

const STEP := 0.05

var _failures := 0


func _init() -> void:
	_test_disconnected_accumulation_is_one_batch()
	_test_long_processor_chain_is_exact()
	_test_draining_releases_progressively()
	_test_visual_caps_do_not_change_totals()
	_test_deleting_node_accounts_for_its_backlog()
	_test_disconnect_returns_in_flight_quantity_and_value()
	_test_disconnect_during_backlog_drain_is_safe()
	_stress_scenario()

	if _failures == 0:
		print("All resource flow tests passed.")
	else:
		printerr("%d resource flow assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _new_simulation(graph: NetworkGraph) -> ProductionSimulation:
	var simulation := ProductionSimulation.new(graph)
	simulation.money = LargeNumber.from_int(0)
	return simulation


func _conservation_holds(simulation: ProductionSimulation) -> bool:
	var accounted := simulation.paid_units.add(simulation.get_held_units()).add(simulation.lost_units)
	return accounted.compare(simulation.produced_units) == 0


func _chain(graph: NetworkGraph, types: Array) -> Array:
	var ids: Array = []
	for type in types:
		ids.append(graph.add_node(type))
	for index in range(ids.size() - 1):
		graph.connect_nodes(ids[index], ids[index + 1])
	return ids


func _test_disconnected_accumulation_is_one_batch() -> void:
	var graph := NetworkGraph.new()
	var ids := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR])
	var simulation := _new_simulation(graph)

	for _i in range(2400):
		simulation.step(STEP)

	_assert_equal(simulation.get_waiting_batch_count(), 1, "120 seconds of backlog is one batch, not 120 objects")
	_assert_equal(simulation.get_held_units().compare(simulation.produced_units), 0,
		"the held quantity equals everything produced")
	_assert_equal(_conservation_holds(simulation), true, "produced = paid + held + lost while accumulating")


func _test_long_processor_chain_is_exact() -> void:
	var graph := NetworkGraph.new()
	var types: Array = [NodeDefinitions.Type.GENERATOR]
	for _i in range(70):
		types.append(NodeDefinitions.Type.PROCESSOR)
	types.append(NodeDefinitions.Type.OUTPUT)
	_chain(graph, types)
	var simulation := _new_simulation(graph)

	var payouts: Array[String] = []
	simulation.payout_received.connect(func(amount: LargeNumber, _output_id: int) -> void: payouts.append(amount.to_text()))
	var elapsed := 0.0
	while payouts.is_empty() and elapsed < 200.0:
		simulation.step(STEP)
		elapsed += STEP

	_assert_equal(payouts.size() > 0, true, "a 70-processor chain still pays out")
	_assert_equal(payouts[0], "1180591620717411303424", "the first payout is exactly 2^70, not a wrapped value")
	_assert_equal(simulation.money.compare(LargeNumber.from_int(0)) > 0, true, "money is positive, never wrapped negative or zero")


func _test_draining_releases_progressively() -> void:
	var graph := NetworkGraph.new()
	var ids := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR])
	var simulation := _new_simulation(graph)
	for _i in range(2400):
		simulation.step(STEP)
	var backlog_before := simulation.get_waiting_total(ids[1])

	var output_id := graph.add_node(NodeDefinitions.Type.OUTPUT)
	graph.connect_nodes(ids[1], output_id)
	for _i in range(20):
		simulation.step(STEP)

	var released := backlog_before.subtract(simulation.get_waiting_total(ids[1]))
	_assert_equal(released.compare(LargeNumber.from_int(1)) > 0, true, "a connection releases more than one unit")
	_assert_equal(released.compare(LargeNumber.from_int(LineBalance.DRAIN_BATCH_SIZE * 3)) <= 0, true,
		"release is rate-limited, not an instant spike")
	_assert_equal(_conservation_holds(simulation), true, "draining conserves every unit")


func _test_visual_caps_do_not_change_totals() -> void:
	var graph := NetworkGraph.new()
	var source := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var target := graph.add_node(NodeDefinitions.Type.OUTPUT)
	graph.connect_nodes(source, target)
	var manager := NetworkManager.new()
	manager.graph = graph
	manager.simulation = ProductionSimulation.new(graph)
	manager.simulation.money = LargeNumber.from_int(0)

	for _i in range(500):
		manager.simulation.in_flight.append(ResourceBatch.new(LargeNumber.from_int(1), LargeNumber.from_int(1), source, target))
	var held_before := manager.simulation.get_held_units().to_text()

	var view := NetworkView.new()
	view.simulation = manager.simulation
	view.graph = graph
	view.layout = manager.layout
	var plan := view.plan_particles()

	_assert_equal(plan.size() <= VisualLimits.PARTICLES_PER_CONNECTION, true, "one connection never draws more than its cap")
	_assert_equal(manager.simulation.get_held_units().to_text(), held_before, "capping visuals leaves the held total unchanged")
	view.free()


func _test_deleting_node_accounts_for_its_backlog() -> void:
	var graph := NetworkGraph.new()
	var ids := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR])
	var simulation := _new_simulation(graph)
	for _i in range(400):
		simulation.step(STEP)
	var backlog := simulation.get_waiting_total(ids[1])

	simulation.drop_node_state(ids[1])
	graph.remove_node(ids[1])

	_assert_equal(simulation.get_waiting_batch_count(), 0, "deleting a node clears its backlog")
	_assert_equal(simulation.lost_units.compare(backlog) >= 0, true, "the deleted backlog is recorded as lost, not vanished")
	_assert_equal(_conservation_holds(simulation), true, "deletion keeps the ledger balanced")


func _test_disconnect_returns_in_flight_quantity_and_value() -> void:
	var manager := NetworkManager.new()
	manager.simulation.money = LargeNumber.from_int(0)
	var graph := manager.graph
	var simulation := manager.simulation
	var generator := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var processor := graph.add_node(NodeDefinitions.Type.PROCESSOR)
	var output := graph.add_node(NodeDefinitions.Type.OUTPUT)
	graph.connect_nodes(generator, processor)
	graph.connect_nodes(processor, output)

	for _i in range(200):
		simulation.step(STEP)
	var on_edge := LargeNumber.from_int(0)
	var edge_value := ""
	for batch in simulation.in_flight:
		if batch.from_id == processor and batch.to_id == output:
			on_edge = on_edge.add(batch.quantity)
			edge_value = batch.value_per_unit.to_text()
	_assert_equal(on_edge.is_zero(), false, "processed resources are travelling on the edge before disconnecting")

	var held_before := simulation.get_held_units().to_text()
	var money_before := simulation.money.to_text()
	var returned = manager.disconnect_nodes(processor, output)

	_assert_equal(returned.compare(on_edge), 0, "the returned quantity equals what was travelling on the edge")
	_assert_equal(simulation.get_held_units().to_text(), held_before, "no resources are duplicated or lost by disconnecting")
	_assert_equal(simulation.money.to_text(), money_before, "disconnecting pays nothing and loses nothing")
	_assert_equal(simulation.get_waiting_total(processor).compare(on_edge), 0, "the in-flight quantity waits at its source")
	_assert_equal(simulation.get_waiting(processor)[0].value_per_unit.to_text(), edge_value, "the processed value is preserved")
	_assert_equal(_conservation_holds(simulation), true, "the ledger stays balanced across a disconnect")

	for _i in range(200):
		simulation.step(STEP)
	for batch in simulation.in_flight:
		_assert_equal(batch.to_id == output and batch.from_id == processor, false,
			"no new resources enter the removed edge")


# Disconnecting during a drain stops further release from that node, keeps the backlog, and resumes on reconnect.
func _test_disconnect_during_backlog_drain_is_safe() -> void:
	var manager := NetworkManager.new()
	manager.simulation.money = LargeNumber.from_int(0)
	var graph := manager.graph
	var simulation := manager.simulation
	var processor := graph.add_node(NodeDefinitions.Type.PROCESSOR)
	var output := graph.add_node(NodeDefinitions.Type.OUTPUT)
	var generator := graph.add_node(NodeDefinitions.Type.GENERATOR)
	graph.connect_nodes(generator, processor)
	graph.connect_nodes(processor, output)

	for _i in range(200):
		simulation.step(STEP)
	manager.disconnect_nodes(processor, output)
	for _i in range(200):
		simulation.step(STEP)
	var backlog := simulation.get_waiting_total(processor)
	var paid_before_reconnect := simulation.paid_units.to_text()

	manager.connect_nodes(processor, output)
	for _i in range(40):
		simulation.step(STEP)
	manager.disconnect_nodes(processor, output)
	var backlog_mid_drain := simulation.get_waiting_total(processor)
	_assert_equal(backlog_mid_drain.compare(backlog) < 0, true, "reconnecting drains part of the backlog")
	var paid_mid := simulation.paid_units.to_text()
	for _i in range(200):
		simulation.step(STEP)

	_assert_equal(paid_mid != paid_before_reconnect, true, "reconnected backlog pays out before the second disconnect")
	_assert_equal(simulation.paid_units.to_text(), paid_mid, "after the second disconnect, no further payouts occur")
	_assert_equal(_conservation_holds(simulation), true, "disconnecting mid-drain conserves every unit")


# Practical stress run: many nodes, a 40-processor chain under sustained production, a backlog
# that is later connected, and several payouts. Prints measurements for the report.
func _stress_scenario() -> void:
	var graph := NetworkGraph.new()

	var chain_types: Array = [NodeDefinitions.Type.GENERATOR]
	for _i in range(40):
		chain_types.append(NodeDefinitions.Type.PROCESSOR)
	chain_types.append(NodeDefinitions.Type.OUTPUT)
	var chain := _chain(graph, chain_types)

	var backlog := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR])
	var backlog_tail := _chain(graph, [NodeDefinitions.Type.PROCESSOR, NodeDefinitions.Type.PROCESSOR, NodeDefinitions.Type.OUTPUT])

	for _i in range(20):
		var generator := graph.add_node(NodeDefinitions.Type.GENERATOR)
		var processor := graph.add_node(NodeDefinitions.Type.PROCESSOR)
		var output := graph.add_node(NodeDefinitions.Type.OUTPUT)
		graph.connect_nodes(generator, processor)
		graph.connect_nodes(processor, output)

	var simulation := _new_simulation(graph)
	var first_chain_payouts: Array[String] = []
	simulation.payout_received.connect(func(amount: LargeNumber, output_id: int) -> void:
		if output_id == chain[-1] and first_chain_payouts.is_empty():
			first_chain_payouts.append(amount.to_text()))

	var max_in_flight := 0
	var max_waiting_batches := 0
	var started := Time.get_ticks_usec()
	var steps := 0

	for _i in range(12000):
		simulation.step(STEP)
		steps += 1
		max_in_flight = maxi(max_in_flight, simulation.in_flight.size())
		max_waiting_batches = maxi(max_waiting_batches, simulation.get_waiting_batch_count())

	graph.connect_nodes(backlog[1], backlog_tail[0])
	for _i in range(4000):
		simulation.step(STEP)
		steps += 1
		max_in_flight = maxi(max_in_flight, simulation.in_flight.size())
		max_waiting_batches = maxi(max_waiting_batches, simulation.get_waiting_batch_count())

	var elapsed_us := Time.get_ticks_usec() - started
	var per_step := float(elapsed_us) / float(steps)

	_assert_equal(first_chain_payouts.size() > 0 and first_chain_payouts[0] == "1099511627776", true,
		"the 40-processor chain pays exactly 2^40 for its first unit")
	_assert_equal(_conservation_holds(simulation), true, "stress run conserves every unit")
	_assert_equal(max_waiting_batches <= 2, true, "waiting batches stay bounded by distinct values")
	_assert_equal(max_in_flight <= 200, true, "in-flight batches stay bounded by path length, not by quantity")

	print("STRESS nodes=%d steps=%d produced=%s paid=%s held=%s money=%s" % [
		graph.get_node_ids().size(), steps,
		simulation.produced_units.to_text(), simulation.paid_units.to_text(),
		simulation.get_held_units().to_text(), simulation.money.to_text(),
	])
	print("STRESS max_in_flight_batches=%d max_waiting_batches=%d usec_per_step=%.2f" % [
		max_in_flight, max_waiting_batches, per_step,
	])
