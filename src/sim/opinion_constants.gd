extends RefCounted

## Every tunable in the public-opinion model, in one file.
##
## Referenced as `const K = preload("res://src/sim/opinion_constants.gd")`, the
## same shape as economy_constants.gd, so opinion.gd and the polling panel cannot
## drift apart and S10's balance pass has a single place to edit. Rationale for
## every number is in docs/opinion-model.md; this file is the values, that file is
## the argument.
##
## Not in data/ on purpose. Starting tax rates are content — a designer plausibly
## authors more of them. Voter blocs are not: regional and generational breakdown
## is someday tier, so six blocs is one fixed set, forever, which is exactly the
## definition economy-model.md uses for "model parameter". See
## docs/data-architecture.md for the decision and the trigger that reverses it.
##
## Bloc names appear here and nowhere else. Every consumer iterates BLOC_KEYS, so
## moving blocs into data/ later is a change to this file plus a loader, not a
## rewrite of opinion.gd, the panel, S6 elections and the save format.

# --- Blocs -------------------------------------------------------------------

const BLOC_KEYS := ["workers", "pensioners", "urban", "rural", "business", "students"]

## Share of the electorate. A partition by dominant identity, summing to 1.0 —
## which is what makes the weighted roll-up defensible rather than arbitrary.
const BLOC_SIZE := {
	"workers": 0.30,
	"pensioners": 0.24,
	"urban": 0.15,
	"rural": 0.13,
	"business": 0.10,
	"students": 0.08,
}

const BLOC_LABEL := {
	"workers": "Workers",
	"pensioners": "Pensioners",
	"urban": "Urban",
	"rural": "Rural",
	"business": "Business owners",
	"students": "Students",
}

# --- Issues ------------------------------------------------------------------

## Every issue is a satisfaction in [-1, +1], measured as a delta against the
## nation's own starting figure. At new-game every one of them is exactly zero,
## so the model needs no calibration constant — the same trick the economy's
## potential_shift uses.
const ISSUE_KEYS := [
	"jobs", "growth",
	"tax_income", "tax_corporate", "tax_vat",
	"health", "education", "defence", "pensions", "infrastructure",
	"public_finances",
]

const ISSUE_LABEL := {
	"jobs": "Unemployment",
	"growth": "The economy",
	"tax_income": "Income tax",
	"tax_corporate": "Corporate tax",
	"tax_vat": "VAT",
	"health": "Health",
	"education": "Education",
	"defence": "Defence",
	"pensions": "Pensions",
	"infrastructure": "Infrastructure",
	"public_finances": "Public finances",
}

## Deltas that saturate an issue's satisfaction at full strength.
const JOBS_SCALE_PP := 3.0        # points of unemployment
const GROWTH_SCALE_PP := 4.0      # points of growth away from trend
const TAX_SCALE_PP := 8.0         # points of a tax rate
const SPEND_SCALE_PP := 3.0       # points of GDP on a spending line
const DEFICIT_SCALE_PP := 3.0     # points of GDP of deficit

# --- Salience ----------------------------------------------------------------

## What each bloc cares about, before the news moves it. Sparse — an issue a bloc
## has no entry for carries no weight for that bloc, which is what makes
## "fixing something nobody cares about buys nothing" true. Each row sums to 1.0;
## the code normalises anyway, so a tuning pass need not keep it that way.
##
## Note pensioners weight pensions at 0.45 and students at nothing. That pair is
## the S5 done-when condition, and it is a property of this table, not of code.
const BLOC_SALIENCE_BASE := {
	"workers": {
		"jobs": 0.40,
		"tax_income": 0.19,
		"health": 0.11,
		"tax_vat": 0.09,
		"pensions": 0.07,
		"growth": 0.07,
		"public_finances": 0.07,
	},
	"pensioners": {
		"pensions": 0.44,
		"health": 0.26,
		"public_finances": 0.13,
		"tax_vat": 0.09,
		"jobs": 0.08,
	},
	"urban": {
		"health": 0.22,
		"jobs": 0.21,
		"education": 0.17,
		"infrastructure": 0.13,
		"tax_income": 0.11,
		"growth": 0.09,
		"public_finances": 0.07,
	},
	"rural": {
		"infrastructure": 0.24,
		"jobs": 0.19,
		"health": 0.15,
		"tax_vat": 0.13,
		"pensions": 0.11,
		"defence": 0.11,
		"public_finances": 0.07,
	},
	"business": {
		"tax_corporate": 0.30,
		"public_finances": 0.24,
		"growth": 0.22,
		"infrastructure": 0.11,
		"jobs": 0.07,
		"education": 0.06,
	},
	"students": {
		"education": 0.44,
		"jobs": 0.25,
		"tax_vat": 0.11,
		"growth": 0.07,
		"health": 0.07,
		"public_finances": 0.06,
	},
}

## How much bad news raises an issue's weight. Applied as
## `base * (1 + GAIN * severity)` and then renormalised, so weights stay on the
## simplex and no amount of bad news can make them compound.
const SALIENCE_GAIN := 1.0

# --- Approval ----------------------------------------------------------------

## Where every bloc starts and where a bloc with nothing to complain about sits.
## No honeymoon bonus — time in office as its own drag is V1.
const APPROVAL_NEUTRAL := 50.0

## Satisfaction is bounded to [-1, +1], so target approval lives in [10, 90] and
## the hard clamp below is a guard rail that never binds under sane play.
const APPROVAL_SPAN := 40.0

const APPROVAL_MIN := 0.0
const APPROVAL_MAX := 100.0

## Fraction of the gap to target closed per month. Half-life ~2.4 months.
##
## Deliberately fast. Opinion sits downstream of an economy that already lags —
## Okun plus a three-year reversion — so a slow inertia term would put two lags in
## series on the channel that is already the slowest, and the game would stop
## answering. A spending change hits its issue with no lag at all, which is where
## this constant actually shows: roughly 58% of the move lands within three
## months. See docs/opinion-model.md.
const INERTIA_RATE := 0.25
