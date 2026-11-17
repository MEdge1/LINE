class_name BalanceAnalysis
extends RefCounted

# Pure analysis over runner results: feasibility, candidate rows, winners, marginal and Booster tables, and
# CSV text. Construction cost affects only feasibility and cost metrics. It never reaches the simulation.

const DURATIONS := [60, 300]
const OBJECTIVES := [
	"revenue_per_sec", "total_revenue_value", "completed_per_sec", "revenue_per_cost",
	"total_revenue_per_cost", "revenue_per_cell", "throughput_per_cost", "throughput_per_cell",
]
const COLUMNS := [
	"experiment_id", "family", "topology", "complexity_k", "processor_cost_model", "processor_cost_growth",
	"generator_level", "budget", "cell_limit", "duration", "processor_count", "splitter_count", "merger_count",
	"booster_count", "output_count", "construction_cost", "unused_budget", "cells_used", "unused_cells", "max_depth",
	"max_complexity", "time_first_payout", "time_first_c5", "time_first_c10", "revenue_total", "completed_total",
	"revenue_per_sec", "completed_per_sec", "steady_revenue_per_sec", "steady_completed_per_sec", "revenue_per_cost",
	"total_revenue_per_cost", "revenue_per_cell", "throughput_per_cost", "throughput_per_cell", "average_queue",
	"peak_queue", "queue_pressure", "average_bottlenecks", "peak_bottlenecks", "bottlenecks_end", "queue_end",
	"min_processor_capacity", "complexity_model", "work_base", "work_multiplier_at_max_depth",
	"deepest_effective_capacity", "seconds_per_unit_at_deepest_stage", "payouts", "average_payout_interval",
	"chain_fill_time", "queue_growth_per_sec", "normalized_queue_pressure", "limit_class", "first_payout_flag",
	"first_payout_very_slow_flag", "deep_stage_slow_flag", "queue_saturated_flag", "bottleneck_heavy_flag",
	"throughput_collapse_flag", "produced", "paid", "held", "lost", "conserved",
]


static func feasible(counts: Dictionary, cost: int, budget: int, cell_limit: int) -> bool:
	return cost <= budget and int(counts["cells_used"]) <= cell_limit


# One row per feasible candidate, per scenario (growth, budget, cell limit), per window (checkpoint).
static func rows(sims: Array, growths: Array, budgets: Array, cell_limits: Array) -> Array:
	var out: Array = []
	for sim in sims:
		for growth in growths:
			var config := BalanceExperimentConfig.new(sim["complexity_k"], growth, float(sim.get("work_base", 0.0)))
			var cost := BalanceTopologies.construction_cost(sim, config)
			for budget in budgets:
				for cell_limit in cell_limits:
					if not feasible(sim, cost, budget, cell_limit):
						continue
					for window in sim["windows"]:
						out.append(row(sim, window, config, cost, budget, cell_limit, int(round(float(window["seconds"])))))
	return out


static func row(sim: Dictionary, window: Dictionary, config: BalanceExperimentConfig, cost: int, budget: int, cell_limit: int, duration: int) -> Dictionary:
	var cells: int = sim["cells_used"]
	var revenue_per_sec: float = window["revenue_per_sec"]
	var completed_per_sec: float = window["completed_per_sec"]
	var total_revenue: float = LargeNumber.from_text(window["revenue_total"]).to_float()
	var mode := "flat" if config.processor_cost_growth == 1.0 else "compound"
	var flags := _flags(sim, window)
	return {
		"experiment_id": "%s|k%.2f|g%.2f|L%d|b%d|c%d|d%d" % [sim["label"], config.complexity_k, config.processor_cost_growth, sim["generator_level"], budget, cell_limit, duration],
		"family": sim["family"],
		"topology": sim["label"],
		"complexity_k": config.complexity_k,
		"processor_cost_model": mode,
		"processor_cost_growth": config.processor_cost_growth,
		"generator_level": sim["generator_level"],
		"budget": budget,
		"cell_limit": cell_limit,
		"duration": duration,
		"processor_count": sim["processors"],
		"splitter_count": sim["splitters"],
		"merger_count": sim["mergers"],
		"booster_count": sim["boosters"],
		"output_count": sim["outputs"],
		"construction_cost": cost,
		"unused_budget": budget - cost,
		"cells_used": cells,
		"unused_cells": cell_limit - cells,
		"max_depth": sim["max_depth"],
		"max_complexity": window["max_complexity"],
		"time_first_payout": window["time_first_payout"],
		"time_first_c5": window["time_first_c5"],
		"time_first_c10": window["time_first_c10"],
		"revenue_total": window["revenue_total"],
		"completed_total": window["completed_total"],
		"revenue_per_sec": revenue_per_sec,
		"completed_per_sec": completed_per_sec,
		"steady_revenue_per_sec": window["steady_revenue_per_sec"],
		"steady_completed_per_sec": window["steady_completed_per_sec"],
		"revenue_per_cost": revenue_per_sec / cost,
		"total_revenue_value": total_revenue,
		"total_revenue_per_cost": total_revenue / cost,
		"revenue_per_cell": revenue_per_sec / cells,
		"throughput_per_cost": completed_per_sec / cost,
		"throughput_per_cell": completed_per_sec / cells,
		"average_queue": window["average_queue"],
		"peak_queue": window["peak_queue"],
		"queue_pressure": window["average_queue"] / (LineBalance.BUFFER_CAPACITY * cells),
		"average_bottlenecks": window["average_bottlenecks"],
		"peak_bottlenecks": window["peak_bottlenecks"],
		"bottlenecks_end": window["bottlenecks_end"],
		"queue_end": window["queue_end"],
		"min_processor_capacity": sim["min_processor_capacity"],
		"complexity_model": config.complexity_model(),
		"work_base": config.work_base,
		"work_multiplier_at_max_depth": sim["work_multiplier_at_max_depth"],
		"deepest_effective_capacity": sim["deepest_effective_capacity"],
		"seconds_per_unit_at_deepest_stage": sim["seconds_per_unit_at_deepest_stage"],
		"payouts": window["payouts"],
		"average_payout_interval": window["average_payout_interval"],
		"chain_fill_time": window["time_first_payout"],
		"queue_growth_per_sec": window["queue_growth_per_sec"],
		"normalized_queue_pressure": flags["normalized_queue_pressure"],
		"limit_class": flags["limit_class"],
		"first_payout_flag": flags["first_payout_flag"],
		"first_payout_very_slow_flag": flags["first_payout_very_slow_flag"],
		"deep_stage_slow_flag": flags["deep_stage_slow_flag"],
		"queue_saturated_flag": flags["queue_saturated_flag"],
		"bottleneck_heavy_flag": flags["bottleneck_heavy_flag"],
		"throughput_collapse_flag": flags["throughput_collapse_flag"],
		"produced": window["produced"],
		"paid": window["paid"],
		"held": window["held"],
		"lost": window["lost"],
		"conserved": window["conserved"],
	}


