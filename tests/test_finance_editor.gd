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
const FinanceLever = preload("res://src/ui/finance_lever.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const FinancePrice = preload("res://src/ui/finance_price.gd")
const Budget = preload("res://src/sim/budget.gd")
const LedgerBox = preload("res://src/ui/ledger_box.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0
var _rows_y := 0.0


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
			# The docked width: wraps (the ranges' captions) only match the game's at about this size.
			_panel.size = Vector2(1240, 820)
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
			_check_another_row_and_a_reopen_keep_the_draft()
			_check_a_refused_table_keeps_the_draft()
			_check_an_amendment_adds_to_the_tabled_bill()
			_check_a_spending_line_stops_at_zero()
			_check_the_brackets_are_priced_end_to_end()
			_check_a_state_move_reaches_an_open_editor()
			_check_the_price_cache_reprices_after_eviction()
			_check_spending_rows_are_priced()
			_check_a_tabled_row_never_opens()
			_check_discard_drops_the_draft()
			_check_the_footer_says_the_forecast()
			_check_leaving_an_untouched_off_grid_row_drafts_nothing()
			_check_a_sweep_waits_for_the_hand()
			_check_the_unset_lines_say_what_they_hold()
			_check_a_text_size_change_rebuilds_the_page()
			_check_withdraw_keeps_the_draft()
			_check_a_go_opens_the_folded_row()
			_panel._open_id = ""
			_panel._stamp = ""
			_panel._dirty = true
			_panel._process(0.0)
			_panel._forecast.state_changed()
			_panel._paint(_state.player())
		4:
			_rows_y = _revenue_row_y()
			_panel._forecast.drain()
			_panel._paint(_state.player())
		5:
			if absf(_revenue_row_y() - _rows_y) > 0.5:
				_fail("the rows moved %s px when the forecast settled (QA's B1)" % (_revenue_row_y() - _rows_y))
			if _panel._ranges.size.y < FinancesPanel.ranges_height(1.0) - 0.5:
				_fail("the ranges row is %s px, its fixed height is %s" % [_panel._ranges.size.y, FinancesPanel.ranges_height(1.0)])
			# The first draft move, "computing ..." again, then settled: the rows stay where they were.
			_panel._draft.set_value(FinanceDraft.TAX, "income", float(_state.player().tax_rates_pct["income"]) + 2.0)
			_panel._paint(_state.player())
		6:
			if absf(_revenue_row_y() - _rows_y) > 0.5:
				_fail("the rows moved %s px on the first draft move" % (_revenue_row_y() - _rows_y))
			_panel._forecast.drain()
			_panel._paint(_state.player())
		7:
			if absf(_revenue_row_y() - _rows_y) > 0.5:
				_fail("the rows moved %s px when the drafted forecast settled" % (_revenue_row_y() - _rows_y))
			_panel._draft.revert()
			_panel._paint(_state.player())
		8:
			if absf(_revenue_row_y() - _rows_y) > 0.5:
				_fail("the rows moved %s px when the draft was dropped" % (_revenue_row_y() - _rows_y))
			_panel.open_row(FinanceDraft.TAX, "vat")
			_panel._process(0.0)
		12:
			# The Go puts the cursor on that row's own lever, once the editor is laid out (two frames after the build: G3 S4).
			if _panel._editor == null or root.gui_get_focus_owner() != _panel._editor._slider:
				_fail("a Go did not put the cursor on the row's slider")
			# QA's TAKE on #443 (pass 2 T1's sibling): a tax in force at 0 % (the wealth tax) has no bar to drag, so its open
			# row keeps the editor's own slider; the wheel over it scrolls the books, never the rate.
			_panel._draft.revert()
			root.gui_release_focus()  # the Go's focus on VAT's lever holds the rebuild off
			_panel.open_row(FinanceDraft.TAX, "wealth")
			_panel._process(0.0)
		15:
			var slider: HSlider = _panel._editor._slider if _panel._editor != null else null
			if slider == null or slider is FinanceLever or not slider.is_visible_in_tree():
				_fail("premise: the wealth tax's open row shows no slider of its own")
			else:
				for down in [true, false]:
					var wheel := InputEventMouseButton.new()
					wheel.button_index = MOUSE_BUTTON_WHEEL_UP
					wheel.pressed = down
					wheel.factor = 1.0
					wheel.position = slider.get_global_rect().get_center()
					wheel.global_position = wheel.position
					root.push_input(wheel, true)
				_panel._process(0.0)
				if not _panel._draft.is_empty():
					_fail("the wheel over the wealth tax's slider drafted %d change(s)" % _panel._draft.count())
			_finish()
	return false


## The y of the first revenue row, on screen: what a click lands on.
func _revenue_row_y() -> float:
	return (_panel._revenue_box.get_child(0) as Control).global_position.y


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
	# The track is the line's whole range (the knob reads as the level); the reach is what a drag may take.
	if not is_equal_approx(line.min_value, 0.0) or not is_equal_approx(line.max_value, 30.0):
		_fail("a spending line's track is %s to %s, not 0 to 30" % [line.min_value, line.max_value])
	if not is_equal_approx(_editor()._lo, maxf(0.0, live - 5.0)) or not is_equal_approx(_editor()._hi, live + 5.0):
		_fail("a spending line's reach is %s to %s around %s" % [_editor()._lo, _editor()._hi, live])
	line.value = 30.0
	if not is_equal_approx(_panel._draft.value(FinanceDraft.SPENDING, "health"), live + 5.0):
		_fail("a drag past the reach drafts %s, not the reach's end" % _panel._draft.value(FinanceDraft.SPENDING, "health"))
	if not is_equal_approx(line.value, live + 5.0):
		_fail("the knob stays past the reach at %s" % line.value)
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
	if not _panel._foot.visible or not _panel._foot.find_child("Table", true, false).visible:
		_fail("a drafted row did not bring up the footer's one button")
	if not _panel._foot._count.text.to_lower().contains("1 change"):
		_fail("the rail does not count the row: '%s'" % _panel._foot._count.text)
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
	var table: Button = _panel._foot.find_child("Table", true, false)
	if not table.disabled:
		_fail("the button is live while another bill holds the slot")
	if not _panel._foot._text.text.contains("Another bill holds"):
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
	var table: Button = _panel._foot.find_child("Table", true, false)
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
	if not _panel._foot.find_child("OpenBill", true, false).visible or not _panel._foot.find_child("Withdraw", true, false).visible:
		_fail("the footer does not offer the bill's sheet and its withdrawal")
	_panel._foot.find_child("Withdraw", true, false).pressed.emit()
	if not ns.tabled_bill.is_empty():
		_fail("Withdraw did not take the bill back")
	_panel._process(0.0)
	if _panel._foot._changes.visible or _panel._foot._withdraw.visible:
		_fail("the rail lists changes or a bill with nothing drafted and nothing tabled")


## Opening another row rebuilds the page: the draft rides it, and a reopened row shows the draft against today.
func _check_another_row_and_a_reopen_keep_the_draft() -> void:
	var vat := FinanceRows.row_id(FinanceDraft.TAX, "vat")
	_open(vat)
	var slider: HSlider = _editor()._slider
	var live := float(_state.player().tax_rates_pct["vat"])
	slider.value = live + slider.step
	_open(FinanceRows.row_id(FinanceDraft.TAX, "income"))
	if _panel._draft.count() != 1 or not (_panel._ctx["cells"][vat][0] as Label).text.contains(" to "):
		_fail("opening another row lost the draft or its figure: %d rows" % _panel._draft.count())
	_open(vat)
	if not is_equal_approx(_editor()._slider.value, live + slider.step):
		_fail("a reopened row's slider shows %s, not the draft %s" % [_editor()._slider.value, live + slider.step])
	if not _editor().get_node("Now").text.contains(LedgerBox.text(live, TaxLibrary.step_decimals(_state.player(), "vat"))):
		_fail("a reopened row's 'Now' is not today's rate: '%s'" % _editor().get_node("Now").text)
	_panel._draft.revert()


## A refusal at the press keeps the draft on the rows and still answers (committed, not tabled).
func _check_a_refused_table_keeps_the_draft() -> void:
	var ns = _state.player()
	ns.tabled_bill = {"law_id": "some_law", "vote_year": 2026, "vote_month": 1, "vote_day": 31}
	_panel._draft.set_value(FinanceDraft.TAX, "vat", float(ns.tax_rates_pct["vat"]) + 2.0)
	var heard := []
	_panel.committed.connect(func(_before: Dictionary, tabling: Dictionary) -> void: heard.append(tabling), CONNECT_ONE_SHOT)
	_panel._on_table()
	if heard.size() != 1 or bool(heard[0].get("tabled", true)):
		_fail("a refused table did not answer as refused: %s" % [heard])
	if _panel._draft.count() != 1:
		_fail("a refused table cleared the draft")
	ns.tabled_bill = {}
	_panel._draft.revert()


## A bill already before the Assembly takes the next draft as an amendment: both rows end up in it.
func _check_an_amendment_adds_to_the_tabled_bill() -> void:
	var ns = _state.player()
	_panel._draft.set_value(FinanceDraft.TAX, "vat", float(ns.tax_rates_pct["vat"]) + 2.0)
	_panel._on_table()
	_panel._draft.set_value(FinanceDraft.TAX, "income", float(ns.tax_rates_pct["income"]) + 1.0)
	_panel._dirty = true
	_panel._process(0.0)
	if _panel._foot.find_child("Table", true, false).text != Strings.t("Add to the bill"):
		_fail("the button does not say it adds to the bill: '%s'" % _panel._foot.find_child("Table", true, false).text)
	_panel._foot.find_child("Table", true, false).pressed.emit()
	var rows: Dictionary = ns.tabled_bill.get("finance", {}).get("tax_rates_pct", {})
	if not rows.has("vat") or not rows.has("income"):
		_fail("the amendment is not in the bill: %s" % [ns.tabled_bill])
	if not _panel._draft.is_empty():
		_fail("the draft stands after an amendment")
	_panel._foot.find_child("Withdraw", true, false).pressed.emit()
	_panel._process(0.0)


## A line near zero stops at zero, never below it.
func _check_a_spending_line_stops_at_zero() -> void:
	_open(FinanceRows.row_id(FinanceDraft.SPENDING, "defence"))
	if _editor()._slider.min_value != 0.0:
		_fail("a spending line's floor is %s" % _editor()._slider.min_value)
	var box: LineEdit = _editor()._box
	box.text = "-1"
	box.text_submitted.emit(box.text)
	if _panel._draft.value(FinanceDraft.SPENDING, "defence") != 0.0:
		_fail("a typed -1 drafts %s" % _panel._draft.value(FinanceDraft.SPENDING, "defence"))
	_panel._draft.revert()


## The brackets alone are a priced draft: the effect line, the footer's count.
func _check_the_brackets_are_priced_end_to_end() -> void:
	_open(FinanceRows.row_id(FinanceDraft.TAX, "income"))
	var box: LineEdit = _editor().find_child("BracketsBox", true, false)
	box.text = str(float(_state.player().tax_progressivity) + 0.3)
	box.text_submitted.emit(box.text)
	_panel._process(0.0)
	if _panel._draft.count() != 1 or _editor().get_node("Effect").text == "":
		_fail("a brackets-only draft has no effect line: %d rows '%s'" % [_panel._draft.count(), _editor().get_node("Effect").text])
	if not _panel._foot._count.text.to_lower().contains("1 change"):
		_fail("the rail does not count the brackets: '%s'" % _panel._foot._count.text)
	_panel._draft.revert()


## A law moving a rate the same day: the sweep's mark_dirty re-reads the books and the open editor.
func _check_a_state_move_reaches_an_open_editor() -> void:
	var ns = _state.player()
	var vat := FinanceRows.row_id(FinanceDraft.TAX, "vat")
	_open(vat)
	var live := float(ns.tax_rates_pct["vat"])
	ns.tax_rates_pct["vat"] = live + 2.0
	_panel.mark_dirty()
	_panel._process(0.0)
	var places := TaxLibrary.step_decimals(ns, "vat")
	if not _editor().get_node("Now").text.contains(LedgerBox.text(live + 2.0, places)):
		_fail("after a same-day move the editor still says '%s'" % _editor().get_node("Now").text)
	if not (_panel._ctx["cells"][vat][0] as Label).text.contains(LedgerBox.text(live + 2.0, places)):
		_fail("after a same-day move the row still says '%s'" % (_panel._ctx["cells"][vat][0] as Label).text)
	ns.tax_rates_pct["vat"] = live
	_panel.mark_dirty()
	_panel._process(0.0)


## The price cache keeps four: a fifth pushes the first out, and asking for it again prices it afresh.
func _check_the_price_cache_reprices_after_eviction() -> void:
	var price := FinancePrice.new()
	price.setup(_state)
	var vat := float(_state.player().tax_rates_pct["vat"])
	var pendings := []
	# One more than the cache keeps: the first is evicted, and a full cache must not answer for it (QA's K3 on #368).
	for i in range(1, FinancePrice.KEEP + 2):
		pendings.append({FinanceDraft.TAX: {"vat": vat + float(i) * 0.1}})
		# Each answer is its own pending's, the one asked of a FULL cache included (a full cache must evict, not answer).
		var asked: Dictionary = price.after(pendings[i - 1])
		if not is_equal_approx(float(asked["deficit_pct_gdp"]), float(Budget.preview(_state, pendings[i - 1])["deficit_pct_gdp"])):
			_fail("pending %d is priced as another pending (a full cache answered for it)" % i)
	var again: Dictionary = price.after(pendings[0])
	var fresh: Dictionary = Budget.preview(_state, pendings[0])
	if not is_equal_approx(float(again["deficit_pct_gdp"]), float(fresh["deficit_pct_gdp"])):
		_fail("an evicted pending is not priced afresh")


## A drafted spending row is priced (the old Budget priced the whole five-line dict): Health 1.5 points of GDP
## is 1.5 % of GDP a year.
func _check_spending_rows_are_priced() -> void:
	var ns = _state.player()
	_panel._draft.set_value(FinanceDraft.SPENDING, "health", float(ns.spending_pct_gdp["health"]) + 1.5)
	var moves: Dictionary = _panel._price.moves(_panel._draft.pending())
	var want: float = 1.5 * float(ns.gdp_eur_bn) / 100.0
	if absf(float(moves["spending_bn"]) - want) > 1.0:
		_fail("Health +1.5 points moves spending by %s bn, GDP says %s" % [moves["spending_bn"], want])
	if float(moves["balance_bn"]) >= 0.0:
		_fail("a rise in spending books a gain: %s" % moves["balance_bn"])
	_panel._draft.revert()


## A row at vote opens no editor, whoever asks (the goal panel's Go included).
func _check_a_tabled_row_never_opens() -> void:
	var ns = _state.player()
	FinanceBill_table(ns, {"tax_rates_pct": {"vat": 1.0}, "spending_pct_gdp": {"health": 0.5}})
	for pair in [[FinanceDraft.TAX, "vat"], [FinanceDraft.SPENDING, "health"]]:
		_panel.open_row(pair[0], pair[1])
		_panel._process(0.0)
		if _editor() != null:
			_fail("a row at vote (%s) opened an editor" % pair[1])
	# QA's T4 on #363: a Go on a locked row leaves nothing behind, so a withdrawal opens and focuses nothing.
	if _panel._open_id != "" or _panel._focus_wanted:
		_fail("a Go on a row at vote left _open_id '%s' / _focus_wanted %s behind" % [_panel._open_id, _panel._focus_wanted])
	ns.tabled_bill = {}
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)
	if _editor() != null:
		_fail("a withdrawn bill reopened the row a Go had asked for while it was locked")


func FinanceBill_table(_ns, bill: Dictionary) -> void:
	var tabling: Dictionary = preload("res://src/sim/finance_bill.gd").table(_state, _loader, bill)
	if not bool(tabling.get("tabled", false)):
		_fail("the premise bill was refused: %s" % [tabling])
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)


