extends PanelContainer

## The finance bill's RAIL -- G3 S4, Finances in C ("the bill is the page", the author's pick). One sheet at the
## workspace's right that stays on every Finances tab (Books, Public works, Register, Building: window_manager's
## aside for the domain), because Register and Building feed the same bill and the player should not have to come
## back to Books to see it. It replaces the tray docked under Books (the rework pass's C), and keeps its rules:
##
## - The bill's head: the month, and the day the Assembly divides, in the attention tone (a date that waits on you).
## - The deficit as a WATERFALL (ChartKit.waterfall): today, each change a signed step, the bill. Each change's money
##   a year is the row's own price (FinancePrice.row_balance_bn); the end is the whole bill's (FinancePrice.whole),
##   so a residual the rows alone do not explain (a kind put in force, an interaction) is its own step, never hidden.
## - The changes, each with who it is for (a line's blocs) or who pays (a tax's), its money and its remove mark.
## - How the Assembly would divide now; ONE loud button ("Table the bill"; "Add to the bill" on an amendment; "Apply
##   the moves" for share moves alone); Discard all and Review the bill are links. A bill already before the Assembly
##   with nothing drafted is said, with Open the bill and its withdrawal.
## - ONE filled button a screen (the parent's ruling, 2026-11-22): the filled button is the screen's next step. A tab
##   that shows its own PRIMARY (Register's "Put it in the finance bill") has it; the rail's verb is then plain.
##
## It reads the state and the one draft; it writes nothing (its verbs are signals the Books page answers). While Books
## is shown the page repaints it on every draft move; on another tab it repaints itself when the day or the bill moves.

signal table_pressed
signal discard_pressed
signal open_pressed
signal review_pressed
signal withdraw_pressed
## A change's remove mark: (channel, key) as FinanceDraft.drop takes them.
signal drop_pressed(channel: String, key: String)

