class_name StatisticsManager
extends RefCounted

# Progression and playtest statistics. Counters are exact LargeNumber values that objectives and the
# completion summary read. Rates are sampled from telemetry at the progression tick. None of this
# feeds back into the simulation.

var counters: Dictionary = {}
var highest_complexity: int = 0
var peak_revenue: LargeNumber = LargeNumber.from_int(0)
var peak_production: float = 0.0
var bottlenecks_resolved: int = 0
# Play time in seconds when each milestone was first reached, for pacing measurements.
var first_times: Dictionary = {}

var _was_bottleneck: Dictionary = {}


func counter(key: String) -> LargeNumber:
	return counters.get(key, LargeNumber.from_int(0))


func count(key: String, amount: int = 1) -> void:
	counters[key] = counter(key).add(LargeNumber.from_int(amount))


func add_units(key: String, amount: LargeNumber) -> void:
	counters[key] = counter(key).add(amount)


func note_first(key: String, play_seconds: float) -> void:
	if not first_times.has(key):
		first_times[key] = play_seconds


func record_payout(amount: LargeNumber, complexity: int, play_seconds: float) -> void:
	add_units("revenue", amount)
	highest_complexity = maxi(highest_complexity, complexity)
	note_first("first_payout", play_seconds)
	if complexity >= 1:
		note_first("first_complexity_payout", play_seconds)


func record_processed(units: int) -> void:
	add_units("processed", LargeNumber.from_int(units))


func record_built(type: int, play_seconds: float) -> void:
	count("built." + NodeDefinitions.get_display_name(type))
	note_first("built." + NodeDefinitions.get_display_name(type), play_seconds)


func record_deleted() -> void:
	count("deleted")


func record_upgrade(play_seconds: float) -> void:
	count("upgrades")
	note_first("first_upgrade", play_seconds)


func record_connection() -> void:
	count("connections")


func record_expansion(play_seconds: float) -> void:
	count("expansions")
	note_first("first_expansion", play_seconds)


# Samples peak rates and counts bottlenecks that have cleared. Called at the progression tick.
func sample(network: NetworkManager) -> void:
	var revenue := network.revenue_rate()
	if revenue > 0.0 and not is_inf(revenue):
		var rounded := LargeNumber.from_text("%.0f" % revenue)
		if rounded.compare(peak_revenue) > 0:
			peak_revenue = rounded
	peak_production = maxf(peak_production, network.produced_rate())

	for id in network.graph.get_node_ids():
		var bottleneck := network.is_bottleneck(id)
		if _was_bottleneck.get(id, false) and not bottleneck:
			bottlenecks_resolved += 1
		_was_bottleneck[id] = bottleneck
