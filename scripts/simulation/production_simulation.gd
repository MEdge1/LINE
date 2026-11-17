class_name ProductionSimulation
extends RefCounted

# Authoritative production, buffering, routing, and payout state. Resources are ResourceBatch
# aggregates held in per-node queues or travelling on connections. A node's capacity limits its
# processing or routing work. A full downstream queue back-pressures its upstream: generators pause
# and nothing is discarded.
#
# Invariants:
#   produced = paid + held + lost            (held = in flight + queued + returning)
#   queue + quantity in transit toward a node <= BUFFER_CAPACITY
#   a node's queue never exceeds BUFFER_CAPACITY; disconnect returns wait in a holding list
#   (see return_edge_to_source) until the source has room.
# Presentation reads this state and never changes it.

signal payout_received(amount: LargeNumber, output_id: int, complexity: int)
signal units_processed(node_id: int, count: int)

enum Status { NORMAL, SATURATED, BOTTLENECK, BLOCKED }

const EPSILON := 1e-9

var money: LargeNumber = LargeNumber.from_int(LineBalance.START_MONEY)
var produced_units: LargeNumber = LargeNumber.from_int(0)
var paid_units: LargeNumber = LargeNumber.from_int(0)
var lost_units: LargeNumber = LargeNumber.from_int(0)
var in_flight: Array[ResourceBatch] = []
var telemetry := NetworkTelemetry.new()

var _graph: NetworkGraph
var _queues: Dictionary = {}
# Batches returned by a disconnect that the source has no room for yet. They enter the queue as space frees.
var _returning: Dictionary = {}
var _reserved: Dictionary = {}
var _revenue: Dictionary = {}
var _production_accumulators: Dictionary = {}
# Processing and routing budgets in seconds of work available. See _advance_budget.
var _budgets: Dictionary = {}
var _split_parity: Dictionary = {}
var _last_incoming: Dictionary = {}
var _last_payout_complexity: Dictionary = {}
var _processor_multiplier := LargeNumber.from_int(LineBalance.PROCESSOR_MULTIPLIER)
var _unit_value := LargeNumber.from_int(LineBalance.UNIT_START_VALUE)
var _buffer_size := LineBalance.BUFFER_CAPACITY
# Processing-work rule for Product Complexity. Changed only through set_processing_mode.
var processing_mode: int = ProcessingBalance.Mode.LIVE_HYPERBOLIC
# Booster coverage model. Changed only through change_booster_model (via NetworkManager.set_booster_model).
var booster_model: int = BoosterModel.DEFAULT_MODE


func _init(graph: NetworkGraph) -> void:
	_graph = graph


func get_waiting(node_id: int) -> Array:
	return _queues.get(node_id, [])


func get_waiting_node_ids() -> Array:
	var ids: Array = []
	for node_id in _queues:
		if not _queues[node_id].is_empty():
			ids.append(node_id)
	return ids


func get_waiting_batch_count() -> int:
	var count := 0
	for node_id in _queues:
		count += _queues[node_id].size()
	return count


# Everything a node is holding back: its queue plus any disconnect returns waiting for room.
func get_waiting_total(node_id: int) -> LargeNumber:
	return _queue_total(node_id).add(_returning_total(node_id))


func get_held_units() -> LargeNumber:
	var total := LargeNumber.from_int(0)
	for batch in in_flight:
		total = total.add(batch.quantity)
	for node_id in _queues:
		total = total.add(_queue_total(node_id))
	for node_id in _returning:
		total = total.add(_returning_total(node_id))
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


# Effective processing or routing capacity in units per second. A generator's capacity is its output rate.
func get_capacity(node_id: int) -> float:
	var node := _graph.get_node(node_id)
	if node.type == NodeDefinitions.Type.GENERATOR:
		return get_generator_rate(node_id)
	var base := NodeDefinitions.get_capacity(node.type)
	# A relief model (test-only) replaces the throughput bonus on Processors.
	var relief_replaces_bonus := ComplexityRelief.replaces_bonus() and node.type == NodeDefinitions.Type.PROCESSOR
	if node.boosted and NodeDefinitions.is_boostable(node.type) and not relief_replaces_bonus:
		return base * (1.0 + LineBalance.BOOSTER_BONUS)
	return base


