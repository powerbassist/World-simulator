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

const POLITICAL := "political"
const RELATIONS := "relations"
const TRADE := "trade"

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

## A weight vector is normalised over the other nine, so the honest reference is
## not zero but an even share. Mid-anchoring the trade ramp here makes the map
## read as *above or below its fair share* rather than as *big or small*, which
## is the question a directed weight actually answers. Measured spread, from
## docs/trade-model.md: FRA->DEU 0.329, FRA->LUX 0.021.
const EVEN_SHARE := 1.0 / 9.0
const TRADE_MAX_SHOWN := 0.33

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
		"stops": [
			{"at": 0.03, "text": "3%  marginal"},
			{"at": EVEN_SHARE, "text": "11%  an even ninth"},
			{"at": 0.33, "text": "33%  dominant"},
		],
		"caption": "Share of your external demand.",
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
	return ramp(layer_id, v)


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
		TRADE:
			if v <= EVEN_SHARE:
				return TRADE_LOW.lerp(TRADE_MID, _fraction(v, 0.0, EVEN_SHARE))
			return TRADE_MID.lerp(TRADE_HIGH, _fraction(v, EVEN_SHARE, TRADE_MAX_SHOWN))
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
	return nation_id


## Clamped, so a value outside the shown domain saturates at the end of the ramp
## instead of extrapolating past it. Relations above 76 and a trade share above a
## third are both reachable, and both should read as "the top of the scale"
## rather than as a colour the legend never shows.
static func _fraction(v: float, low: float, high: float) -> float:
	if high <= low:
		return 0.0
	return clampf((v - low) / (high - low), 0.0, 1.0)
