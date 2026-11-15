class_name LineBalance
extends RefCounted

# Provisional Milestone 1 tuning values. Keep all balance numbers here.

const START_MONEY := 0

const GENERATOR_BASE_RATE := 1.0
const GENERATOR_RATE_PER_LEVEL := 0.25
# Cost to go from level N to N + 1 is GENERATOR_UPGRADE_COST_PER_LEVEL * N.
const GENERATOR_UPGRADE_COST_PER_LEVEL := 10

const UNIT_START_VALUE := 1
const PROCESSOR_MULTIPLIER := 2

# Seconds a unit takes to travel each connection.
const TRAVEL_DURATION := 1.25

const NODE_HIT_RADIUS := 72.0
