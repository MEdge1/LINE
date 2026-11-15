class_name NetworkManager
extends RefCounted

# Single entry point for network changes. Keeps the graph, grid layout, and production simulation
# consistent. Booster influence is derived from grid adjacency after every layout change, so a
# moved or deleted Booster or Processor never leaves a stale bonus behind.

signal payout_received(amount: LargeNumber, output_id: int, complexity: int)

enum PlacementResult { OK, OUT_OF_BOUNDS, CELL_OCCUPIED, INSUFFICIENT_FUNDS, UNKNOWN_NODE }

var graph := NetworkGraph.new()
var layout := WorkspaceLayout.new()
var simulation: ProductionSimulation


func _init() -> void:
	simulation = ProductionSimulation.new(graph)
	simulation.payout_received.connect(payout_received.emit)


func step(delta: float) -> void:
	simulation.step(delta)


func can_afford(type: int) -> bool:
	return simulation.can_afford(LargeNumber.from_int(NodeDefinitions.get_cost(type)))


func is_generator(id: int) -> bool:
	return simulation.is_generator(id)


func has_free_output(id: int) -> bool:
	return graph.has_free_output(id)


func construct(type: int, cell: Vector2i) -> PlacementResult:
	if not layout.contains_cell(cell):
		return PlacementResult.OUT_OF_BOUNDS
	if not layout.is_cell_free(cell):
		return PlacementResult.CELL_OCCUPIED
	if not simulation.spend(LargeNumber.from_int(NodeDefinitions.get_cost(type))):
		return PlacementResult.INSUFFICIENT_FUNDS

	var id := graph.add_node(type)
	layout.place(id, cell)
	_refresh_boosts()
	return PlacementResult.OK


func move_node(id: int, cell: Vector2i) -> PlacementResult:
	if not graph.has_node(id):
		return PlacementResult.UNKNOWN_NODE
	if not layout.contains_cell(cell):
		return PlacementResult.OUT_OF_BOUNDS

	var occupant := layout.get_node_at(cell)
	if occupant != 0 and occupant != id:
		return PlacementResult.CELL_OCCUPIED

	layout.move(id, cell)
	_refresh_boosts()
	return PlacementResult.OK


func connect_nodes(from_id: int, to_id: int) -> NetworkGraph.Rejection:
	return graph.connect_nodes(from_id, to_id)


# Returns the quantity of in-flight resources moved back to the source queue, or null if no such edge exists.
func disconnect_nodes(from_id: int, to_id: int) -> LargeNumber:
	if not graph.disconnect_nodes(from_id, to_id):
		return null
	return simulation.return_edge_to_source(from_id, to_id)


func delete_node(id: int) -> LargeNumber:
	if not graph.has_node(id):
		return LargeNumber.from_int(0)

	var refund := int(floor(NodeDefinitions.get_cost(graph.get_node(id).type) * LineBalance.DELETE_REFUND_RATIO))
	simulation.drop_node_state(id)
	graph.remove_node(id)
	layout.remove(id)
	_refresh_boosts()
	simulation.add_money(LargeNumber.from_int(refund))
	return LargeNumber.from_int(refund)


func get_upgrade_cost(id: int) -> LargeNumber:
	return simulation.get_upgrade_cost(id)


func is_at_max_level(id: int) -> bool:
	return simulation.is_at_max_level(id)


func upgrade_node(id: int) -> bool:
	return simulation.upgrade_generator(id)


# Eligible Processors orthogonally adjacent to a Booster. Empty for any other node.
func get_boost_targets(booster_id: int) -> Array:
	var targets: Array = []
	if not graph.has_node(booster_id) or graph.get_node(booster_id).type != NodeDefinitions.Type.BOOSTER:
		return targets
	for neighbour in layout.get_neighbor_ids(booster_id):
		if NodeDefinitions.is_boostable(graph.get_node(neighbour).type):
			targets.append(neighbour)
	return targets


func get_network_summary() -> Dictionary:
	var produced := 0.0
	var waiting := LargeNumber.from_int(0)
	var bottlenecks := 0
	for id in graph.get_node_ids():
		if graph.get_node(id).type == NodeDefinitions.Type.GENERATOR:
			produced += simulation.telemetry.produced_rate(id)
		waiting = waiting.add(simulation.get_waiting_total(id))
		if simulation.get_status(id) == ProductionSimulation.Status.BOTTLENECK:
			bottlenecks += 1
	return {
		"produced_rate": produced,
		"revenue_rate": simulation.telemetry.network_payout_rate(),
		"waiting": waiting,
		"bottlenecks": bottlenecks,
	}


# Recomputes the boosted flag on every node from the current grid. Boosters do not stack:
# a Processor either receives the bonus or it does not.
func _refresh_boosts() -> void:
	for id in graph.get_node_ids():
		graph.get_node(id).boosted = false
	for id in graph.get_node_ids():
		if graph.get_node(id).type != NodeDefinitions.Type.BOOSTER:
			continue
		for target in get_boost_targets(id):
			graph.get_node(target).boosted = true
