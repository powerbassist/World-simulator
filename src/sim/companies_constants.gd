extends RefCounted

## Every tunable in the private-companies model, in one file. Same shape as
## coercion_constants.gd, defence_constants.gd and the rest -- model parameters,
## not content, so not in data/. Rationale for every number is
## docs/companies-model.md; this file is the values, that file is the argument.
##
## PROVISIONAL UNTIL tools/companies_probe.gd RUNS. Written first so the probe has
## something to sweep; the numbers below are the sweep's OUTPUT once it has run.
## A number here that was never measured is the failure docs/scenario-model.md
## records for an authored starting approval -- a lever that turns out to be
## decorative. U6a's precedent is the sharper one: a constant the probe cannot
## justify is DELETED, not left unused.

# --- Content limits -----------------------------------------------------------

## The ops the effects.company channel takes. `subsidise` sets a standing subsidy
## on one firm and `withdraw` clears it; V1.4c's `nationalise` sets a standing
## state holding and `privatise` sells it.
##
## Paired setter/clearer rather than one signed dial, for the reason
## src/core/diplomatic_action.gd gives an agreement's "exit" and a measure's
## "lift": the clearer carries no terms, and a channel where the terms are read
## for one op and ignored for the other is a channel an author gets wrong once.
##
## V1.4c adds two ops and no new channel, which is the seventh session running with
## no new content type. `data/company-actions/` now serves three sessions the way
## `data/diplomatic-actions/` served five.
const COMPANY_OPS := ["subsidise", "withdraw", "nationalise", "privatise"]

## The term each op reads, or "" for the ops that read none. Declared as a table
## rather than as branches in src/core/company_action.gd because the property worth
## having is that EVERY op names its one dial or names none -- a fifth op added
## without a row here fails to load rather than silently ignoring its terms.
const COMPANY_OP_TERM := {
	"subsidise": "intensity",
	"withdraw": "",
	"nationalise": "stake",
	"privatise": "",
}

## How large one authored subsidy may be. Bounds the content, not the accumulated
## state, exactly as coercion_constants.MAX_MEASURE_SEVERITY does.
const MAX_SUBSIDY_INTENSITY := 1.00

## V1.4c. How much of one firm an authored nationalisation may take. The whole of
## it: a state that may not own a firm outright has no privatisation to sell, and
## "a permanent loss of control" needs something whole to lose.
const MAX_STAKE := 1.00

## V1.4b. How hard one authored regulation may lean on a sector, and equally how
## far the ACCUMULATED burden may run in either direction -- unlike the subsidy
## bound above, this one clamps the live state too, because laws stack and nothing
## renormalises them.
##
## ONE CLAMP, not two. A per-law bound plus a separate accumulator bound would
## double the exposure to the failure this project's probes have now found three
## times: the clamp, and not the number being measured, setting the outcome. The
## two channels the burden reaches already carry their own bounds
## (FIRM_IMPULSE_MAX_PCT and FIRM_JOBS_MAX_PCT), so a third above them would be a
## guard rail guarding a guard rail.
##
## SIGNED, and the sign is the whole of deregulation. See src/core/law.gd's
## _extract_company() for why a one-directional burden would be a permanent
## monotone charge rather than a lever.
const REGULATION_BURDEN_MAX := 1.00

## What a company action's preconditions may ask about. `subsidy_active` and
## `subsidy_count` are about the firm and the register; the rest are the acting
## nation's own state, read exactly as Legislature._read_field() reads them.
##
## Short on purpose. diplomacy_constants.PRECONDITION_FIELDS grew to seventeen
## across five sessions because each session had a new register to gate on; this
## list gets its entries the same way, when V1.4b and V1.4c have something to ask.
const PRECONDITION_FIELDS := [
	"subsidy_active", "subsidy_count",
	"state_owned", "state_owned_count",
	"deficit_pct_gdp", "debt_to_gdp_pct", "unemployment_pct", "overall_approval_pct",
]

const PRECONDITION_OPS := ["<", "<=", ">", ">=", "=="]

## The smallest share a firm may be authored at. A firm below this cannot move
## its sector by any reachable amount, so it is a name on a panel rather than a
## firm -- the same standard _validate_people() applies to an unreferenced
## person, and the same one U6b's probe cut a five-deep minister bench for.
const MIN_AUTHORED_SHARE := 0.02

# --- What a subsidy costs -----------------------------------------------------

