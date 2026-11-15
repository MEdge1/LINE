class_name NodeDefinitions
extends RefCounted

# Node types and their connection limits. Indexed by Type. Costs are provisional tuning values.

enum Type { GENERATOR, PROCESSOR, OUTPUT }

const TYPE_DATA := [
	{"name": "GENERATOR", "cost": 25, "max_inputs": 0, "max_outputs": 1},
	{"name": "PROCESSOR", "cost": 50, "max_inputs": 1, "max_outputs": 1},
	{"name": "OUTPUT", "cost": 25, "max_inputs": 1, "max_outputs": 0},
]


static func get_display_name(type: int) -> String:
	return TYPE_DATA[type]["name"]


static func get_cost(type: int) -> int:
	return int(TYPE_DATA[type]["cost"])


static func get_max_inputs(type: int) -> int:
	return int(TYPE_DATA[type]["max_inputs"])


static func get_max_outputs(type: int) -> int:
	return int(TYPE_DATA[type]["max_outputs"])
