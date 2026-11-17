extends Node2D

# LINE v0.4 (Milestone 4: Progression, Objectives, and Persistence)
# Coordinates the game session, workspace view, input controller, HUD, and autosave.
# Rules live in the progression, simulation, and network systems; this script wires signals and saving only.

var _session: GameSession
var _manager: NetworkManager
var _camera := WorkspaceCamera.new()
var _view: NetworkView
var _controller: WorkspaceController
var _hud: Hud
var _ui_timer := 0.0
var _save_dirty := false
var _save_cooldown := 0.0
var _periodic_save_timer := 0.0

const UI_REFRESH_SECONDS := 0.1
const SAVE_COOLDOWN_SECONDS := 0.5
const PERIODIC_SAVE_SECONDS := 30.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(LinePalette.BACKGROUND)

	_camera.setup(get_viewport_rect().size, WorkspaceLayout.get_half_extent())

	_view = NetworkView.new()
	_view.camera = _camera
	add_child(_view)

	_controller = WorkspaceController.new()
	add_child(_controller)

	_hud = Hud.new()
	add_child(_hud)

	get_viewport().size_changed.connect(func() -> void: _camera.set_viewport_size(get_viewport_rect().size))

	_controller.state_changed.connect(_refresh_ui)
	_controller.selection_changed.connect(_on_selection_changed)
	_controller.feedback.connect(_hud.show_feedback)
	_controller.invalid_cell.connect(_view.flash_cell)
	_controller.invalid_connection.connect(_view.flash_connection)

	_hud.placement_requested.connect(_controller.begin_place)
	_hud.connect_requested.connect(_controller.begin_connect)
	_hud.move_requested.connect(_controller.begin_move)
	_hud.upgrade_requested.connect(_controller.request_upgrade)
	_hud.delete_requested.connect(_controller.request_delete)
	_hud.disconnect_requested.connect(_controller.request_disconnect)
	_hud.cancel_requested.connect(_controller.cancel_mode)
	_hud.unlock_requested.connect(_on_unlock_requested)
	_hud.expand_requested.connect(_on_expand_requested)
	_hud.reset_requested.connect(_on_reset_requested)
	_hud.completion_continued.connect(_hud.hide_completion)
	_hud.progress_toggled.connect(func(open: bool) -> void:
		_controller.set_input_enabled(not open)
		_refresh_ui())
	_hud.balance_sheet_toggled.connect(func(open: bool) -> void:
		_controller.set_input_enabled(not open)
		_refresh_ui())
	_hud.balance_mode_requested.connect(_on_balance_mode_requested)
	_hud.booster_model_requested.connect(_on_booster_model_requested)

	# The playtest default applies only to new games and to saves that predate the processing-mode field.
	# Booster coverage defaults to CONTROL, so a save without booster_balance_mode keeps the current Booster.
	var loaded := SaveManager.load_or_new(ProcessingBalance.PLAYTEST_DEFAULT_MODE, BoosterModel.DEFAULT_MODE)
	_bind_session(loaded["session"])
	if loaded["needs_save"]:
		_mark_dirty()
		_save_now()
	if loaded["message"] != "":
		_hud.show_feedback(loaded["message"], true)
	_refresh_ui()


# Connects the views, controller, and session events to one game session. Called at startup and after a reset.
func _bind_session(session: GameSession) -> void:
	_session = session
	_manager = session.network
	_view.graph = _manager.graph
	_view.layout = _manager.layout
	_view.simulation = _manager.simulation
	_view.progression = session.progression
	_controller.setup(_manager, _camera)
	_controller.reset_session_state()

	_manager.payout_received.connect(_on_payout_received)
	session.changed.connect(_mark_dirty)
	session.objective_rewarded.connect(_on_objective_rewarded)
	session.technology_unlocked.connect(_on_technology_unlocked)
	session.workspace_expanded.connect(_on_workspace_expanded)
	session.prototype_completed.connect(_on_prototype_completed)
	_hud.hide_completion()
	if session.is_prototype_completed():
		_hud.show_completion(session)


func _process(delta: float) -> void:
	_session.step(delta)
	_camera.advance(delta)
	# Text and telemetry do not need every frame. Player actions still refresh immediately.
	_ui_timer += delta
	if _ui_timer >= UI_REFRESH_SECONDS:
		_ui_timer = 0.0
		_refresh_ui()
	_tick_autosave(delta)


# Saves shortly after a meaningful change, plus a conservative periodic save. Never every frame.
func _tick_autosave(delta: float) -> void:
	_periodic_save_timer += delta
	if _periodic_save_timer >= PERIODIC_SAVE_SECONDS:
		_periodic_save_timer = 0.0
		_mark_dirty()
	if _save_dirty:
		_save_cooldown -= delta
		if _save_cooldown <= 0.0:
			_save_now()


func _mark_dirty() -> void:
	if not _save_dirty:
		_save_cooldown = SAVE_COOLDOWN_SECONDS
	_save_dirty = true


func _save_now() -> void:
	if _save_dirty and SaveManager.write(_session):
		_save_dirty = false


# Save when the app is closed or sent to the background, so the last moments of play are kept.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_mark_dirty()
		_save_now()


