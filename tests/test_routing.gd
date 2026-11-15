extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_routing.gd

const STEP := 0.05

var _failures := 0


func _init() -> void:
	_test_split_policy_is_deterministic_and_exact()
	_test_split_policy_moves_a_blocked_share_to_the_open_branch()
	_test_processor_throughput_matches_its_capacity()
	_test_fractional_timing_is_deterministic()
	_test_full_queue_backpressures_the_generator()
	_test_splitter_alternates_branches_evenly()
	_test_merger_merges_compatible_batches_and_keeps_value()
	_test_merger_keeps_different_values_separate()
	_test_booster_bonus_follows_orthogonal_adjacency()
	_test_booster_moves_and_deletes_clear_bonus_without_stale_state()
	_test_boosters_do_not_stack()
	_test_booster_rejects_resource_connections()
	_test_bottleneck_is_detected_and_cleared_by_a_booster()
	_test_healthy_processor_is_not_flagged()
	_test_blocked_processor_is_reported_as_blocked()
	_test_routing_nodes_edit_safely()
	_test_complex_network_conserves_through_edits()
	_test_rates_are_not_read_low_during_warm_up()
	_test_returned_surplus_waits_safely_and_keeps_complexity()

	if _failures == 0:
		print("All routing tests passed.")
	else:
		printerr("%d routing assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _manager(money: int = 100000) -> NetworkManager:
	var manager := NetworkManager.new()
	manager.simulation.money = LargeNumber.from_int(money)
	return manager


func _place(manager: NetworkManager, type: int, cell: Vector2i) -> int:
	manager.construct(type, cell)
	return manager.layout.get_node_at(cell)


func _generator_at_level(manager: NetworkManager, cell: Vector2i, level: int) -> int:
	var id := _place(manager, NodeDefinitions.Type.GENERATOR, cell)
	manager.graph.get_node(id).level = level
	return id


func _conservation_holds(simulation: ProductionSimulation) -> bool:
	var accounted := simulation.paid_units.add(simulation.get_held_units()).add(simulation.lost_units)
	return accounted.compare(simulation.produced_units) == 0


func _run(manager: NetworkManager, seconds: float) -> void:
	for _i in range(int(seconds / STEP)):
		manager.step(STEP)


func _test_split_policy_is_deterministic_and_exact() -> void:
	var even := SplitPolicy.split(100, 25, 25, false)
	_assert_equal(even, Vector2i(25, 25), "even offers split equally and never exceed their room")
	var odd_a := SplitPolicy.split(101, 100, 100, false)
	_assert_equal(odd_a, Vector2i(51, 50), "an odd offer gives the extra unit to A when it is due")
	var odd_b := SplitPolicy.split(101, 100, 100, true)
	_assert_equal(odd_b, Vector2i(50, 51), "the next odd offer gives the extra unit to B")
	_assert_equal(SplitPolicy.split(101, 100, 100, false) == SplitPolicy.split(101, 100, 100, false), true,
		"identical inputs always give identical splits")


func _test_split_policy_moves_a_blocked_share_to_the_open_branch() -> void:
	_assert_equal(SplitPolicy.split(100, 0, 100, false), Vector2i(0, 100), "a full branch A sends everything to B")
	_assert_equal(SplitPolicy.split(101, 10, 100, false), Vector2i(10, 91), "a partly full A spills its share to B")
	_assert_equal(SplitPolicy.split(100, 0, 0, false), Vector2i(0, 0), "when both branches are full nothing is taken")


func _test_processor_throughput_matches_its_capacity() -> void:
	var manager := _manager()
	_generator_at_level(manager, Vector2i(0, 0), 15)
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 1))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 2))
	manager.connect_nodes(1, processor)
	manager.connect_nodes(processor, output)

	_run(manager, 20.0)
	var before := manager.simulation.paid_units.to_float()
	_run(manager, 40.0)
	var completed_per_second := (manager.simulation.paid_units.to_float() - before) / 40.0

	_assert_equal(absf(completed_per_second - NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR)) < 0.2, true,
		"a Level 15 Generator is limited to the processor's 4/sec")
	_assert_equal(_conservation_holds(manager.simulation), true, "throughput limits conserve every unit")