const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const ChartWaterfall = preload("res://src/ui/chart_waterfall.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Num = preload("res://src/ui/num.gd")

## The rail's width at text 100: the waterfall's name column (a change and its figures, "Health, 11.0 → 12.5"), a bar
## that still reads at its shortest step, and its figure; with the sheet's margins.
const WIDTH := 470.0
## A residual under this (bn a year) is rounding, not a step.
const RESIDUAL_BN := 0.05

var _title: Label
var _date: PanelContainer
var _text: Label
var _empty: Label
var _table: Button
var _discard: Button
var _open: Button
var _review: Button
var _withdraw: Button
var _changes: VBoxContainer
var _count: Label
var _groups: VBoxContainer
var _fall: VBoxContainer
var _chart: ChartWaterfall
var _pct: Label
## Each change's money a year, by "id|draft value|live value|day": a drag moves one row, so the others are priced once
## per change of their own (pass 2 T2 on #429), not on every frame of the drag.
var _gains := {}
## The blocs that weigh a spending line, by key, for the day they were read (one FinanceRead.line_blocs a line a day).
var _blocs := {}
var _blocs_day := ""
## The index of the change a remove mark took out, -1 for none: the focus goes to the mark now in its place.
var _dropped_at := -1
var _vote_box: VBoxContainer
var _built_ids := []
var _vote_key := ""
var _state
var _loader
var _draft
var _price
var _stamp := ""


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	custom_minimum_size.x = WIDTH * UiTheme.text_scale()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_date = PanelKit.chip(head, "", UiTheme.CHIP_WARN)
	_date.size_flags_horizontal = Control.SIZE_SHRINK_END
	_date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	PanelKit.plain_line(col, Strings.t("It stays on every Finances tab: Register and Building add to it."), PanelKit.Tone.DIM).autowrap_mode = TextServer.AUTOWRAP_WORD
	_empty = PanelKit.plain_line(col, "", PanelKit.Tone.PLAIN)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	_fall = VBoxContainer.new()
	col.add_child(_fall)
	var box := ChartKit.waterfall(_fall, Strings.t("The deficit, a year, bn"), {"label": "", "value": 0.0}, [], {"label": "", "value": 0.0})
	_chart = box.get_meta("chart")
	_chart.set_meta("rail", "waterfall")
	_pct = PanelKit.plain_line(_fall, "", PanelKit.Tone.DIM)

	_changes = VBoxContainer.new()
	col.add_child(_changes)
	var changes_head := HBoxContainer.new()
	changes_head.add_theme_constant_override("separation", 8)
	_changes.add_child(changes_head)
	_count = Label.new()
	_count.theme_type_variation = UiTheme.MICRO
	changes_head.add_child(_count)
	PanelKit.plain_line(changes_head, Strings.t("× takes one out")).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups = VBoxContainer.new()
	_groups.add_theme_constant_override("separation", 2)
	_changes.add_child(_groups)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_text)
	_vote_box = VBoxContainer.new()
	col.add_child(_vote_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var verbs := PanelKit.buttons(col)
	_table = _button(verbs, "Table", Strings.t("Table the bill"), table_pressed)  # i18n: ok a node name
	_table.theme_type_variation = UiTheme.PRIMARY
	_open = _button(verbs, "OpenBill", Strings.t("Open the bill"), open_pressed)
	_discard = _button(verbs, "Discard", Strings.t("Discard all"), discard_pressed)  # i18n: ok a node name
	_discard.flat = true
	_review = _button(verbs, "Review", Strings.t("Review the bill"), review_pressed)  # i18n: ok a node name
	_review.flat = true  # the sheet is the act's detail; the rail's own verb stays the loud one
	_withdraw = _button(verbs, "Withdraw", Strings.t("Withdraw the bill"), withdraw_pressed)  # i18n: ok a node name
	_withdraw.flat = true


func _button(parent: Control, node_name: String, label: String, signal_out: Signal) -> Button:
	var button := PanelKit.sized(Button.new())
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.name = node_name  # i18n: ok a node name, found by tests
	button.text = label
	button.pressed.connect(signal_out.emit)
	parent.add_child(button)
	return button


## What the rail repaints itself from on a tab that is not Books (where the page repaints it on every move).
func setup(state, loader, draft, price) -> void:
	_state = state
	_loader = loader
	_draft = draft
	_price = price
	_stamp = ""


func mark_dirty() -> void:
	_stamp = ""


func _process(_delta: float) -> void:
	if _state == null or not is_visible_in_tree() or _state.player() == null:
		return
	var ns = _state.player()
	var stamp := "%d|%d|%d|%s|%d|%d" % [_state.year, _state.month, _state.day, str(ns.tabled_bill), _draft.count(), _draft.moves().size()]
	if stamp != _stamp:
		refresh(_state, _loader, _draft, _price)
	_quiet_if_the_page_leads()


## Written from the draft and the books; called on every draft move and every redraw, so it reads only.
func refresh(state, loader, draft, price) -> void:
	var ns = state.player()
	var tabled = FinanceBillLaw.tabled(ns)
	var drafted: bool = not draft.is_empty()
	var moves: int = draft.moves().size()
	_stamp = "%d|%d|%d|%s|%d|%d" % [state.year, state.month, state.day, str(ns.tabled_bill), draft.count(), moves]
	var vote_on := DateText.day_mon(Calendar.days_in_month(int(state.year), int(state.month)), int(state.month))
	_title.text = Strings.t("Finance bill · %s") % DateText.month_long(int(state.month))
	_table.visible = drafted or moves > 0
	_discard.visible = drafted or moves > 0
	_review.visible = drafted
	_open.visible = not drafted and tabled != null
	_withdraw.visible = tabled != null
	_changes.visible = drafted
	_fall.visible = drafted
	_vote_box.visible = false
	_empty.visible = not drafted and moves == 0 and tabled == null
	_date.visible = drafted or tabled != null
	if tabled != null:
		vote_on = DateText.day_mon(int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))
	(_date.get_child(0).get_child(-1) as Label).text = Strings.t("divides %s") % vote_on
	_empty.text = Strings.t("No change yet. Move a line's bar on Books, or put a programme in from Register: the deficit and the vote show here.")
	if not drafted:
		_dropped_at = -1  # the changes went with the last one: a stale index would pull the next draft's focus onto an x
	var before_vote := ""
	if tabled != null:
		before_vote = Strings.t("A finance bill is before the Assembly: it divides on %s.") % vote_on
	if not drafted and moves > 0:
		_table.text = Strings.t("Apply the moves")
		_table.disabled = false
		_text.text = Strings.tn("%d share move takes effect now, with no vote.", "%d share moves take effect now, with no vote.", moves) % moves + \
			("\n" + before_vote if tabled != null else "")
		return
	if not drafted:
		_text.text = before_vote
		return
	var read: Dictionary = FinanceRead.draft(state, loader, draft.bill())
	var refusal := String(read["refusal"])
	# The same pricing as the sheet (FinancePrice.whole): the bill the vote decides. On an amendment the money is the
	# whole bill's, and the sentence says so.
	var whole: Dictionary = price.whole(loader, draft, refusal != "")
	_list(state, ns, draft, price, whole)
	var text := ""
	if tabled != null:
		text = Strings.t("An amendment to the bill before the Assembly: the figures are the whole bill's.")
	var autumn: Array = []
	for kind in draft.births():
		autumn.append(Strings.t("creation of %s") % Strings.row_name("taxes", ns.tax_library[kind]))
	for kind in draft.abolitions():
		autumn.append(Strings.t("abolition of %s") % Strings.row_name("taxes", ns.tax_library[kind]))
	if not autumn.is_empty():
		text += ("\n" if text != "" else "") + Strings.t("The autumn bill: %s.") % ", ".join(autumn)
	_table.text = Strings.t("Add to the bill") if tabled != null else Strings.t("Table the bill")
	_table.disabled = refusal != ""
	if moves > 0:
		text += ("\n" if text != "" else "") + Strings.tn("%d share move applies now; the rest is voted on %s.", "%d share moves apply now; the rest is voted on %s.", moves) % [
			moves, vote_on]
	if refusal != "":
		text = reason(refusal) + ("\n" + text if text != "" else "")
	_text.text = text
	_text.visible = text != ""
	if refusal == "":
		# The seats are the bar's (its legend prints each count): the sentence does not say them again.
		_vote(read["vote"])


