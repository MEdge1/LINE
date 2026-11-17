class_name Hud
extends CanvasLayer

# Money, network telemetry, mode banner, feedback toast, and the build and inspect controls.

signal placement_requested(type: int)
signal connect_requested
signal move_requested
signal upgrade_requested
signal delete_requested
signal disconnect_requested(from_id: int, to_id: int)
signal cancel_requested
signal unlock_requested(id: String)
signal expand_requested
signal reset_requested
signal completion_continued
signal progress_toggled(open: bool)
signal balance_mode_requested(mode: int)
signal booster_model_requested(mode: int)
signal balance_sheet_toggled(open: bool)

const TITLE_FONT_SIZE := 32
const MONEY_FONT_SIZE := 28
const TELEMETRY_FONT_SIZE := 18
const BODY_FONT_SIZE := 20
const MARGIN := 24.0
const HEADER_HEIGHT := 200.0
const TOOLBAR_HEIGHT := 150.0
const BANNER_TOP := 214.0
const TOAST_TOP := 264.0
const MONEY_PULSE_UP_TIME := 0.08
const MONEY_PULSE_DOWN_TIME := 0.25
const TOAST_HOLD_TIME := 1.6
const TOAST_FADE_TIME := 0.4
const PRIORITY_HOLD_MSEC := 3000

var _money_label: Label
var _rp_label: Label
var _telemetry_label: Label
var _tracker_label: Label
var _hint_label: Label
var _progress_button: Button
var _money_tween: Tween
var _banner: PanelContainer
var _banner_label: Label
var _toast: Label
var _toast_tween: Tween
var _priority_until_msec: int = 0
var _toolbar: BuildToolbar
var _node_panel: NodePanel
var _progress_panel: ProgressPanel
var _balance_button: Button
var _balance_sheet: PanelContainer
var _booster_buttons: Dictionary = {}
var _balance_live: Button
var _balance_candidate: Button
var _completion_panel: CompletionPanel


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(LinePalette.BACKGROUND, 0.88)
	backdrop.anchor_right = 1.0
	backdrop.offset_bottom = HEADER_HEIGHT
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)

	var header := VBoxContainer.new()
	header.position = Vector2(MARGIN, MARGIN)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(header)
	header.add_child(_make_label("LINE", TITLE_FONT_SIZE))
	var money_row := HBoxContainer.new()
	money_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(money_row)
	_money_label = _make_label("$0", MONEY_FONT_SIZE)
	money_row.add_child(_money_label)
	_rp_label = _make_label("", TELEMETRY_FONT_SIZE)
	_rp_label.add_theme_color_override("font_color", LinePalette.PROCESSED_UNIT)
	_rp_label.size_flags_vertical = Control.SIZE_SHRINK_END
	money_row.add_child(_rp_label)
	_telemetry_label = _make_label("", TELEMETRY_FONT_SIZE)
	header.add_child(_telemetry_label)
	_tracker_label = _make_label("", TELEMETRY_FONT_SIZE)
	header.add_child(_tracker_label)
	_hint_label = _make_label("", TELEMETRY_FONT_SIZE)
	_hint_label.add_theme_color_override("font_color", LinePalette.PROCESSED_UNIT)
	header.add_child(_hint_label)

	_progress_button = Button.new()
	_progress_button.text = "PROGRESS"
	_progress_button.add_theme_font_size_override("font_size", TELEMETRY_FONT_SIZE)
	_progress_button.anchor_left = 1.0
	_progress_button.anchor_right = 1.0
	_progress_button.offset_left = -MARGIN - 170.0
	_progress_button.offset_right = -MARGIN
	_progress_button.offset_top = MARGIN
	_progress_button.offset_bottom = MARGIN + 52.0
	_progress_button.pressed.connect(_toggle_progress)
	root.add_child(_progress_button)

	_banner = _build_banner()
	root.add_child(_banner)

	_toast = _make_label("", BODY_FONT_SIZE)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.offset_left = MARGIN
	_toast.offset_right = -MARGIN
	_toast.offset_top = TOAST_TOP
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	_node_panel = NodePanel.new()
	_node_panel.upgrade_requested.connect(upgrade_requested.emit)
	_node_panel.connect_requested.connect(connect_requested.emit)
	_node_panel.move_requested.connect(move_requested.emit)
	_node_panel.delete_requested.connect(delete_requested.emit)
	_node_panel.disconnect_requested.connect(disconnect_requested.emit)
	_place_above_toolbar(_node_panel, true)
	root.add_child(_node_panel)

	_progress_panel = ProgressPanel.new()
	_progress_panel.unlock_requested.connect(unlock_requested.emit)
	_progress_panel.expand_requested.connect(expand_requested.emit)
	_progress_panel.reset_requested.connect(reset_requested.emit)
	_progress_panel.closed.connect(_set_progress_open.bind(false))
	_place_above_toolbar(_progress_panel, true)
	root.add_child(_progress_panel)

	# Development-only: a small indicator that always shows the active processing model, and a separate sheet
	# to switch it. Neither lives inside the Progress panel's scroll area.
	_balance_button = Button.new()
	_balance_button.add_theme_font_size_override("font_size", TELEMETRY_FONT_SIZE)
	_balance_button.anchor_left = 1.0
	_balance_button.anchor_right = 1.0
	_balance_button.offset_left = -MARGIN - 170.0
	_balance_button.offset_right = -MARGIN
	_balance_button.offset_top = MARGIN + 60.0
	_balance_button.offset_bottom = MARGIN + 100.0
	_balance_button.pressed.connect(_toggle_balance)
	root.add_child(_balance_button)

	_balance_sheet = _build_balance_sheet()
	_place_above_toolbar(_balance_sheet, true)
	root.add_child(_balance_sheet)

	_completion_panel = CompletionPanel.new()
	_completion_panel.continue_requested.connect(completion_continued.emit)
	root.add_child(_completion_panel)

	_toolbar = BuildToolbar.new()
	_toolbar.placement_requested.connect(placement_requested.emit)
	_place_above_toolbar(_toolbar, false)
	root.add_child(_toolbar)


