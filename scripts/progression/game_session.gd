class_name GameSession
extends RefCounted

# One playable game: the network plus its progression, objectives, and statistics. This is the only
# place where authoritative events are connected to progression. Rewards are applied here, and the
# simulation and graph never know about objectives.

signal changed
signal objective_rewarded(id: String, money_text: String, research_points: int)
signal technology_unlocked(id: String)
signal workspace_expanded(index: int)
signal prototype_completed

const TICK_SECONDS := 0.1

var network: NetworkManager
var progression: ProgressionManager
var objectives: ObjectiveManager
var stats: StatisticsManager
# Seconds of simulated play. Used for pacing measurements, not for production.
var play_seconds: float = 0.0
var _tick_elapsed: float = 0.0


static func new_game(processing_mode: int = ProcessingBalance.Mode.LIVE_HYPERBOLIC, booster_model: int = BoosterModel.DEFAULT_MODE) -> GameSession:
	var progression := ProgressionManager.new_game()
	var network := NetworkManager.new()
	network.progression = progression
	network.simulation.money = LargeNumber.from_int(LineBalance.START_MONEY)
	network.simulation.processing_mode = processing_mode
	network.simulation.booster_model = booster_model
	return GameSession.new(network, progression, ObjectiveManager.new(), StatisticsManager.new())


# Development toggle. Changes only how Processors work through complexity; progress, money, and the network stay.
func set_processing_mode(mode: int) -> void:
	network.simulation.set_processing_mode(mode)
	changed.emit()


# Development toggle. Changes only Booster coverage and relief; nothing is built, removed, moved, or paid for.
func set_booster_model(mode: int) -> void:
	network.set_booster_model(mode)
	changed.emit()


func _init(network_manager: NetworkManager, progression_manager: ProgressionManager, objective_manager: ObjectiveManager, statistics: StatisticsManager) -> void:
	network = network_manager
	progression = progression_manager
	objectives = objective_manager
	stats = statistics
	network.progression = progression
	_connect_events()
	objectives.ensure_active(self)


func step(delta: float) -> void:
	network.step(delta)
	play_seconds += delta
	_tick_elapsed += delta
	if _tick_elapsed >= TICK_SECONDS:
		var elapsed := _tick_elapsed
		_tick_elapsed = 0.0
		_tick(elapsed)


func unlock_technology(id: String) -> ProgressionManager.UnlockResult:
	var result := progression.unlock_technology(id)
	if result == ProgressionManager.UnlockResult.OK:
		stats.note_first("unlock." + id, play_seconds)
		technology_unlocked.emit(id)
		changed.emit()
		objectives.evaluate(self, 0.0)
	return result


func purchase_expansion() -> bool:
	if not progression.expand(network.simulation):
		return false
	stats.record_expansion(play_seconds)
	workspace_expanded.emit(progression.expansion_index)
	changed.emit()
	objectives.evaluate(self, 0.0)
	return true


func is_prototype_completed() -> bool:
	return objectives.is_completed(ProgressionCatalog.FINAL_OBJECTIVE)


func _tick(elapsed: float) -> void:
	stats.sample(network)
	objectives.evaluate(self, elapsed)


func _connect_events() -> void:
	network.node_constructed.connect(_on_node_constructed)
	network.node_deleted.connect(_on_node_deleted)
	network.node_moved.connect(func(_id: int) -> void: changed.emit())
	network.connection_created.connect(_on_connection_created)
	network.connection_removed.connect(func(_from: int, _to: int) -> void: changed.emit())
	network.node_upgraded.connect(_on_node_upgraded)
	network.payout_received.connect(_on_payout_received)
	network.units_processed.connect(_on_units_processed)
	objectives.objective_completed.connect(_on_objective_completed)


func _on_node_constructed(id: int, type: int) -> void:
	stats.record_built(type, play_seconds)
	_evaluate_objectives()
	changed.emit()


func _on_node_deleted(_id: int, _type: int) -> void:
	stats.record_deleted()
	_evaluate_objectives()
	changed.emit()


func _on_connection_created(_from_id: int, _to_id: int) -> void:
	stats.record_connection()
	_evaluate_objectives()
	changed.emit()


func _on_node_upgraded(_id: int, _level: int) -> void:
	stats.record_upgrade(play_seconds)
	_evaluate_objectives()
	changed.emit()


# Counter-based objectives are evaluated at the event itself, so an action always counts toward the
# objective that was active when it happened. Time-based and rate-based ones are checked at the tick.
func _evaluate_objectives() -> void:
	objectives.evaluate(self, 0.0)


# Payouts are frequent, so they do not trigger a save on their own. The next tick or action saves them.
func _on_payout_received(amount: LargeNumber, _output_id: int, complexity: int) -> void:
	stats.record_payout(amount, complexity, play_seconds)
	if objectives.active_needs("EARN") or objectives.active_needs("DELIVER_COMPLEXITY"):
		_evaluate_objectives()


func _on_units_processed(_node_id: int, count: int) -> void:
	stats.record_processed(count)
	if objectives.active_needs("PROCESS"):
		_evaluate_objectives()


func _on_objective_completed(id: String) -> void:
	var objective: Dictionary = ProgressionCatalog.OBJECTIVES[ProgressionCatalog.objective_index(id)]
	var money_text: String = objective["reward_money"]
	var research: int = objective["reward_rp"]
	if money_text != "0":
		network.simulation.add_money(LargeNumber.from_text(money_text))
	progression.add_research_points(research)
	stats.note_first("objective." + id, play_seconds)
	objective_rewarded.emit(id, money_text, research)
	if id == ProgressionCatalog.FINAL_OBJECTIVE:
		prototype_completed.emit()
	changed.emit()
