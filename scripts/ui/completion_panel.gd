class_name CompletionPanel
extends PanelContainer

# One-time prototype summary. Shows lifetime totals and lets the player continue. It never resets progress.

signal continue_requested

const FONT_SIZE := 20
const TITLE_FONT_SIZE := 30

var _body: Label


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(620.0, 0.0)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	add_child(content)

	var title := Label.new()
	title.text = "NETWORK STABLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", LinePalette.PAYOUT_HIGHLIGHT)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Prototype progression complete."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", FONT_SIZE)
	content.add_child(subtitle)

	_body = Label.new()
	_body.add_theme_font_size_override("font_size", FONT_SIZE)
	_body.add_theme_color_override("font_color", LinePalette.TEXT)
	content.add_child(_body)

	var continue_button := Button.new()
	continue_button.text = "CONTINUE"
	continue_button.custom_minimum_size = Vector2(0.0, 60.0)
	continue_button.add_theme_font_size_override("font_size", FONT_SIZE)
	continue_button.pressed.connect(continue_requested.emit)
	content.add_child(continue_button)


func show_summary(session: GameSession) -> void:
	var stats := session.stats
	var nodes_built := 0
	for key in stats.counters:
		if key.begins_with("built."):
			nodes_built += stats.counters[key].to_int_clamped()

	_body.text = "\n".join(PackedStringArray([
		"Total Production    %s" % NumberFormat.compact(session.network.simulation.produced_units),
		"Lifetime Revenue    %s" % NumberFormat.money(stats.counter("revenue")),
		"Peak Revenue        %s/sec" % NumberFormat.money(stats.peak_revenue),
		"Highest Complexity  %d" % stats.highest_complexity,
		"Nodes Built         %d" % nodes_built,
		"Bottlenecks Resolved  %d" % stats.bottlenecks_resolved,
	]))
	visible = true