func refresh(session: GameSession, mode: int, placement_type: int, selected_id: int, delete_armed: bool) -> void:
	var manager := session.network
	_refresh_balance(manager.simulation.processing_mode, manager.simulation.booster_model)
	_money_label.text = NumberFormat.money(manager.simulation.money)
	_rp_label.text = "RP %d" % session.progression.research_points
	_telemetry_label.text = _telemetry_text(manager)

	var objective := session.objectives.describe(session)
	_tracker_label.text = _tracker_text(objective)
	_hint_label.text = "" if objective["finished"] else objective["hint"]

	_toolbar.refresh(manager, placement_type if mode == WorkspaceController.Mode.PLACE else -1)
	_node_panel.refresh(manager, selected_id, delete_armed)
	if _progress_panel.visible:
		_node_panel.visible = false
		_progress_panel.refresh(session)
	_banner.visible = mode != WorkspaceController.Mode.IDLE
	_banner_label.text = _banner_text(mode, placement_type)


func show_completion(session: GameSession) -> void:
	_completion_panel.show_summary(session)


func hide_completion() -> void:
	_completion_panel.visible = false


func _toggle_progress() -> void:
	_set_progress_open(not _progress_panel.visible)


func _set_progress_open(open: bool) -> void:
	_progress_panel.visible = open
	if open:
		_node_panel.visible = false
		_set_balance_open(false)
	progress_toggled.emit(open)


func is_progress_open() -> bool:
	return _progress_panel.visible


func _toggle_balance() -> void:
	_set_balance_open(not _balance_sheet.visible)


func _set_balance_open(open: bool) -> void:
	if open and _progress_panel.visible:
		_set_progress_open(false)
	_balance_sheet.visible = open
	if open:
		_node_panel.visible = false
	balance_sheet_toggled.emit(open)


