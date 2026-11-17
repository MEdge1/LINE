extends SceneTree

# Booster complexity-relief, Phase 1B (analysis only, test-only hooks). Stacks relief on the live +25% Booster bonus.
#
#   run=single shard=N shards=5   one-Booster placements, baselines, depth+1 comparators, control and Models A-D
#   merge=plan                    validates single shards and writes the best one-Booster placement per model (for pairs)
#   run=pair shard=N shards=5     two-Booster runs: best one-Booster placement plus one non-overlapping Booster
#   merge=final                   validates both phases and writes the CSV, summary JSON and report (user://balance_results)
#
# Every run measures 900 s and yields 60 s, 300 s and 900 s windows. Work uses Candidate 1 (1.10).

const OUTPUT_DIR := "user://balance_results"
const SHARD_DIR := "user://balance_results/phase1b_shards"
const PLAN_JSON := "user://balance_results/phase1b_plan.json"
const RESULTS_CSV := "user://balance_results/booster_relief_phase1b_results.csv"
const SUMMARY_JSON := "user://balance_results/booster_relief_phase1b_summary.json"
const REPORT_MD := "user://balance_results/booster_relief_phase1b_report.md"
const PHASE1_CSV := "user://balance_results/booster_relief_results.csv"
const DEPTHS := [5, 8, 10, 12, 15, 20, 25, 30]
const GENERATORS := [10, 15]
const SECONDS := 900.0
const WINDOW_COUNT := 3
const WORK_BASE := 1.10
const EXHAUSTIVE_MAX_DEPTH := 15
const HEURISTIC_PROCESSORS := 6
const CONTROL_STACKS := {"kind": "none", "stacks": true}

const COLUMNS := [
	"experiment_id", "kind", "model", "generator_level", "depth", "booster_count", "cells",
	"booster_cells", "window_seconds", "construction_cost", "cells_used", "booster_cost",
	"boosted_processors", "boosted_chain_indices", "boosted_complexity", "relief_applied", "effective_complexity",
	"generic_modifier", "base_capacity", "effective_capacity", "utilization_min", "utilization_max", "utilization_avg",
	"steady_revenue_per_sec", "revenue_per_sec", "steady_completed_per_sec", "completed_per_sec",
	"revenue_total", "completed_total", "produced", "paid", "held", "lost",
	"average_queue", "peak_queue", "normalized_queue_pressure", "queue_growth_per_sec",
	"average_bottlenecks", "peak_bottlenecks", "bottlenecks_end",
	"time_first_payout", "average_payout_interval", "payouts", "conserved", "placement_is_legacy",
]


func _init() -> void:
	var options := _options(OS.get_cmdline_user_args())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHARD_DIR))
	if options.has("merge"):
		var mode := String(options["merge"])
		quit(_merge_plan() if mode == "plan" else _merge_final())
		return
	var shards := int(options.get("shards", "5"))
	var shard := int(options.get("shard", "0"))
	quit(_run_phase(String(options.get("run", "single")), shard, shards))


# ---------- candidate placement ----------

# Legal orthogonal Booster cells beside the chain's Processors. Exhaustive to depth 15; beyond that, the deepest six
# Processors (queue pressure rises along a chain, so this is a documented simplification of bottleneck ranking).
func _candidates(depth: int) -> Array:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(depth), 10)
	var processors := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)
	var start := 0 if depth <= EXHAUSTIVE_MAX_DEPTH else maxi(0, processors.size() - HEURISTIC_PROCESSORS)
	var by_key := {}
	var order: Array = []
	var legacy_cell := ""
	var deepest_cell: Vector2i = manager.layout.get_node_cell(processors[-1])
	for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
		var neighbour: Vector2i = deepest_cell + offset
		if manager.layout.contains_cell(neighbour) and manager.layout.is_cell_free(neighbour):
			legacy_cell = _cell_key(neighbour)
			break
	for index in range(start, processors.size()):
		var cell: Vector2i = manager.layout.get_node_cell(processors[index])
		for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
			var neighbour: Vector2i = cell + offset
			if not (manager.layout.contains_cell(neighbour) and manager.layout.is_cell_free(neighbour)):
				continue
			var key := _cell_key(neighbour)
			if not by_key.has(key):
				by_key[key] = {"cell": [neighbour.x, neighbour.y], "adjacent": [], "legacy": key == legacy_cell}
				order.append(key)
			if not by_key[key]["adjacent"].has(index):
				by_key[key]["adjacent"].append(index)
	var candidates: Array = []
	for key in order:
		candidates.append(by_key[key])
	return candidates


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _build(depth: int, generator_level: int, cells: Array) -> NetworkManager:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(depth), generator_level)
	for cell in cells:
		var result := manager.construct(NodeDefinitions.Type.BOOSTER, Vector2i(int(cell[0]), int(cell[1])))
		if result != NetworkManager.PlacementResult.OK:
			push_error("Booster placement failed at %s: %d" % [str(cell), result])
			return null
	return manager


