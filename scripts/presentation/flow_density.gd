class_name FlowDensity
extends RefCounted

# Visual-only mapping from authoritative quantity to representative particle count.
# The simulation never reads these values. The mapping is deterministic, monotonic,
# and bounded by VisualLimits.PARTICLES_PER_BATCH_MAX.

const LOG10_OF_2 := 0.30102999566


# 1 + floor(log2(quantity)): 1 -> 1, 2-3 -> 2, 4-7 -> 3, 8-15 -> 4, 16-31 -> 5, 32+ -> 6 and up, capped.
static func representative_count(quantity: LargeNumber) -> int:
	var log2_value := _approximate_log2(quantity)
	if log2_value < 0.0:
		return 1
	return clampi(1 + int(floor(log2_value + 1e-9)), 1, VisualLimits.PARTICLES_PER_BATCH_MAX)


static func is_large(quantity: LargeNumber) -> bool:
	return quantity.compare(LargeNumber.from_int(VisualLimits.LARGE_BATCH_QUANTITY)) >= 0


# Works for values beyond float range: uses the leading nine digits and the digit count.
static func _approximate_log2(quantity: LargeNumber) -> float:
	var text := quantity.to_text()
	var leading_digits := mini(text.length(), 9)
	var leading := text.substr(0, leading_digits).to_float()
	if leading <= 0.0:
		return -1.0

	var log10_value := float(text.length() - leading_digits) + log(leading) / log(10.0)
	return log10_value / LOG10_OF_2
