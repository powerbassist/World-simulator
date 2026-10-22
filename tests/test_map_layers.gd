extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_layers.gd
## Non-zero exit on any failure.
##
## Loads the actual main scene, same shape test_map_view.gd and test_minimap.gd
## use -- the layers read live GameState, so a hand-built dictionary would be
## testing a fixture rather than the game.
##
## The load-bearing assertions here are the two the session staked its shape on:
## that MapLayers.LAYERS is the *only* thing the switcher is built from (so
## V1.3c's sanctions layer is an entry and nothing else), and that a data layer's
## colour is viewer-relative rather than a property of the nation.

const MapLayers = preload("res://src/ui/map_layers.gd")
const Relations = preload("res://src/core/relations.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false  # _ready(), then one layout pass so the legend's rows exist

	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null or _main._map_view == null:
		_fail("main scene did not build a GameState and a map view")
		return
	if _main._hud == null or _main._hud.map_legend == null:
		_fail("main scene did not build the map legend")
		return

	_check_registry_drives_the_switcher()
	_check_political_caption()
	_check_ramps_are_monotone()
	_check_no_layer_reads_by_colour_alone()
	_check_viewer_relative()
	_check_the_viewer_has_no_value()
	_check_unknown_layer_falls_back()
	_check_legend_swatches_match_the_map()
	_check_readout_says_what_each_layer_may_claim()
	_check_coercion_is_summed_not_netted()
	_check_fills_match_the_per_nation_form()


## fills() exists to make a DRAG affordable, and the only way it may do that is
## by returning the colour color_for() would have returned. It reaches the same
## ramp by a different route -- one Trade.weights() build read for every nation
## instead of two builds per nation -- so nothing but this equality stops the
## two from drifting into different maps.
##
## Over EVERY registered layer, not just trade: fills() branches on the layer
## id, and a branch that is only exercised on the layer somebody was thinking
## about is the shape of check this project has shipped broken four times.
## Colour equality is exact rather than approximate -- both sides run the same
## float arithmetic on the same inputs, so anything less than exact means the
## two forms genuinely disagree.
func _check_fills_match_the_per_nation_form() -> void:
	var state = _main._state
	var ids: Array = state.nations.keys()
	ids.sort()
	if ids.size() < 2:
		_fail("the roster is too small to compare fills against (%d)" % ids.size())
		return

	for viewer_id: String in [String(ids[0]), String(ids[ids.size() - 1])]:
		for layer_id: String in MapLayers.ids():
			var bulk := MapLayers.fills(layer_id, state, viewer_id, ids)
			if bulk.size() != ids.size():
				_fail("fills() returned %d colours for %d nations on '%s'" % [
					bulk.size(), ids.size(), layer_id])
				continue
			for id in ids:
				var nation_id := String(id)
				var one := MapLayers.color_for(layer_id, state, viewer_id, nation_id)
				var many: Color = bulk.get(nation_id, Color(0, 0, 0, 0))
				if many != one:
					_fail("fills() disagrees with color_for() on '%s' for %s seen from %s: %s vs %s" % [
						layer_id, nation_id, viewer_id, many, one])

	# A null state is a real path -- the map draws before setup() hands it one --
	# and it must not reach Trade.weights() with nothing to read.
	var empty := MapLayers.fills(MapLayers.TRADE, null, String(ids[0]), ids)
	for id in ids:
		var nation_id := String(id)
		if empty.get(nation_id) != MapLayers.color_for(MapLayers.TRADE, null, String(ids[0]), nation_id):
			_fail("fills() over a null state disagrees with color_for() for %s" % nation_id)


## The contract that let U5c run before V1.3c: adding a layer is one entry in
## LAYERS. If the switcher ever stops being built from ids(), that stops being
## true and this fails.
func _check_registry_drives_the_switcher() -> void:
	var legend = _main._hud.map_legend
	var ids: Array = MapLayers.ids()
	if ids.size() < 3:
		_fail("expected at least three layers, got %d" % ids.size())
	if legend._buttons.size() != ids.size():
		_fail("legend built %d toggles for %d registered layers" % [
			legend._buttons.size(), ids.size()
		])
	for id in ids:
		if not legend._buttons.has(id):
			_fail("no toggle for registered layer '%s'" % id)


## B5 (playtest 2026-09-16): the political caption was "The ten the game
## simulates." -- a fragment that 25 of 58 frames read as broken text, and a
## hardcoded count that went stale when the roster hit 29 at V3.3. The repair is
## count-free, and this check pins both halves: the exact authored string, and
## the shape rules a count-free caption must satisfy so the next one does not
## reintroduce either defect.
func _check_political_caption() -> void:
	var caption := String(MapLayers.layer(MapLayers.POLITICAL)["caption"])
	var authored := "Roster nations in their own colour; outlines as borders, read on hover."
	if caption != authored:
		_fail("the political caption is not the authored string: '%s'" % caption)
	if caption.is_empty():
		_fail("the political caption is empty")
		return
	if not caption.ends_with("."):
		_fail("the political caption does not end with a period: '%s'" % caption)
	if caption.contains("The ten"):
		_fail("the political caption still carries the stale 'The ten' fragment")
	for i in 10:
		if caption.contains(str(i)):
			_fail("the political caption hardcodes a count: '%s'" % caption)
			break


## Monotone over the shown domain, and endpoints far enough apart to be told
## apart on a map. Not a colour comparison against typed values -- that would
## just restate the constants -- but a check that the ramp is a ramp.
func _check_ramps_are_monotone() -> void:
	_check_ramp_spread(MapLayers.RELATIONS, MapLayers.RELATIONS_MIN_SHOWN, MapLayers.RELATIONS_MAX_SHOWN)
	# The trade ramp's domain derives from the viewer's effective partners (V4.11), so
	# the spread is checked against the same even share the map draws with.
	var state_for_trade = _main._state
	var even := MapLayers.trade_even_share(state_for_trade, "FRA")
	_check_ramp_spread_trade(even)
	_check_ramp_spread(MapLayers.COERCION, 0.0, MapLayers.COERCION_MAX_SHOWN)

	# Clamped, not extrapolated: relations above 76 and a trade share above a
	# third are both reachable in a played game and must saturate at the end of
	# the ramp rather than run off it into a colour the legend never shows.
	var top := MapLayers.ramp(MapLayers.RELATIONS, MapLayers.RELATIONS_MAX_SHOWN)
	var past := MapLayers.ramp(MapLayers.RELATIONS, 100.0)
	if not _close(top, past):
		_fail("relations ramp is not clamped above its domain: %s vs %s" % [top, past])
	var bottom := MapLayers.ramp(MapLayers.RELATIONS, MapLayers.RELATIONS_MIN_SHOWN)
	var below := MapLayers.ramp(MapLayers.RELATIONS, 0.0)
	if not _close(bottom, below):
		_fail("relations ramp is not clamped below its domain: %s vs %s" % [bottom, below])


## V5.1-d2, the tier's done-when "no map layer that reads by colour alone": every
## data layer's fill also reads by LIGHTNESS, so a player who cannot tell its hues
## apart -- colour-blind, a washed-out screen, a greyscale frame -- still reads
## more from less. Relative luminance rises along the whole shown domain, and each
## legend stop sits at least MIN_STOP_CONTRAST (the WCAG ratio) above the one
## before it, since the stops are the keys the legend names. Political is
## categorical (a nation's own tone) and reads by the names drawn on it.
const MIN_STOP_CONTRAST := 1.4

func _check_no_layer_reads_by_colour_alone() -> void:
	var state = _main._state
	var trade_even := MapLayers.trade_even_share(state, "FRA")
	var prod_even := MapLayers.production_even_share(state)
	var ramps := {
		MapLayers.RELATIONS: [func(v: float) -> Color: return MapLayers.ramp(MapLayers.RELATIONS, v),
			MapLayers.stops(MapLayers.RELATIONS), MapLayers.RELATIONS_MIN_SHOWN, MapLayers.RELATIONS_MAX_SHOWN],
		MapLayers.TRADE: [func(v: float) -> Color: return MapLayers.ramp_trade(v, trade_even),
			MapLayers.trade_stops(trade_even), 0.0, 3.0 * trade_even],
		MapLayers.COERCION: [func(v: float) -> Color: return MapLayers.ramp(MapLayers.COERCION, v),
			MapLayers.stops(MapLayers.COERCION), 0.0, MapLayers.COERCION_MAX_SHOWN],
		MapLayers.PRODUCTION: [func(v: float) -> Color: return MapLayers.ramp_production(v, prod_even),
			MapLayers.production_stops(prod_even), 0.0, MapLayers.PRODUCTION_MAX_SHOWN],
		MapLayers.IMPORT_DEPENDENCY: [func(v: float) -> Color: return MapLayers.ramp(MapLayers.IMPORT_DEPENDENCY, v),
			MapLayers.stops(MapLayers.IMPORT_DEPENDENCY), 0.0, MapLayers.IMPORT_MAX_SHOWN],
	}
	for id in MapLayers.ids():
		if id == MapLayers.POLITICAL:
			continue
		if not ramps.has(id):
			_fail("layer '%s' has no lightness check -- add its ramp here" % id)
			continue
		var entry: Array = ramps[id]
		var colour_at: Callable = entry[0]
		var low: float = entry[2]
		var high: float = entry[3]
		var previous := _luminance(colour_at.call(low))
		for step in range(1, 41):
			var current := _luminance(colour_at.call(low + (high - low) * float(step) / 40.0))
			if current < previous - 0.002:
				_fail("%s ramp darkens as its value rises (%.3f -> %.3f at step %d): it reads by hue alone there" % [id, previous, current, step])
				break
			previous = current
		var stops: Array = entry[1]
		for i in range(1, stops.size()):
			var a := _luminance(colour_at.call(float(stops[i - 1]["at"])))
			var b := _luminance(colour_at.call(float(stops[i]["at"])))
			var ratio := (b + 0.05) / (a + 0.05)
			if ratio < MIN_STOP_CONTRAST:
				_fail("%s: the stops '%s' and '%s' differ by %.2f:1 in lightness, under %.1f" % [
					id, stops[i - 1]["text"], stops[i]["text"], ratio, MIN_STOP_CONTRAST])


func _luminance(c: Color) -> float:
	return c.srgb_to_linear().get_luminance()


func _check_ramp_spread_trade(even: float) -> void:
	var previous := MapLayers.ramp_trade(0.0, even)
	var first := previous
	for step in range(1, 21):
		var at: float = 3.0 * even * float(step) / 20.0
		var current := MapLayers.ramp_trade(at, even)
		if _close(current, previous) and step > 1:
			_fail("trade ramp is flat between two sampled values at %s" % at)
			return
		previous = current
	if _close(first, previous):
		_fail("trade ramp endpoints are not far apart")


func _check_ramp_spread(layer_id: String, low: float, high: float) -> void:
	var previous := MapLayers.ramp(layer_id, low)
	var first := previous
	for step in range(1, 21):
		var at: float = low + (high - low) * float(step) / 20.0
		var current := MapLayers.ramp(layer_id, at)
		if _close(current, previous) and step > 1:
			_fail("%s ramp is flat between two sampled values at %s" % [layer_id, at])
			return
		previous = current

	# Distance in RGB, not a per-channel comparison: the relations ramp diverges
	# through a pale neutral, so red and green both fall and rise along it and
	# no single channel is monotone. What has to hold is that the two ends are
	# nowhere near each other.
	var spread := Vector3(first.r - previous.r, first.g - previous.g, first.b - previous.b).length()
	if spread < 0.5:
		_fail("%s ramp's endpoints are only %.2f apart in RGB" % [layer_id, spread])


## V1.3c's one real design call, and the one a later session is most likely to
## "tidy" into a signed net. The colour is TOTAL severity on the pair, both
## directions summed -- so a mutual embargo reads as the most coerced pair on the
## map. Netted, it would read as clean, which is the single worst thing this map
## could say.
func _check_coercion_is_summed_not_netted() -> void:
	var state = _main._state

	var clean := MapLayers.value(MapLayers.COERCION, state, "FRA", "DEU")
	if not is_zero_approx(clean):
		_fail("a clean pair does not read 0.0 on the coercion layer: %s" % clean)

	state.measures[Relations.directed_key("FRA", "DEU")] = _terms("tariff", 0.625)
	var one_way := MapLayers.value(MapLayers.COERCION, state, "FRA", "DEU")

	state.measures[Relations.directed_key("DEU", "FRA")] = _terms("tariff", 0.625)
	var both_ways := MapLayers.value(MapLayers.COERCION, state, "FRA", "DEU")

	if both_ways <= one_way:
		_fail("a mutual measure (%.3f) does not read above a one-way one (%.3f) -- the layer is netting rather than summing" % [both_ways, one_way])

	# And the readout must recover the direction the colour summed away, naming
	# both sides -- the one place on this map a readout claims both, and it may,
	# because the player is party to both.
	var text := MapLayers.value_text(MapLayers.COERCION, state, "FRA", "DEU")
	if text.find("you") == -1 or text.find("them") == -1:
		_fail("the coercion readout does not name both directions: '%s'" % text)

	state.measures.clear()
	if not is_zero_approx(MapLayers.value(MapLayers.COERCION, state, "FRA", "DEU")):
		_fail("clearing the register did not return the layer to 0.0")


func _terms(kind: String, severity: float) -> Dictionary:
	return {
		"action_id": "test", "action_name": "Test", "kind": kind,
		"severity": severity, "since_year": 2026, "since_month": 1,
		"retaliated": true,
	}


## A trade weight is one row of ninety. The same nation must not come back the
## same colour when the seat changes, or the layer is drawing a property of the
## nation and the directed weight V1.3b built is being thrown away.
func _check_viewer_relative() -> void:
	var state = _main._state
	var from_fra := MapLayers.swatch(MapLayers.TRADE, state, "FRA", "LUX")
	var from_deu := MapLayers.swatch(MapLayers.TRADE, state, "DEU", "LUX")
	if _close(from_fra, from_deu):
		_fail("trade colour for LUX is the same from FRA and from DEU: %s" % from_fra)

	# Relations are symmetric, so the pair reads the same from either side -- the
	# other half of the asymmetry, asserted rather than assumed.
	var fra_deu := MapLayers.swatch(MapLayers.RELATIONS, state, "FRA", "DEU")
	var deu_fra := MapLayers.swatch(MapLayers.RELATIONS, state, "DEU", "FRA")
	if not _close(fra_deu, deu_fra):
		_fail("relations colour is not symmetric: FRA->DEU %s, DEU->FRA %s" % [fra_deu, deu_fra])


## The viewer has no PAIR with itself, so on the pair layers it takes NO_VALUE
## and must not be on the ramp at all, at either end. V4.6: THE RULE IS
## PER-LAYER NOW -- the loop below covers [RELATIONS, TRADE], the pair layers it
## has always exercised, while the two commodity layers are the FIRST where the
## viewer's own nation carries a real reading (production and import dependency
## are properties of a nation, not of a pair). That exception is pinned in
## tests/test_commodities_panel.gd (value() is non-NAN and the swatch is not
## NO_VALUE for the viewer on those two layers).
func _check_the_viewer_has_no_value() -> void:
	var state = _main._state
	for layer_id in [MapLayers.RELATIONS, MapLayers.TRADE]:
		var own := MapLayers.swatch(layer_id, state, "FRA", "FRA")
		if not _close(own, MapLayers.NO_VALUE):
			_fail("%s: the viewer's own nation is not drawn as NO_VALUE: %s" % [layer_id, own])
		if not is_nan(MapLayers.value(layer_id, state, "FRA", "FRA")):
			_fail("%s: the viewer's own nation has a value" % layer_id)

	# And the political layer, which is an identity tint rather than a datum,
	# still gives it a palette colour -- the home mark there is the outline.
	var political := MapLayers.swatch(MapLayers.POLITICAL, state, "FRA", "FRA")
	if _close(political, MapLayers.NO_VALUE):
		_fail("the political layer dropped the viewer's own fill")


func _check_unknown_layer_falls_back() -> void:
	if MapLayers.layer("no-such-layer")["id"] != MapLayers.POLITICAL:
		_fail("an unknown layer id did not fall back to political")

	var map = _main._map_view
	var before: String = map.layer()
	map.set_layer("no-such-layer")
	if map.layer() != MapLayers.POLITICAL:
		_fail("map_view.set_layer stored an unknown id: '%s'" % map.layer())
	map.set_layer(before)

	# The map opens on the political layer -- the one that needs no simulation
	# state to be legible.
	if before != MapLayers.POLITICAL:
		_fail("the map did not open on the political layer, but on '%s'" % before)


## A legend that draws its own colour table would drift from the map the first
## time a ramp is edited. Every swatch is ramp() at that stop's value.
func _check_legend_swatches_match_the_map() -> void:
	var legend = _main._hud.map_legend
	var state = _main._state
	for layer_id in [MapLayers.RELATIONS, MapLayers.TRADE]:
		legend.show_layer(layer_id, state, "FRA")
		# The trade stops derive from the viewer's partner count -- the same even
		# share the ramp colours with -- so the legend cannot promise a fixed
		# scale the map no longer uses.
		var stops: Array = MapLayers.stops(layer_id)
		var even := MapLayers.trade_even_share(state, "FRA")
		if layer_id == MapLayers.TRADE:
			stops = MapLayers.trade_stops(even)
		var rects: Array = _all_color_rects(legend)
		if rects.size() != stops.size():
			_fail("%s: legend shows %d swatches for %d stops" % [
				layer_id, rects.size(), stops.size()
			])
			continue
		for i in stops.size():
			var expected: Color
			if layer_id == MapLayers.TRADE:
				expected = MapLayers.ramp_trade(float(stops[i]["at"]), even)
			else:
				expected = MapLayers.ramp(layer_id, float(stops[i]["at"]))
			if not _close(rects[i].color, expected):
				_fail("%s: swatch %d is %s, ramp says %s" % [
					layer_id, i, rects[i].color, expected
				])

	legend.show_layer(MapLayers.POLITICAL, state, "FRA")
	if not _all_color_rects(legend).is_empty():
		_fail("the political layer has no stops but the legend drew swatches")

	# V5.1-0c: the grade rows were dev text ("4 playable, yours to lead", "37
	# simulated, run by the game", "133 outlines, one world market") -- the author
	# asked why a scope statement was in the game. They are gone; what an outline is
	# is the caption's job. Pinned over every label the legend draws, so the words
	# cannot come back under another name.
	for label in _labels_of(legend):
		var text := String(label.text).to_lower()
		for banned in ["playable", "simulated", "run by the game", "yours to lead", "one world market"]:
			if text.contains(banned):
				_fail("the legend still carries dev text '%s' in '%s'" % [banned, label.text])
	legend.show_layer(MapLayers.RELATIONS, state, "FRA")
	legend.show_layer(MapLayers.POLITICAL, state, "FRA")


func _labels_of(node: Node) -> Array:
	var out: Array = []
	if node is Label and not node.is_queued_for_deletion():
		out.append(node)
	for child in node.get_children():
		out.append_array(_labels_of(child))
	return out


## The asymmetry as the player meets it. A relations readout may name the pair,
## because the number is true read from either side; a trade readout may not,
## because the share belongs to the viewer alone.
func _check_readout_says_what_each_layer_may_claim() -> void:
	var state = _main._state
	var relations := MapLayers.value_text(MapLayers.RELATIONS, state, "FRA", "DEU")
	if not relations.contains("FRA") or not relations.contains("DEU"):
		_fail("the relations readout does not name both sides of the pair: '%s'" % relations)

	var trade := MapLayers.value_text(MapLayers.TRADE, state, "FRA", "DEU")
	if not trade.contains("%"):
		_fail("the trade readout does not give a share: '%s'" % trade)

	var own := MapLayers.value_text(MapLayers.TRADE, state, "FRA", "FRA")
	if own.contains("%"):
		_fail("the readout claims a trade share for the viewer's own nation: '%s'" % own)


func _all_color_rects(node) -> Array:
	var out: Array = []
	if node is ColorRect:
		out.append(node)
	for child in node.get_children():
		out.append_array(_all_color_rects(child))
	return out


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_map_layers: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
