extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_editor.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4, Finances slice 2: the rows are the controls. Pinned: opening a row drafts nothing (for every
## row of the four playable nations, so an off-grid rate is never snapped); the slider steps by the SIM's step
## and stands on the kind's range, a spending line on its reach either side of today; a drag writes the draft and
## repaints the figures in place WITHOUT rebuilding the slider that is being held; a typed rate is exact and
## held to the range; a word in the box is put back; the effect line is the strip's own figure; the footer's one
## button tables the draft, is never a dead verb (a refusal disables it and says why), and a tabled row is locked
## "at vote" until the bill is withdrawn; the brackets are a lever of the income row; a Go from the goal panel
## opens its row and its folded group.

const GameState = preload("res://src/core/game_state.gd")
const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	Strings.set_language("en")
	_panel = FinancesPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_panel.show()
			for nation in ["FRA", "GBR", "DEU", "POL"]:
				_check_opening_every_row_drafts_nothing(nation)
			_state = GameState.new_game(_loader, "FRA")
			_panel.setup(_state, _loader)
		3:
			_check_the_slider_grid_and_range()
			_check_a_drag_repaints_in_place()
			_check_a_typed_rate_is_exact()
			_check_a_refused_entry_puts_the_figure_back()
			_check_the_effect_line_is_the_strips_figure()
			_check_the_brackets_are_a_lever_of_income()
			_check_a_refusal_disables_the_button_and_says_why()
			_check_table_locks_the_rows_and_withdraw_frees_them()
			_check_a_go_opens_the_folded_row()
			_finish()
	return false


func _open(id: String) -> void:
	_panel._open_id = id
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)


func _editor():
	return _panel._editor


func _check_opening_every_row_drafts_nothing(nation: String) -> void:
	var state = GameState.new_game(_loader, nation)
	_panel.setup(state, _loader)
	_panel._process(0.0)
	var ids: Array = _panel._ctx["cells"].keys()
	# A folded kind has no row until its group opens: open them all so every kind is a row.
	for gid in FinanceRows.GROUP_NAME:
		_panel._open_groups[gid] = true
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)
	ids = _panel._ctx["cells"].keys()
	if ids.size() < 6:
		_fail("%s: only %d editable rows" % [nation, ids.size()])
	for id in ids:
		_open(String(id))
		if _editor() == null:
			_fail("%s: opening %s built no editor" % [nation, id])
		if not _panel._draft.is_empty() or _panel._draft.bill() != {}:
			_fail("%s: opening %s drafted something: %s" % [nation, id, _panel._draft.bill()])
	_panel._open_groups.clear()


func _check_the_slider_grid_and_range() -> void:
	var ns = _state.player()
	for gid in FinanceRows.GROUP_NAME:
		_panel._open_groups[gid] = true
	for kind in ns.tax_rates_pct:
		_open(FinanceRows.row_id(FinanceDraft.TAX, String(kind)))
		var slider: HSlider = _editor()._slider
		if not is_equal_approx(slider.step, TaxLibrary.step_pct(ns, String(kind))):
			_fail("%s's slider steps by %s, the sim's step is %s" % [kind, slider.step, TaxLibrary.step_pct(ns, String(kind))])
		var span: Array = ns.tax_library[kind]["rate_range_pct"]
		if not is_equal_approx(slider.min_value, float(span[0])) or not is_equal_approx(slider.max_value, float(span[1])):
			_fail("%s's slider stands on %s to %s, the range is %s" % [kind, slider.min_value, slider.max_value, span])
	_open(FinanceRows.row_id(FinanceDraft.SPENDING, "health"))
	var live := float(ns.spending_pct_gdp["health"])
	var line: HSlider = _editor()._slider
	if not is_equal_approx(line.min_value, maxf(0.0, live - 5.0)) or not is_equal_approx(line.max_value, live + 5.0):
		_fail("a spending line's reach is %s to %s around %s" % [line.min_value, line.max_value, live])
	_panel._open_groups.clear()
	_panel._draft.revert()


