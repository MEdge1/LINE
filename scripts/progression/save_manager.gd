class_name SaveManager
extends RefCounted

# Owns all save-file reading and writing. Nothing else touches the disk.
#
# Writes are atomic: the full save is written to a temporary file, read back and validated, then
# moved over the active save. A save that cannot be parsed or validated is moved aside to a
# timestamped corrupt file, never destroyed, and a new game starts in its place.
#
# Loading validates everything into a fresh GameSession before returning it, so a bad save can
# never leave the live session half-restored.

const SAVE_VERSION := 1
const NEW_GAME_STATUS := "new_game"
const LOADED_STATUS := "loaded"
const RECOVERED_STATUS := "recovered"
const CORRUPT_STATUS := "corrupt"

# Tests point this at a scratch file. The game uses the user:// default.
static var path: String = "user://savegame.json"


static func temp_path() -> String:
	return path + ".tmp"


# Returns {"session": GameSession, "status": String, "message": String, "needs_save": bool}. Never fails hard.
# default_mode is used for new games and for saves without a valid processing_balance_mode field.
static func load_or_new(default_mode: int = ProcessingBalance.Mode.LIVE_HYPERBOLIC, default_booster: int = BoosterModel.DEFAULT_MODE) -> Dictionary:
	# A complete temporary save means the app stopped between replacing and renaming. Recover it.
	if not FileAccess.file_exists(path) and FileAccess.file_exists(temp_path()):
		if not parse(_read(temp_path()), default_mode, default_booster).has("error"):
			_replace(temp_path(), path)
			var recovered := parse(_read(path), default_mode, default_booster)
			return {"session": recovered["session"], "status": RECOVERED_STATUS, "message": "", "needs_save": recovered["legacy_mode"]}

	if not FileAccess.file_exists(path):
		var fresh := GameSession.new_game(default_mode, default_booster)
		write(fresh)
		return {"session": fresh, "status": NEW_GAME_STATUS, "message": "", "needs_save": false}

	var result := parse(_read(path), default_mode, default_booster)
	if result.has("error"):
		var corrupt_path := "%s.corrupt-%d.json" % [path.get_basename(), Time.get_unix_time_from_system()]
		_replace(path, corrupt_path)
		var replacement := GameSession.new_game(default_mode, default_booster)
		write(replacement)
		return {
			"session": replacement,
			"status": CORRUPT_STATUS,
			"message": "Save could not be loaded (%s). It was kept as %s and a new game was started." % [result["error"], corrupt_path.get_file()],
			"needs_save": false,
		}
	return {"session": result["session"], "status": LOADED_STATUS, "message": "", "needs_save": result["legacy_mode"]}


# Starts a new game and saves it in place of the current save. Callers confirm with the player first.
# Both development balance modes are kept, so repeated fresh runs compare under the same configuration.
static func reset_progress(processing_mode: int = ProcessingBalance.Mode.LIVE_HYPERBOLIC, booster_model: int = BoosterModel.DEFAULT_MODE) -> GameSession:
	var fresh := GameSession.new_game(processing_mode, booster_model)
	write(fresh)
	return fresh


# Atomically writes the session. Returns false and leaves the active save untouched on any failure.
static func write(session: GameSession) -> bool:
	var text := JSON.stringify(serialize(session), "\t")
	var file := FileAccess.open(temp_path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()

	if parse(_read(temp_path())).has("error"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path()))
		return false
	_replace(temp_path(), path)
	return true


static func serialize(session: GameSession) -> Dictionary:
	var network := session.network
	var simulation := network.simulation
	var progression := session.progression
	var objectives := session.objectives
	var stats := session.stats

	var nodes: Array = []
	for id in network.graph.get_node_ids():
		var node := network.graph.get_node(id)
		var cell: Vector2i = network.layout.get_node_cell(id)
		nodes.append({
			"id": id,
			"type": NodeDefinitions.get_display_name(node.type),
			"x": cell.x,
			"y": cell.y,
			"level": node.level,
		})

	var connections: Array = []
	for connection in network.graph.get_connections():
		connections.append([connection.x, connection.y])

	var counters := {}
	for key in stats.counters:
		counters[key] = stats.counters[key].to_text()
	var cells: Array = []
	for cell in progression.unlocked_cells():
		cells.append([cell.x, cell.y])
	var states := {}
	for id in objectives.states():
		var state: Dictionary = objectives.states()[id]
		states[id] = {"baselines": state["baselines"], "seconds": state["seconds"]}

	return {
		"save_version": SAVE_VERSION,
		"processing_balance_mode": ProcessingBalance.save_name(simulation.processing_mode),
		"booster_balance_mode": BoosterModel.save_name(simulation.booster_model),
		"play_seconds": session.play_seconds,
		"economy": {
			"money": simulation.money.to_text(),
			"research_points": progression.research_points,
		},
		"progression": {
			"technologies": progression.unlocked_techs(),
			"cells": cells,
			"expansion_index": progression.expansion_index,
		},
		"objectives": {
			"completed": objectives.completed,
			"states": states,
		},
		"statistics": {
			"counters": counters,
			"highest_complexity": stats.highest_complexity,
			"peak_revenue": stats.peak_revenue.to_text(),
			"peak_production": stats.peak_production,
			"bottlenecks_resolved": stats.bottlenecks_resolved,
			"first_times": stats.first_times,
		},
		"network": {
			"next_node_id": network.graph.next_id(),
			"nodes": nodes,
			"connections": connections,
		},
		"simulation": simulation.export_state(),
	}


