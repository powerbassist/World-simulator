extends PanelContainer

## The layer switcher and its legend -- U5c. One plate: three toggles, the active
## layer's ramp read out as swatch-and-label rows, and a line naming whatever is
## under the cursor.
##
## Placed bottom-left above the portrait card rather than in the clock cluster
## next to the minimap, which is where it spatially belongs. The cluster reserved
## its box at a fixed size a session early and tests/test_minimap.gd asserts that
## nothing grows it; putting a switcher in there would mean deliberately
## re-reserving that box and rewriting the one assertion whose whole purpose is
## to catch exactly that. Not worth a corner.
##
## Not a floating window either: a layer switcher you have to open a window to
## reach is a mode the player forgets they are in, and the legend has to be on
## screen while the colours are being read or it is not a legend.
##
## Proposes, never commands -- the same shape clock_cluster.gd states. The active
## layer lives on map_view.gd; this file emits an id and is told what to show.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const MapLayers = preload("res://src/ui/map_layers.gd")
const MapNetwork = preload("res://src/ui/map_network.gd")

signal layer_selected(layer_id: String)

const SWATCH_SIZE := Vector2(22, 12)
const KEY_SIZE := Vector2(22, 8)

## Wide enough that the hover readout's longest form -- "NLD  11.1% of FRA's
## demand" -- does not resize the plate as the cursor crosses the map. A legend
## that changes width while being read is furniture moving under the player.
const MIN_WIDTH := 196

var _buttons := {}          ## layer id -> Button
var _stops: VBoxContainer
var _key: VBoxContainer
var _caption: Label
var _readout: Label
var _layer := MapLayers.POLITICAL


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	custom_minimum_size.x = MIN_WIDTH

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var heading := Label.new()
	heading.theme_type_variation = UiTheme.MICRO
	heading.text = "MAP LAYER"
	column.add_child(heading)

	# Built from MapLayers.ids() and from nothing else, so adding a layer to the
	# registry adds its toggle here with no edit in this file. That is the
	# session's stated contract; tests/test_map_layers.gd asserts the count.
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 2)
	column.add_child(toggles)

	for id in MapLayers.ids():
		var button := Button.new()
		button.theme_type_variation = UiTheme.SUBROW_BUTTON
		button.toggle_mode = true
		button.text = MapLayers.label(id).to_upper()
		var layer_id := String(id)
		button.pressed.connect(func(): layer_selected.emit(layer_id))
		toggles.add_child(button)
		_buttons[layer_id] = button

	_stops = VBoxContainer.new()
	_stops.add_theme_constant_override("separation", 2)
	column.add_child(_stops)

	# V3.4. Always present, on every layer, because the roads are: they are
	# geography rather than a view of it. Two rows and no toggle -- a switcher
	# for a thing that is always on is a control that only ever says yes.
	_key = VBoxContainer.new()
	_key.add_theme_constant_override("separation", 2)
	column.add_child(_key)
	_key.add_child(_key_row(false, "road"))
	_key.add_child(_key_row(true, "ferry"))

	_caption = Label.new()
	_caption.theme_type_variation = UiTheme.CAPTION
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_caption)

	_readout = Label.new()
	_readout.theme_type_variation = UiTheme.FIGURE_LABEL
	column.add_child(_readout)

	# The re-show keeps whatever state the last caller handed in; without it the
	# trade stops would revert to the empty literal table on every hover.
	show_layer(_layer, _last_state, _last_viewer)


## Told, not asked. main.gd sets the map view's layer and then this, so the two
## cannot disagree about which one is up -- the panel never reads back from the
## control it just addressed.
var _last_state = null
var _last_viewer := ""


func show_layer(layer_id: String, state = null, viewer_id := "") -> void:
	_layer = String(MapLayers.layer(layer_id)["id"])
	if state != null:
		_last_state = state
		_last_viewer = viewer_id

	for id in _buttons.keys():
		_buttons[id].button_pressed = (id == _layer)

	for child in _stops.get_children():
		_stops.remove_child(child)
		child.queue_free()

	# The trade layer's scale is the viewer's own partner count, so its stops --
	# and the swatch colours beside them -- derive from the same even share the
	# ramp draws with; a literal here is how the legend promised "an even ninth"
	# on a twenty-eight-partner roster.
	var stops: Array = MapLayers.stops(_layer)
	var even := -1.0
	if _layer == MapLayers.TRADE and state != null:
		even = MapLayers.trade_even_share(state, viewer_id)
		stops = MapLayers.trade_stops(even)
	for stop in stops:
		_stops.add_child(_stop_row(float(stop["at"]), String(stop["text"]), even))

	_caption.text = MapLayers.caption(_layer)
	show_hover("", null, "")


## One row per legend stop. The swatch is MapLayers.ramp() at that stop's value
## rather than a colour typed here, so a ramp edit cannot leave the legend
## showing the old one.
func _stop_row(at: float, text: String, trade_even := -1.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var swatch := ColorRect.new()
	# The trade layer colours through ramp_trade at the same derived even share
	# the stops were computed with; a plain ramp() call here is what left every
	# trade swatch at the ramp's low colour after the trade branch moved.
	swatch.color = MapLayers.ramp_trade(at, trade_even) if trade_even > 0.0 else MapLayers.ramp(_layer, at)
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)

	var label := Label.new()
	label.theme_type_variation = UiTheme.CAPTION
	label.text = text
	row.add_child(label)

	return row


## One key row. The sample is drawn with MapNetwork's own colour and dash rather
## than a literal here, for the same reason _stop_row() takes its swatch from
## MapLayers.ramp(): a stroke edit must not leave the legend showing the old one.
func _key_row(dashed: bool, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var sample := Control.new()
	sample.custom_minimum_size = KEY_SIZE
	sample.draw.connect(func():
		var y := KEY_SIZE.y / 2.0
		if dashed:
			var x := 0.0
			while x < KEY_SIZE.x:
				var to_x: float = minf(x + MapNetwork.DASH_PX, KEY_SIZE.x)
				sample.draw_line(Vector2(x, y), Vector2(to_x, y), MapNetwork.SEA, MapNetwork.WIDTH)
				x += MapNetwork.DASH_PX + MapNetwork.GAP_PX
		else:
			sample.draw_line(Vector2(0, y), Vector2(KEY_SIZE.x, y), MapNetwork.LAND, MapNetwork.WIDTH)
	)
	row.add_child(sample)

	var label := Label.new()
	label.theme_type_variation = UiTheme.MICRO
	label.text = text
	row.add_child(label)
	return row


## The value under the cursor, spelled out. This is what makes a ramp readable
## to better than the nearest stop, and it is where the symmetric/directed split
## becomes visible to the player -- see MapLayers.value_text().
##
## An empty id keeps the line present and blank rather than removing it, so the
## plate does not change height every time the cursor leaves a country.
func show_hover(nation_id: String, state, viewer_id: String) -> void:
	if nation_id == "" or state == null:
		_readout.text = " "
		return
	_readout.text = MapLayers.value_text(_layer, state, viewer_id, nation_id)