# ---------- plan ----------

func _single_units() -> Array:
	var units: Array = []
	for generator_level in GENERATORS:
		for depth in DEPTHS:
			units.append({"kind": "baseline", "model": "NONE", "depth": depth, "generator_level": generator_level, "cells": [], "legacy": false})
			units.append({"kind": "depth_plus_one", "model": "NONE", "depth": depth + 1, "generator_level": generator_level, "cells": [], "legacy": false})
			var candidates := _candidates(depth)
			for model in ComplexityRelief.phase1b_models():
				for candidate in candidates:
					units.append({"kind": "single", "model": model["id"], "depth": depth, "generator_level": generator_level, "cells": [candidate["cell"]], "legacy": bool(candidate["legacy"])})
	return units


func _pair_units(plan: Dictionary) -> Array:
	var units: Array = []
	for generator_level in GENERATORS:
		for depth in DEPTHS:
			for model in ComplexityRelief.phase1b_models():
				var key := "%d|%d|%s" % [generator_level, depth, model["id"]]
				if not plan.has(key):
					continue
				var entry: Dictionary = plan[key]
				for candidate in entry["candidates"]:
					if _cell_key(Vector2i(int(candidate["cell"][0]), int(candidate["cell"][1]))) == String(entry["best_key"]):
						continue
					if _overlaps(entry["best_adjacent"], candidate["adjacent"]):
						continue
					units.append({"kind": "pair", "model": model["id"], "depth": depth, "generator_level": generator_level, "cells": [entry["best_cell"], candidate["cell"]], "legacy": false})
	return units


func _overlaps(a: Array, b: Array) -> bool:
	for value in a:
		if b.has(value):
			return true
	return false


func _unit_id(unit: Dictionary) -> String:
	var cell_key := "+".join(PackedStringArray(unit["cells"].map(func(c: Array) -> String: return "%d,%d" % [int(c[0]), int(c[1])])))
	return "P1B-%s-%s-G%d-D%d-%s" % [unit["kind"], unit["model"], unit["generator_level"], unit["depth"], cell_key]


func _spec_for(model_id: String) -> Dictionary:
	if model_id == "NONE":
		return {}
	for model in ComplexityRelief.phase1b_models():
		if model["id"] == model_id:
			return model["spec"]
	return {}


# ---------- run ----------

