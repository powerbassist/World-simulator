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
const Fields = preload("res://src/core/nation_fields.gd")

var id: String = ""

## Copied from Nation at new-game and never mutated, the same class of field as
## assembly_seats, and read by the trade weight in src/sim/trade.gd -- which is
## why it lives here rather than being looked up through the loader:
## Economy.tick_month() has no loader argument and has twenty-eight call sites
## that would all have to grow one.
var neighbours: Array = []

## V5.1-0d: the nations whose capital this nation holds a resident embassy in --
## DIRECTED (France's embassy in Rome is not Italy's in Paris). Seeded at new game
## by src/sim/diplomacy_embassies.gd from the rule data/world/embassies.json states,
## then written only by open_embassy's `embassy` effect; it is what gates that verb.
## Plain Array for neighbours' reason above (test_state_copy's sentinel probe).
##
## SERIALISED, absent_ok FALSE, and it is what bumps SAVE_VERSION to 41: an absent
## key reads as no embassy anywhere -- the pre-0d model, where the AI opens 33
## "new" embassies in the player's capital and the player is offered one in
## Zagreb. A reloaded game running a different model: eu_member/neighbours' case.
var embassies: Array = []

## V5.1-0d pass 2: the nations this one has NO diplomatic relations with (symmetric;
## data/world/embassies.json's exceptions, copied at the same seed), read by the
## `relations_exist` precondition so open_embassy cannot open what the data says
## cannot stand. A static copy for neighbours' reason: _read_field() has no loader.
## Serialised, absent_ok false under the same bump to 41 (no save at 41 ever shipped
## without it): absent, every pair would read as in relations.
var no_relations: Array = []

## The orgs this nation belongs to, sorted org ids. V3.2. LIVE state, not a
## content lookup: an accession or a withdrawal rewrites it months into a run,
## and every reader -- the trade weight, resting relations, the appraisal's
## external term, the councils -- must see the live truth. `eu_member` above
## dies with the V3.2 readers task; until then both are written at new-game and
## agree. Serialised; an absent entry reads [], which is the truth about a
## non-member.
var orgs := []

## This nation's standing net contribution PER ORG it belongs to, percent of its
## own GDP, derived from prosperity against EACH ORG'S OWN mean at new-game.
## Entries exist only where membership does, so a non-member of an org reads
## 0.0 by `.get(org_id, 0.0)` -- the old exact-zero property, per org.
var org_base_transfer_pct_gdp := {}

## This nation's voting weight PER ORG it belongs to. Seeded at new-game from
## the content's seat table and rewritten by the accession flip from the org's
## authored `accession_seats` -- LIVE state, not a content lookup, because a
## nation that accedes mid-game is on no content table and a member whose vote
## weighs zero is a member in name only (the review's second-class-member
## finding). The council's division and the EP's seats both read this.
var org_seats := {}

# --- Economy -----------------------------------------------------------------

var sector_output := {}  # String -> float, EUR bn. Sums to gdp_eur_bn exactly.
var gdp_eur_bn: float = 0.0
var potential_gdp_eur_bn: float = 0.0

## Region id -> output in EUR bn, plus one entry under region_constants.RESIDUAL_KEY
## for the extra-regio remainder. NATIONAL GDP IS THE SUM OF THIS DICTIONARY -- V2.5.
##
## EARNS THE SAVE_VERSION BUMP, and it is military_capability's case at V1.3g in the
## strongest form this list has carried. Absent, every entry reads 0.0, the sum is
## 0.0, and `ns.gdp_eur_bn` is written to zero on the first tick: the country does not
## run a different model, it ceases to have an economy. Re-deriving on load does not
## rescue it either -- re-seeding from the authored `gdp_share` would erase fourteen
## years of divergence the player watched happen, which is service_quality's reason at
## V1.5a.
##
## WHAT IS NOT HERE IS THE HALF WORTH PINNING. There is no stored regional
## unemployment rate, no regional stock and no regional accumulator:
## src/sim/regions.gd reads a regional rate as a pure function of the national one,
## so tests/test_save_load.gd asserts the ABSENCE and a session that makes it
## stateful turns that red and has to say why. (tests/test_regions.gd reads this
## file for the literal, so the refusal is written without naming it -- the
## test_map_cities fired-on-a-comment lesson.)
var region_gdp_eur_bn := {}

## Region id -> that region's live share of the nation's population, and city id ->
## that city's live share of its region's. V2.6a.
##
## THEY EARN THE SAVE_VERSION BUMP TOGETHER AND FOR ONE REASON. Absent, every share
## reads 0.0: every city's population is zero, src/ui/map_cities.gd draws no glyph at
## any zoom, and both panels print an empty country -- a reloaded game that has lost
## its geography rather than one running a slightly different model. Re-seeding from
## the authored shares does not rescue them: the authored share is where a place
## STARTED, and re-seeding would erase the movement the save exists to remember
## (service_quality's reason at V1.5a, region_gdp_eur_bn's at V2.5).
##
## WHAT IS NOT HERE IS STILL PINNED. There is no stored city POPULATION -- a head
## count is `share x share x population` and storing one would be a second answer to
## a question these two already answer -- and tests/test_save_load.gd keeps that
## absence red the day somebody stores one.
var region_pop_share := {}
var city_pop_share := {}

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

var tax_rates_pct := {}          # income, corporate, vat, capital_gains, wealth
var spending_pct_gdp := {}       # health, education, defence, pensions, infrastructure
var start_tax_rates_pct := {}
var start_spending_pct_gdp := {}

## V1.6d. How steep the income-tax schedule is, as a dimensionless index bounded by
## tax_constants.PROGRESSIVITY_MIN/MAX, initialised for all ten from
## tax_constants.PROGRESSIVITY_BASE.
##
## V1.6d refused a sixth tax key here -- brackets WITHIN income, not further
## keys -- and that refusal was right for what V1.6d was asked to build. V4.2
## overturned it for a different door: the COMPOSITION machine may propose a
## new key with its own base, erosion and rate (a carbon tax, a windfall
## levy), the tax-model wealth-tax precedent being that a new key brings its
## own base. `tax_progressivity` keeps its own meaning untouched: it is still
## the bracket lever WITHIN income, not a key.
##
## BOTH FIELDS EARN THE SAVE BUMP AND FOR THE SAME REASON, unlike most pairs on this
## file's list: an absent `tax_progressivity` reads 0.0, which is not a neutral default
## but PROGRESSIVITY_MIN -- a flat tax, the most regressive schedule the model has --
## and an absent `start_tax_progressivity` reads 0.0 too, so the deviation is 0.0 and
## the reloaded game agrees that a flat tax is normal. A save reloaded after a
## redistributive term silently abolishes the bracket structure AND forgets it ever
## had one. See tests/test_save_load.gd, which asserts the two halves separately.
var tax_progressivity: float = 0.0
var start_tax_progressivity: float = 0.0
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

## V1.6c. The debt ratio at new-game, and the reference src/sim/credit.gd measures the
## bond spread against, so a fresh game borrows at exactly economy_constants.
## DEBT_REAL_RATE_PCT and every balance figure ever quoted against that flat 2.0 keeps
## its meaning. start_deficit_pct_gdp's job one line up, for the other half of the same
## pair.
##
## SET FROM THE SCENARIO-OVERRIDDEN FIGURE rather than from the nation file, in
## src/core/game_state.gd beside debt_eur_bn -- a scenario authoring 140 % of GDP is a
## France that has ALWAYS carried that debt, so it must start at a zero spread rather
## than in immediate breach of a market that never lent it anything.
##
## EARNS THE SAVE_VERSION BUMP TO 21, on its own. Absent it reads 0.0 against a live
## ~110, so the debt gap reads +110 points from the first month, the yield goes to
## credit_constants.YIELD_MAX and the debt service with it -- a reloaded game running a
## DIFFERENT MODEL from the one that saved it, which is `cycle_amplitude_rel` at V1.6a,
## `military_capability` at V1.3g and `eu_member` at V1.3b. Re-deriving on load cannot
## rescue it either: the live ratio has moved, and re-anchoring on it would silently
## forgive every point of debt the player added.
var start_debt_to_gdp_pct: float = 0.0

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

## V1.6a. The business cycle's contribution to this month's annualised growth, in
## points. Signed; a slump is negative.
##
## SUSTAINED, not decayed, and it sits with coercion_impulse_pct and firm_impulse_pct
## on that side of economy.gd's distinction rather than with demand_impulse_pct and
## unrest_impulse_pct on the other: a recession is a condition the economy is IN, not
## a shock it absorbed. It is also the only addend in that sum whose value this month
## says nothing about whether the player did anything, which is the row's whole point.
##
## ONE WRITER, Economy.tick_month(), from the pure read Cycle.impulse_pct(). There is
## no Cycle.tick_month() to forget -- see the header of src/sim/cycle.gd for why that
## is the session's structural call rather than a shortcut.
##
## EXACTLY 0.0 in the game's first month for all ten nations, because every term of
## the wave is a sine with no phase offset measured from cycle_constants'
## CYCLE_EPOCH. Not for a bit-identical re-run -- this session's is predicted not to
## be -- but because `imported.unemployment_pct` and SECTOR_TREND describe a nation at
## potential, and a cycle that started mid-slump would contradict the content on the
## opening month.
var cycle_impulse_pct: float = 0.0

