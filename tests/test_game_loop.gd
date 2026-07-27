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
## V1.2a: a second Main instance, forced to Germany rather than the
## pending_player_id default -- the real proof no France assumption survived
## is a headless run of a nation that isn't the one every prior session tested
## against. Set before add_child(), the same way menu.gd sets it before the
## scene enters the tree -- _ready() reads it immediately.
var _main_deu
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)

	_main_deu = load("res://src/ui/main.tscn").instantiate()
	_main_deu.pending_player_id = "DEU"
	root.add_child(_main_deu)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let both scenes' _ready() run

	_run(_main, "FRA")
	_run(_main_deu, "DEU")
	_finish()
	return false


func _run(main, label: String) -> void:
	if main._state == null:
		_fail("%s: main scene did not build a GameState" % label)
		return

	var ns = main._state.player()
	var gdp_before: float = ns.gdp_eur_bn
	var debt_before: float = ns.debt_eur_bn

	var clock: Node = main.get_node("Clock")
	var days := 0
	for month in range(MONTHS):
		for _d in range(31):
			clock.advance_one_day()
			days += 1

	if main._state.history.size() < MONTHS:
		_fail("%s: clock ran %d days but only %d months reached the simulation" % [label, days, main._state.history.size()])
		return

	if ns.gdp_eur_bn <= gdp_before:
		_fail("%s: GDP did not grow over a simulated year: %.1f -> %.1f" % [label, gdp_before, ns.gdp_eur_bn])
	if ns.debt_eur_bn <= debt_before:
		_fail("%s: debt did not accumulate over a simulated year: %.1f -> %.1f" % [label, debt_before, ns.debt_eur_bn])

	# History entries are stamped with the date, which is what makes them usable
	# for charts later.
	var last: Dictionary = main._state.history[-1]
	if not last.has("year") or not last.has("month"):
		_fail("%s: history entries are not stamped with a date: %s" % [label, last.keys()])
	if main._state.year != clock.year or main._state.month != clock.month:
		_fail("%s: GameState date (%d-%d) drifted from the clock (%d-%d)" % [
			label, main._state.year, main._state.month, clock.year, clock.month
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
