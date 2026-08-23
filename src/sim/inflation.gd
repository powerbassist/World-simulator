extends RefCounted

## Inflation — V1.6b, the second session of the V1.6 block. A per-nation price level
## as a stock, driven by the unemployment gap, charging two prices: a growth cost on
## the economy and a thirteenth issue on the electorate. The model and every
## constant's rationale is docs/inflation-model.md; src/sim/inflation_constants.gd is
## the values.
##
## EVERYTHING IN THIS PROJECT IS IN CONSTANT PRICES AND EVERY RATE IS REAL, so there
## is nothing here for inflation to deflate, and that boundary was decided before a
## line of this file was written. A nominal layer would touch every measured constant
## in the project -- TAX_BASE_SHARE, every SECTOR_TREND, DEBT_REAL_RATE_PCT, every S10
## opinion scale, every balance figure ever quoted -- in exchange for a number the
## player already reads as real. Four nominal channels were considered and cut:
## real-income erosion (needs a nominal wage), inflation eroding the real debt stock
## (debt_eur_bn is already real), VAT as a price-level shock (a level, not a rate, and
## it makes a tax slider write inflation which prices back to the voter through a loop
## with no lag in it) and indexing the spending lines (they are shares of GDP and
## already auto-scale). What DOES reach the economy is relative-price distortion and
## uncertainty, which is a real cost needing no nominal quantity. See output_cost_pct().
##
## NOT A NEW MACHINE. quality_step()/capability_step()'s first-order lag, third use --
## src/sim/defence.gd at V1.3g, src/sim/society.gd at V1.5a, here. Including their
## call that a starting stock is its EQUILIBRIUM and not zero.
##
## SHIPS NO PLAYER VERB, and that is the decomposition's call rather than an omission.
## docs/brainstorm/mechanics-economy.md tiers the central bank, interest rates and
## quantitative easing Someday, and docs/tiers/out-of-scope-mvp.md records that France
## does not set its own rate -- so inflation is a pressure the player fights fiscally
## or not at all. docs/tiers/v1.md section 6 runs (a), (b) and (c) under V1.5's
## inverted rule, *ship a statistic and the price it charges*, and this is (b).
##
## Takes no loader, the discipline defence.gd, society.gd, trade.gd and coercion.gd
## all hold to: the target reads live unemployment and the live structural rate, so
## Budget.project() runs the real model forward on a copy and gets the real answer.
##
## Preloads its own constants and NOTHING ELSE -- a leaf, and more strictly one than
## society.gd, which needs cabinet.gd and demography.gd. It does not preload
## economy.gd or opinion.gd: both read THIS file's output through NationState, never
## the other way round, and a reverse edge would make that one-way relationship a
## convention rather than a fact. tests/test_inflation.gd reads the file and asserts
## the preload list is exactly this one.
##
## WRITES ns.inflation_pct and ns.inflation_impulse_pct AND NOTHING ELSE. The anchor
## and the start baseline are written once at init_nation() and never again;
## tests/test_inflation.gd walks every file in src/sim/ and fails if a second writer
## of any of the four appears. That is `share`/`state_share`/`regulation_burden`'s
## discipline at V1.4c and `gini_index`'s at V1.5c.

const K = preload("res://src/sim/inflation_constants.gd")


