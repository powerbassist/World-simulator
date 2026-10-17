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
const Motion = preload("res://src/ui/motion.gd")

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
	_check_outline_hover(map)
	_check_pan_zoom(map)
	_check_camera(map)
	_check_layer_state(map)
	_check_click_opens_panel_with_live_values(map)
	_check_roads_take_no_clicks()
	_check_draw_order_and_labels()
	_check_legend_key_samples()


## B6, read from source the way _check_roads_take_no_clicks() reads: draw order
## is a literal sequence in _draw() and a headless suite cannot photograph it.
## Labels must ride ABOVE the city crosses (a brass cross over near-white text
## buried the name) and BELOW the interactive pins, which stay last.
func _check_draw_order_and_labels() -> void:
	var text := FileAccess.get_file_as_string("res://src/ui/map_view.gd")
	var draw_start := text.find("func _draw()")
	var draw_stop := text.find("\nfunc ", draw_start + 1)
	var body := text.substr(draw_start, draw_stop - draw_start)
	var cities := body.find("_draw_cities()")
	var labels := body.find("_draw_labels()")
	var markers := body.find("_draw_markers()")
	if cities < 0 or labels < 0 or markers < 0:
		_fail("_draw() is missing one of the cities/labels/markers passes")
		return
	if labels <= cities:
		_fail("_draw_labels() must come AFTER _draw_cities() -- the crosses drew over the country names (B6)")
	if markers <= labels:
		_fail("_draw_markers() must stay LAST -- interactive pins stay on top of text")
	# The contrast half of B6 lives in _draw_labels(): the near-white labels now
	# carry a draw_string_outline halo, and the 1px offset shadow it replaced is
	# gone (outline + shadow would double-darken every glyph edge).
	var labels_start := text.find("func _draw_labels()")
	var labels_stop := text.find("\nfunc ", labels_start + 1)
	var labels_body := text.substr(labels_start, labels_stop - labels_start)
	if not labels_body.contains("draw_string_outline"):
		_fail("_draw_labels() does not draw a draw_string_outline halo")
	if labels_body.contains("+ Vector2.ONE"):
		_fail("_draw_labels() still draws the old 1px offset shadow alongside the outline")


## B11: the legend's key samples draw opaque KEY_* colours at 2px, not
## MapNetwork's alpha 0.30/0.42 at 1px, which vanished on the dark plate.
## Read from source; the samples draw inside a lambda a headless suite cannot
## inspect on a built control.
func _check_legend_key_samples() -> void:
	var text := FileAccess.get_file_as_string("res://src/ui/map_legend.gd")
	var start := text.find("func _key_row")
	var stop := text.find("\nfunc ", start + 1)
	var body := text.substr(start, stop - start)
	if body.contains("MapNetwork.LAND") or body.contains("MapNetwork.SEA"):
		_fail("_key_row() samples still use MapNetwork.LAND/SEA -- invisible at alpha 0.30/0.42 on the dark plate")
	for key in ["KEY_LAND", "KEY_SEA", "KEY_WIDTH"]:
		if not body.contains(key):
			_fail("_key_row() does not use %s" % key)
	for key in ["KEY_LAND", "KEY_SEA"]:
		var line_start := text.find("const %s := Color(" % key)
		if line_start < 0:
			_fail("map_legend.gd has no const %s" % key)
			continue
		var open := text.find("(", line_start)
		var close := text.find(")", open)
		var parts := text.substr(open + 1, close - open - 1).split(",")
		if parts.size() == 4 and parts[3].to_float() < 0.9:
			_fail("%s alpha %s < 0.9 -- the key sample must be opaque to read on the plate" % [key, parts[3]])
	if not text.contains("const KEY_WIDTH := 2.0"):
		_fail("KEY_WIDTH is not 2.0 -- a 1px sample does not read at 22x8")


func _check_geometry(loader) -> void:
	if loader.geo_features.size() != loader.nations.size():
		_fail("expected geometry for %d features, loaded %d" % [loader.nations.size(), loader.geo_features.size()])
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

	# Kaliningrad. Inside Russia's exclave, which the game renders and does not
	# simulate. (This point was Warsaw through the ten-nation era and Oslo from
	# V3.3; each roster growth made the old probe a nation, and V4.11's
	# neighbourhood took Norway. The exclave is the strongest negative case left:
	# on screen at the opening fit and walled in by POL and LTU, so a hit-test
	# that leaked a neighbour's ring across the border would fire here.)
	var outside: Vector2 = map._lonlat_to_screen(20.51, 54.71)
	var hit: String = map.nation_at_screen_point(outside)
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


