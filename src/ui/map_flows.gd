extends Control

## The flows -- V3.4. Trade arcs zoomed out, convoys zoomed in, and the ONLY
## _process this block adds.
##
## A SEPARATE CONTROL RATHER THAN AN EIGHTH PASS, and that choice IS the frame
## gate. src/ui/map_view.gd has no _process and no timer: its queue_redraw()
## sites are all pans, zooms, hovers and layer changes, so its measured
## 7.08-7.23 ms everything-visible band is paid once per event. Animating inside
## it would re-record the raster, the world borders, the roster fills, the
## labels, the crosses, the markers and the plants sixty times a second to move a
## lorry. This control redraws itself instead, and the map keeps the property
## V3.1 bought.
##
## Mirrors the camera the way src/ui/minimap.gd does -- polling
## visible_lonlat_rect() behind a change test, because map_view is the background
## layer and deliberately emits no signal for pan and zoom.
##
## PROJECTS THROUGH THE VIEW RECT, NOT THROUGH BASE_SCALE. This control is
## full-rect over the same map_view, so the lon/lat window at its own corners IS
## visible_lonlat_rect() and the mapping between them is linear -- plate carrée
## on both sides. It therefore reproduces map_view's projection exactly while
## learning nothing about how that projection is built.
##
## ON THE TRADE LAYER ALONE. Roads are geography and draw on every layer; a flow
## is a question the player asked, and the choropleth it rides already answers
## "how much does B matter to A" in colour. Arcs add the one thing a per-nation
## fill cannot show: direction. It also means the animated redraw only runs
## when it was asked for -- and, since V3.4's gates were measured, at the capped
## rate REDRAW_HZ sets rather than on every frame.

const MapLayers = preload("res://src/ui/map_layers.gd")
const MapNetwork = preload("res://src/ui/map_network.gd")
const Clock = preload("res://src/core/clock.gd")
const Trade = preload("res://src/sim/trade.gd")
const Regions = preload("res://src/sim/regions.gd")
const Cycle = preload("res://src/sim/cycle.gd")

## Below this share of an even partner vector an arc is a hairline nobody can
## read, and 28 of them are a hairball. The scale is the layer's own: an even
## share is 1.0 here, so this is "a quarter of an average partner".
const ARC_MIN_RATIO := 0.25
const ARC_MIN_WIDTH := 1.0
const ARC_MAX_WIDTH := 5.0
const ARC_SEGMENTS := 20
const ARC_BOW := 0.16          ## sideways bow as a fraction of the chord
const ARC_HEAD_PX := 7.0

const ARC_OUT := Color(0.976, 0.898, 0.639, 0.80)   ## map_layers.gd's TRADE_HIGH
const ARC_IN := Color(0.788, 0.635, 0.153, 0.55)    ## its TRADE_MID

## At most three either way. The scale is "times the mean", so three is a spine
## carrying three times an average crossing -- and past three a count stops being
## something the eye reads off a line at a glance, which is a legend's job rather
## than a mark's.
const MAX_CONVOYS := 3

## How far a convoy travels in a game-day. NOT a haulage speed: it is a viewing
## pace, chosen against the graph rather than against a lorry. The 463 spines'
## median run is 157 km, so at Clock's speed 1 -- one day per second -- a typical
## crossing takes about six seconds, and the longest, a 914 km sea link, about
## thirty-seven. A physically honest version would need a real kilometres-per-day
## figure, which is the same kind of number docs/network-model.md §7 refuses a
## project's edge-cost discount for wanting. What survives is the part that had
## to be real: the graph's own km, so a long ferry takes longer than a short hop.
const PACE_KM_PER_DAY := 25.0

## THE REDRAW IS RATE-LIMITED, and the measurement that forced it is recorded
## rather than asserted: redrawing on every frame cost 3.01 ms at max zoom
## against V3.4's 1.5 ms gate, and put the opening fit's whole frame at 13.73 ms
## against its 11.0 ms one (docs/map-platform-model.md section 4). The cost is
## paid per REDRAW and not per second, so the only lever is how often it is paid.
## 30 Hz because that is above film's 24 -- the convoys still read as travelling,
## and a camera move is exempt below, so nothing the player DRIVES is slowed.
const REDRAW_HZ := 30.0
const REDRAW_INTERVAL := 1.0 / REDRAW_HZ

