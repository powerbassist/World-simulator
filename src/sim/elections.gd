extends RefCounted

## Monthly election check, vote share, and result attribution.
##
## Runs after Opinion.tick_month and after state.append_history, in the same
## handler main.gd wires the rest of the tick through — see docs/election-model.md
## for why a term boundary is a check inside the existing monthly handler rather
## than a signal of its own.
##
## No engine access, no node references, no signals, and no randomness — the same
## discipline as economy.gd, budget.gd and opinion.gd. A result is exactly
## reproducible from state, which is what tests/test_elections.gd's determinism
## check relies on.

const K = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const ElectoralSystems = preload("res://src/sim/electoral_systems.gd")

const TOP_ISSUE_COUNT := 3


## Seed every nation's election state from its authored schedule and starting
## assembly. Runs for all ten nations, same as Opinion.init_nation — a second
## playable nation is then a data change, not a change here.
##
## `nation` is the Nation this NationState was built from; `party_list` is that
## nation's Array[Party] from DataLoader.parties. `eu` is the loader's EU object.
static func init_nation(ns, nation, party_list: Array, eu) -> void:
	ns.assembly_seats = nation.assembly_seats
	ns.term_months = nation.term_years * 12
	ns.months_in_term = 0

	ns.next_election_year = nation.election_next_year
	ns.next_election_month = nation.election_next_month

	if nation.eu_member:
		ns.next_ep_election_year = eu.next_election_year
		ns.next_ep_election_month = eu.next_election_month

	ns.terms_served = 0
	ns.incumbent_party_id = nation.leader_party_id

	# The starting assembly is real, authored data (party.seat_share), so the
	# initial seats_by_party is that composition allocated onto assembly_seats —
	# reusing the same largest-remainder step pr_national uses on any other
	# vote-share Dictionary, rather than a separate rounding routine.
	var starting_share := {}
	for party in party_list:
		starting_share[party.id] = party.seat_share
	ns.seats_by_party = ElectoralSystems.pr_national(starting_share, ns.assembly_seats, 0.0)

	ns.last_election = {}
	ns.last_ep_election = {}
	ns.in_government = true


## Gated on has_budget, the same flag every other opinion-reading system uses —
## see docs/election-model.md's scope line on why the other nine nations carry a
## real schedule but never resolve it at MVP.
##
## Returns an Array of result Dictionaries — empty on an ordinary month, and
## capable of holding two entries the month a national and an EP election land
## together (France and Belgium, June 2029), which is why this is an Array and
## not a single nullable result.
static func tick_month(state, loader) -> Array:
	var results: Array = []
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		if not ns.in_government:
			continue
		results.append_array(_tick_nation(state, ns, loader))
	return results


static func _tick_nation(state, ns, loader) -> Array:
	var results: Array = []
	ns.months_in_term += 1

	var nation = loader.nations.get(ns.id)
	var party_list: Array = loader.parties.get(ns.id, [])

	if state.year == ns.next_election_year and state.month == ns.next_election_month:
		var result := resolve(ns, party_list, nation.election_system, nation.election_threshold_pct, "national", state.year, state.month)
		ns.seats_by_party = result["seats"]
		ns.last_election = result
		ns.in_government = result["incumbent_largest"]
		if ns.in_government:
			ns.terms_served += 1
			ns.months_in_term = 0
			ns.next_election_year = state.year + int(ns.term_months / 12)
			ns.next_election_month = state.month
		results.append(result)

	if ns.in_government and nation.eu_member:
		if state.year == ns.next_ep_election_year and state.month == ns.next_ep_election_month:
			var ep_result := resolve(ns, party_list, "pr_national", 0.0, "eu_parliament", state.year, state.month, nation.eu_ep_seats)
			ns.last_ep_election = ep_result
			ns.next_ep_election_year = state.year + 5
			ns.next_ep_election_month = state.month
			results.append(ep_result)

	return results


