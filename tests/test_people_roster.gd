extends SceneTree

## Headless test: godot --headless --script res://tests/test_people_roster.gd
## Non-zero exit on any failure.
##
## Rework 1, People and the cabinet (Gameplay's brief, the author's direction A "le
## tableau"): ONE roster sorted by who needs the president, a word before every figure,
## chips and a search box, the government as its first group with a vacant office
## marked, and the verbs on the focused row greyed with the sim's own reason.
##   - the order is the need rule: a request waiting, a word falling due, a grudge past
##     hostile, then standing; the president is never on their own roster;
##   - the government is one row per portfolio, held by a PARTY (the sim names no
##     minister), and a vacant office says what a vacancy does (it counts half);
##   - every chip lists its people; "Abroad" every other nation's leader; a search
##     finds a person across the groups;
##   - only the open group is built (rows for "Needs you" and the government, not the
##     whole register);
##   - See books the request's first free offered day through the diary's own path, and
##     the row then says when; a person with no request has See greyed with the reason;
##     a call already made this month greys Call with the phone's own words;
##   - a vacant office offers Fill, and Dismiss on it is greyed with Removal's reason;
##     Fill seats a party at once; a held office offers the OTHER parties and a Dismiss
##     that asks first, on the confirm card.
## GLM's test-gap pass on the first diff added the due word, the booked See, the search
## by party and the last three.
## Driven through the real controls a frame apart (AGENTS.md: a Control built but not
## shown fails silently).

