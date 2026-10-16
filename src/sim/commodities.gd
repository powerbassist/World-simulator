extends RefCounted

## The commodity layer -- V4.6. Task 1 turned the goods and the recipes into DATA;
## this file is the machine that runs them. Model: docs/commodities-model.md;
## the step-0 verdict it narrows to is reports/production_gdp_probe.txt.
##
## ============================================================================
## IT MODELS CHANGES, NEVER THE LEVEL (the step-0 gate's binding verdict)
## ============================================================================
## The probe fitted one recipe set to the 29 nations and missed worst-case by
## 82 % (LUX), so "GDP is what the recipes say it is" is false and this file does
## not say it. `ns.gdp_eur_bn` stays V1.5's measured register figure and NOTHING
## HERE WRITES IT. What this file produces is a per-month value-added figure on
## `commodity_state`. Since V4.6's Task 3 the machine runs in the live month
## (main.gd, after Economy and before Opinion) and in balance_probe.gd. No SIM
## module reads the `commodity_state` register; its readers are the UI surfaces --
## Task 4's Commodities panel and the two map layers -- which read after the tick
## and never feed the simulation back. The one sim reader of anything this module
## writes is the events machine, and it reads the crossing stamp
## `ns.commodity_high_month` (outside the register), never `commodity_state`.
##
## A LEAF, and the tier's own list of what it may touch: commodity_constants, and
## nothing else. No economy, no trade, no budget, no UI. Every number it reads of
## the world it reads off NationState -- the `siting.gd` line, one layer up, where
## that file takes plain Dictionaries because its caller owns the register and
## this machine genuinely owns one (`calendar.gd`'s position rather than siting's).
##
## WHAT IT OWNS: `ns.commodity_state`, for every nation, and the one stamp
## `ns.commodity_high_month` (the absolute month a good's price last crossed up
## through K.HIGH_PRICE_RATIO of base -- the events machine's hook reads it, since the
## register keeps no history to read a crossing off). Single writer of both,
## pinned by tests/test_commodities.gd reading src/. What it never does: write
## `sector_output` or `gdp_eur_bn` (Economy's), or reach a panel.
##
## DETERMINISM IS THE LAW: no rand(), no RandomNumberGenerator, no mutable state
## a month can observe. Every loop walks an explicitly SORTED id list, never a
## Dictionary's iteration order -- V1.3b's `Trade.weight_table()` states the reason
## once and it holds here unchanged, because an unordered walk lets one nation's
## month depend on an insertion history and the balance harness's whole promise is
## that two runs differing in one decision differ in nothing else. The one static
## below is a MEMO keyed on the loader instance (`_loader_tables`); it is a pure
## function of content the loader never mutates, so it is invisible to the tick.
##
## ============================================================================
## THE MODEL, AND WHY IT IS THIS SHAPE
## ============================================================================
## Per month, in this order:
##   1. CAPACITY   -- what each nation COULD make, from its measured sector mix.
##   2. DEMAND     -- what it wants, from a world per-capita basket modulated by
##                    the live price through DEMAND_ELASTICITY.
##   3. PRODUCTION -- recipe-limited, in the recipe graph's own depth order.
##   4. TRADE      -- surplus nations offer, deficit nations take, sorted ids.
##   5. PRICE      -- the world's own FLOW gap moves the world price, band-clamped.
##   6. VALUE      -- what the month's output was worth, for the UI surfaces that
##                    read it.
##
## PRODUCTION IS NOT CAPPED AT DOMESTIC DEMAND, and that is measurement's finding
## rather than a preference. Capping it makes every nation an autarky by
## construction, so nobody ever holds a surplus, so trade is identically zero and
## the price vector walks to its ceiling and stays there (measured: 32 of 60 goods
## clamped, zero trade turnover). A nation produces what its endowment supports
## and SELLS THE REST; that surplus is the trade model and the reason the clamp
## sits at 4 goods rather than 32.
##
## THE CAPACITY MIX AND THE DEMAND MIX COME FROM ONE STRUCTURE, built from the
## recipe table itself: the value weight each good carries in the fixed point of
## "one unit of every good, pulled through its own input demands". This is the
## session's central design call and it was MEASURED, not assumed. The prototypes
## tried capacity from the sector mix against demand from an authored basket, and
## every such pairing pins between 25 and 50 of the 60 prices to a band edge
## inside 300 months: two structures that disagree for no model reason are a
## machine whose only resting state is the clamp, i.e. a dead one dressed as a
## permanent shortage. Sharing the structure leaves the disagreement where it is
## REAL and nameable -- the recipe chain wants more of some goods than that good's
## own share of sector output provides -- and that residue is exactly the trade
## imbalance and the shortfall the tier promises. NO CONSTANT WAS TUNED TO MAKE IT
## COME OUT THIS WAY, which is `projects_constants.gd`'s and
## `region_constants.gd`'s position a fourth time.
##
## THE ONE PER-NATION INPUT IS THE MEASURED SECTOR MIX, which is register data
## (V1.5's World Bank figures) and not a model parameter: a nation with 89 %
## services (LUX) has almost no capacity for steel and must buy it, and that is
## the trade dependency the tier's map mode later draws. There is no
## `if nation_id == "FRA"` anywhere below -- engine-decision rule 1.

