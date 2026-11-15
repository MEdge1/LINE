extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_complexity.gd

const STEP := 0.05

var _failures := 0


func _init() -> void:
	_test_processing_modifier_is_monotonic_and_bounded()
	_test_booster_and_complexity_multiply_processor_capacity()
	_test_generator_creates_complexity_zero()
	_test_processor_doubles_value_and_adds_one_complexity()
	_test_chain_steps_each_processor_exactly_once()
	_test_splitter_preserves_complexity()
	_test_merger_keeps_different_complexity_separate()
	_test_output_pays_value_regardless_of_complexity()
	_test_move_does_not_alter_complexity()
	_test_delete_keeps_conservation_with_complex_queues()
	_test_depth_forty_three_stays_exact()
	_test_mixed_complexity_network_conserves_through_edits()

	if _failures == 0:
		print("All complexity tests passed.")
	else:
		printerr("%d complexity assertion(s) failed." % _failures)

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


func _conservation_holds(simulation: ProductionSimulation) -> bool:
	var accounted := simulation.paid_units.add(simulation.get_held_units()).add(simulation.lost_units)
	return accounted.compare(simulation.produced_units) == 0


func _run(manager: NetworkManager, seconds: float) -> void:
	for _i in range(int(seconds / STEP)):
		manager.step(STEP)


# Each payout as [amount text, complexity], in arrival order.
func _log_payouts(simulation: ProductionSimulation) -> Array:
	var log: Array = []
	simulation.payout_received.connect(func(amount: LargeNumber, _output_id: int, complexity: int) -> void:
		log.append([amount.to_text(), complexity]))
	return log


func _test_processing_modifier_is_monotonic_and_bounded() -> void:
	_assert_equal(ComplexityModel.processing_modifier(0), 1.0, "complexity 0 has the baseline modifier")
	var previous := 2.0
	var valid := true
	for complexity in range(0, 61):
		var modifier := ComplexityModel.processing_modifier(complexity)
		if modifier <= 0.0 or is_nan(modifier) or is_inf(modifier) or modifier > previous:
			valid = false
		previous = modifier
	_assert_equal(valid, true, "the modifier is positive, finite, and never increases with complexity")
	_assert_equal(ComplexityModel.processing_modifier(-3), 1.0, "negative complexity is treated as the baseline")


func _test_booster_and_complexity_multiply_processor_capacity() -> void:
	var manager := _manager()
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 0))
	manager.graph.get_node(processor).boosted = true
	manager.simulation.seed_queue(processor, LargeNumber.from_int(1), LargeNumber.from_int(1), false, 2)

	var base := NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR)
	var expected := base * (1.0 + LineBalance.BOOSTER_BONUS) * ComplexityModel.processing_modifier(2)
	_assert_equal(absf(manager.simulation.get_effective_capacity(processor) - expected) < 0.000001, true,
		"effective capacity is base x booster x complexity modifier")
	_assert_equal(manager.simulation.get_incoming_complexity(processor), 2, "the queued head sets the incoming complexity")


func _test_generator_creates_complexity_zero() -> void:
	var manager := _manager()
	var generator := _place(manager, NodeDefinitions.Type.GENERATOR, Vector2i(0, 0))
	manager.graph.get_node(generator).level = 15
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 1))
	manager.connect_nodes(generator, output)
	var log := _log_payouts(manager.simulation)

	_run(manager, 10.0)
	_assert_equal(log.is_empty(), false, "a generator's output is paid")
	var all_zero := true
	for entry in log:
		if entry[1] != 0:
			all_zero = false
	_assert_equal(all_zero, true, "generated resources arrive with complexity 0")
	_assert_equal(manager.simulation.get_last_payout_complexity(output), 0, "the output reports complexity 0")


func _test_processor_doubles_value_and_adds_one_complexity() -> void:
	var manager := _manager()
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 0))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 1))
	manager.connect_nodes(processor, output)
	manager.simulation.seed_queue(processor, LargeNumber.from_int(1), LargeNumber.from_int(1), false, 0)
	var log := _log_payouts(manager.simulation)

	_run(manager, 10.0)
	_assert_equal(log, [["2", 1]], "one Processor pays value x2 at complexity +1, exactly once")


func _test_chain_steps_each_processor_exactly_once() -> void:
	var manager := _manager()
	var first := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 0))
	var second := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 1))
	var third := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 2))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 3))
	manager.connect_nodes(first, second)
	manager.connect_nodes(second, third)
	manager.connect_nodes(third, output)
	manager.simulation.seed_queue(first, LargeNumber.from_int(1), LargeNumber.from_int(1), false, 0)
	var log := _log_payouts(manager.simulation)

	_run(manager, 30.0)
	_assert_equal(log, [["8", 3]], "three Processors give value 8 at complexity 3 with no double-processing")
	_assert_equal(_conservation_holds(manager.simulation), true, "the chain conserves its single unit")


func _test_splitter_preserves_complexity() -> void:
	var manager := _manager()
	var splitter := _place(manager, NodeDefinitions.Type.SPLITTER, Vector2i(0, 0))
	var left := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 1))
	var right := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 2))
	manager.connect_nodes(splitter, left)
	manager.connect_nodes(splitter, right)
	manager.simulation.seed_queue(splitter, LargeNumber.from_int(6), LargeNumber.from_int(1), false, 4)
	var log := _log_payouts(manager.simulation)

	_run(manager, 20.0)
	var total := 0
	var preserved := true
	for entry in log:
		total += int(entry[0])
		if entry[1] != 4:
			preserved = false
	_assert_equal(preserved, true, "a splitter passes complexity 4 unchanged to both branches")
	_assert_equal(total, 6, "a splitter divides the quantity without loss")


