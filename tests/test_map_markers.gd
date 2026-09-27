extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_markers.gd
## Non-zero exit on any failure.
##
## U6c, the project marker layer. Loads the actual main scene and drives it a
## frame at a time, test_map_view.gd's idiom, because a Control outside the scene
## tree has not run _ready() -- see docs/engine-decision.md.
##
## What a headless suite CANNOT check here is what the layer looks like; that is
## the screenshot pass's job and is why one exists. What it can check is every
## structural claim U6c makes, and the two worth having are that the marker hit
## test never touches the roster's polygons, and that a marker is not a fifth
## entry in map_layers.LAYERS.

const MapLayers = preload("res://src/ui/map_layers.gd")
const MapMarkers = preload("res://src/ui/map_markers.gd")
const Projects = preload("res://src/sim/projects.gd")

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

	_check_sites_are_content(loader)
	_check_sites_are_inside_their_own_nation(loader)
	_check_absent_block_is_legal(loader)
	_check_markers_follow_the_register(loader, state)
	_check_hit_test_avoids_the_roster(map)
	_check_click_routes_to_the_project(map, state, loader)
	_check_markers_are_not_a_map_layer()


## Every site names a project data/project-actions/ actually ships. Checked here
## rather than in nation.gd, which parses one nation file at a time and has no
## project list at that point.
func _check_sites_are_content(loader) -> void:
	var known := {}
	for action in loader.project_actions:
		var terms: Dictionary = action.effects.get("project", {})
		if String(terms.get("op", "")) == "start":
			known[String(terms.get("project_id", ""))] = true
	if known.is_empty():
		_fail("no start actions loaded, cannot check sites against content")
		return

	var sited := 0
	for id in loader.nations.keys():
		var sites: Dictionary = loader.nations[id].project_sites
		for pid in sites.keys():
			sited += 1
			if not known.has(String(pid)):
				_fail("%s: project_sites names '%s', which no start action defines" % [id, str(pid)])
	if sited == 0:
		_fail("no nation authored a project_sites block at all")


## The stronger content claim, and the one a coordinate typo fails: a site must be
## on its own nation's land. A marker floating in the North Sea is not an error any
## loader could catch, and the geometry is right here.
func _check_sites_are_inside_their_own_nation(loader) -> void:
	for id in loader.nations.keys():
		var nation = loader.nations[id]
		var sites: Dictionary = nation.project_sites
		if sites.is_empty():
			continue
		var rings: Array = loader.geo_features.get(nation.geo_id, [])
		if rings.is_empty():
			_fail("%s: has sites but no polygons" % id)
			continue
		for pid in sites.keys():
			var pt: Vector2 = sites[pid]
			var inside := false
			for ring: PackedVector2Array in rings:
				if ring.size() >= 3 and Geometry2D.is_point_in_polygon(pt, ring):
					inside = true
					break
			if not inside:
				_fail("%s: site '%s' at %s is outside the nation" % [id, str(pid), str(pt)])


## An absent block is a nation with no markers, not an error -- data/companies/'s
## and data/outlets/'s coverage rule. If this ever fails because every nation was
## authored, the assertion to change is this one, deliberately.
func _check_absent_block_is_legal(loader) -> void:
	var without := 0
	for id in loader.nations.keys():
		if loader.nations[id].project_sites.is_empty():
			without += 1
	if without == 0:
		_fail("every nation has sites; the optional-block path is no longer exercised")
	if loader.errors.size() > 0:
		_fail("loader reported %d errors with the sites in place" % loader.errors.size())


## The marker list is derived, never stored: nothing at a new game, one while a
## project builds, one still there once it is finished, none after an abandon.
func _check_markers_follow_the_register(loader, state) -> void:
	var ns = state.player()
	if ns == null:
		_fail("no player nation")
		return

	if MapMarkers.markers(loader, state).size() != 0:
		_fail("a new game drew markers before anything was begun")

	var start = _find_action(loader, "flood_defence", "start")
	var abandon = _find_action(loader, "flood_defence", "abandon")
	if start == null or abandon == null:
		_fail("flood_defence has no start/abandon pair")
		return

	Projects.execute(state, ns, loader.project_actions, start)
	var building: Array = MapMarkers.markers(loader, state)
	if building.size() != 1:
		_fail("expected one marker while building, got %d" % building.size())
		return
	if bool(building[0]["built"]):
		_fail("a project under construction drew as finished")
	if int(building[0]["months_left"]) <= 0:
		_fail("a marker under construction reported no months left")
	if String(building[0]["nation_id"]) != state.player_nation_id:
		_fail("the marker was attributed to '%s'" % String(building[0]["nation_id"]))

	# Long enough for the shortest project on the ladder to finish.
	for i in range(200):
		Projects.tick_month(state, loader)
	var done: Array = MapMarkers.markers(loader, state)
	if done.size() != 1 or not bool(done[0]["built"]):
		_fail("a completed project did not draw as finished")

	# Abandoning is only legal while building, so restart the clock on a second
	# project rather than trying to abandon the finished one.
	var other_start = _find_action(loader, "national_fibre", "start")
	var other_abandon = _find_action(loader, "national_fibre", "abandon")
	if other_start == null or other_abandon == null:
		_fail("national_fibre has no start/abandon pair")
		return
	Projects.execute(state, ns, loader.project_actions, other_start)
	var two: Array = MapMarkers.markers(loader, state)
	Projects.execute(state, ns, loader.project_actions, other_abandon)
	var one: Array = MapMarkers.markers(loader, state)
	if two.size() != one.size() + 1:
		_fail("abandoning did not remove exactly one marker (%d -> %d)" % [two.size(), one.size()])