func _run_phase(phase: String, shard: int, shards: int) -> int:
	var units: Array = _single_units() if phase == "single" else _pair_units(_load_plan())
	var rows: Array = []
	var started := Time.get_ticks_msec()
	var mine: Array = []
	for index in range(units.size()):
		if index % shards == shard:
			mine.append(units[index])
	var deterministic := true
	if shard == 0 and phase == "single" and not mine.is_empty():
		var first_a := _run_unit(mine[0])
		var first_b := _run_unit(mine[0])
		deterministic = var_to_str(first_a) == var_to_str(first_b)
	var invalid := 0
	for position in range(mine.size()):
		var unit: Dictionary = mine[position]
		var unit_rows := _run_unit(unit)
		rows.append_array(unit_rows)
		for row in unit_rows:
			if not bool(row["conserved"]):
				invalid += 1
		_write_progress(phase, shard, shards, position + 1, mine.size(), unit, Time.get_ticks_msec() - started, invalid)
		print("P1B %s shard=%d %d/%d (%.1f%%) model=%s gen=%d depth=%d boosters=%d elapsed=%.0fs invalid=%d" % [
			phase, shard, position + 1, mine.size(), 100.0 * (position + 1) / maxi(mine.size(), 1), unit["model"],
			unit["generator_level"], unit["depth"], unit["cells"].size(), (Time.get_ticks_msec() - started) / 1000.0, invalid,
		])
	ComplexityRelief.active = {}
	BalanceExperimentConfig.restore_production()

	var file := FileAccess.open("%s/%s_shard_%02d.json" % [SHARD_DIR, phase, shard], FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"phase": phase, "shard": shard, "shards": shards, "units": mine.size(), "rows": rows,
		"invalid_rows": invalid, "wall_ms": Time.get_ticks_msec() - started,
		"determinism_passed": deterministic,
		"production_restored": ComplexityModel.work_base == 0.0 and ComplexityModel.cost_per_level == LineBalance.COMPLEXITY_COST_PER_LEVEL,
	}, "\t"))
	file.close()
	print("P1B %s shard=%d done units=%d rows=%d invalid=%d determinism=%s" % [phase, shard, mine.size(), rows.size(), invalid, str(deterministic)])
	return 0 if deterministic and invalid == 0 else 1


# Atomic: write a temporary file, then rename over the progress file. Each shard has its own file.
func _write_progress(phase: String, shard: int, shards: int, completed: int, total: int, unit: Dictionary, elapsed_ms: int, invalid: int) -> void:
	var elapsed := elapsed_ms / 1000.0
	var eta := elapsed / maxf(completed, 1) * (total - completed)
	var path := "%s/progress_%s_shard_%02d.json" % [SHARD_DIR, phase, shard]
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"phase": phase, "worker": shard, "workers": shards, "completed": completed, "total": total,
		"percent": snappedf(100.0 * completed / maxf(total, 1), 0.1), "model": unit["model"],
		"generator_level": unit["generator_level"], "depth": unit["depth"], "boosters": unit["cells"].size(),
		"elapsed_seconds": snappedf(elapsed, 0.1), "eta_seconds": snappedf(eta, 0.1), "invalid_runs": invalid,
	}, "\t"))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))


