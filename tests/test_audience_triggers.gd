extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_triggers.gd
## Non-zero exit on any failure.
##
## V5.2b b3, the meetings and the asks outside the hazard (src/sim/meetings.gd,
## src/sim/audience_triggers.gd; docs/audiences-model.md "The meetings" and "The
## triggers"). What this file holds:
##
##   - A MEETING TEACHES THE HEAD MET, ONCE: a state visit either way, or a summit,
##     stamps GameState.met_months; the month after, the president knows and likes
##     the other nation's head a little more. Any other stamp teaches nothing.
##   - AN OFFICE WANT ASKS AT A RESHUFFLE (the pre-mortem's third trigger): the
##     player's Cabinet.assign() that hands a portfolio to another party stamps the
##     month and the portfolio -- never a no-op assign, never a government's seating;
##     the month after, whoever wanted THAT portfolio and did not get it asks,
##     outside the hazard and under the lane's rules.
##   - A VISITOR UNDER A FRENCH MEASURE ASKS TO HAVE IT LIFTED (the author's answer,
##     2026-10-24, "Lever une mesure francaise"): only when the played nation holds
##     a measure against the visiting nation; priced in rapport only (a foreign head
##     carries no grudge or loyalty on this register); its own cap, outside the
##     domestic lane's; a promise to lift is judged on the measure itself.
##   - THE G7 HOOK: Audiences.invite() is a door into the lane under its rules, for
##     V5.3c's builder (a private firm's chief executive on a "price:" object).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const RK = preload("res://src/core/relations.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Meetings = preload("res://src/sim/meetings.gd")
const President = preload("res://src/sim/president.gd")
const K = preload("res://src/sim/audience_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudienceTriggers = preload("res://src/sim/audience_triggers.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Characters = preload("res://src/sim/characters.gd")
const Levers = preload("res://src/sim/levers.gd")
const Phone = preload("res://src/sim/phone.gd")
const LK = preload("res://src/sim/lever_constants.gd")

const METERS := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}

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

	_check_a_meeting_last_month_teaches_the_head()
	_check_other_stamps_teach_nothing()
	_check_the_month_runs_the_meetings()
	_check_only_the_players_reshuffle_is_stamped()
	_check_an_office_want_asks_after_a_reshuffle()
	_check_a_served_office_want_does_not_ask()
	_check_a_visitor_under_a_french_measure_asks()
	_check_a_visitor_costs_rapport_only()
	_check_visitors_have_their_own_cap()
	_check_a_promise_to_lift_is_judged_on_the_measure()
	_check_an_org_levy_brings_no_visitor()
	_check_a_promise_to_lift_ignores_an_org_levy()
	_check_a_lever_on_a_visitor_writes_no_grudge()
	_check_invite_is_the_lanes_door()

	_finish()


## A pair stamped in the month that just ended: the other nation's head is met --
## knowledge on the audience's curve, the meeting's rapport -- and named; the month
## after, the same stamp teaches nothing more.
func _check_a_meeting_last_month_teaches_the_head() -> void:
	var state = _game()
	var ns = state.player()
	var head := President.leader_id(state.nations["DEU"])
	state.met_months[RK.key(PLAYER, "DEU")] = _now(state) - 1
	var met: Array[String] = Meetings.tick_month(state, _loader)
	if met != [head]:
		_fail("the meeting named %s, not [%s]" % [met, head])
	if absf(President.knowledge(ns, head) - K.KNOW_MEETING) > 0.000001 or absf(President.rapport(ns, head) - K.RAPPORT_MEETING) > 0.000001:
		_fail("meeting %s taught knowledge %.4f and rapport %.4f" % [head, President.knowledge(ns, head), President.rapport(ns, head)])
	_advance(state)
	var k := President.knowledge(ns, head)
	if not Meetings.tick_month(state, _loader).is_empty() or President.knowledge(ns, head) != k:
		_fail("a meeting two months old taught again")


