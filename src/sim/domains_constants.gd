extends RefCounted

## V5.3 a, the sectors (docs/design/v5.3-ab.md 3.1; src/sim/sectors.gd,
## src/core/loaders/domains_loader.gd). data/domains/ holds the sourced facts
## (Content's: shares, start quantities, sources); the tuning lives here.

## The sector ids each spending line is split into (agreed with Content,
## 2026-11-01). The loader refuses a sector id with no elasticity below, so a row
## that names a sector this table does not know is a load error, not a sector that
## silently moves nothing (band A2).
const SECTOR_IDS := {
	"health": ["hospitals", "primary_care", "prevention"],
	"education": ["schools", "universities", "vocational"],
	"infrastructure": ["transport", "energy_networks", "digital"],
	"defence": ["personnel", "equipment", "operations"],
	"pensions": ["basic_pension", "minimum_income"],
}

## How strongly each sector's quantity answers its own spending: the quantity moves
## by (spend now / spend at start) ^ ELASTICITY, a magnitude above zero. The row's
## `better` gives the direction -- more spending always improves the quantity, so a
## lower-is-better quantity (pupils per teacher) falls -- which keeps Content free
## to pick either kind of figure. Stand-ins (Systems), first proposals for a spend
## that moves the figure less than one for one.
const ELASTICITY := {
	"hospitals": 0.6, "primary_care": 0.5, "prevention": 0.4,
	"schools": 0.5, "universities": 0.6, "vocational": 0.5,
	"transport": 0.3, "energy_networks": 0.3, "digital": 0.2,
	"personnel": 0.9, "equipment": 0.7, "operations": 0.6,
	"basic_pension": 0.8, "minimum_income": 0.8,
}

## The lowest spending ratio quantity() raises to the elasticity: a line cut to 0
## would otherwise give a lower-is-better quantity of infinity (pow(0, -e)).
const RATIO_FLOOR := 0.01

## A move never takes a sector under this share of its line, so no sector is
## zeroed by a reallocation (a sector at 0 would be a sector that no longer is).
const MIN_SHARE := 0.01

## How far a nation's start shares may sum from 1.0 before the loader refuses them
## (Content rounds to three decimals); inside it they are renormalised to exactly 1.
const SHARE_SUM_TOLERANCE := 0.002

## V5.3 a, the regional priority (docs/design/v5.3-ab.md 3.3 (a) 1, src/sim/sectors.gd):
## "put hospitals first in Hauts-de-France" raises the region's spending per head on
## the sector by this share, and every other region's falls so the money is the same
## (the line's total, the national quantity and every channel unchanged). A stand-in.
const PRIORITY_UPLIFT := 0.20

## What the money a priority moves does to the region (#267, the parent's ruling: it
## must move a real outcome): a term in the region's growth deviation, zero-mean as a
## fund's, of PRIORITY_BETA x the money as points of the region's output, fixed when
## the priority is set (src/sim/sectors.gd; src/sim/regions.gd reads the register).
## LINEAR AND SMALL, not the fund's FUND_BETA x sqrt(): a priority costs the Budget
## nothing (only its PRIORITY_MONTHS term and its cap at the nation's unemployment
## rate bound it), and the fund's response on its money would make it
## the stronger verb (2.5 points in France's worst region for basic pensions, the
## largest sector, against 0.93 for a 1 bn fund there). At 0.25 that largest case
## equals a 1 bn fund and hospitals give a third of it. A stand-in, the author's call.
const PRIORITY_BETA := 0.25

## The parent's two TAKEs on #267. No free stacking: one region per sector (a second
## replaces the first, which is the choice) and a REGION holds at most this many
## priorities. A term, not a standing lift: a priority lasts PRIORITY_MONTHS,
## renewable by setting it again, the month it ends on its row for the strip.
const PRIORITY_MAX_PER_REGION := 2
const PRIORITY_MONTHS := 36
## The parent's call on #267 (QA's measure: renewed freely, pensions + hospitals kept
## FRE's unemployment ~0.45 points lower and grew its output share 11.8 % in ten
## years -- a permanent lift): a region's priority on a sector may be renewed this many
## times (6 years in all), and once it stops -- its term runs out, it is cleared, or
## another region takes the sector -- that region waits PRIORITY_REST_MONTHS before it
## can take that sector again (a stop by clearing too, else clear-and-set would restart
## the count). The strip shows both (Sectors.priority_estimate()).
const PRIORITY_MAX_RENEWALS := 1
const PRIORITY_REST_MONTHS := 36

## V5.3 a + b, the sector warnings (src/sim/sector_warnings.gd; band B7, the parent's
## option (c)). A sector is in its bad band once its quantity is this share of its
## start figure worse. A stand-in, set by when it fires on a held line (the game's own
## month, nobody answering): at 3 % the first crossings fall in months 34 to 37, inside
## a first term with time left to answer; at 5 % in months 43 to 55, about when it ends.
const WARNING_BAND := 0.03
## After a sector leaves its band, the months before a return can arrive again: the
## mark shows at once, the arrival waits, so a figure sitting on the band's edge does
## not ask every month. A stand-in.
const WARNING_REARM_MONTHS := 12
## The trend's length, for "the worst in ten years" (the spec's own wording, 3.1).
const TREND_MONTHS := 120
## A yearly need rate past this is a data error (the highest sourced cell is 5.24).
const NEED_DRIFT_MAX_PCT_YEAR := 10.0
