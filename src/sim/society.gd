extends RefCounted

## The delivery layer — V1.5a, the first session of the V1.5 block. A service's
## quality as a stock converging on sustained spending, and corruption as the factor
## that degrades what a unit of spending buys. The model and every constant's
## rationale is docs/society-model.md; src/sim/society_constants.gd is the values.
##
## NOT A NEW MACHINE, and that is the honest description rather than modesty.
## docs/tiers/v1.md §5 asks for "healthcare and education quality as outcomes of
## spending" and the project has built that shape three times already —
## military_capability at V1.3g, and potential_shift_pct twice at S4. This file
## completes and NAMES the pattern: capability_target()/capability_step() are lifted
## from src/sim/defence.gd outright, including their call that a starting stock is
## its EQUILIBRIUM and not zero.
##
## Takes no loader, the discipline defence.gd, trade.gd and coercion.gd all hold to:
## quality reads the live spending line and the live corruption level, so
## Budget.project() runs the real model forward on a copy and gets the real answer.
##
## Preloads cabinet.gd and its own constants and NOTHING ELSE from src/sim/ — a leaf,
## reachable from game_state.gd without dragging a chain behind it. It does not
## preload opinion.gd: opinion reads THIS file's output through NationState, never the
## other way round, which is what keeps the double count resolvable in one place.
##
## WRITES ns.service_quality and nothing else. `corruption` has exactly one writer in
## the project and it is Legislature.apply(); this file only ever reads it. That is
## `regulation_burden`'s discipline at V1.4b, and tests/test_society.gd asserts it.

