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

const TITLE_FONT_SIZE := 32
const MONEY_FONT_SIZE := 28
const TELEMETRY_FONT_SIZE := 18
const BODY_FONT_SIZE := 20
const MARGIN := 24.0
const HEADER_HEIGHT := 140.0
const TOOLBAR_HEIGHT := 150.0
const BANNER_TOP := 190.0
const TOAST_TOP := 240.0
const MONEY_PULSE_UP_TIME := 0.08
const MONEY_PULSE_DOWN_TIME := 0.25
const TOAST_HOLD_TIME := 1.6
const TOAST_FADE_TIME := 0.4

var _money_label: Label
var _telemetry_label: Label
var _money_tween: Tween
var _banner: PanelContainer
var _banner_label: Label
var _toast: Label
var _toast_tween: Tween
var _toolbar: BuildToolbar
var _node_panel: NodePanel


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
	_money_label = _make_label("$0", MONEY_FONT_SIZE)
	header.add_child(_money_label)
	_telemetry_label = _make_label("", TELEMETRY_FONT_SIZE)
	header.add_child(_telemetry_label)

	_banner = _build_banner()
	root.add_child(_banner)

	_toast = _make_label("", BODY_FONT_SIZE)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

	_toolbar = BuildToolbar.new()
	_toolbar.placement_requested.connect(placement_requested.emit)
	_place_above_toolbar(_toolbar, false)
	root.add_child(_toolbar)


func refresh(manager: NetworkManager, mode: int, placement_type: int, selected_id: int, delete_armed: bool) -> void:
	_money_label.text = NumberFormat.money(manager.simulation.money)
	_telemetry_label.text = _telemetry_text(manager.get_network_summary())
	_toolbar.refresh(manager, placement_type if mode == WorkspaceController.Mode.PLACE else -1)
	_node_panel.refresh(manager, selected_id, delete_armed)
	_banner.visible = mode != WorkspaceController.Mode.IDLE
	_banner_label.text = _banner_text(mode, placement_type)


func show_feedback(message: String, is_error: bool) -> void:
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
		bottom = viewport_size.y - (TOOLBAR_HEIGHT + MARGIN * 2.0) - _height_of(_node_panel)
	return Rect2(0.0, top, viewport_size.x, maxf(bottom - top, 0.0))


func _telemetry_text(summary: Dictionary) -> String:
	var revenue: float = maxf(summary["revenue_rate"], 0.0)
	var revenue_text := "∞" if is_inf(revenue) else NumberFormat.compact(LargeNumber.from_text("%.0f" % revenue))
	return "Produced %.1f/s · Revenue %s/s · Queued %s · Bottlenecks %d" % [
		summary["produced_rate"],
		revenue_text,
		NumberFormat.compact(summary["waiting"]),
		summary["bottlenecks"],
	]


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