const K = preload("res://src/sim/commodity_constants.gd")

## Good category -> the measured sector that endows it. The five industrial
## categories collapse because `ns.sector_output` has exactly three keys
## (economy_constants.SECTOR_TREND's, the register's own vocabulary, not a choice
## this file may widen). Not content, so not data/: a new CATEGORY is a data edit
## (data_loader.COMMODITY_CATEGORIES) but WHICH SECTOR endows it is a property of
## the three-sector register and belongs beside its reader.
const CATEGORY_SECTOR := {
	"raw": "industry",
	"agri": "agriculture",
	"energy": "industry",
	"intermediate": "industry",
	"capital": "industry",
	"consumer": "industry",
	"services": "services",
}

## THERE IS NO CATEGORY ORDER CONSTANT HERE, and its absence is a fix rather than
## an omission. The first version of this file carried one and used it as the
## production order, which was wrong -- categories are a COARSE order: `energy`
## holds both `uranium_fuel` (depth 1) and `electricity` (depth 2, made from it),
## so electricity came out before the fuel it needs and the whole downstream chain
## followed it down, silently. `_production_order()` computes the real order from
## the recipes instead. A category list is the SHAPE THAT PRODUCED THAT BUG, so
## there is deliberately no second one to reach for: a good's category is read
## where it means something (CATEGORY_SECTOR, and the demand basket in `_want`),
## and never as an ordering.


## The seven keys every `commodity_state` carries, in `init_nation()`'s own write
## order. The lazy-seed gate reads THIS list rather than `is_empty()` alone: a
## hand-built or hand-edited register carrying only SOME of the keys passes an
## emptiness test and then faults on the first missing one mid-tick (`_want()`
## reads `["price"]` before anything writes it), flooding SCRIPT ERRORs instead of
## reseeding. A register missing ANY key is no register at all and reseeds WHOLE,
## so the failure mode is a silent deterministic rebuild rather than a crash.
const STATE_KEYS := [
	"capacity", "output", "demand", "surplus", "trade", "price", "value_added_eur_bn",
]


## Seed ONE nation's commodity state. Called from `new_game` beside
## `Regions.init_nation()` and `Migration.init_nation()`, for their reason: each
## fills a register at the start of the game. This one's `capacity` is a
## SEED-TIME SNAPSHOT rather than a live stock -- the tick re-derives capacity
## from the live `sector_output` every month and never reads the stored key --
## and the world price it lays down is the register's own starting vector.
##
## Every good gets a capacity proportional to its sector's measured output. A
## NATION WITH NO INDUSTRY HAS NO CAPACITY FOR STEEL, and that zero is the truth
## rather than a degenerate case -- it is the state a shortage test creates and
## the reason `_bucket()` carries no floor. Every nation file carries all three
## sectors above zero, so the zero is reached by a fixture or by a player-caused
## collapse and not by content.
static func init_nation(ns, loader) -> void:
	var tables: Dictionary = _loader_tables(loader)
	var structure: Dictionary = tables["structure"]
	var endowed: Dictionary = tables["endowed"]
	var capacity: Dictionary = {}
	for good_id in _goods(loader):
		var good: Dictionary = loader.commodity_goods[good_id]
		capacity[good_id] = _capacity_of(ns, good, structure, endowed)

	ns.commodity_state = {
		"capacity": capacity,
		"output": _zeros(loader),
		"demand": _zeros(loader),
		"surplus": _zeros(loader),
		"trade": _zeros(loader),
		"price": _base_prices(loader),
		"value_added_eur_bn": 0.0,
	}


