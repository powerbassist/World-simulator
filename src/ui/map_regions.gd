extends Control

## The regions on the map -- screen 6, slice 2, the author's direction A ("A, la carte"):
## while the Regions tab is open, the player's regions are tinted by the measure the rail's
## chips pick, each with its figure printed, and the open region ringed in the accent.
##
## An overlay on map_view, not one of its layers: map_view's fill is one palette texel per
## NATION (map_fill_mesh.gd), so a region cannot take its own colour there, and map_view is
## at its size ratchet. The rings are triangulated ONCE in lon/lat (Geometry2D; a ring that
## does not triangulate is skipped and counted, never an engine error), and each draw maps
## lon/lat to the screen with the map's own transform, read off map_view.lonlat_to_screen(),
## so a pan or a zoom re-records two numbers rather than every vertex.
##
## Never takes the mouse: the click is map_view's (its region_picker), so a drag still pans.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Region = preload("res://src/core/region.gd")

## The fill's opacity: a tint over the ground, the map still readable under it.
const FILL_ALPHA := 0.42
const RING_WIDTH := 3.0
## The figure on each region (QA's T1 on #384): the body size in the bold figure face, on an
## ink chip with an edge hairline, so the road and rail lines cannot run through the digits.
const LABEL_SIZE := UiTheme.SIZE_BASE
const CHIP_PAD := Vector2(6, 3)
const CHIP_ALPHA := 0.88

## region id -> {mesh: ArrayMesh, at: Vector2 (lon/lat of the label)}
var _shapes := {}
## region id -> {tone: Color (a == 0 for none), label: String}
var _tint := {}
var _map
var _last_key := []
var selected := ""
## The regions' lon/lat box, and the screen rect the map frames them in when the tab opens
## (the map right of the narrow dock, left of the inbox: regions_shell.gd sets it).
var _bounds := Rect2()
var fit_rect := Rect2()
## region id -> its cities' lon/lat: a figure's chip steps off them (regions_shell.gd sets it).
var _avoid := {}
## region id -> that region's own rings, holes included (its entry of loader.region_rings):
## inside() tests ONE region against them. Without an entry, the drawn outer rings.
var _holed := {}
## The grid a region whose centroid lies outside it is searched on for an anchor.
const ANCHOR_GRID := 16
## label_rects() memo: the chips are laid out once per zoom, text size and tint; a pan only
## moves them (QA's T4 on #384: the layout ran in every pan frame).
var _layout_key := []
var _layout_origin := Vector2.ZERO
var _layout := {}
var _layout_rev := 0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


## `rings` is region id -> Array[PackedVector2Array] in lon/lat (loader.region_features);
## `holed` the same regions' every ring (loader.region_rings' shape, holes kept).
func setup(map, region_ids: Array, rings: Dictionary, holed := {}) -> void:
	_map = map
	_holed = holed
	_layout_rev += 1
	_shapes.clear()
	for id in region_ids:
		var verts := PackedVector2Array()
		var best_area := -1.0
		var at := Vector2.ZERO
		for ring: PackedVector2Array in rings.get(id, []):
			var tri := Geometry2D.triangulate_polygon(ring)
			if tri.is_empty():
				continue
			for i in tri:
				verts.append(ring[i])
			var box := _box(ring)
			if box.get_area() > best_area:
				best_area = box.get_area()
				at = _centroid(ring)
		if verts.is_empty():
			continue
		for ring: PackedVector2Array in rings.get(id, []):
			_bounds = _box(ring) if _bounds.size == Vector2.ZERO else _bounds.merge(_box(ring))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_shapes[String(id)] = {"mesh": mesh, "at": at, "rings": rings.get(id, [])}
	# The figure points are static geometry: found once, here, never in a frame.
	for id in _shapes:
		_anchor(id)
	queue_redraw()


func set_avoid(points: Dictionary) -> void:
	_avoid = points
	_layout_rev += 1


func avoid_points(region_id: String) -> Array:
	return _avoid.get(region_id, [])


## The figure's size on screen: the body size under the player's text size (Settings), as the
## panels' type scales.
func label_size() -> int:
	return int(round(LABEL_SIZE * UiTheme.text_scale()))


