extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_resource_flow.gd
# Asserts correctness and bounds. Stress measurements are printed for the report, not asserted.

const STEP := 0.05

var _failures := 0


func _init() -> void:
	_test_disconnected_backlog_is_bounded_and_conserved()
	_test_long_processor_chain_is_exact()
	_test_release_after_connection_is_rate_limited()
	_test_visual_caps_do_not_change_totals()
	_test_deleting_node_records_its_backlog_as_lost()
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


# Finds the processed value currently queued at a node, or 0 if none is queued.
func _processed_value_at(simulation: ProductionSimulation, node_id: int) -> String:
	for batch in simulation.get_waiting(node_id):
		if batch.processed:
			return batch.value_per_unit.to_text()
	return "0"


func _test_disconnected_backlog_is_bounded_and_conserved() -> void:
	var graph := NetworkGraph.new()
	var ids := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR])
	var simulation := _new_simulation(graph)

	var worst_queue := 0
	for _i in range(2400):
		simulation.step(STEP)
		worst_queue = maxi(worst_queue, simulation.get_waiting_total(ids[1]).to_int_clamped())

	_assert_equal(worst_queue <= LineBalance.BUFFER_CAPACITY, true, "a disconnected backlog never exceeds the buffer")
	_assert_equal(simulation.get_waiting_batch_count() <= 4, true, "a backlog is a handful of batches, not one per unit")
	_assert_equal(_conservation_holds(simulation), true, "produced = paid + held + lost while backed up")


func _test_long_processor_chain_is_exact() -> void:
	var graph := NetworkGraph.new()
	var types: Array = [NodeDefinitions.Type.GENERATOR]
	for _i in range(70):
		types.append(NodeDefinitions.Type.PROCESSOR)
	types.append(NodeDefinitions.Type.OUTPUT)
	_chain(graph, types)
	var simulation := _new_simulation(graph)

	var payouts: Array[String] = []
	simulation.payout_received.connect(func(amount: LargeNumber, _output_id: int, _complexity: int) -> void: payouts.append(amount.to_text()))
	var elapsed := 0.0
	while payouts.is_empty() and elapsed < 300.0:
		simulation.step(STEP)
		elapsed += STEP

	_assert_equal(payouts.size() > 0, true, "a 70-processor chain still pays out")
	_assert_equal(payouts[0], "1180591620717411303424", "the first payout is exactly 2^70, not a wrapped value")
	_assert_equal(_conservation_holds(simulation), true, "the long chain conserves every unit")


# A backlog released onto a new connection flows at the processor's capacity, not as one spike.
func _test_release_after_connection_is_rate_limited() -> void:
	var graph := NetworkGraph.new()
	var ids := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR])
	var simulation := _new_simulation(graph)
	for _i in range(1200):
		simulation.step(STEP)

	var output := graph.add_node(NodeDefinitions.Type.OUTPUT)
	graph.connect_nodes(ids[1], output)
	for _i in range(200):
		simulation.step(STEP)
	var paid_before := simulation.paid_units.to_int_clamped()
	for _i in range(20):
		simulation.step(STEP)
	var paid_in_one_second := simulation.paid_units.to_int_clamped() - paid_before

	_assert_equal(paid_in_one_second > 0, true, "the backlog starts paying once connected")
	_assert_equal(paid_in_one_second <= 5, true, "one second of release is bounded by processor capacity")
	_assert_equal(_conservation_holds(simulation), true, "the release conserves every unit")


func _test_visual_caps_do_not_change_totals() -> void:
	var graph := NetworkGraph.new()
	var source := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var target := graph.add_node(NodeDefinitions.Type.OUTPUT)
	graph.connect_nodes(source, target)
	var simulation := _new_simulation(graph)
	simulation.seed_queue(source, LargeNumber.from_int(500), LargeNumber.from_int(1), false)

	var held_before := simulation.get_held_units().to_text()
	var view := NetworkView.new()
	view.simulation = simulation
	view.graph = graph
	view.layout = WorkspaceLayout.new()
	var plan_size := view.plan_particles().size()
	view.free()

	_assert_equal(plan_size <= VisualLimits.PARTICLES_TOTAL, true, "visual particles stay within the global cap")
	_assert_equal(simulation.get_held_units().to_text(), held_before, "planning visuals leaves held quantity unchanged")


func _test_deleting_node_records_its_backlog_as_lost() -> void:
	var graph := NetworkGraph.new()
	var ids := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR])
	var simulation := _new_simulation(graph)
	for _i in range(400):
		simulation.step(STEP)
	var backlog := simulation.get_waiting_total(ids[1])

	simulation.drop_node_state(ids[1])
	graph.remove_node(ids[1])

	_assert_equal(simulation.get_waiting_batch_count() <= 1, true, "deleting a node clears its backlog")
	_assert_equal(simulation.lost_units.compare(backlog) >= 0, true, "the deleted backlog is recorded as lost, not vanished")
	_assert_equal(_conservation_holds(simulation), true, "deletion keeps the ledger balanced")


func _test_disconnect_returns_in_flight_quantity_and_value() -> void:
	var graph := NetworkGraph.new()
	var generator := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var processor := graph.add_node(NodeDefinitions.Type.PROCESSOR)
	var output := graph.add_node(NodeDefinitions.Type.OUTPUT)
	graph.connect_nodes(generator, processor)
	graph.connect_nodes(processor, output)
	var simulation := _new_simulation(graph)

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
	var returned = _disconnect(graph, simulation, processor, output)

	_assert_equal(returned.compare(on_edge), 0, "the returned quantity equals what was travelling on the edge")
	_assert_equal(simulation.get_held_units().to_text(), held_before, "no resources are duplicated or lost by disconnecting")
	_assert_equal(simulation.money.to_text(), money_before, "disconnecting pays nothing and loses nothing")
	_assert_equal(_processed_value_at(simulation, processor), edge_value, "returned batches keep their processed value")
	_assert_equal(_conservation_holds(simulation), true, "the ledger stays balanced across a disconnect")

	for _i in range(200):
		simulation.step(STEP)
	for batch in simulation.in_flight:
		_assert_equal(batch.to_id == output and batch.from_id == processor, false,
			"no new resources enter the removed edge")


