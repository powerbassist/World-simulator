extends SceneTree

## Headless test: godot --headless --script res://tests/test_legend_clear.gd
## Non-zero exit on any failure.
##
## Gate 3, G3-20 (the author: "clicking on foreign country put colors on france"). At the
## opening camera the legend plate sat over Spain and Portugal, so a click aimed at Iberia
## landed on a layer chip and turned the map to RELATIONS, which fills the player's own nation
## with NO_VALUE. The plate is the map's furniture: at the opening camera, on every layer, at
## both ends of the text sizes and on the common laptop screens, no point of it may lie over a
## nation a click would open (map_view.nation_at_screen_point) -- with the longest hover line
## each layer prints in a game twelve months on, which must wrap rather than widen the plate.
## G3-21: on the pair layers the legend names that NO_VALUE fill.
##
## Every layer change goes through the legend's own signal, the call site main.gd wires.

const MapLayers = preload("res://src/ui/map_layers.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

## The text sizes the settings offer at their ends: the plate grows with its text.
const SCALES := [0.9, 1.0]
## The author's screen, then the two common laptop screens.
const SCREENS := [Vector2i(1920, 1080), Vector2i(1366, 768), Vector2i(1280, 720)]
## A game this far on: trade shares, measures and relations have moved off their seeds.
const MONTHS_ON := 12
## Frames a case is given to lay out (a new window size, a new text size, a new layer).
const SETTLE := 3

var _failures: Array[String] = []
var _main
var _frame := 0
var _cases: Array = []
var _case := -1
var _wait := 0
var _checked := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	for screen in SCREENS:
		for scale in SCALES:
			for id in MapLayers.ids():
				_cases.append({"screen": screen, "scale": float(scale), "layer": String(id)})


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		# Held still: a month end mid-run would redraw the legend under the check.
		_main._clock.paused = true
		for i in MONTHS_ON:
			WorldMonth.tick_month(_main._state, _main._loader)
		return false
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_check_clear(_cases[_case])
		return false
	_case += 1
	if _case >= _cases.size():
		_set_scale(1.0)
		_check_you_row()
		_finish()
		return true
	_stage(_cases[_case])
	_wait = SETTLE
	return false


func _stage(c: Dictionary) -> void:
	var screen: Vector2i = c["screen"]
	if root.size != screen:
		root.size = screen
		# The map fits its opening camera once, on its first size; each screen is the
		# opening camera of a game started on it.
		_main._map_view._has_fitted = false
		_main._map_view._fit_zoom.call_deferred()
	if UiTheme.text_scale() != float(c["scale"]):
		_set_scale(float(c["scale"]))
	var legend = _main._hud.map_legend
	legend.layer_selected.emit(String(c["layer"]))
	legend.show_hover(_longest_readout(String(c["layer"])), _main._state, _main._map_view.viewer_id())


func _set_scale(scale: float) -> void:
	UiTheme.set_text_scale(scale)
	# The settings row's own path for a text size changed mid-game.
	UiTheme.rebuild(_main)


func _longest_readout(layer_id: String) -> String:
	var best := ""
	var best_len := -1
	for id in _main._state.nations.keys():
		var n := MapLayers.value_text(layer_id, _main._state, _main._map_view.viewer_id(), String(id)).length()
		if n > best_len:
			best_len = n
			best = String(id)
	return best


func _check_clear(c: Dictionary) -> void:
	var label := "%s at text %d %% on %dx%d" % [c["layer"], roundi(float(c["scale"]) * 100), c["screen"].x, c["screen"].y]
	var legend: Control = _main._hud.map_legend
	var map = _main._map_view
	if map.layer() != String(c["layer"]):
		_fail("%s: the legend's signal did not set the map's layer (%s)" % [label, map.layer()])
	if not legend.is_visible_in_tree():
		_fail("%s: the legend is not shown at the opening camera" % label)
		return
	_checked += 1
	var rect: Rect2 = legend.get_global_rect()
	var hits := {}
	var y := rect.position.y
	while y <= rect.end.y:
		var x := rect.position.x
		while x <= rect.end.x:
			var id: String = map.nation_at_screen_point(Vector2(x, y))
			if id != "":
				hits[id] = true
			x += 6.0
		y += 6.0
	if not hits.is_empty():
		_fail("%s: the legend plate (%s) lies over %s at the opening camera; a click aimed there switches the layer" % [
			label, rect, ", ".join(PackedStringArray(hits.keys()))])


## G3-21: the pair layers fill the player's own nation with NO_VALUE, and the legend says so.
func _check_you_row() -> void:
	var legend = _main._hud.map_legend
	var name: String = _main._loader.nation_name(_main._map_view.viewer_id())
	for layer_id in MapLayers.ids():
		legend.layer_selected.emit(String(layer_id))
		var found := false
		for label in legend.find_children("*", "Label", true, false):
			if not (label as Label).is_queued_for_deletion() and String(label.text) == "%s (you): no value on this layer" % name:
				found = true
		if found != MapLayers.is_pair_layer(String(layer_id)):
			_fail("%s: the legend %s a row for the player's own no-value fill" % [
				layer_id, "lacks" if MapLayers.is_pair_layer(String(layer_id)) else "wrongly carries"])
	legend.layer_selected.emit(MapLayers.POLITICAL)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _checked != _cases.size():
		_fail("checked %d cases of %d" % [_checked, _cases.size()])
	if _failures.is_empty():
		print("PASS test_legend_clear (%d cases)" % _checked)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		quit(1)
