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
