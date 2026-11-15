class_name NumberFormat
extends RefCounted

# Compact display of LargeNumber values. Display only: authoritative values are never
# changed. Values are truncated, not rounded, so a shown amount never exceeds the real one.

const SUFFIXES := ["", "K", "M", "B", "T"]
const GROUPED_MAX_DIGITS := 4
const SCIENTIFIC_MIN_DIGITS := 16


static func compact(number: LargeNumber) -> String:
	var text := number.to_text()
	var digits := text.length()

	if digits <= GROUPED_MAX_DIGITS:
		return _group_thousands(text)
	if digits >= SCIENTIFIC_MIN_DIGITS:
		return "%s.%se%d" % [text.substr(0, 1), text.substr(1, 2), digits - 1]

	var group := (digits - 1) / 3
	var integer_digits := digits - group * 3
	# One leading digit shows two decimals (2.71M), two digits show one (18.4K), three show none (250K).
	var decimals := 3 - integer_digits
	var body := text.substr(0, integer_digits)
	if decimals > 0:
		body += "." + text.substr(integer_digits, decimals)
	return body + SUFFIXES[group]


static func money(number: LargeNumber) -> String:
	return "$" + compact(number)


static func _group_thousands(text: String) -> String:
	var result := ""
	for index in range(text.length()):
		if index > 0 and (text.length() - index) % 3 == 0:
			result += ","
		result += text[index]
	return result
