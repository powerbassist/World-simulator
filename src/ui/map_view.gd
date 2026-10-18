extends Control

## The world map -- a full-screen background layer, not a modal panel like the
## other UI surfaces. main.gd adds it first so the HUD and every floating window
## draw on top of it.
##
## Projection is plain equirectangular (lon -> x, -lat -> y). Chosen at U2 because
## Europe's latitude band is narrow enough that the distortion does not obscure a
## border; kept at U5b because it is also exactly the projection the Blue Marble
## raster is stored in, so the photograph drops onto the same transform with no
## reprojection step at all. Pan/zoom are a screen-space offset and scalar applied
## on top of that fixed base projection, never reprojected -- see
## _screen_to_lonlat()/_lonlat_to_screen() for the one transform drawing,
## hit-testing and the minimap all share.
##
## Six DRAW layers, back to front: the satellite raster, the outlines of every
## country the game does not simulate, the ten it does (filled by their REGIONS
## since V2.2b, on 1:10m GISCO geometry under the 1:50m national outline), their
## labels, V2.2b's city crosses, and U6c's project markers. The second is drawn
## from `_world_polygons`, and `_nation_at_lonlat` iterates `_polygons` alone,
## so "you cannot click Poland" is structural rather than a filter somewhere that
## could be forgotten. Since V4.11c an outline can be READ: `_outline_at_lonlat`
## is its own hover test over `_world_polygons`, run only where no roster nation
## answered, and it feeds a readout -- never a click, never `nation_hovered`.
##
## The marker pass keeps that property by having its OWN hit test:
## `_project_at_screen_point()` is a radius test in screen space over `_markers`
## and reaches neither `_polygons` nor `_nation_at_lonlat`. Routing a marker click
## through the nation test would have made every marker a second reason for that
## function to exist, and the day someone widened it to answer markers over
## Poland the roster's structural guarantee would die quietly.
## tests/test_map_markers.gd reads this file and fails if either name appears
## inside that function. `_city_at_screen_point()` takes exactly that shape for
## V2.2b's crosses, on the tier doc's own instruction, and
## tests/test_map_cities.gd polices it the same way.
##
## U5c added a second, unrelated sense of the word: a MAP layer is what the ten
## are *coloured by* -- political, relations, trade. Those live entirely in
## map_layers.gd and change only what `_draw_roster()` fills with. The two never
## interact: no map layer adds, removes or reorders a draw layer, and the ~160
## non-simulated countries are coloured by none of them, having neither a pair
## nor a trade weight to show.
##
## Hit-testing, pan/zoom and framing are exposed as plain methods
## (nation_at_screen_point, pan_by, zoom_by, center_on_lonlat,
## visible_lonlat_rect) rather than only reachable through _gui_input, so a
## headless test and the minimap can drive them directly -- the same reason
## law_panel.gd exposes _on_propose() instead of only a button signal.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Motion = preload("res://src/ui/motion.gd")
const MapRaster = preload("res://src/ui/map_raster.gd")
const MapGround = preload("res://src/ui/map_ground.gd")
const Roster = preload("res://src/core/roster.gd")
const MapGlyphs = preload("res://src/ui/map_glyphs.gd")
const MapLabels = preload("res://src/ui/map_labels.gd")
const MapLayers = preload("res://src/ui/map_layers.gd")
const MapMarkers = preload("res://src/ui/map_markers.gd")
const MapOutlines = preload("res://src/ui/map_outlines.gd")
const MapCities = preload("res://src/ui/map_cities.gd")
const MapPlants = preload("res://src/ui/map_plants.gd")
const MapNetwork = preload("res://src/ui/map_network.gd")

signal nation_clicked(nation_id: String)

## A project marker was clicked -- U6c. main.gd opens Public Works on it: the
## marker is a way INTO that panel rather than a second readout of it, because
## three surfaces for one register only works if each says a different thing, and
## what the map says is *where*.
signal project_clicked(project_id: String)

## A city cross was clicked -- V2.2b, the tier doc's own route: *"section 2's city
## is reached by clicking the map"*. main.gd opens the City panel on it, and any
## nation's city answers -- the register is public data and the map colours all
## ten, so a cross that answered no click would be drawn content the game cannot
## reach.
signal city_clicked(city_id: String)

## The nation under the cursor, "" when there is none. U5c: the legend's readout
## needs to name the value the player is looking at, and a colour ramp the player
## can only read to the nearest legend stop is a ramp they cannot read.
signal nation_hovered(nation_id: String)

## V2.8. The point the player picked, in lon/lat. NOT a region id: this file holds no
## geometry lookup and must not learn one -- src/ui/main.gd resolves it through
## Region.region_at_lonlat(), which is also what keeps _plant_at_screen_point() free
## of region_rings and tests/test_map_plants.gd able to say so from the source.
signal map_point_picked(lon: float, lat: float)

## A plant glyph was clicked -- V2.8. main.gd opens the Energy window on it, the
## project marker's route one pass over.
signal plant_clicked(plant_id: String)

## PLACEMENT MODE IS EXCLUSIVE AND SINGLE-SHOT. Exclusive because a click meant to
## site a station must not also open the nation panel -- one press, one thing.
## Single-shot because an armed mode that survives its own click is a mode the player
## has to remember to leave, and the one thing worse than a station in the wrong
## region is a second station in it.
var _placing: bool = false


func begin_placement() -> void:
	_placing = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	queue_redraw()


func end_placement() -> void:
	_placing = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


func is_placing() -> bool:
	return _placing

const BASE_SCALE := 12.0  # screen pixels per degree, before zoom

const MAX_ZOOM := 8.0
const DRAG_THRESHOLD := 6.0

## The furthest zoom out is no longer a constant. U2 picked 1.0 and U5a lowered it
## to 0.25 by eye, both at a time when there was nothing outside Europe to zoom
## out *to*; with world coverage the honest answer is derivable rather than
## tasteful. `min_zoom()` is the cover fit -- the smallest zoom at which the world
## still fills the control on both axes -- so the outermost view is exactly the
## whole planet with no empty margin, on any window size. On 1920x1080 it lands
## near 0.5.
##
## The floor exists only so a degenerate zero-sized control cannot produce a zoom
## of 0 and a division by it downstream.
const MIN_ZOOM_FLOOR := 0.05

## How much of the control the roster's bounding box fills on the opening view.
## Short of 1.0 so the outermost coastlines are not flush against the edge, and
## so the HUD's corners sit over sea rather than over Portugal.
const FIT_FRACTION := 0.82

var _loader
var _state

var _polygons: Dictionary = {}  # nation id -> Array[PackedVector2Array], raw lon/lat
var _nation_boxes: Dictionary = {}  # nation id -> Rect2, the lon/lat bbox of the above
var _world_polygons: Dictionary = {}  # same shape, the ~160 nations not simulated
var _labels: Dictionary = {}  # nation id -> {pos: Vector2 lon/lat, text: String}
var _texture: ImageTexture = null
## V4.10a. The ground at depth and its lon/lat rect, both from MapGround; null
## on a missing asset, and then the photograph keeps every zoom as before.
var _ground: ImageTexture = null
var _ground_bounds := Rect2()
var _ground_feather_deg := 0.0
## V4.10b. Each roster nation's border kind, its Roster.grade() -- content-derived
## and static for the session, so cached in setup() beside the ring boxes rather
## than asked per ring per re-record.
var _border_kind: Dictionary = {}
## V4.10b. city_id -> nation_id for each nation's capital (MapGlyphs.capitals):
## content, built once in setup(); a city's TIER is recomputed with the city list
## each month because tiers 2 and 3 read live population.
var _capitals: Dictionary = {}
## Text sizes by "size|text": the names are content, so a width is measured once
## per session rather than once per re-record per city.
var _text_size: Dictionary = {}
## The last placement, read by tests/test_map_view.gd and tools/label_probe.gd.
var _last_placed: Array = []
## Per tier, how many cities were on screen and eligible at the last placement.
var _label_onscreen: Dictionary = {}
## Probe seam (tools/frame_probe.gd's paired rows): false skips the label pass.
var _labels_enabled := true
var _center_lon := 0.0
var _center_lat := 0.0

var _zoom := 1.0
var _pan_offset := Vector2.ZERO

var _hovered_id := ""

## U6c. Rebuilt from live state on every draw rather than cached, so a project
## that finishes this month is drawn finished on the next redraw with no refresh
## path of its own -- main.gd already redraws the map monthly for U5c's reason.
var _markers: Array = []
var _hovered_project := ""

