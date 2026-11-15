class_name BuildToolbar
extends PanelContainer

# Touch-friendly node picker in two rows. Shows each node's cost and whether it is affordable.

signal placement_requested(type: int)

const BUTTON_HEIGHT := 60.0
const FONT_SIZE := 18
const UNAFFORDABLE_ALPHA := 0.4
const TYPES := [
	NodeDefinitions.Type.GENERATOR,
	NodeDefinitions.Type.PROCESSOR,
	NodeDefinitions.Type.OUTPUT,
	NodeDefinitions.Type.SPLITTER,
	NodeDefinitions.Type.MERGER,
	NodeDefinitions.Type.BOOSTER,
]

var _buttons: Dictionary = {}


func _ready() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)

	for type in TYPES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.add_theme_color_override("font_color", LinePalette.for_node_type(type))
		button.pressed.connect(placement_requested.emit.bind(type))
		grid.add_child(button)
		_buttons[type] = button


func refresh(manager: NetworkManager, active_type: int) -> void:
	for type in TYPES:
		var button: Button = _buttons[type]
		var prefix := "> " if type == active_type else ""
		button.text = "%s%s  $%d" % [prefix, NodeDefinitions.get_display_name(type), NodeDefinitions.get_cost(type)]
		button.modulate = Color.WHITE if manager.can_afford(type) else Color(1.0, 1.0, 1.0, UNAFFORDABLE_ALPHA)
