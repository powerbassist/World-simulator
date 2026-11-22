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
## reach either side of today (LEVER_SPAN, the author's d1b3): the TRACK is the line's whole range, so the knob
## reads as the level (d1b3's own reason), a drag or a typed figure past the reach stops at it, and the reach is
## what the caption beside the box says. The income
## tax carries a second lever, its brackets (the brief's call 4: a setting of that row, not a seventeenth tax).

signal moved
## A verb that changes what the page lists (put in force taken back, a tax abolished or kept): the page rebuilds.
## `keyed`: the verb was pressed from the keyboard (its place lands on the rebuilt editor), not by the mouse.
signal structure_changed(keyed: bool)

const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceSectors = preload("res://src/ui/finance_sectors.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const LedgerBox = preload("res://src/ui/ledger_box.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const GK = preload("res://src/sim/goal_read_constants.gd")

## A spending line's step, ceiling and reach either side of its value today, in points of GDP.
const LINE_STEP := 0.1
const LINE_MAX := 30.0
const LINE_SPAN := 5.0

var channel := ""
var key := ""
## The autumn bill is open (FinanceBill.autumn_open, read by the page): an in-force kind may be abolished.
var autumn := false
## The row's own bar (finance_lever.gd), handed in by the page before setup(): the editor's lever when it can be dragged.
var row_lever: HSlider = null
var _state
var _draft
var _price
var _slider: HSlider
var _box: LineEdit
var _effect: Label
var _brackets: HSlider
var _brackets_box: LineEdit
## The editor's verb (Abolish, Keep it, Take it back): focus_lever's landing when there is no slider.
var _last_verb: Button
var _lo := 0.0
var _hi := 0.0
## A spending line's sectors (slice 5), drawn from the draft again whenever the slider moves.
var _tile: FinanceSectors


func setup(state, loader, draft, price, row_channel: String, row_key: String) -> void:
	_state = state
	_draft = draft
	_price = price
	channel = row_channel
	key = row_key
	var ns = state.player()
	add_theme_constant_override("separation", 6)
	var reach := span(ns, _draft, channel, key)
	var step := float(reach["step"])
	var decimals := int(reach["decimals"])
	_lo = float(reach["lo"])
	_hi = float(reach["hi"])
	var unit := FinanceRows.unit_text(String(ns.tax_library[key]["unit"])) if channel == FinanceDraft.TAX else Strings.t(" % of GDP")
	var in_force: bool = channel != FinanceDraft.TAX or ns.tax_rates_pct.has(key)
	if channel == FinanceDraft.TAX and in_force and autumn and _draft.is_abolished(key):
		# An abolished kind has no rate to set: the editor says so and offers the way back.
		PanelKit.plain_line(self, Strings.t("Abolished in the bill: it leaves the books."), PanelKit.Tone.BAD)
		_verb(Strings.t("Keep it"), "KeepTax", func() -> void: _draft.toggle_abolish(key))  # i18n: ok a node name
		return
	var now := PanelKit.plain_line(self, Strings.t("Now %s") % (LedgerBox.text(_draft.live(channel, key), decimals) + unit) if in_force else Strings.t("Not in force yet"), PanelKit.Tone.DIM)
	now.name = "Now"  # i18n: ok a node name, found by tests
	if channel == FinanceDraft.TAX:
		# What the rate is a rate OF (the data's own words): the hover on the figure, not a sentence on the page.
		now.tooltip_text = Strings.row("taxes", key, "rate_meaning", String(ns.tax_library[key].get("rate_meaning", "")))
		now.mouse_filter = Control.MOUSE_FILTER_PASS
	var made := _lever(self, step, float(reach["track_lo"]), float(reach["track_hi"]), decimals, "Box", _lo, _hi)  # i18n: ok a node name, found by tests
	_slider = made[0]
	_box = made[1]
	if channel == FinanceDraft.TAX and key == _income_key(ns):
		PanelKit.plain_line(self, Strings.t("Income brackets"), PanelKit.Tone.DIM)
		var brackets := _lever(self, 0.01, 0.0, float(TaxK.PROGRESSIVITY_MAX), 2, "BracketsBox", 0.0, float(TaxK.PROGRESSIVITY_MAX), FinanceDraft.BRACKETS, "")  # i18n: ok a node name, found by tests
		_brackets = brackets[0]
		_brackets_box = brackets[1]
	_effect = PanelKit.plain_line(self, "", PanelKit.Tone.PLAIN)
	_effect.name = "Effect"  # i18n: ok a node name, found by tests
	for line in _who_lines(state, loader):
		PanelKit.plain_line(self, line, PanelKit.Tone.DIM).autowrap_mode = TextServer.AUTOWRAP_WORD
	if channel == FinanceDraft.TAX and not in_force and _draft.is_created(key):
		_verb(Strings.t("Take it back"), "TakeBack", func() -> void: _draft.clear_create(key))  # i18n: ok a node name
	elif channel == FinanceDraft.TAX and autumn and in_force and ns.tax_library[key].has("rate_range_pct"):
		_verb(Strings.t("Abolish this tax"), "AbolishTax", func() -> void: _draft.toggle_abolish(key))  # i18n: ok a node name
	if channel == FinanceDraft.SPENDING and FinanceSectors.has_sectors(loader, key):
		_tile = FinanceSectors.new()
		add_child(_tile)
		_tile.setup(state, loader, draft, key, func(target: float) -> void: _write(channel, key, target), _hi, LINE_STEP)
		_tile.changed.connect(moved.emit)
	if channel == FinanceDraft.TAX:
		var yields: Dictionary = FinanceRead.step_yields(ns).get(key, {})
		if yields.has("up_bn"):
			PanelKit.plain_line(self, Strings.t("One step (%s): %s a year.") % [LedgerBox.text(float(yields["step"]), decimals) + unit.strip_edges(), EffectsStrip.money_text(float(yields["up_bn"]))], PanelKit.Tone.DIM)
	_sync()


## A verb of the autumn bill under the row's figures: it changes the draft, and the page rebuilds.
func _verb(text: String, node_name: String, change: Callable) -> void:
	var button := PanelKit.sized(Button.new())
	button.name = node_name
	button.text = text
	button.flat = true
	# gui_input comes before the button's own handling: the press that fires is the last event it saw.
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton:
			button.set_meta(&"keyed", not event is InputEventMouseButton))
	button.pressed.connect(func() -> void:
		change.call()
		structure_changed.emit(bool(button.get_meta(&"keyed", false))))
	_last_verb = button
	add_child(button)


