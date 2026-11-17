class_name NetworkGraph
extends RefCounted

# Logical network topology. Knows nothing about grid positions or drawing.

enum Rejection {
	NONE,
	MISSING_NODE,
	SELF_CONNECTION,
	BOOSTER_NOT_CONNECTABLE,
	DUPLICATE,
	SOURCE_CANNOT_SEND,
	SOURCE_OUTPUT_FULL,
	DESTINATION_CANNOT_RECEIVE,
	DESTINATION_INPUT_FULL,
	WOULD_CREATE_LOOP,
}


class NetworkNode:
	var id: int
	var type: int
	var level: int = 1
	# Set by NetworkManager from Booster coverage. Never set by the graph itself.
	var boosted: bool = false
	# Id of the Booster whose effect applies to this Processor (lowest covering id). 0 when not boosted.
	var boost_owner: int = 0

	func _init(node_id: int, node_type: int) -> void:
		id = node_id
		type = node_type


var _nodes: Dictionary = {}
var _outgoing: Dictionary = {}
var _incoming: Dictionary = {}
var _next_id: int = 1


func restore_node(id: int, type: int, level: int) -> void:
	_nodes[id] = NetworkNode.new(id, type)
	_nodes[id].level = level
	_outgoing[id] = []
	_incoming[id] = []
	_next_id = maxi(_next_id, id + 1)


func next_id() -> int:
	return _next_id


func restore_next_id(value: int) -> void:
	_next_id = maxi(_next_id, value)


func add_node(type: int) -> int:
	var id := _next_id
	_next_id += 1

	_nodes[id] = NetworkNode.new(id, type)
	_outgoing[id] = []
	_incoming[id] = []
	return id


func remove_node(id: int) -> void:
	if not has_node(id):
		return

	for to_id in _outgoing[id].duplicate():
		_incoming[to_id].erase(id)
	for from_id in _incoming[id].duplicate():
		_outgoing[from_id].erase(id)

	_outgoing.erase(id)
	_incoming.erase(id)
	_nodes.erase(id)


func has_node(id: int) -> bool:
	return _nodes.has(id)


func get_node(id: int) -> NetworkNode:
	return _nodes.get(id)


func get_node_ids() -> Array:
	return _nodes.keys()


func get_outgoing(id: int) -> Array:
	return _outgoing.get(id, [])


func get_incoming(id: int) -> Array:
	return _incoming.get(id, [])


func get_connections() -> Array[Vector2i]:
	var connections: Array[Vector2i] = []
	for from_id in _outgoing:
		for to_id in _outgoing[from_id]:
			connections.append(Vector2i(from_id, to_id))
	return connections


func has_free_output(id: int) -> bool:
	return has_node(id) and get_outgoing(id).size() < NodeDefinitions.get_max_outputs(get_node(id).type)


func validate_connection(from_id: int, to_id: int) -> Rejection:
	if not has_node(from_id) or not has_node(to_id):
		return Rejection.MISSING_NODE
	if from_id == to_id:
		return Rejection.SELF_CONNECTION
	if get_node(from_id).type == NodeDefinitions.Type.BOOSTER or get_node(to_id).type == NodeDefinitions.Type.BOOSTER:
		return Rejection.BOOSTER_NOT_CONNECTABLE
	if get_outgoing(from_id).has(to_id):
		return Rejection.DUPLICATE

	var from_type := get_node(from_id).type
	if NodeDefinitions.get_max_outputs(from_type) <= 0:
		return Rejection.SOURCE_CANNOT_SEND
	if get_outgoing(from_id).size() >= NodeDefinitions.get_max_outputs(from_type):
		return Rejection.SOURCE_OUTPUT_FULL

	var to_type := get_node(to_id).type
	if NodeDefinitions.get_max_inputs(to_type) <= 0:
		return Rejection.DESTINATION_CANNOT_RECEIVE
	if get_incoming(to_id).size() >= NodeDefinitions.get_max_inputs(to_type):
		return Rejection.DESTINATION_INPUT_FULL

	# A new edge from->to closes a loop if `from` is already reachable from `to`.
	if _reaches(to_id, from_id):
		return Rejection.WOULD_CREATE_LOOP

	return Rejection.NONE


func connect_nodes(from_id: int, to_id: int) -> Rejection:
	var rejection := validate_connection(from_id, to_id)
	if rejection != Rejection.NONE:
		return rejection

	_outgoing[from_id].append(to_id)
	_incoming[to_id].append(from_id)
	return Rejection.NONE


# Removes only the edge from_id -> to_id. Both nodes stay in place.
func disconnect_nodes(from_id: int, to_id: int) -> bool:
	if not get_outgoing(from_id).has(to_id):
		return false

	_outgoing[from_id].erase(to_id)
	_incoming[to_id].erase(from_id)
	return true


func _reaches(start_id: int, target_id: int) -> bool:
	var pending: Array = [start_id]
	var visited: Dictionary = {}

	while not pending.is_empty():
		var current: int = pending.pop_back()
		if current == target_id:
			return true
		if visited.has(current):
			continue

		visited[current] = true
		for next_id in get_outgoing(current):
			pending.append(next_id)

	return false
