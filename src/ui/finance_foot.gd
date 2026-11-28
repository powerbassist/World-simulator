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
## The folded line's chevron: the shell puts the inbox away (finances_driver.gd), and the rail opens.
signal unfold_pressed
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
const DateText = preload("res://src/ui/date_text.gd")
const Num = preload("res://src/ui/num.gd")
const FinanceRefusal = preload("res://src/ui/finance_refusal.gd")
const FinanceQueue = preload("res://src/ui/finance_queue.gd")
const FinanceStrip = preload("res://src/ui/finance_strip.gd")
const FinancePages = preload("res://src/ui/finance_pages.gd")
const FinanceLanding = preload("res://src/ui/finance_landing.gd")
const FinanceWho = preload("res://src/ui/finance_who.gd")
const ControlStyle = preload("res://src/ui/control_style.gd")
const Icon = preload("res://src/ui/icon.gd")
const HOURGLASS := "res://assets/icons/ui/hourglass.svg"

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
## Who each change is for or who pays it (finance_who.gd keeps a line's blocs for the day).
var _who := FinanceWho.new()
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
var _folded := false
## Frames until the next look at whether the page beside the rail shows its own filled button.
var _lead_wait := 0
var _open_seen: Array = []
## Open: the column. Folded (the inbox shows): one line under the header (finance_strip.gd), the date tag and the verbs
## docked into it.
var _col: VBoxContainer
var _head: HBoxContainer
var _verbs: Container
var _strip: FinanceStrip
var _verdict: Label
var _landing: FinanceLanding  # where the page's programme would land (Register): a dashed place
var _stays: Label
## The frame the chevron was pressed: an unfold that follows within a few frames is the chevron's, and the keyboard
## follows it; a later one (the inbox closed some other way) leaves the focus where it is (pass 1 on #447).
var _unfold_frame := -100


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	custom_minimum_size.x = WIDTH * UiTheme.text_scale()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_col = col
	_strip = FinanceStrip.new()
	add_child(_strip)
	_strip.unfold_pressed.connect(func() -> void: _unfold_frame = Engine.get_process_frames(); unfold_pressed.emit())
	_strip.hide()
	var head := HBoxContainer.new()
	_head = head
	col.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_date = PanelKit.chip(head, "", UiTheme.CHIP_WARN)
	_date.size_flags_horizontal = Control.SIZE_SHRINK_END
	_date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_date_words().autowrap_mode = TextServer.AUTOWRAP_OFF  # a date is one line; a wrapping chip squeezed it to a letter a line
	# A deadline tag wears the hourglass (gate T8 on #443), as the time bar's do.
	var glass := TextureRect.new()
	var px := roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())
	glass.texture = Icon.load_icon(HOURGLASS, UiTheme.WARN, px)
	glass.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	glass.custom_minimum_size = Vector2(px, px)
	_date.get_child(0).add_child(glass)
	_date.get_child(0).move_child(glass, 0)
	_stays = PanelKit.plain_line(col, Strings.t("It stays on every Finances tab: Register and Building add to it."), PanelKit.Tone.DIM)
	_stays.autowrap_mode = TextServer.AUTOWRAP_WORD
	_empty = PanelKit.plain_line(col, "", PanelKit.Tone.PLAIN)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	# The waterfall and the changes scroll between the bill's head and its verdict and verbs: a long draft keeps "Table the
	# bill" on screen (pass 2 T3 on #443). It takes the room the spacer took, so the verbs stay at the rail's foot.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # the focus after a remove lands on an x in it
	col.add_child(scroll)
	var listed := VBoxContainer.new()
	listed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listed.add_theme_constant_override("separation", 10)
	scroll.add_child(listed)
	_fall = VBoxContainer.new()
	listed.add_child(_fall)
	var box := ChartKit.waterfall(_fall, Strings.t("The deficit, a year, bn").to_upper(), {"label": "", "value": 0.0}, [], {"label": "", "value": 0.0})
	_chart = box.get_meta("chart")
	_chart.set_meta("rail", "waterfall")
	_pct = PanelKit.plain_line(_fall, "", PanelKit.Tone.DIM)

	_changes = VBoxContainer.new()
	listed.add_child(_changes)
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
	_landing = FinanceLanding.new()
	listed.add_child(_landing)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_text)
	_vote_box = VBoxContainer.new()
	col.add_child(_vote_box)
	# The Assembly's result in words under its bar, with its check or its cross (gate T9 on #443).
	_verdict = Label.new()
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_verdict)
	var verbs := PanelKit.buttons(col)
	_verbs = verbs
	_table = _button(verbs, "Table", Strings.t("Table the bill"), table_pressed, UiTheme.PRIMARY)  # i18n: ok a node name
	_open = _button(verbs, "OpenBill", Strings.t("Open the bill"), open_pressed)
	# Two looks for a click: a button or a ghost (gate T7 on #443). The links are ghosts; the rail's verb stays the loud one.
	_discard = _button(verbs, "Discard", Strings.t("Discard all"), discard_pressed, UiTheme.GHOST)  # i18n: ok a node name
	_review = _button(verbs, "Review", Strings.t("Review the bill"), review_pressed, UiTheme.GHOST)  # i18n: ok a node name
	_withdraw = _button(verbs, "Withdraw", Strings.t("Withdraw the bill"), withdraw_pressed, UiTheme.GHOST)  # i18n: ok a node name


