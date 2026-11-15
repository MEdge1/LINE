class_name NodePanel
extends PanelContainer

# Inspector for the selected node. Shows type-specific stats, every connection with its
# own DISCONNECT action, and the node's other actions.

signal upgrade_requested
signal connect_requested
signal move_requested
signal delete_requested
signal disconnect_requested(from_id: int, to_id: int)

const FONT_SIZE := 20
const ACTION_HEIGHT := 56.0
const CONNECTION_HEIGHT := 48.0

var _info_label: Label
var _connections_box: VBoxContainer
var _upgrade_button: Button
var _delete_button: Button
var _shown_connections: String = ""


func _ready() -> void:
	visible = false

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	add_child(content)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_info_label.add_theme_color_override("font_color", LinePalette.TEXT)
	content.add_child(_info_label)

	_connections_box = VBoxContainer.new()
	_connections_box.add_theme_constant_override("separation", 8)
	content.add_child(_connections_box)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)

	_upgrade_button = _make_action("UPGRADE", actions)
	_upgrade_button.pressed.connect(upgrade_requested.emit)

	_make_action("CONNECT", actions).pressed.connect(connect_requested.emit)
	_make_action("MOVE", actions).pressed.connect(move_requested.emit)

	_delete_button = _make_action("DELETE", actions)
	_delete_button.pressed.connect(delete_requested.emit)


func refresh(manager: NetworkManager, selected_id: int, delete_armed: bool) -> void:
	visible = selected_id != 0 and manager.graph.has_node(selected_id)
	if not visible:
		_shown_connections = ""
		return

	var node := manager.graph.get_node(selected_id)
	_info_label.text = _describe(manager, node)
	_refresh_connections(manager, selected_id)

	var is_generator := manager.is_generator(selected_id)
	_upgrade_button.visible = is_generator
	if is_generator:
		var at_max := manager.is_at_max_level(selected_id)
		_upgrade_button.disabled = at_max
		_upgrade_button.text = "MAX LEVEL" if at_max else "UPGRADE %s" % NumberFormat.money(manager.get_upgrade_cost(selected_id))

	_delete_button.text = "TAP AGAIN" if delete_armed else "DELETE"


# Rebuilds the connection rows only when the set of connections actually changes.
func _refresh_connections(manager: NetworkManager, selected_id: int) -> void:
	var outgoing: Array = manager.graph.get_outgoing(selected_id)
	var incoming: Array = manager.graph.get_incoming(selected_id)
	var signature := "%s|%s" % [outgoing, incoming]
	if signature == _shown_connections:
		return
	_shown_connections = signature

	for child in _connections_box.get_children():
		child.queue_free()
		_connections_box.remove_child(child)

	if outgoing.is_empty() and incoming.is_empty():
		_connections_box.add_child(_make_label("No connections. Drag from the handle or use CONNECT."))

	for to_id in outgoing:
		_add_connection_row(manager, "→ %s" % _node_label(manager, to_id), selected_id, to_id)
	for from_id in incoming:
		_add_connection_row(manager, "← %s" % _node_label(manager, from_id), from_id, selected_id)


func _add_connection_row(manager: NetworkManager, text: String, from_id: int, to_id: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_connections_box.add_child(row)

	var label := _make_label(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var button := Button.new()
	button.text = "DISCONNECT"
	button.custom_minimum_size = Vector2(0.0, CONNECTION_HEIGHT)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.pressed.connect(disconnect_requested.emit.bind(from_id, to_id))
	row.add_child(button)


func _node_label(manager: NetworkManager, id: int) -> String:
	return "%s #%d" % [NodeDefinitions.get_display_name(manager.graph.get_node(id).type), id]


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", LinePalette.TEXT)
	return label


func _make_action(text: String, parent: Control) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, ACTION_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	parent.add_child(button)
	return button


func _describe(manager: NetworkManager, node: NetworkGraph.NetworkNode) -> String:
	var lines: Array[String] = [NodeDefinitions.get_display_name(node.type)]
	var outputs := manager.graph.get_outgoing(node.id).size()
	var inputs := manager.graph.get_incoming(node.id).size()

	if node.type == NodeDefinitions.Type.GENERATOR:
		var level_line := "Level %d" % node.level
		if manager.is_at_max_level(node.id):
			level_line += "  ·  MAX LEVEL"
		lines.append(level_line)
		lines.append("Production %.2f/sec" % manager.simulation.get_generator_rate(node.id))
		lines.append("Connections %d/%d" % [outputs, NodeDefinitions.get_max_outputs(node.type)])
	elif node.type == NodeDefinitions.Type.PROCESSOR:
		lines.append("Multiplier ×%d" % LineBalance.PROCESSOR_MULTIPLIER)
		lines.append("Input %d/%d   Output %d/%d" % [
			inputs, NodeDefinitions.get_max_inputs(node.type),
			outputs, NodeDefinitions.get_max_outputs(node.type),
		])
		var waiting := manager.simulation.get_waiting_total(node.id)
		if not waiting.is_zero():
			lines.append("Waiting %s" % NumberFormat.compact(waiting))
	else:
		lines.append("Input %d/%d" % [inputs, NodeDefinitions.get_max_inputs(node.type)])
		lines.append("Revenue %s" % NumberFormat.money(manager.simulation.get_revenue(node.id)))

	return "\n".join(PackedStringArray(lines))
