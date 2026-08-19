extends RefCounted

## Every tunable in the economy and budget model, in one file.
##
## Referenced as `const C = preload("res://src/sim/economy_constants.gd")` so
## economy.gd and budget.gd cannot drift apart, and so S10's balance pass has a
## single place to edit. Rationale for every number is in docs/economy-model.md;
## this file is the values, that file is the argument.
##
## Not in data/ on purpose: these are model parameters, of which there is exactly
## one set forever, not content a designer adds more of. See engine-decision.md
## Rule 1.

# --- Sectors -----------------------------------------------------------------

## Real trend growth of each sector, %/yr. A nation's overall trend is the
## share-weighted sum, so ten nations get ten trends from one table.
const SECTOR_TREND := {
	"agriculture": 0.2,
	"industry": 1.0,
	"services": 1.4,
}

## Cyclical amplitude. Industry amplifies the cycle, agriculture barely feels it.
## Used only to distribute the cyclical part of growth, never the trend part.
const SECTOR_CYCLE_BETA := {
	"agriculture": 0.4,
	"industry": 1.8,
	"services": 0.8,
}

## Floor on any single sector's output, EUR bn. Guard against a pathological
## budget driving a small sector negative; never binds under sane play.
const SECTOR_MIN_EUR_BN := 0.001

# --- Output and growth -------------------------------------------------------

## Fraction of the output gap closed per year. 0.30 gives a ~28-month half-life.
const GAP_CLOSE := 0.30

const GROWTH_MIN_PCT := -12.0
const GROWTH_MAX_PCT := 12.0

# --- Labour market -----------------------------------------------------------

## Okun coefficient: points of unemployment removed per point of above-trend
## growth sustained for a year.
const OKUN := 0.4

## Reversion of unemployment to its structural rate, per year.
const UNEMP_REVERT := 0.35

const UNEMP_MIN_PCT := 1.0
const UNEMP_MAX_PCT := 40.0

## Labour-tax wedge: points of structural unemployment per point of income tax.
const STRUCT_INCOME_BETA := 0.08

const STRUCT_MIN_PCT := 2.0
const STRUCT_MAX_PCT := 25.0

# --- Population --------------------------------------------------------------
#
# POP_GROWTH_PCT was here, one flat 0.15 % a year shared by all ten nations, and V1.5b
# DELETED it rather than leaving it unused -- AGREEMENT_ACCEPT_MIN's treatment at
# V1.3e and the day budget's at U6a, because a tuned constant nothing reads is a
# number a later session finds and reasons from.
#
# What replaced it is not another constant but ten measured facts:
# NationState.pop_growth_pct, read off imported.cohorts, which spans Italy's -0.238 to
# Luxembourg's +1.938. The old constant had every nation in Europe growing, and one of
# them shrinks. See src/sim/demography.gd and docs/demography-model.md.

# --- Revenue -----------------------------------------------------------------

## Share of GDP each tax nominally falls on: labour and household income,
## corporate profits, consumption, realised capital gains, and net household
## wealth.
##
## V1.6d ADDS TWO, AND `wealth` IS THE ONLY ENTRY HERE THAT IS NOT A FLOW. Every
## share above it is income earned or money spent within the year; net household
## wealth is a STOCK of roughly four times annual output, which is why 4.00 sits
## beside numbers under 1.0 without being a mistake. That difference is not
## cosmetic -- it is what forces WEALTH_RATE_MAX_PCT and a per-key
## opinion_constants.TAX_SCALE_PP, because a rate on a stock four times the size
## of the base beneath it does the same fiscal work at a twentieth of the number.
## The alternative -- a tiny base share on the same 0-70 scale as the other four --
## keeps every shared table untouched and makes the figure the player sets not a
## wealth-tax rate in any real sense, which is docs/scenario-model.md's
## decorative-axis failure. See docs/tax-model.md section 2.
##
## AUTHORED, all five, and V1.6d checked before assuming so. tools/import_data.py's
## World Bank loop covers GC.TAX.* for 10 of 10 nations over 1990-2024 -- coverage
## is NOT the problem, which is the opposite of what docs/credit-model.md section 2
## found for the bond series. What rules it out is universe and granularity:
## `GC.*` is CENTRAL government (France reads 22.8 % of GDP against the 46.1 the
## nation files carry, Switzerland 9.5), which docs/data-sources.md already rejected
## at S1; `GC.TAX.YPKG.*` puts income, profits AND capital gains in ONE bucket, which
## is precisely the split this session exists to create; and there is no property or
## wealth series at all. See docs/tax-model.md section 1.
const TAX_BASE_SHARE := {
	"income": 0.50,
	"corporate": 0.18,
	"vat": 0.53,
	"capital_gains": 0.02,
	"wealth": 4.00,
}

## Base erosion per unit of relative rate increase. Higher where the base is more
## mobile — corporate profits move, consumption does not.
##
## V1.6d: `capital_gains` is the MOST MOBILE ENTRY IN THIS TABLE and is authored
## above corporate's 0.55, because realisation is a timing choice the holder makes
## and a rate rise is answered by not selling this year. `wealth` sits with it: a
## net-wealth base is the most portable thing a tax can point at, and every roster
## nation that has tried one has watched the base leave.
const TAX_EROSION := {
	"income": 0.35,
	"corporate": 0.55,
	"vat": 0.25,
	"capital_gains": 0.75,
	"wealth": 0.80,
}

const EROSION_MIN := 0.35
const EROSION_MAX := 1.25