## Points of GDP per year for one firm subsidised at full intensity.
##
## Anchored against the tax lines it sits beside on the same budget panel:
## economy_constants.TAX_BASE_SHARE makes one point of VAT worth 0.53 % of GDP and
## one point of income tax 0.50 %, so ONE TAX POINT IS ROUGHLY HALF A PERCENT OF
## GDP. Subsidising one national champion should cost appreciably less than a tax
## point -- it is one firm, not a fiscal programme -- and subsidising the whole
## register should cost more than one and be a visible choice.
const SUBSIDY_COST_PCT_GDP := 0.30

## Hard clamp on the whole subsidy bill, points of GDP.
##
## defence_constants.DEPLOYMENT_BILL_MAX_PCT_GDP's role, and it is measured the
## same way: if the reachable stack sits ON the clamp, the clamp and not the model
## is setting the number, and the session's first escalation trigger has fired.
const SUBSIDY_BILL_MAX_PCT_GDP := 2.50

# --- What a subsidy does to the firm ------------------------------------------

## Share of its sector a firm at full intensity takes from its named rivals each
## month. Taken pro-rata from the other named firms in the same sector of the same
## nation, and NEVER from the unnamed residual -- which is what makes the sum of
## named shares invariant under every lever, rather than merely renormalised.
##
## This is the model's ONE persistent channel. A subsidy withdrawn leaves the
## share where it moved to: the firm out-competed its rivals with public money and
## the market position is real. docs/scenario-model.md's finding is what this is
## answering -- an axis with no persistent channel decays back to neutral inside a
## game year and is decorative.
## Set from tools/companies_probe.gd table (b) AFTER the correction below. Once the
## floor is relative, the ENDPOINT of a subsidy is content and this rate only sets
## how fast the firm gets there -- so it is chosen on `t90`, months to reach 90 % of
## that endpoint, against a band of 12-48 fixed before the column existed. At 0.0020
## t90 is 25 months: a subsidy pays off inside a term without being over in a year.
const SHARE_SHIFT_PER_MONTH := 0.0020

## The most of its own AUTHORED position a rival can be made to give up, ever.
##
## THE PROBE'S FIRST CORRECTION, and it moved the model rather than the number.
## The floor here was a flat 0.0050 -- far below the smallest authored share of
## 0.04 -- so a subsidy could take ninety per cent of a rival's position, and the
## first sweep came back with 0.0020, 0.0040 and 0.0080 producing the IDENTICAL
## five-year answer for every nation. Three different rates, one outcome: the rate
## was not setting anything, the floor was, which is the clamp-sets-the-number
## failure docs/economy-model.md records for `IMPULSE_MAX` and V1.3c found again in
## its strictly-dominated severities.
##
## A relative floor fixes both halves at once. The endpoint of a subsidy becomes a
## property of the CONTENT -- how big the rival was authored -- rather than of a
## global constant that means something different in every sector, and the rate goes
## back to setting how fast the firm gets there, which is what a rate is for. At
## 0.50 a rival keeps at least half of what it started with, so a two-firm sector
## can never collapse into a one-firm sector, which would leave V1.4b and V1.4c a
## register whose rivals had already been driven out.
const RIVAL_FLOOR_FRACTION := 0.50

## Ceiling on a live share, so one firm cannot become its whole sector.
##
## A guard rail rather than a tuned value, and unreachable under the shipped
## content: with the relative floor above, the most any firm can reach is its own
## share plus half of each named rival's, which no authored sector comes close to
## 0.60 with. That is what a guard rail is supposed to look like --
## docs/economy-model.md's note on `IMPULSE_MAX` is about what happens when one is
## reachable instead.
const SHARE_MAX := 0.60

# --- What a subsidy does to growth --------------------------------------------