## V1.6a. This nation's real-GDP-growth volatility as a multiple of the roster mean.
## Measured, per nation, off `imported.cycle.amplitude_rel`; the roster spans France's
## 0.689 to Luxembourg's 1.475.
##
## Static content, never recomputed, which is `eu_member`'s and `neighbours`' standing
## and NOT `start_gini_index`'s: this is not a baseline a deviation is taken against,
## it is a fact about the country.
##
## SERIALISED, AND IT IS WHAT BUMPS SAVE_VERSION TO 19 -- which is not what this
## session's plan predicted, and the reason the prediction was wrong is worth more
## than the field. The plan reasoned that a stateless generator has nothing to save.
## True of src/sim/cycle.gd, which stores nothing and has no tick. False of the save,
## because NationState.from_dict() rebuilds from the dictionary ALONE and never sees
## the loader -- so every content-derived static fact on this class is serialised
## already: eu_member, neighbours, pop_growth_pct, gini_index_per_yr. STATELESSNESS IS
## A PROPERTY OF THE MODULE, NOT OF THE SAVE FILE.
##
## Absent, it reads the default 1.0 and every nation runs the roster-average cycle
## instead of its own -- France 45 % louder than its content says, Luxembourg 32 %
## quieter. That is a reloaded game running a DIFFERENT MODEL from the one that saved
## it, which is `eu_member` at V1.3b and `military_capability` at V1.3g in its
## strongest form. `cycle_impulse_pct` above earns nothing by the same rule and is
## serialised anyway; tests/test_save_load.gd asserts both halves, and the split is
## the assertion worth having. See docs/cycle-model.md section 9.
var cycle_amplitude_rel: float = 1.0

# --- Inflation -----------------------------------------------------------------

## V1.6b. The price level's rate of change, percent per year, as a STOCK. Written by
## Inflation.tick_month() and by nothing else; tests/test_inflation.gd walks src/sim/
## and fails if a second writer appears.
##
## Seeded at this nation's own anchor rather than at 0.0, so `inflation_pct -
## start_inflation_pct` is EXACTLY 0.0 at new game for all ten. A country whose prices
## have risen ~1.8 %/yr for thirty-five years is not at zero on the opening month.
##
## EARNS THE SAVE_VERSION BUMP. Absent it reads 0.0 -- a nation of permanently stable
## prices -- and re-deriving it on load cannot rescue it, because the accumulation IS
## the state: a save reloaded mid-inflation would silently end the inflation the player
## spent a term earning. `service_quality` at V1.5a and `unrest_pct` at V1.5c.
var inflation_pct: float = 0.0

## V1.6b. Where inflation stood on the opening month, and the reference every political
## price is measured against -- start_deficit_pct_gdp's, start_bloc_burden's and
## start_service_quality's treatment.
##
## EARNS THE BUMP TOO, and by a different failure from the field above, which is why
## tests/test_save_load.gd asserts them separately. Absent it reads 0.0 while
## inflation_pct reads ~1.8, so the issue satisfaction reads -(1.8 - 0.0)/SCALE: a
## large negative from the first month, MIS-SIGNED for the rest of the run rather than
## merely missing. `start_bloc_burden` at V1.3d exactly.
var start_inflation_pct: float = 0.0

## V1.6b. The long-run rate this nation's inflation returns to when unemployment sits
## at its structural rate. Imported content, from imported.prices.inflation_pct --
## Switzerland 1.117 to Spain 2.903.
##
## EARNS THE BUMP FOR THE THIRD TIME, which is a first on this list, and it is
## `cycle_amplitude_rel`'s case verbatim: from_dict() rebuilds from the dictionary
## ALONE and never sees the loader, so a content-derived static that is not serialised
## is simply lost. Absent it reads 0.0, every nation's target collapses toward zero,
## and the real channel bills a deflation that nation never had -- a reloaded game
## running a DIFFERENT MODEL from the one that saved it.
var inflation_anchor_pct: float = 0.0

## V1.6b. Points of annual growth lost to inflation above the anchor, the eighth addend
## in economy.gd's growth sum. Signed negative or exactly zero, never positive: see
## Inflation.output_cost_pct() for why the cost is one-sided.
##
## EARNS NOTHING. Absent it reads 0.0 and Inflation.tick_month() rewrites it in full on
## the next tick -- `coercion_impulse_pct`'s and `cycle_impulse_pct`'s case. Serialised
## anyway, so one month of a reloaded save is not quietly cheaper than the month before
## it.
var inflation_impulse_pct: float = 0.0

# --- The bloc ------------------------------------------------------------------

## What the orgs actually cost this month: the standing contribution above, plus
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

## How this nation's votes become seats, and the share a party must clear to get
## any. LIFTED FROM Nation AT V1.7c, exactly as V1.2b lifted formation_method,
## censure_rule and the rest: an electoral system nobody can change is a constant
## wearing a data string, and docs/tiers/v1.md section 7 has asked for the choice
## since the tier was written.
##
## Written by Legislature.apply()'s institutional channel and by
## Elections.init_nation(), and by nothing else. Read by Elections.resolve() for
## the NATIONAL vote only -- the European election allocates on `pr_national`
## whatever the nation does at home, because an EU-wide method is not one member
## state's to amend.
##
## NOT a constitutional amendment, which is the correction V1.7c made to its own
## row: electoral law is ordinary legislation in essentially all ten (France's
## code electoral, changed by ordinary law in 1985 and again in 1986; Germany's
## Bundeswahlgesetz in 2023; Italy's Rosatellum; Britain's ordinary Act), so
## law.gd puts these two keys on the ORDINARY side of its institutional split and
## leaves the entrenched six where they were. See docs/electoral-systems.md.
var election_system: String = ""
var election_threshold_pct: float = 0.0

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

## Whether this nation's constitution offers a REFERENDUM route to an amendment,
## and whether it is a choice or the only path. Copied from Nation at new-game and
## never written again: no content writes it, so unlike amendment_rule directly
## above, a nation cannot vote itself a referendum. See docs/referendum-model.md.
var referendum_mode: String = ""

## The referendum in flight: {law_id, months_left, position}, empty when there is
## none. One at a time, and the register is the whole of that rule -- "the country
## votes on this question" is not a bound that needed a constant.
##
## `position` is COPIED IN at announcement rather than re-read from the loader at
## resolution, so the question the country answers is the question it was asked.
## Written by Referendum.announce(), Referendum.resolve_due() and
## Referendum.withdraw(), and by nothing else.
var referendum_pending: Dictionary = {}

## What the country last said. `last_project_result`'s shape, but SAVED since
## V5.0d: a membership fight (orgs.gd) advances by reading it the month after the
## vote, so a save in between lost a won referendum. Absent reads as "no vote
## yet", correct for every older save -- no bump.
var last_referendum_result: Dictionary = {}

## ============================================================================
## V1.8. THE EVENT REGISTER -- FOUR FIELDS, THREE OF WHICH EARN THE SAVE BUMP
## ============================================================================
## The occasion in front of the player: {event_id, event_name, months_left}, empty when
## there is none. ONE AT A TIME, and the register is the whole of that rule --
## `referendum_pending`'s call, and it is the right one for a second reason here: the
## message column holds six cards and an event the player never read is not an occasion.
##
## `event_name` is copied in at announcement so src/sim/calendar.gd can draw a diary row
## off this register while still preloading nothing -- V1.6f's project entry and V1.7c's
## referendum, a third time. V3.5: a SITED event adds `region_id` and `region_name`,
## copied at announcement on the same leaf argument -- and stored rather than re-derived
## because the register carries no announcement month, so a save reloaded mid-crisis
## could not reconstruct which month drew which place. A non-sited event's register
## carries neither key.
##
## Written by Events.announce(), Events.tick_month() and Events.answer(), and by nothing
## else. V4.4: this replaced `event_pending` -- the desk is a QUEUE now (severity-
## ordered, bounded by events_constants.QUEUE_MAX), because at a hundred-and-two
## events one slot is a draw the world considered and withdrew for no reason the
## content can see. Each entry is the V1.8 register's own shape (event_id,
## event_name, months_left, interrupt, plus region_id/region_name when sited) grown
## by `severity` and `category`.
var event_queue: Array[Dictionary] = []

## Event ids that have already happened, for the `once` ones. `passed_law_ids`' shape.
## Marked at DELIVERY rather than at resolution, because an event has happened the
## moment it arrives -- the choice is the response to it, not the event.
var event_fired: Dictionary = {}

## V4.4. Months before a CATEGORY may draw again, sparse -- entries exist only while
## they bind. The V1.8 global `event_quiet_months` followed the slot down a level:
## one resolution in fiscal silencing scandal forever was the global quiet's defect
## at nine categories.
var event_category_quiet: Dictionary = {}

## V4.4. Event id -> the absolute month until which it may not draw again, sparse.
## An until-month rather than a countdown so the register never holds an entry that
## does not bind, and a save reloaded mid-cooldown keeps the same boundary.
var event_cooldowns: Dictionary = {}

## V4.4. Chains a choice has armed: {event_id, due_index, source_id}. A consequence
## the player paid for must not evaporate on save -- `held_bills`' free-escape case.
var event_armed: Array[Dictionary] = []

