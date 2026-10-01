extends RefCounted

## V4.7b B1: the autonomy machine's constants. Every band below was DECLARED
## BEFORE the probe ran (tools/industry_probe.gd), the same discipline
## companies_constants.gd's own history records a dozen times: a number landing
## outside its band is a finding, not a reason to widen the band. The machine
## is src/sim/industry.gd; this file is the values.

## The largest autonomous share drift one major may take in a month, in the
## sector's MAJORS partition. Anchored on V1.4a's calibrated verb rate:
## SHARE_SHIFT_PER_MONTH is 0.002 for a FULLY subsidised firm, so a firm's own
## management never moves share faster than the player's standing subsidy --
## the world's actors cannot out-shout the player's one lever. Signed by the
## sector's own trend and zero-sum across the partition (the Trade.sector_shift
## idiom), so an idle world leaves every sector's named sum exactly where the
## content put it.
const INVEST_STEP := 0.002

## The share of major-months in which invest intent DRAWS at all: half the
## majors try to grow or shed in a month, the other half sit the month out.
## The value the idle band probe's partition stability rode as shipped, named
## here rather than left inline in _invest (the ultra's find: every other
## machine frequency in the file draws against a named threshold).
const INVEST_PROBABILITY_MONTHLY := 0.5

## A major's chance, per year, of considering a move -- before the distance
## discount. The tier doc's "relocate between regions ... make a relocation
## MEAN something" is a rare event by design: each one should be a story
## rather than weather. THE PROBE CORRECTED THE ANCHOR: the first draft (2 %)
## authored "a handful per run" in its own comment while arithmetic gave
## 317 x 0.02 x 14 = ~89 raw moves -- the comment and the constant disagreed,
## and the run measured 42. Shipped at the value the comment meant:
## 0.2 %/year measures ~4-9 moves per run worldwide (tools/industry_probe.gd).
const RELOCATE_HAZARD_YEARLY := 0.002

## The distance discount on the relocation hazard: 1 - km/2000, floored at
## 0.1. 2000 km is the scale at which V2.4a's travel pricing stops feeling
## domestic. The floor keeps the hazard strictly positive so a draw can
## always fire it -- a distance that killed the hazard outright would make
## the clamp set the number. The far-move story this scale once carried
## (Lisbon-Warsaw at ten times a next-region move) is DEAD BY CONSTRUCTION:
## the machine lands the firm on the graph-NEAREST other region only, so
## the discount is a near-constant x0.85-0.98 -- companies-model section 37
## records it, and this comment now does too (the pass-8 fleet's find:
## a re-tuning session would have tuned an end that cannot fire).
const RELOCATE_KM_SCALE := 2000.0
const RELOCATE_DISCOUNT_FLOOR := 0.1

## The base monthly failure hazard, before multipliers. Anchored so the whole
## band lands inside "a handful of failures per nation per fourteen-year run".
## THE PROBE CORRECTED THE ANCHOR, and the first draft's RECORDED REASON was
## wrong in its own terms (the pass-4 fleet's find, fixed at the record):
## 0.001 measured 1.86 failures/nation/run against a band topping at 0.7, and
## the draft blamed a "declining-sector x2 permanent" multiplier -- but NO
## declining sector exists in shipped content (every SECTOR_TREND positive
## since c4f8f3c), so the declining term contributes exactly 0 and the
## measured 1.86 is the base alone: ~10.9 majors/nation x 168 months x 0.001.
## Shipped at the smallest in-band value per the discipline: 0.0003 measures
## ~0.55/nation/run (tools/industry_probe.gd). The DECLINING term in the
## hazard stays: it is content-shaped, and a sector authored into decline
## turns it on without touching this file.
const FAIL_BASE_MONTHLY := 0.0003

## The failure multipliers, added. A burdened sector TRIPLES the base at the
## burden clamp (1 + 2 x BURDEN_MAX 1.00): V1.4b's compliance arithmetic is
## already the model's "rules have casualties" channel and the failure is its
## tail. A withdrawn subsidy counts once (the state pulled support the firm
## had organised around); a declining sector counts once. The plan's shape:
## base x (1 + 2 x burden + withdrawn + declining).
const FAIL_BURDEN_WEIGHT := 2.0
const FAIL_WITHDRAWN_WINDOW_MONTHS := 12
const FAIL_WITHDRAWN_TERM := 1.0
const FAIL_DECLINE_TERM := 1.0

## Months a failed major's rescue window stays open. Six is half a year: long
## enough to answer inside a term's arithmetic, short enough that ignoring a
## failure is a decision the player made. The window lapsing commits the
## failure (the share is already 0; the flag stops being revertible).
const RESCUE_WINDOW_MONTHS := 6

## A major's chance, per year, of DRAWING a foreign bid, before eligibility.
## Takeover interest is rarer than failure -- the tier doc's "be bought by a
## foreign rival" is an event, not a state. Eligibility (a foreign major in
## the same sector with a larger live share) narrows it further; the probe
## counts what actually opens.
const BID_HAZARD_YEARLY := 0.01

## Months a pending bid stays answerable. Three is a quarter's notice: the
## player must notice the card and decide; an unanswered bid lapses without
## penalty (the foreign state's interest was not a demand).
const BID_WINDOW_MONTHS := 3

## The bid-hazard multiplier for a firm the player has COURTED --
## court_investor's flag. The verb's whole meaning is asking for exposure:
## five times the interest rate is what "the state quietly invites foreign
## capital" buys, and the exposure is exactly that the takeover verbs go
## live on a firm the player nominated.
const COURTED_BID_MULTIPLIER := 5.0
