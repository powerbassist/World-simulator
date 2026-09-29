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
## 0.1. A move across the continent (Lisbon-Warsaw, ~2900 km by road graph)
## is ten times less likely than a next-region move; the firm that does move
## far had a reason. 2000 km is the scale at which V2.4a's travel pricing
## stops feeling domestic. The floor keeps the hazard strictly positive so a
## draw can always fire it -- a distance that killed the hazard outright
## would make the clamp set the number.
const RELOCATE_KM_SCALE := 2000.0
const RELOCATE_DISCOUNT_FLOOR := 0.1

## The base monthly failure hazard, before multipliers. Anchored so the whole
## band lands inside "a handful of failures per nation per fourteen-year run".
## THE PROBE CORRECTED THE ANCHOR, recorded rather than hidden: the first
## draft (0.001) assumed multipliers mostly 1, but a DECLINING sector carries
## +1 for every major in it permanently -- half the register sits at x2 for
## the whole run -- and measured 1.86 failures/nation/run, 2.7x the declared
## band's top. Shipped at the smallest in-band value per the discipline: 0.0003
## measures ~0.55/nation/run (tools/industry_probe.gd).
const FAIL_BASE_MONTHLY := 0.0003

## The failure multipliers, added. A burdened sector doubles the base at its
## clamp (2 x BURDEN_MAX-scale burden): V1.4b's compliance arithmetic is
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
