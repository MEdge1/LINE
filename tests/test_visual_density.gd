extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_visual_density.gd

var _failures := 0


func _init() -> void:
	_test_density_mapping_matches_the_intended_steps()
	_test_density_is_monotonic_and_bounded()
	_test_plan_respects_per_connection_and_global_caps()
	_test_larger_quantities_show_at_least_as_much_activity()
	_test_visual_density_does_not_change_totals()
	_test_repeated_frames_do_not_accumulate_visual_state()

	if _failures == 0:
		print("All visual density tests passed.")
	else:
		printerr("%d visual density assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _number(text: String) -> LargeNumber:
	var result := LargeNumber.from_int(0)
	var ten := LargeNumber.from_int(10)
	for digit in text:
		result = result.multiply(ten).add(LargeNumber.from_int(int(digit)))
	return result


# A batch halfway along its connection, so every trailing particle is on the edge.
func _batch(quantity: LargeNumber, value: LargeNumber, from_id: int, to_id: int) -> ResourceBatch:
	var batch := ResourceBatch.new(quantity, value, from_id, to_id)
	batch.progress = 0.5
	return batch


# A view wired to a simulation with one connection; batches are added by the caller.
func _view_with_connection() -> Array:
	var graph := NetworkGraph.new()
	var source := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var target := graph.add_node(NodeDefinitions.Type.OUTPUT)
	graph.connect_nodes(source, target)
	var simulation := ProductionSimulation.new(graph)
	simulation.money = LargeNumber.from_int(0)
	var view := NetworkView.new()
	view.graph = graph
	view.layout = WorkspaceLayout.new()
	view.simulation = simulation
	return [view, simulation, source, target]


func _test_density_mapping_matches_the_intended_steps() -> void:
	var expected := {"1": 1, "2": 2, "3": 2, "4": 3, "7": 3, "8": 4, "15": 4, "16": 5, "31": 5, "32": 6, "64": 7, "128": 8}
	for text in expected:
		_assert_equal(FlowDensity.representative_count(_number(text)), expected[text],
			"quantity %s maps to %d particles" % [text, expected[text]])
	_assert_equal(FlowDensity.representative_count(_number("1000000000000000000000000000000")), VisualLimits.PARTICLES_PER_BATCH_MAX,
		"enormous quantities are capped at the batch maximum")


func _test_density_is_monotonic_and_bounded() -> void:
	var previous := 0
	var monotonic := true
	var bounded := true
	for quantity in range(1, 5000):
		var count := FlowDensity.representative_count(LargeNumber.from_int(quantity))
		if count < previous:
			monotonic = false
		if count < 1 or count > VisualLimits.PARTICLES_PER_BATCH_MAX:
			bounded = false
		previous = count
	_assert_equal(monotonic, true, "more quantity never shows fewer particles")
	_assert_equal(bounded, true, "every quantity stays within 1..PARTICLES_PER_BATCH_MAX")


func _test_plan_respects_per_connection_and_global_caps() -> void:
	var parts := _view_with_connection()
	var view: NetworkView = parts[0]
	var simulation: ProductionSimulation = parts[1]
	var source: int = parts[2]
	var target: int = parts[3]
	for _i in range(300):
		simulation.in_flight.append(_batch(_number("1000"), LargeNumber.from_int(2), source, target))

	var plan := view.plan_particles()
	_assert_equal(plan.size(), VisualLimits.PARTICLES_PER_CONNECTION, "a busy connection shows exactly its cap")

	var graph: NetworkGraph = view.graph
	for _i in range(60):
		var extra := graph.add_node(NodeDefinitions.Type.GENERATOR)
		var sink := graph.add_node(NodeDefinitions.Type.OUTPUT)
		graph.connect_nodes(extra, sink)
		for _j in range(10):
			simulation.in_flight.append(_batch(_number("500"), LargeNumber.from_int(1), extra, sink))
	plan = view.plan_particles()
	_assert_equal(plan.size(), VisualLimits.PARTICLES_TOTAL, "many busy connections are bounded by the global cap")
	view.free()


func _test_larger_quantities_show_at_least_as_much_activity() -> void:
	var small_parts := _view_with_connection()
	var small_view: NetworkView = small_parts[0]
	var small_sim: ProductionSimulation = small_parts[1]
	small_sim.in_flight.append(_batch(LargeNumber.from_int(1), LargeNumber.from_int(1), small_parts[2], small_parts[3]))
	var small_count: int = small_view.plan_particles().size()
	small_view.free()

	var large_parts := _view_with_connection()
	var large_view: NetworkView = large_parts[0]
	var large_sim: ProductionSimulation = large_parts[1]
	large_sim.in_flight.append(_batch(LargeNumber.from_int(200), LargeNumber.from_int(1), large_parts[2], large_parts[3]))
	var large_count: int = large_view.plan_particles().size()
	large_view.free()

	_assert_equal(small_count, 1, "a single unit shows one understandable particle")
	_assert_equal(large_count >= small_count, true, "a large batch shows at least as much activity")
	_assert_equal(large_count > 1, true, "a large batch visibly shows more than one particle")


func _test_visual_density_does_not_change_totals() -> void:
	var parts := _view_with_connection()
	var view: NetworkView = parts[0]
	var simulation: ProductionSimulation = parts[1]
	simulation.in_flight.append(_batch(LargeNumber.from_int(4000), LargeNumber.from_int(8), parts[2], parts[3]))
	var held := simulation.get_held_units().to_text()
	var money := simulation.money.to_text()

	for _i in range(20):
		view.plan_particles()

	_assert_equal(simulation.get_held_units().to_text(), held, "planning visuals leaves held quantity unchanged")
	_assert_equal(simulation.money.to_text(), money, "planning visuals leaves money unchanged")
	view.free()


func _test_repeated_frames_do_not_accumulate_visual_state() -> void:
	var parts := _view_with_connection()
	var view: NetworkView = parts[0]
	var simulation: ProductionSimulation = parts[1]
	simulation.in_flight.append(_batch(LargeNumber.from_int(100), LargeNumber.from_int(1), parts[2], parts[3]))
	var first_size: int = view.plan_particles().size()

	for _i in range(1000):
		view.show_payout(LargeNumber.from_int(2), parts[3])
		view.flash_cell(Vector2i(0, 0))
		view._advance_effects(1.0 / 60.0)
	for _i in range(60):
		view._advance_effects(1.0 / 60.0)

	_assert_equal(view.plan_particles().size(), first_size, "repeated frames plan the same bounded particles")
	_assert_equal(view._payouts.size() <= VisualLimits.PAYOUT_INDICATORS, true, "payout indicators stay capped")
	_assert_equal(view._cell_flashes.is_empty(), true, "expired flashes are released")
	view.free()
