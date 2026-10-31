extends SceneTree

## Headless test: godot --headless --script res://tests/test_diary_room.gd
## Non-zero exit on any failure.
##
## Final pre-gate TAKE 2 (QA, v5.3-0-pregate-final-report.md), and #231's QA round:
## the Diary's "Book here" fell out of view. The day list's scroll was the panel's
## only flexible region, so everything that grew beside or under it -- the request
## column beside the grid (a card a pending request), "Your word" under it, a larger
## text size -- squeezed it to nothing, and requests lapsed into refusals with their
## days on screen. Capping one grower (#231's first head) left the others.
##
## Here, QA's whole probe matrix: text at 100 / 115 / 130 %, no word or a dozen in
## flight, one to six pending requests, the first request's first free day picked
## by a click on the grid; at six requests the keyboard's path too (the card's
## Days), and a picked day with two entries, then five, listed beside its "Book
## here". Each time "Book here" lies inside EVERY scroll it sits in -- the day
## list's and the docked page's -- so it is on screen, not merely inside a scroll
## that is not.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Words given: past the twelve a long term piles up in QA's run (8 to 10 lines).
const WORDS := 12
const SCALES := [1.0, 1.15, 1.3]
const MAX_REQUESTS := 6
## A packed day: more entries than the day list's floor holds, so "Book here" stays
## in view only because it is listed first, under the date.
const BUSIEST := 5
## Frames for a case to lay out: the deferred rebuilds, then the containers' sort.
const SETTLE := 5

var _failures: Array[String] = []
var _main
var _frame := 0
var _people: Array = []
var _ids: Array = []
var _cases: Array = []
var _case := -1
var _wait := 0
var _checked := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		# A desktop screen, not headless's square one: the squeeze is a height's.
		root.size = Vector2i(1920, 1080)
		return false
	if _frame == 3:
		_main._clock.paused = true
		_collect()
		for n in range(1, MAX_REQUESTS + 1):
			for scale in SCALES:
				for words in [0, WORDS]:
					_cases.append({"n": n, "scale": scale, "words": words, "path": "click"})
				if n == MAX_REQUESTS:
					_cases.append({"n": n, "scale": scale, "words": WORDS, "path": "days"})
					_cases.append({"n": n, "scale": scale, "words": WORDS, "path": "busy", "entries": 2})
					_cases.append({"n": n, "scale": scale, "words": WORDS, "path": "busy", "entries": BUSIEST})
		_next()
		return false
	if _frame < 3:
		return false
	_wait -= 1
	if _wait > 0:
		return false
	_check(_cases[_case])
	if _case + 1 >= _cases.size() or not _failures.is_empty() and _failures[0].begins_with("premise"):
		_finish()
		return true
	_next()
	return false


func _next() -> void:
	_case += 1
	var c: Dictionary = _cases[_case]
	while _ids.size() < int(c["n"]) and not _people.is_empty():
		_arrive_one()
	if _ids.size() < int(c["n"]):
		_fail("premise: only %d requests offering a free day arrived, %d wanted" % [_ids.size(), int(c["n"])])
	UiTheme.set_text_scale(float(c["scale"]))
	# The settings row's own path for a text size changed mid-game.
	UiTheme.rebuild(_main)
	_set_words(int(c["words"]))
	AudienceDriver.refresh(_main)
	_main._windows.open("calendar")
	# The opened panel's own redraw, now rather than next frame: it would hand the
	# grid its items again over the busy day's.
	_main._calendar_panel._process(0.0)
	var free := _free_days(String(_ids[0]))
	match String(c["path"]):
		"days":
			# The card's Days: the grid turns to the first free day and the keyboard
			# lands on its Book here.
			_main._calendar_panel.requests.focus_requested.emit(String(_ids[0]))
		"busy":
			# The day's own entries listed beside its Book here.
			var date: Dictionary = free[0]
			var grid = _main._calendar_panel._grid
			var items: Array = grid._items.duplicate()
			for i in int(c["entries"]):
				items.append({"year": int(date["year"]), "month": int(date["month"]), "day": int(date["day"]),
					"text": "Council votes", "mark": "fixed", "cancel": ""})
			grid.show_items(_main._state, _main._loader, items)
			grid.pick(int(date["year"]), int(date["month"]), int(date["day"]))
		_:
			_main._calendar_panel._grid.pick(int(free[0]["year"]), int(free[0]["month"]), int(free[0]["day"]))
	_wait = SETTLE


