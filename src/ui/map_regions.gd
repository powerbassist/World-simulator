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

## The fill's opacity: a tint over the ground, the map still readable under it.
const FILL_ALPHA := 0.42
const RING_WIDTH := 3.0

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


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


## `rings` is region id -> Array[PackedVector2Array] in lon/lat (loader.region_features).
func setup(map, region_ids: Array, rings: Dictionary) -> void:
	_map = map
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
	queue_redraw()


func set_tint(rows: Dictionary) -> void:
	_tint = rows
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
	var origin: Vector2 = _map.lonlat_to_screen(0.0, 0.0)
	var x_axis: Vector2 = _map.lonlat_to_screen(1.0, 0.0) - origin
	var y_axis: Vector2 = _map.lonlat_to_screen(0.0, 1.0) - origin
	var t := Transform2D(x_axis, y_axis, origin)
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
	var font := UiTheme.map_face()
	if font == null:
		return
	for id in _shapes:
		var text := label_of(id)
		if text == "":
			continue
		var p: Vector2 = t * (_shapes[id]["at"] as Vector2)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_MAP + 3).x
		var at := p - Vector2(w * 0.5, 0.0)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_MAP + 3, 4, UiTheme.INK)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_MAP + 3, UiTheme.TEXT)


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