## V1.6d. The reference rate the erosion curve falls back to when a nation's own
## STARTING rate for a tax is zero, in points.
##
## Budget._erosion() divides by the nation's own start, so a rate of zero left the
## curve with nothing to be relative to and the function returned a flat 1.0 -- no
## diminishing returns at all, linear revenue forever. That is correct for a tax
## nobody has and WRONG the moment a player invents one, and it is reachable
## content rather than a hypothetical: Switzerland taxes no private capital gain,
## Belgium and Luxembourg broadly neither, and eight of the ten start with no
## wealth tax at all. A live exploit in code older than this session, exposed by
## this session's content -- docs/diplomacy-model.md's exploit caught before the
## content shipped.
##
## PER KEY, AND THE FIRST DRAFT WAS ONE SHARED NUMBER. That version is recorded
## because it was wrong in an instructive way: it read "two points, whatever the
## tax, because the reference is relative to the rate being set". It is not. A
## capital-gains tax invented from nothing is normally levied around twenty-five
## points and a wealth tax below one, so a shared reference of two put the invented
## capital-gains tax's revenue peak at about three points -- an order of magnitude
## under every rate any of the ten actually charges -- while leaving the wealth tax
## barely curved at all. ONE CONSTANT CANNOT SERVE TWO RATE SCALES, which is
## WEALTH_RATE_MAX_PCT's finding at a second site inside the same session.
##
## So each entry is the rate that tax is NORMALLY levied at, which is the only thing
## the curve can mean when the nation's own start is zero. The first three are
## unreachable in shipped content -- all ten nations author income, corporate and VAT
## above zero -- and are here anyway, because a scenario may zero one and a table with
## three holes in it is a table a later session reasons from wrongly.
const EROSION_ZERO_REF_PCT := {
	"income": 20.0,
	"corporate": 25.0,
	"vat": 20.0,
	"capital_gains": 25.0,
	"wealth": 0.50,
}

## V1.6d. Ceiling on the wealth rate, in points, and the reason it is not 70 like
## the four beside it. TAX_BASE_SHARE["wealth"] is 4.00 against income's 0.50, so a
## point of wealth rate is eight points of income tax in revenue -- three points is
## already 12 % of GDP, more than every other tax in this model put together at its
## authored rate. A slider running to 70 would not be a wider choice, it would be a
## slider whose top four fifths are a joke; and every historical net-wealth tax that
## has existed sat between 0.2 and 3.0. Read by src/ui/budget_panel.gd's LEVER_MAX
## and asserted against it by tests/test_tax.gd, so the model bound and the control
## cannot drift apart.
const WEALTH_RATE_MAX_PCT := 3.0

const TAX_KEYS := ["income", "corporate", "vat", "capital_gains", "wealth"]
const SPENDING_KEYS := ["health", "education", "defence", "pensions", "infrastructure"]

# --- Debt --------------------------------------------------------------------

## Flat real interest rate on public debt, %/yr. Bond yields and credit ratings
## are V1. What matters is that this exceeds trend growth (~1.3 %/yr for France):
## r > g means a zero primary balance still walks the debt ratio upward.
const DEBT_REAL_RATE_PCT := 2.0

# --- Demand impulse (short run) ----------------------------------------------

const IMPULSE_DECAY := 0.90

## Cap on the demand impulse, %/yr. Must stay *inside* GROWTH_MAX_PCT, not
## outside it. At the S4 value of 50 it sat four times above the growth clamp, so
## any large budget commit drove growth onto ±12 and held it there for a year
## while the impulse decayed — the clamp, not the model, was setting the growth
## rate. At 6 the largest budget a player can commit produces a boom of about
## +6%/yr fading over two years, and the growth clamp goes back to being the
## unreachable guard rail it was meant to be. Found by tools/balance_probe.gd.
const IMPULSE_MAX_PCT := 6.0

## Fiscal multipliers, applied to the change in each line as a % of GDP.
const MULT_SPENDING := 0.90
## V1.6d adds two, and both are LOW for the same reason: a fiscal multiplier is
## about whose spending changes when the tax does, and both of these fall on
## holders rather than on earners or shoppers. Capital gains sits at corporate's
## level; wealth below it, because a levy on a stock is met out of the stock far
## more often than out of the month's consumption.
const MULT_TAX := {
	"income": 0.60,
	"corporate": 0.40,
	"vat": 0.70,
	"capital_gains": 0.35,
	"wealth": 0.25,
}

# --- Potential shift (long run) ----------------------------------------------

## Points of trend growth bought by a sustained extra point of GDP on each line.
const INFRA_BETA := 0.15
const EDU_BETA := 0.10

## Points of trend growth lost per point of corporate tax, through investment.
const CORP_TAX_BETA := 0.02

## Speed of adjustment toward the target shift, per year. 0.20 is a five-year
## time constant — deliberately longer than a term.
const SHIFT_ADJUST := 0.20

## The single most important clamp in the model: potential_shift is the only term
## that feeds back into trend growth, so it is the only one that could compound.
const SHIFT_MAX_PCT := 1.0

# --- Trade -------------------------------------------------------------------
#
# TRADE_BETA lived here from S4 to V1.3a and moved to src/sim/trade_constants.gd
# at V1.3b, unchanged in value, along with every other trade tunable. One system,
# one module: leaving it behind would have split the trade parameters across two
# files, and the trade model is now a module of its own rather than four lines at
# the top of Economy.tick_month().


## Level effect on GDP of an annualised impulse of 1.0 that then decays to
## nothing: the geometric sum of impulse * decay^n / 12.
static func impulse_level_factor() -> float:
	return 1.0 / (12.0 * (1.0 - IMPULSE_DECAY))


## Annual percentage rate to a one-month compounding factor. Floored well above
## -100 so a clamped-but-extreme growth rate can never produce a NaN.
static func monthly_factor(annual_pct: float) -> float:
	return pow(1.0 + maxf(annual_pct, -95.0) / 100.0, 1.0 / 12.0)