func _test_fractional_timing_is_deterministic() -> void:
	var first := _steady_chain_result()
	var second := _steady_chain_result()
	_assert_equal(first, second, "two identical runs produce identical totals")


func _steady_chain_result() -> String:
	var manager := _manager()
	_generator_at_level(manager, Vector2i(0, 0), 15)
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 1))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 2))
	manager.connect_nodes(1, processor)
	manager.connect_nodes(processor, output)
	_run(manager, 60.0)
	return "%s|%s" % [manager.simulation.money.to_text(), manager.simulation.get_held_units().to_text()]


func _test_full_queue_backpressures_the_generator() -> void:
	var manager := _manager()
	var generator := _generator_at_level(manager, Vector2i(0, 0), 15)
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 1))
	manager.connect_nodes(generator, processor)

	_run(manager, 60.0)
	var produced_when_blocked := manager.simulation.produced_units.to_text()
	_run(manager, 30.0)

	_assert_equal(manager.simulation.produced_units.to_text(), produced_when_blocked,
		"with no output the full buffers pause production")
	_assert_equal(manager.simulation.get_waiting_total(processor).compare(LargeNumber.from_int(LineBalance.BUFFER_CAPACITY)) <= 0, true,
		"the processor's queue stays within its buffer")
	_assert_equal(_conservation_holds(manager.simulation), true, "back-pressure loses nothing")


func _test_splitter_alternates_branches_evenly() -> void:
	var manager := _manager()
	var generator := _generator_at_level(manager, Vector2i(0, 0), 15)
	var splitter := _place(manager, NodeDefinitions.Type.SPLITTER, Vector2i(0, 1))
	var out_a := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(1, 0))
	var out_b := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(1, 1))
	manager.connect_nodes(generator, splitter)
	manager.connect_nodes(splitter, out_a)
	manager.connect_nodes(splitter, out_b)

	_run(manager, 120.0)
	var a := manager.simulation.get_revenue(out_a).to_int_clamped()
	var b := manager.simulation.get_revenue(out_b).to_int_clamped()

	_assert_equal(a > 0 and b > 0, true, "both branches receive production")
	_assert_equal(absi(a - b) <= 2, true, "branches receive equal shares, with odd units alternating")
	_assert_equal(_conservation_holds(manager.simulation), true, "splitting duplicates and loses nothing")


func _test_merger_merges_compatible_batches_and_keeps_value() -> void:
	var manager := _manager()
	var first := _generator_at_level(manager, Vector2i(0, 0), 15)
	var second := _generator_at_level(manager, Vector2i(2, 0), 15)
	var merger := _place(manager, NodeDefinitions.Type.MERGER, Vector2i(1, 1))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(1, 2))
	manager.connect_nodes(first, merger)
	manager.connect_nodes(second, merger)
	manager.connect_nodes(merger, output)

	_run(manager, 60.0)

	_assert_equal(manager.simulation.get_waiting(merger).size() <= 1, true,
		"compatible batches from two inputs merge into one queued batch")
	_assert_equal(manager.simulation.get_waiting_total(merger).compare(LargeNumber.from_int(LineBalance.BUFFER_CAPACITY)) <= 0, true,
		"the merger's queue respects its buffer")
	_assert_equal(manager.simulation.get_revenue(output).to_text(), manager.simulation.paid_units.to_text(),
		"merged raw units keep their value: revenue equals quantity paid")
	_assert_equal(_conservation_holds(manager.simulation), true, "merging conserves every unit")