func get_utilization(node_id: int) -> float:
	var capacity := get_effective_capacity(node_id)
	return telemetry.processed_rate(node_id) / capacity if capacity > 0.0 else 0.0


# Processors slow down as their incoming complexity rises. Other nodes have no complexity modifier.
func get_effective_capacity(node_id: int) -> float:
	var capacity := get_capacity(node_id)
	if _graph.get_node(node_id).type == NodeDefinitions.Type.PROCESSOR:
		return capacity * ComplexityModel.processing_modifier(_work_complexity(node_id, get_incoming_complexity(node_id)), processing_mode)
	return capacity


# Complexity that sets a Processor's speed. Equal to the batch complexity unless the Processor is boosted with relief.
func _work_complexity(node_id: int, complexity: int) -> int:
	var node := _graph.get_node(node_id)
	if not node.boosted or node.type != NodeDefinitions.Type.PROCESSOR:
		return complexity
	var spec := relief_spec()
	if spec.is_empty():
		return complexity
	return ComplexityRelief.effective(complexity, spec)


# Relief for boosted Processors. A test-only override (ComplexityRelief.active) wins; otherwise the selected model.
func relief_spec() -> Dictionary:
	if ComplexityRelief.is_active():
		return ComplexityRelief.active
	return BoosterModel.relief_spec(booster_model)



# Complexity of the batch a Processor is working on next. When nothing unprocessed is queued,
# the complexity of the most recent work it did. Zero before any work.
func get_incoming_complexity(node_id: int) -> int:
	var head := _first_unprocessed(_queue(node_id))
	if head != null:
		return head.complexity
	return _last_incoming.get(node_id, 0)


func get_last_payout_complexity(output_id: int) -> int:
	return _last_payout_complexity.get(output_id, -1)


# BOTTLENECK: the node is busy at its capacity and work is queuing because of that capacity.
# BLOCKED: the queue is full while the node is not busy, so it is waiting on its output.
# SATURATED: busy at its capacity with a queue that is keeping up.
func get_status(node_id: int) -> int:
	var node := _graph.get_node(node_id)
	var queued := get_waiting_total(node_id).to_float()
	var buffer := float(_buffer_size)

	if node.type == NodeDefinitions.Type.GENERATOR:
		return Status.BLOCKED if queued >= buffer else Status.NORMAL
	if node.type == NodeDefinitions.Type.BOOSTER:
		return Status.NORMAL

	var utilization := get_utilization(node_id)
	if utilization >= LineBalance.BOTTLENECK_UTILIZATION and queued >= LineBalance.BOTTLENECK_QUEUE_FRACTION * buffer:
		return Status.BOTTLENECK
	if queued >= buffer and utilization < LineBalance.BOTTLENECK_UTILIZATION:
		return Status.BLOCKED
	if utilization >= LineBalance.BOTTLENECK_UTILIZATION:
		return Status.SATURATED
	return Status.NORMAL


# Adds resources straight into a node's queue. Used by scenarios and tests to set up a state.
func seed_queue(node_id: int, quantity: LargeNumber, value: LargeNumber, processed: bool, complexity: int = 0) -> void:
	produced_units = produced_units.add(quantity)
	_deposit(node_id, ResourceBatch.new(quantity, value, node_id, 0, processed, complexity))


# Switches the processing rule while the machine runs. No resource, value, complexity, or queue changes: only
# the time left on each Processor's current unit is rescaled. A Processor that is 50% through its unit under one
# rule stays 50% through it under the other. A Processor with nothing to work on keeps no progress.
func set_processing_mode(mode: int) -> void:
	if mode == processing_mode:
		return
	_rescale_units(func() -> void:
		processing_mode = mode)


