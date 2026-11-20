extends PanelContainer

## The Finances page's tray -- the rework pass's C ("tiroir des changements", the author's pick after the G3 lines
## on the finance buttons). It docks under the Books page and replaces the footer whose five buttons relabelled across
## states. While rows are drafted it lists each change as a dumbbell on one 0-25 scale (ring today, dot the draft,
## ChartDots), its money a year and a remove mark; it says the totals, the deficit before and after, how the Assembly
## would divide now (the for/against/undecided bar) and when; and it carries ONE button, "Table the bill" (a bill
## already before the Assembly takes the draft as an amendment, "Add to the bill"; moves alone apply now, "Apply the
## moves"). "Discard all" and "Review the bill" are links: the review keeps the sheet, where a passage is forced.
## With nothing drafted and a bill before the Assembly it says so, with the bill's sheet and its withdrawal.
## Nothing drafted and nothing tabled: the tray is not there.
##
## SHARE MOVES (slice 5, Gameplay's ruling) ride the draft but not the bill: they apply the moment the verb is pressed,
## and the sentence says how many apply now and when the rest is voted. A button the rule would refuse is never a dead
## verb: disabled, with the refusal in words beside it, read from FinanceRead.draft (the very rule tabling meets).

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
const ChartDots = preload("res://src/ui/chart_dots.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Num = preload("res://src/ui/num.gd")

## The dumbbells' one axis: every rate and line the draft moves sits between 0 and 25 (% or % of GDP).
const SCALE := Vector2(0.0, 25.0)
## The dumbbells' value column at text 100: "11.0 → 12.5 % of GDP" in full.
const VALUE_W := 170.0
## Its name column: the longest change name ("Income brackets", a tax's name) at text 100.
const LABEL_W := 130.0

var _text: Label
var _table: Button
var _discard: Button
var _open: Button
var _review: Button
var _withdraw: Button
var _changes: VBoxContainer
## One chart per unit kind (pass 2 T3): the percentages share the 0-25 scale, any other unit gets its own axis.
var _groups: VBoxContainer
## The dumbbells' legend: shown with the dumbbells only (moves alone draw none).
var _legend: Label
## Each change's money a year, by "id|draft value|live value|day": a drag moves one row, so the others are priced once
## per change of their own (pass 2 T2), not on every frame of the drag.
var _gains := {}
## The index of the change a remove mark took out, -1 for none: the focus goes to the mark now in its place.
var _dropped_at := -1
var _vote_box: VBoxContainer
## The drafted rows' ids the list was built for: a drag changes values, not rows, and repaints in place.
var _built_ids := []
var _vote_key := ""


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)

	_changes = VBoxContainer.new()
	_changes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_changes.size_flags_stretch_ratio = 1.6
	row.add_child(_changes)
	var head := HBoxContainer.new()
	_changes.add_child(head)
	var title := Label.new()
	title.theme_type_variation = UiTheme.MICRO
	title.text = Strings.t("Your draft")
	head.add_child(title)
	_legend = PanelKit.plain_line(head, Strings.t("ring today, dot the draft; × takes a change out"))
	_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_discard = _button(head, "Discard", Strings.t("Discard all"), discard_pressed)  # i18n: ok a node name
	_discard.flat = true
	_groups = VBoxContainer.new()
	_changes.add_child(_groups)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	side.add_child(_text)
	_vote_box = VBoxContainer.new()
	side.add_child(_vote_box)
	var verbs := PanelKit.buttons(side)
	# At the tray's right end (a briefing opened over the page is centred).
	verbs.alignment = FlowContainer.ALIGNMENT_END
	_review = _button(verbs, "Review", Strings.t("Review the bill"), review_pressed)  # i18n: ok a node name
	_review.flat = true  # the sheet is the act's detail; the tray's own verb stays the loud one
	_open = _button(verbs, "OpenBill", Strings.t("Open the bill"), open_pressed)
	_withdraw = _button(verbs, "Withdraw", Strings.t("Withdraw the bill"), withdraw_pressed)  # i18n: ok a node name
	_withdraw.flat = true
	# The verb last, at the right end: the links read before it, and it stays clear of a centred briefing.
	_table = _button(verbs, "Table", Strings.t("Table the bill"), table_pressed)  # i18n: ok a node name
	_table.theme_type_variation = UiTheme.PRIMARY
	visible = false


func _button(parent: Control, node_name: String, label: String, signal_out: Signal) -> Button:
	var button := PanelKit.sized(Button.new())
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.name = node_name  # i18n: ok a node name, found by tests
	button.text = label
	button.pressed.connect(signal_out.emit)
	parent.add_child(button)
	return button


