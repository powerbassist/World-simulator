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
##   - slice 2: Politics retires. Government is one page (People); the majority lives in
##     Parliament's "Majority" tab beside Bills, Dissolve only there; the briefing's
##     majority Go, the strip's assembly figure and the Agenda's office entries open
##     Majority, whose partner lines lead to their offices in People; an office word's Go
##     lands on the office rows;
##   - the cabinet's readings moved with it: a party short of its share says so;
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
			_check_executive_asks()
			_check_offices()
			_check_vacant_since()
			_check_chips()
			_check_search()
			_check_politics_retired()
			_check_shorted_share()
			_main._windows.open("people")
			_panel.mark_dirty()
		4:
			_check_default_view()
			_click(_row("person", String(_asker.id)))
		6:
			_check_see_offered()
			_check_see_day_at_press()
			_check_second_click_keeps_focus()
			_hover_focused_line()
		9:
			_check_card_plate_and_place()
			# The chips are the filter: the quiet one is listed under theirs.
			_press(_chip("regions"))
		10:
			_click(_row("person", String(_quiet.id)))
		12:
			_check_see_greyed()
			_main._state.player().phone_calls[String(_quiet.id)] = _now()
			_panel.mark_dirty()
		14:
			_check_call_greyed()
			_panel._search.text = Labels.portfolio("defence")
			_panel._refresh()
			_check_office_found()
			_panel._search.text = ""
			_press(_chip("needs"))
		16:
			_click(_row("person", String(_asker.id)))
		18:
			_press(_verb("see"))
		20:
			_check_booked()
			Cabinet.vacate(_main._state, "health")
			_panel.mark_dirty()
		22:
			_click(_row("office", "health"))
		24:
			_check_vacant_verbs()
			_press(_verb("fill"))
		26:
			_check_filled()
			_click(_row("office", "education"))
		28:
			_check_held_verbs()
			_press(_verb("dismiss"))
		30:
			_check_dismiss_asks()
			_panel._verbs._confirm.hide()
			# A refusal printed for this office (QA's RECORD on #388) ...
			_panel._verbs._refused("this portfolio changed hands too recently to change again")
			_click(_row("office", "defence"))
		32:
			# ... is not said about the next line focused.
			if _panel._verbs.status_text() != "":
				_fail("a refusal said about one office stays up after another line is focused: '%s'" % _panel._verbs.status_text())
			_press(_chip("press"))
		34:
			# An office word's Go from a group that lists no office: focus("seats") brings them
			# back (its own frame: the partner's line below must not mask it, #389 pass 2 T5).
			_panel._verbs._refused("this portfolio changed hands too recently to change again")
			_panel.focus("seats")
		36:
			if _row("office", "health") == null:
				_fail("focus('seats') did not bring the office rows back from the press group")
			var owner = _panel.get_viewport().gui_get_focus_owner()
			if owner == null or not owner.has_meta("line") or not owner.get_parent().has_meta("office"):
				_fail("an office word's Go leaves the keyboard off the office rows: %s" % owner)
			# T3: a Go is a new pick, so a refusal said about another line goes.
			if _panel._verbs.status_text() != "":
				_fail("focus('seats') keeps a refusal said about another line: '%s'" % _panel._verbs.status_text())
			# T2: the line the keyboard lands on is scrolled into view.
			if not (_panel._body.get_parent() as ScrollContainer).follow_focus:
				_fail("the roster's scroll does not follow the keyboard: a landed line can sit below view")
			_press_partner_link()
		38:
			_check_partner_link_landed()
			_focus_a_partner_and_refresh()
		40:
			_check_partner_focus_survived()
			_check_partner_without_office()
			_main.queue_free()
		42:
			_finish()
			return true
	return false


func _now() -> int:
	return int(_main._state.year) * 12 + int(_main._state.month)


## Pass 2 on #388, TAKE 3: a firm's chief who asks to see the president counts in the
## title bar's requests, so he is on "Needs you" too (executives are not a chip of their
## own: firm chiefs stay in Sectors otherwise).
func _check_executive_asks() -> void:
	var ns = _main._state.player()
	var chief = null
	for person in _main._loader.people[String(ns.id)]:
		if String(person.kind) == "executive":
			chief = person
			break
	if chief == null:
		_fail("premise: no executive in the played nation")
		return
	var id := "%s|%d" % [chief.id, _now()]
	ns.audience_requests.append({"id": id, "person_id": String(chief.id), "object": "programme:none",
		"stance": "sponsor", "arrived_month": _now(), "deadline_month": _now() + 2, "status": "pending", "date": {},
		"resolved_month": -1})
	var listed := RosterRows.rows(_main._state, _main._loader, "needs", "").any(func(r): return String(r["id"]) == String(chief.id))
	ns.audience_requests.pop_back()
	if not listed:
		_fail("a firm chief asking to see you is not on Needs you")