func _run_unit(unit: Dictionary) -> Array:
	var depth := int(unit["depth"])
	var generator_level := int(unit["generator_level"])
	var model_id := String(unit["model"])
	var spec := _spec_for(model_id)
	var has_booster: bool = not unit["cells"].is_empty()
	ComplexityRelief.active = spec if has_booster else {}
	var topology := BalanceTopologies.sequential(depth, false)
	var manager := _build(depth, generator_level, unit["cells"])
	var config := BalanceExperimentConfig.new(0.10, 1.0, WORK_BASE)
	var cost := BalanceTopologies.construction_cost(BalanceTopologies.describe(manager, topology), config)
	var base_cost := BalanceTopologies.construction_cost(BalanceTopologies.describe(BalanceTopologies.build(topology, generator_level), topology), config)
	var processors := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)
	var result := BalanceRunner.measure_built(manager, topology, config, generator_level, SECONDS)

	var boosted_indices: Array = []
	var boosted_complexity: Array = []
	var relief_applied: Array = []
	var effective_complexity: Array = []
	var effective_capacity: Array = []
	var base_capacity := NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR)
	for index in range(processors.size()):
		var id: int = processors[index]
		if not manager.graph.get_node(id).boosted:
			continue
		var complexity: int = manager.simulation.get_incoming_complexity(id)
		var relief: int = ComplexityRelief.relief_amount(complexity, spec) if has_booster and not spec.is_empty() else 0
		boosted_indices.append(index)
		boosted_complexity.append(complexity)
		relief_applied.append(relief)
		effective_complexity.append(maxi(complexity - relief, 0))
		effective_capacity.append(manager.simulation.get_effective_capacity(id))
	var utilisation: Array = []
	for id in processors:
		utilisation.append(manager.simulation.get_utilization(id))
	ComplexityRelief.active = {}
	BalanceExperimentConfig.restore_production()

	var rows: Array = []
	var booster_cells_key := "+".join(PackedStringArray(unit["cells"].map(func(c: Array) -> String: return "%d,%d" % [int(c[0]), int(c[1])])))
	var generic := 1.0 + LineBalance.BOOSTER_BONUS if has_booster else 1.0
	for window in result["windows"]:
		rows.append({
			"experiment_id": _unit_id(unit), "kind": unit["kind"], "model": model_id,
			"generator_level": generator_level, "depth": int(unit["depth"]),
			"booster_count": unit["cells"].size(), "cells": manager.graph.get_node_ids().size(),
			"booster_cells": booster_cells_key, "window_seconds": float(window["seconds"]),
			"construction_cost": cost, "cells_used": manager.graph.get_node_ids().size(),
			"booster_cost": cost - base_cost,
			"boosted_processors": boosted_indices.size(),
			"boosted_chain_indices": "|".join(PackedStringArray(boosted_indices.map(func(v: int) -> String: return str(v)))),
			"boosted_complexity": "|".join(PackedStringArray(boosted_complexity.map(func(v: int) -> String: return str(v)))),
			"relief_applied": "|".join(PackedStringArray(relief_applied.map(func(v: int) -> String: return str(v)))),
			"effective_complexity": "|".join(PackedStringArray(effective_complexity.map(func(v: int) -> String: return str(v)))),
			"generic_modifier": generic if boosted_indices.size() > 0 else 1.0,
			"base_capacity": base_capacity,
			"effective_capacity": "|".join(PackedStringArray(effective_capacity.map(func(v: float) -> String: return "%.6f" % v))),
			"utilization_min": _min(utilisation), "utilization_max": _max(utilisation), "utilization_avg": _avg(utilisation),
			"steady_revenue_per_sec": window["steady_revenue_per_sec"], "revenue_per_sec": window["revenue_per_sec"],
			"steady_completed_per_sec": window["steady_completed_per_sec"], "completed_per_sec": window["completed_per_sec"],
			"revenue_total": window["revenue_total"], "completed_total": window["completed_total"],
			"produced": window["produced"], "paid": window["paid"], "held": window["held"], "lost": window["lost"],
			"average_queue": window["average_queue"], "peak_queue": window["peak_queue"],
			"normalized_queue_pressure": float(window["average_queue"]) / maxf(processors.size(), 1),
			"queue_growth_per_sec": window["queue_growth_per_sec"],
			"average_bottlenecks": window["average_bottlenecks"], "peak_bottlenecks": window["peak_bottlenecks"],
			"bottlenecks_end": window["bottlenecks_end"],
			"time_first_payout": window["time_first_payout"], "average_payout_interval": window["average_payout_interval"],
			"payouts": window["payouts"], "conserved": bool(window["conserved"]),
			"placement_is_legacy": bool(unit["legacy"]),
		})
	return rows


func _min(values: Array) -> float:
	return float(values.min()) if not values.is_empty() else 0.0


func _max(values: Array) -> float:
	return float(values.max()) if not values.is_empty() else 0.0


func _avg(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total / maxf(values.size(), 1)


func _load_plan() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAN_JSON))
	return data if data is Dictionary else {}


# ---------- merge: plan ----------

func _read_shards(phase: String, shards: int) -> Array:
	var rows: Array = []
	for shard in range(shards):
		var path := "%s/%s_shard_%02d.json" % [SHARD_DIR, phase, shard]
		if not FileAccess.file_exists(path):
			push_error("MISSING %s" % path)
			return []
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		rows.append_array(data["rows"])
	return rows


