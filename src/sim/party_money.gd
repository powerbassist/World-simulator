extends RefCounted

## V5.2 C6 -- campaigns paid by the party (docs/design/v5.2-c6-party-campaigns.md;
## bands-v5.2.md B9). The author, gate b: "campaign efforts are funded by the state,
## it should be by the party."
##
## Three rules, each the spec's section of the same number:
##   3. Every running effort is paid each month from the governing party's money
##      (`ns.incumbent_party_id`), CHEAPER FIRST, ties by effort id. One the chest
##      cannot pay stops. Cheaper first because then the dearer effort is the one a
##      short chest stops, which a player can predict, and a short chest buys the most
##      months of effort (the first draft paid in id order and let an alphabetically
##      earlier, dearer effort starve a cheaper one).
##   4. The window's spend past the nation's legal ceiling is allowed (soft) and
##      leaves the evidence a party-money donation of the same size leaves.
##   5-6. Every party of the played nation draws a twelfth of its yearly public
##      funding each month, less running costs equal to its funding at the game's
##      start. The net is therefore EXACTLY zero until a legislative election moves
##      a share, which is what keeps every regime that runs no campaign identical.
##
## Writes party money, the window's spend and evidence -- never the campaign
## register: campaign.gd is that register's single writer, so pay() RETURNS the
## efforts it could not pay and Campaign.tick_month() stops them.
##
## A LEAF: president.gd and constants only (tests/test_party_money.gd pins it).
## campaign.gd preloads this file and elections.gd preloads campaign.gd, so a reach
## into characters.gd (which preloads government and legislature) would close a
## cycle. That is why the party leader is read here off the register rather than
## through Characters.party_leader(), whose rule it repeats in one line.

const President = preload("res://src/sim/president.gd")
const SC = preload("res://src/sim/shadow_constants.gd")


## EUR m a month for one effort, from its authored terms and the nation's population.
static func price_eur_m(ns, terms: Dictionary) -> float:
	return float(terms.get("cost_eur_per_k_pop_month", 0.0)) * float(ns.population) / 1.0e9


## The payer's money: the governing party's.
static func money_eur_m(ns, loader) -> float:
	return President.party_money_eur_m(ns, loader, String(ns.incumbent_party_id))


## EUR m a year of public funding for `party_id`: the vote pot by its vote share plus
## the seat pot by its seat share, nothing when `opposition_only` and the party is in
## government. `now` false is the game's START, the running costs: both shares the
## authored `seat_share` (not seats_by_party, whose whole seats would make the net a
## few thousand euros instead of zero) and the authored leader's party in government.
## `now` true reads the last legislative election, and before one IS the start.
static func funding_eur_m_year(ns, loader, party_id: String, now: bool) -> float:
	var pots: Dictionary = loader.party_funding.get(ns.id, {})
	var party = _party(ns, loader, party_id)
	if pots.is_empty() or party == null:
		return 0.0
	var vote_share: float = party.seat_share
	var seat_share: float = party.seat_share
	var ruling: Array = [String(loader.nations[ns.id].leader_party_id)]
	if now and not ns.last_election.is_empty():
		vote_share = float(ns.last_election.get("vote_share", {}).get(party_id, 0.0))
		seat_share = float(ns.seats_by_party.get(party_id, 0)) / float(maxi(1, ns.assembly_seats))
		ruling = ns.coalition_party_ids
	if bool(pots["opposition_only"]) and ruling.has(party_id):
		return 0.0
	return float(pots["vote_pot_eur_m_year"]) * vote_share + float(pots["seat_pot_eur_m_year"]) * seat_share


## The party's purse for the panel: funding a year now, running costs (the funding at
## the start) and the net between them.
static func purse(ns, loader, party_id: String) -> Dictionary:
	var funding := funding_eur_m_year(ns, loader, party_id, true)
	var running := funding_eur_m_year(ns, loader, party_id, false)
	return {"funding": funding, "running": running, "net": funding - running}


