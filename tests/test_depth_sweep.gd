extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_depth_sweep.gd
# Repeatable Processor-chain depth sweep, with and without Boosters. Prints the table for the report.
# Asserts conservation and that a Booster never reduces throughput. It does not tune the complexity curve.

const DEPTHS := [1, 2, 3, 4, 5, 8, 10, 12, 15, 20, 25, 30, 35, 40, 43]

var _failures := 0


func _init() -> void:
	print("SWEEP depth | variant | cells | boosters | final complexity | value/unit | effective cap/s | completed/s | revenue/s | queued | bottlenecks | conserved")
	for depth in DEPTHS:
		var plain := StrategyScenarios.measure(StrategyScenarios.build_chain(depth))
		var boosted := StrategyScenarios.measure(StrategyScenarios.build_chain_boosted(depth))
		_print_row(depth, "plain", plain)
		_print_row(depth, "boosted", boosted)

		if not plain["conserved"] or not boosted["conserved"]:
			_failures += 1
			printerr("FAIL: depth %d does not conserve resources" % depth)
		if boosted["completed_per_sec"] + 0.001 < plain["completed_per_sec"]:
			_failures += 1
			printerr("FAIL: depth %d is slower with a Booster than without" % depth)

	if _failures == 0:
		print("Depth sweep conserved resources and Boosters never reduced throughput.")
	else:
		printerr("%d depth sweep assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _print_row(depth: int, variant: String, result: Dictionary) -> void:
	print("SWEEP %d | %s | %d | %d | %d | %.4f | %.3f | %.4f | %.4f | %s | %d | %s" % [
		depth, variant, result["cells"], result["boosters"], result["final_complexity"],
		result["value_per_unit"], result["min_effective_capacity"], result["completed_per_sec"],
		result["revenue_per_sec"], result["waiting"], result["bottlenecks"], str(result["conserved"]),
	])
