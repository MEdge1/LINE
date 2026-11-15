class_name ComplexityVisuals
extends RefCounted

# Presentation-only tuning for Product Complexity. The simulation never reads these values.
# Every effect is bounded, so high complexity changes how a resource looks, never how many
# objects exist. Tiers are labels and colour stops only; they never change value or throughput.

# A resource uses the highest tier whose start it has reached.
const TIER_STARTS := [0, 1, 3, 6, 10, 15]
const TIER_NAMES := ["Raw", "Processed", "Refined", "Advanced", "High Complexity", "Extreme"]

# Complexity at which glow, size, and trail stop growing.
const EFFECT_CAP := 15
const GLOW_ALPHA_MIN := 0.2
const GLOW_ALPHA_MAX := 0.85
const RADIUS_SCALE_MAX := 1.3
const MAX_TRAIL_GHOSTS := 3

# Payouts below this tier keep the original green indicator.
const PAYOUT_TINT_TIER := 2
const PAYOUT_TIER_NAME_TIER := 2
const PAYOUT_SIZE_STEP := 2
const PAYOUT_GLOW_TIER := 4
const MONEY_PULSE_BASE_SCALE := 1.15
const MONEY_PULSE_STEP := 0.02
const MONEY_PULSE_MAX_SCALE := 1.25
