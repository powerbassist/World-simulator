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

## Copied from Nation at new-game and never mutated, the same class of field as
## assembly_seats. Both are static facts, and both are read by the trade weight
## in src/sim/trade.gd -- which is why they live here rather than being looked up
## through the loader: Economy.tick_month() has no loader argument and has
## twenty-eight call sites that would all have to grow one.
var eu_member: bool = false
var neighbours: Array = []

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

## External demand from trade partners, recomputed each month. Per-partner since
## V1.3b: a trade-weighted sum over the other nine rather than one GDP-weighted
## aggregate. See docs/trade-model.md.
var external_impulse_pct: float = 0.0

## Each partner's own growth at new-game, keyed by nation id -- the zero point for
## the term above, one per partner rather than one for the lot.
##
## Load-bearing, not bookkeeping. Under the single scalar this replaced,
## RE-WEIGHTING ALONE produced an impulse: shifting weight toward whichever partner
## happened to have the highest trend was a free growth boost with nothing having
## changed abroad. Per partner, the sum is identically zero whenever every partner
## sits at its own baseline, whatever the weights say. tests/test_trade.gd pins
## exactly that, and it is the field that earned SAVE_VERSION 9 -> 10.
var trade_baseline_by_partner := {}

## Growth damage from coercive measures pointed at this nation, %/yr. V1.3c.
## Recomputed from GameState.measures every month by Coercion.impulse(); exactly
## zero whenever nothing is aimed here.
##
## A THIRD impulse rather than a reuse of either above, and the distinction is
## load-bearing:
##
##   - Not demand_impulse_pct, because that DECAYS geometrically. A sanction in
##     force is a standing condition, not a shock, and it must stop the moment the
##     measure is lifted rather than fade while it is still biting.
##   - Not external_impulse_pct, because that one is PLAYER-ONLY -- the
##     `if ns.has_budget` guard in Economy.tick_month() -- and this term's whole
##     job is to move a partner the player has sanctioned. docs/trade-model.md
##     records the eigenvalues for lifting that guard; lifting it replaces the
##     28-month output-gap half-life the game's pacing is argued from, so V1.3c
##     deliberately does not.
##
## The path is one hop: the player sanctions DEU, this term moves DEU's growth,
## and the player feels it back through their OWN external_impulse_pct at
## w(FRA,DEU). No loop, because DEU has no external impulse to carry it onward.
## See docs/coercion-model.md.
var coercion_impulse_pct: float = 0.0

# --- The bloc ------------------------------------------------------------------

## This nation's standing net contribution to the bloc, percent of its own GDP.
## Signed: a net receiver carries a negative figure. Derived once at new-game by
## Bloc.net_positions() from starting prosperity and never recomputed, which is
## the same static-fact treatment eu_member and neighbours get -- and it is what
## puts the contribution inside start_deficit_pct_gdp, where an inherited drag
## the player did not choose belongs. Exactly 0.0 for a non-member.
var bloc_base_transfer_pct_gdp: float = 0.0

## What the bloc actually costs this month: the standing contribution above, plus
## whatever the rules in force move it by, plus the penalties charged for defying
## them. Written by Bloc.tick_month() and read by Budget.recompute() as a line of
## its own -- not a sixth SPENDING_KEYS entry, because docs/tiers/v1.md section 6
## keys spending lines 1:1 to cabinet portfolios and a sixth line would be a
## sixth minister. Same call docs/coercion-model.md made for the tariff line.
var bloc_transfer_pct_gdp: float = 0.0

## How far outside the bloc's rules this nation is sitting, in [0, BURDEN_MAX].
## Zero for a non-member, zero with nothing in force, and zero for a member that
## complies -- a complying player pays in the policy they could not run, which
## shows on the spending lines they had to cut rather than here.
##
## Read by opinion.gd as the `europe` issue's satisfaction, which is V1.3d's
## answer to the ISSUE_KEYS question three sessions deferred to it. See
## docs/bloc-model.md.
var bloc_burden: float = 0.0

