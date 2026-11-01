extends RefCounted

## V5.3 a: the regional development fund's tuning (docs/design/v5.3-ab.md 3.3,
## band A7; src/sim/region_funds.gd). Its own file, not region_constants.gd, which
## holds a key and a bound and reads itself to stay that way (tests/test_regions.gd):
## the fund's beta is a coefficient on a term the player buys, not on a region's own
## trend. The rule's ranges and bloc offsets are data (data/region-actions/fund.json).

## The fund's term in the region's growth deviation, in points a year:
## FUND_BETA x sqrt(the fund's bn a year as points of the region's output). SQUARE
## ROOT, not linear, because A7 asks one fund size (1 bn a year to the region with
## the highest unemployment) to lower unemployment by 0.3 to 1.0 point in 24 months
## in all four playable nations, and their worst regions run from 31 bn (POL's PL81)
## to 197 bn (FRA's FRE) of output: a linear response that gives FRE its 0.3 point
## gives PL81 well over 1.0. Diminishing returns in the fund's size against the
## region's is also the honest shape (absorption, leakage to other regions).
## 1.3 is a stand-in measured by tools/region_fund_probe.gd against A7, not a sourced
## elasticity.
const FUND_BETA := 1.3

## Stopping a fund early: every bloc the fund pleased gives back this share of what
## it gained -- processes' U-turn price (companies_constants.PROCESS_UTURN_SHARE),
## for the same reason: a promise withdrawn costs more than one never made.
const FUND_STOP_SHARE := 0.25

## At most this many funds open at once (the parent's call on #263, 2026-11-01).
## Without it a player could fund every region: the zero-mean term would cancel and
## what was left would be plain spending, a demand lever no one designed. Three
## keeps the verb a choice of where.
const FUND_MAX_OPEN := 3
