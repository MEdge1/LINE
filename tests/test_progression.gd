extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_progression.gd
# Progression rules, objectives, unlocks, expansion, and a scripted first-run playthrough that
# checks the intended objective sequence cannot deadlock. Prints pacing for balancing.

const STEP := 0.1
const PHASE_LIMIT_SECONDS := 3600.0

var _failures := 0


func _init() -> void:
	_test_new_game_starts_small()
	_test_research_point_ledger_is_reachable_in_order()
	_test_technology_unlock_spends_research_points_once()
	_test_locked_technology_cannot_be_constructed()
	_test_locked_cell_rejects_placement_and_move()
	_test_expansion_costs_money_and_unlocks_cells()
	_test_objective_rewards_and_completion_follow_prerequisites()
	_test_objective_progress_uses_authoritative_counters()
	_test_playthrough_reaches_the_prototype_end()

	if _failures == 0:
		print("All progression tests passed.")
	else:
		printerr("%d progression assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _step(session: GameSession, seconds: float) -> void:
	for _i in range(int(round(seconds / STEP))):
		session.step(STEP)


# Steps the session until the predicate holds, or the limit passes. Returns true if it held.
func _wait_until(session: GameSession, predicate: Callable, limit: float) -> bool:
	var elapsed := 0.0
	while elapsed < limit:
		if predicate.call():
			return true
		session.step(STEP)
		elapsed += STEP
	return predicate.call()


func _place(session: GameSession, type: int, cell: Vector2i) -> int:
	session.network.construct(type, cell)
	return session.network.layout.get_node_at(cell)


func _connect(session: GameSession, from_id: int, to_id: int) -> bool:
	return session.network.connect_nodes(from_id, to_id) == NetworkGraph.Rejection.NONE


func _objective_done(session: GameSession, id: String) -> bool:
	return session.objectives.is_completed(id)


func _test_new_game_starts_small() -> void:
	var session := GameSession.new_game()
	var progression := session.progression
	_assert_equal(session.network.simulation.money.to_text(), str(LineBalance.START_MONEY), "a new game starts with the configured money")
	_assert_equal(progression.research_points, 0, "a new game starts with 0 Research Points")
	_assert_equal(progression.is_type_unlocked(NodeDefinitions.Type.GENERATOR), true, "Generator is unlocked at the start")
	_assert_equal(progression.is_type_unlocked(NodeDefinitions.Type.OUTPUT), true, "Output is unlocked at the start")
	for type in [NodeDefinitions.Type.PROCESSOR, NodeDefinitions.Type.SPLITTER, NodeDefinitions.Type.MERGER, NodeDefinitions.Type.BOOSTER]:
		_assert_equal(progression.is_type_unlocked(type), false, "%s starts locked" % NodeDefinitions.get_display_name(type))
	_assert_equal(progression.unlocked_cell_count(), 9, "the workspace starts as a 3×3 region")
	_assert_equal(session.objectives.active_id(), "build_generator", "the first objective is to build a Generator")
	_assert_equal(session.network.graph.get_node_ids().size(), 0, "a new game starts with an empty network")
	_assert_equal(session.stats.counter("revenue").is_zero(), true, "statistics start at zero")


# Each Research Point source must arrive before the unlock that needs it, so the sequence can always finish.
func _test_research_point_ledger_is_reachable_in_order() -> void:
	# Research Points are spent when an unlock objective is completed, so they must be available before its reward.
	var balance := 0
	for objective in ProgressionCatalog.OBJECTIVES:
		for tech in ProgressionCatalog.TECHNOLOGIES:
			if _unlock_objective_for(tech["id"]) == objective["id"]:
				balance -= int(tech["cost"])
				_assert_equal(balance >= 0, true, "Research Points cover the %s unlock" % tech["id"])
		balance += int(objective["reward_rp"])
	var total_cost := 0
	for tech in ProgressionCatalog.TECHNOLOGIES:
		total_cost += int(tech["cost"])
	var total_reward := 0
	for objective in ProgressionCatalog.OBJECTIVES:
		total_reward += int(objective["reward_rp"])
	_assert_equal(total_reward >= total_cost, true, "the objectives award enough Research Points for every technology")


func _unlock_objective_for(tech_id: String) -> String:
	for objective in ProgressionCatalog.OBJECTIVES:
		for condition in objective["conditions"]:
			if condition["type"] == "UNLOCK_TECH" and condition["tech"] == tech_id:
				return objective["id"]
	return ""


func _test_technology_unlock_spends_research_points_once() -> void:
	var progression := ProgressionManager.new_game()
	progression.add_research_points(1)
	_assert_equal(progression.unlock_technology("PROCESSOR"), ProgressionManager.UnlockResult.OK, "a technology with enough RP unlocks")
	_assert_equal(progression.research_points, 0, "the unlock spends its cost exactly once")
	_assert_equal(progression.unlock_technology("PROCESSOR"), ProgressionManager.UnlockResult.ALREADY_UNLOCKED, "an unlocked technology cannot be bought again")
	_assert_equal(progression.research_points, 0, "a refused repeat unlock spends nothing")
	_assert_equal(progression.unlock_technology("SPLITTER"), ProgressionManager.UnlockResult.INSUFFICIENT_RP, "an unlock without enough RP is refused")

	var blocked := ProgressionManager.new_game()
	blocked.add_research_points(5)
	_assert_equal(blocked.unlock_technology("SPLITTER"), ProgressionManager.UnlockResult.MISSING_PREREQUISITE, "a technology needs its prerequisite first")


func _test_locked_technology_cannot_be_constructed() -> void:
	var session := GameSession.new_game()
	var result := session.network.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(2, 4))
	_assert_equal(result, NetworkManager.PlacementResult.TECHNOLOGY_LOCKED, "a locked Processor cannot be built")
	_assert_equal(session.network.graph.get_node_ids().size(), 0, "a refused locked build adds nothing")
	_assert_equal(session.network.simulation.money.to_text(), str(LineBalance.START_MONEY), "a refused locked build spends nothing")
	session.progression.add_research_points(1)
	session.unlock_technology("PROCESSOR")
	_assert_equal(session.network.construct(NodeDefinitions.Type.PROCESSOR, Vector2i(2, 4)), NetworkManager.PlacementResult.OK, "an unlocked Processor can be built")