func _test_merger_keeps_different_complexity_separate() -> void:
	var manager := _manager()
	var merger := _place(manager, NodeDefinitions.Type.MERGER, Vector2i(0, 0))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 1))
	manager.connect_nodes(merger, output)
	var simulation := manager.simulation
	simulation.seed_queue(merger, LargeNumber.from_int(2), LargeNumber.from_int(1), false, 2)
	simulation.seed_queue(merger, LargeNumber.from_int(3), LargeNumber.from_int(1), false, 3)
	_assert_equal(simulation.get_waiting(merger).size(), 2, "batches of different complexity stay separate in a queue")

	simulation.seed_queue(merger, LargeNumber.from_int(1), LargeNumber.from_int(1), false, 3)
	_assert_equal(simulation.get_waiting(merger).size(), 2, "compatible batches merge in a queue")
	_assert_equal(simulation.get_waiting(merger)[1].quantity.to_text(), "4", "the merged batch keeps the combined quantity")

	var log := _log_payouts(simulation)
	_run(manager, 20.0)
	var complexities: Array = []
	for entry in log:
		if not complexities.has(entry[1]):
			complexities.append(entry[1])
	complexities.sort()
	_assert_equal(complexities, [2, 3], "a merger routes each complexity without mixing them")
	_assert_equal(_conservation_holds(simulation), true, "merging conserves every unit")


func _test_output_pays_value_regardless_of_complexity() -> void:
	var manager := _manager()
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 0))
	var log := _log_payouts(manager.simulation)
	manager.simulation.seed_queue(output, LargeNumber.from_int(3), LargeNumber.from_int(128), true, 7)

	_run(manager, 2.0)
	var total := 0
	var all_complex := true
	for entry in log:
		total += int(entry[0])
		if entry[1] != 7:
			all_complex = false
	_assert_equal(total, 384, "payout is quantity x value, summed across however many steps it takes")
	_assert_equal(all_complex, true, "every payout reports the batch's complexity")
	_assert_equal(manager.simulation.get_last_payout_complexity(output), 7, "the output reports the payout complexity")


func _test_move_does_not_alter_complexity() -> void:
	var manager := _manager()
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 0))
	manager.simulation.seed_queue(processor, LargeNumber.from_int(5), LargeNumber.from_int(8), false, 3)

	manager.move_node(processor, Vector2i(4, 4))
	var queued: ResourceBatch = manager.simulation.get_waiting(processor)[0]
	_assert_equal(queued.complexity, 3, "moving a node keeps its queued complexity")
	_assert_equal(queued.value_per_unit.to_text(), "8", "moving a node keeps its queued value")


func _test_delete_keeps_conservation_with_complex_queues() -> void:
	var manager := _manager()
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, 0))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, 1))
	manager.connect_nodes(processor, output)
	manager.simulation.seed_queue(processor, LargeNumber.from_int(4), LargeNumber.from_int(16), false, 4)
	_run(manager, 3.0)

	manager.delete_node(processor)
	_assert_equal(_conservation_holds(manager.simulation), true, "deleting a complex queue records its quantity as lost")


# Depth 43 is the longest chain the grid holds. Its exact payout must still be 2^43.
func _test_depth_forty_three_stays_exact() -> void:
	var manager := _manager()
	var cells := StrategyScenarios.all_cells()
	var previous := 0
	for index in range(43):
		var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, cells[index])
		if previous != 0:
			manager.connect_nodes(previous, processor)
		previous = processor
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, cells[43])
	manager.connect_nodes(previous, output)
	var first := manager.layout.get_node_at(cells[0])
	var simulation := manager.simulation
	simulation.seed_queue(first, LargeNumber.from_int(1), LargeNumber.from_int(1), false, 0)
	var log := _log_payouts(simulation)

	_run(manager, 200.0)
	_assert_equal(log.size(), 1, "one unit travels the whole chain and pays once")
	if not log.is_empty():
		_assert_equal(log[0], ["8796093022208", 43], "depth 43 pays exactly 2^43 at complexity 43")


func _test_mixed_complexity_network_conserves_through_edits() -> void:
	var manager := _manager()
	var generator := _place(manager, NodeDefinitions.Type.GENERATOR, Vector2i(0, 0))
	manager.graph.get_node(generator).level = 15
	var splitter := _place(manager, NodeDefinitions.Type.SPLITTER, Vector2i(0, 1))
	var first := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 1))
	var second := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(2, 1))
	var side := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 2))
	var merger := _place(manager, NodeDefinitions.Type.MERGER, Vector2i(3, 1))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(4, 1))
	manager.connect_nodes(generator, splitter)
	manager.connect_nodes(splitter, first)
	manager.connect_nodes(first, second)
	manager.connect_nodes(second, merger)
	manager.connect_nodes(splitter, side)
	manager.connect_nodes(side, merger)
	manager.connect_nodes(merger, output)

	var simulation := manager.simulation
	var conserved := true
	for second_index in range(60):
		_run(manager, 1.0)
		if second_index == 10:
			manager.disconnect_nodes(splitter, first)
		if second_index == 15:
			manager.connect_nodes(splitter, first)
		if second_index == 25:
			manager.delete_node(side)
		if not _conservation_holds(simulation):
			conserved = false
	_assert_equal(conserved, true, "mixed-complexity edits conserve produced = paid + held + lost every second")
	_assert_equal(simulation.get_last_payout_complexity(output) >= 1, true, "deeper branches produce higher-complexity payouts")