func label_font() -> Font:
	return UiTheme.map_figure_face()


## Each labelled region's chip on screen now: centred on the region's label point, else the
## first of STEPS (in half chips) that covers none of its cities and no chip
## already placed (at a 130 % text size, neighbours' chips overlapped) AND keeps its centre
## inside the region's own rings -- a chip stepped into a neighbour reads as the neighbour's
## figure (QA's T2 on #384). If no step fits, the centred chip stays: over a city is wrong but
## unambiguous, in the wrong region is not.
## In half chips: a small region (Ile-de-France at the framed zoom is barely two chips wide)
## has no room for a whole chip's step, so the near places come first.
const STEPS := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0), Vector2(1, 1),
	Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(0, 2), Vector2(0, -2), Vector2(2, 0),
	Vector2(-2, 0), Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2), Vector2(0, 3), Vector2(0, -3)]


func label_rects() -> Dictionary:
	if _map == null:
		return {}
	var t := _screen_transform()
	var key := [t.x, t.y, label_size(), _layout_rev]
	if key != _layout_key:
		_layout = _lay_out()
		_layout_key = key
		_layout_origin = t.origin
	var shift := t.origin - _layout_origin
	var out := {}
	for id in _layout:
		out[id] = Rect2((_layout[id] as Rect2).position + shift, (_layout[id] as Rect2).size)
	return out


func _lay_out() -> Dictionary:
	var out := {}
	var font := label_font()
	var to_lonlat := _screen_transform().affine_inverse()
	for id in _shapes:
		var text := label_of(id)
		if text == "":
			continue
		var anchor := _anchor(id)
		var at: Vector2 = _map.lonlat_to_screen(anchor.x, anchor.y)
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size()) + CHIP_PAD * 2.0
		var cities: Array = []
		for ll: Vector2 in _avoid.get(id, []):
			cities.append(_map.lonlat_to_screen(ll.x, ll.y))
		var centred := Rect2(at - size * 0.5, size)
		var chip := centred
		for step: Vector2 in [Vector2.ZERO] + STEPS:
			var tried := Rect2(centred.position + step * (size + Vector2(4.0, 4.0)) * 0.5, size)
			var on_city := cities.any(func(c: Vector2) -> bool: return tried.grow(2.0).has_point(c))
			var on_chip := out.values().any(func(r: Rect2) -> bool: return tried.grow(2.0).intersects(r))
			if not on_city and not on_chip and inside(id, to_lonlat * tried.get_center()):
				chip = tried
				break
		out[id] = chip
	return out


## Whether a lon/lat point lies in the region: Region.contains() over the region's OWN rings,
## holes kept, because the drawn rings are outer rings only -- Berlin is a hole in Brandenburg,
## Warsaw in Mazowieckie, and an outer-ring test files their points under the host (QA's T3 on
## #384). One region's rings, never Europe's (QA's T4: region_at_lonlat cost 1.4 ms a call).
func inside(region_id: String, lonlat: Vector2) -> bool:
	if _holed.has(region_id):
		return Region.contains(_holed[region_id], lonlat.x, lonlat.y)
	for ring: PackedVector2Array in _shapes.get(region_id, {}).get("rings", []):
		if ring.size() >= 3 and Geometry2D.is_point_in_polygon(lonlat, ring):
			return true
	return false


## The point a region's figure is centred on: its largest ring's centroid, or, when that falls
## outside the region (Brandenburg's centroid is in Berlin), the grid point of its box inside
## the region nearest the centroid. Geometry only, so it is found once.
func _anchor(region_id: String) -> Vector2:
	var shape: Dictionary = _shapes[region_id]
	if shape.has("anchor"):
		return shape["anchor"]
	var centroid: Vector2 = shape["at"]
	var best := centroid
	if not inside(region_id, centroid):
		var box := Rect2()
		for ring: PackedVector2Array in shape["rings"]:
			box = _box(ring) if box.size == Vector2.ZERO else box.merge(_box(ring))
		var best_d := INF
		for i in range(1, ANCHOR_GRID):
			for j in range(1, ANCHOR_GRID):
				var p := box.position + box.size * Vector2(float(i), float(j)) / float(ANCHOR_GRID)
				if inside(region_id, p) and p.distance_to(centroid) < best_d:
					best_d = p.distance_to(centroid)
					best = p
	shape["anchor"] = best
	return best


