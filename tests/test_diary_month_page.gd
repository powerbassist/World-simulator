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
			_stage()
			AudienceDriver.refresh(_main)
			_main._windows.open("calendar")
		5:
			_check_toggle_and_elsewhere()
			_check_cards()
			_check_summons()
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
	(card.find_child("Decline_%s" % _request, true, false) as Button).pressed.emit()
	if String(Audiences.request(_main._state.player(), _request).get("status", "")) != AK.STATUS_DECLINED:
		_fail("Decline on the card did not decline (%s)" % Audiences.request(_main._state.player(), _request).get("status", ""))


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