## A nation's starting inflation is its EQUILIBRIUM, not zero -- society.gd's and
## defence.gd's init_nation() comments apply word for word. A country whose prices
## have risen ~1.8 %/yr for thirty-five years is not at 0.0 on the day the game
## starts, and seeding at zero would mean every nation spends the first decade of
## every game climbing to its own anchor: a transient nobody authored.
##
## THAT SEED IS LOAD-BEARING FOR TWO EXISTING TESTS, not merely tidy.
## tests/test_opinion.gd requires every issue's satisfaction to read under 1e-9 at new
## game, and tests/test_state_copy.gd only catches a field missing from
## duplicate_state() when its value is NON-ZERO. Seeding at 0.0 would make the second
## check silently useless for all four fields here.
##
## start_inflation_pct is captured HERE rather than derived later, and it is the
## reference the issue satisfaction is measured against -- the treatment
## start_deficit_pct_gdp, start_bloc_burden and start_service_quality already get.
## Because it is captured at the equilibrium, `inflation - start_inflation` is EXACTLY
## 0.0 at new game for all ten nations, and so is output_cost_pct(). That is what lets
## the register go live without moving a single figure until something moves
## unemployment, and tests/test_inflation.gd asserts it with exact equality rather
## than is_zero_approx() -- V1.4a's precedent.
##
## Takes the Nation, unlike defence.gd's and society.gd's one-argument form, because
## the anchor is imported content. src/core/game_state.gd's comment above the inline
## `cycle_amplitude_rel` read states the rule this follows: inline is for content that
## seeds no live stock, and this seeds one. demography.gd's init_nation(ns, nation) is
## the shape.
##
## ORDER AGAINST THE OTHER init_nation() CALLS IS NOT A CONSTRAINT, unlike Demography
## before Society. game_state.gd sets unemployment_pct, start_unemployment_pct and
## structural_unemployment_pct to one figure before any of them run, so the gap is
## exactly 0.0 and the target equals the anchor whenever this is called. Said out loud
## because a reader looking at four ordered inits will otherwise invent a fifth
## constraint -- which is Unrest's own init comment's reason.
static func init_nation(ns, nation) -> void:
	var prices: Dictionary = nation.prices
	ns.inflation_anchor_pct = float(prices.get("inflation_pct", 0.0))
	ns.inflation_pct = inflation_target(ns)
	ns.start_inflation_pct = ns.inflation_pct
	ns.inflation_impulse_pct = 0.0


## Runs AFTER Economy -- it reads the unemployment Economy just settled -- and BEFORE
## Opinion, which prices it in the same month.
##
## THAT SLOT IS NOT SOCIETY'S AND UNREST'S, which both sit after Opinion, and the
## difference is worth stating because a reader will otherwise assume symmetry. Those
## two write a load that Opinion reads on the FOLLOWING month by design. This one
## writes a satisfaction Opinion reads on the SAME month, exactly as `jobs` and
## `growth` are read from figures Economy settled minutes earlier in the same tick.
##
## The impulse it writes is read by Economy on the NEXT month, which is
## unrest_impulse_pct's existing pattern and is what keeps the feedback loop from
## being an intra-month circular dependency.
##
## Runs for all ten nations. Only the player's opinion ticks, but the nine's inflation
## reaches the player through docs/trade-model.md's directed weight the moment their
## growth moves -- the same path V1.6a's cycle takes, and the reason this is not
## gated on has_budget.
static func tick_month(state) -> void:
	for ns in state.nations.values():
		_tick_nation(ns)


## Where inflation is heading, given how hot the labour market is running.
##
## A textbook expectations-anchored Phillips curve on the UNEMPLOYMENT gap, and the
## input is measured rather than assumed: docs/tiers/v1.md section 6's row asks for
## the OUTPUT gap, and the World Bank series says the output gap carries no signal and
## flips sign between sub-samples while the unemployment gap does not. See
## inflation_constants.INFLATION_UNEMP_BETA for the table.
##
## Reading unemployment also dissolves the row's other defect rather than patching it.
## "The gap, the impulse and (a)'s shock" is one quantity written three times -- the
## output gap IS the accumulated integral of the growth addends, so a target reading
## the gap and the impulses that fill it double-counts, which is V1.3c's
## `tariff_rate_pct` error. `unemployment_pct - structural_unemployment_pct` is ONE
## existing quantity that already carries the cycle, the demand impulse, the trade
## impulse and every other shock, through Okun's law in economy.gd.
##
## structural_unemployment_pct rather than start_unemployment_pct is deliberate and it
## buys a consequence nobody authored: raising income tax lifts the structural rate
## through STRUCT_INCOME_BETA's labour-tax wedge, which widens this gap and is
## therefore mildly INFLATIONARY. That is the wage-push story, and it falls out of two
## existing constants rather than being written.
static func inflation_target(ns) -> float:
	var gap: float = (
		float(ns.structural_unemployment_pct) - float(ns.unemployment_pct)
	)
	return clampf(
		float(ns.inflation_anchor_pct) + K.INFLATION_UNEMP_BETA * gap,
		K.INFLATION_MIN, K.INFLATION_MAX
	)