## Pass 2, TAKE 1: a vacancy dates from the event that made it, here a resignation
## (ns.last_resignation), not an older dismissal stamp left on the portfolio.
func _check_vacant_since() -> void:
	var ns = _main._state.player()
	var f := "pensions"
	var held := String(ns.cabinet.get(f, ""))
	var stamp = ns.portfolio_removed_month.get(f)
	var resigned: Dictionary = ns.last_resignation
	ns.cabinet[f] = ""
	ns.portfolio_removed_month[f] = _now() - 20
	ns.last_resignation = {"portfolio": f, "party_id": held, "year": int(_main._state.year), "month": int(_main._state.month)}
	var said := ""
	for row in RosterRows.offices(_main._state, _main._loader):
		if String(row["portfolio"]) == f:
			said = String(row["party"])
	ns.cabinet[f] = held
	ns.last_resignation = resigned
	if stamp == null:
		ns.portfolio_removed_month.erase(f)
	else:
		ns.portfolio_removed_month[f] = stamp
	var want := Strings.t("Vacant since %s") % preload("res://src/ui/lever_words.gd").when(_now())
	if said != want:
		_fail("a vacancy left by a resignation reads '%s', not '%s'" % [said, want])


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
	# never a month later (the month after its deadline, when the request has already lapsed).
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
	return preload("res://src/ui/lever_words.gd").when(_now() + 3)  # deadline now+2 lapses at now+3 (#431)


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
	# Pass 2, TAKE 2: nothing on a line but its press target takes the pointer (the face's
	# portrait ate the clicks and hid the card).
	var line = _row("person", String(_asker.id))
	if line != null:
		for node in line.find_children("*", "Control", true, false):
			if node != line.get_child(0) and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				_fail("a line's %s (%s) takes the pointer from its press target" % [node.name, node.get_class()])
				break
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


## Pass 2, TAKE 5: the day See books is read at the press, not when the line was built:
## a day taken since (here by another appointment) is passed over, never refused.
func _check_see_day_at_press() -> void:
	var state = _main._state
	var row: Dictionary = {}
	for r in RosterRows.rows(state, _main._loader, "needs", ""):
		if String(r["id"]) == String(_asker.id):
			row = r
	var booked: Array = []
	var items: Array = RosterVerbs.for_person(state, _main._loader, row, func(id, date): booked.append(date), func(_pid): pass)
	var first: Dictionary = {}
	for date in Audiences.offered_dates(state, state.player(), _request):
		if bool(date.get("free", false)):
			first = date
			break
	if first.is_empty():
		_fail("premise: no free offered day")
		return
	state.appointments.append({"kind": "address", "status": "booked", "year": int(first["year"]), "month": int(first["month"]),
		"day": int(first["day"]), "travel_days": 0})
	(items[0]["call"] as Callable).call()
	state.appointments.pop_back()
	if booked.size() != 1 or (int(booked[0]["day"]) == int(first["day"]) and int(booked[0]["month"]) == int(first["month"])):
		_fail("See booked the day it was built with, though that day was taken since: %s" % str(booked))


## Pass 2, TAKE 4: clicking the focused line again keeps it focused (a toggle button would
## un-press it with no rebuild to restore it).
func _check_second_click_keeps_focus() -> void:
	var line = _row("person", String(_asker.id))
	var press: Button = line.get_child(0) if line != null else null
	if press == null or not press.button_pressed:
		_fail("premise: the asker's line is not the focused one")
		return
	press.button_pressed = false  # what a second click on a toggle does
	if not press.button_pressed:
		_fail("a second click un-presses the focused line")


## QA's H1 on #388 (real-window play): the hover card had no plate and a foreign face
## (it rode a bare CanvasLayer, outside the theme) and sat on the focused line's verbs.
## The roster now shows the ONE person card (the glossary layer's), above the line.
func _hover_focused_line() -> void:
	var line = _row("person", String(_asker.id))
	if line == null:
		_fail("premise: no asker line to hover")
		return
	(line.get_child(0) as Button).mouse_entered.emit()


