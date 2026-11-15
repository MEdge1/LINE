class_name ComplexityStyle
extends RefCounted

# Maps authoritative complexity to presentation values. Pure and deterministic: same complexity,
# same look. Nothing here is read back by the simulation.


static func tier_index(complexity: int) -> int:
	var tier := 0
	for index in range(ComplexityVisuals.TIER_STARTS.size()):
		if complexity >= ComplexityVisuals.TIER_STARTS[index]:
			tier = index
	return tier


static func tier_name(complexity: int) -> String:
	return ComplexityVisuals.TIER_NAMES[tier_index(complexity)]


# Interpolates between the tier colour stops, so neighbouring complexities look related.
static func color(complexity: int) -> Color:
	var stops: Array = ComplexityVisuals.TIER_STARTS
	var colors: Array = LinePalette.COMPLEXITY_TIER_COLORS
	var level := maxi(complexity, 0)
	var low := tier_index(level)
	if low >= stops.size() - 1:
		return colors[colors.size() - 1]

	var span: float = stops[low + 1] - stops[low]
	var t := clampf(float(level - stops[low]) / span, 0.0, 1.0)
	return (colors[low] as Color).lerp(colors[low + 1], t)


static func glow_alpha(complexity: int) -> float:
	return lerpf(ComplexityVisuals.GLOW_ALPHA_MIN, ComplexityVisuals.GLOW_ALPHA_MAX, _effect_fraction(complexity))


static func radius_scale(complexity: int) -> float:
	return lerpf(1.0, ComplexityVisuals.RADIUS_SCALE_MAX, _effect_fraction(complexity))


# One trail ghost per two tiers, never more than the trail layers the view draws.
static func trail_ghosts(complexity: int) -> int:
	return clampi(1 + tier_index(complexity) / 2, 1, ComplexityVisuals.MAX_TRAIL_GHOSTS)


static func payout_color(complexity: int) -> Color:
	if tier_index(complexity) < ComplexityVisuals.PAYOUT_TINT_TIER:
		return LinePalette.OUTPUT
	return color(complexity)


static func payout_font_size(base_size: int, complexity: int) -> int:
	return base_size + tier_index(complexity) * ComplexityVisuals.PAYOUT_SIZE_STEP


static func shows_tier_name(complexity: int) -> bool:
	return tier_index(complexity) >= ComplexityVisuals.PAYOUT_TIER_NAME_TIER


static func shows_glow(complexity: int) -> bool:
	return tier_index(complexity) >= ComplexityVisuals.PAYOUT_GLOW_TIER


static func money_pulse_scale(complexity: int) -> float:
	var scale := ComplexityVisuals.MONEY_PULSE_BASE_SCALE + tier_index(complexity) * ComplexityVisuals.MONEY_PULSE_STEP
	return minf(scale, ComplexityVisuals.MONEY_PULSE_MAX_SCALE)


static func _effect_fraction(complexity: int) -> float:
	return clampf(float(maxi(complexity, 0)) / float(ComplexityVisuals.EFFECT_CAP), 0.0, 1.0)
