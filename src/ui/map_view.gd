extends Control

## The 2D Europe map -- a full-screen background layer, not a modal panel like
## the other three UI surfaces. main.gd adds it first and moves it to sibling
## index 0 so the HUD and every panel's CenterContainer draw on top of it,
## per docs/data-architecture.md's placement note for this session.
##
## Projection is plain equirectangular (lon -> x, -lat -> y): Europe's latitude
## band is narrow enough that the distortion does not obscure a border, and
## nothing here needs a conformal projection. Pan/zoom are a screen-space
## offset and scalar applied on top of that fixed base projection, never
## reprojected -- see _screen_to_lonlat()/_lonlat_to_screen() for the one
## transform both drawing and hit-testing share.
##
## Hit-testing and pan/zoom are exposed as plain methods (nation_at_screen_point,
## pan_by, zoom_by) rather than only reachable through _gui_input, so a headless
## test can drive them directly -- the same reason law_panel.gd exposes
## _on_propose() instead of only a button signal.

signal nation_clicked(nation_id: String)

const BASE_SCALE := 12.0  # screen pixels per degree, before zoom
const MIN_ZOOM := 0.5
const MAX_ZOOM := 8.0
const DRAG_THRESHOLD := 6.0

var _loader
var _state

var _polygons: Dictionary = {}  # nation id -> Array[PackedVector2Array], raw lon/lat
var _center_lon := 0.0
var _center_lat := 0.0

var _zoom := 1.0
var _pan_offset := Vector2.ZERO

var _hovered_id := ""
var _dragging := false
var _drag_moved := 0.0
var _last_mouse_pos := Vector2.ZERO

const PALETTE: Array[Color] = [
	Color(0.62, 0.40, 0.38), Color(0.38, 0.55, 0.62), Color(0.47, 0.60, 0.40),
	Color(0.62, 0.55, 0.35), Color(0.50, 0.42, 0.60), Color(0.40, 0.60, 0.58),
	Color(0.62, 0.45, 0.55), Color(0.55, 0.55, 0.40), Color(0.42, 0.48, 0.62),
	Color(0.58, 0.50, 0.42),
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func setup(loader, state) -> void:
	_loader = loader
	_state = state
	_polygons.clear()

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var n = loader.nations[id]
		var polys: Array = loader.geo_features.get(n.geo_id, [])
		_polygons[id] = polys

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
		return

	_center_lon = (min_lon + max_lon) / 2.0
	_center_lat = (min_lat + max_lat) / 2.0


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
	queue_redraw()


func zoom_by(factor: float, anchor_screen: Vector2) -> void:
	var anchor_lonlat := _screen_to_lonlat(anchor_screen)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	# Re-derive pan so the same lon/lat stays under the anchor point after the
	# zoom changes scale -- otherwise every scroll recenters on the map origin.
	var base := Vector2(anchor_lonlat.x - _center_lon, -(anchor_lonlat.y - _center_lat)) * BASE_SCALE
	_pan_offset = anchor_screen - _control_center() - base * _zoom
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
	for id in _polygons.keys():
		var color: Color = PALETTE[hash(id) % PALETTE.size()]
		if id == _hovered_id:
			color = color.lightened(0.25)
		for ring: PackedVector2Array in _polygons[id]:
			if ring.size() < 3:
				continue
			var screen_points := PackedVector2Array()
			for p in ring:
				screen_points.append(_lonlat_to_screen(p.x, p.y))
			draw_colored_polygon(screen_points, color)
			var closed := screen_points.duplicate()
			closed.append(screen_points[0])
			draw_polyline(closed, Color(0.05, 0.05, 0.06), 1.5)