## The month. Capacity and demand first, then production, then trade, then the
## world price, then the value the month produced.
static func tick_month(state, loader) -> void:
	var ids: Array = _goods(loader)
	var nation_ids: Array = state.nations.keys()
	nation_ids.sort()

	# THE LAZY SEED -- NOT a pre-serialisation bridge since Task 5, and it survives
	# the serialisation rather than being deleted with it: save_manager refuses a
	# mismatched version outright, so the `{}` this catches now comes from a
	# payload with the key absent, a hand-built fixture, or any caller arriving
	# before the first tick rather than from a pre-V4.6 save. THE PARTIAL REGISTER
	# is the same arrival one step in: a payload carrying some keys and not others
	# passes an emptiness test and then faults on the first missing index, so the
	# gate reads STATE_KEYS and reseeds the whole register instead. The seed lives
	# HERE rather than in the load path for two reasons: it keeps the single-writer
	# pin intact (this file alone writes the field), and it keeps ONE seeding route
	# rather than two that can drift. That the two routes agree to the bit is what
	# tests/test_commodities.gd compares, and it is deterministic for
	# init_nation's own reason -- a pure function of the nation's measured mix.
	# (A reseed puts prices back at base, so the next tick can stamp a crossing the
	# world did not make -- a robustness path only, never reached in a normal game.)
	for nation_id in nation_ids:
		var ns = state.nations[nation_id]
		if ns.commodity_state.is_empty() or not ns.commodity_state.has_all(STATE_KEYS):
			init_nation(ns, loader)

	# The world's own basket, once: output per head, and each sector's share of
	# the world's measured output. Both are aggregates of the REGISTER, so moving
	# a nation's measured mix moves a world price and no constant does.
	var world_pop := 0.0
	var world_value := 0.0
	var world_sector_share := {}
	for nation_id in nation_ids:
		var ns = state.nations[nation_id]
		world_pop += ns.population
		world_value += ns.gdp_eur_bn
		for sector in _sectors(ns):
			world_sector_share[sector] = float(world_sector_share.get(sector, 0.0)) + _sector_value(ns, sector)
	if world_pop <= 0.0 or world_value <= 0.0:
		return
	var per_capita := world_value * 1e9 / 12.0 / world_pop
	for sector in world_sector_share.keys():
		world_sector_share[sector] = float(world_sector_share[sector]) / (world_value * 1e9 / 12.0)
	# THE DEMAND MIX IS ANCHORED to the world's AUTHORED sector mix (data/nations,
	# static content), while its SIZE stays the live world output above. Read off
	# the live register, demand moved one-for-one with capacity: a nation that lost
	# its industry took the same slice out of the world's demand for industrial
	# goods, the gap stayed 0, and no shortage ever reached a price (measured
	# 2026-10-14 once the double count below was gone: FRA's industry zeroed for six
	# months left steel's price unmoved). Anchored, a collapsed endowment is a real
	# world shortfall. Static content, so a save needs no field: every load
	# re-derives the same mix. A fixture loader without a nation's data keeps the
	# live mix rather than inventing one.
	var anchored := _authored_sector_share(loader, nation_ids)
	if not anchored.is_empty():
		world_sector_share = anchored

	var structure: Dictionary = _loader_tables(loader)["structure"]
	# Everything the loader alone determines, derived once for the whole tick
	# rather than once per nation -- the recipe table is static content and the
	# per-nation loop below must not re-derive it 29 times.
	var tables: Dictionary = _loader_tables(loader)
	var endowed: Dictionary = tables["endowed"]
	var natural: Dictionary = endowed.get("goods", {})

	# 1-3. Capacity, demand, production -- per nation.
	var produced := {}
	var made := {}
	var demanded := {}
	var capacities := {}
	var required := {}
	for nation_id in nation_ids:
		var ns = state.nations[nation_id]
		var capacity: Dictionary = {}
		var demand: Dictionary = {}
		for good_id in ids:
			var good: Dictionary = loader.commodity_goods[good_id]
			capacity[good_id] = _capacity_of(ns, good, structure, endowed)
			demand[good_id] = _want(ns, good, structure, world_sector_share, per_capita)
		capacities[nation_id] = capacity
		demanded[nation_id] = demand
		# What this nation's own industry processes of each natural good -- the
		# pre-V4.11 capacity. Routing fills the gap between it and the endowment.
		var need := {}
		for good_id in natural.keys():
			need[good_id] = _bucket(ns, loader.commodity_goods[good_id], structure) / float(loader.commodity_goods[good_id].base_price)
		required[nation_id] = need

	# V4.11b. NATURAL GOODS TRADE BEFORE ANYTHING IS MADE OF THEM. A nation's
	# recipes draw only on what it holds, so with real endowments Europe's steel,
	# fuels and electricity would stop the month its ore and crude became real --
	# routing raw and agri goods first (roster sellers, then the world pool) lets
	# imported ore become domestic steel. docs/commodities-model.md section 8.
	var traded := {}
	var spare_by_nation := {}
	for nation_id in nation_ids:
		traded[nation_id] = _zeros(loader)
		spare_by_nation[nation_id] = _zeros(loader)
	var pool_price: Dictionary = state.nations[nation_ids[0]].commodity_state["price"] if not nation_ids.is_empty() else {}
	for good_id in natural.keys():
		_route_natural(good_id, nation_ids, capacities, required, endowed, pool_price, loader, traded, spare_by_nation)

	for nation_id in nation_ids:
		var ns = state.nations[nation_id]
		var capacity: Dictionary = capacities[nation_id]
		# The recipes read POST-TRADE holdings of natural goods: what was mined
		# here plus what came in, less what went out.
		var holding: Dictionary = capacity.duplicate()
		for good_id in natural.keys():
			holding[good_id] = maxf(float(capacity[good_id]) + float(traded[nation_id][good_id]), 0.0)
		var out: Dictionary = _zeros(loader)
		var gross: Dictionary = _zeros(loader)
		# Last month's price vector, which is the one the nation's own register
		# carries -- every nation's copy is the same numbers, so the route a
		# nation picks cannot depend on which copy it read.
		_produce(tables, holding, ns.commodity_state["price"], out, gross)
		produced[nation_id] = out
		made[nation_id] = gross

	# 4. Trade, one good at a time: that good's surplus nations against its
	# deficit nations, both in SORTED id order. The alternative -- Dictionary
	# iteration order -- is the indeterminism the harness cannot see.
	for good_id in ids:
		# Natural goods were routed before production (V4.11b); routing them again
		# on post-production figures would trade the same ore twice.
		if natural.has(good_id):
			continue
		var offered := {}
		for nation_id in nation_ids:
			var spare := float(produced[nation_id][good_id]) - float(demanded[nation_id][good_id])
			if spare > 0.0:
				offered[nation_id] = spare * K.TRADE_RATE
				spare_by_nation[nation_id][good_id] = spare
		for buyer in nation_ids:
			var want := float(demanded[buyer][good_id]) - float(produced[buyer][good_id])
			if want <= 0.0:
				continue
			for seller in nation_ids:
				if want <= 0.0:
					break
				if not offered.has(seller):
					continue
				var moved: float = minf(want, float(offered[seller]))
				if moved <= 0.0:
					continue
				offered[seller] = float(offered[seller]) - moved
				want -= moved
				traded[seller][good_id] = float(traded[seller][good_id]) - moved
				traded[buyer][good_id] = float(traded[buyer][good_id]) + moved

	# 5. The world price from the world's own FLOW gap -- this month's demand
	# against this month's production, and deliberately not against a stock pile.
	# A carried stock makes the gap negative for ever once it has accumulated,
	# which drives every price to the same floor and reads as a glut the model did
	# not create (measured: the whole vector settles at 0.50x base with a
	# three-month cap). The flow is the honest signal: a good the world cannot make
	# this month is dear this month.
	#
	# Read on GROSS production -- every unit made, before the recipes downstream
	# took their inputs back out -- because the demand side already carries that
	# pull: `_structure()` weighs each good by its own use plus every recipe's
	# use of it, and capacity and demand both read that weight. Comparing it with
	# the NETTED `out` counted intermediate use twice, so every good that is some
	# recipe's input started short and rose until it hit the clamp (measured
	# 2026-10-14: 2 goods >= 1.25x base at month 1, 15 at month 3, cotton at
	# the 1.75x clamp; on gross production, 0 and 1). A real shortage still
	# shows: Leontief caps a good's gross output when its input runs out.
	#
	# Read on production and not on what each nation ended up holding, which is
	# what makes the step safe to run after trade: trade only moves units between
	# nations, so the world totals it compares are the same before and after and
	# the ordering cannot change the answer.
	var gaps := {}
	for good_id in ids:
		var want_total := 0.0
		var have_total := 0.0
		if natural.has(good_id):
			# The WORLD's gap for a natural good: every producer's endowment against
			# every buyer's want, the pool's included -- read before trade, which only
			# moves units between holders and cannot change the totals.
			want_total = _pool_want(endowed, good_id, pool_price, loader)
			have_total = float(endowed["pool_capacity"].get(good_id, 0.0))
			for nation_id in nation_ids:
				want_total += float(required[nation_id][good_id])
				have_total += float(capacities[nation_id][good_id])
			var g_natural := (want_total - have_total) / want_total if want_total > 0.0 else 0.0
			gaps[good_id] = clampf(g_natural, -1.0, 1.0)
			continue
		for nation_id in nation_ids:
			want_total += float(demanded[nation_id][good_id])
			have_total += float(made[nation_id][good_id])
		var gap := (want_total - have_total) / want_total if want_total > 0.0 else 0.0
		gaps[good_id] = clampf(gap, -1.0, 1.0)

	# 6. Write each nation's register: its own figures plus its copy of the ONE
	# world price vector (`commodity_state` is per-nation data, and a panel must
	# read a price without reaching into another nation's state).
	var month_index := int(state.year) * 12 + int(state.month)
	for nation_id in nation_ids:
		var ns = state.nations[nation_id]
		var price: Dictionary = ns.commodity_state["price"]
		# V4.11b. A natural good's `produced` is the POST-TRADE holding less this
		# nation's own use -- trade ran before production. Undo the trade so the
		# register means what it means for every other good: made here, net of own
		# use, before anything was bought or sold. Unclamped for value added (an
		# importer's consumed ore is an input it bought, and comes off), clamped at 0
		# for the `output` a panel prints as "units made". The first cut added back
		# exports only, so every imported unit was counted by both sides and the
		# panel showed imports as made and then again as bought (V4.11 review).
		var own: Dictionary = (produced[nation_id] as Dictionary).duplicate()
		for good_id in natural.keys():
			own[good_id] = float(own[good_id]) - float(traded[nation_id][good_id])
		var value_added := 0.0
		for good_id in ids:
			var base := _base(loader, good_id)
			var previous := float(price[good_id])
			var next: float = clampf(
				previous * (1.0 + K.PRICE_ELASTICITY * float(gaps[good_id])),
				base * (1.0 - K.PRICE_BAND), base * (1.0 + K.PRICE_BAND))
			# THE CROSSING STAMP: the one place both sides of the update are in
			# hand. Below the line before, at or above it after -- a good that
			# STAYS high does not re-stamp, which is the whole point (the
			# commodity_price_high hook is an edge; a level read fired every month).
			var line := base * K.HIGH_PRICE_RATIO
			if previous < line and next >= line:
				ns.commodity_high_month = month_index
			price[good_id] = next
			value_added += float(own[good_id]) * next
		for good_id in natural.keys():
			own[good_id] = maxf(float(own[good_id]), 0.0)
		ns.commodity_state["demand"] = demanded[nation_id]
		# `output` is what `_produce` left standing, which is NET of the inputs
		# this nation's own downstream recipes consumed -- and that is exactly what
		# makes the figure below value added rather than gross production: a tonne
		# of ore that went into this month's steel is not also counted as ore.
		ns.commodity_state["output"] = own
		ns.commodity_state["trade"] = traded[nation_id]
		ns.commodity_state["surplus"] = spare_by_nation[nation_id]
		ns.commodity_state["value_added_eur_bn"] = value_added / 1e9