## V4.4. Law id -> the absolute month it was repealed. The V4.2 ledger ERASE is
## silent (legislature.gd's own record), so the repeal's month is stamped beside
## it -- one line, one writer, and only the law_repealed hook reads it.
var repealed_at: Dictionary = {}

## V4.4. The last accession that flipped: {org, month_index}. orgs.gd deletes the
## finished fight the same tick membership changes, so nothing else records WHEN a
## nation joined -- the accession_won hook reads this stamp.
var last_accession: Dictionary = {}

## V4.4 review. The absolute month (`year*12+month`, `assembly_division_month`'s
## form) an ASSEMBLY bill last came into force, -1 for never. It exists because
## `last_law_result` is overwritten by every later division in the same month: a
## held bill RELEASED by Legislature._tick_held_bills was erased by a same-month
## private member's bill that failed in Statute, and the member_bill_passed hook
## never saw the release. Two writers, one per place an assembly bill takes
## effect (the release, and a division that passes and is not held); the hook is
## the only reader. NO SAVE_VERSION bump: absent reads -1, "no assembly bill has
## passed", which is the truth about every older save (`last_accession`'s case).
var assembly_bill_passed_month: int = -1

## V4.4 pass 22. The absolute month (`year*12+month`, `assembly_bill_passed_month`'s
## form) in which ANY good's world price last CROSSED UP through
## commodity_constants.HIGH_PRICE_RATIO of its base -- below the line before the
## tick, at or above it after -- -1 for never. Commodities writes it (the one machine
## that sees both sides of the update), the commodity_price_high hook is its only
## reader. It exists because the hook was a LEVEL read on a vector that drifts to its
## clamp within months, true almost every month; the register keeps no price history,
## so the edge is stamped where the update happens. NO SAVE_VERSION bump: absent reads
## -1, "no crossing yet", true of every older save (`assembly_bill_passed_month`'s case).
var commodity_high_month: int = -1

## What happened and what the player chose, newest first, capped at EVENTS_KEPT. A
## DISPLAY RECORD: nothing in src/sim/ reads it back, and tests/test_events.gd asserts
## that by reading every file in the directory -- V1.3f's `foreign_acts` property in the
## session most likely to be tempted to build the grievance ledger literally. V4.4:
## the AI nations' choices land here too, their own trace of politics that happened
## to them.
var event_history: Array[Dictionary] = []

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

## V4.2. The per-law effect ledger: law id -> {"channels": {…}, "months": [int]}.
## `channels` records what each passage of that law ACTUALLY moved, taken as a
## before/after diff around apply_effects() -- realized deltas, not authored
## ones, because every accumulator clamps and a repeal must subtract what the
## law moved or the register drifts on every repeal against a bound that was
## binding at passage. A non-once law passed twice merges into the one entry:
## the statute book is per-act, not per-passage.
##
## EARNS THE BUMP (V4.2's six-register gate), and it is `region_gdp_eur_bn`'s
## case: absent it reads empty, which is the TRUTH about every pre-38 save --
## laws passed before the ledger have no record, cannot be repealed, and no
## re-derivation is attempted (reconstructing a past law's realized deltas
## from current state is a second answer to a question only the passage could
## answer). Declared first-order: if later writers displaced a law's
## contribution, repeal subtracts what the law moved at its own passage, not a
## re-derived counterfactual -- recorded in docs/legislature-model.md.
var law_ledger := {}

## V4.2 T2. The composition machine's in-tray: draft id -> the parked spec
## ({name, position, channels, new_tax, repeals, negated, size, price,
## months_left}). Written by Statute.draft() and counted down by
## Statute.tick_month(), and by nothing else. Entries are NEVER erased --
## the id scheme reads .size(), so a deleted entry could hand a later draft
## an id some earlier law already carries; the in-tray read
## (Statute.drafts()) filters on months_left instead, and the record of what
## was drafted is the panel's history for free.
##
## Serialised under the bump game_state.gd's SAVE_VERSION comment already
## argues (T1's six-register gate named this register), so this is not the
## bump's argument again -- only what ABSENCE means HERE: a save taken
## mid-draft that lost draft_bills would lose a bill the player was drafting,
## which is not the truth about that save. Absence still READS empty with no
## error, the law_ledger contract.
var draft_bills := {}

## V4.2 T2. The composed statute book: law id -> Law.to_save_dict(). Written
## when a parked draft's countdown reaches 0 (Statute.tick_month()) and by
## nothing else; read back as Law objects wherever the authored list is
## scanned (legislature.gd's legality scan, the law panel), so a composed law
## is proposed, voted, failed and repealed like any other. Holds the save
## form and never a live Law, on the round-trips-through-JSON discipline
## every register here keeps.
##
## Serialised under the same T1 gate -- absent, acts the player put on the
## book are gone from it, and the accumulators they move would read as
## unauthored drift. Absence reads empty, no error.
var custom_laws := {}

## V4.2 T4. The params of the tax keys the composition machine has BORN:
## key -> {"name", "base_share", "erosion", "ref_pct"}. The rate lives in
## `tax_rates_pct` like any tax's; this register is what makes the key YIELD
## -- `base_share` prices the line, `erosion` is the key's own coefficient on
## the shared curve, and `ref_pct` is the rate the key was BORN at, which is
## its erosion reference: the zero-reference rule's own answer, since the tax
## did not exist at new-game and `start_tax_rates_pct` has no entry for it,
## so the one authored "rate this tax is normally levied at" (tax-model §2's
## definition) is the one its creating bill set.
##
## EARNS ITS PLACE ON THE 38 BUMP game_state.gd's comment already argues:
## absent, the rate survives in tax_rates_pct while the yield stops -- a
## silent half-tax. Absence READS empty with no error, the law_ledger
## contract. ONE WRITER: Legislature.apply()'s registration step, which runs
## BEFORE the passage's effects so commit() sees a keyed tax and not a
## pending rate with nothing behind it. Repeal of the creating bill removes
## the RATE and deliberately leaves the entry: the tax exists at rate 0, the
## way an authored tax nobody charges does.
var custom_taxes := {}

## V4.2 T5. The polls the player has PAID for: bill key -> kind ->
## {"month": absolute month, "cost": EUR bn}. Written by Statute.buy_poll()
## and by nothing else in src/sim/ -- this register remembers MONEY, not
## display; the surfaces (the briefing's poll buttons, the law panel's
## forecast band) read it directly, and the single-writer pin is scanned in
## tests/test_statute_surfaces.gd. One commission per bill per kind, once and
## for good: the bought poll is a published figure the display must never
## re-roll (poll_noise.gd's rule, priced this time).
##
## Serialised under the 38 bump game_state.gd's comment already argues (the
## six-register gate names this register): absent, a reload un-buys the
## fixed-forecast read and a second commission would charge twice for one
## number. Absence READS empty with no error -- which is the truth about every
## save that never commissioned a poll, and it is what "none bought" means.
var poll_purchases := {}

## V4.2 T6. The assembly-bill in-tray: bill id -> {"law_id", "months_left",
## "backer_firm", "backer_chief", "endorse_bonus"}. The private members' bills
## and chief-backed lobbying in flight -- tabled by Statute.tick_month()'s
## hazards, endorsed (once, by the player) through Statute.endorse(), and
## erased at the division, which writes the result into `last_law_result`
## under its assembly marker. Entries do NOT park after resolution, unlike
## draft_bills: the in-tray is bills in flight and the result's record is the
## last_law_result marker plus the cards, while the id scheme stays
## collision-free anyway (it mirrors T2's append-only size() idiom, and the
## absolute month in the id only ever increases within a run, so a size()
## reused in a later month still cannot repeat an earlier id).
##
## Serialised under the 38 bump game_state.gd's comment already argues -- the
## six-register gate names this register: absent, an announced bill the
## assembly will vote on vanishes without a division, the held_bills
## free-escape case. Absence READS empty with no error, the law_ledger
## contract.
var assembly_bills := {}

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

## The HOST's side of a cooldown (the V5.1 play gate's state-visit cadence):
## {action_id: months left} for each verb carrying host_interval_months that this
## nation RECEIVED, from anyone. While an entry stands, no nation is offered that
## verb against this one. Written by src/sim/diplomacy_cooldowns.gd's stamp(), counted down
## beside diplo_cooldown_months. Empty reads correctly for any older save --
## nothing hosted recently -- so it carries no SAVE_VERSION bump.
var diplo_hosted_months := {}

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
##
## V1.4c adds `state_share` to each entry — a THIRD field with a THIRD single
## writer, and the writers stay one apiece: `share` moves only under a subsidy,
## `state_share` only under an ownership op, `regulation_burden` below only under a
## law. It earns no SAVE_VERSION bump on the literal rule — absent it reads 0.0, "the
## state owns nothing", which is the truth about every version-15 save because those
## games could not nationalise anybody.
## V4.7a's own change is recoverable: the register went sparse, and an absent
## body entry reads its authored share (share_of_company's fallback), which is
## the truth about a firm no verb ever touched; majors missing from a pre-7a
## save are repaired by _seed_missing_majors at the first tick. SAVE_VERSION
## remained 37 through V4.7; the statute book's six registers are what 38
## carries. (The owner/failed keys named here in V4.7a's
## first draft are V4.7b's SHIPPED fields -- the autonomy machine and its
## verbs write them; absent, every one reads its default -- the per-field
## argument is industry.gd's header, and tests/test_save_load.gd's
## LIVE_KEYS block pins the key set.)
var companies := {}