## One lever on a line: the slider, then the box that takes the exact figure.
func _lever(parent: Control, step: float, lo: float, hi: float, decimals: int, box_name: String, reach_lo: float, reach_hi: float,
		lever_channel := "", lever_key := "") -> Array:
	if lever_channel == "":
		lever_channel = channel
		lever_key = key
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	# G3 S4: the row's own bar is the lever (finance_lever.gd); the editor keeps the exact box. The row writes the draft
	# on a drag, so here the bar only brings the box and the effect line along.
	if lever_channel == channel and lever_key == key and row_lever != null and row_lever.can_drag():
		row_lever.value_changed.connect(func(_value: float) -> void:
			_sync()
			if _tile != null:
				_tile.refresh())
		var held := LedgerBox.attach(line, reach_lo, reach_hi, func(value: float) -> void: _write(lever_channel, lever_key, value))
		held.name = box_name
		_caption(line, reach_lo, reach_hi, decimals)
		parent.add_child(line)
		return [row_lever, held]
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
	var box := LedgerBox.attach(line, reach_lo, reach_hi, func(value: float) -> void: _write(lever_channel, lever_key, value))
	box.name = box_name
	_caption(line, reach_lo, reach_hi, decimals)
	parent.add_child(line)
	return [slider, box]


func _caption(line: Control, reach_lo: float, reach_hi: float, decimals: int) -> void:
	var caption := Label.new()
	caption.text = Strings.t("%s to %s") % [Num.f(reach_lo, decimals), Num.f(reach_hi, decimals)]
	caption.theme_type_variation = UiTheme.CAPTION
	line.add_child(caption)