## A stamp this month (the tick's own, read next month), one two months old, and a
## pair the player is not in teach nobody; an older save's history of stamps
## teaches nothing beyond the month that just ended.
func _check_other_stamps_teach_nothing() -> void:
	var state = _game()
	var ns = state.player()
	var now := _now(state)
	state.met_months[RK.key(PLAYER, "DEU")] = now
	state.met_months[RK.key(PLAYER, "ITA")] = now - 2
	state.met_months[RK.key(PLAYER, "ESP")] = now - 30
	state.met_months[RK.key("DEU", "ITA")] = now - 1
	var knowledge: Dictionary = ns.person_knowledge.duplicate()
	var rapport: Dictionary = ns.person_rapport.duplicate()
	if not Meetings.tick_month(state, _loader).is_empty():
		_fail("a stamp outside the month that just ended taught someone")
	if ns.person_knowledge != knowledge or ns.person_rapport != rapport:
		_fail("a stamp outside the month that just ended wrote a register")


## Through the game's own month: a visit stamped last month is met in this month's
## Audiences step, and the report names the head.
func _check_the_month_runs_the_meetings() -> void:
	var state = _game()
	var head := President.leader_id(state.nations["ITA"])
	state.met_months[RK.key(PLAYER, "ITA")] = _now(state) - 1
	var report: Dictionary = WorldMonth.tick_month(state, _loader)
	if not (report.get("meetings", []) as Array).has(head):
		_fail("the month's report names %s as met, not %s" % [report.get("meetings", []), head])
	if President.knowledge(state.player(), head) <= 0.0:
		_fail("the month met %s and taught nothing" % head)


## Cabinet.assign() -- the player's reshuffle -- stamps the month; a government
## seated by an election or a formation (Cabinet.seat) does not.
func _check_only_the_players_reshuffle_is_stamped() -> void:
	var state = _game()
	var ns = state.player()
	if int(ns.reshuffle_month) != -1:
		_fail("a new game reads a reshuffle at %d" % int(ns.reshuffle_month))
	var party_list: Array = _loader.parties[PLAYER]
	Cabinet.seat(ns, party_list)
	if int(ns.reshuffle_month) != -1:
		_fail("seating a government stamped a reshuffle")
	var portfolio := ""
	for f in ns.cabinet:
		if String(ns.cabinet[f]) != "":
			portfolio = f
			break
	var other := ""
	for pid in ns.coalition_party_ids:
		if pid != String(ns.cabinet[portfolio]):
			other = pid
	if portfolio == "" or other == "":
		_fail("France's cabinet has no portfolio to hand to a second coalition party")
		return
	Cabinet.assign(state, portfolio, String(ns.cabinet[portfolio]), party_list)
	if int(ns.reshuffle_month) != -1:
		_fail("handing a portfolio to the party that holds it stamped a reshuffle")
	Cabinet.assign(state, portfolio, other, party_list)
	if int(ns.reshuffle_month) != _now(state) or String(ns.reshuffle_portfolio) != portfolio:
		_fail("a reshuffle stamped %d / '%s', not %d / '%s'" % [int(ns.reshuffle_month), ns.reshuffle_portfolio, _now(state), portfolio])


## The month after a reshuffle of a portfolio, whoever wanted it unserved is
## invited -- and arrives in the lane through the month -- while a stamp from this
## month or two months ago, a reshuffle of another portfolio, and a premiership
## want (a portfolio reshuffle never moves the premiership) invite nobody.
func _check_an_office_want_asks_after_a_reshuffle() -> void:
	var state = _game()
	var ns = state.player()
	var asker := _office_wanter(ns, false)
	if asker.is_empty():
		_fail("no France person has an unserved portfolio want to stage the reshuffle")
		return
	var key := String(asker["object"]).substr("office:portfolio:".length())
	var now := _now(state)
	ns.reshuffle_portfolio = key
	for stamp in [now, now - 2]:
		ns.reshuffle_month = stamp
		if _invited(state, ns).has(asker["id"]):
			_fail("a reshuffle stamped %d invited %s at %d" % [stamp, asker["id"], now])
	ns.reshuffle_month = now - 1
	ns.reshuffle_portfolio = "no_such_portfolio"
	if _invited(state, ns).has(asker["id"]):
		_fail("a reshuffle of another portfolio invited %s" % asker["id"])
	ns.reshuffle_portfolio = key
	var invited := _invited(state, ns)
	if String(invited.get(asker["id"], "")) != asker["object"]:
		_fail("the reshuffle did not invite %s about %s (%s)" % [asker["id"], asker["object"], invited])
	for pid in invited:
		if String(invited[pid]) == "office:premiership":
			_fail("a portfolio reshuffle invited %s about the premiership" % pid)
	var report: Dictionary = Audiences.tick_month(state, _loader, METERS)
	var arrived := false
	for row in report["arrived"]:
		arrived = arrived or (String(row["person_id"]) == asker["id"] and String(row["object"]) == asker["object"])
	if not arrived:
		_fail("the invited %s did not reach the lane: %s" % [asker["id"], report["arrived"]])