# Switches the Booster coverage model. Boost state changes through `refresh`, and each Processor's current unit keeps
# its progress fraction under the new capacity and work requirement. No resource, value, or queue changes.
func change_booster_model(mode: int, refresh: Callable) -> void:
	_rescale_units(func() -> void:
		booster_model = mode
		refresh.call())


# Keeps each Processor's progress fraction across a change in work requirement. Units are measured before `change`
# runs and rescaled after it, so the caller decides what changes (processing rule, boost state, or both).
func _rescale_units(change: Callable) -> void:
	var fractions := {}
	for node_id in _graph.get_node_ids():
		if _graph.get_node(node_id).type != NodeDefinitions.Type.PROCESSOR:
			continue
		var head := _first_unprocessed(_queue(node_id))
		if head == null:
			fractions[node_id] = 0.0
			continue
		var capacity := get_capacity(node_id)
		var old_cost := ComplexityModel.unit_cost_seconds(capacity, _work_complexity(node_id, head.complexity), processing_mode)
		var stored: float = _budgets.get(node_id, 0.0)
		fractions[node_id] = clampf(stored / old_cost, 0.0, 1.0) if old_cost > 0.0 else 0.0
	change.call()
	for node_id in fractions:
		var head := _first_unprocessed(_queue(node_id))
		if head == null:
			_budgets[node_id] = 0.0
			continue
		var capacity := get_capacity(node_id)
		var work := _work_complexity(node_id, head.complexity)
		_budgets[node_id] = fractions[node_id] * ComplexityModel.unit_cost_seconds(capacity, work, processing_mode)


func step(delta: float) -> void:
	telemetry.advance(delta)
	_advance_in_flight(delta)
	_rebuild_reservations()
	for node_id in _returning.keys():
		_drain_returning(node_id)

	for node_id in _graph.get_node_ids():
		var node_type: int = _graph.get_node(node_id).type
		if node_type == NodeDefinitions.Type.GENERATOR:
			_run_generator(node_id, delta)
		elif node_type == NodeDefinitions.Type.PROCESSOR:
			_run_processor(node_id, delta)
		elif node_type == NodeDefinitions.Type.SPLITTER:
			_run_splitter(node_id, delta)
		elif node_type == NodeDefinitions.Type.MERGER:
			_run_merger(node_id, delta)
		elif node_type == NodeDefinitions.Type.OUTPUT:
			_run_output(node_id, delta)


# Removes batches and per-node state that reference a node being deleted.
# Resources held by the deleted node or travelling to or from it are recorded as lost.
func drop_node_state(node_id: int) -> void:
	for index in range(in_flight.size() - 1, -1, -1):
		var batch := in_flight[index]
		if batch.from_id == node_id or batch.to_id == node_id:
			lost_units = lost_units.add(batch.quantity)
			in_flight.remove_at(index)

	for batch in get_waiting(node_id):
		lost_units = lost_units.add(batch.quantity)
	for batch in _returning.get(node_id, []):
		lost_units = lost_units.add(batch.quantity)
	_queues.erase(node_id)
	_returning.erase(node_id)
	_reserved.erase(node_id)
	_production_accumulators.erase(node_id)
	_budgets.erase(node_id)
	_split_parity.erase(node_id)
	_last_incoming.erase(node_id)
	_last_payout_complexity.erase(node_id)
	_revenue.erase(node_id)
	telemetry.forget_node(node_id)


# Disconnecting an edge returns its in-flight batches to the source node. Quantity, value,
# complexity, and processed state are preserved, and nothing is lost or transformed again.
# Returned batches enter the source queue as soon as it has room. Any remainder waits in the
# source's holding list, which keeps the queue within BUFFER_CAPACITY. Returns the quantity moved.
func return_edge_to_source(from_id: int, to_id: int) -> LargeNumber:
	var returned := LargeNumber.from_int(0)
	var holding := _returning_list(from_id)
	var kept: Array[ResourceBatch] = []
	for batch in in_flight:
		if batch.from_id == from_id and batch.to_id == to_id:
			returned = returned.add(batch.quantity)
			holding.append(batch)
		else:
			kept.append(batch)
	in_flight = kept

	_rebuild_reservations()
	_drain_returning(from_id)
	return returned


