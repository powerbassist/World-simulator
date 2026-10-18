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
## THE CAP. Where a ring is narrower than the band, its inner edge would cross
## the far coast: at the opening fit the band is 0.28 deg, Malta is ~5 x 4 px,
## and at globe view Luxembourg's band would reach ~4 px into its neighbours
## (review, pass 1). So each band VERTEX carries its own cap: the distance its
## inward ray travels before it leaves the ring, halved (band_caps()), so two
## facing pushes can at most meet. The shader pushes by the smaller of the band
## and the cap. Per vertex, not per ring: pass 1's fix was one cap per ring from
## area / perimeter, which is a strip's half-width but a quarter of a compact
## shape's width, so it thinned the band on rings that had room (review, pass 2:
## Luxembourg 2.5 px instead of 7) and still missed thin peninsulas of large
## rings. The cast walks a grid of the ring's edges (exact against a brute-force
## cast on the live roster); ~80 ms per setup() over the roster's 13.5k points.
##
## Vertex encoding (map_fill.gdshader reads it):
##   VERTEX  lon, lat
##   COLOR.r nation index / 255 (the palette texel; 8-bit, so <= 255 nations)
##   COLOR.g across the band: 0 on the line, 1 on the inner edge
##   COLOR.b 1 for a band vertex, 0 for a fill vertex
##   COLOR.a a band vertex's cap / CAP_RANGE_DEG (8-bit, rounded down)
##   UV      the inward miter for a band's inner vertex, else zero
## A BOUND: vertex() reads COLOR after the canvas multiplied it by the item's
## inherited modulate. Nothing modulates map_view or its ancestors (2026-10-18);
## a fade or tint on the map would scale these channels -- move them to CUSTOM0
## then.

## A miter longer than this many band widths is clamped: a needle-sharp coastal
## spike would otherwise throw its inner vertex far across the country.
const MITER_LIMIT := 2.0
## The share of a vertex's inward hit distance its band may cover: a half, so
## two pushes from facing coasts can at most meet in the middle.
const BAND_CAP_SHARE := 0.5
## The widest band there is, in degrees -- 7 px at the furthest zoom out on a
## 1920-wide window is ~1.2 deg -- and so the largest cap worth storing: the 8-bit
## channel holds it in 0.005 deg steps (half a pixel at max zoom). A ray that
## leaves no nearer than this needs no cap.
const CAP_RANGE_DEG := 1.25
## The edge grid's cell, in degrees: about the widest band, so a ray walks a
## handful of cells (0.25 and 0.5 timed the same on the live roster).
const CAP_CELL_DEG := 0.25


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


## Per vertex of a clean ring, the furthest its band may push inward, in degrees
## along the miter (the shader multiplies the miter by it): half the distance
## the vertex's inward ray travels before it crosses the ring, at most
## CAP_RANGE_DEG. The ray walks the cells it crosses nearest first
## (Amanatides-Woo), testing only the edges filed there.
static func band_caps(ring: PackedVector2Array, miters: PackedVector2Array) -> PackedFloat32Array:
	var n := ring.size()
	# Arrays, not PackedInt32Array: a packed array read out of a Dictionary is a
	# copy, and appending to the copy files nothing (the first prototype's bug).
	var grid := {}
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		for cx in range(floori(minf(a.x, b.x) / CAP_CELL_DEG), floori(maxf(a.x, b.x) / CAP_CELL_DEG) + 1):
			for cy in range(floori(minf(a.y, b.y) / CAP_CELL_DEG), floori(maxf(a.y, b.y) / CAP_CELL_DEG) + 1):
				var key := Vector2i(cx, cy)
				if grid.has(key):
					(grid[key] as Array).append(i)
				else:
					grid[key] = [i]
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var length := miters[i].length()
		var d := miters[i] / length
		var p := ring[i]
		var best := CAP_RANGE_DEG * length / BAND_CAP_SHARE
		var c := Vector2i(floori(p.x / CAP_CELL_DEG), floori(p.y / CAP_CELL_DEG))
		var step := Vector2i(1 if d.x > 0.0 else -1, 1 if d.y > 0.0 else -1)
		var t_max := Vector2(INF, INF)
		var t_delta := Vector2(INF, INF)
		if d.x != 0.0:
			t_max.x = ((float(c.x) + (1.0 if d.x > 0.0 else 0.0)) * CAP_CELL_DEG - p.x) / d.x
			t_delta.x = CAP_CELL_DEG / absf(d.x)
		if d.y != 0.0:
			t_max.y = ((float(c.y) + (1.0 if d.y > 0.0 else 0.0)) * CAP_CELL_DEG - p.y) / d.y
			t_delta.y = CAP_CELL_DEG / absf(d.y)
		var t_enter := 0.0
		while t_enter <= best:
			if grid.has(c):
				for e: int in grid[c]:
					if e == i or e == (i - 1 + n) % n:
						continue
					var hit = Geometry2D.segment_intersects_segment(p, p + d * best, ring[e], ring[(e + 1) % n])
					if hit != null:
						best = minf(best, p.distance_to(hit))
			if t_max.x < t_max.y:
				t_enter = t_max.x
				t_max.x += t_delta.x
				c.x += step.x
			else:
				t_enter = t_max.y
				t_max.y += t_delta.y
				c.y += step.y
		out[i] = minf(BAND_CAP_SHARE * best / length, CAP_RANGE_DEG)
	return out


static func _append_band(ring: PackedVector2Array, n: int, verts: PackedVector2Array,
		colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var count := ring.size()
	if count < 3:
		return
	var miters := inward_miters(ring)
	var caps := band_caps(ring, miters)
	var base := verts.size()
	for i in count:
		# Rounded DOWN to the channel's step, so the stored cap never exceeds it.
		var cap := floorf(caps[i] / CAP_RANGE_DEG * 255.0) / 255.0
		verts.append(ring[i])
		colors.append(Color(float(n) / 255.0, 0.0, 1.0, cap))
		uvs.append(Vector2.ZERO)
		verts.append(ring[i])
		colors.append(Color(float(n) / 255.0, 1.0, 1.0, cap))
		uvs.append(miters[i])
	for i in count:
		var o0 := base + 2 * i
		var i0 := o0 + 1
		var o1 := base + 2 * ((i + 1) % count)
		var i1 := o1 + 1
		indices.append_array([o0, o1, i0, i0, o1, i1])