## A person whose party already holds the portfolio they want is not invited.
func _check_a_served_office_want_does_not_ask() -> void:
	var state = _game()
	var ns = state.player()
	var person = _loader.person_by_id.get("FRA_vasseur")
	if person == null:
		_fail("FRA_vasseur (an office want for pensions) is not in the content")
		return
	ns.cabinet["pensions"] = String(person.party_id)
	ns.reshuffle_month = _now(state) - 1
	ns.reshuffle_portfolio = "pensions"
	if _invited(state, ns).has(person.id):
		_fail("a served portfolio want was invited")


## A head whose nation state-visited France this tick asks to have France's measure
## on their nation lifted -- and only then: no measure, or a visit stamped last
## month, and nobody asks.
func _check_a_visitor_under_a_french_measure_asks() -> void:
	var state = _game()
	var ns = state.player()
	var head := President.leader_id(state.nations["DEU"])
	var object := "measure:%s" % RK.directed_key(PLAYER, "DEU")
	state.met_months[RK.key(PLAYER, "DEU")] = _now(state)
	if _arrived_about(state, head) != "":
		_fail("a visitor with no French measure on their nation asked")
	state = _game()
	_impose(state, "DEU")
	state.met_months[RK.key(PLAYER, "DEU")] = _now(state) - 1
	if _arrived_about(state, head) != "":
		_fail("a visit stamped last month sent a request")
	state = _game()
	_impose(state, "DEU")
	state.met_months[RK.key(PLAYER, "DEU")] = _now(state)
	if _arrived_about(state, head) != object:
		_fail("the visiting %s under a French measure did not ask about %s" % [head, object])


## Declining a visitor -- or letting the request lapse -- costs rapport only: no
## grudge, no loyalty for a foreign head, and the card says so.
func _check_a_visitor_costs_rapport_only() -> void:
	var state = _game()
	var ns = state.player()
	var head := President.leader_id(state.nations["DEU"])
	_impose(state, "DEU")
	state.met_months[RK.key(PLAYER, "DEU")] = _now(state)
	Audiences.tick_month(state, _loader, METERS)
	var id := _request_of(ns, head)
	if id == "":
		_fail("no visitor request to decline")
		return
	if float(Audiences.decline_price(ns, _loader, id)["grudge"]) != 0.0:
		_fail("a visitor's card names a grudge price")
	var r: Dictionary = Audiences.decline(state, ns, _loader, id)
	if ns.person_grudges.has(head) or ns.person_loyalty.has(head):
		_fail("declining a visitor wrote grudge or loyalty for %s" % head)
	if absf(President.rapport(ns, head) - AK_DECLINE()) > 0.000001 or not bool(r.get("ok", false)):
		_fail("declining a visitor left rapport %.3f (%s)" % [President.rapport(ns, head), r])


## A visitor does not queue behind a full domestic lane, and a second visitor waits
## while one is open.
func _check_visitors_have_their_own_cap() -> void:
	var state = _game()
	var ns = state.player()
	var n := 0
	for person in _loader.people[PLAYER]:
		if n >= K.MAX_PENDING:
			break
		if person.id == President.leader_id(ns):
			continue
		ns.audience_requests.append({"id": "%s|full" % person.id, "person_id": person.id, "object": "programme:none",
			"stance": "sponsor", "arrived_month": _now(state), "deadline_month": _now(state) + 2,
			"status": K.STATUS_PENDING, "date": {}, "resolved_month": -1})
		n += 1
	for nation_id in ["DEU", "ITA"]:
		_impose(state, nation_id)
		state.met_months[RK.key(PLAYER, nation_id)] = _now(state)
	Audiences.tick_month(state, _loader, METERS)
	var visitors := 0
	for row in ns.audience_requests:
		if String(row["object"]).begins_with("measure:"):
			visitors += 1
	if visitors != K.MAX_PENDING_FOREIGN:
		_fail("%d visitor requests arrived beside a full domestic lane, not %d" % [visitors, K.MAX_PENDING_FOREIGN])


