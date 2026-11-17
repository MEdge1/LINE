extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_save.gd
# Save/load round trips, validation, corrupt-save handling, reset, and repeated stress saves.
# Uses a scratch save path so the player's real save is never touched.

const TEST_PATH := "user://test_savegame.json"

var _failures := 0


func _init() -> void:
	SaveManager.path = TEST_PATH
	_clean_files()

	_test_missing_save_starts_a_new_game()
	_test_nontrivial_game_round_trips_exactly()
	_test_round_trip_keeps_partial_objective_progress()
	_test_corrupt_save_is_preserved_and_a_new_game_starts()
	_test_invalid_node_reference_is_rejected()
	_test_locked_cell_placement_is_rejected_on_load()
	_test_unbalanced_resources_are_rejected_on_load()
	_test_unknown_fields_are_tolerated()
	_test_unsupported_version_is_rejected()
	_test_reset_replaces_the_save_with_a_new_game()
	_test_stress_save_round_trips_without_drift()

	_clean_files()
	if _failures == 0:
		print("All save tests passed.")
	else:
		printerr("%d save assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _clean_files() -> void:
	var directory := ProjectSettings.globalize_path("user://")
	for file in DirAccess.get_files_at("user://"):
		if file.begins_with("test_savegame"):
			DirAccess.remove_absolute(directory.path_join(file))


func _text(session: GameSession) -> String:
	return JSON.stringify(SaveManager.serialize(session))


func _step(session: GameSession, seconds: float) -> void:
	for _i in range(int(round(seconds / 0.1))):
		session.step(0.1)


func _place(session: GameSession, type: int, cell: Vector2i) -> int:
	session.network.construct(type, cell)
	return session.network.layout.get_node_at(cell)


# A deliberately mixed game: unlocks, an expanded workspace, a routed network with Boosters,
# high-complexity queued batches, LargeNumber money, partial objective progress, and statistics.
func _developed_game() -> GameSession:
	var session := GameSession.new_game()
	var network := session.network
	network.simulation.money = LargeNumber.from_text("123456789012345678901234567890")
	var generator := _place(session, NodeDefinitions.Type.GENERATOR, Vector2i(1, 4))
	var output := _place(session, NodeDefinitions.Type.OUTPUT, Vector2i(3, 4))
	network.connect_nodes(generator, output)
	network.graph.get_node(generator).level = 1
	session.progression.add_research_points(4)
	session.unlock_technology("PROCESSOR")
	session.unlock_technology("SPLITTER")
	network.disconnect_nodes(generator, output)
	var processor := _place(session, NodeDefinitions.Type.PROCESSOR, Vector2i(2, 4))
	var booster := _place(session, NodeDefinitions.Type.BOOSTER, Vector2i(2, 5))
	network.connect_nodes(generator, processor)
	network.connect_nodes(processor, output)
	session.network.simulation.seed_queue(processor, LargeNumber.from_int(7), LargeNumber.from_int(8), false, 3)
	session.network.simulation.seed_queue(output, LargeNumber.from_int(2), LargeNumber.from_int(4), true, 2)
	session.purchase_expansion()
	_step(session, 40.0)
	return session


func _test_missing_save_starts_a_new_game() -> void:
	_clean_files()
	var loaded := SaveManager.load_or_new()
	_assert_equal(loaded["status"], SaveManager.NEW_GAME_STATUS, "no save file starts a new game")
	var session: GameSession = loaded["session"]
	_assert_equal(session.progression.research_points, 0, "the new game starts with 0 Research Points")
	_assert_equal(FileAccess.file_exists(TEST_PATH), true, "a new game is saved right away")


func _test_nontrivial_game_round_trips_exactly() -> void:
	var original := _developed_game()
	var text := _text(original)
	var parsed := SaveManager.parse(text)
	_assert_equal(parsed.has("error"), false, "a developed game saves and validates")
	var reloaded: GameSession = parsed["session"]
	_assert_equal(_text(reloaded), text, "the reloaded game serializes to exactly the same save")
	_assert_equal(reloaded.network.simulation.money.to_text(), original.network.simulation.money.to_text(), "LargeNumber money round-trips exactly")
	_assert_equal(reloaded.progression.research_points, original.progression.research_points, "Research Points round-trip")
	_assert_equal(reloaded.progression.unlocked_cell_count(), original.progression.unlocked_cell_count(), "workspace unlocks round-trip")
	_assert_equal(reloaded.network.simulation.get_held_units().to_text(), original.network.simulation.get_held_units().to_text(), "queued resources round-trip exactly")
	_assert_equal(reloaded.network.graph.get_node_ids().size(), original.network.graph.get_node_ids().size(), "every node round-trips")
	_assert_equal(reloaded.network.graph.get_connections().size(), original.network.graph.get_connections().size(), "every connection round-trips")
	_assert_equal(reloaded.stats.highest_complexity, original.stats.highest_complexity, "statistics round-trip")
	_assert_equal(reloaded.objectives.completed, original.objectives.completed, "completed objectives round-trip")
	var accounted := reloaded.network.simulation.paid_units.add(reloaded.network.simulation.get_held_units()).add(reloaded.network.simulation.lost_units)
	_assert_equal(accounted.compare(reloaded.network.simulation.produced_units) == 0, true, "resources conserve after reload")


func _test_round_trip_keeps_partial_objective_progress() -> void:
	var session := GameSession.new_game()
	_place(session, NodeDefinitions.Type.GENERATOR, Vector2i(1, 4))
	_place(session, NodeDefinitions.Type.OUTPUT, Vector2i(3, 4))
	session.network.connect_nodes(session.network.layout.get_node_at(Vector2i(1, 4)), session.network.layout.get_node_at(Vector2i(3, 4)))
	_step(session, 30.0)
	var before: String = session.objectives.describe(session)["progress"]
	var parsed := SaveManager.parse(_text(session))
	var reloaded: GameSession = parsed["session"]
	_assert_equal(reloaded.objectives.describe(reloaded)["progress"], before, "partial objective progress is restored exactly")
	_assert_equal(reloaded.objectives.active_id(), session.objectives.active_id(), "the active objective is restored")


func _test_corrupt_save_is_preserved_and_a_new_game_starts() -> void:
	_clean_files()
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ this is not a save")
	file.close()
	var loaded := SaveManager.load_or_new()
	_assert_equal(loaded["status"], SaveManager.CORRUPT_STATUS, "a corrupt save is detected")
	_assert_equal(loaded["message"] != "", true, "the player is told the save could not be loaded")
	var session: GameSession = loaded["session"]
	_assert_equal(session.progression.research_points, 0, "a new game starts after a corrupt save")
	var preserved := false
	for name in DirAccess.get_files_at("user://"):
		if name.begins_with("test_savegame.corrupt-"):
			preserved = true
	_assert_equal(preserved, true, "the corrupt save is kept for recovery, not destroyed")


func _test_invalid_node_reference_is_rejected() -> void:
	var data := SaveManager.serialize(_developed_game())
	data["network"]["connections"].append([999, 1])
	_assert_equal(SaveManager.parse(JSON.stringify(data)).has("error"), true, "a connection to a missing node is rejected")


func _test_locked_cell_placement_is_rejected_on_load() -> void:
	var data := SaveManager.serialize(_developed_game())
	data["network"]["nodes"][0]["x"] = 0
	data["network"]["nodes"][0]["y"] = 0
	_assert_equal(SaveManager.parse(JSON.stringify(data)).has("error"), true, "a node placed in a locked cell is rejected")


func _test_unbalanced_resources_are_rejected_on_load() -> void:
	var data := SaveManager.serialize(_developed_game())
	data["simulation"]["paid"] = "999999999999999999999"
	_assert_equal(SaveManager.parse(JSON.stringify(data)).has("error"), true, "resources that do not balance are rejected")


func _test_unknown_fields_are_tolerated() -> void:
	var data := SaveManager.serialize(_developed_game())
	data["future_field"] = {"anything": 1}
	data["network"]["nodes"][0]["future_node_field"] = true
	_assert_equal(SaveManager.parse(JSON.stringify(data)).has("error"), false, "fields from a newer build are ignored")


func _test_unsupported_version_is_rejected() -> void:
	var data := SaveManager.serialize(_developed_game())
	data["save_version"] = 2
	_assert_equal(SaveManager.parse(JSON.stringify(data)).has("error"), true, "an unsupported save version is rejected")


func _test_reset_replaces_the_save_with_a_new_game() -> void:
	var session := _developed_game()
	SaveManager.write(session)
	var fresh := SaveManager.reset_progress()
	_assert_equal(fresh.progression.research_points, 0, "reset starts a new game")
	_assert_equal(fresh.network.graph.get_node_ids().size(), 0, "reset empties the network")
	var reloaded := SaveManager.load_or_new()
	_assert_equal(reloaded["status"], SaveManager.LOADED_STATUS, "the replacement save loads")
	_assert_equal((reloaded["session"] as GameSession).network.graph.get_node_ids().size(), 0, "the saved reset state is the new game")


# A large, fully unlocked network with routing, Boosters, and high-complexity queues, saved and reloaded repeatedly.
func _test_stress_save_round_trips_without_drift() -> void:
	var session := GameSession.new(NetworkManager.new(), ProgressionManager.sandbox(), ObjectiveManager.new(), StatisticsManager.new())
	session.network.progression = session.progression
	session.network.simulation.money = LargeNumber.from_text("9999999999999999999999")
	var cells := StrategyScenarios.all_cells()
	var previous := 0
	for index in range(40):
		var type := NodeDefinitions.Type.PROCESSOR if index % 4 != 3 else NodeDefinitions.Type.BOOSTER
		var node := _place(session, type, cells[index])
		if type == NodeDefinitions.Type.PROCESSOR and previous != 0:
			session.network.connect_nodes(previous, node)
		if type == NodeDefinitions.Type.PROCESSOR:
			previous = node
	var source := _place(session, NodeDefinitions.Type.GENERATOR, cells[40])
	session.network.graph.get_node(source).level = 15
	_place(session, NodeDefinitions.Type.SPLITTER, cells[41])
	session.network.connect_nodes(source, session.network.layout.get_node_at(cells[0]))
	_step(session, 120.0)

	var text := _text(session)
	var started := Time.get_ticks_usec()
	var clean := true
	for _round in range(5):
		SaveManager.write(session)
		var loaded := SaveManager.load_or_new()
		var reloaded: GameSession = loaded["session"]
		if _text(reloaded) != text:
			clean = false
		session = reloaded
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 5000.0
	print("STRESS save %d bytes · average write+load %.1f ms · nodes %d · in-flight %d · waiting %d" % [
		text.length(), elapsed_ms, session.network.graph.get_node_ids().size(),
		session.network.simulation.in_flight.size(), session.network.simulation.get_waiting_batch_count(),
	])
	_assert_equal(clean, true, "five save and reload cycles produce identical state (no duplication, loss, or drift)")
	var accounted := session.network.simulation.paid_units.add(session.network.simulation.get_held_units()).add(session.network.simulation.lost_units)
	_assert_equal(accounted.compare(session.network.simulation.produced_units) == 0, true, "the stress save conserves resources")
