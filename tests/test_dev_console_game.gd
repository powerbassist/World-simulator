extends SceneTree

## Headless test: godot --headless --script res://tests/test_dev_console_game.gd
## Non-zero exit on any failure.
##
## V5.1-0b. The dev console against the real game scene (src/ui/main.tscn): the
## registry and the Logger are pinned without a scene in tests/test_dev_console.gd;
## here the console's other half -- the host that moves the real clock, windows and
## save screen -- and the things only a running game can show:
##
##   - `skip 2` is two REAL months: the game it leaves is the game two
##     WorldMonth.tick_month() calls leave on a bare state, byte for byte (the
##     month through main.gd's own handler, not a copy of it);
##   - every other command lands where the player's own would: the state, the
##     clock, the window registry, a staged event noticed by the UI (the arrival
##     pause's bookkeeping), a save that loads back;
##   - `term_start` ends at a term start with the programme offer standing, or on a
##     lost election with its reason -- never silently in between;
##   - a command that changes the game waits while a month closes across frames and
##     one that reads does not, and the month's cost per system is recorded for the
##     perf overlay by the runner (src/ui/month_runner.gd), complete;
##   - a pushed error shows on the counter and in `errors`, and F12 toggles.
##
## Driven a frame at a time because the month runner IS frames (docs/engine-decision.md).