const LORRY_PX := 3.0
const SHIP_PX := 4.0
const CONVOY_COLOR := Color(0.976, 0.898, 0.639, 0.95)

var _map_view = null
var _clock: Node = null
var _loader = null
var _state = null

var _spines: Array = []
var _traffic: Dictionary = {}   ## "A|B" -> {"ab": float, "ba": float}
var _arcs: Array = []           ## {"from": Vector2, "to": Vector2, "ratio": float, "outbound": bool}

var _spines_considered: int = 0

## Days since setup, on the sim clock's own scale. NOT wall time: pause has to
## freeze it (so tools/screenshot.gd --paused can still prove pixel identity in
## the one block that is about motion) and speed has to move it (so the world and
## the clock the player controls are one thing rather than two).
var _phase_days: float = 0.0

## Never equal to a real view rect, so the first frame redraws -- minimap.gd's
## own sentinel.
var _last_view := Rect2(-1.0, -1.0, -1.0, -1.0)
var _view := Rect2()

## Wall seconds owed to the next redraw. Wall and not game time: the rate limit
## is about the frame the player waits on, which does not slow down when they
## pause the world.
var _since_redraw: float = 0.0


func _ready() -> void:
	# The whole reason this control can sit over the map at all. V3.3f shipped a
	# full-rect holder at the default MOUSE_FILTER_PASS and took every click on
	# the screen from a new game's first frame, behind a green suite, for a whole
	# tier. tests/test_map_flows.gd asserts this value rather than trusting it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func setup(map_view, clock: Node, loader, state) -> void:
	_map_view = map_view
	_clock = clock
	_loader = loader
	_state = state
	_spines = MapNetwork.spines(loader)
	_phase_days = 0.0
	refresh()


## Rebuilt on the monthly hook, not per frame. A trade weight moves with every
## partner's GDP and an accessibility index with every region's output share --
## both monthly quantities. Recomputing them at 60 Hz would put a Dijkstra sweep
## and a whole-roster normalisation inside the frame this file exists to keep
## cheap.
func refresh() -> void:
	_traffic.clear()
	_arcs.clear()
	if _state == null or _loader == null:
		return

	var table: Dictionary = Trade.weight_table(_state)
	var partner_count: int = maxi(1, _state.nations.size() - 1)
	# An even share is 1/(n-1), so dividing by it puts a pair weight on a scale
	# whose mean is exactly 1.0.
	var even: float = 1.0 / float(partner_count)

	var access := {}
	for nation_id in _state.nations.keys():
		var ns = _state.nations[nation_id]
		var region_list: Array = _state.regions.get(nation_id, [])
		if region_list.is_empty():
			continue
		var idx: Dictionary = Regions.accessibility_for(ns, region_list, _state.region_graph)
		for region_id in idx.keys():
			access[String(region_id)] = float(idx[region_id])

	# THE TWO FAMILIES SHARE A UNIT AND IT IS NOT INVENTED. A pair weight vector
	# sums to 1 over n-1 partners, so an average pair reads 1.0 once divided by
	# the even share; accessibility is normalised to an output-weighted mean of
	# exactly 1.0 by src/sim/network.gd's own construction. Both are already
	# "times the mean", which is why one scale can carry both without a
	# conversion constant nobody measured.
	for s in _spines:
		var key := "%s|%s" % [s["region_a"], s["region_b"]]
		var nation_a := String(s["nation_a"])
		var nation_b := String(s["nation_b"])
		if nation_a != nation_b:
			var ab := float((table.get(nation_a, {}) as Dictionary).get(nation_b, 0.0)) / even
			var ba := float((table.get(nation_b, {}) as Dictionary).get(nation_a, 0.0)) / even
			_traffic[key] = {"ab": ab, "ba": ba}
		else:
			var mean := (
				float(access.get(String(s["region_a"]), 1.0))
				+ float(access.get(String(s["region_b"]), 1.0))
			) / 2.0
			_traffic[key] = {"ab": mean, "ba": mean}

	_build_arcs(table, even)


