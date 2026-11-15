class_name NodeDefinitions
extends RefCounted

# Node types, construction costs, connection ports, and processing capacity. Costs and
# capacities are provisional tuning values. Capacity is resource units per second.
# Generator output comes from its level (see ProductionSimulation.get_generator_rate).

enum Type { GENERATOR, PROCESSOR, OUTPUT, SPLITTER, MERGER, BOOSTER }

const TYPE_DATA := [
	{"name": "GENERATOR", "cost": 25, "max_inputs": 0, "max_outputs": 1, "capacity": 0.0, "boostable": false},
	{"name": "PROCESSOR", "cost": 50, "max_inputs": 1, "max_outputs": 1, "capacity": 4.0, "boostable": true},
	{"name": "OUTPUT", "cost": 25, "max_inputs": 1, "max_outputs": 0, "capacity": 6.0, "boostable": false},
	{"name": "SPLITTER", "cost": 40, "max_inputs": 1, "max_outputs": 2, "capacity": 8.0, "boostable": false},
	{"name": "MERGER", "cost": 40, "max_inputs": 2, "max_outputs": 1, "capacity": 8.0, "boostable": false},
	{"name": "BOOSTER", "cost": 30, "max_inputs": 0, "max_outputs": 0, "capacity": 0.0, "boostable": false},
]


static func get_display_name(type: int) -> String:
	return TYPE_DATA[type]["name"]


static func get_cost(type: int) -> int:
	return int(TYPE_DATA[type]["cost"])


static func get_max_inputs(type: int) -> int:
	return int(TYPE_DATA[type]["max_inputs"])


static func get_max_outputs(type: int) -> int:
	return int(TYPE_DATA[type]["max_outputs"])


static func get_capacity(type: int) -> float:
	return float(TYPE_DATA[type]["capacity"])


static func is_boostable(type: int) -> bool:
	return bool(TYPE_DATA[type]["boostable"])
