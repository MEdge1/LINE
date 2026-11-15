class_name NetworkView
extends Node2D

# Draws the production network from simulation state. Owns layout only; it never
# changes simulation values.

const NODE_RADIUS := 48.0
const SELECTION_RADIUS := 62.0
const UNIT_RADIUS := 12.0
const CONNECTION_WIDTH := 8.0
const ARROW_SIZE := 16.0
const LABEL_WIDTH := 160.0
const LABEL_FONT_SIZE := 20

var simulation: ProductionSimulation
var generator_selected: bool = false

var _generator_position := Vector2.ZERO
var _processor_position := Vector2.ZERO
var _output_position := Vector2.ZERO


func _ready() -> void:
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func _process(_delta: float) -> void:
	queue_redraw()


func is_generator_hit(point: Vector2) -> bool:
	return point.distance_to(_generator_position) <= LineBalance.NODE_HIT_RADIUS


func _update_layout() -> void:
	var screen_size := get_viewport_rect().size
	var row_y := screen_size.y * 0.5

	_generator_position = Vector2(screen_size.x * 0.16, row_y)
	_processor_position = Vector2(screen_size.x * 0.5, row_y)
	_output_position = Vector2(screen_size.x * 0.84, row_y)


func _draw() -> void:
	_draw_connection(_generator_position, _processor_position)
	_draw_connection(_processor_position, _output_position)

	_draw_generator()
	_draw_processor()
	_draw_output()

	if simulation == null:
		return

	for unit in simulation.units:
		_draw_unit(unit)


func _draw_connection(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, LinePalette.CONNECTION, CONNECTION_WIDTH, true)

	var direction := (to - from).normalized()
	var perpendicular := direction.orthogonal()
	var tip := to - direction * (NODE_RADIUS + 6.0)
	var base := tip - direction * ARROW_SIZE

	draw_colored_polygon(
		PackedVector2Array([
			tip,
			base + perpendicular * ARROW_SIZE * 0.5,
			base - perpendicular * ARROW_SIZE * 0.5,
		]),
		LinePalette.CONNECTION
	)


func _draw_generator() -> void:
	if generator_selected:
		draw_arc(
			_generator_position,
			SELECTION_RADIUS,
			0.0,
			TAU,
			64,
			LinePalette.SELECTION,
			4.0,
			true
		)

	draw_circle(_generator_position, NODE_RADIUS, LinePalette.GENERATOR)
	_draw_label(_generator_position, "GENERATOR")


func _draw_processor() -> void:
	var center := _processor_position
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -NODE_RADIUS),
		center + Vector2(NODE_RADIUS, 0.0),
		center + Vector2(0.0, NODE_RADIUS),
		center + Vector2(-NODE_RADIUS, 0.0),
	])

	draw_colored_polygon(diamond, LinePalette.PROCESSOR)
	_draw_label(center, "PROCESSOR")


func _draw_output() -> void:
	draw_rect(
		Rect2(
			_output_position - Vector2(NODE_RADIUS, NODE_RADIUS),
			Vector2(NODE_RADIUS, NODE_RADIUS) * 2.0
		),
		LinePalette.OUTPUT,
		true
	)
	_draw_label(_output_position, "OUTPUT")


func _draw_unit(unit: ProductionSimulation.Unit) -> void:
	var unit_position: Vector2

	if unit.leg == 0:
		unit_position = _generator_position.lerp(_processor_position, unit.progress)
	else:
		unit_position = _processor_position.lerp(_output_position, unit.progress)

	var color := LinePalette.UNIT if unit.value == LineBalance.UNIT_START_VALUE else LinePalette.PROCESSED_UNIT
	draw_circle(unit_position, UNIT_RADIUS, color)


func _draw_label(center: Vector2, text: String) -> void:
	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-LABEL_WIDTH * 0.5, NODE_RADIUS + 40.0),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		LABEL_WIDTH,
		LABEL_FONT_SIZE,
		LinePalette.TEXT
	)
