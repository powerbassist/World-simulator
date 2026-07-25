extends SceneTree

## Headless test: godot --headless --script res://tests/test_game_loop.gd
## Non-zero exit on any failure.
##
## The wiring test. Everything else exercises the simulation by calling
## Economy.tick_month and Budget.tick_month directly; this one loads the actual
## main scene and turns the actual clock, so a broken signal connection between
## the clock and the simulation fails here rather than in a playtest.
##
## S5 and S6 hook into the same monthly signal, so this stays useful.

const MONTHS := 12

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return

	var ns = _main._state.player()
	var gdp_before: float = ns.gdp_eur_bn
	var debt_before: float = ns.debt_eur_bn

	var clock: Node = _main.get_node("Clock")
	var days := 0
	for month in range(MONTHS):
		for _d in range(31):
			clock.advance_one_day()
			days += 1

	if _main._state.history.size() < MONTHS:
		_fail("clock ran %d days but only %d months reached the simulation" % [days, _main._state.history.size()])
		return

	if ns.gdp_eur_bn <= gdp_before:
		_fail("GDP did not grow over a simulated year: %.1f -> %.1f" % [gdp_before, ns.gdp_eur_bn])
	if ns.debt_eur_bn <= debt_before:
		_fail("debt did not accumulate over a simulated year: %.1f -> %.1f" % [debt_before, ns.debt_eur_bn])

	# History entries are stamped with the date, which is what makes them usable
	# for charts later.
	var last: Dictionary = _main._state.history[-1]
	if not last.has("year") or not last.has("month"):
		_fail("history entries are not stamped with a date: %s" % [last.keys()])
	if _main._state.year != clock.year or _main._state.month != clock.month:
		_fail("GameState date (%d-%d) drifted from the clock (%d-%d)" % [
			_main._state.year, _main._state.month, clock.year, clock.month
		])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_game_loop: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