# Parses and validates save text. Returns {"session": GameSession, "legacy_mode": bool} or {"error": message}.
# legacy_mode is true when the save had no valid processing_balance_mode, so the default was applied and the
# caller should write the save to persist it.
static func parse(text: String, default_mode: int = ProcessingBalance.Mode.LIVE_HYPERBOLIC, default_booster: int = BoosterModel.DEFAULT_MODE) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "not a valid save file"}
	var data: Dictionary = json.data

	if not _is_int(data.get("save_version", null)) or int(data["save_version"]) != SAVE_VERSION:
		return {"error": "unsupported save version"}

	var validation := _validate(data)
	if validation.has("error"):
		return validation
	var session := _build(data, default_booster)
	var known := ProcessingBalance.mode_from_save_name(data.get("processing_balance_mode", null), -1)
	session.network.simulation.processing_mode = known if known >= 0 else default_mode
	var simulation := session.network.simulation
	var held := simulation.get_held_units()
	var accounted := simulation.paid_units.add(held).add(simulation.lost_units)
	if accounted.compare(simulation.produced_units) != 0:
		return {"error": "resources do not balance (produced = paid + held + lost)"}
	return {"session": session, "legacy_mode": known < 0}


static func _validate(data: Dictionary) -> Dictionary:
	for key in ["economy", "progression", "objectives", "statistics", "network", "simulation"]:
		if typeof(data.get(key, null)) != TYPE_DICTIONARY:
			return {"error": "missing section %s" % key}

	var economy: Dictionary = data["economy"]
	if not _is_digits(economy.get("money", null)) or not _is_int(economy.get("research_points", null)):
		return {"error": "economy values are invalid"}

	var progression_data: Dictionary = data["progression"]
	var technologies: Array = progression_data.get("technologies", [])
	for id in technologies:
		if typeof(id) != TYPE_STRING or ProgressionCatalog.technology_index(id) < 0:
			return {"error": "unknown technology %s" % str(id)}
	for start in ProgressionCatalog.START_TECHNOLOGIES:
		if not technologies.has(start):
			return {"error": "start technology %s is missing" % start}
	for tech in ProgressionCatalog.TECHNOLOGIES:
		if technologies.has(tech["id"]) and tech["prerequisite"] != "" and not technologies.has(tech["prerequisite"]):
			return {"error": "technology %s is unlocked without its prerequisite" % tech["id"]}

	var expansion_index = progression_data.get("expansion_index", null)
	if not _is_int(expansion_index) or int(expansion_index) < 0 or int(expansion_index) > ProgressionCatalog.EXPANSIONS.size():
		return {"error": "expansion index is invalid"}
	var expected_cells: Array = ProgressionCatalog.START_CELLS.duplicate()
	for step in range(int(expansion_index)):
		expected_cells.append_array(ProgressionCatalog.EXPANSIONS[step]["cells"])
	var cells := _parse_cells(progression_data.get("cells", []))
	if cells.is_empty() or cells.size() != expected_cells.size():
		return {"error": "unlocked workspace does not match the expansion index"}
	for cell in expected_cells:
		if not cells.has(cell):
			return {"error": "unlocked workspace does not match the expansion index"}

	var objective_data: Dictionary = data["objectives"]
	var completed: Array = objective_data.get("completed", [])
	var expected_order := []
	for objective in ProgressionCatalog.OBJECTIVES:
		if completed.size() > expected_order.size():
			expected_order.append(objective["id"])
	if completed != expected_order:
		return {"error": "completed objectives are not a valid prefix of the sequence"}
	var states: Dictionary = objective_data.get("states", {})
	for id in states:
		if ProgressionCatalog.objective_index(id) < 0 or completed.has(id):
			return {"error": "objective state %s is invalid" % id}
		var state = states[id]
		if typeof(state) != TYPE_DICTIONARY or not _is_number(state.get("seconds", null)):
			return {"error": "objective state %s is invalid" % id}
		for key in state.get("baselines", {}):
			if not _is_digits(state["baselines"][key]):
				return {"error": "objective baseline %s is invalid" % key}

	var stats_data: Dictionary = data["statistics"]
	for key in stats_data.get("counters", {}):
		if not _is_digits(stats_data["counters"][key]):
			return {"error": "statistic %s is invalid" % key}
	if not _is_digits(stats_data.get("peak_revenue", null)) or not _is_int(stats_data.get("highest_complexity", null)) \
			or not _is_int(stats_data.get("bottlenecks_resolved", null)) or not _is_number(stats_data.get("peak_production", null)):
		return {"error": "statistics are invalid"}

	var network_data: Dictionary = data["network"]
	var validation := _validate_network(network_data, cells)
	if validation.has("error"):
		return validation

	var simulation_data: Dictionary = data["simulation"]
	validation = _validate_simulation(simulation_data, network_data)
	if validation.has("error"):
		return validation

	if not _is_number(data.get("play_seconds", null)) or float(data["play_seconds"]) < 0.0:
		return {"error": "play time is invalid"}
	return {}


