extends SceneTree

## Headless test: godot --headless --script res://tests/test_diary_month_page.gd
## Non-zero exit on any failure.
##
## The month page (picture A, the author's pick, 2026-11-20): beside the grid, one card per
## waiting request with every verb priced on its line, then the president's own reach.
##   - a card per waiting request, its See them, Call, Delegate and Decline each with words
##     beside it; Decline on the card declines the request;
##   - the summons (#432's sim, which no screen reached): a person of his nation picked, See
##     them arms the grid, a click on a free day summons them for that day;
##   - the summons booked is listed with Cancel; the cap then refuses a second this month, and
##     says why beside the picker;
##   - Cancel calls it off and gives the cap back (R-432-cancel);
##   - See them pressed again lets the request go; a request answered elsewhere disarms the
##     grid; Enter on the focused free day books, as a click does; the picked person survives
##     a refresh (the GLM test-gap list on this diff, 2026-11-21).

const Audiences = preload("res://src/sim/audiences.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const DiaryDay = preload("res://src/ui/diary_day.gd")
const Calendar = preload("res://src/sim/calendar.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _request := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._clock.paused = true
			_check_a_new_game_has_its_reach()
			_stage()
			AudienceDriver.refresh(_main)
			_main._windows.open("calendar")
		5:
			_check_days_left()
			_check_waiting_not_in_reach()
			_check_delegate_seen()
			_check_see_route()
			_check_toggle_and_elsewhere()
			_check_cards()
			_check_summons()
			_check_refused_summons()
			_check_armed_summons_lets_go()
			_check_nothing_armed_books_nothing()
			if not _guard_ran:
				_fail("a tinted day clicked with nobody armed raised a script error")
			_check_summons_day_passed_under_hand()
			_go_for_settle()
		8:
			_scroll_then_refocus()
		11:
			_check_refocus_keeps_scroll()
			_turn_the_month()
		14:
			_check_tokens_count_from_the_first()
			_finish()
			return true
	return false


func _stage() -> void:
	var state = _main._state
	var ns = state.player()
	for person in _main._loader.people[String(ns.id)].slice(4):
		var r := Audiences.invite(state, ns, _main._loader, String(person.id), "office:premiership", "wants")
		if bool(r.get("ok", false)):
			_request = String(r["request"]["id"])
			return
	_fail("premise: no request could be staged")


## Pass 2 TAKE 8 (the #427 ruling): a MOUSE click on See them must not hand Space to a day --
## no day takes the focus; from the keyboard, the picked day does, where Enter books it.
func _check_see_route() -> void:
	var people = _people()
	var see := people.find_child("See_%s" % _request, true, false) as Button
	if see == null:
		_fail("premise: the card has no See them")
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	people._input(click)
	see.pressed.emit()
	if _main.get_viewport().gui_get_focus_owner() is DiaryDay:
		_fail("a mouse click on See them left a day focused: Space would book it")
	(_people().find_child("See_%s" % _request, true, false) as Button).pressed.emit()
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	people._input(key)
	(_people().find_child("See_%s" % _request, true, false) as Button).pressed.emit()
	if not (_main.get_viewport().gui_get_focus_owner() is DiaryDay):
		_fail("See them from the keyboard left no day focused")
	(_people().find_child("See_%s" % _request, true, false) as Button).pressed.emit()
	var summons := people.find_child("SummonSee", true, false) as Button
	var can: Array = people._people.filter(func(p: Dictionary) -> bool: return String(p["why"]) == "")
	if summons == null or can.is_empty():
		_fail("premise: no summons See them")
		return
	people.pick_person(String(can[0]["person_id"]))
	people._input(click)
	summons.pressed.emit()
	if _main.get_viewport().gui_get_focus_owner() is DiaryDay:
		_fail("a mouse click on a summons' See them left a day focused")
	people._input(key)
	(people.find_child("SummonSee", true, false) as Button).pressed.emit()
	if not (_main.get_viewport().gui_get_focus_owner() is DiaryDay):
		_fail("a summons' See them from the keyboard left no day focused")
	_main._calendar_panel._grid.arm({})
	_main.get_viewport().gui_release_focus()
	# The inbox card's Go by the mouse: the same rule (pass 1 on the pass-2 delta).
	people._input(click)
	AudienceDriver.lane_of(_main).book_requested.emit(_request)
	if _main.get_viewport().gui_get_focus_owner() is DiaryDay:
		_fail("a mouse click on the inbox's Go left a day focused")
	_main._calendar_panel._grid.arm({})
	_main.get_viewport().gui_release_focus()


## See them toggles; a request answered off the page disarms the grid at its next render.
func _check_toggle_and_elsewhere() -> void:
	var grid = _main._calendar_panel._grid
	var see := _people().find_child("See_%s" % _request, true, false) as Button
	if see == null:
		_fail("premise: the card has no See them")
		return
	see.pressed.emit()
	if String(grid.armed.get("id", "")) != _request:
		_fail("See them did not arm the request")
	see = _people().find_child("See_%s" % _request, true, false) as Button
	if see == null or not see.button_pressed:
		_fail("the armed request's See them is not shown pressed")
		return
	see.pressed.emit()
	if not grid.armed.is_empty():
		_fail("See them pressed again did not let the request go")
	(_people().find_child("See_%s" % _request, true, false) as Button).pressed.emit()
	var ns = _main._state.player()
	var kept: Dictionary = Audiences.request(ns, _request).duplicate(true)
	for row in ns.audience_requests:
		if String(row["id"]) == _request:
			row["status"] = AK.STATUS_DELEGATED
	grid._render()
	if not grid.armed.is_empty():
		_fail("a request answered elsewhere left the grid armed")
	for row in ns.audience_requests:
		if String(row["id"]) == _request:
			row["status"] = String(kept["status"])
	AudienceDriver.refresh(_main)


func _people():
	return _main._calendar_panel.people


func _check_cards() -> void:
	var people = _people()
	var card := people.find_child("Card_%s" % _request, true, false) as Control
	if card == null or not card.is_visible_in_tree():
		_fail("the waiting request has no card beside the grid")
		return
	for verb in ["See", "Call", "Delegate", "Decline"]:
		var b := card.find_child("%s_%s" % [verb, _request], true, false) as Button
		if b == null:
			_fail("the card has no %s" % verb)
			continue
		# The price under the verb's own row (Design's read: "the prices are not beside the verbs").
		var note := card.find_child("Note_%s_%s" % [verb, _request], true, false) as Label
		if note == null or note.text.strip_edges() == "":
			_fail("%s carries no words under it" % verb)
		# The matrix row: four cells beside the verb (a day, rapport, odds, learn).
		if b.get_parent().get_parent().get_child_count() != 5:
			_fail("%s's matrix row has %d cells, not 5" % [verb, b.get_parent().get_parent().get_child_count()])
	# Pass 1 on #434: nothing inside a token stops the mouse, so a press on the face presses it.
	var token := people.find_child("Token_%s" % _request, true, false) as Control
	if token == null:
		_fail("the waiting request has no token")
	for node in (token.find_children("*", "Control", true, false) if token != null else []):
		if (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_fail("%s inside the token stops the mouse: a press on it is a dead click" % node.name)
			break
	# One width for the four answers (the author, 2026-11-21: buttons sized by their text "incongru").
	var widths := {}
	for verb in ["See", "Call", "Delegate", "Decline"]:
		var b := card.find_child("%s_%s" % [verb, _request], true, false) as Button
		if b != null:
			widths[roundi(b.get_combined_minimum_size().x)] = true
	if widths.size() != 1:
		_fail("the file's four answers are not one width: %s" % [widths.keys()])
	var pair := [people.find_child("SummonSee", true, false) as Button, people.find_child("SummonCall", true, false) as Button]
	if roundi(pair[0].get_combined_minimum_size().x) != roundi(pair[1].get_combined_minimum_size().x):
		_fail("the summons' See them and Call are not one width")
	# Pass 2 TAKE 3: the column's verbs are a request seen, as the inbox card's are -- the speed
	# the request's arrival took comes back. See them pressed twice (armed, let go), then Decline.
	_slowed()
	(card.find_child("See_%s" % _request, true, false) as Button).pressed.emit()
	(_people().find_child("See_%s" % _request, true, false) as Button).pressed.emit()
	if _main._clock.speed != 3:
		_fail("See them let go on the column left the clock slowed (speed %d)" % _main._clock.speed)
	_slowed()
	card = people.find_child("Card_%s" % _request, true, false) as Control
	(card.find_child("Decline_%s" % _request, true, false) as Button).pressed.emit()
	if String(Audiences.request(_main._state.player(), _request).get("status", "")) != AK.STATUS_DECLINED:
		_fail("Decline on the card did not decline (%s)" % Audiences.request(_main._state.player(), _request).get("status", ""))
	if _main._clock.speed != 3:
		_fail("Decline on the column left the clock slowed (speed %d)" % _main._clock.speed)


## The request's arrival slowed the clock from 3 (audience_driver._slow_for).
func _slowed(id := "") -> void:
	var game: Dictionary = AudienceDriver._games[_main.get_instance_id()]
	game["slowed_for"] = {(id if id != "" else _request): true}
	game["resume_speed"] = 3
	_main._clock.set_speed(1)


func _check_summons() -> void:
	var state = _main._state
	var ns = state.player()
	var people = _people()
	var grid = _main._calendar_panel._grid
	var can: Array = people._people.filter(func(p: Dictionary) -> bool: return String(p["why"]) == "")
	if can.size() < 2:
		_fail("premise: fewer than two people can be summoned (%d)" % can.size())
		return
	var pid := String(can[0]["person_id"])
	people.pick_person(pid)
	var see := people.find_child("SummonSee", true, false) as Button
	if see == null or see.disabled:
		_fail("See them is missing or refused for a person who can be summoned")
		return
	# QA on #434: the cap's caption reads free before the month's summons, used after.
	if people._cap.text != tr("Summons this month: ● free"):
		_fail("before any summons the cap reads '%s', not free" % people._cap.text)
	see.pressed.emit()
	if not bool(grid.armed.get("summons", false)) or String(grid.armed.get("person_id", "")) != pid:
		_fail("See them did not arm the grid for the summons (%s)" % grid.armed)
		return
	var first: Dictionary = {}
	for d in Audiences.summon_days(state, pid):
		if bool(d["free"]):
			first = d
			break
	grid.show_month(int(first["year"]), int(first["month"]))
	var cell = grid._days.get_node_or_null("Day_%d" % int(first["day"]))
	if cell == null or not bool(cell.tinted):
		_fail("the summons' first free day is not tinted")
	# The keyboard's path: Enter on the focused free day books it, as a click does.
	cell.grab_focus()
	var enter := InputEventAction.new()
	enter.action = "ui_accept"
	enter.pressed = true
	cell._gui_input(enter)
	var row := {}
	for r in ns.audience_requests:
		if AK.is_summons(r) and String(r["person_id"]) == pid:
			row = r
	if row.is_empty() or String(row["status"]) != AK.STATUS_BOOKED or int(row["date"]["day"]) != int(first["day"]):
		_fail("the click did not summon them for that day: %s" % [row])
		return
	if not grid.armed.is_empty():
		_fail("the grid stayed armed after the summons")
	AudienceDriver.refresh(_main)
	if people._cap.text != tr("Summons this month: ○ used"):
		_fail("after the month's summons the cap reads '%s', not used" % people._cap.text)
	# The cap: a second person this month is refused, and the reason is said beside the picker.
	people.pick_person(String(can[1]["person_id"]))
	if not see.disabled or not people._why.visible or people._why.text == "":
		_fail("a second summons this month is not refused with its reason")
	AudienceDriver.refresh(_main)
	if people._picked() != String(can[1]["person_id"]):
		_fail("a refresh dropped the person picked for a summons")
	var cancel := people.find_child("CancelSummons", true, false) as Button
	if cancel == null:
		_fail("the summons booked is not listed with Cancel")
		return
	cancel.pressed.emit()
	if ns.audience_summoned_month.has(pid):
		_fail("Cancel did not give the summons' stamp back")
	people.pick_person(String(can[1]["person_id"]))
	if see.disabled:
		_fail("after Cancel, the month's summons is still spent: %s" % people._why.text)


## Pass 2 TAKE 4: a summons refused at the click (here the person's months stamped between the
## See them and the click) leaves no day tinted, and a second click books nothing -- it once
## sent the grid's emptied target on as a booking.
func _check_refused_summons() -> void:
	var state = _main._state
	var ns = state.player()
	var people = _people()
	var grid = _main._calendar_panel._grid
	var can: Array = people._people.filter(func(p: Dictionary) -> bool: return String(p["why"]) == "")
	if can.is_empty():
		_fail("premise: nobody left to summon")
		return
	var pid := String(can[0]["person_id"])
	people.pick_person(pid)
	(people.find_child("SummonSee", true, false) as Button).pressed.emit()
	var first: Dictionary = {}
	for d in Audiences.summon_days(state, pid):
		if bool(d["free"]):
			first = d
			break
	if first.is_empty() or not bool(grid.armed.get("summons", false)):
		_fail("premise: the summons is not armed on a free day")
		return
	grid.show_month(int(first["year"]), int(first["month"]))
	ns.audience_summoned_month[pid] = int(state.year) * 12 + int(state.month)
	var before: int = ns.audience_requests.size()
	var enter := InputEventAction.new()
	enter.action = "ui_accept"
	enter.pressed = true
	grid._days.get_node("Day_%d" % int(first["day"]))._gui_input(enter)
	var cell = grid._days.get_node_or_null("Day_%d" % int(first["day"]))
	if cell == null or cell.is_queued_for_deletion() or bool(cell.tinted):
		cell = null
		for c in grid._days.get_children():
			if not c.is_queued_for_deletion() and c.name == "Day_%d" % int(first["day"]):
				cell = c
	if cell == null or bool(cell.tinted):
		_fail("a summons refused at the click left its day tinted")
		return
	cell._gui_input(enter)
	if ns.audience_requests.size() != before or not grid.armed.is_empty():
		_fail("a second click after a refused summons booked or armed something")
	ns.audience_summoned_month.erase(pid)


## Pass 2 TAKE 5: a summons armed and not clicked lets go when the Diary closes and on a load --
## it once summoned the person in the loaded game at the next click.
func _check_armed_summons_lets_go() -> void:
	AudienceDriver.refresh(_main)
	var people = _people()
	var grid = _main._calendar_panel._grid
	var can: Array = people._people.filter(func(p: Dictionary) -> bool: return String(p["why"]) == "")
	if can.is_empty():
		_fail("premise: nobody left to summon")
		return
	people.pick_person(String(can[0]["person_id"]))
	var see := people.find_child("SummonSee", true, false) as Button
	see.pressed.emit()
	_main._windows.close("calendar")
	if not grid.armed.is_empty():
		_fail("a summons armed stayed armed with the Diary closed")
	_main._windows.open("calendar")
	people.pick_person(String(can[0]["person_id"]))
	see.pressed.emit()
	AudienceDriver.after_load(_main)
	if not grid.armed.is_empty():
		_fail("a summons armed stayed armed across a load")


## Pass 2 TAKE 7: a Go settles the page once (scroll from the top to the day); the daily
## refocus while armed must not, or the page jumps back to the top each in-game day.
var _scroll: ScrollContainer
var _scrolled := -1


func _go_for_settle() -> void:
	_stage()
	AudienceDriver.refresh(_main)
	# A page longer than the view, as with a long day list or a full column: it really scrolls.
	var tall := Control.new()
	tall.custom_minimum_size.y = 2000
	_main._calendar_panel._grid.get_parent().add_child(tall)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	_people()._input(key)
	AudienceDriver.lane_of(_main).book_requested.emit(_request)


func _scroll_then_refocus() -> void:
	var node: Node = _main._calendar_panel._grid.get_parent()
	while node != null and not (node is ScrollContainer):
		node = node.get_parent()
	_scroll = node as ScrollContainer
	if _scroll == null:
		_fail("premise: the Diary's page is in no scroll")
		return
	# Down, the picked day still whole in view: nothing the keyboard needs is off screen.
	var grid = _main._calendar_panel._grid
	var day := grid._days.get_node_or_null("Day_%d" % grid._selected) as Control
	if day == null:
		_fail("premise: no picked day")
		return
	var top := day.get_global_rect().position.y - _scroll.get_global_rect().position.y + _scroll.scroll_vertical
	_scroll.scroll_vertical = int(top / 3.0)
	_scrolled = _scroll.scroll_vertical
	if _scrolled <= 0:
		_fail("premise: the Diary's page does not scroll (%d)" % _scrolled)
		return
	# The daily redraw freed the focused day: the refocus puts the keyboard back on it.
	_main.get_viewport().gui_release_focus()
	_main._calendar_panel.booking._refocus()


func _check_refocus_keeps_scroll() -> void:
	if _scroll == null or _scrolled <= 0:
		return
	if not (_main.get_viewport().gui_get_focus_owner() is DiaryDay):
		_fail("premise: the refocus put the keyboard on no day")
	if _scroll.scroll_vertical != _scrolled:
		_fail("the daily refocus moved the page from %d to %d" % [_scrolled, _scroll.scroll_vertical])


## QA on #434 (TAKE 11): the days left to answer count the last day -- "1 day" on it, never
## 0 -- and mid-window, today to the answer-by month's last day, both ends counted.
func _check_days_left() -> void:
	var state = _main._state
	var request := Audiences.request(state.player(), _request)
	var by := Audiences.answer_by(request)
	var by_y := floori((by - 1) / 12.0)
	var by_m := by - by_y * 12
	var last := Calendar.days_in_month(by_y, by_m)
	var end := Time.get_unix_time_from_datetime_dict({"year": by_y, "month": by_m, "day": last})
	var now := Time.get_unix_time_from_datetime_dict({"year": int(state.year), "month": int(state.month), "day": int(state.day)})
	var mid := int((end - now) / 86400) + 1
	var person := String(_main._loader.person_name(String(request["person_id"])))
	_tooltip_reads("%s: %d days left to answer" % [person, mid], "mid-window")
	var kept := [int(state.year), int(state.month), int(state.day)]
	state.year = by_y
	state.month = by_m
	state.day = last
	# G3 S2 pass 2 TAKE 11: the last day says so, as the token's caption does ("today").
	_tooltip_reads("%s: today is the last day to answer" % person, "on the last day")
	state.year = kept[0]
	state.month = kept[1]
	state.day = kept[2]
	AudienceDriver.refresh(_main)


func _tooltip_reads(want: String, when: String) -> void:
	AudienceDriver.refresh(_main)
	var token := _people().find_child("Token_%s" % _request, true, false) as Button
	if token == null or token.tooltip_text != want:
		_fail("%s the token reads '%s', not '%s'" % [when, token.tooltip_text if token != null else "no token", want])


## QA on #434: a person with a request waiting is answered on their card, never offered again
## under "Someone else".
func _check_waiting_not_in_reach() -> void:
	var pid := String(Audiences.request(_main._state.player(), _request)["person_id"])
	for p in _people()._people:
		if String(p["person_id"]) == pid:
			_fail("a person with a request waiting is offered under Someone else")


## QA on #434 (TAKE 3): Delegate on the column is the request seen -- the speed comes back.
func _check_delegate_seen() -> void:
	var state = _main._state
	var ns = state.player()
	var other := ""
	var asker := String(Audiences.request(ns, _request)["person_id"])
	for person in _main._loader.people[String(ns.id)].slice(4):
		if String(person.id) == asker:
			continue
		var r := Audiences.invite(state, ns, _main._loader, String(person.id), "office:premiership", "wants")
		if bool(r.get("ok", false)):
			other = String(r["request"]["id"])
			break
	if other == "":
		_fail("premise: no second request could be staged")
		return
	AudienceDriver.refresh(_main)
	_slowed(other)
	_people().delegate_requested.emit(other)
	if _main._clock.speed != 3:
		_fail("Delegate on the column left the clock slowed (speed %d)" % _main._clock.speed)


## QA on #434: a tinted day clicked with nobody armed (a load cleared it before the redraw)
## books nothing and raises nothing.
func _check_nothing_armed_books_nothing() -> void:
	AudienceDriver.refresh(_main)
	var people = _people()
	var grid = _main._calendar_panel._grid
	var ns = _main._state.player()
	var can: Array = people._people.filter(func(p: Dictionary) -> bool: return String(p["why"]) == "")
	if can.is_empty():
		_fail("premise: nobody left to summon")
		return
	people.pick_person(String(can[0]["person_id"]))
	(people.find_child("SummonSee", true, false) as Button).pressed.emit()
	var tinted: Control = null
	for c in grid._days.get_children():
		# The last one: not the day See them already picked.
		if c is DiaryDay and bool(c.tinted) and int(String(c.name).trim_prefix("Day_")) != grid._selected:
			tinted = c
	if tinted == null:
		_fail("premise: no tinted day")
		return
	grid.armed = {}
	var before: int = ns.audience_requests.size()
	_guard_ran = false
	_click(tinted)
	_guard_ran = true
	if ns.audience_requests.size() != before:
		_fail("a tinted day clicked with nobody armed booked something")
	# A plain pick then, as any day not booked by the click: its list opens under the grid.
	if grid._selected != int(String(tinted.name).trim_prefix("Day_")):
		_fail("a tinted day clicked with nobody armed was not picked (picked %d)" % grid._selected)


var _guard_ran := false


func _click(cell) -> void:
	var enter := InputEventAction.new()
	enter.action = "ui_accept"
	enter.pressed = true
	cell._gui_input(enter)


## QA on #434: the summons' day turned into today under the hand books the first free day, as
## a request's booking does (#431 pass 2 TAKE 1).
func _check_summons_day_passed_under_hand() -> void:
	AudienceDriver.refresh(_main)
	var state = _main._state
	var ns = state.player()
	var people = _people()
	var grid = _main._calendar_panel._grid
	var can: Array = people._people.filter(func(p: Dictionary) -> bool: return String(p["why"]) == "")
	if can.is_empty():
		_fail("premise: nobody left to summon")
		return
	var pid := String(can[0]["person_id"])
	people.pick_person(pid)
	(people.find_child("SummonSee", true, false) as Button).pressed.emit()
	var first: Dictionary = {}
	for d in Audiences.summon_days(state, pid):
		if bool(d["free"]):
			first = d
			break
	grid.show_month(int(first["year"]), int(first["month"]))
	var cell = grid._days.get_node_or_null("Day_%d" % int(first["day"]))
	if cell == null or not bool(cell.tinted):
		_fail("premise: the summons' first free day is not tinted")
		return
	var kept := [int(state.year), int(state.month), int(state.day)]
	state.year = int(first["year"])
	state.month = int(first["month"])
	state.day = int(first["day"])
	_click(cell)
	var row := {}
	for r in ns.audience_requests:
		if AK.is_summons(r) and String(r["person_id"]) == pid and String(r["status"]) == AK.STATUS_BOOKED:
			row = r
	if row.is_empty() or int(row["date"]["day"]) + int(row["date"]["month"]) * 100 <= int(first["day"]) + int(first["month"]) * 100:
		_fail("a summons day turned today under the hand did not book the first free day: %s" % [row])
	elif not bool(Audiences.decline(state, ns, _main._loader, String(row["id"])).get("ok", false)):
		_fail("premise: the summons could not be cancelled")
	state.year = kept[0]
	state.month = kept[1]
	state.day = kept[2]
	AudienceDriver.refresh(_main)


## QA play on #434: a new game's Diary has its "Someone else" before any month closes -- the
## picker filled, the cap's caption set (no refresh had run before the first month's end).
func _check_a_new_game_has_its_reach() -> void:
	var people = _people()
	if people._people.is_empty() or people._pick.item_count == 0 or people._cap.text == "":
		_fail("a new game's Diary has no one to summon and no cap caption before the first month ends")


## QA play on #434: at a month's close the clock's day is still the old month's last; the
## tokens must count from the 1st once it arrives, and count down day by day after.
var _turn_request := ""


func _turn_the_month() -> void:
	var state = _main._state
	_turn_request = _request
	state.day = 31
	state.month += 1
	AudienceDriver.after_month(_main, {})
	_main._clock.day_advanced.emit(int(state.year), int(state.month), 1)


func _check_tokens_count_from_the_first() -> void:
	var state = _main._state
	if int(state.day) != 1:
		_fail("premise: the clock's 1st did not land (day %d)" % int(state.day))
		return
	var request := Audiences.request(state.player(), _turn_request)
	if String(request.get("status", "")) != AK.STATUS_PENDING:
		_fail("premise: the request is no longer waiting (%s)" % request.get("status", ""))
		return
	var person := String(_main._loader.person_name(String(request["person_id"])))
	var token := _people().find_child("Token_%s" % _turn_request, true, false) as Button
	var want := "%s: %d days left to answer" % [person, _left(request)]
	if token == null or token.tooltip_text != want:
		_fail("after a month's close the token reads '%s', not '%s'" % [token.tooltip_text if token != null else "no token", want])
	# Days passed with the Diary shut: it opens counting from today.
	_main._windows.close("calendar")
	state.day = 9
	_main._windows.open("calendar")
	token = _people().find_child("Token_%s" % _turn_request, true, false) as Button
	want = "%s: %d days left to answer" % [person, _left(request)]
	if token == null or token.tooltip_text != want:
		_fail("the Diary opened days later reads '%s', not '%s'" % [token.tooltip_text if token != null else "no token", want])


## Days from today to the answer-by month's last day, both counted.
func _left(request: Dictionary) -> int:
	var state = _main._state
	var by := Audiences.answer_by(request)
	var by_y := floori((by - 1) / 12.0)
	var by_m := by - by_y * 12
	var end := Time.get_unix_time_from_datetime_dict({"year": by_y, "month": by_m, "day": Calendar.days_in_month(by_y, by_m)})
	var now := Time.get_unix_time_from_datetime_dict({"year": int(state.year), "month": int(state.month), "day": int(state.day)})
	return int((end - now) / 86400) + 1


func _finish() -> void:
	if _failures.is_empty():
		print("test_diary_month_page: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
