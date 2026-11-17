class_name WorkspaceController
extends Node

# Turns touch and mouse gestures into workspace actions. Owns the interaction mode,
# selection, and the drag-to-connect preview. Network changes go through NetworkManager.

signal state_changed
signal feedback(message: String, is_error: bool)
signal invalid_cell(cell: Vector2i)
signal invalid_connection(from_id: int, to_id: int)
signal selection_changed(id: int)

enum Mode { IDLE, PLACE, CONNECT, MOVE }

# A pointer that moves less than this (screen pixels) before release counts as a tap.
const TAP_MAX_DRAG := 14.0
const ZOOM_STEP := 1.1
const MOUSE_POINTER := -1
const NO_POINTER := -99
# Output handle position relative to a node centre, and how close a press must land (world units).
const OUTPUT_HANDLE_OFFSET := 58.0
const HANDLE_HIT_RADIUS := 44.0

var mode: int = Mode.IDLE
var input_enabled := true
var placement_type: int = -1
var selected_id: int = 0
var delete_armed: bool = false

# Drag-to-connect preview. Read by the workspace view each frame.
var drag_source_id: int = 0
var drag_pointer_world := Vector2.ZERO
var drag_target_id: int = 0
var drag_target_valid: bool = false

var _manager: NetworkManager
var _camera: WorkspaceCamera
var _pointers: Dictionary = {}
var _primary_pointer: int = NO_POINTER
var _press_origin := Vector2.ZERO
var _gesture_moved: bool = false
var _pinch_distance: float = 0.0
var _pinch_midpoint := Vector2.ZERO


func setup(manager: NetworkManager, camera: WorkspaceCamera) -> void:
	_manager = manager
	_camera = camera


# Panels that cover the workspace turn workspace input off. Any gesture in progress is dropped.
func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		_pointers.clear()
		_primary_pointer = NO_POINTER
		_gesture_moved = false
		_cancel_drag_connection()


func begin_place(type: int) -> void:
	if not _manager.progression.is_type_unlocked(type):
		feedback.emit("Unlock %s in PROGRESS first" % NodeDefinitions.get_display_name(type), true)
		return
	if not _manager.can_afford(type):
		feedback.emit("Need $%d for %s" % [NodeDefinitions.get_cost(type), NodeDefinitions.get_display_name(type)], true)
		return

	mode = Mode.PLACE
	placement_type = type
	_select(0)
	feedback.emit("Tap an empty cell to place %s" % NodeDefinitions.get_display_name(type), false)
	state_changed.emit()


func begin_connect() -> void:
	if selected_id == 0:
		return
	if not _manager.has_free_output(selected_id):
		feedback.emit("This node has no free output", true)
		return

	mode = Mode.CONNECT
	feedback.emit("Tap the node to connect to, or drag from the handle", false)
	state_changed.emit()


func begin_move() -> void:
	if selected_id == 0:
		return

	mode = Mode.MOVE
	feedback.emit("Tap an empty cell to move the node", false)
	state_changed.emit()


func reset_session_state() -> void:
	mode = Mode.IDLE
	placement_type = -1
	selected_id = 0
	delete_armed = false
	_clear_drag_connection()
	state_changed.emit()


func cancel_mode() -> void:
	mode = Mode.IDLE
	placement_type = -1
	state_changed.emit()


func request_upgrade() -> void:
	if selected_id == 0 or not _manager.is_generator(selected_id):
		return

	if _manager.is_at_max_level(selected_id):
		feedback.emit("Generator is at MAX LEVEL", true)
	elif _manager.upgrade_node(selected_id):
		var level := _manager.graph.get_node(selected_id).level
		feedback.emit("Generator upgraded to Level %d" % level, false)
	else:
		feedback.emit("Need %s to upgrade" % NumberFormat.money(_manager.get_upgrade_cost(selected_id)), true)
	state_changed.emit()


func request_disconnect(from_id: int, to_id: int) -> void:
	var returned := _manager.disconnect_nodes(from_id, to_id)
	if returned == null:
		feedback.emit("That connection no longer exists", true)
	elif returned.is_zero():
		feedback.emit("Disconnected", false)
	else:
		feedback.emit("Disconnected · %s returned to the source" % NumberFormat.compact(returned), false)
	state_changed.emit()