# Disconnecting mid-drain stops further payouts from that edge, and reconnecting resumes them.
func _test_disconnect_during_backlog_drain_is_safe() -> void:
	var graph := NetworkGraph.new()
	var generator := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var processor := graph.add_node(NodeDefinitions.Type.PROCESSOR)
	var output := graph.add_node(NodeDefinitions.Type.OUTPUT)
	graph.connect_nodes(generator, processor)
	graph.connect_nodes(processor, output)
	var simulation := _new_simulation(graph)

	for _i in range(200):
		simulation.step(STEP)
	_disconnect(graph, simulation, processor, output)
	for _i in range(200):
		simulation.step(STEP)

	graph.connect_nodes(processor, output)
	for _i in range(40):
		simulation.step(STEP)
	_disconnect(graph, simulation, processor, output)
	for _i in range(40):
		simulation.step(STEP)
	var paid_at_disconnect := simulation.paid_units.to_text()
	for _i in range(400):
		simulation.step(STEP)

	_assert_equal(simulation.paid_units.to_text(), paid_at_disconnect,
		"once the Output's queue drains, no further payouts occur from the removed edge")
	_assert_equal(_conservation_holds(simulation), true, "disconnecting mid-drain conserves every unit")


func _disconnect(graph: NetworkGraph, simulation: ProductionSimulation, from_id: int, to_id: int) -> LargeNumber:
	graph.disconnect_nodes(from_id, to_id)
	return simulation.return_edge_to_source(from_id, to_id)


# Practical stress run: many nodes, a 40-processor chain under sustained production, a backed-up
# processor later connected, and several payouts. Prints measurements for the report.
func _stress_scenario() -> void:
	var graph := NetworkGraph.new()

	var chain_types: Array = [NodeDefinitions.Type.GENERATOR]
	for _i in range(40):
		chain_types.append(NodeDefinitions.Type.PROCESSOR)
	chain_types.append(NodeDefinitions.Type.OUTPUT)
	var chain := _chain(graph, chain_types)

	var backlog := _chain(graph, [NodeDefinitions.Type.GENERATOR, NodeDefinitions.Type.PROCESSOR])
	var backlog_output := graph.add_node(NodeDefinitions.Type.OUTPUT)

	for _i in range(20):
		var generator := graph.add_node(NodeDefinitions.Type.GENERATOR)
		var processor := graph.add_node(NodeDefinitions.Type.PROCESSOR)
		var output := graph.add_node(NodeDefinitions.Type.OUTPUT)
		graph.connect_nodes(generator, processor)
		graph.connect_nodes(processor, output)

	var simulation := _new_simulation(graph)
	var first_chain_payouts: Array[String] = []
	simulation.payout_received.connect(func(amount: LargeNumber, output_id: int, _complexity: int) -> void:
		if output_id == chain[-1] and first_chain_payouts.is_empty():
			first_chain_payouts.append(amount.to_text()))

	var max_in_flight := 0
	var max_queue := 0
	var max_queue_batches := 0
	var started := Time.get_ticks_usec()
	var steps := 0

	for _i in range(12000):
		simulation.step(STEP)
		steps += 1
		max_in_flight = maxi(max_in_flight, simulation.in_flight.size())
		max_queue = maxi(max_queue, _largest_queue(simulation, graph))
		max_queue_batches = maxi(max_queue_batches, simulation.get_waiting_batch_count())

	graph.connect_nodes(backlog[1], backlog_output)
	for _i in range(4000):
		simulation.step(STEP)
		steps += 1
		max_in_flight = maxi(max_in_flight, simulation.in_flight.size())
		max_queue = maxi(max_queue, _largest_queue(simulation, graph))
		max_queue_batches = maxi(max_queue_batches, simulation.get_waiting_batch_count())

	var per_step := float(Time.get_ticks_usec() - started) / float(steps)

	_assert_equal(first_chain_payouts.size() > 0 and first_chain_payouts[0] == "1099511627776", true,
		"the 40-processor chain pays exactly 2^40 for its first unit")
	_assert_equal(_conservation_holds(simulation), true, "stress run conserves every unit")
	_assert_equal(max_queue <= LineBalance.BUFFER_CAPACITY, true, "no queue exceeds its buffer in the stress run")
	_assert_equal(max_in_flight <= 200, true, "in-flight batches stay bounded by path length, not by quantity")

	print("STRESS nodes=%d steps=%d produced=%s paid=%s held=%s money=%s" % [
		graph.get_node_ids().size(), steps,
		simulation.produced_units.to_text(), simulation.paid_units.to_text(),
		simulation.get_held_units().to_text(), simulation.money.to_text(),
	])
	print("STRESS max_in_flight_batches=%d max_queue_batches=%d max_queue_quantity=%d usec_per_step=%.2f" % [
		max_in_flight, max_queue_batches, max_queue, per_step,
	])


func _largest_queue(simulation: ProductionSimulation, graph: NetworkGraph) -> int:
	var largest := 0
	for id in graph.get_node_ids():
		largest = maxi(largest, simulation.get_waiting_total(id).to_int_clamped())
	return largest
