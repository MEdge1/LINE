class_name BalanceTopologies
extends RefCounted

# Parameterised topology templates built through the real NetworkManager, so placement, graph validation,
# buffers, and Booster adjacency are production behaviour. Construction costs are computed separately by
# BalanceExperimentConfig; the simulation never reads them.

const BUILD_MONEY := 1000000000
const COUNT_KEYS := {
	NodeDefinitions.Type.GENERATOR: "generators",
	NodeDefinitions.Type.PROCESSOR: "processors",
	NodeDefinitions.Type.OUTPUT: "outputs",
	NodeDefinitions.Type.SPLITTER: "splitters",
	NodeDefinitions.Type.MERGER: "mergers",
	NodeDefinitions.Type.BOOSTER: "boosters",
}


# A spec is {family, branches, boosted}. One branch means a single chain; several branches mean a
# Splitter fans out to them and a Merger rejoins them. Boosted adds a Booster beside each Processor.
static func sequential(depth: int, boosted: bool = false) -> Dictionary:
	return {"family": "boosted_sequential" if boosted else "sequential", "branches": [depth], "boosted": boosted}


static func parallel(branches: Array, boosted: bool = false) -> Dictionary:
	return {"family": "hybrid" if boosted else "parallel", "branches": branches, "boosted": boosted}


static func label(spec: Dictionary) -> String:
	var parts := PackedStringArray()
	for length in spec["branches"]:
		parts.append(str(length))
	return "%s[%s]" % [spec["family"], "+".join(parts)]


static func build(spec: Dictionary, generator_level: int) -> NetworkManager:
	var manager := NetworkManager.new()
	manager.simulation.money = LargeNumber.from_int(BUILD_MONEY)
	var cells := StrategyScenarios.all_cells()
	var cursor: int = 0

	var generator: int = _place(manager, NodeDefinitions.Type.GENERATOR, cells[cursor])
	cursor += 1
	var branches: Array = spec["branches"]
	var parallel_layout: bool = branches.size() > 1
	var entry: int = generator
	if parallel_layout:
		var splitter: int = _place(manager, NodeDefinitions.Type.SPLITTER, cells[cursor])
		cursor += 1
		manager.connect_nodes(generator, splitter)
		entry = splitter

	var tails: Array = []
	for length in branches:
		var previous: int = entry
		for _step in range(int(length)):
			var processor: int = _place(manager, NodeDefinitions.Type.PROCESSOR, cells[cursor])
			cursor += 1
			manager.connect_nodes(previous, processor)
			previous = processor
		tails.append(previous)

	var join: int = tails[0]
	if parallel_layout:
		join = _place(manager, NodeDefinitions.Type.MERGER, cells[cursor])
		cursor += 1
		for tail in tails:
			manager.connect_nodes(tail, join)
	var output: int = _place(manager, NodeDefinitions.Type.OUTPUT, cells[cursor])
	manager.connect_nodes(join, output)

	if spec["boosted"]:
		_add_boosters(manager)
	manager.graph.get_node(generator).level = generator_level
	return manager


# Counts by node type plus the cells the network uses. Every node occupies one cell, so cells = nodes.
static func describe(manager: NetworkManager, spec: Dictionary) -> Dictionary:
	var counts := {"generators": 0, "processors": 0, "outputs": 0, "splitters": 0, "mergers": 0, "boosters": 0}
	for id in manager.graph.get_node_ids():
		var key: String = COUNT_KEYS[manager.graph.get_node(id).type]
		counts[key] += 1
	var longest := 0
	for length in spec["branches"]:
		longest = maxi(longest, int(length))
	counts["cells_used"] = manager.graph.get_node_ids().size()
	counts["max_depth"] = longest
	counts["family"] = spec["family"]
	counts["label"] = label(spec)
	return counts


# Total construction cost. Processors use the growth model; every other node uses its production cost.
static func construction_cost(counts: Dictionary, config: BalanceExperimentConfig) -> int:
	return int(counts["generators"]) * NodeDefinitions.get_cost(NodeDefinitions.Type.GENERATOR) \
		+ int(counts["outputs"]) * NodeDefinitions.get_cost(NodeDefinitions.Type.OUTPUT) \
		+ int(counts["splitters"]) * NodeDefinitions.get_cost(NodeDefinitions.Type.SPLITTER) \
		+ int(counts["mergers"]) * NodeDefinitions.get_cost(NodeDefinitions.Type.MERGER) \
		+ int(counts["boosters"]) * NodeDefinitions.get_cost(NodeDefinitions.Type.BOOSTER) \
		+ config.processors_cost(int(counts["processors"]))


static func ids_of_type(manager: NetworkManager, type: int) -> Array:
	var ids: Array = []
	for id in manager.graph.get_node_ids():
		if manager.graph.get_node(id).type == type:
			ids.append(id)
	return ids


static func output_id(manager: NetworkManager) -> int:
	var ids := ids_of_type(manager, NodeDefinitions.Type.OUTPUT)
	return int(ids[0]) if not ids.is_empty() else 0


static func _place(manager: NetworkManager, type: int, cell: Vector2i) -> int:
	var result := manager.construct(type, cell)
	if result != NetworkManager.PlacementResult.OK:
		push_error("Topology placement failed for %s at %s: %d" % [NodeDefinitions.get_display_name(type), cell, result])
		return 0
	return manager.layout.get_node_at(cell)


# Boosters go in the first free orthogonal cell beside each Processor, in id order. Cells decide the count.
static func _add_boosters(manager: NetworkManager) -> void:
	for processor in ids_of_type(manager, NodeDefinitions.Type.PROCESSOR):
		var cell: Vector2i = manager.layout.get_node_cell(processor)
		for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
			var neighbour: Vector2i = cell + offset
			if manager.layout.contains_cell(neighbour) and manager.layout.is_cell_free(neighbour):
				manager.construct(NodeDefinitions.Type.BOOSTER, neighbour)
				break
