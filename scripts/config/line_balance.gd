class_name LineBalance
extends RefCounted

# Provisional Milestone 1 tuning values. Keep all balance numbers here.

const START_MONEY := 120

const GENERATOR_BASE_RATE := 1.0
const GENERATOR_RATE_PER_LEVEL := 0.25
# Cost to go from level N to N + 1 is GENERATOR_UPGRADE_COST_PER_LEVEL * N.
const GENERATOR_UPGRADE_COST_PER_LEVEL := 10
# Temporary prototype safeguard. Upgrades stop here.
const GENERATOR_MAX_LEVEL := 15

const UNIT_START_VALUE := 1
const PROCESSOR_MULTIPLIER := 2

# Seconds a unit takes to travel each connection.
const TRAVEL_DURATION := 1.25

# Milestone 2 temporary drain rule: a backlog held at a node with no downstream
# connection is released DRAIN_BATCH_SIZE units every DRAIN_INTERVAL seconds once a
# connection exists. Milestone 3 replaces this with throughput limits and buffers.
const DRAIN_INTERVAL := 0.5
const DRAIN_BATCH_SIZE := 8

# Fraction of a node's construction cost returned when it is deleted.
const DELETE_REFUND_RATIO := 1.0
