extends SceneTree

## Headless test: godot --headless --script res://tests/test_month_runner.gd
## Non-zero exit on any failure.
##
## V5.1-0a: the month a player watches runs across frames (src/ui/month_runner.gd)
## and the month a test drives by hand runs whole. Three copies of one new game:
## A is the game whose month is one Clock.advance_one_day() call, B is the game
## whose month is reached by real time passing (the clock's own _process) and is
## watched frame by frame, and C is no game at all -- a bare GameState ticked by
## WorldMonth.tick_month(), the month every balance harness runs. What must hold,
## each a silent failure if it does not:
##
##   - B's month takes more than one frame (the freeze is gone) while A's is
##     done before the call returns (every harness keeps its whole month);
##   - while B's month closes, its calendar does not move, its 1st has not been
##     announced, its windows hold their frame, and a key the player presses is
##     not acted on -- it is acted on once the month is done, not lost;
##   - B ends every month where A and C end, byte for byte (sorted keys): the
##     month across frames through the in-game driver is the balance probes'
##     month -- for six months running, so a month that pauses itself mid-close
##     (an event on the desk, the term-start offer) is among them;
##   - and a seventh month is closed under fire: a pause, a speed change, the
##     save/load dialog's key, a budget commit and a law proposal are all given
##     while it closes. None of them lands mid-month -- the month's result is
##     still C's, to the byte -- and every one lands after it, once.
##
## Driven a frame at a time because the runner IS frames, and because a Control
## outside the scene tree has not run _ready() (docs/engine-decision.md).

const WorldMonth = preload("res://src/sim/world_month.gd")
const GameState = preload("res://src/core/game_state.gd")
const MonthRunner = preload("res://src/ui/month_runner.gd")

const MAX_FRAMES := 4000
const MONTHS := 6

var _failures: Array[String] = []
var _a
var _b
var _bare
var _frame := 0
var _phase := "boot"
var _month_frames := 0
var _months_done := 0
var _recorder: Recorder
## The seventh month's commands, and what B looked like the instant its month
## was done -- before the clock let go and the deferred input was replayed.
var _law_name := ""
var _at_month_end := {}
var _speed_before := 0
var _settle_left := 0


## A clock that is real time and holds, and nothing else: what run() asks of one.
class HeldClock extends Node:
	var in_real_time := true
	var held := false

	func hold() -> void:
		held = true

	func release() -> void:
		held = false


## The frame budget as STRUCTURE, never as a stopwatch (the test audit,
## 2026-10-21). "More than one frame" above holds for a month cut in two
## five-second halves; what makes the month a slice per frame is the rule that a
## unit known to cost more than what is left of the budget waits for the next
## frame, after at least one unit has run. Every unit is pre-costed past the
## whole budget, so the rule allows exactly one unit a frame, and the frames must
## equal the month's units, counted on a twin state by the cursor itself. And
## the budget, read back, fits a 60 Hz frame.
func _check_the_budget_slices_the_month(loader) -> void:
	if MonthRunner.FRAME_BUDGET_USEC > 16667:
		_fail("FRAME_BUDGET_USEC is %d -- more than a 60 Hz frame (16 667 us) of simulation alone" % MonthRunner.FRAME_BUDGET_USEC)
	var twin = GameState.new_game(loader, "FRA")
	var watched = GameState.new_game(loader, "FRA")
	for s in [twin, watched]:
		s.year = 2026
		s.month = 2
	var units := 0
	var cursor = WorldMonth.begin(twin, loader)
	while not WorldMonth.done(cursor):
		WorldMonth.run_unit(cursor)
		units += 1

	var runner = MonthRunner.new()
	var clock := HeldClock.new()
	var held := Node.new()
	var finished := [false]
	runner.run(watched, loader, Callable(), func(_report: Dictionary) -> void: finished[0] = true, clock, held)
	for step in range(WorldMonth.STEPS.size()):
		for unit in range(256):
			runner._cost["%d:%d" % [step, unit]] = MonthRunner.FRAME_BUDGET_USEC + 1
	var frames := 0
	while runner.running() and frames <= units + 1:
		runner._process(0.0)
		frames += 1
	if not finished[0]:
		_fail("the runner had not finished a month of %d units after %d frames" % [units, frames])
	elif frames != units:
		_fail("a month of %d units, every one costed past the budget, took %d frames -- one unit a frame is the rule" % [units, frames])
	if clock.held:
		_fail("the runner left its clock held after the month")
	runner.free()
	clock.free()
	held.free()


## What reaches the game as unhandled input. F12 is bound to nothing, so this is
## the only reader of it: whether it arrives, and when, is the whole question.
class Recorder extends Node:
	var presses := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.keycode == KEY_F12 and event.pressed:
			presses += 1


