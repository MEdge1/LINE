class_name ProgressionManager
extends RefCounted

# Owns unlock state: technologies, Research Points, and unlocked workspace cells. Build validation
# queries this manager. The simulation never checks unlocks, and money is spent through the simulation.

enum UnlockResult { OK, UNKNOWN_TECHNOLOGY, ALREADY_UNLOCKED, MISSING_PREREQUISITE, INSUFFICIENT_RP }

var research_points: int = 0
var expansion_index: int = 0

var _unlocked_techs: Dictionary = {}
var _unlocked_cells: Dictionary = {}


# A real new game: start technologies, start region, no Research Points.
static func new_game() -> ProgressionManager:
	var progression := ProgressionManager.new()
	for id in ProgressionCatalog.START_TECHNOLOGIES:
		progression._unlocked_techs[id] = true
	for cell in ProgressionCatalog.START_CELLS:
		progression._unlocked_cells[cell] = true
	return progression


# Explicit test and development state: everything unlocked, the full 5×9 grid available.
# NetworkManager uses this by default so construction tests can exercise the simulation directly.
static func sandbox() -> ProgressionManager:
	var progression := ProgressionManager.new()
	for tech in ProgressionCatalog.TECHNOLOGIES:
		progression._unlocked_techs[tech["id"]] = true
	for column in range(WorkspaceLayout.COLUMNS):
		for row in range(WorkspaceLayout.ROWS):
			progression._unlocked_cells[Vector2i(column, row)] = true
	progression.expansion_index = ProgressionCatalog.EXPANSIONS.size()
	return progression


func is_type_unlocked(type: int) -> bool:
	return is_tech_unlocked(NodeDefinitions.get_display_name(type))


func is_tech_unlocked(id: String) -> bool:
	return _unlocked_techs.has(id)


func is_cell_unlocked(cell: Vector2i) -> bool:
	return _unlocked_cells.has(cell)


func unlocked_cell_count() -> int:
	return _unlocked_cells.size()


func all_technologies_unlocked() -> bool:
	for tech in ProgressionCatalog.TECHNOLOGIES:
		if not is_tech_unlocked(tech["id"]):
			return false
	return true


func can_unlock(id: String) -> UnlockResult:
	var index := ProgressionCatalog.technology_index(id)
	if index < 0:
		return UnlockResult.UNKNOWN_TECHNOLOGY
	if is_tech_unlocked(id):
		return UnlockResult.ALREADY_UNLOCKED
	var tech: Dictionary = ProgressionCatalog.TECHNOLOGIES[index]
	if tech["prerequisite"] != "" and not is_tech_unlocked(tech["prerequisite"]):
		return UnlockResult.MISSING_PREREQUISITE
	if research_points < int(tech["cost"]):
		return UnlockResult.INSUFFICIENT_RP
	return UnlockResult.OK


# Spends the technology's Research Points exactly once and records the unlock.
func unlock_technology(id: String) -> UnlockResult:
	var result := can_unlock(id)
	if result != UnlockResult.OK:
		return result
	research_points -= int(ProgressionCatalog.TECHNOLOGIES[ProgressionCatalog.technology_index(id)]["cost"])
	_unlocked_techs[id] = true
	return UnlockResult.OK


func add_research_points(amount: int) -> void:
	research_points += amount


func is_fully_expanded() -> bool:
	return expansion_index >= ProgressionCatalog.EXPANSIONS.size()


func next_expansion_cost() -> int:
	if is_fully_expanded():
		return -1
	return int(ProgressionCatalog.EXPANSIONS[expansion_index]["cost"])


# Cells the next purchase would unlock. Empty once fully expanded.
func next_expansion_cells() -> Array:
	if is_fully_expanded():
		return []
	return ProgressionCatalog.EXPANSIONS[expansion_index]["cells"].duplicate()


func can_expand(simulation: ProductionSimulation) -> bool:
	return not is_fully_expanded() and simulation.can_afford(LargeNumber.from_int(next_expansion_cost()))


# Buys the next expansion step with money. Returns false when it is fully expanded or unaffordable.
func expand(simulation: ProductionSimulation) -> bool:
	if not can_expand(simulation):
		return false
	simulation.spend(LargeNumber.from_int(next_expansion_cost()))
	for cell in ProgressionCatalog.EXPANSIONS[expansion_index]["cells"]:
		_unlocked_cells[cell] = true
	expansion_index += 1
	return true


func unlocked_techs() -> Array:
	var ids: Array = []
	for tech in ProgressionCatalog.TECHNOLOGIES:
		if is_tech_unlocked(tech["id"]):
			ids.append(tech["id"])
	return ids


func unlocked_cells() -> Array:
	var cells: Array = _unlocked_cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return cells


# Restores validated save data. Callers check every value before calling.
func restore(techs: Array, cells: Array, points: int, index: int) -> void:
	_unlocked_techs.clear()
	for id in techs:
		_unlocked_techs[id] = true
	_unlocked_cells.clear()
	for cell in cells:
		_unlocked_cells[cell] = true
	research_points = points
	expansion_index = index