## Production for one nation, in the recipe graph's own depth order so every input
## exists before the good that consumes it. A primary producer (no recipe) runs to
## CAPACITY -- not to demand, which is the correction measurement forced: capping
## every good at what its own nation wants leaves nobody with a surplus, so trade
## is identically zero and a world of balanced autarkies pins its prices to the
## ceiling. A nation produces what its endowment allows and sells the rest; that
## surplus IS the trade model.
##
## A manufactured good takes the CHEAPEST route at the live price, deterministic
## on recipe id, and is capped by its own capacity and by what its inputs support
## (Leontief: the first input to run out binds).
##
## Spending is recorded by DECREMENTING the input's own slot on `out`, so a later
## consumer of the same input reads the reduced figure with no second register to
## keep in step.
##
## `gross` takes every unit made BEFORE that decrement -- the price gap reads it
## (step 5), since demand already carries the downstream pull.
##
## Route choice is by cost and not by availability, a stated limitation rather
## than a claim: a nation with no coal takes the coal route and produces nothing
## where another route was affordable. Recorded as the first thing a later session
## should improve, because it is the one place this machine is less general than
## the content it reads.
##
## `tables` is the bundle from `_loader_tables()` and not the loader: the recipe
## table is static content, so the production order and the candidate-route lists
## are derived ONCE per loader rather than once per nation per month. The
## unhoisted form was a 60-round relaxation and a full recipe scan per good per
## nation -- 29 nations' worth of the same answer, every tick.
static func _produce(tables: Dictionary, capacity: Dictionary, price: Dictionary, out: Dictionary, gross: Dictionary) -> void:
	var routes: Dictionary = tables["routes"]
	for good_id in tables["order"]:
		var cap := maxf(float(capacity.get(good_id, 0.0)), 0.0)
		var route = _cheapest_route(tables, good_id, price)
		var target := cap
		if route != null:
			for input_id in route.inputs.keys():
				var per: float = float(route.inputs[input_id])
				if per <= 0.0:
					continue
				target = minf(target, maxf(float(out.get(String(input_id), 0.0)), 0.0) / per)
		if target <= 0.0:
			continue
		out[good_id] = float(out.get(good_id, 0.0)) + target
		gross[good_id] = float(gross.get(good_id, 0.0)) + target
		if route != null:
			for input_id in route.inputs.keys():
				out[String(input_id)] = float(out[String(input_id)]) - float(route.inputs[input_id]) * target


