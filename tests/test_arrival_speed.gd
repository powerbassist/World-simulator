extends SceneTree

## Headless test: godot --headless --script res://tests/test_arrival_speed.gd
## Non-zero exit on any failure.
##
## The author's "Revenir à ta vitesse après" (2026-10-30), on top of "Ralentir à
## l'arrivée" (2026-10-24): a month that brings a request drops the clock to speed
## 1, and once the player has SEEN it the speed they had comes back
## (audience_driver.gd's _slow_for / _seen). Every click is real, press and release
## frames apart (tests/click.gd). Each case: a speed, an arrival (-> 1), a way of
## seeing it, the speed expected after:
##   - the card clicked -> back; its X -> back; an answer (Decline) -> back; the
##     title bar's requests mark -> back (QA's TAKE 2 on #207: all four verbs);
##   - the player picks a speed after the arrival -> theirs stays;
##   - a load between the arrival and the click -> 1 stays (the load forgets it);
##   - the code dismissing the card (a lapse, a card put up again) -> 1 stays: that
##     is not the player having seen it;
##   - Book a day STARTS an answer (the parent's call on QA's #207): with the date
##     picker open the clock stays at 1, and the booking's end -- a day booked, or
##     the picker's Cancel -- gives the speed back.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Click = preload("res://tests/click.gd")

## [speed before, how it is seen, speed expected after, what a failure means]
const CASES := [
	[3, "body", 3, "a request's card clicked did not give the speed back"],
	[2, "x", 2, "a request's card closed did not give the speed back"],
	[3, "answer", 3, "a request answered from its card did not give the speed back"],
	[2, "mark", 2, "the requests mark did not give the speed back"],
	[3, "hand", 2, "seeing a request undid a speed the player picked after its arrival"],
	[3, "load", 1, "a load between the arrival and the click still gave the speed back"],
	[3, "code", 1, "a card the code took down gave the speed back"],
	[3, "book_day", 3, "a day booked from the picker did not give the speed back"],
	[2, "book_cancel", 2, "the picker's Cancel did not give the speed back"],
]
## Frames from an arrival to its press, to its release, to the check: the press
## waits a frame for the lane to lay out the raised card.
const PRESS_AT := 2
const RELEASE_AT := 5
const CHECK_AT := 7

var _failures: Array[String] = []
var _main
var _frame := 0
var _people: Array = []
var _case := -1
var _case_frame := 0
var _target: Control
## 1 once a booking case's Book click is done and its picker click is next.
var _stage := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _case < 0:
		# Paused, so no month runs under the test: the speed is a setting either way.
		_main._clock.paused = true
		_pick_people()
		_next()
		return false
	var at := _frame - _case_frame
	if _target != null and at == PRESS_AT:
		_press(true)
	elif _target != null and at == RELEASE_AT:
		_press(false)
	elif at == CHECK_AT:
		var c: Array = CASES[_case]
		if String(c[1]).begins_with("book") and _stage == 0:
			if _main._clock.speed != 1:
				_fail("opening the date picker gave the speed back (%d) before the booking ended" % _main._clock.speed)
			_stage = 1
			_case_frame = _frame
			_target = _picker_button(String(c[1]) == "book_day")
			return false
		if _main._clock.speed != int(c[2]):
			_fail("%s: speed %d, expected %d" % [c[3], _main._clock.speed, c[2]])
		if _case + 1 >= CASES.size():
			_finish()
			return true
		_next()
	return false


## One person of the played nation with a want per case, distinct, never the head
## of state.
func _pick_people() -> void:
	var ns = _main._state.player()
	for person in _main._loader.people.get(String(ns.id), []):
		if not person.wants.is_empty() and String(person.id) != String(ns.head_of_state_person_id) \
				and _people.size() < CASES.size():
			_people.append(person)
	if _people.size() < CASES.size():
		_fail("premise: fewer than %d people with a want (%d)" % [CASES.size(), _people.size()])


func _next() -> void:
	_case += 1
	_stage = 0
	_case_frame = _frame
	_target = _arrive(_case)


## At the case's speed, its person asks through the sim's own arrival and the
## month's UI half runs on it; the clock must drop to 1. Returns what to click, or
## null when the case sees (or does not see) the request without a click.
func _arrive(i: int) -> Control:
	if i >= _people.size():
		return null
	var c: Array = CASES[i]
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	_main._clock.set_speed(int(c[0]))
	var arrived := []
	Audiences._arrive(ns, _people[i], _people[i].wants[0], now, arrived)
	AudienceDriver.after_month(_main, {"audience_requests": {"arrived": arrived, "lapsed": []}})
	if _main._clock.speed != 1:
		_fail("an arrival at speed %d did not drop the clock to 1 (%d)" % [c[0], _main._clock.speed])
	if arrived.is_empty():
		_fail("premise: %s's request did not arrive" % _people[i].id)
		return null
	var card_id := AudienceDriver.lane_of(_main).card_of(String(arrived[0]["id"]))
	var card = _main._hud.inbox._cards.get(card_id)
	if card == null:
		_fail("the arrived request has no card")
		return null
	_main._hud.inbox.raise_card(card_id)
	var buttons: Array = card.find_children("*", "Button", true, false)
	match String(c[1]):
		"x":
			for b in buttons:
				if (b as Button).text == "X":
					return b
		"answer", "book_day", "book_cancel":
			# Decline is the card's third answer, Book its first (request_lane.gd's order).
			var answers := buttons.filter(func(b): return (b as Button).text != "X")
			var at := 2 if String(c[1]) == "answer" else 0
			return answers[at] if answers.size() > at else null
		"mark":
			return _main._hud.title_bar._requests
		"hand":
			_main._clock.set_speed(2)
		"load":
			AudienceDriver.after_load(_main)
		"code":
			_main._hud.inbox.dismiss(card_id)
			return null
	return card.find_children("*", "Label", true, false)[0]


## In the open picker: its first free day, or its Cancel.
func _picker_button(day: bool) -> Control:
	var block = _main._calendar_panel.audience
	if not block.visible or block.request_id() == "":
		_fail("Book a day did not open the date picker")
		return null
	if not day:
		return block.find_child("Cancel", true, false)
	for b in block.find_children("*", "Button", true, false):
		if String(b.name) != "Cancel" and not (b as Button).disabled:
			return b
	_fail("premise: the picker offers no free day")
	return null


func _press(down: bool) -> void:
	if _target == null or not is_instance_valid(_target):
		_fail("nothing to click in case %d" % _case)
		return
	Click.half(_main.get_viewport(), _target, down)


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
