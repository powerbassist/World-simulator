extends RefCounted

## Law proposal, vote resolution and effect application.
##
## A law's support is read off the same two-axis ideology space
## election_constants.gd's SLOT_POSITION already positions every party on --
## no parallel ideology vocabulary. Vote resolution is a pure function of
## ns.seats_by_party (live, election-updated state) and the law; no rand()
## anywhere, so a vote is exactly reproducible from state, the same discipline
## as economy.gd, budget.gd, opinion.gd and elections.gd.
##
## The model, and the justification for every constant, is
## docs/legislature-model.md.

const LK = preload("res://src/sim/legislature_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const Government = preload("res://src/sim/government.gd")
const GK = preload("res://src/sim/government_constants.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const DK = preload("res://src/sim/discipline_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")


## Reset every nation's legislature state. Runs for all ten, same as
## Opinion.init_nation and Elections.init_nation -- a second playable nation is
## then a data change, not a change here.
static func init_nation(ns) -> void:
	ns.law_structural_offset_pct = 0.0
	ns.law_potential_target_pct = 0.0
	ns.law_other_revenue_pct_gdp = 0.0
	ns.law_bloc_offset = {}
	ns.passed_law_ids = {}
	ns.law_cooldown_months = {}
	ns.last_law_result = {}


## Count down cooldowns. Gated on has_budget, the same flag every other
## opinion-reading system uses -- the other nine nations have no assembly vote
## to resolve at MVP.
static func tick_month(state) -> void:
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		if ns.force_cooldown_months > 0:
			ns.force_cooldown_months -= 1
		var expired: Array = []
		for law_id in ns.law_cooldown_months:
			var remaining: int = int(ns.law_cooldown_months[law_id]) - 1
			if remaining <= 0:
				expired.append(law_id)
			else:
				ns.law_cooldown_months[law_id] = remaining
		for law_id in expired:
			ns.law_cooldown_months.erase(law_id)


## Every law from `all_laws` currently proposable against `ns`: preconditions
## met, not already passed as a once-only law, and not on cooldown.
static func available(ns, all_laws: Array) -> Array:
	var out: Array = []
	for law in all_laws:
		if law.id == "":
			continue
		if law.once and ns.passed_law_ids.has(law.id):
			continue
		if ns.law_cooldown_months.has(law.id):
			continue
		if _preconditions_met(ns, law):
			out.append(law)
	return out


static func _preconditions_met(ns, law) -> bool:
	for cond in law.preconditions:
		var actual: float = _read_field(ns, cond["field"])
		var value: float = cond["value"]
		var ok: bool
		match cond["op"]:
			"<": ok = actual < value
			"<=": ok = actual <= value
			">": ok = actual > value
			">=": ok = actual >= value
			"==": ok = is_equal_approx(actual, value)
			_: ok = false
		if not ok:
			return false
	return true


static func _read_field(ns, field: String) -> float:
	match field:
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"overall_approval_pct": return ns.overall_approval_pct
		"growth_annual_pct": return ns.growth_annual_pct
		"terms_served": return float(ns.terms_served)
		_:
			push_error("legislature: unknown precondition field '%s'" % field)
			return 0.0


## A single party's support for a law, in [-1, +1]. Gaussian falloff on
## ideological distance, same functional form elections.gd:vote_share() uses
## against SLOT_POSITION, with its own (tighter) sigma -- parties are
## disciplined voting blocs, not fuzzy electorates. Plus a bonus for sitting in
## the government whose bill this is.
##
## That bonus used to be a flat GOVERNMENT_BONUS for the single incumbent party.
## It is now earned: government.gd scales it by the party's distance from the
## coalition's agreed position and by how reliably that party delivers its
## seats, so a partner dragged a long way from its own ideology is a less
## dependable vote than the one that wrote the bill. Opposition still gets
## nothing. See docs/government-model.md.
static func support(ns, party, law) -> float:
	return clampf(spatial_support(ns, party, law) + Government.coalition_bonus(ns, party), -1.0, 1.0)


## The same party's view of the same bill with no government whip on it -- the
## purely spatial term, before coalition_bonus(). Split out of support() at V1.1b
## because the gap between the two IS the strain the rebellion split measures,
## and computing it twice in two files would let them drift.
##
## Identical for an opposition party, whose bonus is zero by construction. That
## is why opposition parties never rebel: nothing is pulling their members away
## from where they already stand.
static func spatial_support(ns, party, law) -> float:
	var pos: Dictionary = K.SLOT_POSITION.get(party.ideology_slot, {"economic": 0.0, "social": 0.0})
	var d_econ: float = float(pos["economic"]) - float(law.position["economic"])
	var d_social: float = float(pos["social"]) - float(law.position["social"])
	var dist: float = sqrt(d_econ * d_econ + d_social * d_social)

	return clampf(2.0 * exp(-pow(dist / LK.LAW_SIGMA, 2.0)) - 1.0, -1.0, 1.0)


## How a support score reads as a vote. Named so the forecast in law_panel.gd and
## the real division cannot disagree about where the band sits.
static func vote_of(s: float) -> String:
	if s > LK.ABSTAIN_BAND:
		return "yes"
	if s < -LK.ABSTAIN_BAND:
		return "no"
	return "abstain"


## Vote share -> seats, resolved once against ns.seats_by_party. Does not
## mutate state; propose() below does that after reading the result.
##
## Since V1.1b a party is not one bloc. Its line is support(); its members with
## no whip on them are spatial_support(); where those two read as different votes,
## the share of seats discipline.gd computes goes with the second. `party_votes`
## still names the party's line, and `party_rebels` says how many of its seats
## did not follow it.
static func resolve_vote(ns, party_list: Array, law) -> Dictionary:
	var yes_seats := 0
	var no_seats := 0
	var abstain_seats := 0
	var party_votes := {}
	var party_support := {}
	var party_rebels := {}

	for party in party_list:
		var s: float = support(ns, party, law)
		var own: float = spatial_support(ns, party, law)
		party_support[party.id] = s

		var seats: int = int(ns.seats_by_party.get(party.id, 0))
		var line := vote_of(s)
		var rebel_line := vote_of(own)

		var rebels := 0
		if rebel_line != line:
			rebels = Discipline.rebel_seats(ns, party, s, own)
		if rebels > 0:
			party_rebels[party.id] = rebels

		match line:
			"yes": yes_seats += seats - rebels
			"no": no_seats += seats - rebels
			_: abstain_seats += seats - rebels
		match rebel_line:
			"yes": yes_seats += rebels
			"no": no_seats += rebels
			_: abstain_seats += rebels

		party_votes[party.id] = line

	var seats_total: int = ns.assembly_seats
	var passed: bool
	match law.majority:
		"simple":
			passed = yes_seats > no_seats
		"absolute":
			passed = float(yes_seats) > LK.ABSOLUTE_MAJORITY_FRACTION * float(seats_total)
		"two_thirds":
			passed = float(yes_seats) >= LK.TWO_THIRDS_MAJORITY_FRACTION * float(seats_total)
		_:
			push_error("legislature: unknown majority type '%s'" % law.majority)
			passed = false

	return {
		"law_id": law.id,
		"passed": passed,
		"majority": law.majority,
		"yes_seats": yes_seats,
		"no_seats": no_seats,
		"abstain_seats": abstain_seats,
		"seats_total": seats_total,
		"party_votes": party_votes,
		"party_support": party_support,
		"party_rebels": party_rebels,
	}


## Apply a passed law's effects onto ns. Budget-lever effects are routed through
## Budget.commit() so the demand impulse, the erosion curve and the opinion
## issue all fire exactly as they would for a player-driven budget change --
## the same mechanism, so double-counting is structurally impossible. Every
## other channel is one clamped accumulator, read by an existing formula.
static func apply(state, ns, law) -> void:
	var effects: Dictionary = law.effects

	var pending := {}
	if effects.has("tax_rates_pct"):
		var rates := {}
		for key in effects["tax_rates_pct"]:
			rates[key] = float(ns.tax_rates_pct.get(key, 0.0)) + float(effects["tax_rates_pct"][key])
		pending["tax_rates_pct"] = rates
	if effects.has("spending_pct_gdp"):
		var spending := {}
		for key in effects["spending_pct_gdp"]:
			spending[key] = float(ns.spending_pct_gdp.get(key, 0.0)) + float(effects["spending_pct_gdp"][key])
		pending["spending_pct_gdp"] = spending
	if not pending.is_empty():
		Budget.commit(state, pending)

	if effects.has("structural_unemployment_pct"):
		ns.law_structural_offset_pct = clampf(
			ns.law_structural_offset_pct + float(effects["structural_unemployment_pct"]),
			LK.STRUCTURAL_OFFSET_MIN_PCT, LK.STRUCTURAL_OFFSET_MAX_PCT
		)

	if effects.has("potential_growth_pct"):
		ns.law_potential_target_pct = clampf(
			ns.law_potential_target_pct + float(effects["potential_growth_pct"]),
			LK.POTENTIAL_TARGET_MIN_PCT, LK.POTENTIAL_TARGET_MAX_PCT
		)

	if effects.has("other_revenue_pct_gdp"):
		ns.law_other_revenue_pct_gdp = clampf(
			ns.law_other_revenue_pct_gdp + float(effects["other_revenue_pct_gdp"]),
			LK.OTHER_REVENUE_MIN_PCT, LK.OTHER_REVENUE_MAX_PCT
		)

	if effects.has("bloc_offset"):
		for bloc in effects["bloc_offset"]:
			var current: float = float(ns.law_bloc_offset.get(bloc, 0.0))
			ns.law_bloc_offset[bloc] = clampf(
				current + float(effects["bloc_offset"][bloc]),
				LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX
			)

	if law.once:
		ns.passed_law_ids[law.id] = true


## The player command: resolve the vote, apply effects on passage, set a
## cooldown on failure, and record the result for the law screen to read.
## `loader` is the same DataLoader main.gd already threads through to
## Elections.tick_month() -- parties live in loader.parties, keyed by nation id.
##
## `force` is Article 49.3: the bill is adopted without a vote, and the assembly
## may then censure the government instead. See docs/government-model.md.
static func propose(state, loader, law, force := false) -> Dictionary:
	var ns = state.player()
	var party_list: Array = loader.parties.get(ns.id, [])

	if force:
		return _force(state, ns, party_list, law)

	var result := resolve_vote(ns, party_list, law)
	if result["passed"]:
		apply(state, ns, law)
	elif law.cooldown_months > 0:
		ns.law_cooldown_months[law.id] = law.cooldown_months

	# A whip that failed fails more easily next time, whichever way the bill went.
	# Applied here rather than in resolve_vote(), which stays a pure function of
	# state so the forecast can call it as often as it likes.
	Discipline.penalise_rebellions(ns, result["party_rebels"], _by_id(party_list))

	ns.last_law_result = result
	return result


static func _by_id(party_list: Array) -> Dictionary:
	var by_id := {}
	for party in party_list:
		by_id[party.id] = party
	return by_id


## Article 49.3. The bill is adopted with no vote taken, which is why every seat
## tally below is zero -- there was no division. What the government pays for it
## is a censure motion resolved at FORCE_HOSTILITY_BONUS, and the risk is real
## only for a government that cannot cover the censure threshold.
static func _force(state, ns, party_list: Array, law) -> Dictionary:
	var result := {
		"law_id": law.id,
		"passed": true,
		"forced": true,
		"majority": law.majority,
		"yes_seats": 0,
		"no_seats": 0,
		"abstain_seats": 0,
		"seats_total": ns.assembly_seats,
		"party_votes": {},
		"party_support": {},
		"party_rebels": {},
	}

	if not Government.can_force(ns):
		result["passed"] = false
		result["refused"] = true
		ns.last_law_result = result
		return result

	apply(state, ns, law)
	ns.force_cooldown_months = GK.FORCE_COOLDOWN_MONTHS

	var by_id := _by_id(party_list)

	# Bypassing the assembly costs something whether or not the censure motion
	# carries. Without this, a government that can cover the threshold would
	# force every bill it could not win, for free.
	Government.penalise_blocs(ns, GK.FORCE_BLOC_PENALTY)

	# The second price of the article, and the one paid in the chamber rather
	# than in the polls: a government that goes over its own majority's head
	# finds that majority less willing the next time it asks. Applied before the
	# censure motion resolves, because the insult is the reason for the motion.
	Discipline.penalise(ns, ns.coalition_party_ids, DK.FORCE_DISCIPLINE_PENALTY, by_id)

	# Resolved against the government the bill was forced through for, and
	# before any collapse re-forms it, so the vote reads the coalition that
	# actually did the forcing.
	var censure := Government.resolve_censure(ns, party_list, true)
	Discipline.penalise_rebellions(ns, censure["party_rebels"], by_id)
	if censure["carried"]:
		Government.fall(ns, party_list, censure)
		# Cabinet.seat() is called here rather than from inside government.gd
		# itself -- Cabinet depends on Government (cohesion(), penalise_blocs()),
		# so the reverse would be a preload() cycle. See docs/cabinet-model.md.
		Cabinet.seat(ns, party_list)

	ns.last_censure = censure
	result["censure"] = censure
	ns.last_law_result = result
	return result