const K = preload("res://src/sim/society_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Demography = preload("res://src/sim/demography.gd")


## A nation's starting quality is its EQUILIBRIUM, not zero — defence.gd's
## init_nation() comment applies word for word. A France that has spent 11.0 % of GDP
## on health for decades has hospitals on the day the game starts, and seeding at
## zero would mean every nation spends the first decade of every game acquiring them:
## a transient nobody authored, visible in every number that reads quality, and wrong.
##
## start_service_quality is captured HERE rather than derived later, and it is the
## reference every satisfaction term is measured against — the treatment
## start_deficit_pct_gdp and start_bloc_burden already get in opinion.gd. Because it
## is captured at the equilibrium, `quality - start_quality` is EXACTLY 0.0 at new
## game for all ten nations, which is what lets the register go live without moving
## a single figure until the player touches a spending line.
##
## Runs for all ten nations even though only the player's opinion ticks, so the state
## shape is uniform and duplicate_state() has nothing conditional to copy — the
## reason opinion.gd's own init_nation() gives.
static func init_nation(ns) -> void:
	ns.service_quality = {}
	ns.start_service_quality = {}
	for key in K.QUALITY_KEYS:
		var q: float = quality_target(ns, key)
		ns.service_quality[key] = q
		ns.start_service_quality[key] = q


## Runs in Companies' slot in src/ui/main.gd's order — AFTER Opinion, not before it
## — and Budget.project() runs it in the same place. The first draft of this comment
## said "before Opinion", on the general tick-order argument that opinion should react
## to figures that have already settled. That is the wrong argument here, and
## Companies' own comment has the right one: quality feeds `health` satisfaction,
## which feeds `overall_approval_pct`, which IS an entry in
## legislature_constants.PRECONDITION_FIELDS — so quality → approval → which laws are
## available → a `society` law → corruption → quality is a closed loop, and the
## one-month lag is what breaks it structurally rather than by being careful. A stock
## with a ~34-month half-life is indifferent to the lag; the loop is not.
##
## For all ten nations, like Defence.tick_month(). The nine have no budget model and
## their spending never moves, so their quality sits exactly still for a full run;
## tests/test_society.gd asserts that rather than leaving it to this comment, which is
## the assertion tests/test_defence.gd makes about capability for the same reason.
static func tick_month(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		_tick_nation(state.nations[id])


# --- The stock ----------------------------------------------------------------

## What this line's quality is converging on: the nation's own spending on it,
## delivered. Derived and never authored — an authored per-nation service quality is
## a second number somebody has to keep in step with the first, and it disagrees with
## it the moment a player moves the lever. defence.gd's capability_target() makes the
## identical argument about military strength.
##
## Multiplied by effectiveness as well as by delivery, and the two are different
## claims that happen to be commensurable: Cabinet.effectiveness() is how well this
## government runs the department, delivery is how much of the money reaches the
## service at all. A vacant ministry and a corrupt state are independently bad.
##
## V1.5b DIVIDES BY THE DEPENDENCY FACTOR, and that one divisor is the whole of
## "ageing driving pension and health costs". docs/tiers/v1.md section 5 asks for a
## COST and `spending_pct_gdp` is a player-set RATE, so ageing cannot drive it; what
## ageing can do is make the same rate buy less. A nation's own starting spending is
## by definition adequate for its own starting dependency, so the required rate scales
## with the ratio and nothing has to be authored — no per-capita benefit, no
## beneficiary count, no cost side. The factor is exactly 1.0 at new game for all ten
## nations, so this is inert until the clock runs.
##
## Raised to a per-line elasticity, because a pension is spent per pensioner and a
## health budget is only age-graded. See society_constants.DEPENDENCY_ELASTICITY —
## `pensions` at 1.0 is definitional rather than tuned, and it is what finally gives
## `pensions` the denominator that kept it out of QUALITY_KEYS at V1.5a.
static func quality_target(ns, key: String) -> float:
	var spend: float = float(ns.spending_pct_gdp.get(key, 0.0))
	return clampf(
		spend * Cabinet.effectiveness(ns, key) * delivery_factor(ns)
		/ dependency_divisor(ns, key),
		K.QUALITY_MIN, K.QUALITY_MAX
	)


## What ageing has done to what a point of GDP on this line buys, since the game
## began. Exactly 1.0 for a line with no entry in DEPENDENCY_ELASTICITY, and exactly
## 1.0 at new game for every line that has one — so a caller need not know which lines
## are age-graded, which is quality_deviation()'s own property and what keeps the
## elasticity table a registry.
##
## Read through here rather than inline so the clamp on the FACTOR is what bounds this
## and the clamp inside quality_target() stays slack. A divisor bounded away from zero
## is the difference between a guard rail and the clamp setting the number.
static func dependency_divisor(ns, key: String) -> float:
	var elasticity: float = float(K.DEPENDENCY_ELASTICITY.get(key, 0.0))
	if elasticity == 0.0:
		return 1.0
	return pow(Demography.dependency_factor(ns), elasticity)


## One month of convergence. Pure, so tools/society_probe.gd can sweep the constant
## over a fourteen-year horizon without building a GameState — defence.gd's
## capability_step() has the same signature for the same reason.
static func quality_step(current: float, target: float) -> float:
	return clampf(
		current + K.QUALITY_CONVERGENCE * (target - current),
		K.QUALITY_MIN, K.QUALITY_MAX
	)


## How much of a unit of spending reaches the service. 1.0 at corruption 0, so this
## factor is EXACTLY neutral for every game in which no `society` law has ever
## passed — `trade_baseline_by_partner`'s idiom and V1.4a's, and what makes the
## claim in init_nation() above exact rather than approximate.
##
## Signed both ways: see society_constants.CORRUPTION_MAX for why a one-directional
## corruption level would be a permanent monotone charge AND make an anti-corruption
## law inert on a clean state.
static func delivery_factor(ns) -> float:
	return clampf(
		1.0 - K.CORRUPTION_DELIVERY_BETA * float(ns.corruption),
		K.DELIVERY_MIN, K.DELIVERY_MAX
	)


## The signed deviation of a line's quality from where it started, in points of GDP.
## Everything that prices quality reads it through here — so the
## measured-against-its-own-start anchoring is not something a caller can bypass by
## subtracting from something else, which is capability_ratio()'s discipline.
##
## Returns exactly 0.0 for a line with no stock, so opinion.gd may ask about any of
## the five spending lines without knowing which are in QUALITY_KEYS. That is what
## keeps the registry a registry: adding `pensions` at V1.5b needs no change in
## opinion.gd at all.
static func quality_deviation(ns, key: String) -> float:
	if not ns.service_quality.has(key):
		return 0.0
	return (
		float(ns.service_quality[key])
		- float(ns.start_service_quality.get(key, 0.0))
	)


static func _tick_nation(ns) -> void:
	for key in K.QUALITY_KEYS:
		ns.service_quality[key] = quality_step(
			float(ns.service_quality.get(key, 0.0)), quality_target(ns, key)
		)
