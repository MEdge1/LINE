class_name RateWindow
extends RefCounted

# Rolling per-second rate over LineBalance.RATE_WINDOW_SECONDS, built from fixed time buckets.
# Depends only on the simulation clock, so results are deterministic.

const BUCKET_COUNT := 16

var _totals := PackedFloat64Array()
var _indices := PackedInt64Array()
var _started_at := -1.0


func _init() -> void:
	_totals.resize(BUCKET_COUNT)
	_totals.fill(0.0)
	_indices.resize(BUCKET_COUNT)
	_indices.fill(-1)


func add(amount: float, now: float) -> void:
	if _started_at < 0.0:
		_started_at = now
	var index := floori(now / LineBalance.RATE_BUCKET_SECONDS)
	var slot := posmod(index, BUCKET_COUNT)
	if _indices[slot] != index:
		_indices[slot] = index
		_totals[slot] = 0.0
	_totals[slot] += amount


# Divides by the span actually observed, so a new measurement is not read as low until the window fills.
func rate(now: float) -> float:
	if _started_at < 0.0:
		return 0.0
	var current := floori(now / LineBalance.RATE_BUCKET_SECONDS)
	var sum := 0.0
	for slot in range(BUCKET_COUNT):
		if _indices[slot] >= 0 and current - _indices[slot] < BUCKET_COUNT:
			sum += _totals[slot]
	var span := clampf(now - _started_at, LineBalance.RATE_BUCKET_SECONDS, LineBalance.RATE_WINDOW_SECONDS)
	return sum / span