## Bloc-weighted, turnout-weighted, ideology-affinity vote share. Every party in
## `party_list` gets a share in [0, 1], summing to 1.0. See
## docs/election-model.md for the formula and the argument for each term.
static func vote_share(ns, party_list: Array, incumbent_party_id: String) -> Dictionary:
	var totals := {}
	for party in party_list:
		totals[party.id] = 0.0

	var turnout_total := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		turnout_total += float(OpinionK.BLOC_SIZE[bloc]) * float(K.BLOC_TURNOUT[bloc])

	for bloc in OpinionK.BLOC_KEYS:
		var ideal: Dictionary = K.BLOC_IDEAL[bloc]
		var weights := {}
		var weight_total := 0.0

		for party in party_list:
			var pos: Dictionary = K.SLOT_POSITION.get(party.ideology_slot, {"economic": 0.0, "social": 0.0})
			var d_econ: float = float(pos["economic"]) - float(ideal["economic"])
			var d_social: float = float(pos["social"]) - float(ideal["social"])
			var dist: float = sqrt(d_econ * d_econ + d_social * d_social)
			var affinity: float = exp(-pow(dist / K.AFFINITY_SIGMA, 2.0))

			var w: float = float(party.seat_share) * affinity
			if party.id == incumbent_party_id:
				var approval: float = float(ns.bloc_approval.get(bloc, OpinionK.APPROVAL_NEUTRAL))
				var pull: float = clampf((approval - OpinionK.APPROVAL_NEUTRAL) / OpinionK.APPROVAL_NEUTRAL, -1.0, 1.0)
				w *= (1.0 + K.INCUMBENT_SWING * pull)

			weights[party.id] = w
			weight_total += w

		if weight_total <= 0.0:
			continue

		var bloc_weight: float = float(OpinionK.BLOC_SIZE[bloc]) * float(K.BLOC_TURNOUT[bloc])
		for party in party_list:
			totals[party.id] = float(totals[party.id]) + bloc_weight * (float(weights[party.id]) / weight_total)

	var shares := {}
	for party in party_list:
		shares[party.id] = 0.0 if turnout_total <= 0.0 else float(totals[party.id]) / turnout_total
	return shares


## Vote share, seat allocation, win/lose, and attribution — one Dictionary
## describing what happened. `seats` in the returned Dictionary defaults to
## `ns.assembly_seats` for a national election; pass `seat_count` explicitly for
## the EP, whose seat count is the nation's EP delegation, not its assembly.
static func resolve(ns, party_list: Array, system: String, threshold_pct: float, kind: String, year: int, month: int, seat_count: int = -1) -> Dictionary:
	var seats_total: int = ns.assembly_seats if seat_count < 0 else seat_count
	var shares := vote_share(ns, party_list, ns.incumbent_party_id)
	var seats := ElectoralSystems.allocate(system, shares, seats_total, threshold_pct)

	var largest_party := ""
	var largest_seats := -1
	for party_id in seats:
		var s: int = int(seats[party_id])
		if s > largest_seats:
			largest_seats = s
			largest_party = party_id

	return {
		"kind": kind,
		"year": year,
		"month": month,
		"vote_share": shares,
		"seats": seats,
		"seats_total": seats_total,
		"incumbent_party_id": ns.incumbent_party_id,
		"incumbent_seats": int(seats.get(ns.incumbent_party_id, 0)),
		"incumbent_vote_share": float(shares.get(ns.incumbent_party_id, 0.0)),
		"largest_party_id": largest_party,
		"incumbent_largest": largest_party == ns.incumbent_party_id,
		"attribution": attribution(ns),
	}


## The issues that most shaped this result: the most-salient issues at the
## moment of the vote, reusing Opinion's own ranking rather than inventing a
## second one. The panel turns this into prose; this just names the numbers.
static func attribution(ns) -> Array:
	var top: Array = Opinion.top_issues(ns, TOP_ISSUE_COUNT)
	var sat: Dictionary = Opinion.issue_satisfaction(ns)
	var out: Array = []
	for entry in top:
		var issue: String = entry[0]
		out.append({
			"issue": issue,
			"salience": entry[1],
			"satisfaction": float(sat.get(issue, 0.0)),
		})
	return out