func _refresh_ui() -> void:
	var placing := _controller.mode == WorkspaceController.Mode.PLACE
	var moving := _controller.mode == WorkspaceController.Mode.MOVE

	_view.selected_id = _controller.selected_id
	_view.booster_model = _session.network.simulation.booster_model
	_view.placement_hint = placing or moving
	_view.set_preview_cells(_session.progression.next_expansion_cells() if _hud.is_progress_open() else [])
	_view.preview_source_id = _controller.drag_source_id
	_view.preview_pointer = _controller.drag_pointer_world
	_view.preview_target_id = _controller.drag_target_id
	_view.preview_target_valid = _controller.drag_target_valid
	_hud.refresh(_session, _controller.mode, _controller.placement_type, _controller.selected_id, _controller.delete_armed)


func _on_unlock_requested(id: String) -> void:
	var result := _session.unlock_technology(id)
	match result:
		ProgressionManager.UnlockResult.MISSING_PREREQUISITE:
			_hud.show_feedback("Unlock the previous technology first", true)
		ProgressionManager.UnlockResult.INSUFFICIENT_RP:
			_hud.show_feedback("Not enough Research Points for %s" % id, true)
		ProgressionManager.UnlockResult.ALREADY_UNLOCKED:
			_hud.show_feedback("%s is already unlocked" % id, false)
	_refresh_ui()


func _on_expand_requested() -> void:
	if not _session.purchase_expansion():
		if _session.progression.is_fully_expanded():
			_hud.show_feedback("The workspace is fully expanded", false)
		else:
			_hud.show_feedback("Not enough money for more space", true)
	_refresh_ui()


func _on_workspace_expanded(index: int) -> void:
	_hud.show_feedback("WORKSPACE EXPANDED · %d cells unlocked" % _session.progression.unlocked_cell_count(), false)
	# The camera moves only when none of the newly bought cells are on screen, and never recentres.
	var bought: Array = ProgressionCatalog.EXPANSIONS[index - 1]["cells"]
	var band := _hud.workspace_band(get_viewport_rect().size)
	for cell in bought:
		if _camera.is_visible_in(_manager.layout.get_cell_center(cell), band):
			return
	_camera.reveal_node(_manager.layout.get_cell_center(bought[0]), band)


# Confirmation happens in the progress panel. This only runs after the player confirms.
# The balance-test processing model and Booster model are kept, so repeated fresh runs compare under the same configuration.
func _on_reset_requested() -> void:
	_bind_session(SaveManager.reset_progress(_session.network.simulation.processing_mode, _session.network.simulation.booster_model))
	_refresh_ui()
	_hud.show_feedback("Progress reset. A new game has started.", false)


# Development toggle. Only the processing rule changes; the machine keeps running on the same network.
func _on_balance_mode_requested(mode: int) -> void:
	if _session.network.simulation.processing_mode == mode:
		return
	_session.set_processing_mode(mode)
	_mark_dirty()
	_save_now()
	_hud.show_feedback("Processing model: %s" % ProcessingBalance.short_label(mode), false)
	_refresh_ui()


# Development toggle. Only Booster coverage changes; nothing is built, removed, moved, or paid for.
func _on_booster_model_requested(mode: int) -> void:
	if _session.network.simulation.booster_model == mode:
		return
	_session.set_booster_model(mode)
	_mark_dirty()
	_save_now()
	_hud.show_feedback("Booster model: %s" % BoosterModel.label(mode), false)
	_refresh_ui()


func _on_objective_rewarded(id: String, money_text: String, research_points: int) -> void:
	var objective: Dictionary = ProgressionCatalog.OBJECTIVES[ProgressionCatalog.objective_index(id)]
	var rewards: Array[String] = []
	if money_text != "0":
		rewards.append("+%s" % NumberFormat.money(LargeNumber.from_text(money_text)))
	if research_points > 0:
		rewards.append("+%d RP" % research_points)
	var reward_line := "  ·  ".join(PackedStringArray(rewards))
	_hud.show_priority_feedback("OBJECTIVE COMPLETE · %s%s" % [objective["title"], "\n" + reward_line if reward_line != "" else ""])


func _on_technology_unlocked(id: String) -> void:
	var tech: Dictionary = ProgressionCatalog.TECHNOLOGIES[ProgressionCatalog.technology_index(id)]
	_hud.show_priority_feedback("TECHNOLOGY UNLOCKED · %s\n%s" % [id, tech["summary"]])


func _on_prototype_completed() -> void:
	_hud.show_completion(_session)


func _on_selection_changed(id: int) -> void:
	_refresh_ui()
	if id == 0:
		return
	# The inspector's height is only known after layout, so the correction waits two frames.
	await get_tree().process_frame
	await get_tree().process_frame
	if _controller.selected_id != id or not _manager.graph.has_node(id):
		return
	var world := _manager.layout.get_cell_center(_manager.layout.get_node_cell(id))
	_camera.reveal_node(world, _hud.workspace_band(get_viewport_rect().size))


func _on_payout_received(amount: LargeNumber, output_id: int, complexity: int) -> void:
	_view.show_payout(amount, output_id, complexity)
	_hud.pulse_money(complexity)