## The burden at new-game, the reference the europe issue is measured against --
## the same "delta against the nation's own start" every other satisfaction term
## uses. France may begin in real breach of a deficit rule, and that is
## politically free until the player makes it worse or better, exactly as its
## real 4.7%-of-GDP starting deficit already is.
var start_bloc_burden: float = 0.0

# --- Elections -----------------------------------------------------------------

## Copied from Nation at new-game; the assembly's size never changes mid-game.
var assembly_seats: int = 0

## The PLAYER's term in months: the executive's where one exists (France), the
## legislature's otherwise -- see docs/government-model.md's two clocks. Not
## simply term_years * 12 from the legislative block; Elections.init_nation()
## reads whichever schedule is the player's. months_in_term counts up from the
## term the player inherits at new-game, which is usually shorter than a full
## one — see docs/electoral-systems.md.
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

## False the moment the incumbent's office is lost — an executive election
## defeat, a legislative election that leaves their party no longer largest,
## or a term limit reached. Gates the clock: main.gd stops advancing time once
## this is false. A legislative election can take the player's majority away
## but never their office where the two are separate — see
## docs/government-model.md. Only the player's nation has a meaningful reading.
var in_government: bool = true

## The executive's own schedule, present only where the head of government is
## elected separately from the assembly — of the ten, only France. When absent
## the executive term IS the legislative term and these mirror it, so the tick
## has one code path rather than two.
var has_executive: bool = false
var next_executive_year: int = 0
var next_executive_month: int = 0

# --- Political system --------------------------------------------------------

## Copied from Nation at new-game; which template this nation's institutions
## are declared as. See docs/political-systems.md.
var system_id: String = ""

## The head of state -- decorative except for elected_president's clock, which
## dissolution.gd reads for head_of_state_limited. See political_system.gd.
var head_of_state_kind: String = ""
var head_of_state_title: String = ""
var head_of_state_person_id: String = ""
var head_of_state_next_year: int = 0
var head_of_state_next_month: int = 0

## What ends the player's run, dispatched in src/sim/elections.gd -- named
## rather than inferred from has_executive, see docs/political-systems.md.
var lose_condition: String = ""

## How many terms the player's own office permits, 0 meaning no limit. Checked
## alongside lose_condition at the executive verdict.
var term_limit: int = 0

## What a constitutional amendment must clear to pass. Mutable at runtime, in
## contrast to every other field on this page -- amendment_rule itself is a
## valid amendment target (entrenchment), which is why it lives here rather
## than being read straight off Nation. See docs/amendment-model.md.
var amendment_rule: String = ""

## Whether this nation's own constitution permits changing its political
## system at all. Copied from Nation at new-game and never written again --
## unlike amendment_rule above, no amendment in this game can un-entrench
## itself. See docs/transition-model.md.
var permits_system_change: bool = false

# --- Dissolution ---------------------------------------------------------------

## Copied from Nation at new-game; who may end the current assembly early and
## what it costs to. Dispatched in src/sim/dissolution.gd, never on the nation
## id. See docs/dissolution-model.md.
var dissolution_rule: String = ""
var dissolution_lockout_months: int = 0
var dissolution_notice_months: int = 0

## Months remaining before the player may dissolve again, counted down by
## src/sim/dissolution.gd. Set at the RESULTING election, not at the command --
## France's lockout is one year from the new Assembly, not from the decree.
var dissolution_lockout_remaining: int = 0

## True from the command until the snap election it scheduled actually fires.
## Read once by Elections._tick_nation() and cleared there.
var dissolution_pending: bool = false

## How many times the player has dissolved this run. Never reset.
var dissolutions_called: int = 0

## {year, month} of the most recently called dissolution, for the government
## screen to read. Empty until the first one.
var last_dissolution := {}

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
var start_head_of_government_person_id: String = ""

## The live government: which parties are in it, how many seats they carry
## between them, and the seat-weighted mean of their ideology positions. That
## position is the government's agreed line, and legislature.gd reads it.
var coalition_party_ids: Array = []
var coalition_seats: int = 0
var coalition_position := {"economic": 0.0, "social": 0.0}

