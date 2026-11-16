extends SceneTree

## Headless test: godot --headless --script res://tests/test_region_load.gd
## Non-zero exit on any failure.
##
## The Regions map overlay across a load, and the fill around an enclave (the retro UI
## review of 2026-11-17, items 1 and 3):
##   - Continue boots the default game (France) and then loads the save, so an overlay built
##     once at startup kept France's regions: on a Germany save the tab tinted nothing and a
##     click on a German region opened no sheet. A load re-binds the overlay to the loaded
##     nation's regions;
##   - Berlin is a hole in Brandenburg. The fill was triangulated from outer rings only, so
##     Brandenburg's tint was painted over Berlin under Berlin's own;
##   - a click on a city cross opens the tab on that city, and the map stays on the city:
##     the tab's framing of the nation on open (item 12) had jumped it away to the regions;
##   - #391 pass 2: ONE framing owner. A load with the tab open re-frames the loaded nation,
##     "All regions" re-frames it, the arrival card's Open keeps the map on the region it
##     centred, and a load resets the map's measure.
## Driven through main.gd's real load handler, a frame at a time.

const SaveManager = preload("res://src/core/save_manager.gd")
const GameState = preload("res://src/core/game_state.gd")
const Region = preload("res://src/core/region.gd")
const Regions = preload("res://src/sim/regions.gd")
const MapRegions = preload("res://src/ui/map_regions.gd")
const RegionArrival = preload("res://src/ui/region_arrival.gd")

const SLOT := "__test_region_load__"
const BERLIN := "DE3"
const BRANDENBURG := "DE4"
## Alexanderplatz, inside Berlin's ring.
const BERLIN_POINT := Vector2(13.4125, 52.5219)
## Cottbus, in Brandenburg proper: the cut must keep the host's own land filled.
const COTTBUS := Vector2(14.3329, 51.7563)

const PARIS_ID := "FR1_paris"
const PARIS := Vector2(2.3488, 48.8534)