func _check_discard_drops_the_draft() -> void:
	_panel._draft.set_value(FinanceDraft.TAX, "vat", float(_state.player().tax_rates_pct["vat"]) + 2.0)
	_panel._dirty = true
	_panel._process(0.0)
	var discard: Button = _panel._foot.find_child("Discard", true, false)
	if not discard.visible:
		_fail("a draft has no way to be dropped")
	discard.pressed.emit()
	_panel._process(0.0)
	if not _panel._draft.is_empty() or _panel._foot._changes.visible:
		_fail("Discard left the draft or the rail's changes up")


## The price before he tables: the tray's bar is the very division FinanceRead.draft meets (its legend prints the seats;
## the sentence no longer repeats them, #429 pass 2 T10).
func _check_the_footer_says_the_forecast() -> void:
	var ns = _state.player()
	_panel._draft.set_value(FinanceDraft.TAX, "vat", float(ns.tax_rates_pct["vat"]) + 2.0)
	_panel._dirty = true
	_panel._process(0.0)
	var vote: Dictionary = preload("res://src/sim/finance_read.gd").draft(_state, _loader, _panel._draft.bill())["vote"]
	var legend := ""
	for label in _panel._foot._vote_box.find_children("*", "Label", true, false):
		legend += (label as Label).text + " "
	for seats in [int(vote["yes_seats"]), int(vote["no_seats"]), int(vote["abstain_seats"])]:
		if not legend.contains(str(seats)):
			_fail("the tray's bar does not print %d seats: '%s'" % [seats, legend])
	_panel._draft.revert()
	_panel._dirty = true
	_panel._process(0.0)


