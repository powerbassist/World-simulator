extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_cull.gd
## Non-zero exit on any failure.
##
## V3.1, the cull pass. What a headless suite CANNOT check here is the pixels
## -- that is the before/after identity frames' job, captured at fixed zooms
## with screenshot.gd --zoom. What it can check is the one silent-failure class
## the cull carries: an inverted or over-eager predicate that drops geometry
## the player is looking at, which would be a hole in the map no number on any
## panel would ever explain.
##
## The check is CONSISTENCY, not spots: at two framings (Paris at max zoom,
## the opening fit) the predicate must agree with a naive bounding-box test
## computed here, over every region ring and every world ring. A fixed "far
## region" would be brittle twice over -- the headless window is square
## (1920x1920, where a Paris-centred max-zoom view reaches Madrid), and the
## real window is 16:9, where it does not -- so no fixed id is trusted; the
## test also asserts that SOMETHING culls at each framing, which is what stops
## a predicate stuck at true from passing.
##
## test_map_cities.gd's idiom, same reason: a Control outside the scene tree
## has not run _ready().

const Region = preload("res://src/core/region.gd")

const CENTER_LON := 2.35
const CENTER_LAT := 48.86

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_run()
	if not _failures.is_empty():
		for f in _failures:
			printerr("FAIL: " + f)
		quit(1)
	else:
		print("test_map_cull: all checks passed")
		quit(0)
	return true


func _run() -> void:
	var map = _main._map_view
	if map == null:
		_fail("main scene did not build a map view")
		return
	if not map.has_method("_ring_reaches_view"):
		_fail("map_view.gd lost the cull predicate")
		return

	# Paris at max zoom, then the opening fit -- two framings, two pad sizes,
	# one predicate.
	map._zoom = 8.0
	map.center_on_lonlat(CENTER_LON, CENTER_LAT)
	_check_framing(map, "Paris max zoom")
	map._zoom = 2.1
	map.center_on_lonlat(CENTER_LON, CENTER_LAT)
	_check_framing(map, "opening fit")

	# Degenerate rings never drew (every draw pass guards size >= 3), so the
	# predicate must refuse them too.
	var stub := PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
	if map._ring_reaches_view(stub, map.visible_lonlat_rect()):
		_fail("a two-point ring reached the view")


## The predicate must agree with the geometric truth everywhere, and must
## actually cull somewhere at this framing.
func _check_framing(map, label: String) -> void:
	var view: Rect2 = map.visible_lonlat_rect()
	var pad: float = 8.0 / (12.0 * float(map._zoom))  # CULL_PAD_PX / (BASE_SCALE * zoom)

	var reached_under_centre := false
	var culled := 0
	var checked := 0

	var sets := [
		_main._loader.region_features,
		_main._loader.world_features,
	]
	for set_features in sets:
		for id in set_features.keys():
			for ring in set_features[id]:
				if ring.size() < 3:
					continue
				checked += 1
				if map._ring_reaches_view(ring, view):
					if _bbox_reaches(ring, view, pad):
						if set_features == _main._loader.region_features:
							pass  # reach under the centre checked below
					else:
						_fail("%s: %s ring reached but its bbox is outside the view" % [label, id])
				else:
					culled += 1
					if _bbox_reaches(ring, view, pad):
						_fail("%s: %s ring culled but its bbox reaches the view" % [label, id])

	# The region under the view centre must never cull -- the readable form of
	# the inverted-predicate failure.
	var centre_region: String = Region.region_at_lonlat(
		_main._loader.region_rings, CENTER_LON, CENTER_LAT)
	for ring in _main._loader.region_features.get(centre_region, []):
		if map._ring_reaches_view(ring, view):
			reached_under_centre = true
	if not reached_under_centre:
		_fail("%s: the region under the view centre was culled (%s)" % [label, centre_region])

	if culled == 0:
		_fail("%s: nothing culled at this framing -- the predicate cannot be trusted" % label)
	else:
		print("%s: %d of %d rings culled" % [label, culled, checked])


func _bbox_reaches(ring: PackedVector2Array, view: Rect2, pad: float) -> bool:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in ring:
		mn = mn.min(p)
		mx = mx.max(p)
	if mx.x < view.position.x - pad or mn.x > view.end.x + pad:
		return false
	if mx.y < view.position.y - pad or mn.y > view.end.y + pad:
		return false
	return true


func _fail(msg: String) -> void:
	_failures.append(msg)
