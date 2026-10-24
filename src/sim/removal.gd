extends RefCounted

## V5.2 b+ R4 -- the price of taking a portfolio from a party. The player's two
## removals cost the same: Dismiss (the holder out at once, the office vacant) and
## a Reassign that takes the office from one party to give it to another. Both pay
## the reshuffle's bloc cost (Cabinet's primitives charge it), the party's loyalty
## through its shortfall (Cabinet.loyalty() reads the seat count, so nothing is
## written for it) and a grudge pulse on the party's CURRENT leader -- none when
## that leader is the president, who may reshuffle their own people with no
## personal grudge. Filling a vacancy takes from nobody and pays only the
## reshuffle. The design and every number: docs/design/v5.2-bplus-spec.md "R4".
##
## WHY A FILE OF ITS OWN: the pulse is Characters' to write, and cabinet.gd cannot
## preload characters.gd (Characters -> Legislature -> Cabinet is a cycle). The
## command lives above both; Cabinet keeps the seat primitives (seat_party,
## vacate), and nothing outside this file and the tests calls them, so no caller
## moves a portfolio without paying for it.
##
## THE ONE WRITER of NationState.portfolio_removed_month (the limit's register).

const Cabinet = preload("res://src/sim/cabinet.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const President = preload("res://src/sim/president.gd")


## Dismiss: the portfolio's holder out at once -- not booked, a dismissal is
## sudden -- and the office vacant until a Reassign. {ok, error, party_id, pulse}.
static func dismiss(state, loader, portfolio: String) -> Dictionary:
	var ns = state.player()
	var why := why_not(state, ns, portfolio, "")
	if why != "":
		return {"ok": false, "error": why}
	var party_id := String(ns.cabinet[portfolio])
	Cabinet.vacate(state, portfolio)
	return _removed(state, ns, loader, portfolio, party_id)


## Reassign: the seat to `party_id`, a removal when it takes the office from
## another party. {ok, error, party_id (the party removed, or ""), pulse}.
static func reassign(state, loader, portfolio: String, party_id: String) -> Dictionary:
	var ns = state.player()
	var why := why_not(state, ns, portfolio, party_id)
	if why != "":
		return {"ok": false, "error": why}
	var from := String(ns.cabinet.get(portfolio, ""))
	Cabinet.seat_party(state, portfolio, party_id, loader.parties.get(ns.id, []))
	if from == "" or from == party_id:
		return {"ok": true, "error": "", "party_id": "", "pulse": 0.0}
	return _removed(state, ns, loader, portfolio, from)


## Why the command would be refused now, or "": `party_id` "" asks for Dismiss.
## The Diary reads it when a Reassign is booked AND on its day, so the booking and
## the act cannot disagree. Words, like Cabinet.refusal_reason() beside it.
static func why_not(state, ns, portfolio: String, party_id: String) -> String:
	if ns == null:
		return "no government"
	if party_id == "":
		if not CK.PORTFOLIO_KEYS.has(portfolio):
			return "no such portfolio"
		if String(ns.cabinet.get(portfolio, "")) == "":
			return "the portfolio is already vacant"
	else:
		var reason := Cabinet.refusal_reason(ns, portfolio, party_id)
		var from := String(ns.cabinet.get(portfolio, ""))
		if reason != "" or from == "" or from == party_id:
			return reason
	var last = ns.portfolio_removed_month.get(portfolio)
	if last != null and _now(state) - int(last) < CK.REMOVAL_LIMIT_MONTHS:
		return "this portfolio changed hands less than a year ago"
	return ""


## The confirmation's price, nothing written: who loses the office, their leader's
## grudge before and after the pulse, and the party's loyalty before and after
## (the shortfall's effect on the next division's rebels). {} for a vacancy.
static func price(state, ns, loader, portfolio: String) -> Dictionary:
	var party = _party(ns, loader, String(ns.cabinet.get(portfolio, "")))
	if party == null:
		return {}
	var leader := _leader(ns, party)
	var before := float(ns.person_grudges.get(leader, 0.0))
	return {
		"party_id": String(party.id),
		"leader_id": leader,
		"grudge_before": before,
		"grudge_after": before + _pulse(ns, loader, leader, false),
		"loyalty_before": Cabinet.loyalty(ns, party),
		"loyalty_after": Cabinet.loyalty(ns, party, 1),
	}


static func _removed(state, ns, loader, portfolio: String, party_id: String) -> Dictionary:
	ns.portfolio_removed_month[portfolio] = _now(state)
	var party = _party(ns, loader, party_id)
	var pulse := 0.0 if party == null else _pulse(ns, loader, _leader(ns, party), true)
	return {"ok": true, "error": "", "party_id": party_id, "pulse": pulse}


## The pulse on `leader`, written when `write`, else only read through the same
## door; 0 for the president, an unknown id or a foreign person.
static func _pulse(ns, loader, leader: String, write: bool) -> float:
	var person = loader.person_by_id.get(leader)
	if person == null or leader == President.leader_id(ns):
		return 0.0
	if write:
		return float(Characters.price_removal(ns, person, CK.REMOVAL_GRUDGE)["grudge"])
	return Characters.refusal_grudge(ns, person, CK.REMOVAL_GRUDGE, 1.0)


## The party's current leader: Characters' own read (the override, else the
## authored edge), so a challenge's new leader takes the pulse.
static func _leader(ns, party) -> String:
	return Characters.party_leader(ns, party.id, {party.id: party.leader_person_id})


static func _party(ns, loader, party_id: String):
	for party in loader.parties.get(ns.id, []):
		if party.id == party_id:
			return party
	return null


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
