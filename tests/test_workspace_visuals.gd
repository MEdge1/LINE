extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_workspace_visuals.gd
# Workspace states, the expansion preview, and the reveal that follows a purchase. Authoritative
# cell rules are checked against the progression; the reveal is checked against its timing only.

var _failures := 0


func _init() -> void:
	_test_cell_states_follow_unlocks()
	_test_expansion_preview_matches_the_next_purchase()
	_test_full_expansion_never_exceeds_the_world()
	_test_purchase_reveals_only_the_new_cells()
	_test_loading_a_session_does_not_reveal()

	if _failures == 0:
		print("All workspace visual tests passed.")
	else:
		printerr("%d workspace visual assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _test_cell_states_follow_unlocks() -> void:
	var session := GameSession.new_game()
	var layout := session.network.layout
	var progression := session.progression
	_assert_equal(WorkspaceStyle.cell_state(layout, progression, Vector2i(2, 4)), WorkspaceStyle.CellState.UNLOCKED, "a starting cell is buildable")
	_assert_equal(WorkspaceStyle.cell_state(layout, progression, Vector2i(0, 0)), WorkspaceStyle.CellState.LOCKED, "a locked cell inside the world is expandable")
	_assert_equal(WorkspaceStyle.cell_state(layout, progression, Vector2i(5, 0)), WorkspaceStyle.CellState.OUTSIDE, "a cell past the world edge is outside")
	_assert_equal(WorkspaceStyle.cell_state(layout, progression, Vector2i(-1, 4)), WorkspaceStyle.CellState.OUTSIDE, "a negative cell is outside")
	_assert_equal(WorkspaceStyle.is_valid_target(layout, progression, Vector2i(2, 4)), true, "an empty unlocked cell is a valid target")
	_assert_equal(WorkspaceStyle.is_valid_target(layout, progression, Vector2i(0, 0)), false, "a locked cell is not a valid target")
	_assert_equal(WorkspaceStyle.world_rect().size, Vector2(WorkspaceLayout.COLUMNS, WorkspaceLayout.ROWS) * WorkspaceLayout.CELL_SIZE, "the boundary covers the full 5×9 world")


func _test_expansion_preview_matches_the_next_purchase() -> void:
	var session := GameSession.new_game()
	var progression := session.progression
	var preview := progression.next_expansion_cells()
	session.network.simulation.money = LargeNumber.from_int(1000)
	_assert_equal(session.purchase_expansion(), true, "the first expansion can be bought")
	for cell in preview:
		_assert_equal(progression.is_cell_unlocked(cell), true, "the previewed cell %s is unlocked by the purchase" % cell)
	_assert_equal(progression.next_expansion_cells().size(), 3, "the following step previews its own cells")


func _test_full_expansion_never_exceeds_the_world() -> void:
	var session := GameSession.new_game()
	session.network.simulation.money = LargeNumber.from_int(100000000)
	while session.purchase_expansion():
		pass
	var progression := session.progression
	_assert_equal(progression.unlocked_cell_count(), WorkspaceLayout.COLUMNS * WorkspaceLayout.ROWS, "full expansion unlocks exactly the 5×9 world")
	_assert_equal(progression.next_expansion_cells().is_empty(), true, "nothing is previewed once fully expanded")
	_assert_equal(WorkspaceStyle.cell_state(session.network.layout, progression, Vector2i(5, 9)), WorkspaceStyle.CellState.OUTSIDE, "the world does not grow past its boundary")


func _test_purchase_reveals_only_the_new_cells() -> void:
	var session := GameSession.new_game()
	session.network.simulation.money = LargeNumber.from_int(1000)
	var view := NetworkView.new()
	view.progression = session.progression
	view._track_unlocks(0.0)

	var preview := session.progression.next_expansion_cells()
	session.purchase_expansion()
	view._track_unlocks(0.1)
	_assert_equal(view._reveal_ages.size(), preview.size(), "a purchase reveals exactly its new cells")
	for cell in preview:
		_assert_equal(view._reveal_ages.has(cell), true, "the new cell %s is marked for reveal" % cell)
	_assert_equal(WorkspaceStyle.reveal_strength(0.0), 1.0, "a new cell starts at full reveal emphasis")
	_assert_equal(WorkspaceStyle.transition_progress(0.0), 0.0, "a new cell starts locked-looking")

	view._track_unlocks(WorkspaceVisuals.REVEAL_SECONDS)
	_assert_equal(view._reveal_ages.is_empty(), true, "the reveal expires and no state accumulates")
	view.free()


func _test_loading_a_session_does_not_reveal() -> void:
	var session := GameSession.new_game()
	var view := NetworkView.new()
	view.progression = session.progression
	view._track_unlocks(0.0)
	var reloaded := GameSession.new_game()
	reloaded.network.simulation.money = LargeNumber.from_int(1000)
	reloaded.purchase_expansion()
	view.progression = reloaded.progression
	view._track_unlocks(0.1)
	_assert_equal(view._reveal_ages.is_empty(), true, "a newly bound session starts without reveal animations")
	view.free()
