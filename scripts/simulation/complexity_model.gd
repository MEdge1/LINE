class_name ComplexityModel
extends RefCounted

# Product Complexity processing cost. Complexity is authoritative per batch and only Processors
# raise it. This model turns incoming complexity into processing speed. It never changes value.
#
#   LIVE_HYPERBOLIC:            processing_modifier(c) = 1 / (1 + COMPLEXITY_COST_PER_LEVEL * c)
#   EXPONENTIAL_CANDIDATE_1:    processing_modifier(c) = 1 / (CANDIDATE_1_WORK_BASE ^ c)
#
# Effective Processor capacity = base capacity * booster modifier * processing_modifier(incoming complexity).
# The booster is applied first, then the complexity modifier. Both are multiplicative.


# Live value by default. The balance harness (tests/balance) is the only code that changes these, and restores them.
static var cost_per_level: float = LineBalance.COMPLEXITY_COST_PER_LEVEL
# 0 disables the harness override. A positive value takes precedence over the mode (test-only): modifier = 1 / base^c.
static var work_base: float = 0.0


static func processing_modifier(complexity: int, mode: int = ProcessingBalance.Mode.LIVE_HYPERBOLIC) -> float:
	var level := maxi(complexity, 0)
	if work_base > 0.0:
		return 1.0 / pow(work_base, level)
	if mode == ProcessingBalance.Mode.EXPONENTIAL_CANDIDATE_1:
		return 1.0 / pow(ProcessingBalance.CANDIDATE_1_WORK_BASE, level)
	return 1.0 / (1.0 + cost_per_level * level)


# Seconds a Processor needs to work through one unit of the given complexity.
static func unit_cost_seconds(capacity: float, complexity: int, mode: int = ProcessingBalance.Mode.LIVE_HYPERBOLIC) -> float:
	return 1.0 / (capacity * processing_modifier(complexity, mode))