func _test_merger_keeps_different_values_separate() -> void:
	var manager := _manager()
	var merger := _place(manager, NodeDefinitions.Type.MERGER, Vector2i(1, 1))
	var simulation := manager.simulation
	simulation.seed_queue(merger, LargeNumber.from_int(3), LargeNumber.from_int(1), false)
	simulation.seed_queue(merger, LargeNumber.from_int(2), LargeNumber.from_int(2), true)

	_assert_equal(simulation.get_waiting(merger).size(), 2, "batches of different value stay separate")
	_assert_equal(simulation.get_waiting_total(merger).to_text(), "5", "their quantities are preserved")


func _test_booster_bonus_follows_orthogonal_adjacency() -> void:
	var manager := _manager()
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(2, 2))
	var north := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(2, 3))
	var east := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(3, 2))
	var diagonal := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(3, 3))
	var far := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(4, 2))

	var targets: Array = manager.get_boost_targets(booster)
	_assert_equal(targets.size() == 2 and targets.has(north) and targets.has(east), true,
		"a Booster targets its orthogonal Processors only")
	_assert_equal(manager.graph.get_node(diagonal).boosted, false, "diagonal Processors are not boosted")
	_assert_equal(manager.graph.get_node(far).boosted, false, "nonadjacent Processors are not boosted")
	_assert_equal(is_equal_approx(manager.simulation.get_capacity(north), 4.0 * (1.0 + LineBalance.BOOSTER_BONUS)), true,
		"an adjacent Processor gains the centralized bonus")


func _test_booster_moves_and_deletes_clear_bonus_without_stale_state() -> void:
	var manager := _manager()
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(2, 2))
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(2, 3))

	manager.move_node(booster, Vector2i(0, 0))
	_assert_equal(manager.graph.get_node(processor).boosted, false, "moving the Booster away clears its bonus immediately")

	manager.move_node(booster, Vector2i(2, 2))
	_assert_equal(manager.graph.get_node(processor).boosted, true, "moving the Booster back restores the bonus")

	manager.move_node(processor, Vector2i(4, 4))
	manager.move_node(processor, Vector2i(2, 3))
	manager.delete_node(booster)
	_assert_equal(manager.graph.get_node(processor).boosted, false, "deleting the Booster leaves no stale bonus")
	_assert_equal(manager.simulation.get_capacity(processor), 4.0, "capacity returns to the base value")


func _test_boosters_do_not_stack() -> void:
	var manager := _manager()
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(2, 3))
	_place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(2, 2))
	_place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 3))

	_assert_equal(is_equal_approx(manager.simulation.get_capacity(processor), 4.0 * (1.0 + LineBalance.BOOSTER_BONUS)), true,
		"two adjacent Boosters give one bonus, not two")

	manager.delete_node(manager.layout.get_node_at(Vector2i(1, 3)))
	_assert_equal(is_equal_approx(manager.simulation.get_capacity(processor), 4.0 * (1.0 + LineBalance.BOOSTER_BONUS)), true,
		"removing one of two Boosters keeps the remaining bonus")


func _test_booster_rejects_resource_connections() -> void:
	var manager := _manager()
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(2, 2))
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(2, 3))

	_assert_equal(manager.connect_nodes(booster, processor), NetworkGraph.Rejection.BOOSTER_NOT_CONNECTABLE,
		"a Booster cannot send resources")
	_assert_equal(manager.connect_nodes(processor, booster), NetworkGraph.Rejection.BOOSTER_NOT_CONNECTABLE,
		"a Booster cannot receive resources")
	_assert_equal(manager.graph.get_connections().size(), 0, "rejected Booster connections create no edge")


