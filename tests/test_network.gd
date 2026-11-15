extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_network.gd

var _failures := 0
var _controllers: Array[WorkspaceController] = []


func _init() -> void:
	_test_graph_rejects_invalid_connections()
	_test_graph_rejects_loops()
	_test_graph_limits_each_node_to_its_ports()
	_test_removing_node_removes_its_connections()
	_test_construction_spends_exact_cost()
	_test_construction_rejects_insufficient_funds_and_occupied_cells()
	_test_moving_node_keeps_logical_connections()
	_test_deleting_node_refunds_and_cleans_state()
	_test_layout_cell_centers_round_trip()
	_test_drag_from_handle_creates_valid_edge()
	_test_drag_to_invalid_target_is_rejected_and_warned()
	_test_releasing_over_empty_space_creates_no_edge()
	_test_second_pointer_cancels_drag_so_pinch_never_connects()
	_test_panning_empty_space_never_connects()
	_test_disconnect_removes_only_the_selected_edge()
	_test_reconnect_after_disconnect_succeeds()
	_test_deleting_a_node_after_disconnect_is_safe()

	for controller in _controllers:
		controller.free()

	if _failures == 0:
		print("All network tests passed.")
	else:
		printerr("%d network assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _new_manager(money: int) -> NetworkManager:
	var manager := NetworkManager.new()
	manager.simulation.money = LargeNumber.from_int(money)
	return manager


func _test_graph_rejects_invalid_connections() -> void:
	var graph := NetworkGraph.new()
	var generator := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var processor := graph.add_node(NodeDefinitions.Type.PROCESSOR)
	var output := graph.add_node(NodeDefinitions.Type.OUTPUT)

	_assert_equal(graph.connect_nodes(processor, processor), NetworkGraph.Rejection.SELF_CONNECTION,
		"a node cannot connect to itself")
	_assert_equal(graph.connect_nodes(output, processor), NetworkGraph.Rejection.SOURCE_CANNOT_SEND,
		"output cannot originate a connection")
	_assert_equal(graph.connect_nodes(processor, generator), NetworkGraph.Rejection.DESTINATION_CANNOT_RECEIVE,
		"generator cannot receive a connection")
	_assert_equal(graph.connect_nodes(generator, processor), NetworkGraph.Rejection.NONE,
		"generator -> processor is valid")
	_assert_equal(graph.connect_nodes(generator, processor), NetworkGraph.Rejection.DUPLICATE,
		"identical connection is rejected")
	_assert_equal(graph.connect_nodes(generator, output), NetworkGraph.Rejection.SOURCE_OUTPUT_FULL,
		"generator output port is limited to one")
	_assert_equal(graph.connect_nodes(99, output), NetworkGraph.Rejection.MISSING_NODE,
		"connections to unknown nodes are rejected")


func _test_graph_rejects_loops() -> void:
	var graph := NetworkGraph.new()
	var first := graph.add_node(NodeDefinitions.Type.PROCESSOR)
	var second := graph.add_node(NodeDefinitions.Type.PROCESSOR)

	_assert_equal(graph.connect_nodes(first, second), NetworkGraph.Rejection.NONE, "first processor feeds second")
	_assert_equal(graph.connect_nodes(second, first), NetworkGraph.Rejection.WOULD_CREATE_LOOP,
		"closing a loop between processors is rejected")


func _test_graph_limits_each_node_to_its_ports() -> void:
	var graph := NetworkGraph.new()
	var generator := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var processor := graph.add_node(NodeDefinitions.Type.PROCESSOR)
	var other := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var output := graph.add_node(NodeDefinitions.Type.OUTPUT)

	_assert_equal(graph.connect_nodes(generator, processor), NetworkGraph.Rejection.NONE, "first input is accepted")
	_assert_equal(graph.connect_nodes(other, processor), NetworkGraph.Rejection.DESTINATION_INPUT_FULL,
		"processor input is limited to one")
	_assert_equal(graph.connect_nodes(processor, output), NetworkGraph.Rejection.NONE, "processor -> output is valid")
	_assert_equal(graph.has_free_output(processor), false, "processor reports its output as used")


func _test_removing_node_removes_its_connections() -> void:
	var graph := NetworkGraph.new()
	var generator := graph.add_node(NodeDefinitions.Type.GENERATOR)
	var processor := graph.add_node(NodeDefinitions.Type.PROCESSOR)
	var output := graph.add_node(NodeDefinitions.Type.OUTPUT)
	graph.connect_nodes(generator, processor)
	graph.connect_nodes(processor, output)

	graph.remove_node(processor)

	_assert_equal(graph.get_connections().size(), 0, "deleting a node removes all its connections")
	_assert_equal(graph.get_incoming(output).size(), 0, "no dangling incoming reference remains")
	_assert_equal(graph.get_outgoing(generator).size(), 0, "no dangling outgoing reference remains")


func _test_construction_spends_exact_cost() -> void:
	var manager := _new_manager(100)

	var result := manager.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(0, 0))

	_assert_equal(result, NetworkManager.PlacementResult.OK, "affordable node is placed")
	_assert_equal(manager.simulation.money.compare(LargeNumber.from_int(100 - NodeDefinitions.get_cost(NodeDefinitions.Type.PROCESSOR))), 0,
		"construction spends the node's cost")
	_assert_equal(manager.layout.get_node_at(Vector2i(0, 0)) != 0, true, "node occupies its cell")


