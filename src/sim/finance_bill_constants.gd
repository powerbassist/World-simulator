extends RefCounted

## The finance bill's tuning (docs/design/finance-bill.md section 3). Constants only:
## finance_bill_law.gd and finance_bill.gd read them.

## Where a line's change sits on the two axes, per channel, key and direction: the
## authored law that moves that line, its position verbatim. A bill's position is the
## coalition's own, moved toward the size-weighted mean of these. A tax kind's rows moved
## into its file in data/taxes/ at V5.3 e (section 9's `finance_anchor`).
const ANCHOR := {
	"spending_pct_gdp": {
		# health_service_reform (-0.3 / -0.1); a cut mirrors it.
		"health": {"up": {"economic": -0.3, "social": -0.1}, "down": {"economic": 0.3, "social": 0.1}},
		# student_grants_act (-0.4 / -0.3); a cut mirrors it.
		"education": {"up": {"economic": -0.4, "social": -0.3}, "down": {"economic": 0.4, "social": 0.3}},
		# pension_uplift_act up (-0.45 / +0.1), retirement_age_reform down (+0.45 / +0.25).
		"pensions": {"up": {"economic": -0.45, "social": 0.1}, "down": {"economic": 0.45, "social": 0.25}},
		# The mean of the twelve infrastructure movers (-0.217 / -0.154, rounded); a cut
		# mirrors it.
		"infrastructure": {"up": {"economic": -0.22, "social": -0.15}, "down": {"economic": 0.22, "social": 0.15}},
		# No authored mover: a rise reads socially conservative, authored judgement
		# (flagged in the spec); a cut mirrors it.
		"defence": {"up": {"economic": 0.0, "social": 0.3}, "down": {"economic": 0.0, "social": -0.3}},
	},
}

## A tax key with no library row reads income's, the anchor row of statute's CHANNEL_PRICE
## too. The tax anchors themselves are each kind's `finance_anchor` in data/taxes/ (V5.3 e).
const FALLBACK_TAX_KEY := "income"

## Progressivity is an index in [0, 2]; it reads income's row, a full-range move
## weighing as 5 income points (authored judgement, flagged in the spec).
const PROGRESSIVITY_INCOME_POINTS := 2.5

## The size, in Statute's units (|value| x CHANNEL_COST), at which a bill reads wholly
## as its content: high_earner_surtax's (5.0 income points x 0.2). A smaller bill sits
## that far along the way from the coalition's own place.
const REF_SIZE := 1.0

## The name a tabled finance bill carries on the law surfaces.
const BILL_NAME := "Finance bill"  # i18n: msgid

## The range check at tabling (section 10, the parent's ruling on #334's call 2): a rate
## row's live rate plus its delta may sit this far past its kind's `rate_range_pct` and
## still table. A panel builds the delta as its target minus the live rate, so the sum
## can miss a bound the slider itself reached by a rounding step; a point in a billion is
## far below anything a slider or a row can mean.
const RANGE_TOLERANCE := 1e-9