func _test_locked_cell_rejects_placement_and_move() -> void:
	var session := GameSession.new_game()
	_assert_equal(session.network.construct(NodeDefinitions.Type.GENERATOR, Vector2i(0, 0)), NetworkManager.PlacementResult.CELL_LOCKED, "a locked cell rejects placement")
	_assert_equal(session.network.construct(NodeDefinitions.Type.GENERATOR, Vector2i(2, 4)), NetworkManager.PlacementResult.OK, "an unlocked cell accepts placement")
	var generator := session.network.layout.get_node_at(Vector2i(2, 4))
	_assert_equal(session.network.move_node(generator, Vector2i(4, 8)), NetworkManager.PlacementResult.CELL_LOCKED, "a node cannot be moved into a locked cell")


func _test_expansion_costs_money_and_unlocks_cells() -> void:
	var session := GameSession.new_game()
	var money_before := session.network.simulation.money.to_text()
	_assert_equal(session.purchase_expansion(), false, "expansion is refused without the money")
	session.network.simulation.money = LargeNumber.from_int(1000)
	_assert_equal(session.purchase_expansion(), true, "the first expansion is bought with money")
	_assert_equal(session.network.simulation.money.to_text(), str(1000 - 150), "expansion costs exactly its configured money")
	_assert_equal(session.progression.unlocked_cell_count(), 9 + 3, "the first expansion unlocks its cells")
	_assert_equal(session.progression.is_cell_unlocked(Vector2i(2, 2)), true, "the expanded row is available")
	_assert_equal(money_before != "0", true, "the starting money was positive")