## THE FILL MEMO. `_draw_roster()` re-records every pan and zoom frame (a drag
## queues a redraw per mouse-motion event), and MapLayers.fills() is stateless on
## purpose -- its own header says nothing is cached there -- so importing the layer
## re-sums all 29 nations x 60 goods on EVERY frame. Measured: 1.506 ms/frame for
## IMPORT_DEPENDENCY against a 0.040 ms political baseline, ~38x, which the player
## pays while dragging. So the result is memoised HERE at the caller, keyed on
## `_fill_key`. `MapLayers` is untouched: the caching stays on this side of the
## contract, the same way this file owns when a fill is derived.
##
## ONLY THE COMMODITY LAYERS ARE MEMOISED. Their every input is `commodity_state`,
## and the sole writer of that (Commodities.tick_month) runs inside the monthly
## tick -- so between two ticks the fills cannot change and a memo is exact. The
## pair layers (RELATIONS, TRADE, COERCION) read relations, orgs and measures that
## a diplomatic action or an event can move MID-month, so memoising them on the
## month would hand back a stale colour until the next tick; they keep the
## derived-every-draw path. POLITICAL is an id tint and needs no memo.
##
## The key is (state identity, absolute month year*12+month, layer, viewer). A
## pan/hover frame leaves all four equal and hits the memo; a tick, a layer toggle
## or a new `setup()` changes one and rebuilds. State IDENTITY is in the key so a
## fresh game at month 0 cannot read the previous game's dictionary.
var _fill_key := {}
var _fill_cache: Dictionary = {}

## V2.2b, CORRECTED at V2.6b1: rebuilt on the MONTHLY hook by refresh_cities(),
## not once in setup(). This paragraph used to argue the register was static
## content, which was true when it was written and false from V2.6a, when a city's
## population became two live shares times a live head count -- so the crosses
## never grew or shrank for a whole session. Not per draw either: this walks 581
## cities and derives a site per nation, and V2.3 already paid for putting that
## kind of work on a draw path. Ascending population, so the largest draws last
## and wins an overlap; see MapCities and refresh_cities() below.
var _cities: Array = []
var _hovered_city := ""
## V4.11c. The outline under the cursor ("" for none), and where the cursor
## entered it -- the readout draws there rather than at a centroid, which for
## Russia or Canada can sit off-screen.
var _hovered_outline := ""
var _hover_screen := Vector2.ZERO

## Built once in setup() from content that never mutates -- the graph, and each
## region's cities[0]. Not rebuilt on the monthly hook the way _cities is: a
## city's population is live state and a road's endpoints are not.
var _spines: Array = []

## How many spines the last _draw() SUBMITTED after the cull -- not how many
## landed visible pixels, which is the distinction map_network.gd's own doc
## draws. Read by tests/test_map_view.gd, which asserts the cull by number.
var _spines_drawn: int = 0

var _dragging := false
var _drag_moved := 0.0
var _last_mouse_pos := Vector2.ZERO

## Degrees spanned by the loaded polygons, and whether the opening zoom has been
## chosen yet. Both exist only for _fit_zoom(); see it for why the fit cannot
## happen inside setup().
var _span_deg := Vector2.ZERO
var _has_fitted := false

## Which layer is up. The fill is map_layers.gd's business as of U5c -- there is
## no colour table and no alpha constant in this file any more, and no mode flag
## threaded through _draw() either: _draw_roster() asks the registry for a Colour
## per id, and a new layer is an entry there that this file never learns about.
##
## Political by default. It is the layer that needs no simulation state to be
## legible, so it is what the map should open on and what an unknown id falls
## back to -- see MapLayers.layer().
var _layer := MapLayers.POLITICAL

## V4.9b. A layer change crossfades rather than cuts: `_fill_from` is what the
## map showed the moment the player toggled (mid-blend included, so a second
## toggle starts from the colours on screen), `_layer_blend` how far the new
## layer's fills have come in, 1.0 when no fade runs. Only the FILL fades --
## strokes, hover and the legend change at once, because they say which layer
## is up and should not be ambiguous for 0.3 s. V4.10's modes share this path.
var _fill_from: Dictionary = {}
var _layer_blend := 1.0

## The sea, now only a fallback. Kept rather than deleted with the raster's
## arrival because MapRaster.texture() returning null is a declared outcome, not
## an error: a clone missing the 2.5 MB asset should look plainer, not open onto a
## black void with ten countries floating in it.
const SEA := Color(0.043, 0.075, 0.129)

## V4.10b. BORDERS WEIGHTED BY KIND, one table, one draw pass per kind. The third
## key is the roster grade (author's call at the V4.10b plan gate): V4.11's derived
## playable / simulated / outline, read through Roster.grade() and never stored,
## beside the regional hairline inside a nation. Before this every roster nation
## stroked the same near-white line and only the world layer was quieter.
##
## Each kind carries TWO colours because the ground under it changes with the
## zoom band (V4.10a): over the satellite at globe view a line has to be light to
## read against sea and forest, over the paper ground at depth it has to be ink.
## border_color() blends them by ground_alpha(), so a line never sits on the
## wrong ground. The photo colours are the pre-V4.10b values unchanged: COAST was
## (0.95, 0.96, 0.99, 0.88), WORLD_BORDER (0.71, 0.78, 0.86, 0.22), REGION_BORDER
## (0.71, 0.78, 0.86, 0.35).
##
## Widths are a hierarchy a player reads without a legend: the nations you can
## lead heaviest, the ones the game runs a step lighter (they still answer a
## click), the world's outlines at the old world-border weight, and the regional
## hairline lightest, because it is structure inside a country rather than the
## edge of one. COAST_WIDTH (1.5) sat between the first two.
const BORDER_KINDS := {
	"playable": {"photo": Color(0.95, 0.96, 0.99, 0.88), "paper": Color(0.13, 0.11, 0.09, 0.92), "width": 2.0},
	"simulated": {"photo": Color(0.95, 0.96, 0.99, 0.70), "paper": Color(0.13, 0.11, 0.09, 0.72), "width": 1.4},
	"outline": {"photo": Color(0.71, 0.78, 0.86, 0.22), "paper": Color(0.22, 0.19, 0.16, 0.40), "width": 1.0},
	"regional": {"photo": Color(0.71, 0.78, 0.86, 0.35), "paper": Color(0.22, 0.19, 0.16, 0.45), "width": 0.75},
}
## V4.11c. The hovered outline's line: the world border's hue at roughly the
## coastline's strength, so the country being read stands out without looking
## like one the player can act on (the roster's line stays the brightest). Since
## V4.10b only its ALPHA is read: the hue follows border_color("outline").
const WORLD_BORDER_HOVER := Color(0.71, 0.78, 0.86, 0.70)
const WORLD_BORDER_HOVER_WIDTH := 1.5
## The readout's offset from the cursor, its line gap and its plate's padding.
const OUTLINE_READOUT_OFFSET := Vector2(14.0, -8.0)
const OUTLINE_READOUT_GAP := 16.0
const OUTLINE_READOUT_PAD := 6.0
## The plate's body: the HUD's hull, a touch translucent so the country under it
## still reads as the thing being described.
const OUTLINE_READOUT_PLATE := Color(0.063, 0.106, 0.188, 0.92)

## Hover and the viewer's own nation both move the *stroke* rather than the fill,
## and on a data layer that is not a style choice. U5b's hover lifted the fill
## toward the accent by 0.35, which on the political layer says "this one is under
## the cursor" and on a relations layer says a pair is warmer than it is -- the
## one place in the interface where pointing at a number would change it. The
## outline is already what separates the roster (see BORDER_KINDS), so it is the honest
## carrier for both marks.
## Hover is mostly width: the roster's photo line is already near-white, so a
## brighter white adds little and brass is spoken for by the home mark. 3.0 was
## legible in a frame only just, hence 4.0.
const HOVER_WIDTH := 4.0
const HOME_WIDTH := 2.5

## V2.2b's regional hairline lives in BORDER_KINDS["regional"] since V4.10b: it
## is structure inside the roster, not context outside it, and must stay quiet
## enough that the national stroke remains the line saying which nations answer
## a click.

## V3.1 culling. The pad is DERIVED, not swept: the widest stroke on the map is
## HOVER_WIDTH (4.0 px) and antialias feather adds a couple more, so a ring
## whose box comes within 8 px of the view edge could still paint a pixel of
## line. The ring passes convert it to degrees at the current zoom and share
## one value, so no pass can pad differently and survive the two-pass enclave
## rule; the city pass keeps it in screen pixels beside its own radius terms.
const CULL_PAD_PX := 8.0

## Below this zoom a label is dropped. At the world view ten labels across Europe
## are ten labels on top of each other; the threshold is set just under the
## opening Europe fit, so the roster is named from the moment the game starts and
## the names clear off as the player pulls back to the globe.
## A few pixels of slack around the glyph, so a 6px dot is not a 6px target, and
## a 2px cross is not a 2px target. Not in map_markers.gd with the other marker
## constants: that file says what a marker looks like, and this says how forgiving
## this control is about pointing at one.
const MARKER_HIT_PAD := 3.0

const LABEL_MIN_ZOOM := 1.4

