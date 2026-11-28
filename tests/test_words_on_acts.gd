extends SceneTree

## The author's call 2 B, "Seulement des actes" (2026-11-28; the blind playtest's G7): a word
## is given only on something the president DOES -- a bill brought, a post given, a region's
## fund opened, a measure lifted, a plant answered. A want on a programme's place or a meter's
## level is talk. Headless. The audience's half (the ask, Grant, the approaches, the close) is
## in tests/test_deal.gd; this file holds the rule itself, the phone, the levers' own spend and
## the words an older save already carries.
##
##   - WantTerms.is_act is the one predicate, and Deal, Levers and Phone all read it.
##   - The phone offers no promise on talk, and no vote-trade IOU lands on one.
##   - Levers.pay refuses a promise or an IOU on talk, whatever door reached it.
##   - A word already given on a programme or a meter (an older save) is judged as it was
##     given, through a save: the measured oracle is the playtest probe's (Delcour broken while
##     the programme stands, Pradelles kept once press freedom is above her line).
##   - Delegation is unchanged (call 2 B pick 3 a): the minister still answers in a word.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const WantTerms = preload("res://src/sim/want_terms.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Levers = preload("res://src/sim/levers.gd")
const Phone = preload("res://src/sim/phone.gd")
const President = preload("res://src/sim/president.gd")
const Programme = preload("res://src/sim/programme.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_the_acts()
	_check_the_phone_promises_no_talk()
	_check_the_phone_trades_no_vote_on_talk()
	_check_the_levers_spend_no_word_on_talk()
	_check_a_promise_on_talk_spends_no_attempt()
	_check_an_old_word_is_judged_as_it_was_given()
	_check_delegation_still_answers_in_a_word()
	_finish()


func _check_the_acts() -> void:
	for object in ["law:x", "office:portfolio:health", "region:FRE", "measure:tariff", "firm:x"]:
		if not WantTerms.is_act(object):
			_fail("%s is an act" % object)
	for object in ["programme:prog_jobs_first", "meter:press_freedom", "office:premiership", "office:party_leadership:x", ""]:
		if WantTerms.is_act(object):
			_fail("%s is not an act" % object)


func _check_the_phone_promises_no_talk() -> void:
	for object in ["meter:press_freedom", "region:FRE"]:
		var f := _requested(object)
		if f.is_empty():
			return
		var row := _lever_row(Phone.options(f["state"], f["ns"], _loader, f["pid"]), "promise_date")
		var talk: bool = String(object).begins_with("meter:")
		if talk and (bool(row.get("offered", true)) or String(row.get("why_not", "")) != AK.TALK_ONLY):
			_fail("the phone offers a promise on %s: %s" % [object, row])
		if not talk and String(row.get("why_not", "")) == AK.TALK_ONLY:
			_fail("the phone calls a fund talk: %s" % [row])
		if talk:
			var r: Dictionary = Phone.dial(f["state"], f["ns"], _loader, f["pid"], "promise_date", {"due_month": _now(f["state"]) + LK.PROMISE_MIN_MONTHS})
			if bool(r.get("ok", true)) or String(r.get("error", "")) != AK.TALK_ONLY or not f["ns"].commitments.is_empty():
				_fail("a phone promise on talk went through: %s %s" % [r, f["ns"].commitments])


func _check_the_phone_trades_no_vote_on_talk() -> void:
	var f := _requested("meter:press_freedom")
	if f.is_empty():
		return
	var bargain := _lever_row(Phone.options(f["state"], f["ns"], _loader, f["pid"]), "bargain")
	for currency in bargain.get("currencies", []):
		if String(currency["currency"]) == LK.CURRENCY_VOTE_TRADE and (bool(currency["offered"]) or String(currency["why_not"]) != AK.TALK_ONLY):
			_fail("the phone card offers a vote trade on talk: %s" % [currency])
	var r: Dictionary = Phone.dial(f["state"], f["ns"], _loader, f["pid"], "bargain", {"currency": LK.CURRENCY_VOTE_TRADE})
	if not f["ns"].commitments.is_empty():
		_fail("a vote trade by phone wrote an IOU on talk: %s (%s)" % [f["ns"].commitments, r])
	if bool(r.get("ok", true)) or String(r.get("error", "")) != AK.TALK_ONLY:
		_fail("a vote trade by phone on talk is refused with the talk reason: %s" % [r])


func _check_the_levers_spend_no_word_on_talk() -> void:
	var f := _requested("meter:press_freedom")
	if f.is_empty():
		return
	var state = f["state"]
	var ns = f["ns"]
	var person = _loader.person_by_id[f["pid"]]
	var now := _now(state)
	var due := now + LK.PROMISE_MIN_MONTHS
	for object in ["meter:press_freedom", "programme:prog_jobs_first"]:
		if not Levers.pay(state, ns, _loader, person, object, "promise_date", {"due_month": due}, now).has("refused") \
				or not Levers.pay(state, ns, _loader, person, object, "bargain", {"currency": LK.CURRENCY_VOTE_TRADE}, now).has("refused"):
			_fail("the levers' spend gave a word on %s" % object)
	if not ns.commitments.is_empty():
		_fail("a refused word wrote a row: %s" % [ns.commitments])
	if Levers.pay(state, ns, _loader, person, "region:FRE", "promise_date", {"due_month": due}, now).has("refused") \
			or Levers.pay(state, ns, _loader, person, "region:FRE", "bargain", {"currency": LK.CURRENCY_VOTE_TRADE}, now).has("refused"):
		_fail("a word on a region's fund, an act, was refused")
	if ns.commitments.size() != 2:
		_fail("a word and an IOU on a fund are two rows: %s" % [ns.commitments])


## A scene opened by Levers alone (no Deal ask): a promise on talk is refused before its roll.
func _check_a_promise_on_talk_spends_no_attempt() -> void:
	var f := _requested("meter:press_freedom")
	if f.is_empty():
		return
	var state = f["state"]
	for d in Audiences.offered_dates(state, f["ns"], f["id"]):
		if bool(d["free"]) and bool(Audiences.book(state, f["ns"], _loader, f["id"], d).get("ok", false)):
			state.year = int(d["year"])
			state.month = int(d["month"])
			state.day = int(d["day"])
			break
	var session: Dictionary = Levers.open(state, f["ns"], _loader, f["id"])
	if session.is_empty():
		_fail("premise: the audience did not open")
		return
	var r: Dictionary = Levers.attempt(f["state"], f["ns"], _loader, session, "promise_date", {"due_month": _now(f["state"]) + LK.PROMISE_MIN_MONTHS})
	if bool(r.get("ok", true)) or String(r.get("error", "")) != AK.TALK_ONLY or int(session["attempts_left"]) != LK.ATTEMPTS or not f["ns"].commitments.is_empty():
		_fail("a promise on talk took a roll or wrote a word: %s %s" % [r, session])


## The probe's oracle (blind playtest 2026-11-28, G7): written raw as an older save holds
## them, through a save, each judged on its want at its date.
func _check_an_old_word_is_judged_as_it_was_given() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	var ns = state.player()
	if not bool(Programme.choose(state, ns, "prog_jobs_first", _loader).get("applied", false)):
		_fail("premise: Jobs First could not be chosen")
		return
	var due := _now(state) + 1
	ns.commitments.append({"kind": "promise", "person_id": "FRA_delcour", "object": "programme:prog_jobs_first", "made_month": _now(state), "due_month": due})
	ns.commitments.append({"kind": "promise", "person_id": "FRA_pradelles", "object": "meter:press_freedom", "made_month": _now(state), "due_month": due})
	var back = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	if back.commitments.size() != 2:
		_fail("the old words did not survive a save: %s" % [back.commitments])
		return
	state.nations[PLAYER] = back
	back.press_freedom = 0.25
	state.month = 2
	var judged := Levers.tick_month(state, _loader, WorldMonth.character_meters(state))
	var verdicts := {}
	for verdict in ["kept", "broken", "void"]:
		for row in judged[verdict]:
			verdicts[String(row["person_id"])] = verdict
	if String(verdicts.get("FRA_delcour", "")) != "broken":
		_fail("an old word to Delcour, against the programme still on the register, is broken: %s" % [verdicts])
	if String(verdicts.get("FRA_pradelles", "")) != "kept":
		_fail("an old word to Pradelles, press freedom above her line, is kept: %s" % [verdicts])


func _check_delegation_still_answers_in_a_word() -> void:
	var f := _requested("meter:press_freedom")
	if f.is_empty():
		return
	var r: Dictionary = Audiences.delegate(f["state"], f["ns"], _loader, f["id"])
	var rows: Array = f["ns"].commitments
	if not bool(r.get("ok", false)) or rows.size() != 1 or String(rows[0]["kind"]) != "delegated":
		_fail("a delegated talk request still writes the minister's word (pick 3 a): %s %s" % [r, rows])


# --- Fixtures ---------------------------------------------------------------------------

## A France game in its first month with one open request on `object`, from the first
## person the phone reaches. {state, ns, pid, id}.
func _requested(object: String) -> Dictionary:
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	var ns = state.player()
	for person in _loader.people.get(PLAYER, []):
		if person.id == President.leader_id(ns) or not President.covers(state, ns, _loader, person.id):
			continue
		Audiences._arrive(ns, person, {"object": object, "stance": "want"}, _now(state), [])
		return {"state": state, "ns": ns, "pid": String(person.id), "id": String(ns.audience_requests[-1]["id"])}
	_fail("premise: nobody for the phone to reach")
	return {}


func _lever_row(options: Dictionary, lever: String) -> Dictionary:
	for row in options.get("levers", []):
		if String(row["lever"]) == lever:
			return row
	return {}


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_words_on_acts: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
