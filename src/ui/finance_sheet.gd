extends PanelContainer

## The finance bill's DOCUMENT -- the author's pick "C" (2026-11-28; Design's c-build.md): the whole bill before it is
## tabled, one centred plate on the screen stack (finances_driver.gd puts it at SCENE and holds the clock while it is
## open), so nothing of the page can draw over it. Top to bottom: the month and the day the Assembly divides; four
## totals; the changes beside the deficit's steps (the rail's own chart, finance_steps.gd); the foot
## (finance_sheet_foot.gd): the verdict and the verbs. It hugs: a draft too long for the screen scrolls the list of
## changes only. It follows the draft; the page closes it when nothing is left.
##
## It computes nothing of its own: the totals and each row's money are FinancePrice's (the rail's figures), the
## division is FinanceRead.draft's. A row's line two is a neutral read: a spending line's blocs are the ones that weigh
## its issue (finance_who.gd), a tax's are its payers (the data); a rise pleases the line's blocs and angers the
## payers, a cut the reverse. The brackets and the autumn's two rows name no one.
##
## It is read-only over the game. A press is a signal: the page owns the commands.

signal table_pressed(force: bool)
signal withdraw_pressed
signal discard_pressed
signal close_pressed
## A change's remove mark: (channel, key) as FinanceDraft.drop takes them.
signal drop_pressed(channel: String, key: String)

const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const FinanceQueue = preload("res://src/ui/finance_queue.gd")
const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceSteps = preload("res://src/ui/finance_steps.gd")
const FinanceSheetFoot = preload("res://src/ui/finance_sheet_foot.gd")
const FinanceWho = preload("res://src/ui/finance_who.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const ControlStyle = preload("res://src/ui/control_style.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")

const HOURGLASS := "res://assets/icons/ui/hourglass.svg"
## The width at text 100, and the chart's column in it.
const WIDTH := 1080.0
const CHART_W := 440.0
## The room it leaves the window: at each side, and above and below.
const SIDE := 24.0
const EDGE := 40.0
## The list of changes never closes below this, however short the screen.
const LIST_MIN := 40.0
## The names a for or against phrase says before "+N".
const NAMES_SHOWN := 3

var _state
var _loader
var _draft
var _price
var _body: VBoxContainer
var _columns: HBoxContainer
var _left: VBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _foot: FinanceSheetFoot
var _stamp := ""
## The index of the change a remove mark took out, -1 for none: the keyboard goes to the mark now in its place.
var _dropped_at := -1
var _who := FinanceWho.new()


func _ready() -> void:
	name = "Sheet"  # i18n: ok a node name, found by tests
	theme_type_variation = UiTheme.PLATE
	visible = false
	var margin := MarginContainer.new()
	# With the plate's own content margins: 22 above, 24 at the sides, 20 below.
	for side in [["top", 14], ["left", 14], ["right", 14], ["bottom", 12]]:
		margin.add_theme_constant_override("margin_%s" % side[0], side[1])
	add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	margin.add_child(_body)


func setup(state, loader, draft, price) -> void:
	_state = state
	_loader = loader
	_draft = draft
	_price = price
	_stamp = ""
	_dropped_at = -1


## Written from the draft; called on every paint while open, and a rebuild is made only when something it reads
## changed (the draft, the slot, the day, the text size, the language). The force box is NOT in that stamp: ticking it
## redraws the foot's lines and verbs and leaves the box (and the keyboard's focus on it) where it is.
func refresh() -> void:
	if not visible or _state == null:
		_dropped_at = -1
		return
	# The whole bill, births and abolitions with the priced rows: hashing pending() alone left an autumn row
	# drafted with the document open off it, and Table tabled what the player had not been shown.
	var stamp := "%s|%d|%d|%d|%s|%s|%s|%d" % [var_to_str(_draft.bill()), _state.year, _state.month, _state.day,
		str([_state.player().tabled_bill, _state.player().bill_queue]), UiTheme.text_scale(), Strings.language(), _draft.moves().size()]
	if stamp == _stamp:
		return
	_stamp = stamp
	# A rebuild frees the control the keyboard is on: it comes back to the act (or the way out) rather than vanish.
	var held := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var had_focus: bool = held != null and is_ancestor_of(held)
	_build()
	var marks := _marks()
	if _dropped_at >= 0 and not marks.is_empty():
		(marks[mini(_dropped_at, marks.size() - 1)] as Control).grab_focus()
	elif had_focus:
		focus_primary()
	_dropped_at = -1


## The keyboard lands on the act when the document opens, or on the way out when the act is refused.
func focus_primary() -> void:
	var table := find_child("SheetTable", true, false) as Button
	if table != null and not table.disabled:
		table.grab_focus()
	else:
		(find_child("SheetClose", true, false) as Button).grab_focus()


## The width and the list's height follow the window: a label's height is known only once its width is, so both are
## read every frame it is open and set only when they differ.
func _process(_delta: float) -> void:
	if not visible or _scroll == null:
		return
	var view := get_viewport_rect().size
	var width := minf(WIDTH * UiTheme.text_scale(), view.x - 2.0 * SIDE)
	if not is_equal_approx(custom_minimum_size.x, width):
		custom_minimum_size.x = width
	# What the document needs besides the columns, and the left column besides its list.
	var around := get_combined_minimum_size().y - _columns.get_combined_minimum_size().y
	var above := _left.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	# shortcut: the chart does not scroll, so a draft of some 30 changes on a 1080 screen would pass the cap.
	var room := maxf(view.y - 2.0 * EDGE - around - above, LIST_MIN)
	var height := minf(_list.get_combined_minimum_size().y, room)
	if not is_equal_approx(_scroll.custom_minimum_size.y, height):
		_scroll.custom_minimum_size.y = height


func _build() -> void:
	var ticked := _foot != null and is_instance_valid(_foot) and _foot.force_ticked()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var ns = _state.player()
	var read: Dictionary = FinanceRead.draft(_state, _loader, _draft.bill())
	var refused := String(read["refusal"]) != ""
	_head(ns, FinanceQueue.verb(_state, _loader, String(read["refusal"]), _draft.bill()))
	var whole: Dictionary = _price.whole(_loader, _draft, refused)
	_totals(whole)
	_rule(_body)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 24)
	_body.add_child(_columns)
	_changes(ns)
	_chart(whole, refused)
	_rule(_body)
	_foot = FinanceSheetFoot.new()
	_body.add_child(_foot)
	_foot.build(_state, _loader, _draft, read, ticked)
	_foot.table_pressed.connect(table_pressed.emit)
	_foot.discard_pressed.connect(discard_pressed.emit)
	_foot.withdraw_pressed.connect(withdraw_pressed.emit)
	_foot.close_pressed.connect(close_pressed.emit)
	_foot.refilled.connect(_pin_the_keyboard)  # the force box writes new verbs
	_pin_the_keyboard()