## Below this zoom a city cross is dropped -- V2.2b, on LABEL_MIN_ZOOM's own
## discipline: set just under the opening Europe fit, so the crosses are there
## from the moment the game starts and clear off as the player pulls back to the
## globe. The fit is computed from the committed extents, not eyeballed, and
## V3.3 re-measured it for the EU-29 roster: 2.08 on 1080p, lat-bound as before
## (the eastward growth to Cyprus does not move the binding dimension), so 2.0
## keeps its just-under place and the value is unchanged. The volume clause was
## re-measured with it: CITY_MIN_POP's 2021 sweep shipped ~1065 cities on the
## new roster against the same px/degree, per BALANCE_PLAN.md's band. Names stay
## on hover alone, where the labels at least get the opening fit. The HIT test
## reads the same gate, so a glyph that is not drawn is never a target.
const CITY_MIN_ZOOM := 2.0
const LABEL_COLOR := Color(0.94, 0.96, 1.0, 0.92)
## The outline halo (near-black, a=0.8) replaces the old 1px offset drop shadow
## -- the shadow was too weak over Alpine snow, and outline+shadow together
## would double-darken every glyph edge for no gain, so only the outline draws.
const LABEL_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const LABEL_OUTLINE_PX := 3

## V4.10b. The zoom at which each glyph tier's cities are NAMED permanently (below
## it a city is named on hover only, as before). Set by tools/label_probe.gd's
## band, written before the run: a tier turns on at the lowest zoom of the grid
## where >= 70 % of its on-screen cities get a name in BOTH stress views
## (Nordrhein-Westfalen, Lombardia) with the tiers above it already on. The
## measured table is in docs/map-platform-model.md §10. Measured 2026-10-18:
## tiers 1 and 2 pass at the grid's first step (>= 80 % named in both views at
## 2.0, which is CITY_MIN_ZOOM, so they are named wherever their marks are drawn).
## Tier 3 is a BOUND: it peaks at 64 % over the Ruhr at max zoom (71 % over
## Lombardia), so tier-3 names stay on hover -- INF says "never" without a magic
## zoom a later MAX_ZOOM could quietly reach.
const LABEL_ZOOM_T1 := 2.0
const LABEL_ZOOM_T2 := 2.0
const LABEL_ZOOM_T3 := INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	# V4.10a. The ground is mipmapped because at the band's low edge it is
	# minified 4:1 (60 texels/deg onto 15 px/deg) and shimmers without; the
	# photograph has no mipmaps and falls back to plain linear, as before.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## The first layout pass is where the control finally has a size, which is what
## _fit_zoom() needs and cannot get in setup(). Hooked here as well as in
## _draw() so a hit-test that happens before the first frame is drawn still uses
## the zoom the player will see.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_zoom()
		# A later resize does not re-fit -- see _fit_zoom() -- but it does change
		# what the cover fit is, so a window that grows can leave the current zoom
		# below the new floor and the current pan outside the world.
		_zoom = clampf(_zoom, min_zoom(), MAX_ZOOM)
		_clamp_pan()
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT and _hovered_outline != "":
		# V4.11c. The readout is a plate of text, not a brighter stroke: when the
		# cursor leaves for a window or the HUD no further motion reaches this
		# control, so without this it stays on screen until the cursor comes back
		# (the V4.11 review). Godot 4 sends the exit when a window occludes the map.
		_hovered_outline = ""
		queue_redraw()


func setup(loader, state) -> void:
	_loader = loader
	_state = state
	_polygons.clear()
	_labels.clear()
	_nation_boxes.clear()

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var n = loader.nations[id]
		var polys: Array = loader.geo_features.get(n.geo_id, [])
		_polygons[id] = polys
		# V3.3's watch-point made real: the hit test walks every roster outline
		# per mouse-move, and the roster tripled, so each nation carries a bbox
		# the test can reject on before touching a ring. Built from the same
		# arrays the test walks, so the two cannot disagree.
		var box := Rect2()
		var first := true
		for ring: PackedVector2Array in polys:
			for pt in ring:
				if first:
					box = Rect2(pt, Vector2.ZERO)
					first = false
				else:
					box = box.expand(pt)
		_nation_boxes[id] = box
		if loader.label_points.has(n.geo_id):
			_labels[id] = {
				"pos": loader.label_points[n.geo_id],
				"text": n.nation_name.to_upper(),
			}

	_world_polygons = loader.world_features
	_texture = MapRaster.texture()
	_ground = MapGround.texture()
	_ground_bounds = MapGround.bounds()
	_ground_feather_deg = float(MapGround.sidecar().get("feather_deg", 0.0))
	_border_kind.clear()
	for id in ids:
		_border_kind[id] = Roster.grade(loader, String(id))

	# Per-ring bounding boxes for the draw cull, built ONCE beside the arrays
	# they walk -- the same call _nation_boxes made for the hit test. The cull
	# itself used to recompute each ring's box on every re-record, walking all
	# ~28k visible-ring points per pan frame for a number that never changes:
	# the rings are content. Built from the same arrays the draw walks, so a
	# box and its ring cannot disagree.
	_ring_boxes_roster.clear()
	_ring_boxes_region.clear()
	_ring_boxes_world.clear()
	for id in ids:
		_ring_boxes_roster[id] = _ring_boxes_for(_polygons[id])
	for region_id in loader.region_features.keys():
		_ring_boxes_region[String(region_id)] = _ring_boxes_for(
			loader.region_features[region_id])
	for id in _world_polygons.keys():
		_ring_boxes_world[id] = _ring_boxes_for(_world_polygons[id])

	_capitals = MapGlyphs.capitals(loader)

	# Built here for _refresh_markers()'s reason: a hit test can happen before the
	# first frame is drawn, and an empty list would answer it with "nothing here".
	refresh_cities()

	# Built here rather than in _draw() for the reason the city list is: content
	# that never mutates is built once, and a first frame that finds an empty
	# list draws a map with no roads on it.
	_spines = MapNetwork.spines(loader)

	# Built here as well as in _draw() for the reason _fit_zoom() is hooked in
	# _notification(): a hit test can happen before the first frame is drawn, and
	# an empty marker list would answer it with "nothing here".
	_refresh_markers()

	_fit_bounds()
	queue_redraw()


## Centres the base projection on the bounding box of every loaded polygon, so
## the map opens framed on Europe rather than on whatever origin (0,0) happens
## to be in lon/lat space.
func _fit_bounds() -> void:
	var min_lon := INF
	var max_lon := -INF
	var min_lat := INF
	var max_lat := -INF
	var found := false

	for polys in _polygons.values():
		for ring: PackedVector2Array in polys:
			for p in ring:
				found = true
				min_lon = minf(min_lon, p.x)
				max_lon = maxf(max_lon, p.x)
				min_lat = minf(min_lat, p.y)
				max_lat = maxf(max_lat, p.y)

	if not found:
		_center_lon = 0.0
		_center_lat = 0.0
		_span_deg = Vector2.ZERO
		return

	_center_lon = (min_lon + max_lon) / 2.0
	_center_lat = (min_lat + max_lat) / 2.0
	_span_deg = Vector2(max_lon - min_lon, max_lat - min_lat)


## Chooses the opening zoom so the roster fills the view.
##
## Not done in setup(): the control has no size until the first layout pass, and
## U2 never noticed because a 12px-per-degree map inside a dock happened to look
## reasonable. As a full-screen background it does not -- at zoom 1.0 on 1920x1080
## Europe is a 480x420 object floating in the middle of an empty screen.
##
## Runs once. A resize after the player has panned somewhere should not throw
## away where they were looking.
func _fit_zoom() -> void:
	if _has_fitted or _span_deg.x <= 0.0 or _span_deg.y <= 0.0:
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_has_fitted = true
	_zoom = clampf(
		minf(
			size.x * FIT_FRACTION / (_span_deg.x * BASE_SCALE),
			size.y * FIT_FRACTION / (_span_deg.y * BASE_SCALE)
		),
		min_zoom(), MAX_ZOOM
	)
	center_on_lonlat(_center_lon, _center_lat)


## The cover fit: the smallest zoom at which the world still fills the control on
## both axes. Derived rather than a constant -- see MIN_ZOOM_FLOOR.
func min_zoom() -> float:
	if size.x <= 0.0 or size.y <= 0.0:
		return MIN_ZOOM_FLOOR
	var lon_span := MapRaster.LON_MAX - MapRaster.LON_MIN
	var lat_span := MapRaster.LAT_MAX - MapRaster.LAT_MIN
	return maxf(
		MIN_ZOOM_FLOOR,
		maxf(size.x / (lon_span * BASE_SCALE), size.y / (lat_span * BASE_SCALE))
	)


## Keeps the world under the viewport. Before U5b the map could be dragged into
## empty space and nothing said otherwise, because past Europe's coast there was
## nothing to see either way; with a photograph of the planet underneath, empty
## space is visibly a bug. On an axis where the world is larger than the control
## the viewport is pushed back inside it; on one where it is smaller -- possible
## only transiently, since min_zoom() is a cover fit -- the world is centred.
func _clamp_pan() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var top_left := _lonlat_to_screen(MapRaster.LON_MIN, MapRaster.LAT_MAX)
	var bottom_right := _lonlat_to_screen(MapRaster.LON_MAX, MapRaster.LAT_MIN)

	for axis in [Vector2.AXIS_X, Vector2.AXIS_Y]:
		var extent: float = bottom_right[axis] - top_left[axis]
		if extent >= size[axis]:
			if top_left[axis] > 0.0:
				_pan_offset[axis] -= top_left[axis]
			elif bottom_right[axis] < size[axis]:
				_pan_offset[axis] += size[axis] - bottom_right[axis]
		else:
			_pan_offset[axis] += (size[axis] - top_left[axis] - bottom_right[axis]) / 2.0