## Focus in and out of an untouched row whose figure the box rounds drafts nothing and rewrites no rate.
func _check_leaving_an_untouched_off_grid_row_drafts_nothing() -> void:
	var ns = _state.player()
	var was := float(ns.tax_rates_pct["income"])
	ns.tax_rates_pct["income"] = 21.4567
	_panel.mark_dirty()
	_panel._process(0.0)
	_open(FinanceRows.row_id(FinanceDraft.TAX, "income"))
	var box: LineEdit = _editor()._box
	box.focus_exited.emit()
	if not _panel._draft.is_empty() or _panel._draft.bill() != {}:
		_fail("leaving an untouched off-grid row drafted it: %s" % [_panel._draft.bill()])
	ns.tax_rates_pct["income"] = was
	_panel.mark_dirty()
	_panel._process(0.0)


## A sweep while the player's hand is on the open row repaints and does not rebuild; once the hand leaves, it does.
func _check_a_sweep_waits_for_the_hand() -> void:
	_open(FinanceRows.row_id(FinanceDraft.TAX, "vat"))
	var slider: HSlider = _editor()._slider
	slider.grab_focus()
	if root.gui_get_focus_owner() != slider:
		_fail("premise: the slider did not take the focus")
		return
	var first := slider.get_instance_id()
	_panel.mark_dirty()
	_panel._process(0.0)
	if _editor() == null or _editor()._slider.get_instance_id() != first:
		_fail("a sweep rebuilt the slider under the player's hand")
	slider.release_focus()
	_panel._process(0.0)
	if _editor()._slider.get_instance_id() == first:
		_fail("the rebuild never came once the hand left")


