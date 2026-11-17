class_name ComplexityRelief
extends RefCounted

# Experimental Booster relief. A relieved Processor works at the reduced complexity, so its speed uses the
# reduced value. Authoritative complexity (batch value, payout, output) is never changed.
# Live play never sets `active`, so this path is only reached by the balance harness.
#
# Relief kinds (effective = max(0, c - relief), never negative):
#   {"kind": "flat", "amount": n}                            relief = n
#   {"kind": "percent", "fraction": f}                       relief = floor(c × f)
#   {"kind": "minimum_plus", "minimum": m, "fraction": f}    relief = max(m, floor(c × f))
#
# Rounding: floor(x + ROUNDING_EPSILON), so 20 × 0.15 = 3 is not floored to 2 by float error.

const ROUNDING_EPSILON := 1e-9

# Test-only. Empty means no relief, which is the live behaviour.
# A spec with "stacks": true keeps the +25% Booster bonus (Phase 1B). Without it, the relief replaces the bonus (Phase 1).
static var active: Dictionary = {}


static func is_active() -> bool:
	return not active.is_empty()


static func replaces_bonus() -> bool:
	return is_active() and not bool(active.get("stacks", false))


static func relief_amount(complexity: int, spec: Dictionary) -> int:
	var c := maxi(complexity, 0)
	match String(spec.get("kind", "")):
		"flat":
			return maxi(int(spec["amount"]), 0)
		"percent":
			return floori(c * float(spec["fraction"]) + ROUNDING_EPSILON)
		"minimum_plus":
			return maxi(int(spec["minimum"]), floori(c * float(spec["fraction"]) + ROUNDING_EPSILON))
	return 0


static func effective(complexity: int, spec: Dictionary) -> int:
	var c := maxi(complexity, 0)
	return maxi(c - relief_amount(c, spec), 0)


# Complexity used for a Processor's speed. Only a boosted Processor is relieved, and only while a model is active.
static func work_complexity(complexity: int, boosted_processor: bool) -> int:
	if not is_active() or not boosted_processor:
		return complexity
	return effective(complexity, active)


# Phase 1B: the live +25% bonus stacks with the relief. Control has no relief, so 1.25 ÷ 1.10^c.
static func phase1b_models() -> Array:
	return [
		{"id": "CONTROL", "spec": {"kind": "none", "stacks": true}},
		{"id": "A", "spec": {"kind": "minimum_plus", "minimum": 1, "fraction": 0.15, "stacks": true}},
		{"id": "B", "spec": {"kind": "minimum_plus", "minimum": 2, "fraction": 0.20, "stacks": true}},
		{"id": "C", "spec": {"kind": "minimum_plus", "minimum": 2, "fraction": 0.25, "stacks": true}},
		{"id": "D", "spec": {"kind": "minimum_plus", "minimum": 3, "fraction": 0.30, "stacks": true}},
	]


# Phase 1 candidate relief models. Values are the harness's grid; confirm before reading results.
static func models() -> Array:
	return [
		{"id": "A1", "spec": {"kind": "flat", "amount": 1}},
		{"id": "A2", "spec": {"kind": "flat", "amount": 2}},
		{"id": "A3", "spec": {"kind": "flat", "amount": 3}},
		{"id": "A4", "spec": {"kind": "flat", "amount": 5}},
		{"id": "A5", "spec": {"kind": "flat", "amount": 8}},
		{"id": "B1", "spec": {"kind": "percent", "fraction": 0.10}},
		{"id": "B2", "spec": {"kind": "percent", "fraction": 0.20}},
		{"id": "B3", "spec": {"kind": "percent", "fraction": 0.30}},
		{"id": "B4", "spec": {"kind": "percent", "fraction": 0.40}},
		{"id": "B5", "spec": {"kind": "percent", "fraction": 0.50}},
		{"id": "C1", "spec": {"kind": "minimum_plus", "minimum": 1, "fraction": 0.10}},
		{"id": "C2", "spec": {"kind": "minimum_plus", "minimum": 1, "fraction": 0.20}},
		{"id": "C3", "spec": {"kind": "minimum_plus", "minimum": 2, "fraction": 0.15}},
		{"id": "C4", "spec": {"kind": "minimum_plus", "minimum": 2, "fraction": 0.25}},
		{"id": "C5", "spec": {"kind": "minimum_plus", "minimum": 3, "fraction": 0.30}},
	]
