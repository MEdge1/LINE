class_name NodePanel
extends PanelContainer

# Inspector for the selected node. Shows type-specific measurements, every connection with its own
# DISCONNECT action, and the node's other actions.

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

	_info_label = _make_label("")
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
		_connections_box.remove_child(child)
		child.queue_free()

	if outgoing.is_empty() and incoming.is_empty():
		_connections_box.add_child(_make_label("No connections. Drag from the handle or use CONNECT."))

	for to_id in outgoing:
		_add_connection_row(manager, "→ %s" % _node_label(manager, to_id), selected_id, to_id)
	for from_id in incoming:
		_add_connection_row(manager, "← %s" % _node_label(manager, from_id), from_id, selected_id)


func _add_connection_row(_manager: NetworkManager, text: String, from_id: int, to_id: int) -> void:
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
	var simulation := manager.simulation
	var lines: Array[String] = [NodeDefinitions.get_display_name(node.type)]
	var outputs := manager.graph.get_outgoing(node.id).size()
	var inputs := manager.graph.get_incoming(node.id).size()

	match node.type:
		NodeDefinitions.Type.GENERATOR:
			var level_line := "Level %d" % node.level
			if manager.is_at_max_level(node.id):
				level_line += "  ·  MAX LEVEL"
			lines.append(level_line)
			lines.append("Production %.2f/sec  (measured %s/sec)" % [simulation.get_generator_rate(node.id), _rate(simulation.telemetry.produced_rate(node.id))])
			lines.append("Connections %d/%d" % [outputs, NodeDefinitions.get_max_outputs(node.type)])
			lines.append("Status %s" % _status_text(simulation.get_status(node.id)))
		NodeDefinitions.Type.PROCESSOR:
			lines.append("Multiplier ×%d  ·  Incoming complexity %d  ·  Model %s" % [LineBalance.PROCESSOR_MULTIPLIER, simulation.get_incoming_complexity(node.id), ProcessingBalance.short_label(simulation.processing_mode)])
			var base := NodeDefinitions.get_capacity(node.type)
			lines.append("Boosted %s  ·  Booster model %s" % ["Yes" if node.boosted else "No", BoosterModel.label(simulation.booster_model)])
			if node.boosted:
				var authoritative := simulation.get_incoming_complexity(node.id)
				var spec := simulation.relief_spec()
				var relief := ComplexityRelief.relief_amount(authoritative, spec) if not spec.is_empty() else 0
				lines.append("Authoritative complexity %d  ·  Effective %d  ·  Relief %d" % [authoritative, maxi(authoritative - relief, 0), relief])
			lines.append("Base %s/sec%s" % [_rate(base), "  ·  booster +%d%%" % roundi(LineBalance.BOOSTER_BONUS * 100.0) if node.boosted else ""])
			lines.append("Complexity ×%.3f  ·  Effective %s/sec" % [ComplexityModel.processing_modifier(simulation.get_incoming_complexity(node.id), simulation.processing_mode), _rate(simulation.get_effective_capacity(node.id))])
			lines.append("Input %s/sec  ·  Utilization %d%%" % [_rate(simulation.telemetry.arrival_rate(node.id)), roundi(simulation.get_utilization(node.id) * 100.0)])
			lines.append("Queue %s/%d  ·  %s" % [NumberFormat.compact(simulation.get_waiting_total(node.id)), LineBalance.BUFFER_CAPACITY, _status_text(simulation.get_status(node.id))])
		NodeDefinitions.Type.OUTPUT:
			lines.append("Input %s/sec" % _rate(simulation.telemetry.arrival_rate(node.id)))
			lines.append("Acceptance %s/sec" % _rate(simulation.get_capacity(node.id)))
			lines.append("Revenue %s/sec  ·  total %s" % [_rate(simulation.telemetry.payout_rate(node.id)), NumberFormat.money(simulation.get_revenue(node.id))])
			var payout_complexity := simulation.get_last_payout_complexity(node.id)
			lines.append("Last payout complexity %s" % ("none yet" if payout_complexity < 0 else str(payout_complexity)))
			lines.append("Status %s" % _status_text(simulation.get_status(node.id)))
		NodeDefinitions.Type.SPLITTER:
			lines.append("Input %s/sec" % _rate(simulation.telemetry.arrival_rate(node.id)))
			var branches: Array = manager.graph.get_outgoing(node.id)
			for index in range(branches.size()):
				lines.append("Branch %s → #%d  %s/sec" % ["A" if index == 0 else "B", branches[index], _rate(simulation.telemetry.edge_rate(node.id, branches[index]))])
			lines.append("Routing: alternating, odd units alternate")
			lines.append("Queue %s/%d  ·  %s" % [NumberFormat.compact(simulation.get_waiting_total(node.id)), LineBalance.BUFFER_CAPACITY, _status_text(simulation.get_status(node.id))])
		NodeDefinitions.Type.MERGER:
			for from_id in manager.graph.get_incoming(node.id):
				lines.append("Input #%d  %s/sec" % [from_id, _rate(simulation.telemetry.edge_rate(from_id, node.id))])
			lines.append("Output %s/sec  ·  capacity %s/sec" % [_rate(simulation.telemetry.processed_rate(node.id)), _rate(simulation.get_capacity(node.id))])
			lines.append("Queue %s/%d  ·  %s" % [NumberFormat.compact(simulation.get_waiting_total(node.id)), LineBalance.BUFFER_CAPACITY, _status_text(simulation.get_status(node.id))])
		NodeDefinitions.Type.BOOSTER:
			lines.append("Model %s  ·  Coverage %s" % [BoosterModel.label(simulation.booster_model), _coverage_text(simulation.booster_model)])
			lines.append("Capacity +%d%%  ·  Complexity Relief %s" % [roundi(LineBalance.BOOSTER_BONUS * 100.0), _relief_text(simulation.booster_model)])
			var targets := manager.get_boost_targets(node.id)
			if targets.is_empty():
				lines.append("Affected: nothing yet. Place beside a Processor.")
			else:
				var names: Array[String] = []
				for target in targets.slice(0, 6):
					names.append("#%d" % target)
				var more := "" if targets.size() <= 6 else "  +%d more" % (targets.size() - 6)
				lines.append("Affected %d Processor%s: %s%s" % [targets.size(), "" if targets.size() == 1 else "s", ", ".join(PackedStringArray(names)), more])

	return "\n".join(PackedStringArray(lines))


