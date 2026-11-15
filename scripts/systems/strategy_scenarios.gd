class_name StrategyScenarios
extends RefCounted

# Repeatable network layouts for comparing strategies. Every scenario uses the same Generator
# level, the same 5x9 grid, and the same measurement window. Each reports its own cell count and
# construction cost, so the comparison shows tradeoffs rather than forcing equal results.

const GENERATOR_LEVEL := 15
const BUILD_BUDGET := 1000000000
const STEP := 0.05
const WARMUP_SECONDS := 120.0
const WINDOW_SECONDS := 60.0


static func all_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for column in range(WorkspaceLayout.COLUMNS):
		for row in range(WorkspaceLayout.ROWS):
			cells.append(Vector2i(column, row))
	return cells


# Generator -> N Processors -> Output, using every remaining cell for the chain.
static func build_chain(processor_count: int) -> NetworkManager:
	var manager := _new_manager()
	var cells := all_cells()
	var generator := _place(manager, NodeDefinitions.Type.GENERATOR, cells[0])
	var previous := generator
	for index in range(processor_count):
		var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, cells[1 + index])
		manager.connect_nodes(previous, processor)
		previous = processor
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, cells[1 + processor_count])
	manager.connect_nodes(previous, output)
	return manager


# The same chain with a Booster placed in the first free orthogonal cell beside each Processor, in
# chain order. Grid space decides how many Processors get one; the count is reported, not assumed.
static func build_chain_boosted(processor_count: int) -> NetworkManager:
	var manager := build_chain(processor_count)
	for processor in _ids_of_type(manager, NodeDefinitions.Type.PROCESSOR):
		var cell := manager.layout.get_node_cell(processor)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbour: Vector2i = cell + offset
			if manager.layout.contains_cell(neighbour) and manager.layout.is_cell_free(neighbour):
				_place(manager, NodeDefinitions.Type.BOOSTER, neighbour)
				break
	return manager


# Generator -> Splitter -> two branches of `branch_length` Processors -> Merger -> Output.
static func build_parallel(branch_length: int) -> NetworkManager:
	var manager := _new_manager()
	var cells := all_cells()
	var cursor := 0
	var generator := _place(manager, NodeDefinitions.Type.GENERATOR, cells[cursor])
	cursor += 1
	var splitter := _place(manager, NodeDefinitions.Type.SPLITTER, cells[cursor])
	cursor += 1
	manager.connect_nodes(generator, splitter)

	var branch_tails: Array = []
	for _branch in range(2):
		var previous := splitter
		for _step in range(branch_length):
			var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, cells[cursor])
			cursor += 1
			manager.connect_nodes(previous, processor)
			previous = processor
		branch_tails.append(previous)

	var merger := _place(manager, NodeDefinitions.Type.MERGER, cells[cursor])
	cursor += 1
	for tail in branch_tails:
		manager.connect_nodes(tail, merger)
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, cells[cursor])
	manager.connect_nodes(merger, output)
	return manager


# One Generator feeds two Processors that both sit beside a Booster. The Booster sits between them.
static func build_boosted() -> NetworkManager:
	var manager := _new_manager()
	var generator := _place(manager, NodeDefinitions.Type.GENERATOR, Vector2i(0, 4))
	var first := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 4))
	_place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 5))
	var second := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 6))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(2, 5))
	manager.connect_nodes(generator, first)
	manager.connect_nodes(first, second)
	manager.connect_nodes(second, output)
	return manager


# Same chain as build_boosted but with no Booster, for a direct comparison.
static func build_unboosted() -> NetworkManager:
	var manager := _new_manager()
	var generator := _place(manager, NodeDefinitions.Type.GENERATOR, Vector2i(0, 4))
	var first := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 4))
	var second := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 6))
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(2, 5))
	manager.connect_nodes(generator, first)
	manager.connect_nodes(first, second)
	manager.connect_nodes(second, output)
	return manager


static func total_cost(manager: NetworkManager) -> int:
	var cost := 0
	for id in manager.graph.get_node_ids():
		cost += NodeDefinitions.get_cost(manager.graph.get_node(id).type)
	return cost


# Runs the warm-up, then measures a steady window. Rates come from the measured window only.
static func measure(manager: NetworkManager) -> Dictionary:
	var simulation := manager.simulation
	for _i in range(int(WARMUP_SECONDS / STEP)):
		manager.step(STEP)

	var paid_before := simulation.paid_units.to_float()
	var money_before := simulation.money.to_float()
	var money_start := simulation.money.to_text()
	for _i in range(int(WINDOW_SECONDS / STEP)):
		manager.step(STEP)

	var completed := (simulation.paid_units.to_float() - paid_before) / WINDOW_SECONDS
	var revenue := (simulation.money.to_float() - money_before) / WINDOW_SECONDS
	var summary := manager.get_network_summary()
	var output_id := _first_of_type(manager, NodeDefinitions.Type.OUTPUT)
	return {
		"cells": manager.graph.get_node_ids().size(),
		"cost": total_cost(manager),
		"processors": _ids_of_type(manager, NodeDefinitions.Type.PROCESSOR).size(),
		"boosters": _ids_of_type(manager, NodeDefinitions.Type.BOOSTER).size(),
		"final_complexity": simulation.get_last_payout_complexity(output_id),
		"value_per_unit": _value_per_unit(simulation, money_before, paid_before),
		"min_effective_capacity": _min_effective_capacity(manager),
		"input_per_sec": summary["produced_rate"],
		"completed_per_sec": completed,
		"revenue_per_sec": revenue,
		"total_payout": simulation.get_revenue(output_id).to_text(),
		"waiting": summary["waiting"].to_text(),
		"bottlenecks": summary["bottlenecks"],
		"money_start_of_window": money_start,
		"money_total": simulation.money.to_text(),
		"conserved": _conserved(simulation),
	}


static func _value_per_unit(simulation: ProductionSimulation, money_before: float, paid_before: float) -> float:
	var paid_delta := simulation.paid_units.to_float() - paid_before
	return (simulation.money.to_float() - money_before) / paid_delta if paid_delta > 0.0 else 0.0


static func _min_effective_capacity(manager: NetworkManager) -> float:
	var lowest := -1.0
	for id in _ids_of_type(manager, NodeDefinitions.Type.PROCESSOR):
		var capacity := manager.simulation.get_effective_capacity(id)
		if lowest < 0.0 or capacity < lowest:
			lowest = capacity
	return maxf(lowest, 0.0)


static func _ids_of_type(manager: NetworkManager, type: int) -> Array:
	var ids: Array = []
	for id in manager.graph.get_node_ids():
		if manager.graph.get_node(id).type == type:
			ids.append(id)
	return ids


static func _first_of_type(manager: NetworkManager, type: int) -> int:
	var ids := _ids_of_type(manager, type)
	return ids[0] if not ids.is_empty() else 0


static func _conserved(simulation: ProductionSimulation) -> bool:
	var accounted := simulation.paid_units.add(simulation.get_held_units()).add(simulation.lost_units)
	return accounted.compare(simulation.produced_units) == 0


static func _new_manager() -> NetworkManager:
	var manager := NetworkManager.new()
	manager.simulation.money = LargeNumber.from_int(BUILD_BUDGET)
	return manager


static func _place(manager: NetworkManager, type: int, cell: Vector2i) -> int:
	manager.construct(type, cell)
	var id := manager.layout.get_node_at(cell)
	if type == NodeDefinitions.Type.GENERATOR:
		manager.graph.get_node(id).level = GENERATOR_LEVEL
	return id