# Authoritative state for saving. Telemetry, reservations, and boost flags are not saved: they
# are rebuilt or restarted on load. Numbers are exact texts, and node references are ids.
func export_state() -> Dictionary:
	var state := {
		"money": money.to_text(),
		"produced": produced_units.to_text(),
		"paid": paid_units.to_text(),
		"lost": lost_units.to_text(),
		"in_flight": [],
		"queues": [],
		"returning": [],
		"revenue": [],
		"accumulators": [],
		"budgets": [],
		"split_parity": [],
		"last_incoming": [],
		"last_payout_complexity": [],
	}
	for batch in in_flight:
		state["in_flight"].append(_batch_to_dict(batch))
	for node_id in _queues:
		state["queues"].append({"node": node_id, "batches": _batches_to_array(_queues[node_id])})
	for node_id in _returning:
		state["returning"].append({"node": node_id, "batches": _batches_to_array(_returning[node_id])})
	for node_id in _revenue:
		state["revenue"].append([node_id, _revenue[node_id].to_text()])
	for node_id in _production_accumulators:
		state["accumulators"].append([node_id, _production_accumulators[node_id]])
	for node_id in _budgets:
		state["budgets"].append([node_id, _budgets[node_id]])
	for node_id in _split_parity:
		state["split_parity"].append([node_id, _split_parity[node_id]])
	for node_id in _last_incoming:
		state["last_incoming"].append([node_id, _last_incoming[node_id]])
	for node_id in _last_payout_complexity:
		state["last_payout_complexity"].append([node_id, _last_payout_complexity[node_id]])
	return state


# Restores state exported by export_state. The caller validates node references first.
func import_state(state: Dictionary) -> void:
	money = LargeNumber.from_text(state["money"])
	produced_units = LargeNumber.from_text(state["produced"])
	paid_units = LargeNumber.from_text(state["paid"])
	lost_units = LargeNumber.from_text(state["lost"])

	in_flight.clear()
	for entry in state["in_flight"]:
		in_flight.append(_batch_from_dict(entry))
	_queues.clear()
	for entry in state["queues"]:
		_queues[int(entry["node"])] = _batches_from_array(entry["batches"])
	_returning.clear()
	for entry in state["returning"]:
		_returning[int(entry["node"])] = _batches_from_array(entry["batches"])
	_revenue.clear()
	for pair in state["revenue"]:
		_revenue[int(pair[0])] = LargeNumber.from_text(pair[1])
	_production_accumulators = _pairs_to_dict(state["accumulators"], false)
	_budgets = _pairs_to_dict(state["budgets"], false)
	_split_parity = _pairs_to_dict(state["split_parity"], true)
	_last_incoming = _pairs_to_dict(state["last_incoming"], true)
	_last_payout_complexity = _pairs_to_dict(state["last_payout_complexity"], true)
	_reserved.clear()


func _batch_to_dict(batch: ResourceBatch) -> Dictionary:
	return {
		"quantity": batch.quantity.to_text(),
		"value": batch.value_per_unit.to_text(),
		"complexity": batch.complexity,
		"processed": batch.processed,
		"from": batch.from_id,
		"to": batch.to_id,
		"progress": batch.progress,
	}


func _batch_from_dict(entry: Dictionary) -> ResourceBatch:
	var batch := ResourceBatch.new(
		LargeNumber.from_text(entry["quantity"]),
		LargeNumber.from_text(entry["value"]),
		int(entry["from"]),
		int(entry["to"]),
		bool(entry["processed"]),
		int(entry["complexity"])
	)
	batch.progress = float(entry["progress"])
	return batch


func _batches_to_array(batches: Array) -> Array:
	var result: Array = []
	for batch in batches:
		result.append(_batch_to_dict(batch))
	return result


func _batches_from_array(entries: Array) -> Array:
	var result: Array = []
	for entry in entries:
		result.append(_batch_from_dict(entry))
	return result


