extends SceneTree

## Headless test: godot --headless --script res://tests/test_month_close_pause.gd
## Non-zero exit on any failure.
##
## QA's pre-gate repro (qa-report.md, "PRE-GATE playthrough", issue 1): a quiet
## event sits on the desk with two months left, the clock runs at speed 3, and
## the player presses Space while the month closes. The press is deferred until
## the month is done (month_runner.gd); the month end's lapse guard then holds
## the clock for the event's last month. The replayed press was a TOGGLE, so it
## resumed the clock the guard had just held, and the decision defaulted
## unanswered on the next 1st.
##
## What must hold: the press was made against a running clock, so it meant
## pause -- the clock is paused after the month, and the decision's hold (the
## flag the next press reads) is still up.
##
## A second month, closed on the window's close button (QA's Q1 on #464): a close
## is a notification, which the runner's deferral never saw, so the pause menu
## opened on half a month and remembered a running clock -- Resume then ran it over
## the hold the month's end had raised.

const Events = preload("res://src/sim/events.gd")

const MAX_FRAMES := 600

var _failures: Array[String] = []
var _main
var _frame := 0
var _event_id := ""
var _closing := false
var _by_close_button := false
var _day_closed_on := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	if _frame > MAX_FRAMES:
		_fail("the month never finished closing")
		return _finish()
	if not _closing:
		return _stage_and_close()
	if _main._month_runner.running():
		return false
	_check_after_the_month()
	if _by_close_button or not _failures.is_empty():
		return _finish()
	_by_close_button = true
	_closing = false
	return false


func _stage_and_close() -> bool:
	var clock = _main._clock
	var ns = _main._state.player()
	var ev = null
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt):
			ev = candidate
			break
	if ev == null:
		_fail("no quiet event in the loader to stage the repro with")
		return _finish()
	_event_id = String(ev.id)
	# The desk as QA found it: the quiet event announced and its card already
	# shown, two months left -- the month end takes it to one and the lapse
	# guard holds the clock for it.
	ns.event_queue.clear()
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) == _event_id:
			entry["months_left"] = 2
	_main._unseen_events.clear()
	_main._unseen_events[_event_id] = false
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	# One close press only asks; cut the real Quit all the same, so a regression cannot end the run as a pass.
	for link in _main._pause_menu.quit_requested.get_connections():
		_main._pause_menu.quit_requested.disconnect(link["callable"])

	clock.set_process(false)
	clock.set_speed(3)
	while clock.day < clock._days_in_month(clock.month, clock.year):
		clock.advance_one_day()
	clock.paused = false
	clock._process(1.0 / clock.SPEED_DAYS_PER_SECOND[2])
	if not _main._month_runner.running():
		_fail("premise: the 1st did not start a month across frames")
		return _finish()
	_day_closed_on = clock.day
	if _by_close_button:
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		_closing = true
		return false
	# Space while the month closes: deferred by the runner, replayed after it.
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.physical_keycode = KEY_SPACE
		key.pressed = pressed
		root.push_input(key, true)
	_closing = true
	return false


func _check_after_the_month() -> void:
	var left := -1
	for entry in _main._state.player().event_queue:
		if String(entry.get("event_id", "")) == _event_id:
			left = int(entry.get("months_left", -1))
	if left != 1:
		_fail("premise: the staged event has %d months left after the month, not 1" % left)
	var press := "Space pressed"
	if _by_close_button:
		press = "Resume after a window close sent"
		if not _main._pause_menu.visible or not _main._pause_menu.warns():
			_fail("a window close sent while the month closed did not put the pause menu's question")
		if _main._month_runner._asked.is_valid():
			_fail("the window close was kept after the month answered it: the next month's end would press Quit again")
		_main._pause_menu.resumed.emit()
		for i in 35:  # five seconds of the real clock at speed 3
			_main._clock._process(1.0 / _main._clock.SPEED_DAYS_PER_SECOND[2])
		if _main._clock.day != _day_closed_on:
			_fail("%s while the month closed ran the clock from day %d to %d" % [press, _day_closed_on, _main._clock.day])
	if not _main._clock.paused:
		_fail("%s while the month closed left the clock RUNNING after it" % press)
	if not _main._paused_for_decision:
		_fail("%s while the month closed released the decision's hold" % press)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	if _failures.is_empty():
		print("test_month_close_pause: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
