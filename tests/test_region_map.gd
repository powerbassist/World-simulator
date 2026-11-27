extends SceneTree

## Headless test: godot --headless --script res://tests/test_region_map.gd
## Non-zero exit on any failure.
##
## Screen 6, Regions, slice 2 -- the author's pick, direction A ("A, la carte"): the map
## is the screen. While the Regions tab is open:
##   - the dock narrows so the nation stays on the map to its right, and widens back for
##     any other tab;
##   - the player's regions are tinted by the measure the chips pick (jobless against the
##     nation by default; output per head; the 12-month change), each with its figure
##     printed, a glyph beside the tone so it never rests on colour alone;
##   - a click on a region opens its sheet, and the open region is ringed on the map;
##   - the overlay goes when the tab closes.
## Driven a frame apart through the real map click (press and release on the region's
## screen point, map_view's own _gui_input).

const RegionsShell = preload("res://src/ui/regions_shell.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")
const Region = preload("res://src/core/region.gd")
const RegionPanel = preload("res://src/ui/region_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")

## Hauts-de-France, the worst region in France's data, and a point inside it (Lille).
const WORST := "FRE"
const LILLE := Vector2(3.0551, 50.6339)
const NARROW_MAX := 560.0

var _failures: Array[String] = []
var _main
var _panel
var _overlay
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_check_in_region_rule()
			_check_anchors_all_nations()
			_panel = _main._windows.content("region")
			_overlay = _panel.get("_overlay")
			if _overlay == null:
				_fail("the regions tab has no map overlay")
				_finish()
				return true
			if _overlay.visible:
				_fail("the region overlay shows before the tab opens")
			_main._windows.open("region")
		4:
			_check_open()
			_check_jobless_tint()
			_press_measure("per_head")
			# A plain resize at the same interface size keeps the player's view (F11, a
			# maximize, an edge drag): map_view.gd's _fit_zoom() rule.
			_overlay.fit_rect = Rect2()
			_main.get_viewport().size_changed.emit()
		5:
			if _overlay.fit_rect != Rect2():
				_fail("a resize at the same interface size framed the nation again: the player's view is lost")
			# The interface size changing the canvas frames the nation again on the new one.
			root.content_scale_factor = 0.8
			_main.get_viewport().size_changed.emit()
		6:
			if _overlay.fit_rect != RegionsShell.fit_rect_for(_main.get_viewport_rect().size):
				_fail("an interface size change with the Regions tab open did not frame the nation again (%s)" % _overlay.fit_rect)
			_check_per_head()
			_click_map(_countryside(WORST))
		8:
			if String(_panel._game.open_region) != WORST:
				_fail("a click in the region's countryside opened '%s', not %s" % [_panel._game.open_region, WORST])
			if String(_overlay.selected) != WORST:
				_fail("the open region is not ringed on the map (selected '%s')" % _overlay.selected)
			# With a region open the view is the player's: a factor change does not reframe.
			_overlay.fit_rect = Rect2()
			root.content_scale_factor = 1.0
			_main.get_viewport().size_changed.emit()
		9:
			if _overlay.fit_rect != Rect2():
				_fail("an interface size change reframed the nation over an open region")
			_main._windows.open("economy")
		10:
			if _overlay.visible:
				_fail("the region overlay stays on the map with another tab open")
			if _dock_width() <= NARROW_MAX:
				_fail("the dock stays narrow (%.0f) for another tab" % _dock_width())
			_main.queue_free()
		12:
			_finish()
			return true
	return false


