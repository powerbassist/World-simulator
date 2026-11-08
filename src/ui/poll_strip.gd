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
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")

const TIER_NAME := {
	"quick": "Quick",  # i18n: msgid
	"standard": "Standard",  # i18n: msgid
	"deep": "Deep",  # i18n: msgid
}
const CHIP_META := "poll_tier"
const STRIP_META := "poll_strip"
const GO_META := "poll_go"
## Points either side of an even split inside which a bloc reads as unsure. A STAND-IN.
const WORD_BAND := 5.0

## The tier picked on each measure, so a rebuild keeps what the player is weighing. A display
## pick only, as a counter's is: a stale one falls back to the first tier.
static var _picked := {}


## The whole of it, in `box`. `commission` takes the tier and makes the purchase: the host owns
## the press, its baseline and its redraw. A measure the country cannot read yet offers no poll
## (MeasurePolls.position_of: a process verb with no position in content).
static func build(box: Control, state, loader, key: String, commission: Callable) -> void:
	var ns = state.player()
	_results(box, state, loader, key)
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
	go.pressed.connect(func() -> void: commission.call(String(_picked[key])))
	show.call(shown)


## Price, margin and wait, and the Go down on a tier already bought: fixed, never a reroll.
static func _fill(strip: EffectsStrip, go: Button, ns, key: String, tier: String) -> void:
	var terms: Dictionary = K.TIERS[tier]
	var cost := -float(terms["cost_eur_bn"])
	strip.show_lines(Strings.t("Treasury"), EffectsStrip.sum_text(cost), cost,
		Strings.t("Support per bloc, within %s points.") % Num.f(float(terms["margin"]), 1),
		Strings.t("Arrives in %d weeks.") % int(terms["weeks"]))
	go.disabled = MeasurePolls.bought(ns, key).has(tier)


## The narrowest poll printed as a table, and a line for each still out.
static func _results(box: Control, state, loader, key: String) -> void:
	var ns = state.player()
	var best := narrowest(ns, key)
	var polls := MeasurePolls.bought(ns, key)
	if best.is_empty():
		_free_read(box, state, loader, key)
	if polls.is_empty():
		PanelKit.line(box, Strings.t("No poll on this yet."), PanelKit.Tone.DIM)
	elif not best.is_empty():
		var rows: Array = [["", Strings.t("Support")]]
		for bloc in OpinionK.BLOC_KEYS:
			if best["ranges"].has(bloc):
				rows.append([Labels.bloc(String(bloc)), range_text(best["ranges"][bloc])])
		PanelKit.ledger(box, rows)
		PanelKit.line(box, Strings.t("As of %s, within %s points.") % [arrived_text(best["row"]), Num.f(float(K.TIERS[best["tier"]]["margin"]), 1)], PanelKit.Tone.DIM)
	for tier in polls:
		if not (polls[tier] as Dictionary).has("ranges"):
			PanelKit.line(box, Strings.t("%s poll: arrives %s.") % [Strings.t(String(TIER_NAME[tier])), arrived_text(polls[tier])], PanelKit.Tone.PLAIN)  # i18n: row-ok a tier id, its name the msgid


## The free read (the parent's ruling on #304): a word per bloc, the figure being what a poll
## sells. The word is taken through the ordinary poll's noise, so it is no leak of the truth.
static func _free_read(box: Control, state, loader, key: String) -> void:
	var words := free_words(state, loader, key)
	if words.is_empty():
		return
	var rows: Array = [["", Strings.t("The country")]]
	for bloc in OpinionK.BLOC_KEYS:
		rows.append([Labels.bloc(String(bloc)), String(words[bloc])])
	PanelKit.ledger(box, rows)


## {bloc: For / Against / Unsure}, {} for a measure the country cannot read yet.
static func free_words(state, loader, key: String) -> Dictionary:
	var support := MeasurePolls.support(state.player(), loader, key)
	var id := PollNoise.poll_id(int(state.year), int(state.month))
	var out := {}
	for bloc in support:
		out[bloc] = lean_word(PollNoise.displayed(id, "%s|%s" % [key, bloc], float(support[bloc])))
	return out


static func lean_word(shown: float) -> String:
	if shown >= 50.0 + WORD_BAND:
		return Strings.t("For")
	if shown <= 50.0 - WORD_BAND:
		return Strings.t("Against")
	return Strings.t("Unsure")


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
	# With its year: a read is fixed for good, and can be years old.
	return DateText.day_month_year(int(on["day"]), int(on["month"]), int(on["year"]))


## "Workers 41.2-47.4, Urban 38.0-44.0, ...": a poll's blocs on one line, for a card or a strip.
static func support_line(ranges: Dictionary) -> String:
	var parts := PackedStringArray()
	# In the blocs' own order: a load brings a row's keys back sorted (QA's RECORD on #304).
	for bloc in OpinionK.BLOC_KEYS:
		if ranges.has(bloc):
			parts.append("%s %s" % [Labels.bloc(String(bloc)), range_text(ranges[bloc])])
	return ", ".join(parts)