## The waterfall and the change list: the list is rebuilt when the rows change, the figures every refresh.
func _list(state, ns, draft, price, whole: Dictionary) -> void:
	var rows: Array = draft.rows()
	var ids := []
	for row in rows:
		ids.append(FinanceRows.row_id(String(row["channel"]), String(row["key"])))
	var shape := [ids, UiTheme.text_scale()]
	if shape != _built_ids:
		_built_ids = shape
		for child in _groups.get_children():
			_groups.remove_child(child)
			child.queue_free()
		for row in rows:
			_change(ns, row)
	_count.text = Strings.tn("%d change", "%d changes", rows.size()) % rows.size()
	# The books today, as the price reads them (re-read after a tabling or a law): a row's money is kept while they hold.
	var day := "%d-%d-%d|%s" % [int(state.year), int(state.month), int(state.day), str(price.now().get("deficit_pct_gdp", 0.0))]
	var steps := []
	var walked := 0.0
	for i in rows.size():
		var gain := _gain(price, rows[i], day)
		var money: Label = _groups.get_child(i).find_child("Money_*", true, false)
		money.text = EffectsStrip.money_text(gain)
		money.theme_type_variation = EffectsStrip.cell_variation(EffectsStrip.money_tone(gain))
		# A gain to the treasury narrows the deficit: the step is its opposite.
		steps.append({"label": "%s, %s" % [FinanceRows.change_label(ns, rows[i]), FinanceRows.change_figures(ns, rows[i])], "value": -gain})
		walked -= gain
	var now := float(whole["deficit_now_bn"])
	var after := float(whole["deficit_after_bn"])
	if absf(after - now - walked) >= RESIDUAL_BN:
		steps.append({"label": Strings.t("Together, and what the rows alone miss"), "value": after - now - walked})
	_chart.setup({"label": Strings.t("Today"), "value": now}, steps, {"label": Strings.t("With the bill"), "value": after}, {"label_w": 190.0})
	_pct.text = Strings.t("%s bn is %s %% of GDP; today %s %%.") % [Num.f(after, 0), Num.f(float(whole["deficit_after_pct"]), 2),
		Num.f(float(price.now().get("deficit_pct_gdp", 0.0)), 2)]
	if _dropped_at >= 0:
		var marks_now := []
		for button in _groups.find_children("*", "BaseButton", true, false):  # i18n: ok a class name
			if button.has_meta("drop") and not button.is_queued_for_deletion():
				marks_now.append(button)
		var next: Control = marks_now[mini(_dropped_at, marks_now.size() - 1)] if not marks_now.is_empty() else _table
		_dropped_at = -1
		next.grab_focus()


