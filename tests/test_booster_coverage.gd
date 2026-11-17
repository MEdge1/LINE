extends SceneTree

# Focused checks for Booster coverage models (CONTROL, CHAIN B, CHAIN C, RADIUS B), non-stacking ownership,
# coverage updates after network edits, mode switching, and save fields. Processing rules are covered elsewhere.
#
# The workspace is 5 columns by 9 rows. Chains run down column 0 (generator at y=0, Processors at y=1..count, Output
# after them). Boosters sit in column 1 beside the Processor they should cover.

var _failures := 0


func _init() -> void:
	_test_control_is_orthogonal_only()
	_test_chain_reach_is_two_hops_from_entry()
	_test_chain_c_has_same_coverage_as_chain_b()
	_test_radius_b_is_manhattan_two_and_includes_separate_networks()
	_test_chain_excludes_unconnected_network()
	_test_connection_removal_and_creation_update_coverage()
	_test_booster_movement_updates_coverage()
	_test_processor_movement_updates_control_coverage()
	_test_deletion_removes_effect()
	_test_non_stacking_single_owner()
	_test_all_modes_keep_the_bonus()
	_test_mode_switch_keeps_money_and_conserves_value()
	_test_save_round_trip_and_fallbacks()
	_test_reset_keeps_booster_mode()
	print("BOOSTER COVERAGE TESTS failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		push_error("FAIL %s: expected %s, got %s" % [message, str(expected), str(actual)])


func _assert_true(condition: bool, message: String) -> void:
	_assert_equal(condition, true, message)


func _network() -> NetworkManager:
	var manager := NetworkManager.new()
	manager.simulation.money = LargeNumber.from_int(100000000)
	return manager


func _place(manager: NetworkManager, type: int, cell: Vector2i) -> int:
	var result := manager.construct(type, cell)
	if result != NetworkManager.PlacementResult.OK:
		push_error("placement failed at %s: %d" % [str(cell), result])
		return 0
	return manager.layout.get_node_at(cell)


# Generator at (0,0), Processors at (0,1..count) connected in order, Output at (0,count+1).
func _chain(count: int) -> Dictionary:
	var manager := _network()
	var generator := _place(manager, NodeDefinitions.Type.GENERATOR, Vector2i(0, 0))
	var processors: Array = []
	var previous := generator
	for index in range(count):
		var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(0, index + 1))
		manager.connect_nodes(previous, processor)
		processors.append(processor)
		previous = processor
	var output := _place(manager, NodeDefinitions.Type.OUTPUT, Vector2i(0, count + 1))
	manager.connect_nodes(previous, output)
	return {"manager": manager, "generator": generator, "processors": processors, "output": output}


func _test_control_is_orthogonal_only() -> void:
	var network := _chain(5)
	var manager: NetworkManager = network["manager"]
	var processors: Array = network["processors"]
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 3))
	_assert_equal(manager.get_boost_targets(booster), [processors[2]], "CONTROL covers only the orthogonal Processor beside the Booster")
	_assert_equal(manager.graph.get_node(processors[1]).boosted, false, "a Processor one hop away is not boosted under CONTROL")


func _test_chain_reach_is_two_hops_from_entry() -> void:
	var network := _chain(7)
	var manager: NetworkManager = network["manager"]
	var processors: Array = network["processors"]
	manager.set_booster_model(BoosterModel.Mode.CHAIN_B)
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 4))
	var expected := [processors[1], processors[2], processors[3], processors[4], processors[5]]
	expected.sort()
	_assert_equal(manager.get_boost_targets(booster), expected, "CHAIN B covers the entry and Processors within two hops in either direction")
	_assert_equal(manager.graph.get_node(processors[0]).boosted, false, "a Processor three hops away is excluded")
	_assert_equal(manager.graph.get_node(processors[6]).boosted, false, "the far end Processor is excluded")


