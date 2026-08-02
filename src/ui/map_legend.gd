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

signal layer_selected(layer_id: String)

const SWATCH_SIZE := Vector2(22, 12)

## Wide enough that the hover readout's longest form -- "NLD  11.1% of FRA's
## demand" -- does not resize the plate as the cursor crosses the map. A legend
## that changes width while being read is furniture moving under the player.
const MIN_WIDTH := 196

var _buttons := {}          ## layer id -> Button
var _stops: VBoxContainer
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

	_caption = Label.new()
	_caption.theme_type_variation = UiTheme.CAPTION
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_caption)

	_readout = Label.new()
	_readout.theme_type_variation = UiTheme.FIGURE_LABEL
	column.add_child(_readout)

	show_layer(_layer)


## Told, not asked. main.gd sets the map view's layer and then this, so the two
## cannot disagree about which one is up -- the panel never reads back from the
## control it just addressed.
func show_layer(layer_id: String) -> void:
	_layer = String(MapLayers.layer(layer_id)["id"])

	for id in _buttons.keys():
		_buttons[id].button_pressed = (id == _layer)

	for child in _stops.get_children():
		_stops.remove_child(child)
		child.queue_free()

	for stop in MapLayers.stops(_layer):
		_stops.add_child(_stop_row(float(stop["at"]), String(stop["text"])))

	_caption.text = MapLayers.caption(_layer)
	show_hover("", null, "")


## One row per legend stop. The swatch is MapLayers.ramp() at that stop's value
## rather than a colour typed here, so a ramp edit cannot leave the legend
## showing the old one.
func _stop_row(at: float, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var swatch := ColorRect.new()
	swatch.color = MapLayers.ramp(_layer, at)
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)

	var label := Label.new()
	label.theme_type_variation = UiTheme.CAPTION
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
