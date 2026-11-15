class_name WorkspaceLayout
extends RefCounted

# Grid placement state. Owns where nodes sit. It never touches network connections.

const COLUMNS := 5
const ROWS := 9
const CELL_SIZE := 150.0
const NEIGHBOR_OFFSETS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _cell_of: Dictionary = {}
var _node_at: Dictionary = {}


static func get_half_extent() -> Vector2:
	return Vector2(COLUMNS, ROWS) * CELL_SIZE * 0.5


func contains_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < COLUMNS and cell.y < ROWS


func is_cell_free(cell: Vector2i) -> bool:
	return contains_cell(cell) and not _node_at.has(cell)


func get_cell_at_world(world: Vector2) -> Vector2i:
	return Vector2i(
		floori(world.x / CELL_SIZE + COLUMNS * 0.5),
		floori(world.y / CELL_SIZE + ROWS * 0.5)
	)


func get_cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
		(cell.x - COLUMNS * 0.5 + 0.5) * CELL_SIZE,
		(cell.y - ROWS * 0.5 + 0.5) * CELL_SIZE
	)


func get_node_cell(id: int) -> Vector2i:
	return _cell_of.get(id, Vector2i(-1, -1))


func get_node_at(cell: Vector2i) -> int:
	return _node_at.get(cell, 0)


# Ids of nodes in the four orthogonal neighbouring cells.
func get_neighbor_ids(id: int) -> Array:
	var ids: Array = []
	var cell := get_node_cell(id)
	for offset in NEIGHBOR_OFFSETS:
		var other := get_node_at(cell + offset)
		if other != 0:
			ids.append(other)
	return ids


func place(id: int, cell: Vector2i) -> void:
	_cell_of[id] = cell
	_node_at[cell] = id


func move(id: int, cell: Vector2i) -> void:
	remove(id)
	place(id, cell)


func remove(id: int) -> void:
	if not _cell_of.has(id):
		return

	_node_at.erase(_cell_of[id])
	_cell_of.erase(id)