func _test_construction_rejects_insufficient_funds_and_occupied_cells() -> void:
	var manager := _new_manager(0)

	_assert_equal(manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(1, 1)),
		NetworkManager.PlacementResult.INSUFFICIENT_FUNDS, "insufficient funds prevents construction")
	_assert_equal(manager.graph.get_node_ids().size(), 0, "no node is created without funds")

	manager.simulation.money = LargeNumber.from_int(200)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(1, 1))
	_assert_equal(manager.construct(NodeDefinitions.Type.OUTPUT, Vector2i(1, 1)),
		NetworkManager.PlacementResult.CELL_OCCUPIED, "a cell cannot hold two nodes")
	_assert_equal(manager.construct(NodeDefinitions.Type.OUTPUT, Vector2i(99, 99)),
		NetworkManager.PlacementResult.OUT_OF_BOUNDS, "placement outside the grid is rejected")


func _test_moving_node_keeps_logical_connections() -> void:
	var manager := _new_manager(200)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(0, 0))
	manager.construct(NodeDefinitions.Type.OUTPUT, Vector2i(0, 1))
	var generator := manager.layout.get_node_at(Vector2i(0, 0))
	var output := manager.layout.get_node_at(Vector2i(0, 1))
	manager.connect_nodes(generator, output)

	var result := manager.move_node(generator, Vector2i(4, 4))

	_assert_equal(result, NetworkManager.PlacementResult.OK, "node moves to a free cell")
	_assert_equal(manager.layout.get_node_cell(generator), Vector2i(4, 4), "layout records the new cell")
	_assert_equal(manager.graph.get_connections(), [Vector2i(generator, output)],
		"moving a node keeps its logical connections")
	_assert_equal(manager.move_node(generator, Vector2i(0, 1)), NetworkManager.PlacementResult.CELL_OCCUPIED,
		"moving onto another node is rejected")


func _test_deleting_node_refunds_and_cleans_state() -> void:
	var manager := _new_manager(200)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(0, 0))
	manager.construct(NodeDefinitions.Type.OUTPUT, Vector2i(0, 1))
	var generator := manager.layout.get_node_at(Vector2i(0, 0))
	var output := manager.layout.get_node_at(Vector2i(0, 1))
	manager.connect_nodes(generator, output)
	var money_before := manager.simulation.money

	var refund := manager.delete_node(generator)
	var expected_refund := LargeNumber.from_int(NodeDefinitions.get_cost(NodeDefinitions.Type.GENERATOR))

	_assert_equal(refund.compare(expected_refund), 0, "delete refunds the build cost")
	_assert_equal(manager.simulation.money.compare(money_before.add(refund)), 0, "refund is added to money")
	_assert_equal(manager.graph.get_connections().size(), 0, "deleting a node removes its connections")
	_assert_equal(manager.layout.get_node_at(Vector2i(0, 0)), 0, "deleted node frees its cell")
	_assert_equal(manager.graph.has_node(output), true, "connected neighbours survive deletion")


func _test_layout_cell_centers_round_trip() -> void:
	var layout := WorkspaceLayout.new()
	var mismatches := 0
	for column in range(WorkspaceLayout.COLUMNS):
		for row in range(WorkspaceLayout.ROWS):
			var cell := Vector2i(column, row)
			if layout.get_cell_at_world(layout.get_cell_center(cell)) != cell:
				mismatches += 1

	_assert_equal(mismatches, 0, "every cell centre maps back to its own cell")


# Drag-connection tests drive the controller's real press, drag, and release handlers.
func _controller_for(manager: NetworkManager) -> Array:
	var camera := WorkspaceCamera.new()
	camera.setup(Vector2(720.0, 1280.0), WorkspaceLayout.get_half_extent())
	var controller := WorkspaceController.new()
	controller.setup(manager, camera)
	_controllers.append(controller)
	return [controller, camera]


