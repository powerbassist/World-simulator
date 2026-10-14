extends RefCounted

## The contested council, V4.5a: who chairs, who sponsors and how hard, and what
## a member's vote is bargained to. Model: docs/orgs-model.md, "V4.5 -- the
## council, contested".
##
## A LEAF beside orgs.gd, not a rewrite of it. orgs.gd keeps membership, the
## tally and adoption and calls in here at four seams (the agenda pick, the
## opening, the division, the register tick). Together the two files are the
## only writers of GameState.orgs; this one writes only the keys the contested
## layer added (pending.lobbied, pending.bargains, register.aid,
## register.debts) and the relations those prices are paid in.
##
## MUST NOT preload orgs.gd: orgs.gd preloads this file. That is why the asks
## are spelled in council_constants.gd and why the agenda's eligibility rule
## stays in orgs.gd, which owns the rules in force it reads.
##
## No RNG, no engine access, no signals -- the council's determinism is pinned
## by tests/test_orgs.gd and nothing here may be the first thing to break it.

const K = preload("res://src/sim/bloc_constants.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const RK = preload("res://src/core/relations.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")


## Who chairs this council this month, or "" for a council with no presidency.
##
## Derived from the calendar, never stored: the term index is whole terms since
## the anchor (posmod, so a date before the anchor runs the rotation backwards
## rather than into a negative index), and a chair who has left the org hands
## the rest of the term to the next member in the order -- the real Council
## re-plans the trio; a game that froze the chair on a non-member would let a
## nation outside the club set its agenda.
static func presiding_nation(state, loader, org_id: String) -> String:
	var org = loader.orgs_by_id.get(org_id, null)
	if org == null or org.presidency.is_empty():
		return ""
	var order: Array = org.presidency["order"]
	var months: int = int(org.presidency["months"])
	var now: int = state.year * 12 + (state.month - 1)
	var term: int = floori(float(now - int(org.presidency["anchor_index"])) / float(months))
	var n: int = order.size()
	for step in n:
		var id := String(order[posmod(term + step, n)])
		var ns = state.nations.get(id, null)
		if ns != null and ns.orgs.has(org_id):
			return id
	return ""


## The decision class a proposal is divided under: its own if authored, its
## org's otherwise. Resolved here rather than at load because a proposal cannot
## see its org while it parses.
static func decision_of(loader, proposal) -> String:
	if proposal.decision != "":
		return proposal.decision
	var org = loader.orgs_by_id.get(proposal.org_id, null)
	return org.decision_rule if org != null else CouncilK.DECISION_QMR


## How hard a nation pushes what it sponsors: its live head of government's
## authored ambition. The SAME person state V4.3's character layer reads -- the
## tier's "no second ambition meter" -- and live, so an election abroad that
## changes the face changes the push.
static func drive(state, loader, nation_id: String) -> float:
	var ns = state.nations.get(nation_id, null)
	if ns == null:
		return CouncilK.SPONSOR_DRIVE_DEFAULT
	var person = loader.person_by_id.get(String(ns.pm_person_id), null)
	if person == null:
		return CouncilK.SPONSOR_DRIVE_DEFAULT
	return clampf(float(person.ambition), 0.0, 1.0)


## The authored sponsor if it is still in the club, else "". A sponsor that
## withdrew cannot push a proposal through a council it left.
static func live_sponsor(state, proposal) -> String:
	if proposal.sponsor == "":
		return ""
	var ns = state.nations.get(proposal.sponsor, null)
	if ns == null or not ns.orgs.has(proposal.org_id):
		return ""
	return proposal.sponsor


## What lobbying and bargaining add to one member's appraisal of the proposal
## pending. Signed by the ask: a bargain for `against` subtracts. Exactly 0.0
## for a pending entry that carries neither key -- the whole of the inertness
## clause on the vote path.
static func swing(pending: Dictionary, nation_id: String) -> float:
	var s: float = float((pending.get("lobbied", {}) as Dictionary).get(nation_id, 0.0))
	var b: Dictionary = (pending.get("bargains", {}) as Dictionary).get(nation_id, {})
	if not b.is_empty():
		var amount: float = float(b.get("swing", 0.0))
		s += amount if String(b.get("ask", "")) == CouncilK.ASK_FOR else -amount
	return s


## Pay `amount` of the a-b relationship, clamped to the readable range. The ONE
## spending path for every V4.5 price in relations, so the clamp and the key
## cannot be done two ways.
static func spend_relations(state, a: String, b: String, amount: float) -> void:
	RK.adjust(state, a, b, -amount, DK.RELATIONS_MIN, DK.RELATIONS_MAX)


## The sponsor works the room at the opening. Every member short of the vote
## threshold by no more than drive x LOBBY_SWING_PER_DRIVE is swung by EXACTLY
## its gap (plus a rounding margin) and the sponsor pays for each in its own
## relations with that member. Over-reach is refused rather than half-paid: a
## swing that cannot turn the member buys nothing, and a sponsor that spent on
## it would be pricing a gesture. Members in id order, so who is lobbied first
## never depends on dictionary order.
##
## `supports` is each AI member's appraisal of the proposal, computed by
## orgs.gd (which owns the appraisal); a human sponsor returns {} -- the player
## bargains by hand through bargain().
static func lobby(state, loader, sponsor_id: String, supports: Dictionary) -> Dictionary:
	var out := {}
	if sponsor_id == "":
		return out
	var sponsor = state.nations.get(sponsor_id, null)
	if sponsor == null or sponsor.has_budget:
		return out
	var cap: float = drive(state, loader, sponsor_id) * CouncilK.LOBBY_SWING_PER_DRIVE
	var ids: Array = supports.keys()
	ids.sort()
	for id in ids:
		if String(id) == sponsor_id:
			continue
		var gap: float = K.SUPPORT_THRESHOLD - float(supports[id])
		if gap <= 0.0:
			continue
		var amount: float = gap + CouncilK.LOBBY_MARGIN
		if amount > cap:
			continue
		spend_relations(state, sponsor_id, String(id), amount * CouncilK.LOBBY_RELATIONS_PER_SWING)
		out[String(id)] = amount
	return out


## The sponsor answers each human member's vote at the division: thanks for a
## for, resentment for an against, nothing for an abstention -- sitting out is
## the cheap way to disappoint, which is what makes it a choice.
static func answer_sponsor(state, loader, sponsor_id: String, by_nation: Dictionary) -> void:
	if sponsor_id == "":
		return
	var d: float = drive(state, loader, sponsor_id)
	var ids: Array = by_nation.keys()
	ids.sort()
	for id in ids:
		if String(id) == sponsor_id:
			continue
		var ns = state.nations.get(String(id), null)
		if ns == null or not ns.has_budget:
			continue
		var vote := String(by_nation[id])
		if vote == CouncilK.ASK_FOR:
			spend_relations(state, String(id), sponsor_id, -CouncilK.SPONSOR_THANKS * d)
		elif vote == CouncilK.ASK_AGAINST:
			spend_relations(state, String(id), sponsor_id, CouncilK.SPONSOR_SNUB * d)
