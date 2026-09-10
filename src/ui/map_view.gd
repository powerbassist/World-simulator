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
## from `_world_polygons` and hit-tested by nothing -- `_nation_at_lonlat`
## iterates `_polygons` alone, so "you cannot click Poland" is structural rather
## than a filter somewhere that could be forgotten.
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
const MapRaster = preload("res://src/ui/map_raster.gd")
const MapLayers = preload("res://src/ui/map_layers.gd")
const MapMarkers = preload("res://src/ui/map_markers.gd")
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

## The sea, now only a fallback. Kept rather than deleted with the raster's
## arrival because MapRaster.texture() returning null is a declared outcome, not
## an error: a clone missing the 2.5 MB asset should look plainer, not open onto a
## black void with ten countries floating in it.
const SEA := Color(0.043, 0.075, 0.129)

## Coastlines of the ten, and a quieter line for the outlines of everything else.
## The world layer is deliberately dimmer than the roster: it is context, and a
## border the player cannot cross should not compete with one they can. The
## roster's line is bright because over a satellite photograph it is doing the
## work the fill used to do -- saying which ten answer a click.
const COAST := Color(0.95, 0.96, 0.99, 0.88)
const WORLD_BORDER := Color(0.71, 0.78, 0.86, 0.22)
const WORLD_BORDER_WIDTH := 1.0

## Hover and the viewer's own nation both move the *stroke* rather than the fill,
## and on a data layer that is not a style choice. U5b's hover lifted the fill
## toward the accent by 0.35, which on the political layer says "this one is under
## the cursor" and on a relations layer says a pair is warmer than it is -- the
## one place in the interface where pointing at a number would change it. The
## outline is already what separates the roster (see COAST), so it is the honest
## carrier for both marks.
## Hover is width alone, not brightness: COAST is already near-white, so a
## brighter white adds nothing and brass is spoken for by the home mark. 3.0 was
## legible in a frame only just, hence 4.0.
const COAST_WIDTH := 1.5
const HOVER_WIDTH := 4.0
const HOME_WIDTH := 2.5

## V2.2b: the hairline between one region and the next, inside the national
## outline. It sits between WORLD_BORDER and COAST in brightness on purpose:
## it is structure inside the roster, not context outside it, but it must stay
## quiet enough that the bright national stroke remains the one line saying
## which ten answer a click.
const REGION_BORDER := Color(0.71, 0.78, 0.86, 0.35)
const REGION_BORDER_WIDTH := 1.0

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
const LABEL_SHADOW := Color(0.0, 0.0, 0.0, 0.65)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


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
	_layer = resolved
	queue_redraw()


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


func _draw() -> void:
	_fit_zoom()
	_draw_raster()
	_draw_world_borders()
	_draw_roster()
	_draw_spines()
	_draw_labels()
	_draw_cities()
	_refresh_markers()
	_draw_markers()
	MapPlants.draw_plants(self, _state, func(lon: float, lat: float) -> Vector2:
		return _lonlat_to_screen(lon, lat))
	if _placing:
		# A brass reticle at the cursor. The state's own material marks what is
		# waiting on the player -- V2.1c's rule, reused rather than joined by a
		# second visual language for "we are waiting on you".
		var at := get_local_mouse_position()
		draw_arc(at, 14.0, 0.0, TAU, 32, UiTheme.ACCENT, 1.5)
		draw_line(at - Vector2(20, 0), at + Vector2(20, 0), UiTheme.ACCENT, 1.0)
		draw_line(at - Vector2(0, 20), at + Vector2(0, 20), UiTheme.ACCENT, 1.0)


func _draw_raster() -> void:
	if _texture == null:
		draw_rect(Rect2(Vector2.ZERO, size), SEA)
		return
	var top_left := _lonlat_to_screen(MapRaster.LON_MIN, MapRaster.LAT_MAX)
	var bottom_right := _lonlat_to_screen(MapRaster.LON_MAX, MapRaster.LAT_MIN)
	draw_texture_rect(_texture, Rect2(top_left, bottom_right - top_left), false)


## Outlines only, no fill: the landmass is already in the photograph underneath,
## and what a border adds is the political line the photograph cannot show.
func _draw_world_borders() -> void:
	var view := visible_lonlat_rect()
	for id in _world_polygons.keys():
		for ring: PackedVector2Array in _world_polygons[id]:
			if not _ring_reaches_view(ring, view):
				continue
			var screen_points := PackedVector2Array()
			for p in ring:
				screen_points.append(_lonlat_to_screen(p.x, p.y))
			screen_points.append(screen_points[0])
			draw_polyline(screen_points, WORLD_BORDER, WORLD_BORDER_WIDTH)