## Everything derived from the loader alone and needed every tick, built ONCE a
## month and handed down: the production order, the candidate routes per output,
## and the base prices the route cost falls back to.
##
## `routes` is the `_routes_for()` scan turned inside out -- one pass over the
## recipe ids keyed by output, rather than a full rescan for every good of every
## nation. The recipes inside each list keep `_recipe_ids()` order, so the
## tie-break in `_cheapest_route()` sees the same sequence it always did.
static func _static_tables(loader) -> Dictionary:
	var routes := {}
	for recipe_id in _recipe_ids(loader):
		var recipe = loader.commodity_recipes[recipe_id]
		var output := String(recipe.output)
		if not routes.has(output):
			routes[output] = []
		routes[output].append(recipe)
	return {
		"order": _production_order(loader),
		"routes": routes,
		"base": _base_prices(loader),
	}


## The one static in this file, and it is a MEMO rather than model state. Both
## halves it caches are pure functions of the loader's content -- `_structure()`
## is a 60-round relaxation and `_static_tables()` scans 24 recipes into 34
## routes -- and the loader fills those dictionaries once at startup and never
## mutates them, so re-deriving them every month is pure waste (the T2 hoist one
## level up: that one measured a per-tick 228 -> 44 ms; this is per-month ->
## per-loader). THE KEY IS THE LOADER INSTANCE, not its content: GDScript `!=` on
## a RefCounted is IDENTITY, so a second loader -- a different fixture, a second
## game in one process -- rebuilds, and the same one never does. Determinism
## holds by construction rather than by argument: the cached value IS what a
## fresh call returns, so a cached tick is bit-identical to an uncached one. The
## returned bundle is READ-ONLY to every caller (`_produce`/`_cheapest_route`
## only read it), which is what makes handing the same instance back safe.
static var _cache_loader = null
static var _cache_tables: Dictionary = {}

static func _loader_tables(loader) -> Dictionary:
	if _cache_loader != loader:
		_cache_loader = loader
		var tables: Dictionary = _static_tables(loader)
		tables["structure"] = _structure(loader)
		tables["endowed"] = _endowment_tables(loader, tables["structure"])
		_cache_tables = tables
	return _cache_tables


