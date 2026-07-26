extends RefCounted

## Live per-nation simulation state. Plain data — no engine dependency, no node
## references, no signals. Built at new-game by copying starting values out of a
## Nation (static data), then mutated every simulated month by src/sim/.
##
## The static Nation object still says what unemployment was at game start; this
## says what it is now. See docs/data-architecture.md.
##
## Later sessions add their own fields here — S5 opinion, S6 election state —
## the same way the nation schema is grown.

const C = preload("res://src/sim/economy_constants.gd")

var id: String = ""

# --- Economy -----------------------------------------------------------------

var sector_output := {}  # String -> float, EUR bn. Sums to gdp_eur_bn exactly.
var gdp_eur_bn: float = 0.0
var potential_gdp_eur_bn: float = 0.0

var trend_annual_pct: float = 0.0
var growth_annual_pct: float = 0.0

var unemployment_pct: float = 0.0
var structural_unemployment_pct: float = 0.0
var start_unemployment_pct: float = 0.0

var population: float = 0.0

# --- Policy ------------------------------------------------------------------

## Only the player's nation has a budget. The other nine carry these fields
## unchanged from their starting values so one code path serves both.
var has_budget: bool = false

var tax_rates_pct := {}          # income, corporate, vat
var spending_pct_gdp := {}       # health, education, defence, pensions, infrastructure
var start_tax_rates_pct := {}
var start_spending_pct_gdp := {}
var other_spending_pct_gdp: float = 0.0

## Calibration residual, fixed at new-game so starting revenue equals the
## nation's authored fiscal.tax_revenue_pct_gdp. Social contributions, local
## taxes, everything the player has no slider for.
var other_revenue_pct_gdp: float = 0.0

# --- Fiscal results, recomputed every month ----------------------------------

var revenue_pct_gdp := {}        # income, corporate, vat, other
var total_revenue_pct_gdp: float = 0.0
var total_spending_pct_gdp: float = 0.0
var debt_service_pct_gdp: float = 0.0
var deficit_pct_gdp: float = 0.0
var debt_eur_bn: float = 0.0

## The deficit at new-game. The opinion model's public_finances issue is measured
## against this, so a fresh game starts on exactly neutral.
var start_deficit_pct_gdp: float = 0.0

# --- Opinion -----------------------------------------------------------------

## String bloc id -> approval, 0-100. Keys come from opinion_constants.BLOC_KEYS
## and appear nowhere else, so the set of blocs is one table's business.
var bloc_approval := {}

## Bloc approval weighted by bloc size. The headline number.
var overall_approval_pct: float = 0.0

## String issue id -> how much the electorate currently cares, summing to 1.0.
var issue_salience := {}

# --- Impulses ----------------------------------------------------------------

## Short-run demand shock from a committed budget change. Decays geometrically.
var demand_impulse_pct: float = 0.0

## Long-run shift to trend growth from infrastructure, education and corporate
## tax. Hard-clamped; this is the only feedback into trend.
var potential_shift_pct: float = 0.0

## External demand from neighbours, recomputed each month.
var external_impulse_pct: float = 0.0

## GDP-weighted neighbour growth at new-game, the zero point for the term above.
var trade_baseline_pct: float = 0.0

# --- Elections -----------------------------------------------------------------

## Copied from Nation at new-game; the assembly's size never changes mid-game.
var assembly_seats: int = 0

## term_years * 12, from Nation.government.term_years. months_in_term counts up
## from the term the player inherits at new-game — see docs/election-model.md on
## why that term is usually shorter than a full one.
var term_months: int = 0
var months_in_term: int = 0

## The nation's real, authored election date until the first one fires; reset to
## exactly term_months later after every national election. See
## docs/electoral-systems.md for where these numbers come from.
var next_election_year: int = 0
var next_election_month: int = 0

## Mirrors data/eu_parliament.json's schedule until the first EP election fires,
## then advances five years. Zero for a non-member — same "field exists, tick
## does nothing" shape has_budget uses elsewhere.
var next_ep_election_year: int = 0
var next_ep_election_month: int = 0