func _screen_of_cell(camera: WorkspaceCamera, manager: NetworkManager, cell: Vector2i) -> Vector2:
	return camera.world_to_screen(manager.layout.get_cell_center(cell))


func _screen_of_handle(camera: WorkspaceCamera, manager: NetworkManager, cell: Vector2i) -> Vector2:
	return camera.world_to_screen(manager.layout.get_cell_center(cell) + Vector2(WorkspaceController.OUTPUT_HANDLE_OFFSET, 0.0))


func _test_drag_from_handle_creates_valid_edge() -> void:
	var manager := _new_manager(200)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(2, 6))
	manager.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(2, 5))
	var generator := manager.layout.get_node_at(Vector2i(2, 6))
	var processor := manager.layout.get_node_at(Vector2i(2, 5))
	var parts := _controller_for(manager)
	var controller: WorkspaceController = parts[0]
	var camera: WorkspaceCamera = parts[1]
	controller.selected_id = generator

	controller._press(WorkspaceController.MOUSE_POINTER, _screen_of_handle(camera, manager, Vector2i(2, 6)))
	_assert_equal(controller.drag_source_id, generator, "pressing the output handle starts a connection drag")
	controller._drag(WorkspaceController.MOUSE_POINTER, _screen_of_cell(camera, manager, Vector2i(2, 5)), Vector2.ZERO)
	_assert_equal(controller.drag_target_valid, true, "hovering a valid destination marks it valid")
	controller._release(WorkspaceController.MOUSE_POINTER, _screen_of_cell(camera, manager, Vector2i(2, 5)))

	_assert_equal(manager.graph.get_connections(), [Vector2i(generator, processor)],
		"releasing over a valid destination creates the edge")
	_assert_equal(controller.drag_source_id, 0, "drag state is cleared after release")


func _test_drag_to_invalid_target_is_rejected_and_warned() -> void:
	var manager := _new_manager(200)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(2, 6))
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(3, 6))
	var generator := manager.layout.get_node_at(Vector2i(2, 6))
	var other_generator := manager.layout.get_node_at(Vector2i(3, 6))
	var parts := _controller_for(manager)
	var controller: WorkspaceController = parts[0]
	var camera: WorkspaceCamera = parts[1]
	var warnings: Array[int] = []
	controller.invalid_connection.connect(func(_from: int, _to: int) -> void: warnings.append(1))
	controller.selected_id = generator

	controller._press(WorkspaceController.MOUSE_POINTER, _screen_of_handle(camera, manager, Vector2i(2, 6)))
	controller._drag(WorkspaceController.MOUSE_POINTER, _screen_of_cell(camera, manager, Vector2i(3, 6)), Vector2.ZERO)
	_assert_equal(controller.drag_target_valid, false, "hovering an invalid destination marks it invalid")
	controller._release(WorkspaceController.MOUSE_POINTER, _screen_of_cell(camera, manager, Vector2i(3, 6)))

	_assert_equal(manager.graph.get_connections().size(), 0, "an invalid drag creates no edge")
	_assert_equal(warnings.size(), 1, "an invalid drag raises the explanatory warning")
	_assert_equal(manager.graph.has_node(other_generator), true, "the rejected target is untouched")


func _test_releasing_over_empty_space_creates_no_edge() -> void:
	var manager := _new_manager(200)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(2, 6))
	var generator := manager.layout.get_node_at(Vector2i(2, 6))
	var parts := _controller_for(manager)
	var controller: WorkspaceController = parts[0]
	var camera: WorkspaceCamera = parts[1]
	controller.selected_id = generator

	controller._press(WorkspaceController.MOUSE_POINTER, _screen_of_handle(camera, manager, Vector2i(2, 6)))
	controller._drag(WorkspaceController.MOUSE_POINTER, _screen_of_cell(camera, manager, Vector2i(0, 0)), Vector2.ZERO)
	controller._release(WorkspaceController.MOUSE_POINTER, _screen_of_cell(camera, manager, Vector2i(0, 0)))

	_assert_equal(manager.graph.get_connections().size(), 0, "releasing over empty space cancels the drag")
	_assert_equal(controller.drag_source_id, 0, "cancelled drag clears its state")


func _test_second_pointer_cancels_drag_so_pinch_never_connects() -> void:
	var manager := _new_manager(200)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(2, 6))
	manager.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(2, 5))
	var generator := manager.layout.get_node_at(Vector2i(2, 6))
	var parts := _controller_for(manager)
	var controller: WorkspaceController = parts[0]
	var camera: WorkspaceCamera = parts[1]
	controller.selected_id = generator

	controller._press(0, _screen_of_handle(camera, manager, Vector2i(2, 6)))
	controller._press(1, _screen_of_cell(camera, manager, Vector2i(0, 0)))
	controller._drag(0, _screen_of_cell(camera, manager, Vector2i(2, 5)), Vector2.ZERO)
	controller._release(0, _screen_of_cell(camera, manager, Vector2i(2, 5)))
	controller._release(1, _screen_of_cell(camera, manager, Vector2i(0, 0)))

	_assert_equal(manager.graph.get_connections().size(), 0, "a second finger cancels the drag, so pinch never connects")


