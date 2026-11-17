extends SceneTree

## Headless test: godot --headless --script res://tests/test_legend_clear.gd
## Non-zero exit on any failure.
##
## Gate 3, G3-20 (the author: "clicking on foreign country put colors on france"). At the
## opening camera the legend plate sat over Spain and Portugal, so a click aimed at Iberia
## landed on a layer chip and turned the map to RELATIONS, which fills the player's own nation
## with NO_VALUE. The plate is the map's furniture: at the opening camera, on every layer, no
## point of it may lie over a nation a click would open (map_view.nation_at_screen_point).
## G3-21: on the pair layers the legend names that NO_VALUE fill.

const MapLayers = preload("res://src/ui/map_layers.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## The text sizes the settings offer at their ends: the plate grows with its text.
const SCALES := [1.0, 1.3]

var _failures: Array[String] = []
var _main
var _frame := 0
var _layers: Array = []
var _cases: Array = []
var _layer_index := -1
var _checked := 0


func _init() -> void:
	root.size = Vector2i(1920, 1080)
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	_layers = MapLayers.ids()
	for scale in SCALES:
		for id in _layers:
			_cases.append([float(scale), String(id)])


func _process(_delta: float) -> bool:
	_frame += 1
	# The headless window opens at its own size; the opening camera is fitted to the
	# viewport, so the 1920x1080 frame the author plays is set before the map fits.
	if root.size != Vector2i(1920, 1080):
		root.size = Vector2i(1920, 1080)
	if _frame < 6:
		return false
	if _frame == 6:
		# The map fits its opening camera once, on its first size; the headless window's
		# first size was not the player's, so the fit is taken again at 1920x1080.
		_main._map_view._has_fitted = false
		_main._map_view._fit_zoom()
		return false
	# One case per three frames: the plate re-lays out after show_layer() (a data layer
	# grows it) and after a new text size.
	if _frame % 3 == 0:
		if _layer_index >= 0:
			_check_clear(_cases[_layer_index])
		_layer_index += 1
		if _layer_index >= _cases.size():
			UiTheme.set_text_scale(1.0)
			UiTheme.rebuild(_main)
			_check_you_row()
			_finish()
			return true
		var c: Array = _cases[_layer_index]
		if UiTheme.text_scale() != float(c[0]):
			UiTheme.set_text_scale(float(c[0]))
			# The settings row's own path for a text size changed mid-game.
			UiTheme.rebuild(_main)
		_main._map_view.set_layer(String(c[1]))
		_main._hud.map_legend.show_layer(String(c[1]), _main._state, _main._map_view.viewer_id(), "France")
		# The longest hover line this layer can print: the readout must not widen the plate.
		_main._hud.map_legend.show_hover(_longest_readout(String(c[1])), _main._state, _main._map_view.viewer_id())
	return false


func _longest_readout(layer_id: String) -> String:
	var best := ""
	var best_len := -1
	for id in _main._state.nations.keys():
		var n := MapLayers.value_text(layer_id, _main._state, _main._map_view.viewer_id(), String(id)).length()
		if n > best_len:
			best_len = n
			best = String(id)
	return best


func _check_clear(c: Array) -> void:
	var layer_id := "%s at text %d %%" % [c[1], roundi(float(c[0]) * 100)]
	var legend: Control = _main._hud.map_legend
	var map = _main._map_view
	if not legend.is_visible_in_tree():
		_fail("%s: the legend is not shown at the opening camera" % layer_id)
		return
	var rect: Rect2 = legend.get_global_rect()
	_checked += 1
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
			layer_id, rect, ", ".join(PackedStringArray(hits.keys()))])


## G3-21: the pair layers fill the player's own nation with NO_VALUE, and the legend says so.
func _check_you_row() -> void:
	var legend = _main._hud.map_legend
	for layer_id in [MapLayers.RELATIONS, MapLayers.TRADE, MapLayers.COERCION, MapLayers.POLITICAL, MapLayers.PRODUCTION]:
		legend.show_layer(layer_id, _main._state, "FRA", "France")
		var found := false
		for label in legend.find_children("*", "Label", true, false):
			if not (label as Label).is_queued_for_deletion() and String(label.text) == "France (you): no value on this layer":
				found = true
		var wants: bool = layer_id in [MapLayers.RELATIONS, MapLayers.TRADE, MapLayers.COERCION]
		if found != wants:
			_fail("%s: the legend %s a row for the player's own no-value fill" % [layer_id, "lacks" if wants else "wrongly carries"])
	legend.show_layer(MapLayers.POLITICAL, _main._state, "FRA", "France")


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _checked != _cases.size():
		_fail("checked %d cases of %d" % [_checked, _cases.size()])
	if _failures.is_empty():
		print("PASS test_legend_clear")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		quit(1)