## Points of annual growth per unit of intensity, for a firm of exactly
## GDP_SHARE_REFERENCE size:
##
##     firm_impulse(A) = SUBSIDY_GROWTH_BETA
##                       * Sigma_f intensity(f) * gdp_share(f) / GDP_SHARE_REFERENCE
##
## Scaled by the firm's own weight in the economy, which is what makes WHICH FIRM
## a decision rather than a label. defence_constants.CAPABILITY_REFERENCE's shape:
## a quantity expressed as a multiple of an ordinary one, so the constant is
## anchored on something nameable instead of on the raw units.
##
## Reads EXACTLY 0.0 with no subsidy standing, for every nation, in every month.
## That is not an accident of the arithmetic -- it is the property
## tests/test_companies.gd asserts and the reason V1.4a's balance re-run can be
## bit-identical across all fourteen existing regimes with the whole firm register
## live.
##
## THE PROBE'S SECOND CORRECTION, from 0.30. Set from tools/companies_probe.gd
## table (c) against a band of 0.05-0.60 %/yr fixed before the sweep ran; 0.30 put
## France and Britain at 0.71 and 0.72, over the ceiling. The ceiling is the half
## that was doing work: a subsidy to ONE FIRM must not out-punch a whole budget,
## whose demand impulse runs to several points, and 0.30 had one firm worth more
## than a percentage point of every tax at once.
const SUBSIDY_GROWTH_BETA := 0.20

## The size of an ordinary national champion, as a share of GDP. France's largest
## authored firm sits near this by construction, so the ratio above is near 1.0
## for a big industrial firm and well under it for a mid-sized one.
const GDP_SHARE_REFERENCE := 0.020

## Hard clamp on the accumulated firm impulse, %/yr.
##
## docs/economy-model.md's divergence argument is PER QUANTITY -- every term that
## reaches growth carries its own bound rather than trusting GROWTH_MIN/MAX to
## catch it downstream. A new quantity owes that argument a row, and this is it.
## Under coercion_constants.COERCION_IMPULSE_MAX and economy_constants.
## IMPULSE_MAX_PCT, both 6.0: a subsidy programme is not a budget shock.
const FIRM_IMPULSE_MAX_PCT := 2.00

# --- What a subsidy does to jobs ----------------------------------------------
#
# LABOUR_FORCE_SHARE was here at 0.45, and its own comment defended it as "NOT A TUNED
# CONSTANT ... the measured participation-times-working-age figure for the roster, not
# a dial". V1.5b took that claim at its word and checked it: France is 0.7407
# participation x 0.6134 of working age = 0.4543, so the constant was right to three
# digits -- for France. Germany is 0.7994 x 0.6289 = 0.5027, and the roster spans Italy
# 0.423 to the Netherlands 0.551.
#
# So it was DELETED rather than re-derived, and Demography.labour_force() reads the two
# measured facts instead. One number right for one nation became two facts for all ten,
# and this file has one fewer constant than it did. The jobs channel's "no tuned
# constant at all" property survives the change intact -- it now has no constant of its
# own beyond the clamp below.

## Hard clamp on the firm layer's contribution to structural unemployment, points.
## Same per-quantity bound as FIRM_IMPULSE_MAX_PCT above, on the other channel.
const FIRM_JOBS_MAX_PCT := 1.50


# --- V1.4b: what a sector burden costs ------------------------------------------

## Fraction of a named firm's staff shed at a burden of 1.0.
##
## The burden reaches jobs through Companies.headcount() and therefore through the
## EXISTING firm_jobs_offset_pct, which already measures live headcount against
## authored headcount. That is not a saving of one field; it is the reason the jobs
## price exists at all. A sector-wide rule priced on sector OUTPUT is
## docs/tiers/v1.md section 6's sectoral lever with a minus sign, reproducible
## without a firm register anywhere in it -- while jobs-per-share is firm content,
## so no sector lever can express this number. Without it V1.4b is section 6 early
## and the decomposition's a/b boundary collapses.
##
## Provisional. tools/companies_probe.gd table (g) sweeps it against a floor of
## 0.05 unemployment points fixed before the sweep, and against the standing
## prediction that agriculture cannot clear that floor at any sane value -- 39k
## named jobs against a 30.9M labour force. If it does not, the bound is RECORDED
## and not tuned around; see docs/defence-model.md's DEPLOYMENT_OPINION_CHOSEN.
const REGULATION_JOBS_BETA := 0.10

## %/yr of growth given up per unit of GDP-weighted burden, scaled by
## GDP_SHARE_REFERENCE exactly as SUBSIDY_GROWTH_BETA is.
##
## Reads the burdened sector's NAMED firms and nothing else, so a sector that is a
## quarter named is a quarter as regulable. That is the second thing separating a
## regulation from a sector lever, and it is structural rather than a coefficient:
## the unnamed residual of a sector is not reached by this model at all, which is a
## bound docs/companies-model.md records rather than a rounding error.
##
## Provisional, swept by table (h) against the same 0.05-0.60 %/yr band table (c)
## measured the subsidy on -- a rule on one sector must no more out-punch a whole
## budget than a subsidy to one firm may.
const REGULATION_GROWTH_BETA := 0.10