func _test_panning_empty_space_never_connects() -> void:
	var manager := _new_manager(200)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(2, 6))
	manager.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(2, 5))
	var parts := _controller_for(manager)
	var controller: WorkspaceController = parts[0]
	var camera: WorkspaceCamera = parts[1]
	var offset_before := camera.offset

	controller._press(WorkspaceController.MOUSE_POINTER, _screen_of_cell(camera, manager, Vector2i(0, 0)))
	controller._drag(WorkspaceController.MOUSE_POINTER, _screen_of_cell(camera, manager, Vector2i(0, 0)) + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
	controller._release(WorkspaceController.MOUSE_POINTER, _screen_of_cell(camera, manager, Vector2i(0, 0)) + Vector2(60.0, 0.0))

	_assert_equal(manager.graph.get_connections().size(), 0, "panning empty space creates no connection")
	_assert_equal(camera.offset != offset_before, true, "dragging empty space pans the camera")


func _test_disconnect_removes_only_the_selected_edge() -> void:
	var manager := _new_manager(500)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(0, 0))
	manager.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(0, 1))
	manager.construct(NodeDefinitions.Type.OUTPUT, Vector2i(0, 2))
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(4, 0))
	manager.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(4, 1))
	var generator := manager.layout.get_node_at(Vector2i(0, 0))
	var processor := manager.layout.get_node_at(Vector2i(0, 1))
	var output := manager.layout.get_node_at(Vector2i(0, 2))
	var other_generator := manager.layout.get_node_at(Vector2i(4, 0))
	var other_processor := manager.layout.get_node_at(Vector2i(4, 1))
	manager.connect_nodes(generator, processor)
	manager.connect_nodes(processor, output)
	manager.connect_nodes(other_generator, other_processor)

	var returned = manager.disconnect_nodes(processor, output)

	_assert_equal(returned != null, true, "disconnecting an existing edge succeeds")
	_assert_equal(manager.graph.get_connections(),
		[Vector2i(generator, processor), Vector2i(other_generator, other_processor)],
		"only the selected edge is removed; unrelated edges remain")
	_assert_equal(manager.graph.has_node(processor) and manager.graph.has_node(output), true,
		"both nodes remain after disconnecting")
	_assert_equal(manager.layout.get_node_at(Vector2i(0, 2)), output, "nodes keep their grid cells")
	_assert_equal(manager.graph.get_incoming(output).size(), 0, "no dangling incoming reference on the old target")
	_assert_equal(manager.graph.get_outgoing(processor).size(), 0, "no dangling outgoing reference on the source")
	_assert_equal(manager.disconnect_nodes(processor, output) == null, true, "disconnecting twice is refused safely")


func _test_reconnect_after_disconnect_succeeds() -> void:
	var manager := _new_manager(500)
	manager.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(1, 1))
	manager.construct(NodeDefinitions.Type.OUTPUT, Vector2i(1, 2))
	var processor := manager.layout.get_node_at(Vector2i(1, 1))
	var output := manager.layout.get_node_at(Vector2i(1, 2))
	manager.connect_nodes(processor, output)
	manager.disconnect_nodes(processor, output)

	_assert_equal(manager.connect_nodes(processor, output), NetworkGraph.Rejection.NONE,
		"both nodes can be reconnected after a disconnect")
	_assert_equal(manager.graph.get_connections(), [Vector2i(processor, output)], "reconnected edge is present once")


func _test_deleting_a_node_after_disconnect_is_safe() -> void:
	var manager := _new_manager(500)
	manager.construct(NodeDefinitions.Type.GENERATOR, Vector2i(2, 0))
	manager.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(2, 1))
	var generator := manager.layout.get_node_at(Vector2i(2, 0))
	var processor := manager.layout.get_node_at(Vector2i(2, 1))
	manager.connect_nodes(generator, processor)
	manager.disconnect_nodes(generator, processor)

	var refund := manager.delete_node(processor)

	_assert_equal(refund.is_zero(), false, "deleting a disconnected node still refunds it")
	_assert_equal(manager.graph.get_connections().size(), 0, "no connections remain after deletion")
	_assert_equal(manager.graph.get_outgoing(generator).size(), 0, "the surviving node holds no stale reference")