func _check_card_plate_and_place() -> void:
	var layer = _main.get_tree().get_first_node_in_group(preload("res://src/ui/term_text.gd").GROUP)
	if layer == null or not layer.person_card_visible():
		_fail("hovering a roster line does not open the shared person card")
		return
	var card: Control = layer._people._card
	var plate = card.get_theme_stylebox("panel")
	if not (plate is StyleBoxFlat) or (plate as StyleBoxFlat).bg_color.a < 0.8:
		_fail("the person card has no near-opaque plate: %s" % plate)
	var face = card.get_theme_font("font", "Label")
	if face != _panel.get_theme_font("font", "Label"):
		_fail("the person card draws in another face than the panel's")
	var strip = _panel.find_child("VerbWhy", true, false)
	if strip != null and card.get_global_rect().intersects((strip.get_parent() as Control).get_global_rect()):
		_fail("the person card covers the focused line's verbs: card %s, strip %s" % [card.get_global_rect(), (strip.get_parent() as Control).get_global_rect()])
	if card.get_global_rect().intersects(_row("person", String(_asker.id)).get_global_rect()):
		_fail("the person card covers the line it is about")
	# QA's H2 on #388: the card goes when the pointer leaves the line, and when the list
	# scrolls under it (pass 1's "hover card outliving its line").
	(_row("person", String(_asker.id)).get_child(0) as Button).mouse_exited.emit()
	if layer.person_card_visible():
		_fail("the person card stays up after the pointer left the line")
	(_row("person", String(_asker.id)).get_child(0) as Button).mouse_entered.emit()
	var scroll := _panel._body.get_parent() as ScrollContainer
	scroll.get_v_scroll_bar().value_changed.emit(1.0)
	if layer.person_card_visible():
		_fail("the person card stays up after the list scrolled")


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
	# Pass 2, TAKE 6: a count picks its form (one office, not "1 offices").
	if not _text().to_upper().contains((Strings.tn("The government: %d office", "The government: %d offices", 1) % 1).to_upper() + "
"):
		_fail("one office found is not counted as one office: %s" % _text().left(200))
	if _text().contains(Strings.t("Nobody of that name, party or office.")):
		_fail("a search that found an office still says nobody matches")


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


func _check_politics_retired() -> void:
	var Domains = load("res://src/ui/domains.gd")
	var ids: Array = _main._windows.panel_ids()
	if ids.has("politics"):
		_fail("the Politics tab is still registered")
	if Domains.tabs("government", ids) != ["people"]:
		_fail("Government is not one page: %s" % str(Domains.tabs("government", ids)))
	if Domains.domain_of("majority") != "parliament" or not Domains.tabs("parliament", ids).has("majority"):
		_fail("the Majority tab is not in Parliament")
	if _main._windows.frame("majority") == null or _main._windows.frame("majority")._content != _main._government_panel:
		_fail("the Majority tab is not the majority's panel")
	if _main._law_panel.find_child("Dissolve", true, false) != null:
		_fail("Bills still carries a Dissolve: its one home is the Majority tab")
	if _main._government_panel.find_child("Dissolve", true, false) == null:
		_fail("the Majority tab has no Dissolve")
	if _main._government_panel.find_child("CabinetVerbs", true, false) != null:
		_fail("the Majority tab still carries the cabinet's verbs")
	var PKs = load("res://src/ui/priorities_constants.gd")
	for tab in PKs.GO_TAB.values():
		if String(tab) == "politics":
			_fail("a briefing Go still lands on Politics: %s" % str(PKs.GO_TAB))
	# One problem, one home (the parent's ruling on #389): the briefing's majority Go and the
	# strip's troubled assembly figure open the same tab, Majority.
	if String(PKs.GO_TAB.get("majority", "")) != "majority":
		_fail("the majority's Go does not open the Majority tab: %s" % PKs.GO_TAB.get("majority", ""))
	var office_go: Dictionary = load("res://src/ui/briefing_driver.gd").target_of(
		{"kind": "commitment", "subject": "promise|x|office:portfolio:health", "go": {"tab": ""}})
	if String(office_go["tab"]) != "people" or String(office_go["acts_on"]) != "seats":
		_fail("a word on an office lands on %s, not the office rows" % str(office_go))
	if String(load("res://src/ui/term_reads.gd").GROUP_TAB.get("office", "")) != "majority":
		_fail("the programme's office entries do not open the Majority tab")
	# The strip's assembly figure, in trouble, opens the arithmetic: the Majority tab.
	var ns = _main._state.player()
	var was: bool = ns.is_minority
	ns.is_minority = true
	var reading: Dictionary = load("res://src/ui/strip_readings.gd")._assembly(ns)
	ns.is_minority = was
	if String(reading["alert_window"]) != String(PKs.GO_TAB.get("majority", "")):
		_fail("the troubled assembly figure opens '%s', the briefing's majority Go '%s'" % [reading["alert_window"], PKs.GO_TAB.get("majority", "")])


## Politics' cabinet table said a party held under its d'Hondt share (docs/cabinet-model.md:
## the condition a resignation needs); the office rows say it now.
func _check_shorted_share() -> void:
	var ns = _main._state.player()
	var target := ""
	for pid in ns.coalition_party_ids:
		if int(ns.cabinet_entitlement.get(pid, 0)) > 0:
			target = String(pid)
			break
	var taken := ""
	for f in CK.PORTFOLIO_KEYS:
		if String(ns.cabinet.get(f, "")) == target:
			taken = f
			break
	if target == "" or taken == "":
		_fail("premise: no entitled coalition party holding an office")
		return
	var other := ""
	for f in CK.PORTFOLIO_KEYS:
		if f != taken and String(ns.cabinet.get(f, "")) == target:
			other = f
	var entitled := int(ns.cabinet_entitlement[target])
	ns.cabinet[taken] = ""
	var held := entitled - 1
	var said := ""
	for row in RosterRows.offices(_main._state, _main._loader):
		if String(row["party_id"]) == target:
			said = String(row["owe"])
	ns.cabinet[taken] = target
	if other == "":
		return  # its only office was the one taken: no row is left to say it
	if said != Strings.t("Holds %d of its %d offices") % [held, entitled]:
		_fail("a party held under its share does not say so: '%s'" % said)


## On the Majority tab, a partner's line leads to its offices in People (the verb lives there).
var _partner := ""


func _press_partner_link() -> void:
	var majority = _main._government_panel
	_main._windows.open("majority")
	majority._refresh()
	for button in majority.find_children("*", "Button", true, false):
		if button.has_meta("party") and not (button as Button).disabled:
			_partner = String(button.get_meta("party"))
			(button as Button).pressed.emit()
			return
	_fail("no partner line on the Majority tab leads to its offices")


func _check_partner_link_landed() -> void:
	if _partner == "":
		return
	if not _main._windows.is_open("people"):
		_fail("a partner's line did not open People")
	var picked: Array = _panel._picked
	var ns = _main._state.player()
	if picked.size() != 2 or String(picked[0]) != "office" or String(ns.cabinet.get(String(picked[1]), "")) != _partner:
		_fail("a partner's line did not focus one of its offices: %s (party %s)" % [picked, _partner])


## #389 pass 2 T4: the Majority tab rebuilds its partner lines on every refresh; the
## keyboard on one stays on it.
var _focused_party := ""


func _focus_a_partner_and_refresh() -> void:
	var majority = _main._government_panel
	_main._windows.open("majority")
	majority._refresh()
	for button in majority.find_children("*", "Button", true, false):
		if button.has_meta("party") and not (button as Button).disabled:
			_focused_party = String(button.get_meta("party"))
			(button as Button).grab_focus()
			break
	if _focused_party == "":
		_fail("premise: no partner line to focus")
		return
	majority.mark_dirty()
	majority._refresh()


## A frame on, the old lines are freed: the keyboard must be on the new one.
func _check_partner_focus_survived() -> void:
	if _focused_party == "":
		return
	var owner = _main._government_panel.get_viewport().gui_get_focus_owner()
	if owner == null or not owner.has_meta("party") or String(owner.get_meta("party")) != _focused_party:
		_fail("a Majority refresh drops the keyboard off the partner line it was on: %s" % owner)


## #389 pass 2 T1: a partner holding no office says so and leads to no other party's office.
func _check_partner_without_office() -> void:
	var ns = _main._state.player()
	var majority = _main._government_panel
	var empty := ""
	var keeper := ""
	for pid in ns.coalition_party_ids:
		if String(pid) != String(ns.pm_party_id):
			empty = String(pid)
		else:
			keeper = String(pid)
	if empty == "" or keeper == "":
		_fail("premise: no second government party")
		return
	var cabinet: Dictionary = ns.cabinet.duplicate()
	for f in ns.cabinet.keys():
		if String(ns.cabinet[f]) == empty:
			ns.cabinet[f] = keeper
	majority._refresh()
	var line: Button = null
	for button in majority.find_children("*", "Button", true, false):
		if button.has_meta("party") and String(button.get_meta("party")) == empty:
			line = button
	if line == null or not line.disabled or line.tooltip_text == "":
		_fail("a partner holding no office is not a greyed line that says why: %s" % line)
	_panel._picked = []
	_panel.show_offices(empty)
	if _panel.focused == "seats" or not _panel._picked.is_empty():
		_fail("People lands on another party's office for a partner holding none: %s" % [_panel._picked])
	ns.cabinet = cabinet
	majority._refresh()


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