func _test_objective_rewards_and_completion_follow_prerequisites() -> void:
	var session := GameSession.new_game()
	var gen := _place(session, NodeDefinitions.Type.GENERATOR, Vector2i(1, 4))
	_step(session, 0.2)
	_assert_equal(_objective_done(session, "build_generator"), true, "building a Generator completes its objective")
	_assert_equal(session.objectives.active_id(), "build_output", "the next objective follows the sequence")
	_assert_equal(gen != 0, true, "the Generator exists")
	_assert_equal(session.network.simulation.money.to_text(), str(LineBalance.START_MONEY - 25 + 20), "the Generator objective pays its money reward")


func _test_objective_progress_uses_authoritative_counters() -> void:
	var session := GameSession.new_game()
	_place(session, NodeDefinitions.Type.GENERATOR, Vector2i(1, 4))
	_step(session, 0.2)
	var description := session.objectives.describe(session)
	_assert_equal(description["id"], "build_output", "the tracker moves on once the objective is finished")
	_assert_equal(description["progress"].find("0 / 1") >= 0, true, "progress is read from the build counter")
	_place(session, NodeDefinitions.Type.OUTPUT, Vector2i(3, 4))
	_step(session, 0.2)
	_assert_equal(session.objectives.is_completed("build_output"), true, "the Output objective completes from the build counter")

	# Removing a node after building it does not undo a completed build objective.
	session.network.delete_node(session.network.layout.get_node_at(Vector2i(1, 4)))
	_step(session, 0.2)
	_assert_equal(session.objectives.is_completed("build_generator"), true, "a completed objective stays completed")


# Scripted first run through every objective. It uses only public game APIs and waits for the
# game's own rules, so any objective that cannot be finished, or any unlock that cannot be paid for,
# fails the test. Pacing for each objective is printed for balancing.
func _test_playthrough_reaches_the_prototype_end() -> void:
	var session := GameSession.new_game()
	var network := session.network
	var simulation := network.simulation
	var progression := session.progression
	var failed := ""

	var generator := _place(session, NodeDefinitions.Type.GENERATOR, Vector2i(1, 4))
	var output := _place(session, NodeDefinitions.Type.OUTPUT, Vector2i(3, 4))
	_connect(session, generator, output)
	failed = _require(session, "connect_line", failed)
	failed = _require(session, "earn_100", failed, func() -> void: pass)

	_wait_until(session, func() -> bool: return simulation.can_afford_upgrade(generator), PHASE_LIMIT_SECONDS)
	network.upgrade_node(generator)
	failed = _require(session, "upgrade_generator", failed)

	failed = _require(session, "unlock_processing", failed, func() -> void: session.unlock_technology("PROCESSOR"))

	var processor := _place(session, NodeDefinitions.Type.PROCESSOR, Vector2i(2, 4))
	network.disconnect_nodes(generator, output)
	_connect(session, generator, processor)
	_connect(session, processor, output)
	failed = _require(session, "build_processor", failed)
	failed = _require(session, "process_10", failed)
	failed = _require(session, "complexity_1", failed)

	failed = _require(session, "unlock_splitting", failed, func() -> void: session.unlock_technology("SPLITTER"))
	_place(session, NodeDefinitions.Type.SPLITTER, Vector2i(2, 3))
	failed = _require(session, "build_splitter", failed)
	_place(session, NodeDefinitions.Type.PROCESSOR, Vector2i(1, 3))
	_place(session, NodeDefinitions.Type.PROCESSOR, Vector2i(3, 3))
	failed = _require(session, "build_branches", failed)

	failed = _require(session, "unlock_merging", failed, func() -> void: session.unlock_technology("MERGER"))
	_place(session, NodeDefinitions.Type.MERGER, Vector2i(1, 5))
	failed = _require(session, "build_merger", failed)

	# Level 6 Generator (2.25/s) so completed units per second clear the 2.0 target with margin.
	while network.graph.get_node(generator).level < 6:
		_wait_until(session, func() -> bool: return simulation.can_afford_upgrade(generator), PHASE_LIMIT_SECONDS)
		network.upgrade_node(generator)
	failed = _require(session, "throughput_2", failed)

	failed = _require(session, "unlock_boosting", failed, func() -> void: session.unlock_technology("BOOSTER"))
	_place(session, NodeDefinitions.Type.BOOSTER, Vector2i(2, 5))
	failed = _require(session, "use_booster", failed)
	failed = _require(session, "bottleneck_free", failed)

	for _i in range(2):
		_wait_until(session, func() -> bool: return simulation.can_afford(LargeNumber.from_int(int(ProgressionCatalog.EXPANSIONS[session.progression.expansion_index]["cost"]))), PHASE_LIMIT_SECONDS)
		session.purchase_expansion()
	failed = _require(session, "expand_space", failed)

	# Final stage: buy the rest of the space needed for the stable-network conditions, then a deep chain.
	while progression.unlocked_cell_count() < 25 and not progression.is_fully_expanded():
		_wait_until(session, func() -> bool: return simulation.can_afford(LargeNumber.from_int(progression.next_expansion_cost())), PHASE_LIMIT_SECONDS)
		session.purchase_expansion()
	network.disconnect_nodes(processor, output)
	var previous := processor
	var chain: Array = []
	for cell in progression.unlocked_cells():
		if chain.size() >= 9:
			break
		if network.layout.is_cell_free(cell):
			chain.append(cell)
	for cell in chain:
		_wait_until(session, func() -> bool: return simulation.can_afford(LargeNumber.from_int(NodeDefinitions.get_cost(NodeDefinitions.Type.PROCESSOR))), PHASE_LIMIT_SECONDS)
		var node := _place(session, NodeDefinitions.Type.PROCESSOR, cell)
		_connect(session, previous, node)
		previous = node
	_connect(session, previous, output)
	for attempt in range(6):
		if _objective_done(session, ProgressionCatalog.FINAL_OBJECTIVE):
			break
		_step(session, 60.0)
		_add_booster_beside_deepest_processor(session)
	failed = _require(session, ProgressionCatalog.FINAL_OBJECTIVE, failed)

	_assert_equal(failed, "", "every objective in the intended sequence can be completed")
	_assert_equal(session.is_prototype_completed(), true, "the prototype ends in the completion objective")
	_print_pacing(session)