## The lon/lat window the control currently shows. Rect2 in degrees, position at
## the south-west corner -- latitude increases upward while screen y increases
## downward, so the two corners swap on that axis.
func visible_lonlat_rect() -> Rect2:
	var top_left := _screen_to_lonlat(Vector2.ZERO)
	var bottom_right := _screen_to_lonlat(size)
	return Rect2(
		Vector2(top_left.x, bottom_right.y),
		Vector2(bottom_right.x - top_left.x, top_left.y - bottom_right.y)
	)


## True when a lon/lat ring's bounding box reaches the view rect, grown by the
## stroke pad. Conservative by construction: a bounding box can only
## OVER-include, never clip a visible ring -- a huge ring whose box covers the
## view draws whole, exactly as before. Static geometry (loader data never
## mutates), so reading live lon/lat bounds carries no staleness class; city
## populations are the live quantity and are culled on screen points instead.
## Applied inside each pass over the same rings, which is what keeps the
## two-pass enclave draw intact: any ring drawn at all is drawn as both fill
## and hairline, because the hairline list is built only from rings this
## predicate let through.
## The single-ring statement of the draw cull, and the shape the cached boxes
## in _draw() answer for the whole roster at once -- the same split as
## network.gd's _network_pct/_sited_pct beside their per-roster pass. Kept as
## the readable contract tests/test_map_cull.gd pins; the draw reads the boxes.
func _ring_reaches_view(ring: PackedVector2Array, view: Rect2) -> bool:
	if ring.size() < 3:
		return false
	var pad := CULL_PAD_PX / (BASE_SCALE * _zoom)
	var min_lon := INF
	var max_lon := -INF
	var min_lat := INF
	var max_lat := -INF
	for p in ring:
		min_lon = minf(min_lon, p.x)
		max_lon = maxf(max_lon, p.x)
		min_lat = minf(min_lat, p.y)
		max_lat = maxf(max_lat, p.y)
	if max_lon < view.position.x - pad or min_lon > view.end.x + pad:
		return false
	if max_lat < view.position.y - pad or min_lat > view.end.y + pad:
		return false
	return true


## Puts a lon/lat point at the centre of the control, then re-clamps. The minimap
## calls this; so does _fit_zoom(), because a zoom chosen without recentring can
## leave the pan from the previous size behind.
func center_on_lonlat(lon: float, lat: float) -> void:
	var base := Vector2(lon - _center_lon, -(lat - _center_lat)) * BASE_SCALE
	_pan_offset = -base * _zoom
	_clamp_pan()
	queue_redraw()


func _control_center() -> Vector2:
	return size / 2.0


## Per-ring bounding boxes, index-aligned with the ring arrays they gate. A
## negative-size Rect2 marks a ring the old cull never drew (fewer than three
## points) so the draw's single `continue` covers both gates.
var _ring_boxes_roster: Dictionary = {}
var _ring_boxes_region: Dictionary = {}
var _ring_boxes_world: Dictionary = {}


func _ring_boxes_for(polys: Array) -> Array:
	var out: Array = []
	for ring: PackedVector2Array in polys:
		if ring.size() < 3:
			out.append(Rect2(0, 0, -1, -1))
			continue
		var box := Rect2(ring[0], Vector2.ZERO)
		for i in range(1, ring.size()):
			box = box.expand(ring[i])
		out.append(box)
	return out


## The per-draw expansion of _lonlat_to_screen()'s affine: screen =
## (p.x * _kx + _ox, p.y * _ky + _oy). Written by _draw(), read by the heavy
## ring passes only. See the comment in _draw().
var _kx: float = 0.0
var _ky: float = 0.0
var _ox: float = 0.0
var _oy: float = 0.0


func _lonlat_to_screen(lon: float, lat: float) -> Vector2:
	var base := Vector2(lon - _center_lon, -(lat - _center_lat)) * BASE_SCALE
	return base * _zoom + _pan_offset + _control_center()


func _screen_to_lonlat(screen_pos: Vector2) -> Vector2:
	var base := (screen_pos - _control_center() - _pan_offset) / _zoom
	var lon := base.x / BASE_SCALE + _center_lon
	var lat := _center_lat - base.y / BASE_SCALE
	return Vector2(lon, lat)


## Returns the nation id whose outer ring contains the given lon/lat point, or
## "" if none does. First match wins -- Europe's nations here don't overlap.
## The bbox pre-reject is the watch-point V3.1's §7 handed this block: the
## roster tripled the per-move point count, so a point outside a nation's box
## never reaches that nation's rings.
func _nation_at_lonlat(pt: Vector2) -> String:
	for id in _polygons.keys():
		if not (_nation_boxes.get(id, Rect2()) as Rect2).has_point(pt):
			continue
		for ring: PackedVector2Array in _polygons[id]:
			if ring.size() >= 3 and Geometry2D.is_point_in_polygon(pt, ring):
				return id
	return ""


func nation_at_screen_point(screen_pos: Vector2) -> String:
	return _nation_at_lonlat(_screen_to_lonlat(screen_pos))


## V4.11c. The outline under a lon/lat point, or "". Its OWN test over the outline
## register, the marker precedent: `_nation_at_lonlat` stays roster-only, so an
## outline can be read but never clicked or selected. The per-ring boxes are the
## ones the border pass culls on, built in setup() from the same arrays.
func _outline_at_lonlat(pt: Vector2) -> String:
	for id in _world_polygons.keys():
		var polys: Array = _world_polygons[id]
		var boxes: Array = _ring_boxes_world[id]
		for r in range(polys.size()):
			var box: Rect2 = boxes[r]
			if box.size.x < 0.0 or not box.has_point(pt):
				continue
			var ring: PackedVector2Array = polys[r]
			if ring.size() >= 3 and Geometry2D.is_point_in_polygon(pt, ring):
				return id
	return ""


## V2.6b1. The city list is NOT static, and the comment that used to sit on it said
## it was -- which is how V2.6a's own headline readout claim went untrue on screen
## without anything going red. `population` is `Migration.city_population()`, live
## since V2.6a, and V2.6b1 adds a per-city unrest flag; both were being read once at
## setup and never again, so the crosses did not grow or shrink for a whole session
## and a demonstration drew no ring at all. Found by the screenshot pass, which is
## the only thing that could have found it: the headless suite has no draw.
##
## Rebuilt MONTHLY rather than per draw, unlike _refresh_markers(). That is
## deliberate: this walks 581 cities and derives a site per nation, where the marker
## list walks a handful of started projects. V2.3 put Icon.load_icon() on the path
## that refreshes with the clock and rasterised an SVG on every call -- a class of
## bug a screenshot pass structurally cannot see -- so the expensive rebuild goes on
## the hook U5c already added for the same staleness, and the draw stays a draw.
func refresh_cities() -> void:
	_cities = MapCities.cities(_loader, _state)
	for city in _cities:
		city["tier"] = MapGlyphs.tier_of(city, _capitals)


func _refresh_markers() -> void:
	_markers = MapMarkers.markers(_loader, _state)


## The project id of the marker under a screen point, or "" if there is none.
##
## A radius test in SCREEN space, over the marker list and nothing else. It does
## not go through the roster's polygons and must not be made to -- see the header.
## Screen space rather than lon/lat because the glyph is a fixed number of pixels
## at every zoom, so the region a player can hit has to be too; a degree-radius
## test would be a target that shrinks as you zoom out to find it.
##
## Last match wins, so the marker drawn on top of an overlapping pair is the one
## a click reaches -- _draw_markers() walks the same list in the same order.
## The plant under the cursor, or "". A radius test in SCREEN space, like
## _project_at_screen_point() and _city_at_screen_point() beside it: the glyph is a
## fixed number of pixels at every zoom, so a degree-radius target would shrink as
## the player zoomed out to look for it.
func _plant_at_screen_point(screen_pos: Vector2) -> String:
	var best: String = ""
	var best_d: float = MapPlants.RADIUS + 3.0
	var nation_ids: Array = _state.nations.keys()
	nation_ids.sort()
	for nation_id in nation_ids:
		var ns = _state.nations[nation_id]
		var plant_ids: Array = ns.plants.keys()
		plant_ids.sort()
		for plant_id in plant_ids:
			var entry: Dictionary = ns.plants[plant_id]
			var at := _lonlat_to_screen(float(entry.get("lon", 0.0)), float(entry.get("lat", 0.0)))
			var d := at.distance_to(screen_pos)
			if d <= best_d:
				best_d = d
				best = String(plant_id)
	return best