## One change: its name, who it is for or who pays, its money a year and its remove mark.
func _change(ns, row: Dictionary) -> void:
	var channel := String(row["channel"])
	var key := String(row["key"])
	var id := FinanceRows.row_id(channel, key)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.set_meta("rail", "change")
	line.set_meta("id", id)
	_groups.add_child(line)
	var name := PanelKit.plain_line(line, FinanceRows.change_label(ns, row), PanelKit.Tone.PLAIN)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.custom_minimum_size.x = 110.0 * UiTheme.text_scale()
	var who := PanelKit.plain_line(line, _who(ns, row), PanelKit.Tone.DIM)
	who.autowrap_mode = TextServer.AUTOWRAP_OFF
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.tooltip_text = who.text
	who.mouse_filter = Control.MOUSE_FILTER_PASS
	var money := Label.new()
	money.name = "Money_" + id.replace(":", "_")  # i18n: ok a node name, found by tests
	money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money.custom_minimum_size.x = 76.0 * UiTheme.text_scale()
	line.add_child(money)
	# A LinkButton: no stylebox padding, so it fits the row; its focus box still draws (Godot 4.7 LinkButton: theme style `focus`).
	var drop := LinkButton.new()
	drop.underline = LinkButton.UNDERLINE_MODE_NEVER
	drop.focus_mode = Control.FOCUS_ALL  # reachable by the keyboard, and where the focus goes after a remove
	drop.text = "×"  # i18n: ok a glyph, its tooltip says it
	drop.tooltip_text = Strings.t("Take this change out of the draft")
	drop.custom_minimum_size = Vector2(22.0 * UiTheme.text_scale(), 0.0)
	drop.set_meta("drop", id)
	drop.pressed.connect(func() -> void:
		_dropped_at = _index_of(id)
		drop_pressed.emit(channel, key))
	line.add_child(drop)


## Who a change is for (a line's blocs, most first) or who pays it (a tax's payers); the autumn's two rows name no one.
func _who(ns, row: Dictionary) -> String:
	var key := String(row["key"])
	match String(row["channel"]):
		FinanceDraft.SPENDING:
			var blocs := _line_blocs(key)
			return Strings.t("for %s") % ", ".join(blocs.map(func(b) -> String: return Labels.bloc(String(b)))) if not blocs.is_empty() else ""
		FinanceDraft.TAX:
			if bool(row.get("birth", false)):
				return ""
			var payers: Array = ns.tax_library[key].get("who_pays", [])
			return Strings.t("%s pay") % ", ".join(payers.map(func(b) -> String: return Labels.bloc(String(b)))) if not payers.is_empty() else ""
	return ""


func _line_blocs(key: String) -> Array:
	var day := "%d|%d|%d" % [_state.year, _state.month, _state.day] if _state != null else ""
	if day != _blocs_day:
		_blocs_day = day
		_blocs = {}
	if not _blocs.has(key):
		_blocs[key] = [] if _state == null else (FinanceRead.line_blocs(_state, _loader, key)["weights"] as Array).map(func(pair: Array) -> String: return String(pair[0]))
	return _blocs[key]


