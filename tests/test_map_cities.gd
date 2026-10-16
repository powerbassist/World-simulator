extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_cities.gd
## Non-zero exit on any failure.
##
## V2.2b, the city crosses. Loads the actual main scene and drives it a frame
## at a time, test_map_markers.gd's idiom, because a Control outside the scene
## tree has not run _ready() -- see docs/engine-decision.md.
##
## What a headless suite CANNOT check here is what a brass cross looks like over
## a satellite photograph; that is the screenshot pass's job and is why one
## exists. What it can check is every structural claim the session makes: the
## hit test never touches the roster's polygons (U5b's guarantee, one layer
## down), the zoom threshold gates the hit test exactly as it gates the draw,
## the list is ranked so the largest cross wins an overlap, and the population
## under a glyph is the two shares read through the live nation -- never an
## authored figure, city.gd's four-field rule.

const MapCities = preload("res://src/ui/map_cities.gd")

## The register is the list (V4 handoff): a literal 29-id roster here went
## stale the moment V4.11 grew the roster -- five test files at once.
func _nations() -> Array:
	var ids: Array = _main._loader.nations.keys()
	ids.sort()
	return ids
const EXPECTED_CITIES := 1262  # geography-model.md's volume clause (<= 1 800 cities, V3.3), re-checked at V4.11a1 (36 nations); CITY_MIN_POP 58000 held so the 29's cities stay byte-identical

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null or _main._map_view == null:
		_fail("main scene did not build a state and a map view")
		return

	var loader = _main._loader
	var state = _main._state
	var map = _main._map_view

	_check_the_list_is_the_register(loader, state)
	_check_populations_are_derived(loader, state)
	_check_the_ranking(loader, state)
	_check_hit_test_avoids_the_roster(map)
	_check_the_threshold_gates_the_hit_test(map)
	_check_click_routes_to_the_city(map)


## Every named city on the roster, all twenty-nine nations, no more and no fewer. The
## count is the volume clause geography-model.md §6 measured -- a register that
## grew past it has to come and re-measure the clause, not just this constant.
func _check_the_list_is_the_register(loader, state) -> void:
	var cities: Array = MapCities.cities(loader, state)
	if cities.size() != EXPECTED_CITIES:
		_fail("MapCities.cities returned %d cities against the register's %d" % [cities.size(), EXPECTED_CITIES])

	var nations_seen := {}
	var ids := {}
	for city in cities:
		nations_seen[city["nation_id"]] = true
		if ids.has(city["city_id"]):
			_fail("city id '%s' appears twice in the draw list" % String(city["city_id"]))
		ids[city["city_id"]] = true
	for id in _nations():
		if not nations_seen.has(id):
			_fail("no city of %s reached the draw list" % id)


## The one arithmetic the glyph rests on: population = live national population
## x region share x city share, to the float. An authored figure here would be
## one quantity written twice, and the panel would drift from the map.
func _check_populations_are_derived(loader, state) -> void:
	var cities: Array = MapCities.cities(loader, state)
	var checked := 0
	for city in cities:
		var ns = state.nations.get(city["nation_id"])
		if ns == null:
			_fail("draw list holds a city of '%s', which has no live state" % String(city["nation_id"]))
			continue
		var region = _region_of(loader, String(city["nation_id"]), String(city["region_id"]))
		if region == null:
			_fail("draw list holds region '%s' of %s, which the register does not" % [String(city["region_id"]), String(city["nation_id"])])
			continue
		var expected: float = float(ns.population) * float(region.share) * float(_share_of(loader, String(city["nation_id"]), String(city["region_id"]), String(city["city_id"])))
		if absf(float(city["population"]) - expected) > 0.5:
			_fail("city '%s' drew population %s against %s" % [String(city["city_id"]), str(city["population"]), str(expected)])
		checked += 1
	if checked < EXPECTED_CITIES / 2:
		_fail("population check covered only %d cities; it is measuring nothing" % checked)


## Ascending population, so the largest draws last and wins an overlap, and the
## radius it wins with grows with the population it ranks on. A list in file
## order would draw a suburb over its capital.
func _check_the_ranking(loader, state) -> void:
	var cities: Array = MapCities.cities(loader, state)
	var last_pop := -1.0
	var last_radius := -1.0
	for city in cities:
		var pop: float = float(city["population"])
		var radius: float = MapCities.radius_of(city)
		if pop < last_pop:
			_fail("the draw list is not ascending by population after '%s'" % String(city["city_id"]))
		if radius < last_radius:
			_fail("the radius shrank while the population grew at '%s'" % String(city["city_id"]))
		last_pop = pop
		last_radius = radius
	if MapCities.radius_of({"population": 1000.0}) != MapCities.RADIUS_MIN:
		_fail("a village-sized city does not clamp to RADIUS_MIN")
	if MapCities.radius_of({"population": 500_000_000.0}) != MapCities.RADIUS_MAX:
		_fail("a megalopolis does not clamp to RADIUS_MAX")


