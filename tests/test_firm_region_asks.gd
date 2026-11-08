extends SceneTree

## The deal's two missing objects (docs/audiences-model.md section 14): a chief who comes
## about a closing plant, and a regional figure who wants a development fund.
##
##   - A CLOSURE BRINGS ITS CHIEF, in a place of their own: never counted against the
##     domestic lane, with no money on the table, and only with days the plant will still
##     be there for.
##   - A REQUEST THE EVENTS OVERTOOK IS NOT A REFUSAL. The plant landed, or the player
##     answered it on the Industry tab: the request closes unpriced, its day given back.
##   - GRANT IS THE RESCUE, THE SMALLER GRANT THE BUYER. Neither writes a word, so "promise
##     a date" is not on offer, and no minister can answer for either.
##   - region:<id> IS SERVED WHILE A FUND IS OPEN THERE: a discrete holding, charged once
##     when it turns, and asked as a dated word.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Person = preload("res://src/core/person.gd")
const PeopleLoader = preload("res://src/core/loaders/people_loader.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudienceLane = preload("res://src/sim/audience_lane.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalK = preload("res://src/sim/calendar_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const Closures = preload("res://src/sim/closures.gd")
const CloK = preload("res://src/sim/closures_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Deal = preload("res://src/sim/deal.gd")
const Delegation = preload("res://src/sim/delegation.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const Levers = preload("res://src/sim/levers.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const President = preload("res://src/sim/president.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const LeverWords = preload("res://src/ui/lever_words.gd")

const PLAYER := "FRA"
const METERS := {"press_freedom": 50.0, "judicial_independence": 50.0, "grievance": 30.0}
const REGION := "FR1"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_a_closure_brings_its_chief_once()
	_check_a_chief_is_outside_the_domestic_lane()
	_check_a_chief_is_offered_only_days_before_the_plant_lands()
	_check_a_closure_that_lands_closes_the_request_unpriced()
	_check_a_closure_answered_elsewhere_closes_the_request_and_frees_its_day()
	_check_a_chief_refused_is_priced_as_a_refusal()
	_check_no_minister_can_answer_for_a_firm_or_a_region()
	_check_grant_is_the_rescue_and_writes_no_word()
	_check_a_bargain_won_is_the_buyer_and_writes_no_word()
	_check_a_promise_is_not_an_approach_on_a_firm()
	_check_grant_is_closed_once_the_plant_is_past_answering()

	_check_the_region_grammar()
	_check_the_loader_resolves_a_region()
	_check_a_region_is_served_while_a_fund_is_open()
	_check_a_region_denied_is_charged_once()
	_check_a_region_ask_is_a_dated_word_judged_on_the_fund()
	_check_the_card_names_both_objects()
	_finish()


# --- The chief --------------------------------------------------------------------------

func _check_a_closure_brings_its_chief_once() -> void:
	var f := _announced()
	var arrived := _tick_audiences(f)
	var row := _chief_row(f)
	if row.is_empty():
		_fail("a closure announced brought no request from %s, arrived %s" % [f["chief"], arrived])
		return
	if String(row["object"]) != "firm:%s" % f["company_id"] or String(row["stance"]) != "want":
		_fail("the chief asks about the wrong thing: %s" % [row])
	if int(row["deadline_month"]) != int(f["closure"]["due"]):
		_fail("the request's window (%d) is not the closure's due month (%d)" % [int(row["deadline_month"]), int(f["closure"]["due"])])
	if not (row["offer"] as Dictionary).is_empty():
		_fail("a chief's plea carried money: %s" % [row["offer"]])
	_month(f)
	_tick_audiences(f)
	if _chief_rows(f) != 1:
		_fail("the chief asked %d times about one closure" % _chief_rows(f))


func _check_a_chief_is_outside_the_domestic_lane() -> void:
	var f := _announced()
	_tick_audiences(f)
	var ns = f["ns"]
	if _chief_row(f).is_empty():
		_fail("no chief's request to read the lane against")
		return
	var domestic := 0
	for row in ns.audience_requests:
		if AK.OPEN.has(String(row["status"])) and not String(row["object"]).begins_with("firm:"):
			domestic += 1
	if AudienceLane.open_count(ns, true) != domestic:
		_fail("the domestic lane reads %d, its own requests are %d" % [AudienceLane.open_count(ns, true), domestic])


func _check_a_chief_is_offered_only_days_before_the_plant_lands() -> void:
	var f := _announced()
	_tick_audiences(f)
	var due := int(f["closure"]["due"])
	var dates: Array = Audiences.offered_dates(f["state"], f["ns"], String(_chief_row(f).get("id", "")))
	if dates.is_empty():
		_fail("the chief offered no day at all")
	for d in dates:
		if int(d["year"]) * 12 + int(d["month"]) >= due:
			_fail("a day offered after the plant lands: %s, due %d" % [d, due])


func _check_a_closure_that_lands_closes_the_request_unpriced() -> void:
	var f := _announced()
	_tick_audiences(f)
	var before := _prices(f)
	_month(f)
	_month(f)
	Closures.tick_month(f["state"], _loader)
	if String(f["closure"]["status"]) == "announced":
		_fail("the closure did not land at its due month, so this check reads nothing")
	var out: Dictionary = Audiences.tick_month(f["state"], _loader, METERS)
	var row := _chief_row(f)
	if String(row.get("status", "")) != AK.STATUS_OVERTAKEN:
		_fail("a request the plant's landing overtook reads '%s'" % row.get("status", ""))
	for lapsed in out["lapsed"]:
		if String(lapsed["person_id"]) == f["chief"]:
			_fail("an overtaken request was reported as lapsed")
	if _prices(f) != before:
		_fail("an overtaken request was priced: %s to %s" % [before, _prices(f)])


func _check_a_closure_answered_elsewhere_closes_the_request_and_frees_its_day() -> void:
	var f := _announced()
	_tick_audiences(f)
	var row := _booked(f)
	if row.is_empty():
		return
	var before := _prices(f)
	var answered: Dictionary = Closures.answer(f["state"], f["ns"], _loader, String(f["closure"]["id"]), "rescue")
	if not bool(answered["ok"]):
		_fail("the rescue was refused: %s" % [answered])
	_tick_audiences(f)
	if String(row["status"]) != AK.STATUS_OVERTAKEN:
		_fail("answered on the Industry tab, the request reads '%s'" % row["status"])
	for entry in Calendar.booked(f["state"]):
		if String(entry.get("kind", "")) == CalK.KIND_AUDIENCE and String(entry.get("action_id", "")) == String(row["id"]):
			_fail("the overtaken audience kept its day in the diary")
	if _prices(f) != before:
		_fail("a request overtaken by the player's own answer was priced")


func _check_a_chief_refused_is_priced_as_a_refusal() -> void:
	var f := _announced()
	_tick_audiences(f)
	var before := _prices(f)
	var refused: Dictionary = Audiences.decline(f["state"], f["ns"], _loader, String(_chief_row(f)["id"]))
	if not bool(refused.get("ok", false)) or String(_chief_row(f)["status"]) != AK.STATUS_DECLINED:
		_fail("the chief could not be refused: %s" % [refused])
	if float(_prices(f)["grudge"]) <= float(before["grudge"]):
		_fail("refusing a chief to their face cost nothing")


func _check_no_minister_can_answer_for_a_firm_or_a_region() -> void:
	for object in ["firm:FRA_x", "region:%s" % REGION]:
		if Delegation.impossible(object, "want") == "":
			_fail("a minister can deliver %s" % object)
		if LeverWords.delegate_hint({"why": Delegation.impossible(object, "want"), "chance": 0.0}).begins_with("A minister gives"):
			_fail("the card has no reason for %s" % object)


func _check_grant_is_the_rescue_and_writes_no_word() -> void:
	var f := _held_chief()
	if f.is_empty():
		return
	var ask: Dictionary = f["session"]["ask"]
	if String(ask["kind"]) != "firm" or String(ask["closure_id"]) != String(f["closure"]["id"]):
		_fail("the chief's ask is not the plant: %s" % [ask])
	if float((ask.get("rescue", {}) as Dictionary).get("total_eur_bn", 0.0)) <= 0.0 or not ask.has("buyer"):
		_fail("the ask does not carry the two prices the card shows: %s" % [ask])
	var card: Dictionary = Deal.answers(f["state"], f["ns"], _loader, f["session"])
	if not bool(card["grant"]["ok"]):
		_fail("Grant is closed on an open closure: %s" % [card["grant"]])
	var done: Dictionary = Deal.grant(f["state"], f["ns"], _loader, f["session"])
	if not bool(done.get("ok", false)):
		_fail("Grant failed: %s" % [done])
		return
	if String(f["closure"]["status"]) != "rescuing":
		_fail("Grant did not rescue the plant, status '%s'" % f["closure"]["status"])
	if not President.commitments(f["ns"]).is_empty():
		_fail("a rescue paid now wrote a word: %s" % [President.commitments(f["ns"])])
	if not President.keeps_silent(f["ns"], f["chief"]):
		_fail("the chief, with no party, gives silence for it")


func _check_a_bargain_won_is_the_buyer_and_writes_no_word() -> void:
	var f := _held_chief()
	if f.is_empty():
		return
	_seed_for(f, "argue", true)
	var done: Dictionary = Deal.bargain(f["state"], f["ns"], _loader, f["session"], "argue")
	if not bool(done.get("success", false)):
		_fail("the staged win did not win: %s" % [done])
		return
	if String(f["closure"]["status"]) != "searching" or String(f["closure"]["answer"]) != "buyer":
		_fail("a bargain won did not start the buyer's search: %s" % [f["closure"]])
	if not President.commitments(f["ns"]).is_empty():
		_fail("the smaller grant wrote a word: %s" % [President.commitments(f["ns"])])


func _check_a_promise_is_not_an_approach_on_a_firm() -> void:
	var f := _held_chief()
	if f.is_empty():
		return
	var offered: Array = Deal.answers(f["state"], f["ns"], _loader, f["session"])["bargain"]["approaches"]
	if offered.is_empty():
		_fail("no approach offered at all")
	for row in offered:
		if String(row["lever"]) == "promise_date":
			_fail("a dated promise is offered on a plant paid for now")
	if bool(Deal.bargain(f["state"], f["ns"], _loader, f["session"], "promise_date", {"month": _now(f) + 6}).get("ok", false)):
		_fail("the command took a dated promise on a plant")


func _check_grant_is_closed_once_the_plant_is_past_answering() -> void:
	var f := _held_chief()
	if f.is_empty():
		return
	Closures.answer(f["state"], f["ns"], _loader, String(f["closure"]["id"]), "close")
	var ask: Dictionary = Deal.ask_of(f["state"], f["ns"], _loader, _chief_row(f))
	if String(ask.get("why_not", "")) == "":
		_fail("the ask has no reason once the plant is closed: %s" % [ask])
	f["session"]["ask"] = ask
	if bool(Deal.grant(f["state"], f["ns"], _loader, f["session"]).get("ok", false)):
		_fail("Grant went through on a closed plant")


# --- The region --------------------------------------------------------------------------

func _check_the_region_grammar() -> void:
	var errors: Array[String] = []
	var p = Person.from_dict({"id": "X_a", "name": "A", "wants": [{"object": "region:%s" % REGION, "stance": "want"}]}, 0, "t.json", errors)
	if not errors.is_empty() or p.wants.size() != 1:
		_fail("a region want did not load: %s" % [errors])
	for stance in ["oppose", "sponsor"]:
		var refused: Array[String] = []
		Person.from_dict({"id": "X_a", "name": "A", "wants": [{"object": "region:%s" % REGION, "stance": stance}]}, 0, "t.json", refused)
		if refused.is_empty():
			_fail("a region want took the stance '%s'" % stance)


func _check_the_loader_resolves_a_region() -> void:
	var before: int = _loader.errors.size()
	PeopleLoader.resolve_want(_loader, {"object": "region:%s" % REGION}, PLAYER, "X_a", {}, {})
	if _loader.errors.size() != before:
		_fail("a real region was refused: %s" % [_loader.errors])
	for bad in ["region:NOWHERE", "region:DE1"]:
		PeopleLoader.resolve_want(_loader, {"object": bad}, PLAYER, "X_a", {}, {})
		if _loader.errors.size() == before:
			_fail("the loader took %s for France" % bad)
		_loader.errors.resize(before)


func _check_a_region_is_served_while_a_fund_is_open() -> void:
	var state = _state()
	var ns = state.player()
	var person = _person_with_region_want()
	var want: Dictionary = person.wants[person.wants.size() - 1]
	if Characters.want_served(ns, person, want, METERS, {}):
		_fail("a region with no fund reads served")
	var id := _open_fund(state, ns)
	if not Characters.want_served(ns, person, want, METERS, {}):
		_fail("a region with an open fund reads unserved")
	RegionFunds.stop(state, ns, id)
	if Characters.want_served(ns, person, want, METERS, {}):
		_fail("a stopped fund still serves the region")
	person.wants.pop_back()


## A fund is a holding, not a level the government keeps up month by month, so a figure
## is charged when it goes, not for every month after: the office want's rule.
func _check_a_region_denied_is_charged_once() -> void:
	var state = _state()
	var ns = state.player()
	var person = _person_with_region_want()
	var id := _open_fund(state, ns)
	Characters._settle_wants(ns, person, METERS, {})
	RegionFunds.stop(state, ns, id)
	var start := float(ns.person_grudges.get(person.id, 0.0))
	Characters._settle_wants(ns, person, METERS, {})
	var after_turn := float(ns.person_grudges.get(person.id, 0.0))
	if after_turn <= start:
		_fail("the fund stopped and nothing was charged")
	Characters._settle_wants(ns, person, METERS, {})
	if not is_equal_approx(float(ns.person_grudges.get(person.id, 0.0)), after_turn):
		_fail("a stopped fund is billed every month")
	person.wants.pop_back()


func _check_a_region_ask_is_a_dated_word_judged_on_the_fund() -> void:
	var state = _state()
	var ns = state.player()
	var person = _person_with_region_want()
	var object := "region:%s" % REGION
	var f := {"state": state}
	var ask: Dictionary = Deal.ask_of(state, ns, _loader, {"object": object, "stance": "want", "person_id": String(person.id)})
	if String(ask["kind"]) != "word" or int(ask["due_month"]) != _now(f) + int(Deal.K.WORD_MONTHS):
		_fail("a region's ask is a dated word, got %s" % [ask])
	if not President.commit(state, ns, _loader, "promise", String(person.id), object, _now(f) + 1):
		_fail("the word was not written")
	_open_fund(state, ns)
	_month(f)
	var judged: Dictionary = Levers.tick_month(state, _loader, METERS)
	if (judged["kept"] as Array).size() != 1:
		_fail("a word on a region with a fund open was not kept: %s" % [judged])
	person.wants.pop_back()


func _check_the_card_names_both_objects() -> void:
	var ns = _state().player()
	var company_id := String(Companies.majors_of(_loader, PLAYER)[0].id)
	for object in ["region:%s" % REGION, "firm:%s" % company_id]:
		var text: String = PersonCard.object_text(_loader, ns, object, {})
		if text == "" or text.contains(":") or text.contains(REGION) or text.contains(company_id):
			_fail("the card shows a raw object for %s: '%s'" % [object, text])


# --- Fixtures ----------------------------------------------------------------------------

func _state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 3
	state.day = 1
	return state


## A closure staged on the first major, through the machine's own announcement.
func _announced() -> Dictionary:
	var state = _state()
	var ns = state.player()
	var company = null
	for c in Companies.majors_of(_loader, PLAYER):
		if Companies.share_of_company(ns, c) > 0.0:
			company = c
			break
	var f := {"state": state, "ns": ns, "company_id": String(company.id), "chief": String(company.chief_id)}
	Closures._announce(ns, company, ns.companies[company.id], 0.1, _loader.closure_rule, _now(f))
	f["closure"] = ns.companies[company.id]["closure"]
	return f


func _tick_audiences(f: Dictionary) -> Array:
	return Audiences.tick_month(f["state"], _loader, METERS)["arrived"]


func _chief_row(f: Dictionary) -> Dictionary:
	for row in f["ns"].audience_requests:
		if String(row["person_id"]) == f["chief"]:
			return row
	return {}


func _chief_rows(f: Dictionary) -> int:
	var n := 0
	for row in f["ns"].audience_requests:
		n += 1 if String(row["person_id"]) == f["chief"] else 0
	return n


## The chief's request, booked on a free day it offers.
func _booked(f: Dictionary) -> Dictionary:
	var row := _chief_row(f)
	for d in Audiences.offered_dates(f["state"], f["ns"], String(row.get("id", ""))):
		if bool(d["free"]) and bool(Audiences.book(f["state"], f["ns"], _loader, String(row["id"]), d)["ok"]):
			return row
	_fail("the chief's request could not be booked")
	return {}


## The audience open on its day, the closure still waiting.
func _held_chief() -> Dictionary:
	var f := _announced()
	_tick_audiences(f)
	var row := _booked(f)
	if row.is_empty():
		return {}
	var date: Dictionary = row["date"]
	f["state"].year = int(date["year"])
	f["state"].month = int(date["month"])
	f["state"].day = int(date["day"])
	var session: Dictionary = Deal.open(f["state"], f["ns"], _loader, String(row["id"]))
	if session.is_empty():
		_fail("the chief's booked audience did not open")
		return {}
	f["session"] = session
	f["person_id"] = f["chief"]
	return f


## A loaded person carrying the region want; each check pops it again.
func _person_with_region_want():
	var leader := String(_loader.nations[PLAYER].leader_person_id)
	for person in _loader.people.get(PLAYER, []):
		if String(person.id) != leader:
			person.wants.append({"object": "region:%s" % REGION, "stance": "want"})
			return person
	return null


func _open_fund(state, ns) -> String:
	var rule: Dictionary = _loader.region_fund_rule
	var opened: Dictionary = RegionFunds.start(state, ns, _loader, REGION, float(rule["eur_bn"][0]), int(rule["years"][1]))
	if not bool(opened.get("ok", false)):
		_fail("the fund did not open: %s" % [opened])
		return ""
	return String(opened["id"])


func _prices(f: Dictionary) -> Dictionary:
	var pid := String(f["chief"])
	return {"grudge": float(f["ns"].person_grudges.get(pid, 0.0)), "loyalty": float(f["ns"].person_loyalty.get(pid, 0.0)),
		"rapport": President.rapport(f["ns"], pid)}


## A draw seed under which this attempt's roll lands as `want`, read the way Levers rolls it.
func _seed_for(f: Dictionary, lever: String, want: bool) -> void:
	var ns = f["ns"]
	var session: Dictionary = f["session"]
	var p := LeverOdds.odds(_loader.person_by_id[f["person_id"]], lever, Levers.cell(f["state"], ns, _loader, session))
	var index := LK.ATTEMPTS - int(session["attempts_left"])
	for s in range(1, 2000):
		var roll := Cycle.unit_pair(String(session["request_id"]), Cycle.salted("%s:%s:%d" % [LK.SALT_ROLL, lever, index], s), _now(f))
		if (roll < p) == want:
			ns.draw_seed = s
			return
	_fail("no seed lands %s as %s" % [lever, want])


func _month(f: Dictionary) -> void:
	var state = f["state"]
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _now(f: Dictionary) -> int:
	return int(f["state"].year) * 12 + int(f["state"].month)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_firm_region_asks: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
