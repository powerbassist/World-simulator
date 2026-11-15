extends VBoxContainer

## The row editor of the Finances page -- V5.3 screen 4, direction A slice 2: what one row of the books becomes
## when the player opens it. A slider and a box that takes the exact figure (LedgerBox), its unit, the money the
## move books a year (the strip's own figure, signed and toned), who it is for, and what one step would do. It
## replaces the Budget tab's lever and the Tax Code tab's, and it is the same component for a spending line and
## a tax kind.
##
## It writes the page's ONE draft (finance_draft.gd) on the player's input and nowhere else: opening a row, a
## refresh or a re-sync never drafts it, so an off-grid rate (0.6545) stays in the register. The slider's grid
## is the sim's (TaxLibrary.step_pct); a spending line keeps the Budget's tenth of a point and its five-point
## reach either side of today (LEVER_SPAN, the author's d1b3), which the box is held to as well. The income
## tax carries a second lever, its brackets (the brief's call 4: a setting of that row, not a seventeenth tax).

signal moved

const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const LedgerBox = preload("res://src/ui/ledger_box.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")

## A spending line's step, ceiling and reach either side of its value today, in points of GDP.
const LINE_STEP := 0.1
const LINE_MAX := 30.0
const LINE_SPAN := 5.0

var channel := ""
var key := ""
var _state
var _draft
var _price
var _slider: HSlider
var _box: LineEdit
var _effect: Label
var _brackets: HSlider
var _brackets_box: LineEdit
var _lo := 0.0
var _hi := 0.0


func setup(state, loader, draft, price, row_channel: String, row_key: String) -> void:
	_state = state
	_draft = draft
	_price = price
	channel = row_channel
	key = row_key
	var ns = state.player()
	add_theme_constant_override("separation", 6)
	var step := LINE_STEP
	var decimals := 1
	if channel == FinanceDraft.TAX:
		var span: Array = ns.tax_library[key]["rate_range_pct"]
		_lo = float(span[0])
		_hi = float(span[1])
		step = TaxLibrary.step_pct(ns, key)
		decimals = TaxLibrary.step_decimals(ns, key)
	else:
		var at: float = _draft.live(channel, key)
		_lo = maxf(0.0, at - LINE_SPAN)
		_hi = minf(LINE_MAX, at + LINE_SPAN)
	var unit := FinanceRows.unit_text(String(ns.tax_library[key]["unit"])) if channel == FinanceDraft.TAX else Strings.t(" % of GDP")
	var now := PanelKit.plain_line(self, Strings.t("Now %s") % (LedgerBox.text(_draft.live(channel, key), decimals) + unit), PanelKit.Tone.DIM)
	now.name = "Now"  # i18n: ok a node name, found by tests
	var made := _lever(self, step, _lo, _hi, decimals, unit, channel, key, "Box")  # i18n: ok a node name, found by tests
	_slider = made[0]
	_box = made[1]
	if channel == FinanceDraft.TAX and key == _income_key(ns):
		var brackets := _lever(self, 0.01, 0.0, float(TaxK.PROGRESSIVITY_MAX), 2, "", FinanceDraft.BRACKETS, "", "BracketsBox")  # i18n: ok a node name, found by tests
		PanelKit.plain_line(self, Strings.t("Income brackets: how steeply the rate climbs with income."), PanelKit.Tone.DIM)
		_brackets = brackets[0]
		_brackets_box = brackets[1]
	_effect = PanelKit.plain_line(self, "", PanelKit.Tone.PLAIN)
	_effect.name = "Effect"  # i18n: ok a node name, found by tests
	var who := PanelKit.plain_line(self, _who_text(state, loader), PanelKit.Tone.DIM)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD
	if channel == FinanceDraft.TAX:
		var yields: Dictionary = FinanceRead.step_yields(ns).get(key, {})
		if yields.has("up_bn"):
			PanelKit.plain_line(self, Strings.t("One step (%s): %s a year.") % [LedgerBox.text(float(yields["step"]), decimals) + unit.strip_edges(), EffectsStrip.money_text(float(yields["up_bn"]))], PanelKit.Tone.DIM)
	_sync()