var pm_party_id: String = ""
var pm_person_id: String = ""

## True when the assembly majority is a bloc that excludes the executive's own
## party — the player keeps the office and loses the legislature.
var is_cohabitation: bool = false

## True when the government holds at most half the chamber. A legal outcome,
## not a failure: it governs until it is censured.
var is_minority: bool = false

## The full description of the most recent formation, for the government screen
## to read. Same shape src/sim/government.gd:form() returns.
var last_formation := {}

## Months before the government may force another bill through under Article
## 49.3. Counted down by legislature.gd alongside the per-law cooldowns.
var force_cooldown_months: int = 0

## Parties that voted for a censure motion that carried. Barred from joining the
## replacement government -- they have just shown they will not support one --
## until the next legislative election clears the slate.
var censure_barred_party_ids: Array = []

## How many governments have been censured out of office this run. Never reset;
## a president who has burned through three prime ministers should read as one.
var governments_fallen: int = 0

## The most recent censure motion, for the law and government screens to read.
## Empty until one is moved. Same shape government.gd:resolve_censure() returns.
var last_censure := {}

# --- Cabinet -----------------------------------------------------------------

## Copied from cabinet_constants.PORTFOLIO_KEYS at every seating -- portfolio
## string -> holding party id, "" is vacant. Dispatched on in src/sim/cabinet.gd.
## See docs/cabinet-model.md.
var cabinet := {}

## Cached at every seat()/assign()/resignation, the same way coalition_position
## is cached by government.gd rather than recomputed by every reader --
## opinion.gd reads this directly and has no reason to know a Party object
## exists. portfolio string -> effectiveness float.
var cabinet_effectiveness := {}

## How many of the five portfolios each coalition party is entitled to by
## d'Hondt over coalition seats, cached at the same time as cabinet itself.
## party id -> int, summing to PORTFOLIO_KEYS.size().
var cabinet_entitlement := {}

## How many times the player has reshuffled the cabinet this run. Never reset --
## the same shape dissolutions_called and governments_fallen already use.
var reshuffles_called: int = 0

## How many ministers have resigned this run. Never reset.
var resignations_count: int = 0

## The most recent resignation, for the government screen to read. Empty until
## the first one.
var last_resignation := {}

# --- Discipline ------------------------------------------------------------------

## String party id -> how reliably that party currently delivers its seats, in
## [DISCIPLINE_MIN, the party's authored figure]. Seeded from data/parties/*.json
## and moved every month by src/sim/discipline.gd; the authored number is what
## the party manages at its best, this is what it manages now.
##
## Read by government.gd's coalition_bonus() and hostility(), and by the
## rebellion split in both vote resolvers. See docs/discipline-model.md.
var party_discipline := {}

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
## still apply. For decisions with no budget footprint and so no matching issue.
##
## Named `law_bloc_offset` until V1.3a, when the prefix stopped being true for
## the fifth time: a law writes it, but so do Government.penalise_blocs() after
## a censure or an Article 49.3, a cabinet resignation, a reshuffle, a
## dissolution, a scenario's authored starting approval, and now a diplomatic
## action. It is the model's ONE persistent per-bloc approval channel, and the
## save version was already bumping for `relations`, which is the only window
## in which renaming a serialised field is free. See docs/diplomacy-model.md.
var bloc_offset := {}

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


# --- Diplomacy (V1.3a) ---------------------------------------------------------

## "action_id|TARGET" -> months remaining before that action can be used against
## THAT nation again, counting down every tick. Keyed on the pair rather than on
## the action alone because condemning Germany is not a reason to be unable to
## condemn Italy -- the verb is on cooldown against one counterparty, not
## globally. The relations SCORE lives on GameState, not here; this is the
## acting nation's own record of what it has recently done, which genuinely is
## per-nation. See docs/diplomacy-model.md.
var diplo_cooldown_months := {}

## The most recent diplomatic action, for the nation panel to read after acting.
## Empty until the first one resolves.
var last_diplomatic_result := {}

