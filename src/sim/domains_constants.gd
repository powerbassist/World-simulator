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

## A move never takes a sector under this share of its line, so no sector is
## zeroed by a reallocation (a sector at 0 would be a sector that no longer is).
const MIN_SHARE := 0.01

## How far a nation's start shares may sum from 1.0 before the loader refuses them
## (Content rounds to three decimals); inside it they are renormalised to exactly 1.
const SHARE_SUM_TOLERANCE := 0.002