func _project_at_screen_point(screen_pos: Vector2) -> String:
	var hit := ""
	for marker in _markers:
		var lonlat: Vector2 = marker["lonlat"]
		var at := _lonlat_to_screen(lonlat.x, lonlat.y)
		if at.distance_to(screen_pos) <= MapMarkers.RADIUS + MARKER_HIT_PAD:
			hit = String(marker["project_id"])
	return hit


## Whose seat the data layers are read from. The player's, always -- U5c's first
## call, argued in ROADMAP's U5c row. It is a method rather than an inlined
## `_state.player_nation_id` at four call sites so that a selected-nation viewer,
## if a later session wants one, is a change here and nowhere else.
func viewer_id() -> String:
	if _state == null:
		return ""
	return _state.player_nation_id


## Public rather than only reachable from the legend's toggle, the same rule the
## camera methods state: a headless test drives this directly.
func set_layer(layer_id: String) -> void:
	# Normalised through the registry, so an unknown id is stored as the fallback
	# rather than kept and resolved on every draw -- layer() must report what is
	# actually being drawn.
	var resolved := String(MapLayers.layer(layer_id)["id"])
	if resolved == _layer:
		return
	var shown: Dictionary = _shown_fills(viewer_id()) if _state != null else {}
	# Land any fade still running BEFORE taking its place: its last step clears
	# _fill_from, which must not happen after the new one is set.
	Motion.finish(self)
	_layer = resolved
	_fill_from = shown
	_layer_blend = 0.0
	Motion.run(self, Motion.LAYER_S, func(t: float):
		_layer_blend = t
		if t >= 1.0:
			_fill_from = {}
		queue_redraw()
	)


func layer() -> String:
	return _layer


## Public because src/ui/map_flows.gd needs the zoom band to choose between arcs
## and convoys, and because a headless test cannot reach a private field. The
## overlay reads this and CITY_MIN_ZOOM and nothing else about the camera except
## visible_lonlat_rect() -- it never learns what BASE_SCALE is.
func zoom() -> float:
	return _zoom


func spines_drawn() -> int:
	return _spines_drawn


## The whole list's size, so a cull test can state its bound as a FRACTION of
## the roster rather than as a figure that silently becomes a test of the
## window size the day anyone changes it.
func spine_count() -> int:
	return _spines.size()


## Sets the zoom directly, for tests and probes. zoom_by() is the player's route
## and takes an anchor; this is the one tools/frame_probe.gd and the map tests
## already need and were reaching around for.
func set_zoom_for_test(z: float) -> void:
	_has_fitted = true
	_zoom = clampf(z, min_zoom(), MAX_ZOOM)
	_clamp_pan()
	queue_redraw()


## The city id of the cross under a screen point, or "" if there is none --
## V2.2b, taking the marker hit test's contract exactly. A radius test in SCREEN
## space over the city list and nothing else, reaching neither the roster's
## polygons nor its hit test -- the tier doc's own instruction, for markers'
## reason: routing a cross through the nation test would make every city a
## second reason for the roster's own hit test to exist. Screen space because
## the glyph is a fixed number of pixels at every zoom, so the region a player
## can hit has to be too. The radius is the cross's own -- a bigger city is a
## bigger target, which is the one thing its radius is for.
##
## Gated on CITY_MIN_ZOOM, where markers' test is not: a cross that is not drawn
## must not be a target, and below the threshold the map answers the nation
## beneath the invisible cross instead.
##
## Last match wins, so the cross drawn on top of an overlapping pair is the one
## a click reaches -- the list is ascending population and the largest drew last.
##
## Sits here rather than beside the marker hit test it copies, because the
## source-reading test that polices that function swallows whatever comment
## follows it -- and this doc names the things it must not reach.
func _city_at_screen_point(screen_pos: Vector2) -> String:
	if _zoom < CITY_MIN_ZOOM:
		return ""
	var hit := ""
	for city in _cities:
		var lonlat: Vector2 = city["lonlat"]
		var at := _lonlat_to_screen(lonlat.x, lonlat.y)
		if at.distance_to(screen_pos) <= MapCities.radius_of(city) + MARKER_HIT_PAD:
			hit = String(city["city_id"])
	return hit


func pan_by(delta: Vector2) -> void:
	_pan_offset += delta
	_clamp_pan()
	queue_redraw()


