extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_labels.gd
## Non-zero exit on any failure.
##
## V4.10b, the label placer. Pure, so it is tested with a fixed text measure (7 px
## per character, 12 px tall) instead of a font: what can fail silently here is
## geometry -- two names drawn over each other, a name over a glyph, a name off
## the edge, a small city's name winning over a capital's, or an order that moves
## between two identical frames (labels that shimmer while the camera is still).

const MapLabels = preload("res://src/ui/map_labels.gd")

const VIEW := Rect2(0.0, 0.0, 1920.0, 1080.0)

var _failures: Array[String] = []
var _measure := func(t: String) -> Vector2: return Vector2(7.0 * t.length(), 12.0)


func _init() -> void:
	_check_no_overlap()
	_check_rank_wins()
	_check_anchor_order()
	_check_deterministic()
	_check_dense_cluster()
	_check_cost()
	_check_no_comparator_sort()
	_check_over_marks_and_reserved()
	_finish()


## gap 6: clear of the 6x6 test glyph (half-extent 3) plus the placer's 2 px pad,
## which is how map_view derives it from glyph_rect().
func _cand(id: String, text: String, at: Vector2, rank: Array, gap := 6.0) -> Dictionary:
	return {"id": id, "text": text, "at": at, "gap": gap, "rank": rank}


func _random_cands(n: int, box: Rect2, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	for i in n:
		var at := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		var tier := rng.randi_range(1, 3)
		out.append(_cand("c%04d" % i, "City%d" % i, at, [tier, -rng.randf() * 1e6, "c%04d" % i]))
	return out


func _assert_clean(placed: Array, blocked: Array, label: String) -> void:
	for i in placed.size():
		var a: Rect2 = placed[i]["rect"]
		if not VIEW.encloses(a):
			_failures.append("%s: %s placed outside the view: %s" % [label, placed[i]["id"], a])
		for b: Rect2 in blocked:
			if a.intersects(b):
				_failures.append("%s: %s placed over a glyph" % [label, placed[i]["id"]])
				break
		for j in range(i + 1, placed.size()):
			if a.intersects(placed[j]["rect"]):
				_failures.append("%s: %s overlaps %s" % [label, placed[i]["id"], placed[j]["id"]])
				return


func _check_no_overlap() -> void:
	var cands := _random_cands(200, VIEW, 7)
	var blocked: Array = []
	for c in cands:
		blocked.append(Rect2(c["at"] - Vector2(3, 3), Vector2(6, 6)))
	var placed: Array = MapLabels.place(cands, blocked, VIEW, _measure)
	if placed.is_empty():
		_failures.append("no_overlap: nothing placed from 200 spread candidates")
	_assert_clean(placed, blocked, "no_overlap")


func _check_rank_wins() -> void:
	var at := Vector2(500, 500)
	var placed: Array = MapLabels.place(
		[_cand("small", "Small", at, [3, -1000.0, "small"]), _cand("cap", "Capital", at, [1, -10.0, "cap"])],
		[], VIEW, _measure)
	if placed.is_empty() or placed[0]["id"] != "cap":
		_failures.append("rank_wins: the tier-1 candidate did not place first: %s" % [placed])
		return
	var cap_rect: Rect2 = placed[0]["rect"]
	if cap_rect.position.x < at.x:
		_failures.append("rank_wins: the winner did not take the first anchor (right): %s" % cap_rect)
	_assert_clean(placed, [], "rank_wins")


func _check_anchor_order() -> void:
	var at := Vector2(800, 400)
	# A wall to the right of the point, clear of where the "above" box would sit
	# (that box spans +-21 px for "Aachen", plus the pad): only "right" is blocked.
	var wall := Rect2(at + Vector2(26, -20), Vector2(200, 40))
	var placed: Array = MapLabels.place([_cand("a", "Aachen", at, [2, 0.0, "a"])], [wall], VIEW, _measure)
	if placed.size() != 1:
		_failures.append("anchor_order: not placed with only the right side blocked")
		return
	var r: Rect2 = placed[0]["rect"]
	if not (r.end.y <= at.y):
		_failures.append("anchor_order: with right blocked it should go above, got %s" % r)


func _check_deterministic() -> void:
	var cands := _random_cands(150, Rect2(200, 200, 600, 400), 11)
	var first: Array = MapLabels.place(cands, [], VIEW, _measure)
	var again: Array = MapLabels.place(cands, [], VIEW, _measure)
	var shuffled := cands.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var third: Array = MapLabels.place(shuffled, [], VIEW, _measure)
	if not _same(first, again) or not _same(first, third):
		_failures.append("deterministic: placement changed between identical (or reordered) inputs")


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i]["id"] != b[i]["id"] or a[i]["rect"] != b[i]["rect"]:
			return false
	return true