func _merge_plan() -> int:
	var shards := 5
	var expected := _single_units()
	var rows := _read_shards("single", shards)
	if rows.is_empty():
		return 1
	var ids := {}
	for row in rows:
		ids[row["experiment_id"]] = ids.get(row["experiment_id"], 0) + 1
	var missing := 0
	for unit in expected:
		if not ids.has(_unit_id(unit)):
			missing += 1
	var duplicates := 0
	for key in ids:
		if int(ids[key]) != WINDOW_COUNT:
			duplicates += 1

	var plan := {}
	var best_by_key := {}
	for row in rows:
		if row["kind"] != "single" or float(row["window_seconds"]) != SECONDS:
			continue
		var key := "%d|%d|%s" % [int(row["generator_level"]), int(row["depth"]), row["model"]]
		var current: Dictionary = best_by_key.get(key, {"revenue": -1.0})
		var revenue := float(row["steady_revenue_per_sec"])
		if revenue > float(current["revenue"]):
			best_by_key[key] = {"revenue": revenue, "cell": row["booster_cells"], "row": row}
	for key in best_by_key:
		var parts: PackedStringArray = key.split("|")
		var depth := int(parts[1])
		var candidates := _candidates(depth)
		var best_cell: String = best_by_key[key]["cell"]
		var best_entry := {}
		for candidate in candidates:
			if _cell_key(Vector2i(int(candidate["cell"][0]), int(candidate["cell"][1]))) == best_cell:
				best_entry = candidate
		plan[key] = {
			"best_cell": best_entry["cell"], "best_key": best_cell, "best_adjacent": best_entry["adjacent"],
			"candidates": candidates,
		}
	var file := FileAccess.open(PLAN_JSON, FileAccess.WRITE)
	file.store_string(JSON.stringify(plan, "\t"))
	file.close()
	var ok := missing == 0 and duplicates == 0 and rows.size() == expected.size() * 3
	print("P1B plan units=%d rows=%d missing=%d duplicates=%d plan_entries=%d passed=%s" % [expected.size(), rows.size(), missing, duplicates, plan.size(), str(ok)])
	return 0 if ok else 1


# ---------- merge: final ----------

func _merge_final() -> int:
	var singles := _read_shards("single", 5)
	var pairs := _read_shards("pair", 5)
	if singles.is_empty() or pairs.is_empty():
		return 1
	var all_rows := singles + pairs
	var expected_ids := {}
	for unit in _single_units():
		expected_ids[_unit_id(unit)] = true
	for unit in _pair_units(_load_plan()):
		expected_ids[_unit_id(unit)] = true
	var seen := {}
	var duplicates := 0
	for row in all_rows:
		if seen.has(row["experiment_id"] + str(row["window_seconds"])):
			duplicates += 1
		seen[row["experiment_id"] + str(row["window_seconds"])] = true
	var missing := 0
	for id in expected_ids:
		if not _has_id(all_rows, id):
			missing += 1
	var invalid := 0
	for row in all_rows:
		if not bool(row["conserved"]):
			invalid += 1
	var deterministic := true
	var restored := true
	for phase in ["single", "pair"]:
		for shard in range(5):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s_shard_%02d.json" % [SHARD_DIR, phase, shard]))
			if phase == "single" and shard == 0:
				deterministic = bool(data["determinism_passed"])
			restored = restored and bool(data["production_restored"])

	var legacy := _legacy_validation(all_rows)
	var summary := _summarise(singles)
	var passed: bool = missing == 0 and duplicates == 0 and invalid == 0 and deterministic and restored and legacy["matches"] and duplicates == 0 and invalid == 0 and deterministic and restored and legacy["matches"]
	var file := FileAccess.open(RESULTS_CSV, FileAccess.WRITE)
	file.store_string(_csv(all_rows))
	file.close()
	var out := {
		"experiment_ids": expected_ids.size(), "rows": all_rows.size(), "missing_experiments": missing,
		"duplicate_rows": duplicates, "invalid_rows": invalid, "determinism_passed": deterministic,
		"production_restored": restored, "control_validation": legacy, "passed": passed, "summary": summary,
	}
	var summary_file := FileAccess.open(SUMMARY_JSON, FileAccess.WRITE)
	summary_file.store_string(JSON.stringify(out, "\t"))
	summary_file.close()
	var report := FileAccess.open(REPORT_MD, FileAccess.WRITE)
	report.store_string(_report(out, singles, pairs))
	report.close()
	print("P1B merged experiments=%d rows=%d missing=%d duplicates=%d invalid=%d determinism=%s control_matches=%s passed=%s" % [
		expected_ids.size(), all_rows.size(), missing, duplicates, invalid, str(deterministic), str(legacy["matches"]), str(passed)])
	return 0 if passed else 1


func _has_id(rows: Array, id: String) -> bool:
	for row in rows:
		if row["experiment_id"] == id:
			return true
	return false


