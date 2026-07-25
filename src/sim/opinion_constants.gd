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

## Points of GDP of deficit. Widened from S5's 3.0 during the S10 balance pass:
## at 3.0 the issue saturated at ±1 on a three-point move, so a deficit two
## points over the starting one and a deficit twenty points over it read exactly
## the same to a voter. Six points spans a genuine consolidation or a genuine
## blowout, which is the range the player actually moves this number over.
const DEFICIT_SCALE_PP := 6.0

# --- Salience ----------------------------------------------------------------

## What each bloc cares about, before the news moves it. Sparse — an issue a bloc
## has no entry for carries no weight for that bloc, which is what makes
## "fixing something nobody cares about buys nothing" true. Each row sums to 1.0;
## the code normalises anyway, so a tuning pass need not keep it that way.
##
## Note pensioners weight pensions far above anything else and students at
## nothing. That pair is the S5 done-when condition, and it is a property of this
## table, not of code.
##
## The public_finances row was raised across every bloc during the S10 balance
## pass. At the S5 weights it carried about 0.10 of the national agenda against
## roughly 0.50 for the five spending lines, which made fiscal discipline a
## strictly dominated strategy: a budget with every spending line maxed and every
## tax at zero ran a deficit of 112% of GDP, walked debt to 1346% of GDP, and
## still held approval at 57 and won three consecutive elections, while an
## austerity budget that ran a surplus lost. Roughly doubling this one row is the
## whole fix — and it is surgical, because a player who never touches the budget
## sits at a public_finances satisfaction of about zero and is untouched by the
## change. It bites only once the player moves the deficit, in whichever
## direction. Found by tools/balance_probe.gd.
const BLOC_SALIENCE_BASE := {
	"workers": {
		"jobs": 0.34,
		"public_finances": 0.18,
		"tax_income": 0.15,
		"health": 0.10,
		"tax_vat": 0.08,
		"growth": 0.08,
		"pensions": 0.07,
	},
	"pensioners": {
		"pensions": 0.38,
		"health": 0.21,
		"public_finances": 0.20,
		"jobs": 0.13,
		"tax_vat": 0.08,
	},
	"urban": {
		"health": 0.19,
		"jobs": 0.18,
		"public_finances": 0.17,
		"education": 0.14,
		"infrastructure": 0.11,
		"tax_income": 0.11,
		"growth": 0.10,
	},
	"rural": {
		"infrastructure": 0.20,
		"public_finances": 0.18,
		"jobs": 0.16,
		"health": 0.13,
		"defence": 0.12,
		"tax_vat": 0.11,
		"pensions": 0.10,
	},
	"business": {
		"public_finances": 0.34,
		"tax_corporate": 0.25,
		"growth": 0.19,
		"infrastructure": 0.09,
		"jobs": 0.07,
		"education": 0.06,
	},
	"students": {
		"education": 0.38,
		"jobs": 0.22,
		"public_finances": 0.14,
		"tax_vat": 0.10,
		"growth": 0.08,
		"health": 0.08,
	},
}

## How much bad news raises an issue's weight. Applied as
## `base * (1 + GAIN * severity)` and then renormalised, so weights stay on the
## simplex and no amount of bad news can make them compound.
##
## Raised from S5's 1.0 in the S10 balance pass. This is the constant that makes
## losing *attributable*: the election result screen names the most-salient
## issues at the moment of the vote, so at a low gain it names whatever the base
## table says regardless of what actually went wrong in the run. At 5.0 the issue
## the player is failing on climbs to the top of the agenda and the result screen
## names it. The renormalisation argument above is what keeps this safe to raise.
##
## It is also the constant that repairs the model's one non-monotone corner.
## Satisfaction is clamped to [-1, +1], so once a deficit has saturated
## public_finances at -1 it cannot get any worse — and every further giveaway is
## then free upside. A budget with every spending line maxed *and* every tax at
## zero used to be more popular than either half on its own, because the second
## half added three saturated positives against a negative already at the floor.
## The gain is the only term that can outweigh that: it multiplies the weight by
## (1 + GAIN * severity), so an issue in crisis (severity 1.0) grows six times
## while one that is merely uncomfortable (severity 0.3) grows 2.5 times. The
## flip point for that combined-giveaway budget sits between 4.0 and 4.5; 5.0 is
## chosen for headroom past it, and costs a managed budget nothing measurable
## against a do-nothing one. Found by tools/balance_probe.gd.
const SALIENCE_GAIN := 5.0

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
