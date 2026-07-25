extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_view.gd
## Non-zero exit on any failure.
##
## Loads the actual main scene, same shape test_law_panel.gd and
## test_election_panel.gd use. Driven a frame at a time because a Control
## outside the scene tree has not run _ready() and signals don't emit -- see
## docs/engine-decision.md.

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
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return
	if _main._map_view == null:
		_fail("main scene did not build a map view")
		return
	if _main._nation_panel == null:
		_fail("main scene did not build a nation panel")
		return

	var loader = _main._loader
	var map = _main._map_view

	_check_geometry(loader)
	_check_projection_and_hit_test(map)
	_check_pan_zoom(map)
	_check_click_opens_panel_with_live_values(map)


func _check_geometry(loader) -> void:
	if loader.geo_features.size() != 10:
		_fail("expected geometry for 10 features, loaded %d" % loader.geo_features.size())
	for id in loader.nations.keys():
		var n = loader.nations[id]
		var polys: Array = loader.geo_features.get(n.geo_id, [])
		if polys.is_empty():
			_fail("%s: no polygons loaded for geo_id '%s'" % [id, n.geo_id])
			continue
		for ring in polys:
			if ring.size() < 3:
				_fail("%s: an outer ring has fewer than 3 points" % id)


func _check_projection_and_hit_test(map) -> void:
	var polys: Array = map._polygons.get("FRA", [])
	if polys.is_empty():
		_fail("no polygon loaded for FRA, cannot test hit-testing")
		return

	var ring: PackedVector2Array = polys[0]
	var centroid := Vector2.ZERO
	for p in ring:
		centroid += p
	centroid /= ring.size()

	# The centroid of a ring is not guaranteed to be inside a concave shape,
	# but France's mainland outline is convex enough near its centre for this
	# to hold -- confirmed empirically rather than asserted geometrically.
	var screen_point: Vector2 = map._lonlat_to_screen(centroid.x, centroid.y)
	var hit: String = map.nation_at_screen_point(screen_point)
	if hit != "FRA":
		_fail("expected FRA's own centroid to hit-test as FRA, got '%s'" % hit)

	var far_away := Vector2(-100000, -100000)
	var miss: String = map.nation_at_screen_point(far_away)
	if miss != "":
		_fail("expected a point far outside every polygon to hit nothing, got '%s'" % miss)


func _check_pan_zoom(map) -> void:
	var zoom_before: float = map._zoom
	var pan_before: Vector2 = map._pan_offset

	map.pan_by(Vector2(37, -19))
	if not (map._pan_offset - (pan_before + Vector2(37, -19))).is_zero_approx():
		_fail("pan_by did not move _pan_offset by the given delta")

	map.zoom_by(1.5, map._control_center())
	if is_equal_approx(map._zoom, zoom_before):
		_fail("zoom_by did not change _zoom")
	if map._zoom > map.MAX_ZOOM or map._zoom < map.MIN_ZOOM:
		_fail("zoom_by produced an out-of-range zoom: %s" % map._zoom)

	# Clamp holds even for an extreme factor.
	map.zoom_by(1000.0, map._control_center())
	if map._zoom > map.MAX_ZOOM:
		_fail("zoom_by did not clamp to MAX_ZOOM")

	# Reset so the click test below hit-tests against the original projection.
	map._pan_offset = pan_before
	map._zoom = zoom_before


func _check_click_opens_panel_with_live_values(map) -> void:
	var ns = _main._state.player()  # FRA
	var n = _main._loader.nations["FRA"]

	# Move GDP away from the static data file's figure, so the panel can only
	# be showing live simulation values if it displays the moved number.
	ns.gdp_eur_bn += 123.0

	var polys: Array = map._polygons.get("FRA", [])
	var ring: PackedVector2Array = polys[0]
	var centroid := Vector2.ZERO
	for p in ring:
		centroid += p
	centroid /= ring.size()
	var screen_point: Vector2 = map._lonlat_to_screen(centroid.x, centroid.y)

	map._gui_input(_mouse_event(MOUSE_BUTTON_LEFT, true, screen_point))
	map._gui_input(_mouse_event(MOUSE_BUTTON_LEFT, false, screen_point))

	if not _main._nation_panel.visible:
		_fail("clicking a nation on the map did not open the nation panel")
		return

	_main._nation_panel._process(0.0)
	var text := _collect_text(_main._nation_panel)

	if not text.contains(n.nation_name):
		_fail("nation panel does not show the clicked nation's name: %s" % text)

	var live_gdp_text := "%.0f" % ns.gdp_eur_bn
	if not text.contains(live_gdp_text):
		_fail("nation panel does not show the live GDP figure (%s): %s" % [live_gdp_text, text])

	var static_gdp_text := "%.0f" % n.gdp_eur_bn
	if static_gdp_text != live_gdp_text and text.contains(static_gdp_text):
		_fail("nation panel shows the static data GDP figure instead of the live one: %s" % text)


func _mouse_event(button: int, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	return e


func _collect_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_map_view: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