func _test_bottleneck_is_detected_and_cleared_by_a_booster() -> void:
	var manager := _manager()
	var generator := _generator_at_level(manager, Vector2i(0, 4), 15)
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 4))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(2, 4))
	manager.connect_nodes(generator, processor)
	manager.connect_nodes(processor, output)

	_run(manager, 60.0)
	_assert_equal(manager.simulation.get_status(processor), ProductionSimulation.Status.BOTTLENECK,
		"a Level 15 Generator overwhelms a 4/sec processor: BOTTLENECK")
	_assert_equal(manager.get_network_summary()["bottlenecks"], 1, "the network summary counts the bottleneck")

	_place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 5))
	_run(manager, 60.0)
	_assert_equal(manager.simulation.get_status(processor) != ProductionSimulation.Status.BOTTLENECK, true,
		"a Booster lifts capacity to 5/sec and clears the bottleneck")


func _test_healthy_processor_is_not_flagged() -> void:
	var manager := _manager()
	var generator := _place(manager, NodeDefinitions.Type.GENERATOR, Vector2i(0, 4))
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 4))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(2, 4))
	manager.connect_nodes(generator, processor)
	manager.connect_nodes(processor, output)

	_run(manager, 60.0)
	_assert_equal(manager.simulation.get_status(processor), ProductionSimulation.Status.NORMAL,
		"a 1/sec Generator leaves a 4/sec processor unflagged")
	_assert_equal(manager.simulation.get_status(processor) == ProductionSimulation.Status.BOTTLENECK, false,
		"a healthy processor is never a bottleneck")


func _test_blocked_processor_is_reported_as_blocked() -> void:
	var manager := _manager()
	var generator := _place(manager, NodeDefinitions.Type.GENERATOR, Vector2i(0, 4))
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 4))
	manager.connect_nodes(generator, processor)

	_run(manager, 120.0)
	_assert_equal(manager.simulation.get_status(processor), ProductionSimulation.Status.BLOCKED,
		"a full queue with no output is BLOCKED, not a capacity bottleneck")


func _test_routing_nodes_edit_safely() -> void:
	var manager := _manager()
	var generator := _generator_at_level(manager, Vector2i(0, 0), 15)
	var splitter := _place(manager, NodeDefinitions.Type.SPLITTER, Vector2i(0, 1))
	var out_a := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(1, 0))
	var out_b := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(1, 1))
	manager.connect_nodes(generator, splitter)
	manager.connect_nodes(splitter, out_a)
	manager.connect_nodes(splitter, out_b)
	_run(manager, 20.0)

	_assert_equal(manager.disconnect_nodes(splitter, out_b) != null, true, "a Splitter branch can be disconnected")
	_assert_equal(manager.graph.get_outgoing(splitter), [out_a], "only the chosen branch is removed")
	_assert_equal(manager.connect_nodes(splitter, out_b), NetworkGraph.Rejection.NONE, "the branch can be reconnected")

	manager.move_node(splitter, Vector2i(3, 3))
	_assert_equal(manager.graph.get_outgoing(splitter).size(), 2, "moving a Splitter keeps its connections")

	var refund := manager.delete_node(splitter)
	_assert_equal(refund.to_text(), str(NodeDefinitions.get_cost(NodeDefinitions.Type.SPLITTER)), "deleting a Splitter refunds it")
	_assert_equal(manager.graph.get_incoming(out_a).size() + manager.graph.get_incoming(out_b).size(), 0,
		"deleting a Splitter removes its edges")
	_assert_equal(_conservation_holds(manager.simulation), true, "routing edits conserve every unit")
	_assert_equal(manager.graph.has_node(generator), true, "the upstream Generator survives")


func _test_rates_are_not_read_low_during_warm_up() -> void:
	var window := RateWindow.new()
	for index in range(4):
		window.add(0.25, index * 0.25)
	_assert_equal(absf(window.rate(1.0) - 1.0) < 0.01, true,
		"a steady 1/sec stream reads 1/sec after one second, not 0.25")
	for index in range(40):
		window.add(0.25, 1.0 + index * 0.25)
	# The window spans whole buckets, so its edge can fall one bucket (0.25 s of samples) short.
	_assert_equal(absf(window.rate(11.0) - 1.0) <= LineBalance.RATE_BUCKET_SECONDS, true,
		"the rate stays accurate, within one bucket, once the window is full")