## lon/lat -> screen, the map's own transform read off two of its points.
func _screen_transform() -> Transform2D:
	var origin: Vector2 = _map.lonlat_to_screen(0.0, 0.0)
	return Transform2D(_map.lonlat_to_screen(1.0, 0.0) - origin, _map.lonlat_to_screen(0.0, 1.0) - origin, origin)


func set_tint(rows: Dictionary) -> void:
	_tint = rows
	_layout_rev += 1
	queue_redraw()


func select(region_id: String) -> void:
	selected = region_id
	queue_redraw()


## Frame the nation in fit_rect: zoom so its box fills nine tenths of the rect, then pan its
## centre to the rect's, through the map's own zoom and pan (which clamp as they always do).
func fit() -> void:
	if _map == null or fit_rect.size == Vector2.ZERO or _bounds.size == Vector2.ZERO:
		return
	var a: Vector2 = _map.lonlat_to_screen(_bounds.position.x, _bounds.end.y)
	var b: Vector2 = _map.lonlat_to_screen(_bounds.end.x, _bounds.position.y)
	var span := (b - a).abs()
	if span.x <= 0.0 or span.y <= 0.0:
		return
	_map.zoom_by(0.9 * minf(fit_rect.size.x / span.x, fit_rect.size.y / span.y), fit_rect.get_center())
	_map.pan_by(fit_rect.get_center() - _map.lonlat_to_screen(_bounds.get_center().x, _bounds.get_center().y))


func drawn_count() -> int:
	return _shapes.size()


func fill_of(region_id: String) -> Color:
	var tone: Color = (_tint.get(region_id, {}) as Dictionary).get("tone", Color(0, 0, 0, 0))
	return Color(tone.r, tone.g, tone.b, FILL_ALPHA if tone.a > 0.0 else 0.0)


func label_of(region_id: String) -> String:
	return String((_tint.get(region_id, {}) as Dictionary).get("label", ""))  # i18n: row-ok built through Num and Strings in region_tint.gd


## A pan or a zoom moves the map's transform: redraw only then.
func _process(_delta: float) -> void:
	if not visible or _map == null:
		return
	var key := [_map.lonlat_to_screen(0.0, 0.0), _map.lonlat_to_screen(1.0, 1.0), size]
	if key != _last_key:
		_last_key = key
		queue_redraw()


func _draw() -> void:
	if _map == null:
		return
	var t := _screen_transform()
	for id in _shapes:
		var fill := fill_of(id)
		if fill.a > 0.0:
			draw_set_transform_matrix(t)
			draw_mesh(_shapes[id]["mesh"], null, Transform2D.IDENTITY, fill)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if _shapes.has(selected):
		for ring: PackedVector2Array in _shapes[selected]["rings"]:
			var pts := t * ring
			pts.append(pts[0])
			draw_polyline(pts, UiTheme.accent(), RING_WIDTH, true)
	var font := label_font()
	var chips := label_rects()
	for id in chips:
		var chip: Rect2 = chips[id]
		draw_rect(chip, Color(UiTheme.INK, CHIP_ALPHA))
		draw_rect(chip, UiTheme.EDGE, false, 1.0)
		var baseline := Vector2(chip.position.x + CHIP_PAD.x, chip.position.y + CHIP_PAD.y + font.get_ascent(label_size()))
		draw_string(font, baseline, label_of(id), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size(), UiTheme.TEXT)


static func _box(ring: PackedVector2Array) -> Rect2:
	var box := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		box = box.expand(p)
	return box


## The ring's area centroid, its box centre for a degenerate ring.
static func _centroid(ring: PackedVector2Array) -> Vector2:
	var area := 0.0
	var c := Vector2.ZERO
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var cross := a.x * b.y - b.x * a.y
		area += cross
		c += (a + b) * cross
	if absf(area) < 1e-9:
		return _box(ring).get_center()
	return c / (3.0 * area)