## Written from the draft and the books; called on every draft move and every redraw, so it reads only.
func refresh(state, loader, draft, price) -> void:
	var ns = state.player()
	var tabled = FinanceBillLaw.tabled(ns)
	var drafted: bool = not draft.is_empty()
	var moves: int = draft.moves().size()
	visible = drafted or moves > 0 or tabled != null
	_table.visible = drafted or moves > 0
	_discard.visible = drafted or moves > 0
	_review.visible = drafted
	_open.visible = not drafted and tabled != null
	_withdraw.visible = tabled != null
	_changes.visible = drafted or moves > 0  # Discard sits in its head: moves alone can be put away too
	_groups.visible = drafted
	_legend.visible = drafted
	_vote_box.visible = false
	if not visible:
		_dropped_at = -1  # the tray went with the last change: a stale index would pull the next draft's focus onto an x
		return
	if drafted:
		_list(state, ns, draft, price)
	elif _dropped_at >= 0:
		# The last change went: no mark to land on. Discard while moves remain, else the focus is let go with the tray.
		_dropped_at = -1
		if _discard.is_visible_in_tree():
			_discard.grab_focus()
	var before_vote := ""
	if tabled != null:
		before_vote = Strings.t("A finance bill is before the Assembly: it divides on %s.") % DateText.day_month(
			int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))
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
	# The same pricing as the sheet (FinancePrice.whole): the bill the vote decides. On an amendment the count is the
	# new rows but the money is the whole bill's, and the sentence says so.
	var whole: Dictionary = price.whole(loader, draft, refusal != "")
	var money := Strings.t("the whole bill: spending %s, revenue %s a year") if tabled != null else Strings.t("spending %s, revenue %s a year")
	var vote_on := DateText.day_month(Calendar.days_in_month(int(state.year), int(state.month)), int(state.month))
	var text: String = Strings.tn("%d change", "%d changes", draft.count()) % draft.count() + " · " + \
		money % [EffectsStrip.money_text(float(whole["spending_bn"])), EffectsStrip.money_text(float(whole["revenue_bn"]))] + " · " + \
		Strings.t("the Assembly divides on %s") % vote_on
	# The autumn bill's rows are named in the sentence (their money is in the totals, priced by FinanceBill.preview).
	var autumn: Array = []
	for kind in draft.births():
		autumn.append(Strings.t("creation of %s") % Strings.row_name("taxes", ns.tax_library[kind]))
	for kind in draft.abolitions():
		autumn.append(Strings.t("abolition of %s") % Strings.row_name("taxes", ns.tax_library[kind]))
	if not autumn.is_empty():
		text += " · " + ", ".join(autumn)
	text += "\n" + Strings.t("Deficit %s → %s bn (%s %% of GDP)") % [Num.f(float(whole["deficit_now_bn"]), 0),
		Num.f(float(whole["deficit_after_bn"]), 0), Num.f(float(whole["deficit_after_pct"]), 2)]
	_table.text = Strings.t("Add to the bill") if tabled != null else Strings.t("Table the bill")
	_table.disabled = refusal != ""
	var now_line := ""
	if moves > 0:
		now_line = "\n" + Strings.tn("%d share move applies now; the rest is voted on %s.", "%d share moves apply now; the rest is voted on %s.", moves) % [
			moves, vote_on]
	if refusal != "":
		_text.text = text + "\n" + reason(refusal) + now_line
		return
	# The seats are the bar's (its legend prints each count): the sentence does not say them again (pass 2 T10).
	_text.text = text + now_line
	_vote(read["vote"])


