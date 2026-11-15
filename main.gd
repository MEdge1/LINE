extends Node2D

# LINE v0.3 (Milestone 2: Build Your Own Network)
# Coordinates the network manager, workspace view, input controller, and HUD.
# Network rules live in NetworkManager; this script wires signals only.

var _manager := NetworkManager.new()
var _camera := WorkspaceCamera.new()
var _view: NetworkView
var _controller: WorkspaceController
var _hud: Hud
var _ui_timer := 0.0

const UI_REFRESH_SECONDS := 0.1


func _ready() -> void:
	RenderingServer.set_default_clear_color(LinePalette.BACKGROUND)

	_camera.setup(get_viewport_rect().size, WorkspaceLayout.get_half_extent())

	_view = NetworkView.new()
	_view.graph = _manager.graph
	_view.layout = _manager.layout
	_view.simulation = _manager.simulation
	_view.camera = _camera
	add_child(_view)

	_controller = WorkspaceController.new()
	_controller.setup(_manager, _camera)
	add_child(_controller)

	_hud = Hud.new()
	add_child(_hud)

	_manager.payout_received.connect(_on_payout_received)
	get_viewport().size_changed.connect(func() -> void: _camera.set_viewport_size(get_viewport_rect().size))

	_controller.state_changed.connect(_refresh_ui)
	_controller.selection_changed.connect(_on_selection_changed)
	_controller.feedback.connect(_hud.show_feedback)
	_controller.invalid_cell.connect(_view.flash_cell)
	_controller.invalid_connection.connect(_view.flash_connection)

	_hud.placement_requested.connect(_controller.begin_place)
	_hud.connect_requested.connect(_controller.begin_connect)
	_hud.move_requested.connect(_controller.begin_move)
	_hud.upgrade_requested.connect(_controller.request_upgrade)
	_hud.delete_requested.connect(_controller.request_delete)
	_hud.disconnect_requested.connect(_controller.request_disconnect)
	_hud.cancel_requested.connect(_controller.cancel_mode)

	_refresh_ui()


func _process(delta: float) -> void:
	_manager.step(delta)
	_camera.advance(delta)
	# Text and telemetry do not need every frame. Player actions still refresh immediately.
	_ui_timer += delta
	if _ui_timer >= UI_REFRESH_SECONDS:
		_ui_timer = 0.0
		_refresh_ui()


func _refresh_ui() -> void:
	var placing := _controller.mode == WorkspaceController.Mode.PLACE
	var moving := _controller.mode == WorkspaceController.Mode.MOVE

	_view.selected_id = _controller.selected_id
	_view.placement_hint = placing or moving
	_view.preview_source_id = _controller.drag_source_id
	_view.preview_pointer = _controller.drag_pointer_world
	_view.preview_target_id = _controller.drag_target_id
	_view.preview_target_valid = _controller.drag_target_valid
	_hud.refresh(_manager, _controller.mode, _controller.placement_type, _controller.selected_id, _controller.delete_armed)


func _on_selection_changed(id: int) -> void:
	_refresh_ui()
	if id == 0:
		return
	# The inspector's height is only known after layout, so the correction waits two frames.
	await get_tree().process_frame
	await get_tree().process_frame
	if _controller.selected_id != id or not _manager.graph.has_node(id):
		return
	var world := _manager.layout.get_cell_center(_manager.layout.get_node_cell(id))
	_camera.reveal_node(world, _hud.workspace_band(get_viewport_rect().size))


func _on_payout_received(amount: LargeNumber, output_id: int, complexity: int) -> void:
	_view.show_payout(amount, output_id, complexity)
	_hud.pulse_money(complexity)