## Months until this nation next considers acting on its own initiative. V1.3f.
##
## The only serialised field this session adds, and the one that earns
## SAVE_VERSION 12 on its own: absent it reads as 0, which means every one of the
## nine acts in the first month after a reload — a nine-act burst a played game
## never produces, because the staggered counters are what spread them out.
## GameState.foreign_acts does NOT earn the bump; absent it reads as "nothing has
## happened yet", which is correct. tests/test_save_load.gd asserts both halves.
##
## Per-nation rather than one counter on GameState, unlike the council's
## bloc.months_to_next: nine actors on one shared counter would all act in the
## same month, and message_stack.gd holds six cards. Seeded DETERMINISTICALLY by
## Diplomacy.init_nation() from the nation's index in a sorted id list — there is
## no rand() anywhere in src/sim/, and the budget projection runs this forward on
## a copy, so a projection, a reloaded save and a played game must agree.
##
## Zero for the player's nation and never ticked there: has_budget means a human
## decides here, which is the one place in the project that guard is read the
## other way round.
var diplo_months_to_act: int = 0


## Military capability, V1.3g. DERIVED from sustained defence spending and never
## authored — the treatment src/sim/cabinet.gd's competence gets, and for the same
## reason: an authored per-nation strength is a second number somebody has to keep
## in step with the spending line, and it disagrees with it the moment a player
## moves the lever.
##
## The ONE field this session adds that earns SAVE_VERSION 13. Absent it reads as
## 0.0, against a France that has spent 2.0 % of GDP on defence since before the
## game started, and two readers break at once: the deployment cost divides by it,
## so every commitment jumps to the clamp, and ForeignPolicy.would_accept_pact()
## reads the whole roster as militarily worthless. A reloaded game runs a DIFFERENT
## MODEL from the one that saved it, which is eu_member/neighbours' case in its
## strongest form. Neither GameState.pacts nor GameState.deployments earns it, and
## tests/test_save_load.gd asserts every half.
##
## Seeded AT equilibrium by Defence.init_nation(), not at zero: an army exists on
## the day the game starts.
var military_capability: float = 0.0

## Both defence prices, recomputed once a month by Defence._recompute_prices() and
## read from here rather than called for. Cached because of the preload graph
## rather than for speed: budget.gd and opinion.gd reading Defence directly is an
## edge each, and Opinion.issue_satisfaction(ns) would stop being pure-on-ns, which
## elections.gd's attribution and overview_panel.gd both rely on.
##
## Neither earns a save bump on its own — both are recomputed from the registers on
## the first tick after a load — but they are serialised anyway so a save read back
## and never ticked reports the same budget it was saved with. bloc_transfer's shape.
var deployment_bill_pct_gdp: float = 0.0
var deployment_opinion_load: float = 0.0


# --- Private companies (V1.4a) --------------------------------------------------

## company id -> {"share": float, "subsidy": float}. The live half of the firm
## register, and ONLY the live half: a firm's authored share and headcount are
## content, so DataLoader.companies is the baseline and this carries what moved.
## Storing the baseline here too is the duplication data/people/ was built to
## remove.
##
## THE FIELD THAT EARNS SAVE_VERSION 15. Absent, every firm reads as share 0.0 —
## the partition vanishes, `output_eur_bn()` returns nothing for every firm, and a
## subsidy the player is still paying for through a serialised budget line moves a
## share that is not there. That is `military_capability` at V1.3g and
## `eu_member`/`neighbours` at V1.3b: a reloaded game running a DIFFERENT MODEL
## from the one that saved it, not merely a game missing a number.
##
## Per-nation and keyed by a content id, which is `party_discipline`'s and
## `cabinet`'s shape — so V1.4a adds a register and NO NEW KIND of live state, the
## claim V1.3g made for its two.
var companies := {}