# Practical-playability labels and the limiting resource. Labels are reported; they never remove a run.
# Normalized queue pressure = average queued units / (buffer capacity × Processors). The Output (capacity 6) never
# binds at Generator 15 (4.5/s), so the limit class is GENERATOR, BUFFER, PROCESSOR, or NONE.
static func _flags(sim: Dictionary, window: Dictionary) -> Dictionary:
	var processors := maxi(int(sim["processors"]), 1)
	var normalized := float(window["average_queue"]) / (LineBalance.BUFFER_CAPACITY * processors)
	var generator_rate := LineBalance.GENERATOR_BASE_RATE + LineBalance.GENERATOR_RATE_PER_LEVEL * (int(sim["generator_level"]) - 1)
	var first := float(window["time_first_payout"])
	var per_unit := float(sim["seconds_per_unit_at_deepest_stage"])
	var completed := float(window["completed_per_sec"])
	var queue_saturated := normalized > 0.8
	var bottleneck_heavy := int(sim["processors"]) > 0 and float(window["average_bottlenecks"]) > int(sim["processors"]) / 2.0
	var limit_class := "NONE"
	if completed >= 0.9 * generator_rate:
		limit_class = "GENERATOR"
	elif queue_saturated:
		limit_class = "BUFFER"
	elif float(window["average_bottlenecks"]) >= 1.0:
		limit_class = "PROCESSOR"
	return {
		"normalized_queue_pressure": normalized,
		"limit_class": limit_class,
		"first_payout_flag": first < 0.0 or first > 30.0,
		"first_payout_very_slow_flag": first < 0.0 or first > 60.0,
		"deep_stage_slow_flag": per_unit > 10.0,
		"queue_saturated_flag": queue_saturated,
		"bottleneck_heavy_flag": bottleneck_heavy,
		"throughput_collapse_flag": completed < 0.1 * generator_rate,
	}


# Winner per objective for each scenario. Non-conserved rows never compete. Ties keep the first row.
static func tallies(rows_in: Array) -> Dictionary:
	var groups: Dictionary = {}
	for row_data in rows_in:
		if not row_data["conserved"]:
			continue
		var key := "%d|%.2f|%.2f|%d|%d|%d" % [row_data["generator_level"], row_data["complexity_k"], row_data["processor_cost_growth"], row_data["budget"], row_data["cell_limit"], row_data["duration"]]
		if not groups.has(key):
			groups[key] = {"scenario": row_data, "best": {}}
		var best: Dictionary = groups[key]["best"]
		for objective in OBJECTIVES:
			if not best.has(objective) or float(row_data[objective]) > float(best[objective]["value"]):
				best[objective] = {"value": float(row_data[objective]), "family": row_data["family"], "topology": row_data["topology"]}

	var buckets: Dictionary = {}
	var baseline: Array = []
	for key in groups:
		var scenario: Dictionary = groups[key]["scenario"]
		var best: Dictionary = groups[key]["best"]
		var bucket := "gen%d|%ds|%s" % [scenario["generator_level"], scenario["duration"], phase(scenario["budget"], scenario["cell_limit"])]
		if not buckets.has(bucket):
			buckets[bucket] = {}
		for objective in OBJECTIVES:
			var winner: Dictionary = best[objective]
			if not buckets[bucket].has(objective):
				buckets[bucket][objective] = {}
			var family_counts: Dictionary = buckets[bucket][objective]
			family_counts[winner["family"]] = int(family_counts.get(winner["family"], 0)) + 1
			if scenario["complexity_k"] == 0.10 and scenario["processor_cost_growth"] == 1.0 and scenario["generator_level"] == 15 and scenario["duration"] == 300:
				baseline.append({"budget": scenario["budget"], "cell_limit": scenario["cell_limit"], "objective": objective, "topology": winner["topology"], "value": winner["value"]})
	return {"tallies": buckets, "baseline": baseline}