var terms_served: int = 0

## String party id -> seats, from the most recent national election. Empty
## until the first one resolves.
var incumbent_party_id: String = ""
var seats_by_party := {}

## The full result of the most recent national and EP elections — vote share,
## seats, turnout and attribution, everything the result screen reads. See
## src/sim/elections.gd. Empty {} until the first one of each kind fires.
var last_election := {}
var last_ep_election := {}

## False the moment the incumbent loses an EXECUTIVE election. Gates the clock:
## main.gd stops advancing time once this is false. A legislative election can
## take the player's majority away but never their office — see
## docs/government-model.md. Only the player's nation has a meaningful reading.
var in_government: bool = true

## The executive's own schedule, present only where the head of government is
## elected separately from the assembly — of the ten, only France. When absent
## the executive term IS the legislative term and these mirror it, so the tick
## has one code path rather than two.
var has_executive: bool = false
var next_executive_year: int = 0
var next_executive_month: int = 0

# --- Government ------------------------------------------------------------------

## Copied from Nation at new-game; how this nation assembles a government and
## what it takes to bring one down. Dispatched on in src/sim/government.gd,
## never branched on the nation id.
var formation_method: String = ""
var censure_rule: String = ""
var head_of_government_title: String = ""

## The head of government holding office at game start. Reused whenever the
## premiership returns to the executive's own party, because in a
## semi-presidential system that party's authored leader is the President, not
## the Prime Minister.
var start_head_of_government_name: String = ""

## The live government: which parties are in it, how many seats they carry
## between them, and the seat-weighted mean of their ideology positions. That
## position is the government's agreed line, and legislature.gd reads it.
var coalition_party_ids: Array = []
var coalition_seats: int = 0
var coalition_position := {"economic": 0.0, "social": 0.0}

var pm_party_id: String = ""
var pm_name: String = ""

## True when the assembly majority is a bloc that excludes the executive's own
## party — the player keeps the office and loses the legislature.
var is_cohabitation: bool = false

## True when the government holds at most half the chamber. A legal outcome,
## not a failure: it governs until it is censured.
var is_minority: bool = false

## The full description of the most recent formation, for the government screen
## to read. Same shape src/sim/government.gd:form() returns.
var last_formation := {}

# --- Legislature ---------------------------------------------------------------

## Accumulated across every passed law, each clamped in legislature_constants.gd.
## Read once each tick by economy.gd/budget.gd/opinion.gd, alongside the terms
## those formulas already compute -- one added term each, no new equation. See
## docs/legislature-model.md.
var law_structural_offset_pct: float = 0.0
var law_potential_target_pct: float = 0.0
var law_other_revenue_pct_gdp: float = 0.0

## String bloc id -> accumulated offset, summed into that bloc's approval
## *target* in opinion.gd, not into approval directly -- inertia and every bound
## still apply. For laws with no budget footprint and so no matching issue.
var law_bloc_offset := {}

## String law id -> true. A law with `once = true` that has passed can never be
## proposed again; a law that failed and has `cooldown_months > 0` goes in
## law_cooldown_months instead, not here.
var passed_law_ids := {}

## String law id -> months remaining before it can be proposed again, counting
## down every tick. Set on a failed vote; absent once it reaches zero.
var law_cooldown_months := {}

## The most recent law vote, for the law screen to read after proposing. Empty
## until the first one resolves. Same shape as Elections.resolve()'s result.
var last_law_result := {}


