class_name WorkspaceCamera
extends RefCounted

# Pan and zoom for the workspace. Converts between screen and world coordinates.

const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.6
const INITIAL_ZOOM := 0.9
const EDGE_MARGIN := 160.0
# Vertical screen position of the world origin, above the bottom UI.
const HOME_Y_RATIO := 0.42

var zoom: float = INITIAL_ZOOM
var offset := Vector2.ZERO

var _viewport_size := Vector2.ZERO
var _world_extent := Vector2.ZERO


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


func pan(screen_delta: Vector2) -> void:
	offset += screen_delta
	_clamp_offset()


func zoom_at(screen_point: Vector2, factor: float) -> void:
	var new_zoom := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	offset = screen_point - (screen_point - offset) * (new_zoom / zoom)
	zoom = new_zoom
	_clamp_offset()


func _home() -> Vector2:
	return Vector2(_viewport_size.x * 0.5, _viewport_size.y * HOME_Y_RATIO)


# Keeps the grid reachable so panning cannot lose the network off-screen.
func _clamp_offset() -> void:
	var home := _home()
	var limit := _world_extent * zoom + Vector2(EDGE_MARGIN, EDGE_MARGIN)
	offset = Vector2(
		clampf(offset.x, home.x - limit.x, home.x + limit.x),
		clampf(offset.y, home.y - limit.y, home.y + limit.y)
	)