## The arcs are the VIEWER's own vector, both ways, and not every ordered pair in
## the roster. The trade layer's choropleth and its legend readout are already
## viewer-relative ("NLD 11.1% of FRA's demand"), so an arc set that ignored the
## viewer would be a second answer to the question the layer under it is already
## answering. 28 partners times two directions is legible; the full square is a
## hairball.
func _build_arcs(table: Dictionary, even: float) -> void:
	var viewer := String(_state.player_nation_id)
	var mine: Dictionary = table.get(viewer, {})
	var home = _label_point(viewer)
	if home == null:
		return
	var partner_ids: Array = mine.keys()
	partner_ids.sort()
	for partner_id in partner_ids:
		var there = _label_point(String(partner_id))
		if there == null:
			continue
		var out_ratio := float(mine[partner_id]) / even
		var in_ratio := float((table.get(partner_id, {}) as Dictionary).get(viewer, 0.0)) / even
		if out_ratio >= ARC_MIN_RATIO:
			_arcs.append({"from": home, "to": there, "ratio": out_ratio, "outbound": true})
		if in_ratio >= ARC_MIN_RATIO:
			_arcs.append({"from": there, "to": home, "ratio": in_ratio, "outbound": false})


## Natural Earth's own hand-placed LABEL_X/LABEL_Y, carried into the geometry as
## label_lon/label_lat -- better than a centroid, which for Norway is in Sweden
## (docs/data-sources.md says so about this exact field). minimap.gd reads the
## player's home point through the same two hops.
func _label_point(nation_id: String):
	if _loader == null or not _loader.nations.has(nation_id):
		return null
	var geo_id: String = _loader.nations[nation_id].geo_id
	if not _loader.label_points.has(geo_id):
		return null
	return _loader.label_points[geo_id]


func _process(delta: float) -> void:
	if _map_view == null or _clock == null:
		return

	# The phase moves on the CLOCK's scale, which is what makes pause a freeze
	# and speed a real acceleration rather than two separate behaviours.
	if not bool(_clock.paused):
		var speed_index: int = clampi(int(_clock.speed) - 1, 0, Clock.SPEED_DAYS_PER_SECOND.size() - 1)
		_phase_days += delta * Clock.SPEED_DAYS_PER_SECOND[speed_index]

	if not _is_showing():
		return

	# Poll-behind-a-change-test, minimap.gd's pattern: nothing here is signalled,
	# so the camera is compared and the clock is asked, once a frame.
	var view: Rect2 = _map_view.visible_lonlat_rect()
	var view_changed: bool = view != _last_view
	_last_view = view
	if _redraw_due(delta, view_changed, bool(_clock.paused)):
		queue_redraw()


## THE REDRAW DECISION, LIFTED OUT OF _process SO A CHECK CAN ASK IT. The cap is
## what brings G4 and G5 inside their gates, which makes its CADENCE load-bearing
## and not a detail -- and queue_redraw() leaves nothing a headless test can read
## back afterwards. So the decision is a function with an answer instead:
## tests/test_map_flows.gd asks this one directly. It owns _since_redraw.
func _redraw_due(delta: float, view_changed: bool, paused: bool) -> bool:
	# A camera move is EXEMPT from the rate limit and redraws on the frame it
	# happens: this control sits on the map, so an arc that arrives a frame after
	# the coastline it is drawn over reads as the two layers coming apart. It is
	# checked before the pause test because panning a paused map still moves the
	# picture.
	if view_changed:
		_since_redraw = 0.0
		return true
	# While the clock is paused nothing but the camera can move the picture, so
	# there is nothing to redraw for -- the same freeze tools/screenshot.gd
	# --paused depends on.
	if paused:
		return false

	_since_redraw += delta
	if _since_redraw < REDRAW_INTERVAL:
		return false
	# The REMAINDER is kept and not zeroed, so the average rate stays REDRAW_HZ
	# instead of drifting down by one frame's worth on every tick. fmod and not a
	# subtraction, because a frame longer than the interval would otherwise leave
	# a backlog and redraw on every frame until it was paid off -- a stall would
	# turn the rate limit off exactly when the frame could least afford it. A
	# redraw is a state, not an event queue: there is nothing to catch up on.
	_since_redraw = fmod(_since_redraw, REDRAW_INTERVAL)
	return true