## Deep copy. The budget projection runs the real simulation forward on a copy,
## so every mutable field — every Dictionary — must be duplicated, not shared.
func duplicate_state():
	var s = new()
	s.id = id

	s.sector_output = sector_output.duplicate(true)
	s.gdp_eur_bn = gdp_eur_bn
	s.potential_gdp_eur_bn = potential_gdp_eur_bn
	s.trend_annual_pct = trend_annual_pct
	s.growth_annual_pct = growth_annual_pct
	s.unemployment_pct = unemployment_pct
	s.structural_unemployment_pct = structural_unemployment_pct
	s.start_unemployment_pct = start_unemployment_pct
	s.population = population

	s.has_budget = has_budget
	s.tax_rates_pct = tax_rates_pct.duplicate(true)
	s.spending_pct_gdp = spending_pct_gdp.duplicate(true)
	s.start_tax_rates_pct = start_tax_rates_pct.duplicate(true)
	s.start_spending_pct_gdp = start_spending_pct_gdp.duplicate(true)
	s.other_spending_pct_gdp = other_spending_pct_gdp
	s.other_revenue_pct_gdp = other_revenue_pct_gdp

	s.revenue_pct_gdp = revenue_pct_gdp.duplicate(true)
	s.total_revenue_pct_gdp = total_revenue_pct_gdp
	s.total_spending_pct_gdp = total_spending_pct_gdp
	s.debt_service_pct_gdp = debt_service_pct_gdp
	s.deficit_pct_gdp = deficit_pct_gdp
	s.debt_eur_bn = debt_eur_bn
	s.start_deficit_pct_gdp = start_deficit_pct_gdp

	s.bloc_approval = bloc_approval.duplicate(true)
	s.overall_approval_pct = overall_approval_pct
	s.issue_salience = issue_salience.duplicate(true)

	s.demand_impulse_pct = demand_impulse_pct
	s.potential_shift_pct = potential_shift_pct
	s.external_impulse_pct = external_impulse_pct
	s.trade_baseline_pct = trade_baseline_pct

	s.assembly_seats = assembly_seats
	s.term_months = term_months
	s.months_in_term = months_in_term
	s.next_election_year = next_election_year
	s.next_election_month = next_election_month
	s.next_ep_election_year = next_ep_election_year
	s.next_ep_election_month = next_ep_election_month
	s.terms_served = terms_served
	s.incumbent_party_id = incumbent_party_id
	s.seats_by_party = seats_by_party.duplicate(true)
	s.last_election = last_election.duplicate(true)
	s.last_ep_election = last_ep_election.duplicate(true)
	s.in_government = in_government
	s.has_executive = has_executive
	s.next_executive_year = next_executive_year
	s.next_executive_month = next_executive_month

	s.formation_method = formation_method
	s.censure_rule = censure_rule
	s.head_of_government_title = head_of_government_title
	s.start_head_of_government_name = start_head_of_government_name
	s.coalition_party_ids = coalition_party_ids.duplicate(true)
	s.coalition_seats = coalition_seats
	s.coalition_position = coalition_position.duplicate(true)
	s.pm_party_id = pm_party_id
	s.pm_name = pm_name
	s.is_cohabitation = is_cohabitation
	s.is_minority = is_minority
	s.last_formation = last_formation.duplicate(true)

	s.law_structural_offset_pct = law_structural_offset_pct
	s.law_potential_target_pct = law_potential_target_pct
	s.law_other_revenue_pct_gdp = law_other_revenue_pct_gdp
	s.law_bloc_offset = law_bloc_offset.duplicate(true)
	s.passed_law_ids = passed_law_ids.duplicate(true)
	s.law_cooldown_months = law_cooldown_months.duplicate(true)
	s.last_law_result = last_law_result.duplicate(true)

	return s


