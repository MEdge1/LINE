extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_large_number.gd

var _failures := 0


func _init() -> void:
	_test_arithmetic_is_exact_beyond_64_bits()
	_test_subtraction_and_comparison()
	_test_compact_formatting()
	_test_formatting_never_changes_the_value()

	if _failures == 0:
		print("All large number tests passed.")
	else:
		printerr("%d large number assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _test_arithmetic_is_exact_beyond_64_bits() -> void:
	var value := LargeNumber.from_int(1)
	var two := LargeNumber.from_int(2)
	for _i in range(70):
		value = value.multiply(two)

	_assert_equal(value.to_text(), "1180591620717411303424", "2^70 is exact, with no wrap to zero")
	_assert_equal(LargeNumber.from_int(999999999).add(LargeNumber.from_int(1)).to_text(), "1000000000",
		"addition carries across limbs")
	_assert_equal(LargeNumber.from_int(0).to_text(), "0", "zero is represented")


func _test_subtraction_and_comparison() -> void:
	var big := LargeNumber.from_int(1000000000)
	_assert_equal(big.subtract(LargeNumber.from_int(1)).to_text(), "999999999", "subtraction borrows across limbs")
	_assert_equal(big.compare(LargeNumber.from_int(999999999)), 1, "larger value compares greater")
	_assert_equal(LargeNumber.from_int(5).compare(LargeNumber.from_int(5)), 0, "equal values compare equal")
	_assert_equal(LargeNumber.from_int(0).is_zero(), true, "zero reports as zero")


func _test_compact_formatting() -> void:
	var cases := {
		0: "0",
		1250: "1,250",
		9999: "9,999",
		18400: "18.4K",
		2710000: "2.71M",
		8350000000: "8.35B",
		1260000000000: "1.26T",
		999000000000000: "999T",
		1000000000000000: "1.00e15",
	}
	for value in cases:
		_assert_equal(NumberFormat.compact(LargeNumber.from_int(value)), cases[value],
			"compact format of %d" % value)

	_assert_equal(NumberFormat.money(LargeNumber.from_int(24)), "$24", "money format prefixes a dollar sign")

	var huge := LargeNumber.from_int(1)
	for _i in range(70):
		huge = huge.multiply(LargeNumber.from_int(2))
	_assert_equal(NumberFormat.compact(huge), "1.18e21", "values beyond the T range use scientific notation")


func _test_formatting_never_changes_the_value() -> void:
	var value := LargeNumber.from_int(18400)
	NumberFormat.compact(value)
	_assert_equal(value.to_text(), "18400", "formatting leaves the authoritative value untouched")
