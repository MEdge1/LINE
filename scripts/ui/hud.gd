class_name Hud
extends CanvasLayer

signal upgrade_pressed

const TITLE_FONT_SIZE := 32
const MONEY_FONT_SIZE := 28
const BODY_FONT_SIZE := 22
const MARGIN := 32.0
const PANEL_WIDTH := 420.0

var _money_label: Label
var _panel: PanelContainer
var _level_label: Label
var _production_label: Label
var _upgrade_button: Button


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var header := VBoxContainer.new()
	header.position = Vector2(MARGIN, MARGIN)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(header)

	header.add_child(_make_label("LINE", TITLE_FONT_SIZE))
	_money_label = _make_label("$0", MONEY_FONT_SIZE)
	header.add_child(_money_label)

	_panel = _build_generator_panel()
	root.add_child(_panel)


func refresh(simulation: ProductionSimulation, generator_selected: bool) -> void:
	_money_label.text = "$%d" % simulation.money
	_panel.visible = generator_selected

	if not generator_selected:
		return

	_level_label.text = "Level %d" % simulation.generator_level
	_production_label.text = "Production  %.2f/sec" % simulation.get_generator_rate()
	_upgrade_button.text = "UPGRADE  $%d" % simulation.get_upgrade_cost()
	_upgrade_button.disabled = not simulation.can_afford_upgrade()


func _build_generator_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Anchor to bottom-center and grow upward so the panel fits any phone height.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -MARGIN

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	content.add_child(_make_label("GENERATOR", TITLE_FONT_SIZE))
	_level_label = _make_label("", BODY_FONT_SIZE)
	content.add_child(_level_label)
	_production_label = _make_label("", BODY_FONT_SIZE)
	content.add_child(_production_label)

	_upgrade_button = Button.new()
	_upgrade_button.custom_minimum_size = Vector2(0.0, 72.0)
	_upgrade_button.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_upgrade_button.pressed.connect(upgrade_pressed.emit)
	content.add_child(_upgrade_button)

	return panel


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", LinePalette.TEXT)
	return label
