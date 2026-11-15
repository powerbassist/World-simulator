extends PanelContainer

## The Finances page -- V5.3 screen 4, direction A ("in and out, to scale", the author's pick). The one
## sentence the screen exists to say (what comes in, what goes out, the gap, the debt), the three
## two-year ranges, and under them the books drawn to one scale: revenue by base on the left, spending
## by line on the right, the deficit the spending stack's overhang (finance_stacks.gd). The rows beside
## the stacks name and size every part (finance_rows.gd); a bill before the Assembly is said at the foot.
##
## Slice 2 makes the rows the controls: a row's name opens its editor (finance_editor.gd) under it, every
## moved row is part of ONE draft (finance_draft.gd), and the footer (finance_foot.gd) tables that draft as the
## month's finance bill. The Budget and Tax Code tabs are gone. The page reads the state and writes nothing
## but that one command; the two-year ranges are the budget forecast's own (budget_forecast.gd, off the frame).
##
## WHEN IT REBUILDS: the books are rebuilt when their structure changes (a day, a bill, a row opened, a fold),
## never on a draft move, which only repaints the figures in place -- a rebuild would drop the slider the
## player is holding and the box they are typing in.

signal go_requested(window_id: String)
## The fiscal command landed (a bill tabled, added to, or withdrawn): main's acknowledgment and effect
## baseline, as the Budget's and the Tax Code's Commit had (Trends.snapshot_now taken before it).
signal committed(before: Dictionary, tabling: Dictionary)

