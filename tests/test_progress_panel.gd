extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_progress_panel.gd
# Drives the real main scene with touch and mouse events. Checks scrolling, tap-versus-drag
# behaviour, workspace isolation while the sheet is open, the expansion purchase, reset safety,
# and that the close control stays reachable.

const TEST_PATH := "user://test_progress_panel.json"
const LIMIT_STAGE := 40

var _main
var _stage := 0
var _elapsed := 0.0
var _until := 0.0
var _failures := 0
var _money_before := ""
var _offset_before := Vector2.ZERO
var _zoom_before := 1.0
var _rp_before := 0


func _init() -> void:
	SaveManager.path = TEST_PATH
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 600.0:
		printerr("FAIL: the test did not finish within its time limit (stage %d)" % _stage)
		quit(1)
		return true
	if _elapsed < _until:
		return false
	match _stage:
		0:
			_main = load("res://main.tscn").instantiate()
			root.add_child(_main)
			_wait(0.5, 1)
		1:
			# Reach the workspace-expansion objective: everything before it is complete.
			var session = _session()
			session.progression.add_research_points(3)
			session.network.simulation.money = LargeNumber.from_int(100000)
			var prefix: Array = []
			for objective in ProgressionCatalog.OBJECTIVES:
				if objective["id"] == "expand_space":
					break
				prefix.append(objective["id"])
			_session().objectives.restore(prefix, {})
			_session().objectives.ensure_active(_session())
			_main._hud._set_progress_open(true)
			_wait(0.5, 2)
		2:
			var bar: ScrollBar = _bar()
			_offset_before = _main._camera.offset
			_check(bar.max_value - bar.page > 0.0, "the content is taller than the visible body, so it has scroll range")
			_check(_panel().get_global_rect().size.x > 0.0, "the progress panel is laid out")
			_check(not _main._controller.input_enabled, "workspace input is disabled while the sheet is open")
			_wait(0.1, 3)
		3:
			var before := _scroll().scroll_vertical
			_drag(_label_point(), Vector2(0.0, -300.0))
			_check(_scroll().scroll_vertical > before, "a one-finger drag over a label scrolls the body down")
			_check(_main._camera.offset == _offset_before, "a drag inside the sheet does not pan the workspace")
			_wait(0.1, 4)
		4:
			_drag(_label_point(), Vector2(0.0, 1500.0))
			_check(_scroll().scroll_vertical == 0, "dragging back up scrolls the body to the top")
			_wait(0.1, 5)
		5:
			_centre_expansion_button()
			_wait(0.1, 55)
		55:
			_check(_scroll().get_global_rect().encloses(_space_button().get_global_rect()), "scrolling reaches the workspace expansion button, fully on screen")
			_check(_scroll().scroll_vertical > 0, "reaching the expansion section scrolls the body")
			_drag(_label_point(), Vector2(0.0, -3000.0))
			_wait(0.1, 56)
		56:
			_check(not _more_visible(), "the more-below cue disappears at the bottom")
			_drag(_label_point(), Vector2(0.0, 3000.0))
			_wait(0.1, 57)
		57:
			_centre_expansion_button()
			_wait(0.1, 58)
		58:
			_check(_scroll().get_global_rect().encloses(_space_button().get_global_rect()), "the expansion button is reachable again after returning from the bottom")
			_wait(0.1, 6)
		6:
			var close_rect := _find_button("CLOSE").get_global_rect()
			_check(_panel().get_global_rect().encloses(close_rect) and _find_button("CLOSE").is_visible_in_tree(), "the close control stays visible at the bottom of the scroll")
			_check(_panel()._space_preview.text.begins_with("NEXT +3 cells"), "the expansion preview shows the cells gained before buying")
			_money_before = _session().network.simulation.money.to_text()
			_tap(_space_button().get_global_rect().get_center())
			_wait(0.3, 7)
		7:
			var money_after: String = _session().network.simulation.money.to_text()
			var expected := LargeNumber.from_text(_money_before).subtract(LargeNumber.from_int(150)).to_text()
			_check(money_after == expected, "buying expansion after scrolling costs exactly its price")
			_check(_session().progression.unlocked_cell_count() == 12, "the unlocked workspace grows immediately")
			var description: Dictionary = _session().objectives.describe(_session())
			_check(String(description["progress"]).find("Cells 12 / 15") >= 0, "the expansion objective progress updates")
			_check(_scroll().get_v_scroll_bar().max_value > 0.0, "the panel stays scrollable after the content changes")
			_wait(0.1, 8)
		8:
			_drag(_label_point(), Vector2(0.0, 3000.0))
			_tap(_tech_button("PROCESSOR").get_global_rect().get_center())
			_check(_session().progression.is_tech_unlocked("PROCESSOR"), "tapping a technology button still unlocks it")
			_check(_session().progression.research_points == 2, "the unlock spends exactly its Research Point")
			_wait(0.1, 9)
		9:
			var splitter := _tech_button("SPLITTER")
			_rp_before = _session().progression.research_points
			_drag(splitter.get_global_rect().get_center(), Vector2(0.0, -120.0))
			_check(not _session().progression.is_tech_unlocked("SPLITTER"), "a drag that starts on a technology button does not unlock it")
			_check(_session().progression.research_points == _rp_before, "a drag that starts on a button spends nothing")
			_wait(0.1, 10)
		10:
			_drag(_label_point(), Vector2(0.0, 3000.0))
			var reset := _find_button("RESET PROGRESS")
			_drag(reset.get_global_rect().get_center(), Vector2(0.0, -150.0))
			_check(not _confirm_row().visible, "a drag across Reset Progress does not open its confirmation")
			_check(_session().progression.research_points == _rp_before, "a drag across Reset Progress deletes nothing")
			_tap(_find_button("RESET PROGRESS").get_global_rect().get_center())
			_check(_confirm_row().visible, "a tap on Reset Progress asks for confirmation")
			_tap(_find_button_in(_confirm_row(), "CANCEL").get_global_rect().get_center())
			_check(not _confirm_row().visible, "cancel closes the reset confirmation")
			_check(_session().progression.research_points == _rp_before, "cancelling the reset keeps progress")
			_wait(0.1, 11)
		11:
			_drag(_label_point(), Vector2(0.0, 3000.0))
			_drag(_label_point(), Vector2(0.0, 1500.0))
			_wait(0.1, 12)
		12:
			var zoom_before: float = _main._camera.zoom
			var offset_before: Vector2 = _main._camera.offset
			_pinch(_label_point())
			_check(_main._camera.zoom == zoom_before and _main._camera.offset == offset_before, "pinch zoom and pan do not affect the workspace while the sheet is open")
			_wait(0.1, 13)
		13:
			_drag(_label_point(), Vector2(0.0, 3000.0))
			_find_button("CLOSE").pressed.emit()
			_check(not _panel().visible, "the close control closes the sheet from the bottom of the scroll")
			_check(_main._controller.input_enabled, "workspace input resumes after the sheet closes")
			_wait(0.1, 14)
		14:
			print("PROGRESS-PANEL-TEST failures=%d" % _failures)
			quit(1 if _failures > 0 else 0)
			return true
	return false


