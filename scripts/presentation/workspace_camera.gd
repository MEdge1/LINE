class_name WorkspaceCamera
extends RefCounted

# Pan and zoom for the workspace. Converts between screen and world coordinates.

const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.6
const INITIAL_ZOOM := 0.9
const EDGE_MARGIN := 160.0
# Vertical screen position of the world origin, above the bottom UI.
const HOME_Y_RATIO := 0.42
# Eased correction used to reveal a node hidden by a panel.
const REVEAL_SECONDS := 0.25
# Screen pixels kept clear between a revealed node and the edge of the usable band.
const REVEAL_MARGIN := 24.0
# World radius kept visible around a selected node, including its selection ring.
const REVEAL_NODE_RADIUS := 60.0

var zoom: float = INITIAL_ZOOM
var offset := Vector2.ZERO

var _viewport_size := Vector2.ZERO
var _world_extent := Vector2.ZERO
var _revealing := false
var _reveal_from := Vector2.ZERO
var _reveal_to := Vector2.ZERO
var _reveal_elapsed := 0.0


func setup(viewport_size: Vector2, world_extent: Vector2) -> void:
	_world_extent = world_extent
	set_viewport_size(viewport_size)
	offset = _home()


func set_viewport_size(viewport_size: Vector2) -> void:
	_viewport_size = viewport_size
	_clamp_offset()


func world_to_screen(world: Vector2) -> Vector2:
	return offset + world * zoom


func screen_to_world(screen: Vector2) -> Vector2:
	return (screen - offset) / zoom


# A deliberate player pan always wins over an automatic reveal in progress.
func pan(screen_delta: Vector2) -> void:
	cancel_reveal()
	offset += screen_delta
	_clamp_offset()


# Moves the camera only as far as needed to bring a selected node inside the usable band.
# A node that is already fully visible causes no movement, so the player's view is preserved.
func reveal_node(world: Vector2, band: Rect2) -> void:
	var delta := reveal_delta(world_to_screen(world), REVEAL_NODE_RADIUS * zoom, band, REVEAL_MARGIN)
	if delta == Vector2.ZERO:
		return
	_start_reveal(offset + delta)


# Pure: the screen-space displacement that brings a circle fully inside the band, with a margin.
static func reveal_delta(center: Vector2, radius: float, band: Rect2, margin: float) -> Vector2:
	return Vector2(
		_axis_shift(center.x, radius, band.position.x, band.end.x, margin),
		_axis_shift(center.y, radius, band.position.y, band.end.y, margin)
	)


# Advances an in-progress reveal with ease-out. Call once per frame.
func advance(delta: float) -> void:
	if not _revealing:
		return
	_reveal_elapsed += delta
	var t := clampf(_reveal_elapsed / REVEAL_SECONDS, 0.0, 1.0)
	offset = _reveal_from.lerp(_reveal_to, 1.0 - pow(1.0 - t, 3.0))
	if t >= 1.0:
		_revealing = false


func cancel_reveal() -> void:
	_revealing = false


func is_revealing() -> bool:
	return _revealing


func zoom_at(screen_point: Vector2, factor: float) -> void:
	cancel_reveal()
	var new_zoom := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	offset = screen_point - (screen_point - offset) * (new_zoom / zoom)
	zoom = new_zoom
	_clamp_offset()


func _home() -> Vector2:
	return Vector2(_viewport_size.x * 0.5, _viewport_size.y * HOME_Y_RATIO)


# Keeps the grid reachable so panning cannot lose the network off-screen.
func _clamp_offset() -> void:
	offset = _clamped(offset)


func _clamped(value: Vector2) -> Vector2:
	var home := _home()
	var limit := _world_extent * zoom + Vector2(EDGE_MARGIN, EDGE_MARGIN)
	return Vector2(
		clampf(value.x, home.x - limit.x, home.x + limit.x),
		clampf(value.y, home.y - limit.y, home.y + limit.y)
	)


func _start_reveal(target: Vector2) -> void:
	_reveal_from = offset
	_reveal_to = _clamped(target)
	_reveal_elapsed = 0.0
	_revealing = true


static func _axis_shift(center: float, radius: float, low: float, high: float, margin: float) -> float:
	var inner_low := low + margin
	var inner_high := high - margin
	if center - radius >= inner_low and center + radius <= inner_high:
		return 0.0
	# A band too small for the whole node reveals its centre instead.
	if inner_high - inner_low < radius * 2.0:
		return (low + high) * 0.5 - center
	if center - radius < inner_low:
		return inner_low - (center - radius)
	return inner_high - (center + radius)
