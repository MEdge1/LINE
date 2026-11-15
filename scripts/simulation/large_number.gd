class_name LargeNumber
extends RefCounted

# Non-negative integer of unlimited size, used for money, values, and quantities.
# Stored as base-1e9 limbs (least significant first), so arithmetic never overflows or
# wraps. Instances are immutable: every operation returns a new LargeNumber.

const LIMB_BASE := 1000000000

var _limbs: PackedInt64Array


func _init(limbs: PackedInt64Array) -> void:
	_limbs = limbs
	_trim()


static func from_int(value: int) -> LargeNumber:
	var limbs := PackedInt64Array()
	var remaining := maxi(value, 0)
	while remaining > 0:
		limbs.append(remaining % LIMB_BASE)
		remaining /= LIMB_BASE
	return LargeNumber.new(limbs)


func is_zero() -> bool:
	return _limbs.size() == 1 and _limbs[0] == 0


func add(other: LargeNumber) -> LargeNumber:
	var result := PackedInt64Array()
	var carry := 0
	for index in range(maxi(_limbs.size(), other._limbs.size())):
		var sum := _limb(index) + other._limb(index) + carry
		result.append(sum % LIMB_BASE)
		carry = sum / LIMB_BASE
	if carry > 0:
		result.append(carry)
	return LargeNumber.new(result)


# Callers must check affordability first. A result below zero is clamped to zero, never wrapped.
func subtract(other: LargeNumber) -> LargeNumber:
	if compare(other) < 0:
		push_error("LargeNumber.subtract would go negative; clamped to zero.")
		return LargeNumber.from_int(0)

	var result := PackedInt64Array()
	var borrow := 0
	for index in range(_limbs.size()):
		var difference := _limbs[index] - other._limb(index) - borrow
		if difference < 0:
			difference += LIMB_BASE
			borrow = 1
		else:
			borrow = 0
		result.append(difference)
	return LargeNumber.new(result)


func multiply(other: LargeNumber) -> LargeNumber:
	var result := PackedInt64Array()
	result.resize(_limbs.size() + other._limbs.size())
	result.fill(0)

	for i in range(_limbs.size()):
		var carry := 0
		for j in range(other._limbs.size()):
			var current := result[i + j] + _limbs[i] * other._limbs[j] + carry
			result[i + j] = current % LIMB_BASE
			carry = current / LIMB_BASE

		var k := i + other._limbs.size()
		while carry > 0:
			var current := result[k] + carry
			result[k] = current % LIMB_BASE
			carry = current / LIMB_BASE
			k += 1

	return LargeNumber.new(result)


# Returns -1, 0, or 1 for less than, equal, or greater than.
func compare(other: LargeNumber) -> int:
	if _limbs.size() != other._limbs.size():
		return -1 if _limbs.size() < other._limbs.size() else 1

	for index in range(_limbs.size() - 1, -1, -1):
		if _limbs[index] != other._limbs[index]:
			return -1 if _limbs[index] < other._limbs[index] else 1
	return 0


func to_text() -> String:
	var text := str(_limbs[_limbs.size() - 1])
	for index in range(_limbs.size() - 2, -1, -1):
		text += "%09d" % _limbs[index]
	return text


static func min_of(first: LargeNumber, second: LargeNumber) -> LargeNumber:
	return first if first.compare(second) <= 0 else second


static func from_text(digits: String) -> LargeNumber:
	var result := LargeNumber.from_int(0)
	var ten := LargeNumber.from_int(10)
	for digit in digits:
		result = result.multiply(ten).add(LargeNumber.from_int(int(digit)))
	return result


# Lossy. Used only for telemetry and display rates, never for authoritative values.
func to_float() -> float:
	var value := 0.0
	for index in range(_limbs.size() - 1, -1, -1):
		value = value * LIMB_BASE + float(_limbs[index])
	return value


# Only for values known to be small, such as buffer space and per-step budgets.
# Anything larger than 64 bits clamps to the maximum.
func to_int_clamped() -> int:
	if _limbs.size() > 2:
		return 9223372036854775807
	var value := _limbs[0]
	if _limbs.size() == 2:
		value += _limbs[1] * LIMB_BASE
	return value


func _limb(index: int) -> int:
	return _limbs[index] if index < _limbs.size() else 0


func _trim() -> void:
	while _limbs.size() > 1 and _limbs[_limbs.size() - 1] == 0:
		_limbs.resize(_limbs.size() - 1)
	if _limbs.is_empty():
		_limbs.append(0)