func _check_a_drag_repaints_in_place() -> void:
	var id := FinanceRows.row_id(FinanceDraft.TAX, "vat")
	_open(id)
	var slider: HSlider = _editor()._slider
	var first := slider.get_instance_id()
	var live := float(_state.player().tax_rates_pct["vat"])
	slider.value = live + slider.step
	_panel._process(0.0)
	slider.value = live + 2.0 * slider.step
	_panel._process(0.0)
	if _editor()._slider.get_instance_id() != first:
		_fail("a drag rebuilt the slider that is being held")
	if not is_equal_approx(_panel._draft.value(FinanceDraft.TAX, "vat"), live + 2.0 * slider.step):
		_fail("the drag did not reach the draft")
	var cell: Label = _panel._ctx["cells"][id][0]
	if not cell.text.contains(" to "):
		_fail("the row's figure does not show the move: '%s'" % cell.text)
	if not _panel._foot.visible or not _panel._foot.get_node("Table").visible:
		_fail("a drafted row did not bring up the footer's one button")
	if not _panel._foot._text.text.contains("1 change"):
		_fail("the footer does not count the row: '%s'" % _panel._foot._text.text)
	_panel._draft.revert()
	_panel._paint(_state.player())


func _check_a_typed_rate_is_exact() -> void:
	var ns = _state.player()
	_open(FinanceRows.row_id(FinanceDraft.TAX, "income"))
	var box: LineEdit = _editor()._box
	box.text = "22,35"
	box.text_submitted.emit(box.text)
	if absf(_panel._draft.value(FinanceDraft.TAX, "income") - 22.35) > 1e-9:
		_fail("a typed 22,35 drafts %s" % _panel._draft.value(FinanceDraft.TAX, "income"))
	if _panel._draft.bill().get("tax_rates_pct", {}).keys() != ["income"]:
		_fail("a typed rate tables more than its own row: %s" % [_panel._draft.bill()])
	box.text = "9999"
	box.text_submitted.emit(box.text)
	if _panel._draft.value(FinanceDraft.TAX, "income") != float(ns.tax_library["income"]["rate_range_pct"][1]):
		_fail("a typed rate past the ceiling drafts %s" % _panel._draft.value(FinanceDraft.TAX, "income"))
	_panel._draft.revert()


func _check_a_refused_entry_puts_the_figure_back() -> void:
	_open(FinanceRows.row_id(FinanceDraft.TAX, "vat"))
	var box: LineEdit = _editor()._box
	var shown := box.text
	box.text = "lots"
	box.text_submitted.emit(box.text)
	if box.text != shown or not _panel._draft.is_empty():
		_fail("a word in the box drafted VAT or left '%s' for '%s'" % [box.text, shown])


func _check_the_effect_line_is_the_strips_figure() -> void:
	_open(FinanceRows.row_id(FinanceDraft.TAX, "vat"))
	var slider: HSlider = _editor()._slider
	slider.value = float(_state.player().tax_rates_pct["vat"]) + 2.0 * slider.step
	var gain: float = _panel._price.balance_bn(_panel._draft.pending())
	var want := EffectsStrip.money_text(gain)
	if not _editor().get_node("Effect").text.contains(want):
		_fail("the effect line says '%s', the strip's figure is %s" % [_editor().get_node("Effect").text, want])
	if gain <= 0.0:
		_fail("raising VAT does not book a gain (%s)" % gain)
	_panel._draft.revert()


func _check_the_brackets_are_a_lever_of_income() -> void:
	_open(FinanceRows.row_id(FinanceDraft.TAX, "vat"))
	if _editor().get_node_or_null("BracketsBox") != null:
		_fail("the brackets sit on VAT's row")
	_open(FinanceRows.row_id(FinanceDraft.TAX, "income"))
	var box: LineEdit = _editor().find_child("BracketsBox", true, false)
	if box == null:
		_fail("the income row has no brackets lever")
		return
	var live := float(_state.player().tax_progressivity)
	box.text = str(live + 0.2)
	box.text_submitted.emit(box.text)
	if not _panel._draft.bill().has(FinanceDraft.BRACKETS):
		_fail("the brackets lever did not draft: %s" % [_panel._draft.bill()])
	_panel._draft.revert()


