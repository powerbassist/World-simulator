extends RefCounted

## Every tunable in the sectoral-investment model, in one file. Same shape as
## companies_constants.gd, coercion_constants.gd and the rest -- model parameters,
## not content, so not in data/. Rationale for every number is
## docs/sector-model.md; this file is the values, that file is the argument.
##
## THREE TUNED CONSTANTS AND ONE GUARD RAIL, all four set by tools/investment_probe.gd
## rather than guessed and defended afterwards. Every band and every tiebreaker is
## pre-committed in that file's header.
##
## A FOURTH WAS DELETED BY THE PROBE. INVESTMENT_BILL_MAX_PCT_GDP stood here until the
## bill became share-scaled, at which point the three shares summing to exactly 1.0
## made the whole bill bounded above by INVESTMENT_COST_PCT_GDP itself -- a clamp
## guarding arithmetic. Deleted rather than left unused, which is U6a's treatment of
## the day budget and V1.3e's of AGREEMENT_ACCEPT_MIN: a tuned constant nothing reads
## is a number a later session finds and reasons from.
##
## AND ALL THREE THAT REMAIN ARE CLOSED FORM OR MEASURED TO A FIXED POINT, so no grid
## can move any of them. That is the strongest position this project has reached on a
## first pass, and it is not luck: two of the three responses are linear by
## construction and the third is a first-order lag whose t90 has an exact solution.

# --- Content limits -----------------------------------------------------------

## The ops the effects.investment channel takes. `invest` sets a standing
## programme on one sector and `withdraw` clears it.
##
## Paired setter/clearer rather than one signed dial, for companies_constants.
## COMPANY_OPS' reason: the clearer carries no terms, and a channel where the
## terms are read for one op and ignored for the other is a channel an author gets
## wrong once.
##
## THERE IS NO `disinvest`, and the absence is the design. V1.4b's regulation is
## signed because a burden is a rule and a rule can be relaxed; capital is a
## STOCK, and a negative stock is a sector the state has demolished. Withdrawal
## already carries the whole downside: the money stops and the stock decays.
const INVESTMENT_OPS := ["invest", "withdraw"]

## The term each op reads, or "" for the ops that read none. A table rather than
## branches in src/core/investment_action.gd, for COMPANY_OP_TERM's reason: the
## property worth having is that EVERY op names its one dial or names none, so a
## third op added without a row here fails to load rather than silently ignoring
## its terms.
const INVESTMENT_OP_TERM := {
	"invest": "intensity",
	"withdraw": "",
}

## How large one authored programme may be. Bounds the CONTENT, not the
## accumulated state -- the stock below is bounded by construction rather than by
## a clamp, which is why there is no accumulator bound beside this one.
const MAX_INVESTMENT_INTENSITY := 1.00

## What an investment action's preconditions may ask about. `investment_active` is
## about the SECTOR the action names; the rest are the acting nation's own state,
## read exactly as Companies._read_field() reads them.
##
## companies_constants.PRECONDITION_FIELDS minus the two firm fields, which is the
## whole difference between the two verbs stated as a list: a subsidy asks about a
## firm, this asks about a sector and about the books.
const PRECONDITION_FIELDS := [
	"investment_active", "investment_count",
	"deficit_pct_gdp", "debt_to_gdp_pct", "unemployment_pct", "overall_approval_pct",
]

const PRECONDITION_OPS := ["<", "<=", ">", ">=", "=="]

# --- What a programme costs ---------------------------------------------------