## The three prices, recomputed once a month by Companies._recompute_prices() and
## read from here rather than called for. Cached because of the preload graph
## rather than for speed: companies.gd takes a LOADER, and economy.gd's twenty-eight
## call sites and budget.gd's recompute() would all have to grow one to ask it
## anything.
##
## `subsidy_bill_pct_gdp` is a computed spending line, NOT a sixth entry in
## economy_constants.SPENDING_KEYS — that list is keyed 1:1 to cabinet portfolios,
## so a sixth line would be a sixth minister. `deployment_bill_pct_gdp` above took
## the same route for the same reason.
##
## The other two are DEVIATION terms and read exactly 0.0 until a subsidy stands —
## or, since V1.4b, until a regulation does. None of the three earns the bump on
## its own — all three are recomputed from `companies` and `regulation_burden` on
## the first tick after a load — but they are serialised anyway so a save read back
## and never ticked reports the budget it was saved with.
var subsidy_bill_pct_gdp: float = 0.0
var firm_impulse_pct: float = 0.0
var firm_jobs_offset_pct: float = 0.0

## V1.4b. Sector id → signed accumulated regulatory burden, clamped to
## ±companies_constants.REGULATION_BURDEN_MAX. Written by Legislature.apply() and
## by nothing else in the project.
##
## PER SECTOR AND NEVER PER FIRM. A regulation is sector-wide where a subsidy is
## firm-targeted, and a per-firm burden field would put a second writer beside
## `share` — two answers to the question of who is winning the sector — as well as
## breaking tests/test_save_load.gd's assertion that a register entry holds nothing
## beyond `share` and `subsidy`.
##
## EARNS NO SAVE_VERSION BUMP, and the rule is applied literally: a version-15 save
## is a game that could not pass a regulation, so an absent register reads as every
## burden 0.0, which is correct for it. `measures` at V1.3c, `pacts` at V1.3g and
## `appointments` at U6a. Serialised all the same, because a law writes it once and
## no tick recomputes it — unlike the three prices above.
var regulation_burden := {}

## The most recent company action, for the companies panel to read after acting.
## Empty until the first one resolves. `last_diplomatic_result`'s shape.
var last_company_result := {}


## Deep copy. The budget projection runs the real simulation forward on a copy,
## so every mutable field — every Dictionary — must be duplicated, not shared.
func duplicate_state():
	var s = new()
	s.id = id
	s.eu_member = eu_member
	s.neighbours = neighbours.duplicate()

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
	s.trade_baseline_by_partner = trade_baseline_by_partner.duplicate(true)
	s.coercion_impulse_pct = coercion_impulse_pct

	s.bloc_base_transfer_pct_gdp = bloc_base_transfer_pct_gdp
	s.bloc_transfer_pct_gdp = bloc_transfer_pct_gdp
	s.bloc_burden = bloc_burden
	s.start_bloc_burden = start_bloc_burden

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

	s.system_id = system_id
	s.head_of_state_kind = head_of_state_kind
	s.head_of_state_title = head_of_state_title
	s.head_of_state_person_id = head_of_state_person_id
	s.head_of_state_next_year = head_of_state_next_year
	s.head_of_state_next_month = head_of_state_next_month
	s.lose_condition = lose_condition
	s.term_limit = term_limit
	s.amendment_rule = amendment_rule
	s.permits_system_change = permits_system_change

	s.dissolution_rule = dissolution_rule
	s.dissolution_lockout_months = dissolution_lockout_months
	s.dissolution_notice_months = dissolution_notice_months
	s.dissolution_lockout_remaining = dissolution_lockout_remaining
	s.dissolution_pending = dissolution_pending
	s.dissolutions_called = dissolutions_called
	s.last_dissolution = last_dissolution.duplicate(true)

	s.formation_method = formation_method
	s.censure_rule = censure_rule
	s.head_of_government_title = head_of_government_title
	s.start_head_of_government_person_id = start_head_of_government_person_id
	s.coalition_party_ids = coalition_party_ids.duplicate(true)
	s.coalition_seats = coalition_seats
	s.coalition_position = coalition_position.duplicate(true)
	s.pm_party_id = pm_party_id
	s.pm_person_id = pm_person_id
	s.is_cohabitation = is_cohabitation
	s.is_minority = is_minority
	s.last_formation = last_formation.duplicate(true)
	s.force_cooldown_months = force_cooldown_months
	s.censure_barred_party_ids = censure_barred_party_ids.duplicate(true)
	s.governments_fallen = governments_fallen
	s.last_censure = last_censure.duplicate(true)

	s.cabinet = cabinet.duplicate(true)
	s.cabinet_effectiveness = cabinet_effectiveness.duplicate(true)
	s.cabinet_entitlement = cabinet_entitlement.duplicate(true)
	s.reshuffles_called = reshuffles_called
	s.resignations_count = resignations_count
	s.last_resignation = last_resignation.duplicate(true)

	s.party_discipline = party_discipline.duplicate(true)

	s.law_structural_offset_pct = law_structural_offset_pct
	s.law_potential_target_pct = law_potential_target_pct
	s.law_other_revenue_pct_gdp = law_other_revenue_pct_gdp
	s.bloc_offset = bloc_offset.duplicate(true)
	s.passed_law_ids = passed_law_ids.duplicate(true)
	s.law_cooldown_months = law_cooldown_months.duplicate(true)
	s.last_law_result = last_law_result.duplicate(true)

	s.diplo_cooldown_months = diplo_cooldown_months.duplicate(true)
	s.last_diplomatic_result = last_diplomatic_result.duplicate(true)
	s.diplo_months_to_act = diplo_months_to_act

	s.military_capability = military_capability
	s.deployment_bill_pct_gdp = deployment_bill_pct_gdp
	s.deployment_opinion_load = deployment_opinion_load

	s.companies = companies.duplicate(true)
	s.subsidy_bill_pct_gdp = subsidy_bill_pct_gdp
	s.firm_impulse_pct = firm_impulse_pct
	s.firm_jobs_offset_pct = firm_jobs_offset_pct
	s.regulation_burden = regulation_burden.duplicate(true)
	s.last_company_result = last_company_result.duplicate(true)

	return s


