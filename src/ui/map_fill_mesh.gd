extends RefCounted

## V4.10c. The roster's fills as ONE mesh in lon/lat, built once at setup().
##
## Why a mesh: the attribution (map-platform-model §11) put 41 ms of the 83 ms
## opening-fit drag in the fills alone -- `draw_colored_polygon` re-projects
## and RE-TRIANGULATES every ring on every re-record, and a drag re-records
## every frame, while nothing in a fill depends on the camera. Triangulated here
## in lon/lat instead: the projection is affine, and an affine map carries a
## triangulation over unchanged, so this is the triangulation the old call made
## every frame, made once. A ring that fails it (empty indices) also failed
## `draw_colored_polygon`, which drew nothing for it, so skipping it here is the
## same picture.
##
## THE ORDER IS THE OLD DRAW ORDER: per nation, its 1:50m base rings, then its
## 1:10m regions, nation after nation. The fills are translucent and one draw
## call blends its triangles in index order, so the alpha compounds exactly as
## the per-ring calls did (the base under the regions is what hides the
## GISCO/Natural Earth coast seam -- map_view's V2.2b comment).
##
## THEN THE EDGE BAND, every nation's after every fill: a strip along each
## 1:50m ring whose inner vertices carry the inward miter in UV. The shader
## pushes them inward by `band_px / px_per_deg`, so the band is a constant
## width in screen pixels at every zoom without the mesh ever being rebuilt.
## With the band width at 0 the strip has no area and draws nothing.
##
## Vertex encoding (map_fill.gdshader reads it):
##   VERTEX  lon, lat
##   COLOR.r nation index / 255 (the palette texel; 8-bit, so <= 255 nations)
##   COLOR.g across the band: 0 on the line, 1 on the inner edge
##   COLOR.b 1 for a band vertex, 0 for a fill vertex
##   UV      the inward miter for a band's inner vertex, else zero

## A miter longer than this many band widths is clamped: a needle-sharp coastal
## spike would otherwise throw its inner vertex far across the country.
const MITER_LIMIT := 2.0


## nations: one entry per roster nation in palette order, each
## {"rings": Array[PackedVector2Array] (1:50m), "regions": Array[PackedVector2Array]}.
## Returns {"mesh": ArrayMesh, "fill_vertices": int, "band_vertices": int,
## "skipped": int}; mesh is null when nothing triangulated.
static func build(nations: Array) -> Dictionary:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var skipped := 0

	for n in nations.size():
		var tag := Color(float(n) / 255.0, 0.0, 0.0, 1.0)
		var rings: Array = (nations[n]["rings"] as Array) + (nations[n]["regions"] as Array)
		for ring: PackedVector2Array in rings:
			if ring.size() < 3:
				continue
			var tri := Geometry2D.triangulate_polygon(ring)
			if tri.is_empty():
				skipped += 1
				continue
			var base := verts.size()
			for p in ring:
				verts.append(p)
				colors.append(tag)
				uvs.append(Vector2.ZERO)
			for i in tri:
				indices.append(base + i)
	var fill_vertices := verts.size()

	for n in nations.size():
		for ring: PackedVector2Array in nations[n]["rings"]:
			_append_band(_clean(ring), n, verts, colors, uvs, indices)

	if indices.is_empty():
		return {"mesh": null, "fill_vertices": 0, "band_vertices": 0, "skipped": skipped}
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {
		"mesh": mesh,
		"fill_vertices": fill_vertices,
		"band_vertices": verts.size() - fill_vertices,
		"skipped": skipped,
	}


## The ring without repeated points (a zero-length edge has no normal) and
## without a closing duplicate of its first point.
static func _clean(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ring:
		if out.is_empty() or not out[out.size() - 1].is_equal_approx(p):
			out.append(p)
	if out.size() > 1 and out[0].is_equal_approx(out[out.size() - 1]):
		out.remove_at(out.size() - 1)
	return out


## Twice the signed area: positive when the ring winds counter-clockwise in
## lon/lat (latitude up), where the interior lies to the LEFT of each edge.
static func signed_area2(ring: PackedVector2Array) -> float:
	var a := 0.0
	var n := ring.size()
	for i in n:
		var p := ring[i]
		var q := ring[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a


## The inward miter at every vertex of a clean ring, in lon/lat units per unit
## band width. Exposed for the test, which checks it points inside.
static func inward_miters(ring: PackedVector2Array) -> PackedVector2Array:
	var n := ring.size()
	var out := PackedVector2Array()
	out.resize(n)
	var side := 1.0 if signed_area2(ring) > 0.0 else -1.0
	var normals := PackedVector2Array()
	normals.resize(n)
	for i in n:
		var d := (ring[(i + 1) % n] - ring[i]).normalized()
		# Left of the edge for a counter-clockwise ring, right for a clockwise one.
		normals[i] = Vector2(-d.y, d.x) * side
	for i in n:
		var before := normals[(i - 1 + n) % n]
		var after := normals[i]
		var m := before + after
		if m.length_squared() < 1e-12:
			out[i] = after  # a 180-degree spike: no miter, take the outgoing edge's
			continue
		m = m.normalized()
		var cos_half := m.dot(after)
		out[i] = m * minf(1.0 / maxf(cos_half, 1e-6), MITER_LIMIT)
	return out


static func _append_band(ring: PackedVector2Array, n: int, verts: PackedVector2Array,
		colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var count := ring.size()
	if count < 3:
		return
	var miters := inward_miters(ring)
	var on_line := Color(float(n) / 255.0, 0.0, 1.0, 1.0)
	var inner := Color(float(n) / 255.0, 1.0, 1.0, 1.0)
	var base := verts.size()
	for i in count:
		verts.append(ring[i])
		colors.append(on_line)
		uvs.append(Vector2.ZERO)
		verts.append(ring[i])
		colors.append(inner)
		uvs.append(miters[i])
	for i in count:
		var o0 := base + 2 * i
		var i0 := o0 + 1
		var o1 := base + 2 * ((i + 1) % count)
		var i1 := o1 + 1
		indices.append_array([o0, o1, i0, i0, o1, i1])
