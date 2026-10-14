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


## The player asks a member to vote `ask` on the proposal pending in this
## council, and pays in `currency`. One bargain per member per division; every
## refusal is checked BEFORE anything is spent, so a refused bargain costs
## nothing. Returns whether it was struck.
##
## Postings and concessions are refused this block by the author's call
## (2026-10-14): no machine exists to price either, and a currency with no
## price is a free swing.
static func bargain(state, org_id: String, target_id: String, currency: String, ask: String) -> bool:
	if not CouncilK.CURRENCIES.has(currency) or not CouncilK.ASKS.has(ask):
		return false
	if not state.orgs.has(org_id):
		return false
	var register: Dictionary = state.orgs[org_id]
	var pending: Dictionary = register.get("pending", {})
	if pending.is_empty():
		return false
	var ns = state.player()
	if ns == null or not ns.orgs.has(org_id) or target_id == ns.id:
		return false
	var target = state.nations.get(target_id, null)
	if target == null or not target.orgs.has(org_id):
		return false
	# Asking a sponsor to vote for its own proposal buys nothing honest -- it
	# would take the payment for a vote it was always going to cast.
	if String(pending.get("sponsor", "")) == target_id:
		return false
	var bargains: Dictionary = pending.get("bargains", {})
	if bargains.has(target_id):
		return false

	var amount := 0.0
	if currency == CouncilK.CURRENCY_FAVOUR:
		if RK.score(state, ns.id, target_id) < CouncilK.FAVOUR_MIN_RELATIONS:
			return false
		spend_relations(state, ns.id, target_id, CouncilK.FAVOUR_RELATIONS_COST)
		amount = CouncilK.FAVOUR_SWING
	elif currency == CouncilK.CURRENCY_AID:
		var aid: Array = register.get("aid", [])
		aid.append({
			"payer": ns.id, "recipient": target_id,
			"pct_gdp": CouncilK.AID_PCT_GDP, "months_left": CouncilK.AID_MONTHS,
		})
		register["aid"] = aid
		amount = CouncilK.AID_SWING
	elif currency == CouncilK.CURRENCY_VOTE_TRADE:
		var debts: Array = register.get("debts", [])
		# One open IOU per creditor per council: a second promise to the same
		# member before the first is kept is a promise nobody would take.
		for d in debts:
			if String(d.get("debtor", "")) == ns.id and String(d.get("creditor", "")) == target_id:
				return false
		debts.append({
			"debtor": ns.id, "creditor": target_id,
			"made_on": int(pending.get("opened_year", 0)) * 12 + int(pending.get("opened_month", 0)),
			"months_left": CouncilK.IOU_EXPIRY_MONTHS, "awaiting": "",
		})
		register["debts"] = debts
		amount = CouncilK.IOU_SWING

	bargains[target_id] = {"currency": currency, "ask": ask, "swing": amount}
	pending["bargains"] = bargains
	return true


## What this nation pays this org in aid this month, % of GDP. Summed into the
## org's transfer line by orgs.gd -- the budget line that already carries a
## club's money, so aid reaches the deficit through the one writer it has.
static func aid_line(state, nation_id: String, org_id: String) -> float:
	var total := 0.0
	for a in (state.orgs[org_id].get("aid", []) as Array):
		if String(a.get("payer", "")) == nation_id and int(a.get("months_left", 0)) >= 0:
			total += float(a.get("pct_gdp", 0.0))
	return total


## Run BEFORE the month's transfer is read, so the line and the breakdown read
## after the tick see one register. An entry struck with AID_MONTHS is counted
## down to AID_MONTHS-1 on its first tick and still charges at 0; it is pruned
## only when it goes below zero -- paid exactly AID_MONTHS times. (Run AFTER the
## read instead and the last month's breakdown, taken after the prune, no longer
## shows what the line just charged.) An IOU lives IOU_EXPIRY_MONTHS + 1 ticks
## on the same rule: nothing reads its months_left but this prune.
static func tick_register(state, org_id: String) -> void:
	var register: Dictionary = state.orgs[org_id]
	for key in ["aid", "debts"]:
		var entries: Array = register.get(key, [])
		if entries.is_empty():
			continue
		var kept: Array = []
		for e in entries:
			e["months_left"] = int(e.get("months_left", 0)) - 1
			if int(e["months_left"]) >= 0:
				kept.append(e)
		register[key] = kept