func zoom_by(factor: float, anchor_screen: Vector2) -> void:
	var anchor_lonlat := _screen_to_lonlat(anchor_screen)
	_zoom = clampf(_zoom * factor, min_zoom(), MAX_ZOOM)
	# Re-derive pan so the same lon/lat stays under the anchor point after the
	# zoom changes scale -- otherwise every scroll recenters on the map origin.
	var base := Vector2(anchor_lonlat.x - _center_lon, -(anchor_lonlat.y - _center_lat)) * BASE_SCALE
	_pan_offset = anchor_screen - _control_center() - base * _zoom
	_clamp_pan()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# PLACEMENT MODE INTERCEPTS THE PRESS ITSELF, before the drag
				# bookkeeping: a click that sites a station is not the first half
				# of a pan, and the test drives exactly this event.
				if _placing:
					var pt := _screen_to_lonlat(event.position)
					end_placement()
					map_point_picked.emit(pt.x, pt.y)
					return
				_dragging = true
				_drag_moved = 0.0
				_last_mouse_pos = event.position
			else:
				if _dragging and _drag_moved < DRAG_THRESHOLD:
					# Markers first, cities next, and a hit stops there: a marker
					# or a cross sits on top of the nation that owns it, so falling
					# through would open two windows on one click.
					# V2.8. Plants first -- last drawn is topmost -- and a hit
					# stops the fall-through, the markers-first rule one pass on.
					var plant := _plant_at_screen_point(event.position)
					if plant != "":
						plant_clicked.emit(plant)
					else:
						var project := _project_at_screen_point(event.position)
						if project != "":
							project_clicked.emit(project)
						else:
							var city := _city_at_screen_point(event.position)
							if city != "":
								city_clicked.emit(city)
							else:
								var id := nation_at_screen_point(event.position)
								if id != "":
									nation_clicked.emit(id)
				# CLEARED UNCONDITIONALLY, outside the click branch above --
				# window_frame.gd's own release does the same. Nested one tab deeper
				# until the V2.8 review, it ran only when the press had been short
				# enough to count as a click, so a real pan left _dragging true on
				# release and the motion branch below kept calling pan_by() with no
				# button held. The map followed the free cursor until the next press,
				# and nation_hovered stopped emitting with it, freezing the legend,
				# _hovered_project and _hovered_city at their drag-start values.
				_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_by(1.15, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_by(1.0 / 1.15, event.position)

	elif event is InputEventMouseMotion:
		if _dragging:
			var delta: Vector2 = event.position - _last_mouse_pos
			_drag_moved += delta.length()
			_last_mouse_pos = event.position
			pan_by(delta)
			# The readout sits at a screen point, so a pan would leave it floating
			# over whatever slid under it; it returns on the next free move.
			_hovered_outline = ""
		else:
			var id := nation_at_screen_point(event.position)
			if id != _hovered_id:
				_hovered_id = id
				nation_hovered.emit(id)
				queue_redraw()
			# Independent of the nation hover rather than replacing it: the
			# country under a marker is still legitimately under the cursor,
			# and the legend's readout should not blank because a dot is in the
			# way.
			var project := _project_at_screen_point(event.position)
			if project != _hovered_project:
				_hovered_project = project
				queue_redraw()
			# And a third independent hover, the cross under the cursor -- same
			# rule again: the nation under it is still under it.
			var city := _city_at_screen_point(event.position)
			if city != _hovered_city:
				_hovered_city = city
				queue_redraw()
			# V4.11c. A fourth hover, and only where no roster nation answered:
			# the outline readout never competes with a nation under the cursor.
			var outline := "" if id != "" else _outline_at_lonlat(_screen_to_lonlat(event.position))
			# Redrawn on a CHANGE only, as the nation hover is: a readout that
			# followed the cursor would re-record the whole map on every move
			# (~73 ms at the opening fit), so it anchors where the cursor entered.
			if outline != _hovered_outline:
				_hovered_outline = outline
				_hover_screen = event.position
				queue_redraw()


func _draw() -> void:
	_fit_zoom()
	# THE ONE TRANSFORM, EXPANDED ONCE PER DRAW. The heavy passes below inline
	# _lonlat_to_screen() as two multiply-adds over these locals: a pan re-record
	# walks every visible ring's points (65k at the EU-27 roster), and a GDScript
	# function call per point cost ~80 ms per pan frame -- a drag at 11 fps.
	# The folded constants reorder two multiplications against the function
	# body, which moves projected vertices by less than a billionth of a pixel;
	# the function stays the readable statement of the transform and every
	# non-hot path (hit tests, cities, labels, markers, plants) still calls it.
	_kx = BASE_SCALE * _zoom
	_ky = -BASE_SCALE * _zoom
	var cc := _control_center()
	_ox = _pan_offset.x + cc.x - _center_lon * _kx
	_oy = _pan_offset.y + cc.y + _center_lat * _kx
	_draw_raster()
	_draw_world_borders()
	_draw_outline_hover_ring()
	_draw_roster()
	_draw_spines()
	# Labels above city crosses: a brass cross over near-white text buried the
	# name (B6), and text is what the cross points at. _refresh_markers() is a
	# state read, not a draw, so the pins still draw last and stay on top.
	_draw_cities()
	_draw_labels()
	_refresh_markers()
	_draw_markers()
	MapPlants.draw_plants(self, _state, func(lon: float, lat: float) -> Vector2:
		return _lonlat_to_screen(lon, lat))
	# Frontmost: a readout is text the player asked for with the cursor.
	_draw_outline_readout()
	if _placing:
		# A brass reticle at the cursor. The state's own material marks what is
		# waiting on the player -- V2.1c's rule, reused rather than joined by a
		# second visual language for "we are waiting on you".
		var at := get_local_mouse_position()
		draw_arc(at, 14.0, 0.0, TAU, 32, UiTheme.ACCENT, 1.5)
		draw_line(at - Vector2(20, 0), at + Vector2(20, 0), UiTheme.ACCENT, 1.0)
		draw_line(at - Vector2(0, 20), at + Vector2(0, 20), UiTheme.ACCENT, 1.0)


## V4.10a. How much of the ground is drawn over the photograph at this zoom: 0
## at globe view, 1 at depth, the derived band between (MapGround.band_alpha).
## 0 when the asset is missing, which is the whole fresh-clone fallback.
func ground_alpha() -> float:
	if _ground == null:
		return 0.0
	return MapGround.band_alpha(_zoom, BASE_SCALE)


## V4.10b. The border kind a nation or outline strokes with: its roster grade.
func border_kind_of(id: String) -> String:
	return String(_border_kind.get(id, "outline"))


## The kind's line colour on whatever ground is under it right now.
func border_color(kind: String) -> Color:
	var k: Dictionary = BORDER_KINDS[kind]
	return (k["photo"] as Color).lerp(k["paper"], ground_alpha())


func _draw_raster() -> void:
	var a := ground_alpha()
	# A whole-screen photograph under an opaque ground is fill nobody sees: skip
	# it once the band is complete and the view sits inside the ground's opaque
	# core (its bounds less the baked feather). Anywhere else -- mid-band, or
	# panned to where the ground feathers out -- the photograph is what shows
	# through, so it draws.
	var core := _ground_bounds.grow(-_ground_feather_deg)
	if not (a >= 1.0 and core.encloses(visible_lonlat_rect())):
		if _texture == null:
			draw_rect(Rect2(Vector2.ZERO, size), SEA)
		else:
			var top_left := _lonlat_to_screen(MapRaster.LON_MIN, MapRaster.LAT_MAX)
			var bottom_right := _lonlat_to_screen(MapRaster.LON_MAX, MapRaster.LAT_MIN)
			draw_texture_rect(_texture, Rect2(top_left, bottom_right - top_left), false)
	if a > 0.0:
		var g_tl := _lonlat_to_screen(_ground_bounds.position.x, _ground_bounds.end.y)
		var g_br := _lonlat_to_screen(_ground_bounds.end.x, _ground_bounds.position.y)
		draw_texture_rect(_ground, Rect2(g_tl, g_br - g_tl), false, Color(1.0, 1.0, 1.0, a))


## Outlines only, no fill: the landmass is already underneath -- in the
## photograph at globe view, in the baked ground at depth (V4.10a), whose land
## mask was rasterised from these same rings -- and what a border adds is the
## political line neither can show.
func _draw_world_borders() -> void:
	var outline_color := border_color("outline")
	var outline_width := float(BORDER_KINDS["outline"]["width"])
	var view := visible_lonlat_rect()
	var padded := view.grow(CULL_PAD_PX / (BASE_SCALE * _zoom))
	for id in _world_polygons.keys():
		var polys: Array = _world_polygons[id]
		var boxes: Array = _ring_boxes_world[id]
		for r in range(polys.size()):
			var box: Rect2 = boxes[r]
			if box.size.x < 0.0 or not padded.intersects(box):
				continue
			var ring: PackedVector2Array = polys[r]
			var screen_points := PackedVector2Array()
			for p in ring:
				screen_points.append(Vector2(p.x * _kx + _ox, p.y * _ky + _oy))
			screen_points.append(screen_points[0])
			draw_polyline(screen_points, outline_color, outline_width)


## V4.11c. The hovered outline restroked brighter, in the world pass's slot so the
## roster still draws over a shared coastline.
func _draw_outline_hover_ring() -> void:
	if _hovered_outline == "" or not _world_polygons.has(_hovered_outline):
		return
	# V4.10b: the outline kind's colour on the ground under it, at the hover
	# strength. The fixed pale blue was right over the photograph and LIGHTER than
	# the resting ink line over paper -- the hover cue reversed at depth.
	var hover_color := Color(border_color("outline"), WORLD_BORDER_HOVER.a)
	for ring: PackedVector2Array in _world_polygons[_hovered_outline]:
		if ring.size() < 2:
			continue
		var screen_points := PackedVector2Array()
		for p in ring:
			screen_points.append(Vector2(p.x * _kx + _ox, p.y * _ky + _oy))
		screen_points.append(screen_points[0])
		draw_polyline(screen_points, hover_color, WORLD_BORDER_HOVER_WIDTH)


## V4.11c. Two lines beside the cursor -- the outline's name, then what it supplies
## the world (MapOutlines owns the text) -- on a small HUD plate: the hull body and
## the brass hairline on the TOP edge only (the U5a signature). The first cut used
## the city label's bare shadowed text and the windowed screenshot showed why a
## plate: over snow and the roster's own labels the line could not be read.
## Clamped inside the control so a hover near the right edge still reads.
func _draw_outline_readout() -> void:
	if _hovered_outline == "" or _loader == null:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var lines := [
		[MapOutlines.name_of(_loader, _hovered_outline), UiTheme.SIZE_SMALL],
		[MapOutlines.profile_of(_loader, _hovered_outline), UiTheme.SIZE_MICRO],
	]
	var width := 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(line[1])).x)
	var plate_size := Vector2(width + 2.0 * OUTLINE_READOUT_PAD, OUTLINE_READOUT_GAP * lines.size() + OUTLINE_READOUT_PAD)
	var corner := _hover_screen + OUTLINE_READOUT_OFFSET
	corner.x = clampf(corner.x, 4.0, maxf(4.0, size.x - plate_size.x - 4.0))
	corner.y = clampf(corner.y, 4.0, maxf(4.0, size.y - plate_size.y - 4.0))
	draw_rect(Rect2(corner, plate_size), OUTLINE_READOUT_PLATE)
	draw_line(corner, corner + Vector2(plate_size.x, 0.0), UiTheme.ACCENT, 1.0)
	var at := corner + Vector2(OUTLINE_READOUT_PAD, OUTLINE_READOUT_GAP - 2.0)
	for i in lines.size():
		var text := String(lines[i][0])
		var font_size := int(lines[i][1])
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTheme.TEXT if i == 0 else UiTheme.TEXT_DIM)
		at.y += OUTLINE_READOUT_GAP


## MapLayers.fills() behind the month-keyed memo the `_fill_key` paragraph argues.
## Only the commodity layers take the memo; everything else is derived fresh, so
## this is a fast path and never a new contract for the other layers.
func _layer_fills(viewer: String) -> Dictionary:
	if _layer != MapLayers.PRODUCTION and _layer != MapLayers.IMPORT_DEPENDENCY:
		return MapLayers.fills(_layer, _state, viewer, _polygons.keys())
	var month := -1
	if _state != null:
		month = int(_state.year) * 12 + int(_state.month)
	var key := {
		"state": _state,
		"month": month,
		"layer": _layer,
		"viewer": viewer,
	}
	if _fill_key != key:
		_fill_key = key
		_fill_cache = MapLayers.fills(_layer, _state, viewer, _polygons.keys())
	return _fill_cache


## The fills as drawn this frame: the layer's own, or mid-crossfade each
## nation's colour on its way from what was shown before the toggle.
func _shown_fills(viewer: String) -> Dictionary:
	var fills: Dictionary = _layer_fills(viewer)
	if _fill_from.is_empty() or _layer_blend >= 1.0:
		return fills
	var out := {}
	for id in fills.keys():
		var to: Color = fills[id]
		out[id] = (_fill_from[id] as Color).lerp(to, _layer_blend) if _fill_from.has(id) else to
	return out