func _test_chain_c_has_same_coverage_as_chain_b() -> void:
	var network := _chain(7)
	var manager: NetworkManager = network["manager"]
	manager.set_booster_model(BoosterModel.Mode.CHAIN_C)
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 4))
	_assert_equal(manager.get_boost_targets(booster).size(), 5, "CHAIN C covers the same five Processors as CHAIN B")
	_assert_equal(BoosterModel.relief_spec(BoosterModel.Mode.CHAIN_C)["fraction"], BoosterModel.RELIEF_FRACTION_C, "CHAIN C uses its own relief fraction")
	_assert_equal(BoosterModel.relief_spec(BoosterModel.Mode.CHAIN_B)["fraction"], BoosterModel.RELIEF_FRACTION_B, "CHAIN B uses its own relief fraction")


func _test_radius_b_is_manhattan_two_and_includes_separate_networks() -> void:
	var manager := _network()
	var near := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(2, 5))
	var second := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(4, 4))
	var far := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(4, 6))
	manager.set_booster_model(BoosterModel.Mode.RADIUS_B)
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(2, 4))
	var covered: Array = manager.get_boost_targets(booster)
	_assert_true(covered.has(near), "RADIUS B covers a Processor at Manhattan distance 1")
	_assert_true(covered.has(second), "RADIUS B covers a Processor at Manhattan distance 2")
	_assert_equal(covered.has(far), false, "RADIUS B excludes a Processor at Manhattan distance 4")


func _test_chain_excludes_unconnected_network() -> void:
	var network := _chain(3)
	var manager: NetworkManager = network["manager"]
	var processors: Array = network["processors"]
	var separate := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(3, 3))
	manager.set_booster_model(BoosterModel.Mode.CHAIN_B)
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 3))
	var covered: Array = manager.get_boost_targets(booster)
	_assert_equal(covered.has(separate), false, "CHAIN coverage excludes a nearby Processor that is not connected")
	_assert_true(covered.has(processors[2]), "CHAIN coverage still includes the connected entry")
	manager.set_booster_model(BoosterModel.Mode.RADIUS_B)
	_assert_true(manager.get_boost_targets(booster).has(separate), "RADIUS coverage includes the nearby separate Processor")


func _test_connection_removal_and_creation_update_coverage() -> void:
	var network := _chain(7)
	var manager: NetworkManager = network["manager"]
	var processors: Array = network["processors"]
	manager.set_booster_model(BoosterModel.Mode.CHAIN_B)
	_place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 3))
	_assert_true(manager.graph.get_node(processors[4]).boosted, "the Processor two hops away is covered before the edge is removed")
	manager.disconnect_nodes(processors[3], processors[4])
	_assert_equal(manager.graph.get_node(processors[4]).boosted, false, "removing the connection drops the cut-off Processor from coverage")
	manager.connect_nodes(processors[3], processors[4])
	_assert_true(manager.graph.get_node(processors[4]).boosted, "recreating the connection restores coverage")


func _test_booster_movement_updates_coverage() -> void:
	var network := _chain(7)
	var manager: NetworkManager = network["manager"]
	var processors: Array = network["processors"]
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 2))
	_assert_equal(manager.get_boost_targets(booster), [processors[1]], "CONTROL before movement covers the Processor at y=2")
	manager.move_node(booster, Vector2i(1, 6))
	_assert_equal(manager.get_boost_targets(booster), [processors[5]], "moving the Booster moves its coverage to the new neighbour")
	_assert_equal(manager.graph.get_node(processors[1]).boosted, false, "the old Processor loses its boost after the Booster moves")


func _test_processor_movement_updates_control_coverage() -> void:
	var network := _chain(5)
	var manager: NetworkManager = network["manager"]
	var processors: Array = network["processors"]
	_place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 3))
	_assert_true(manager.graph.get_node(processors[2]).boosted, "the Processor beside the Booster is boosted before it moves")
	manager.move_node(processors[2], Vector2i(4, 8))
	_assert_equal(manager.graph.get_node(processors[2]).boosted, false, "moving the Processor away removes its boost")


func _test_deletion_removes_effect() -> void:
	var network := _chain(5)
	var manager: NetworkManager = network["manager"]
	var processors: Array = network["processors"]
	manager.set_booster_model(BoosterModel.Mode.CHAIN_B)
	var booster := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 3))
	_assert_true(manager.graph.get_node(processors[0]).boosted, "the chain is boosted before deletion")
	manager.delete_node(booster)
	_assert_equal(manager.boosted_processor_count(), 0, "deleting the Booster removes its effect from every Processor")