## The two unset lines say what the model keeps in them, in the sim's own parts.
func _check_the_unset_lines_say_what_they_hold() -> void:
	var tips := []
	for node in _panel._spending_box.find_children("*", "HBoxContainer", true, false) + _panel._revenue_box.find_children("*", "HBoxContainer", true, false):
		if (node as Control).tooltip_text != "":
			tips.append((node as Control).tooltip_text)
	var said := 0
	for tip in tips:
		if String(tip).contains("not split"):
			said += 1
	if said != 2:
		_fail("the two unset lines do not both say what is not split: %s" % [tips])


## A text-size change in Settings rebuilds the page by itself (QA's B2 on #363), and back at 100 % it
## goes back to its build. (The 130 % layout, where a spending figure became the row's hover, left
## with that size.)
func _check_a_text_size_change_rebuilds_the_page() -> void:
	var UiTheme = preload("res://src/ui/ui_theme.gd")
	UiTheme.set_text_scale(1.15)
	# No manual dirty mark.
	_panel._process(0.0)
	if not String(_panel._lead.text).contains("font_size=%d" % int(round(UiTheme.SIZE_LEAD * 1.15))):
		_fail("a text-size change did not rebuild the page at 115 %%: lead '%s'" % _panel._lead.text)
	UiTheme.set_text_scale(1.0)
	_panel._process(0.0)
	if not String(_panel._lead.text).contains("font_size=%d" % UiTheme.SIZE_LEAD):
		_fail("back at 100 %% the page kept its 115 %% build: lead '%s'" % _panel._lead.text)