func _check_open() -> void:
	if not _overlay.visible:
		_fail("the region overlay does not show with the tab open")
	if _dock_width() > NARROW_MAX:
		_fail("the dock is %.0f wide with Regions open: the map behind it is hidden" % _dock_width())
	# The nation framed beside the dock: Lille lands in the map's free rect, not under the dock.
	var at: Vector2 = _main._map_view.lonlat_to_screen(LILLE.x, LILLE.y)
	if not _overlay.fit_rect.has_point(at):
		_fail("Lille draws at %s, outside the map's free rect %s: the nation is not framed" % [at, _overlay.fit_rect])
	# QA's T1 on #384: the figures read on a real screen -- the body size at least, a bold
	# figure face, each on its own ink chip, and no chip over one of the region's cities.
	if _overlay.label_size() < roundi(UiTheme.SIZE_BASE * UiTheme.text_scale()):
		_fail("the map figures are drawn at %d, under the body size %d" % [_overlay.label_size(), UiTheme.SIZE_BASE])
	if _overlay.label_font() != UiTheme.map_figure_face():
		_fail("the map figures are not drawn in the bold figure face")
	_check_budget()
	# The chips at the default text size and at the larger ones, where they crowd.
	for scale in [0.9, 1.0, 1.6]:
		UiTheme.set_text_scale(scale)
		_check_chips(scale)
	UiTheme.set_text_scale(1.0)
	var regions: Array = _main._loader.regions.get(_main._state.player().id, [])
	if _overlay.drawn_count() < regions.size() - 1:
		_fail("the overlay draws %d of %d regions" % [_overlay.drawn_count(), regions.size()])


## The in-region rule on a shape built to need it: region A is four degrees wide and one
## tall, drawn at 20 px a degree (80 x 20 px, shorter than a chip), with its largest city at
## its centre, and region B sits under it. Any vertical step leaves A; a step into B would
## read as B's figure. The chip must step sideways and keep its centre in A.
class FakeMap:
	func lonlat_to_screen(lon: float, lat: float) -> Vector2:
		return Vector2(400.0 + lon * 20.0, 400.0 - lat * 20.0)


func _check_in_region_rule() -> void:
	var MapRegions = load("res://src/ui/map_regions.gd")
	var probe = MapRegions.new()
	root.add_child(probe)
	var a := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 1), Vector2(0, 1)])
	var b := PackedVector2Array([Vector2(0, -3), Vector2(4, -3), Vector2(4, 0), Vector2(0, 0)])
	probe.setup(FakeMap.new(), ["A", "B"], {"A": [a], "B": [b]})
	probe.set_avoid({"A": [Vector2(2.0, 0.5)]})
	probe.set_tint({"A": {"tone": UiTheme.BAD, "label": "▲ 9.5 %"}})
	var chip: Rect2 = probe.label_rects().get("A", Rect2())
	var map := FakeMap.new()
	var centre := chip.get_center()
	var lonlat := Vector2((centre.x - 400.0) / 20.0, (400.0 - centre.y) / 20.0)
	if not probe.inside("A", lonlat):
		_fail("the in-region rule: A's chip is centred at %s, outside A" % lonlat)
	if chip.has_point(map.lonlat_to_screen(2.0, 0.5)):
		_fail("the in-region rule: A's chip stayed on its city though a place inside A was free")
	probe.queue_free()
	# QA's T3 on #384: a hole. H is a square with C, a smaller square, cut out of its middle
	# (Berlin in Brandenburg); the drawn rings are outer rings only, so H's centroid lies in C.
	# Tested against H's own rings with C as its hole, H's figure is centred in H, not on C.
	var holed = MapRegions.new()
	root.add_child(holed)
	var h := PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 6), Vector2(0, 6)])
	var c := PackedVector2Array([Vector2(2, 2), Vector2(4, 2), Vector2(4, 4), Vector2(2, 4)])
	holed.setup(FakeMap.new(), ["H", "C"], {"H": [h], "C": [c]}, {"H": [[h, c]], "C": [[c]]})
	holed.set_tint({"H": {"tone": UiTheme.BAD, "label": "▲ 9.5 %"}})
	var at: Rect2 = holed.label_rects().get("H", Rect2())
	var mid := Vector2((at.get_center().x - 400.0) / 20.0, (400.0 - at.get_center().y) / 20.0)
	if Geometry2D.is_point_in_polygon(mid, c) or not Geometry2D.is_point_in_polygon(mid, h):
		_fail("the hole rule: H's chip is centred at %s, not in H" % mid)
	holed.queue_free()


