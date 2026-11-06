extends RefCounted

## A counter's chips (V5.3 b, #280 and #285): shared by a process's price ask and a plant
## closure's buyer, so the player learns one shape. The caller fills the strip and makes
## the counter; the picks are read, then answered.

const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")


## #280's counters as ONE row (the parent's design): a chip per counter (5, 10, 15 %),
## the picked chip's strip under the row -- the countered price, the blocs, its chances
## as the sim shows them (the range, NEVER the drawn odds) and the walk-away risk --
## and one button that makes the picked counter. The picks are read, then answered.
static func build(box: Control, counters: Array, fill: Callable, make: Callable, go_key: String) -> void:
	var row := PanelKit.buttons(box)
	PanelKit.plain_line(row, Strings.t("Counter"), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var group := ButtonGroup.new()
	# No fixed width (the parent's ruling on #281): the strip takes half the row, a
	# spacer the other half, so it shrinks with a narrow workspace and wraps at a larger
	# text size, while its money stays near its caption rather than at the far edge.
	var strip := EffectsStrip.new()
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.set_meta("counter_strip", true)
	var half := HBoxContainer.new()
	half.add_child(strip)
	var rest := Control.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	half.add_child(rest)
	var go := PanelKit.sized(Button.new())
	go.text = Strings.t("Make the counter")
	go.set_meta(go_key, "counter")
	var picked := [String(counters[0]["id"])]
	var show := func(option: Dictionary) -> void:
		picked[0] = String(option["id"])
		fill.call(strip, option)
	for option in counters:
		var chip := PanelKit.sized(Button.new())
		chip.text = Strings.t("%d %%") % roundi(100.0 * float(option["counter"]))
		chip.toggle_mode = true
		chip.button_group = group
		chip.button_pressed = String(option["id"]) == picked[0]
		chip.set_meta("counter_id", String(option["id"]))
		chip.pressed.connect(func() -> void: show.call(option))
		row.add_child(chip)
	box.add_child(half)
	box.add_child(go)
	go.pressed.connect(func() -> void: make.call(String(picked[0])))
	show.call(counters[0])


## An answer id's words: negotiate_N is "Counter N %".
static func label(id: String) -> String:
	return Strings.t("Counter %d %%") % int(id.trim_prefix("negotiate_"))