## Serialise to a plain Dictionary (JSON-safe: String/float/int/bool/Array/
## Dictionary only). Same field set as duplicate_state(), in the same order,
## so the two stay easy to compare when a field is added. See
## docs/data-architecture.md Persistence.
func to_dict() -> Dictionary:
	return {
		"id": id,

		"sector_output": sector_output,
		"gdp_eur_bn": gdp_eur_bn,
		"potential_gdp_eur_bn": potential_gdp_eur_bn,
		"trend_annual_pct": trend_annual_pct,
		"growth_annual_pct": growth_annual_pct,
		"unemployment_pct": unemployment_pct,
		"structural_unemployment_pct": structural_unemployment_pct,
		"start_unemployment_pct": start_unemployment_pct,
		"population": population,

		"has_budget": has_budget,
		"tax_rates_pct": tax_rates_pct,
		"spending_pct_gdp": spending_pct_gdp,
		"start_tax_rates_pct": start_tax_rates_pct,
		"start_spending_pct_gdp": start_spending_pct_gdp,
		"other_spending_pct_gdp": other_spending_pct_gdp,
		"other_revenue_pct_gdp": other_revenue_pct_gdp,

		"revenue_pct_gdp": revenue_pct_gdp,
		"total_revenue_pct_gdp": total_revenue_pct_gdp,
		"total_spending_pct_gdp": total_spending_pct_gdp,
		"debt_service_pct_gdp": debt_service_pct_gdp,
		"deficit_pct_gdp": deficit_pct_gdp,
		"debt_eur_bn": debt_eur_bn,
		"start_deficit_pct_gdp": start_deficit_pct_gdp,

		"bloc_approval": bloc_approval,
		"overall_approval_pct": overall_approval_pct,
		"issue_salience": issue_salience,

		"demand_impulse_pct": demand_impulse_pct,
		"potential_shift_pct": potential_shift_pct,
		"external_impulse_pct": external_impulse_pct,
		"trade_baseline_pct": trade_baseline_pct,

		"assembly_seats": assembly_seats,
		"term_months": term_months,
		"months_in_term": months_in_term,
		"next_election_year": next_election_year,
		"next_election_month": next_election_month,
		"next_ep_election_year": next_ep_election_year,
		"next_ep_election_month": next_ep_election_month,
		"terms_served": terms_served,
		"incumbent_party_id": incumbent_party_id,
		"seats_by_party": seats_by_party,
		"last_election": last_election,
		"last_ep_election": last_ep_election,
		"in_government": in_government,
		"has_executive": has_executive,
		"next_executive_year": next_executive_year,
		"next_executive_month": next_executive_month,

		"formation_method": formation_method,
		"censure_rule": censure_rule,
		"head_of_government_title": head_of_government_title,
		"start_head_of_government_name": start_head_of_government_name,
		"coalition_party_ids": coalition_party_ids,
		"coalition_seats": coalition_seats,
		"coalition_position": coalition_position,
		"pm_party_id": pm_party_id,
		"pm_name": pm_name,
		"is_cohabitation": is_cohabitation,
		"is_minority": is_minority,
		"last_formation": last_formation,

		"law_structural_offset_pct": law_structural_offset_pct,
		"law_potential_target_pct": law_potential_target_pct,
		"law_other_revenue_pct_gdp": law_other_revenue_pct_gdp,
		"law_bloc_offset": law_bloc_offset,
		"passed_law_ids": passed_law_ids,
		"law_cooldown_months": law_cooldown_months,
		"last_law_result": last_law_result,
	}