const WorldMonth = preload("res://src/sim/world_month.gd")
const GameState = preload("res://src/core/game_state.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Programme = preload("res://src/sim/programme.gd")

const MAX_FRAMES := 3000
const SLOT := "dev_console_test"

var _failures: Array[String] = []
var _frame := 0
var _phase := "sync"
var _a
var _b
var _c
var _console_b
var _seats_before := 0
var _closing_frames := 0


func _init() -> void:
	for name in ["_a", "_b", "_c"]:
		var game = load("res://src/ui/main.tscn").instantiate()
		root.add_child(game)
		set(name, game)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # both scenes' _ready()
	if _frame > MAX_FRAMES:
		_fail("still in phase '%s' after %d frames" % [_phase, MAX_FRAMES])
		return _finish()
	match _phase:
		"sync":
			_run_sync()
			return _begin_month() if _failures.is_empty() else _finish()
		"closing":
			return _watch_month()
		"after":
			return _after_month()
		"overlay":
			return _check_overlay()
		"stale":
			return _check_stale()
	return false


func _console(game):
	for child in game.get_children():
		if child.has_method("run_command"):
			return child
	_fail("the game scene has no dev console in a debug build")
	return null


func _dump(state) -> String:
	return JSON.stringify(state.to_dict(), "", true)


func _run_sync() -> void:
	var console = _console(_a)
	_console_b = _console(_b)
	var console_c = _console(_c)
	if console == null or _console_b == null or console_c == null:
		return

	_check_toggle(console_c)
	_check_term_start_at_the_start(console)
	_check_skip_is_real_months(console)
	_check_commands_land_where_the_players_do(console)
	_check_event_is_noticed(console)
	_check_interrupt_event_holds_the_clock(console)
	_check_save_load(console)
	_check_term_start(console_c)


## F12 through the real input path, both ways. All three games hear the key, in
## reverse tree order, and the first to act marks it handled: the LAST game's
## console is the one that opens.
func _check_toggle(console) -> void:
	if console.is_open():
		_fail("the console starts open")
	for want in [true, false]:
		_press(KEY_F12)
		if console.is_open() != want:
			_fail("F12 did not %s the console" % ("open" if want else "close"))


func _check_term_start_at_the_start(console) -> void:
	var r: String = console.run_command("term_start")
	if not r.contains("already") or _a._clock.month != 1:
		_fail("a new game is at a term start already, and term_start should say so: %s" % r)


func _check_skip_is_real_months(console) -> void:
	var bare = GameState.new_game(_a._loader, _a.pending_player_id, _a.pending_scenario_id)
	bare.year = _a._clock.year
	bare.month = _a._clock.month
	var history: int = _a._state.history.size()
	var r: String = console.run_command("skip 2")
	for i in 2:
		bare.month += 1
		if bare.month > 12:
			bare.month = 1
			bare.year += 1
		WorldMonth.tick_month(bare, _a._loader)
	if _a._state.history.size() != history + 2 or _a._clock.month != 3:
		_fail("skip 2 did not run two months: history %d -> %d, clock month %d" % [
			history, _a._state.history.size(), _a._clock.month])
	if not r.contains("2026-03"):
		_fail("skip 2 should answer with the date it reached: %s" % r)
	if _dump(_a._state) != _dump(bare):
		_fail("skip 2 left a game that differs from two WorldMonth.tick_month() calls on a bare state")
	if console.run_command("skip 0").is_empty() or _a._state.history.size() != history + 2:
		_fail("skip 0 should be refused without moving time")


func _check_commands_land_where_the_players_do(console) -> void:
	var ns = _a._state.player()
	console.run_command("set me.assembly_seats 777")
	if ns.assembly_seats != 777:
		_fail("set did not reach the game's state")
	if not console.run_command("get me.assembly_seats").contains("777"):
		_fail("get does not read what set wrote")
	console.run_command("speed 3")
	if _a._clock.speed != 3:
		_fail("speed 3 did not reach the clock: %d" % _a._clock.speed)
	console.run_command("pause on")
	if not _a._clock.paused:
		_fail("pause on did not pause the clock")
	console.run_command("pause off")
	if _a._clock.paused:
		_fail("pause off did not resume the clock")
	console.run_command("open budget")
	if not _a._windows.is_open("budget"):
		_fail("open budget did not open the window")
	if not console.run_command("open nonsense").contains("budget"):
		_fail("open of an unknown panel should list the ids")
	if not console.run_command("person %s" % _a._loader.person_by_id.keys()[0]).contains("party"):
		_fail("person printed nothing useful")


## An event put on the desk goes through the UI's arrival path, so the clock-hold
## bookkeeping knows it -- otherwise it would expire unseen, behind the player's back.
func _check_event_is_noticed(console) -> void:
	var ns = _a._state.player()
	ns.event_queue.clear()
	var id := String(_a._loader.events[0].id)
	var r: String = console.run_command("event %s" % id)
	if not r.contains(id) or ns.event_queue.size() != 1:
		_fail("event %s was not staged: %s" % [id, r])
	if not _a._unseen_events.has(id):
		_fail("the UI never noticed the staged event (no arrival bookkeeping)")


## An interrupt event is the one the player cannot ignore: arriving by the month it
## pauses the clock and opens Dispatches (main._enforce_interrupt), so staged by
## hand it must too -- or the repro is not the event.
func _check_interrupt_event_holds_the_clock(console) -> void:
	var ns = _a._state.player()
	ns.event_queue.clear()
	_a._unseen_events.clear()
	_a._paused_for_decision = false
	_a._clock.paused = false
	_a._windows.close("events")
	var id := ""
	for ev in _a._loader.events:
		if bool(ev.interrupt):
			id = String(ev.id)
			break
	if id.is_empty():
		_fail("premise: no interrupt event in the data")
		return
	console.run_command("event %s" % id)
	if not _a._clock.paused or not _a._windows.is_open("events"):
		_fail("a staged interrupt event did not pause the clock and open Dispatches")
	ns.event_queue.clear()
	_a._unseen_events.clear()
	_a._paused_for_decision = false
	_a._clock.paused = false


func _check_save_load(console) -> void:
	var ns = _a._state.player()
	console.run_command("set me.assembly_seats 11")
	var r: String = console.run_command("save %s" % SLOT)
	if not r.contains("saved"):
		_fail("save: %s" % r)
	console.run_command("set me.assembly_seats 22")
	r = console.run_command("load %s" % SLOT)
	if not r.contains("loaded") or _a._state.player().assembly_seats != 11:
		_fail("load did not bring the saved game back: %s seats=%d" % [r, _a._state.player().assembly_seats])
	if not console.run_command("load no_such_slot_here").contains("no save"):
		_fail("loading a missing slot should say so")
	SaveManager.delete_slot(SLOT)
	ns = null
	# A save that will not load: the answer says so and the live game stays.
	var bad := "dev_console_bad_slot"
	var file := FileAccess.open(SaveManager._path_for(bad), FileAccess.WRITE)
	file.store_string("this is not a save")
	file.close()
	var live = _a._state
	## expects-error: Parse JSON failed
	r = console.run_command("load %s" % bad)
	if r.contains("loaded") or not r.contains("failed") or _a._state != live:
		_fail("a load that failed was reported as done, or replaced the game: %s" % r)
	SaveManager.delete_slot(bad)


## The election two months out, so the honest route to a term start is short.
## Either outcome is right, but it must be one of the two and say which.
func _check_term_start(console) -> void:
	console.run_command("set me.next_executive_year 2026")
	console.run_command("set me.next_executive_month 3")
	console.run_command("skip 1")
	var r: String = console.run_command("term_start")
	var ns = _c._state.player()
	if r.contains("next term start reached"):
		if not Programme.is_term_start(ns) or _c._programme_card_id.is_empty() or not _c._clock.paused:
			_fail("term_start said it reached a term start but the offer is not standing: %s" % r)
	elif r.contains("out of government"):
		if ns.in_government:
			_fail("term_start said the election was lost but the player is in government: %s" % r)
	else:
		_fail("term_start ended in neither a term start nor a lost election: %s" % r)


## A real-time month in B: the clock is held and the runner spreads it over frames.
func _begin_month() -> bool:
	_b._clock.set_process(false)
	_b._clock.set_speed(1)
	while _b._clock.day < _b._clock._days_in_month(_b._clock.month, _b._clock.year):
		_b._clock.advance_one_day()
	_b._clock.paused = false
	_b._clock._process(1.0 / _b._clock.SPEED_DAYS_PER_SECOND[0])
	if not _b._month_runner.running():
		_fail("premise: the month did not start across frames")
		return _finish()
	_seats_before = _b._state.player().assembly_seats
	var refused: String = _console_b.run_command("set me.assembly_seats %d" % (_seats_before + 1))
	if not refused.contains("month is closing") or _b._state.player().assembly_seats != _seats_before:
		_fail("a cheat given while the month closed was not refused: %s" % refused)
	if not _console_b.run_command("get me.assembly_seats").contains(str(_seats_before)):
		_fail("a read should answer while the month closes")
	_phase = "closing"
	return false


func _watch_month() -> bool:
	if _b._month_runner.running():
		_closing_frames += 1
		return false
	if _closing_frames < 1:
		_fail("the month closed inside the frame that started it")
	_phase = "after"
	return false


func _after_month() -> bool:
	var costs: Dictionary = _b._month_runner.last_month_costs
	var total := 0
	for step in WorldMonth.STEPS:
		if not costs.has(step):
			_fail("the month's cost table has no entry for step %s" % step)
		total += int(costs.get(step, 0))
	if total <= 0 or int(costs.get("Economy", 0)) <= 0:
		_fail("the month's cost table recorded no time: total %d usec, Economy %d" % [total, int(costs.get("Economy", 0))])
	var answered: String = _console_b.run_command("set me.assembly_seats %d" % (_seats_before + 1))
	if answered.contains("month is closing") or _b._state.player().assembly_seats != _seats_before + 1:
		_fail("a cheat should land once the month is done: %s" % answered)
	_console_b.run_command("perf on")
	## expects-error: test_dev_console_game: expected error
	push_error("test_dev_console_game: expected error")
	_phase = "overlay"
	_closing_frames = 0
	return false


## A save of a state holding a NaN (a decision with no baseline) makes the engine warn
## once; that known line must not turn every clean session's counter to WARN 1.
## Then a hand-driven month: the overlay must not pass the real-time month's table off
## as current.
func _stage_stale_checks() -> void:
	_b._state.player().gdp_eur_bn = NAN
	## expects-warning: `NaN` ("Not a Number") found in argument passed to JSON.stringify
	_console_b.run_command("save %s" % SLOT)
	SaveManager.delete_slot(SLOT)
	_b._state.player().gdp_eur_bn = 1.0
	_console_b.run_command("skip 1")
	_console_b.run_command("perf on")  # forces the overlay's next refresh
	_phase = "stale"
	_closing_frames = 0


func _check_stale() -> bool:
	_closing_frames += 1
	if _closing_frames < 3:
		return false
	if not _b._month_runner.last_month_costs.is_empty():
		_fail("a hand-driven month left the real-time month's cost table standing")
	var text: String = _console_b._overlay.text
	if text.contains("Economy") or not text.contains("no real-time month"):
		_fail("the overlay still shows an old month's costs after a hand-driven month: %s" % text)
	if not String(_console_b._counter.text).contains("WARN 0"):
		_fail("the known NaN save warning was counted: %s" % _console_b._counter.text)
	if not _console_b.run_command("errors").contains("(expected)"):
		_fail("the known NaN save warning should be listed, marked (expected)")
	return _finish()


func _check_overlay() -> bool:
	_closing_frames += 1
	if _closing_frames < 3:
		return false
	var text: String = _console_b._overlay.text
	if not (text.contains("frame") and text.contains("month") and text.contains("Economy")):
		_fail("the perf overlay does not show frame time and the month's costs: %s" % text)
	if not String(_console_b._counter.text).contains("ERR") or String(_console_b._counter.text).contains("ERR 0"):
		_fail("the error counter did not count a pushed error: %s" % _console_b._counter.text)
	var listing: String = _console_b.run_command("errors")
	if not (listing.contains("expected error") and listing.contains("test_dev_console_game.gd")):
		_fail("errors should list the pushed error with its script: %s" % listing)
	_stage_stale_checks()
	return false


func _press(keycode: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		root.push_input(key, true)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	if _failures.is_empty():
		print("test_dev_console_game: all checks passed")
		quit(0)
		return true
	for message in _failures:
		printerr("FAIL: %s" % message)
	printerr("test_dev_console_game: %d check(s) failed" % _failures.size())
	quit(1)
	return true
