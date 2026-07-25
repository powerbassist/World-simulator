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

## False the moment the incumbent loses a national election. Gates the clock:
## main.gd stops advancing time once this is false. Only the player's nation
## has a meaningful reading — see has_budget below.
var in_government: bool = true


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