var _paris_before := Vector2.ZERO
var _arrival_region := ""
var _arrival_city := Vector2.ZERO
var _arrival_at := Vector2.ZERO
var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			# The tab is OPEN across the load (#391 pass 2, T1): the rebind must re-frame.
			_main._windows.open("region")
		4:
			var other = GameState.new_game(_main._loader, "DEU", "")
			other.year = _main._clock.year
			other.month = _main._clock.month
			var error := SaveManager.save_game(other, _main._clock, SLOT)
			if error != "":
				_fail("could not save the Germany game: %s" % error)
				_cleanup()
				_finish()
				return true
			# The discarded game's picks, which must not survive the load. "change" too (T4):
			# a save with under two months sampled has no change to tint.
			var panel = _main._windows.content("region")
			panel._game.open_region = "FRE"
			panel._game.fund_share = 0.3
			panel._game.fund_years = 4
			panel._game.fund_refusal = "refused in the old game"
			panel._game.measure = "change"
			_main._map_view.pan_by(Vector2(-300.0, 120.0))
			_main._on_load_requested(SLOT)
			# Read after the load: a load gives the panel a NEW state (#391 second pass 2, T6).
			var g = panel._game
			if g.open_region != "" or g.fund_share != 0.0 or g.fund_years != 0 or g.fund_refusal != "":
				_fail("the old game's open region or fund sums survive the load")
			if g.measure != "jobless":
				_fail("the old game's map measure '%s' survives the load" % g.measure)
		7:
			if not _main._windows.is_open("region"):
				_fail("the premise failed: the load closed the Regions tab")
			_check_framed("a load with the Regions tab open")
			_check_overlay_follows_the_load()
			_check_enclave_not_painted()
			_check_enclave_split_keeps_both_halves()
			_cleanup()
			_main._windows.close_all()
		9:
			# The player has moved the map since the tab last framed the nation.
			_main._map_view.pan_by(Vector2(-300.0, 120.0))
			_paris_before = _main._map_view.lonlat_to_screen(PARIS.x, PARIS.y)
			_main._map_view.city_clicked.emit(PARIS_ID)
		12:
			if String(_main._windows.content("region")._game.city_id) != PARIS_ID:
				_fail("a city click did not open its detail")
			var after: Vector2 = _main._map_view.lonlat_to_screen(PARIS.x, PARIS.y)
			if after.distance_to(_paris_before) > 1.0:
				_fail("a click on Paris moved the map (%s -> %s): the tab reframed the regions" % [_paris_before, after])
			# "All regions" from the city: back on the list, the nation framed again.
			_main._windows.content("region")._back_button.pressed.emit()
		15:
			_check_framed("All regions after a city")
			_main._windows.close_all()
			_main._map_view.pan_by(Vector2(250.0, -90.0))
			_check_arrival_open_centres()
		18:
			var after: Vector2 = _main._map_view.lonlat_to_screen(_arrival_city.x, _arrival_city.y)
			if after.distance_to(_arrival_at) > 1.0:
				_fail("the arrival card's Open centred %s, then the tab's framing moved it (%s -> %s)" % [_arrival_region, _arrival_at, after])
			if String(_main._windows.content("region")._game.open_region) != _arrival_region:
				_fail("the arrival card's Open did not open %s" % _arrival_region)
			# Opened and closed in one frame: the queued framing must not move a map the
			# player has back.
			_main._windows.close_all()
			_main._map_view.pan_by(Vector2(-120.0, 60.0))
			_paris_before = _main._map_view.lonlat_to_screen(PARIS.x, PARIS.y)
			_main._windows.open("region")
			_main._windows.close_all()
		20:
			if _main._map_view.lonlat_to_screen(PARIS.x, PARIS.y).distance_to(_paris_before) > 1.0:
				_fail("a tab opened and closed in one frame still framed the nation")
			_check_refused_city_open_stores_nothing()
			# T1: the tab shows a city, then the arrival card's Open names a region.
			_main._region_panel.open_city(PARIS_ID)
			_arrival_from_a_city()
		23:
			var panel = _main._windows.content("region")
			if String(panel._game.city_id) != "" or String(panel._game.open_region) != _arrival_region:
				_fail("the arrival card's Open over a city left city '%s', region '%s' (wanted %s)" % [panel._game.city_id, panel._game.open_region, _arrival_region])
			if not String(panel._title.text).begins_with(tr("Regions of %s") % ""):
				_fail("the arrival card's Open over a city shows '%s', not the regions" % panel._title.text)
			# T2: a city reached from inside the open region, then "All regions".
			panel.show_city(String(panel._largest_city(_arrival_region).id))
		25:
			_main._windows.content("region")._back_button.pressed.emit()
		28:
			var at: Vector2 = _main._map_view.lonlat_to_screen(_arrival_city.x, _arrival_city.y)
			if at.distance_to(_main._map_view.size / 2.0) > 1.0:
				_fail("All regions from a city inside %s did not come back to the region (its city at %s, the map's centre %s)" % [_arrival_region, at, _main._map_view.size / 2.0])
			_main.queue_free()
		30:
			_finish()
			return true
	return false


## The loaded nation's box centred in the overlay's fit rect: the tab framed it.
func _check_framed(when: String) -> void:
	var overlay = _main._windows.content("region").get("_overlay")
	var box: Rect2 = overlay._bounds
	var at: Vector2 = _main._map_view.lonlat_to_screen(box.get_center().x, box.get_center().y)
	if at.distance_to(overlay.fit_rect.get_center()) > 2.0:
		_fail("%s: the nation is not framed (its centre at %s, the frame's at %s)" % [when, at, overlay.fit_rect.get_center()])


## The inbox card's Open (region_arrival.gd's _on_go), the real handler, on a closed tab: the
## tab opens and the map centres on the region's largest city. The tab's own framing on open
## must not then move the map to the nation.
func _check_arrival_open_centres() -> void:
	var panel = _main._windows.content("region")
	var ns = _main._state.player()
	var regions: Array = _main._loader.regions.get(ns.id, [])
	var access: Dictionary = Regions.accessibility_for(ns, regions, _main._state.region_graph)
	_arrival_region = String(panel.worst_first(_main._state, ns, regions, access)[0].id)
	_arrival_city = panel._largest_city(_arrival_region).lonlat
	RegionArrival._told[_main.get_instance_id()] = {"state_id": _main._state.get_instance_id(), "told": {},
		"cards": {"__test_card__": _arrival_region}, "wired": true}
	RegionArrival._on_go("__test_card__", 0, _main)
	_arrival_at = _main._map_view.lonlat_to_screen(_arrival_city.x, _arrival_city.y)


