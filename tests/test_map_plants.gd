extends SceneTree

## V2.8. Placement mode's exclusivity, the hit test's purity, and the pin that says
## a plant is a DRAW PASS and not a fifth map layer.
##
## Driven a frame at a time because a Control outside the scene tree has not run
## _ready() -- tests/test_shell.gd's idiom, and the reason a one-shot _init() here
## would assert against a tree of nulls.

const Main = preload("res://src/ui/main.tscn")
const MapLayers = preload("res://src/ui/map_layers.gd")

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
	_check_source_purity()
	_check_layers_unchanged()
	_check_placement_exclusive()
	_report()
	return true


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