## The four prices, recomputed once a month by Companies._recompute_prices() and
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
## `dividend_revenue_pct_gdp` is V1.4c's, and a computed REVENUE line — the second
## on that side after V1.3c's tariffs, and not a fourth entry in TAX_KEYS: a
## dividend has no rate, no base share and no erosion curve.
##
## The other two are DEVIATION terms and read exactly 0.0 until a subsidy stands —
## or, since V1.4b, until a regulation does. None of the four earns the bump on
## its own — all four are recomputed from `companies` and `regulation_burden` on
## the first tick after a load — but they are serialised anyway so a save read back
## and never ticked reports the budget it was saved with.
var subsidy_bill_pct_gdp: float = 0.0
var firm_impulse_pct: float = 0.0
var firm_jobs_offset_pct: float = 0.0
var dividend_revenue_pct_gdp: float = 0.0

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

# --- Sectoral investment (V1.6e) -------------------------------------------------

## sector id -> {"intensity": float, "capital": float}. The standing programme the
## player has committed to, and the capital it has accumulated. Written by
## Investment.execute() (the intensity) and Investment.tick_month() (the capital),
## one writer apiece, which is `share`/`state_share`/`regulation_burden`'s
## discipline one block on.
##
## KEYED BY SECTOR AND NOT BY A CONTENT ID, which is what makes it a register with
## no baseline anywhere else: the three sectors are economy_constants.SECTOR_TREND's
## keys, fixed for every nation, so unlike `companies` there is no authored half of
## this that DataLoader carries. What is here is the whole of it.
##
## EARNS NO SAVE_VERSION BUMP, and the rule is applied literally: a version-22 save
## is a game that had no investment verb, so an absent register reads as no
## programme running and nothing built, which is the truth about that save.
## `measures` at V1.3c, `pacts` at V1.3g and `regulation_burden` at V1.4b.
##
## SERIALISED ALL THE SAME, and that half is not free. The capital stock is written
## by a tick and NO TICK RE-DERIVES IT FROM CONTENT -- unlike V1.4a's four prices,
## which come back on the next tick -- so a save that dropped it would silently
## demolish everything the player spent a term building. `regulation_burden`'s exact
## argument, on a stock rather than on an accumulator.
var sector_investment := {}

## V1.6e's computed spending line, recomputed once a month by
## Investment.tick_month() and read from here rather than called for -- the fourth
## to take this route after the bloc transfer, the deployment bill and the subsidy
## bill, and cached for the same reason: budget.gd's recompute() reads it a month
## late on purpose, because `deficit_pct_gdp` is one of this verb's own precondition
## fields and a bill that widened the deficit inside the month would close a loop.
##
## Earns nothing on the rule -- recomputed from `sector_investment` on the first
## tick after a load -- and is serialised anyway so a save read back and never
## ticked reports the budget it was saved with. `subsidy_bill_pct_gdp`'s case.
##
## THE TREND SHIFT IS NOT CACHED BESIDE IT, and the asymmetry is deliberate:
## Investment.sector_trend_shift() takes no loader, so economy.gd can simply call it
## at the two sites that need it. The four fields above are cached because
## companies.gd takes a loader and economy.gd's call sites do not have one.
var investment_bill_pct_gdp: float = 0.0

## The most recent investment action, for the companies panel to read after acting.
## `last_company_result`'s shape.
var last_investment_result := {}

# --- Infrastructure projects (V1.6f) --------------------------------------------

## Project id -> {"months_left": int, "done": bool}. The whole of what the game
## remembers about the state's discrete building commitments. Written by
## Projects.tick_month() and by Projects.execute(), and by nothing else -- the single
## writer discipline `share`, `state_share`, `regulation_burden`, `gini_index` and
## `sector_investment` are each held to.
##
## EXACTLY TWO KEYS PER ENTRY, and projects_constants is not where that is pinned --
## Projects.ENTRY_KEYS is, and tests/test_projects.gd asserts against it. The cost,
## the duration and the payoff are AUTHORED in data/project-actions/, so caching any
## of them here would put content in the save file, which is the property V1.4a's own
## test pins for `companies` and V1.6e's for `sector_investment`.
##
## *** THIS FIELD EARNS THE SAVE_VERSION BUMP, AND IT SPLITS -- WHICH IS THE
## ASSERTION WORTH HAVING RATHER THAN THE BUMP. *** V1.3g's `deployments` exactly:
##
##   the BUILDING half fails soft. An absent register reads as "nothing under
##   construction", which is the truth about every version-22 save, because those
##   games had no project verb. `measures` at V1.3c, `sector_investment` at V1.6e.
##
##   the DONE half does not. A France that finished the rail spine and the grid has a
##   permanent claim on its own trend, and an absent register erases the record of it.
##   Re-deriving on load cannot rescue it, because there is nothing left to derive
##   from: the accumulator below is the only other trace and it is not content.
##
## So the bump is earned by the half of one dictionary, and tests/test_save_load.gd
## asserts the two halves separately -- a single combined check would let either half
## be quietly wrong.
var projects := {}

## Points of trend growth per year, accumulated across every COMPLETED project and
## added to the target Economy._update_potential_shift() converges toward.
##
## `law_potential_target_pct`'s exact shape, three fields up, and the match is the
## argument rather than a resemblance: a passed law and a finished project are the
## same act -- a one-time decision producing a permanent addend -- so the two are
## written the same way, bounded alike (projects_constants.PROJECT_POTENTIAL_MAX_PCT
## against legislature_constants.POTENTIAL_TARGET_MAX_PCT) and read at the same site.
##
## *** THIS IS WHY V1.6f ADDS NO THIRD QUANTITY REACHING TREND. *** V1.6e had to add
## investment_constants.SECTOR_TREND_MAX_PCT because Investment.sector_trend_shift()
## reaches Economy.trend_pct() directly. This does not: it reaches the TARGET of a lag
## economy_constants.SHIFT_MAX_PCT already bounds, so the amended clause in that
## constant's comment stays true as V1.6e left it.
##
## Serialised, and derivable in principle from `projects` plus the content -- which is
## exactly `law_potential_target_pct`'s position, derivable from the passed-law list
## plus data/laws/. Stored for the same reason: Economy._update_potential_shift()
## takes no loader, so a derived read there would mean handing one to the economy.
var project_potential_target_pct: float = 0.0

## V1.6f's computed spending line, recomputed once a month by Projects.tick_month()
## and read from here rather than called for -- the FIFTH to take this route after the
## bloc transfer, the deployment bill, the subsidy bill and the investment bill,
## cached for the same reason: budget.gd's recompute() reads it a month late on
## purpose, because `deficit_pct_gdp` is one of this verb's own precondition fields
## and a bill that widened the deficit inside the month would close a loop.
##
## Earns nothing on the rule -- recomputed from `projects` and the content on the
## first tick after a load -- and is serialised anyway so a save read back and never
## ticked reports the budget it was saved with. `investment_bill_pct_gdp`'s case.
var project_bill_pct_gdp: float = 0.0

## The most recent project action, for the panel to read after acting.
## `last_investment_result`'s shape, and not serialised for its reason either: it is a
## display record of something that has already happened to the register.
var last_project_result := {}

# --- Energy (V2.8) --------------------------------------------------------------

## plant id -> {"source_id": String, "region_id": String, "lon": float,
## "lat": float, "connection": float, "months_left": int, "done": bool}.
## Energy.ENTRY_KEYS is the shape and tests/test_save_load.gd asserts against it, as
## it does for `projects`.
##
## THE COORDINATE IS THE PLAYER'S AND IS STORED, which is the opposite of
## Projects.site_region()'s derive-every-read -- and the two are opposites because
## the two facts are opposite kinds. A project's site is CONTENT, so a stored copy
## could disagree with data/nations/ and the content must win. A plant's site is an
## ACT, so there is nothing for it to disagree with, and what a re-imported geometry
## must NOT do is re-price a station the player was already quoted for.
var plants := {}

## Monotone, so a decommission can never free an id a later plant re-uses and make
## two different stations one row in the ledger. Absent reads 0, correct for every
## version-30 save because those games had no plants at all.
var plant_seq: int = 0

## The measured baseline the register is a deviation against. CONTENT-DERIVED and
## therefore serialised, on V1.6a's finding: NationState.from_dict() rebuilds from
## the dictionary alone and never sees the loader, so a static fact that lives on
## this class is already in the save whether or not the module is stateless.
var start_energy_mix := {}
var start_import_dependency_pct: float = 0.0
var energy_kwh_per_capita: float = 0.0

## V3.5. The measured per-capita baseline, same content-derived-static rule as the
## three above it: serialised because from_dict() never sees the loader.
var start_co2e_per_capita_t: float = 0.0

## Written every tick from the mix, for the readouts and the accord's rule field --
## import_dependency_pct's own shape, and Energy.tick_month() runs BEFORE
## Orgs.tick_month() (budget.gd:388 then :396), so the council judges settled books.
var co2e_per_capita_t: float = 0.0

## Recomputed from `plants` and the content on the first tick. Serialised so a save
## reloaded and not yet ticked reports the budget it was saved with --
## project_bill_pct_gdp's case exactly.
var energy_bill_pct_gdp: float = 0.0

