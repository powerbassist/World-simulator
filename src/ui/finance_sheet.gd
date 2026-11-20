extends PanelContainer

## The finance bill's sheet before it is tabled -- V5.3 screen 4, direction A slice 3 (the picture's -sheet). The
## act: only the rows the player CHANGED (the one draft, finance_draft.gd; the full list stays in the books), what
## they do to the books and who they please or anger, how the Assembly would divide on them now, the forced
## passage where the political system has one, and the verbs: Table, and Withdraw while a bill is at vote.
##
## It computes nothing of its own: the totals and each row's balance are FinancePrice's (the footer's figures),
## the division is FinanceRead.draft's, the censure is Government.resolve_censure's (the Government window's
## own tally), and whether a passage can be forced is the very rule tabling meets (FinanceBill.refusal with the
## force flag), never a nation id. A row's chips are neutral reads: a spending line's blocs are the ones that
## weigh its issue (FinanceRead.line_blocs, once per line and day), a tax's are its payers (the data); a rise
## pleases the line's blocs and angers the payers, a cut the reverse. The brackets name no bloc.
##
## It is read-only over the game. A press is a signal: the page owns the commands.

signal table_pressed(force: bool)
signal withdraw_pressed
signal close_pressed

const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceFoot = preload("res://src/ui/finance_foot.gd")
const Government = preload("res://src/sim/government.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")

## The chips a row shows before "+N": a row's line is for few blocs, a tax's payers are a handful.
const CHIPS_SHOWN := 3
const WIDTH := 540.0

var _state
var _loader
var _draft
var _price
var _body: VBoxContainer
var _force: CheckBox
var _stamp := ""
var _tabled := false
var _can_force := false
var _read := {}
var _decision: VBoxContainer
var _verb_box: VBoxContainer
## {line key: [bloc, ...]} the blocs that weigh a spending line, read once per day.
var _weights := {}
var _weights_day := ""


func _ready() -> void:
	name = "Sheet"  # i18n: ok a node name, found by tests
	custom_minimum_size.x = WIDTH
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_FILL
	visible = false
	var margin := PanelKit.padded(self, 14, 10)
	_body = margin


func setup(state, loader, draft, price) -> void:
	_state = state
	_loader = loader
	_draft = draft
	_price = price
	_stamp = ""


## Written from the draft; called on every paint while open, and a repaint is made only when something it
## reads changed (the draft, the slot, the day, the text size, the language). The force box is NOT in that
## stamp: ticking it redraws the division and the verbs under it and leaves the box (and the keyboard's focus
## on it) where it is.
func refresh() -> void:
	if not visible or _state == null:
		return
	# The whole bill, births and abolitions with the priced rows: hashing pending() alone left an autumn row
	# drafted with the sheet open off it, and Table tabled what the player had not been shown.
	var stamp := "%s|%d|%d|%d|%s|%s|%s|%d" % [var_to_str(_draft.bill()), _state.year, _state.month, _state.day,
		str(_state.player().tabled_bill), UiTheme.text_scale(), Strings.language(), _draft.moves().size()]
	if stamp == _stamp:
		return
	_stamp = stamp
	# A rebuild frees the control the keyboard is on: it comes back to the act (or the way out) rather than vanish.
	var held := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var had_focus: bool = held != null and is_ancestor_of(held)
	_build()
	if had_focus:
		focus_primary()


func _build() -> void:
	var kept := _force != null and is_instance_valid(_force) and _force.button_pressed
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_force = null
	var ns = _state.player()
	var bill: Dictionary = _draft.bill()
	_tabled = FinanceBillLaw.tabled(ns) != null
	_read = FinanceRead.draft(_state, _loader, bill)
	_head(ns, _tabled)
	_totals()
	_rows()
	_decision = VBoxContainer.new()
	_body.add_child(_decision)
	# The very rule tabling meets: a refusal for another reason says so, and a system with no forced passage says "forced".
	_can_force = String(_read["refusal"]) == "" and not FinanceBill.refusal(_state, _loader, bill, true).has("forced")
	if _can_force:
		_force_box(kept)
	_verb_box = VBoxContainer.new()
	_body.add_child(_verb_box)
	_fill(kept and _can_force)


