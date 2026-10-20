extends SceneTree

## Headless test: godot --headless --script res://tests/test_month_runner.gd
## Non-zero exit on any failure.
##
## V5.1-0a: the month a player watches runs across frames (src/ui/month_runner.gd)
## and the month a test drives by hand runs whole. Two new games side by side:
## A's month is one Clock.advance_one_day() call, B's is the same day reached by
## real time passing (the clock's own _process), and B is watched frame by frame.
## What must hold, each a silent failure if it does not:
##
##   - B's month takes more than one frame (the freeze is gone) while A's is
##     done before the call returns (every harness keeps its whole month);
##   - while B's month closes, its calendar does not move, its 1st has not been
##     announced, its windows hold their frame, and a key the player presses is
##     not acted on -- it is acted on once the month is done, not lost;
##   - and B ends where A ends, byte for byte: the same month, the UI's half
##     included, in the same order -- for six months running, so a month that
##     pauses itself mid-close (an event on the desk, the term-start offer) is
##     among them.
##
## Driven a frame at a time because the runner IS frames, and because a Control
## outside the scene tree has not run _ready() (docs/engine-decision.md).

const MAX_FRAMES := 3000
const MONTHS := 6

var _failures: Array[String] = []
var _a
var _b
var _frame := 0
var _phase := "boot"
var _month_frames := 0
var _months_done := 0
var _recorder: Recorder


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
			return _start(true)
		"closing":
			return _watch()
	return false


## Both games to the last day of the month by hand, then the rollover: A's by
## hand, B's by real time. The first month also presses a key while it closes.
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
	var key := InputEventKey.new()
	key.keycode = KEY_F12
	key.physical_keycode = KEY_F12
	key.pressed = true
	root.push_input(key, true)
	var release: InputEventKey = key.duplicate()
	release.pressed = false
	root.push_input(release, true)
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
	if JSON.stringify(_a._state.to_dict()) != JSON.stringify(_b._state.to_dict()):
		_fail("month %d, run across frames, saved differently from the month run whole" % _months_done)
		return _finish()
	if _months_done < MONTHS:
		_month_frames = 0
		return _start(false)
	return _finish()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	if _failures.is_empty():
		print("test_month_runner: all checks passed (%d months)" % _months_done)
		quit(0)
		return true
	for message in _failures:
		printerr(message)
	printerr("test_month_runner: %d check(s) failed" % _failures.size())
	quit(1)
	return true
