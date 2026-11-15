class_name ComplexityModel
extends RefCounted

# Product Complexity processing cost. Complexity is authoritative per batch and only Processors
# raise it. This model turns incoming complexity into processing speed. It never changes value.
#
#   processing_modifier(c) = 1 / (1 + COMPLEXITY_COST_PER_LEVEL * c)
#
# Effective Processor capacity = base capacity * booster modifier * processing_modifier(incoming complexity).
# The booster is applied first, then the complexity modifier. Both are multiplicative.


static func processing_modifier(complexity: int) -> float:
	return 1.0 / (1.0 + LineBalance.COMPLEXITY_COST_PER_LEVEL * maxi(complexity, 0))


# Seconds a Processor needs to work through one unit of the given complexity.
static func unit_cost_seconds(capacity: float, complexity: int) -> float:
	return 1.0 / (capacity * processing_modifier(complexity))