# Waits for an objective to complete, optionally running an action first. Returns the failure label on timeout.
func _require(session: GameSession, id: String, failed: String, action: Callable = Callable()) -> String:
	if failed != "":
		return failed
	if action.is_valid():
		action.call()
	if _wait_until(session, func() -> bool: return _objective_done(session, id), PHASE_LIMIT_SECONDS):
		return ""
	printerr("FAIL: objective %s could not be completed (active: %s)" % [id, session.objectives.active_id()])
	return id


func _add_booster_beside_deepest_processor(session: GameSession) -> void:
	var network := session.network
	var processors: Array = []
	for id in network.graph.get_node_ids():
		if network.graph.get_node(id).type == NodeDefinitions.Type.PROCESSOR:
			processors.append(id)
	processors.reverse()
	for processor in processors:
		var cell: Vector2i = network.layout.get_node_cell(processor)
		for offset in WorkspaceLayout.NEIGHBOR_OFFSETS:
			var neighbour: Vector2i = cell + offset
			if session.progression.is_cell_unlocked(neighbour) and network.layout.is_cell_free(neighbour) and network.layout.contains_cell(neighbour):
				_wait_until(session, func() -> bool: return network.simulation.can_afford(LargeNumber.from_int(NodeDefinitions.get_cost(NodeDefinitions.Type.BOOSTER))), PHASE_LIMIT_SECONDS)
				_place(session, NodeDefinitions.Type.BOOSTER, neighbour)
				return


func _print_pacing(session: GameSession) -> void:
	for objective in ProgressionCatalog.OBJECTIVES:
		var key: String = "objective." + objective["id"]
		var when: float = session.stats.first_times.get(key, -1.0)
		print("PACING %-20s done at %7.1f s of play" % [objective["id"], when])
	print("PACING total play time %.1f s · revenue %s · highest complexity %d · nodes %d" % [
		session.play_seconds, session.stats.counter("revenue").to_text(), session.stats.highest_complexity,
		session.network.graph.get_node_ids().size(),
	])