static func _validate_network(network_data: Dictionary, cells: Array) -> Dictionary:
	var seen_ids := {}
	var seen_cells := {}
	var largest_id := 0
	for node_data in network_data.get("nodes", []):
		if typeof(node_data) != TYPE_DICTIONARY or not _is_int(node_data.get("id", null)) or not _is_int(node_data.get("x", null)) \
				or not _is_int(node_data.get("y", null)) or not _is_int(node_data.get("level", null)):
			return {"error": "a node entry is malformed"}
		var id := int(node_data["id"])
		var type := ProgressionCatalog.node_type_for(str(node_data.get("type", "")))
		if id < 1 or seen_ids.has(id) or type < 0:
			return {"error": "node %d is invalid" % id}
		seen_ids[id] = true
		largest_id = maxi(largest_id, id)

		var cell := Vector2i(int(node_data["x"]), int(node_data["y"]))
		if cell.x < 0 or cell.y < 0 or cell.x >= WorkspaceLayout.COLUMNS or cell.y >= WorkspaceLayout.ROWS:
			return {"error": "node %d is outside the grid" % id}
		if not cells.has(cell):
			return {"error": "node %d sits in a locked cell" % id}
		if seen_cells.has(cell):
			return {"error": "two nodes share cell %s" % str(cell)}
		seen_cells[cell] = true

		var level := int(node_data["level"])
		if type == NodeDefinitions.Type.GENERATOR:
			if level < 1 or level > LineBalance.GENERATOR_MAX_LEVEL:
				return {"error": "generator %d has an invalid level" % id}
		elif level != 1:
			return {"error": "node %d has an invalid level" % id}

	if not _is_int(network_data.get("next_node_id", null)) or int(network_data["next_node_id"]) <= largest_id:
		return {"error": "next node id is invalid"}

	for connection in network_data.get("connections", []):
		if typeof(connection) != TYPE_ARRAY or connection.size() != 2 or not seen_ids.has(int(connection[0])) or not seen_ids.has(int(connection[1])):
			return {"error": "a connection references a missing node"}
	return {}


static func _validate_simulation(simulation_data: Dictionary, network_data: Dictionary) -> Dictionary:
	var node_ids := {}
	for node_data in network_data.get("nodes", []):
		node_ids[int(node_data["id"])] = true

	var batch_fields := ["in_flight", "queues", "returning", "revenue", "accumulators", "budgets", "split_parity", "last_incoming", "last_payout_complexity"]
	for field in batch_fields:
		if typeof(simulation_data.get(field, null)) != TYPE_ARRAY:
			return {"error": "simulation field %s is missing" % field}

	for key in ["money", "produced", "paid", "lost"]:
		if not _is_digits(simulation_data.get(key, null)):
			return {"error": "simulation total %s is invalid" % key}

	for batch in simulation_data["in_flight"]:
		var error := _validate_batch(batch, node_ids)
		if error != "":
			return {"error": "in-flight batch: " + error}
		if not node_ids.has(int(batch["to"])):
			return {"error": "in-flight batch targets a missing node"}

	for entry in simulation_data["queues"]:
		if typeof(entry) != TYPE_DICTIONARY or not node_ids.has(int(entry.get("node", -1))):
			return {"error": "a queue references a missing node"}
		var total := LargeNumber.from_int(0)
		for batch in entry["batches"]:
			var error := _validate_batch(batch, node_ids)
			if error != "":
				return {"error": "queued batch: " + error}
			total = total.add(LargeNumber.from_text(batch["quantity"]))
		if total.compare(LargeNumber.from_int(LineBalance.BUFFER_CAPACITY)) > 0:
			return {"error": "a queue exceeds its buffer"}

	for entry in simulation_data["returning"]:
		if typeof(entry) != TYPE_DICTIONARY or not node_ids.has(int(entry.get("node", -1))):
			return {"error": "a holding list references a missing node"}
		for batch in entry["batches"]:
			var error := _validate_batch(batch, node_ids)
			if error != "":
				return {"error": "holding batch: " + error}

	for pair in simulation_data["revenue"]:
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2 or not node_ids.has(int(pair[0])) or not _is_digits(pair[1]):
			return {"error": "a revenue total is invalid"}
	for field in ["accumulators", "budgets", "split_parity", "last_incoming", "last_payout_complexity"]:
		for pair in simulation_data[field]:
			if typeof(pair) != TYPE_ARRAY or pair.size() != 2 or not node_ids.has(int(pair[0])) or not _is_number(pair[1]):
				return {"error": "simulation field %s is invalid" % field}
	return {}


