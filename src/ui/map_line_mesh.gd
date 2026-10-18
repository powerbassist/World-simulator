extends RefCounted

## V4.10c. Closed rings as ONE line mesh in lon/lat: the outline borders, or the
## roster's hairlines and national strokes, each set a single draw call.
##
## Why: drawn as draw_polyline on a layer that is never culled (map_view's
## projected layers move with the camera, so they cannot cull to a view), the
## lines were ~1300 commands and ~1500 draw calls replayed every frame -- 4 ms
## of max zoom where the culled per-frame pass had cost 0.6 (map-platform-model
## §11). As a mesh they are one call, and nothing about them re-records again:
## each vertex carries its ring's palette index, and map_line.gdshader reads the
## colour (row 0) and the width in screen pixels (row 1) from the palette and
## pushes the vertex out by half that width over the scale. A hover or a
## ground-band step rewrites texels; a zoom alone touches nothing.
##
## Geometry: each ring a closed strip, two vertices per point pushed either way
## along the point's miter (MapFillMesh's, clamped at MITER_LIMIT). draw_polyline
## pushed along the unclamped average normal and left the closing point
## unjoined; at the map's 0.75 to 4 px the two are the same line.
##
## Vertex encoding (map_line.gdshader reads it):
##   VERTEX    lon, lat
##   COLOR.rg  palette index, low byte then high byte, each / 255
##   UV        the miter, signed for the side
## A BOUND: vertex() reads COLOR after the canvas multiplied it by the item's
## inherited modulate. Nothing modulates map_view or its ancestors (2026-10-18);
## a fade or tint on the map would scale these channels -- move them to CUSTOM0
## then.

const MapFillMesh = preload("res://src/ui/map_fill_mesh.gd")


## rings: [palette index, PackedVector2Array] pairs in DRAW order -- one mesh
## blends its triangles in index order, so this order is the old call order.
## Returns null when no ring had three distinct points.
static func build(rings: Array) -> ArrayMesh:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for entry in rings:
		var ring: PackedVector2Array = MapFillMesh._clean(entry[1])
		var count := ring.size()
		if count < 3:
			continue
		var index: int = entry[0]
		var tag := Color(float(index & 255) / 255.0, float(index >> 8) / 255.0, 0.0, 1.0)
		var miters := MapFillMesh.inward_miters(ring)
		var base := verts.size()
		for i in count:
			verts.append(ring[i])
			colors.append(tag)
			uvs.append(miters[i])
			verts.append(ring[i])
			colors.append(tag)
			uvs.append(-miters[i])
		for i in count:
			var a0 := base + 2 * i
			var b0 := a0 + 1
			var a1 := base + 2 * ((i + 1) % count)
			var b1 := a1 + 1
			indices.append_array([a0, a1, b0, b0, a1, b1])
	if indices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