## V4.11c. An outline answers a HOVER through its own test and nothing else: no
## nation hover, no click, and `_nation_at_lonlat` still never reads the outline
## register -- "you cannot click Poland", restated for the block that made
## outlines readable.
func _check_outline_hover(map) -> void:
	var outline_id := ""
	var pt := Vector2.ZERO
	var ids: Array = map._world_polygons.keys()
	ids.sort()
	for id in ids:
		for ring: PackedVector2Array in map._world_polygons[id]:
			if ring.size() < 50:
				continue
			var c := Vector2.ZERO
			for q in ring:
				c += q
			c /= ring.size()
			if Geometry2D.is_point_in_polygon(c, ring) and map._nation_at_lonlat(c) == "":
				outline_id = id
				pt = c
				break
		if outline_id != "":
			break
	if outline_id == "":
		_fail("no outline ring with an inside centroid -- cannot test the outline hover")
		return
	if map._outline_at_lonlat(pt) != outline_id:
		_fail("the outline test missed %s at its own centroid (got '%s')" % [outline_id, map._outline_at_lonlat(pt)])

	var hovered: Array = []
	var clicked: Array = []
	var on_hover := func(id: String) -> void: hovered.append(id)
	var on_click := func(id: String) -> void: clicked.append(id)
	map.nation_hovered.connect(on_hover)
	map.nation_clicked.connect(on_click)
	var screen: Vector2 = map._lonlat_to_screen(pt.x, pt.y)
	var move := InputEventMouseMotion.new()
	move.position = screen
	map._gui_input(move)
	if map._hovered_outline != outline_id:
		_fail("hovering %s set the outline hover to '%s'" % [outline_id, map._hovered_outline])
	if map._hovered_id != "" or hovered.has(outline_id):
		_fail("hovering the outline %s reached the nation hover" % outline_id)
	map._gui_input(_mouse_event(MOUSE_BUTTON_LEFT, true, screen))
	map._gui_input(_mouse_event(MOUSE_BUTTON_LEFT, false, screen))
	if not clicked.is_empty():
		_fail("a click on the outline %s emitted nation_clicked %s" % [outline_id, str(clicked)])
	# Leaving the map takes the readout with it -- no later motion would.
	map._gui_input(move)
	map.notification(Control.NOTIFICATION_MOUSE_EXIT)
	if map._hovered_outline != "":
		_fail("the outline readout outlived the cursor leaving the map ('%s')" % map._hovered_outline)

	# A roster nation under the cursor wins: the readout never competes with one.
	var fra: PackedVector2Array = map._polygons["FRA"][0]
	var fc := Vector2.ZERO
	for q in fra:
		fc += q
	fc /= fra.size()
	move = InputEventMouseMotion.new()
	move.position = map._lonlat_to_screen(fc.x, fc.y)
	map._gui_input(move)
	if map._hovered_outline != "":
		_fail("over France the outline hover still read '%s'" % map._hovered_outline)
	map.nation_hovered.disconnect(on_hover)
	map.nation_clicked.disconnect(on_click)

	var text := FileAccess.get_file_as_string("res://src/ui/map_view.gd")
	var start := text.find("func _nation_at_lonlat")
	var stop := text.find("
func ", start + 1)
	var body := text.substr(start, stop - start)
	for forbidden in ["_world_polygons", "_outline_at_lonlat", "_ring_boxes_world"]:
		if body.contains(forbidden):
			_fail("_nation_at_lonlat() reads %s -- an outline would become clickable" % forbidden)


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
	_check_layer_crossfade(map, viewer, target)


## V4.9b. A layer toggle crossfades the fills: headless (motion off) the new
## layer is drawn at once; with motion on the fill starts at what was SHOWN and
## lands on the new layer's own colours, and a second toggle mid-fade starts
## from the mid-fade colour, not from either layer's.
func _check_layer_crossfade(map, viewer: String, target: String) -> void:
	if map._layer_blend != 1.0 or not map._fill_from.is_empty():
		_fail("with motion off a layer toggle left a fade behind (blend %.2f)" % map._layer_blend)
	var political: Color = map._layer_fills(viewer)[target]
	Motion.override = 1
	map.set_layer(MapLayers.RELATIONS)
	var relations: Color = map._layer_fills(viewer)[target]
	if not map._shown_fills(viewer)[target].is_equal_approx(political):
		_fail("the crossfade did not start from the colour on screen")
	var tween: Tween = map.get_meta(&"motion_tween")
	tween.custom_step(Motion.LAYER_S * 0.5)
	var mid: Color = map._shown_fills(viewer)[target]
	if mid.is_equal_approx(political) or mid.is_equal_approx(relations):
		_fail("half a crossfade draws %s, expected between %s and %s" % [mid, political, relations])
	map.set_layer(MapLayers.TRADE)
	if not map._shown_fills(viewer)[target].is_equal_approx(mid):
		_fail("a toggle mid-fade jumped from %s to %s" % [mid, map._shown_fills(viewer)[target]])
	Motion.finish(map)
	if map._layer_blend != 1.0 or not map._fill_from.is_empty():
		_fail("finish() left the crossfade at blend %.2f" % map._layer_blend)
	if not map._shown_fills(viewer)[target].is_equal_approx(map._layer_fills(viewer)[target]):
		_fail("a finished crossfade does not draw the layer's own fill")
	map.set_layer(MapLayers.POLITICAL)
	Motion.finish(map)
	Motion.override = -1


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
			# of the whole graph and the bound has to sit below it.
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