static func phase(budget: int, cell_limit: int) -> String:
	if cell_limit <= 15 and budget <= 500:
		return "EARLY"
	if cell_limit >= 45 and budget >= 5000:
		return "LATE"
	return "MID"


# Change from D to D+1 sequential Processors at full window duration, with the cost of the added Processor.
static func marginal(sims: Array, growths: Array, complexity_values: Array, generator_level: int) -> Array:
	var index: Dictionary = {}
	for sim in sims:
		if sim["generator_level"] == generator_level and sim["family"] == "sequential":
			index["%.2f|%d" % [sim["complexity_k"], sim["max_depth"]]] = sim
	var table: Array = []
	for complexity in complexity_values:
		for growth in growths:
			var config := BalanceExperimentConfig.new(complexity, growth)
			for depth in range(0, 43):
				var here: Dictionary = index.get("%.2f|%d" % [complexity, depth], {})
				var next: Dictionary = index.get("%.2f|%d" % [complexity, depth + 1], {})
				if here.is_empty() or next.is_empty():
					continue
				var added_cost := config.processor_cost(depth + 1)
				var before: Dictionary = here["windows"][1]
				var after: Dictionary = next["windows"][1]
				var delta_revenue: float = float(after["revenue_per_sec"]) - float(before["revenue_per_sec"])
				var first_before: float = before["time_first_payout"]
				var first_after: float = after["time_first_payout"]
				table.append({
					"complexity_k": complexity,
					"processor_cost_growth": growth,
					"from_depth": depth,
					"added_cost": added_cost,
					"delta_revenue_per_sec": delta_revenue,
					"delta_steady_revenue_per_sec": float(after["steady_revenue_per_sec"]) - float(before["steady_revenue_per_sec"]),
					"delta_completed_per_sec": float(after["completed_per_sec"]) - float(before["completed_per_sec"]),
					"delta_total_revenue": LargeNumber.from_text(after["revenue_total"]).subtract(LargeNumber.from_text(before["revenue_total"])).to_text(),
					"revenue_per_added_dollar": delta_revenue / added_cost,
					"delta_average_queue": float(after["average_queue"]) - float(before["average_queue"]),
					"delta_average_bottlenecks": float(after["average_bottlenecks"]) - float(before["average_bottlenecks"]),
					"delta_time_first_payout": first_after - first_before if first_before >= 0.0 and first_after >= 0.0 else -1.0,
				})
	return table


# Revenue gained by boosting the same chain, per dollar of Booster cost.
static func booster_value(sims: Array, complexity_values: Array, depths: Array, generator_level: int, booster_cost: int) -> Array:
	var index: Dictionary = {}
	for sim in sims:
		if sim["generator_level"] == generator_level:
			index["%s|%.2f|%d" % [sim["family"], sim["complexity_k"], sim["max_depth"]]] = sim
	var table: Array = []
	for complexity in complexity_values:
		for depth in depths:
			var plain: Dictionary = index.get("sequential|%.2f|%d" % [complexity, depth], {})
			var boosted: Dictionary = index.get("boosted_sequential|%.2f|%d" % [complexity, depth], {})
			if plain.is_empty() or boosted.is_empty():
				continue
			var added_cost: int = int(boosted["boosters"]) * booster_cost
			var delta: float = float(boosted["windows"][1]["revenue_per_sec"]) - float(plain["windows"][1]["revenue_per_sec"])
			table.append({
				"complexity_k": complexity,
				"depth": depth,
				"boosters": boosted["boosters"],
				"added_cost": added_cost,
				"delta_revenue_per_sec": delta,
				"revenue_per_booster_dollar": delta / added_cost if added_cost > 0 else 0.0,
			})
	return table


static func csv_text(rows_in: Array) -> String:
	var lines := PackedStringArray([",".join(PackedStringArray(COLUMNS))])
	for row_data in rows_in:
		var cells := PackedStringArray()
		for column in COLUMNS:
			cells.append(_csv_value(row_data[column]))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


static func _csv_value(value: Variant) -> String:
	if value is float:
		return "%.6f" % value
	return str(value)