func _check_a_refusal_disables_the_button_and_says_why() -> void:
	var ns = _state.player()
	ns.tabled_bill = {"law_id": "some_law", "vote_year": 2026, "vote_month": 1, "vote_day": 31}
	_panel._stamp = ""
	_panel._draft.set_value(FinanceDraft.TAX, "vat", float(ns.tax_rates_pct["vat"]) + 2.0)
	_panel._dirty = true
	_panel._process(0.0)
	var table: Button = _panel._foot.get_node("Table")
	if not table.disabled:
		_fail("the button is live while another bill holds the slot")
	if not _panel._foot._text.text.contains("queue it"):
		_fail("the refusal is not said in words: '%s'" % _panel._foot._text.text)
	ns.tabled_bill = {}
	_panel._draft.revert()
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)


func _check_table_locks_the_rows_and_withdraw_frees_them() -> void:
	var ns = _state.player()
	var heard := []
	_panel.committed.connect(func(_before: Dictionary, tabling: Dictionary) -> void: heard.append(tabling), CONNECT_ONE_SHOT)
	_panel._draft.set_value(FinanceDraft.TAX, "vat", float(ns.tax_rates_pct["vat"]) + 2.0)
	_panel._dirty = true
	_panel._process(0.0)
	var table: Button = _panel._foot.get_node("Table")
	if table.disabled:
		_fail("the button is dead with a legal draft")
	table.pressed.emit()
	if heard.is_empty() or not bool(heard[0].get("tabled", false)):
		_fail("the button did not table the draft: %s" % [heard])
	if ns.tabled_bill.is_empty() or not _panel._draft.is_empty():
		_fail("after tabling the bill is not held or the draft stands")
	_panel._process(0.0)
	var id := FinanceRows.row_id(FinanceDraft.TAX, "vat")
	var button_found := false
	for node in _panel._revenue_box.find_children("*", "Button", true, false):
		if (node as Button).toggle_mode and (node as Button).text == Strings.row_name("taxes", ns.tax_library["vat"]):
			button_found = true
	if button_found:
		_fail("a row at vote still opens an editor")
	if not (_panel._ctx["cells"][id][0] as Label).text.contains(" to "):
		_fail("a row at vote does not show where it is going")
	if not _panel._foot.get_node("OpenBill").visible or not _panel._foot.get_node("Withdraw").visible:
		_fail("the footer does not offer the bill's sheet and its withdrawal")
	_panel._foot.get_node("Withdraw").pressed.emit()
	if not ns.tabled_bill.is_empty():
		_fail("Withdraw did not take the bill back")
	_panel._process(0.0)
	if _panel._foot.visible:
		_fail("the footer stays up with nothing drafted and nothing tabled")


func _check_a_go_opens_the_folded_row() -> void:
	var ns = _state.player()
	var folded := ""
	var book: Dictionary = _panel._book
	for group in book["groups"]:
		if not (group["folded"] as Array).is_empty():
			folded = String(group["folded"][0]["id"])
			break
	if folded == "":
		return
	_panel._open_groups.clear()
	_panel.open_row(FinanceDraft.TAX, folded)
	_panel._process(0.0)
	if _editor() == null or _editor().key != folded:
		_fail("a Go to the folded kind %s opened no editor" % folded)
	if ns.tax_library[folded]["group"] == "" or not _panel._open_groups.has(String(ns.tax_library[folded]["group"])):
		_fail("a Go to a folded kind did not open its group")


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_finance_editor: all checks passed")
		quit(0)
	else:
		print("test_finance_editor: %d failure(s)" % _failures.size())
		quit(1)