# Deleting needs a second tap so one stray tap cannot remove a node.
func request_delete() -> void:
	if selected_id == 0:
		return

	if not delete_armed:
		delete_armed = true
		feedback.emit("Tap DELETE again to confirm", false)
		state_changed.emit()
		return

	var refund := _manager.delete_node(selected_id)
	feedback.emit("Node deleted. Refunded %s" % NumberFormat.money(refund), false)
	mode = Mode.IDLE
	_select(0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position)
		else:
			_release(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_drag(drag.index, drag.position, drag.relative)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _pointers.has(MOUSE_POINTER):
		var motion := event as InputEventMouseMotion
		_drag(MOUSE_POINTER, motion.position, motion.relative)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_release(MOUSE_POINTER, event.position)
		return

	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom_at(event.position, ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom_at(event.position, 1.0 / ZOOM_STEP)
		MOUSE_BUTTON_LEFT:
			_press(MOUSE_POINTER, event.position)


func _press(pointer: int, position: Vector2) -> void:
	# Any new touch is the player taking control, so an automatic reveal must not fight it.
	_camera.cancel_reveal()
	_pointers[pointer] = position

	if _pointers.size() == 1:
		_primary_pointer = pointer
		_press_origin = position
		_gesture_moved = false
		if mode == Mode.IDLE and _is_on_output_handle(position):
			_begin_drag_connection(position)
	else:
		# A second pointer means pinch, which must never connect or tap.
		if drag_source_id != 0:
			_cancel_drag_connection()
		_gesture_moved = true
		_pinch_distance = _pointer_distance()
		_pinch_midpoint = _pointer_midpoint()


func _drag(pointer: int, position: Vector2, relative: Vector2) -> void:
	if not _pointers.has(pointer):
		return

	_pointers[pointer] = position

	if drag_source_id != 0:
		if pointer == _primary_pointer and _pointers.size() == 1:
			drag_pointer_world = _camera.screen_to_world(position)
			_update_drag_target()
		return

	if _pointers.size() == 1:
		if not _gesture_moved and position.distance_to(_press_origin) > TAP_MAX_DRAG:
			_gesture_moved = true
		if _gesture_moved:
			_camera.pan(relative)
	else:
		var distance := _pointer_distance()
		var midpoint := _pointer_midpoint()
		if _pinch_distance > 0.0 and distance > 0.0:
			_camera.zoom_at(midpoint, distance / _pinch_distance)
		_camera.pan(midpoint - _pinch_midpoint)
		_pinch_distance = distance
		_pinch_midpoint = midpoint


func _release(pointer: int, position: Vector2) -> void:
	if not _pointers.has(pointer):
		return

	var was_alone := _pointers.size() == 1
	_pointers.erase(pointer)

	if drag_source_id != 0 and was_alone and pointer == _primary_pointer:
		_finish_drag_connection()
		return

	if was_alone and pointer == _primary_pointer and not _gesture_moved:
		_handle_tap(position)


func _is_on_output_handle(screen_position: Vector2) -> bool:
	if selected_id == 0 or not _manager.has_free_output(selected_id):
		return false

	var handle := _handle_world_position(selected_id)
	return _camera.screen_to_world(screen_position).distance_to(handle) <= HANDLE_HIT_RADIUS


func _handle_world_position(id: int) -> Vector2:
	var layout := _manager.layout
	return layout.get_cell_center(layout.get_node_cell(id)) + Vector2(OUTPUT_HANDLE_OFFSET, 0.0)


func _begin_drag_connection(screen_position: Vector2) -> void:
	drag_source_id = selected_id
	drag_pointer_world = _camera.screen_to_world(screen_position)
	_gesture_moved = true
	_update_drag_target()


func _update_drag_target() -> void:
	var layout := _manager.layout
	var cell := layout.get_cell_at_world(drag_pointer_world)
	var target := layout.get_node_at(cell) if layout.contains_cell(cell) else 0

	drag_target_id = target
	drag_target_valid = target != 0 and target != drag_source_id \
		and _manager.graph.validate_connection(drag_source_id, target) == NetworkGraph.Rejection.NONE


# Releasing over empty space or the source itself cancels silently. Releasing over any
# other node attempts the connection and explains a rejection.
func _finish_drag_connection() -> void:
	var source := drag_source_id
	var target := drag_target_id
	_clear_drag_connection()

	if target != 0 and target != source:
		var rejection := _manager.connect_nodes(source, target)
		if rejection == NetworkGraph.Rejection.NONE:
			feedback.emit("Connected", false)
		else:
			invalid_connection.emit(source, target)
			feedback.emit(_connection_message(rejection), true)
	state_changed.emit()


func _cancel_drag_connection() -> void:
	_clear_drag_connection()
	state_changed.emit()


func _clear_drag_connection() -> void:
	drag_source_id = 0
	drag_target_id = 0
	drag_target_valid = false


func _pointer_distance() -> float:
	var keys := _pointers.keys()
	if keys.size() < 2:
		return 0.0
	return _pointers[keys[0]].distance_to(_pointers[keys[1]])


func _pointer_midpoint() -> Vector2:
	var sum := Vector2.ZERO
	for position in _pointers.values():
		sum += position
	return sum / float(_pointers.size())


func _handle_tap(screen_position: Vector2) -> void:
	var cell := _manager.layout.get_cell_at_world(_camera.screen_to_world(screen_position))

	if not _manager.layout.contains_cell(cell):
		if mode == Mode.IDLE:
			_select(0)
		else:
			cancel_mode()
		return

	match mode:
		Mode.PLACE:
			_try_place(cell)
		Mode.MOVE:
			_try_move(cell)
		Mode.CONNECT:
			_try_connect(cell)
		_:
			_select(_manager.layout.get_node_at(cell))


func _try_place(cell: Vector2i) -> void:
	var result := _manager.construct(placement_type, cell)
	if result == NetworkManager.PlacementResult.OK:
		feedback.emit("%s placed" % NodeDefinitions.get_display_name(placement_type), false)
	else:
		invalid_cell.emit(cell)
		feedback.emit(_placement_message(result), true)
	state_changed.emit()


func _try_move(cell: Vector2i) -> void:
	var result := _manager.move_node(selected_id, cell)
	if result == NetworkManager.PlacementResult.OK:
		mode = Mode.IDLE
		feedback.emit("Node moved", false)
	else:
		invalid_cell.emit(cell)
		feedback.emit(_placement_message(result), true)
	state_changed.emit()


func _try_connect(cell: Vector2i) -> void:
	var target := _manager.layout.get_node_at(cell)
	if target == 0:
		cancel_mode()
		return

	var rejection := _manager.connect_nodes(selected_id, target)
	if rejection == NetworkGraph.Rejection.NONE:
		mode = Mode.IDLE
		feedback.emit("Connected", false)
	else:
		invalid_connection.emit(selected_id, target)
		feedback.emit(_connection_message(rejection), true)
	state_changed.emit()


func _select(id: int) -> void:
	selected_id = id
	delete_armed = false
	selection_changed.emit(id)
	state_changed.emit()


func _placement_message(result: NetworkManager.PlacementResult) -> String:
	match result:
		NetworkManager.PlacementResult.OUT_OF_BOUNDS:
			return "Outside the grid"
		NetworkManager.PlacementResult.CELL_LOCKED:
			return "That area is still locked. Buy space in PROGRESS"
		NetworkManager.PlacementResult.TECHNOLOGY_LOCKED:
			return "Unlock this technology in PROGRESS first"
		NetworkManager.PlacementResult.CELL_OCCUPIED:
			return "That cell is occupied"
		NetworkManager.PlacementResult.INSUFFICIENT_FUNDS:
			return "Not enough money"
		_:
			return "That node no longer exists"


func _connection_message(rejection: NetworkGraph.Rejection) -> String:
	match rejection:
		NetworkGraph.Rejection.SELF_CONNECTION:
			return "A node cannot connect to itself"
		NetworkGraph.Rejection.DUPLICATE:
			return "Already connected"
		NetworkGraph.Rejection.SOURCE_CANNOT_SEND:
			return "This node cannot send resources"
		NetworkGraph.Rejection.SOURCE_OUTPUT_FULL:
			return "That output is already in use"
		NetworkGraph.Rejection.DESTINATION_CANNOT_RECEIVE:
			return "This node cannot receive resources"
		NetworkGraph.Rejection.DESTINATION_INPUT_FULL:
			return "That input is already in use"
		NetworkGraph.Rejection.WOULD_CREATE_LOOP:
			return "That connection would create a loop"
		NetworkGraph.Rejection.BOOSTER_NOT_CONNECTABLE:
			return "Boosters boost neighbours; they carry no resources"
		_:
			return "That node no longer exists"
