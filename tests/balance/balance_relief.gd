extends SceneTree

# Booster-relief experiment, core scope. Test-only; live play never sets ComplexityRelief.active.
#
# Each worker runs its share of the units in a separate Godot process:
#   --script res://tests/balance/balance_relief.gd -- shard=0 shards=5
# Then one merge process combines the shard files:
#   --script res://tests/balance/balance_relief.gd -- merge=1 shards=5
#
# Unit = (control or relief model) × depth × Generator level. Each unit runs once to 900 s, which gives the 300 s and
# 900 s windows. The single Booster sits beside the deepest Processor, where complexity is highest.
# Every run uses the Candidate 1 work base (1.10) so relief is compared against the exponential work model.

const OUTPUT_DIR := "user://balance_results"
const SHARD_DIR := "user://balance_results/relief_shards"
const RESULTS_CSV := "user://balance_results/booster_relief_results.csv"
const SUMMARY_JSON := "user://balance_results/booster_relief_summary.json"
const DEPTHS := [8, 15, 22, 30]
const GENERATORS := [5, 10, 15]
const WINDOWS := [300.0, 900.0]
const SECONDS := 900.0
const WORK_BASE := 1.10
const CONTROL_ID := "CONTROL"

const CSV_COLUMNS := [
	"model", "kind", "depth", "generator_level", "window_seconds",
	"steady_revenue_per_sec", "revenue_per_sec", "completed_per_sec", "steady_completed_per_sec",
	"payouts", "time_first_payout", "time_first_c5", "time_first_c10", "max_complexity",
	"peak_queue", "queue_growth_per_sec", "bottlenecks_end", "conserved",
]


func _init() -> void:
	var options := _options(OS.get_cmdline_user_args())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHARD_DIR))
	var shards := int(options.get("shards", "5"))
	if options.has("merge"):
		quit(_merge(shards))
		return
	quit(_run_shard(int(options.get("shard", "0")), shards))


func _units() -> Array:
	var models: Array = [{"id": CONTROL_ID, "kind": "live_booster_control", "spec": {}}]
	for model in ComplexityRelief.models():
		models.append({"id": model["id"], "kind": String(model["spec"]["kind"]), "spec": model["spec"]})
	var units: Array = []
	for model in models:
		for depth in DEPTHS:
			for generator_level in GENERATORS:
				units.append({"model": model, "depth": depth, "generator_level": generator_level})
	return units


func _run_shard(shard: int, shards: int) -> int:
	var rows: Array = []
	var started := Time.get_ticks_msec()
	var units := _units()
	var done := 0
	for index in range(units.size()):
		if index % shards != shard:
			continue
		var unit: Dictionary = units[index]
		rows.append_array(_run_unit(unit))
		done += 1
		print("RELIEF shard=%d unit=%d/%d model=%s depth=%d gen=%d" % [shard, index + 1, units.size(), unit["model"]["id"], unit["depth"], unit["generator_level"]])

	var deterministic := true
	if shard == 0:
		deterministic = _determinism_check()
	ComplexityRelief.active = {}
	BalanceExperimentConfig.restore_production()

	var file := FileAccess.open("%s/shard_%02d.json" % [SHARD_DIR, shard], FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"shard": shard,
		"shards": shards,
		"units": done,
		"rows": rows,
		"wall_ms": Time.get_ticks_msec() - started,
		"determinism_passed": deterministic,
		"production_restored": ComplexityModel.work_base == 0.0 and ComplexityModel.cost_per_level == LineBalance.COMPLEXITY_COST_PER_LEVEL,
	}, "\t"))
	file.close()
	print("RELIEF shard=%d done units=%d rows=%d determinism=%s" % [shard, done, rows.size(), str(deterministic)])
	return 0 if deterministic else 1


func _run_unit(unit: Dictionary) -> Array:
	var model: Dictionary = unit["model"]
	ComplexityRelief.active = model["spec"]
	var config := BalanceExperimentConfig.new(0.10, 1.0, WORK_BASE)
	var spec := BalanceTopologies.sequential(int(unit["depth"]), false)
	var manager := _with_booster(int(unit["depth"]), int(unit["generator_level"]))
	var result := BalanceRunner.measure_built(manager, spec, config, int(unit["generator_level"]), SECONDS)
	ComplexityRelief.active = {}

	var rows: Array = []
	for window in result["windows"]:
		var seconds := float(window["seconds"])
		if not _is_reported_window(seconds):
			continue
		rows.append({
			"model": model["id"],
			"kind": model["kind"],
			"depth": int(unit["depth"]),
			"generator_level": int(unit["generator_level"]),
			"window_seconds": seconds,
			"steady_revenue_per_sec": float(window["steady_revenue_per_sec"]),
			"revenue_per_sec": float(window["revenue_per_sec"]),
			"completed_per_sec": float(window["completed_per_sec"]),
			"steady_completed_per_sec": float(window["steady_completed_per_sec"]),
			"payouts": int(window["payouts"]),
			"time_first_payout": float(window["time_first_payout"]),
			"time_first_c5": float(window["time_first_c5"]),
			"time_first_c10": float(window["time_first_c10"]),
			"max_complexity": int(window["max_complexity"]),
			"peak_queue": float(window["peak_queue"]),
			"queue_growth_per_sec": float(window["queue_growth_per_sec"]),
			"bottlenecks_end": int(window["bottlenecks_end"]),
			"conserved": bool(window["conserved"]),
		})
	return rows


