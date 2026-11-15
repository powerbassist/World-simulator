extends SceneTree

## Headless test: godot --headless --script res://tests/test_briefing_clock.gd
## Non-zero exit on any failure.
##
## G1, the chief off the clock (chief-briefing-brief.md; the author: "Jamais"). The
## game's own clock, running at the player's speed in real frames, crosses month
## boundaries, and
##   - a month end never pauses for the chief: the briefing's card stays down, the
##     clock keeps running, the date moves on, and the clock line names no briefing;
##   - the month's ranking is still stored, and the chief's mark in the title bar
##     names its first line (title and deadline chip);
##   - when he speaks, his line is a caption under the mark (no dim, no key), and the
##     voice he says it in is gated on the caption, not on the card;
##   - a real click on the mark opens the read he was asked for: it holds the clock
##     while it is open, the clock line says so, and a real click on Continue gives
##     the speed back;
##   - a request the read NAMES counts as seen when the read opens (#207's rule): its
##     arrival slowed the clock from 3 to 1 by AudienceDriver's own rule, and the
##     closed read leaves 3 -- on a line, in the footer, folded into another
##     request's "+N more"; a speed the player picked after the arrival (2) is kept.

const Click = preload("res://tests/click.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")
const PriorityWords = preload("res://src/ui/priority_words.gd")
const Voice = preload("res://src/ui/voice.gd")
const Programme = preload("res://src/sim/programme.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const AudK = preload("res://src/sim/audience_constants.gd")

const SPEED := 4
const TIMEOUT_FRAMES := 900
const RUN_FRAMES := 30
## Month ends crossed with the clock running before the mark is clicked.
const BOUNDARIES := 3
const ARRIVAL_FROM := 3
const SEEN_CASES := [["line", 0, 3], ["footer", 0, 3], ["line", 2, 2], ["folded", 0, 3]]

var _failures: Array[String] = []
var _main
var _frame := 0
var _phase := ""
var _since := 0
var _month := 0
var _crossed := 0
var _date := Vector3i()
var _card
var _case := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	_since += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_start()
		return false
	if _since > TIMEOUT_FRAMES:
		_fail("timed out in phase '%s' (date %s, paused %s, card %s)" % [_phase, _today(), _main._clock.paused, _card.visible])
		_finish()
		return true
	match _phase:
		"to_boundary":
			if int(_main._clock.month) != _month and not _main._month_runner.running():
				_check_month_end()
				_date = _today()
				_go("running")
		"running":
			# The clock runs on after the month end: the date moves (the timeout fails it).
			if _today() == _date or _since < RUN_FRAMES:
				return false
			_crossed += 1
			if _crossed < BOUNDARIES:
				_quiet_desk()
				_month = int(_main._clock.month)
				_last_day()
				_go("to_boundary")
				return false
			Click.half(_main.get_viewport(), _mark(), true)
			_go("mark_release")
		"mark_release":
			Click.half(_main.get_viewport(), _mark(), false)
			_go("read")
		"read":
			if _since < 2:
				return false
			if not _card.visible:
				_fail("a click on the chief's mark did not open his read")
			if not _main._clock.paused:
				_fail("the read the player opened does not hold the clock")
			# The speed Continue gives back: the clock's under the read (opening it counts
			# a named request as seen, which may already have given an arrival's speed back).
			_speed_before_read = _main._clock.speed
			if HoldReason.show(_main) != tr("Paused: the monthly briefing."):
				_fail("the clock line under the read: '%s'" % HoldReason.show(_main))
			Click.half(_main.get_viewport(), _card._close, true)
			_go("close_release")
		"close_release":
			Click.half(_main.get_viewport(), _card._close, false)
			_go("closed")
		"closed":
			if _since < 2:
				return false
			if _card.visible:
				_fail("Continue did not close the read")
			if _main._clock.paused:
				_fail("Continue did not give the clock back")
			if _main._clock.speed != _speed_before_read:
				_fail("the clock resumed at %d, not the %d it had" % [_main._clock.speed, _speed_before_read])
			_seen_case()
		"seen_press":
			Click.half(_main.get_viewport(), _card._close, true)
			_go("seen_release")
		"seen_release":
			Click.half(_main.get_viewport(), _card._close, false)
			_go("seen_check")
		"seen_check":
			if _since < 2:
				return false
			var c: Array = SEEN_CASES[_case]
			if _card.visible:
				_fail("Continue did not close the read (case %s)" % str(c))
			if _main._clock.speed != int(c[2]):
				_fail("a request named on the read's %s, hand speed %d: the clock left at speed %d, not %d" % [
					c[0], c[1], _main._clock.speed, c[2]])
			_case += 1
			if _case >= SEEN_CASES.size():
				_finish()
				return true
			_seen_case()
	return false


var _speed_before_read := 0


## What every month end must leave: no card, no pause, the ranking kept and named.
func _check_month_end() -> void:
	if _card.visible:
		_fail("month %d: the briefing opened by itself" % _main._clock.month)
	if _main._clock.paused and not _main._decision_holds_clock() and not _main._paused_for_programme:
		_fail("month %d: the month end paused the clock for the chief" % _main._clock.month)
	if HoldReason.show(_main) != "":
		_fail("month %d: the clock line says '%s'" % [_main._clock.month, HoldReason.show(_main)])
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	var lines: Array = game.get("lines", [])
	var mark = _mark()
	if not mark.visible:
		_fail("month %d: no chief's mark in the title bar" % _main._clock.month)
	if lines.is_empty():
		_fail("month %d: the month's ranking was not stored" % _main._clock.month)
	else:
		var want := PriorityWords.title(lines[0], _main._state, _main._loader)
		if mark.title_text() != want:
			_fail("month %d: the mark says '%s', the first line is '%s'" % [_main._clock.month, mark.title_text(), want])
		if mark.chip_text() != PriorityWords.chip(lines[0], _main._state):
			_fail("month %d: the mark's chip '%s'" % [_main._clock.month, mark.chip_text()])
	# The first month always speaks (no situation said yet): his line is the caption.
	if _crossed == 0:
		var caption = _main._hud.chief_caption
		if not caption.visible or caption.text().is_empty():
			_fail("the chief spoke and no caption showed his line")
		var said: Node = _main.get_node_or_null(Voice.NODE)
		if said == null or String(said.get_meta("card", "")) != BriefingDriver.LINE_CARD:
			_fail("the chief's caption showed and his voice did not play (main's voice: %s)" % (
				said.get_meta("card", "") if said != null else "none"))


func _mark():
	return _main._hud.title_bar.chief_mark


func _start() -> void:
	var state = _main._state
	var ns = state.player()
	var offer: Array = Programme.available(state, ns, _main._loader)
	if not offer.is_empty():
		_main._on_programme_chosen(String(offer[0]["id"]))
	_card = BriefingDriver.card_of(_main)
	_quiet_desk()
	_main._windows.close_all()
	_main._clock.set_speed(SPEED)
	_month = int(_main._clock.month)
	_last_day()
	_main._clock.paused = false
	_go("to_boundary")


## One case: a request arrives at speed ARRIVAL_FROM (AudienceDriver slows to 1), the
## player may pick a speed, and the read names it on a line or in the footer.
func _seen_case() -> void:
	var c: Array = SEEN_CASES[_case]
	_quiet_desk()
	var state = _main._state
	var now := int(state.year) * 12 + int(state.month)
	var rid := "%s|seen%d" % [String(_main._loader.people[String(state.player().id)][0].id), _case]
	_main._clock.paused = false
	_main._clock.set_speed(ARRIVAL_FROM)
	AudienceDriver._slow_for(_main, [{"id": rid}])
	if _main._clock.speed != 1:
		_fail("premise: the arrival did not slow the clock to 1")
	if int(c[1]) > 0:
		_main._clock.set_speed(int(c[1]))
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	var cand := Priorities._cand("request", rid, now + 1, 1.0, 1.0, now)
	if String(c[0]) == "folded":
		var line := Priorities._cand("request", rid + "_other", now + 1, 1.0, 1.0, now)
		Priorities._fold_into(line, cand)
		cand = line
	game["lines"] = [] if String(c[0]) == "footer" else [cand]
	game["also"] = [cand] if String(c[0]) == "footer" else []
	BriefingDriver.read(_main, false)  # the lines as staged, not ranked again
	_go("seen_press")


func _quiet_desk() -> void:
	var ns = _main._state.player()
	ns.event_queue.clear()
	ns.audience_requests.clear()
	_main._unseen_events.clear()
	# V5.3 B7's quiet-month call would bring a visitor or a minor event: held off, so
	# no arrival holds the clock -- the hold under test is the chief's.
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	for i in AudK.QUIET_ASKS_MAX:
		ns.audience_asked_month["ZZZ_hold%d" % i] = now
	for ev in _main._loader.events:
		ns.event_category_quiet[ev.category] = 3


func _last_day() -> void:
	var clock = _main._clock
	clock.day = clock._days_in_month(clock.month, clock.year)


func _today() -> Vector3i:
	return Vector3i(_main._clock.year, _main._clock.month, _main._clock.day)


func _go(phase: String) -> void:
	_phase = phase
	_since = 0


func _finish() -> void:
	for f in _failures:
		printerr("FAIL: %s" % f)
	if _failures.is_empty():
		print("test_briefing_clock: all checks passed")
	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)
