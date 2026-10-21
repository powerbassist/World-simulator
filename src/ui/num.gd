extends RefCounted

## The ONE formatter for a figure with decimals -- V5.1b2. `"%.2f" % x` prints a decimal
## point in every language ("7.40 %" in French, where the rule is the comma); a figure
## goes through here instead, so the separator is the language's own
## (data/i18n/languages.json `decimal`). A format string keeps a `%s` for it:
## `tr("Rate %s%%") % Num.f(rate, 2)`. tests/test_i18n_lint.gd fails a raw `%.Nf`.
##
## No thousands separator: nothing in the interface prints one (2910 Bn, not 2,910 Bn),
## so the formatter has none to localise.

const Strings = preload("res://src/ui/strings.gd")


## `value` with `places` decimals ("%.2f"), the language's decimal separator.
static func f(value: float, places: int) -> String:
	return _local(("%." + str(places) + "f") % value, places)


## The same with a sign ("%+.2f").
static func fs(value: float, places: int) -> String:
	return _local(("%+." + str(places) + "f") % value, places)


static func _local(text: String, places: int) -> String:
	var separator := Strings.decimal()
	if places <= 0 or separator == ".":
		return text
	return text.replace(".", separator)
