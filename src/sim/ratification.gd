extends RefCounted

## Ratification at home, V4.5a. Model: docs/orgs-model.md, "V4.5 -- the council,
## contested". The strongest link between the game's two halves, and it costs no
## new machine: a treaty IS a bill. It is built as a Law on the proposal's own
## position and divided through Legislature.resolve_vote() -- the same parties,
## whip, rebellion split and upper chamber every statute meets. A second vote
## resolver for treaties was refused at the plan gate by name.
##
## Its own file because it preloads legislature.gd, which (through budget.gd)
## preloads orgs.gd: orgs.gd preloading this file would close that cycle.
## Nothing in src/sim/ preloads it; the panel (V4.5b) and the tests do.

const Orgs = preload("res://src/sim/orgs.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Law = preload("res://src/core/law.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")


## The treaty as a bill. `simple` majority: a ratification act is an ordinary
## law (Art. 53 in France), not an amendment. Never constitutional here -- a
## treaty needing a revision first (Art. 54) is a content call no shipped
## proposal makes, recorded as a bound.
static func treaty_bill(proposal):
	var t = Law.new()
	t.id = "treaty:" + proposal.id
	t.law_name = proposal.proposal_name
	t.summary = proposal.summary
	t.position = (proposal.position as Dictionary).duplicate()
	t.majority = "simple"
	t.constitutional = false
	return t


## What the player's assembly would do with the treaty this council is
## ratifying, without doing it. Pure: resolve_vote() mutates nothing, which is
## why law_panel.gd can forecast with it as often as it likes.
static func forecast(state, loader, org_id: String) -> Dictionary:
	var proposal = _ratifying_proposal(state, loader, org_id)
	var ns = state.player()
	if proposal == null or ns == null:
		return {"refused": true}
	return Legislature.resolve_vote(ns, loader.parties.get(ns.id, []), treaty_bill(proposal))


## The player puts the treaty to the assembly. Lower chamber first; an upper
## chamber with an ABSOLUTE veto over ordinary law must agree too, a suspensive
## one is overridden (the lower house has the last word on an ordinary act).
## Rebels are priced exactly as for any bill. The outcome goes to
## Orgs.record_ratification(), which adopts or kills the treaty for the club.
static func submit(state, loader, org_id: String) -> Dictionary:
	var proposal = _ratifying_proposal(state, loader, org_id)
	var ns = state.player()
	if proposal == null or ns == null or not ns.has_budget or not ns.orgs.has(org_id):
		return {"refused": true}
	var r: Dictionary = state.orgs[org_id]["ratifying"]
	if String((r.get("nations", {}) as Dictionary).get(ns.id, "")) != CouncilK.RATIFY_PENDING:
		return {"refused": true}

	var party_list: Array = loader.parties.get(ns.id, [])
	var treaty = treaty_bill(proposal)
	var result: Dictionary = Legislature.resolve_vote(ns, party_list, treaty)
	if bool(result["passed"]) and Chambers.power_over(ns, treaty) == ChambersK.VERDICT_ABSOLUTE:
		var upper: Dictionary = Legislature.resolve_upper(ns, party_list, treaty)
		result["upper_passed"] = upper["passed"]
		if not bool(upper["passed"]):
			result["passed"] = false
			result["blocked_by_upper"] = true

	var by_id := {}
	for party in party_list:
		by_id[party.id] = party
	Discipline.penalise_rebellions(ns, result["party_rebels"], by_id)
	Orgs.record_ratification(state, loader, org_id, ns.id, bool(result["passed"]))
	return result


static func _ratifying_proposal(state, loader, org_id: String):
	if not state.orgs.has(org_id):
		return null
	var r: Dictionary = state.orgs[org_id].get("ratifying", {})
	if r.is_empty():
		return null
	return Orgs.proposal_by_id(loader, org_id, String(r.get("proposal_id", "")))