# The indicator always shows both active models. The active choice is disabled, so repeat taps do nothing.
func _refresh_balance(processing_mode: int, booster_mode: int) -> void:
	_balance_button.text = "EXP 1.10 · %s" % BoosterModel.label(booster_mode) if processing_mode == ProcessingBalance.Mode.EXPONENTIAL_CANDIDATE_1 else "LIVE · %s" % BoosterModel.label(booster_mode)
	_balance_button.add_theme_color_override("font_color", LinePalette.WARNING if processing_mode == ProcessingBalance.Mode.EXPONENTIAL_CANDIDATE_1 else LinePalette.TEXT)
	_balance_live.disabled = processing_mode == ProcessingBalance.Mode.LIVE_HYPERBOLIC
	_balance_candidate.disabled = processing_mode == ProcessingBalance.Mode.EXPONENTIAL_CANDIDATE_1
	_balance_live.text = "LIVE  ·  active" if _balance_live.disabled else "LIVE\nCurrent hyperbolic complexity"
	_balance_candidate.text = "CANDIDATE 1  ·  active" if _balance_candidate.disabled else "CANDIDATE 1\nExponential work ×1.10 per complexity"
	for mode in _booster_buttons:
		var button: Button = _booster_buttons[mode]
		button.disabled = mode == booster_mode
		button.text = "%s  ·  active" % BoosterModel.label(mode) if button.disabled else BoosterModel.label(mode)


func _build_balance_sheet() -> PanelContainer:
	var sheet := PanelContainer.new()
	sheet.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	sheet.add_child(column)
	column.add_child(_make_label("BALANCE TEST  ·  DEVELOPMENT", BODY_FONT_SIZE))
	column.add_child(_make_label("Processing model. Switching keeps progress, money, and the network.", TELEMETRY_FONT_SIZE))

	_balance_live = Button.new()
	_balance_live.custom_minimum_size = Vector2(0.0, 72.0)
	_balance_live.pressed.connect(func() -> void: balance_mode_requested.emit(ProcessingBalance.Mode.LIVE_HYPERBOLIC))
	column.add_child(_balance_live)

	_balance_candidate = Button.new()
	_balance_candidate.custom_minimum_size = Vector2(0.0, 72.0)
	_balance_candidate.pressed.connect(func() -> void: balance_mode_requested.emit(ProcessingBalance.Mode.EXPONENTIAL_CANDIDATE_1))
	column.add_child(_balance_candidate)

	column.add_child(_make_label("BOOSTER MODEL  ·  same network, only coverage changes", TELEMETRY_FONT_SIZE))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for mode in BoosterModel.all_modes():
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 56.0)
		button.pressed.connect(func() -> void: booster_model_requested.emit(mode))
		grid.add_child(button)
		_booster_buttons[mode] = button

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0.0, 56.0)
	close.pressed.connect(_set_balance_open.bind(false))
	column.add_child(close)
	return sheet


func show_feedback(message: String, is_error: bool) -> void:
	# Objective and unlock notices hold the toast briefly so routine messages cannot hide them.
	# Errors always show at once.
	if not is_error and Time.get_ticks_msec() < _priority_until_msec:
		return
	_show_toast(message, is_error)


func show_priority_feedback(message: String) -> void:
	_priority_until_msec = Time.get_ticks_msec() + PRIORITY_HOLD_MSEC
	_show_toast(message, false)


func _show_toast(message: String, is_error: bool) -> void:
	_toast.text = message
	_toast.add_theme_color_override("font_color", LinePalette.INVALID if is_error else LinePalette.TEXT)
	_toast.modulate.a = 1.0

	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD_TIME)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE_TIME)