func _init() -> void:
	_a = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_a)
	_b = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_b)
	# Last, so it hears unhandled input ahead of both scenes.
	_recorder = Recorder.new()
	root.add_child(_recorder)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let both scenes' _ready() run
	if _frame > MAX_FRAMES:
		_fail("B's month was still closing after %d frames" % MAX_FRAMES)
		return _finish()
	match _phase:
		"boot":
			_check_the_budget_slices_the_month(_b._loader)
			_bare = GameState.new_game(_b._loader, _b.pending_player_id, _b.pending_scenario_id)
			_bare.year = _b._clock.year
			_bare.month = _b._clock.month
			return _start(true)
		"closing":
			return _watch()
		"settle":
			# Both surfaces lay themselves out before anything is aimed at them.
			_settle_left -= 1
			return _aim_and_fire() if _settle_left <= 0 else false
		"under_fire":
			return _watch_under_fire()
	return false


## Both games to the last day of the month by hand, then the rollover: A's by
## hand, B's by real time, C's by tick_month(). The first month also presses a
## key while it closes.
func _start(first: bool) -> bool:
	for game in [_a, _b]:
		if game._state == null:
			_fail("a main scene built no GameState")
			return _finish()
		# The engine must not advance B on its own: real time is handed in below,
		# exactly one day of it.
		game._clock.set_process(false)
		game._clock.set_speed(1)
		while game._clock.day < game._clock._days_in_month(game._clock.month, game._clock.year):
			game._clock.advance_one_day()

	var history_a: int = _a._state.history.size()
	_a._clock.advance_one_day()
	if _a._month_runner.running():
		_fail("a hand-driven day left its month running across frames")
	if _a._state.history.size() != history_a + 1:
		_fail("a hand-driven day returned before its month was done")
	_tick_bare()

	var history_b: int = _b._state.history.size()
	var last_day: int = _b._state.day
	# Whatever paused B last month (a desk, an offer) is let go: real time only
	# passes on an unpaused clock, and A's hand-driven days never asked.
	_b._clock.paused = false
	_b._clock._process(1.0 / _b._clock.SPEED_DAYS_PER_SECOND[0])
	if not _b._month_runner.running():
		_fail("real time reaching the 1st ran its month inside one frame")
		return _finish()
	if not _b._clock.held:
		_fail("the clock is not held while its month closes")
	if _b._state.day != last_day:
		_fail("the 1st was announced before its month had run")

	if not first:
		_phase = "closing"
		return false
	# A key the player presses while the month closes.
	_press(KEY_F12)
	if _recorder.presses != 0:
		_fail("a key pressed while the month closed reached the game mid-month")
	if _b._state.history.size() != history_b:
		_fail("the month's history entry landed before the runner ran a frame")
	_phase = "closing"
	return false


func _watch() -> bool:
	if _b._month_runner.running():
		_month_frames += 1
		if _b._clock.day != 1 or _b._state.day == 1:
			_fail("the calendar moved, or the 1st was announced, while the month closed")
		if _b._windows.process_mode != Node.PROCESS_MODE_DISABLED:
			_fail("the windows went on processing while the month closed")
		if _months_done == 0 and _recorder.presses != 0:
			_fail("a key pressed while the month closed reached the game mid-month")
		return false

	_months_done += 1
	if _month_frames < 1:
		_fail("B's month closed inside the frame that started it")
	if _b._clock.held:
		_fail("the clock is still held after its month closed")
	if _b._state.day != 1:
		_fail("the 1st's day_advanced was never delivered after the month")
	if _b._windows.process_mode != Node.PROCESS_MODE_INHERIT:
		_fail("the windows did not resume processing after the month")
	if _recorder.presses != 1:
		_fail("the key pressed while the month closed reached the game %d times after it, not once" % _recorder.presses)
	if _dump(_a._state) != _dump(_b._state):
		_fail("month %d, run across frames, saved differently from the month run whole" % _months_done)
		return _finish()
	if _dump(_bare) != _dump(_b._state):
		_fail("month %d, run across frames by the game, saved differently from tick_month() on a bare state" % _months_done)
		return _finish()
	_month_frames = 0
	if _months_done < MONTHS:
		return _start(false)
	_prepare_under_fire()
	return false


## The seventh month. The budget window is pinned top-right and the briefing for
## a bill is open, both in reach of the pointer; then real time reaches the 1st
## and, while the month closes, the player commits the budget, proposes the
## bill, pauses, picks speed 3 and asks for the save/load dialog -- in that order,
## the clicks first so no dialog they summon covers them on the replay.
func _prepare_under_fire() -> void:
	_b._windows.open("budget")
	var budget_frame: Control = _b._windows.frame("budget")
	budget_frame.set_pinned(true)
	budget_frame.position = Vector2(_b._windows.size.x - budget_frame.size.x - 30.0, 70.0)
	var law = _b._loader.laws[0]
	_law_name = String(law.law_name)
	_b._briefing.open_for_law(law, _b._state, _b._loader)
	_b._briefing.show()
	_settle_left = 3
	_phase = "settle"