func _pairs_to_dict(pairs: Array, as_int: bool) -> Dictionary:
	var result := {}
	for pair in pairs:
		result[int(pair[0])] = int(pair[1]) if as_int else float(pair[1])
	return result


func _advance_in_flight(delta: float) -> void:
	for index in range(in_flight.size() - 1, -1, -1):
		var batch := in_flight[index]
		batch.progress += delta / LineBalance.TRAVEL_DURATION
		if batch.progress < 1.0:
			continue

		in_flight.remove_at(index)
		telemetry.record_arrival(batch.to_id, batch.quantity.to_float())
		# Arriving resources have not been transformed by the node they just reached.
		batch.processed = false
		_deposit(batch.to_id, batch)


func _rebuild_reservations() -> void:
	_reserved.clear()
	for batch in in_flight:
		_reserved[batch.to_id] = _reserved_for(batch.to_id).add(batch.quantity)


func _run_generator(node_id: int, delta: float) -> void:
	var rate := get_generator_rate(node_id)
	var accumulator: float = float(_production_accumulators.get(node_id, 0.0)) + delta * rate
	var room := maxi(_buffer_size - _queue_total(node_id).to_int_clamped(), 0)
	var count := mini(floori(accumulator), room)
	if count > 0:
		_deposit(node_id, ResourceBatch.new(LargeNumber.from_int(count), _unit_value, node_id, 0, false))
		produced_units = produced_units.add(LargeNumber.from_int(count))
		telemetry.record_produced(node_id, float(count))
		accumulator -= float(count)
	# Production paused by a full buffer does not bank up into a burst later.
	_production_accumulators[node_id] = minf(accumulator, maxf(1.0, rate * LineBalance.BURST_SECONDS))
	_emit_ready(node_id, true)


func _run_processor(node_id: int, delta: float) -> void:
	var capacity := get_capacity(node_id)
	var queue := _queue(node_id)
	var head := _first_unprocessed(queue)
	var min_seconds := 0.0 if head == null else ComplexityModel.unit_cost_seconds(capacity, _work_complexity(node_id, head.complexity), processing_mode)
	var budget := _advance_budget(node_id, delta, min_seconds)
	var consumed := 0
	var index := 0

	while index < queue.size():
		var item: ResourceBatch = queue[index]
		if item.processed:
			index += 1
			continue

		# Strict FIFO: a unit that cannot be afforded yet holds back everything queued behind it.
		var unit_cost := ComplexityModel.unit_cost_seconds(capacity, _work_complexity(node_id, item.complexity), processing_mode)
		var count := mini(item.quantity.to_int_clamped(), floori(budget / unit_cost + EPSILON))
		if count <= 0:
			break

		var batch := _take(queue, index, LargeNumber.from_int(count))
		budget -= count * unit_cost
		consumed += count
		_last_incoming[node_id] = batch.complexity
		batch.value_per_unit = batch.value_per_unit.multiply(_processor_multiplier)
		batch.complexity += 1
		batch.processed = true
		_deposit(node_id, batch)

	telemetry.record_processed(node_id, float(consumed))
	if consumed > 0:
		units_processed.emit(node_id, consumed)
	_budgets[node_id] = budget
	_emit_ready(node_id, false)


