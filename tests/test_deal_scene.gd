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


func _text(name: String) -> String:
	var node: Label = _scene().find_child(name, true, false)
	return node.text if node != null else ""


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
	var deal = _scene().deal
	deal.show_card({"want": "w", "want_stake": "", "give": "g", "give_stake": "", "give_good": false, "grant_ok": false,
		"grant_why": "Why not.", "grant_cost": "A price.", "bargain": "", "struck": false, "refuse": ""})
	if _text("GrantCost") != "Why not.":
		_fail("a refused Grant does not say why on its line: '%s'" % _text("GrantCost"))


func _check_offer_card() -> void:
	var session := _session()
	if session.is_empty():
		_fail("the booked day did not open the audience")
		return
	if not session.has("ask"):
		_fail("the scene opened Levers' session, not Deal's")
	var answers: Dictionary = Deal.answers(_main._state, _ns(), _main._loader, session)
	var seats := int(answers["offer"]["seats"])
	if not _text("GiveStake").contains(str(seats)):
		_fail("the strip does not say the %d seats the division gains: '%s'" % [seats, _text("GiveStake")])
	if _text("Want") == "" or _text("Give") == "":
		_fail("the card has no ask or no offer")
	if _text("GrantCost") == "":
		_fail("Grant's cost is not on the strip")
	var feel := preload("res://src/ui/feelings.gd").of(_ns(), _voter)
	var price := Words.price_text(answers["refuse"], feel)
	if not _text("RefuseCost").contains(price):
		_fail("Refuse's price is not on the strip: '%s' against '%s'" % [_text("RefuseCost"), price])
	var bargain_head := _text("BargainHead")
	if not bargain_head.contains(Words.when(int(answers["bargain"]["due_month"]))):
		_fail("Bargain's smaller grant has no date: '%s'" % bargain_head)
	var verbs = _scene().verbs
	for lever in ["argue", "promise_date", "pressure"]:
		if verbs.lever_button(lever) == null:
			_fail("the approach %s is missing" % lever)
	for lever in ["flatter", "friendship", "bargain"]:
		if verbs.lever_button(lever) != null:
			_fail("the scene still offers %s" % lever)


func _check_grant() -> void:
	var before := President.owed(_ns()).size()
	(_scene().find_child("Grant", true, false) as Button).pressed.emit()
	if President.owed(_ns()).size() != before + 1:
		_fail("Grant did not write what they owe")
	if _scene()._tone.text != tr("In your favour"):
		_fail("Grant landed as '%s', not in the player's favour" % _scene()._tone.text)
	if not (_scene().find_child("Grant", true, false) as Button).disabled:
		_fail("Grant stays open after the deal is struck")
	if _scene().verbs.lever_button("argue") != null:
		_fail("the approaches stay on the table after the deal is struck")
	if _scene()._end.text != tr("End the audience"):
		_fail("after the deal the way out reads '%s'" % _scene()._end.text)


func _end_and_leave() -> void:
	_scene()._end.pressed.emit()
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


func _check_silence_and_refuse() -> void:
	var session := _session()
	if session.is_empty():
		_fail("the second audience did not open")
		return
	var answers: Dictionary = Deal.answers(_main._state, _ns(), _main._loader, session)
	if String(answers["offer"]["kind"]) != "silence":
		_fail("premise: the second offer is no longer silence")
	if not _text("GiveStake").contains(str(int(answers["offer"]["months"]))):
		_fail("a silence's strip does not give its months: '%s'" % _text("GiveStake"))
	if _scene()._end.text != tr("Refuse"):
		_fail("the way out before a deal reads '%s', not Refuse" % _scene()._end.text)
	# A lever outside the three is refused by Deal.bargain, and Levers.attempt would have taken it.
	var attempts := int(session["attempts_left"])
	_scene().attempted.emit("flatter", {})
	if _scene()._tone.text != tr("Not possible") or int(session["attempts_left"]) != attempts:
		_fail("an approach did not go through Deal.bargain: tone '%s', attempts %d" % [_scene()._tone.text, int(session["attempts_left"])])
	var id := String(session["request_id"])
	_scene()._end.pressed.emit()
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