const FinanceBooks = preload("res://src/ui/finance_books.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceStacks = preload("res://src/ui/finance_stacks.gd")
const Forecast = preload("res://src/ui/budget_forecast.gd")
const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceEditor = preload("res://src/ui/finance_editor.gd")
const FinanceFoot = preload("res://src/ui/finance_foot.gd")
const FinancePrice = preload("res://src/ui/finance_price.gd")
const Trends = preload("res://src/ui/trends.gd")
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
var _foot: FinanceFoot
var _scroll: ScrollContainer
var _with: Label
var _draft := FinanceDraft.new()
var _price := FinancePrice.new()
## The row whose editor is open ("channel:key", "" none), the cells the rows kept to repaint in place, and
## the editor built for the open row.
var _open_id := ""
var _ctx := {}
var _editor: FinanceEditor
var _focus_wanted := false
var _paint_due := true
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
	_with = PanelKit.plain_line(root, "", PanelKit.Tone.DIM)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	var books := HBoxContainer.new()
	books.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	books.add_theme_constant_override("separation", 14)
	_scroll.add_child(books)
	_revenue_box = VBoxContainer.new()
	_revenue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	books.add_child(_revenue_box)
	_stacks = FinanceStacks.new()
	_stacks.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	books.add_child(_stacks)
	_spending_box = VBoxContainer.new()
	_spending_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	books.add_child(_spending_box)
	_foot = FinanceFoot.new()
	root.add_child(_foot)
	_foot.table_pressed.connect(_on_table)
	_foot.open_pressed.connect(go_requested.emit.bind("legislature"))
	_foot.withdraw_pressed.connect(_on_withdraw)
	_foot.discard_pressed.connect(_on_discard)
	add_child(_forecast)
	_forecast.settled.connect(func() -> void: _paint_due = true)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_forecast.setup(state, loader, PROJECTION_MONTHS)
	_draft.setup(state)
	_price.setup(state)
	_open_id = ""
	_stamp = ""
	_dirty = true


func mark_dirty() -> void:
	_price.reset()
	_forecast.state_changed()
	# A law, an event or a summit moved the register: the books are read again, not kept for the day.
	_stamp = ""
	_dirty = true


func _process(_delta: float) -> void:
	if _state == null or not is_visible_in_tree() or (not _dirty and not _paint_due):
		return
	var ns = _state.player()
	if ns == null:
		return
	# A hand on the open row's slider or box keeps its row: the books are rebuilt when it leaves, never under it
	# (a sweep at speed 3 would free the slider mid-drag and the box mid-typing).
	if not _dirty or _editor_busy():
		_paint(ns)
		return
	_dirty = false
	# The books are read once a day and when the slot changes: a read is two copies of the state.
	var stamp := "%d|%d|%d|%s" % [_state.year, _state.month, _state.day, str(ns.tabled_bill)]
	if stamp != _stamp:
		_stamp = stamp
		_book = FinanceBooks.read(_state)
	_refresh(ns)


func _refresh(ns) -> void:
	_lead.text = _sentence()
	var wide := UiTheme.text_scale() < 1.2
	for box in [_revenue_box, _spending_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_editor = null
	_ctx = {"draft": _draft, "open": _open_id, "on_open": _on_open, "tabled": _tabled_rows(ns), "cells": {}, "editor": _make_editor, "wide": wide,
		"parts": FinanceRead.other_parts(ns)}
	FinanceRows.revenue(_revenue_box, _book, _state, _loader, _open_groups, _toggle_group, wide, _ctx)
	FinanceRows.spending(_spending_box, _book, _ctx)
	_stacks.setup(_revenue_parts(), _spending_parts(), float(_book["deficit_bn"]))
	_paint(ns)
	if _focus_wanted and _editor != null:
		_focus_wanted = false
		_focus_editor.call_deferred(_editor)


## The Go's landing, a frame after the build: the editor may have been rebuilt or closed since (a stale one is skipped).
func _focus_editor(editor: FinanceEditor) -> void:
	if is_instance_valid(editor) and editor.is_inside_tree() and _scroll.is_ancestor_of(editor):
		_scroll.ensure_control_visible(editor)
		editor.focus_lever()


## What changes without a rebuild: the rows' figures, the footer, the line about the draft and the ranges.
func _paint(ns) -> void:
	# Before the first build there are no rows to repaint: the rebuild (and its own paint) comes first.
	if _ctx.is_empty():
		_dirty = true
		return
	_paint_due = false
	FinanceRows.paint_rates(_ctx)
	_foot.refresh(_state, _loader, _draft, _price)
	var drafted: bool = not _draft.is_empty()
	_forecast.want(_draft.pending(), drafted)
	if drafted:
		var after: Dictionary = _price.after(_draft.pending())
		_with.text = Strings.t("With your changes: deficit %s bn (%s %% of GDP).") % [
			Num.f(float(after["deficit_pct_gdp"]) * float(after["gdp_eur_bn"]) / 100.0, 0), Num.f(float(after["deficit_pct_gdp"]), 2)]
	else:
		_with.text = ""
	for child in _ranges.get_children():
		_ranges.remove_child(child)
		child.queue_free()
	var rows: Dictionary = _forecast.rows(ns)
	for entry in [["proj_growth", Strings.t("Growth, 2 years")], ["proj_unemployment", Strings.t("Unemployment, 2 years")], ["proj_debt", Strings.t("Debt, 2 years")]]:
		var pair: Array = rows.get(entry[0], ["…", "…"])
		PanelKit.figure(_ranges, String(pair[1] if drafted else pair[0]), Strings.t("%s, with your changes") % entry[1] if drafted else entry[1])


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


## Whether the player's hand is on the open row: the focus is inside its editor.
func _editor_busy() -> bool:
	if _editor == null or not is_instance_valid(_editor) or not is_inside_tree():
		return false
	var held := get_viewport().gui_get_focus_owner()
	return held != null and _editor.is_ancestor_of(held)


## The page's ONE draft: the Budget tab's levers read and write it too (no second pending set).
func shared_draft() -> FinanceDraft:
	return _draft


func _on_discard() -> void:
	_draft.revert()
	_open_id = ""
	_stamp = ""
	_dirty = true


## A draft move: the figures repaint in place, the rows stay where they are.
func _on_moved() -> void:
	_paint_due = true


func _make_editor(channel: String, key: String) -> Control:
	var editor := FinanceEditor.new()
	editor.setup(_state, _loader, _draft, _price, channel, key)
	editor.moved.connect(_on_moved)
	_editor = editor
	return editor


## A row's name pressed: its editor opens under it, or closes if it was the open one.
func _on_open(id: String) -> void:
	_open_id = "" if _open_id == id else id
	_dirty = true


## Where a goal panel's Go lands: that row, open, its slider focused. A folded kind opens its group.
func open_row(channel: String, key: String) -> void:
	if channel == FinanceDraft.TAX and _state != null and _state.player() != null and _state.player().tax_library.has(key):
		_open_groups[String(_state.player().tax_library[key]["group"])] = true
	var id := FinanceRows.row_id(channel, key)
	# A row at vote opens no editor: leave nothing behind that would open it, and take the focus, once it is withdrawn.
	var locked: bool = _state != null and _state.player() != null and _tabled_rows(_state.player()).has(id)
	_open_id = "" if locked else id
	_focus_wanted = not locked
	_dirty = true


## The tabled bill's rows as {row id: delta}: those rows are at vote, and locked.
func _tabled_rows(ns) -> Dictionary:
	var out := {}
	var finance: Dictionary = ns.tabled_bill.get("finance", {})
	for channel in [FinanceDraft.TAX, FinanceDraft.SPENDING]:
		for key in finance.get(channel, {}):
			out[FinanceRows.row_id(channel, String(key))] = float(finance[channel][key])
	return out


func _on_table() -> void:
	var before := Trends.snapshot_now(_state)
	var tabling := FinanceBill.table(_state, _loader, _draft.bill())
	# A refusal keeps the draft on the rows; a tabled bill clears it.
	if bool(tabling.get("tabled", false)):
		_draft.revert()
		_open_id = ""
		_stamp = ""
		_dirty = true
	committed.emit(before, tabling)


func _on_withdraw() -> void:
	var before := Trends.snapshot_now(_state)
	var result := FinanceBill.withdraw(_state)
	_stamp = ""
	_dirty = true
	committed.emit(before, result)


## The control this page exists to let the player press: the draft's verb, else the bill's sheet.
func primary_action() -> Control:
	return _foot.primary_action()