func _is_reported_window(seconds: float) -> bool:
	for reported in WINDOWS:
		if absf(seconds - reported) < 0.01:
			return true
	return false


# One sequential chain with a single Booster beside the deepest Processor.
func _with_booster(depth: int, generator_level: int) -> NetworkManager:
	var manager := BalanceTopologies.build(BalanceTopologies.sequential(depth), generator_level)
	var processors := BalanceTopologies.ids_of_type(manager, NodeDefinitions.Type.PROCESSOR)
	var target: int = processors[-1]
	var cell: Vector2i = manager.layout.get_node_cell(target)
	for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
		var neighbour: Vector2i = cell + offset
		if manager.layout.contains_cell(neighbour) and manager.layout.is_cell_free(neighbour):
			manager.construct(NodeDefinitions.Type.BOOSTER, neighbour)
			break
	return manager


# Same run twice must match exactly (full 900 s). Checks that the relief path adds no nondeterminism.
func _determinism_check() -> bool:
	var first := _run_unit({"model": {"id": "B2", "kind": "percent", "spec": {"kind": "percent", "fraction": 0.20}}, "depth": 8, "generator_level": 5})
	var second := _run_unit({"model": {"id": "B2", "kind": "percent", "spec": {"kind": "percent", "fraction": 0.20}}, "depth": 8, "generator_level": 5})
	ComplexityRelief.active = {}
	return var_to_str(first) == var_to_str(second)


func _merge(shards: int) -> int:
	var rows: Array = []
	var invalid := 0
	var determinism := false
	var restored := true
	var units := 0
	for shard in range(shards):
		var path := "%s/shard_%02d.json" % [SHARD_DIR, shard]
		if not FileAccess.file_exists(path):
			push_error("MISSING shard file %s" % path)
			return 1
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		rows.append_array(data["rows"])
		units += int(data["units"])
		if shard == 0:
			determinism = bool(data["determinism_passed"])
		restored = restored and bool(data["production_restored"])

	var expected_units := _units().size()
	var expected_rows := expected_units * WINDOWS.size()
	var control := {}
	for row in rows:
		if not bool(row["conserved"]):
			invalid += 1
		if row["model"] == CONTROL_ID:
			control[_key(row)] = float(row["steady_revenue_per_sec"])
	var stats := _model_stats(rows, control)
	var ok := units == expected_units and rows.size() == expected_rows and invalid == 0 and determinism and restored

	var file := FileAccess.open(RESULTS_CSV, FileAccess.WRITE)
	file.store_string(_csv(rows))
	file.close()
	var summary := {
		"units": units,
		"expected_units": expected_units,
		"rows": rows.size(),
		"expected_rows": expected_rows,
		"invalid_rows": invalid,
		"determinism_passed": determinism,
		"production_restored": restored,
		"passed": ok,
		"models_vs_control_900s": stats,
	}
	var summary_file := FileAccess.open(SUMMARY_JSON, FileAccess.WRITE)
	summary_file.store_string(JSON.stringify(summary, "\t"))
	summary_file.close()
	print("RELIEF merged units=%d/%d rows=%d/%d invalid=%d determinism=%s passed=%s" % [units, expected_units, rows.size(), expected_rows, invalid, str(determinism), str(ok)])
	print("RELIEF output %s" % ProjectSettings.globalize_path(RESULTS_CSV))
	return 0 if ok else 1


func _key(row: Dictionary) -> String:
	return "%d|%d|%s" % [int(row["depth"]), int(row["generator_level"]), str(row["window_seconds"])]


# Mean and worst steady revenue ratio against the live control at 900 s, plus how many grid cells beat the control.
func _model_stats(rows: Array, control: Dictionary) -> Dictionary:
	var stats := {}
	for row in rows:
		if row["model"] == CONTROL_ID or float(row["window_seconds"]) != SECONDS:
			continue
		var base: float = control.get(_key(row), 0.0)
		if base <= 0.0:
			continue
		var ratio := float(row["steady_revenue_per_sec"]) / base
		var entry: Dictionary = stats.get(row["model"], {"cells": 0, "wins": 0, "sum": 0.0, "worst": INF})
		entry["cells"] = int(entry["cells"]) + 1
		entry["wins"] = int(entry["wins"]) + (1 if ratio > 1.0 else 0)
		entry["sum"] = float(entry["sum"]) + ratio
		entry["worst"] = minf(float(entry["worst"]), ratio)
		stats[row["model"]] = entry
	for model_id in stats:
		var entry: Dictionary = stats[model_id]
		entry["mean_ratio"] = float(entry["sum"]) / maxf(int(entry["cells"]), 1)
		entry.erase("sum")
	return stats


func _csv(rows: Array) -> String:
	var lines := PackedStringArray([",".join(PackedStringArray(CSV_COLUMNS))])
	for row in rows:
		var values := PackedStringArray()
		for column in CSV_COLUMNS:
			values.append(str(row[column]))
		lines.append(",".join(values))
	return "\n".join(lines) + "\n"


func _options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
		else:
			options[parts[0]] = "1"
	return options
