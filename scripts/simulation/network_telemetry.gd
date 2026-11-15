class_name NetworkTelemetry
extends RefCounted

# Rolling measurements for inspection and the HUD. Written only from simulation events and never
# read back into simulation state. Values are approximate floats; authoritative values are LargeNumber.

var clock: float = 0.0

var _arrivals: Dictionary = {}
var _processed: Dictionary = {}
var _produced: Dictionary = {}
var _payouts_by_node: Dictionary = {}
var _edges: Dictionary = {}
var _payouts := RateWindow.new()


func advance(delta: float) -> void:
	clock += delta


func record_arrival(node_id: int, amount: float) -> void:
	_window(_arrivals, node_id).add(amount, clock)


func record_processed(node_id: int, amount: float) -> void:
	_window(_processed, node_id).add(amount, clock)


func record_produced(node_id: int, amount: float) -> void:
	_window(_produced, node_id).add(amount, clock)


func record_payout(node_id: int, amount: float) -> void:
	_window(_payouts_by_node, node_id).add(amount, clock)
	_payouts.add(amount, clock)


func record_edge(from_id: int, to_id: int, amount: float) -> void:
	_window(_edges, Vector2i(from_id, to_id)).add(amount, clock)


func arrival_rate(node_id: int) -> float:
	return _rate(_arrivals, node_id)


func processed_rate(node_id: int) -> float:
	return _rate(_processed, node_id)


func produced_rate(node_id: int) -> float:
	return _rate(_produced, node_id)


func payout_rate(node_id: int) -> float:
	return _rate(_payouts_by_node, node_id)


func network_payout_rate() -> float:
	return _payouts.rate(clock)


func edge_rate(from_id: int, to_id: int) -> float:
	return _rate(_edges, Vector2i(from_id, to_id))


func forget_node(node_id: int) -> void:
	_arrivals.erase(node_id)
	_processed.erase(node_id)
	_produced.erase(node_id)
	_payouts_by_node.erase(node_id)
	for key in _edges.keys():
		if key.x == node_id or key.y == node_id:
			_edges.erase(key)


func _window(store: Dictionary, key: Variant) -> RateWindow:
	if not store.has(key):
		store[key] = RateWindow.new()
	return store[key]


func _rate(store: Dictionary, key: Variant) -> float:
	return store[key].rate(clock) if store.has(key) else 0.0
