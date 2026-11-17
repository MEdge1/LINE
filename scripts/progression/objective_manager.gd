class_name ObjectiveManager
extends RefCounted

# Evaluates the active objective from authoritative state: statistics counters, the graph, progression,
# and sampled network telemetry. Definitions come from ProgressionCatalog. Visual state never counts.
# Evaluation runs at the progression tick, not every frame, and only the active objective is checked.

signal objective_completed(id: String)

# Ordered ids of finished objectives.
var completed: Array = []

# Per active objective: counter baselines taken at activation, and seconds for BOTTLENECK_FREE.
var _state: Dictionary = {}


func is_completed(id: String) -> bool:
	return completed.has(id)


func is_finished() -> bool:
	return completed.size() == ProgressionCatalog.OBJECTIVES.size()


# The first unfinished objective whose prerequisites are all finished. Empty when everything is done.
func active_id() -> String:
	for objective in ProgressionCatalog.OBJECTIVES:
		if completed.has(objective["id"]):
			continue
		var ready := true
		for prerequisite in objective["prerequisites"]:
			if not completed.has(prerequisite):
				ready = false
		if ready:
			return objective["id"]
	return ""


func active_state() -> Dictionary:
	return _state.get(active_id(), {})


# Copy of the in-progress objective state, for saving.
func states() -> Dictionary:
	return _state.duplicate(true)


# Everything the progression UI needs for the tracked objective. Numbers are display text only.
func describe(session) -> Dictionary:
	var id := active_id()
	if id == "":
		return {"finished": true, "id": "", "title": "Prototype complete", "hint": "Free play: keep building", "stage": ProgressionCatalog.STAGE_SCALE, "progress": "", "index": ProgressionCatalog.OBJECTIVES.size(), "total": ProgressionCatalog.OBJECTIVES.size()}

	var objective := _objective(id)
	var parts: Array[String] = []
	for condition in objective["conditions"]:
		parts.append(_condition_text(session, condition, _state.get(id, {})))
	return {
		"finished": false,
		"id": id,
		"title": objective["title"],
		"hint": objective["hint"],
		"stage": objective["stage"],
		"progress": "  ·  ".join(PackedStringArray(parts)),
		"index": completed.size() + 1,
		"total": ProgressionCatalog.OBJECTIVES.size(),
		"reward_money": objective["reward_money"],
		"reward_rp": objective["reward_rp"],
	}


# Called at the progression tick and after player actions that can change progress.
# `dt` is the seconds since the last evaluation, used by time-based conditions.
func evaluate(session, dt: float) -> void:
	var id := active_id()
	if id == "":
		return

	var objective := _objective(id)
	if not _state.has(id):
		_state[id] = _new_state(session, objective)
	var state: Dictionary = _state[id]

	if _has_condition(objective, "BOTTLENECK_FREE"):
		state["seconds"] = 0.0 if session.network.has_bottleneck() else float(state["seconds"]) + dt

	for condition in objective["conditions"]:
		if not _met(session, condition, state):
			return

	completed.append(id)
	_state.erase(id)
	ensure_active(session)
	objective_completed.emit(id)
	# A completed objective can make the next one immediately satisfied; check it now.
	evaluate(session, 0.0)


# True when the active objective has a condition of this type. Event handlers use it so they only
# evaluate when the event can change the tracked objective.
func active_needs(condition_type: String) -> bool:
	var id := active_id()
	return id != "" and _has_condition(_objective(id), condition_type)


# Starts tracking the active objective now, so counters are measured from the moment it became
# active. Called on new games, on loads, and when an objective completes.
func ensure_active(session) -> void:
	var id := active_id()
	if id != "" and not _state.has(id):
		_state[id] = _new_state(session, _objective(id))


func _new_state(session, objective: Dictionary) -> Dictionary:
	var baselines := {}
	for condition in objective["conditions"]:
		for key in _counter_keys(condition):
			baselines[key] = session.stats.counter(key).to_text()
	return {"baselines": baselines, "seconds": 0.0}


func _counter_keys(condition: Dictionary) -> Array:
	match condition["type"]:
		"BUILD_NODE":
			return ["built." + condition["node"]]
		"UPGRADE":
			return ["upgrades"]
		"EARN":
			return ["revenue"]
		"PROCESS":
			return ["processed"]
		_:
			return []