## Points of GDP per year for a full-intensity programme in a sector that IS the
## whole economy. What one sector actually costs is this times its own share of GDP.
##
## *** SCALED BY SHARE, AND THAT IS THE PROBE'S MODEL CORRECTION. *** The first
## version was a flat fee per sector, and tools/investment_probe.gd table (e) measured
## a sixty-three-to-one spread in what that fee bought across the three French sectors
## -- the same money for less of everything, which is the strictly-dominated shape this
## project has caught six times. See Investment.bill_pct_gdp() for the argument. The
## fix moves the model and adds no constant, and it DELETED one:
## INVESTMENT_BILL_MAX_PCT_GDP is gone, because the three shares sum to exactly 1.0 and
## the whole bill is therefore bounded above by this number itself.
##
## BANDED AGAINST WHAT V1.6d LEFT OF THE DEFICIT ISSUE, which is the one thing this
## session was told to measure before assuming there was room. docs/tax-model.md
## section 7 measured the two new taxes alone at 4.62 points of
## opinion_constants.DEFICIT_SCALE_PP's six-point span -- 77 % -- so the headroom a
## fourth computed budget line may take is 1.38 points, not
## companies_constants.SUBSIDY_BILL_MAX_PCT_GDP's 2.50.
##
##   (i)  LEGIBLE: the largest single-sector programme France can run costs >= 0.20
##        points of GDP, about two fifths of an income-tax point.
##   (ii) FITS: the whole-economy programme -- which is this constant exactly -- plus
##        the tax swing stays inside DEFICIT_SCALE_PP.
##
## Both edges are CLOSED FORM, so no grid can move the answer, which is
## docs/tax-model.md's PROGRESSIVITY_BASE_BETA standard. Two-sided on two model
## criteria, so V1.5c's midpoint rule. France's services sector is 0.7930 of GDP, so
## clause (i) is 0.20 / 0.7930 = 0.2522 and clause (ii) is the headroom itself:
##
##     interval [0.2522, 1.3800], midpoint 0.8161.
##
## THE FIRST RUN REPORTED 0.40, AND THAT IS RECORDED RATHER THAN TIDIED. The table
## printed the widest PASSING GRID ROW instead of solving the edge, so the answer moved
## with the grid inside a table whose whole claim was that no grid could move it --
## V1.5b's "the range was choosing the constant" in the one place it should have been
## impossible. Both edges are solved arithmetically now and the grid is a legibility
## column.
##
## Measured against the real model once, so a second-order effect could not hide inside
## the closed form: the whole economy at full intensity for ten years widens the deficit
## by 1.1074 points against a quiet run, which is this constant plus debt service on
## what it borrowed.
##
## For scale: one point of income tax is 0.50 % of GDP, so backing the entire economy
## at full intensity costs about a point and a half of income tax and backing French
## services alone costs about one and a third.
const INVESTMENT_COST_PCT_GDP := 0.8161

# --- What a programme builds --------------------------------------------------

## Fraction of the gap between the standing intensity and the accumulated capital
## closed per year.
##
## THE ONE CONSTANT THAT SETS SPEED, AND THERE IS DELIBERATELY NOT A SECOND.
## Capital is normalised so that full intensity converges on exactly 1.0, so the
## ENDPOINT is content -- the authored intensity -- and this only sets how fast the
## sector gets there. A build rate plus a depreciation rate plus an equilibrium is
## one strength written three times, which is docs/coercion-model.md's
## `tariff_rate_pct` error; here the equilibrium is fixed by the normalisation and
## cannot disagree with anything.
##
## SYMMETRIC: money stops and capital decays toward zero at the same rate it grew.
## An asymmetric decay is the session's named escalation trigger and is added only
## if the probe finds a withdrawal reverses the whole gain inside a game year --
## docs/scenario-model.md's decorative-axis failure. Not added pre-emptively.
##
## Banded on t90, months to reach 90 % of the endpoint, which is
## companies_constants.SHARE_SHIFT_PER_MONTH's device. The band is 36-84 months, fixed
## before the column existed: docs/brainstorm/mechanics-economy.md's sketch is "direct
## state money at a sector and WAIT SEVERAL YEARS", and a lever that pays inside a year
## is not this one.
##
## CLOSED FORM: t90 = ln(0.1) / ln(1 - rate/12), so the band maps exactly onto rates
## [0.3245, 0.7435]. THE MIDPOINT IS TAKEN IN MONTHS AND NOT IN THE RATE, because the
## band is written in months and the map between them is convex -- a midpoint of the
## rate is a midpoint of the wrong quantity. t90 = 60.0 months exactly, solving back to
## 0.4518.
##
## Sixty months is five years, which lands this on the same time constant
## economy_constants.SHIFT_ADJUST already uses for potential and for the same reason:
## deliberately longer than a term, so the president who pays is not always the
## president who collects. Nothing arranged that; the band was fixed first.
##
## The measured decay is what closed the escalation trigger: a year after a withdrawal
## 63 % of the capital is still standing, and five years after it 10 %. A withdrawal is
## not a demolition, so no asymmetric second rate was added.
const CAPITAL_CONVERGENCE := 0.4518

