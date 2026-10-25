extends SceneTree

## Headless test: godot --headless --script res://tests/test_exposure_desk.gd
## Non-zero exit on any failure.
##
## V5.2c c1: an exposure needs no surface of its own -- it is a scandal on the
## desk (the plan's "What Interface must build"). Each exposure event in content,
## armed through the sim's chain door (Events.arm) for next month and reached
## through main's own month runner, arrives as a decision card: its title the
## event's row name, never its id, and every choice a button with words.

const Events = preload("res://src/sim/events.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _events: Array = []


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_arm_every_exposure()
		if _events.is_empty():
			return _end()
	elif _frame > 4 and not _main._month_runner.running():
		_check_cards()
		return _end()
	return false


## Every exposure event at once: the desk holds QUEUE_MAX, and the chain door
## waits for room, so the ones that land are checked and the rest wait their turn.
func _arm_every_exposure() -> void:
	var state = _main._state
	var ns = state.player()
	var next: int = int(state.year) * 12 + int(state.month) + 1
	for ev in _main._loader.events:
		if String(ev.exposure_route) != "":
			_events.append(ev)
	if _events.is_empty():
		_fail("premise: content has no exposure event")
		return
	for ev in _events:
		if not Events.arm(ns, _main._loader, String(ev.id), next):
			_fail("premise: Events.arm refused %s" % ev.id)
	var year := floori((next - 1) / 12.0)
	_main._on_month_elapsed(year, next - year * 12)


func _check_cards() -> void:
	var ns = _main._state.player()
	var carded := 0
	for ev in _events:
		var on_desk := false
		for entry in ns.event_queue:
			if String(entry.get("event_id", "")) == String(ev.id):
				on_desk = true
		if not on_desk:
			continue
		var card_id := ""
		for id in _main._event_cards:
			if String(_main._event_cards[id]) == String(ev.id):
				card_id = String(id)
		if card_id == "":
			_fail("the exposure %s reached the desk with no decision card" % ev.id)
			continue
		carded += 1
		var title := Strings.row_name("events", ev)
		if title == "" or title == String(ev.id):
			_fail("the exposure %s is titled by its id" % ev.id)
		for choice in ev.choices:
			if Strings.choice_label(ev.id, choice) == "":
				_fail("a choice of %s has no words" % ev.id)
	if carded == 0:
		_fail("no armed exposure reached the desk as a card")


func _fail(message: String) -> void:
	_failures.append(message)


func _end() -> bool:
	if _failures.is_empty():
		print("test_exposure_desk: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