func _rate(value: float) -> String:
	return "%.1f" % value


func _coverage_text(mode: int) -> String:
	match mode:
		BoosterModel.Mode.CHAIN_B, BoosterModel.Mode.CHAIN_C:
			return "Graph distance %d" % BoosterModel.GRAPH_REACH
		BoosterModel.Mode.RADIUS_B:
			return "Manhattan radius %d" % BoosterModel.RADIUS
	return "Orthogonal neighbours"


func _relief_text(mode: int) -> String:
	match mode:
		BoosterModel.Mode.CHAIN_B, BoosterModel.Mode.RADIUS_B:
			return "%d%% · minimum %d" % [roundi(BoosterModel.RELIEF_FRACTION_B * 100.0), BoosterModel.RELIEF_MINIMUM]
		BoosterModel.Mode.CHAIN_C:
			return "%d%% · minimum %d" % [roundi(BoosterModel.RELIEF_FRACTION_C * 100.0), BoosterModel.RELIEF_MINIMUM]
	return "none"


func _status_text(status: int) -> String:
	match status:
		ProductionSimulation.Status.BOTTLENECK:
			return "BOTTLENECK"
		ProductionSimulation.Status.BLOCKED:
			return "BLOCKED (waiting on output)"
		ProductionSimulation.Status.SATURATED:
			return "BUSY"
		_:
			return "OK"
