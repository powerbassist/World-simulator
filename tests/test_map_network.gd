extends SceneTree

## V3.4. The spine list is COMPLETE and it is anchored where the graph's own
## kilometres were measured.
##
## Headless and one-shot: this file asserts over the loader and a static array,
## and touches no Control -- so unlike tests/test_map_flows.gd it needs no frame
## loop. The drawing side is asserted there and in tests/test_map_view.gd.

const Loader = preload("res://src/core/data_loader.gd")
const MapNetwork = preload("res://src/ui/map_network.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader = Loader.new()
	loader.load_all()
	var edges: Array = loader.region_graph.get("edges", [])
	var spines: Array = MapNetwork.spines(loader)

	# EVERY EDGE GETS A SPINE. A region with no city cannot anchor one, and the
	# register has one such case in its history (FI20 carries no GeoNames place
	# at all, so V3.3 refused its ferry). If that ever becomes true again this
	# count drops and the map quietly loses a line -- which is exactly the class
	# of silent loss a count assertion is for.
	if spines.size() != edges.size():
		_fail("spines %d != edges %d -- a region lost its principal city" % [spines.size(), edges.size()])

	if edges.size() != 463:
		_fail("the graph has %d edges, expected 463 (447 land + 16 sea)" % edges.size())

	var sea := 0
	for s in spines:
		if String(s["kind"]) == "sea":
			sea += 1
	if sea != 16:
		_fail("%d sea spines, expected 16 authored crossings" % sea)

	_check_anchor(loader, spines)
	_check_box(spines)
	_report()


## THE SPINE MUST END WHERE THE KILOMETRE WAS MEASURED. build_region_graph()
## wrote each edge's km as the great-circle distance between the two regions'
## cities[0] -- the authored descending-by-population order. A spine drawn to
## any other point is a line whose length disagrees with the number the sim
## prices accessibility with, and nothing on screen would say so.
func _check_anchor(loader, spines: Array) -> void:
	var by_region := {}
	for nation_id in loader.regions.keys():
		for region in loader.regions[nation_id]:
			if not region.cities.is_empty():
				by_region[String(region.id)] = region.cities[0].lonlat
	for s in spines:
		var want_a = by_region.get(String(s["region_a"]))
		var want_b = by_region.get(String(s["region_b"]))
		if want_a == null or want_b == null:
			_fail("spine %s-%s names a region with no city" % [s["region_a"], s["region_b"]])
			return
		if (s["a"] as Vector2) != (want_a as Vector2) or (s["b"] as Vector2) != (want_b as Vector2):
			_fail("spine %s-%s is not anchored on cities[0]" % [s["region_a"], s["region_b"]])
			return


## The cull reads this box and never the endpoints, so a wrong box is an
## invisible road rather than a crash.
##
## GROWN BEFORE THE TEST, and by a hair rather than by a margin. Rect2.has_point()
## is half-open -- it excludes the right and bottom edges -- and a TIGHT bounding
## box always puts one of its two defining ends on exactly those edges, so the
## check would reject every correct box in the list. AT11-AT12 is the worst of it:
## both cities sit on the same latitude, the box has zero height, and neither end
## counts as inside. 0.001 degrees is about 100 m, which is below any wrong-box
## error worth catching -- those miss by whole degrees -- and above float noise.
func _check_box(spines: Array) -> void:
	for s in spines:
		var box: Rect2 = (s["box"] as Rect2).grow(0.001)
		if not box.has_point(s["a"]) or not box.has_point(s["b"]):
			_fail("spine %s-%s has a box that misses its own ends" % [s["region_a"], s["region_b"]])
			return


func _fail(msg: String) -> void:
	_failures.append(msg)


func _report() -> void:
	if _failures.is_empty():
		print("test_map_network: all checks passed")
		quit()
		return
	for f in _failures:
		print("FAIL: %s" % f)
	quit(1)
