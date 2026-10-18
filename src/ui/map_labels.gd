extends RefCounted

## The label placer -- V4.10b. Greedy declutter by rank over a screen-space grid
## hash, the author's call at the plan gate over a per-zoom precomputed table: the
## table would pop between bands and could not promote a name whose city became
## news this month; this runs on every re-record over what is on screen, and the
## re-record is event-driven (docs/map-platform-model.md §2), so it is paid on a
## pan or a hover, not per frame.
##
## Greedy, deliberately: candidates go in rank order (map_view passes tier, then
## population, then id), each tries four anchors, and the first that collides with
## nothing already placed wins; a candidate with no free anchor is DROPPED. So the
## biggest names in a dense cluster always win and the small ones give way -- the
## look of a printed political map, and the worst case is legible rather than
## cluttered (the Ruhr at a country-scale zoom names its largest cities only).
## A total order (the id breaks every tie) makes the result identical from frame
## to frame while the camera is still: labels that reshuffled on a hover redraw
## would shimmer.
##
## Pure: no font, no canvas. The caller passes a measure function, which is what
## lets tests/test_map_labels.gd pin the geometry headless.

## Tried in this order: beside the mark reads first on a map, above is the next
## most natural, and below is last because it collides with the name of whatever
## lies south on a dense map more often than the others.
const ANCHORS := ["right", "above", "left", "below"]

## Clearance between two names, and between a name and a mark.
const PAD_PX := 2.0

## Grid cell. Twice a typical city name's height plus its pad on each side, so
## most rects touch one to four cells and a lookup walks a handful of rects.
const CELL_PX := 64.0


## The grid is keyed by one int per cell rather than a Vector2i and walked in
## place rather than through a cell list: the first form of this file allocated an
## Array per lookup and placed 1400 candidates in 27 ms headless, against the
## plan's 4 ms line.
static func _key(gx: int, gy: int) -> int:
	return (gx + 4096) * 8192 + (gy + 4096)


static func _insert(grid: Dictionary, r: Rect2) -> void:
	for gx in range(floori(r.position.x / CELL_PX), floori(r.end.x / CELL_PX) + 1):
		for gy in range(floori(r.position.y / CELL_PX), floori(r.end.y / CELL_PX) + 1):
			var k := _key(gx, gy)
			var bucket = grid.get(k)
			if bucket == null:
				grid[k] = [r]
			else:
				bucket.append(r)


static func _free(grid: Dictionary, r: Rect2) -> bool:
	var probe := r.grow(PAD_PX)
	for gx in range(floori(probe.position.x / CELL_PX), floori(probe.end.x / CELL_PX) + 1):
		for gy in range(floori(probe.position.y / CELL_PX), floori(probe.end.y / CELL_PX) + 1):
			var bucket = grid.get(_key(gx, gy))
			if bucket == null:
				continue
			for other: Rect2 in bucket:
				if probe.intersects(other):
					return false
	return true


static func _anchor_rect(anchor: String, at: Vector2, gap: float, size: Vector2) -> Rect2:
	match anchor:
		"center":
			return Rect2(at - size * 0.5, size)
		"right":
			return Rect2(Vector2(at.x + gap, at.y - size.y * 0.5), size)
		"above":
			return Rect2(Vector2(at.x - size.x * 0.5, at.y - gap - size.y), size)
		"left":
			return Rect2(Vector2(at.x - gap - size.x, at.y - size.y * 0.5), size)
		_:
			return Rect2(Vector2(at.x - size.x * 0.5, at.y + gap), size)


## candidates: [{"id", "text", "at": Vector2, "gap": float, "rank": Array}],
## optionally "anchors": [String] in place of ANCHORS -- a nation's name is
## centred on its label point and nowhere else ("center") -- and "over_marks":
## true for a name that may sit over a blocked mark (never over another name).
## A nation's name needs it: with one anchor, a capital's ring under its centre
## would drop it, and the V4.10b review counted 20 of 41 roster names lost that
## way at the opening fit (Spain to Madrid, Poland to Lodz).
## reserved: [Rect2] that NO name may cover, over_marks or not -- the hovered
## city's full label, which is the text the player pointed at.
## blocked: [Rect2] the marks a name may not cover. measure(text) -> Vector2.
## Returns [{"id", "text", "anchor", "rect": Rect2}] in placement order; the rect
## is the text's box (top-left origin), and the caller sets the baseline from
## its own font's ascent.
static func place(candidates: Array, blocked: Array, view: Rect2, measure: Callable,
		reserved: Array = []) -> Array:
	# Native Array.sort() on [rank..., index] keys (Arrays compare element-wise),
	# not sort_custom: a GDScript comparator cost 10 ms of the first 21 ms at
	# 1400 candidates; this is ~1.7 ms. The index never decides an order the rank
	# has not -- the caller's id already breaks every tie.
	var keys: Array = []
	for i in candidates.size():
		var k: Array = (candidates[i]["rank"] as Array).duplicate()
		k.append(i)
		keys.append(k)
	keys.sort()
	# Two grids: names (and the reserved boxes) every candidate must clear, and
	# marks that only an "over_marks" candidate may sit on.
	var names := {}
	var marks := {}
	for b: Rect2 in blocked:
		_insert(marks, b)
	for r: Rect2 in reserved:
		_insert(names, r)
	var placed: Array = []
	for k: Array in keys:
		var c: Dictionary = candidates[int(k[-1])]
		var size: Vector2 = measure.call(String(c["text"]))
		var over_marks := bool(c.get("over_marks", false))
		for anchor: String in c.get("anchors", ANCHORS):
			var r := _anchor_rect(anchor, c["at"], float(c["gap"]), size)
			if not view.encloses(r) or not _free(names, r):
				continue
			if not over_marks and not _free(marks, r):
				continue
			_insert(names, r)
			placed.append({"id": c["id"], "text": c["text"], "anchor": anchor, "rect": r})
			break
	return placed
