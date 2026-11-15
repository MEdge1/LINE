class_name ProductionSimulation
extends RefCounted

# Authoritative production and currency state. Resources follow the NetworkGraph's
# connections as ResourceBatch aggregates. Presentation reads batches but never changes them.
#
# Holding rule: a node with no downstream connection keeps its resources as one waiting
# batch per value. Once a downstream connection exists, the backlog drains in
# LineBalance.DRAIN_BATCH_SIZE steps (temporary Milestone 2 rule; see LineBalance).

signal payout_received(amount: LargeNumber, output_id: int)

# Conservation ledger: produced = paid + held + lost. Nothing is discarded without being counted.
var produced_units: LargeNumber = LargeNumber.from_int(0)
var paid_units: LargeNumber = LargeNumber.from_int(0)
var lost_units: LargeNumber = LargeNumber.from_int(0)

var money: LargeNumber = LargeNumber.from_int(LineBalance.START_MONEY)
var in_flight: Array[ResourceBatch] = []

var _graph: NetworkGraph
var _waiting: Dictionary = {}
var _revenue: Dictionary = {}
var _production_accumulators: Dictionary = {}
var _drain_accumulator: float = 0.0
var _processor_multiplier: LargeNumber = LargeNumber.from_int(LineBalance.PROCESSOR_MULTIPLIER)
var _unit_value: LargeNumber = LargeNumber.from_int(LineBalance.UNIT_START_VALUE)


func _init(graph: NetworkGraph) -> void:
	_graph = graph


func get_held_units() -> LargeNumber:
	var total := LargeNumber.from_int(0)
	for batch in in_flight:
		total = total.add(batch.quantity)
	for node_id in _waiting:
		total = total.add(get_waiting_total(node_id))
	return total


func get_waiting(node_id: int) -> Array:
	return _waiting.get(node_id, [])


func get_waiting_node_ids() -> Array:
	return _waiting.keys()


func get_waiting_batch_count() -> int:
	var count := 0
	for node_id in _waiting:
		count += _waiting[node_id].size()
	return count


func get_waiting_total(node_id: int) -> LargeNumber:
	var total := LargeNumber.from_int(0)
	for batch in get_waiting(node_id):
		total = total.add(batch.quantity)
	return total


func get_revenue(output_id: int) -> LargeNumber:
	return _revenue.get(output_id, LargeNumber.from_int(0))


func get_generator_rate(generator_id: int) -> float:
	var level := _graph.get_node(generator_id).level
	return LineBalance.GENERATOR_BASE_RATE + LineBalance.GENERATOR_RATE_PER_LEVEL * float(level - 1)


func get_upgrade_cost(generator_id: int) -> LargeNumber:
	return LargeNumber.from_int(LineBalance.GENERATOR_UPGRADE_COST_PER_LEVEL * _graph.get_node(generator_id).level)


func is_generator(id: int) -> bool:
	return _graph.has_node(id) and _graph.get_node(id).type == NodeDefinitions.Type.GENERATOR


func is_at_max_level(generator_id: int) -> bool:
	return is_generator(generator_id) and _graph.get_node(generator_id).level >= LineBalance.GENERATOR_MAX_LEVEL


func can_afford(amount: LargeNumber) -> bool:
	return money.compare(amount) >= 0


func spend(amount: LargeNumber) -> bool:
	if not can_afford(amount):
		return false

	money = money.subtract(amount)
	return true


func add_money(amount: LargeNumber) -> void:
	money = money.add(amount)


func can_afford_upgrade(generator_id: int) -> bool:
	return is_generator(generator_id) and not is_at_max_level(generator_id) and can_afford(get_upgrade_cost(generator_id))


# Rejected at the level cap, so repeated attempts spend nothing and change nothing.
func upgrade_generator(generator_id: int) -> bool:
	if not can_afford_upgrade(generator_id):
		return false

	spend(get_upgrade_cost(generator_id))
	_graph.get_node(generator_id).level += 1
	return true


func step(delta: float) -> void:
	# Advance existing batches first so newly produced batches start at progress 0.
	_advance_in_flight(delta)
	_drain_waiting(delta)
	_produce(delta)


# Disconnecting an edge returns its in-flight batches to the source node's queue. Quantity and
# value are preserved, nothing is lost, and the value is not processed again. Returns the quantity returned.
func return_edge_to_source(from_id: int, to_id: int) -> LargeNumber:
	var returned := LargeNumber.from_int(0)
	for index in range(in_flight.size() - 1, -1, -1):
		var batch := in_flight[index]
		if batch.from_id == from_id and batch.to_id == to_id:
			in_flight.remove_at(index)
			batch.to_id = 0
			batch.progress = 0.0
			_add_waiting(from_id, batch)
			returned = returned.add(batch.quantity)
	return returned


