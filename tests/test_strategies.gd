extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_strategies.gd
# Asserts that every scenario conserves resources. Prints the strategy comparison for the report.
# The comparison is measured, not tuned: no balance is adjusted to equalise the strategies.

var _failures := 0


func _init() -> void:
	var scenarios := {
		"A. Long Processor chain (43)": StrategyScenarios.build_chain(43),
		"B. Parallel 2x20 Processors": StrategyScenarios.build_parallel(20),
		"C. Parallel 2x2 Processors": StrategyScenarios.build_parallel(2),
		"D. Boosted pair": StrategyScenarios.build_boosted(),
		"E. Unboosted pair": StrategyScenarios.build_unboosted(),
		"F. Medium-depth parallel 2x8": StrategyScenarios.build_parallel(8),
	}

	print("STRATEGY label | cells | cost | processors | boosters | final complexity | value/unit | min effective cap | input/s | completed/s | revenue/s | waiting | bottlenecks | total payout | conserved")
	for label in scenarios:
		var result := StrategyScenarios.measure(scenarios[label])
		print("STRATEGY %s | %d | $%d | %d | %d | %d | %.4f | %.3f | %.2f | %.4f | %.4f | %s | %d | %s | %s" % [
			label, result["cells"], result["cost"], result["processors"], result["boosters"],
			result["final_complexity"], result["value_per_unit"], result["min_effective_capacity"],
			result["input_per_sec"], result["completed_per_sec"], result["revenue_per_sec"],
			result["waiting"], result["bottlenecks"], result["total_payout"], str(result["conserved"]),
		])
		if not result["conserved"]:
			_failures += 1
			printerr("FAIL: %s does not conserve resources" % label)

	var boosted := StrategyScenarios.measure(StrategyScenarios.build_boosted())
	var unboosted := StrategyScenarios.measure(StrategyScenarios.build_unboosted())
	if boosted["revenue_per_sec"] <= unboosted["revenue_per_sec"]:
		_failures += 1
		printerr("FAIL: the Booster should improve a bottlenecked pair")

	if _failures == 0:
		print("All strategy scenarios conserved resources.")
	else:
		printerr("%d strategy assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)