## Tab and the arrows walk the document's controls in reading order and come round: left unpinned, Godot gives an
## arrow to the closest control in that direction, which may be one under the dim.
func _pin_the_keyboard() -> void:
	var ring: Array = find_children("*", "Control", true, false).filter(  # i18n: ok a class name
		func(c) -> bool: return c.focus_mode == Control.FOCUS_ALL)
	for i in ring.size():
		var at: Control = ring[i]
		var back: NodePath = at.get_path_to(ring[i - 1])
		var on: NodePath = at.get_path_to(ring[(i + 1) % ring.size()])
		at.focus_previous = back
		at.focus_next = on
		for side in [SIDE_LEFT, SIDE_TOP]:
			at.set_focus_neighbor(side, back)
		for side in [SIDE_RIGHT, SIDE_BOTTOM]:
			at.set_focus_neighbor(side, on)


## The title row, and under it what the player must know before the figures.
func _head(ns, queue: Dictionary) -> void:
	var tabled := FinanceBillLaw.tabled(ns) != null
	# G2: a draft the footer would queue is dated by the month it lands in; a tabled bill by its own vote day.
	var day := int(queue.get("day", Calendar.days_in_month(int(_state.year), int(_state.month))))
	var month := int(queue.get("month", _state.month))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	_body.add_child(line)
	var title := PanelKit.plain_line(line, Strings.t("Finance bill · %s") % DateText.month_long(month))
	title.theme_type_variation = UiTheme.LEAD
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	if tabled:
		day = int(ns.tabled_bill.get("vote_day", day))
		month = int(ns.tabled_bill.get("vote_month", month))
	var date := PanelKit.chip(line, Strings.t("divides %s") % DateText.day_mon(day, month), UiTheme.CHIP_WARN, HOURGLASS)
	date.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(date.get_child(0).get_child(-1) as Label).autowrap_mode = TextServer.AUTOWRAP_OFF  # a date is one line
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(spacer)
	var cross := Button.new()
	cross.name = "SheetCross"  # i18n: ok a node name, found by tests
	cross.text = "×"  # i18n: ok a glyph, its tooltip says it
	cross.tooltip_text = Strings.t("Close")
	cross.theme_type_variation = UiTheme.GHOST
	cross.custom_minimum_size = Vector2(PanelKit.BTN_W_ICON, PanelKit.BTN_H) * UiTheme.text_scale()
	cross.pressed.connect(close_pressed.emit)
	line.add_child(cross)
	# Table books the drafted share moves at once, whatever the vote (slice 5): said here, as the rail does.
	var moves: int = _draft.moves().size()
	if moves > 0:
		PanelKit.plain_line(_body, Strings.tn("%d share move applies now; the rest is voted on %s.", "%d share moves apply now; the rest is voted on %s.", moves) % [
			moves, DateText.day_month(day, month)]).name = "SheetMoves"  # i18n: ok a node name
	if tabled:
		PanelKit.plain_line(_body, Strings.t("An amendment to the bill before the Assembly: the figures are the whole bill's.")).name = "SheetAmendment"  # i18n: ok a node name


