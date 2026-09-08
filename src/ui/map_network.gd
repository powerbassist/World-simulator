extends RefCounted

## The spines -- V3.4. V2.7 modelled a transport graph and V3.3 grew it to 463
## edges; until this file nothing had ever drawn one.
##
## GEOMETRY DERIVED, NOT DOWNLOADED, and that is a LICENCE decision before it is
## a cost one. Routed road geometry was refused twice at V2.7 -- ODbL's
## share-alike attaches to derived databases and data/ would be one -- and
## Natural Earth's own 1:10m roads were measured over this roster at V3.4 step 0
## and refused on coverage (tools/roads_probe.py, verdict in
## docs/data-sources.md). A straight line between two principal cities is
## derived from committed data, so neither refusal reaches it.
##
## ANCHORED ON cities[0], NOT ON THE LARGEST SHARE. src/sim/campaign.gd picks a
## principal city by max share, which is the right rule for a campaign stop; the
## importer's build_region_graph() wrote each edge's kilometres between the two
## regions' cities[0] in the authored descending order. The line on screen has to
## end where the number was measured, or its length disagrees with the distance
## the sim discounts accessibility by and nothing would say so.
##
## ONE COLOUR, TWO STROKES. Land solid, sea dashed. A ferry is told apart by its
## stroke rather than by a second hue because the map's one accent is already
## spent on the marks the player made -- cities, projects, plants -- and a road is
## geography, which is why it sits behind them at a low alpha instead of
## competing with them.
##
## Knows no projection: `to_screen` is passed in rather than reached for, which is
## src/ui/map_plants.gd's and src/ui/map_cities.gd's own arrangement.

## Brass at low alpha. Not a second hue for the same reason map_cities.gd does
## not have one: two accents means the player has to learn which is which, and
## a road never needs to be picked out of the map, only read off it.
const LAND := Color(0.788, 0.635, 0.153, 0.30)
const SEA := Color(0.788, 0.635, 0.153, 0.42)

const WIDTH := 1.0

## The ferry dash. Long enough to read as a dash at the zoom roads appear at
## (CITY_MIN_ZOOM). Whether it still reads as more than one dash on the
## register's actual shortest sea crossing -- DK01-SE22, Copenhagen-Malmo, 28.4 km,
## not the Channel Tunnel's FR1-UKI at 343.8 km -- is a look question this block
## settles at the screenshot pass against a frame, not here.
const DASH_PX := 7.0
const GAP_PX := 5.0


## The spine list, built once from content that never mutates.
##
## Returns lon/lat, not screen points: the cull happens in degrees against the
## view rect BEFORE anything is transformed, which is docs/map-platform-model.md
## §7's gate for this block in its own words. A list of screen points would have
## to be rebuilt on every pan.
static func spines(loader) -> Array:
	var out: Array = []
	if loader == null:
		return out

	var anchor := {}   ## region id -> Vector2 lon/lat
	var owner := {}    ## region id -> nation id
	var nation_ids: Array = loader.regions.keys()
	nation_ids.sort()
	for nation_id in nation_ids:
		for region in loader.regions[nation_id]:
			if region.cities.is_empty():
				continue
			anchor[String(region.id)] = region.cities[0].lonlat
			owner[String(region.id)] = String(nation_id)

	for edge in loader.region_graph.get("edges", []):
		var a_id := String(edge[0])
		var b_id := String(edge[1])
		if not anchor.has(a_id) or not anchor.has(b_id):
			# Not silently skipped: tests/test_map_network.gd asserts the count
			# against the edge count, so a region that loses its cities turns
			# the suite red rather than the map quiet.
			continue
		var a: Vector2 = anchor[a_id]
		var b: Vector2 = anchor[b_id]
		out.append({
			"a": a,
			"b": b,
			"kind": String(edge[3]),
			"region_a": a_id,
			"region_b": b_id,
			"nation_a": owner[a_id],
			"nation_b": owner[b_id],
			"km": float(edge[2]),
			"box": Rect2(a, Vector2.ZERO).expand(b),
		})
	return out


