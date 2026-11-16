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
##     the tab's framing of the nation on open (item 12) had jumped it away to the regions.
## Driven through main.gd's real load handler, a frame at a time.

const SaveManager = preload("res://src/core/save_manager.gd")
const GameState = preload("res://src/core/game_state.gd")

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
			var other = GameState.new_game(_main._loader, "DEU", "")
			other.year = _main._clock.year
			other.month = _main._clock.month
			var error := SaveManager.save_game(other, _main._clock, SLOT)
			if error != "":
				_fail("could not save the Germany game: %s" % error)
				_cleanup()
				_finish()
				return true
			# The discarded game's open region and fund sums, which must not survive the load.
			var panel = _main._windows.content("region")
			panel._open_region = "FRE"
			panel._fund_share = 0.3
			panel._fund_years = 4
			panel._fund_refusal = "refused in the old game"
			_main._on_load_requested(SLOT)
			if panel._open_region != "" or panel._fund_share != 0.0 or panel._fund_years != 0 or panel._fund_refusal != "":
				_fail("the old game's open region or fund sums survive the load")
		4:
			_main._windows.open("region")
		6:
			_check_overlay_follows_the_load()
			_check_enclave_not_painted()
			_cleanup()
			_main._windows.close_all()
		8:
			# The player has moved the map since the tab last framed the nation.
			_main._map_view.pan_by(Vector2(-300.0, 120.0))
			_paris_before = _main._map_view.lonlat_to_screen(PARIS.x, PARIS.y)
			_main._map_view.city_clicked.emit(PARIS_ID)
		11:
			if String(_main._windows.content("region")._city_id) != PARIS_ID:
				_fail("a city click did not open its detail")
			var after: Vector2 = _main._map_view.lonlat_to_screen(PARIS.x, PARIS.y)
			if after.distance_to(_paris_before) > 1.0:
				_fail("a click on Paris moved the map (%s -> %s): the tab reframed the regions" % [_paris_before, after])
			_main.queue_free()
		13:
			_finish()
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