func _button(parent: Control, node_name: String, label: String, signal_out: Signal, variation := "") -> Button:
	var button := PanelKit.sized(Button.new())
	button.theme_type_variation = variation
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.name = node_name  # i18n: ok a node name, found by tests
	button.text = label
	button.pressed.connect(signal_out.emit)
	parent.add_child(button)
	return button


func _date_words() -> Label:
	return _date.get_child(0).get_child(-1) as Label


## Folds the rail to one line under the header (window_manager, while the inbox shows) or opens it again: the date tag
## and the verbs move with it, so each stays one control. True when it changed.
func set_folded(folded: bool) -> bool:
	if folded == _folded:
		return false
	_folded = folded
	_col.visible = not folded
	_strip.visible = folded
	if folded:
		_strip.dock([_date] + _verbs.get_children())
	else:
		_date.reparent(_head, false)
		for verb in [_table, _open, _discard, _review, _withdraw]:
			verb.reparent(_verbs, false)
		var first := _verbs.get_children().filter(func(v) -> bool: return v.visible and not v.disabled)
		if Engine.get_process_frames() - _unfold_frame <= 3 and not first.is_empty():
			(first[0] as Control).call_deferred("grab_focus")
	custom_minimum_size.x = _width()
	_stamp = ""
	if _state != null and _state.player() != null:
		refresh(_state, _loader, _draft, _price)
	return true


func is_folded() -> bool:
	return _folded


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
	var stamp := FinanceQueue.stamp(_state, ns, _draft)
	if not is_equal_approx(custom_minimum_size.x, _width()):
		stamp = ""
	if stamp != _stamp:
		refresh(_state, _loader, _draft, _price)
	# A tab switched beside the rail is looked at at once.
	var manager = get_tree().get_first_node_in_group("window_manager")
	var shown: Array = manager.open_ids() if manager != null else []
	if shown != _open_seen:
		_open_seen = shown
		_lead_wait = 0
	_lead_wait -= 1
	if _lead_wait <= 0:
		_lead_wait = 15  # a quarter of a second: a placed unit lights Register's button, nothing faster needs it
		_quiet_if_the_page_leads()