## T3: an open refused (a scene holds the screen) stores no city for a later open.
func _check_refused_city_open_stores_nothing() -> void:
	var panel = _main._windows.content("region")
	_main._windows.close_all()
	var before := String(panel._game.city_id)
	var scene: Control = _main._windows._pages["summit"]
	scene.show()
	panel.open_city(PARIS_ID)
	scene.hide()
	if _main._windows.is_open("region"):
		_fail("premise: the tab opened over a scene")
	if String(panel._game.city_id) != before:
		_fail("a city open refused under a scene stored '%s' for the next open" % panel._game.city_id)


func _arrival_from_a_city() -> void:
	RegionArrival._told[_main.get_instance_id()]["cards"]["__test_card_2__"] = _arrival_region
	RegionArrival._on_go("__test_card_2__", 0, _main)


## Berlin's hole is cut at its box's centre: Brandenburg land just west AND just east of that
## cut, north of the hole, must both stay filled (a cut that dropped a half would pass Cottbus).
func _check_enclave_split_keeps_both_halves() -> void:
	var overlay = _main._windows.content("region").get("_overlay")
	if not overlay._shapes.has(BRANDENBURG):
		return
	var hole := Rect2()
	for ring: PackedVector2Array in _main._loader.region_features.get(BERLIN, []):
		hole = MapRegions._box(ring) if hole.size == Vector2.ZERO else hole.merge(MapRegions._box(ring))
	var lat := hole.end.y + 0.05
	for p in [Vector2(hole.get_center().x - 0.05, lat), Vector2(hole.get_center().x + 0.05, lat)]:
		if not Region.contains(_main._loader.region_rings.get(BRANDENBURG, []), p.x, p.y):
			_fail("the premise failed: %s is not in Brandenburg" % p)
		elif not _covers(overlay._shapes[BRANDENBURG]["mesh"], p):
			_fail("Brandenburg's fill drops %s, %s of the cut through Berlin" % [p, "west" if p.x < hole.get_center().x else "east"])


func _covers(mesh: ArrayMesh, p: Vector2) -> bool:
	var verts: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0, verts.size() - 2, 3):
		if Geometry2D.point_is_inside_triangle(p, verts[i], verts[i + 1], verts[i + 2]):
			return true
	return false


func _check_overlay_follows_the_load() -> void:
	var panel = _main._windows.content("region")
	var overlay = panel.get("_overlay")
	if _main._state.player_nation_id != "DEU":
		_fail("the premise failed: the loaded game is %s, not DEU" % _main._state.player_nation_id)
		return
	var expected := {}
	for region in _main._loader.regions.get("DEU", []):
		expected[String(region.id)] = true
	var drawn: Array = overlay._shapes.keys()
	var foreign := drawn.filter(func(id): return not expected.has(String(id)))
	if not foreign.is_empty():
		_fail("after loading a Germany save the overlay still draws %d foreign regions (%s ...)" % [foreign.size(), foreign[0]])
	if overlay.drawn_count() < expected.size() - 1:
		_fail("after loading a Germany save the overlay draws %d of Germany's %d regions" % [overlay.drawn_count(), expected.size()])
	var picked := String(_main._map_view.region_picker.call(BERLIN_POINT))
	if picked != BERLIN:
		_fail("a click in Berlin after the load picks '%s', not %s" % [picked, BERLIN])
	# The framing box is the loaded nation's, not France's merged with it.
	var box: Rect2 = overlay._bounds
	if box.has_point(Vector2(-1.0, 46.0)):
		_fail("the overlay's framing box %s still spans France after the load" % box)


func _check_enclave_not_painted() -> void:
	var overlay = _main._windows.content("region").get("_overlay")
	if not overlay._shapes.has(BRANDENBURG):
		_fail("Brandenburg is not drawn")
		return
	var mesh: ArrayMesh = overlay._shapes[BRANDENBURG]["mesh"]
	var verts: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var covers := func(p: Vector2) -> bool:
		for i in range(0, verts.size() - 2, 3):
			if Geometry2D.point_is_inside_triangle(p, verts[i], verts[i + 1], verts[i + 2]):
				return true
		return false
	if covers.call(BERLIN_POINT):
		_fail("Brandenburg's fill covers Berlin, a hole in it: two tints stack over the city")
	if not covers.call(COTTBUS):
		_fail("Brandenburg's fill no longer covers Cottbus: the cut took the host's own land")


func _cleanup() -> void:
	for p in [SaveManager._path_for(SLOT), SaveManager._path_for(SLOT) + SaveManager.TEMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_region_load: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