## Written every tick from the register, for the readouts. Not read back by
## src/sim/.
var import_dependency_pct: float = 0.0
var energy_impulse_pct: float = 0.0

## Display record of the last order or decommission. Not serialised --
## last_project_result's case.
var last_energy_result := {}

# --- The campaign phase (V1.7a) --------------------------------------------------

## Effort ids currently in the field. Written by Campaign.execute() and by
## Campaign.tick_month()'s clear, and by nothing else -- the single-writer discipline
## `share`, `state_share`, `regulation_burden`, `gini_index`, `sector_investment` and
## `projects` are each held to.
##
## AN ARRAY AND NOT A DICTIONARY, unlike every other register on this page, because
## there is nothing per-entry to remember. What an effort costs and who it reaches are
## AUTHORED in data/campaign-actions/, and how long it has run is already in the
## accumulator below -- so an entry would carry only its own key. `projects` needs a
## dictionary because months_left and done are live per project; this does not.
##
## EARNS NO SAVE_VERSION BUMP, and the rule is applied literally: absent it reads as
## "no effort in the field", which is the truth about every version-23 save, because
## those games had no campaign verb. `measures` at V1.3c, `pacts` at V1.3g,
## `appointments` at U6a, `sector_investment` at V1.6e. Serialised anyway, because a
## verb writes it and no tick can recompute it -- a save that dropped it would silently
## stand down a campaign in progress and hand the player back its bill.
var campaign_running: Array = []

## Effort ids that have been in the field at any point in the CURRENT run-up, whether
## or not they still are. Written by Campaign.execute() and by Campaign.tick_month()'s
## clear, and by nothing else -- `campaign_running`'s single-writer discipline.
##
## AN EFFORT GETS ONE RUN PER WINDOW, and this register is the whole of that rule.
## Without it, start/stop/start inside one month re-paid the action's authored
## `bloc_offset` on every cycle -- a permanent accumulator charged at the press against
## a bill charged over the running set once a month, so the loop cost nothing and
## elapsed no time. See Campaign._op_legal().
##
## EARNS THE BUMP TO 24, where `campaign_running` beside it earned nothing, and the
## reason is the one this list has used since V1.3a: absent it reads as "no effort has
## run yet" while the serialised `campaign_running` says one is in the field, so the
## two disagree and the disagreement is the exploit. A save reloaded inside a run-up
## hands every spent effort back, which makes save-scumming an unbounded version of the
## press loop the register exists to close -- `diplo_months_to_act` at U6a, whose
## absent value read as "act now", and the spent-days counter U6a's probe deleted
## before it could hand a reloading player their month back.
var campaign_started: Array = []

## Bloc → accumulated mobilisation, as a shift in the LOG-ODDS of that bloc turning
## out. Read by Campaign.turnout_of(), which Elections.vote_share() calls in place of
## election_constants.BLOC_TURNOUT's raw figure.
##
## *** THE FIRST WRITER OF TURNOUT THIS PROJECT HAS EVER HAD, and that is why the
## campaign lands here rather than on approval. *** BLOC_TURNOUT is read in exactly two
## places, both inside vote_share(), and nothing has ever moved it -- so this register
## has no double count to resolve, where a campaign term on ns.bloc_approval would have
## been a second writer of the one quantity the whole game is judged on. See
## docs/campaign-model.md.
##
## An absent bloc reads 0.0 and turnout_of() returns the authored constant BIT-FOR-BIT,
## which is what keeps the nine non-playing nations and every pre-V1.7a test identical.
##
## EARNS NO BUMP, for `campaign_running`'s reason exactly, and it is serialised for a
## second one the array does not have: it is spent at the ballot box, so a save reloaded
## in the last month of a run-up would otherwise go to the vote with a campaign the
## player has already paid for and no longer has.
var campaign_mobilisation := {}

## V1.7a's computed spending line, recomputed once a month by Campaign.tick_month() and
## read from here rather than called for -- the SIXTH to take this route after the bloc
## transfer, the deployment bill, the subsidy bill, the investment bill and the project
## bill, cached for the same reason: budget.gd's recompute() reads it a month late on
## purpose, because `deficit_pct_gdp` is one of this verb's own precondition fields and
## a bill that widened the deficit inside the month would close a loop.
##
## THE SECOND BILL IN THIS PROJECT THAT STOPS, and it stops on a date the player cannot
## move. V1.6f's project bill ends when the work does, which is a length the player
## chose by choosing the project; this one ends at the vote.
##
## Earns nothing on the rule -- recomputed from `campaign_running` and the content on
## the first tick after a load -- and is serialised anyway so a save read back and never
## ticked reports the budget it was saved with. `project_bill_pct_gdp`'s case.
var campaign_bill_pct_gdp: float = 0.0

## V2.6b2. Where each running effort's meetings are held: effort id -> region id,
## written at the press, erased at stop, cleared with the rest of the register when the
## window closes. Serialised for campaign_running's reason -- a verb writes it and no
## tick can recompute it -- and EARNING THE BUMP TO 30 beside the register below: a
## running effort whose site was dropped falls back to the factor-1.0 national reach,
## so a reloaded save would disagree with its own panel and its own map about where
## the president is, which is a silent lie rather than a lost figure.
var campaign_sites := {}

## V2.6b2. Region id -> the fraction of that region's attention the player's own
## meetings already hold, in [0, 1]. The saturation counter docs/siting-model.md
## section 11 demanded: a memory of the player's own acts rather than an opinion, and
## the only honest breaker of the reach-per-day dominance the tour probe measured.
## Accrued +1.0 (clamped) per meeting month by Campaign._accrue(), decaying on
## SATURATION_HALF_LIFE_MONTHS by Campaign._decay() every month whether or not a
## campaign runs, and NOT cleared when the window closes -- attention persists.
##
## EARNING THE BUMP TO 30, for `campaign_started`'s reason one level up: absent it
## reads as "nobody has been spoken to", and a save that dropped it would hand every
## saturated region back at full reach -- the tour un-spoken, save-scummed.
var campaign_saturation := {}

## The most recent campaign action, for the panel to read after acting.
## `last_project_result`'s shape, and not serialised for its reason either: it is a
## display record of something that has already happened to the register.
var last_campaign_result := {}

# --- Campaign promises (V1.7b) -----------------------------------------------------

## The promises this nation has on the books. One entry per promise, each carrying the
## {field, op, value} triple it is judged on, the two dates that bound the term it
## binds, and how many of that term's months it has stood broken. Written by
## Pledges.execute() and Pledges.tick_month() and by nothing else.
##
## *** IT HOLDS NO CONTENT. *** The breach rates and the promise's own display name
## live in data/pledges/ and are read through the loader on every tick, so a save
## round-trips the DECISION and never the ladder -- the property tests/test_pledges.gd
## pins, and V1.4a's, V1.6e's, V1.6f's and V1.7a's tests before it.
##
## *** THE TWO DATES ARE FROZEN RATHER THAN DERIVED, and that is the one place it
## matters. *** Elections.tick_month() pushes next_executive_* a full term forward the
## moment the incumbent wins, so a promise deriving its own deadline from that field
## would move its own goalposts on the night it was won.
##
## EARNS NO SAVE BUMP. Absent it reads as "nothing promised", which is the truth about
## every version-23 save because those games had no pledge verb -- `measures` at
## V1.3c, `pacts` at V1.3g, `appointments` at U6a, `campaign_running` at V1.7a. It is
## serialised regardless and that half is not free: a verb writes it, no tick
## recomputes it, and the reward has ALREADY been paid, so a save that dropped it would
## hand the player the upside of every promise they had made and delete the liability.
## `regulation_burden`'s case at V1.4b, and tests/test_save_load.gd checks that premise
## rather than asserting it.
var pledges: Array = []

## The most recent pledge action, for the panel to read after acting.
## `last_campaign_result`'s shape, and not serialised for its reason either.
var last_pledge_result := {}

# --- The government's programme (V4.1) ----------------------------------------------

## The programme register: the entries this nation has CHOSEN, at most one per term,
## each carrying the six decision keys -- which entry, which term, how many months
## live, the status, and the (term, month-of-term) pair the conclusion happened in.
## Written by Programme.choose() and Programme.tick_month() and by nothing else.
##
## *** IT HOLDS NO CONTENT. *** The triggers, the goal and every effect live in
## data/programme/ and are read through the loader on every read, and progress is
## DERIVED from the live figure -- Programme.progress_of() -- never stored, because
## a cached value could disagree with the figure it reads and then the panel lies.
## tests/test_programme.gd pins the six-key shape and the round trip.
##
## EARNED THE BUMP TO 35, taken at Task 3 with the absences rather than at the
## pulse wiring -- the version gate is shut on the day PROGRAMME_SPAN goes live,
## before the first save that could hold a priced register is ever written. The
## case is game_state.gd's SAVE_VERSION comment's: a save that dropped this
## register un-prices a term the player already lived. Until Task 2 the pledges
## precedent held exactly -- a version-34 save was made by code with no programme
## verb on any tick path, so "absent reads []" was the truth about every save
## that existed -- and it is serialised for the verb's reason regardless: a verb
## writes it and no tick recomputes it.
var programme: Array = []

