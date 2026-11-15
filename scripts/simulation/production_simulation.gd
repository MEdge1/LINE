class_name ProductionSimulation
extends RefCounted

# Authoritative game state for the production line. Holds no nodes or visuals;
# presentation reads `units` and draws them.

class Unit:
	var value: int
	# 0 = Generator -> Processor, 1 = Processor -> Output
	var leg: int = 0
	# 0.0 at the start of a leg, 1.0 at its end.
	var progress: float = 0.0

	func _init(unit_value: int) -> void:
		value = unit_value


var money: int = LineBalance.START_MONEY
var generator_level: int = 1
var units: Array[Unit] = []

var _production_accumulator: float = 0.0


func get_generator_rate() -> float:
	return LineBalance.GENERATOR_BASE_RATE \
		+ LineBalance.GENERATOR_RATE_PER_LEVEL * float(generator_level - 1)


func get_upgrade_cost() -> int:
	return LineBalance.GENERATOR_UPGRADE_COST_PER_LEVEL * generator_level


func can_afford_upgrade() -> bool:
	return money >= get_upgrade_cost()


func upgrade_generator() -> bool:
	if not can_afford_upgrade():
		return false

	money -= get_upgrade_cost()
	generator_level += 1
	return true


func step(delta: float) -> void:
	# Advance existing units first so newly produced units start at progress 0.
	_advance_units(delta)
	_produce(delta)


func _produce(delta: float) -> void:
	_production_accumulator += delta * get_generator_rate()

	while _production_accumulator >= 1.0:
		_production_accumulator -= 1.0
		units.append(Unit.new(LineBalance.UNIT_START_VALUE))


func _advance_units(delta: float) -> void:
	# Iterate backwards so units can be removed while looping.
	for index in range(units.size() - 1, -1, -1):
		var unit := units[index]
		unit.progress += delta / LineBalance.TRAVEL_DURATION

		if unit.progress < 1.0:
			continue

		if unit.leg == 0:
			unit.value *= LineBalance.PROCESSOR_MULTIPLIER
			unit.leg = 1
			unit.progress = 0.0
		else:
			money += unit.value
			units.remove_at(index)
