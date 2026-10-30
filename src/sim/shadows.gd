extends RefCounted

## The shadows -- V5.2c: corruption offered and taken. The design is
## docs/design/v5.2-spec.md, "Corruption, in the author's four currencies"; the
## bands are bands-v5.2.md B6 (the evidence) and B5's amendment (the corrupt rows
## priced at their expected cost); every number is in shadow_constants.gd.
##
## Two doors. An OFFER rides on a request (offers.gd draws it as the request
## arrives): in the scene the president takes the money -- paid to themself, or to
## their own party (the governing party), the request served, an attempt spent, evidence left -- or
## refuses it, which costs the offerer's regard and nothing else. A CORRUPT
## CURRENCY pays a bargain off the books: backroom (a person who knows) or aid (a
## diverted budget line) -- better odds, evidence instead of an open spend, and no
## fiscal line (the plan's Call 7: EUR millions against hundreds of billions). The
## audience only: the phone offers neither (Call 8), so Levers asks for them.
##
## THE AFFAIR: a married president and a person they have a spark with (a fixed
## seeded draw per pair) who is close. It accrues `affair` evidence each month it
## lasts; ending it costs the lover's regard, which can turn them. THE BOND RULE
## writes rival and enemy off rapport and the grudge each month (B6's amendment),
## through the one cut helper R11's feeling words also call, never over an affair.
##
## Writes only through the registers' own doors: President (money, evidence,
## rapport) and Audiences (the request agreed). The session is the scene's and is
## never saved, as in Levers.