## The last term a programme was chosen in, -1 meaning never. The one-choice-per-
## term gate is a comparison against terms_served -- a level read, so there is no
## "has chosen this term" flag anywhere and nothing lifts one.
var programme_chosen_term: int = -1

## The bounded [-1, 1] stock the conclusion pulses feed -- +1 a completion, -1 a
## failure, 0 an invalid -- decayed monthly at PROGRAMME_DECAY_RATE and read by
## Opinion as PROGRAMME_SPAN * stock beside the honeymoon
## (docs/programme-model.md section 3). Accumulated state nothing recomputes, so
## serialised for corruption's reason: a save that dropped it would re-price every
## delivery the player already lived. Typed-cast in from_dict() -- a stock of 1.0
## comes back from JSON as the int 1.
var programme_stock: float = 0.0

# --- The character layer (V4.3) ------------------------------------------------
## SIX REGISTERS OF PERSON STATE, and they are the whole of what a save remembers
## about what the player did to the people in it. Content says who a person IS --
## traits, ambition, kind, party, wants (src/core/person.gd, data/people/) -- and
## never moves; these say what has happened to them. The split is
## docs/people-model.md section 14's, and it is V1.4a's content/state line drawn
## around a person rather than a firm.

## person id -> loyalty in [-1, 1]. Written by characters.gd (Task 3); nothing
## writes it yet.
##
## EARNS THE SAVE_VERSION BUMP TO 36, with the four below. Absent it reads as an
## empty register, so every person reads 0.0 -- "nobody remembers anything you did
## to them" -- which is the V1.6a load-bearing test stated in the game's own voice
## and `programme_stock`'s case exactly: a warm, neutral memory where the save
## should carry a history the player spent a term writing. Re-deriving on load
## cannot rescue it, because there is nothing outside this register to derive it
## from -- the acts that wrote it are not stored either.
var person_loyalty: Dictionary[String, float] = {}

## person id -> political standing in [0, 1]. A person's weight in the acts they
## take: the challenge threshold and how far an endorsement carries. Written by
## Characters.init_nation (cleared and seeded); nothing else writes it -- the
## standing seed is the register's only content.
##
## Earns the bump for the field above's reason, stated once. A dropped standing
## register reads every person at 0.0 -- nobody carries any weight -- so a
## deposed or promoted figure reverts to the anonymous bench.
var person_standing: Dictionary[String, float] = {}

## person id -> accumulated grudge in [0, 1]. The slow channel: a denied want and a
## betrayal add to it, and it decays on the half-life characters.gd owns. Written
## by characters.gd's adjusters and decay (init_nation seeds it zero).
##
## Earns the bump with the pair above, and it is the one a lost save is most
## visible in: a dropped register forgives every grudge the player earned, which is
## a second chance the game never granted.
var person_grudges: Dictionary[String, float] = {}

## party id -> the person id currently leading it, where a leadership challenge has
## moved the party off its authored `leader_person_id`. Empty means the authored
## leader, which is the truth about every version-35 save. Written by the
## challenge act (characters.gd) when a leadership contest fires.
##
## EARNS THE BUMP ON ITS OWN ARGUMENT, which the loyalty dict does not have: an
## absent override is not neutral, it RESURRECTS A DEPOSED RIVAL mid-term. The
## player watched a leadership change; the save, dropped, hands the party back to
## the person they removed, and the panel and the party's own edge disagree with
## the world they left.
var party_leader_override: Dictionary[String, String] = {}

## person id -> the party they now sit in, where a defection has moved them off
## their authored `party_id`. Empty means the authored affiliation. Written by
## the defect act (characters.gd) when a person crosses the party line.
##
## EARNS THE BUMP for the override's reason one level down: an absent entry is not
## "no change", it SILENTLY RE-AFFILIATES a defector the save remembers -- the
## person walks back to the party they left, and a bench that had been changed by
## the block's most consequential verb reverts to its authored shape.
var person_party_override: Dictionary[String, String] = {}

## person id + "|" + want object -> was the want served last month (bool).
## The EDGE-TRIGGER's memory: a grudge fires when a want TURNS denied and a
## loyalty pulse when it TURNS served, so the register the month-over-month
## comparison reads must survive the save -- a denial straddling a save would
## otherwise re-fire its grudge on every load. Absent it (a version-35 save)
## every want reads as its own current state, so the FIRST post-load month
## writes no pulse -- which is the honest reading: the load knows nothing
## about what the save's last month saw.
var person_want_state: Dictionary[String, bool] = {}

# --- The president's registers (V5.2a) ------------------------------------------
## SEVEN REGISTERS OF WHAT HAS PASSED BETWEEN THIS NATION'S LEADER AND A PERSON,
## each an edge from the president to one person (theirs, or a foreign head met)
## or a figure of the president alone -- never person to person (spec C1).
## src/sim/president.gd is the only writer and the only reader that combines
## them with content (people-model 14.9). EVERY ONE IS absent_ok, no bump: each
## is a delta over content, so an absent register is "nothing has happened yet"
## -- a stranger, neutral, no bond, no money moved, nothing promised, nothing
## left behind -- which is the truth about every save made before V5.2a.

## person id -> how well the president knows them, [0, 1].
var person_knowledge: Dictionary[String, float] = {}

## person id -> how they feel about the president personally, [-1, 1]. Not
## loyalty, which is political: a rival can be loyal to the line.
var person_rapport: Dictionary[String, float] = {}

## person id -> an explicit bond (friend, close, rival, enemy, affair). Stranger
## and acquaintance are never stored: they are read off knowledge.
var person_bond: Dictionary[String, String] = {}

## person id -> personal wealth gained or lost, EUR millions, over the authored
## Person.wealth_eur_m.
var person_wealth_delta_eur_m: Dictionary[String, float] = {}

## party id -> party funds gained or spent, EUR millions, over the authored
## Party.funds_eur_m.
var party_money_delta_eur_m: Dictionary[String, float] = {}

## The president's promises and IOUs in flight, one row each:
## {kind, person_id, object, made_month, due_month}, months absolute.
var commitments: Array[Dictionary] = []

## The hidden evidence a corrupt act or an affair left, one row each:
## {kind, person_id, size, month}, month absolute.
var exposure_evidence: Array[Dictionary] = []

# --- Audience requests (V5.2b) ----------------------------------------------------
## The REQUESTS lane: every request a person of this nation made to the
## president, pending and recently resolved, one row each --
## {id, person_id, object, stance, arrived_month, deadline_month, status, date,
## resolved_month}, months absolute. Written by src/sim/audiences.gd alone; the
## lane the inbox shows IS this register, so nothing between them can drop one.
## absent_ok, no bump: before V5.2b nobody asked, which is what absent reads.
var audience_requests: Array[Dictionary] = []

## person id -> the absolute month they last asked (the per-person cooldown).
## absent_ok for the same reason: nobody has asked yet.
var audience_asked_month := {}

# --- The commodity layer (V4.6) -------------------------------------------------
## The nation's commodity state: what it can make, what it wants, what it made,
## what it bought and sold, and the ONE world price vector. Written by
## commodities.gd and by nothing else (single writer, pinned by
## tests/test_commodities.gd reading src/), seeded by Commodities.init_nation at
## new game.
##
## SEVEN KEYS, and the shape is the module's contract rather than this field's:
##   capacity           good id -> units/month the nation COULD make. This is the
##                      SEED-TIME SNAPSHOT (month-0 sector output through the
##                      recipe structure): the tick derives capacity FRESH from
##                      the live `sector_output` every month and never reads this
##                      key back, so it is a record of how the game began and not
##                      a live stock.
##   demand             good id -> units it wants this month, at the live price.
##   output             good id -> units made NET of what this nation's own
##                      downstream recipes consumed of it, so the figure is value
##                      added's own numerator rather than a gross production count:
##                      a tonne of iron ore that went into this month's steel is
##                      not also counted as iron ore output.
##                      (Gross production would double-count every intermediate,
##                      which is why the net form is stored.)
##   surplus            good id -> output minus demand where that is positive,
##                      i.e. what it has to sell; 0.0 where it does not.
##   trade              good id -> units bought (positive) or sold (negative).
##   price              good id -> the world price (EUR/unit), one vector shared
##                      by every nation and clamped to
##                      commodity_constants.PRICE_BAND of base.
##   value_added_eur_bn what this month's output was worth, EUR bn -- the CHANGE
##                      the block models (the step-0 verdict: levels are not
##                      reproducible from recipes, deltas are). No SIM module
##                      reads it; the readers are the UI surfaces (the
##                      Commodities panel and the two map layers).
##
## SERIALISED, SAVE_VERSION 37, and it earns the bump rather than riding one: an
## absent register reads as a nation that can make nothing and holds no price
## vector, which is the `region_gdp_eur_bn` class and not the neutral-empty one.
## The whole dictionary travels under its own key, and it reaches from_dict()
## through `nation_field_readers.commodity_state()` -- which casts and re-owns it, the
## character registers' discipline applied to a register that is a dictionary of
## dictionaries rather than a typed flat map.
##
## THE LAZY SEED IN Commodities.tick_month() STAYS, and the reason is narrower
## than "backwards compatibility": save_manager refuses a mismatched version
## outright (V3.3's argument at the gate), so no pre-37 save reaches this field
## through the load path at all. What the branch still covers is an ns arriving
## from a payload with the key absent -- a stripped dictionary, a hand-built
## fixture, or a caller that built a NationState before the first tick -- and it
## is deterministic for `init_nation`'s own reason: a pure function of the
## nation's measured mix. tests/test_commodities.gd pins that it agrees with a
## fresh init to the bit.
var commodity_state: Dictionary = {}

