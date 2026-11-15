extends Node2D

# LINE v0.3 (Milestone 2: Build Your Own Network)
# Coordinates the network manager, workspace view, input controller, and HUD.
# Network rules live in NetworkManager; this script wires signals only.

var _manager := NetworkManager.new()
var _camera := WorkspaceCamera.new()
var _view: NetworkView
var _controller: WorkspaceController
var _hud: Hud


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


func _on_payout_received(amount: LargeNumber, output_id: int) -> void:
	_view.show_payout(amount, output_id)
	_hud.pulse_money()