## Serialise to a plain Dictionary (JSON-safe: String/float/int/bool/Array/
## Dictionary only). Same field set as duplicate_state(), in the same order,
## so the two stay easy to compare when a field is added. See
## docs/data-architecture.md Persistence.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"eu_member": eu_member,
		"neighbours": neighbours,

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
		"trade_baseline_by_partner": trade_baseline_by_partner,
		"coercion_impulse_pct": coercion_impulse_pct,

		"bloc_base_transfer_pct_gdp": bloc_base_transfer_pct_gdp,
		"bloc_transfer_pct_gdp": bloc_transfer_pct_gdp,
		"bloc_burden": bloc_burden,
		"start_bloc_burden": start_bloc_burden,

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

		"system_id": system_id,
		"head_of_state_kind": head_of_state_kind,
		"head_of_state_title": head_of_state_title,
		"head_of_state_person_id": head_of_state_person_id,
		"head_of_state_next_year": head_of_state_next_year,
		"head_of_state_next_month": head_of_state_next_month,
		"lose_condition": lose_condition,
		"term_limit": term_limit,
		"amendment_rule": amendment_rule,
		"permits_system_change": permits_system_change,

		"dissolution_rule": dissolution_rule,
		"dissolution_lockout_months": dissolution_lockout_months,
		"dissolution_notice_months": dissolution_notice_months,
		"dissolution_lockout_remaining": dissolution_lockout_remaining,
		"dissolution_pending": dissolution_pending,
		"dissolutions_called": dissolutions_called,
		"last_dissolution": last_dissolution,

		"formation_method": formation_method,
		"censure_rule": censure_rule,
		"head_of_government_title": head_of_government_title,
		"start_head_of_government_person_id": start_head_of_government_person_id,
		"coalition_party_ids": coalition_party_ids,
		"coalition_seats": coalition_seats,
		"coalition_position": coalition_position,
		"pm_party_id": pm_party_id,
		"pm_person_id": pm_person_id,
		"is_cohabitation": is_cohabitation,
		"is_minority": is_minority,
		"last_formation": last_formation,
		"force_cooldown_months": force_cooldown_months,
		"censure_barred_party_ids": censure_barred_party_ids,
		"governments_fallen": governments_fallen,
		"last_censure": last_censure,

		"cabinet": cabinet,
		"cabinet_effectiveness": cabinet_effectiveness,
		"cabinet_entitlement": cabinet_entitlement,
		"reshuffles_called": reshuffles_called,
		"resignations_count": resignations_count,
		"last_resignation": last_resignation,

		"party_discipline": party_discipline,

		"law_structural_offset_pct": law_structural_offset_pct,
		"law_potential_target_pct": law_potential_target_pct,
		"law_other_revenue_pct_gdp": law_other_revenue_pct_gdp,
		"bloc_offset": bloc_offset,
		"passed_law_ids": passed_law_ids,
		"law_cooldown_months": law_cooldown_months,
		"last_law_result": last_law_result,

		"diplo_cooldown_months": diplo_cooldown_months,
		"last_diplomatic_result": last_diplomatic_result,
		"diplo_months_to_act": diplo_months_to_act,

		"military_capability": military_capability,
		"deployment_bill_pct_gdp": deployment_bill_pct_gdp,
		"deployment_opinion_load": deployment_opinion_load,

		"companies": companies,
		"subsidy_bill_pct_gdp": subsidy_bill_pct_gdp,
		"firm_impulse_pct": firm_impulse_pct,
		"firm_jobs_offset_pct": firm_jobs_offset_pct,
		"regulation_burden": regulation_burden,
		"last_company_result": last_company_result,
	}