const RosterRows = preload("res://src/ui/roster_rows.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const RosterVerbs = preload("res://src/ui/roster_verbs.gd")
const President = preload("res://src/sim/president.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _asker = null
var _request := ""
var _quiet = null


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			root.size = Vector2i(1920, 1080)
		2:
			_panel = _main._people_panel
			_seed()
			_check_order()
			_check_offices()
			_check_chips()
			_check_search()
			_main._windows.open("people")
			_panel.mark_dirty()
		4:
			_check_default_view()
			_click(_row("person", String(_asker.id)))
		6:
			_check_see_offered()
			# The chips are the filter: the quiet one is listed under theirs.
			_press(_chip("regions"))
		8:
			_click(_row("person", String(_quiet.id)))
		10:
			_check_see_greyed()
			_main._state.player().phone_calls[String(_quiet.id)] = _now()
			_panel.mark_dirty()
		12:
			_check_call_greyed()
			_panel._search.text = Labels.portfolio("defence")
			_panel._refresh()
			_check_office_found()
			_panel._search.text = ""
			_press(_chip("needs"))
		14:
			_click(_row("person", String(_asker.id)))
		16:
			_press(_verb("see"))
		18:
			_check_booked()
			Cabinet.vacate(_main._state, "health")
			_panel.mark_dirty()
		20:
			_click(_row("office", "health"))
		22:
			_check_vacant_verbs()
			_press(_verb("fill"))
		24:
			_check_filled()
			_click(_row("office", "education"))
		26:
			_check_held_verbs()
			_press(_verb("dismiss"))
		28:
			_check_dismiss_asks()
			_main.queue_free()
		30:
			_finish()
			return true
	return false


func _now() -> int:
	return int(_main._state.year) * 12 + int(_main._state.month)


## A union leader asks to see the president (the bench folds behind its chip, so only
## the need puts them on the default view); a regional figure with nothing asked is the
## quiet one.
func _seed() -> void:
	var ns = _main._state.player()
	for person in _main._loader.people[String(ns.id)]:
		if _asker == null and String(person.kind) == "union_leader":
			_asker = person
		if _quiet == null and String(person.kind) == "regional_figure":
			_quiet = person
	if _asker == null or _quiet == null:
		_fail("premise: no union leader or regional figure in the played nation")
		return
	_request = "%s|%d" % [_asker.id, _now()]
	ns.audience_requests.append({"id": _request, "person_id": String(_asker.id), "object": "programme:none",
		"stance": "sponsor", "arrived_month": _now(), "deadline_month": _now() + 2, "status": "pending", "date": {},
		"resolved_month": -1})


func _check_order() -> void:
	var ns = _main._state.player()
	var rows: Array = RosterRows.rows(_main._state, _main._loader, "needs", "")
	if rows.is_empty() or String(rows[0]["id"]) != String(_asker.id):
		_fail("the roster does not lead with the person asking to see you: %s" % str(rows.slice(0, 2)))
		return
	# #388 TAKE 1: the roster dates the request as the inbox card does (Audiences.answer_by),
	# never a month later (the deadline month itself, when the request has already lapsed).
	var card := AudienceDriver.row_of(_main, Audiences.request(_main._state.player(), _request))
	if not String(rows[0]["wants"]).contains(String(card["by"])):
		_fail("the roster's date is not the inbox card's '%s': '%s'" % [card["by"], rows[0]["wants"]])
	if String(rows[0]["wants"]).contains(_lapse_text()):
		_fail("the roster dates the request a month late (%s): '%s'" % [_lapse_text(), rows[0]["wants"]])
	var president := President.leader_id(ns)
	for chip in RosterRows.CHIPS:
		for row in RosterRows.rows(_main._state, _main._loader, String(chip[0]), ""):
			if String(row["id"]) == president:
				_fail("the president is on their own roster (chip %s)" % chip[0])
				return
	# A grudge past hostile ranks under a request and over standing.
	var everyone: Array = RosterRows.rows(_main._state, _main._loader, "politicians", "")
	if everyone.size() < 2:
		_fail("premise: fewer than two politicians")
		return
	var sore := String(everyone[everyone.size() - 1]["id"])
	ns.person_grudges[sore] = 0.95
	var again: Array = RosterRows.rows(_main._state, _main._loader, "politicians", "")
	if String(again[0]["id"]) != sore:
		_fail("a hostile grudge does not lift its person to the top of the group: %s" % again[0]["id"])
	if String(again[0]["feels_tone"]) == "" or String(again[0]["feels"]) == "":
		_fail("the hostile row carries no feeling word: %s" % str(again[0]))
	ns.person_grudges.erase(sore)
	# A word of the president's falling due ranks under a request and over a grudge.
	var owed := String(everyone[everyone.size() - 1]["id"])
	ns.commitments.append({"kind": "promise", "person_id": owed, "object": "meter:unemployment_pct",
		"made_month": _now(), "due_month": _now() + 1})
	var due: Array = RosterRows.rows(_main._state, _main._loader, "politicians", "")
	if String(due[0]["id"]) != owed or int(due[0]["rank"]) != RosterRows.Need.DUE or String(due[0]["owe"]) == "—":
		_fail("a word falling due does not lift its person, or the row does not say it: %s" % str(due[0]))
	ns.commitments.pop_back()


func _lapse_text() -> String:
	return preload("res://src/ui/lever_words.gd").when(_now() + 2)


func _check_offices() -> void:
	var ns = _main._state.player()
	var offices: Array = RosterRows.offices(_main._state, _main._loader)
	if offices.size() != CK.PORTFOLIO_KEYS.size():
		_fail("%d office rows for %d portfolios" % [offices.size(), CK.PORTFOLIO_KEYS.size()])
		return
	for row in offices:
		var held := String(ns.cabinet.get(String(row["portfolio"]), ""))
		if bool(row["vacant"]) != (held == ""):
			_fail("office %s reads vacant=%s with holder '%s'" % [row["portfolio"], row["vacant"], held])
		if String(row["party"]) == "" and held != "":
			_fail("office %s names no party" % row["portfolio"])
		if String(row["delivers"]) == "":
			_fail("office %s says nothing about what it delivers" % row["portfolio"])


## Every chip lists people; Abroad is every other nation's leader.
func _check_chips() -> void:
	for chip in RosterRows.CHIPS:
		var id := String(chip[0])
		var rows: Array = RosterRows.rows(_main._state, _main._loader, id, "")
		if rows.is_empty() and id != "needs":
			_fail("the chip '%s' lists nobody" % id)
		for row in rows:
			for key in ["name", "holds", "known"]:
				if String(row[key]) == "":
					_fail("chip %s: a row with no %s: %s" % [id, key, row["id"]])
					return
	var abroad: Array = RosterRows.rows(_main._state, _main._loader, "abroad", "")
	if abroad.size() != _main._state.nations.size() - 1:
		_fail("Abroad lists %d leaders for %d other nations" % [abroad.size(), _main._state.nations.size() - 1])


func _check_search() -> void:
	var name := String(_quiet.person_name)
	var last := name.get_slice(" ", name.get_slice_count(" ") - 1).to_lower()
	var found: Array = RosterRows.rows(_main._state, _main._loader, "needs", last)
	if found.is_empty() or not found.any(func(r): return String(r["id"]) == String(_quiet.id)):
		_fail("a search for '%s' does not find %s" % [last, name])
	# A party's name finds its people (the line's second line is searched too).
	var party := RosterRows._side(_main._state, _main._loader, _main._state.player(), _main._loader.person_by_id[String(_asker.id)])
	var by_party: Array = RosterRows.rows(_main._state, _main._loader, "", party)
	if party != "" and by_party.is_empty():
		_fail("a search for the side '%s' finds nobody" % party)


## The default view: the need group and the government; the bench is not built.
func _check_default_view() -> void:
	var text := _text()
	for heading in ["NEEDS YOU", "THE GOVERNMENT"]:
		if not text.to_upper().contains(heading):
			_fail("the default view has no '%s' group" % heading)
	if _row("person", String(_asker.id)) == null:
		_fail("the asker has no row on the default view")
	if _row("person", String(_quiet.id)) != null:
		_fail("the quiet regional figure is built on the default view: every row was built, not the open group")
	var offices := 0
	for node in _panel.find_children("*", "Control", true, false):
		if node.has_meta("office"):
			offices += 1
	if offices != CK.PORTFOLIO_KEYS.size():
		_fail("%d office rows drawn for %d portfolios" % [offices, CK.PORTFOLIO_KEYS.size()])


func _check_see_offered() -> void:
	var see: Button = _verb("see")
	if see == null:
		_fail("the asker's focused row offers no See")
		return
	if see.disabled:
		_fail("See is greyed for a person whose request waits: '%s'" % _why())
	var day: Dictionary = {}
	for date in Audiences.offered_dates(_main._state, _main._state.player(), _request):
		if bool(date.get("free", false)):
			day = date
			break
	if day.is_empty():
		_fail("premise: the request offers no free day")
		return
	if not see.text.contains(str(int(day["day"]))):
		_fail("See does not name the day it books: '%s'" % see.text)


func _check_see_greyed() -> void:
	var see: Button = _verb("see")
	if see == null or not see.disabled:
		_fail("See is not greyed for someone who has not asked")
		return
	if _why() == "":
		_fail("the greyed See carries no reason")


func _check_call_greyed() -> void:
	var call: Button = _verb("call")
	if call == null or not call.disabled:
		_fail("Call is not greyed after a call this month")
		return
	if not _why().to_lower().contains(Strings.t("you have spoken this month already").to_lower()):
		_fail("the greyed Call does not give the phone's reason: '%s'" % _why())


## #388 TAKE 2: the search box says "an office" -- typing one lists its row.
func _check_office_found() -> void:
	if _row("office", "defence") == null:
		_fail("a search for '%s' lists no office row" % _panel._search.text)
	if _row("office", "health") != null:
		_fail("a search for '%s' lists the health office too" % _panel._search.text)


func _check_booked() -> void:
	var request := Audiences.request(_main._state.player(), _request)
	if String(request.get("status", "")) != "booked":
		_fail("See did not book the request (status '%s')" % request.get("status", ""))
		return
	var row = _row("person", String(_asker.id))
	if row == null:
		_fail("the asker's row is gone after See")
		return
	var said := ""
	for label in row.find_children("*", "Label", true, false):
		said += (label as Label).text + " "
	if not said.contains("Sees you on"):
		_fail("the row does not say when the president sees them after See: '%s'" % said)
	var see: Button = _verb("see")
	if see == null or not see.disabled or not _why().contains(Strings.t("Already in your diary.")):
		_fail("See is not greyed as already booked after the booking: '%s'" % _why())


func _check_vacant_verbs() -> void:
	if _verb("fill") == null:
		_fail("a vacant office offers no Fill")
	var dismiss: Button = _verb("dismiss")
	if dismiss == null or not dismiss.disabled:
		_fail("Dismiss is not greyed on a vacant office")
		return
	if not _why().to_lower().contains(Strings.t("the portfolio is already vacant").to_lower()):
		_fail("the greyed Dismiss does not give Removal's reason: '%s'" % _why())
	var row = _row("office", "health")
	var said := ""
	for label in row.find_children("*", "Label", true, false):
		said += (label as Label).text + " "
	if not said.to_lower().contains("half"):
		_fail("the vacant office does not say it counts half: '%s'" % said)


func _check_filled() -> void:
	var held := String(_main._state.player().cabinet.get("health", ""))
	if held == "":
		_fail("Fill left the health office vacant")


## A held office: Give it to the OTHER government parties (never its holder), Dismiss live.
func _check_held_verbs() -> void:
	var holder := String(_main._state.player().cabinet.get("education", ""))
	for row in RosterRows.offices(_main._state, _main._loader):
		if String(row["portfolio"]) != "education":
			continue
		for item in RosterVerbs.for_office(_main._state, _main._loader, row, _panel._verbs):
			if String(item["id"]) == "reassign" and String(item["text"]).contains(String(row["party"])):
				_fail("Give it to offers the office to its own holder (%s)" % holder)
	var dismiss: Button = _verb("dismiss")
	if dismiss == null or dismiss.disabled:
		_fail("Dismiss is not live on a held office: '%s'" % _why())


## A removal asks first, on the confirm card with its price; nothing is removed yet.
func _check_dismiss_asks() -> void:
	if String(_main._state.player().cabinet.get("education", "")) == "":
		_fail("Dismiss removed the holder without asking")
	var card = _panel._verbs._confirm
	if card == null or not card.is_visible_in_tree():
		_fail("Dismiss did not raise the confirm card")


# --- helpers -------------------------------------------------------------------------

const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")


func _row(kind: String, id: String):
	for node in _panel.find_children("*", "Control", true, false):
		if node.has_meta(kind) and String(node.get_meta(kind)) == id and node.is_visible_in_tree():
			return node
	return null


func _verb(id: String):
	for node in _panel.find_children("*", "Button", true, false):
		if node.has_meta("verb") and String(node.get_meta("verb")) == id and node.is_visible_in_tree():
			return node
	return null


func _chip(id: String):
	for node in _panel.find_children("*", "Button", true, false):
		if node.has_meta("chip") and String(node.get_meta("chip")) == id:
			return node
	return null


## The reason line beside the focused row's verbs.
func _why() -> String:
	var node = _panel.find_child("VerbWhy", true, false)
	return (node as Label).text if node != null and node.is_visible_in_tree() else ""


func _text() -> String:
	var out := ""
	for node in _panel.find_children("*", "Label", true, false):
		if node.is_visible_in_tree():
			out += (node as Label).text + "\n"
	return out


func _click(node) -> void:
	if node == null:
		_fail("nothing to click at frame %d" % _frame)
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(node as Control).gui_input.emit(click)


func _press(button) -> void:
	if button == null:
		_fail("no button to press at frame %d" % _frame)
		return
	(button as Button).pressed.emit()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: test_people_roster")
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
	quit(0 if _failures.is_empty() else 1)