## One month of public funding less running costs, for every party of `ns` -- the
## played nation's (Campaign.tick_month() calls it for that one). A zero net writes
## nothing, so a party no election has touched carries no register entry at all.
static func tick_month(ns, loader) -> void:
	for party in loader.parties.get(ns.id, []):
		var net := (funding_eur_m_year(ns, loader, party.id, true) - funding_eur_m_year(ns, loader, party.id, false)) / 12.0
		if net != 0.0:
			President.adjust_party_money_eur_m(ns, loader, party.id, net)


## Pays the month of every running effort, cheaper first (see the header), and
## returns the ids of those the chest could not pay. Paying before the accrual is what
## makes a stopped effort accrue nothing for the month it was not paid.
static func pay(state, ns, loader, terms_by_effort: Dictionary) -> Array:
	var stopped: Array = []
	if ns.campaign_running.is_empty():
		return stopped
	var order: Array = []
	for eid in ns.campaign_running:
		order.append({"id": String(eid), "price": price_eur_m(ns, terms_by_effort.get(String(eid), {}))})
	order.sort_custom(func(a, b): return a["price"] < b["price"] or (a["price"] == b["price"] and a["id"] < b["id"]))
	for row in order:
		if money_eur_m(ns, loader) < float(row["price"]):
			stopped.append(row["id"])
			continue
		President.adjust_party_money_eur_m(ns, loader, String(ns.incumbent_party_id), -float(row["price"]))
		_spend(state, ns, loader, float(row["price"]))
	return stopped


## The nation's legal ceiling on one window's spend, EUR m; negative when it sets none.
static func ceiling_eur_m(ns, loader) -> float:
	return float(loader.party_funding.get(ns.id, {}).get("cap_eur_m", -1.0))


## What is left under the ceiling this window, EUR m: negative is spent past it, the
## amount the auditors can find. INF when the nation sets no ceiling.
static func ceiling_room_eur_m(ns, loader) -> float:
	var cap := ceiling_eur_m(ns, loader)
	return INF if cap < 0.0 else cap - float(ns.campaign_spent_eur_m)


## The window's spend grows by `amount`; the part of it past the ceiling leaves
## party-money evidence at a donation's own rate (SC.EVIDENCE_PER_EUR_M, accept_offer's
## formula), so overspending EUR 10 m is as exposed as taking EUR 10 m. One row per
## person, grown (Gameplay, 2026-10-25).
static func _spend(state, ns, loader, amount: float) -> void:
	var before: float = ns.campaign_spent_eur_m
	ns.campaign_spent_eur_m = before + amount
	var cap := ceiling_eur_m(ns, loader)
	var over: float = ns.campaign_spent_eur_m - maxf(before, cap)
	if cap >= 0.0 and over > 0.0:
		President.grow_evidence(state, ns, loader, "party_money", _bagman(state, ns, loader), over * SC.EVIDENCE_PER_EUR_M)


## Who the overspend's evidence names (Gameplay, 2026-10-25): the payer party's leader,
## or, when that is the president (or someone the register does not cover), the
## party's first covered politician in authored order. "" when there is none, and
## grow_evidence() then writes nothing.
static func _bagman(state, ns, loader) -> String:
	var pid := String(ns.incumbent_party_id)
	var party = _party(ns, loader, pid)
	if party == null:
		return ""
	var leader := String(ns.party_leader_override.get(pid, party.leader_person_id))
	if President.covers(state, ns, loader, leader):
		return leader
	for person in loader.people.get(ns.id, []):
		if person.kind == "politician" and String(ns.person_party_override.get(person.id, person.party_id)) == pid \
				and President.covers(state, ns, loader, String(person.id)):
			return String(person.id)
	return ""


static func _party(ns, loader, party_id: String):
	for party in loader.parties.get(ns.id, []):
		if party.id == party_id:
			return party
	return null