## Draws every spine whose lon/lat box reaches the view, and returns how many
## survived that cull and were submitted for drawing -- not how many pixels
## landed on screen. A sea spine can pass this coarse bbox cull and still have
## _clip_to_box return an empty range once projected, drawing nothing; the land
## branch's draw_line is likewise unclipped and can fall entirely off the
## control. Both are consistent, not a bug, and Task 3's cull test asserts a
## fraction of the roster rather than an exact figure -- but the number this
## returns counts submissions, not verified pixels.
##
## The count is returned rather than kept, so tests/test_map_flows.gd and
## tests/test_map_view.gd can assert the cull by NUMBER at a deep zoom. A
## viewport-bounded claim that is only claimed is not measured -- V3.1's whole
## method.
static func draw_spines(
	canvas: CanvasItem, spine_list: Array, view: Rect2, to_screen: Callable,
	control_size: Vector2
) -> int:
	var drawn := 0
	for s in spine_list:
		# BORDERS EXCLUDED: Rect2.intersects() defaults include_borders to
		# false, so a degenerate box lying exactly on the view's edge is culled
		# away silently rather than drawn (probed on 4.7.1: true for a
		# degenerate box strictly inside the view, false on an edge or corner).
		# Inert today -- tests/test_map_network.gd scans all 463 committed
		# edges and finds none whose cities[0] share an exact longitude or
		# latitude -- but it goes live the day a future edge does.
		if not view.intersects(s["box"]):
			continue
		var a: Vector2 = to_screen.call(s["a"].x, s["a"].y)
		var b: Vector2 = to_screen.call(s["b"].x, s["b"].y)
		if String(s["kind"]) == "sea":
			_draw_dashed(canvas, a, b, control_size)
		else:
			canvas.draw_line(a, b, LAND, WIDTH)
		drawn += 1
	return drawn


## A dashed segment, clipped to the control before it is dashed.
##
## The clip is not tidiness: a bbox cull lets through an edge that merely REACHES
## the view, and at max zoom such an edge can be tens of thousands of pixels
## long. Dashing it whole would emit thousands of draw_line calls for the handful
## that land on screen, which is the "transform first, cull second" failure
## docs/map-platform-model.md §7 names, arriving through the back door.
static func _draw_dashed(canvas: CanvasItem, a: Vector2, b: Vector2, control_size: Vector2) -> void:
	var span := b - a
	var length := span.length()
	if length <= 0.001:
		return
	var dir := span / length
	var box := Rect2(-Vector2.ONE * DASH_PX, control_size + Vector2.ONE * DASH_PX * 2.0)
	var range_t := _clip_to_box(a, dir, length, box)
	var t: float = range_t.x
	var stop: float = range_t.y
	while t < stop:
		var seg_end: float = minf(t + DASH_PX, stop)
		canvas.draw_line(a + dir * t, a + dir * seg_end, SEA, WIDTH)
		t += DASH_PX + GAP_PX


## The [enter, exit] parameter range of the ray a + dir*t inside `box`, clamped
## to [0, length]. Liang-Barsky on two axes; an axis the ray is parallel to
## either misses entirely (empty range) or constrains nothing.
static func _clip_to_box(a: Vector2, dir: Vector2, length: float, box: Rect2) -> Vector2:
	var t0 := 0.0
	var t1 := length
	for axis in [Vector2.AXIS_X, Vector2.AXIS_Y]:
		var d: float = dir[axis]
		var lo: float = box.position[axis]
		var hi: float = box.end[axis]
		if absf(d) < 0.000001:
			if a[axis] < lo or a[axis] > hi:
				return Vector2(0.0, 0.0)
			continue
		var ta: float = (lo - a[axis]) / d
		var tb: float = (hi - a[axis]) / d
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 <= t0:
		return Vector2(0.0, 0.0)
	return Vector2(t0, t1)
