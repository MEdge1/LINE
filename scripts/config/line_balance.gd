class_name LineBalance
extends RefCounted

# Provisional tuning values. Keep all balance numbers here.

const START_MONEY := 120

const GENERATOR_BASE_RATE := 1.0
const GENERATOR_RATE_PER_LEVEL := 0.25
const GENERATOR_UPGRADE_COST_PER_LEVEL := 10
# Temporary prototype safeguard. Upgrades stop here.
const GENERATOR_MAX_LEVEL := 15

const UNIT_START_VALUE := 1
const PROCESSOR_MULTIPLIER := 2
# Each complexity level of incoming resources divides a Processor's speed by (1 + this * complexity).
# Value is never affected; see ComplexityModel.
const COMPLEXITY_COST_PER_LEVEL := 0.10

# Seconds a resource batch takes to cross a connection.
const TRAVEL_DURATION := 1.25
# Batches of the same value entering one connection within this window share a batch.
const MERGE_WINDOW_SECONDS := 0.25

# Resource quantity each node's queue can hold. Measured in quantity, never in batches or particles.
const BUFFER_CAPACITY := 25
# Processing and routing budgets accumulate at most this many seconds of capacity while idle.
const BURST_SECONDS := 1.0

# Multiplier on an eligible node's capacity while it is orthogonally adjacent to a Booster.
const BOOSTER_BONUS := 0.25

# A node is SATURATED when it processes at or above this share of its capacity.
const BOTTLENECK_UTILIZATION := 0.9
# A saturated node is a BOTTLENECK when its queue holds at least this share of its buffer.
const BOTTLENECK_QUEUE_FRACTION := 0.25

# Telemetry rates are averaged over this window, built from fixed-size buckets.
const RATE_WINDOW_SECONDS := 4.0
const RATE_BUCKET_SECONDS := 0.25

const DELETE_REFUND_RATIO := 1.0
const NODE_HIT_RADIUS := 72.0