## What the bill does to each side a year, and the deficit before (the books today, no bill) and after (the whole bill
## passed). EVERY figure describes the bill the vote will decide: the rows already at vote with the new ones merged (an
## amendment), the same as the seat forecast under it; the list of changes alone is the new rows. A refused draft has
## no merged text, so its figures are the new rows'. A spending rise is bad news and a revenue rise good, as the rail
## and the editors tone them.
func _totals(whole: Dictionary) -> void:
	var line := HBoxContainer.new()
	line.name = "SheetTotals"  # i18n: ok a node name, found by tests
	line.add_theme_constant_override("separation", 40)
	_body.add_child(line)
	var spending := float(whole["spending_bn"])
	var revenue := float(whole["revenue_bn"])
	PanelKit.figure(line, EffectsStrip.money_text(spending), Strings.t("Spending"), EffectsStrip.money_tone(-spending))
	PanelKit.figure(line, EffectsStrip.money_text(revenue), Strings.t("Revenue"), EffectsStrip.money_tone(revenue))
	# The author's rule (2026-11-28): a size, and the caption's word carries the sign, a word a side. One signed
	# figure picks it for both captions, so a rounding cannot make them disagree.
	var was := float(whole["deficit_now_bn"])
	var will := float(whole["deficit_after_bn"])
	var captions := _balance_captions(was < 0.0, will < 0.0)
	var sides: Array[Control] = [
		PanelKit.figure(line, "%s → %s" % [Num.f(absf(was), 0), Strings.t("%s bn") % Num.f(absf(will), 0)], captions[0]),
		PanelKit.figure(line, "%s → %s %%" % [Num.f(absf(float(_price.now().get("deficit_pct_gdp", 0.0))), 2),
			Num.f(absf(float(whole["deficit_after_pct"])), 2)], captions[1])]
	# "Deficit → surplus, a year" is longer than its figure: the column widens, the caption keeps one line.
	for box in sides:
		(box.get_child(1) as Label).autowrap_mode = TextServer.AUTOWRAP_OFF


## The "a year" and "of GDP" captions, by whether today's books and the books with the bill are in surplus.
static func _balance_captions(today: bool, with_bill: bool) -> Array[String]:
	if today and with_bill:
		return [Strings.t("Surplus, a year"), Strings.t("Surplus, of GDP")]
	if today:
		return [Strings.t("Surplus → deficit, a year"), Strings.t("Surplus → deficit, of GDP")]
	if with_bill:
		return [Strings.t("Deficit → surplus, a year"), Strings.t("Deficit → surplus, of GDP")]
	return [Strings.t("Deficit, a year"), Strings.t("Deficit, of GDP")]


func _rule(box: Control) -> void:
	var line := ColorRect.new()
	line.color = UiTheme.LINE
	line.custom_minimum_size.y = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)


func _changes(ns) -> void:
	_left = VBoxContainer.new()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_child(_left)
	var rows: Array = _draft.rows()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_left.add_child(head)
	var count := Label.new()
	count.name = "SheetCount"  # i18n: ok a node name, found by tests
	count.text = (Strings.tn("%d change", "%d changes", rows.size()) % rows.size()).to_upper()
	count.theme_type_variation = UiTheme.MICRO
	head.add_child(count)
	PanelKit.plain_line(head, Strings.t("× takes one out")).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll = ScrollContainer.new()
	_scroll.name = "SheetList"  # i18n: ok a node name, found by tests
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_left.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	for i in rows.size():
		if i > 0:
			_rule(_list)
		_change(ns, rows[i], i)