## The parent's one rule, over the real data: for each playable nation, every region's figure
## point lies in that region and in no other -- region_at_lonlat over loader.region_rings,
## every ring of regions.geojson, holes included (Berlin in Brandenburg, Warsaw in Mazowieckie).
func _check_anchors_all_nations() -> void:
	var MapRegions = load("res://src/ui/map_regions.gd")
	var loader = _main._loader
	for nation in ["FRA", "DEU", "GBR", "POL"]:
		var ids: Array = []
		for region in loader.regions.get(nation, []):
			ids.append(String(region.id))
		if ids.is_empty():
			_fail("premise: %s has no regions" % nation)
			continue
		var probe = MapRegions.new()
		root.add_child(probe)
		var holed := {}
		for id in ids:
			holed[id] = loader.region_rings.get(id, [])
		probe.setup(FakeMap.new(), ids, loader.region_features, holed)
		for id in ids:
			var point: Vector2 = probe._anchor(id)
			var home := Region.region_at_lonlat(loader.region_rings, point.x, point.y)
			if home != id:
				_fail("%s: %s's figure point %s lies in '%s'" % [nation, id, point, home])
		probe.queue_free()


## QA's T4 on #384: the chips are laid out in the frame a pan or zoom draws. A fresh layout
## (a new zoom or tint) over France stays well inside the G2 frame budget, and a pan reuses
## the layout itself, no point test at all. The all-Europe point test this replaced took
## 1.4 ms a call, 17 ms a layout (its mutant fails here). The median of five, generous against
## a loaded runner: what it catches is that order.
const LAYOUT_BUDGET_MS := 6.0


func _check_budget() -> void:
	var fresh: Array = []
	for i in 5:
		_overlay.set_tint(_overlay._tint)
		var t0 := Time.get_ticks_usec()
		_overlay.label_rects()
		fresh.append((Time.get_ticks_usec() - t0) / 1000.0)
	fresh.sort()
	print("test_region_map: a fresh layout of France's figures, median %.3f ms" % fresh[2])
	if float(fresh[2]) > LAYOUT_BUDGET_MS:
		_fail("a fresh layout of the map's figures takes %.2f ms, over %.1f" % [fresh[2], LAYOUT_BUDGET_MS])
	var laid: Dictionary = _overlay._layout
	var before: Rect2 = _overlay.label_rects().values()[0]
	_main._map_view.pan_by(Vector2(3, 0))
	var after: Rect2 = _overlay.label_rects().values()[0]
	_main._map_view.pan_by(Vector2(-3, 0))
	if not is_same(laid, _overlay._layout):
		_fail("a pan laid the map's figures out again instead of moving them")
	if not after.position.is_equal_approx(before.position + Vector2(3, 0)):
		_fail("a pan of 3 px moved a figure from %s to %s" % [before.position, after.position])


## No two chips overlap, none covers its region's largest city, and each is centred inside
## its own region (QA's T2 on #384: a chip stepped into a neighbour reads as the neighbour's).
func _check_chips(scale: float) -> void:
	var map = _main._map_view
	var chips: Dictionary = _overlay.label_rects()
	var placed: Array = chips.values()
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			if (placed[i] as Rect2).intersects(placed[j]):
				_fail("text %d %%: two figure chips overlap: %s and %s" % [roundi(scale * 100.0), placed[i], placed[j]])
	for id in chips:
		var chip: Rect2 = chips[id]
		for city in _overlay.avoid_points(id):
			if chip.has_point(map.lonlat_to_screen(city.x, city.y)):
				_fail("text %d %%: %s's figure chip %s sits on its largest city" % [roundi(scale * 100.0), id, chip])
		var centre: Vector2 = map._screen_to_lonlat(chip.get_center())
		var home := Region.region_at_lonlat(_main._loader.region_rings, centre.x, centre.y)
		if home != String(id):
			_fail("text %d %%: %s's figure chip is centred in '%s', not in its own region" % [roundi(scale * 100.0), id, home])


