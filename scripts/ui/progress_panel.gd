class_name ProgressPanel
extends PanelContainer

# Progression sheet: the tracked objective, Research Points, technology unlocks, workspace expansion,
# and a confirmed reset. Opened from the header. The panel only reads state and emits requests.

signal unlock_requested(id: String)
signal expand_requested
signal reset_requested
signal closed

const PANEL_HEIGHT := 560.0
const FONT_SIZE := 20
const SMALL_SIZE := 16
const BUTTON_HEIGHT := 52.0
# A touch that moves less than this (screen pixels) before release counts as a tap.
const TAP_SLOP := 14.0

var _stage_label: Label
var _title_label: Label
var _progress_label: Label
var _rp_label: Label
var _tech_buttons: Dictionary = {}
var _space_label: Label
var _space_button: Button
var _space_preview: Label
var _confirm_row: HBoxContainer
var _scroll: ScrollContainer
var _more_label: Label
# Buttons inside the scrolling body are activated by the panel on a tap, never by the engine's
# button press. That lets any vertical drag start on a button and still scroll the body.
var _tap_targets: Array = []
var _gesture_active := false
var _gesture_moved := false
var _gesture_origin := Vector2.ZERO
var _gesture_scroll := 0


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, PANEL_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	# Fixed header: stays visible while the body scrolls, so the sheet can always be closed.
	var header := HBoxContainer.new()
	layout.add_child(header)
	var heading := _make_label("PROGRESS", FONT_SIZE)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_rp_label = _make_label("", FONT_SIZE)
	_rp_label.add_theme_color_override("font_color", LinePalette.PROCESSED_UNIT)
	header.add_child(_rp_label)
	var close := _make_button("CLOSE", FONT_SIZE)
	close.custom_minimum_size = Vector2(120.0, BUTTON_HEIGHT)
	close.pressed.connect(closed.emit)
	header.add_child(close)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.gui_input.connect(_on_scroll_gui_input)
	layout.add_child(_scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	_scroll.add_child(content)

	_stage_label = _make_label("", SMALL_SIZE)
	content.add_child(_stage_label)
	_title_label = _make_label("", FONT_SIZE)
	content.add_child(_title_label)
	_progress_label = _make_label("", SMALL_SIZE)
	_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_progress_label)

	content.add_child(_make_label("TECHNOLOGY", SMALL_SIZE))
	for tech in ProgressionCatalog.TECHNOLOGIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		content.add_child(row)

		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text)
		text.add_child(_make_label(tech["id"], FONT_SIZE))
		var summary := _make_label(tech["summary"], SMALL_SIZE)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(summary)

		var button := _make_button("", FONT_SIZE)
		button.custom_minimum_size = Vector2(190.0, BUTTON_HEIGHT)
		_track_button(button, unlock_requested.emit.bind(tech["id"]))
		row.add_child(button)
		_tech_buttons[tech["id"]] = button

	content.add_child(_make_label("WORKSPACE", SMALL_SIZE))
	_space_label = _make_label("", FONT_SIZE)
	content.add_child(_space_label)
	_space_preview = _make_label("", SMALL_SIZE)
	_space_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_space_preview.add_theme_color_override("font_color", LinePalette.PAYOUT_HIGHLIGHT)
	content.add_child(_space_preview)
	_space_button = _make_button("", FONT_SIZE)
	_space_button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	_track_button(_space_button, expand_requested.emit)
	content.add_child(_space_button)

	var reset := _make_button("RESET PROGRESS", SMALL_SIZE)
	reset.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	_track_button(reset, func() -> void: _confirm_row.visible = not _confirm_row.visible)
	content.add_child(reset)

	_confirm_row = HBoxContainer.new()
	_confirm_row.visible = false
	_confirm_row.add_theme_constant_override("separation", 10)
	content.add_child(_confirm_row)
	var warning := _make_label("RESET PROGRESS? This permanently deletes the current LINE save.", SMALL_SIZE)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warning.add_theme_color_override("font_color", LinePalette.INVALID)
	_confirm_row.add_child(warning)
	var cancel := _make_button("CANCEL", SMALL_SIZE)
	_track_button(cancel, func() -> void: _confirm_row.visible = false)
	_confirm_row.add_child(cancel)
	var confirm := _make_button("RESET", SMALL_SIZE)
	_track_button(confirm, func() -> void:
		_confirm_row.visible = false
		reset_requested.emit())
	_confirm_row.add_child(confirm)

	# Shown only while more content lies below the visible body.
	_more_label = _make_label("↓  more below", SMALL_SIZE)
	_more_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more_label.add_theme_color_override("font_color", LinePalette.PROCESSED_UNIT)
	_more_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_more_label)