## The goods in an order that is genuinely topological for THIS recipe table:
## sorted by recipe depth, then by id so the order is total and stable. Depth is
## the length of the longest input chain ending at a good, so a good is always
## produced after everything it consumes.
##
## Computed rather than authored, because a hand-written list cannot stay correct
## as content grows -- the category list this file shipped first looked right and
## was wrong (`uranium_fuel` and `electricity` share the `energy` category), and
## a depth-first order is what makes that class impossible rather than noted. On
## this register it runs 6 deep at its longest chain (a capital good from an ore).
static func _production_order(loader) -> Array:
	var depth := {}
	for good_id in _goods(loader):
		depth[good_id] = 0
	# Relaxation to a fixed count: V(goods) rounds is enough for any chain the
	# register can express, and a bounded loop cannot spin on a recipe table that
	# somehow contained a cycle (it would settle at the highest reachable depth
	# instead of hanging, which is the failure mode a while-loop would have).
	for i in _goods(loader).size():
		for recipe_id in _recipe_ids(loader):
			var recipe = loader.commodity_recipes[recipe_id]
			var best := 0
			for input_id in recipe.inputs.keys():
				best = maxi(best, int(depth.get(String(input_id), 0)) + 1)
			var output := String(recipe.output)
			if int(depth.get(output, 0)) < best:
				depth[output] = best
	var out: Array = _goods(loader)
	out.sort_custom(func(a, b) -> bool:
		if int(depth[a]) != int(depth[b]):
			return int(depth[a]) < int(depth[b])
		return String(a) < String(b))
	return out


## The cheapest route for a good at the LIVE world price, or null for a primary
## producer (no recipe -- Task 1's rule: a raw, agri or services row would be a
## second way to declare the same output).
##
## Cost is the input VALUE per unit at the live price, tie-broken on recipe id so
## two equal-cost routes always resolve the same way -- the candidate list arrives
## already in `_recipe_ids()` order, so the first strict improvement wins. Live
## rather than base, so a route really is chosen on what its inputs cost this
## month: a shortage of crude oil is what should push refining toward the gas
## route. `labour_per_unit` and `capital_per_unit` are carried by the register and
## NOT read: this layer has no wage or capital price to value them against, and
## inventing one would be a second GDP lever the step-0 verdict refuses.
static func _cheapest_route(tables: Dictionary, good_id: String, price: Dictionary):
	var best = null
	var best_cost := 0.0
	for recipe in tables["routes"].get(good_id, []):
		var cost := 0.0
		for input_id in recipe.inputs.keys():
			var i_id := String(input_id)
			cost += float(recipe.inputs[input_id]) * float(price.get(i_id, float(tables["base"].get(i_id, 0.0))))
		if best == null or cost < best_cost - 1e-12:
			best = recipe
			best_cost = cost
	return best


## What one nation wants of one good this month: its share of the world's
## per-capita basket, a quantity taken at the good's BASE price and then answered
## by the LIVE price through the elasticity dial (K = 1.0 is a plain unit-elastic
## response). Dividing the basket by its base and not by the live price is what
## keeps the dial single-counted: the second term is the WHOLE price response, so
## `DEMAND_ELASTICITY` means what its comment promises. Without the second term
## demand is a constant and the only equilibrium a shortage has is the clamp.
##
## The basket is UNIFORM over the world's sector budgets through the recipe
## structure, so it is the same rule that sizes capacity and the two cannot drift
## apart for a reason no model states.
static func _want(ns, good: Dictionary, structure: Dictionary, world_sector_share: Dictionary, per_capita: float) -> float:
	var sector := String(CATEGORY_SECTOR.get(String(good.category), "industry"))
	var price := float(ns.commodity_state["price"].get(String(good.id), float(good.base_price)))
	var base := float(good.base_price)
	var value: float = per_capita * ns.population \
		* float(world_sector_share.get(sector, 0.0)) * float(structure.get(String(good.id), 0.0))
	var quantity := value / maxf(base, 1e-9)
	return quantity * pow(base / maxf(price, 1e-9), K.DEMAND_ELASTICITY)


## The one structure the whole file runs on: each good's value weight in the
## fixed point of `w_g = 1 + the input value one unit of w_g requires, summed
## over its routes`. Every route carries an equal share of its output's pull --
## this is content, not the tick, and assuming a nation prefers a route it has
## not priced yet would put a second rule inside the seeding.
##
## A FIXED iteration count, never a convergence test: the answer must not depend
## on a floating-point comparison, and K.STRUCTURE_ITERATIONS records the
## measured residual. The weights are then normalised WITHIN SECTOR, so a
## sector's goods split that sector's output among themselves and cannot claim
## another sector's.
static func _structure(loader) -> Dictionary:
	var ids: Array = _goods(loader)
	var weight := {}
	for good_id in ids:
		weight[good_id] = 1.0
	for i in K.STRUCTURE_ITERATIONS:
		var next := {}
		for good_id in ids:
			next[good_id] = 1.0
		for recipe_id in _recipe_ids(loader):
			var recipe = loader.commodity_recipes[recipe_id]
			var output := String(recipe.output)
			var share: float = float(weight[output]) / maxf(float(_routes_for(loader, output).size()), 1.0)
			for input_id in recipe.inputs.keys():
				var i_id := String(input_id)
				next[i_id] = float(next[i_id]) \
					+ float(recipe.inputs[input_id]) * (share / _base(loader, output)) * _base(loader, i_id)
		weight = next

	var total := {}
	for good_id in ids:
		var sector := _sector_of(loader, good_id)
		total[sector] = float(total.get(sector, 0.0)) + float(weight[good_id])
	var out := {}
	for good_id in ids:
		var sector := _sector_of(loader, good_id)
		out[good_id] = float(weight[good_id]) / maxf(float(total.get(sector, 0.0)), 1e-12)
	return out