# --- What the capital is worth ------------------------------------------------

## Points of that sector's OWN annual trend growth per unit of accumulated capital.
##
## Read at two sites in economy.gd -- the per-sector rate inside
## _apply_growth_to_sectors() and, SHARE-WEIGHTED, inside trend_pct() -- and both
## are required. Added to only the first, the level effect would be cancelled by
## the cyclical residual in the same tick, because that function reconciles the
## three sectors against the month's GDP target exactly. See docs/sector-model.md
## section 2, which is why the row's "acts on sector_output itself" names a write
## this model structurally refuses.
##
## NOT A SECOND economy_constants.INFRA_BETA, and that boundary check was settled
## before this band was written rather than after -- V1.6c's rule that a band is a
## test of size and not of legitimacy. INFRA_BETA reads a player-set SPENDING LINE
## keyed 1:1 to a cabinet portfolio and produces a UNIFORM shift through
## potential_shift_pct; this reads a register written by a VERB and produces a
## PER-SECTOR one. Against src/core/law.gd's own criterion for the three existing
## anti-double-count pairs -- same act, same landing site AND same units -- it fails
## two of the three.
##
## Banded: (i) LEGIBLE, the national trend move at a reachable programme clears what a
## reachable infrastructure budget already buys through INFRA_BETA (one point of GDP is
## 0.15 %/yr); (ii) NOT DOMINANT, it stays under economy_constants.SHIFT_MAX_PCT = 1.0,
## or one verb out-punches the entire long-run budget of every other lever combined.
##
## *** CLAUSE (ii) WAS MEASURING THE CLAMP ON THE FIRST RUN, AND THAT IS V1.6d's OWN
## FINDING ARRIVING IN THE SESSION AFTER IT. *** Read off the shipped figure the
## national shift is scaled down to SECTOR_TREND_MAX_PCT the moment it would exceed it,
## so "stays under SHIFT_MAX_PCT" is true at every candidate above the clamp point BY
## THE CLAMP -- and the grid, being wide enough to reach it, reported an interval whose
## upper edge was a guard rail rather than the model. Clause (ii) reads the UNCLAMPED
## weighted shift now and the probe prints both columns.
##
## The response is exactly linear in this constant, so one measured slope gives both
## crossings: 0.8072 points of national trend per unit of beta at France's reachable
## services programme.
##
##     interval [0.1858, 1.2389], midpoint 0.7124.
##
## Smooth crossing rather than a plateau, so V1.5d's extension applies and the interior
## governs. ITERATED TO A FIXED POINT -- the slope is measured on a path this constant
## is on, so the shipped value is the one at which the measured midpoint equals it,
## which is docs/credit-model.md's EQUITY_PREMIUM_PCT standard. It converged in one
## pass to four decimals.
##
## MEASURED BY EXACT EMULATION rather than by rescaling the shipped figure: a candidate
## is run by holding the capital at true * candidate / shipped for the two economy reads
## and restoring it before the stock advances. V1.6b's correction -- its first table
## rescaled from the shipped constant and the passing interval MOVED when that constant
## moved.
const SECTOR_TREND_BETA := 0.7124

## Hard clamp on this layer's contribution to the NATION'S trend, %/yr -- the
## share-weighted sum of the three per-sector shifts.
##
## docs/economy-model.md's divergence argument is PER QUANTITY: every term that
## reaches trend carries its own bound rather than trusting SHIFT_MAX_PCT to catch
## it downstream. This is the first term other than potential_shift_pct ever to
## reach trend, so economy_constants.SHIFT_MAX_PCT's comment -- "the only term that
## feeds back into trend growth" -- is amended by this session rather than left to
## quietly become false.
##
## Applied by SCALING ALL THREE per-sector shifts by one factor rather than by
## clipping the sum after the fact, which is what keeps economy.gd's two readers
## exactly consistent with each other when it binds.
##
## A GUARD RAIL and explicitly not a selector. MEASURED SLACK: the largest programme a
## player can run -- all three sectors at full intensity for ten years -- reaches
## 0.7053 against this 1.00, so the model and not the clamp is setting every reachable
## number. That is what a guard rail is supposed to look like, and
## docs/economy-model.md's note on IMPULSE_MAX is about what happens when one is
## reachable instead.
const SECTOR_TREND_MAX_PCT := 1.00