func refresh(session: GameSession) -> void:
	var progression := session.progression
	var objective := session.objectives.describe(session)
	_stage_label.text = "STAGE · %s" % objective["stage"]
	_title_label.text = objective["title"]
	_progress_label.text = objective["progress"] if not objective["finished"] else "Every prototype system is mastered."
	_rp_label.text = "RP %d" % progression.research_points

	for tech in ProgressionCatalog.TECHNOLOGIES:
		var button: Button = _tech_buttons[tech["id"]]
		var result := progression.can_unlock(tech["id"])
		match result:
			ProgressionManager.UnlockResult.ALREADY_UNLOCKED:
				button.text = "UNLOCKED"
				button.disabled = true
			ProgressionManager.UnlockResult.OK:
				button.text = "UNLOCK · %d RP" % int(tech["cost"])
				button.disabled = false
			ProgressionManager.UnlockResult.INSUFFICIENT_RP:
				button.text = "NEEDS %d RP" % int(tech["cost"])
				button.disabled = true
			_:
				button.text = "LOCKED"
				button.disabled = true

	var cost := progression.next_expansion_cost()
	var unlocked := progression.unlocked_cell_count()
	var total := WorkspaceLayout.COLUMNS * WorkspaceLayout.ROWS
	_space_label.text = "%d of %d cells unlocked" % [unlocked, total]
	if cost < 0:
		_space_preview.text = ""
		_space_button.text = "FULLY EXPANDED"
		_space_button.disabled = true
	else:
		var gained := progression.next_expansion_cells().size()
		_space_preview.text = "NEXT +%d cells  ·  %d → %d" % [gained, unlocked, unlocked + gained]
		_space_button.text = "BUY SPACE · %s" % NumberFormat.money(LargeNumber.from_int(cost))
		_space_button.disabled = not progression.can_expand(session.network.simulation)


func _process(_delta: float) -> void:
	if visible and _more_label:
		_more_label.visible = _has_more_below()


func _has_more_below() -> bool:
	var bar := _scroll.get_v_scroll_bar()
	return bar.max_value - bar.page > _scroll.scroll_vertical + 2


func _track_button(button: Button, action: Callable) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.focus_mode = Control.FOCUS_NONE
	_tap_targets.append({"button": button, "action": action})


# Touch and mouse input inside the body. Dragging scrolls; a press and release without real movement is
# a tap, and a tap activates the button under it. Every event is accepted here, so nothing reaches the workspace.
func _on_scroll_gui_input(event: InputEvent) -> void:
	var is_press: bool = event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	if is_press:
		var position: Vector2 = event.position
		if event.pressed:
			_gesture_active = true
			_gesture_moved = false
			_gesture_origin = position
			_gesture_scroll = _scroll.scroll_vertical
		elif _gesture_active:
			_gesture_active = false
			if not _gesture_moved:
				_activate_at(position)
		_scroll.accept_event()
		return

	var is_drag: bool = event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)
	if is_drag and _gesture_active:
		var total: Vector2 = event.position - _gesture_origin
		if not _gesture_moved and total.length() > TAP_SLOP:
			_gesture_moved = true
		if _gesture_moved:
			var bar := _scroll.get_v_scroll_bar()
			var limit := int(bar.max_value - bar.page)
			_scroll.scroll_vertical = clampi(int(round(_gesture_scroll - total.y)), 0, maxi(limit, 0))
		_scroll.accept_event()


func _activate_at(position: Vector2) -> void:
	# Gesture positions are local to the scroll area; button rects are global.
	var global_point := _scroll.get_global_transform() * position
	for target in _tap_targets:
		var button: Button = target["button"]
		if button.disabled or not button.is_visible_in_tree():
			continue
		if button.get_global_rect().has_point(global_point):
			(target["action"] as Callable).call()
			return


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", LinePalette.TEXT)
	return label


func _make_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	return button