## A promise to lift the measure is judged on the measure at its date: lifted, it
## is kept; still standing, it is a lie -- rapport and knowledge fall, and no
## grudge lands on a foreign head.
func _check_a_promise_to_lift_is_judged_on_the_measure() -> void:
	for lifted in [true, false]:
		var state = _game()
		var ns = state.player()
		var head := President.leader_id(state.nations["DEU"])
		var directed := RK.directed_key(PLAYER, "DEU")
		_impose(state, "DEU")
		President.learn(state, ns, _loader, head, 0.6)
		var due := _now(state) + LK.PROMISE_MIN_MONTHS
		if not President.commit(state, ns, _loader, "promise", head, "measure:%s" % directed, due):
			_fail("a promise to the German head was refused")
			return
		if lifted:
			state.measures.erase(directed)
		var r0 := President.rapport(ns, head)
		state.year = floori((due - 1) / 12.0)
		state.month = due - state.year * 12
		var report: Dictionary = Levers.tick_month(state, _loader, METERS)
		var verdict := "kept" if lifted else "broken"
		if (report[verdict] as Array).size() != 1:
			_fail("a promise to lift (lifted %s) was judged %s" % [lifted, report])
		var want := LK.PROMISE_KEPT_RAPPORT if lifted else -LK.LIE_RAPPORT
		if absf(President.rapport(ns, head) - r0 - want) > 0.000001:
			_fail("a promise to lift (lifted %s) moved rapport by %.3f, not %.3f" % [lifted, President.rapport(ns, head) - r0, want])
		if ns.person_grudges.has(head):
			_fail("a broken promise to a foreign head wrote a grudge")


## RECORD 11 (pre-gate B): an org's collective levy sits on the same directed key as
## France's own tariff (Orgs._apply_external_measure writes one per member, tagged
## "org"), but it is the org's to lift, not France's -- so a visitor under it asks
## for nothing. QA's run had every visitor asking about the Climate Accord's levy
## and none about the tariff France imposed itself.
func _check_an_org_levy_brings_no_visitor() -> void:
	var state = _game()
	var head := President.leader_id(state.nations["DEU"])
	_levy(state, "DEU")
	state.met_months[RK.key(PLAYER, "DEU")] = _now(state)
	if _arrived_about(state, head) != "":
		_fail("a visitor asked France to lift an org's levy on their nation")


## The visitor's want is France's OWN measure lifted: with it gone, the promise is
## kept even if an org's levy now stands on the pair -- the order it happens in,
## since an org writes its levy only on a pair that holds no measure.
func _check_a_promise_to_lift_ignores_an_org_levy() -> void:
	var state = _game()
	var ns = state.player()
	var head := President.leader_id(state.nations["DEU"])
	var directed := RK.directed_key(PLAYER, "DEU")
	_impose(state, "DEU")
	President.learn(state, ns, _loader, head, 0.6)
	var due := _now(state) + LK.PROMISE_MIN_MONTHS
	if not President.commit(state, ns, _loader, "promise", head, "measure:%s" % directed, due):
		_fail("a promise to the German head was refused")
		return
	state.measures.erase(directed)
	_levy(state, "DEU")
	state.year = floori((due - 1) / 12.0)
	state.month = due - state.year * 12
	var report: Dictionary = Levers.tick_month(state, _loader, METERS)
	if (report["kept"] as Array).size() != 1:
		_fail("a promise to lift France's own measure, lifted, was not kept under an org's levy: %s" % report)


