class_name ProcessingBalance
extends RefCounted

# Processing-work rules for Product Complexity. Only the work formula differs between modes. Every other rule
# (value ×2, complexity +1, buffers, routing, Boosters, LargeNumber) is shared by both modes.

enum Mode { LIVE_HYPERBOLIC, EXPONENTIAL_CANDIDATE_1 }

# Candidate 1: work multiplier = 1.10 ^ incoming complexity. A development comparison, not a balance decision.
const CANDIDATE_1_WORK_BASE := 1.10

# The one place that sets the physical-playtest default. The app entry point passes it to SaveManager for new
# games and for saves written before the field existed. Automated tests and the simulation default to LIVE.
const PLAYTEST_DEFAULT_MODE := Mode.EXPONENTIAL_CANDIDATE_1

const SAVE_NAMES := {
	Mode.LIVE_HYPERBOLIC: "LIVE_HYPERBOLIC",
	Mode.EXPONENTIAL_CANDIDATE_1: "EXPONENTIAL_CANDIDATE_1",
}


static func save_name(mode: int) -> String:
	return SAVE_NAMES.get(mode, SAVE_NAMES[PLAYTEST_DEFAULT_MODE])


# Unknown or missing names fall back to the given default rather than failing the load.
static func mode_from_save_name(value: Variant, fallback: int) -> int:
	for mode in SAVE_NAMES:
		if value == SAVE_NAMES[mode]:
			return mode
	return fallback


static func short_label(mode: int) -> String:
	return "EXP 1.10" if mode == Mode.EXPONENTIAL_CANDIDATE_1 else "LIVE"
