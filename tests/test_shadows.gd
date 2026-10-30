extends SceneTree

## V5.2c Task 4. Offers and the corrupt bargain currencies: an executive or a press
## owner may come with money, the president may take it or not, and a bargain may
## pay off the books -- each corrupt act leaving evidence for the exposure machine.
## The plan: .superpowers/sdd/v5.2c-plan.md, Task 4; the spec's currencies table.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Levers = preload("res://src/sim/levers.gd")
const Offers = preload("res://src/sim/offers.gd")
const Phone = preload("res://src/sim/phone.gd")
const President = preload("res://src/sim/president.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const SC = preload("res://src/sim/shadow_constants.gd")

const PLAYER := "FRA"
const METERS := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_offer_only_from_offerer_kinds()
	_check_offer_draw_moves_no_other_draw()
	_check_an_arrived_request_carries_its_offer()
	_check_accept_pays_and_leaves_evidence()
	_check_accept_party_money_pays_the_presidents_party()
	_check_refuse_costs_rapport_only()
	_check_one_offer_per_scene()
	_check_corrupt_currency_raises_odds_and_leaves_evidence()
	_check_the_phone_offers_no_corrupt_currency()
	# Task 6: the affair and the bond rule.
	_check_unmarried_president_no_affair()
	_check_affair_reasons()
	_check_one_affair_proposal_per_audience()
	_check_affair_accrues_evidence_monthly()
	_check_bond_rule_turns_and_recovers()
	_check_affair_never_overwritten_by_the_rule()
	_check_end_affair_can_turn_the_lover()
	_check_a_new_leader_inherits_no_affair()
	_finish()


func _state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	return state


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	state.day = 1


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


## The first request of a fresh game, booked and opened on its day:
## {state, ns, id, pid, session}, or {} with a failure. test_levers' path.
func _booked() -> Dictionary:
	var state = _state()
	var ns = state.player()
	for _m in range(24):
		Audiences.tick_month(state, _loader, METERS)
		var lane: Array[Dictionary] = Audiences.pending(ns)
		if lane.is_empty():
			_advance(state)
			continue
		var id := String(lane[0]["id"])
		_advance(state)
		for d in Audiences.offered_dates(state, ns, id):
			if bool(d["free"]) and bool(Audiences.book(state, ns, _loader, id, d).get("ok", false)):
				state.year = int(d["year"])
				state.month = int(d["month"])
				state.day = int(d["day"])
				var session: Dictionary = Levers.open(state, ns, _loader, id)
				if session.is_empty():
					break
				return {"state": state, "ns": ns, "id": id, "pid": String(lane[0]["person_id"]), "session": session}
		break
	_failures.append("fixture: no audience could be booked and opened")
	return {}


## The request's offer, set by hand: whoever asked, the offer is the fixture's.
func _with_offer(b: Dictionary, currency: String) -> void:
	for row in b["ns"].audience_requests:
		if String(row["id"]) == String(b["id"]):
			row["offer"] = {"currency": currency, "amount_eur_m": SC.OFFER_EUR_M}


func _check_offer_only_from_offerer_kinds() -> void:
	var ns = _state().player()
	var seen := {}
	for person in _loader.people[PLAYER]:
		var kind := String(person.kind)
		for now in range(24300, 24420):
			var offer: Dictionary = Offers.offer_for(ns, person, now)
			if offer.is_empty():
				continue
			if not SC.OFFER_KINDS.has(kind) or not (SC.OFFER_KINDS[kind] as Array).has(String(offer["currency"])):
				_failures.append("a %s offered %s" % [kind, offer])
				return
			if not is_equal_approx(float(offer["amount_eur_m"]), SC.OFFER_EUR_M):
				_failures.append("an offer of %s, not the declared amount" % [offer])
			seen["%s:%s" % [kind, offer["currency"]]] = true
	for kind in SC.OFFER_KINDS:
		for currency in SC.OFFER_KINDS[kind]:
			if not seen.has("%s:%s" % [kind, currency]):
				_failures.append("ten years of draws never had a %s offer %s" % [kind, currency])


## Its own salt: a game drawing every offer every month sees the same request
## stream as one drawing none.
func _check_offer_draw_moves_no_other_draw() -> void:
	var streams: Array[String] = []
	for heavy in [false, true]:
		var state = _state()
		var ns = state.player()
		var stream: Array = []
		for _m in range(36):
			if heavy:
				for person in _loader.people[PLAYER]:
					Offers.offer_for(ns, person, _now(state))
			for row in Audiences.tick_month(state, _loader, METERS).get("arrived", []):
				stream.append([String(row["id"]), int(row["arrived_month"])])
			_advance(state)
		if stream.is_empty():
			_failures.append("fixture: 36 months brought no request")
			return
		streams.append(JSON.stringify(stream))
	if streams[0] != streams[1]:
		_failures.append("drawing offers moved the request stream")


## The offer rides on the request row (Audiences._arrive) and its view; a row from
## before c, with no offer, reads as none (the plan's Review focus 4).
func _check_an_arrived_request_carries_its_offer() -> void:
	var state = _state()
	var ns = state.player()
	var checked := 0
	for _m in range(36):
		for view in Audiences.tick_month(state, _loader, METERS).get("arrived", []):
			var person = _loader.person_by_id[String(view["person_id"])]
			if JSON.stringify(view.get("offer", null)) != JSON.stringify(Offers.offer_for(ns, person, int(view["arrived_month"]))):
				_failures.append("an arrived request's offer %s is not the draw's" % [view.get("offer", null)])
				return
			checked += 1
		_advance(state)
	if checked == 0:
		_failures.append("fixture: no request arrived")
	var row: Dictionary = ns.audience_requests[0]
	row.erase("offer")
	if not Audiences.request(ns, String(row["id"])).get("offer", {}).is_empty():
		_failures.append("a request row with no offer key read as an offer")


func _check_accept_pays_and_leaves_evidence() -> void:
	var b := _booked()
	if b.is_empty():
		return
	var ns = b["ns"]
	_with_offer(b, "personal_wealth")
	var leader := President.leader_id(ns)
	var wealth := President.wealth_eur_m(ns, _loader, leader)
	var attempts := int(b["session"]["attempts_left"])
	if Shadows.offer(ns, b["session"]).is_empty():
		_failures.append("the scene does not see the request's offer")
	var r: Dictionary = Shadows.accept_offer(b["state"], ns, _loader, b["session"])
	if not bool(r.get("ok", false)):
		_failures.append("a legal offer was refused: %s" % [r])
		return
	if not is_equal_approx(President.wealth_eur_m(ns, _loader, leader) - wealth, SC.OFFER_EUR_M):
		_failures.append("accepting did not pay the president the offer")
	if ns.exposure_evidence.size() != 1 or String(ns.exposure_evidence[0]["kind"]) != "personal_wealth" \
			or String(ns.exposure_evidence[0]["person_id"]) != String(b["pid"]) \
			or not is_equal_approx(float(ns.exposure_evidence[0]["size"]), SC.OFFER_EUR_M * SC.EVIDENCE_PER_EUR_M):
		_failures.append("accepting left the wrong evidence: %s" % [ns.exposure_evidence])
	if int(b["session"]["attempts_left"]) != attempts - 1 or String(b["session"]["won"]) == "":
		_failures.append("accepting did not spend an attempt and win the scene: %s" % [b["session"]])
	var grudge := float(ns.person_grudges.get(String(b["pid"]), 0.0))
	var closed: Dictionary = Levers.close(b["state"], ns, _loader, b["session"])
	if String(closed.get("outcome", "")) != AK.STATUS_SETTLED or not (closed.get("price", {}) as Dictionary).is_empty() \
			or float(ns.person_grudges.get(String(b["pid"]), 0.0)) != grudge:
		_failures.append("a bought audience closed as %s, priced %s" % [closed.get("outcome", ""), closed.get("price", {})])


## Party money goes to the governing party (the president's own), never another.
func _check_accept_party_money_pays_the_presidents_party() -> void:
	var b := _booked()
	if b.is_empty():
		return
	var ns = b["ns"]
	_with_offer(b, "party_money")
	var own := String(ns.incumbent_party_id)
	if own == "":
		_failures.append("fixture: the played nation has no governing party")
		return
	var before := {}
	for party in _loader.parties[PLAYER]:
		before[party.id] = President.party_money_eur_m(ns, _loader, party.id)
	if not bool(Shadows.accept_offer(b["state"], ns, _loader, b["session"]).get("ok", false)):
		_failures.append("a party-money offer was refused")
		return
	for party in _loader.parties[PLAYER]:
		var moved := President.party_money_eur_m(ns, _loader, party.id) - float(before[party.id])
		var want := SC.OFFER_EUR_M if party.id == own else 0.0
		if not is_equal_approx(moved, want):
			_failures.append("party %s moved %.2f, not %.2f" % [party.id, moved, want])
	if ns.exposure_evidence.is_empty() or String(ns.exposure_evidence[0]["kind"]) != "party_money":
		_failures.append("a party-money offer left no party-money evidence")


## The visitors' precedent: a refusal costs rapport, never a grudge or loyalty.
func _check_refuse_costs_rapport_only() -> void:
	var b := _booked()
	if b.is_empty():
		return
	var ns = b["ns"]
	var pid := String(b["pid"])
	_with_offer(b, "personal_wealth")
	var rapport := President.rapport(ns, pid)
	var grudges := JSON.stringify(ns.person_grudges)
	var loyalty := JSON.stringify(ns.person_loyalty)
	var attempts := int(b["session"]["attempts_left"])
	if not bool(Shadows.refuse_offer(b["state"], ns, _loader, b["session"]).get("ok", false)):
		_failures.append("refusing an open offer was refused")
		return
	if not is_equal_approx(President.rapport(ns, pid) - rapport, -SC.OFFER_REFUSED_RAPPORT):
		_failures.append("refusing cost %.3f rapport, not the declared %.3f" % [President.rapport(ns, pid) - rapport, -SC.OFFER_REFUSED_RAPPORT])
	if JSON.stringify(ns.person_grudges) != grudges or JSON.stringify(ns.person_loyalty) != loyalty:
		_failures.append("refusing an offer moved a grudge or a loyalty")
	if int(b["session"]["attempts_left"]) != attempts or not ns.exposure_evidence.is_empty():
		_failures.append("refusing an offer spent an attempt or left evidence")
	if not Shadows.offer(ns, b["session"]).is_empty() or bool(Shadows.accept_offer(b["state"], ns, _loader, b["session"]).get("ok", false)):
		_failures.append("a refused offer could still be taken")


func _check_one_offer_per_scene() -> void:
	var b := _booked()
	if b.is_empty():
		return
	var ns = b["ns"]
	for row in ns.audience_requests:
		if String(row["id"]) == String(b["id"]):
			row.erase("offer")
	if bool(Shadows.accept_offer(b["state"], ns, _loader, b["session"]).get("ok", false)) \
			or bool(Shadows.refuse_offer(b["state"], ns, _loader, b["session"]).get("ok", false)):
		_failures.append("a scene with no offer took or refused one")
	_with_offer(b, "personal_wealth")
	Shadows.accept_offer(b["state"], ns, _loader, b["session"])
	var after := JSON.stringify([ns.to_dict(), b["session"]])
	if bool(Shadows.accept_offer(b["state"], ns, _loader, b["session"]).get("ok", false)) \
			or bool(Shadows.refuse_offer(b["state"], ns, _loader, b["session"]).get("ok", false)) \
			or JSON.stringify([ns.to_dict(), b["session"]]) != after:
		_failures.append("one scene answered its offer twice, or a refused second answer wrote")


## Backroom and aid: their odds bonus, the evidence each leaves, on the bargain only.
func _check_corrupt_currency_raises_odds_and_leaves_evidence() -> void:
	if not is_equal_approx(Shadows.odds_bonus("bargain", {"currency": LK.CURRENCY_BACKROOM}), SC.CURRENCY_ODDS[LK.CURRENCY_BACKROOM]) \
			or not is_equal_approx(Shadows.odds_bonus("bargain", {"currency": LK.CURRENCY_AID}), SC.CURRENCY_ODDS[LK.CURRENCY_AID]) \
			or Shadows.odds_bonus("bargain", {"currency": LK.CURRENCY_FAVOUR}) != 0.0 \
			or Shadows.odds_bonus("argue", {"currency": LK.CURRENCY_AID}) != 0.0:
		_failures.append("the odds bonus is not the declared table's")
	for currency in [LK.CURRENCY_BACKROOM, LK.CURRENCY_AID]:
		var b := _booked()
		if b.is_empty():
			return
		var ns = b["ns"]
		var bargain := {}
		for row in Levers.offered(b["state"], ns, _loader, b["session"]):
			if String(row["lever"]) == "bargain":
				bargain = row
		var listed := {}
		for c in bargain.get("currencies", []):
			listed[String(c["currency"])] = c
		if not listed.has(currency) or not bool(listed[currency]["offered"]) \
				or float(listed[currency]["odds_hi"]) < float(bargain["odds_hi"]) - 1e-9:
			_failures.append("the audience's bargain row does not offer %s at its raised odds: %s" % [currency, listed.get(currency, {})])
		var r: Dictionary = Levers.attempt(b["state"], ns, _loader, b["session"], "bargain", {"currency": currency})
		if not bool(r.get("ok", false)):
			_failures.append("a bargain in %s was refused: %s" % [currency, r])
			continue
		if ns.exposure_evidence.size() != 1 or String(ns.exposure_evidence[0]["kind"]) != String(SC.CURRENCY_EVIDENCE[currency]) \
				or String(ns.exposure_evidence[0]["person_id"]) != String(b["pid"]):
			_failures.append("a bargain in %s left the wrong evidence: %s" % [currency, ns.exposure_evidence])


## The plan's Call 8: the phone is the lighter channel -- no bribe down the line.
func _check_the_phone_offers_no_corrupt_currency() -> void:
	var b := _booked()
	if b.is_empty():
		return
	var options: Dictionary = Phone.options(b["state"], b["ns"], _loader, String(b["pid"]))
	for row in options.get("levers", []):
		for c in row.get("currencies", []):
			if SC.CURRENCY_EVIDENCE.has(String(c["currency"])):
				_failures.append("the phone lists the corrupt currency %s" % c["currency"])
	if Levers.arg_error("bargain", {"currency": LK.CURRENCY_AID}, _now(b["state"])) == "" \
			or Levers.arg_error("bargain", {"currency": LK.CURRENCY_BACKROOM}, _now(b["state"]), true) != "":
		_failures.append("arg_error does not keep the corrupt currencies to the audience")


## A person of the played nation the president has a spark with, not the spouse.
func _lover(ns) -> String:
	var leader = _loader.person_by_id[President.leader_id(ns)]
	for person in _loader.people[PLAYER]:
		if person.id != leader.id and person.id != leader.spouse_id and Shadows.spark(ns, String(person.id)):
			return String(person.id)
	return ""


## The plan's Review focus 5: flirting is offered, the affair is not.
func _check_unmarried_president_no_affair() -> void:
	var state = _state()
	var ns = state.player()
	var leader = _loader.person_by_id[President.leader_id(ns)]
	var spouse := String(leader.spouse_id)
	if spouse == "":
		_failures.append("fixture: France's president is unmarried; the spouse content is missing")
		return
	leader.spouse_id = ""
	var pid := _lover(ns)
	President.adjust_rapport(state, ns, _loader, pid, 0.9)
	if Shadows.flirt_why_not(state, ns, _loader, pid) != "" or Shadows.may_begin_affair(state, ns, _loader, pid) != "unmarried" 			or bool(Shadows.begin_affair(state, ns, _loader, pid).get("ok", true)) or President.relationship(ns, pid) == "affair":
		_failures.append("an unmarried president could begin an affair, or could not flirt")
	leader.spouse_id = spouse


func _check_affair_reasons() -> void:
	var state = _state()
	var ns = state.player()
	var spouse := String(_loader.person_by_id[President.leader_id(ns)].spouse_id)
	if Shadows.flirt_why_not(state, ns, _loader, spouse) != "spouse" or Shadows.may_begin_affair(state, ns, _loader, spouse) != "spouse":
		_failures.append("the president's own spouse read as a possible affair")
	var pid := _lover(ns)
	if pid == "":
		_failures.append("fixture: no spark with anyone in France")
		return
	if Shadows.may_begin_affair(state, ns, _loader, pid) != "too_cold":
		_failures.append("an affair with a stranger at rapport 0 read '%s', not too_cold" % Shadows.may_begin_affair(state, ns, _loader, pid))
	President.adjust_rapport(state, ns, _loader, pid, 0.9)
	if Shadows.may_begin_affair(state, ns, _loader, pid) != "":
		_failures.append("a warm spark could not begin an affair: %s" % Shadows.may_begin_affair(state, ns, _loader, pid))
	for person in _loader.people[PLAYER]:
		if person.id != pid and person.id != spouse and person.id != President.leader_id(ns) and not Shadows.spark(ns, String(person.id)):
			President.adjust_rapport(state, ns, _loader, String(person.id), 0.9)
			if Shadows.may_begin_affair(state, ns, _loader, String(person.id)) != "no_spark":
				_failures.append("no spark did not read no_spark")
			break
	if Shadows.may_begin_affair(state, ns, _loader, "nobody") != "not_covered":
		_failures.append("an id the register does not cover read as a possible affair")


## V5.2 close R7 (Interface): one proposal per audience. A refused proposal cannot be
## asked again in the same audience at no cost -- even after a topic warms the person
## past too_cold. The audience's session carries the mark; a new audience (a new
## session) asks afresh, and a call with no session (the probes) keeps no memory.
func _check_one_affair_proposal_per_audience() -> void:
	var state = _state()
	var ns = state.player()
	var pid := _lover(ns)
	var session := {"person_id": pid}
	var first := Shadows.begin_affair(state, ns, _loader, pid, session)
	if bool(first.get("ok", false)) or String(first.get("error", "")) != "too_cold":
		_failures.append("the cold first proposal did not refuse too_cold: %s" % [first])
	President.adjust_rapport(state, ns, _loader, pid, 0.9)
	if Shadows.may_begin_affair(state, ns, _loader, pid, session) != "asked":
		_failures.append("after a refusal the same audience reads '%s', not asked" % Shadows.may_begin_affair(state, ns, _loader, pid, session))
	var second := Shadows.begin_affair(state, ns, _loader, pid, session)
	if bool(second.get("ok", false)) or String(second.get("error", "")) != "asked" or President.relationship(ns, pid) == "affair":
		_failures.append("a second proposal in one audience was not refused 'asked': %s" % [second])
	# A new audience asks afresh; no session keeps no memory.
	if Shadows.may_begin_affair(state, ns, _loader, pid, {"person_id": pid}) != "" or Shadows.may_begin_affair(state, ns, _loader, pid) != "":
		_failures.append("a new audience (or no session) inherited the refusal")
	# A proposal that succeeds reads `already` afterwards, not `asked`.
	var fresh := {"person_id": pid}
	if not bool(Shadows.begin_affair(state, ns, _loader, pid, fresh).get("ok", false)) \
			or Shadows.may_begin_affair(state, ns, _loader, pid, fresh) != "already":
		_failures.append("a begun affair read '%s' in its audience, not already" % Shadows.may_begin_affair(state, ns, _loader, pid, fresh))


func _check_affair_accrues_evidence_monthly() -> void:
	var state = _state()
	var ns = state.player()
	var pid := _lover(ns)
	President.adjust_rapport(state, ns, _loader, pid, 0.9)
	if not bool(Shadows.begin_affair(state, ns, _loader, pid).get("ok", false)) or President.relationship(ns, pid) != "affair":
		_failures.append("a legal affair did not begin")
		return
	for _m in range(3):
		_advance(state)
		Shadows.tick_month(state, _loader)
	if ns.exposure_evidence.size() != 1 or String(ns.exposure_evidence[0]["kind"]) != "affair" 			or not is_equal_approx(float(ns.exposure_evidence[0]["size"]), 3.0 * SC.AFFAIR_EVIDENCE_PER_MONTH):
		_failures.append("three months of an affair left %s" % [ns.exposure_evidence])


## B6's amendment: rival below -0.30 (cold), enemy a rival at the 0.45 grudge, and
## cleared the month the condition fails -- no hysteresis. Three declines from 0 sum
## to -0.30000000000000004 and are still not a rival (the one cut helper).
func _check_bond_rule_turns_and_recovers() -> void:
	var state = _state()
	var ns = state.player()
	var pid := _lover(ns)
	for _i in range(3):
		President.adjust_rapport(state, ns, _loader, pid, -0.1)
	Shadows.tick_month(state, _loader)
	if President.relationship(ns, pid) == "rival":
		_failures.append("three declines (on the cut) made a rival")
	President.adjust_rapport(state, ns, _loader, pid, -0.05)
	Shadows.tick_month(state, _loader)
	if President.relationship(ns, pid) != "rival":
		_failures.append("a cold person is not a rival: %s" % President.relationship(ns, pid))
	ns.person_grudges[pid] = SC.ENEMY_GRUDGE
	Shadows.tick_month(state, _loader)
	if President.relationship(ns, pid) != "enemy":
		_failures.append("a cold person at the leak grudge is not an enemy: %s" % President.relationship(ns, pid))
	ns.person_grudges[pid] = 0.2
	Shadows.tick_month(state, _loader)
	if President.relationship(ns, pid) != "rival":
		_failures.append("an enemy whose grudge fell did not turn back into a rival")
	President.adjust_rapport(state, ns, _loader, pid, 0.2)
	Shadows.tick_month(state, _loader)
	if President.relationship(ns, pid) == "rival" or President.relationship(ns, pid) == "enemy":
		_failures.append("a rival warmed past the cut stayed a rival")


func _check_affair_never_overwritten_by_the_rule() -> void:
	var state = _state()
	var ns = state.player()
	var pid := _lover(ns)
	President.adjust_rapport(state, ns, _loader, pid, 0.9)
	Shadows.begin_affair(state, ns, _loader, pid)
	President.adjust_rapport(state, ns, _loader, pid, -1.8)
	Shadows.tick_month(state, _loader)
	if President.relationship(ns, pid) != "affair":
		_failures.append("the bond rule overwrote an affair: %s" % President.relationship(ns, pid))


## Ending it costs the lover's regard -- enough, from warm, to make a rival who can
## talk (the turned route).
func _check_end_affair_can_turn_the_lover() -> void:
	var state = _state()
	var ns = state.player()
	var pid := _lover(ns)
	President.adjust_rapport(state, ns, _loader, pid, SC.AFFAIR_RAPPORT_MIN + 0.01)
	Shadows.begin_affair(state, ns, _loader, pid)
	var rapport := President.rapport(ns, pid)
	if not bool(Shadows.end_affair(state, ns, _loader, pid).get("ok", false)) 			or not is_equal_approx(President.rapport(ns, pid) - rapport, -SC.AFFAIR_END_RAPPORT):
		_failures.append("ending the affair did not cost AFFAIR_END_RAPPORT")
	if President.relationship(ns, pid) == "affair" or bool(Shadows.end_affair(state, ns, _loader, pid).get("ok", true)):
		_failures.append("an ended affair is still one, or ended twice")
	Shadows.tick_month(state, _loader)
	if President.relationship(ns, pid) != "rival":
		_failures.append("a lover left from just past warm did not turn rival: %s" % President.relationship(ns, pid))



## The parent's call on #170 (review RECORD): person_bond is keyed by person, so an
## affair would outlive its president and accrue as the successor's. It ends at the
## successor's first month instead, and the successor's register gains no row.
func _check_a_new_leader_inherits_no_affair() -> void:
	var state = _state()
	var ns = state.player()
	var pid := _lover(ns)
	President.adjust_rapport(state, ns, _loader, pid, 0.9)
	Shadows.begin_affair(state, ns, _loader, pid)
	for _m in range(2):
		_advance(state)
		Shadows.tick_month(state, _loader)
	var first := President.leader_id(ns)
	if ns.exposure_evidence.size() != 1:
		_failures.append("fixture: two months of an affair left %s" % [ns.exposure_evidence])
		return
	var successor := ""
	for person in _loader.people[PLAYER]:
		if person.id != pid and person.id != first:
			successor = String(person.id)
			break
	ns.head_of_state_person_id = successor
	ns.pm_person_id = successor
	_advance(state)
	Shadows.tick_month(state, _loader)
	if President.relationship(ns, pid) == "affair":
		_failures.append("an affair outlived the president who began it")
	for row in ns.exposure_evidence:
		if President.evidence_leader(ns, row) == successor:
			_failures.append("the successor accrued the predecessor's affair: %s" % [row])
	if ns.exposure_evidence.size() != 1 or not is_equal_approx(float(ns.exposure_evidence[0]["size"]), 2.0 * SC.AFFAIR_EVIDENCE_PER_MONTH):
		_failures.append("the predecessor's row moved: %s" % [ns.exposure_evidence])


func _finish() -> void:
	if _failures.is_empty():
		print("test_shadows: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