# --- V1.4c: what a firm is worth, and what owning it pays -----------------------

## What the state pays for a whole firm, as a multiple of that firm's ANNUAL
## OUTPUT.
##
## A price multiple rather than an authored valuation, for the reason revenue is
## not authored: `output_eur_bn()` is already share x sector output, so a valuation
## field on a firm would be a third record of a product of two things that exist,
## and one a content edit would silently disagree with.
##
## Priced on OUTPUT and not on profit, which is the call docs/companies-model.md
## section 13 made in advance and V1.4c is bound by: there is no margin, profit or
## productivity quantity anywhere in src/sim/, and half-inventing one here would
## leave every later reader to either read it or contradict it.
##
## Provisional. tools/companies_probe.gd table (l) sweeps it against the DEBT JUMP
## from nationalising the largest firm in the register, banded 2-8 points of
## debt-to-GDP: the purchase must be able to matter against the bloc's own
## `debt_to_gdp_pct` rule without breaching it from a single act.
const PRICE_TO_OUTPUT := 1.00

## Fraction of a state-held firm's annual output that reaches the treasury.
##
##     dividend = state_share x share x sector_output x DIVIDEND_YIELD
##
## THE WHOLE FISCAL SHAPE OF THE SESSION FALLS OUT OF THIS AGAINST
## PRICE_TO_OUTPUT AND economy_constants.DEBT_REAL_RATE_PCT, and none of it is
## authored. The yield ON PRICE is DIVIDEND_YIELD / PRICE_TO_OUTPUT, and it is set
## EQUAL to the real rate on the debt that bought the firm.
##
## THE PROBE'S CORRECTION, from 0.04, and it moved what the number is measured
## AGAINST rather than the band. Table (m)'s band could not choose: three of four
## candidate rows landed inside 0.05-0.40 % of GDP, which is a band measuring
## whether the line is READABLE and not whether it is right. What chose is table
## (n). At 0.04 the yield on price was 4.0 % against a 2.0 % borrowing rate, so
## every nationalisation paid for itself twice over and table (p) came back better
## than a quiet run on the headline AND on the deficit -- free on both axes, which
## is the strictly-dominated shape V1.3c, V1.3d, V1.4a and V1.4b each hit.
##
## At the borrowing rate the treasury neither gains nor loses on the exchange, which
## is the honest model when there is no risk and no business cycle for an equity
## premium to be compensation FOR -- docs/tiers/v1.md section 6 owns both. What
## nationalising costs is then a stock rather than a flow: the whole purchase lands
## on `debt_to_gdp_pct` at once, which is a bloc rule's field and a precondition
## field in four modules, and privatising is the only lever in the game that moves a
## stock back down. What it buys is the jobs shield and the workers' row.
##
## NOT deleted and NOT derived, though it is anchored -- table (r)'s question, asked
## again after the correction. PRICE_TO_OUTPUT sets the SIZE of the act and this
## sets its fiscal SIGN; they are two decisions, and a session that wanted state
## ownership to be a slow fiscal gain or a slow drain would move this one alone.
##
## V1.6a ARRIVED WITH THE CYCLE AND DISCHARGED NOTHING, WHICH IS NOT WHAT V1.6's
## DECOMPOSITION PREDICTED. That decomposition read the sentence above -- "no risk and
## no business cycle for an equity premium to be compensation FOR" -- as two clauses
## with two owners, and booked the procyclical half to V1.6a as free: sector_output
## already moves with the cycle through SECTOR_CYCLE_BETA, so a claim on it should have
## become procyclical with no code at all.
##
## tools/cycle_probe.gd table (e) refuted it, and the mechanism is one line of
## Companies.dividend_revenue_pct_gdp(): the line is a SHARE OF GDP, `100.0 * paid /
## ns.gdp_eur_bn`, and the cycle moves the numerator and the denominator together. They
## cancel. What survives is the sector-COMPOSITION effect alone -- industry swings at
## SECTOR_CYCLE_BETA 1.8 against services' 0.8 -- and it measures 1.07x the flat-cycle
## variation against a pre-committed floor of 1.5x.
##
##     A DIVIDEND EXPRESSED AS A SHARE OF GDP IS NOT PROCYCLICAL BY CONSTRUCTION.
##
## *** V1.6c IS WHERE THE OBLIGATION IS DISCHARGED, AND THE ANSWER IS THAT THE PREMIUM
## IS PRICED ON A RATE. *** V1.6a left this constant one extra thing to answer: pricing
## the dividend on a GDP share is what makes the equity premium unreachable, so V1.6c
## either prices it on something that is not a GDP share or says out loud there is no
## channel. A RATE is the one quantity in this model that is not a share of GDP, and
## V1.6c is the session that makes one move -- src/sim/credit.gd floats the BORROWING
## rate around economy_constants.DEBT_REAL_RATE_PCT while this yield stays fixed.
##
## So the identity below replaces V1.4c's:
##
##     DIVIDEND_YIELD / PRICE_TO_OUTPUT * 100 == DEBT_REAL_RATE_PCT + EQUITY_PREMIUM_PCT
##     0.0312          / 1.00             * 100 == 2.00 + 1.12 == 3.12
##
## tests/test_credit.gd PINS that identity rather than this file asserting it, so a later
## session moving either side turns a test red and has to come and say why. It is written
## as a literal with the arithmetic here rather than as a cross-file const expression,
## which is this project's style for a derived number.
##
## WHAT IT BUYS IS THAT NATIONALISATION IS NO LONGER FREE OR COSTLY IN GENERAL -- it is
## one or the other depending on how the player has governed. While the spread is under
## the premium the state gains on the flow; once it is above, the debt that bought the
## firm costs more than the firm returns. The crossing is EXACT and needs no simulation:
## the two rates meet precisely where `spread == EQUITY_PREMIUM_PCT`. That is why V1.4c's
## strictly-dominated shape does not come back -- which side you are on is a consequence
## of your own fiscal record rather than a constant.
const DIVIDEND_YIELD := 0.0312