## U5b's structural guarantee, and the reason U6c has its own hit test at all.
## `_nation_at_lonlat()` iterates `_polygons` alone, so a marker test routed
## through it would make that function answer for two things and the property
## would die the first time someone widened it. Read from the source, the idiom
## tests/test_projects.gd uses for "calendar.gd is still a leaf".
func _check_hit_test_avoids_the_roster(map) -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/map_view.gd")
	if src == "":
		_fail("could not read map_view.gd to check the hit test")
		return
	var at := src.find("func _project_at_screen_point(")
	if at < 0:
		_fail("map_view.gd has no _project_at_screen_point()")
		return
	var body := src.substr(at)
	var ends := body.find("\nfunc ", 1)
	if ends > 0:
		body = body.substr(0, ends)
	for banned in ["_nation_at_lonlat", "_polygons", "nation_at_screen_point"]:
		if body.find(banned) >= 0:
			_fail("_project_at_screen_point() reaches %s; U5b's structural guarantee dies" % banned)

	# And the roster's own test still answers as it did: a marker sits on top of
	# its nation and must not have hijacked the nation hit test.
	var site := _first_site(_main._loader, map)
	if site == Vector2.INF:
		return
	var screen: Vector2 = map._lonlat_to_screen(site.x, site.y)
	if map.nation_at_screen_point(screen) != _main._state.player_nation_id:
		_fail("a point under a marker no longer hit-tests as its own nation")


## A click on a marker is a project click and NOT a nation click, or one press
## opens two windows.
func _check_click_routes_to_the_project(map, state, loader) -> void:
	var ns = state.player()
	var start = _find_action(loader, "high_speed_rail", "start")
	if start == null:
		_fail("high_speed_rail has no start action")
		return
	Projects.execute(state, ns, loader.project_actions, start)
	map._refresh_markers()

	var sites: Dictionary = loader.nations[state.player_nation_id].project_sites
	if not sites.has("high_speed_rail"):
		_fail("the player's nation has no high_speed_rail site")
		return
	var lonlat: Vector2 = sites["high_speed_rail"]
	var screen: Vector2 = map._lonlat_to_screen(lonlat.x, lonlat.y)

	if map._project_at_screen_point(screen) != "high_speed_rail":
		_fail("a point on the site did not hit its own marker")

	var far: Vector2 = screen + Vector2(500, 500)
	if map._project_at_screen_point(far) != "":
		_fail("a point far from every marker hit one")

	var projects_seen: Array[String] = []
	var nations_seen: Array[String] = []
	map.project_clicked.connect(func(pid: String): projects_seen.append(pid))
	map.nation_clicked.connect(func(nid: String): nations_seen.append(nid))

	_click(map, screen)
	if projects_seen != ["high_speed_rail"]:
		_fail("clicking a marker emitted %s" % str(projects_seen))
	if not nations_seen.is_empty():
		_fail("clicking a marker also emitted nation_clicked %s" % str(nations_seen))


## A marker is an always-on overlay, NOT a map layer. If a later session makes it
## one, this turns red and that session has to come and say why -- the reasons are
## in map_markers.gd's header.
##
## V4.6: THE COUNT WAS A PROXY. This read `LAYERS.size() != 4` until Task 4 added
## two genuine per-nation fill layers (production, import dependency), which the
## registry SHOULD hold and this check has no reason to refuse -- the count would
## have failed on that growth rather than on a marker becoming a layer. The
## property is what is asserted now: no registry entry is a marker, whatever else
## the registry holds. The source scan below is unchanged and still the sharper
## half, because it catches the id being introduced under another name.
func _check_markers_are_not_a_map_layer() -> void:
	for id in MapLayers.ids():
		if String(id).contains("marker"):
			_fail("the marker overlay registered itself as a map layer: '%s'" % id)
	var src := FileAccess.get_file_as_string("res://src/ui/map_layers.gd")
	if src.findn("marker") >= 0:
		_fail("map_layers.gd mentions markers; the registry does not know about them")


# --- helpers -----------------------------------------------------------------

func _find_action(loader, project_id: String, op: String):
	for action in loader.project_actions:
		var terms: Dictionary = action.effects.get("project", {})
		if String(terms.get("project_id", "")) == project_id and String(terms.get("op", "")) == op:
			return action
	return null


func _first_site(loader, _map) -> Vector2:
	var sites: Dictionary = loader.nations[_main._state.player_nation_id].project_sites
	for pid in sites.keys():
		return sites[pid]
	return Vector2.INF


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
		print("test_map_markers: OK")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	printerr("test_map_markers: %d failure(s)" % _failures.size())
	quit(1)