func _wait(seconds: float, next_stage: int) -> void:
	_until = _elapsed + seconds
	_stage = next_stage


func _session():
	return _main._session


func _panel():
	return _main._hud._progress_panel


func _scroll() -> ScrollContainer:
	return _panel()._scroll


func _bar():
	return _scroll().get_v_scroll_bar()


func _more_visible() -> bool:
	return _panel()._more_label.visible


func _space_button() -> Button:
	return _panel()._space_button


func _tech_button(id: String) -> Button:
	return _panel()._tech_buttons[id]


func _confirm_row() -> HBoxContainer:
	return _panel()._confirm_row


func _camera_start() -> Vector2:
	return _main._camera.offset


func _label_point() -> Vector2:
	var rect: Rect2 = _scroll().get_global_rect()
	return rect.position + Vector2(rect.size.x * 0.3, 40.0)


# Drags the body so the expansion button sits in the middle of the visible body, as a player would.
func _centre_expansion_button() -> void:
	var body: Rect2 = _scroll().get_global_rect()
	var button: Rect2 = _space_button().get_global_rect()
	var offset_to_centre := (button.position.y - body.position.y) - (body.size.y - button.size.y) * 0.5
	_drag(_label_point(), Vector2(0.0, -offset_to_centre))


func _find_button(text: String) -> Button:
	return _find_button_in(_panel(), text)


func _find_button_in(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button_in(child, text)
		if found != null:
			return found
	return null


func _tap(point: Vector2) -> void:
	_touch(true, point)
	_touch(false, point)


func _drag(from: Vector2, total: Vector2) -> void:
	_touch(true, from)
	var last := from
	for step in range(1, 11):
		var point := from + total * (float(step) / 10.0)
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = point
		event.relative = point - last
		_send_to_body(event)
		last = point
	_touch(false, last)


# Two fingers on the sheet, spreading apart. The workspace must receive none of it.
func _pinch(center: Vector2) -> void:
	_send_to_workspace(_touch_event(true, center + Vector2(-40.0, 0.0), 0))
	_send_to_workspace(_touch_event(true, center + Vector2(40.0, 0.0), 1))
	for step in range(1, 6):
		var event := InputEventScreenDrag.new()
		event.index = 1
		event.position = center + Vector2(40.0 + step * 20.0, 0.0)
		event.relative = Vector2(20.0, 0.0)
		_send_to_workspace(event)
	_send_to_workspace(_touch_event(false, center + Vector2(140.0, 0.0), 1))
	_send_to_workspace(_touch_event(false, center + Vector2(-40.0, 0.0), 0))


func _touch(pressed: bool, position: Vector2, index: int = 0) -> void:
	_send_to_body(_touch_event(pressed, position, index))


func _touch_event(pressed: bool, position: Vector2, index: int = 0) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event


# Headless runs do not route engine GUI input, so the panel's gesture handler is fed the same
# signal the engine emits for its scroll area. Android touch routing is verified on the device.
func _send_to_body(event: InputEvent) -> void:
	# The engine delivers gui_input positions local to the scroll area, so the test converts from screen space.
	var inverse := _scroll().get_global_transform().affine_inverse()
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		touch.position = inverse * touch.position
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		drag.position = inverse * drag.position
	_scroll().gui_input.emit(event)


# Workspace input goes through the controller's unhandled-input path, as it does in the game.
func _send_to_workspace(event: InputEvent) -> void:
	_main._controller._unhandled_input(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: %s" % message)
	else:
		print("PASS: %s" % message)