func _check_dense_cluster() -> void:
	var cands := _random_cands(120, Rect2(900, 500, 300, 200), 19)
	cands.append(_cand("top", "Cologne", Vector2(1050, 600), [1, -1e7, "top"]))
	var placed: Array = MapLabels.place(cands, [], VIEW, _measure)
	var ids := placed.map(func(p): return p["id"])
	if not ids.has("top"):
		_failures.append("dense_cluster: the rank-0 candidate was dropped")
	_assert_clean(placed, [], "dense_cluster")
	print("dense_cluster: %d of %d placed" % [placed.size(), cands.size()])


func _check_cost() -> void:
	var cands := _random_cands(1400, VIEW, 23)
	var t0 := Time.get_ticks_usec()
	var placed: Array = MapLabels.place(cands, [], VIEW, _measure)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("cost: 1400 candidates -> %d placed in %.2f ms (headless)" % [placed.size(), ms])
	# A STRESS figure, not the game's, and PRINTED rather than asserted: 1400 is
	# every city on the roster at once, which no zoom asks for, and a wall-clock
	# cap in a parallel suite is flaky by construction -- the first cap (20 ms)
	# failed at 22.7 ms in the full suite while the same file alone ran 13.5 ms.
	# The shipped placement's cost is priced where frames are priced:
	# tools/label_probe.gd (1.5-2.9 ms per placement) and frame_probe.gd's paired
	# labels_off rows. What a test CAN pin without a clock is the shape that made
	# it fast: the native key sort (see _check_no_comparator_sort).
	print("cost: 1400 candidates -> %d placed in %.2f ms (headless, not asserted)" % [placed.size(), ms])


## The first placer sorted with a GDScript comparator, and the sort alone was
## 10 ms of 21 at 1400 candidates; Array.sort() on precomputed keys is ~1.7 ms.
## Pinned on the source, which is clock-free.
func _check_no_comparator_sort() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/map_labels.gd")
	for line in src.split("
"):
		if line.split("#")[0].contains("sort_custom("):
			_failures.append("map_labels.gd sorts with a GDScript comparator again: %s" % line.strip_edges())


## V4.10b review pass 1: a one-anchor name over a mark is dropped unless it may
## sit over marks; a reserved box beats everyone, over_marks or not.
func _check_over_marks_and_reserved() -> void:
	var at := Vector2(600, 400)
	var mark := Rect2(at - Vector2(5, 5), Vector2(10, 10))
	var nation := _cand("nation", "SPAIN", at, [0, 0.0, "nation"])
	nation["anchors"] = ["center"]
	var dropped: Array = MapLabels.place([nation], [mark], VIEW, _measure)
	if not dropped.is_empty():
		_failures.append("over_marks: a centred name over a mark placed without the flag")
	nation["over_marks"] = true
	var kept: Array = MapLabels.place([nation], [mark], VIEW, _measure)
	if kept.size() != 1:
		_failures.append("over_marks: a centred name with the flag was dropped over a mark")
	var reserved := Rect2(at - Vector2(30, 10), Vector2(60, 20))
	var blocked_by_reserve: Array = MapLabels.place([nation], [mark], VIEW, _measure, [reserved])
	if not blocked_by_reserve.is_empty():
		_failures.append("reserved: a name was placed over a reserved box")


func _finish() -> void:
	if _failures.is_empty():
		print("test_map_labels: OK")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		quit(1)
