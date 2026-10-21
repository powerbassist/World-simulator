extends SceneTree

## Headless test: godot --headless --script res://tests/test_num.gd
## Non-zero exit on any failure.
##
## V5.1b2. Every figure with decimals goes through Num, so the decimal separator follows
## the language (a French "7,40 %", an English "7.40%"): `%.2f` prints a point in every
## language and is a lint failure in src/ui. No thousands separator is shown anywhere
## (figures print as 2910, not 2,910), so the formatter has none.

const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []


func _init() -> void:
	Strings.set_language("en")
	_check("en f", Num.f(7.4, 2), "7.40")
	_check("en f rounds", Num.f(2.675, 1), "2.7")
	_check("en f negative", Num.f(-0.5, 1), "-0.5")
	_check("en fs positive", Num.fs(0.45, 2), "+0.45")
	_check("en fs negative", Num.fs(-0.45, 2), "-0.45")
	_check("en fs zero", Num.fs(0.0, 1), "+0.0")
	_check("en no places", Num.f(12.6, 0), "13")
	Strings.set_language("fr")
	_check("fr f", Num.f(7.4, 2), "7,40")
	_check("fr f negative", Num.f(-0.5, 1), "-0,5")
	_check("fr fs", Num.fs(0.45, 2), "+0,45")
	_check("fr no places keeps no separator", Num.f(12.6, 0), "13")
	_check("fr integer-valued", Num.f(3.0, 2), "3,00")
	Strings.set_language("en")
	_check("back to en", Num.f(7.4, 2), "7.40")
	if Strings.decimal() != ".":
		_fail("the English decimal separator should be a point, got '%s'" % Strings.decimal())
	_finish()
	quit(1 if not _failures.is_empty() else 0)


func _check(what: String, got: String, want: String) -> void:
	if got != want:
		_fail("%s: got '%s', wanted '%s'" % [what, got, want])


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_num: all checks passed")
	else:
		for f in _failures:
			printerr(f)
