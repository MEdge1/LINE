class_name NetworkManager
extends RefCounted

# Single entry point for network changes. Keeps the graph, grid layout, and production simulation
# consistent. Booster influence is derived from grid adjacency after every layout change, so a
# moved or deleted Booster or Processor never leaves a stale bonus behind.

signal payout_received(amount: LargeNumber, output_id: int, complexity: int)
signal units_processed(node_id: int, count: int)
signal node_constructed(id: int, type: int)
signal node_deleted(id: int, type: int)
signal node_moved(id: int)
signal connection_created(from_id: int, to_id: int)
signal connection_removed(from_id: int, to_id: int)
signal node_upgraded(id: int, level: int)

enum PlacementResult { OK, OUT_OF_BOUNDS, CELL_LOCKED, CELL_OCCUPIED, TECHNOLOGY_LOCKED, INSUFFICIENT_FUNDS, UNKNOWN_NODE }

var graph := NetworkGraph.new()
var layout := WorkspaceLayout.new()
var simulation: ProductionSimulation
# Build validation queries this. Defaults to unrestricted sandbox state; live games assign a real one.
var progression: ProgressionManager = ProgressionManager.sandbox()


func _init() -> void:
	simulation = ProductionSimulation.new(graph)
	simulation.payout_received.connect(payout_received.emit)
	simulation.units_processed.connect(units_processed.emit)


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
	if not progression.is_cell_unlocked(cell):
		return PlacementResult.CELL_LOCKED
	if not layout.is_cell_free(cell):
		return PlacementResult.CELL_OCCUPIED
	if not progression.is_type_unlocked(type):
		return PlacementResult.TECHNOLOGY_LOCKED
	if not simulation.spend(LargeNumber.from_int(NodeDefinitions.get_cost(type))):
		return PlacementResult.INSUFFICIENT_FUNDS

	var id := graph.add_node(type)
	layout.place(id, cell)
	_refresh_boosts()
	node_constructed.emit(id, type)
	return PlacementResult.OK


func move_node(id: int, cell: Vector2i) -> PlacementResult:
	if not graph.has_node(id):
		return PlacementResult.UNKNOWN_NODE
	if not layout.contains_cell(cell):
		return PlacementResult.OUT_OF_BOUNDS
	if not progression.is_cell_unlocked(cell):
		return PlacementResult.CELL_LOCKED

	var occupant := layout.get_node_at(cell)
	if occupant != 0 and occupant != id:
		return PlacementResult.CELL_OCCUPIED

	layout.move(id, cell)
	_refresh_boosts()
	node_moved.emit(id)
	return PlacementResult.OK


func connect_nodes(from_id: int, to_id: int) -> NetworkGraph.Rejection:
	var rejection := graph.connect_nodes(from_id, to_id)
	if rejection == NetworkGraph.Rejection.NONE:
		_refresh_boosts()
		connection_created.emit(from_id, to_id)
	return rejection


# Returns the quantity of in-flight resources moved back to the source, or null if no such edge exists.
func disconnect_nodes(from_id: int, to_id: int) -> LargeNumber:
	if not graph.disconnect_nodes(from_id, to_id):
		return null
	_refresh_boosts()
	connection_removed.emit(from_id, to_id)
	return simulation.return_edge_to_source(from_id, to_id)


func delete_node(id: int) -> LargeNumber:
	if not graph.has_node(id):
		return LargeNumber.from_int(0)

	var type: int = graph.get_node(id).type
	var refund := int(floor(NodeDefinitions.get_cost(type) * LineBalance.DELETE_REFUND_RATIO))
	simulation.drop_node_state(id)
	graph.remove_node(id)
	layout.remove(id)
	_refresh_boosts()
	simulation.add_money(LargeNumber.from_int(refund))
	node_deleted.emit(id, type)
	return LargeNumber.from_int(refund)


func get_upgrade_cost(id: int) -> LargeNumber:
	return simulation.get_upgrade_cost(id)


func is_at_max_level(id: int) -> bool:
	return simulation.is_at_max_level(id)


func upgrade_node(id: int) -> bool:
	if not simulation.upgrade_generator(id):
		return false
	node_upgraded.emit(id, graph.get_node(id).level)
	return true


# Restores one node from a validated save. Call finish_restore() after all nodes and connections.
func restore_node(id: int, type: int, cell: Vector2i, level: int) -> void:
	graph.restore_node(id, type, level)
	layout.place(id, cell)


func restore_connection(from_id: int, to_id: int) -> NetworkGraph.Rejection:
	return graph.connect_nodes(from_id, to_id)


func finish_restore(next_node_id: int) -> void:
	graph.restore_next_id(next_node_id)
	_refresh_boosts()


# Live queries used by objectives and telemetry. They read authoritative state or sampled telemetry only.
func revenue_rate() -> float:
	return simulation.telemetry.network_payout_rate()


func produced_rate() -> float:
	var produced := 0.0
	for id in graph.get_node_ids():
		if graph.get_node(id).type == NodeDefinitions.Type.GENERATOR:
			produced += simulation.telemetry.produced_rate(id)
	return produced


# Completed units per second, from the rate at which every Output accepts units.
func completed_rate() -> float:
	var completed := 0.0
	for id in graph.get_node_ids():
		if graph.get_node(id).type == NodeDefinitions.Type.OUTPUT:
			completed += simulation.telemetry.processed_rate(id)
	return completed


func is_bottleneck(id: int) -> bool:
	return simulation.get_status(id) == ProductionSimulation.Status.BOTTLENECK


func has_bottleneck() -> bool:
	for id in graph.get_node_ids():
		if is_bottleneck(id):
			return true
	return false


func boosted_processor_count() -> int:
	var count := 0
	for id in graph.get_node_ids():
		var node := graph.get_node(id)
		if node.type == NodeDefinitions.Type.PROCESSOR and node.boosted:
			count += 1
	return count


func has_connection_between(from_type: int, to_type: int) -> bool:
	for connection in graph.get_connections():
		if graph.get_node(connection.x).type == from_type and graph.get_node(connection.y).type == to_type:
			return true
	return false


# Processors covered by a Booster under the selected model. Empty for any other node.
func get_boost_targets(booster_id: int) -> Array:
	return BoosterCoverage.targets(graph, layout, booster_id, simulation.booster_model)


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


# Recomputes the boost state of every node from the current grid, connections, and Booster model.
# Boosters do not stack: each Processor has at most one owner, and only that owner's effect applies.
func _refresh_boosts() -> void:
	for id in graph.get_node_ids():
		graph.get_node(id).boosted = false
		graph.get_node(id).boost_owner = 0
	var owners := BoosterCoverage.owners(graph, layout, simulation.booster_model)
	for processor in owners:
		graph.get_node(processor).boosted = true
		graph.get_node(processor).boost_owner = owners[processor]


# Switches the Booster coverage model on the running network. Boost state is recomputed, then each Processor's
# current unit keeps its progress fraction under the new work requirement (see ProductionSimulation).
func set_booster_model(mode: int) -> void:
	if mode == simulation.booster_model:
		return
	simulation.change_booster_model(mode, Callable(self, "_refresh_boosts"))
