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
## corporate profits, consumption.
const TAX_BASE_SHARE := {
	"income": 0.50,
	"corporate": 0.18,
	"vat": 0.53,
}

## Base erosion per unit of relative rate increase. Higher where the base is more
## mobile — corporate profits move, consumption does not.
const TAX_EROSION := {
	"income": 0.35,
	"corporate": 0.55,
	"vat": 0.25,
}

const EROSION_MIN := 0.35
const EROSION_MAX := 1.25

const TAX_KEYS := ["income", "corporate", "vat"]
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
const MULT_TAX := {
	"income": 0.60,
	"corporate": 0.40,
	"vat": 0.70,
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