func _gain(price, row: Dictionary, day: String) -> float:
	var key := "%s|%s|%s|%s" % [FinanceRows.row_id(String(row["channel"]), String(row["key"])), row["draft"], row["live"], day]
	if not _gains.has(key):
		if _gains.size() > 64:
			_gains.clear()  # a long drag leaves one stale key per step
		_gains[key] = price.row_balance_bn(row)
	return float(_gains[key])


## The place of change `id` among the remove marks on screen, in reading order.
func _index_of(id: String) -> int:
	var i := 0
	for button in _groups.find_children("*", "BaseButton", true, false):  # i18n: ok a class name
		if button.has_meta("drop"):
			if String(button.get_meta("drop")) == id:
				return i
			i += 1
	return -1


## How the Assembly would divide on the draft now, as the sheet draws it; redrawn only when the seats move.
func _vote(vote: Dictionary) -> void:
	_vote_box.visible = true
	var key := "%d|%d|%d" % [int(vote["yes_seats"]), int(vote["no_seats"]), int(vote["abstain_seats"])]
	if key == _vote_key and _vote_box.get_child_count() > 0:
		return
	_vote_key = key
	for child in _vote_box.get_children():
		child.queue_free()
	ChartKit.stack(_vote_box, Strings.t("Assembly, if it divided now"), [
		{"label": Strings.t("For"), "value": float(vote["yes_seats"])},
		{"label": Strings.t("Against"), "value": float(vote["no_seats"])},
		{"label": Strings.t("Undecided"), "value": float(vote["abstain_seats"])},
	], {"places": 0, "colors": [UiTheme.GOOD, UiTheme.BAD, FinanceRows.MUTED], "marker": 0.5})


## The parent's ruling (2026-11-22): one filled button a screen, the screen's next step. A tab that shows a PRIMARY
## of its own (Register's "Put it in the finance bill") leads; the rail's verb is then plain, and filled again on a tab
## that feeds the bill nothing (Building) or on Books, whose next step is the rail's.
func _quiet_if_the_page_leads() -> void:
	var leads := page_leads()
	var want := "" if leads else UiTheme.PRIMARY
	if _table.theme_type_variation != want:
		_table.theme_type_variation = want


## Whether the workspace page shown beside the rail shows a PRIMARY button of its own.
func page_leads() -> bool:
	var manager = get_tree().get_first_node_in_group("window_manager") if is_inside_tree() else null
	if manager == null:
		return false
	for id in manager.open_ids():
		var page: Control = manager.content(id)
		if page == null or page.is_ancestor_of(self):
			continue
		for button in page.find_children("*", "Button", true, false):  # i18n: ok a class name
			if (button as Button).theme_type_variation == UiTheme.PRIMARY and (button as Button).is_visible_in_tree():
				return true
	return false


## The refusal in words, for a page with no queue verb: another bill in the slot is said as it is.
static func reason(flag: String) -> String:
	if flag == "already_tabled":
		return Strings.t("Another bill holds this month's slot.")
	if flag == "autumn":
		return Strings.t("A tax is created or abolished only in the autumn month.")
	# The refusal flags Legislature.refusal and FinanceBill.refusal hand back, in words (moved
	# here from goal_rows.gd when the Bills second pass took the goal tiles off the tab).
	match flag:
		"finance_queued":
			return Strings.t("A budget text is already queued.")
		"referendum_in_flight":
			return Strings.t("A referendum is in flight.")
		"unavailable":
			return Strings.t("Not open to propose now.")
		"range":
			return Strings.t("Outside the tax's range.")
		"verb":
			return Strings.t("A row of the bill is not legal now.")
	return Strings.t("It cannot be tabled now.")


## The control the page exists to let the player press: the draft's verb, else the bill's sheet.
func primary_action() -> Control:
	if _table.visible:
		return _table
	return _open if _open.visible else null
