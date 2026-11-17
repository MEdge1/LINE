class_name BalanceExperimentConfig
extends RefCounted

# Test-only candidate parameters for the balance harness. Production values stay in LineBalance and
# NodeDefinitions. The only simulation hook is ComplexityModel.cost_per_level, set while a run is active.
# Processor value stays at LineBalance.PROCESSOR_MULTIPLIER (×2) and is never swept.

var complexity_k: float
var processor_cost_growth: float
# 0 keeps the live hyperbolic complexity model. A positive base switches to exponential work.
var work_base: float


func _init(k: float = LineBalance.COMPLEXITY_COST_PER_LEVEL, growth: float = 1.0, base: float = 0.0) -> void:
	complexity_k = k
	processor_cost_growth = growth
	work_base = base


func apply() -> void:
	ComplexityModel.cost_per_level = complexity_k
	ComplexityModel.work_base = work_base


func complexity_model() -> String:
	return "exponential_work" if work_base > 0.0 else "hyperbolic_live"


static func restore_production() -> void:
	ComplexityModel.cost_per_level = LineBalance.COMPLEXITY_COST_PER_LEVEL
	ComplexityModel.work_base = 0.0


# Cost of the nth Processor bought (1-based): base × growth^(n-1), rounded to whole dollars.
func processor_cost(index: int) -> int:
	var base := NodeDefinitions.get_cost(NodeDefinitions.Type.PROCESSOR)
	return int(round(base * pow(processor_cost_growth, index - 1)))


func processors_cost(count: int) -> int:
	var total := 0
	for index in range(1, count + 1):
		total += processor_cost(index)
	return total