## U5b's structural guarantee, one layer down from the markers. `_city_at_screen_point()`
## takes `_project_at_screen_point()`'s contract, on the tier doc's own
## instruction, and this reads the source for the same reason that test does: a
## cross test routed through the nation hit test would make `_nation_at_lonlat`
## answer for two things, and the property would die the day someone widened it.
func _check_hit_test_avoids_the_roster(map) -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/map_view.gd")
	if src == "":
		_fail("could not read map_view.gd to check the hit test")
		return
	var at := src.find("func _city_at_screen_point(")
	if at < 0:
		_fail("map_view.gd has no _city_at_screen_point()")
		return
	var body := src.substr(at)
	var ends := body.find("\nfunc ", 1)
	if ends > 0:
		body = body.substr(0, ends)
	for banned in ["_nation_at_lonlat", "_polygons", "nation_at_screen_point"]:
		if body.find(banned) >= 0:
			_fail("_city_at_screen_point() reaches %s; U5b's structural guarantee dies" % banned)


## A glyph that is not drawn is never a target: below CITY_MIN_ZOOM the hit test
## answers nothing even at a city's exact screen point, so the map answers the
## nation beneath the invisible cross instead. Checked against the REAL point
## rather than a synthetic one, because the claim is about the same gate
## reading the same constant in two places.
func _check_the_threshold_gates_the_hit_test(map) -> void:
	var paris := _screen_of(map, "FR1_paris")
	while map._zoom >= map.CITY_MIN_ZOOM:
		map.zoom_by(0.5, map.size / 2.0)
	if map._zoom >= map.CITY_MIN_ZOOM:
		_fail("could not zoom below CITY_MIN_ZOOM to test the gate")
		return
	if map._city_at_screen_point(paris) != "":
		_fail("the hit test answered below CITY_MIN_ZOOM, where nothing is drawn")

	map.zoom_by(8.0, map.size / 2.0)
	if map._zoom < map.CITY_MIN_ZOOM:
		_fail("could not zoom above CITY_MIN_ZOOM to test the hit")
		return
	# Recomputed, because the pan moved under the zooms: the stored point is
	# where Paris WAS, and the claim below is about where it is.
	paris = _screen_of(map, "FR1_paris")
	if map._city_at_screen_point(paris) != "FR1_paris":
		_fail("a point on Paris did not hit Paris's cross")


## A click on a cross is a city click and NOT a nation click, or one press opens
## two windows. The markers' claim, one layer down.
func _check_click_routes_to_the_city(map) -> void:
	var paris := _screen_of(map, "FR1_paris")

	var cities_seen: Array[String] = []
	var nations_seen: Array[String] = []
	map.city_clicked.connect(func(cid: String): cities_seen.append(cid))
	map.nation_clicked.connect(func(nid: String): nations_seen.append(nid))

	_click(map, paris)
	if cities_seen != ["FR1_paris"]:
		_fail("clicking a cross emitted %s" % str(cities_seen))
	if not nations_seen.is_empty():
		_fail("clicking a cross also emitted nation_clicked %s" % str(nations_seen))

	# Mid-Atlantic rather than "Paris + N pixels": at high zoom a few hundred
	# pixels from Paris is another French city, and a far-click that hits a real
	# cross is a flaky test, not a bug. Nothing the register holds is at -30.
	var far: Vector2 = map._lonlat_to_screen(-30.0, 45.0)
	_click(map, far)
	if cities_seen.size() != 1:
		_fail("a click far from every cross reached one anyway")


# --- helpers -----------------------------------------------------------------

## The screen point of a city id, with the map zoomed past the threshold first
## so the question is asked where the glyph exists.
func _screen_of(map, city_id: String) -> Vector2:
	if map._zoom < map.CITY_MIN_ZOOM:
		map.zoom_by(8.0, map.size / 2.0)
	var city = _find_city(city_id)
	var lonlat: Vector2 = city["lonlat"]
	return map._lonlat_to_screen(lonlat.x, lonlat.y)


func _find_city(city_id: String) -> Dictionary:
	for entry in _main._map_view._cities:
		if String(entry["city_id"]) == city_id:
			return entry
	_fail("city '%s' is not in the draw list" % city_id)
	return {"lonlat": Vector2.ZERO}


func _region_of(loader, nation_id: String, region_id: String):
	for region in loader.regions.get(nation_id, []):
		if region.id == region_id:
			return region
	return null


func _share_of(loader, nation_id: String, region_id: String, city_id: String) -> float:
	for region in loader.regions.get(nation_id, []):
		if region.id != region_id:
			continue
		for city in region.cities:
			if city.id == city_id:
				return float(city.share)
	return 0.0


func _click(map, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	map._gui_input(down)

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	map._gui_input(up)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_map_cities: OK")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	printerr("test_map_cities: %d failure(s)" % _failures.size())
	quit(1)