func _draw_roster() -> void:
	var view := visible_lonlat_rect()
	var padded := view.grow(CULL_PAD_PX / (BASE_SCALE * _zoom))
	var viewer := viewer_id()

	# One pass for every fill on the layer, rather than one call per nation.
	# What that buys is a trade-layer measurement: swatch() reads the viewer's
	# partner vector twice per nation, so the per-nation form paid fifty-eight
	# Trade.weights() builds to fill twenty-nine countries. See MapLayers.fills().
	# A fill depends on the layer, the state and the viewer and on NOTHING the
	# camera does, so hoisting it out of this loop cannot change when a colour
	# updates -- it is still derived once per re-record, exactly as before. The
	# memo below extends that same argument across the re-records that share a
	# month (`_fill_key`), because the state cannot move between them.
	var fills: Dictionary = _shown_fills(viewer)
	# Border colours once per re-record, not per ring: they move with the zoom
	# band only, and every ring of a kind shares one.
	var kind_colors := {}
	for kind in BORDER_KINDS.keys():
		kind_colors[kind] = border_color(kind)
	var regional_color: Color = kind_colors["regional"]
	var regional_width := float(BORDER_KINDS["regional"]["width"])

	for id in _polygons.keys():
		var color: Color = fills[id]

		# Brass for the nation the player governs, the heaviest line at hover
		# width under the cursor, its kind's line otherwise. The home mark wins a
		# collision: hovering your own country should not stop it being yours,
		# and it carries no value on either data layer for the readout to
		# disagree with. Hover takes the playable kind's colour rather than pure
		# white since V4.10b: white was right over the photograph and is the
		# weakest line there is over paper; the playable colour is near-white at
		# globe view and ink at depth.
		var kind := border_kind_of(String(id))
		var stroke: Color = kind_colors[kind]
		var width := float(BORDER_KINDS[kind]["width"])
		if id == _hovered_id:
			stroke = Color(kind_colors["playable"], 1.0)
			width = HOVER_WIDTH
		if MapLayers.is_viewer(viewer, id):
			stroke = UiTheme.ACCENT
			width = HOME_WIDTH

		# V2.2b, finer map geometry. The nation is still FILLED from the 1:50m
		# roster outline first, as a same-hue base under the 1:10m region fills:
		# GISCO and Natural Earth disagree at the coast by a few kilometres, which
		# is a few pixels at MAX_ZOOM, and the base turns that disagreement from a
		# hole in the country into a seam the eye cannot find. What the player
		# sees as the fill is the regions.
		var polys: Array = _polygons[id]
		var boxes: Array = _ring_boxes_roster[id]
		for r in range(polys.size()):
			var box: Rect2 = boxes[r]
			if box.size.x < 0.0 or not padded.intersects(box):
				continue
			var ring: PackedVector2Array = polys[r]
			var base_points := PackedVector2Array()
			for p in ring:
				base_points.append(Vector2(p.x * _kx + _ox, p.y * _ky + _oy))
			draw_colored_polygon(base_points, color)

		# Region fills first, ALL of them, then ALL the hairlines. The two-pass
		# order is structural rather than stylistic: with holes dropped, a host
		# region's outer ring covers its enclave, and whether the enclave's own
		# boundary survives depends entirely on draw order -- the roster carries
		# one enclave of EACH direction (Berlin outpopulates its host Brandenburg,
		# Bremen is a third of its host Niedersachsen), so no fill-and-stroke
		# order renders both, and only drawing every line after every fill does.
		# In the same hue the covered fills are invisible; only the lines show.
		var region_rings: Array = []
		for region in _loader.regions.get(id, []):
			var region_ring_arrays: Array = _loader.region_features.get(region.id, [])
			var region_boxes: Array = _ring_boxes_region.get(region.id, [])
			for ri in range(region_ring_arrays.size()):
				var ring: PackedVector2Array = region_ring_arrays[ri]
				# The cull gates the FILL, and region_rings is built only from
				# rings the cull let through -- so the hairline loop below
				# cannot disagree with it, which is how the two-pass enclave
				# draw survives culling: any ring drawn at all is drawn in
				# both passes.
				var rbox: Rect2 = region_boxes[ri] if ri < region_boxes.size() else Rect2(0, 0, -1, -1)
				if rbox.size.x < 0.0 or not padded.intersects(rbox):
					continue
				var region_points := PackedVector2Array()
				for p in ring:
					region_points.append(Vector2(p.x * _kx + _ox, p.y * _ky + _oy))
				draw_colored_polygon(region_points, color)
				region_rings.append(region_points)
		for region_points: PackedVector2Array in region_rings:
			var closed := region_points.duplicate()
			closed.append(region_points[0])
			draw_polyline(closed, regional_color, regional_width)

		# The national stroke last, from the 1:50m outline it has always used:
		# the bright line is the one that says which ten answer a click, and it
		# belongs to the nation rather than to any region of it.
		for r in range(polys.size()):
			var box: Rect2 = boxes[r]
			if box.size.x < 0.0 or not padded.intersects(box):
				continue
			var ring: PackedVector2Array = polys[r]
			var stroke_points := PackedVector2Array()
			for p in ring:
				stroke_points.append(Vector2(p.x * _kx + _ox, p.y * _ky + _oy))
			var closed := stroke_points.duplicate()
			closed.append(stroke_points[0])
			draw_polyline(closed, stroke, width)


## The spine pass -- V3.4, between the roster fills and the labels. Over the land
## it crosses and under every name and mark, which is where a road belongs on a
## political map: it is the thing the marks sit ON.
##
## GATED ON CITY_MIN_ZOOM, the same number _draw_cities() uses rather than a
## second one. A spine ends on two principal cities, so a spine drawn while
## neither glyph is drawn is a line from nowhere to nowhere. Nothing was swept
## for this -- the reason is structural, not a volume measurement, which is the
## difference from the sweep that set CITY_MIN_POP.
##
## Culled in DEGREES against the view before anything is projected, which is
## docs/map-platform-model.md §7's "cull first, transform second" in its own
## words. The list is static content, so reading live lon/lat bounds carries no
## staleness class -- the same argument _ring_reaches_view() already states.
func _draw_spines() -> void:
	_spines_drawn = 0
	if _zoom < CITY_MIN_ZOOM:
		return
	var pad := CULL_PAD_PX / (BASE_SCALE * _zoom)
	var view := visible_lonlat_rect().grow(pad)
	_spines_drawn = MapNetwork.draw_spines(
		self, _spines, view,
		func(lon: float, lat: float) -> Vector2: return _lonlat_to_screen(lon, lat),
		size, ground_alpha()
	)


