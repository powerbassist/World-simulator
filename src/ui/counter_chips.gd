extends RefCounted

## A counter's chips (V5.3 b, #280 and #285): shared by a process's price ask and a plant
## closure's buyer, so the player learns one shape. The caller fills the strip and makes
## the counter; the picks are read, then answered.

const AnswerRow = preload("res://src/ui/answer_row.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")

## The chip picked on each row (a process or a closure id), so a rebuild of the panel
## keeps what the player is weighing. A display pick only: a stale id falls back to the
## first chip, and the strip always prices the chip shown.
static var _picked := {}


## #280's counters as ONE answer row (Design's T13 on #441): the button that makes the picked
## counter in the row's first cell, like every answer; in its slots a chip per counter (5, 10,
## 15 %), the picked chip's cost in the costs' column, who it pleases and angers (the glyph
## lines), what follows, and its chance as the sim shows it (the range, NEVER the drawn odds).
## `fill(strip, option)` prices the strip and returns what follows. The picks are read, then answered.
static func build(box: VBoxContainer, key: String, counters: Array, fill: Callable, make: Callable, go_key: String) -> void:
	var go := PanelKit.sized(Button.new())
	var slots := AnswerRow.shell(box, go)
	var row := PanelKit.buttons(slots)
	PanelKit.plain_line(row, Strings.t("Counter"), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var group := ButtonGroup.new()
	var strip := EffectsStrip.new()
	strip.price_neutral = true
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.set_meta("counter_strip", true)
	var who := AnswerRow.who_box(slots)
	var follows := PanelKit.plain_line(slots, "")
	follows.set_meta("counter_follows", true)
	go.text = Strings.t("Make the counter")
	go.set_meta(go_key, "counter")
	var shown: Dictionary = counters[0]
	for option in counters:
		if String(option["id"]) == String(_picked.get(key, "")):
			shown = option
	# The chance they accept as a range on a 0 to 100 track (Design's T8 on #441), the sim's
	# shown range, never the drawn odds; its middle is the range's.
	var chance := ChartKit.range_bar(slots, Strings.t("Chance they accept, %"), 0.0, 0.0, 0.0)
	chance.set_meta("counter_chance", true)
	var show := func(option: Dictionary) -> void:
		_picked[key] = String(option["id"])
		follows.text = String(fill.call(strip, option))
		AnswerRow.fill_who(who, option.get("bloc_offset", {}))
		var lo := 100.0 * float(option["odds_lo"])
		var hi := 100.0 * float(option["odds_hi"])
		chance.get_meta("chart").setup(lo, (lo + hi) / 2.0, hi, {"track": [0.0, 100.0], "places": 0})
	for option in counters:
		var chip := PanelKit.sized(Button.new())
		chip.text = Strings.t("%d %%") % roundi(100.0 * float(option["counter"]))
		PanelKit.toggle(chip)
		chip.button_group = group
		chip.button_pressed = String(option["id"]) == String(shown["id"])
		chip.set_meta("counter_id", String(option["id"]))
		chip.pressed.connect(func() -> void: show.call(option))
		row.add_child(chip)
	slots.add_child(strip)
	slots.move_child(strip, 1)
	slots.move_child(chance, -1)
	go.pressed.connect(func() -> void: make.call(String(_picked[key])))
	show.call(shown)


## An answer id's words: negotiate_N is "Counter N %".
static func label(id: String) -> String:
	return Strings.t("Counter %d %%") % int(id.trim_prefix("negotiate_"))