## A row's reach: where a write is clamped (lo, hi), the track a lever spans (track_lo, track_hi), its step and decimals.
## A tax moves inside its range; a spending line LINE_SPAN either side of today, on a 0 to LINE_MAX track. The row's
## bar (finance_rows.gd) and this editor read the same reach.
static func span(ns, draft, row_channel: String, row_key: String) -> Dictionary:
	if row_channel == FinanceDraft.TAX:
		var range_pct: Array = ns.tax_library[row_key].get("rate_range_pct", [0.0, 0.0])
		return {"lo": float(range_pct[0]), "hi": float(range_pct[1]), "track_lo": float(range_pct[0]), "track_hi": float(range_pct[1]),
			"step": TaxLibrary.step_pct(ns, row_key), "decimals": TaxLibrary.step_decimals(ns, row_key)}
	var at: float = draft.live(row_channel, row_key)
	return {"lo": maxf(0.0, at - LINE_SPAN), "hi": minf(LINE_MAX, at + LINE_SPAN), "track_lo": 0.0, "track_hi": LINE_MAX, "step": LINE_STEP, "decimals": 1}


## The player's input: into the draft, never from a refresh.
func _write(lever_channel: String, lever_key: String, value: float) -> void:
	if lever_channel == FinanceDraft.BRACKETS:
		_draft.set_brackets(value)
	else:
		_draft.set_value(lever_channel, lever_key, clampf(value, _lo, _hi))
	_sync()
	if _tile != null:
		_tile.refresh()
	moved.emit()


## Slider, box and effect line from the draft (a refresh from outside lands here too, and writes nothing).
func _sync() -> void:
	if _slider == null:
		return
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
	var born: bool = channel == FinanceDraft.TAX and _draft.is_created(key)
	if own.is_empty() and not born:
		_effect.text = ""
		_effect.theme_type_variation = ""
		return
	# A kind put in force is priced as a bill of its one row: Budget.preview refuses a rate on a kind not in force.
	var gain: float = _price.bill_balance_bn({FinanceBill.CREATE: {key: value}}) if born else _price.balance_bn(own)
	_effect.text = Strings.t("Balance: %s a year.") % EffectsStrip.money_text(gain)
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


## Who the row is for: a tax's payers (the data); a spending line's blocs (what Opinion weighs for its issue) and
## what one step of it does to each (the net, in words: at a game's start a rise angers nearly every bloc, because
## the deficit it adds is counted). One FinanceRead.line_blocs call when the row opens (~30 ms).
func _who_lines(state, loader) -> Array:
	if channel == FinanceDraft.TAX:
		var paid: Array = state.player().tax_library[key].get("who_pays", [])
		return [Strings.t("Paid by: %s") % ", ".join(paid.map(func(b) -> String: return Labels.bloc(String(b))))]
	var read: Dictionary = FinanceRead.line_blocs(state, loader, key)
	var out := []
	var weights: Array = read["weights"]
	if not weights.is_empty():
		out.append(Strings.t("For: %s") % ", ".join(weights.map(func(pair: Array) -> String: return Labels.bloc(String(pair[0])))))
	var offsets := {}
	for pair in read["gains"] + read["loses"]:
		offsets[pair[0]] = pair[1]
	var cost: float = GK.SPENDING_STEP * float(state.player().gdp_eur_bn) / 100.0
	out.append(Strings.t("One step (%s pt of GDP): %s a year. %s") % [Num.f(GK.SPENDING_STEP, 1), EffectsStrip.money_text(-cost), EffectsStrip.who_text(offsets)])
	return out


## The slider the player's cursor goes to (the goal panel's Go lands here).
func focus_lever() -> void:
	if _slider != null:
		_slider.grab_focus()
		return
	# An abolished kind has no slider: its way back takes the keyboard.
	if _last_verb != null:
		_last_verb.grab_focus()
