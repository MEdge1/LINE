class_name BalanceProgress
extends RefCounted

# Console and checkpoint progress for long balance runs. Output is throttled to every PRINT_EVERY simulations so
# reporting never measurably slows the sweep. The checkpoint is replaced atomically, so readers never see a partial file.

const PRINT_EVERY := 25

var checkpoint_path: String
var total_simulations: int
var growths: Array
var completed := 0
var rows := 0
var invalid := 0
var phase := "simulation"
var generator_level := 0
var complexity_k := 0.0
var work_base := 0.0
var _started_msec := 0


func _init(path: String, total: int, growth_values: Array) -> void:
	checkpoint_path = path
	total_simulations = total
	growths = growth_values
	_started_msec = Time.get_ticks_msec()
	_write()


func advance(sim: Dictionary, rows_added: int) -> void:
	completed += 1
	rows += rows_added
	generator_level = int(sim["generator_level"])
	complexity_k = float(sim["complexity_k"])
	work_base = float(sim.get("work_base", 0.0))
	for window in sim["windows"]:
		if not window["conserved"]:
			invalid += 1
			break
	if completed % PRINT_EVERY == 0 or completed == total_simulations:
		_write()
		print(status_line())


func finish() -> void:
	phase = "complete"
	_write()
	print(status_line())


func percent() -> float:
	return 100.0 * completed / maxf(total_simulations, 1)


func elapsed_seconds() -> float:
	return (Time.get_ticks_msec() - _started_msec) / 1000.0


# Linear estimate from the average time per completed simulation. Unknown (-1) before the first one finishes.
static func estimate_remaining(elapsed: float, done: int, total: int) -> float:
	if done <= 0:
		return -1.0
	return elapsed / done * maxi(total - done, 0)


func status_line() -> String:
	var remaining := estimate_remaining(elapsed_seconds(), completed, total_simulations)
	var eta := "unknown" if remaining < 0.0 else "%.0fs" % remaining
	return "PROGRESS %s %d/%d (%.1f%%) gen=%d k=%.2f work_base=%.2f growths=%s rows=%d invalid=%d elapsed=%.0fs eta=%s" % [
		phase, completed, total_simulations, percent(), generator_level, complexity_k, work_base, str(growths),
		rows, invalid, elapsed_seconds(), eta,
	]


func _write() -> void:
	var elapsed := elapsed_seconds()
	var data := {
		"phase": phase,
		"complete": phase == "complete",
		"completed_simulations": completed,
		"total_simulations": total_simulations,
		"percent": snappedf(percent(), 0.01),
		"generator_level": generator_level,
		"complexity_k": complexity_k,
		"work_base": work_base,
		"processor_cost_growths": growths,
		"elapsed_seconds": snappedf(elapsed, 0.1),
		"estimated_remaining_seconds": snappedf(estimate_remaining(elapsed, completed, total_simulations), 0.1),
		"rows": rows,
		"invalid_runs": invalid,
	}
	var temporary := checkpoint_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(checkpoint_path))