## Inverse of to_dict(). Every Dictionary/Array comes from JSON.parse_string(),
## already fresh and unshared, so no .duplicate() is needed here the way
## duplicate_state() needs one.
static func from_dict(d: Dictionary):
	var s = new()
	s.id = d.get("id", "")

	s.sector_output = d.get("sector_output", {})
	s.gdp_eur_bn = d.get("gdp_eur_bn", 0.0)
	s.potential_gdp_eur_bn = d.get("potential_gdp_eur_bn", 0.0)
	s.trend_annual_pct = d.get("trend_annual_pct", 0.0)
	s.growth_annual_pct = d.get("growth_annual_pct", 0.0)
	s.unemployment_pct = d.get("unemployment_pct", 0.0)
	s.structural_unemployment_pct = d.get("structural_unemployment_pct", 0.0)
	s.start_unemployment_pct = d.get("start_unemployment_pct", 0.0)
	s.population = d.get("population", 0.0)

	s.has_budget = d.get("has_budget", false)
	s.tax_rates_pct = d.get("tax_rates_pct", {})
	s.spending_pct_gdp = d.get("spending_pct_gdp", {})
	s.start_tax_rates_pct = d.get("start_tax_rates_pct", {})
	s.start_spending_pct_gdp = d.get("start_spending_pct_gdp", {})
	s.other_spending_pct_gdp = d.get("other_spending_pct_gdp", 0.0)
	s.other_revenue_pct_gdp = d.get("other_revenue_pct_gdp", 0.0)

	s.revenue_pct_gdp = d.get("revenue_pct_gdp", {})
	s.total_revenue_pct_gdp = d.get("total_revenue_pct_gdp", 0.0)
	s.total_spending_pct_gdp = d.get("total_spending_pct_gdp", 0.0)
	s.debt_service_pct_gdp = d.get("debt_service_pct_gdp", 0.0)
	s.deficit_pct_gdp = d.get("deficit_pct_gdp", 0.0)
	s.debt_eur_bn = d.get("debt_eur_bn", 0.0)
	s.start_deficit_pct_gdp = d.get("start_deficit_pct_gdp", 0.0)

	s.bloc_approval = d.get("bloc_approval", {})
	s.overall_approval_pct = d.get("overall_approval_pct", 0.0)
	s.issue_salience = d.get("issue_salience", {})

	s.demand_impulse_pct = d.get("demand_impulse_pct", 0.0)
	s.potential_shift_pct = d.get("potential_shift_pct", 0.0)
	s.external_impulse_pct = d.get("external_impulse_pct", 0.0)
	s.trade_baseline_pct = d.get("trade_baseline_pct", 0.0)

	# JSON has one numeric type; Godot's parser hands every number back as a
	# float. Cast the int-typed fields back explicitly.
	s.assembly_seats = int(d.get("assembly_seats", 0))
	s.term_months = int(d.get("term_months", 0))
	s.months_in_term = int(d.get("months_in_term", 0))
	s.next_election_year = int(d.get("next_election_year", 0))
	s.next_election_month = int(d.get("next_election_month", 0))
	s.next_ep_election_year = int(d.get("next_ep_election_year", 0))
	s.next_ep_election_month = int(d.get("next_ep_election_month", 0))
	s.terms_served = int(d.get("terms_served", 0))
	s.incumbent_party_id = d.get("incumbent_party_id", "")
	s.seats_by_party = d.get("seats_by_party", {})
	s.last_election = d.get("last_election", {})
	s.last_ep_election = d.get("last_ep_election", {})
	s.in_government = d.get("in_government", true)
	s.has_executive = d.get("has_executive", false)
	s.next_executive_year = int(d.get("next_executive_year", 0))
	s.next_executive_month = int(d.get("next_executive_month", 0))

	s.formation_method = d.get("formation_method", "")
	s.censure_rule = d.get("censure_rule", "")
	s.head_of_government_title = d.get("head_of_government_title", "")
	s.start_head_of_government_name = d.get("start_head_of_government_name", "")
	s.coalition_party_ids = d.get("coalition_party_ids", [])
	s.coalition_seats = int(d.get("coalition_seats", 0))
	s.coalition_position = d.get("coalition_position", {"economic": 0.0, "social": 0.0})
	s.pm_party_id = d.get("pm_party_id", "")
	s.pm_name = d.get("pm_name", "")
	s.is_cohabitation = d.get("is_cohabitation", false)
	s.is_minority = d.get("is_minority", false)
	s.last_formation = d.get("last_formation", {})

	s.law_structural_offset_pct = d.get("law_structural_offset_pct", 0.0)
	s.law_potential_target_pct = d.get("law_potential_target_pct", 0.0)
	s.law_other_revenue_pct_gdp = d.get("law_other_revenue_pct_gdp", 0.0)
	s.law_bloc_offset = d.get("law_bloc_offset", {})
	s.passed_law_ids = d.get("passed_law_ids", {})
	s.law_cooldown_months = d.get("law_cooldown_months", {})
	s.last_law_result = d.get("last_law_result", {})

	return s


func debt_to_gdp_pct() -> float:
	if gdp_eur_bn <= 0.0:
		return 0.0
	return debt_eur_bn / gdp_eur_bn * 100.0


func player_spending_pct_gdp() -> float:
	var total := 0.0
	for key in C.SPENDING_KEYS:
		total += float(spending_pct_gdp.get(key, 0.0))
	return total