func _run_splitter(node_id: int, delta: float) -> void:
	var capacity := get_capacity(node_id)
	var budget := _advance_budget(node_id, delta, 0.0)
	var whole := _units_available(budget, capacity)
	var outputs := _graph.get_outgoing(node_id)
	var branch_a: int = outputs[0] if outputs.size() > 0 else 0
	var branch_b: int = outputs[1] if outputs.size() > 1 else 0
	var routed_total := 0
	var queue := _queue(node_id)
	var index := 0

	while whole > 0 and index < queue.size():
		var room_a := _free_int(branch_a)
		var room_b := _free_int(branch_b)
		if room_a + room_b <= 0:
			break

		var offered := mini(whole, queue[index].quantity.to_int_clamped())
		var parity: int = _split_parity.get(node_id, 0)
		var split := SplitPolicy.split(offered, room_a, room_b, parity == 1)
		if offered % 2 == 1:
			_split_parity[node_id] = 1 - parity

		var routed := split.x + split.y
		if routed <= 0:
			break
		var batch := _take(queue, index, LargeNumber.from_int(routed))
		if split.x > 0:
			_emit(node_id, branch_a, _with_quantity(batch, split.x))
		if split.y > 0:
			_emit(node_id, branch_b, _with_quantity(batch, split.y))
		whole -= routed
		routed_total += routed

	telemetry.record_processed(node_id, float(routed_total))
	_spend_budget(node_id, budget, routed_total, capacity)


func _run_merger(node_id: int, delta: float) -> void:
	var capacity := get_capacity(node_id)
	var budget := _advance_budget(node_id, delta, 0.0)
	var whole := _units_available(budget, capacity)
	var outputs := _graph.get_outgoing(node_id)
	var to_id: int = outputs[0] if not outputs.is_empty() else 0
	var routed_total := 0
	var queue := _queue(node_id)
	var index := 0

	while whole > 0 and index < queue.size() and to_id != 0:
		var room := _free_int(to_id)
		if room <= 0:
			break
		var amount := LargeNumber.min_of(queue[index].quantity, LargeNumber.from_int(mini(whole, room)))
		var count := amount.to_int_clamped()
		_emit(node_id, to_id, _take(queue, index, amount))
		whole -= count
		routed_total += count

	telemetry.record_processed(node_id, float(routed_total))
	_spend_budget(node_id, budget, routed_total, capacity)


func _run_output(node_id: int, delta: float) -> void:
	var capacity := get_capacity(node_id)
	var budget := _advance_budget(node_id, delta, 0.0)
	var whole := _units_available(budget, capacity)
	var consumed := 0
	var queue := _queue(node_id)
	var index := 0

	while whole > 0 and index < queue.size():
		var amount := LargeNumber.min_of(queue[index].quantity, LargeNumber.from_int(whole))
		var count := amount.to_int_clamped()
		var batch := _take(queue, index, amount)
		whole -= count
		consumed += count

		# Payout is authoritative: quantity times value. Complexity is reported, never used in the sum.
		var payout := batch.quantity.multiply(batch.value_per_unit)
		money = money.add(payout)
		paid_units = paid_units.add(batch.quantity)
		_revenue[node_id] = get_revenue(node_id).add(payout)
		_last_payout_complexity[node_id] = batch.complexity
		telemetry.record_payout(node_id, payout.to_float())
		telemetry.record_processed(node_id, float(count))
		payout_received.emit(payout, node_id, batch.complexity)

	_spend_budget(node_id, budget, consumed, capacity)


# Sends ready resources to the single downstream node while it has free space.
# Generators send everything they hold; processors send only processed batches.
func _emit_ready(node_id: int, is_generator: bool) -> void:
	var outputs := _graph.get_outgoing(node_id)
	if outputs.is_empty():
		return
	var to_id: int = outputs[0]
	var queue := _queue(node_id)
	var index := 0

	while index < queue.size():
		var item: ResourceBatch = queue[index]
		if not is_generator and not item.processed:
			index += 1
			continue
		var room := _free_space(to_id)
		if room.is_zero():
			break
		_emit(node_id, to_id, _take(queue, index, LargeNumber.min_of(item.quantity, room)))


func _advance_budget(node_id: int, delta: float, min_cap_seconds: float) -> float:
	# Idle budget is capped at BURST_SECONDS, or at the cost of one waiting unit if that is larger,
	# so a slow high-complexity unit can always be worked through.
	var stored: float = _budgets.get(node_id, 0.0)
	var cap := maxf(LineBalance.BURST_SECONDS, min_cap_seconds)
	return minf(stored + delta, cap)


func _units_available(budget: float, capacity: float) -> int:
	return floori(budget * capacity + EPSILON)


