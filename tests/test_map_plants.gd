extends SceneTree

## V2.8. Placement mode's exclusivity, the hit test's purity, and the pin that says
## a plant is a DRAW PASS and not a fifth map layer.
##
## Driven a frame at a time because a Control outside the scene tree has not run
## _ready() -- tests/test_shell.gd's idiom, and the reason a one-shot _init() here
## would assert against a tree of nulls.

const Main = preload("res://src/ui/main.tscn")
const MapLayers = preload("res://src/ui/map_layers.gd")

const UiTheme = preload("res://src/ui/ui_theme.gd")
const MapPlants = preload("res://src/ui/map_plants.gd")

var _failures: Array[String] = []
var _frame: int = 0
var _main: Node = null


func _init() -> void:
	_main = Main.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_check_source_purity()
		_check_layers_unchanged()
		_check_placement_exclusive()
		_check_plant_readout()
		_start_the_fleet_route()
		return false
	if _frame < 3 + ROUTE_FRAMES:
		return false
	_check_the_fleet_route()
	_report()
	return true


## V5.1-0a review: a glyph's route opens the Energy window and asks it to bring
## the fleet section into view in the same frame -- and since a panel builds only
## while its window shows, a window never opened this session has no fleet
## section yet to scroll to. The window is fitted to a short band here so the
## fleet, the panel's last section, is below the fold and the scroll is visible.
const ROUTE_FRAMES := 5


func _start_the_fleet_route() -> void:
	_main._windows.close_all()
	# V5.2-0b trimmed the Energy body to fit a 1080 dock, so the route is staged at
	# the largest text size, where it no longer fits and there is something to scroll.
	UiTheme.set_text_scale(1.6)
	UiTheme.rebuild(_main)
	_main._map_view.plant_clicked.emit("")
	_main._windows.frame("energy").fit_within(Vector2(900, 260))


func _check_the_fleet_route() -> void:
	var scroll: ScrollContainer = _main._energy_panel._scroll
	if scroll.get_v_scroll_bar().max_value <= scroll.size.y:
		_fail("premise: the Energy window's body fits its band, so the fleet route has nothing to scroll (max %s, band %s)" % [scroll.get_v_scroll_bar().max_value, scroll.size.y])
		return
	if scroll.scroll_vertical <= 0:
		_fail("a plant's route opened the Energy window at the top, not at the fleet section")
	_main._windows.close_all()


## V5.2 b+ (R1, gate b: "i cant check how far the work is done, no infobulle"). A
## plant under construction says how far it is, on the map: the glyph fills as an
## arc, and the cursor on it reads its name, region and progress. Another nation's
## plant says what it is and whether it runs, never its schedule.
func _check_plant_readout() -> void:
	var state = _main._state
	var map = _main._map_view
	var ns = state.player()
	var region = _main._loader.regions[ns.id][0]
	var at: Vector2 = region.cities[0].lonlat
	ns.plants["nuclear_epr#91"] = {"source_id": "nuclear_epr", "region_id": region.id, "lon": at.x, "lat": at.y,
		"months_left": 80, "done": false, "connection": 1.0}
	var built := MapPlants.progress(ns.plants["nuclear_epr#91"], _main._loader)
	if absf(built - 40.0 / 120.0) > 1e-6:
		_fail("a reactor 80 of 120 months from done reads %.3f built, not a third" % built)
	var motion := InputEventMouseMotion.new()
	motion.position = map._lonlat_to_screen(at.x, at.y)
	map._gui_input(motion)
	if map._hovered_plant != [String(ns.id), "nuclear_epr#91"]:
		_fail("the cursor on the player's plant glyph did not hover it: %s" % [map._hovered_plant])
	var mine := " ".join(_texts(MapPlants.readout_lines(state, _main._loader, String(ns.id), "nuclear_epr#91")))
	for want in [String(region.region_name), "33 % built", "80 months left"]:
		if not mine.contains(want):
			_fail("the plant readout '%s' does not say '%s'" % [mine, want])
	var deu = state.nations["DEU"]
	deu.plants["nuclear_epr#92"] = {"source_id": "nuclear_epr", "region_id": "", "lon": 10.0, "lat": 50.0,
		"months_left": 30, "done": false, "connection": 1.0}
	var theirs := " ".join(_texts(MapPlants.readout_lines(state, _main._loader, "DEU", "nuclear_epr#92")))
	if theirs.contains("month") or theirs.contains("%") or not theirs.contains("Under construction"):
		_fail("another nation's plant readout gives its schedule or not its state: '%s'" % theirs)
	ns.plants.erase("nuclear_epr#91")
	deu.plants.erase("nuclear_epr#92")
	map._hovered_plant = []