# Two Boosters beside one free Processor: one owner (lowest id), and the +25% bonus applies once.
func _test_non_stacking_single_owner() -> void:
	var manager := _network()
	var processor := _place(manager, NodeDefinitions.Type.PROCESSOR, Vector2i(2, 4))
	var first := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 4))
	var second := _place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(3, 4))
	var owners := BoosterCoverage.owners(manager.graph, manager.layout, BoosterModel.Mode.CONTROL)
	_assert_equal(owners[processor], min(first, second), "the lowest Booster id owns a Processor covered by two Boosters")
	_assert_equal(manager.graph.get_node(processor).boost_owner, min(first, second), "the owner id is stored on the Processor")
	var base := NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR)
	_assert_true(is_equal_approx(manager.simulation.get_capacity(processor), base * (1.0 + LineBalance.BOOSTER_BONUS)), "two covering Boosters apply the +25% bonus once")


func _test_all_modes_keep_the_bonus() -> void:
	var base := NodeDefinitions.get_capacity(NodeDefinitions.Type.PROCESSOR)
	for mode in BoosterModel.all_modes():
		var network := _chain(3)
		var manager: NetworkManager = network["manager"]
		var processors: Array = network["processors"]
		manager.set_booster_model(mode)
		_place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 2))
		_assert_true(is_equal_approx(manager.simulation.get_capacity(processors[1]), base * (1.0 + LineBalance.BOOSTER_BONUS)), "%s keeps the +25%% bonus" % BoosterModel.label(mode))


func _test_mode_switch_keeps_money_and_conserves_value() -> void:
	var network := _chain(7)
	var manager: NetworkManager = network["manager"]
	_place(manager, NodeDefinitions.Type.BOOSTER, Vector2i(1, 4))
	for _step in range(2000):
		manager.step(0.05)
	var money_before := manager.simulation.money.to_text()
	manager.set_booster_model(BoosterModel.Mode.CHAIN_B)
	_assert_equal(manager.simulation.money.to_text(), money_before, "switching the Booster model does not change money")
	for _step in range(2000):
		manager.step(0.05)
	var accounted := manager.simulation.paid_units.add(manager.simulation.get_held_units()).add(manager.simulation.lost_units)
	_assert_equal(accounted.compare(manager.simulation.produced_units), 0, "conservation holds across a model switch")


func _test_save_round_trip_and_fallbacks() -> void:
	SaveManager.path = "user://test_booster_coverage_save.json"
	var session := GameSession.new_game(ProcessingBalance.Mode.EXPONENTIAL_CANDIDATE_1, BoosterModel.Mode.CHAIN_C)
	var text := JSON.stringify(SaveManager.serialize(session))
	var parsed := SaveManager.parse(text)
	_assert_equal(parsed.has("error"), false, "a saved session with a Booster model parses")
	_assert_equal(parsed["session"].network.simulation.booster_model, BoosterModel.Mode.CHAIN_C, "the Booster model survives a save and load")

	var legacy: Dictionary = JSON.parse_string(text)
	legacy.erase("booster_balance_mode")
	var old_parse := SaveManager.parse(JSON.stringify(legacy))
	_assert_equal(old_parse["session"].network.simulation.booster_model, BoosterModel.DEFAULT_MODE, "an old save without the Booster field loads as CONTROL")

	_assert_equal(BoosterModel.mode_from_save_name("NOT_A_MODE"), BoosterModel.DEFAULT_MODE, "an unknown Booster name falls back to CONTROL")
	_assert_equal(BoosterModel.mode_from_save_name(null), BoosterModel.DEFAULT_MODE, "a missing Booster name falls back to CONTROL")
	SaveManager.path = "user://savegame.json"


func _test_reset_keeps_booster_mode() -> void:
	SaveManager.path = "user://test_booster_coverage_reset.json"
	var fresh := SaveManager.reset_progress(ProcessingBalance.Mode.LIVE_HYPERBOLIC, BoosterModel.Mode.CHAIN_C)
	_assert_equal(fresh.network.simulation.booster_model, BoosterModel.Mode.CHAIN_C, "Reset Progress keeps the selected Booster model")
	SaveManager.path = "user://savegame.json"