static func _validate_batch(batch, node_ids: Dictionary) -> String:
	if typeof(batch) != TYPE_DICTIONARY:
		return "malformed"
	if not _is_digits(batch.get("quantity", null)) or not _is_digits(batch.get("value", null)):
		return "quantity or value is not an exact number"
	if not _is_int(batch.get("complexity", null)) or int(batch["complexity"]) < 0:
		return "complexity is invalid"
	if typeof(batch.get("processed", null)) != TYPE_BOOL:
		return "processed flag is invalid"
	if not _is_int(batch.get("from", null)) or not _is_int(batch.get("to", null)):
		return "endpoints are invalid"
	if not node_ids.has(int(batch["from"])):
		return "origin node is missing"
	if not _is_number(batch.get("progress", null)) or float(batch["progress"]) < 0.0 or float(batch["progress"]) > 1.0:
		return "progress is invalid"
	return ""


# Builds a live session from validated data. Conservation is checked at the end.
static func _build(data: Dictionary, booster_default: int = BoosterModel.DEFAULT_MODE) -> GameSession:
	var progression_data: Dictionary = data["progression"]
	var progression := ProgressionManager.new()
	progression.restore(
		progression_data["technologies"],
		_parse_cells(progression_data["cells"]),
		int(data["economy"]["research_points"]),
		int(progression_data["expansion_index"])
	)

	var network := NetworkManager.new()
	network.progression = progression
	# Set before nodes are restored, so boost state is computed under the saved coverage model.
	network.simulation.booster_model = BoosterModel.mode_from_save_name(data.get("booster_balance_mode", null), booster_default)
	var network_data: Dictionary = data["network"]
	for node_data in network_data["nodes"]:
		network.restore_node(
			int(node_data["id"]),
			ProgressionCatalog.node_type_for(node_data["type"]),
			Vector2i(int(node_data["x"]), int(node_data["y"])),
			int(node_data["level"])
		)
	for connection in network_data["connections"]:
		network.restore_connection(int(connection[0]), int(connection[1]))
	network.finish_restore(int(network_data["next_node_id"]))
	network.simulation.import_state(data["simulation"])

	var objective_data: Dictionary = data["objectives"]
	var objectives := ObjectiveManager.new()
	var states := {}
	for id in objective_data["states"]:
		states[id] = objective_data["states"][id]
	objectives.restore(objective_data["completed"], states)

	var stats := StatisticsManager.new()
	var stats_data: Dictionary = data["statistics"]
	for key in stats_data["counters"]:
		stats.counters[key] = LargeNumber.from_text(stats_data["counters"][key])
	stats.highest_complexity = int(stats_data["highest_complexity"])
	stats.peak_revenue = LargeNumber.from_text(stats_data["peak_revenue"])
	stats.peak_production = float(stats_data["peak_production"])
	stats.bottlenecks_resolved = int(stats_data["bottlenecks_resolved"])
	stats.first_times = stats_data["first_times"]

	var session := GameSession.new(network, progression, objectives, stats)
	session.play_seconds = float(data["play_seconds"])
	return session


static func _parse_cells(entries: Array) -> Array:
	var cells: Array = []
	for entry in entries:
		if typeof(entry) == TYPE_ARRAY and entry.size() == 2 and _is_int(entry[0]) and _is_int(entry[1]):
			cells.append(Vector2i(int(entry[0]), int(entry[1])))
	return cells


static func _is_int(value) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_equal_approx(float(value), roundf(float(value)))


static func _is_number(value) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and not is_nan(float(value)) and not is_inf(float(value))


# Exact integer text: digits only, so LargeNumber parsing never sees a float.
static func _is_digits(value) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty():
		return false
	for character in value:
		if not "0123456789".contains(character):
			return false
	return true


static func _read(file_path: String) -> String:
	var file := FileAccess.open(file_path, FileAccess.READ)
	return file.get_as_text() if file else ""


static func _replace(from_path: String, to_path: String) -> void:
	if FileAccess.file_exists(to_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(to_path))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))