# The Phase 1B control at the deepest-first legacy placement must reproduce the Phase 1 live control exactly.
func _legacy_validation(rows: Array) -> Dictionary:
	var phase1 := _phase1_control_rows()
	var compared := 0
	var mismatches := 0
	for row in rows:
		if row["model"] != "CONTROL" or row["kind"] != "single" or not bool(row["placement_is_legacy"]):
			continue
		if float(row["window_seconds"]) != SECONDS:
			continue
		var key := "%d|%d" % [int(row["generator_level"]), int(row["depth"])]
		if not phase1.has(key):
			continue
		compared += 1
		if absf(float(row["steady_revenue_per_sec"]) - float(phase1[key])) > 1e-9:
			mismatches += 1
	return {"compared": compared, "mismatches": mismatches, "matches": compared > 0 and mismatches == 0}


func _phase1_control_rows() -> Dictionary:
	var found := {}
	if not FileAccess.file_exists(PHASE1_CSV):
		return found
	var lines := FileAccess.get_file_as_string(PHASE1_CSV).split("\n")
	var header := lines[0].split(",")
	var model_col := header.find("model")
	var gen_col := header.find("generator_level")
	var depth_col := header.find("depth")
	var window_col := header.find("window_seconds")
	var steady_col := header.find("steady_revenue_per_sec")
	for line in lines.slice(1):
		if line.is_empty():
			continue
		var cells := line.split(",")
		if cells[model_col] != "CONTROL" or float(cells[window_col]) != SECONDS:
			continue
		found["%d|%d" % [int(float(cells[gen_col])), int(float(cells[depth_col]))]] = float(cells[steady_col])
	return found


func _summarise(singles: Array) -> Dictionary:
	var at_end := {}
	for row in singles:
		if float(row["window_seconds"]) != SECONDS:
			continue
		at_end["%d|%d|%s|%s" % [int(row["generator_level"]), int(row["depth"]), row["kind"], row["model"]]] = row
	var models := {}
	for generator_level in GENERATORS:
		for depth in DEPTHS:
			var base: Dictionary = at_end.get("%d|%d|baseline|NONE" % [generator_level, depth], {})
			var next: Dictionary = at_end.get("%d|%d|depth_plus_one|NONE" % [generator_level, depth], {})
			for model in ComplexityRelief.phase1b_models():
				var key := "%d|%d|single|%s" % [generator_level, depth, model["id"]]
				var cells := singles.filter(func(r: Dictionary) -> bool: return r["experiment_id"].begins_with("P1B-single-%s-G%d-D%d-" % [model["id"], generator_level, depth]) and float(r["window_seconds"]) == SECONDS)
				if cells.is_empty() or base.is_empty():
					continue
				var revenues := cells.map(func(r: Dictionary) -> float: return float(r["steady_revenue_per_sec"]))
				revenues.sort()
				var best: Dictionary = cells.filter(func(r: Dictionary) -> bool: return float(r["steady_revenue_per_sec"]) == revenues[-1])[0]
				models[key] = {
					"best_revenue": revenues[-1], "median_revenue": revenues[revenues.size() / 2], "worst_revenue": revenues[0],
					"best_cells": best["booster_cells"],
					"baseline_revenue": float(base["steady_revenue_per_sec"]), "depth_plus_one_revenue": float(next["steady_revenue_per_sec"]) if not next.is_empty() else 0.0,
					"throughput_gain_pct": _pct(float(best["steady_completed_per_sec"]), float(base["steady_completed_per_sec"])),
					"revenue_gain_pct": _pct(revenues[-1], float(base["steady_revenue_per_sec"])),
					"best_to_worst_ratio": revenues[-1] / maxf(revenues[0], 1e-9),
					"booster_cost": int(best["booster_cost"]),
				}
	return models


func _pct(value: float, base: float) -> float:
	return 100.0 * (value - base) / maxf(absf(base), 1e-9)