## Inverse of to_dict(). Every Dictionary/Array comes from JSON.parse_string(),
## already fresh and unshared, so no .duplicate() is needed here the way
## duplicate_state() needs one.
static func from_dict(d: Dictionary):
	var s = new()
	s.id = d.get("id", "")
	s.eu_member = bool(d.get("eu_member", false))
	s.neighbours = d.get("neighbours", [])

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
	# Re-floated key by key rather than taken wholesale, the same reason
	# GameState.from_dict() re-floats relations: JSON round-trips a whole-number
	# growth as an int, and a baseline dictionary holding a mix of ints and floats
	# would make the impulse arithmetic depend on how a value happened to be saved.
	var baselines: Dictionary = d.get("trade_baseline_by_partner", {})
	for partner_id in baselines.keys():
		s.trade_baseline_by_partner[partner_id] = float(baselines[partner_id])
	# Absent in a version-10 save, and 0.0 is exactly right for one: nothing was in
	# force, so nothing was being damaged. Recomputed from GameState.measures on the
	# first tick after loading in any case -- see the field's own declaration.
	s.coercion_impulse_pct = float(d.get("coercion_impulse_pct", 0.0))

	# The pair of fields that earns V1.3d's SAVE_VERSION bump, and the reason is
	# the one game_state.gd's own comment states rather than a new one. An absent
	# bloc_base_transfer_pct_gdp reads as 0.0 -- a France that pays nothing into a
	# budget it has always paid into -- and an absent start_bloc_burden reads as
	# 0.0 against a live burden, which permanently MIS-SIGNS the europe issue: a
	# player who loaded a save while in breach would be scored as though the
	# breach were new. Both are eu_member/neighbours' case, not agreements' case.
	s.bloc_base_transfer_pct_gdp = float(d.get("bloc_base_transfer_pct_gdp", 0.0))
	s.bloc_transfer_pct_gdp = float(d.get("bloc_transfer_pct_gdp", 0.0))
	s.bloc_burden = float(d.get("bloc_burden", 0.0))
	s.start_bloc_burden = float(d.get("start_bloc_burden", 0.0))

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

	s.system_id = d.get("system_id", "")
	s.head_of_state_kind = d.get("head_of_state_kind", "")
	s.head_of_state_title = d.get("head_of_state_title", "")
	s.head_of_state_person_id = d.get("head_of_state_person_id", "")
	s.head_of_state_next_year = int(d.get("head_of_state_next_year", 0))
	s.head_of_state_next_month = int(d.get("head_of_state_next_month", 0))
	s.lose_condition = d.get("lose_condition", "")
	s.term_limit = int(d.get("term_limit", 0))
	s.amendment_rule = d.get("amendment_rule", "")
	s.permits_system_change = d.get("permits_system_change", false)

	s.dissolution_rule = d.get("dissolution_rule", "")
	s.dissolution_lockout_months = int(d.get("dissolution_lockout_months", 0))
	s.dissolution_notice_months = int(d.get("dissolution_notice_months", 0))
	s.dissolution_lockout_remaining = int(d.get("dissolution_lockout_remaining", 0))
	s.dissolution_pending = d.get("dissolution_pending", false)
	s.dissolutions_called = int(d.get("dissolutions_called", 0))
	s.last_dissolution = d.get("last_dissolution", {})

	s.formation_method = d.get("formation_method", "")
	s.censure_rule = d.get("censure_rule", "")
	s.head_of_government_title = d.get("head_of_government_title", "")
	s.start_head_of_government_person_id = d.get("start_head_of_government_person_id", "")
	s.coalition_party_ids = d.get("coalition_party_ids", [])
	s.coalition_seats = int(d.get("coalition_seats", 0))
	s.coalition_position = d.get("coalition_position", {"economic": 0.0, "social": 0.0})
	s.pm_party_id = d.get("pm_party_id", "")
	s.pm_person_id = d.get("pm_person_id", "")
	s.is_cohabitation = d.get("is_cohabitation", false)
	s.is_minority = d.get("is_minority", false)
	s.last_formation = d.get("last_formation", {})
	s.force_cooldown_months = int(d.get("force_cooldown_months", 0))
	s.censure_barred_party_ids = d.get("censure_barred_party_ids", [])
	s.governments_fallen = int(d.get("governments_fallen", 0))
	s.last_censure = d.get("last_censure", {})

	s.cabinet = d.get("cabinet", {})
	s.cabinet_effectiveness = d.get("cabinet_effectiveness", {})
	s.cabinet_entitlement = d.get("cabinet_entitlement", {})
	s.reshuffles_called = int(d.get("reshuffles_called", 0))
	s.resignations_count = int(d.get("resignations_count", 0))
	s.last_resignation = d.get("last_resignation", {})

	s.party_discipline = d.get("party_discipline", {})

	s.law_structural_offset_pct = d.get("law_structural_offset_pct", 0.0)
	s.law_potential_target_pct = d.get("law_potential_target_pct", 0.0)
	s.law_other_revenue_pct_gdp = d.get("law_other_revenue_pct_gdp", 0.0)
	s.bloc_offset = d.get("bloc_offset", {})
	s.diplo_cooldown_months = d.get("diplo_cooldown_months", {})
	s.last_diplomatic_result = d.get("last_diplomatic_result", {})
	s.diplo_months_to_act = int(d.get("diplo_months_to_act", 0))
	# The 0.0 fallback here is the one this session bumps SAVE_VERSION for, and it
	# is deliberately NOT softened into "recompute it from spending" -- a fallback
	# that quietly repairs the field would make the save version unnecessary and
	# the next genuinely unrecoverable field would have no precedent to point at.
	s.companies = d.get("companies", {})
	s.subsidy_bill_pct_gdp = float(d.get("subsidy_bill_pct_gdp", 0.0))
	s.firm_impulse_pct = float(d.get("firm_impulse_pct", 0.0))
	s.firm_jobs_offset_pct = float(d.get("firm_jobs_offset_pct", 0.0))
	# V1.4b, and the empty fallback is CORRECT rather than merely tolerable: a
	# version-15 save comes from a game with no `business` laws in it, so every
	# burden really was 0.0. That is why this field earns no bump of its own.
	s.regulation_burden = d.get("regulation_burden", {})
	s.last_company_result = d.get("last_company_result", {})

	s.military_capability = float(d.get("military_capability", 0.0))
	s.deployment_bill_pct_gdp = float(d.get("deployment_bill_pct_gdp", 0.0))
	s.deployment_opinion_load = float(d.get("deployment_opinion_load", 0.0))
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
