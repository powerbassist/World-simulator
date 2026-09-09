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
		"caption": "The ten the game simulates.",
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
		"caption": "Share of your external demand.",
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
	if layer_id != TRADE or state == null:
		for id in nation_ids:
			var nation_id := String(id)
			out[nation_id] = color_for(layer_id, state, viewer_id, nation_id)
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
	if is_viewer(viewer_id, nation_id):
		return NO_VALUE
	var v := value(layer_id, state, viewer_id, nation_id)
	if is_nan(v):
		return NO_VALUE
	if layer_id == TRADE:
		return ramp_trade(v, trade_even_share(state, viewer_id))
	return ramp(layer_id, v)


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
	return NO_VALUE


## The raw datum, or NAN where there is none. NAN rather than 0.0 for the same
## reason Diplomacy.score() refuses to default: on the relations layer 0.0 is the
## worst possible score, not the absence of one.
static func value(layer_id: String, state, viewer_id: String, nation_id: String) -> float:
	if state == null or is_viewer(viewer_id, nation_id):
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
	return NAN


## One line naming the hovered nation's value, for the legend's readout.
##
## The relations line is written as a PAIR and the trade line is not, and that is
## the whole of the symmetric-vs-directed asymmetry as the player meets it:
## "FRA-DEU 68" is true read from either side, whereas a trade share belongs to
## the viewer alone and claiming DEU's side would need a second number this
## layer does not show.
static func value_text(layer_id: String, state, viewer_id: String, nation_id: String) -> String:
	if is_viewer(viewer_id, nation_id):
		return "%s — you" % nation_id
	var v := value(layer_id, state, viewer_id, nation_id)
	if is_nan(v):
		return nation_id
	match layer_id:
		RELATIONS:
			return "%s–%s  %.0f / 100" % [viewer_id, nation_id, v]
		TRADE:
			return "%s  %.1f%% of %s's demand" % [nation_id, 100.0 * v, viewer_id]
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