## Arcs and convoys ride the trade layer; roads do not. A hidden control's
## _process still runs, so the layer test lives here rather than in visibility.
func _is_showing() -> bool:
	return _map_view != null and String(_map_view.layer()) == MapLayers.TRADE


func spines_considered() -> int:
	return _spines_considered


func phase_days() -> float:
	return _phase_days


## Exact, because this control is full-rect over the same map_view: the lon/lat
## at its corners IS visible_lonlat_rect() and the projection between them is
## linear on both axes. Latitude increases upward while screen y increases
## downward, which is the one sign flip.
func _to_screen(lon: float, lat: float) -> Vector2:
	if _view.size.x <= 0.0 or _view.size.y <= 0.0:
		return Vector2.ZERO
	return Vector2(
		(lon - _view.position.x) / _view.size.x * size.x,
		(_view.position.y + _view.size.y - lat) / _view.size.y * size.y
	)


func _draw() -> void:
	_spines_considered = 0
	if not _is_showing():
		return
	_view = _map_view.visible_lonlat_rect()
	if float(_map_view.zoom()) < float(_map_view.CITY_MIN_ZOOM):
		_draw_arcs()
	else:
		_draw_convoys(_spines_in_view())


## THE CULL, IN DEGREES AND BEFORE ANYTHING IS PROJECTED -- the same predicate
## and the same reason as the spine pass's, and it is what makes the per-frame
## walk viewport-bounded: at max zoom over one city most of the spine list is
## somewhere else, and none of it is transformed. It is also the ONE place the
## readout tests/test_map_flows.gd asserts is written, so a convoy pass cannot
## quietly count a second time or count something else.
##
## Rect2.intersects() defaults to include_borders = false, so a box lying exactly
## on a view edge is dropped: an edge with a horizontal or vertical run would be
## the case that matters, and tests/test_map_network.gd asserts no spine in the
## list has a coincident axis.
func _spines_in_view() -> Array:
	var out: Array = []
	if _view.size.x <= 0.0 or _view.size.y <= 0.0:
		return out
	# DERIVED FROM THE GLYPH, not chosen. The widest mark this overlay puts on a
	# spine is a ship at SHIP_PX, and a convoy sitting just off the edge must
	# still draw, so the pad is exactly that radius expressed in degrees --
	# `_view.size.x / size.x` is the control's own degrees-per-pixel, which it
	# already has because it mirrors the camera. map_view.gd's CULL_PAD_PX is
	# derived from its widest stroke the same way and for the same reason: a
	# tuned pad is a number nobody can re-derive, and this one shrinks with zoom
	# exactly as the glyph's footprint in degrees does.
	var deg_per_px: float = _view.size.x / maxf(1.0, size.x)
	var view: Rect2 = _view.grow(maxf(SHIP_PX, LORRY_PX) * deg_per_px)
	for s in _spines:
		if view.intersects(s["box"]):
			out.append(s)
	_spines_considered = out.size()
	return out


## One quadratic bow per direction, each bowing to its own side, so the pair is
## two readable curves rather than one line drawn twice. Direction is in the bow
## AND in the arrowhead: a directed table drawn undirected is the table's whole
## point thrown away, and V1.3b's asymmetry is load-bearing elsewhere in the game
## (coercion damage scales with w(target -> imposer)).
func _draw_arcs() -> void:
	for arc in _arcs:
		var a := _to_screen(arc["from"].x, arc["from"].y)
		var b := _to_screen(arc["to"].x, arc["to"].y)
		var chord := b - a
		if chord.length() < 1.0:
			continue
		var color: Color = ARC_OUT if bool(arc["outbound"]) else ARC_IN
		# The ratio is already "times the mean", so it IS the width in pixels: an
		# average partner draws a 1 px thread and a dominant one draws up to five.
		# No scale constant, because there is no second unit to convert into.
		var width: float = clampf(float(arc["ratio"]), ARC_MIN_WIDTH, ARC_MAX_WIDTH)
		var control := a + chord * 0.5 + Vector2(-chord.y, chord.x).normalized() * chord.length() * ARC_BOW

		var points := PackedVector2Array()
		for i in ARC_SEGMENTS + 1:
			var t := float(i) / float(ARC_SEGMENTS)
			points.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
		draw_polyline(points, color, width)

		# The head at the destination end, aimed along the last segment.
		var tip: Vector2 = points[points.size() - 1]
		var dir := (tip - points[points.size() - 2]).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(
			PackedVector2Array([
				tip,
				tip - dir * ARC_HEAD_PX + side * ARC_HEAD_PX * 0.45,
				tip - dir * ARC_HEAD_PX - side * ARC_HEAD_PX * 0.45,
			]),
			color
		)