## People with a want, the head of state's own aside.
func _collect() -> void:
	var ns = _main._state.player()
	for person in _main._loader.people.get(String(ns.id), []):
		if not person.wants.is_empty() and String(person.id) != String(ns.head_of_state_person_id):
			_people.append(person)


## One more request arrived that offers a day the Diary can take.
func _arrive_one() -> void:
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	while not _people.is_empty():
		var person = _people.pop_front()
		var arrived := []
		Audiences._arrive(ns, person, person.wants[0], now, arrived)
		if arrived.is_empty():
			continue
		AudienceDriver.after_month(_main, {"audience_requests": {"arrived": arrived, "lapsed": []}})
		var id := String(arrived[0]["id"])
		if not _free_days(id).is_empty():
			_ids.append(id)
			return


func _free_days(id: String) -> Array:
	return Audiences.offered_dates(_main._state, _main._state.player(), id).filter(func(d): return bool(d["free"]))


## Words in flight to people of this nation, as delegations write them; 0 clears them.
func _set_words(count: int) -> void:
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	var people: Array = _main._loader.people.get(String(ns.id), [])
	for i in range(ns.commitments.size() - 1, -1, -1):
		if String(ns.commitments[i].get("kind", "")) == "delegated":
			ns.commitments.remove_at(i)
	for i in count:
		ns.commitments.append({"kind": "delegated", "person_id": String(people[i % people.size()].id),
			"object": "programme:%s" % String(_main._loader.programme[i % _main._loader.programme.size()]["id"]),
			"made_month": now, "due_month": now + 2 + i % 3})


func _check(c: Dictionary) -> void:
	if _ids.size() < int(c["n"]):
		return
	var label := "text %d %%, %d words, %d requests, %s %d" % [roundi(float(c["scale"]) * 100), int(c["words"]), int(c["n"]), c["path"], int(c.get("entries", 0))]
	var panel = _main._calendar_panel
	if panel.requests.find_children("Request_*", "", true, false).size() != int(c["n"]):
		_fail("premise: %s: the column does not hold %d cards" % [label, int(c["n"])])
		return
	var book := panel.find_child("BookHere_%s" % String(_ids[0]), true, false) as Control
	if book == null or not book.is_visible_in_tree():
		_fail("%s: the picked day shows no Book here" % label)
		return
	# The heading, the Book here and the entries.
	if String(c["path"]) == "busy" and panel._grid.day_list.get_child_count() < 2 + int(c["entries"]):
		_fail("premise: %s: the picked day does not list its entries beside Book here" % label)
		return
	_checked += 1
	var at := book.get_global_rect()
	var scrolls := 0
	var node: Node = book.get_parent()
	while node != null:
		if node is ScrollContainer:
			scrolls += 1
			var view := (node as ScrollContainer).get_global_rect()
			if view.size.y < at.size.y or not view.encloses(at):
				_fail("%s: Book here (%s) lies outside the view of %s (%s)" % [label, at, node.name, view])
				return
		node = node.get_parent()
	if scrolls < 2:
		_fail("%s: Book here sits in %d scroll(s), not the day list's and the page's" % [label, scrolls])


func _finish() -> void:
	UiTheme.set_text_scale(1.0)
	if _checked != _cases.size():
		_failures.append("premise: %d of %d cases checked" % [_checked, _cases.size()])
	for f in _failures:
		printerr("FAIL: %s" % f)
	if _failures.is_empty():
		print("test_diary_room: all %d cases passed" % _checked)
	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)
