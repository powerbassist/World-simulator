extends SceneTree

## Headless test: godot --headless --script res://tests/test_commodities_panel.gd
## Non-zero exit on any failure.
##
## V4.6, Task 4's pins over the commodity layer, kept when the Commodities window
## retired into the Sectors domain (V5.3 screen 5, slice 1): its goods are each sector
## tab's "What it makes", its shortage line SectorGoods' (read by the tabs, the strip and
## the outliner). What this file still pins:
##
##   - THE SCANNER RULES over the files that read the layer now.
##   - IT READS AND NEVER WRITES: a source scan of the readers for an indexed write into
##     the register (commodities.gd is its one writer), and a deep-equality check across
##     a sector tab's refresh.
##   - THE SHORTAGE FLIP, BOTH SIDES OF THE THRESHOLD, with two negative controls.
##   - THE TWO MAP MODES, registry entries the legend's switcher grows on its own.
##
## The shortage threshold and the map modes live in docs/commodities-model.md.

const SectorGoods = preload("res://src/ui/sector_goods.gd")
const MapLayers = preload("res://src/ui/map_layers.gd")

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
	var panel = _main._sector_panels.get("industry")
	if panel == null:
		_fail("main scene did not build the industry tab, the goods' home")
		return
	var state = _main._state
	_check_scanner_rules()
	_main._windows.open("sector_industry")
	panel.mark_dirty()
	panel._refresh()
	_check_hover_sentences(state)
	_check_reads_and_never_writes(panel, state)
	_check_shortage_flip(state)
	_check_map_modes(panel, state)


## The two scanner rules test_panel_kit.gd enforces globally, asserted here on the
## files this task writes so the session that breaks one is the session that sees
## it. The panel-name list is derived from the registry, never written down.
func _check_scanner_rules() -> void:
	var names: Array[String] = []
	for id in _main._windows.panel_ids():
		names.append("_%s_panel" % id)

	for path in ["res://src/ui/sector_goods.gd", "res://src/ui/sector_panel.gd", "res://src/ui/map_layers.gd"]:
		var source := FileAccess.get_file_as_string(path)
		if source.is_empty():
			_fail("could not read %s" % path)
			continue
		if path.ends_with("sector_panel.gd") and not source.contains("PanelKit"):
			_fail("sector_panel.gd builds its rows without the kit")
		var worst := 0
		for opener in [["[", "]"], ["{", "}"]]:
			for chunk in source.split(opener[0]):
				var head: String = chunk.split(opener[1])[0]
				if head.length() > 600:
					continue
				var count := 0
				for name in names:
					if head.contains(name):
						count += 1
				worst = maxi(worst, count)
		if worst >= 3:
			_fail("%s names %d panels in one literal -- that is a list, and the registry already knows them" % [path, worst])


## Both halves. The scan catches the shape commodities.gd's own single-writer pin
## reads; the deep comparison catches a write nobody thought of (a cache stuffed
## back into the register, a default seeded into it). The test itself may write --
## only the panel may not.
func _check_reads_and_never_writes(panel, state) -> void:
	for path in ["res://src/ui/sector_goods.gd", "res://src/ui/sector_panel.gd"]:
		var source := FileAccess.get_file_as_string(path)
		if source.is_empty():
			_fail("could not read %s" % path)
			continue
		for raw_line in source.split("\n"):
			var line := String(raw_line)
			var hash_at := line.find("#")
			if hash_at != -1:
				line = line.substr(0, hash_at)
			if line.contains("commodity_state[") and (line.contains("] =") or line.contains(".erase(")):
				_fail("%s writes commodity_state" % path + " -- the UI reads sim state, it never writes it: " + line.strip_edges())
			if line.contains("Commodities.tick_month("):
				_fail(path + " ticks the simulation -- the month belongs to main.gd")

	var before: Dictionary = state.player().commodity_state.duplicate(true)
	panel.mark_dirty()
	panel._refresh()
	var after: Dictionary = state.player().commodity_state
	if not _deep_equal(before, after):
		_fail("the commodity register changed across a refresh -- the panel wrote sim state")


