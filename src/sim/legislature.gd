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
	var pos: Dictionary = K.SLOT_POSITION.get(party.ideology_slot, {"economic": 0.0, "social": 0.0})
	var d_econ: float = float(pos["economic"]) - float(law.position["economic"])
	var d_social: float = float(pos["social"]) - float(law.position["social"])
	var dist: float = sqrt(d_econ * d_econ + d_social * d_social)

	var spatial: float = 2.0 * exp(-pow(dist / LK.LAW_SIGMA, 2.0)) - 1.0
	return clampf(spatial + Government.coalition_bonus(ns, party), -1.0, 1.0)


## Vote share -> seats, resolved once against ns.seats_by_party. Does not
## mutate state; propose() below does that after reading the result.
static func resolve_vote(ns, party_list: Array, law) -> Dictionary:
	var yes_seats := 0
	var no_seats := 0
	var abstain_seats := 0
	var party_votes := {}
	var party_support := {}

	for party in party_list:
		var s: float = support(ns, party, law)
		party_support[party.id] = s
		var seats: int = int(ns.seats_by_party.get(party.id, 0))
		if s > LK.ABSTAIN_BAND:
			yes_seats += seats
			party_votes[party.id] = "yes"
		elif s < -LK.ABSTAIN_BAND:
			no_seats += seats
			party_votes[party.id] = "no"
		else:
			abstain_seats += seats
			party_votes[party.id] = "abstain"

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
static func propose(state, loader, law) -> Dictionary:
	var ns = state.player()
	var party_list: Array = loader.parties.get(ns.id, [])

	var result := resolve_vote(ns, party_list, law)
	if result["passed"]:
		apply(state, ns, law)
	elif law.cooldown_months > 0:
		ns.law_cooldown_months[law.id] = law.cooldown_months

	ns.last_law_result = result
	return result