## Every permanent name on the map, nation and (since V4.10b) city, drawn from
## one placement -- see _place_labels() for who is named and in what order.
func _draw_labels() -> void:
	if not _labels_enabled:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := UiTheme.SIZE_MICRO
	var ascent := font.get_ascent(font_size)
	for p in _place_labels():
		var at: Vector2 = (p["rect"] as Rect2).position + Vector2(0.0, ascent)
		# An outline halo rather than the old 1px offset shadow: over a satellite
		# image the contrast varies from Alpine snow to North Sea, and over the
		# paper ground (V4.10a) a light name needs its dark edge just as much. One
		# style for nation and city names: the placer, not the paint, ranks them.
		draw_string_outline(font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_OUTLINE_PX, LABEL_OUTLINE_COLOR)
		draw_string(font, at, String(p["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)


func _label_zoom(tier: int) -> float:
	match tier:
		1:
			return LABEL_ZOOM_T1
		2:
			return LABEL_ZOOM_T2
	return LABEL_ZOOM_T3


func _measure_text(font: Font, font_size: int, text: String) -> Vector2:
	var key := "%d|%s" % [font_size, text]
	var cached = _text_size.get(key)
	if cached != null:
		return cached
	var sz := Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x,
		font.get_height(font_size))
	_text_size[key] = sz
	return sz


## V4.10b. ONE placement over every name on screen -- the roster's nation names
## first (a country's name outranks every city in it), then each on-screen city
## whose tier is named at this zoom, ranked tier, population, id (MapLabels'
## total order). Every drawn glyph is an obstacle a name may not cover, and the
## hovered city is left out: its hover label in _draw_cities() is the one name it
## gets. Callable outside _draw() so the tests and tools/label_probe.gd read the
## same placement the frame draws.
##
## max_tier >= 1 is the probe's override: name tiers 1..max_tier at ANY zoom from
## CITY_MIN_ZOOM, ignoring LABEL_ZOOM_T*, which is how the band was measured.
##
## The only "only the roster is named" rule from U5b survives: outlines get no
## name. Naming the countries the player cannot click would say the opposite of
## what the outline grade is for.
func _place_labels(max_tier := -1) -> Array:
	_last_placed = []
	_label_onscreen = {1: 0, 2: 0, 3: 0}
	var font := get_theme_default_font()
	if font == null:
		return _last_placed
	var font_size := UiTheme.SIZE_MICRO
	var view := Rect2(Vector2.ZERO, size)
	var measure := func(text: String) -> Vector2: return _measure_text(font, font_size, text)
	var candidates: Array = []
	var blocked: Array = []
	if _zoom >= LABEL_MIN_ZOOM:
		for id in _labels.keys():
			var entry: Dictionary = _labels[id]
			var lonlat: Vector2 = entry["pos"]
			candidates.append({
				"id": "nation:%s" % id, "text": entry["text"],
				"at": _lonlat_to_screen(lonlat.x, lonlat.y), "gap": 0.0,
				"rank": [0, 0.0 if border_kind_of(String(id)) == "playable" else 1.0, String(id)],
				"anchors": ["center"], "over_marks": true,
			})
	if _zoom >= CITY_MIN_ZOOM:
		# A tier that is neither named at this zoom nor an obstacle (tier 3, by
		# the band) contributes nothing, so it is skipped BEFORE it is projected:
		# ~1270 of 1373 cities, and the projection was most of the pass's cost.
		# Tiers 1-2 always walk (they are obstacles); the probe's override walks
		# exactly what it asked to name.
		var top_tier := 3
		if max_tier >= 1:
			top_tier = maxi(max_tier, 2)
		elif _zoom < _label_zoom(3):
			top_tier = 2
		for city in _cities:
			var tier := int(city.get("tier", 3))
			if tier > top_tier:
				continue
			var lonlat: Vector2 = city["lonlat"]
			var at := _lonlat_to_screen(lonlat.x, lonlat.y)
			if not view.has_point(at):
				continue
			var glyph := MapGlyphs.glyph_rect(at, city, tier)
			# Only tiers 1-2 are obstacles. With every on-screen glyph blocked, a
			# placement over the Ruhr at the opening fit inserted ~1300 rects and
			# cost 25-45 ms per re-record (tools/label_probe.gd, 2026-10-18) --
			# paid on every frame of a drag. A tier-3 cross is 2-4 px and a
			# haloed name over it still reads; a capital's ring or a big city's
			# cross under a name does not.
			if tier <= 2:
				blocked.append(glyph)
			var named := tier <= max_tier if max_tier >= 1 else _zoom >= _label_zoom(tier)
			if not named:
				continue
			_label_onscreen[tier] = int(_label_onscreen[tier]) + 1
			var city_id := String(city["city_id"])
			if city_id == _hovered_city:
				continue
			candidates.append({
				"id": "city:%s" % city_id, "text": String(city["name"]), "at": at,
				"gap": glyph.size.x * 0.5 + MapLabels.PAD_PX,
				"rank": [tier, -float(city["population"]), city_id],
			})
	var reserved: Array = []
	var hover_rect := _hover_label_rect()
	if hover_rect.size.x > 0.0:
		reserved.append(hover_rect)
	_last_placed = MapLabels.place(candidates, blocked, view, measure, reserved)
	return _last_placed


## The hovered city's full label box -- the same text, offset and size
## _draw_cities() draws it with -- or Rect2() when no city is hovered (or the map
## is above CITY_MIN_ZOOM's cut, where no city is drawn). Reserved in the
## placement so no permanent name lands on the text the player pointed at.
func _hover_label_rect() -> Rect2:
	if _hovered_city == "" or _zoom < CITY_MIN_ZOOM:
		return Rect2()
	var font := get_theme_default_font()
	if font == null:
		return Rect2()
	for city in _cities:
		if String(city["city_id"]) != _hovered_city:
			continue
		var font_size := UiTheme.SIZE_MICRO
		var lonlat: Vector2 = city["lonlat"]
		var at := _lonlat_to_screen(lonlat.x, lonlat.y)
		var text: String = MapCities.label_of(city)
		var sz := _measure_text(font, font_size, text)
		var text_at := at + MapCities.label_offset(MapCities.radius_of(city)) - Vector2(sz.x / 2.0, 0.0)
		# text_at is the baseline; the box runs from the ascent above it, and the
		# drop shadow's 1 px is inside the placer's own 2 px pad.
		return Rect2(Vector2(text_at.x, text_at.y - font.get_ascent(font_size)), sz)
	return Rect2()


## The fifth pass, behind the markers -- V2.2b, and the tier doc's *"brass
## crosses onto the map for the first time and only for where people are"*.
## What a cross looks like is map_cities.gd's business, the way a fill is
## map_layers.gd's and a marker is map_markers.gd's; this walks the list and
## puts the glyph on the screen. Behind the markers on purpose: a project site
## is usually IN a city, and the rarer, more specific glyph goes in front.
##
## Gated on CITY_MIN_ZOOM, where the marker pass is not: five sites on France are
## the whole point of that layer at any zoom, while 581 crosses at the Europe fit
## are noise by the register's own volume clause. The FULL label (name,
## population, unrest) is drawn here on hover; since V4.10b a city whose tier is
## named at this zoom also carries a permanent name, placed by _place_labels()
## so that names never collide -- the reason they used to be hover-only.
func _draw_cities() -> void:
	if _zoom < CITY_MIN_ZOOM:
		return
	var font := get_theme_default_font()
	for city in _cities:
		var lonlat: Vector2 = city["lonlat"]
		var at := _lonlat_to_screen(lonlat.x, lonlat.y)
		var color: Color = MapCities.color_of(city)
		var radius: float = MapCities.radius_of(city)
		var hovered: bool = String(city["city_id"]) == _hovered_city
		var width: float = MapCities.HOVER_WIDTH if hovered else MapCities.WIDTH

		# V3.1. Culled on the SCREEN point because the population it sizes the
		# glyph with is live state -- two shares times a head count, V2.6a's
		# lesson about caching live quantities. The pad covers the cross's
		# arms, an unrest ring and the stroke, so a glyph partly over the edge
		# still draws whole. The hit test is untouched: a click cannot land
		# off-screen, so an off-screen cross being a target costs nothing.
		var cull_pad: float = radius + MapCities.ring_radius(city) + CULL_PAD_PX
		if at.x < -cull_pad or at.x > size.x + cull_pad:
			continue
		if at.y < -cull_pad or at.y > size.y + cull_pad:
			continue

		# V4.10b: the mark by tier (MapGlyphs) -- V2.2b's cross for tiers 2 and 3,
		# thinner for 3, ringed for a capital. Size is still radius_of().
		MapGlyphs.draw_glyph(self, at, city, int(city.get("tier", 3)), width)

		# V2.6b1. A ring around the cross where the country's demonstration is. It is
		# NOT a fifth map layer and NOT a sixth draw pass: a LAYERS entry chooses a
		# per-nation roster FILL one at a time, and this is a mark on a glyph that is
		# already here -- so tests/test_map_markers.gd's pin at four stands, and the
		# hit test is untouched, which keeps _city_at_screen_point() answering for
		# exactly one thing.
		# One ring either way: a demonstration and a campaign meeting landing on the
		# same city would be two concentric arcs of noise, and the label already says
		# which one it is (unrest's clause wins it).
		if MapCities.is_unrest(city) or MapCities.is_campaign(city):
			draw_arc(
				at, MapCities.ring_radius(city), 0.0, TAU, MapCities.RING_POINTS,
				color, MapCities.RING_WIDTH
			)

		if not hovered or font == null:
			continue
		var text: String = MapCities.label_of(city)
		var font_size := UiTheme.SIZE_MICRO
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var text_at := at + MapCities.label_offset(radius) - Vector2(text_width / 2.0, 0.0)
		# The label pass's drop shadow, for the same reason: over a satellite
		# photograph the contrast runs from Alpine snow to the North Sea.
		draw_string(
			font, text_at + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, MapCities.LABEL_SHADOW
		)
		draw_string(
			font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, MapCities.LABEL_COLOR
		)


## The sixth and frontmost pass -- U6c (fifth until V2.2b's crosses arrived).
## What a marker looks like is
## map_markers.gd's business, the way a fill is map_layers.gd's; this walks the
## list and puts the glyph on the screen.
##
## No zoom threshold, where a label has one. Five dots on France are five dots at
## any scale and are the whole point of the layer, so what gets dropped when they
## crowd is their NAMES -- which is why the text is drawn on hover alone rather
## than under LABEL_MIN_ZOOM's rule.
func _draw_markers() -> void:
	var font := get_theme_default_font()
	for marker in _markers:
		var lonlat: Vector2 = marker["lonlat"]
		var at := _lonlat_to_screen(lonlat.x, lonlat.y)
		var color: Color = MapMarkers.color_of(marker)
		var hovered: bool = String(marker["project_id"]) == _hovered_project
		var width: float = MapMarkers.HOVER_RING_WIDTH if hovered else MapMarkers.RING_WIDTH

		if MapMarkers.is_filled(marker):
			draw_circle(at, MapMarkers.RADIUS, color)
		draw_arc(at, MapMarkers.RADIUS, 0.0, TAU, 24, color, width)

		if not hovered or font == null:
			continue
		var text: String = MapMarkers.label_of(marker, _loader)
		var font_size := UiTheme.SIZE_MICRO
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var text_at := at + MapMarkers.LABEL_OFFSET - Vector2(text_width / 2.0, 0.0)
		# The label pass's drop shadow, for the same reason: over a satellite
		# photograph the contrast runs from Alpine snow to the North Sea.
		draw_string(
			font, text_at + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, MapMarkers.LABEL_SHADOW
		)
		draw_string(
			font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, MapMarkers.LABEL_COLOR
		)