func _texts(lines: Array) -> Array:
	var out: Array = []
	for line in lines:
		out.append(String(line[0]))
	return out


## THE HIT TEST DOES NOT GO THROUGH THE ROSTER, read from the source rather than
## promised in a comment. U5b's "a non-simulated country is unclickable
## STRUCTURALLY" rests on _nation_at_lonlat() being the only thing that iterates
## _polygons; a plant test routed through it would make that function answer for two
## things and the property would die the day someone widened it.
## tests/test_map_markers.gd and tests/test_map_cities.gd police theirs the same way.
func _check_source_purity() -> void:
	var text := FileAccess.get_file_as_string("res://src/ui/map_view.gd")
	var start := text.find("func _plant_at_screen_point")
	if start < 0:
		_fail("map_view.gd has no _plant_at_screen_point()")
		return
	var stop := text.find("\nfunc ", start + 1)
	var body := text.substr(start, stop - start if stop > start else -1)
	for forbidden in ["_polygons", "_nation_at_lonlat", "region_rings"]:
		if body.contains(forbidden):
			_fail("_plant_at_screen_point() reaches %s -- it is a screen-space radius test" % forbidden)


## A PLANT IS A DRAW PASS, NOT A LAYER. map_layers.gd's own header says no map layer
## adds, removes or reorders a draw layer: LAYERS chooses a roster FILL from a
## per-nation scalar, one at a time, and a plant is a point and is additive.
##
## V4.6: THE COUNT WAS A PROXY, and this check and test_map_markers.gd's sibling
## both carried it -- see test_map_flows.gd's note. Task 4 added two real per-nation
## fill layers, so the count is gone and the PROPERTY is asserted: the plant layer
## owns no id in the registry, whatever else the registry holds.
func _check_layers_unchanged() -> void:
	for id in MapLayers.ids():
		if String(id).contains("plant"):
			_fail("the plant layer registered itself as a map layer: '%s' -- a plant is a draw pass" % id)


## PLACEMENT MODE INTERCEPTS EVERYTHING. A click meant to site a station must not
## also open the nation panel, or one press does two things and the player has
## bought a reactor and changed windows.
func _check_placement_exclusive() -> void:
	var map = _main._map_view
	if map == null:
		return
	var opened: Array[String] = []
	map.nation_clicked.connect(func(id: String): opened.append(id))
	map.city_clicked.connect(func(id: String): opened.append(id))
	map.project_clicked.connect(func(id: String): opened.append(id))
	var picked: Array = []
	map.map_point_picked.connect(func(lon: float, lat: float): picked.append(Vector2(lon, lat)))

	map.begin_placement()
	if not map.is_placing():
		_fail("begin_placement() did not arm placement mode")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = map.size * 0.5
	map._gui_input(ev)

	if picked.size() != 1:
		_fail("a click in placement mode emitted %d points, expected 1" % picked.size())
	if not opened.is_empty():
		_fail("a click in placement mode also opened %s" % [opened])
	if map.is_placing():
		_fail("placement mode did not disarm after the pick -- the next click sites a second plant")


func _fail(msg: String) -> void:
	_failures.append(msg)


func _report() -> void:
	if _failures.is_empty():
		print("test_map_plants: all checks passed")
		quit()
		return
	for f in _failures:
		print("FAIL: %s" % f)
	quit(1)
