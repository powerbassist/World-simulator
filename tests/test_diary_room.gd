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
## Here, QA's whole probe matrix: text at 100 / 115 %, no word or a dozen in
## flight, one to six pending requests, the first request's first free day picked
## by a click on the grid; at six requests the keyboard's path too (the card's
## Days), a click on a list the player had scrolled down, and a picked day with
## two entries, then five, listed beside its "Book here". Each time "Book here"
## lies inside EVERY scroll it sits in -- the day list's and the docked page's --
## so it is on screen, not merely inside a scroll that is not.
##
## The month page (picture A, Interface's card): the booking moved onto the grid -- the
## request is armed (the card's See them, or the inbox's Go) and a click on a free day books
## it. The same matrix now holds the armed request's first free DAY and its See them on
## screen inside every scroll they sit in, and the line over the grid saying until when.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const DateText = preload("res://src/ui/date_text.gd")

## Words given: past the twelve a long term piles up in QA's run (8 to 10 lines).
const WORDS := 12
const SCALES := [1.0, 1.15]
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
					_cases.append({"n": n, "scale": scale, "words": WORDS, "path": "scrolled"})
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
	var free := _free_days(String(_ids[0]))
	_main._calendar_panel._grid.arm({})
	match String(c["path"]):
		"days":
			# The inbox card's Go: the request armed, the grid on its first free day.
			AudienceDriver.lane_of(_main).book_requested.emit(String(_ids[0]))
		_:
			var see := _main._calendar_panel.find_child("See_%s" % String(_ids[0]), true, false) as Button
			if see == null:
				_fail("premise: the request's card has no See them")
			else:
				see.pressed.emit()
	_main._calendar_panel._process(0.0)
	match String(c["path"]):
		"days":
			pass
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
		"scrolled":
			# The player had scrolled the list down (LATER, a long day) before the click.
			var grid = _main._calendar_panel._grid
			grid._list_scroll.scroll_vertical = 10000
			grid.pick(int(free[0]["year"]), int(free[0]["month"]), int(free[0]["day"]))
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
	if Audiences.pending(_main._state.player()).size() != int(c["n"]):
		_fail("premise: %s: %d requests are not waiting" % [label, int(c["n"])])
		return
	if String(panel._grid.armed.get("id", "")) != String(_ids[0]):
		_fail("%s: the request is not armed (%s)" % [label, panel._grid.armed])
		return
	var first: Dictionary = _free_days(String(_ids[0]))[0]
	var day := panel._grid._days.get_node_or_null("Day_%d" % int(first["day"])) as Control
	if day == null or not bool(day.tinted):
		_fail("%s: the first free day is not on the grid, tinted" % label)
		return
	# The heading and the entries.
	if String(c["path"]) == "busy" and panel._grid.day_list.get_child_count() < 1 + int(c["entries"]):
		_fail("premise: %s: the picked day does not list its entries" % label)
		return
	_check_why_these_days(panel, label)
	_checked += 1
	# Pass 2 TAKE 6: at 115 % the page grew wider than the dock -- a sideways scroll, the
	# column's right edge past the dock. Every scroll over the column must hold its width.
	var col := panel.people as Control
	var up: Node = col.get_parent()
	while up != null:
		if up is ScrollContainer:
			var sc := up as ScrollContainer
			var inner := sc.get_child(0) as Control
			if inner != null and inner.get_combined_minimum_size().x > sc.size.x + 0.5:
				_fail("%s: the page needs %.0f px across, its view %s has %.0f: a sideways scroll" % [label, inner.get_combined_minimum_size().x, sc.name, sc.size.x])
				return
			if col.get_global_rect().end.x > sc.get_global_rect().end.x + 0.5:
				_fail("%s: the people column ends at x %.0f, past its view's %.0f" % [label, col.get_global_rect().end.x, sc.get_global_rect().end.x])
				return
		up = up.get_parent()
	for target in [day, panel.find_child("See_%s" % String(_ids[0]), true, false) as Control]:
		if target == null or not target.is_visible_in_tree():
			_fail("%s: %s is not on screen" % [label, target.name if target != null else "See them"])
			return
		var at: Rect2 = target.get_global_rect()
		var node: Node = target.get_parent()
		while node != null:
			if node is ScrollContainer:
				var view := (node as ScrollContainer).get_global_rect()
				if view.size.y < at.size.y or not view.encloses(at):
					_fail("%s: %s (%s) lies outside the view of %s (%s)" % [label, target.name, at, node.name, view])
					return
			node = node.get_parent()


## Gate 3 (G3-16): "je ne peux choisir la date, alors que mon agenda apparait vide". Since the
## author's "N'importe quel jour libre" (2026-11-20) any free day to the answer-by month books, and
## the line over the grid says until when.
func _check_why_these_days(panel, label: String) -> void:
	var ns = _main._state.player()
	var rid := String(_ids[0])
	var who: String = _main._loader.person_name(String(Audiences.request(ns, rid)["person_id"]))
	var dates: Array = Audiences.offered_dates(_main._state, ns, rid)
	if dates.is_empty():
		_fail("%s: the request has no day at all to read the line against" % label)  # QA's lead 14 on #431
		return
	var last: Dictionary = dates[dates.size() - 1]
	var want := "Click a free day to see %s: any free day until %s." % [who, DateText.day_month_year(int(last["day"]), int(last["month"]), int(last["year"]))]
	var line := panel.find_child("ArmedLine", true, false) as Label
	if line == null or not line.is_visible_in_tree() or line.text != want:
		_fail("%s: the line over the grid says '%s', not '%s'" % [label, line.text if line != null else "nothing", want])


## The line names the window's last day with its year, and says nothing for no day.
func _check_offer_line_forms() -> void:
	var grid = _main._calendar_panel._grid
	var kept: Dictionary = grid.armed
	var dates: Array = grid._armed_dates
	grid.armed = {"id": "x", "person": "X"}
	grid._armed_dates = [{"year": 2026, "month": 12, "day": 30, "free": true}, {"year": 2027, "month": 1, "day": 6, "free": false}]
	if grid.armed_line() != "Click a free day to see X: any free day until %s." % DateText.day_month_year(6, 1, 2027):
		_fail("the window's line reads '%s'" % grid.armed_line())
	grid._armed_dates = []
	if grid.armed_line() != "":
		_fail("a request with no day left names an end")
	grid._armed_dates = [{"year": 2026, "month": 3, "day": 5, "free": false}]
	if grid.armed_line() != "":
		_fail("a request with every day taken still promises a free day")
	grid.armed = kept
	grid._armed_dates = dates


func _finish() -> void:
	_check_offer_line_forms()
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