## One change on two lines: its name, its tag, its figures, its money a year and its remove mark; then who is for or
## against it.
func _change(ns, row: Dictionary, at: int) -> void:
	var channel := String(row["channel"])
	var key := String(row["key"])
	var id := FinanceRows.row_id(channel, key)
	var box := VBoxContainer.new()
	box.name = "SheetRow_" + id.replace(":", "_")  # i18n: ok a node name, found by tests
	box.add_theme_constant_override("separation", 2)
	_list.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	box.add_child(line)
	var words := HFlowContainer.new()
	words.add_theme_constant_override("h_separation", 8)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(words)
	var born := bool(row.get("birth", false))
	var abolished := channel == FinanceDraft.ABOLISH
	# The tag says what happens to the tax, so the name is the tax's own, not "Creation of ...".
	var title := Strings.row_name("taxes", ns.tax_library[key]) if born or abolished else FinanceRows.change_label(ns, row)
	var name_label := _word(words, title, ControlStyle.STRONG)
	name_label.name = "Name"  # i18n: ok a node name, found by tests
	if born or abolished:
		var tag := PanelKit.chip(words, Strings.t("New") if born else Strings.t("Abolished"), UiTheme.CHIP)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		(tag.get_child(0).get_child(-1) as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
	_word(words, FinanceRows.change_figures(ns, row), UiTheme.CAPTION).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var gain: float = _price.row_balance_bn(row)
	var money := _word(line, EffectsStrip.sum_text(gain), EffectsStrip.cell_variation(EffectsStrip.money_tone(gain)))
	money.name = "Money"  # i18n: ok a node name, found by tests
	money.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# A LinkButton as the rail's: no stylebox padding, so it fits the row; its focus box still draws.
	var drop := LinkButton.new()
	drop.underline = LinkButton.UNDERLINE_MODE_NEVER
	drop.focus_mode = Control.FOCUS_ALL
	drop.text = "×"  # i18n: ok a glyph, its tooltip says it
	drop.tooltip_text = Strings.t("Take this change out of the draft")
	drop.custom_minimum_size.x = 22.0 * UiTheme.text_scale()
	drop.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	drop.set_meta("drop", id)
	drop.pressed.connect(func() -> void:
		_dropped_at = at
		drop_pressed.emit(channel, key))
	line.add_child(drop)
	if not born and not abolished:
		_who_line(box, channel, key, float(row["draft"]) > float(row["live"]))


## A label that is never wrapped: a "11 → 12 % of GDP" folded in a tight row is a column of single words.
func _word(parent: Control, text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text  # i18n: row-ok the caller passes shown text
	label.theme_type_variation = variation
	parent.add_child(label)
	return label


## Who a rise or a cut pleases and angers: one phrase a side with an arrow and a tone, never colour alone.
func _who_line(box: Control, channel: String, key: String, rise: bool) -> void:
	var pleased: Array = []
	var angered: Array = []
	if channel == FinanceDraft.SPENDING:
		(pleased if rise else angered).append_array(_who.line_blocs(_state, _loader, key))
	elif channel == FinanceDraft.TAX:
		(angered if rise else pleased).append_array(_state.player().tax_library[key].get("who_pays", []))
	for side in [[pleased, "▲ ", Strings.t("%s for"), UiTheme.GOOD_SMALL], [angered, "▼ ", Strings.t("%s against"), UiTheme.BAD_SMALL]]:
		var blocs: Array = side[0]
		if blocs.is_empty():
			continue
		var names := ", ".join(blocs.slice(0, NAMES_SHOWN).map(func(b) -> String: return Labels.bloc(String(b))))
		if blocs.size() > NAMES_SHOWN:
			names += ", +%d" % (blocs.size() - NAMES_SHOWN)
		var phrase := PanelKit.plain_line(box, String(side[1]) + String(side[2]) % names)
		phrase.name = "Who"  # i18n: ok a node name, found by tests
		phrase.theme_type_variation = String(side[3])


## The deficit walked change by change: the rail's own chart, amendment and residual steps included.
func _chart(whole: Dictionary, refused: bool) -> void:
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = CHART_W * UiTheme.text_scale()
	_columns.add_child(right)
	var none := {"label": "", "value": 0.0}
	var chart := ChartKit.waterfall(right, Strings.t("The deficit, a year, bn").to_upper(), none, [], none)
	FinanceSteps.setup(chart.get_meta("chart"), _state, _loader, _draft, _price, whole, refused)


## The remove marks, in reading order.
func _marks() -> Array:
	return find_children("*", "BaseButton", true, false).filter(  # i18n: ok a class name
		func(b) -> bool: return b.has_meta("drop") and not b.is_queued_for_deletion())
