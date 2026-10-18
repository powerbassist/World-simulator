extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_fill_mesh.gd
## Non-zero exit on any failure.
##
## V4.10c, the fill mesh. Pure, so it is tested on hand-made rings. What can
## fail silently here is all invisible to a green suite and visible on the map:
## a band pushed OUTWARD (a dark halo over the neighbour and the sea), a ring
## wound the other way flipping it, a fill drawn in a different order than the
## old per-ring calls (the alpha would compound differently), a needle spike
## throwing its inner vertex across the country.

const MapFillMesh = preload("res://src/ui/map_fill_mesh.gd")
const MapLineMesh = preload("res://src/ui/map_line_mesh.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_band_points_inward()
	_check_order_and_counts()
	_check_spike_is_clamped()
	_check_degenerate_rings()
	_check_line_mesh()
	_finish()


func _square(ccw: bool) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	if not ccw:
		pts.reverse()
	return pts


## Both windings, an L-shaped ring with a reflex corner, and a ring that repeats
## its first point at the end: every inner vertex lands inside the ring.
func _check_band_points_inward() -> void:
	var ell := PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 2),
		Vector2(2, 2), Vector2(2, 6), Vector2(0, 6)])
	var closed := _square(true)
	closed.append(closed[0])
	for case in [["ccw square", _square(true)], ["cw square", _square(false)],
			["L", ell], ["L reversed", _reversed(ell)], ["closed square", closed]]:
		var ring: PackedVector2Array = MapFillMesh._clean(case[1])
		var miters := MapFillMesh.inward_miters(ring)
		for i in ring.size():
			var inner: Vector2 = ring[i] + miters[i] * 0.1
			if not Geometry2D.is_point_in_polygon(inner, ring):
				_fail("%s: vertex %d's band edge %s is outside the ring" % [case[0], i, inner])
			if miters[i].length() < 0.99:
				_fail("%s: vertex %d's miter is shorter than the band (%.3f)" % [case[0], i, miters[i].length()])


func _reversed(ring: PackedVector2Array) -> PackedVector2Array:
	var out := ring.duplicate()
	out.reverse()
	return out


## Two nations, each a base ring and a region ring. The fills come first and in
## the old draw order (A base, A region, B base, B region), each tagged with its
## nation's palette index; the bands come after every fill.
func _check_order_and_counts() -> void:
	var a := _square(true)
	var b := PackedVector2Array()
	for p in a:
		b.append(p + Vector2(10, 0))
	var built := MapFillMesh.build([
		{"rings": [a], "regions": [a]},
		{"rings": [b], "regions": [b]},
	])
	if built["mesh"] == null:
		_fail("two squares built no mesh")
		return
	if int(built["fill_vertices"]) != 16:
		_fail("fill vertices %d, expected 16 (4 rings x 4 points)" % int(built["fill_vertices"]))
	if int(built["band_vertices"]) != 16:
		_fail("band vertices %d, expected 16 (2 base rings x 4 points x 2)" % int(built["band_vertices"]))
	var arrays: Array = (built["mesh"] as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var expected_nation := [0, 0, 1, 1]
	for ring_i in 4:
		var c := colors[ring_i * 4]
		if roundi(c.r * 255.0) != expected_nation[ring_i] or c.b != 0.0:
			_fail("fill ring %d is tagged %s, expected nation %d, fill" % [ring_i, c, expected_nation[ring_i]])
	if not verts[8].is_equal_approx(b[0]):
		_fail("the third fill ring does not start at B's base ring -- order changed")
	for v in range(16, 32):
		if colors[v].b != 1.0:
			_fail("vertex %d after the fills is not a band vertex" % v)
			break


## A needle: the miter at its tip would be enormous unclamped.
func _check_spike_is_clamped() -> void:
	var needle := PackedVector2Array([Vector2(0, 0), Vector2(10, 0.05), Vector2(0, 0.1), Vector2(-1, 0.05)])
	var miters := MapFillMesh.inward_miters(needle)
	for i in needle.size():
		if miters[i].length() > MapFillMesh.MITER_LIMIT + 1e-4:
			_fail("needle vertex %d miter %.2f exceeds the limit %.1f" % [i, miters[i].length(), MapFillMesh.MITER_LIMIT])


## Rings under three points never drew; a nation of nothing but those builds no
## mesh rather than an empty one the draw would choke on.
func _check_degenerate_rings() -> void:
	var built := MapFillMesh.build([{"rings": [PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])], "regions": []}])
	if built["mesh"] != null:
		_fail("a two-point ring built a mesh")


## The line mesh: a palette index past one byte survives the two-byte encoding
## (the outlines number 133 today and the world more), every point has a vertex
## each side of the line, and the rings keep the order they were given.
func _check_line_mesh() -> void:
	var a := _square(true)
	var mesh := MapLineMesh.build([[300, a], [7, _square(false)]])
	if mesh == null:
		_fail("two squares built no line mesh")
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if colors.size() != 16:
		_fail("line mesh has %d vertices, expected 16 (2 rings x 4 points x 2 sides)" % colors.size())
		return
	var first := roundi(colors[0].r * 255.0) + 256 * roundi(colors[0].g * 255.0)
	var second := roundi(colors[8].r * 255.0) + 256 * roundi(colors[8].g * 255.0)
	if first != 300 or second != 7:
		_fail("line indices decode to %d, %d -- expected 300, 7 in the order given" % [first, second])
	for v in range(0, 16, 2):
		if not uvs[v].is_equal_approx(-uvs[v + 1]) or uvs[v].length() < 0.99:
			_fail("line vertex pair %d is not pushed equally either side (%s, %s)" % [v / 2, uvs[v], uvs[v + 1]])
			break


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_map_fill_mesh: OK")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		quit(1)