## The convoys -- lorries on land, ships on the sea links, moving along the same
## spines src/ui/map_network.gd draws.
##
## COUNTED FROM THE TRAFFIC RATIO, PER DIRECTION. A cross-border spine's two
## counts come from w(A->B) and w(B->A) separately, so the asymmetry V1.3b
## derived is a thing you can SEE: more lorries leave Luxembourg for France than
## arrive, because w(LUX->FRA) is 12x w(FRA->LUX). An internal spine's two counts
## are equal, because accessibility is undirected and pretending otherwise would
## be drawing a number that does not exist.
##
## THE CULL IS NOT HERE, and that is deliberate. Task 4's _spines_in_view() owns
## it and hands this function the survivors, so `_spines_considered` is written
## in exactly one place and a convoy pass cannot quietly count a second time.
## Walking `_spines` here instead would double the readout and turn the cull test
## red while drawing the identical picture.
func _draw_convoys(in_view: Array) -> void:
	for s in in_view:
		var key := "%s|%s" % [s["region_a"], s["region_b"]]
		var load: Dictionary = _traffic.get(key, {"ab": 0.0, "ba": 0.0})
		var a := _to_screen(s["a"].x, s["a"].y)
		var b := _to_screen(s["b"].x, s["b"].y)
		var sea := String(s["kind"]) == "sea"
		# The graph's own kilometres, so the trip time is a property of the
		# crossing rather than a constant per edge. The one-day floor catches the
		# four spines shorter than 25 km, whose convoys would otherwise complete a
		# run in under a second at speed 1 and read as a flicker, not as travel.
		var trip_days: float = maxf(1.0, float(s["km"]) / PACE_KM_PER_DAY)

		_draw_convoy_run(key, a, b, float(load["ab"]), trip_days, sea, 0)
		_draw_convoy_run(key, b, a, float(load["ba"]), trip_days, sea, 1)


## One direction's marks. The stagger is Cycle.unit() of the edge key and the
## index -- a pure hash, so nothing is stored and a reloaded save puts every
## convoy back where a fresh clock would. src/sim/cycle.gd is the ONE
## deterministic draw in the simulation and this reads it rather than carrying a
## second copy, which is the rule its own header states.
func _draw_convoy_run(
	key: String, from: Vector2, to: Vector2, ratio: float, trip_days: float,
	sea: bool, direction: int
) -> void:
	var count: int = clampi(int(round(ratio)), 0, MAX_CONVOYS)
	if count <= 0:
		return
	var span := to - from
	if span.length() < 2.0:
		return
	var heading := span.normalized()
	var side := Vector2(-heading.y, heading.x)
	var radius: float = SHIP_PX if sea else LORRY_PX

	for i in count:
		var stagger := Cycle.unit("%s|%d" % [key, direction], i)
		var t := fposmod(stagger + _phase_days / trip_days, 1.0)
		var at := from + span * t
		if at.x < -radius or at.x > size.x + radius:
			continue
		if at.y < -radius or at.y > size.y + radius:
			continue
		if sea:
			# A hull: a triangle pointed the way it is going. The only glyph on
			# the map that says "moving" rather than "here", which is why the
			# cities' cross and the plants' circle are both wrong for it.
			draw_colored_polygon(
				PackedVector2Array([
					at + heading * radius,
					at - heading * radius + side * radius * 0.7,
					at - heading * radius - side * radius * 0.7,
				]),
				CONVOY_COLOR
			)
		else:
			# A short bar along the road. Not a dot: at this size a dot is a
			# small city cross and the map already has 1 065 of those.
			draw_line(at - heading * radius, at + heading * radius, CONVOY_COLOR, 2.0)
