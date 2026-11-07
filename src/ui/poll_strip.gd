extends RefCounted

## A poll on a measure, what the player reads before buying and after: V5.3 b, docs/design/
## v5.3-ab.md 4.2. A chip per tier and the picked one's strip (the price, the margin, the
## wait), the shape a counter's chips have (counter_chips.gd); then what has been bought: the
## printed range per bloc of the narrowest poll arrived, dated, since a range is fixed and
## stops bracketing once the country moves, and the day each other poll arrives.
##
## Every figure is poll_constants' or the register's. MeasurePolls.support is the truth and is
## never shown. A row of the register is read here, never edited (QA's RECORD on #299).

const MeasurePolls = preload("res://src/sim/measure_polls.gd")
const K = preload("res://src/sim/poll_constants.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Labels = preload("res://src/ui/labels.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

const TIER_NAME := {
	"quick": "Quick",  # i18n: msgid
	"standard": "Standard",  # i18n: msgid
	"deep": "Deep",  # i18n: msgid
}
const CHIP_META := "poll_tier"
const STRIP_META := "poll_strip"
const GO_META := "poll_go"

## The tier picked on each measure, so a rebuild keeps what the player is weighing. A display
## pick only, as a counter's is: a stale one falls back to the first tier.
static var _picked := {}


## The whole of it, in `box`. `bought` is called after a commission lands. A measure the
## country cannot read yet offers no poll (MeasurePolls.position_of: a process verb with no
## position in content).
static func build(box: Control, state, loader, key: String, bought: Callable) -> void:
	var ns = state.player()
	_results(box, ns, key)
	if MeasurePolls.position_of(ns, loader, key).is_empty():
		return
	var row := PanelKit.buttons(box)
	var strip := EffectsStrip.new()
	strip.set_meta(STRIP_META, true)
	var go := PanelKit.sized(Button.new())
	go.text = Strings.t("Commission")
	go.set_meta(GO_META, true)
	var group := ButtonGroup.new()
	var shown: String = _picked.get(key, K.TIERS.keys()[0])
	var show := func(tier: String) -> void:
		_picked[key] = tier
		_fill(strip, go, ns, key, tier)
	for tier in K.TIERS:
		var chip := PanelKit.sized(Button.new())
		chip.text = Strings.t(String(TIER_NAME[tier]))  # i18n: row-ok a tier id, its name the msgid
		chip.toggle_mode = true
		chip.button_group = group
		chip.button_pressed = tier == shown
		chip.set_meta(CHIP_META, String(tier))
		chip.pressed.connect(show.bind(String(tier)))
		row.add_child(chip)
	box.add_child(strip)
	box.add_child(go)
	go.pressed.connect(func() -> void:
		if bool(MeasurePolls.commission(state, loader, key, String(_picked[key]))["ok"]):
			bought.call())
	show.call(shown)


## Price, margin and wait, and the Go down on a tier already bought: fixed, never a reroll.
static func _fill(strip: EffectsStrip, go: Button, ns, key: String, tier: String) -> void:
	var terms: Dictionary = K.TIERS[tier]
	var cost := -float(terms["cost_eur_bn"])
	strip.show_lines(Strings.t("Debt, once"), EffectsStrip.sum_text(cost), cost,
		Strings.t("Support per bloc, within %s points.") % Num.f(float(terms["margin"]), 1),
		Strings.t("Arrives in %d weeks.") % int(terms["weeks"]))
	go.disabled = MeasurePolls.bought(ns, key).has(tier)


## The narrowest poll printed as a table, and a line for each still out.
static func _results(box: Control, ns, key: String) -> void:
	var best := narrowest(ns, key)
	if best.is_empty():
		PanelKit.line(box, Strings.t("No poll on this yet."), PanelKit.Tone.DIM)
	else:
		var rows: Array = [["", Strings.t("Support")]]
		for bloc in best["ranges"]:
			rows.append([Labels.bloc(String(bloc)), range_text(best["ranges"][bloc])])
		PanelKit.ledger(box, rows)
		PanelKit.line(box, Strings.t("As of %s, within %s points.") % [arrived_text(best["row"]), Num.f(float(K.TIERS[best["tier"]]["margin"]), 1)], PanelKit.Tone.DIM)
	var polls := MeasurePolls.bought(ns, key)
	for tier in polls:
		if not (polls[tier] as Dictionary).has("ranges"):
			PanelKit.line(box, Strings.t("%s poll: arrives %s.") % [Strings.t(String(TIER_NAME[tier])), arrived_text(polls[tier])], PanelKit.Tone.PLAIN)  # i18n: row-ok a tier id, its name the msgid


## {tier, row, ranges} of the narrowest poll printed on a measure, {} before one arrives.
static func narrowest(ns, key: String) -> Dictionary:
	var out := {}
	var polls := MeasurePolls.bought(ns, key)
	for tier in polls:
		if (polls[tier] as Dictionary).has("ranges") and (out.is_empty() or float(K.TIERS[tier]["margin"]) < float(K.TIERS[out["tier"]]["margin"])):
			out = {"tier": String(tier), "row": polls[tier], "ranges": polls[tier]["ranges"]}
	return out


static func range_text(printed: Array) -> String:
	return "%s-%s" % [Num.f(float(printed[0]), 1), Num.f(float(printed[1]), 1)]


static func arrived_text(row: Dictionary) -> String:
	var on := MeasurePolls.arrives_on(row)
	return DateText.day_month(int(on["day"]), int(on["month"]))


## "Workers 41.2-47.4, Urban 38.0-44.0, ...": a poll's blocs on one line, for a card or a strip.
static func support_line(ranges: Dictionary) -> String:
	var parts := PackedStringArray()
	for bloc in ranges:
		parts.append("%s %s" % [Labels.bloc(String(bloc)), range_text(ranges[bloc])])
	return ", ".join(parts)