## Jobless against the nation: the worst region well over it reads BAD with its glyph,
## its figure printed; a region under the nation carries no tone and no glyph.
func _check_jobless_tint() -> void:
	var ns = _main._state.player()
	var jobless := _jobless(WORST)
	var fill: Color = _overlay.fill_of(WORST)
	if not _same_hue(fill, UiTheme.BAD):
		_fail("%s at %.1f %% against %.1f %%: its fill %s is not the alert tone" % [WORST, jobless, float(ns.unemployment_pct), fill])
	var label: String = _overlay.label_of(WORST)
	if not label.contains("▲") or not label.contains(Num.f(jobless, 1)):
		_fail("%s's map label '%s' lacks the glyph or its %s %%" % [WORST, label, Num.f(jobless, 1)])
	for region in _main._loader.regions.get(ns.id, []):
		if _jobless(region.id) < float(ns.unemployment_pct):
			if _overlay.fill_of(region.id).a > 0.01 or _overlay.label_of(region.id).contains("▲") or _overlay.label_of(region.id).contains("△"):
				_fail("%s is under the nation and still toned on the map" % region.id)
			return


func _check_per_head() -> void:
	var ns = _main._state.player()
	var regions: Array = _main._loader.regions.get(ns.id, [])
	var index: float = Regions.gdp_per_head_index(ns, regions, WORST, Migration.region_share(ns, WORST))
	var label: String = _overlay.label_of(WORST)
	if not label.contains(Num.f(index * 100.0, 0)):
		_fail("per head: %s's label '%s' does not print %s %%" % [WORST, label, Num.f(index * 100.0, 0)])


# -- helpers --

func _jobless(region_id: String) -> float:
	var ns = _main._state.player()
	var regions: Array = _main._loader.regions.get(ns.id, [])
	var access: Dictionary = Regions.accessibility_for(ns, regions, _main._state.region_graph)
	return Regions.unemployment_pct(ns, regions, region_id, access, _main._state.project_sited_pct.get(ns.id, {}))


func _press_measure(measure: String) -> void:
	for b in _panel.find_children("*", "Button", true, false):
		if b.has_meta("measure") and String(b.get_meta("measure")) == measure and b.is_visible_in_tree():
			(b as Button).pressed.emit()
			return
	_fail("no '%s' chip on the rail" % measure)


## A press and a release at the point, through map_view's own input path.
func _click_map(lonlat: Vector2) -> void:
	var map = _main._map_view
	var at: Vector2 = map.lonlat_to_screen(lonlat.x, lonlat.y)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		map._gui_input(ev)


## A point in the region with no city, plant or project under it: those answer a click
## before the region does, as they answer before the nation (map_view's fall-through).
func _countryside(region_id: String) -> Vector2:
	var map = _main._map_view
	var rings: Array = _main._loader.region_features.get(region_id, [])
	var box := Rect2((rings[0] as PackedVector2Array)[0], Vector2.ZERO)
	for p in rings[0]:
		box = box.expand(p)
	for i in range(1, 10):
		for j in range(1, 10):
			var ll := box.position + box.size * Vector2(i / 10.0, j / 10.0)
			var at: Vector2 = map.lonlat_to_screen(ll.x, ll.y)
			if String(map.region_picker.call(ll)) == region_id and map._city_at_screen_point(at) == "" 					and map._plant_at_screen_point(at) == "" and map._project_at_screen_point(at) == "":
				return ll
	_fail("no clear point in %s to click" % region_id)
	return LILLE


func _dock_width() -> float:
	return float(_main._windows._dock.size.x)


func _same_hue(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02 and a.a > 0.05


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_region_map: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
