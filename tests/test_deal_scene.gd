extends SceneTree

## V5.3 b, step 6 (docs/design/v5.3-ab.md section 5, #301's Deal): the scene is one ask, one
## offer and three answers, with the stakes on screen before the choice:
##   - what they want and what they give, each with what it is worth (the seats the division
##     gains, a silence's months), and what Grant, Bargain and Refuse each cost;
##   - only the three priced approaches, whose win is the smaller grant;
##   - Grant strikes the deal without a roll: the sim's rows written, a good tone, the verbs
##     folded to "End the audience", and what they owe in the Diary's list;
##   - Refuse is the decline priced once.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Bills = preload("res://src/sim/bills.gd")
const Deal = preload("res://src/sim/deal.gd")
const DealWords = preload("res://src/ui/deal_words.gd")
const ClosureCard = preload("res://src/ui/closure_card.gd")
const SC = preload("res://src/sim/shadow_constants.gd")
const AudienceWords = preload("res://src/ui/audience_words.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const President = preload("res://src/sim/president.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Words = preload("res://src/ui/lever_words.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _voter := ""
var _quiet := ""
var _start := Vector3i.ZERO


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._clock.paused = true
			_stage()
			_check_words()
			_open(_voter)
		6:
			_check_offer_card()
			_check_the_corrupt_approach()
			_check_grant()
		8:
			_end_and_leave()
		10:
			_check_owed()
			_open(_quiet)
		13:
			_check_silence_and_refuse()
		15:
			_finish()
			return true
	return false


func _ns():
	return _main._state.player()


func _scene():
	return AudienceDriver.scene_of(_main)


## A bill tabled that some requester's faction would add seats to, and one requester whose
## offer is silence: the two offers the strip words differently.
func _stage() -> void:
	var ns = _ns()
	var state = _main._state
	_start = Vector3i(int(state.year), int(state.month), int(state.day))
	var now: int = int(state.year) * 12 + int(state.month)
	var laws: Array = Legislature.available(ns, Bills.open(state, ns, _main._loader))
	for law in laws:
		ns.tabled_bill = {"law_id": String(law.id), "scale": 1.0, "referendum": false}
		_voter = ""
		_quiet = ""
		for person in _main._loader.people.get(String(ns.id), []):
			if person.wants.is_empty() or String(person.id) == String(ns.head_of_state_person_id):
				continue
			var offer: Dictionary = Deal.offer_of(state, ns, _main._loader, String(person.id))
			if _voter == "" and String(offer["kind"]) == "vote":
				_voter = String(person.id)
			elif _quiet == "" and String(offer["kind"]) == "silence":
				_quiet = String(person.id)
		if _voter != "" and _quiet != "":
			break
	if _voter == "" or _quiet == "":
		_fail("premise: no law gives both a vote offer and a silence")
		return
	for pid in [_voter, _quiet]:
		var person = _main._loader.person_by_id[pid]
		Audiences._arrive(ns, person, person.wants[0], now, [])
	AudienceDriver.refresh(_main)


func _request_of(pid: String) -> Dictionary:
	for row in Audiences.pending(_ns()):
		if String(row["person_id"]) == pid:
			return row
	return {}


## Booked and reached the way the game reaches a day (the state's date set, then its door).
func _open(pid: String) -> void:
	var row := _request_of(pid)
	if row.is_empty():
		_fail("premise: no request from %s" % pid)
		return
	var id := String(row["id"])
	# Back to the first day: the first audience moved the date past the second's offers.
	_main._state.year = int(_start.x)
	_main._state.month = int(_start.y)
	_main._state.day = int(_start.z)
	for date in Audiences.offered_dates(_main._state, _ns(), id):
		if bool(date["free"]):
			Audiences.book(_main._state, _ns(), _main._loader, id, date)
			_main._state.year = int(date["year"])
			_main._state.month = int(date["month"])
			_main._clock.year = int(date["year"])
			_main._clock.month = int(date["month"])
			_main._on_day_advanced(int(date["year"]), int(date["month"]), int(date["day"]))
			return
	_fail("premise: no free day for %s" % pid)


## Every word the three cards say, joined: the card's lines are built from the sim's reads and read here as a player does.
func _text(_name := "") -> String:
	var out := PackedStringArray()
	for label in _scene().cards.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return " ".join(out)


func _button(name: String) -> Button:
	return _scene().cards.find_child(name, true, false) as Button


func _session() -> Dictionary:
	return AudienceDriver._games[_main.get_instance_id()]["session"]


## The words alone, on the shapes Deal.answers returns.
func _check_words() -> void:
	var money := {"money": {"currency": "personal_wealth", "amount_eur_m": 2.0, "found_in_a_year": 0.34, "found_in_a_year_without": 0.12}}
	var risk := DealWords.risk(money["money"])
	if not risk.contains("34") or not risk.contains("12"):
		_fail("the money's risk does not give both chances: '%s'" % risk)
	if DealWords.risk({}) != "":
		_fail("no money still reads a risk")
	if risk.find("34") > risk.find("12"):
		_fail("the money's two chances are the wrong way round: '%s'" % risk)
	_check_a_firm_card()
	_check_a_dated_vote()
	_check_a_post_cost()
	var row := {"person_id": _voter, "verdict": "kept"}
	var kept := DealWords.owed_verdict(_main._loader, row)
	row["verdict"] = "broken"
	if not kept.contains("kept") or not DealWords.owed_verdict(_main._loader, row).contains("broke"):
		_fail("a judged word reads the wrong way: '%s', '%s'" % [kept, DealWords.owed_verdict(_main._loader, row)])
	# A Grant the sim refuses says why on its own card's line, and its button is down.
	var q := AudienceWords.question(_main._loader, _ns(), {}, {"ask": {"kind": "word", "object": "x", "due_month": 0}, "offer": {"kind": "silence", "months": 12},
		"grant": {"ok": false, "why_not": "Why not."}, "refuse": {}, "bargain": {"due_month": 0, "approaches": []}}, {}, "w", "executive", {})
	var lines: Array = q["grant"]["lines"]
	if bool(q["grant"]["ok"]) or not lines.any(func(l: Dictionary) -> bool: return String(l["text"]) == "Why not."):
		_fail("a refused Grant does not say why on its card: %s" % [lines])
	if not (q["counter"] as Dictionary).is_empty():
		_fail("an ask with no date to move still has a Counter")


func _card(ask: Dictionary, offer: Dictionary) -> Dictionary:
	return DealWords.card(_main._loader, _ns(), {"ask": ask, "offer": offer, "grant": {"ok": true, "why_not": ""}, "refuse": {},
		"bargain": {"due_month": int(ask.get("smaller_due_month", 0)), "approaches": []}}, {}, "wants it", "executive")


## A closing plant is paid now: the rescue's price on Grant, the buyer's on Bargain, no word.
func _check_a_firm_card() -> void:
	var rescue := {"id": "rescue", "kind": "rescue", "debt_eur_bn_per_year": 0.5, "months": 24, "jobs_lost": 0.0, "total_eur_bn": 1.0}
	var buyer := {"id": "buyer", "kind": "buyer", "jobs_lost": 1000.0, "debt_eur_bn": 0.1, "sweetener_eur_bn": 0.2, "chance": 0.6, "months": 6}
	var card := _card({"kind": "firm", "object": "firm:nobody", "closure_id": "c", "why_not": "", "rescue": rescue, "buyer": buyer}, {"kind": "silence", "months": 12})
	if not String(card["grant_cost"]).contains(ClosureCard.money(rescue)[0]):
		_fail("a firm's Grant does not say what the rescue costs: '%s'" % card["grant_cost"])
	if not String(card["bargain"]).contains(ClosureCard.money(buyer)[0]):
		_fail("a firm's Bargain does not say what the buyer costs: '%s'" % card["bargain"])
	for key in ["grant_cost", "bargain"]:
		if String(card[key]).contains("-1") or String(card[key]).contains(tr("Your word")):
			_fail("a firm's card reads as a dated word: '%s'" % card[key])


func _check_a_dated_vote() -> void:
	var offer := {"kind": "vote", "law_id": "x", "seats": 16, "date": {"year": 2026, "month": 12, "day": 3}}
	var stake := String(_card({"kind": "word", "object": "meter:x", "due_month": 24313, "smaller_due_month": 24325}, offer)["give_stake"])
	var day: String = preload("res://src/ui/date_text.gd").day_month_year(3, 12, 2026)
	if not stake.contains(day) or not stake.contains("16"):
		_fail("a dated vote does not say its seats and day '%s': '%s'" % [day, stake])


func _check_a_post_cost() -> void:
	var removal := {"leader_id": _voter, "grudge_before": 0.0, "grudge_after": 0.5, "rebels": 1, "rebels_after": 3}
	var cost := DealWords._post_cost(_main._loader, _ns(), removal)
	if not cost.contains(_main._loader.person_name(_voter)) or not cost.contains("2 more"):
		_fail("a post taken from a partner does not read its price: '%s'" % cost)
	if not DealWords._post_cost(_main._loader, _ns(), {}).contains("free"):
		_fail("a free portfolio reads as priced")


func _check_offer_card() -> void:
	var session := _session()
	if session.is_empty():
		_fail("the booked day did not open the audience")
		return
	if not session.has("ask"):
		_fail("the scene opened Levers' session, not Deal's")
	var answers: Dictionary = Deal.answers(_main._state, _ns(), _main._loader, session)
	var seats := int(answers["offer"]["seats"])
	var said := _text()
	if not said.contains(str(seats)):
		_fail("the cards do not say the %d seats the division gains: '%s'" % [seats, said])
	if _scene()._lead.text == "":
		_fail("the card has no ask or no offer")
	var feel := preload("res://src/ui/feelings.gd").of(_ns(), _voter)
	var price := Words.price_text(answers["refuse"], feel)
	if not said.contains(price):
		_fail("Refuse's price is not on its card: '%s' against '%s'" % [said, price])
	var counter = _scene().cards.date_pick
	if counter == null or counter.absolute_month() != int(answers["bargain"]["due_month"]):
		_fail("the Counter's field does not open on the month the smaller grant is for")
	for lever in ["argue", "promise_date", "pressure", "flatter", "friendship", "bargain"]:
		if _scene().find_child("Lever_" + lever, true, false) != null:
			_fail("the scene still shows the lever %s" % lever)


## The parent's ruling on #311, the author's call: the corrupt bargain is a fourth approach, on
## a person whose request came with money (rare, and never a principled person's), its risk
## on the row; favour and vote trade do not come back with it.
func _check_the_corrupt_approach() -> void:
	var session := _session()
	var row: Dictionary = {}
	for candidate in _ns().audience_requests:
		if String(candidate["id"]) == String(session["request_id"]):
			row = candidate
	var state = _main._state
	var plain: Array = Deal.answers(state, _ns(), _main._loader, session)["bargain"]["approaches"]
	if plain.any(func(r: Dictionary) -> bool: return String(r["lever"]) == "bargain"):
		_fail("the corrupt bargain is open on a person who offered nothing")
	row["offer"] = {"currency": "personal_wealth", "amount_eur_m": 2.0}
	var approaches: Array = Deal.answers(state, _ns(), _main._loader, session)["bargain"]["approaches"]
	var found: Array = approaches.filter(func(r: Dictionary) -> bool: return String(r["lever"]) == "bargain")
	if found.size() != 1:
		_fail("a person who came with money has no corrupt approach")
	else:
		for currency in found[0]["currencies"]:
			if not SC.CURRENCY_EVIDENCE.has(String(currency["currency"])):
				_fail("the fourth approach still sells %s" % currency["currency"])
			if not currency.has("found_in_a_year") or not currency.has("found_in_a_year_without"):
				_fail("the %s row has no risk on it" % currency["currency"])
	var attempts := int(session["attempts_left"])
	var refused: Dictionary = Deal.bargain(state, _ns(), _main._loader, session, "bargain", {"currency": "favour"})
	if bool(refused["ok"]) or int(session["attempts_left"]) != attempts:
		_fail("the fourth approach took a clean currency: %s" % [refused])
	row.erase("offer")


func _check_grant() -> void:
	var before := President.owed(_ns()).size()
	_button("GrantButton").pressed.emit()
	if President.owed(_ns()).size() != before + 1:
		_fail("Grant did not write what they owe")
	if _scene()._tone.text != tr("In your favour"):
		_fail("Grant landed as '%s', not in the player's favour" % _scene()._tone.text)
	if _scene().cards.visible or not _scene().flow.in_talk():
		_fail("after the deal the cards stay up or the talk does not open")
	if _scene()._end.text != tr("That will be all"):
		_fail("after the deal the way out reads '%s'" % _scene()._end.text)


func _end_and_leave() -> void:
	_scene()._end.pressed.emit()


## The deal stands in the Diary's list, what they owe in their name; judged, in its record.
func _check_owed() -> void:
	var row: Dictionary = President.owed(_ns())[0].duplicate()
	row["verdict"] = "broken"
	row["judged_month"] = 1
	_ns().commitments_judged.append(row)
	var recorded := false
	for line in AudienceDriver.judged_rows(_main):
		recorded = recorded or String(line["text"]).contains(_main._loader.person_name(String(row["person_id"])))
	if not recorded:
		_fail("a judged pledge is not on the Diary's record")
	_ns().commitments_judged.pop_back()
	# Their half by its own words: the president's word names the same person.
	var theirs := DealWords.owed_text(_main._loader, _ns(), President.owed(_ns())[0])
	if not AudienceDriver.given_lines(_main).has(theirs):
		_fail("what they owe is not in the Diary's list: %s" % [AudienceDriver.given_lines(_main)])
	var owed: Dictionary = President.owed(_ns())[0]
	var due := int(owed["due_month"])
	_main._calendar_panel._grid.show_items(_main._state, _main._loader, [])
	var marked := false
	for entry in _main._calendar_panel._grid._entries((due - 1) / 12, (due - 1) % 12 + 1).get(1, []):
		marked = marked or String(entry["text"]) == theirs
	if not marked:
		_fail("what they owe is not on its due date in the Diary")


func _check_silence_and_refuse() -> void:
	var session := _session()
	if session.is_empty():
		_fail("the second audience did not open")
		return
	var answers: Dictionary = Deal.answers(_main._state, _ns(), _main._loader, session)
	if String(answers["offer"]["kind"]) != "silence":
		_fail("premise: the second offer is no longer silence")
	if not _text().contains(str(int(answers["offer"]["months"]))):
		_fail("a silence's card does not give its months: '%s'" % _text())
	if _button("RefuseButton") == null or _button("GrantButton") == null:
		_fail("the question has no Grant or no Refuse")
	# A lever outside the approaches is refused by Deal.bargain, and Levers.attempt would have taken it.
	var attempts := int(session["attempts_left"])
	var refused: Dictionary = Deal.bargain(_main._state, _ns(), _main._loader, session, "flatter", {})
	if bool(refused["ok"]) or int(session["attempts_left"]) != attempts:
		_fail("an approach did not go through Deal.bargain: %s" % [refused])
	var id := String(session["request_id"])
	_button("RefuseButton").pressed.emit()
	if _scene().flow.state != preload("res://src/ui/audience_flow.gd").S.REFUSED:
		_fail("Refuse did not end on the refusal's own state: %s" % _scene().flow.name_of(_scene().flow.state))
	if String(Audiences.request(_ns(), id).get("status", "")) == "held":
		_fail("Refuse left the request held")


func _finish() -> void:
	if _failures.is_empty():
		print("test_deal_scene: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
