class_name BoosterCoverage
extends RefCounted

# Which Processors a Booster covers under a BoosterModel. Pure functions over graph and layout state, so every
# editing action recomputes the same answer. Non-stacking: a Processor covered by several Boosters belongs to the
# lowest-numbered Booster, and only that owner's effect applies.


# Processors covered by one Booster, sorted by id. Empty for anything that is not a Booster.
static func targets(graph: NetworkGraph, layout: WorkspaceLayout, booster_id: int, mode: int) -> Array:
	if not graph.has_node(booster_id) or graph.get_node(booster_id).type != NodeDefinitions.Type.BOOSTER:
		return []
	var covered := {}
	if mode == BoosterModel.Mode.RADIUS_B:
		_add_radius(graph, layout, booster_id, covered)
	else:
		var entries := _adjacent_processors(graph, layout, booster_id)
		if BoosterModel.uses_graph_coverage(mode):
			_add_graph_reach(graph, entries, covered)
		else:
			for entry in entries:
				covered[entry] = true
	var result: Array = covered.keys()
	result.sort()
	return result


# Owner per covered Processor: processor id -> lowest Booster id covering it. Covers every Processor exactly once.
static func owners(graph: NetworkGraph, layout: WorkspaceLayout, mode: int) -> Dictionary:
	var result := {}
	var booster_ids := []
	for id in graph.get_node_ids():
		if graph.get_node(id).type == NodeDefinitions.Type.BOOSTER:
			booster_ids.append(id)
	booster_ids.sort()
	for booster_id in booster_ids:
		for processor in targets(graph, layout, booster_id, mode):
			if not result.has(processor):
				result[processor] = booster_id
	return result


static func _adjacent_processors(graph: NetworkGraph, layout: WorkspaceLayout, booster_id: int) -> Array:
	var found := []
	for neighbour in layout.get_neighbor_ids(booster_id):
		if NodeDefinitions.is_boostable(graph.get_node(neighbour).type):
			found.append(neighbour)
	found.sort()
	return found


# Breadth-first walk over every connection (both directions, routing nodes included as hops) up to GRAPH_REACH hops
# from each entry. Only Processors are recorded. Nothing outside the connected network is reached.
static func _add_graph_reach(graph: NetworkGraph, entries: Array, covered: Dictionary) -> void:
	for entry in entries:
		var best := {entry: 0}
		var frontier := [entry]
		for hop in range(BoosterModel.GRAPH_REACH):
			var next_frontier := []
			for id in frontier:
				for neighbour in graph.get_outgoing(id) + graph.get_incoming(id):
					if not best.has(neighbour):
						best[neighbour] = hop + 1
						next_frontier.append(neighbour)
			frontier = next_frontier
		for id in best:
			if NodeDefinitions.is_boostable(graph.get_node(id).type):
				covered[id] = true


static func _add_radius(graph: NetworkGraph, layout: WorkspaceLayout, booster_id: int, covered: Dictionary) -> void:
	var origin: Vector2i = layout.get_node_cell(booster_id)
	for id in graph.get_node_ids():
		if not NodeDefinitions.is_boostable(graph.get_node(id).type):
			continue
		var cell: Vector2i = layout.get_node_cell(id)
		var distance := absi(cell.x - origin.x) + absi(cell.y - origin.y)
		if distance > 0 and distance <= BoosterModel.RADIUS:
			covered[id] = true
