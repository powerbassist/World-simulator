extends SceneTree

## Headless test: godot --headless --script res://tests/test_diary_room.gd
## Non-zero exit on any failure.
##
## Final pre-gate TAKE 2 (QA, v5.3-0-pregate-final-report.md): the Diary's "Book
## here" fell out of view once "Your word" grew. The promise list sits under the
## Diary's only scroll, outside it, and gained a line for every word given or
## broken; by mid-2027 it squeezed the day list's scroll to nothing, and three
## requests lapsed into refusals with their days on screen. Here: a request's
## offered day picked, then the same with a dozen words in flight -- each time
## "Book here" lies inside its scroll's visible rect.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")

## Words given: past the twelve a long term piles up in QA's run (8 to 10 lines).
const WORDS := 12

var _failures: Array[String] = []
var _main
var _frame := 0
var _request_id := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			# A desktop screen, not headless's square one: the squeeze is a height's.
			root.size = Vector2i(1920, 1080)
		3:
			_main._clock.paused = true
			_arrive()
			_pick()
		8:
			_check("with no word given")
			_give_words()
			_pick()
		14:
			_check("with %d words given" % WORDS)
			_finish()
			return true
	return false


func _arrive() -> void:
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	for person in _main._loader.people.get(String(ns.id), []):
		if person.wants.is_empty() or String(person.id) == String(ns.head_of_state_person_id):
			continue
		var arrived := []
		Audiences._arrive(ns, person, person.wants[0], now, arrived)
		if arrived.is_empty():
			continue
		AudienceDriver.after_month(_main, {"audience_requests": {"arrived": arrived, "lapsed": []}})
		var id := String(arrived[0]["id"])
		if Audiences.offered_dates(_main._state, ns, id).any(func(d): return bool(d["free"])):
			_request_id = id
			return
	_fail("premise: no arrived request offers a free day")


## Words in flight to people of this nation, as delegations write them.
func _give_words() -> void:
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	var people: Array = _main._loader.people.get(String(ns.id), [])
	for i in WORDS:
		ns.commitments.append({"kind": "delegated", "person_id": String(people[i % people.size()].id),
			"object": "programme:%s" % String(_main._loader.programme[i % _main._loader.programme.size()]["id"]),
			"made_month": now, "due_month": now + 2 + i % 3})
	AudienceDriver.refresh(_main)


## The Diary open on the request's first free offered day.
func _pick() -> void:
	if _request_id == "":
		return
	var ns = _main._state.player()
	var free: Array = Audiences.offered_dates(_main._state, ns, _request_id).filter(func(d): return bool(d["free"]))
	_main._windows.open("calendar")
	_main._calendar_panel._grid.pick(int(free[0]["year"]), int(free[0]["month"]), int(free[0]["day"]))


func _check(label: String) -> void:
	if _request_id == "":
		return
	var book := _main._calendar_panel.find_child("BookHere_%s" % _request_id, true, false) as Control
	if book == null or not book.is_visible_in_tree():
		_fail("%s: the picked day shows no Book here" % label)
		return
	var scroll: Node = book.get_parent()
	while scroll != null and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	if scroll == null:
		_fail("%s: Book here is in no scroll" % label)
		return
	var view := (scroll as ScrollContainer).get_global_rect()
	var at := book.get_global_rect()
	if view.size.y < at.size.y or not view.encloses(at):
		_fail("%s: Book here (%s) lies outside its scroll's view (%s)" % [label, at, view])


func _finish() -> void:
	for f in _failures:
		printerr("FAIL: %s" % f)
	if _failures.is_empty():
		print("test_diary_room: all checks passed")
	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)