## C3 on #363: Withdraw is there whenever a bill is at vote, and withdrawing keeps what the player is drafting.
func _check_withdraw_keeps_the_draft() -> void:
	var ns = _state.player()
	FinanceBill_table(ns, {"tax_rates_pct": {"vat": 1.0}})
	_panel._draft.set_value(FinanceDraft.TAX, "income", float(ns.tax_rates_pct["income"]) + 1.0)
	_panel._dirty = true
	_panel._process(0.0)
	if not _panel._foot.find_child("Withdraw", true, false).visible or not _panel._foot.find_child("Table", true, false).visible:
		_fail("with a draft and a bill at vote the footer must offer both Withdraw and the draft's verb")
	_panel._foot.find_child("Withdraw", true, false).pressed.emit()
	if not ns.tabled_bill.is_empty():
		_fail("Withdraw did not take the bill back with a draft standing")
	if _panel._draft.count() != 1:
		_fail("withdrawing the bill dropped the draft: %d rows" % _panel._draft.count())
	_panel._process(0.0)
	if not _panel._foot.find_child("Table", true, false).visible or _panel._foot.find_child("Withdraw", true, false).visible:
		_fail("after the withdrawal the footer should offer the draft's verb alone")
	_panel._draft.revert()
	_panel._dirty = true
	_panel._process(0.0)


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