func _aim_and_fire() -> bool:
	var commit: Button = _b._budget_panel._commit_button
	var propose := _find_button(_b._briefing, "Propose the bill")
	if propose == null:
		_fail("premise: the briefing has no 'Propose the bill' button")
		return _finish()
	for target in [commit, propose]:
		if _hovered_at(target.get_global_rect().get_center()) != target:
			_fail("premise: the point aimed at '%s' reaches %s, not the button" % [
				target.text, _hovered_at(target.get_global_rect().get_center())])
			return _finish()

	for game in [_a, _b]:
		while game._clock.day < game._clock._days_in_month(game._clock.month, game._clock.year):
			game._clock.advance_one_day()
	_tick_bare()
	_speed_before = _b._clock.speed
	_b._clock.paused = false
	_b._clock._process(1.0 / _b._clock.SPEED_DAYS_PER_SECOND[_b._clock.speed - 1])
	if not _b._month_runner.running():
		_fail("premise: the seventh month did not start across frames")
		return _finish()
	# The instant the month is done: before the clock lets go and the deferred
	# input is replayed, B must be C, with not one command in it.
	var finish: Callable = _b._month_runner._done
	_b._month_runner._done = func(report: Dictionary) -> void:
		_at_month_end = {
			"dump": _dump(_b._state),
			"paused": _b._clock.paused,
			"speed": _b._clock.speed,
			"save_dialog": _b._save_load_panel.visible,
			"effects": _effect_labels(),
		}
		finish.call(report)
		_at_month_end["paused_after_tail"] = _b._clock.paused

	_click(commit.get_global_rect().get_center())
	_click(propose.get_global_rect().get_center())
	_press(KEY_SPACE)
	_press(KEY_3)
	_press(KEY_S)
	_phase = "under_fire"
	return false


func _watch_under_fire() -> bool:
	if _b._month_runner.running():
		var labels := _effect_labels()
		if labels.has("Budget change") or labels.has(_law_name):
			_fail("a command given while the month closed was applied mid-month: %s" % [labels])
			return _finish()
		if _b._clock.speed != _speed_before or _b._save_load_panel.visible:
			_fail("a key given while the month closed was acted on mid-month")
			return _finish()
		return false

	if _at_month_end.is_empty():
		_fail("the seventh month ended without passing through the runner's end")
		return _finish()
	if String(_at_month_end["dump"]) != _dump(_bare):
		_fail("the month closed under fire is not the month tick_month() runs on a bare state")
	var labels_then: Array = _at_month_end["effects"]
	if labels_then.has("Budget change") or labels_then.has(_law_name):
		_fail("at the month's end a command given during it was already applied: %s" % [labels_then])
	if int(_at_month_end["speed"]) != _speed_before or bool(_at_month_end["save_dialog"]):
		_fail("at the month's end a key given during it was already acted on")

	# After it: every command, once.
	var labels_now := _effect_labels()
	if labels_now.count("Budget change") != 1:
		_fail("the budget commit given during the month landed %d times after it, not once" % labels_now.count("Budget change"))
	if labels_now.count(_law_name) != 1:
		_fail("the bill proposed during the month landed %d times after it, not once" % labels_now.count(_law_name))
	if _b._clock.speed != 3:
		_fail("the speed picked during the month was never applied: speed %d" % _b._clock.speed)
	if _b._clock.paused == bool(_at_month_end["paused_after_tail"]):
		_fail("the pause given during the month was never applied after it")
	if not _b._save_load_panel.visible:
		_fail("the save/load dialog asked for during the month never opened after it")
	return _finish()


func _tick_bare() -> void:
	_bare.month += 1
	if _bare.month > 12:
		_bare.month = 1
		_bare.year += 1
	WorldMonth.tick_month(_bare, _b._loader)


func _dump(state) -> String:
	return JSON.stringify(state.to_dict(), "", true)


func _effect_labels() -> Array:
	var out: Array = []
	for pending in _b._pending_effects:
		out.append(String(pending["label"]))
	return out


func _press(keycode: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		root.push_input(key, true)


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		root.push_input(click, true)


func _hovered_at(at: Vector2) -> Control:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	return root.gui_get_hovered_control()


func _find_button(node: Node, text: String) -> Button:
	if node is Button and String(node.text) == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	if _failures.is_empty():
		print("test_month_runner: all checks passed (%d months, then one under fire)" % _months_done)
		quit(0)
		return true
	for message in _failures:
		printerr(message)
	printerr("test_month_runner: %d check(s) failed" % _failures.size())
	quit(1)
	return true
