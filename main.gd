extends Node2D

# LINE v0.1
# First production loop:
# Generator -> moving unit -> Output -> money

const BACKGROUND_COLOR := Color("#0b1020")
const CONNECTION_COLOR := Color("#334155")
const GENERATOR_COLOR := Color("#38bdf8")
const OUTPUT_COLOR := Color("#22c55e")
const UNIT_COLOR := Color("#f8fafc")
const TEXT_COLOR := Color("#e2e8f0")

var money: float = 0.0

var generator_position := Vector2.ZERO
var output_position := Vector2.ZERO

var production_interval: float = 1.0
var production_timer: float = 0.0

var travel_duration: float = 1.25
var traveling_units: Array[Dictionary] = []


func _ready() -> void:
	get_viewport().size_changed.connect(_update_layout)

	_update_layout()
	queue_redraw()


func _process(delta: float) -> void:
	production_timer += delta

	if production_timer >= production_interval:
		production_timer -= production_interval
		_create_unit()

	_update_units(delta)
	queue_redraw()


func _update_layout() -> void:
	var screen_size := get_viewport_rect().size

	generator_position = Vector2(
		screen_size.x * 0.25,
		screen_size.y * 0.55
	)

	output_position = Vector2(
		screen_size.x * 0.75,
		screen_size.y * 0.55
	)

	queue_redraw()


func _create_unit() -> void:
	var new_unit := {
		"progress": 0.0,
		"value": 1.0
	}

	traveling_units.append(new_unit)


func _update_units(delta: float) -> void:
	for index in range(traveling_units.size() - 1, -1, -1):
		var unit: Dictionary = traveling_units[index]

		unit["progress"] += delta / travel_duration

		if unit["progress"] >= 1.0:
			money += float(unit["value"])
			traveling_units.remove_at(index)
		else:
			traveling_units[index] = unit


func _draw() -> void:
	var screen_size := get_viewport_rect().size

	# Background
	draw_rect(
		Rect2(Vector2.ZERO, screen_size),
		BACKGROUND_COLOR
	)

	# Title and money
	draw_string(
		ThemeDB.fallback_font,
		Vector2(32.0, 52.0),
		"LINE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		32,
		TEXT_COLOR
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(32.0, 98.0),
		"Money: $%.0f" % money,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		28,
		TEXT_COLOR
	)

	# Connection
	draw_line(
		generator_position,
		output_position,
		CONNECTION_COLOR,
		8.0,
		true
	)

	# Generator
	draw_circle(
		generator_position,
		48.0,
		GENERATOR_COLOR
	)

	draw_string(
		ThemeDB.fallback_font,
		generator_position + Vector2(-70.0, 90.0),
		"GENERATOR",
		HORIZONTAL_ALIGNMENT_CENTER,
		140.0,
		20,
		TEXT_COLOR
	)

	# Output
	draw_rect(
		Rect2(
			output_position - Vector2(48.0, 48.0),
			Vector2(96.0, 96.0)
		),
		OUTPUT_COLOR,
		true
	)

	draw_string(
		ThemeDB.fallback_font,
		output_position + Vector2(-70.0, 90.0),
		"OUTPUT",
		HORIZONTAL_ALIGNMENT_CENTER,
		140.0,
		20,
		TEXT_COLOR
	)

	# Traveling units
	for unit in traveling_units:
		var progress: float = float(unit["progress"])

		var unit_position := generator_position.lerp(
			output_position,
			progress
		)

		draw_circle(
			unit_position,
			12.0,
			UNIT_COLOR
		)