## One lever on a line: the slider, then the box that takes the exact figure.
func _lever(parent: Control, step: float, lo: float, hi: float, decimals: int, unit: String, lever_channel: String, lever_key: String, box_name: String) -> Array:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi if hi > lo else lo + step
	slider.step = step
	slider.custom_minimum_size.x = 150
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.set_block_signals(true)
	slider.value = _draft.value(lever_channel, lever_key)
	slider.set_block_signals(false)
	slider.value_changed.connect(func(value: float) -> void: _write(lever_channel, lever_key, value))
	line.add_child(slider)
	var box := LedgerBox.attach(line, lo, hi, func(value: float) -> void: _write(lever_channel, lever_key, value))
	box.name = box_name
	var caption := Label.new()
	caption.text = Strings.t("%s to %s") % [Num.f(lo, decimals), Num.f(hi, decimals)]
	caption.theme_type_variation = UiTheme.CAPTION
	line.add_child(caption)
	parent.add_child(line)
	return [slider, box]


## The player's input: into the draft, never from a refresh.
func _write(lever_channel: String, lever_key: String, value: float) -> void:
	if lever_channel == FinanceDraft.BRACKETS:
		_draft.set_brackets(value)
	else:
		_draft.set_value(lever_channel, lever_key, clampf(value, _lo, _hi))
	_sync()
	moved.emit()


## Slider, box and effect line from the draft (a refresh from outside lands here too, and writes nothing).
func _sync() -> void:
	var ns = _state.player()
	var places := TaxLibrary.step_decimals(ns, key) if channel == FinanceDraft.TAX else 1
	var value: float = _draft.value(channel, key)
	_slider.set_block_signals(true)
	_slider.value = value
	_slider.set_block_signals(false)
	LedgerBox.show(_box, LedgerBox.text(value, places))
	if _brackets != null:
		var level: float = _draft.value(FinanceDraft.BRACKETS, "")
		_brackets.set_block_signals(true)
		_brackets.value = level
		_brackets.set_block_signals(false)
		LedgerBox.show(_brackets_box, LedgerBox.text(level, 2))
	var own := _own_pending()
	if own.is_empty():
		_effect.text = ""
		_effect.theme_type_variation = ""
		return
	var gain: float = _price.balance_bn(own)
	_effect.text = Strings.t("Books %s a year.") % EffectsStrip.money_text(gain)
	_effect.theme_type_variation = EffectsStrip.cell_variation(EffectsStrip.money_tone(gain))


## The pending of this editor's own rows alone (the row, and the brackets for the income tax).
func _own_pending() -> Dictionary:
	var all: Dictionary = _draft.pending()
	var own := {}
	if all.has(channel) and (all[channel] as Dictionary).has(key):
		own[channel] = {key: all[channel][key]}
	if _brackets != null and all.has(FinanceDraft.BRACKETS):
		own[FinanceDraft.BRACKETS] = all[FinanceDraft.BRACKETS]
	return own


func _income_key(ns) -> String:
	# The brackets shape the income tax's base: the kind whose library row says so.
	return "income" if ns.tax_library.has("income") else ""


## Who the row is for: a tax's payers (the data), a spending line's blocs (what Opinion weighs for its issue,
## read once when the row opens: ~30 ms).
func _who_text(state, loader) -> String:
	if channel == FinanceDraft.TAX:
		var paid: Array = state.player().tax_library[key].get("who_pays", [])
		return Strings.t("Paid by: %s") % ", ".join(paid.map(func(b) -> String: return Labels.bloc(String(b))))
	var weights: Array = FinanceRead.line_blocs(state, loader, key)["weights"]
	if weights.is_empty():
		return ""
	return Strings.t("For: %s") % ", ".join(weights.map(func(pair: Array) -> String: return Labels.bloc(String(pair[0]))))


## The slider the player's cursor goes to (the goal panel's Go lands here).
func focus_lever() -> void:
	_slider.grab_focus()
