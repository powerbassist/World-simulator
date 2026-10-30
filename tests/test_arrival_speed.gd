extends SceneTree

## Headless test: godot --headless --script res://tests/test_arrival_speed.gd
## Non-zero exit on any failure.
##
## The author's "Revenir à ta vitesse après" (2026-10-30), on top of "Ralentir à
## l'arrivée" (2026-10-24): a month that brings a request drops the clock to speed
## 1, and once the player has SEEN it the speed they had comes back
## (audience_driver.gd's _slow_for / _seen). Every click is real, press and release
## frames apart (tests/click.gd):
##   - speed 3 -> arrival -> 1 -> the card clicked -> 3;
##   - speed 2 -> arrival -> 1 -> the card's X -> 2;
##   - speed 3 -> arrival -> 1 -> the player picks 2 -> the card clicked -> still 2:
##     a speed the player chose is theirs, not the arrival's to undo.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _people: Array = []
var _target: Control


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	# Each arrival raises its card to the top of the lane; the press waits a frame
	# for the lane to lay it out there.
	match _frame:
		3:
			# Paused, so no month runs under the test: the speed is a setting either way.
			_main._clock.paused = true
			_pick_people()
			_target = _arrive_at(3, 0, false)
		5:
			_press(true)
		8:
			_press(false)
		10:
			_expect(3, "a request's card clicked did not give the speed back")
			_target = _arrive_at(2, 1, true)
		12:
			_press(true)
		15:
			_press(false)
		17:
			_expect(2, "a request's card closed did not give the speed back")
			_target = _arrive_at(3, 2, false)
			_main._clock.set_speed(2)
		19:
			_press(true)
		22:
			_press(false)
		24:
			_expect(2, "seeing a request undid a speed the player picked after its arrival")
			_finish()
			return true
	return false


## Three people of the played nation with a want, distinct, never the head of state.
func _pick_people() -> void:
	var ns = _main._state.player()
	for person in _main._loader.people.get(String(ns.id), []):
		if not person.wants.is_empty() and String(person.id) != String(ns.head_of_state_person_id) and _people.size() < 3:
			_people.append(person)
	if _people.size() < 3:
		_fail("premise: fewer than three people with a want (%d)" % _people.size())


## At `speed`, person `i` asks through the sim's own arrival and the month's UI half
## runs on it; the clock must drop to 1. Returns what to click on its card: the X
## when `close`, else the card's title (a Label passes the press to the card).
func _arrive_at(speed: int, i: int, close: bool) -> Control:
	if i >= _people.size():
		return null
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	_main._clock.set_speed(speed)
	var arrived := []
	Audiences._arrive(ns, _people[i], _people[i].wants[0], now, arrived)
	AudienceDriver.after_month(_main, {"audience_requests": {"arrived": arrived, "lapsed": []}})
	if _main._clock.speed != 1:
		_fail("an arrival at speed %d did not drop the clock to 1 (%d)" % [speed, _main._clock.speed])
	if arrived.is_empty():
		_fail("premise: %s's request did not arrive" % _people[i].id)
		return null
	var card_id := AudienceDriver.lane_of(_main).card_of(String(arrived[0]["id"]))
	var card = _main._hud.inbox._cards.get(card_id)
	if card == null:
		_fail("the arrived request has no card")
		return null
	_main._hud.inbox.raise_card(card_id)
	for b in card.find_children("*", "Button", true, false):
		if close and (b as Button).text == "X":
			return b
	return null if close else card.find_children("*", "Label", true, false)[0]


func _press(down: bool) -> void:
	if _target == null:
		_fail("nothing to click")
		return
	Click.half(_main.get_viewport(), _target, down)


func _expect(speed: int, message: String) -> void:
	if _main._clock.speed != speed:
		_fail("%s: speed %d, expected %d" % [message, _main._clock.speed, speed])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_arrival_speed: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