## V1.5a. Spending line → the quality of that service as a stock, in points of GDP,
## converging on what the nation actually spends on it delivered. Written by
## Society.tick_month() and by nothing else. Keyed by society_constants.QUALITY_KEYS,
## which holds `health` alone today for a reason that is the design rather than a
## limitation: `defence` already has military_capability and `education` and
## `infrastructure` already share potential_shift_pct, so a second stock on either
## would be that lever twice.
##
## EARNS THE SAVE_VERSION BUMP, 15 → 16, and it is the only one of the three fields
## here that does. Absent it reads 0.0 against a France that has spent 11.0 % of GDP
## on health for decades — every reader then sees a country whose hospitals have
## ceased to exist, and the satisfaction term reads a collapse the player did not
## cause. `military_capability`'s case at V1.3g verbatim, and it is the strongest
## form of it: equilibrium-init does not rescue the field, because re-deriving it on
## load would silently erase an accumulated decline the player spent a term earning.
var service_quality := {}

## The reference every quality satisfaction term is measured against — captured at
## init from the equilibrium, so `service_quality - start_service_quality` is exactly
## 0.0 at new game. `start_deficit_pct_gdp`'s and `start_bloc_burden`'s treatment.
##
## EARNS NOTHING. It is recomputed at init from the `spending_pct_gdp` every nation
## file already authors, so like a firm's authored share it round-trips through
## `data/nations/` rather than through the save. Serialised all the same, because a
## save reloaded before its first tick must measure against the same reference it was
## saved with rather than against a fresh equilibrium.
var start_service_quality := {}

## V1.5a. Signed accumulated corruption, clamped to
## ±society_constants.CORRUPTION_MAX. Written by Legislature.apply() through the
## `society` effect channel and by nothing else in the project — `regulation_burden`
## above has the identical discipline, and `Society` only ever reads this.
##
## Read as a factor on the quality stock's TARGET, not on the satisfaction delta.
## Cabinet.effectiveness() multiplies deltas only, so a corruption factor placed
## there would cost a player who never moves a spending line exactly zero.
##
## EARNS NOTHING. Absent it reads 0.0 — no corruption — which is correct for every
## version-15 save, because those games carried no `society` law to pass. `measures`
## at V1.3c, `pacts` at V1.3g, `appointments` at U6a and `regulation_burden` at
## V1.4b. Serialised regardless, for V1.4b's reason: a law writes it once and no tick
## recomputes it, so a save that dropped it would silently repeal every
## anti-corruption act the assembly ever passed.
var corruption: float = 0.0

## V1.5b. The share of the population aged 0–14 and 65+, as fractions. Written by
## Demography.tick_month() and by nothing else. The 15–64 share is NOT here: it is
## the residual `1 - young - old`, derived by Demography.working_share() at every
## read, so the three sum to 1.0 by construction and a conservation bug is
## structurally impossible — _apply_growth_to_sectors()'s discipline, which keeps
## sector output summing to GDP with no reconciliation.
##
## BOTH EARN THE SAVE_VERSION BUMP, 16 → 17. Absent they read 0.0, which is not a
## neutral default but a different model: the working share becomes 1.0, the
## dependency ratio 0.0, the denominator under the quality stock 0/start, and the
## labour force the entire population. `military_capability`'s case at V1.3g and
## `eu_member`/`neighbours`' at V1.3b — a reloaded game running a different model
## from the one that saved it. Init-from-content does NOT rescue them, for
## `service_quality`'s reason one session earlier: re-deriving on load would erase a
## drift the player spent a term living through.
var young_share: float = 0.0
var old_share: float = 0.0

## The references the dependency factor is measured against — captured at init, so
## Demography.dependency_factor() is exactly 1.0 at new game for all ten nations.
## `start_service_quality`'s treatment and `start_bloc_burden`'s.
##
## EARN NOTHING. Recomputed at init from the `imported.cohorts` every nation file now
## carries, so they round-trip through `data/nations/` rather than through the save.
## Serialised all the same, for start_service_quality's reason: a save reloaded
## before its first tick must measure against the reference it was saved with.
var start_young_share: float = 0.0
var start_old_share: float = 0.0

## Static per-nation facts copied off `imported.cohorts` at init and never written
## again — the treatment `eu_member` and `neighbours` get, and for the same reason:
## it is what lets Demography take no loader, so Budget.project() runs the real model
## forward on a copy and gets the real answer.
##
## `pop_growth_pct` replaces economy_constants.POP_GROWTH_PCT, one flat 0.15 shared by
## all ten. Measured, it spans Italy's **−0.238** to Luxembourg's **+1.938**, so the
## constant had every nation in the roster growing and one of them shrinks.
##
## EARN NOTHING, and they are the clearest case of it on this list: they are content.
var young_share_per_yr: float = 0.0
var old_share_per_yr: float = 0.0
var participation_share: float = 0.0
var pop_growth_pct: float = 0.0

## V1.5b. Signed accumulated migration stance, clamped to
## ±demography_constants.MIGRATION_STANCE_MAX. Written by Legislature.apply() through
## the `society` effect channel and by nothing else — `corruption` above has the
## identical discipline, and Demography only ever reads this.
##
## The second term on `effects.society`, which V1.5a declared as schema two later
## sessions would read rather than one session's private field. This is the first of
## them, so the channel needed no widening beyond one key.
##
## EARNS NOTHING. Absent it reads 0.0 — no standing migration policy — which is
## correct for every version-16 save, because those games had no migration law to
## pass. `corruption`'s case one session earlier. Serialised regardless and for
## `corruption`'s reason: a law writes it once and no tick recomputes it, so a save
## that dropped it would silently repeal every migration act the assembly passed.
var migration_stance: float = 0.0

## V1.5c. The Gini index, drifting at its own measured rate, and the reference the
## deviation is taken against. Written by Demography.tick_month() and by nothing else —
## `young_share`'s discipline, and it lives beside it rather than beside the unrest
## fields below because this layer owns measured facts about the POPULATION and the
## session that prices a fact owns the price rather than the fact.
##
## THE DECLARED STOPGAP docs/tiers/v1.md §5 books to V1.5c, with §6 named as its real
## writer. That row says the index "cannot be DERIVED", which is true — there are no
## brackets, no deciles and no capital/labour split anywhere — and it does not follow
## that it has to be invented: the provider behind every other figure in
## `imported` publishes it for all ten. Nothing the player does moves this number, and
## that is the mechanical form of the §5/§6 split rather than a limitation.
##
## `gini_index` EARNS THE BUMP, 17 → 18, and `start_gini_index` earns nothing.
## `young_share`'s split exactly: absent, the live index reads 0.0 against a France
## sitting at 31.8, so the deviation the whole term is built on is measured from a
## country with no inequality at all — and re-deriving on load would erase a drift the
## player spent a term living through, which is `service_quality`'s reason. The
## reference is recomputed at init from `imported.inequality` and round-trips through
## `data/nations/`; serialised regardless, `start_young_share`'s treatment.
var gini_index: float = 0.0
var start_gini_index: float = 0.0

## Static per-nation fact off `imported.inequality`, never written again —
## `young_share_per_yr`'s treatment and standing. SIGNED, and that is the roster rather
## than a courtesy: six of the ten are growing more equal (NLD −0.417, ESP −0.350) and
## four less (DEU +0.329, CHE +0.214), so a one-directional model would be wrong about
## most of Europe. EARNS NOTHING — it is content.
var gini_index_per_yr: float = 0.0

## V1.5c. The grievance index, 0–100, written by Unrest.tick_month() and by nothing
## else. Exactly 0.0 at new game for all ten nations, because every term of its target
## is a deviation against the nation's own start — `trade_baseline_by_partner`'s idiom
## and `delivery_factor`'s, and what lets the whole layer go live with the shared
## balance regimes moving only where an act actually fires.
##
## EARNS THE SAVE_VERSION BUMP, 17 → 18. Absent it reads 0.0 — a perfectly calm France
## — which silently ends a crisis the player spent a term living through, and
## init-from-equilibrium does not rescue it for `service_quality`'s reason at V1.5a:
## re-deriving on load erases the accumulation, which IS the state.
var unrest_pct: float = 0.0

## Months until industrial action can fire again. Written by Unrest.tick_month().
##
## ALSO EARNS THE BUMP, and separately, which is why the two are asserted separately in
## tests/test_save_load.gd. Absent it reads 0, and 0 means *act now* — so a reloaded
## save fires a strike in its first month regardless of what the player was doing.
## U6a's `diplo_months_to_act` case, where an absent counter read as "act now" and fired
## nine acts in one month.
var unrest_cooldown_months: int = 0

## Points of annual growth the standing industrial action is costing, negative, decaying
## toward zero. A SIXTH addend in economy.gd's growth sum and the only price unrest
## charges — see docs/unrest-model.md §4 for why there is no direct opinion term.
##
## DECAYING and not sustained, which is the distinction economy.gd's own comment draws
## about the five terms already there: a measure in force and a subsidy in force are
## standing conditions, and a strike is a SHOCK. Decayed by Unrest.tick_month() rather
## than by Economy, so this field keeps one writer.
##
## EARNS NOTHING. Absent it reads 0.0 — a shock already over — which is soft and
## self-correcting within months, `trade_baseline_by_partner`'s case.
var unrest_impulse_pct: float = 0.0