## One month of convergence. Pure, so tools/inflation_probe.gd can sweep over a
## fourteen-year horizon without building a GameState -- society.gd's quality_step()
## and defence.gd's capability_step() have the same signature for the same reason.
static func inflation_step(current: float, target: float) -> float:
	return clampf(
		current + K.INFLATION_CONVERGENCE * (target - current),
		K.INFLATION_MIN, K.INFLATION_MAX
	)


## The signed deviation of inflation from where this nation started, in points.
## Everything that prices inflation politically reads it through here, so the
## measured-against-its-own-start anchoring is not something a caller can bypass --
## quality_deviation()'s and capability_ratio()'s discipline.
##
## SIGNED, where output_cost_pct() below is one-sided, and the asymmetry is the point
## rather than an inconsistency. A voter punishes prices RISING against what they
## remember, so a president who inherits 5 % and delivers 2 % should be rewarded and
## here is. The economy's cost is about distance from the anchor in either direction
## and is bounded below for a different reason. Two prices, two shapes, two arguments
## -- docs/coercion-model.md's one verb, two prices.
static func inflation_deviation(ns) -> float:
	return float(ns.inflation_pct) - float(ns.start_inflation_pct)


## Points of annual growth lost to inflation this month. The standard real cost --
## relative-price distortion and uncertainty depressing output -- which is a REAL
## effect and so needs no nominal quantity, which is what lets it exist inside this
## project's constant-price boundary.
##
## ONE-SIDED, ABOVE THE ANCHOR ONLY, AND THE ONE-SIDEDNESS IS FORCED RATHER THAN
## CHOSEN. The two-sided form is the more realistic economics and it is UNSTABLE on
## its lower branch: below the anchor a negative impulse raises unemployment, which
## through a positive INFLATION_UNEMP_BETA lowers inflation further, which enlarges
## the cost -- a deflation spiral, and the only self-amplifying path this model would
## contain. docs/economy-model.md's stability argument is that no term feeds its own
## growth rate without a clamp between, and a two-sided cost would be the first
## exception.
##
## A deflation trap is a NOMINAL phenomenon: it needs a zero lower bound on a nominal
## interest rate, and there are no nominal rates here. So the same boundary that cuts
## the nominal layer cuts the lower branch, and the trap is recorded rather than
## modelled -- it is not that it would be wrong, it is that this model has no floor
## for it to hit.
##
## ABOVE the anchor the loop is NEGATIVE feedback and therefore self-correcting: high
## inflation gives a negative impulse, growth falls below trend, unemployment rises,
## the gap goes negative, the target falls below the anchor and inflation comes down.
## The loop gain is analytic -- see INFLATION_OUTPUT_BETA -- and stable for any
## candidate an order of magnitude above what ships.
static func output_cost_pct(ns) -> float:
	var above: float = maxf(
		0.0, float(ns.inflation_pct) - float(ns.inflation_anchor_pct)
	)
	return -K.INFLATION_OUTPUT_BETA * above


static func _tick_nation(ns) -> void:
	ns.inflation_pct = inflation_step(
		float(ns.inflation_pct), inflation_target(ns)
	)
	ns.inflation_impulse_pct = output_cost_pct(ns)
