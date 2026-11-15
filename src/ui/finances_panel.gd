extends PanelContainer

## The Finances page -- V5.3 screen 4, direction A ("in and out, to scale", the author's pick). The one
## sentence the screen exists to say (what comes in, what goes out, the gap, the debt), the three
## two-year ranges, and under them the books drawn to one scale: revenue by base on the left, spending
## by line on the right, the deficit the spending stack's overhang (finance_stacks.gd). The rows beside
## the stacks name and size every part (finance_rows.gd); a bill before the Assembly is said at the foot.
##
## Slice 1 READS the books; the Budget and Tax Code tabs still set them. Slice 2 puts the row editor in
## this page (one draft, one bill) and retires those two tabs. Reads the state, writes nothing; the
## two-year ranges are the budget forecast's own (budget_forecast.gd, off the frame).

signal go_requested(window_id: String)

const FinanceBooks = preload("res://src/ui/finance_books.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceStacks = preload("res://src/ui/finance_stacks.gd")
const Forecast = preload("res://src/ui/budget_forecast.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")

const PROJECTION_MONTHS := 24

var _state
var _loader
var _lead: RichTextLabel
var _ranges: HBoxContainer
var _stacks: FinanceStacks
var _revenue_box: VBoxContainer
var _spending_box: VBoxContainer
var _footer: HBoxContainer
var _footer_text: Label
var _forecast := Forecast.new()
var _book := {}
var _stamp := ""
var _dirty := true
## The groups whose folded kinds are shown (a press on the fold line).
var _open_groups := {}


func _ready() -> void:
	custom_minimum_size = Vector2(900, 520)
	var root := PanelKit.padded(self, 16, 12)
	_lead = RichTextLabel.new()
	_lead.bbcode_enabled = true
	_lead.fit_content = true
	_lead.scroll_active = false
	_lead.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_lead)
	_ranges = HBoxContainer.new()
	_ranges.add_theme_constant_override("separation", 40)
	root.add_child(_ranges)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var books := HBoxContainer.new()
	books.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	books.add_theme_constant_override("separation", 14)
	scroll.add_child(books)
	_revenue_box = VBoxContainer.new()
	_revenue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	books.add_child(_revenue_box)
	_stacks = FinanceStacks.new()
	_stacks.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	books.add_child(_stacks)
	_spending_box = VBoxContainer.new()
	_spending_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	books.add_child(_spending_box)
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 16)
	root.add_child(_footer)
	_footer_text = Label.new()
	_footer_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(_footer_text)
	var open := PanelKit.sized(Button.new())
	open.name = "OpenBill"  # i18n: ok a node name, found by tests
	open.text = Strings.t("Open the bill")
	open.pressed.connect(go_requested.emit.bind("legislature"))
	_footer.add_child(open)
	add_child(_forecast)
	_forecast.settled.connect(mark_dirty)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_forecast.setup(state, loader, PROJECTION_MONTHS)
	_stamp = ""
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or _state == null or not is_visible_in_tree():
		return
	_dirty = false
	var ns = _state.player()
	if ns == null:
		return
	# The books are read once a day and when the slot changes: a read is two copies of the state.
	var stamp := "%d|%d|%d|%s" % [_state.year, _state.month, _state.day, str(ns.tabled_bill)]
	if stamp != _stamp:
		_stamp = stamp
		_book = FinanceBooks.read(_state)
	_refresh(ns)


func _refresh(ns) -> void:
	_lead.text = _sentence()
	for child in _ranges.get_children():
		_ranges.remove_child(child)
		child.queue_free()
	var rows: Dictionary = _forecast.rows(ns)
	for entry in [["proj_growth", Strings.t("Growth, 2 years")], ["proj_unemployment", Strings.t("Unemployment, 2 years")], ["proj_debt", Strings.t("Debt, 2 years")]]:
		PanelKit.figure(_ranges, String(rows.get(entry[0], ["…", "…"])[0]), entry[1])
	var wide := UiTheme.text_scale() < 1.2
	for box in [_revenue_box, _spending_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	FinanceRows.revenue(_revenue_box, _book, _state, _loader, _open_groups, _toggle_group, wide)
	FinanceRows.spending(_spending_box, _book)
	_stacks.setup(_revenue_parts(), _spending_parts(), float(_book["deficit_bn"]))
	var tabled = FinanceBillLaw.tabled(ns)
	_footer.visible = tabled != null
	if tabled != null:
		_footer_text.text = Strings.t("A finance bill is before the Assembly: it divides on %s.") % DateText.day_month(
			int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))


## The sentence the page is for. Its figures are FIGURE-sized, the rest LEAD, as the brief asks.
func _sentence() -> String:
	var lead := int(round(UiTheme.SIZE_LEAD * UiTheme.text_scale()))
	var big := int(round(UiTheme.SIZE_FIGURE * UiTheme.text_scale()))
	var f := func(text: String) -> String: return "[font_size=%d][b]%s[/b][/font_size]" % [big, text]
	return "[font_size=%d]%s[/font_size]" % [lead, Strings.t("Revenue is %s bn and spending %s bn: the deficit is %s bn (%s %% of GDP). Debt stands at %s %% of GDP.") % [
		f.call(Num.f(float(_book["revenue_bn"]), 0)), f.call(Num.f(float(_book["spending_bn"]), 0)),
		f.call(Num.f(float(_book["deficit_bn"]), 0)), Num.f(float(_book["deficit_pct"]), 2), f.call(Num.f(float(_book["debt_pct"]), 0))]]


func _revenue_parts() -> Array:
	var parts := []
	for group in _book["groups"]:
		parts.append({"label": FinanceRows.group_name(String(group["id"])), "value": float(group["total"]), "color": FinanceRows.group_color(String(group["id"]))})
	parts.append({"label": Strings.t("Other revenue"), "value": float(_book["other_revenue_bn"]), "color": FinanceRows.MUTED})
	return parts


func _spending_parts() -> Array:
	var lines: Array = (_book["lines"] as Array).duplicate()
	lines.sort_custom(func(a, b) -> bool: return float(a["bn"]) > float(b["bn"]))
	var parts := []
	for line in lines:
		parts.append({"label": String(line["key"]), "value": float(line["bn"]), "color": FinanceRows.line_color(String(line["key"]))})
	parts.append({"label": Strings.t("Debt service"), "value": float(_book["service_bn"]), "color": FinanceRows.SERVICE})
	parts.append({"label": Strings.t("Other spending"), "value": float(_book["other_spending_bn"]), "color": FinanceRows.MUTED})
	return parts


func _toggle_group(group_id: String) -> void:
	if _open_groups.has(group_id):
		_open_groups.erase(group_id)
	else:
		_open_groups[group_id] = true
	_dirty = true


## The control this page exists to let the player press: the bill, once one is before the Assembly.
func primary_action() -> Control:
	return _footer.get_node("OpenBill") if _footer.visible else null