## The share of one nation's own sector output a good's capacity is worth, in
## EUR per month. The ONLY per-nation input to the mix, and it is the register's
## measured figure -- this file's header says why nothing finer is authored.
static func _bucket(ns, good: Dictionary, structure: Dictionary) -> float:
	var sector := String(CATEGORY_SECTOR.get(String(good.category), "industry"))
	# NO FLOOR, deliberately: a nation with no industry makes no steel, and that
	# zero is the truth rather than a degenerate case to paper over. The first
	# draft floored this at 1e-9 to keep every column alive, which made a
	# collapsed endowment produce a nanogram of steel and report it as output --
	# a guard rail that hid the very state the shortage test exists to create.
	# The division below is safe: `_want` and the price step both guard their own
	# denominators, and every nation file carries all three sectors above zero.
	return _sector_value(ns, sector) * float(structure.get(String(good.id), 0.0))


static func _sector_of(loader, good_id: String) -> String:
	return String(CATEGORY_SECTOR.get(String(loader.commodity_goods[good_id].category), "industry"))


## The world's sector mix as authored: each nation's measured GDP times its
## measured sector shares, summed and normalised. Empty when any nation in play
## has no authored record, so the caller falls back to the live mix.
static func _authored_sector_share(loader, nation_ids: Array) -> Dictionary:
	var nations = loader.get("nations")
	if not (nations is Dictionary):
		return {}
	var weight := {}
	var total := 0.0
	for nation_id in nation_ids:
		if not nations.has(nation_id):
			return {}
		var n = nations[nation_id]
		var gdp := float(n.gdp_eur_bn)
		var sectors: Dictionary = n.sectors
		for sector in sectors.keys():
			var w := gdp * float(sectors[sector])
			weight[sector] = float(weight.get(sector, 0.0)) + w
			total += w
	if total <= 0.0:
		return {}
	for sector in weight.keys():
		weight[sector] = float(weight[sector]) / total
	return weight


static func _sector_value(ns, sector: String) -> float:
	return float(ns.sector_output.get(sector, 0.0)) * 1e9 / 12.0


static func _sectors(ns) -> Array:
	var out: Array = ns.sector_output.keys()
	out.sort()
	return out


static func _goods(loader) -> Array:
	var out: Array = loader.commodity_goods.keys()
	out.sort()
	return out


static func _recipe_ids(loader) -> Array:
	var out: Array = loader.commodity_recipes.keys()
	out.sort()
	return out


static func _routes_for(loader, output: String) -> Array:
	var out: Array = []
	for recipe_id in _recipe_ids(loader):
		if String(loader.commodity_recipes[recipe_id].output) == output:
			out.append(recipe_id)
	return out


static func _base(loader, good_id: String) -> float:
	return float(loader.commodity_goods[good_id].base_price)


static func _base_prices(loader) -> Dictionary:
	var out := {}
	for good_id in _goods(loader):
		out[good_id] = _base(loader, good_id)
	return out


static func _zeros(loader) -> Dictionary:
	var out := {}
	for good_id in _goods(loader):
		out[good_id] = 0.0
	return out


# --- V4.11b: real endowments and the world pool -----------------------------------
# docs/commodities-model.md section 8. Everything here is a pure function of the
# loader's content (authored nation figures, the outline register, the endowment
# shares), memoised with the recipe tables, so it adds no state and no save field.

## A good's capacity for one nation: its share of the WORLD's volume where the good
## is endowed, its sector output times the structure weight otherwise.
static func _capacity_of(ns, good: Dictionary, structure: Dictionary, endowed: Dictionary) -> float:
	var good_id := String(good.id)
	var natural: Dictionary = endowed.get("goods", {})
	if natural.has(good_id):
		return float(endowed["capacity"].get(String(ns.id), {}).get(good_id, 0.0))
	return _bucket(ns, good, structure) / float(good.base_price)


