extends RefCounted

## V5.3 c' (docs/design/v5.3-c-register.md): the construction register's names and
## stand-ins. Every number here is a stand-in until tools/units_probe.gd has run and
## the author has accepted its table (the spec's section 12).

## A catalogue row's payoff. `capacity` is a unit a region counts (section 1);
## `potential` is one of the five projects, re-expressed at load from
## data/project-actions (section 8: the parent's ruling, one source, no copy);
## `network` is V5.4 d's, refused in a catalogue file until then.
const PAYOFF_CAPACITY := "capacity"
const PAYOFF_POTENTIAL := "potential"
const PAYOFF_NETWORK := "network"
const CATALOGUE_PAYOFFS := [PAYOFF_CAPACITY]

## A programme row of ns.unit_programmes: `op` builds or closes, `state` is where it
## stands. Only a DONE row moves a region's figure: a unit still building, or still
## being demolished, is not yet capacity gained or lost.
const OP_BUILD := "build"
const OP_DEMOLISH := "demolish"
const STATE_BUILDING := "building"
const STATE_DONE := "done"

## The files of data/units/ that are not catalogue rows.
const COFINANCING_FILE := "cofinancing.json"
const STOCK_DIR := "stock"

## A stock file's levels, weighted by the regions' people (data/regions `share`), must
## give its `national` back within this share of it (section 2 as amended; the check
## unemployment_rel gets at import). Stand-in.
const UNIT_LEVEL_TOLERANCE := 0.03

# --- The price (section 4) -----------------------------------------------------

## The range's half-width w around the estimate, by the competence of the minister
## of the type's line: w = FOG_MAX - (FOG_MAX - FOG_MIN) x competence, a vacant seat
## at the widest. Stand-ins.
const UNIT_FOG_MAX := 0.25
const UNIT_FOG_MIN := 0.08

## Concentration: the units ordered in one region within CONC_MONTHS, beyond
## CONC_FREE of that region's start stock (in units), raise the unit price there by
## CONC_SLOPE points per further point of the stock. Stand-ins.
const UNIT_CONC_MONTHS := 12
const UNIT_CONC_FREE := 0.05
const UNIT_CONC_SLOPE := 1.0

## How many programmes may build at once (the five projects do not count). Stand-in.
const UNIT_PROGRAMMES_MAX_OPEN := 4

# --- The overrun's odds (section 5), fixed at tabling --------------------------

## The type's overrun_odds x (ODDS_BASE - competence), kept between MIN and MAX.
const UNIT_ODDS_BASE := 1.5
const UNIT_ODDS_MIN := 0.05
const UNIT_ODDS_MAX := 0.60
