extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_ownership.gd
## Non-zero exit on any failure.
##
## V5.1a QA. The accent is the PLAYED nation's identity, and the map draws every
## nation's cities, project markers and power plants: with one colour for all of
## them, zoomed in, Bucharest and Madrid wore France's blue. The accent goes on the
## player's own marks only; every other nation's are the neutral map tone.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const MapCities = preload("res://src/ui/map_cities.gd")
const MapMarkers = preload("res://src/ui/map_markers.gd")
const MapPlants = preload("res://src/ui/map_plants.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check_colours()
	_check_the_lists_know_who_owns_what()
	_finish()
	return false


func _check_colours() -> void:
	if UiTheme.MAP_NEUTRAL == UiTheme.accent():
		_fail("the neutral map tone is the accent, so ownership cannot show")
	if MapCities.color_of({"own": true}) != UiTheme.accent():
		_fail("the player's own city is not drawn in the accent")
	if MapCities.color_of({"own": false}) != UiTheme.MAP_NEUTRAL:
		_fail("another nation's city is not drawn in the neutral map tone")
	if MapMarkers.color_of({"own": true}) != UiTheme.accent():
		_fail("the player's own project marker is not drawn in the accent")
	if MapMarkers.color_of({"own": false}) != UiTheme.MAP_NEUTRAL:
		_fail("another nation's project marker is not drawn in the neutral map tone")
	if MapPlants.color_of("FRA", "FRA") != UiTheme.accent():
		_fail("the player's own plant is not drawn in the accent")
	if MapPlants.color_of("DEU", "FRA") != UiTheme.MAP_NEUTRAL:
		_fail("another nation's plant is not drawn in the neutral map tone")


## The real lists carry the flag, so the draw path has what it needs.
func _check_the_lists_know_who_owns_what() -> void:
	var state = _main._state
	var player: String = state.player_nation_id
	var cities: Array = MapCities.cities(_main._loader, state)
	var own := 0
	for city in cities:
		if bool(city.get("own", false)) != (String(city["nation_id"]) == player):
			_fail("city %s of %s has own=%s" % [city["city_id"], city["nation_id"], city.get("own")])
			break
		if bool(city.get("own", false)):
			own += 1
	if own == 0 or own == cities.size():
		_fail("the city list has %d own of %d: the flag does not discriminate" % [own, cities.size()])


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_map_ownership: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
