extends SceneTree

## Headless test: godot --headless --script res://tests/test_briefing_go.gd
## Non-zero exit on any failure.
##
## V5.3-0, band RF3 (docs/design/v5.3-0-readability.md 2.4): every briefing Go lands
## on a verb. For each kind: a fixture state where the line's subject is real (an
## event on the desk, a request on its card, a tabled bill, a live programme entry,
## a hostile person), the line built with the ranker's own constructor (the ranking
## itself is test_priorities.gd's), the card shown through the driver's view, and
## its Go pressed by a real click, press and release frames apart. Then: the target
## tab is open and an ENABLED, shown control carries the subject (acts_on.gd).
##
## The one named exception (the parent's call on RF3): a tabled bill has no verb
## until the Assembly divides, so its Go is checked to show the tabled line.
##
## The Go is also checked to close the card, and the chief of staff's face, name and
## line to fill the card from a person record of kind chief_of_staff (a fixture until
## Content's records are on main).

const Click = preload("res://tests/click.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const DeskCards = preload("res://src/ui/desk_cards.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Programme = preload("res://src/sim/programme.gd")
const Person = preload("res://src/core/person.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _cases: Array = []
var _case: Dictionary = {}
var _step := 0
var _wait := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_cases = _plan()
		_check_chief()
		return false
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			if _cases.is_empty():
				_finish()
				return true
			_case = _cases.pop_front()
			_show(_case)
			_step = 1
		1:
			Click.half(_main.get_viewport(), _go_button(), true)
			_step = 2
		2:
			Click.half(_main.get_viewport(), _go_button(), false)
			_step = 3
			_wait = 3  # a panel marked dirty rebuilds on its own _process
		3:
			_check(_case)
			_step = 0
	return false


func _plan() -> Array:
	var state = _main._state
	var ns = state.player()
	var loader = _main._loader
	var now := int(state.year) * 12 + int(state.month)
	var pid := _person(ns, loader)
	var cases: Array = []
	# Before the term-start choice: the offer is the programme line, held.
	if not Programme.available(state, ns, loader).is_empty():
		cases.append({"kind": "programme", "subject": "offer"})
	cases.append({"kind": "crisis", "setup": func() -> String: return _desk(3, true, 0)})
	cases.append({"kind": "decision", "setup": func() -> String: return _desk(1, false, 1)})
	cases.append({"kind": "election", "subject": "national", "setup": func() -> String:
		ns.has_executive = true
		var when := now + 3
		ns.next_executive_year = floori((when - 1) / 12.0)
		ns.next_executive_month = when - ns.next_executive_year * 12
		return "national"})
	cases.append({"kind": "majority", "subject": "seats"})
	cases.append({"kind": "commitment", "subject": "promise|%s|meter:unemployment_pct" % pid, "setup": func() -> String:
		ns.commitments.append({"kind": "promise", "person_id": pid, "object": "meter:unemployment_pct",
			"made_month": now, "due_month": now + 2})
		return "promise|%s|meter:unemployment_pct" % pid})
	cases.append({"kind": "request", "setup": func() -> String:
		var id := "%s|%d" % [pid, now]
		ns.audience_requests.append({"id": id, "person_id": pid, "object": "programme:none", "stance": "sponsor",
			"arrived_month": now, "deadline_month": now + 2, "status": "pending", "date": {}, "resolved_month": -1})
		AudienceDriver.refresh(_main)
		return id})
	cases.append({"kind": "bloc", "subject": _liked_bloc(ns, loader)})
	cases.append({"kind": "budget", "subject": "deficit"})
	cases.append({"kind": "unrest", "subject": "unrest"})
	cases.append({"kind": "person", "subject": pid, "setup": func() -> String:
		ns.person_grudges[pid] = 0.9
		return pid})
	# A live entry: chosen now, its "Work on it" is the verb.
	cases.append({"kind": "programme", "setup": func() -> String:
		var offer: Array = Programme.available(state, ns, loader)
		if offer.is_empty():
			return ""
		_main._on_programme_chosen(String(offer[0]["id"]))
		return String(offer[0]["id"])})
	cases.append({"kind": "bill", "setup": func() -> String:
		var law = loader.laws[0]
		ns.tabled_bill = {"law_id": String(law.id), "vote_year": int(state.year), "vote_month": int(state.month), "vote_day": 28}
		return String(law.id)})
	return cases


## Shows the card with the case's line first and two standing lines after it.
func _show(c: Dictionary) -> void:
	var subject := String(c.get("subject", ""))
	if c.has("setup"):
		subject = (c["setup"] as Callable).call()
	c["subject"] = subject
	var now := int(_main._state.year) * 12 + int(_main._state.month)
	var line := Priorities._cand(String(c["kind"]), subject, now + 2, 5.0, 1.0, now)
	var lines := [line, Priorities._standing("budget", "balance"), Priorities._standing("unrest", "unrest")]
	if c["kind"] == "budget" or c["kind"] == "unrest":
		lines = [line, Priorities._standing("majority", "seats"), Priorities._standing("bloc", "workers")]
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	game["lines"] = lines
	BriefingDriver.card_of(_main).show_view(BriefingDriver.view(_main, lines, {}))
	c["target"] = BriefingDriver.target_of(line)


func _go_button() -> Control:
	return BriefingDriver.card_of(_main).go_buttons[0]


func _check(c: Dictionary) -> void:
	var kind := String(c["kind"])
	var target: Dictionary = c["target"]
	var tab := String(target["tab"])
	var label := "%s (%s)" % [kind, c["subject"]]
	if String(c["subject"]) == "":
		_fail("%s: premise, the fixture named no subject" % label)
		return
	if BriefingDriver.card_of(_main).visible:
		_fail("%s: Go did not close the briefing" % label)
	if tab == "inbox":
		if not _main._hud.inbox.visible:
			_fail("%s: Go did not bring up the inbox" % label)
	elif not _main._windows.is_open(tab):
		_fail("%s: Go did not open the '%s' tab" % [label, tab])
	if kind == "bill":
		var page: Control = _main._windows.content("legislature")
		if not _shows_text(page, _main._law_panel._laws.tabled_text(_main._state.player())):
			_fail("bill: Go did not land on the tabled line")
		return
	# On the target tab -- except the desk's cards and a request, whose verbs are the
	# inbox card's answers (booking inside the Diary's grid is (b)'s, 3.4).
	var where: Node = _main._hud.inbox if tab == "inbox" or kind == "request" else _main._windows.content(tab)
	if where == null or ActsOn.find(where, String(target["acts_on"])) == null:
		_fail("%s: Go to '%s' found no enabled control acting on '%s'" % [label, tab, target["acts_on"]])
	if kind == "bloc":
		var laws = _main._law_panel._laws
		if laws.bloc_filter != String(c["subject"]):
			_fail("bloc: the Legislature is not filtered for the bloc")
		# A law picked under the filter opens its own detail (review: the filter's row
		# once shifted select()'s rows by one).
		var picked: String = laws._shown[-1].id
		laws.select(picked)
		var row: Button = laws._rows.get_child(laws._rows.get_child_count() - 1).get_child(0)
		if not row.button_pressed or laws.selected_id() != picked:
			_fail("bloc: picking a law under the filter did not select it")
		_main._windows.open("budget")
		if laws.bloc_filter != "":
			_fail("bloc: the filter outlived the tab")


## The chief's slot: empty without a chief record, face + name + line with one.
func _check_chief() -> void:
	var loader = _main._loader
	var nid := String(_main._state.player().id)
	var lines := [Priorities._standing("budget", "balance")]
	if BriefingDriver.chief_of(loader, nid) == null:
		var bare: Dictionary = BriefingDriver.view(_main, lines, {})
		if String(bare["who"]) != "" or String(bare["line"]) != "":
			_fail("with no chief of staff the card still names one")
		var chief := Person.new()
		chief.id = "%s_chief_fixture" % nid
		chief.person_name = "Fixture Chief"
		chief.kind = "chief_of_staff"
		chief.voice = "chief_%s" % nid.to_lower()
		loader.people[nid].append(chief)
		loader.person_by_id[chief.id] = chief
	var view: Dictionary = BriefingDriver.view(_main, lines, {})
	if not String(view["who"]).contains("chief of staff"):
		_fail("the chief's name is not on the card: '%s'" % view["who"])
	if String(view["line"]) == "":
		_fail("the chief says nothing (voice '%s')" % BriefingDriver.chief_of(loader, nid).voice)
	var a := BriefingDriver.chief_line(loader, String(BriefingDriver.chief_of(loader, nid).id), "calm", 10)
	var b := BriefingDriver.chief_line(loader, String(BriefingDriver.chief_of(loader, nid).id), "calm", 11)
	if a == b:
		_fail("the chief's line repeats two months running: '%s'" % a)


# --- fixtures --------------------------------------------------------------------------

func _desk(severity: int, interrupt: bool, index: int) -> String:
	var ns = _main._state.player()
	var ev = _main._loader.events[index]
	var entry := {"event_id": String(ev.id), "event_name": ev.event_name, "months_left": 2,
		"interrupt": interrupt, "severity": severity, "category": ev.category}
	ns.event_queue.append(entry)
	DeskCards.push(_main, ev, entry)
	return String(ev.id)


func _person(ns, loader) -> String:
	for person in loader.people[String(ns.id)]:
		if String(person.kind) != "chief_of_staff" and String(person.id) != String(ns.cabinet.get("head_of_state", "")):
			return String(person.id)
	return ""


## A bloc some proposable law likes, so the filtered list has a Propose.
func _liked_bloc(ns, loader) -> String:
	var LawList = preload("res://src/ui/law_list.gd")
	var laws: Array = preload("res://src/sim/legislature.gd").available(ns, loader.laws)
	for bloc in preload("res://src/sim/opinion_constants.gd").BLOC_KEYS:
		if not LawList.liked_by(laws, bloc).is_empty():
			return bloc
	return ""


func _shows_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).visible and (node as Label).text == text:
		return true
	if node is RichTextLabel and (node as RichTextLabel).visible and (node as RichTextLabel).get_parsed_text() == text:
		return true
	for child in node.get_children():
		if (not (child is Control) or (child as Control).visible) and _shows_text(child, text):
			return true
	return false


func _finish() -> void:
	for f in _failures:
		printerr("FAIL: %s" % f)
	if _failures.is_empty():
		print("test_briefing_go: all checks passed")
	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)