## The threshold, both sides and with two negative controls. The fixture is the
## test's own write, which is the house way (test_people_panel vacates a cabinet
## seat the same way): the check drives the ONE state the panel cannot reach by
## playing, and the threshold is asserted at its exact edge because an
## approximate edge is a threshold nobody has measured.
##
## THE FIXTURE TAKES OVER THE WHOLE REGISTER rather than one good, and the first
## version did not -- the real state carries genuinely short goods (cotton at 0 %,
## uranium ore at 10 % for France), so a "fully covered" fixture left the alert
## heading up for those and the negative control read as a panel defect. Zeroing
## every want first makes the register have exactly one thing to say, which is
## what makes each side of the flip unambiguous.
func _check_shortage_flip(state) -> void:
	var ns = state.player()
	var cs: Dictionary = ns.commodity_state
	var goods: Array = _loader_goods()
	if goods.size() < 2:
		_fail("the register carries %d goods, so this fixture proves nothing" % goods.size())
		return
	var good_id := String(goods[0])
	var threshold: float = SectorGoods.SHORTAGE_COVERAGE
	var keep: Dictionary = cs.duplicate(true)
	for gid in goods:
		cs["demand"][gid] = 0.0
		cs["output"][gid] = 0.0
		cs["trade"][gid] = 0.0
	# EXACTLY at the threshold: covered, and so not a shortage.
	cs["demand"][good_id] = 100.0
	cs["output"][good_id] = 100.0 * threshold
	if not SectorGoods.shortages(ns, goods).is_empty():
		_fail("a good covered at exactly %.0f%% of its want reads as a shortage -- the edge is on the wrong side" % (threshold * 100.0))
	# A hair under it: a shortage, and it names the good.
	cs["output"][good_id] = 100.0 * threshold - 1.0
	var short: Array = SectorGoods.shortages(ns, goods)
	if short.size() != 1 or String(short[0]["id"]) != good_id:
		_fail("a good covered at %.1f%% of its want reads %s, expected '%s' alone" % [100.0 * (threshold - 0.01), short, good_id])
	# Fully covered: the negative control on the other side of the flip.
	cs["output"][good_id] = 100.0
	if not SectorGoods.shortages(ns, goods).is_empty():
		_fail("a fully covered good still reads as a shortage")
	# Zero demand: a good nobody wants is never short, however little is made of it.
	cs["demand"][good_id] = 0.0
	cs["output"][good_id] = 0.0
	if not SectorGoods.shortages(ns, goods).is_empty():
		_fail("a good nobody wants reads as a shortage when nothing is made of it -- a zero denominator is not a total shortfall")
	cs["demand"] = keep["demand"]
	cs["output"] = keep["output"]
	cs["trade"] = keep["trade"]


## The two modes are REGISTRY entries, which is the whole design: the switcher is
## built from MapLayers.ids() and nothing else, so growing the registry IS growing
## the map's mode surface. Both halves are asserted -- the legend grew the toggles
## without an edit in map_legend.gd, and the map view takes the id -- because a
## registry entry the control refuses is a toggle that does nothing.
func _check_map_modes(panel, state) -> void:
	var map = _main._map_view
	var legend = _main._hud.map_legend

	for mode in ["production", "import_dependency"]:
		if not MapLayers.ids().has(mode):
			_fail("'%s' is not a registered map layer" % mode)
			continue
		if not legend._buttons.has(mode):
			_fail("the legend built no toggle for registered layer '%s' -- the switcher is not derived from the registry any more" % mode)
		var before: String = map.layer()
		map.set_layer(mode)
		if map.layer() != mode:
			_fail("map_view refused the '%s' layer and stayed on '%s'" % [mode, map.layer()])
		map.set_layer(before)

	# Both modes must colour a nation differently from the political fill, or the
	# entry is a toggle that changes nothing on screen.
	var viewed := ""
	for id in state.nations.keys():
		if String(id) != map.viewer_id():
			viewed = String(id)
			break
	if viewed == "":
		_fail("no roster nation to compare a fill against")
		return
	for mode in ["production", "import_dependency"]:
		var data := MapLayers.swatch(mode, state, map.viewer_id(), viewed)
		var political := MapLayers.swatch(MapLayers.POLITICAL, state, map.viewer_id(), viewed)
		if _close(data, political):
			_fail("the '%s' fill for %s is the political palette colour -- the mode draws nothing" % [mode, viewed])
		if data == MapLayers.NO_VALUE:
			_fail("the '%s' fill for %s is NO_VALUE -- these are per-nation quantities, not pair data, so every nation has one" % [mode, viewed])

	# The viewer's own nation has a value on these two layers, unlike the pair
	# layers where NO_VALUE is the honest answer. Pinned both ways round.
	for mode in ["production", "import_dependency"]:
		if is_nan(MapLayers.value(mode, state, map.viewer_id(), map.viewer_id())):
			_fail("the viewer's own nation reads NAN on '%s' -- production and import dependency are properties of a nation, not of a pair" % mode)
		if _close(MapLayers.swatch(mode, state, map.viewer_id(), map.viewer_id()), MapLayers.NO_VALUE):
			_fail("the viewer's own nation is drawn as NO_VALUE on '%s'" % mode)
	for pair_layer in [MapLayers.RELATIONS, MapLayers.TRADE]:
		if not is_nan(MapLayers.value(pair_layer, state, map.viewer_id(), map.viewer_id())):
			_fail("the viewer's own nation has a value on the pair layer '%s'" % pair_layer)

	# THE LEGEND'S SWATCH IS THE MAP'S FILL, for these two layers specifically.
	# test_map_layers.gd runs this check for RELATIONS and TRADE only, and the
	# production ramp's anchor is DERIVED from the roster -- so a legend that
	# coloured its stops through the plain ramp() would show the stale scale with
	# nothing red, which is exactly how the trade legend came to promise "an even
	# ninth" on a twenty-eight-partner roster. Checked here because the derived
	# anchor is what makes these two layers the risky pair.
	var even := MapLayers.production_even_share(state)
	for mode in ["production", "import_dependency"]:
		legend.show_layer(mode, state, map.viewer_id())
		var stops: Array = MapLayers.stops(mode)
		if mode == "production":
			stops = MapLayers.production_stops(even)
		var rects: Array = _all_color_rects(legend)
		if rects.size() != stops.size():
			_fail("%s: legend shows %d swatches for %d stops" % [mode, rects.size(), stops.size()])
			continue
		for i in stops.size():
			var expected := MapLayers.ramp_production(float(stops[i]["at"]), even) if mode == "production" \
				else MapLayers.ramp(mode, float(stops[i]["at"]))
			if not _close(rects[i].color, expected):
				_fail("%s: swatch %d is %s, the ramp says %s" % [mode, i, rects[i].color, expected])

	# AND THE STOP TEXT IS CHECKED AS RENDERED, not just the swatch. The whole
	# legend was green while two import-dependency stops printed the literal "%%":
	# they are plain text, and only the third stop on that list runs through a
	# format operator, so a doubled percent in the other two is never collapsed.
	# A colour check structurally cannot see that class -- the swatches were right
	# the whole time -- so the rendered LABELS are asserted here.
	for mode in ["production", "import_dependency"]:
		legend.show_layer(mode, state, map.viewer_id())
		var rendered := _label_text_of(legend)
		if rendered.contains("%%"):
			_fail("the '%s' legend shows a literal '%%' -- a doubled percent in a stop nothing formats: %s" % [mode, rendered])
		var shown: Array = MapLayers.production_stops(even) if mode == "production" else MapLayers.stops(mode)
		for stop in shown:
			if not rendered.contains(String(stop["text"])):
				_fail("the '%s' legend does not show the stop text '%s' -- what is on screen: %s" % [
					mode, String(stop["text"]), rendered])
	# A const stop is a msgid: the text the legend looks up must be the literal the
	# extractor lists. "%d%%  dependent" formatted inside the const was looked up as
	# "60%  dependent", which no table could ever hold (V5.1b3). The literal states
	# the number, so the top stop must still match the cap it names.
	var source := FileAccess.get_file_as_string("res://src/ui/map_layers.gd")
	for stop in MapLayers.stops("import_dependency"):
		if not source.contains("\"%s\"" % String(stop["text"])):
			_fail("the import stop '%s' is not a literal in map_layers.gd, so no table can translate it" % stop["text"])
	var top := String(MapLayers.stops("import_dependency")[-1]["text"])
	if not top.begins_with("%d%%" % roundi(100.0 * MapLayers.IMPORT_MAX_SHOWN)):
		_fail("the import legend's top stop '%s' no longer names the cap, %d%%" % [top, roundi(100.0 * MapLayers.IMPORT_MAX_SHOWN)])
	legend.show_layer(MapLayers.POLITICAL, state, map.viewer_id())