# Counter growth since the objective became active. Never negative.
func _since(session, state: Dictionary, key: String) -> LargeNumber:
	var baseline := LargeNumber.from_text(state["baselines"].get(key, "0"))
	var current: LargeNumber = session.stats.counter(key)
	return current.subtract(baseline) if current.compare(baseline) >= 0 else LargeNumber.from_int(0)


func _met(session, condition: Dictionary, state: Dictionary) -> bool:
	match condition["type"]:
		"BUILD_NODE":
			return _since(session, state, "built." + condition["node"]).compare(LargeNumber.from_int(int(condition["count"]))) >= 0
		"UPGRADE":
			return _since(session, state, "upgrades").compare(LargeNumber.from_int(int(condition["count"]))) >= 0
		"EARN":
			return _since(session, state, "revenue").compare(LargeNumber.from_text(condition["amount"])) >= 0
		"PROCESS":
			return _since(session, state, "processed").compare(LargeNumber.from_text(condition["units"])) >= 0
		"CONNECT":
			return session.network.has_connection_between(ProgressionCatalog.node_type_for(condition["from"]), ProgressionCatalog.node_type_for(condition["to"]))
		"UNLOCK_TECH":
			return session.progression.is_tech_unlocked(condition["tech"])
		"DELIVER_COMPLEXITY":
			return session.stats.highest_complexity >= int(condition["level"])
		"REACH_THROUGHPUT":
			return session.network.completed_rate() >= float(condition["units_per_sec"])
		"REACH_REVENUE_RATE":
			return session.network.revenue_rate() >= float(condition["per_sec"])
		"BOTTLENECK_FREE":
			return float(state["seconds"]) >= float(condition["seconds"])
		"USE_BOOSTER":
			return session.network.boosted_processor_count() >= int(condition["count"])
		"NETWORK_SIZE":
			return session.network.graph.get_node_ids().size() >= int(condition["count"])
		"WORKSPACE_CELLS":
			return session.progression.unlocked_cell_count() >= int(condition["count"])
		"ALL_TECHNOLOGIES":
			return session.progression.all_technologies_unlocked()
		_:
			return false


func _condition_text(session, condition: Dictionary, state: Dictionary) -> String:
	match condition["type"]:
		"BUILD_NODE":
			return "%s %s / %d" % [_node_label(condition["node"]), _since(session, state, "built." + condition["node"]).to_text(), int(condition["count"])]
		"UPGRADE":
			return "Upgrades %s / %d" % [_since(session, state, "upgrades").to_text(), int(condition["count"])]
		"EARN":
			return "$%s / $%s" % [_since(session, state, "revenue").to_text(), condition["amount"]]
		"PROCESS":
			return "%s / %s units" % [_since(session, state, "processed").to_text(), condition["units"]]
		"CONNECT":
			return "%s → %s" % [condition["from"], condition["to"]]
		"UNLOCK_TECH":
			return "Unlock %s" % condition["tech"]
		"DELIVER_COMPLEXITY":
			return "Complexity %d / %d" % [session.stats.highest_complexity, int(condition["level"])]
		"REACH_THROUGHPUT":
			return "%.1f / %.1f units/s" % [session.network.completed_rate(), float(condition["units_per_sec"])]
		"REACH_REVENUE_RATE":
			return "$%.0f / $%.0f per s" % [session.network.revenue_rate(), float(condition["per_sec"])]
		"BOTTLENECK_FREE":
			return "%.0f / %.0f s clear" % [float(state.get("seconds", 0.0)), float(condition["seconds"])]
		"USE_BOOSTER":
			return "Boosted Processors %d / %d" % [session.network.boosted_processor_count(), int(condition["count"])]
		"NETWORK_SIZE":
			return "Nodes %d / %d" % [session.network.graph.get_node_ids().size(), int(condition["count"])]
		"WORKSPACE_CELLS":
			return "Cells %d / %d" % [session.progression.unlocked_cell_count(), int(condition["count"])]
		"ALL_TECHNOLOGIES":
			return "All technologies"
		_:
			return ""


func _node_label(name: String) -> String:
	return name.capitalize()


func _objective(id: String) -> Dictionary:
	return ProgressionCatalog.OBJECTIVES[ProgressionCatalog.objective_index(id)]


func _has_condition(objective: Dictionary, type: String) -> bool:
	for condition in objective["conditions"]:
		if condition["type"] == type:
			return true
	return false


# Restores completed ids and per-objective state from a validated save.
func restore(completed_ids: Array, states: Dictionary) -> void:
	completed = completed_ids.duplicate()
	_state = states.duplicate(true)