func _draw_roster() -> void:
	var view := visible_lonlat_rect()
	var viewer := viewer_id()

	# One pass for every fill on the layer, rather than one call per nation.
	# What that buys is a trade-layer measurement: swatch() reads the viewer's
	# partner vector twice per nation, so the per-nation form paid fifty-eight
	# Trade.weights() builds to fill twenty-nine countries. See MapLayers.fills().
	# A fill depends on the layer, the state and the viewer and on NOTHING the
	# camera does, so hoisting it out of this loop cannot change when a colour
	# updates -- it is still derived once per re-record, exactly as before.
	var fills := MapLayers.fills(_layer, _state, viewer, _polygons.keys())

	for id in _polygons.keys():
		var color: Color = fills[id]

		# Brass for the nation the player governs, thicker white under the cursor,
		# the plain coastline otherwise. The home mark wins a collision: hovering
		# your own country should not stop it being yours, and it carries no value
		# on either data layer for the readout to disagree with.
		var stroke := COAST
		var width := COAST_WIDTH
		if id == _hovered_id:
			stroke = Color(1.0, 1.0, 1.0, 1.0)
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
		for ring: PackedVector2Array in _polygons[id]:
			if not _ring_reaches_view(ring, view):
				continue
			var base_points := PackedVector2Array()
			for p in ring:
				base_points.append(_lonlat_to_screen(p.x, p.y))
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
			for ring: PackedVector2Array in _loader.region_features.get(region.id, []):
				# The cull gates the FILL, and region_rings is built only from
				# rings the cull let through -- so the hairline loop below
				# cannot disagree with it, which is how the two-pass enclave
				# draw survives culling: any ring drawn at all is drawn in
				# both passes.
				if not _ring_reaches_view(ring, view):
					continue
				var region_points := PackedVector2Array()
				for p in ring:
					region_points.append(_lonlat_to_screen(p.x, p.y))
				draw_colored_polygon(region_points, color)
				region_rings.append(region_points)
		for region_points: PackedVector2Array in region_rings:
			var closed := region_points.duplicate()
			closed.append(region_points[0])
			draw_polyline(closed, REGION_BORDER, REGION_BORDER_WIDTH)

		# The national stroke last, from the 1:50m outline it has always used:
		# the bright line is the one that says which ten answer a click, and it
		# belongs to the nation rather than to any region of it.
		for ring: PackedVector2Array in _polygons[id]:
			if not _ring_reaches_view(ring, view):
				continue
			var stroke_points := PackedVector2Array()
			for p in ring:
				stroke_points.append(_lonlat_to_screen(p.x, p.y))
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
		size
	)


## The roster only. Naming the ~160 countries the player cannot click would say
## the opposite of what U5b is for -- the unlabelled ones are the edge of the
## game, and leaving them unnamed is how that edge is visible without a click
## that leads nowhere.
func _draw_labels() -> void:
	if _zoom < LABEL_MIN_ZOOM:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := UiTheme.SIZE_MICRO
	for id in _labels.keys():
		var entry: Dictionary = _labels[id]
		var lonlat: Vector2 = entry["pos"]
		var text: String = entry["text"]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at := _lonlat_to_screen(lonlat.x, lonlat.y) - Vector2(width / 2.0, 0.0)
		# One-pixel drop shadow rather than a plate behind the text: over a
		# satellite image the contrast varies from Alpine snow to North Sea, and a
		# shadow holds legibility on both without putting a box on the map.
		draw_string(font, at + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_SHADOW)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)


## The fifth pass, behind the markers -- V2.2b, and the tier doc's *"brass
## crosses onto the map for the first time and only for where people are"*.
## What a cross looks like is map_cities.gd's business, the way a fill is
## map_layers.gd's and a marker is map_markers.gd's; this walks the list and
## puts the glyph on the screen. Behind the markers on purpose: a project site
## is usually IN a city, and the rarer, more specific glyph goes in front.
##
## Gated on CITY_MIN_ZOOM, where the marker pass is not: five sites on France are
## the whole point of that layer at any zoom, while 581 crosses at the Europe fit
## are noise by the register's own volume clause. The name is drawn on hover
## alone, for labels' reason -- at this zoom the crosses are dense enough that
## permanent names would collide, and a cross that needs its name asks for it
## with the cursor.
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

		# A cross rather than a dot: the one glyph left that says *people* rather
		# than *thing*, and it stays legible from 2px to 12px where a ring would
		# close up. The arms are the radius on the diagonal, so two cities a few
		# pixels apart read as two marks, the bigger of them the bigger.
		var arm := Vector2(radius, 0.0).rotated(PI / 4.0)
		draw_line(at - arm, at + arm, color, width)
		draw_line(at - Vector2(arm.x, -arm.y), at + Vector2(arm.x, -arm.y), color, width)

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
