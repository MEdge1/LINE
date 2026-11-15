class_name VisualLimits
extends RefCounted

# Presentation-only caps. They bound how many representative particles and indicators
# are drawn. The simulation is never limited by these values.

const PARTICLES_PER_CONNECTION := 12
const PARTICLES_TOTAL := 200
# Representative particles one batch can show: 1 + floor(log2(quantity)), capped here.
const PARTICLES_PER_BATCH_MAX := 8
# Batches at or above this quantity get a larger marker.
const LARGE_BATCH_QUANTITY := 32
# Trailing particles are spaced this far apart along a connection (fraction of its length).
const PARTICLE_STAGGER := 0.04
# Each batch starts at a deterministic offset this large, so neighbouring batches don't line up.
const PHASE_SPREAD := 0.05
# Visual trail behind each particle: spacing (fraction of the connection) and opacity per ghost.
const TRAIL_OFFSET := 0.035
const TRAIL_ALPHAS := [0.35, 0.15]
const WAITING_DOTS_PER_NODE := 4
const PAYOUT_INDICATORS := 6
# Representative particles on a connection at which its glow reaches full strength.
const CONNECTION_GLOW_AT := 8.0
