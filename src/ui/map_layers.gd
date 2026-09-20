extends RefCounted

## What colour a nation is on the map, and why -- U5c. The one place a roster
## fill is chosen; map_view.gd's _draw_roster() asks this and indexes nothing
## itself.
##
## **A registry, not a mode flag.** LAYERS below is the whole surface: adding
## V1.3c's sanctions layer is one entry here plus one branch in _value() and
## _ramp(), and touches map_view.gd, map_legend.gd and main.gd not at all. That
## is this file's contract and the reason U5c could run before V1.3c at all --
## ROADMAP's U5c row deferred the layer system partly so one session could colour
## tariffs too, and a registry is what buys that back.
##
## Stateless and pure: every function is a read over GameState, the same shape
## src/sim/trade.gd takes. The active layer id lives on map_view.gd, because that
## is the control the player is looking at.

const Trade = preload("res://src/sim/trade.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const Relations = preload("res://src/core/relations.gd")

const POLITICAL := "political"
const RELATIONS := "relations"
const TRADE := "trade"
const COERCION := "coercion"
const PRODUCTION := "production"
const IMPORT_DEPENDENCY := "import_dependency"

## The commodity layers' reader -- V4.6 Task 4. The register itself is read off
## GameState, so this file stays the stateless read trade.gd's header promises;
## the preload exists only so the two quantities below are expressed ONCE.
const CommoditiesK = preload("res://src/sim/commodity_constants.gd")

## The relations ramp's domain, and why it is not 0-100.
##
## diplomacy_constants.gd runs the scale 0-100, but the reachable game is narrow
## and measured: docs/diplomacy-model.md's four resting tiers are 45, 53, 60 and
## 68, and the strongest positive verb reaches about 76 under sustained spam. A
## ramp stretched over the nominal range would put all forty-five pairs inside
## its middle third and read as one colour on the map. 60 is the midpoint AND a
## real tier (bloc, no border), so the diverging neutral lands on something.
##
## The warm end is 72, not 80, and that was the first frame's correction. At 80,
## the top resting tier -- 68, bloc *and* border, twelve of the forty-five pairs
## -- landed only 40 % along the warm half and came out a wash barely separable
## from the neutral at 60. Resolution belongs in 45-68, where the game actually
## sits, rather than in headroom a player reaches only under sustained spam. A
## pair driven past 72 saturates, which _fraction() clamps and
## tests/test_map_layers.gd asserts is deliberate.
const RELATIONS_MIN_SHOWN := 40.0
const RELATIONS_MID_SHOWN := 60.0
const RELATIONS_MAX_SHOWN := 72.0

## A weight vector is normalised over the viewer's partners, so the honest
## reference is not zero but an even SHARE -- and which share is even depends on
## the partner count, which is why V3.3 retired the literal 1/9 this ramp was
## anchored on: at twenty-nine nations it drew four times a partner's fair
## share as "even". trade_even_share() derives it; "dominant" stays three times
## that, which is what TRADE_MAX_SHOWN's 0.33 always was against 1/9.

## The coercion ramp's domain: total severity on the pair, both directions summed.
##
## SUMMED RATHER THAN NETTED, and that is this layer's one real call. A signed
## net -- what you impose minus what is imposed on you -- reads a mutual embargo
## as zero, which is the single worst thing this map could say. Summing is also
## what makes the colour the quantity the MODEL actually uses:
## Coercion.severity_on_pair() is what cuts the trade weight, and the map draws it
## rather than a second number of the UI's own. Direction is not lost, it moves to
## the hover readout, where it can be stated exactly instead of encoded in a hue.
##
## The stops are the shipped content read back: one tariff is 0.625, its
## retaliation 0.375, so a tariff answered is 1.0 -- the value a player in an
## ordinary trade fight will actually see. 2.0 is both sides at full embargo and
## is the ceiling, since one measure per directed pair is the register's rule.
const COERCION_MAX_SHOWN := 2.0

## The production layer's domain: a nation's share of the world's commodity value
## added this month.
##
## Measured before it was typed (tools/ probe over 240 months of the live tick, all
## 29 nations): the share runs 0.0 to **0.1909**, with DEU the maximum and the
## world's even share at 1/29 = 0.0345. The stops break AT the even share rather
## than at the domain's midpoint for the trade ramp's own reason -- 0.0345 is the
## one value on this scale that means something a player can name ("an even
## slice"), and stretching the scale so it landed mid-ramp would put twenty-four
## of the twenty-nine inside one colour.
##
## 0.0 is a REACHABLE value and a real datum, not the viewer's absence: a nation
## with no output at all -- the collapsed-endowment state test_commodities.gd
## creates -- reads the bottom of the ramp. That is why the two commodity layers
## are the first on this map where the viewer's OWN nation carries a value.
const PRODUCTION_MAX_SHOWN := 0.20

## The import-dependency layer's domain: the value of what a nation buys from
## abroad over the value of everything it wants, both at the live price.
##
## Measured the same way: 0.0 to **0.5854**, and the distribution is the finding
## -- a dozen of the twenty-nine sit at literally 0.000 and the rest run 0.24 to
## 0.59. So the ramp's resolution belongs in the upper half and the bottom is
## genuinely flat, which is the honest shape rather than a stub: a nation that
## makes what it wants trades nothing and has no dependency to draw. 0.60 is just
## past the measured maximum so the worst case saturates at the top rather than
## hanging off the end (_fraction clamps).
const IMPORT_MAX_SHOWN := 0.60

## Where the import ramp breaks, and the measurement is the reason rather than the
## midpoint: a quarter is where the dependent nations actually begin (0.24 is the
## lowest non-zero share measured), so the break lands on the boundary the data has
## instead of in the middle of a cluster.
##
## A QUARTER AS AN ABSOLUTE SHARE, not a fraction of a per-nation anchor, and that
## is the one place this pair does NOT copy the trade layer: a trade weight is
## normalised over the viewer's partners, whereas "how much of what I want do I buy
## in" is already a share of a whole and means the same thing for every nation. An
## anchor would be a second normalisation of a quantity that has one.
const IMPORT_MID_SHOWN := 0.25

## The layers, in switcher order.
##
## **`alpha` is per-layer, and the political layer's 0.20 is deliberately not
## inherited.** U5b lowered it from 0.42 after looking at a frame: PALETTE is
## desaturated navy, so at 0.42 it behaved as a grey wash and the ten playable
## nations came out the flattest things on screen while Poland and Ireland kept
## the satellite's colour -- the exact inverse of what the tint is for. What
## separates the roster on that layer is its *outline*, not its fill.
##
## That finding is about a ramp with no hue variation, and it does not transfer.
## A saturated diverging ramp does not go grey when it is turned up, and the
## failure mode inverts: the roster becomes the most-coloured thing on screen,
## which on a data layer is correct. So the data layers carry their own 0.50 --
## a number set by looking at a frame, the same way 0.20 was, and the only one in
## this file that a screenshot rather than an argument decides.
##
## `stops` are the legend's rows, in ramp order: the value, and what that value
## means in words. They are values rather than colours so the legend swatch and
## the map fill go through the same ramp() and cannot drift apart.
const LAYERS: Array[Dictionary] = [
	{
		"id": POLITICAL,
		"label": "Political",
		"alpha": 0.20,
		"stops": [],
		"caption": "Every nation the game simulates, in its own colour.",
	},
	{
		"id": RELATIONS,
		"label": "Relations",
		"alpha": 0.50,
		"stops": [
			{"at": 45.0, "text": "45  no ties"},
			{"at": 53.0, "text": "53  border only"},
			{"at": 60.0, "text": "60  bloc only"},
			{"at": 68.0, "text": "68  bloc and border"},
		],
		"caption": "Your pair score with each nation.",
	},
	{
		"id": TRADE,
		"label": "Trade",
		"alpha": 0.50,
		# The trade stops are DERIVED -- trade_stops(even) -- because their scale
		# is the viewer's own partner count. map_legend.gd branches to it; keeping
		# literals here is how the legend ended up promising "an even ninth" on a
		# twenty-eight-partner roster.
		"stops": [],
		"caption": "Share of your external demand. Arcs show direction; convoys ride the roads when you zoom in.",
	},
	{
		"id": COERCION,
		"label": "Coercion",
		"alpha": 0.50,
		"stops": [
			{"at": 0.0, "text": "—  nothing in force"},
			{"at": 0.625, "text": "0.6  tariffs one way"},
			{"at": 1.0, "text": "1.0  tariffs answered"},
			{"at": 2.0, "text": "2.0  mutual embargo"},
		],
		"caption": "Tariffs and sanctions on the pair, both ways.",
	},
	{
		"id": PRODUCTION,
		"label": "Production",
		"alpha": 0.50,
		# Signed at zero, because a nation with no output at all reads 0.0 and its
		# cheap fill is the ramp's own low end -- unlike the pair layers, an entry
		# here is a real datum and not the viewer's absence.
		"stops": [
			{"at": 0.0, "text": "0.0  nothing made"},
			{"at": PRODUCTION_MAX_SHOWN, "text": "%.2f  industrial core" % PRODUCTION_MAX_SHOWN},
		],
		# The production stops are DERIVED too -- production_stops(even) -- and for
		# the trade layer's exact reason: the break on this ramp is the world's
		# even share, which is the roster's own size and not a constant, and
		# keeping a literal here is how the trade legend ended up promising "an
		# even ninth" on a twenty-eight-partner roster. map_legend.gd branches to
		# it the same way.
		"caption": "Share of the world's commodity value added, this month.",
	},
	{
		"id": IMPORT_DEPENDENCY,
		"label": "Import dep.",
		"alpha": 0.50,
		"stops": [
			{"at": 0.0, "text": "0%%  self-sufficient"},
			{"at": 0.25, "text": "25%%  a quarter bought in"},
			{"at": IMPORT_MAX_SHOWN, "text": "%d%%  dependent" % roundi(100.0 * IMPORT_MAX_SHOWN)},
		],
		"caption": "Share of what a nation wants that it buys from abroad.",
	},
]

# -- Ramps ----------------------------------------------------------------------

## Relations: diverging, red through a pale neutral to teal. Red-to-teal rather
## than the GOOD/BAD red-to-green the theme already owns, because those two are
## the game's semantic pair for a *delta* and this is a level, and because
## red-green is the one diverging ramp a colour-blind player cannot read.
const REL_COLD := Color(0.851, 0.267, 0.298)
const REL_NEUTRAL := Color(0.847, 0.827, 0.729)
const REL_WARM := Color(0.196, 0.722, 0.678)

## Trade: sequential along the brass axis, dark to pale gold. Quantity, so one
## hue rather than two directions -- the same reasoning ui_theme.gd's ProgressBar
## fill uses for a share-of-a-whole bar. Distinct enough from the relations ramp
## that a player who has forgotten which layer is up can tell from the map alone.
const TRADE_LOW := Color(0.180, 0.196, 0.310)
const TRADE_MID := Color(0.788, 0.635, 0.153)
const TRADE_HIGH := Color(0.976, 0.898, 0.639)

## Coercion: sequential, from the map's own navy up through ember to a hot red.
## Sequential rather than diverging because the datum is a magnitude with no
## natural middle -- zero is not a neutral between two opposites, it is simply
## nothing in force, and the low end is pulled toward NO_VALUE so a quiet Europe
## reads as quiet rather than as a colour choice.
##
## Red, and deliberately the only place on this map that uses it as a LEVEL. The
## relations ramp's cold end is also red, but the two layers are never up at once
## and a player looking at a red continent should be in no doubt something is
## wrong -- which on this layer is exactly what the colour means.
const COERCE_NONE := Color(0.129, 0.196, 0.310)
const COERCE_MID := Color(0.706, 0.325, 0.180)
const COERCE_HIGH := Color(0.918, 0.243, 0.208)

## Production: sequential, and deliberately the TEAL axis the relations ramp's warm
## end already uses, because it answers the inverse question about the same kind of
## quantity -- the relations layer's warm end is "close to you", and here warm is
## "makes a lot". Two layers with a shared vocabulary for intensity is the grammar
## this map already has; a third unrelated axis would be a colour nobody can place.
##
## PROD_LOW IS NOT NO_VALUE, and the first draft had it byte-identical -- caught by
## this task's own test, which asserts a data layer's fill cannot be NO_VALUE. The
## reasoning is the same one that made NO_VALUE a colour on neither ramp: a nation
## that made nothing this month is a DATUM (the collapsed-endowment state), not an
## absence, and if the empty end of the ramp IS the no-data colour then the map
## cannot say which of the two it is drawing. So the low end is pulled toward the
## teal it interpolates to rather than reusing the navy NO_VALUE owns.
const PROD_LOW := Color(0.075, 0.157, 0.196)
const PROD_MID := Color(0.196, 0.722, 0.678)
const PROD_HIGH := Color(0.694, 0.949, 0.925)

## Import dependency: sequential along the ember-to-red axis, which on this map
## already means "something is wrong" (the coercion ramp) -- and a dependency is
## the commodity layer's version of that. Distinct from production's teal, so a
## player who has forgotten which of the two is up can still tell from the map.
##
## DEP_LOW carries PROD_LOW's lesson in the other direction: it interpolates from
## the theme's SLATE toward brass rather than from NO_VALUE's navy, so the two
## "empty" ends of the two commodity ramps are distinct colours as well as distinct
## from the no-data colour.
const DEP_LOW := Color(0.231, 0.243, 0.337)
const DEP_MID := Color(0.788, 0.635, 0.153)
const DEP_HIGH := Color(0.918, 0.243, 0.208)

## Ten land tones for the political layer, cycled by hash so neighbours rarely
## collide. Moved here from map_view.gd at U5c with its argument intact.
##
## Desaturated and pulled toward the theme's navy at U5a: U2 chose these to be
## distinguishable inside a tab, which is a different problem from sitting under a
## whole interface all game. Saturated pink and olive against a brass-on-navy HUD
## read as two designs on one screen.
const PALETTE: Array[Color] = [
	Color(0.28, 0.34, 0.40), Color(0.24, 0.32, 0.42), Color(0.31, 0.36, 0.36),
	Color(0.26, 0.30, 0.38), Color(0.33, 0.35, 0.41), Color(0.22, 0.30, 0.36),
	Color(0.30, 0.33, 0.44), Color(0.35, 0.38, 0.39), Color(0.25, 0.34, 0.38),
	Color(0.32, 0.31, 0.37),
]

## What a nation with no value on this layer is drawn as: the viewer's own
## nation, which has no pair with itself and no self-weight. Deliberately a
## colour that is on neither ramp, so "you" can never be misread as a datum --
## inventing a self-value would be the only lie on the map.
const NO_VALUE := Color(0.106, 0.173, 0.290)

# -- The public surface ---------------------------------------------------------


## Every layer id, in switcher order. map_legend.gd builds its toggles from this
## and from nothing else, which is what makes "adding a layer adds a toggle"
## true rather than a convention.
static func ids() -> Array:
	var out: Array = []
	for entry in LAYERS:
		out.append(String(entry["id"]))
	return out


## An unknown id resolves to the political layer rather than erroring. A layer
## is a view, and a saved-off or mistyped one should show the map the game opens
## on -- not a black continent and not a crash mid-draw.
static func layer(layer_id: String) -> Dictionary:
	for entry in LAYERS:
		if entry["id"] == layer_id:
			return entry
	return LAYERS[0]


static func alpha(layer_id: String) -> float:
	return float(layer(layer_id)["alpha"])


static func label(layer_id: String) -> String:
	return String(layer(layer_id)["label"])


static func caption(layer_id: String) -> String:
	return String(layer(layer_id)["caption"])


static func stops(layer_id: String) -> Array:
	return layer(layer_id)["stops"]


## True when this nation is the one doing the viewing, and so has no value on any
## data layer. Its own function rather than an `== ` at three call sites because
## map_view.gd draws it differently as well as filling it differently.
static func is_viewer(viewer_id: String, nation_id: String) -> bool:
	return viewer_id == nation_id


## The fill, alpha already applied. The one function _draw_roster() calls.
static func color_for(layer_id: String, state, viewer_id: String, nation_id: String) -> Color:
	var color := swatch(layer_id, state, viewer_id, nation_id)
	color.a = alpha(layer_id)
	return color


## Every roster fill for one layer, derived in one pass. _draw_roster() calls
## this instead of color_for() per nation, and the reason is a measurement
## rather than tidiness.
##
## swatch() on the TRADE layer reads the viewer's partner vector TWICE per
## nation -- once through value() for the share, once through
## trade_even_share() for the anchor it is measured against -- and
## Trade.weights() builds that whole vector from scratch each time, walking
## every partner through a gravity term, shared_bonus() over live org
## membership, relations, agreements and measures. At twenty-nine nations that
## is FIFTY-EIGHT full vector builds to fill one roster, for a quantity that is
## the same vector all fifty-eight times. Derived once here, it is one.
##
## Why this was invisible until V3.4: the map re-records on hover, pan, zoom and
## the monthly tick, so the cost landed inside the run-to-run spread of an
## event-driven redraw. A drag re-records EVERY FRAME, and at that rate the
## trade layer measured ~14-17 ms per re-record above the political one, which
## pays nothing here at all (a political fill is a hash of the nation id).
##
## Still stateless and still pure -- nothing is cached in this file. The caller
## owns when a fill is derived exactly as it owned when color_for() was called,
## so a fill can no more go stale than it could before.
static func fills(layer_id: String, state, viewer_id: String, nation_ids: Array) -> Dictionary:
	var out: Dictionary = {}

	# Every other layer reads a per-PAIR datum -- a relations score, a severity
	# on the pair -- so there is nothing shared across nations to hoist, and
	# going through color_for() keeps one definition of what a fill is rather
	# than a second copy of swatch()'s branches that could drift from it.
	# state == null takes this path too: value() answers NAN there and swatch()
	# returns NO_VALUE, which is reached without building any vector.
	if layer_id != TRADE and layer_id != PRODUCTION or state == null:
		for id in nation_ids:
			var nation_id := String(id)
			out[nation_id] = color_for(layer_id, state, viewer_id, nation_id)
		return out

	# The production layer has the trade layer's shape and not its scale: its
	# anchor is the roster's size, which is one number, but `production_share()`
	# sums every nation's value added and swatch() would call it once per nation --
	# twenty-nine walks of the same twenty-nine figures, on a layer the player pans
	# across. One world total hoisted here is one walk. (The trade vector below is
	# the same defect at fifty-eight builds, and V3.4 measured it at 14-17 ms per
	# drag frame.)
	if layer_id == PRODUCTION:
		var world := 0.0
		for id in nation_ids:
			world += float(_value_added(state.nations[id]))
		var even := 1.0 / float(maxi(1, state.nations.size()))
		var prod_alpha := alpha(PRODUCTION)
		for id in nation_ids:
			var nation_id := String(id)
			var share := float(_value_added(state.nations[nation_id])) / world if world > 0.0 else 0.0
			var color := ramp_production(share, even)
			color.a = prod_alpha
			out[nation_id] = color
		return out

	# The one vector. value() reads exactly this dictionary and
	# trade_even_share() exactly this size, so the colour below is the colour
	# swatch() would have returned -- tests/test_map_layers.gd pins that
	# equality rather than trusting this comment.
	var weights: Dictionary = Trade.weights(state, viewer_id)
	var even := 1.0 / float(maxi(1, weights.size()))
	var trade_alpha := alpha(TRADE)
	for id in nation_ids:
		var nation_id := String(id)
		var color: Color
		if is_viewer(viewer_id, nation_id):
			color = NO_VALUE
		else:
			# get(..., 0.0) is value()'s own default: a roster nation absent from
			# the vector trades nothing with the viewer, which is a real zero on
			# this ramp and not a missing datum.
			color = ramp_trade(float(weights.get(nation_id, 0.0)), even)
		color.a = trade_alpha
		out[nation_id] = color
	return out


## The same colour at full opacity -- what a legend swatch and a test compare.
## Split from color_for() so a stop's swatch is provably the colour the map draws
## rather than a second table someone has to keep in step.
static func swatch(layer_id: String, state, viewer_id: String, nation_id: String) -> Color:
	if layer_id == POLITICAL:
		return PALETTE[hash(nation_id) % PALETTE.size()]
	# NO_VALUE is the answer for the viewer's own nation on the PAIR layers only --
	# a nation has no pair with itself. On the two commodity layers "you" is a real
	# reading and falls through to the ramp.
	if is_viewer(viewer_id, nation_id) and layer_id in [RELATIONS, TRADE, COERCION]:
		return NO_VALUE
	var v := value(layer_id, state, viewer_id, nation_id)
	if is_nan(v):
		return NO_VALUE
	if layer_id == TRADE:
		return ramp_trade(v, trade_even_share(state, viewer_id))
	if layer_id == PRODUCTION:
		return ramp_production(v, production_even_share(state))
	return ramp(layer_id, v)


## The production ramp's anchor: one over the roster's size, the share a nation
## would hold if the world's commodity output were spread evenly. Derived rather
## than typed, exactly as trade_even_share() is and for the same reason -- the
## roster grew 10 -> 27 -> 29 and a literal baked into the ramp or the legend
## would have gone stale silently, which is the V3.3 trade-legend defect.
static func production_even_share(state) -> float:
	if state == null:
		return 0.0
	return 1.0 / float(maxi(1, state.nations.size()))


## The production legend's stops, derived beside the ramp so the words cannot
## promise a scale the colours do not use -- trade_stops()'s rule, one layer over.
static func production_stops(even: float) -> Array:
	return [
		{"at": 0.0, "text": "0.0  nothing made"},
		{"at": even, "text": "%.3f  an even share" % even},
		{"at": PRODUCTION_MAX_SHOWN, "text": "%.2f  industrial core" % PRODUCTION_MAX_SHOWN},
	]


## The trade ramp's anchor: one over the viewer's partner count, the share a
## weight would carry if the viewer's demand were spread evenly -- the same
## derivation foreign_policy.even_share() makes for the sim's thresholds, and
## for the same reason. "Dominant" stays three times it.
static func trade_even_share(state, viewer_id: String) -> float:
	var count := Trade.weights(state, viewer_id).size()
	return 1.0 / float(maxi(1, count))


static func ramp_trade(v: float, even: float) -> Color:
	if v <= even:
		return TRADE_LOW.lerp(TRADE_MID, _fraction(v, 0.0, even))
	return TRADE_MID.lerp(TRADE_HIGH, _fraction(v, even, 3.0 * even))


## The trade legend's stops, derived beside the ramp so the words cannot promise
## a scale the colours do not use.
static func trade_stops(even: float) -> Array:
	return [
		{"at": even / 3.0, "text": "%d%%  marginal" % roundi(100.0 * even / 3.0)},
		{"at": even, "text": "%d%%  an even share" % roundi(100.0 * even)},
		{"at": 3.0 * even, "text": "%d%%  dominant" % roundi(300.0 * even)},
	]


## The ramp alone, over a raw value. Public so map_legend.gd can colour a stop
## that belongs to no nation.
static func ramp(layer_id: String, v: float) -> Color:
	match layer_id:
		RELATIONS:
			if v <= RELATIONS_MID_SHOWN:
				return REL_COLD.lerp(REL_NEUTRAL, _fraction(
					v, RELATIONS_MIN_SHOWN, RELATIONS_MID_SHOWN))
			return REL_NEUTRAL.lerp(REL_WARM, _fraction(
				v, RELATIONS_MID_SHOWN, RELATIONS_MAX_SHOWN))
		COERCION:
			# Broken at 1.0 -- a tariff answered -- rather than at the domain's
			# midpoint, so the ordinary trade fight sits at the top of the first
			# half and the whole second half is reserved for escalation past it.
			if v <= 1.0:
				return COERCE_NONE.lerp(COERCE_MID, _fraction(v, 0.0, 1.0))
			return COERCE_MID.lerp(COERCE_HIGH, _fraction(v, 1.0, COERCION_MAX_SHOWN))
		PRODUCTION:
			# NO_VALUE, deliberately, where the other ramps return a colour. This
			# layer's break is the ROSTER'S OWN SIZE and an anchor cannot be
			# invented here without going stale the way the trade legend's "even
			# ninth" did. Every caller that has a GameState -- swatch(), fills(),
			# map_legend.gd's stops -- goes through ramp_production() with the
			# derived anchor; this function, which has no state, says so rather
			# than guessing one.
			return NO_VALUE
		IMPORT_DEPENDENCY:
			# Broken at a QUARTER rather than the domain's midpoint, and the
			# measurement is why: a dozen of the twenty-nine sit at literally 0.000
			# and the rest run 0.24 to 0.59, so the resolution belongs in the upper
			# half. Splitting at 0.30 would put two thirds of the dependent nations
			# in one colour.
			if v <= IMPORT_MID_SHOWN:
				return DEP_LOW.lerp(DEP_MID, _fraction(v, 0.0, IMPORT_MID_SHOWN))
			return DEP_MID.lerp(DEP_HIGH, _fraction(v, IMPORT_MID_SHOWN, IMPORT_MAX_SHOWN))
	return NO_VALUE


## The production ramp alone, over its derived anchor. Public for production_stops()'s
## own reason: map_legend.gd colours a stop that belongs to no nation.
##
## `even` is passed rather than read, the same split ramp_trade() makes -- ramp()
## has no GameState and must not pretend to.
static func ramp_production(v: float, even: float) -> Color:
	if even <= 0.0 or even >= PRODUCTION_MAX_SHOWN:
		return PROD_MID
	if v <= even:
		return PROD_LOW.lerp(PROD_MID, _fraction(v, 0.0, even))
	return PROD_MID.lerp(PROD_HIGH, _fraction(v, even, PRODUCTION_MAX_SHOWN))


## The raw datum, or NAN where there is none. NAN rather than 0.0 for the same
## reason Diplomacy.score() refuses to default: on the relations layer 0.0 is the
## worst possible score, not the absence of one.
static func value(layer_id: String, state, viewer_id: String, nation_id: String) -> float:
	if state == null:
		return NAN
	# The two commodity layers are the FIRST on this map where the viewer's own
	# nation carries a value, so the self-check that used to head this function is
	# per-layer now. Production and import dependency are properties of a nation
	# and not of a pair: "you" is a real reading on both, which is also why
	# swatch() does not send them to NO_VALUE.
	if is_viewer(viewer_id, nation_id) and layer_id in [RELATIONS, TRADE, COERCION]:
		return NAN
	match layer_id:
		RELATIONS:
			return Diplomacy.score(state, viewer_id, nation_id)
		TRADE:
			return float(Trade.weights(state, viewer_id).get(nation_id, 0.0))
		COERCION:
			# 0.0 rather than NAN for a clean pair: "nothing in force" is a real
			# reading and belongs on the ramp, unlike the viewer's own nation, which
			# has no pair with itself and is caught above.
			return Coercion.severity_on_pair(state, viewer_id, nation_id)
		PRODUCTION:
			return production_share(state, nation_id)
		IMPORT_DEPENDENCY:
			return import_dependency(state, nation_id)
	return NAN


## A nation's share of the world's commodity value added this month. THE
## DENOMINATOR IS THE WORLD'S OWN SUM, not a stored total: `commodity_state` is
## per-nation data and nothing keeps a world aggregate (commodities.gd's step 5
## sums one transiently and writes it nowhere), so deriving it here is the only
## shape available -- and the right one, since a stored total would be a second
## record that could disagree with the parts it is the sum of.
##
## An empty register reads 0.0 rather than NAN, and that is a real datum for the
## same reason value() gives COERCION zero: a nation that made nothing this month
## has a genuine zero share, and it is the state a collapsed endowment produces.
static func production_share(state, nation_id: String) -> float:
	var world := 0.0
	for id in state.nations.keys():
		world += float(_value_added(state.nations[id]))
	if world <= 0.0:
		return 0.0
	return float(_value_added(state.nations[nation_id])) / world


## The value of what a nation buys from abroad over the value of everything it
## wants, both at the live price. VALUE rather than a unit count, and that is a
## measurement's call: a tonne of ore and a tonne of semiconductors are not
## comparable quantities, and an unweighted count of units would report a nation
## that imports only cheap ore perfectly as dependent as one that imports only
## aircraft. The live price is what makes the two commensurable.
##
## Defined on what the nation BOUGHT (the positive half of `trade`) rather than on
## what it wants and did not make, so the figure answers the question the layer's
## name asks: what actually crossed a border to get here. `maxf(0.0, ...)` because
## `trade` is signed -- a negative entry is a sale and belongs on the export side
## of the panel, not in a dependency reading.
static func import_dependency(state, nation_id: String) -> float:
	var cs: Dictionary = state.nations[nation_id].commodity_state
	if cs.is_empty():
		return 0.0
	var want := 0.0
	var bought := 0.0
	for good_id in (cs["demand"] as Dictionary).keys():
		var price := float(cs["price"].get(String(good_id), 0.0))
		want += float(cs["demand"][good_id]) * price
		bought += maxf(0.0, float(cs["trade"].get(String(good_id), 0.0))) * price
	if want <= 0.0:
		return 0.0
	return clampf(bought / want, 0.0, 1.0)


static func _value_added(ns) -> float:
	var cs: Dictionary = ns.commodity_state
	return float(cs["value_added_eur_bn"]) if cs.has("value_added_eur_bn") else 0.0


## One line naming the hovered nation's value, for the legend's readout.
##
## The relations line is written as a PAIR and the trade line is not, and that is
## the whole of the symmetric-vs-directed asymmetry as the player meets it:
## "FRA-DEU 68" is true read from either side, whereas a trade share belongs to
## the viewer alone and claiming DEU's side would need a second number this
## layer does not show.
static func value_text(layer_id: String, state, viewer_id: String, nation_id: String) -> String:
	if is_viewer(viewer_id, nation_id) and layer_id in [RELATIONS, TRADE, COERCION]:
		return "%s — you" % nation_id
	var v := value(layer_id, state, viewer_id, nation_id)
	if is_nan(v):
		return nation_id
	match layer_id:
		RELATIONS:
			return "%s–%s  %.0f / 100" % [viewer_id, nation_id, v]
		TRADE:
			return "%s  %.1f%% of %s's demand" % [nation_id, 100.0 * v, viewer_id]
		PRODUCTION:
			# "you" in the tail rather than the bare "— you" the pair layers print,
			# because the number is real here: the planet's supply tells you your
			# own weight exactly as well as it tells you anybody else's.
			var mark := " (you)" if is_viewer(viewer_id, nation_id) else ""
			return "%s  %.1f%% of world output%s" % [nation_id, 100.0 * v, mark]
		IMPORT_DEPENDENCY:
			# A nation at zero buys nothing, and a 0.0 that could also be a NAN
			# should say which it is -- the layer's own flat-bottom finding.
			if is_zero_approx(v):
				return "%s  buys nothing in%s" % [
					nation_id, " (you)" if is_viewer(viewer_id, nation_id) else ""]
			return "%s  %.0f%% of its demand imported%s" % [
				nation_id, 100.0 * v, " (you)" if is_viewer(viewer_id, nation_id) else ""]
		COERCION:
			# The one readout on this map that names BOTH sides of a pair, and it
			# may: the colour is a sum, so direction has to be recoverable
			# somewhere, and unlike a trade share both halves are the viewer's own
			# business -- one is what they did, the other is what was done to them.
			# U5c's rule is about what a readout may CLAIM, and it claims nothing
			# here that the player is not party to.
			if is_zero_approx(v):
				return "%s  nothing in force" % nation_id
			return "%s  you %s, them %s" % [
				nation_id,
				_measure_text(state, viewer_id, nation_id),
				_measure_text(state, nation_id, viewer_id),
			]
	return nation_id


## One side of a coercion pair, in words. "—" where that side has imposed nothing,
## so the readout says which of the two directions is live rather than printing a
## zero the player has to interpret.
static func _measure_text(state, from_id: String, to_id: String) -> String:
	var terms = state.measures.get(Relations.directed_key(from_id, to_id))
	if terms == null:
		return "—"
	return "%s %.2f" % [String(terms.get("kind", "")), float(terms.get("severity", 0.0))]


## Clamped, so a value outside the shown domain saturates at the end of the ramp
## instead of extrapolating past it. Relations above 76 and a trade share above a
## third are both reachable, and both should read as "the top of the scale"
## rather than as a colour the legend never shows.
static func _fraction(v: float, low: float, high: float) -> float:
	if high <= low:
		return 0.0
	return clampf((v - low) / (high - low), 0.0, 1.0)