const Cut = preload("res://src/core/cut.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const SC = preload("res://src/sim/shadow_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const President = preload("res://src/sim/president.gd")


## The scene's open offer: the request's, until the president answers it. {} for
## none -- a request from before V5.2c carries no offer key and reads as none.
static func offer(ns, session: Dictionary) -> Dictionary:
	if session.is_empty() or bool(session.get("offer_answered", false)):
		return {}
	return Audiences.request(ns, String(session.get("request_id", ""))).get("offer", {})


## Take the money: {ok, error, paid: {register: EUR m}, evidence: size}. Refused,
## with nothing written: no open offer, the audience over, the person agreed or no
## attempt left, or no one to pay (party money to a president with no party).
static func accept_offer(state, ns, loader, session: Dictionary) -> Dictionary:
	var refused := {"ok": false, "error": _why_not(ns, session), "paid": {}, "evidence": 0.0}
	if refused["error"] == "" and String(session.get("won", "")) != "":
		refused["error"] = "they have already agreed"
	elif refused["error"] == "" and int(session.get("attempts_left", 0)) <= 0:
		refused["error"] = "no attempts left"
	var pid := String(session.get("person_id", ""))
	if refused["error"] == "" and not President.covers(state, ns, loader, pid):
		refused["error"] = "they are no longer someone the president deals with"
	if refused["error"] != "":
		return refused
	var o := offer(ns, session)
	var currency := String(o.get("currency", ""))
	var amount := float(o.get("amount_eur_m", 0.0))
	var leader := President.leader_id(ns)
	var paid := {}
	if currency == "party_money":
		# The governing party, the one C6's campaigns draw on: the president's own.
		if not President.adjust_party_money_eur_m(ns, loader, String(ns.incumbent_party_id), amount):
			refused["error"] = "the president has no party to pay"
			return refused
		paid["party_money_eur_m"] = amount
	else:
		if not President.adjust_wealth_eur_m(ns, loader, leader, amount):
			refused["error"] = "the president cannot be paid"
			return refused
		paid["wealth_eur_m"] = amount
	var evidence := amount * SC.EVIDENCE_PER_EUR_M
	President.leave_evidence(state, ns, loader, currency, pid, evidence)
	Audiences.agree(ns, String(session["request_id"]), AK.STATUS_SETTLED)
	session["offer_answered"] = true
	session["won"] = "offer"
	session["attempts_left"] = int(session["attempts_left"]) - 1
	(session["attempts"] as Array).append({"lever": "offer", "success": true})
	return {"ok": true, "error": "", "paid": paid, "evidence": evidence}


## Turn the money down: the offerer's regard falls by OFFER_REFUSED_RAPPORT, no
## grudge, no loyalty, no attempt spent. {ok, error, rapport}.
static func refuse_offer(state, ns, loader, session: Dictionary) -> Dictionary:
	var why := _why_not(ns, session)
	if why != "":
		return {"ok": false, "error": why, "rapport": 0.0}
	var pid := String(session["person_id"])
	var before := President.rapport(ns, pid)
	President.adjust_rapport(state, ns, loader, pid, -SC.OFFER_REFUSED_RAPPORT)
	session["offer_answered"] = true
	return {"ok": true, "error": "", "rapport": President.rapport(ns, pid) - before}


## Whether `currency` is one of the corrupt bargain currencies.
static func is_currency(currency: String) -> bool:
	return SC.CURRENCY_EVIDENCE.has(currency)


## What a corrupt currency adds to a lever's odds: a bargain's only.
static func odds_bonus(lever: String, args: Dictionary) -> float:
	if lever != "bargain":
		return 0.0
	return float(SC.CURRENCY_ODDS.get(String(args.get("currency", "")), 0.0))


## The bargain's spend in a corrupt currency: one act of evidence on the person,
## {evidence: size}; {refused} with nothing written when the register refuses it.
static func pay_currency(state, ns, loader, person, currency: String) -> Dictionary:
	if not President.leave_evidence(state, ns, loader, String(SC.CURRENCY_EVIDENCE[currency]), String(person.id), SC.ACT_EVIDENCE):
		return {"refused": true}
	return {"evidence": SC.ACT_EVIDENCE}


## The bargain row's corrupt currencies, each at its raised odds' range (B4's fog,
## re-clamped to the odds' ceiling), for the audience's card.
static func currency_rows(ns, person, p: float, why_not: String, knowledge: float) -> Array:
	var rows := []
	for currency in SC.CURRENCY_EVIDENCE:
		var raised := clampf(p + float(SC.CURRENCY_ODDS[currency]), LK.ODDS_MIN, LK.ODDS_MAX)
		var r := Vector2.ZERO if p < 0.0 else LeverOdds.shown_range(person.id, "bargain", raised, knowledge, ns.draw_seed)
		rows.append({"currency": currency, "offered": why_not == "", "why_not": why_not,
			"spends": {"evidence": SC.ACT_EVIDENCE}, "odds_lo": r.x, "odds_hi": r.y})
	return rows


## The month, the played nation's: each affair accrues its evidence, then the bond
## rule reads every person the president has a rapport with. Before Exposure, so a
## rival made this month can talk this month.
static func tick_month(state, loader) -> void:
	var ns = state.player()
	if ns == null:
		return
	for pid in ns.person_bond.keys():
		if String(ns.person_bond[pid]) != "affair":
			continue
		# person_bond is keyed by person, not by president: an affair whose last row is
		# a predecessor's ends here rather than accruing as the successor's (#170's
		# review). One begun in a predecessor's last month, before its first row, is
		# the edge this cannot see.
		if _affair_leader(ns, String(pid)) != President.leader_id(ns):
			President.set_bond(state, ns, loader, String(pid), "")
			continue
		President.grow_evidence(state, ns, loader, "affair", String(pid), SC.AFFAIR_EVIDENCE_PER_MONTH)
	for pid in ns.person_rapport.keys():
		var bond := String(ns.person_bond.get(pid, ""))
		if bond == "affair":
			continue
		var turned := ""
		if Cut.below(President.rapport(ns, pid), SC.RIVAL_RAPPORT):
			turned = "enemy" if Cut.at_or_above(float(ns.person_grudges.get(pid, 0.0)), SC.ENEMY_GRUDGE) else "rival"
		elif bond != "rival" and bond != "enemy":
			continue
		if turned != bond:
			President.set_bond(state, ns, loader, String(pid), turned)


## Whether there is a spark between the sitting president and the person: one
## seeded draw per pair, at index 0, so flirting again never re-rolls it.
static func spark(ns, pid: String) -> bool:
	var key := Cycle.salted("%s|%s" % [SC.SALT_SPARK, President.leader_id(ns)], ns.draw_seed)
	return Cycle.unit_pair(pid, key, 0) < SC.SPARK_CHANCE


## The flirt topic's gate: "" (offered) or a reason key. An unmarried president may
## flirt -- it is rapport -- but begins no affair (the plan's Review focus 5).
static func flirt_why_not(state, ns, loader, pid: String) -> String:
	if not President.covers(state, ns, loader, pid):
		return "not_covered"
	return "spouse" if pid == _spouse(ns, loader) else ""


## "" or a reason key: not_covered, unmarried, spouse, already, asked, too_cold, no_spark.
## `asked` (V5.2 close R7): this audience's `session` has already carried a proposal --
## one per audience, so a refusal cannot be re-asked for free once a topic has warmed
## the person past too_cold. No session (the probes, a read outside an audience) keeps
## no such memory.
static func may_begin_affair(state, ns, loader, pid: String, session: Dictionary = {}) -> String:
	var why := flirt_why_not(state, ns, loader, pid)
	if why == "not_covered":
		return why
	if _spouse(ns, loader) == "":
		return "unmarried"
	if why != "":
		return why
	if President.relationship(ns, pid) == "affair":
		return "already"
	if bool(session.get("affair_asked", false)):
		return "asked"
	if not Cut.above(President.rapport(ns, pid), SC.AFFAIR_RAPPORT_MIN):
		return "too_cold"
	return "" if spark(ns, pid) else "no_spark"


## {ok, error}: the bond becomes `affair`, refused with may_begin_affair's key. With
## the audience's `session`, the proposal is marked there (`affair_asked`) whatever
## the answer, so the same audience cannot ask twice.
static func begin_affair(state, ns, loader, pid: String, session: Dictionary = {}) -> Dictionary:
	var why := may_begin_affair(state, ns, loader, pid, session)
	if not session.is_empty():
		session["affair_asked"] = true
	if why != "":
		return {"ok": false, "error": why}
	President.set_bond(state, ns, loader, pid, "affair")
	return {"ok": true, "error": ""}


## {ok, error, rapport}: the affair over, the lover's regard down AFFAIR_END_RAPPORT.
## The evidence it left stays, and the bond rule may turn them next month.
static func end_affair(state, ns, loader, pid: String) -> Dictionary:
	if President.relationship(ns, pid) != "affair":
		return {"ok": false, "error": "not_affair", "rapport": 0.0}
	var before := President.rapport(ns, pid)
	President.set_bond(state, ns, loader, pid, "")
	President.adjust_rapport(state, ns, loader, pid, -SC.AFFAIR_END_RAPPORT)
	return {"ok": true, "error": "", "rapport": President.rapport(ns, pid) - before}


## The president an affair's latest row was left by (found or not); the sitting
## one when it has none yet -- an affair begun this month.
static func _affair_leader(ns, pid: String) -> String:
	var who := President.leader_id(ns)
	for row in President.exposures(ns):
		if String(row["kind"]) == "affair" and String(row["person_id"]) == pid:
			who = String(row["leader_id"])
	for row in ns.exposure_evidence:
		if String(row.get("kind", "")) == "affair" and String(row.get("person_id", "")) == pid:
			who = President.evidence_leader(ns, row)
	return who


static func _spouse(ns, loader) -> String:
	var leader = loader.person_by_id.get(President.leader_id(ns))
	return "" if leader == null else String(leader.spouse_id)


## Why the offer cannot be answered now: none open, or the audience is over.
static func _why_not(ns, session: Dictionary) -> String:
	if offer(ns, session).is_empty():
		return "there is no offer on the table"
	var row := Audiences.request(ns, String(session.get("request_id", "")))
	if bool(session.get("closed", true)) or String(row.get("status", "")) != AK.STATUS_HELD:
		return "this audience is over"
	return ""