# Parallel network with disconnect, reconnect, move, and delete through the manager,
# checking conservation as the network changes.
func _test_complex_network_conserves_through_edits() -> void:
	var manager := StrategyScenarios.build_parallel(3)
	manager.simulation.money = LargeNumber.from_int(100000)
	var graph := manager.graph
	var splitter := 0
	var merger := 0
	var branch_first := 0
	for id in graph.get_node_ids():
		var type: int = graph.get_node(id).type
		if type == NodeDefinitions.Type.SPLITTER:
			splitter = id
		elif type == NodeDefinitions.Type.MERGER:
			merger = id
	branch_first = graph.get_outgoing(splitter)[0]

	var conserved := true
	for index in range(4000):
		manager.step(STEP)
		if index == 500:
			manager.disconnect_nodes(splitter, branch_first)
		elif index == 900:
			manager.connect_nodes(splitter, branch_first)
		elif index == 1500:
			manager.delete_node(merger)
		if index % 200 == 0 and not _conservation_holds(manager.simulation):
			conserved = false

	_assert_equal(conserved, true, "conservation holds at every checkpoint of a network under edits")
	_assert_equal(_conservation_holds(manager.simulation), true, "final ledger balances after edits")


# A disconnect can return more than the source's buffer holds. The surplus waits at the source,
# the queue never exceeds BUFFER_CAPACITY, and everything drains once an output is reconnected.
func _test_returned_surplus_waits_safely_and_keeps_complexity() -> void:
	var manager := _manager()
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 0))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 1))
	manager.connect_nodes(processor, output)
	var simulation := manager.simulation
	simulation.seed_queue(processor, LargeNumber.from_int(LineBalance.BUFFER_CAPACITY), LargeNumber.from_int(1), false, 0)
	simulation.produced_units = simulation.produced_units.add(LargeNumber.from_int(20))
	simulation.in_flight.append(ResourceBatch.new(LargeNumber.from_int(20), LargeNumber.from_int(4), processor, output, true, 2))

	var returned := manager.disconnect_nodes(processor, output)
	_assert_equal(returned.to_text(), "20", "the disconnect reports the quantity returned")
	_assert_equal(_queue_units(simulation, processor) <= LineBalance.BUFFER_CAPACITY, true,
		"the queue stays within its buffer when the source is already full")
	_assert_equal(simulation.get_waiting_total(processor).to_text(), "45", "the surplus is held at the source, not lost")

	var kept_within_buffer := true
	for _i in range(100):
		manager.step(STEP)
		if _queue_units(simulation, processor) > LineBalance.BUFFER_CAPACITY:
			kept_within_buffer = false
	_assert_equal(kept_within_buffer, true, "the queue never exceeds its buffer while the surplus waits")

	var payouts: Array = []
	simulation.payout_received.connect(func(amount: LargeNumber, _output_id: int, complexity: int) -> void:
		payouts.append([amount.to_text(), complexity]))
	var second_output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 2))
	manager.connect_nodes(processor, second_output)
	_run(manager, 60.0)

	_assert_equal(simulation.paid_units.to_text(), "45", "every returned unit is eventually paid after reconnecting")
	_assert_equal(simulation.get_held_units().is_zero(), true, "nothing remains held once the source drains")
	_assert_equal(_conservation_holds(simulation), true, "the surplus is conserved end to end")
	var returned_payout := 0
	for entry in payouts:
		if entry[1] == 2:
			returned_payout += int(entry[0])
	_assert_equal(returned_payout, 80, "returned processed batches keep their complexity and are not processed again")


func _queue_units(simulation: ProductionSimulation, node_id: int) -> int:
	var total := 0
	for batch in simulation.get_waiting(node_id):
		total += batch.quantity.to_int_clamped()
	return total