func _all_color_rects(node) -> Array:
	var out: Array = []
	for n in _walk(node):
		if n is ColorRect:
			out.append(n)
	return out


## Every Label's text inside the legend, which is what the player actually reads --
## the swatch colour and its stop text are two different failures and only one of
## them was being checked.
func _label_text_of(node) -> String:
	var out := ""
	for n in _walk(node):
		if n is Label:
			out += String(n.text) + "\n"
	return out


func _loader_goods() -> Array:
	var out: Array = _main._loader.commodity_goods.keys()
	out.sort()
	return out


## Finding 7's test leg: the zero-dependency hover must be a COMPLETE sentence.
## The shipped form read "DEU  buys nothing in" -- a preposition with no object
## -- for every nation at month 0 and 13 of 29 after a year (runtime-measured in
## review round 2). The fix says "is self-sufficient"; this asserts the rendered
## words the player reads, the run-1 lesson (a swatch-colour check could not see
## this class). Month 0 only, and before any fixture mutates a register: at
## month 0 every nation's dependency is exactly 0.0, so all 29 hit the branch.
func _check_hover_sentences(state) -> void:
	var viewer: String = _main._map_view.viewer_id()
	for nation_id in state.nations.keys():
		var text: String = MapLayers.value_text(MapLayers.IMPORT_DEPENDENCY, state, viewer, String(nation_id))
		if text.contains("nothing in"):
			_fail("hover for %s still dangles the preposition: %s" % [nation_id, text])
		if not text.contains("self-sufficient"):
			_fail("zero-dependency hover for %s is not the self-sufficient sentence: %s" % [nation_id, text])


func _walk(node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


func _deep_equal(a, b) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for key in a.keys():
				if not b.has(key) or not _deep_equal(a[key], b[key]):
					return false
			return true
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i in range(a.size()):
				if not _deep_equal(a[i], b[i]):
					return false
			return true
		TYPE_FLOAT:
			return absf(a - b) < 1e-12
		_:
			return a == b


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.001 and absf(a.g - b.g) < 0.001 and absf(a.b - b.b) < 0.001


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_commodities_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	if _main != null:
		_main.queue_free()