## The changes as dumbbells, one chart per unit kind in the draft's own order, each change with its own figures, its
## money a year and its remove mark beside its row.
func _list(state, ns, draft, price) -> void:
	var rows: Array = draft.rows()
	var kinds: Array = []
	var by_kind := {}
	for row in rows:
		var kind := _kind(ns, row)
		if not by_kind.has(kind):
			kinds.append(kind)
			by_kind[kind] = []
		(by_kind[kind] as Array).append(row)
	var ids := []
	for row in rows:
		ids.append(FinanceRows.row_id(String(row["channel"]), String(row["key"])))
	var shape := [kinds, ids, UiTheme.text_scale()]
	if shape != _built_ids:
		_built_ids = shape
		for child in _groups.get_children():
			_groups.remove_child(child)
			child.queue_free()
		for kind in kinds:
			_group(by_kind[kind])
	# The books today, as the price reads them (re-read after a tabling or a law): a row's money is kept while they hold.
	var day := "%d-%d-%d|%s" % [int(state.year), int(state.month), int(state.day), str(price.now().get("deficit_pct_gdp", 0.0))]
	for g in _groups.get_child_count():
		var group: Array = by_kind[kinds[g]]
		var chart: ChartDots = _groups.get_child(g).get_child(0)
		var dots := []
		var top := 0.0
		for row in group:
			dots.append({"id": FinanceRows.row_id(String(row["channel"]), String(row["key"])), "label": FinanceRows.change_label(ns, row),
				"before": float(row["live"]), "after": float(row["draft"]), "moved": true, "text": FinanceRows.change_figures(ns, row)})
			top = maxf(top, maxf(float(row["live"]), float(row["draft"])))
		# The percentages share one 0-25 scale while they fit it; any other unit, or a value past it, fits its own axis.
		# The figures carry their unit ("11.0 → 12.5 % of GDP"): a wider value column. A fitted axis of small values
		# (a duty in EUR/l, the brackets) ticks at two decimals, or its two ends both read "0.7".
		var opts := {"places": 1, "value_w": VALUE_W, "label_w": LABEL_W}
		if kinds[g] == "pct" and top <= SCALE.y:
			opts["fixed"] = SCALE
		elif kinds[g] != "pct":
			opts["places"] = 2
		chart.setup(dots, opts)
		var marks: VBoxContainer = chart.get_meta("marks")
		for i in group.size():
			var money: Label = marks.get_child(i).get_child(0)
			var gain := _gain(price, group[i], day)
			money.text = EffectsStrip.money_text(gain)
			money.theme_type_variation = EffectsStrip.cell_variation(EffectsStrip.money_tone(gain))
	if _dropped_at >= 0:
		var marks_now := []
		for button in _groups.find_children("*", "BaseButton", true, false):  # i18n: ok a class name
			if button.has_meta("drop") and not button.is_queued_for_deletion():
				marks_now.append(button)
		var next: Control = marks_now[mini(_dropped_at, marks_now.size() - 1)] if not marks_now.is_empty() else _table
		_dropped_at = -1
		next.grab_focus()


## A change's unit kind: "pct" for a share of GDP or a rate in %, the brackets apart, else the tax's own unit.
static func _kind(ns, row: Dictionary) -> String:
	match String(row["channel"]):
		FinanceDraft.SPENDING:
			return "pct"
		FinanceDraft.BRACKETS:
			return "brackets"
	var unit := String(ns.tax_library[String(row["key"])]["unit"])
	return "pct" if unit == "%" else unit


## One unit kind: its chart and, beside each row, the change's money and remove mark.
func _group(rows: Array) -> void:
	var line := HBoxContainer.new()
	_groups.add_child(line)
	var chart := ChartDots.new()
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.set_meta("tray", "changes")
	line.add_child(chart)
	var marks := VBoxContainer.new()
	marks.add_theme_constant_override("separation", 0)
	chart.set_meta("marks", marks)
	line.add_child(marks)
	for row in rows:
		_mark(marks, chart, String(row["channel"]), String(row["key"]), FinanceRows.row_id(String(row["channel"]), String(row["key"])))


func _gain(price, row: Dictionary, day: String) -> float:
	var key := "%s|%s|%s|%s" % [FinanceRows.row_id(String(row["channel"]), String(row["key"])), row["draft"], row["live"], day]
	if not _gains.has(key):
		if _gains.size() > 64:
			_gains.clear()  # a long drag leaves one stale key per step
		_gains[key] = price.row_balance_bn(row)
	return float(_gains[key])


func _mark(marks: VBoxContainer, chart: ChartDots, channel: String, key: String, id: String) -> void:
	var h := chart.row_height()
	var line := HBoxContainer.new()
	# Exactly a chart row's height, so the money and the mark sit beside their change (pass 2 T4): the children are
	# shrunk into it, never the reverse.
	line.custom_minimum_size.y = h
	line.clip_contents = true
	marks.add_child(line)
	var money := Label.new()
	money.name = "Money_" + id.replace(":", "_")  # i18n: ok a node name, found by tests
	money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	money.custom_minimum_size.x = 76.0 * UiTheme.text_scale()
	money.size_flags_vertical = Control.SIZE_FILL
	line.add_child(money)
	# A LinkButton: no stylebox padding, so it fits the row (a Button's own margins made the line 31 px for a 24 px row);
	# its focus box still draws (Godot 4.7 LinkButton: theme style `focus`).
	var drop := LinkButton.new()
	drop.underline = LinkButton.UNDERLINE_MODE_NEVER
	drop.focus_mode = Control.FOCUS_ALL  # reachable by the keyboard, and where the focus goes after a remove
	drop.text = "×"  # i18n: ok a glyph, its tooltip says it
	drop.tooltip_text = Strings.t("Take this change out of the draft")
	drop.custom_minimum_size = Vector2(h, 0.0)  # a target as wide as the row is tall
	drop.size_flags_vertical = Control.SIZE_FILL
	drop.set_meta("drop", id)
	drop.pressed.connect(func() -> void:
		_dropped_at = _index_of(id)
		drop_pressed.emit(channel, key))
	line.add_child(drop)


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
	if not visible:
		return null
	return _table if _table.visible else _open