func _report(out: Dictionary, singles: Array, pairs: Array) -> String:
	var lines := PackedStringArray()
	lines.append("# Booster Complexity-Relief Phase 1B")
	lines.append("")
	lines.append("Analysis only. Stacks relief on the live +25% Booster bonus. Live Booster, save, and Candidate 1 (1.10) unchanged. Not a playtest conclusion.")
	lines.append("")
	lines.append("## Formulas")
	lines.append("- Control: base × 1.25 ÷ 1.10^c (no relief).")
	lines.append("- Model A: relief = max(1, floor(c × 0.15)); effective = max(0, c − relief); base × 1.25 ÷ 1.10^effective.")
	lines.append("- Model B: relief = max(2, floor(c × 0.20)). Model C: max(2, floor(c × 0.25)). Model D: max(3, floor(c × 0.30)).")
	lines.append("- Relief changes processing speed only. Batch complexity, value, and Output complexity are not mutated.")
	lines.append("")
	lines.append("## Run and validation")
	lines.append("- Experiments: %d. Rows: %d. Missing: %d. Duplicates: %d." % [out["experiment_ids"], out["rows"], out["missing_experiments"], out["duplicate_rows"]])
	lines.append("- Conservation: %d invalid rows. Determinism: %s. Production restored: %s." % [out["invalid_rows"], str(out["determinism_passed"]), str(out["production_restored"])])
	var control: Dictionary = out["control_validation"]
	lines.append("- Control validation vs Phase 1 live control: %d compared, %d mismatches." % [control["compared"], control["mismatches"]])
	lines.append("- Overall: %s." % ("PASSED" if out["passed"] else "FAILED"))
	lines.append("")
	lines.append("## Best one-Booster placement by depth and model (900 s steady)")
	lines.append("| Gen | Depth | Model | Best cell | Best rev/s | Median | Worst | Rev gain vs baseline | Throughput gain | Best/worst |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|")
	var summary: Dictionary = out["summary"]
	for generator_level in GENERATORS:
		for depth in DEPTHS:
			for model in ComplexityRelief.phase1b_models():
				var key := "%d|%d|single|%s" % [generator_level, depth, model["id"]]
				if not summary.has(key):
					continue
				var s: Dictionary = summary[key]
				lines.append("| %d | %d | %s | %s | %.4f | %.4f | %.4f | %+.1f%% | %+.1f%% | %.3f |" % [
					generator_level, depth, model["id"], s["best_cells"], s["best_revenue"], s["median_revenue"], s["worst_revenue"],
					s["revenue_gain_pct"], s["throughput_gain_pct"], s["best_to_worst_ratio"],
				])
	lines.append("")
	lines.append("## Flags (computed from measured data)")
	var no_change := 0
	var irrelevant := 0
	var total := 0
	for key in summary:
		total += 1
		if float(summary[key]["throughput_gain_pct"]) < 10.0:
			no_change += 1
		if float(summary[key]["best_to_worst_ratio"]) < 1.05:
			irrelevant += 1
	lines.append("- NO_MEANINGFUL_CHANGE (throughput gain < 10%%): %d of %d model/depth/generator cases." % [no_change, total])
	lines.append("- PLACEMENT_IRRELEVANT (best within 5%% of worst): %d of %d cases." % [irrelevant, total])
	lines.append("- Two-Booster runs: %d. Compare them in the CSV against their one-Booster rows at the same depth and model." % pairs.size())
	lines.append("")
	lines.append("## Limitations")
	lines.append("- Depths 20–30 search only the deepest six Processors (queue-pressure ranking simplified to depth rank).")
	lines.append("- Utilisation min/max/avg are instantaneous values at the end of each run, not time averages.")
	lines.append("- Two-Booster runs pair the best one-Booster placement with one non-overlapping Booster only.")
	lines.append("- Cell limits (15/25/45) are recorded via cells_used; no run was excluded by a cell limit.")
	lines.append("- Feedback labels and physical playtest conclusions are not included; they need human review.")
	lines.append("")
	return "\n".join(lines)


func _csv(rows: Array) -> String:
	var lines := PackedStringArray([",".join(PackedStringArray(COLUMNS))])
	for row in rows:
		var values := PackedStringArray()
		for column in COLUMNS:
			values.append(_csv_value(row.get(column, "")))
		lines.append(",".join(values))
	return "\n".join(lines) + "\n"


func _csv_value(value: Variant) -> String:
	var text := str(value)
	if text.contains(",") or text.contains("\""):
		return "\"%s\"" % text.replace("\"", "\"\"")
	return text


func _options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		var parts := arg.split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() == 2 else "1"
	return options
