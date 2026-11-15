class_name ResourceBatch
extends RefCounted

# A group of identical resources that waits or travels together. Accumulated production is one
# batch per value and complexity, never one object per unit. `processed` means the node holding
# the batch has already transformed it and it is ready to leave. Arriving at a node resets it to false.
# `complexity` counts Processor steps applied to the resource. Only Processors raise it.

var quantity: LargeNumber
var value_per_unit: LargeNumber
var complexity: int = 0
var from_id: int
# Destination while travelling. 0 while queued.
var to_id: int
# 0.0 at the start of a connection, 1.0 at its end.
var progress: float = 0.0
var processed: bool = false


func _init(batch_quantity: LargeNumber, unit_value: LargeNumber, origin_id: int, destination_id: int, is_processed: bool = false, batch_complexity: int = 0) -> void:
	quantity = batch_quantity
	value_per_unit = unit_value
	from_id = origin_id
	to_id = destination_id
	processed = is_processed
	complexity = batch_complexity


# Batches merge only when every property that affects routing or payout matches.
func is_compatible_with(other: ResourceBatch) -> bool:
	return processed == other.processed and complexity == other.complexity \
		and value_per_unit.compare(other.value_per_unit) == 0