func _spend_budget(node_id: int, budget: float, spent: int, capacity: float) -> void:
	_budgets[node_id] = budget - float(spent) / capacity


# Creates or extends a transit batch on the edge. Batches that are compatible and enter the same
# edge within the merge window share one batch, which keeps the transit count small.
func _emit(from_id: int, to_id: int, batch: ResourceBatch) -> void:
	var amount := batch.quantity
	_reserved[to_id] = _reserved_for(to_id).add(amount)
	telemetry.record_edge(from_id, to_id, amount.to_float())

	var merge_limit := LineBalance.MERGE_WINDOW_SECONDS / LineBalance.TRAVEL_DURATION
	for existing in in_flight:
		if existing.from_id == from_id and existing.to_id == to_id and existing.progress < merge_limit \
				and existing.is_compatible_with(batch):
			existing.quantity = existing.quantity.add(amount)
			return

	in_flight.append(ResourceBatch.new(amount, batch.value_per_unit, from_id, to_id, batch.processed, batch.complexity))


func _deposit(node_id: int, batch: ResourceBatch) -> void:
	var queue := _queue(node_id)
	batch.from_id = node_id
	batch.to_id = 0
	batch.progress = 0.0
	for existing in queue:
		if existing.is_compatible_with(batch):
			existing.quantity = existing.quantity.add(batch.quantity)
			return
	queue.append(batch)


func _first_unprocessed(queue: Array) -> ResourceBatch:
	for item in queue:
		if not item.processed:
			return item
	return null


# Moves returned batches into the queue as the node has room. A partly fitting batch is split,
# so the queue fills exactly to its free space and never beyond it.
func _drain_returning(node_id: int) -> void:
	if not _returning.has(node_id):
		return
	var holding: Array = _returning[node_id]
	while not holding.is_empty():
		var room := _free_space(node_id)
		if room.is_zero():
			break
		_deposit(node_id, _take(holding, 0, LargeNumber.min_of(holding[0].quantity, room)))
	if holding.is_empty():
		_returning.erase(node_id)


func _returning_list(node_id: int) -> Array:
	if not _returning.has(node_id):
		_returning[node_id] = []
	return _returning[node_id]


func _returning_total(node_id: int) -> LargeNumber:
	var total := LargeNumber.from_int(0)
	for batch in _returning.get(node_id, []):
		total = total.add(batch.quantity)
	return total


# Removes `amount` from the queue entry at `index`. Returns a batch holding exactly `amount`.
func _take(queue: Array, index: int, amount: LargeNumber) -> ResourceBatch:
	var item: ResourceBatch = queue[index]
	if item.quantity.compare(amount) <= 0:
		queue.remove_at(index)
		return item

	item.quantity = item.quantity.subtract(amount)
	return ResourceBatch.new(amount, item.value_per_unit, item.from_id, item.to_id, item.processed, item.complexity)


func _with_quantity(batch: ResourceBatch, count: int) -> ResourceBatch:
	return ResourceBatch.new(LargeNumber.from_int(count), batch.value_per_unit, batch.from_id, batch.to_id, batch.processed, batch.complexity)


func _queue(node_id: int) -> Array:
	if not _queues.has(node_id):
		_queues[node_id] = []
	return _queues[node_id]


func _queue_total(node_id: int) -> LargeNumber:
	var total := LargeNumber.from_int(0)
	for batch in _queues.get(node_id, []):
		total = total.add(batch.quantity)
	return total


func _reserved_for(node_id: int) -> LargeNumber:
	return _reserved.get(node_id, LargeNumber.from_int(0))


func _free_space(node_id: int) -> LargeNumber:
	if node_id == 0:
		return LargeNumber.from_int(0)
	var used := _queue_total(node_id).add(_reserved_for(node_id))
	var buffer := LargeNumber.from_int(_buffer_size)
	return buffer.subtract(used) if used.compare(buffer) < 0 else LargeNumber.from_int(0)


func _free_int(node_id: int) -> int:
	return _free_space(node_id).to_int_clamped()