## V1.6c. Points of annual yield the state's claim on a firm pays ABOVE what the state
## borrows at when its credit is unblemished. The equity premium, discharging the
## obligation docs/tiers/v1.md section 6 handed here through V1.4c and V1.6a.
##
## SWEPT, and the kill switch did NOT fire. tools/credit_probe.gd table (g), two clauses
## closing the interval from opposite sides:
##   (i)  NOT FREE -- `hands_off` peak spread 1.1761 must EXCEED the premium, so a
##        president who does nothing for fourteen years ends up losing on the flow;
##   (ii) NOT POINTLESS -- the extra revenue is >= 0.05 points of GDP at the largest
##        holding France can actually take (Banque Meridienne at state_share 1.0, 0.0952
##        points of GDP at the anchor), which is docs/companies-model.md table (m)'s own
##        readability floor, applied to the increment because the increment is what shows
##        on the budget panel's dividend row.
## Exact crossings [1.05086, 1.19130], midpoint 1.12108, and that is a FIXED POINT
## rather than one reading: the interval is measured on a path this constant is on, so it
## was iterated until the shipped value equalled the midpoint measured at it. Three passes,
## residual movement under the second decimal. Stronger than V1.6b's check that the table
## moves by less than 0.003 when the constant does.
##
## CLAUSE (i) WAS TIGHTENED FROM WHAT THE PROBE PRE-COMMITTED, and the change is recorded
## in tools/credit_probe.gd rather than hidden: it read *some reachable regime*, and the
## only regime exceeding a high premium is one that survives exactly one term, so the
## clause was a bound and not a selector -- V1.5a's CORRUPTION_DELIVERY_BETA failure.
## Naming `hands_off` makes it select, and it makes the better claim: DOING NOTHING FOR
## LONG ENOUGH TURNS A NATIONALISATION INTO A LOSS.
##
## It is well under a real-world equity risk premium of three to five points, and that is
## the honest place for it: this model still has no equity RISK to compensate for beyond
## the sovereign's own, so a premium at the empirical level would be the free lunch V1.4c
## corrected away from.
const EQUITY_PREMIUM_PCT := 1.12

## Hard clamp on the whole dividend line, points of GDP. SUBSIDY_BILL_MAX_PCT_GDP's
## role on the other side of the budget, and measured the same way: a reachable
## stack sitting ON the clamp means the clamp and not the model is setting the
## number.
const DIVIDEND_MAX_PCT_GDP := 1.50
