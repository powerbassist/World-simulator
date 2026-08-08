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
## `europe` is V1.3d's, and it is the call V1.3a, V1.3b and V1.3c each deferred
## to it by name. Everything before it priced its domestic cost through
## bloc_offset; the bloc could not, for three structural reasons and not a
## thematic one. bloc_offset never enters issue_salience, so a Europe priced on
## it could never be named by the polling panel's agenda list or by
## elections.gd's attribution() -- the two surfaces that exist to tell the player
## WHY. A split price never clears the poll-noise floor in the headline figure,
## which docs/diplomacy-model.md measured, and Europe is a split issue by nature.
## And bloc_offset is a flat additive that cannot become more SALIENT, where a
## bloc rule biting hard is precisely the thing that should raise how much the
## country argues about Europe.
##
## The cost was measured before it was taken, by tools/bloc_probe.gd: every row
## below is scaled by 1/(1+w) once europe joins it, and S10's finding was the
## RATIO of public_finances to the five spending lines, which moves by +0.39%.
## See docs/bloc-model.md.
##
## V1.4c ASKED THE SAME QUESTION FOR `ownership` AND THE ANSWER IS NO, measured the
## same way and recorded here so a later session finds the reasons rather than the
## silence. tools/companies_probe.gd table (q), against V1.3d's four tests plus a
## fifth V1.4b forced:
##
##   1. The price is not nameable otherwise -- HOLDS, identically to europe's.
##   3. A flat offset cannot become more salient -- HOLDS, identically.
##   5. But a REGULATION has 1 and 3 identically too, and V1.4b took no key. The
##      proposed distinction was that state ownership is a single standing STOCK the
##      player can point at where a burden is a per-sector rule; it does not survive,
##      because `regulation_burden` summed over three sectors is equally a stock and
##      nothing about ownership's is more pointable-at. Same footing, same answer.
##   2. The satisfaction could not clear the model's own resolution: V1.4b measured
##      this layer's channels at ~0.1 %/yr of growth and ~0.02 points of
##      unemployment. A thirteenth row of near-zeroes on the polling panel is worse
##      than no row.
##   4. And the measured cost is -1.46% on the S10 ratio, in the UNSAFE direction,
##      where V1.3d's was +0.39% in the safe one. That is STRUCTURAL rather than a
##      bad candidate row: business carries `public_finances` at 0.34 and is the bloc
##      that makes ownership divisive at all, so any row expressing the mechanic
##      leans on the bloc S10's ratio lives in. Re-measured with business at 0.04 the
##      drift falls to -0.29% -- and a row that light does not express the mechanic.
##
## What names ownership to the player instead is the authored `bloc_offset` on
## data/company-actions/ownership.json, read on the polling panel's bloc rows -- the
## surface docs/diplomacy-model.md's finding has pointed at five times.
const ISSUE_KEYS := [
	"jobs", "growth",
	"tax_income", "tax_corporate", "tax_vat",
	"health", "education", "defence", "pensions", "infrastructure",
	"public_finances", "europe",
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
	"europe": "Europe",
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

## Units of bloc burden. The one scale in this table that is not a quantity in
## percentage points, because burden is already a normalised score rather than a
## measurement.
##
## NOT 1.0, and the reason is DEFICIT_SCALE_PP's exactly. bloc_constants.BURDEN_MAX
## is 1.0 and is reached only by breaching all four rules to their full tolerance
## at once -- an extreme, not a policy. The range the player actually moves this
## number over is roughly [0, 0.6]: one rule defied outright is 0.33, two is 0.59.
## At a scale of 1.0 that whole band is squeezed into the middle third of the
## issue, and tools/bloc_probe.gd measured the consequence -- one defied rule moved
## the headline figure by 3.24 points against a 3.0 noise floor, clearing it by
## almost exactly nothing, which is docs/scenario-model.md's `deu_grand_coalition`
## mistake. 0.60 maps the reachable band onto the full satisfaction range.
##
## Deliberately not folded into BURDEN_MAX: that constant bounds the MODEL and is
## what makes the four severities sum to exactly 1.0; this one converts a burden
## into what a voter feels. Collapsing them would make the burden's ceiling
## unmovable without also moving the electorate's reaction to it.
##
## Swept rather than reasoned to, because SALIENCE_GAIN makes the response to this
## constant sharply non-linear -- 1.00 gives one defied rule a headline move of
## -3.2, 0.60 gives -13.0, and the anchor that settles it is docs/coercion-model.md's
## measured -4.9 to -7.4 for a full embargo by the largest trading partner. Defying
## one bloc rule and being embargoed by Germany should cost about the same, and at
## 0.80 they do.
const EUROPE_SCALE := 0.80

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
## The `europe` row is V1.3d's, and it is the only issue in this table whose
## entries are NOT the row a bloc would write for itself. Every satisfaction in
## opinion.gd enters every bloc's score with the SAME SIGN -- blocs differ in how
## much they weigh an issue, never in which way it moves them -- so a bloc cannot
## be authored as pro-European through this channel. The entries below are
## therefore "how much does being overruled from Brussels dominate this bloc's
## agenda", one-signed, and the political SPLIT falls out of the rows that were
## already here rather than being authored:
##
##   pensioners (0.24) and rural (0.13) carry NO `growth` entry at all, so 37% of
##   the electorate receives the sovereignty cost and none of the single market's
##   upside, while business weights growth 0.19 and public_finances 0.34 and gets
##   both. A eurosceptic countryside and a pro-European boardroom, measured off a
##   table written at S5 for reasons that had nothing to do with Europe.
##
## Rows no longer sum to 1.0 and do not need to -- salience_weights() renormalises
## and the comment above already said a tuning pass need not keep them that way.
## What that renormalisation costs the eleven measured issues was the session's
## first measurement, not an afterthought: see tools/bloc_probe.gd table (a) and
## docs/bloc-model.md.
const BLOC_SALIENCE_BASE := {
	"workers": {
		"jobs": 0.34,
		"public_finances": 0.18,
		"tax_income": 0.15,
		"health": 0.10,
		"europe": 0.10,
		"tax_vat": 0.08,
		"growth": 0.08,
		"pensions": 0.07,
	},
	"pensioners": {
		"pensions": 0.38,
		"health": 0.21,
		"public_finances": 0.20,
		"jobs": 0.13,
		"europe": 0.10,
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
		"europe": 0.06,
	},
	"rural": {
		"infrastructure": 0.20,
		"public_finances": 0.18,
		"jobs": 0.16,
		"europe": 0.14,
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
		"europe": 0.06,
		"education": 0.06,
	},
	"students": {
		"education": 0.38,
		"jobs": 0.22,
		"public_finances": 0.14,
		"tax_vat": 0.10,
		"growth": 0.08,
		"health": 0.08,
		"europe": 0.05,
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
