extends RefCounted

## V5.3 a: the regional development fund's tuning (docs/design/v5.3-ab.md 3.3,
## band A7; src/sim/region_funds.gd). Its own file, not region_constants.gd, which
## holds a key and a bound and reads itself to stay that way (tests/test_regions.gd):
## the fund's beta is a coefficient on a term the player buys, not on a region's own
## trend. The rule's ranges and bloc offsets are data (data/region-actions/fund.json).

## The fund's term in the region's growth deviation, in points a year:
## FUND_BETA x sqrt(the fund as a percentage of the region's output). The fund is a share
## of the region (the author, 2026-11-09), so one level is one effort in any nation. SQUARE
## ROOT, not linear, for the levels: a fund twice the size does not do twice the work
## (absorption, leakage to other regions). 1.3 is a stand-in measured by
## tools/region_fund_probe.gd against A7 at 1 % and 3 %, not a sourced elasticity.
const FUND_BETA := 1.3

## Stopping a fund early: every bloc the fund pleased gives back this share of what
## it gained -- processes' U-turn price (companies_constants.PROCESS_UTURN_SHARE),
## for the same reason: a promise withdrawn costs more than one never made.
const FUND_STOP_SHARE := 0.25

## At most this many funds open at once (the parent's call on #263, 2026-11-01).
## Without it a player could fund every region: the zero-mean terms would cancel and
## what was left would be plain spending through the demand channel, a stimulus by
## another door than the Budget's lines. Three keeps the verb a choice of where.
const FUND_MAX_OPEN := 3

## A fund row's status while it runs. Here so a leaf can read it without preloading the system.
const STATUS_OPEN := "open"
