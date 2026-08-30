extends RefCounted

## Tuning for src/sim/regions.gd. See docs/region-economy-model.md.
##
## THIS FILE SHIPS NO TUNED CONSTANT, which is src/sim/projects_constants.gd's
## position reached a second time, and the reason is the model rather than restraint:
## a region's trend IS its own sector mix read through economy_constants.SECTOR_TREND,
## the same expression Economy.trend_pct() applies to a nation. A coefficient in front
## of it would be one strength written twice -- investment_action.gd's refusal.
##
## What is here is one key and one bound.


## The unnamed remainder of the national output: extra-regio -- offshore platforms,
## embassies, ships -- which is what `<CC>ZZ` holds and why it was never in the
## roster. SHARES are still never stored (Region.national_gdp_residual() derives
## one), but the LEVEL has to live somewhere or the sum cannot close.
##
## An underscore cannot begin a NUTS code, so this key can never collide with a
## region's own.
const RESIDUAL_KEY := "_residual"


## How far a region's share of national GDP may drift from where it started, in
## share points. docs/economy-model.md's divergence argument is PER QUANTITY, so a
## new quantity feeding a compounding path owes it a bound -- and this one is a bound
## rather than a dial: at the measured mix spread nothing approaches it, and
## tools/regions_probe.gd reports the slack rather than tuning against it. It exists
## so a later session that widens the mix channel cannot silently produce a France
## that is one region.
const SHARE_DRIFT_MAX := 0.15
