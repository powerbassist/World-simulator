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
## Four layers, back to front: the satellite raster, the outlines of every country
## the game does not simulate, the ten it does, and their labels. The middle layer
## is drawn from `_world_polygons` and hit-tested by nothing -- `_nation_at_lonlat`
## iterates `_polygons` alone, so "you cannot click Poland" is structural rather
## than a filter somewhere that could be forgotten.
##
## Hit-testing, pan/zoom and framing are exposed as plain methods
## (nation_at_screen_point, pan_by, zoom_by, center_on_lonlat,
## visible_lonlat_rect) rather than only reachable through _gui_input, so a
## headless test and the minimap can drive them directly -- the same reason
## law_panel.gd exposes _on_propose() instead of only a button signal.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const MapRaster = preload("res://src/ui/map_raster.gd")

signal nation_clicked(nation_id: String)

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
var _dragging := false
var _drag_moved := 0.0
var _last_mouse_pos := Vector2.ZERO

## Degrees spanned by the loaded polygons, and whether the opening zoom has been
## chosen yet. Both exist only for _fit_zoom(); see it for why the fit cannot
## happen inside setup().
var _span_deg := Vector2.ZERO
var _has_fitted := false

## Ten land tones, cycled by hash so neighbours rarely collide. Desaturated and
## pulled toward the theme's navy at U5a: U2 chose these to be distinguishable
## inside a tab, which is a different problem from sitting under a whole
## interface all game. Saturated pink and olive against a brass-on-navy HUD read
## as two designs on one screen.
##
## Drawn at LAND_ALPHA over the satellite raster since U5b, not as opaque fills.
## Opaque would hide the photograph the session exists to add; bare would lose the
## one thing the tint is for, which is that these ten and only these ten answer a
## click. Colouring these by relations and trade is U5c's.
const PALETTE: Array[Color] = [
	Color(0.28, 0.34, 0.40), Color(0.24, 0.32, 0.42), Color(0.31, 0.36, 0.36),
	Color(0.26, 0.30, 0.38), Color(0.33, 0.35, 0.41), Color(0.22, 0.30, 0.36),
	Color(0.30, 0.33, 0.44), Color(0.35, 0.38, 0.39), Color(0.25, 0.34, 0.38),
	Color(0.32, 0.31, 0.37),
]

## Low, and lowered from 0.42 after looking at a frame rather than reasoning about
## one. The palette is desaturated navy, so at 0.42 it behaved as a grey wash and
## the ten playable nations came out the flattest things on screen while Poland
## and Ireland kept the satellite's colour -- the exact inverse of what the tint
## is for. What separates the roster now is its *outline*, not its fill.
const LAND_ALPHA := 0.20

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

## Below this zoom a label is dropped. At the world view ten labels across Europe
## are ten labels on top of each other; the threshold is set just under the
## opening Europe fit, so the roster is named from the moment the game starts and
## the names clear off as the player pulls back to the globe.
const LABEL_MIN_ZOOM := 1.4
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
				queue_redraw()


func _draw() -> void:
	_fit_zoom()
	_draw_raster()
	_draw_world_borders()
	_draw_roster()
	_draw_labels()


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
	for id in _polygons.keys():
		var color: Color = PALETTE[hash(id) % PALETTE.size()]
		# Hover lifts toward the accent rather than toward white, so the one
		# country under the cursor is picked out in the same brass everything
		# else selectable uses.
		if id == _hovered_id:
			color = color.lerp(UiTheme.ACCENT, 0.35)
		color.a = LAND_ALPHA
		for ring: PackedVector2Array in _polygons[id]:
			if ring.size() < 3:
				continue
			var screen_points := PackedVector2Array()
			for p in ring:
				screen_points.append(_lonlat_to_screen(p.x, p.y))
			draw_colored_polygon(screen_points, color)
			var closed := screen_points.duplicate()
			closed.append(screen_points[0])
			draw_polyline(closed, COAST, 1.5)


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
