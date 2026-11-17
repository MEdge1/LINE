class_name BoosterModel
extends RefCounted

# Development Booster coverage model. The processing rule (LIVE or EXP 1.10) is separate and lives in ProcessingBalance.
#
#   CONTROL    orthogonally adjacent Processors, +25% capacity, no complexity relief (the current playable Booster)
#   CHAIN_B    graph walk up to 2 hops from each entry Processor, +25% capacity, relief max(2, floor(c x 0.20))
#   CHAIN_C    same coverage as CHAIN_B, relief max(2, floor(c x 0.25))
#   RADIUS_B   every Processor with Manhattan grid distance 1-2 from the Booster, +25%, relief max(2, floor(c x 0.20))
#
# Relief changes processing difficulty only. Batch complexity, value, and Output payouts are never changed.

enum Mode { CONTROL, CHAIN_B, CHAIN_C, RADIUS_B }

const DEFAULT_MODE := Mode.CONTROL
const GRAPH_REACH := 2
const RADIUS := 2
const RELIEF_MINIMUM := 2
const RELIEF_FRACTION_B := 0.20
const RELIEF_FRACTION_C := 0.25

const _SAVE_NAMES := {
	Mode.CONTROL: "CONTROL",
	Mode.CHAIN_B: "CHAIN_B",
	Mode.CHAIN_C: "CHAIN_C",
	Mode.RADIUS_B: "RADIUS_B",
}
const _LABELS := {
	Mode.CONTROL: "CONTROL",
	Mode.CHAIN_B: "CHAIN B",
	Mode.CHAIN_C: "CHAIN C",
	Mode.RADIUS_B: "RADIUS B",
}


static func all_modes() -> Array:
	return [Mode.CONTROL, Mode.CHAIN_B, Mode.CHAIN_C, Mode.RADIUS_B]


static func save_name(mode: int) -> String:
	return _SAVE_NAMES.get(mode, _SAVE_NAMES[DEFAULT_MODE])


static func label(mode: int) -> String:
	return _LABELS.get(mode, _LABELS[DEFAULT_MODE])


# Unknown or missing names fall back to the default, so an old or damaged save never blocks loading.
static func mode_from_save_name(name: Variant, fallback: int = DEFAULT_MODE) -> int:
	if typeof(name) != TYPE_STRING:
		return fallback
	for mode in _SAVE_NAMES:
		if _SAVE_NAMES[mode] == name:
			return mode
	return fallback


# Relief spec consumed by ComplexityRelief.effective(). Empty means no relief.
static func relief_spec(mode: int) -> Dictionary:
	match mode:
		Mode.CHAIN_B, Mode.RADIUS_B:
			return {"kind": "minimum_plus", "minimum": RELIEF_MINIMUM, "fraction": RELIEF_FRACTION_B, "stacks": true}
		Mode.CHAIN_C:
			return {"kind": "minimum_plus", "minimum": RELIEF_MINIMUM, "fraction": RELIEF_FRACTION_C, "stacks": true}
	return {}


static func uses_graph_coverage(mode: int) -> bool:
	return mode == Mode.CHAIN_B or mode == Mode.CHAIN_C