## Written from the draft and the books; called on every draft move and every redraw, so it reads only.
func refresh(state, loader, draft, price) -> void:
	var ns = state.player()
	var tabled = FinanceBillLaw.tabled(ns)
	var drafted: bool = not draft.is_empty()
	var moves: int = draft.moves().size()
	_stamp = FinanceQueue.stamp(state, ns, draft)
	custom_minimum_size.x = _width()  # the text size may have moved
	_lead_wait = 0
	var vote_on := DateText.day_mon(Calendar.days_in_month(int(state.year), int(state.month)), int(state.month))
	var waiting: Dictionary = FinanceQueue.waiting(state) if not drafted and tabled == null else {}
	_text.visible = true
	_verdict.visible = false
	_table.visible = drafted or moves > 0
	_discard.visible = drafted or moves > 0
	_review.visible = drafted
	_open.visible = not drafted and (tabled != null or not waiting.is_empty())
	_withdraw.visible = tabled != null
	_changes.visible = drafted
	_fall.visible = drafted
	_vote_box.visible = false
	_empty.visible = not drafted and moves == 0 and tabled == null and waiting.is_empty()
	_date.visible = drafted or tabled != null or not waiting.is_empty()
	if tabled != null:
		vote_on = DateText.day_mon(int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))
	vote_on = _head_for(state, waiting, vote_on)
	_empty.text = Strings.t("No change yet.")
	if not drafted and _dropped_at >= 0:
		# The changes went with the last one: the focus goes to a verb still here (Discard all while share moves remain,
		# pass 2 T8 on #443), never nowhere; a stale index would pull the next draft's focus onto an x.
		_dropped_at = -1
		var next: Control = _discard if _discard.visible else (_open if _open.visible else null)
		if next != null:
			next.grab_focus()
	var before_vote := String(waiting.get("text", ""))
	if tabled != null:
		before_vote = Strings.t("A finance bill is before the Assembly: it divides on %s.") % vote_on
	if not drafted and moves > 0:
		_table.text = Strings.t("Apply the moves")
		_table.disabled = false
		_text.text = Strings.tn("%d share move takes effect now, with no vote.", "%d share moves take effect now, with no vote.", moves) % moves + \
			("\n" + before_vote if tabled != null else "")
		_strip.say(_title.text, _text.text.replace("\n", " "), "", false, false)
		return
	if not drafted:
		_text.text = before_vote
		_strip.say(_title.text, before_vote if before_vote != "" else _empty.text, "", false, false)
		return
	var read: Dictionary = FinanceRead.draft(state, loader, draft.bill())
	var refusal := String(read["refusal"])
	# G2: another bill holds the slot, so the verb queues the draft and the bar is dated by the month it lands in.
	var queue: Dictionary = FinanceQueue.verb(state, refusal)
	var can_queue := bool(queue.get("enabled", false))
	vote_on = _head_for(state, queue, vote_on)
	# The same pricing as the sheet (FinancePrice.whole): the bill the vote decides. On an amendment the money is the
	# whole bill's, and the sentence says so.
	var whole: Dictionary = price.whole(loader, draft, refusal != "")
	# An amendment's money is the whole bill's: the bill already tabled is its own first step (pass 2 T6 on #443).
	var first := {}
	if tabled != null and refusal == "":
		var alone: Dictionary = price.tabled(loader)
		first = {"label": Strings.t("The bill before the Assembly"), "value": float(alone["deficit_after_bn"]) - float(alone["deficit_now_bn"])}
	_list(ns, draft, price, whole, first)
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
	var verb := Strings.t("Add to the bill") if tabled != null else Strings.t("Table the bill")
	_table.text = verb if String(queue.get("text", "")) == "" else String(queue["text"])
	_table.disabled = refusal != "" and not can_queue
	if moves > 0:
		text += ("\n" if text != "" else "") + Strings.tn("%d share move applies now; the rest is voted on %s.", "%d share moves apply now; the rest is voted on %s.", moves) % [
			moves, vote_on]
	var said := "" if refusal == "" else FinanceRefusal.reason(refusal) + (" " + String(queue["note"]) if queue.has("note") else "")
	if said != "":
		text = said + ("\n" + text if text != "" else "")
	_text.text = text
	_text.visible = text != ""
	var vote: Dictionary = read["vote"]
	var verdict := said if refusal != "" else FinanceRefusal.carries_text(vote)
	if refusal == "":
		# The seats are the bar's (its legend prints each count); the verdict says the result in words.
		_vote(vote)
		_verdict.text = verdict
		_verdict.theme_type_variation = UiTheme.GOOD_SMALL if bool(vote.get("passed", false)) else UiTheme.BAD_SMALL
		_verdict.visible = true
	_strip.say(_title.text, Strings.tn("%d change", "%d changes", draft.count()) % draft.count() + " · " + \
		Strings.t("deficit %s → %s bn a year") % [Num.f(float(whole["deficit_now_bn"]), 0), Num.f(float(whole["deficit_after_bn"]), 0)],
		verdict, refusal == "" and bool(vote.get("passed", false)), not can_queue and (refusal != "" or not bool(vote.get("passed", false))))


## The title and the date tag: this month's bill, or the month a queued one (`lands`: {month, day}) divides in.
## Returns the vote's date as the bar writes it.
func _head_for(state, lands: Dictionary, vote_on: String) -> String:
	if lands.has("month"):
		vote_on = DateText.day_mon(int(lands["day"]), int(lands["month"]))
	_title.text = Strings.t("Finance bill · %s") % DateText.month_long(int(lands.get("month", state.month)))
	_date_words().text = Strings.t("divides %s") % vote_on
	return vote_on


func _width() -> float:
	return 0.0 if _folded else WIDTH * UiTheme.text_scale()


## The waterfall and the change list: the list is rebuilt when the rows change, the figures every refresh.
func _list(ns, draft, price, whole: Dictionary, first: Dictionary) -> void:
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
	_count.text = (Strings.tn("%d change", "%d changes", rows.size()) % rows.size()).to_upper()
	# A row's money is kept by the price while the books hold (FinancePrice.row_balance_bn).
	var steps := [] if first.is_empty() else [first]
	var walked := 0.0 if first.is_empty() else float(first["value"])
	for i in rows.size():
		var gain: float = price.row_balance_bn(rows[i])
		var money: Label = _groups.get_child(i).find_child("Money_*", true, false)
		money.text = EffectsStrip.money_text(gain)
		money.theme_type_variation = ControlStyle.STRONG  # a price is neutral with its sign (gate T4 on #443)
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
	var who := PanelKit.plain_line(line, _who.say(_state, _loader, row), PanelKit.Tone.DIM)
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
	FinanceRefusal.division_bar(_vote_box, Strings.t("Assembly, if it divided now").to_upper(), vote)


## The parent's ruling (2026-11-22): one filled button a screen, the screen's next step. A tab that shows a PRIMARY
## of its own (Register's "Put it in the finance bill") leads; the rail's verb is then plain, and filled again on a tab
## that feeds the bill nothing (Building) or on Books, whose next step is the rail's.
func _quiet_if_the_page_leads() -> void:
	_landing.show_for(FinancePages.landing(self))
	var leads := FinancePages.leads(self)
	var want := "" if leads else UiTheme.PRIMARY
	if _table.theme_type_variation != want:
		_table.theme_type_variation = want


## The control the page exists to let the player press: the draft's verb, else the bill's sheet.
func primary_action() -> Control:
	if _table.visible:
		return _table
	return _open if _open.visible else null