## At a division the creditor sponsors, every IOU owed to it comes due. A `for`
## repays it -- unless the division is a treaty going home (`treaty_id` set),
## where a `for` only ARMS the repayment: backing the creditor's treaty at
## council and killing it in your own assembly is the betrayal it looks like
## (author's call, 2026-10-14). Anything else is a betrayal now. A debt struck
## at THIS division's opening is not due in it (keyed by the opening stamp, not
## the proposal id, so a proposal re-opened years later is a new division).
static func settle_debts(state, org_id: String, sponsor_id: String, opened_stamp: int, by_nation: Dictionary, treaty_id := "") -> void:
	if sponsor_id == "":
		return
	var register: Dictionary = state.orgs[org_id]
	var debts: Array = register.get("debts", [])
	if debts.is_empty():
		return
	var kept: Array = []
	for d in debts:
		var debtor := String(d.get("debtor", ""))
		if String(d.get("creditor", "")) != sponsor_id or int(d.get("made_on", -1)) == opened_stamp \
				or not by_nation.has(debtor) or String(d.get("awaiting", "")) != "":
			kept.append(d)
			continue
		if String(by_nation[debtor]) != CouncilK.ASK_FOR:
			spend_relations(state, debtor, sponsor_id, CouncilK.IOU_BETRAYAL)
		elif treaty_id != "":
			d["awaiting"] = treaty_id
			kept.append(d)
	register["debts"] = kept


## A treaty's ratification ended: every IOU awaiting it settles. A debtor that
## killed it at home pays the betrayal; every other awaiting debt is repaid.
static func settle_awaiting(state, org_id: String, treaty_id: String, failing: Array) -> void:
	var register: Dictionary = state.orgs[org_id]
	var debts: Array = register.get("debts", [])
	if debts.is_empty():
		return
	var kept: Array = []
	for d in debts:
		if String(d.get("awaiting", "")) != treaty_id:
			kept.append(d)
			continue
		if failing.has(String(d.get("debtor", ""))):
			spend_relations(state, String(d.get("debtor", "")), String(d.get("creditor", "")), CouncilK.IOU_BETRAYAL)
	register["debts"] = kept


## A treaty everyone else signed, killed at home. The sponsor charges each
## failing member in proportion to how badly it wanted the thing; every other
## member charges a flat bystander's price. Ids sorted -- pricing order must not
## depend on dictionary order even though relations writes commute today.
static func price_failed_treaty(state, loader, org_id: String, sponsor_id: String, failing: Array) -> void:
	if failing.is_empty():
		return
	# The sponsor is the id stored when the division carried; a sponsor that has
	# since left the club has no standing to charge anyone for a treaty of it.
	var sponsor = state.nations.get(sponsor_id, null)
	if sponsor == null or not sponsor.orgs.has(org_id):
		sponsor_id = ""
	var d: float = drive(state, loader, sponsor_id) if sponsor_id != "" else 0.0
	var others: Array = []
	for id in state.nations.keys():
		if state.nations[id].orgs.has(org_id):
			others.append(String(id))
	others.sort()
	for f in failing:
		if sponsor_id != "" and sponsor_id != String(f):
			spend_relations(state, sponsor_id, String(f), CouncilK.RATIFY_FAIL_SPONSOR * d)
		for m in others:
			if m == String(f) or m == sponsor_id:
				continue
			spend_relations(state, m, String(f), CouncilK.RATIFY_FAIL_MEMBER)