## What the country's grievance takes off every bloc's approval target, on the [-1, +1]
## scale opinion.gd's satisfaction terms use. Written by Unrest.tick_month() and read by
## opinion.gd from here rather than by calling Unrest — `deployment_opinion_load`'s
## arrangement, and here it is what keeps the two files out of a preload cycle.
##
## THE PRICE THE PROBE FORCED. V1.5c was designed with an output-only price, on the
## premise that approval would fall through `growth` and `jobs`; measured on an isolated
## path, fourteen years at maximum grievance costs 4.94 % of GDP and 0.42 points of
## workers approval, because this opinion model prices RATES and a permanent LEVEL loss
## is invisible to it. See unrest_constants.UNREST_OPINION_SCALE.
##
## EARNS NOTHING. Absent it reads 0.0 and Unrest.tick_month() recomputes it from
## `unrest_pct` on the next tick, so it fails soft for exactly one month —
## `unrest_impulse_pct`'s case and `trade_baseline_by_partner`'s.
var unrest_opinion_load: float = 0.0

## V1.5c. Signed accumulated settlement stance, clamped to
## ±unrest_constants.SETTLEMENT_STANCE_MAX. Written by Legislature.apply() through the
## `society` channel and by nothing else — the THIRD term on that channel, after
## `corruption` at V1.5a and `migration` at V1.5b, and the second piece of evidence that
## V1.5a was right to call it schema rather than one session's private field.
##
## It is what makes unrest CLOSABLE. Without it the only lever pointed at a strike is a
## spending increase, and society_probe.gd table (c) established that raising a line
## necessarily widens the deficit — so the player could buy industrial peace only by
## opening `public_finances`, and unrest would be the permanent monotone charge
## docs/defence-model.md names.
##
## EARNS NOTHING. Absent it reads 0.0 — no standing settlement — correct for every
## version-17 save, because those games had no settlement law to pass.
## `migration_stance`'s case one session earlier, and serialised for its reason.
var settlement_stance: float = 0.0

## V1.5d. Signed accumulated press-freedom stance, clamped to
## ±media_constants.PRESS_FREEDOM_MAX. Written by Legislature.apply() through the
## `society` channel and by nothing else — the FOURTH term on that channel, after
## `corruption`, `migration` and `settlement`. A channel carrying four registers written
## by four different sessions is schema rather than luck, which is what
## docs/society-model.md section 3 bet on when it opened the channel with one term.
##
## TWO PRICES, ONE VERB, which is docs/coercion-model.md's shape: it scales the framing
## deviation below, and it adds a signed term to Unrest.unrest_target(). The second is
## this session's answer to "press freedom as a dial with LEGITIMACY costs" — there is
## no legitimacy quantity and the row handed V1.5d the choice of inventing one or
## dropping the clause. Neither: legitimacy is willingness to accept your rule outside
## the ballot box, which is the grievance V1.5c already built. See
## media_constants.PRESS_UNREST_BETA.
##
## EARNS NOTHING. Absent it reads 0.0 — no standing press law — correct for every
## version-18 save, because those games had none to pass. `settlement_stance`'s case one
## session later, and serialised for its reason: a law writes it once and no tick
## recomputes it, so a save that dropped it would silently repeal the act.
var press_freedom: float = 0.0

## V1.5d. Per-bloc salience gain, keyed by opinion_constants.BLOC_KEYS. Written by
## Media.tick_month() and read by opinion.gd from here rather than by calling Media —
## `deployment_opinion_load`'s and `unrest_opinion_load`'s arrangement for the third
## time, and here it does two jobs at once: it keeps opinion.gd out of a preload cycle
## AND it keeps opinion.gd from needing a DataLoader, which it has never had and which
## would have cost fourteen call sites to give it.
##
## Every entry is exactly opinion_constants.SALIENCE_GAIN at new game for all ten
## nations, and forever for the seven with no data/outlets/ file. The size-weighted mean
## across the six blocs is exactly SALIENCE_GAIN in EVERY state, because the deviation
## media.gd computes is anchored on that mean — which is what lets this session change
## what the electorate notices without re-baselining a constant measured at S10.
## tests/test_media.gd asserts both with exact equality.
##
## EARNS NOTHING. Absent it reads empty and Media.tick_month() rewrites it in full on
## the next tick, so it fails soft for exactly one month — `unrest_opinion_load`'s case.
var framing_gain: Dictionary = {}


# --- V1.1e: the second chamber ------------------------------------------------

## Whether this nation has one at all. Copied from the nation's own
## `government.upper` block, which Luxembourg does not carry -- absent-means-
## unicameral, the shape `has_executive` already uses one field group up.
##
## EARNS THE BUMP, and for `election_system`'s reason at V1.7c rather than for a
## reason of its own: from_dict() never sees the loader, so a content-derived static
## fact that is not serialised cannot be re-derived on load. Absent it reads false and
## a reloaded France has no Senate -- a different model from the one that saved it.
var has_upper_house: bool = false
var upper_chamber_name: String = ""
var upper_seats: int = 0
var upper_ordinary: String = ""
var upper_amendment: String = ""

## The chamber's composition, as a party-keyed SHARE rather than as seats.
##
## ONE RECORD OF ONE FACT. The seats are ElectoralSystems.pr_national() over this,
## derived by Chambers.seats() at every read the way Defence.allies() derives an
## alliance -- storing both would be two records of one thing, and the lag has to run
## on the share anyway, because a partial renewal of integers is a rounding rule
## pretending to be a model.
##
## EARNS THE BUMP. Absent it reads empty, Chambers.seats() returns an empty chamber,
## and an empty chamber refuses everything or passes everything depending on which way
## the comparison falls -- `military_capability`'s case at V1.3g. Elections rewrite it,
## but only at an election, which for France is up to five years away.
var upper_share: Dictionary = {}

## Bills the second chamber has refused and not killed: law id -> {"months":
## months remaining, "origin": "player"|"assembly"} -- the ultra pass-2 shape.
## Counted down by Legislature.tick_month(), which every harness already calls.
## The origin is the release price's gate: the override charge is the
## GOVERNMENT's insistence priced, so a held private member's bill (the
## assembly's own writer in statute.gd) releases free.
##
## EARNS THE BUMP, and it is `referendum_pending`'s case at V1.7c and
## `event_pending`'s at V1.8: absent, the register reads empty and a bill the Senate
## refused simply is not there any more -- a FREE ESCAPE from the one obstacle this
## session adds, available to anyone who saves and loads.
var held_bills: Dictionary = {}


# --- V1.1e: the judiciary -----------------------------------------------------

## Whether this nation's courts may strike down primary legislation --
## judiciary_constants.KNOWN_REVIEWS. `has_upper_house`'s case exactly: content-
## derived, static, and unreachable from from_dict() without the loader, so absent it
## reads "" and the dispatch falls through to no review at all, which is a silently
## different constitution rather than a neutral default.
var judicial_review: String = ""

## Rule of law, 0-100, docs/tiers/v1.md section 5's own statistic handed to section
## 1's judiciary bullet at V1.5's decomposition. Initialised from the nation's own
## imported.institutions.rule_of_law_score and moved ONLY by Legislature.
## apply_effects() through the fifth effects.society term -- `regulation_burden`'s
## single-writer shape, with an authored base where that one starts at zero.
##
## EARNS THE BUMP, and it is `service_quality`'s case at V1.5a in its strongest form:
## absent it reads 0.0 against a France whose courts the World Bank scores 73.8, so
## every law passes and the session's whole gate is gone -- AND re-deriving it from
## content on load does not rescue it, because that would erase the erosion a player
## spent a term buying.
var judicial_independence: float = 0.0

## What it was at new game, so the grievance price reads a DEVIATION rather than a
## level -- start_service_quality's and start_bloc_burden's shape. A country whose
## courts have always been weak is not permanently rioting about it, and Italy is not
## angrier than Switzerland on frame one.
##
## EARNS NOTHING: it round-trips through data/nations/, so it is content rather than
## state -- a firm's authored share at V1.4a. Serialised anyway, because nothing
## recomputes it after init and a save that dropped it would price every deviation
## against zero.
var start_judicial_independence: float = 0.0


## Deep copy. The budget projection runs the real simulation forward on a copy,
## so every mutable field -- every Dictionary and Array -- must be duplicated, not
## shared. The field list is src/core/nation_fields.gd's table; a field missing
## from it fails tests/test_nation_fields.gd rather than going silently uncopied.
func duplicate_state():
	var s = new()
	Fields.copy_into(self, s)
	return s


## Serialise to a plain Dictionary (JSON-safe: String/float/int/bool/Array/
## Dictionary only), over the same table. See docs/data-architecture.md
## Persistence.
func to_dict() -> Dictionary:
	return Fields.to_dict(self)


## Inverse of to_dict(), over the same table. Every register is REBUILT, never
## assigned, so two states loaded from one payload share nothing.
static func from_dict(d: Dictionary):
	var s = new()
	Fields.read_into(s, d)
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