func pulse_money(complexity: int = 0) -> void:
	# Restart from the current state so rapid payouts retrigger the pulse cleanly.
	if _money_tween and _money_tween.is_valid():
		_money_tween.kill()

	_money_label.pivot_offset = Vector2(0.0, _money_label.size.y * 0.5)
	var pulse := Vector2.ONE * ComplexityStyle.money_pulse_scale(complexity)

	_money_tween = create_tween()
	_money_tween.tween_property(_money_label, "scale", pulse, MONEY_PULSE_UP_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_money_tween.parallel().tween_property(_money_label, "modulate", LinePalette.PAYOUT_HIGHLIGHT, MONEY_PULSE_UP_TIME)
	_money_tween.tween_property(_money_label, "scale", Vector2.ONE, MONEY_PULSE_DOWN_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_money_tween.parallel().tween_property(_money_label, "modulate", Color.WHITE, MONEY_PULSE_DOWN_TIME)


# The screen band that no panel covers: below the header or banner and above the inspector or toolbar.
func workspace_band(viewport_size: Vector2) -> Rect2:
	var top := HEADER_HEIGHT
	if _banner.visible:
		top = _banner.position.y + _banner.size.y

	var toolbar_top := viewport_size.y - MARGIN - _height_of(_toolbar)
	var bottom := toolbar_top
	if _node_panel.visible:
		bottom = minf(bottom, viewport_size.y - (TOOLBAR_HEIGHT + MARGIN * 2.0) - _height_of(_node_panel))
	if _progress_panel.visible:
		bottom = minf(bottom, viewport_size.y - (TOOLBAR_HEIGHT + MARGIN * 2.0) - _height_of(_progress_panel))
	return Rect2(0.0, top, viewport_size.x, maxf(bottom - top, 0.0))


func _telemetry_text(manager: NetworkManager) -> String:
	var summary := manager.get_network_summary()
	var revenue: float = maxf(summary["revenue_rate"], 0.0)
	var revenue_text := "∞" if is_inf(revenue) else NumberFormat.compact(LargeNumber.from_text("%.0f" % revenue))
	return "Produced %.1f/s · Done %.2f/s · Revenue %s/s · Queued %s · Bottlenecks %d" % [
		summary["produced_rate"],
		manager.completed_rate(),
		revenue_text,
		NumberFormat.compact(summary["waiting"]),
		summary["bottlenecks"],
	]


func _tracker_text(objective: Dictionary) -> String:
	if objective["finished"]:
		return "PROTOTYPE COMPLETE · free play"
	var text := "OBJECTIVE %d/%d · %s" % [objective["index"], objective["total"], objective["title"]]
	if objective["progress"] != "":
		text += "\n%s" % objective["progress"]
	return text


func _build_banner() -> PanelContainer:
	var banner := PanelContainer.new()
	banner.anchor_left = 0.0
	banner.anchor_right = 1.0
	banner.offset_left = MARGIN
	banner.offset_right = -MARGIN
	banner.offset_top = BANNER_TOP
	banner.mouse_filter = Control.MOUSE_FILTER_STOP
	banner.visible = false

	var row := HBoxContainer.new()
	banner.add_child(row)

	_banner_label = _make_label("", BODY_FONT_SIZE)
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_banner_label)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	cancel.pressed.connect(cancel_requested.emit)
	row.add_child(cancel)

	return banner


# Bottom-anchored controls grow upward so they fit any phone height.
func _place_above_toolbar(control: Control, stack_above_toolbar: bool) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = MARGIN
	control.offset_right = -MARGIN
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bottom := -(TOOLBAR_HEIGHT + MARGIN * 2.0) if stack_above_toolbar else -MARGIN
	control.offset_top = bottom
	control.offset_bottom = bottom


func _banner_text(mode: int, placement_type: int) -> String:
	match mode:
		WorkspaceController.Mode.PLACE:
			return "PLACE %s  ·  tap an empty cell" % NodeDefinitions.get_display_name(placement_type)
		WorkspaceController.Mode.CONNECT:
			return "CONNECT  ·  tap the destination node"
		WorkspaceController.Mode.MOVE:
			return "MOVE  ·  tap an empty cell"
		_:
			return ""


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", LinePalette.TEXT)
	return label


# Bottom-anchored panels size themselves from content, so use whichever is larger right now.
func _height_of(control: Control) -> float:
	return maxf(control.size.y, control.get_combined_minimum_size().y)
