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
const Government = preload("res://src/sim/government.gd")

## V1.1e, one direction only: this file tells the second chamber when to renew and
## chambers.gd knows nothing about an election. Elections already reads
## electoral_systems.gd, which chambers.gd also reads, so this adds no new leaf.
const Chambers = preload("res://src/sim/chambers.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
## V1.7a. The ONE edge this file gained, and it is a read: Campaign.turnout_of()
## replaces the raw election_constants.BLOC_TURNOUT lookup in vote_share() below.
## Nothing here calls back into it -- the run-up opens and closes on a level read of
## the clock, so campaign.gd needs no hook at the vote and this file needs no
## knowledge of the window. See docs/campaign-model.md.
const Campaign = preload("res://src/sim/campaign.gd")

const TOP_ISSUE_COUNT := 3


## Seed every nation's election state from its authored schedule and starting
## assembly. Runs for all ten nations, same as Opinion.init_nation — a second
## playable nation is then a data change, not a change here.
##
## `nation` is the Nation this NationState was built from; `party_list` is that
## nation's Array[Party] from DataLoader.parties. `eu` is the loader's EU object.
##
## `seat_share_override` is a start scenario's authored assembly, {party id ->
## share}, merged over the party file's own shares below. Empty for a standard
## start, which is every call but the player's under a scenario. See
## docs/scenario-model.md.
static func init_nation(ns, nation, party_list: Array, eu, seat_share_override: Dictionary = {}) -> void:
	ns.assembly_seats = nation.assembly_seats
	# V1.7c. Lifted from Nation onto NationState, exactly as V1.2b lifted
	# formation_method, censure_rule, dissolution_rule and amendment_rule: an
	# electoral system nobody can change is a constant wearing a data string.
	# Legislature.apply()'s institutional channel is the only other writer.
	ns.election_system = nation.election_system
	ns.election_threshold_pct = nation.election_threshold_pct
	ns.months_in_term = 0

	ns.next_election_year = nation.election_next_year
	ns.next_election_month = nation.election_next_month

	# Two clocks, not one. Where the executive is elected separately — of the
	# ten, only France — term_months is the EXECUTIVE's term, because that is
	# the player's. Where it is not, the executive comes out of the chamber and
	# the two schedules are the same schedule, so the tick below needs no
	# special case. See docs/government-model.md.
	ns.has_executive = nation.has_executive
	if nation.has_executive:
		ns.term_months = nation.executive_term_years * 12
		ns.next_executive_year = nation.executive_next_year
		ns.next_executive_month = nation.executive_next_month
	else:
		ns.term_months = nation.term_years * 12
		ns.next_executive_year = nation.election_next_year
		ns.next_executive_month = nation.election_next_month

	if nation.eu_member:
		ns.next_ep_election_year = eu.next_election_year
		ns.next_ep_election_month = eu.next_election_month

	ns.terms_served = 0
	ns.incumbent_party_id = nation.leader_party_id

	# The starting assembly is real, authored data (party.seat_share), so the
	# initial seats_by_party is that composition allocated onto assembly_seats —
	# reusing the same largest-remainder step pr_national uses on any other
	# vote-share Dictionary, rather than a separate rounding routine.
	#
	# A scenario overrides that composition and nothing else about it: the
	# allocation below is pr_national regardless of the nation's own election
	# system, so an authored assembly needs no per-system branch — GBR's fptp
	# seats itself here exactly as France's two_round does. The loader has
	# already checked the merged shares still sum to 1.0.
	var starting_share := {}
	for party in party_list:
		starting_share[party.id] = party.seat_share
	for party_id in seat_share_override.keys():
		starting_share[party_id] = seat_share_override[party_id]
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

	# A legislative election rewrites the assembly and forces a new government.
	# It does NOT decide whether the player keeps their office — under a
	# separately elected executive it cannot, and the government that comes out
	# of it may exclude the player's own party entirely. That is cohabitation,
	# not defeat.
	if state.year == ns.next_election_year and state.month == ns.next_election_month:
		var result := resolve(ns, party_list, ns.election_system, ns.election_threshold_pct, "national", state.year, state.month)
		ns.seats_by_party = result["seats"]
		ns.last_election = result
		# V1.1e. The second chamber renews PARTLY, and this is the only call site.
		# After the new seats above and before Government.form() below, because
		# Chambers.target_share() is a transform of the assembly the voters just
		# elected -- not one of the ten upper houses is returned by the national
		# electorate, so there is no second vote_share() to compute.
		#
		# THE LAG IS WHAT MAKES IT A CHECK: without it a landslide sweeps both
		# chambers on one day and the upper house agrees by construction, where
		# France's Senat is a check precisely because it survived 2012 and 2017.
		# See docs/upper-house-model.md.
		Chambers.renew(ns, party_list)
		ns.next_election_year = state.year + nation.term_years
		ns.next_election_month = state.month
		# A new assembly is a clean slate: parties barred for censuring the last
		# government are eligible again, because the voters have since spoken.
		ns.censure_barred_party_ids = []

		# The player called this one -- see src/sim/dissolution.gd. The lockout is
		# set HERE, at the resulting election, not at the command: France's rule
		# is one year from the new Assembly, not from the decree.
		result["snap"] = ns.dissolution_pending
		if ns.dissolution_pending:
			ns.dissolution_pending = false
			ns.dissolution_lockout_remaining = ns.dissolution_lockout_months

		result["formation"] = Government.form(ns, party_list)
		# See docs/cabinet-model.md: called here, not from inside government.gd,
		# to avoid a preload() cycle -- Cabinet depends on Government, so
		# Government must never depend on Cabinet.
		Cabinet.seat(ns, party_list)
		results.append(result)

	# The executive verdict. Where the executive is drawn from the chamber this
	# fires in the same month as the legislative election above and reads its
	# result rather than resolving a second vote — one office, one verdict.
	if state.year == ns.next_executive_year and state.month == ns.next_executive_month:
		# A termed-out incumbent does not stand, so no vote is resolved on
		# their behalf -- the run ends here, the same as any other lost
		# office. See docs/political-systems.md.
		if ns.term_limit > 0 and ns.terms_served >= ns.term_limit:
			# V1.6 audit, V1. This used to set the flag and append NOTHING, and the
			# result screen is gated on a non-empty Array -- so the one event that
			# ends a French presidency rendered no screen, no pause and no card, and
			# tick_month() then skipped the nation for good, leaving a clock running
			# with no election able to resolve and nothing anywhere saying why. The
			# comment above already claimed the run ends here "the same as any other
			# lost office"; now it reports itself like one.
			#
			# NOTE what this does NOT do: it resolves no vote. The first attempt
			# called resolve_executive() so the successor race could be shown, and
			# test_balance.gd caught it -- "exactly 2 executive elections before the
			# term limit barred a third" is a stated invariant, and the comment above
			# is the reason for it. A termed-out incumbent does not stand, so there is
			# no verdict to compute; the notice carries resolve_executive()'s key set
			# with the vote emptied, so the panel needs no special case to read it.
			results.append({
				# Its OWN kind, not "executive". A termed-out notice is not an
				# election -- nobody voted -- and test_balance.gd counts results by
				# kind to assert "exactly 2 executive elections before the term limit
				# barred a third". Reusing the kind made that invariant read 3 and
				# turned the check red; the invariant is right and this is not an
				# election, so the kind is what had to change.
				"kind": "termed_out",
				"termed_out": true,
				"year": state.year,
				"month": state.month,
				"vote_share": {},
				"seats": {},
				"seats_total": 0,
				"incumbent_party_id": ns.incumbent_party_id,
				"incumbent_seats": 0,
				"incumbent_vote_share": 0.0,
				"largest_party_id": "",
				"incumbent_largest": false,
				"attribution": [],
			})
			ns.in_government = false
		else:
			var exec_result: Dictionary
			if ns.has_executive:
				exec_result = resolve_executive(ns, party_list, state.year, state.month)
				results.append(exec_result)
			else:
				exec_result = ns.last_election

			# Dispatched on the declared lose_condition, not on has_executive --
			# "never" (a collegial executive) can only be won, and every other
			# nation's office is lost or kept on the same vote has_executive
			# already selected above. See docs/political-systems.md.
			ns.in_government = ns.lose_condition == "never" or bool(exec_result.get("incumbent_largest", false))
			if ns.in_government:
				ns.terms_served += 1
				ns.months_in_term = 0
				ns.next_executive_year = state.year + int(ns.term_months / 12)
				ns.next_executive_month = state.month
				# A re-elected president appoints a government afresh against the
				# assembly they actually have.
				if ns.has_executive:
					Government.form(ns, party_list)
					Cabinet.seat(ns, party_list)

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

	# V1.7a: turnout is no longer the authored constant but the constant as the campaign
	# left it. Campaign.turnout_of() returns K.BLOC_TURNOUT[bloc] BIT-FOR-BIT while the
	# nation has no mobilisation, which is every nation that has not campaigned and every
	# month outside a run-up -- so this is not a change to the model for anyone who does
	# not use the verb, and tests/test_campaign.gd asserts that with exact equality.
	var turnout_total := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		turnout_total += float(OpinionK.BLOC_SIZE[bloc]) * Campaign.turnout_of(ns, bloc)

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

		var bloc_weight: float = float(OpinionK.BLOC_SIZE[bloc]) * Campaign.turnout_of(ns, bloc)
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


## A directly elected executive is not a seat allocation — one office, won on
## the highest vote share. Reuses vote_share() and attribution() unchanged, so
## the presidential verdict is computed from exactly the same opinion state the
## legislative one reads, and returns the same key set so the result screen
## needs no special case beyond its label.
##
## The two-round runoff is not simulated: with no second-preference data there
## is nothing to transfer, and docs/electoral-systems.md already reduces
## France's legislative two-round system to a national-level approximation for
## the same reason. Highest first-round share wins. Ties break by party id, so
## the outcome never depends on roster order.
static func resolve_executive(ns, party_list: Array, year: int, month: int) -> Dictionary:
	var shares := vote_share(ns, party_list, ns.incumbent_party_id)

	var winner := ""
	var best := -1.0
	for party_id in shares:
		var s: float = float(shares[party_id])
		if s > best or (is_equal_approx(s, best) and party_id < winner):
			best = s
			winner = party_id

	return {
		"kind": "executive",
		"year": year,
		"month": month,
		"vote_share": shares,
		"seats": {},
		"seats_total": 0,
		"incumbent_party_id": ns.incumbent_party_id,
		"incumbent_seats": 0,
		"incumbent_vote_share": float(shares.get(ns.incumbent_party_id, 0.0)),
		"largest_party_id": winner,
		"incumbent_largest": winner == ns.incumbent_party_id,
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