## The part the force box changes: the division (or the censure) and the verbs.
func _fill(forced: bool) -> void:
	for box in [_decision, _verb_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var refusal := String(_read["refusal"])
	if refusal != "":
		PanelKit.plain_line(_decision, FinanceFoot.reason(refusal), PanelKit.Tone.BAD)
	else:
		_assembly(_state.player(), _read["vote"], forced)
	_verbs(_tabled, refusal, forced)


func _head(ns, tabled: bool) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var title := PanelKit.plain_line(line, Strings.t("Finance bill · %s") % DateText.month_long(int(_state.month)), PanelKit.Tone.PLAIN)
	title.theme_type_variation = UiTheme.MICRO
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := PanelKit.sized(Button.new())
	close.name = "SheetClose"  # i18n: ok a node name, found by tests
	close.text = Strings.t("Close")
	close.flat = true
	close.pressed.connect(close_pressed.emit)
	line.add_child(close)
	_body.add_child(line)
	var day := _vote_day()
	var month := int(_state.month)
	if tabled:
		day = int(ns.tabled_bill.get("vote_day", day))
		month = int(ns.tabled_bill.get("vote_month", month))
	var tag := PanelKit.plain_line(_body, Strings.t("The Assembly divides on %s") % DateText.day_month(day, month), PanelKit.Tone.DIM)
	tag.theme_type_variation = UiTheme.WARN_TEXT
	# Table books the drafted share moves at once, whatever the vote (slice 5): the sheet says so, as the footer does.
	var moves: int = _draft.moves().size()
	if moves > 0:
		PanelKit.plain_line(_body, Strings.tn("%d share move applies now; the rest is voted on %s.", "%d share moves apply now; the rest is voted on %s.", moves) % [
			moves, DateText.day_month(day, month)], PanelKit.Tone.DIM).name = "SheetMoves"  # i18n: ok a node name


func _vote_day() -> int:
	return DateText.days_in(int(_state.month), int(_state.year))


## The four figures: what the bill does to each side a year, and the deficit before (the books today, no bill) and
## after (the whole bill passed). EVERY figure on the sheet describes the bill the vote will decide: the rows already
## at vote with the new ones merged (an amendment), the same as the seat forecast beside it; the changed-rows list
## alone is the new rows. A refused draft has no merged text, so its figures are the new rows'. A spending rise is
## bad news and a revenue rise good, as the footer and the editors tone them.
func _totals() -> void:
	var whole: Dictionary = _price.whole(_loader, _draft, String(_read["refusal"]) != "")
	var deficit_now := float(whole["deficit_now_bn"])
	var deficit_after := float(whole["deficit_after_bn"])
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 22)
	_body.add_child(line)
	PanelKit.figure(line, EffectsStrip.money_text(float(whole["spending_bn"])), Strings.t("Spending"), EffectsStrip.money_tone(-float(whole["spending_bn"])))
	PanelKit.figure(line, EffectsStrip.money_text(float(whole["revenue_bn"])), Strings.t("Revenue"), EffectsStrip.money_tone(float(whole["revenue_bn"])))
	PanelKit.figure(line, "%s → %s" % [Num.f(deficit_now, 0), Num.f(deficit_after, 0)], Strings.t("Deficit, bn"),
		EffectsStrip.money_tone(deficit_now - deficit_after))
	PanelKit.figure(line, Num.f(float(whole["deficit_after_pct"]), 2) + " %", Strings.t("Deficit, % of GDP"))


func _rows() -> void:
	var rows: Array = _draft.rows()
	PanelKit.heading(_body, Strings.tn("%d changed row", "%d changed rows", rows.size()) % rows.size())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for row in rows:
		_row(list, row)


func _row(list: Control, row: Dictionary) -> void:
	var ns = _state.player()
	var channel := String(row["channel"])
	var key := String(row["key"])
	var box := VBoxContainer.new()
	box.name = "SheetRow_" + FinanceRows.row_id(channel, key).replace(":", "_")  # i18n: ok a node name, found by tests
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	box.add_child(line)
	# The autumn bill's two rows (a kind put in force, a kind abolished) name no one for and against.
	var autumn_row: bool = channel == FinanceDraft.ABOLISH or bool(row.get("birth", false))
	var name := PanelKit.plain_line(line, FinanceRows.change_label(ns, row), PanelKit.Tone.PLAIN)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The figures are one line each: a wrapped "11 → 12 % of GDP" in a tight row is a column of single words.
	PanelKit.plain_line(line, FinanceRows.change_figures(ns, row), PanelKit.Tone.DIM).autowrap_mode = TextServer.AUTOWRAP_OFF
	var gain: float = _price.row_balance_bn(row)
	var effect := PanelKit.plain_line(line, EffectsStrip.money_text(gain), PanelKit.Tone.PLAIN)
	effect.autowrap_mode = TextServer.AUTOWRAP_OFF
	effect.theme_type_variation = EffectsStrip.cell_variation(EffectsStrip.money_tone(gain))
	if not autumn_row:
		_chips(box, channel, key, float(row["draft"]) > float(row["live"]))
	list.add_child(box)


