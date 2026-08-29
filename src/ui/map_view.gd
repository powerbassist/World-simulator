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

## V2.2b. Built ONCE in setup() rather than per draw, the deliberate opposite of
## _markers: the register is static content, and the only live quantity under a
## glyph is the population its radius ranks on -- a decade of demographic drift
## moves no city past another, so rebuilding per draw would buy nothing. Ascending
## population, so the largest draws last and wins an overlap; see MapCities.
var _cities: Array = []
var _hovered_city := ""

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
## discipline: set just under the opening Europe fit (which lands near 2.1 on
## 1080p), so the crosses are there from the moment the game starts and clear
## off as the player pulls back to the globe. That is the reading the register's
## volume clause was measured for -- *"V2.2b draws by rank and the roster at the
## opening fit is ~1000 px wide"* -- so a threshold above the opening fit would
## ship 581 cities the default frame never shows. Names stay on hover alone,
## where the labels at least get the opening fit. The HIT test reads the same
## gate, so a glyph that is not drawn is never a target.
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

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var n = loader.nations[id]
		var polys: Array = loader.geo_features.get(n.geo_id, [])
		_polygons[id] = polys
		if loader.label_points.has(n.geo_id):
			_labels[id] = {
				"pos": loader.label_points[n.geo_id],
				"text": n.nation_name.to_upper(),
			}

	_world_polygons = loader.world_features
	_texture = MapRaster.texture()

	# Static content, so once rather than per draw -- see the field. Built here for
	# _refresh_markers()'s reason: a hit test can happen before the first frame is
	# drawn, and an empty list would answer it with "nothing here".
	_cities = MapCities.cities(_loader, _state)

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
## "" if none does. First match wins -- Europe's ten nations here don't overlap.
func _nation_at_lonlat(pt: Vector2) -> String:
	for id in _polygons.keys():
		for ring: PackedVector2Array in _polygons[id]:
			if ring.size() >= 3 and Geometry2D.is_point_in_polygon(pt, ring):
				return id
	return ""


func nation_at_screen_point(screen_pos: Vector2) -> String:
	return _nation_at_lonlat(_screen_to_lonlat(screen_pos))


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
				_dragging = true
				_drag_moved = 0.0
				_last_mouse_pos = event.position
			else:
				if _dragging and _drag_moved < DRAG_THRESHOLD:
					# Markers first, cities next, and a hit stops there: a marker
					# or a cross sits on top of the nation that owns it, so falling
					# through would open two windows on one click.
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
	_draw_labels()
	_draw_cities()
	_refresh_markers()
	_draw_markers()


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
	for id in _world_polygons.keys():
		for ring: PackedVector2Array in _world_polygons[id]:
			if ring.size() < 3:
				continue
			var screen_points := PackedVector2Array()
			for p in ring:
				screen_points.append(_lonlat_to_screen(p.x, p.y))
			screen_points.append(screen_points[0])
			draw_polyline(screen_points, WORLD_BORDER, WORLD_BORDER_WIDTH)


func _draw_roster() -> void:
	var viewer := viewer_id()
	for id in _polygons.keys():
		var color := MapLayers.color_for(_layer, _state, viewer, id)

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
			if ring.size() < 3:
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
				if ring.size() < 3:
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
			if ring.size() < 3:
				continue
			var stroke_points := PackedVector2Array()
			for p in ring:
				stroke_points.append(_lonlat_to_screen(p.x, p.y))
			var closed := stroke_points.duplicate()
			closed.append(stroke_points[0])
			draw_polyline(closed, stroke, width)


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

		# A cross rather than a dot: the one glyph left that says *people* rather
		# than *thing*, and it stays legible from 2px to 12px where a ring would
		# close up. The arms are the radius on the diagonal, so two cities a few
		# pixels apart read as two marks, the bigger of them the bigger.
		var arm := Vector2(radius, 0.0).rotated(PI / 4.0)
		draw_line(at - arm, at + arm, color, width)
		draw_line(at - Vector2(arm.x, -arm.y), at + Vector2(arm.x, -arm.y), color, width)

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
