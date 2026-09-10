extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_view.gd
## Non-zero exit on any failure.
##
## Loads the actual main scene, same shape test_law_panel.gd and
## test_election_panel.gd use. Driven a frame at a time because a Control
## outside the scene tree has not run _ready() and signals don't emit -- see
## docs/engine-decision.md.

const MapLayers = preload("res://src/ui/map_layers.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _stage: int = 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	if _frame == 2:
		_run()

	# V3.4's staged checks hold the report back until each has had its own
	# settled frame; a run that never built a map view has nothing to stage and
	# has already recorded that failure in _run().
	if _main._map_view == null or _check_roads_staged():
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
	_check_world_geometry(loader, map)
	_check_raster(map)
	_check_projection_and_hit_test(map)
	_check_pan_zoom(map)
	_check_camera(map)
	_check_layer_state(map)
	_check_click_opens_panel_with_live_values(map)
	_check_roads_take_no_clicks()


func _check_geometry(loader) -> void:
	if loader.geo_features.size() != 29:
		_fail("expected geometry for 29 features, loaded %d" % loader.geo_features.size())
	for id in loader.nations.keys():
		var n = loader.nations[id]
		var polys: Array = loader.geo_features.get(n.geo_id, [])
		if polys.is_empty():
			_fail("%s: no polygons loaded for geo_id '%s'" % [id, n.geo_id])
			continue
		for ring in polys:
			if ring.size() < 3:
				_fail("%s: an outer ring has fewer than 3 points" % id)


## U5b's backdrop. The assertion that matters is the *negative* one: a country the
## game does not simulate must hit-test to nothing, which is what makes "the edge
## of the game is visible without a click that leads nowhere" true rather than
## aspirational.
func _check_world_geometry(loader, map) -> void:
	if loader.world_features.is_empty():
		_fail("no world features loaded -- data/geo/world.geojson missing or unparsed")
		return
	if loader.world_features.size() < 100:
		_fail("only %d world features loaded, expected well over 100" % loader.world_features.size())

	for id in loader.nations.keys():
		var geo_id: String = loader.nations[id].geo_id
		if loader.world_features.has(geo_id):
			_fail("%s is in both europe.geojson and world.geojson; it would be drawn twice" % geo_id)

	# Oslo. Inside Norway, which the game renders and does not simulate. (This
	# point was Warsaw through the ten-nation era, because Poland itself was
	# backdrop then; V3.3's roster made Poland a nation and the negative case
	# moved north with it.)
	var oslo: Vector2 = map._lonlat_to_screen(10.75, 59.9)
	var hit: String = map.nation_at_screen_point(oslo)
	if hit != "":
		_fail("a point inside a non-simulated country hit-tested as '%s'" % hit)

	# Every nation the labels name must be one of the ten.
	for id in map._labels.keys():
		if not loader.nations.has(id):
			_fail("map labels a nation that is not in the roster: '%s'" % id)
	if map._labels.size() != loader.nations.size():
		_fail("expected a label point for all %d nations, got %d" % [loader.nations.size(), map._labels.size()])


## The fresh-clone check, and the reason map_raster.gd decodes bytes rather than
## calling load(). A load()-based raster passes in the editor and fails here.
func _check_raster(map) -> void:
	if map._texture == null:
		_fail("map raster did not load -- assets/map/ missing, or loaded via load() instead of from bytes")
		return
	if map._texture.get_width() < 1000:
		_fail("map raster is %d px wide, far below the shipped asset" % map._texture.get_width())


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

	# V3.3's bbox pre-reject must be behaviour-invisible: a lon/lat grid over
	# the roster's full extent, tested against a naive full scan of the same
	# polygons, agrees everywhere or the reject is answering a different
	# question than the rings are.
	var grid_hits := 0
	var lon := -12.0
	while lon <= 35.0:
		var lat := 34.0
		while lat <= 71.0:
			var pt := Vector2(lon, lat)
			var rejected: String = map._nation_at_lonlat(pt)
			var naive := ""
			for id in map._polygons.keys():
				if naive != "":
					break
				for naive_ring: PackedVector2Array in map._polygons[id]:
					if naive_ring.size() >= 3 and Geometry2D.is_point_in_polygon(pt, naive_ring):
						naive = id
						break
			if rejected != naive:
				_fail("bbox pre-reject disagrees with a full scan at %.2f,%.2f: '%s' vs '%s'" % [lon, lat, rejected, naive])
			if rejected != "":
				grid_hits += 1
			lat += 0.5
		lon += 0.5
	if grid_hits < 29:
		_fail("grid found only %d nation-hitting points across 29 nations" % grid_hits)


func _check_pan_zoom(map) -> void:
	var zoom_before: float = map._zoom
	var pan_before: Vector2 = map._pan_offset

	# A small pan, well inside the world, so the clamp has nothing to do and the
	# delta arrives intact. A pan large enough to hit the clamp is checked below.
	map.pan_by(Vector2(37, -19))
	if not (map._pan_offset - (pan_before + Vector2(37, -19))).is_zero_approx():
		_fail("pan_by did not move _pan_offset by the given delta")

	map.zoom_by(1.5, map._control_center())
	if is_equal_approx(map._zoom, zoom_before):
		_fail("zoom_by did not change _zoom")
	if map._zoom > map.MAX_ZOOM or map._zoom < map.min_zoom():
		_fail("zoom_by produced an out-of-range zoom: %s" % map._zoom)

	# Clamp holds even for an extreme factor.
	map.zoom_by(1000.0, map._control_center())
	if map._zoom > map.MAX_ZOOM:
		_fail("zoom_by did not clamp to MAX_ZOOM")

	map.zoom_by(0.00001, map._control_center())
	if map._zoom < map.min_zoom() - 0.0001:
		_fail("zoom_by went below the cover fit: %s < %s" % [map._zoom, map.min_zoom()])

	# Reset so the click test below hit-tests against the original projection.
	map._pan_offset = pan_before
	map._zoom = zoom_before


## The camera surface U5b added, and the one it changed. min_zoom() is derived
## from the control's size rather than being a constant, so the furthest zoom out
## is exactly the whole world -- assert that, not a number.
func _check_camera(map) -> void:
	var zoom_before: float = map._zoom
	var pan_before: Vector2 = map._pan_offset

	if map.size.x <= 0.0 or map.size.y <= 0.0:
		_fail("map view has no size; the camera checks below would be meaningless")
		return

	# At exactly min_zoom the world covers the control on both axes, with no
	# margin to spare on the tighter one.
	map._zoom = map.min_zoom()
	map._clamp_pan()
	var visible: Rect2 = map.visible_lonlat_rect()
	if visible.size.x > 360.5 and visible.size.y > 180.5:
		_fail("at min_zoom the view is larger than the world on both axes: %s" % visible.size)
	if visible.size.x < 359.5 and visible.size.y < 179.5:
		_fail("at min_zoom the world does not cover the control on either axis: %s" % visible.size)

	# Panning far past the edge cannot leave the world behind.
	map.pan_by(Vector2(100000, 100000))
	var clamped: Rect2 = map.visible_lonlat_rect()
	if clamped.position.x < -181.0 or clamped.position.x + clamped.size.x > 181.0:
		_fail("pan escaped the world in longitude: %s" % clamped)
	if clamped.position.y < -91.0 or clamped.position.y + clamped.size.y > 91.0:
		_fail("pan escaped the world in latitude: %s" % clamped)

	# center_on_lonlat puts the point under the control centre. Zoomed in, so the
	# clamp is not what decides where the view ends up.
	map._zoom = 4.0
	map.center_on_lonlat(2.35, 48.86)  # Paris
	var back: Vector2 = map._screen_to_lonlat(map._control_center())
	if absf(back.x - 2.35) > 0.01 or absf(back.y - 48.86) > 0.01:
		_fail("center_on_lonlat(2.35, 48.86) left %s under the control centre" % back)

	# Zooming in shrinks the window, which is what the minimap's rectangle reads.
	var wide: Rect2 = map.visible_lonlat_rect()
	map.zoom_by(2.0, map._control_center())
	var close: Rect2 = map.visible_lonlat_rect()
	if close.size.x >= wide.size.x or close.size.y >= wide.size.y:
		_fail("zooming in did not shrink visible_lonlat_rect: %s -> %s" % [wide.size, close.size])

	map._pan_offset = pan_before
	map._zoom = zoom_before


## U5c's half of the map's own contract. The ramps themselves are
## tests/test_map_layers.gd's; what belongs here is that this control asks the
## registry rather than colouring anything itself, and that **hover does not
## touch the fill on a data layer** -- U5b's hover lifted it toward the accent,
## which on the political layer picks a country out and on a relations layer
## would say a pair is warmer than it is.
func _check_layer_state(map) -> void:
	if map.layer() != MapLayers.POLITICAL:
		_fail("the map did not open on the political layer, but on '%s'" % map.layer())

	var viewer: String = map.viewer_id()
	if viewer != _main._state.player_nation_id:
		_fail("map viewer is '%s', not the player nation" % viewer)

	map.set_layer(MapLayers.RELATIONS)
	if map.layer() != MapLayers.RELATIONS:
		_fail("set_layer did not take")

	var hovered_before: String = map._hovered_id
	var target := "DEU" if viewer != "DEU" else "FRA"

	var plain: Color = MapLayers.color_for(map.layer(), _main._state, viewer, target)
	map._hovered_id = target
	var hovered: Color = MapLayers.color_for(map.layer(), _main._state, viewer, target)
	if not plain.is_equal_approx(hovered):
		_fail("hovering %s changed its fill on a data layer: %s -> %s" % [target, plain, hovered])

	# And the fill is the ramp at that pair's live score, not a table in this
	# control -- the end-to-end version of "one place picks a fill colour".
	var expected := MapLayers.ramp(
		MapLayers.RELATIONS, Diplomacy.score(_main._state, viewer, target)
	)
	expected.a = MapLayers.alpha(MapLayers.RELATIONS)
	if not plain.is_equal_approx(expected):
		_fail("%s's fill is %s, the ramp at its live score is %s" % [target, plain, expected])

	map._hovered_id = hovered_before
	map.set_layer(MapLayers.POLITICAL)


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


## V3.4. Two properties, each needing its own settled frame.
##
## Staged rather than called inline because queue_redraw() is a REQUEST: the
## pass runs when the engine next draws this control, and reading the counter in
## the same frame reads the frame before it. Calling _draw() by hand instead is
## worse than useless -- draw_line() outside NOTIFICATION_DRAW is an engine
## error, so the "test" would measure a function that drew nothing.
##
## Returns true once every stage has been asserted.
func _check_roads_staged() -> bool:
	var map = _main._map_view
	match _stage:
		0:
			# ROADS ARE GATED ON THE CITY THRESHOLD, and it is the SAME number
			# rather than a second one. A spine ends on two principal cities, so
			# a spine drawn when neither glyph is drawn is a line from nowhere to
			# nowhere -- structural, which is why nothing was swept for it.
			map.set_zoom_for_test(map.CITY_MIN_ZOOM - 0.2)
			_stage = 1
		1:
			if map.spines_drawn() != 0:
				_fail("%d spines drawn below CITY_MIN_ZOOM" % map.spines_drawn())
			map.set_zoom_for_test(map.CITY_MIN_ZOOM + 0.2)
			_stage = 2
		2:
			if map.spines_drawn() <= 0:
				_fail("no spines drawn above CITY_MIN_ZOOM -- the pass is not wired")
			# THE CULL IS ASSERTED BY COUNT, NOT BY EYE. A pass that transforms
			# first and culls second draws the identical picture, costs the whole
			# roster, and no frame would say so -- so the failing case is a count
			# of exactly 463 and the bound has to sit below it.
			#
			# The bound is a FRACTION rather than a figure, because the figure
			# depends on the window: MAX_ZOOM is 8.0 and BASE_SCALE 12, so at the
			# project's 1920x1080 the view at max zoom is ~20 deg by ~11 deg --
			# France, Benelux, western Germany and northern Italy, which is a
			# large minority of the roster and not a handful. A hard number here
			# would be a test of the window size.
			map.set_zoom_for_test(map.MAX_ZOOM)
			map.center_on_lonlat(2.35, 48.86)
			_stage = 3
		3:
			var total: int = map.spine_count()
			if map.spines_drawn() >= total:
				_fail("all %d spines drew at max zoom -- the pass transforms before it culls" % total)
			elif map.spines_drawn() > int(total * 0.6):
				_fail("%d of %d spines survived the cull at max zoom over Paris -- not viewport-bounded" % [map.spines_drawn(), total])
			elif map.spines_drawn() <= 0:
				_fail("no spines at all at max zoom over Paris -- the cull is rejecting everything")
			return true
	return false


## A ROAD SWALLOWS NO CLICKS. The chain is placement -> plants -> projects ->
## cities -> nations and this block adds nothing to it. Read from the source the
## way tests/test_map_cities.gd and tests/test_map_plants.gd read theirs: a hit
## test that learned about spines would be a hit test answering for two things.
func _check_roads_take_no_clicks() -> void:
	var text := FileAccess.get_file_as_string("res://src/ui/map_view.gd")
	for fn in ["func _city_at_screen_point", "func _nation_at_lonlat", "func _project_at_screen_point", "func _plant_at_screen_point"]:
		var start := text.find(fn)
		if start < 0:
			_fail("map_view.gd has no %s()" % fn)
			continue
		var stop := text.find("\nfunc ", start + 1)
		var body := text.substr(start, stop - start if stop > start else -1)
		for forbidden in ["_spines", "MapNetwork"]:
			if body.contains(forbidden):
				_fail("%s() reaches %s -- a road takes no clicks" % [fn, forbidden])


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
