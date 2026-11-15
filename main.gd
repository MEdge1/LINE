extends Node2D

# LINE v0.2 (Milestone 1: The Living Production Line)
# Generator -> Processor (x2) -> Output -> money
# Owns the simulation and wires input, presentation, and UI together.

var _simulation := ProductionSimulation.new()
var _view: NetworkView
var _hud: Hud


func _ready() -> void:
	RenderingServer.set_default_clear_color(LinePalette.BACKGROUND)

	_view = NetworkView.new()
	_view.simulation = _simulation
	add_child(_view)

	_hud = Hud.new()
	_hud.upgrade_pressed.connect(_on_upgrade_pressed)
	add_child(_hud)

	_simulation.payout_received.connect(_on_payout_received)
	_hud.refresh(_simulation, _view.generator_selected)


func _process(delta: float) -> void:
	_simulation.step(delta)
	_hud.refresh(_simulation, _view.generator_selected)


func _unhandled_input(event: InputEvent) -> void:
	# Touch input arrives as emulated mouse input (project default), so one path covers both.
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	_view.generator_selected = _view.is_generator_hit(mouse_event.position)
	_hud.refresh(_simulation, _view.generator_selected)


func _on_upgrade_pressed() -> void:
	_simulation.upgrade_generator()
	_hud.refresh(_simulation, _view.generator_selected)


func _on_payout_received(amount: int) -> void:
	_view.show_payout(amount)
	_hud.pulse_money()
