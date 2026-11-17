class_name WorkspaceStyle
extends RefCounted

# Pure presentation helpers for the three workspace states. Reads authoritative progression and grid
# geometry, never writes them.

enum CellState { UNLOCKED, LOCKED, OUTSIDE }


static func cell_state(layout: WorkspaceLayout, progression: ProgressionManager, cell: Vector2i) -> int:
	if not layout.contains_cell(cell):
		return CellState.OUTSIDE
	return CellState.UNLOCKED if progression.is_cell_unlocked(cell) else CellState.LOCKED


# A cell a node could be placed in right now: unlocked, inside the world, and empty.
static func is_valid_target(layout: WorkspaceLayout, progression: ProgressionManager, cell: Vector2i) -> bool:
	return cell_state(layout, progression, cell) == CellState.UNLOCKED and layout.is_cell_free(cell)


# The full world in world coordinates, centred on the origin. The boundary and the grid share this.
static func world_rect() -> Rect2:
	var half := WorkspaceLayout.get_half_extent()
	return Rect2(-half, half * 2.0)


# 1 right after an expansion, fading to 0 once the emphasis has expired.
static func reveal_strength(age: float) -> float:
	return clampf(1.0 - age / WorkspaceVisuals.REVEAL_SECONDS, 0.0, 1.0)


# 0 while a cell is still locked, rising to 1 as it finishes its transition to unlocked.
static func transition_progress(age: float) -> float:
	return clampf(age / WorkspaceVisuals.REVEAL_TRANSITION_SECONDS, 0.0, 1.0)
