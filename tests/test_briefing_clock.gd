extends SceneTree

## Headless test: godot --headless --script res://tests/test_briefing_clock.gd
## Non-zero exit on any failure.
##
## V5.3-0, band RF4 observed rather than derived (QA's RECORD on #217): the game's
## own clock, running at the player's speed in real frames, crosses a month
## boundary, and
##   - the monthly briefing opens and the clock is paused: the date does not move
##     across frames while the card is up;
##   - a real click on Continue (press and release frames apart) resumes the clock
##     at the speed it had when the card opened (a request's arrival may have slowed
##     it to 1 by its own rule, audience_driver.gd; the briefing changes nothing),
##     and the date moves again;
##   - with Messages' "Only when something is new", a month whose three are last
##     month's three crosses its boundary without stopping. Which month that is
##     depends on the sim's arrivals, so the test crosses boundaries until the
##     ranking says "nothing new" (up to QUIET_TRIES), and checks that one; every
##     month it crosses that has something new must hold.

const Click = preload("res://tests/click.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const Programme = preload("res://src/sim/programme.gd")
const MessageSettings = preload("res://src/ui/message_settings.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")

const SPEED := 4
const TIMEOUT_FRAMES := 900
const HELD_FRAMES := 30
const QUIET_TRIES := 8

var _failures: Array[String] = []
var _main
var _frame := 0
var _phase := ""
var _since := 0
var _date := Vector3i()
var _card
var _speed := 0
var _tries := 0


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
			if _card.visible and not _main._month_runner.running():
				_date = _today()
				_speed = _main._clock.speed
				_go("held")
		"held":
			if not _main._clock.paused:
				_fail("the briefing is up and the clock runs")
			if _today() != _date:
				_fail("the date moved under the briefing: %s -> %s" % [_date, _today()])
			if _since >= HELD_FRAMES:
				_quiet_desk()
				Click.half(_main.get_viewport(), _card._close, true)
				_go("release")
		"release":
			Click.half(_main.get_viewport(), _card._close, false)
			_go("resumed")
		"resumed":
			if _since == 2:
				if _card.visible:
					_fail("Continue did not close the briefing")
				if _main._clock.paused:
					_fail("Continue did not resume the clock (holds: decision %s, programme %s)" % [
						_main._decision_holds_clock(), _main._paused_for_programme])
				if _main._clock.speed != _speed:
					_fail("the clock resumed at speed %d, not the %d it had" % [_main._clock.speed, _speed])
			elif _today() != _date:
				_quiet_month()
				_go("quiet")
		"quiet":
			if _main._month_runner.running() or int(_main._clock.month) == _date.y:
				return false
			var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
			var fresh := bool(game["pending"].get("new", true))
			_tries += 1
			if fresh:
				if not _card.visible:
					_fail("'Only when something is new' skipped a month with something new")
				if _tries >= QUIET_TRIES:
					_fail("premise: %d months crossed, none without something new" % _tries)
					_finish()
					return true
				BriefingDriver.close(_main)
				_main._clock.paused = false
				_quiet_month()
				_go("quiet")
				return false
			if _card.visible:
				_fail("'Only when something is new' held a month that repeats the last")
			if _main._clock.paused and not _main._decision_holds_clock() and not _main._paused_for_programme:
				_fail("the quiet month's boundary paused the clock")
			print("quiet month found after %d boundaries" % _tries)
			_finish()
			return true
	return false


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
	_last_day()
	_main._clock.paused = false
	_go("to_boundary")


## No arrival holds the clock in this test: the hold under test is the briefing's.
func _quiet_desk() -> void:
	var ns = _main._state.player()
	ns.event_queue.clear()
	ns.audience_requests.clear()
	_main._unseen_events.clear()


## The next boundary repeats this month's three: the setting on, and the memory
## of the last briefing what the next ranking will find.
func _quiet_month() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value(MessageSettings.SECTION, MessageSettings.BRIEFING_NEW_ONLY_KEY, true)
	cfg.save(SettingsPanel.CONFIG_PATH)
	_quiet_desk()
	var ns = _main._state.player()
	ns.commitments.clear()
	ns.person_grudges.clear()
	ns.tabled_bill = {}
	_date = _today()
	_last_day()


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
