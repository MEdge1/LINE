class_name ResourceBatch
extends RefCounted

# A group of identical resources that travel or wait together. Accumulated production
# is one batch per value, never one object per unit.

var quantity: LargeNumber
var value_per_unit: LargeNumber
var from_id: int
# Destination while travelling. 0 while waiting at from_id.
var to_id: int
# 0.0 at the start of a connection, 1.0 at its end.
var progress: float = 0.0


func _init(batch_quantity: LargeNumber, unit_value: LargeNumber, origin_id: int, destination_id: int) -> void:
	quantity = batch_quantity
	value_per_unit = unit_value
	from_id = origin_id
	to_id = destination_id
