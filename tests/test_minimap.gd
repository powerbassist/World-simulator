extends SceneTree

## Headless test: godot --headless --script res://tests/test_minimap.gd
## Non-zero exit on any failure.
##
## Loads the actual main scene and drives it a frame at a time -- a Control
## outside the scene tree has not run _ready(), so nothing it builds exists yet.
## See docs/engine-decision.md.
##
## The load-bearing assertion here is the *size* one. clock_cluster.gd reserved
## the minimap's box at its final size a whole session early, specifically so that
## filling it would move nothing else; a test that only checked the minimap was
## present would pass while the cluster grew and shoved the speed buttons up into
## the map.

const ClockCluster = preload("res://src/ui/clock_cluster.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false  # _ready(), then one layout pass so sizes are real

	_run()
	_finish()
	return false


func _run() -> void:
	if _main._minimap == null:
		_fail("main scene did not build a minimap")
		return
	if _main._map_view == null:
		_fail("main scene did not build a map view")
		return

	_check_in_the_slot()
	_check_cluster_did_not_grow()
	_check_click_moves_the_map()
	_check_viewport_rect_tracks_zoom()


func _check_in_the_slot() -> void:
	var cluster = _main._hud.clock_cluster
	var minimap = _main._minimap

	if not minimap.is_inside_tree():
		_fail("minimap is not in the scene tree -- set_minimap() should have added it")
		return
	if not cluster.is_ancestor_of(minimap):
		_fail("minimap is not inside the clock cluster")

	# The placeholder set_minimap() clears must be gone, not merely covered.
	for label in _all_labels(cluster):
		if label.text == "MAP OVERVIEW":
			_fail("the reserved slot's placeholder is still in the tree")


## The cluster must be no taller than it would be with the slot empty. Derived
## from MINIMAP_SIZE rather than from a number typed here, so a deliberate change
## to the reserved size does not read as a failure.
func _check_cluster_did_not_grow() -> void:
	var cluster = _main._hud.clock_cluster
	var minimap = _main._minimap

	if minimap.custom_minimum_size != Vector2.ZERO:
		_fail("minimap sets a custom_minimum_size (%s); the slot's size is the cluster's business" % minimap.custom_minimum_size)

	if minimap.size.x > ClockCluster.MINIMAP_SIZE.x + 1.0 or minimap.size.y > ClockCluster.MINIMAP_SIZE.y + 1.0:
		_fail("minimap (%s) is larger than the reserved slot (%s)" % [minimap.size, ClockCluster.MINIMAP_SIZE])

	# The date label, the speed row and the slot, plus separations and the plate's
	# own margins. A cluster taller than the slot plus a generous allowance for
	# those means the minimap pushed it.
	var ceiling: float = ClockCluster.MINIMAP_SIZE.y + 90.0
	if cluster.size.y > ceiling:
		_fail("clock cluster is %.0f px tall, above the %.0f ceiling -- the minimap grew it" % [cluster.size.y, ceiling])


func _check_click_moves_the_map() -> void:
	var map = _main._map_view
	var minimap = _main._minimap

	var before: Rect2 = map.visible_lonlat_rect()
	var before_center := before.position + before.size / 2.0

	# The middle of the minimap is lon 0, lat 0 -- the Gulf of Guinea, a long way
	# from the opening view over Europe.
	minimap.jump_to_local(minimap.size / 2.0)

	var after: Rect2 = map.visible_lonlat_rect()
	var after_center := after.position + after.size / 2.0

	if after_center.is_equal_approx(before_center):
		_fail("clicking the minimap did not move the map view")
		return
	if after_center.distance_to(before_center) < 5.0:
		_fail("clicking the minimap moved the view by less than 5 degrees: %s -> %s" % [before_center, after_center])

	# And it must stay on the planet. This is the pan clamp, seen from the one
	# surface that can ask for an arbitrary centre.
	minimap.jump_to_local(Vector2(-500, -500))
	var clamped: Rect2 = map.visible_lonlat_rect()
	if clamped.position.x < -181.0 or clamped.position.x + clamped.size.x > 181.0:
		_fail("a minimap click off the left edge panned the map off the world: %s" % clamped)


func _check_viewport_rect_tracks_zoom() -> void:
	var map = _main._map_view
	var wide: Rect2 = map.visible_lonlat_rect()
	map.zoom_by(2.0, map._control_center())
	var close: Rect2 = map.visible_lonlat_rect()

	if close.size.x >= wide.size.x or close.size.y >= wide.size.y:
		_fail("zooming in did not shrink visible_lonlat_rect: %s -> %s" % [wide.size, close.size])


func _all_labels(node) -> Array:
	var out: Array = []
	if node is Label:
		out.append(node)
	for child in node.get_children():
		out.append_array(_all_labels(child))
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_minimap: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