## {} when the loader carries no endowments (a fixture, or the pre-V4.11 model).
## Otherwise: "goods" (the endowed set), "capacity" {nation: {good: units/month}},
## "pool_capacity" and "pool_base_want" {good: units/month}.
##
## The WORLD VOLUME is the world's REQUIREMENT -- every roster nation's from its
## AUTHORED sector output through `_bucket`'s own formula (what its industry
## processes), every outline's from its own GDP through the world sector mix --
## so the world opens balanced and the shares only decide who makes it.
static func _endowment_tables(loader, structure: Dictionary) -> Dictionary:
	var shares = loader.get("commodity_endowments")
	if not (shares is Dictionary) or (shares as Dictionary).is_empty():
		return {}
	var nations: Dictionary = loader.nations
	var nation_ids: Array = nations.keys()
	nation_ids.sort()
	var wss := _authored_sector_share(loader, nation_ids)
	var outlines: Dictionary = loader.get("outlines") if loader.get("outlines") is Dictionary else {}
	var outline_value := 0.0
	for outline_id in outlines.keys():
		outline_value += maxf(float(outlines[outline_id]["gdp_eur_bn"]), 0.0) * 1e9 / 12.0

	var capacity := {}
	for nation_id in nation_ids:
		capacity[nation_id] = {}
	var pool_capacity := {}
	var pool_base_want := {}
	var endowed_goods := {}
	for good_id in (shares as Dictionary).keys():
		if not loader.commodity_goods.has(good_id):
			continue
		var good: Dictionary = loader.commodity_goods[good_id]
		var sector := String(CATEGORY_SECTOR.get(String(good.category), "industry"))
		var weight := float(structure.get(good_id, 0.0)) / float(good.base_price)
		var roster_need := 0.0
		for nation_id in nation_ids:
			var n = nations[nation_id]
			roster_need += float(n.gdp_eur_bn) * 1e9 / 12.0 * float(n.sectors.get(sector, 0.0)) * weight
		var outline_want := outline_value * float(wss.get(sector, 0.0)) * weight
		var world := roster_need + outline_want
		var good_shares: Dictionary = shares[good_id]
		var pool_share := 0.0
		for producer in good_shares.keys():
			var s := float(good_shares[producer])
			if nations.has(producer):
				capacity[producer][good_id] = s * world
			else:
				pool_share += s
		pool_capacity[good_id] = pool_share * world
		pool_base_want[good_id] = outline_want
		endowed_goods[good_id] = true
	return {
		"goods": endowed_goods,
		"capacity": capacity,
		"pool_capacity": pool_capacity,
		"pool_base_want": pool_base_want,
	}


## The world pool's requirement for a good at this month's price, with `_want`'s
## own price response -- the outlines buy less of what grew dear.
static func _pool_want(endowed: Dictionary, good_id: String, price: Dictionary, loader) -> float:
	var base := float(loader.commodity_goods[good_id].base_price)
	var p := float(price.get(good_id, base))
	return float(endowed["pool_base_want"].get(good_id, 0.0)) * pow(base / maxf(p, 1e-9), K.DEMAND_ELASTICITY)


## One natural good across the roster and the pool. Roster sellers offer their
## spare at TRADE_RATE to roster buyers first, in sorted id order; the pool then
## SELLS its whole net surplus to whoever is still short, or BUYS what roster
## sellers still offer up to its net shortfall. The pool trades its full net
## position because it is the rest of the world clearing against Europe, not one
## nation keeping a month's buffer (K.POOL_OFFER_RATE, argued at the constant).
static func _route_natural(good_id: String, nation_ids: Array, capacities: Dictionary, required: Dictionary,
		endowed: Dictionary, price: Dictionary, loader, traded: Dictionary, spare_by_nation: Dictionary) -> void:
	var offered := {}
	for nation_id in nation_ids:
		var spare := float(capacities[nation_id][good_id]) - float(required[nation_id][good_id])
		if spare > 0.0:
			offered[nation_id] = spare * K.TRADE_RATE
			spare_by_nation[nation_id][good_id] = spare
	var pool_net := float(endowed["pool_capacity"].get(good_id, 0.0)) - _pool_want(endowed, good_id, price, loader)
	var pool_offer := maxf(pool_net, 0.0) * K.POOL_OFFER_RATE
	var pool_need := maxf(-pool_net, 0.0) * K.POOL_OFFER_RATE
	for buyer in nation_ids:
		var want := float(required[buyer][good_id]) - float(capacities[buyer][good_id])
		if want <= 0.0:
			continue
		for seller in nation_ids:
			if want <= 0.0:
				break
			if not offered.has(seller):
				continue
			var moved: float = minf(want, float(offered[seller]))
			if moved <= 0.0:
				continue
			offered[seller] = float(offered[seller]) - moved
			want -= moved
			traded[seller][good_id] = float(traded[seller][good_id]) - moved
			traded[buyer][good_id] = float(traded[buyer][good_id]) + moved
		if want > 0.0 and pool_offer > 0.0:
			var from_pool: float = minf(want, pool_offer)
			pool_offer -= from_pool
			traded[buyer][good_id] = float(traded[buyer][good_id]) + from_pool
	for seller in nation_ids:
		if pool_need <= 0.0:
			break
		if not offered.has(seller):
			continue
		var sold: float = minf(pool_need, float(offered[seller]))
		if sold <= 0.0:
			continue
		offered[seller] = float(offered[seller]) - sold
		pool_need -= sold
		traded[seller][good_id] = float(traded[seller][good_id]) - sold