# Removes batches and per-node state that reference a node being deleted.
# Resources on the deleted node's connections are lost with it.
func drop_node_state(node_id: int) -> void:
	for index in range(in_flight.size() - 1, -1, -1):
		var batch := in_flight[index]
		if batch.from_id == node_id or batch.to_id == node_id:
			lost_units = lost_units.add(batch.quantity)
			in_flight.remove_at(index)

	for batch in get_waiting(node_id):
		lost_units = lost_units.add(batch.quantity)
	_waiting.erase(node_id)
	_production_accumulators.erase(node_id)
	_revenue.erase(node_id)


func _first_downstream(node_id: int) -> int:
	var downstream := _graph.get_outgoing(node_id)
	return downstream[0] if not downstream.is_empty() else 0


func _advance_in_flight(delta: float) -> void:
	# Iterate backwards so batches can be removed while looping.
	for index in range(in_flight.size() - 1, -1, -1):
		var batch := in_flight[index]
		batch.progress += delta / LineBalance.TRAVEL_DURATION
		if batch.progress >= 1.0:
			_arrive(index)


func _arrive(index: int) -> void:
	var batch := in_flight[index]
	batch.from_id = batch.to_id
	batch.to_id = 0
	batch.progress = 0.0

	var node := _graph.get_node(batch.from_id)
	if node.type == NodeDefinitions.Type.OUTPUT:
		in_flight.remove_at(index)
		var payout := batch.quantity.multiply(batch.value_per_unit)
		money = money.add(payout)
		paid_units = paid_units.add(batch.quantity)
		_revenue[node.id] = get_revenue(node.id).add(payout)
		payout_received.emit(payout, node.id)
	elif node.type == NodeDefinitions.Type.PROCESSOR:
		# The whole batch is processed once on arrival, so value changes per batch, not per unit.
		batch.value_per_unit = batch.value_per_unit.multiply(_processor_multiplier)
		var downstream := _first_downstream(node.id)
		if downstream != 0:
			batch.to_id = downstream
		else:
			in_flight.remove_at(index)
			_add_waiting(node.id, batch)


func _add_waiting(node_id: int, batch: ResourceBatch) -> void:
	var list: Array = _waiting.get(node_id, [])
	for existing in list:
		if existing.value_per_unit.compare(batch.value_per_unit) == 0:
			existing.quantity = existing.quantity.add(batch.quantity)
			return

	list.append(batch)
	_waiting[node_id] = list


func _drain_waiting(delta: float) -> void:
	_drain_accumulator += delta
	while _drain_accumulator >= LineBalance.DRAIN_INTERVAL:
		_drain_accumulator -= LineBalance.DRAIN_INTERVAL
		for node_id in _waiting.keys():
			var downstream := _first_downstream(node_id)
			if downstream != 0:
				_release_waiting(node_id, downstream)


# Releases up to DRAIN_BATCH_SIZE units from a node's backlog onto its downstream edge.
func _release_waiting(node_id: int, downstream: int) -> void:
	var list: Array = _waiting[node_id]
	var budget := LargeNumber.from_int(LineBalance.DRAIN_BATCH_SIZE)

	while not list.is_empty() and not budget.is_zero():
		var source: ResourceBatch = list[0]
		var amount := source.quantity if source.quantity.compare(budget) <= 0 else budget
		source.quantity = source.quantity.subtract(amount)
		budget = budget.subtract(amount)
		_enqueue_on_edge(node_id, downstream, amount, source.value_per_unit)
		if source.quantity.is_zero():
			list.remove_at(0)

	if list.is_empty():
		_waiting.erase(node_id)


func _produce(delta: float) -> void:
	for id in _graph.get_node_ids():
		if not is_generator(id):
			continue

		var downstream := _first_downstream(id)
		if downstream == 0:
			continue

		var accumulator := float(_production_accumulators.get(id, 0.0))
		accumulator += delta * get_generator_rate(id)
		var produced := int(floor(accumulator))
		if produced > 0:
			accumulator -= produced
			_enqueue_on_edge(id, downstream, LargeNumber.from_int(produced), _unit_value)
			produced_units = produced_units.add(LargeNumber.from_int(produced))
		_production_accumulators[id] = accumulator


# Batches that enter the same connection with the same value within one drain window
# share a batch. This keeps the in-flight count proportional to path length, not to units.
func _enqueue_on_edge(from_id: int, to_id: int, quantity: LargeNumber, value: LargeNumber) -> void:
	var merge_window := LineBalance.DRAIN_INTERVAL / LineBalance.TRAVEL_DURATION
	for batch in in_flight:
		if batch.from_id == from_id and batch.to_id == to_id and batch.progress < merge_window \
				and batch.value_per_unit.compare(value) == 0:
			batch.quantity = batch.quantity.add(quantity)
			return

	in_flight.append(ResourceBatch.new(quantity, value, from_id, to_id))