## A lever on a visitor's request -- pressure by phone, whose spend is a grudge pulse
## and rapport -- moves the head's rapport and writes no grudge or loyalty.
func _check_a_lever_on_a_visitor_writes_no_grudge() -> void:
	var state = _game()
	var ns = state.player()
	var head := President.leader_id(state.nations["DEU"])
	_impose(state, "DEU")
	state.met_months[RK.key(PLAYER, "DEU")] = _now(state)
	Audiences.tick_month(state, _loader, METERS)
	var r: Dictionary = Phone.dial(state, ns, _loader, head, "pressure")
	if not bool(r.get("ok", false)):
		_fail("pressure by phone on a visitor's request was refused: %s" % [r])
		return
	if ns.person_grudges.has(head) or ns.person_loyalty.has(head):
		_fail("a lever on a visitor wrote grudge or loyalty for %s: %s" % [head, r])
	if not President.rapport(ns, head) < 0.0:
		_fail("pressure on a visitor spent no rapport")


## Audiences.invite() puts a request in the lane on the caller's object, under the
## lane's rules: a person of this nation, not twice while one is open, never past
## the cap, never a foreign id.
func _check_invite_is_the_lanes_door() -> void:
	var state = _game()
	var ns = state.player()
	var chief := ""
	for person in _loader.people[PLAYER]:
		if String(person.kind) == "executive":
			chief = person.id
			break
	var r: Dictionary = Audiences.invite(state, ns, _loader, chief, "price:a_project", "want")
	if not bool(r.get("ok", false)) or String(r["request"].get("object", "")) != "price:a_project" \
			or Audiences.request(ns, String(r["request"].get("id", ""))).is_empty():
		_fail("inviting the chief executive %s on a price failed: %s" % [chief, r])
	if bool(Audiences.invite(state, ns, _loader, chief, "price:another", "want").get("ok", true)):
		_fail("a person with a request open was invited again")
	var head := President.leader_id(state.nations["DEU"])
	if bool(Audiences.invite(state, ns, _loader, head, "price:a_project", "want").get("ok", true)):
		_fail("a foreign head was invited into the domestic lane")


# --- Helpers ------------------------------------------------------------------------

## The played nation imposes a tariff on `nation_id` (the measure register's shape).
func _impose(state, nation_id: String) -> void:
	state.measures[RK.directed_key(PLAYER, nation_id)] = {"action_id": "impose_tariffs", "action_name": "Tariffs",
		"kind": "tariff", "severity": 0.625, "since_year": state.year, "since_month": state.month, "retaliated": false}


## The Climate Accord's levy as Orgs._apply_external_measure() writes it.
func _levy(state, nation_id: String) -> void:
	state.measures[RK.directed_key(PLAYER, nation_id)] = {"action_id": "accord_levy", "action_name": "Levy",
		"kind": "tariff", "severity": 0.3, "since_year": state.year, "since_month": state.month,
		"org": "climate_accord", "retaliated": true}


## One tick of the lane; what `pid` asked about, or "".
func _arrived_about(state, pid: String) -> String:
	for row in Audiences.tick_month(state, _loader, METERS)["arrived"]:
		if String(row["person_id"]) == pid:
			return String(row["object"])
	return ""


func _request_of(ns, pid: String) -> String:
	for row in Audiences.pending(ns):
		if String(row["person_id"]) == pid:
			return String(row["id"])
	return ""


func AK_DECLINE() -> float:
	return K.DECLINE_RAPPORT


## person id -> the object they are invited about this month.
func _invited(state, ns) -> Dictionary:
	var out := {}
	for pair in AudienceTriggers.invitations(state, ns, _loader, METERS, _leaders(), _now(state)):
		out[String(pair[0].id)] = String(pair[1]["object"])
	return out


## A France person with a portfolio want that is, or is not, served in this state:
## {id, object}, or {}.
func _office_wanter(ns, served: bool) -> Dictionary:
	for person in _loader.people[PLAYER]:
		if person.id == President.leader_id(ns):
			continue
		for want in person.wants:
			var object := String(want["object"])
			if object.begins_with("office:portfolio:") and Characters.want_served(ns, person, want, METERS, _leaders()) == served:
				return {"id": person.id, "object": object}
	return {}


func _leaders() -> Dictionary:
	var leaders := {}
	for party in _loader.parties[PLAYER]:
		leaders[party.id] = party.leader_person_id
	return leaders


func _game():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 3
	state.day = 1
	return state


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	state.day = 1


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_audience_triggers: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