## Who a rise or a cut pleases and angers, one neutral word each with an arrow and a tone, never colour alone.
func _chips(box: Control, channel: String, key: String, rise: bool) -> void:
	var pleased: Array = []
	var angered: Array = []
	if channel == FinanceDraft.SPENDING:
		(pleased if rise else angered).append_array(_line_blocs(key))
	elif channel == FinanceDraft.TAX:
		(angered if rise else pleased).append_array(_state.player().tax_library[key].get("who_pays", []))
	if pleased.is_empty() and angered.is_empty():
		return
	var flow := PanelKit.buttons(box)
	var shown := 0
	for entry in [[pleased, "▲ ", Strings.t("%s for"), UiTheme.GOOD_SMALL], [angered, "▼ ", Strings.t("%s against"), UiTheme.BAD_SMALL]]:
		for bloc in entry[0]:
			if shown >= CHIPS_SHOWN:
				break
			var chip := Label.new()
			chip.text = String(entry[1]) + String(entry[2]) % Labels.bloc(String(bloc))
			chip.theme_type_variation = String(entry[3])
			flow.add_child(chip)
			shown += 1
	var more := pleased.size() + angered.size() - shown
	if more > 0:
		var rest := Label.new()
		rest.text = "+%d" % more
		rest.theme_type_variation = UiTheme.CAPTION
		flow.add_child(rest)


## The blocs that weigh a spending line, most first; one read per line and day (it prices a copy of the state).
func _line_blocs(key: String) -> Array:
	var day := "%d|%d|%d" % [_state.year, _state.month, _state.day]
	if day != _weights_day:
		_weights_day = day
		_weights = {}
	if not _weights.has(key):
		_weights[key] = (FinanceRead.line_blocs(_state, _loader, key)["weights"] as Array).map(func(pair: Array) -> String: return String(pair[0]))
	return _weights[key]


func _assembly(ns, vote: Dictionary, forced: bool) -> void:
	if forced:
		var censure: Dictionary = Government.resolve_censure(ns, _loader.parties.get(ns.id, []), true)
		PanelKit.plain_line(_decision, Strings.t("Adopted without a vote. A censure motion follows: %d seats would move against the government, %d are needed.") % [
			int(censure["for_seats"]), Government.censure_seats(ns)], PanelKit.Tone.PLAIN)
		PanelKit.plain_line(_decision, Strings.t("It survives: the bill is adopted.") if not bool(censure["carried"]) \
			else Strings.t("It falls: the government goes and the bill with it."), PanelKit.Tone.GOOD if not bool(censure["carried"]) else PanelKit.Tone.BAD)
		PanelKit.plain_line(_decision, Strings.t("Forcing costs standing with every bloc and with your own majority."), PanelKit.Tone.DIM)
		return
	ChartKit.stack(_decision, Strings.t("Assembly, if it divided now"), [
		{"label": Strings.t("For"), "value": float(vote["yes_seats"])},
		{"label": Strings.t("Against"), "value": float(vote["no_seats"])},
		{"label": Strings.t("Undecided"), "value": float(vote["abstain_seats"])},
	], {"places": 0, "colors": [UiTheme.GOOD, UiTheme.BAD, FinanceRows.MUTED], "marker": 0.5})
	var rebels := 0
	for party in vote.get("party_rebels", {}):
		rebels += int(vote["party_rebels"][party])
	if rebels > 0:
		PanelKit.plain_line(_decision, Strings.t("%d of your seats rebel.") % rebels, PanelKit.Tone.DIM)
	PanelKit.plain_line(_decision, Strings.t("It carries.") if bool(vote["passed"]) else Strings.t("It falls."),
		PanelKit.Tone.GOOD if bool(vote["passed"]) else PanelKit.Tone.BAD)


func _force_box(ticked: bool) -> void:
	_force = CheckBox.new()
	_force.name = "Force"  # i18n: ok a node name, found by tests
	_force.text = Strings.t("Force it through (49.3)")
	_force.theme_type_variation = UiTheme.OPTION_CHECK
	_force.set_pressed_no_signal(ticked)
	_force.toggled.connect(_fill)
	_body.add_child(_force)


func _verbs(tabled: bool, refusal: String, forced: bool) -> void:
	var row := PanelKit.buttons(_verb_box)
	var table := PanelKit.sized(Button.new())
	table.name = "SheetTable"  # i18n: ok a node name, found by tests
	table.text = Strings.t("Table and force it") if forced else (Strings.t("Add to the bill") if tabled else Strings.t("Table the bill"))
	table.disabled = refusal != ""
	table.pressed.connect(func() -> void: table_pressed.emit(forced))
	row.add_child(table)
	if tabled:
		var withdraw := PanelKit.sized(Button.new())
		withdraw.name = "SheetWithdraw"  # i18n: ok a node name, found by tests
		withdraw.text = Strings.t("Withdraw the bill")
		withdraw.flat = true
		withdraw.pressed.connect(withdraw_pressed.emit)
		row.add_child(withdraw)


## The keyboard lands on the act when the sheet opens (the player came from the footer's button, which the sheet covers).
func focus_primary() -> void:
	var table := find_child("SheetTable", true, false) as Button
	if table != null and not table.disabled:
		table.grab_focus()
	else:
		(find_child("SheetClose", true, false) as Button).grab_focus()  # a refused draft: the way out
