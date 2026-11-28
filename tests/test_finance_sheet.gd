extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_sheet.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4, Finances slice 3: the bill's sheet BEFORE it is tabled. Pinned: the footer offers the sheet only
## while rows are drafted; the sheet lists the CHANGED rows of the one draft and none other; its totals are the
## footer's own (FinancePrice) and its seats are FinanceRead.draft's division; the forced passage is offered
## where the formation rule allows it (France) and nowhere else (Britain), and forcing writes a forced bill and
## says the censure instead of a vote; the sheet's Table is the footer's command; Withdraw is there only while a
## bill is at vote; closing the sheet keeps the draft; a draft move while it is open repaints it.

const GameState = preload("res://src/core/game_state.gd")
const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinancePrice = preload("res://src/ui/finance_price.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const Budget = preload("res://src/sim/budget.gd")
const ChartWaterfall = preload("res://src/ui/chart_waterfall.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Government = preload("res://src/sim/government.gd")
const Labels = preload("res://src/ui/labels.gd")
const Strings = preload("res://src/ui/strings.gd")
const BillVerbs = preload("res://src/ui/bill_verbs.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Tones = preload("res://src/ui/ui_theme.gd")

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
			_panel.size = Vector2(1240, 820)
			_state = GameState.new_game(_loader, "FRA")
			_panel.setup(_state, _loader)
		3:
			_check_no_review_without_a_draft()
			_check_the_sheet_lists_only_the_changed_rows()
			_check_the_totals_are_the_footers()
			_check_the_seats_are_the_forecast()
			_check_the_words_are_counted()
			_check_the_deficit_runs_from_now_to_after()
			_check_the_chips_follow_the_direction()
			_check_a_ticked_force_survives_a_draft_move()
			_check_a_draft_move_repaints_the_open_sheet()
			_check_an_abolition_repaints_the_open_sheet()
			_check_a_birth_rate_change_repaints_the_open_sheet()
			_check_closing_keeps_the_draft()
			_check_france_may_force_and_says_the_censure()
			_check_table_from_the_sheet_tables_the_draft()
			_check_forcing_writes_a_forced_bill()
			_check_withdraw_only_while_a_bill_is_at_vote()
			_check_an_emptied_draft_puts_the_sheet_away()
			_check_a_refusal_downs_table_and_the_force_box()
			_check_a_refusal_is_amber_beside_a_live_verb()
			_check_an_amendment_prices_the_whole_bill()
			_check_a_tabled_programme_is_priced_in_the_whole_bill()
			_check_the_waterfall_is_mirrored()
			_check_a_surplus_says_surplus()
			_check_a_small_change_reads_in_millions()
			_check_britain_has_no_forcing()
		5:
			return _finish()
	return false


func _node(node_name: String) -> Node:
	return _panel.find_child(node_name, true, false)


func _sheet() -> Control:
	return _node("Sheet")


func _open_sheet() -> void:
	(_node("Review") as Button).pressed.emit()


## Health up, Education down and VAT one step up: the picture's three rows.
func _draft_three() -> void:
	var draft = _panel.shared_draft()
	draft.revert()
	draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.5)
	draft.set_value(FinanceDraft.SPENDING, "education", draft.live(FinanceDraft.SPENDING, "education") - 0.5)
	draft.set_value(FinanceDraft.TAX, "vat", draft.live(FinanceDraft.TAX, "vat") + 2.0)
	_panel._on_moved()


func _settle() -> void:
	_panel._paint(_state.player())


func _check_no_review_without_a_draft() -> void:
	_panel.shared_draft().revert()
	_panel._dirty = true
	_panel._process(0.0)
	var review := _node("Review") as Button
	if review != null and review.is_visible_in_tree():
		_fail("the sheet is offered with nothing drafted")
	if _sheet() != null and _sheet().visible:
		_fail("the sheet is open with nothing drafted")


func _check_the_sheet_lists_only_the_changed_rows() -> void:
	_draft_three()
	_panel._process(0.0)
	var review := _node("Review") as Button
	if review == null or not review.is_visible_in_tree():
		_fail("a draft offers no way to the sheet")
		return
	_open_sheet()
	_settle()
	var sheet := _sheet()
	if sheet == null or not sheet.visible:
		_fail("pressing Review did not open the sheet")
		return
	if _panel.get_viewport().gui_get_focus_owner() != _node("SheetTable"):
		_fail("the sheet's Table does not take the keyboard when the sheet opens")
	var rows := sheet.find_children("SheetRow_*", "", true, false)
	if rows.size() != 3:
		_fail("the sheet lists %d rows for a draft of 3" % rows.size())
	for expected in ["SheetRow_spending_pct_gdp_health", "SheetRow_spending_pct_gdp_education", "SheetRow_tax_rates_pct_vat"]:
		if sheet.find_child(expected, true, false) == null:
			_fail("the sheet lacks %s" % expected)
	if sheet.find_child("SheetRow_spending_pct_gdp_defence", true, false) != null:
		_fail("an untouched row is on the sheet")


func _check_the_totals_are_the_footers() -> void:
	var price := FinancePrice.new()
	price.setup(_state)
	var draft = _panel.shared_draft()
	var moves: Dictionary = price.moves(draft.pending())
	var text := _text_of(_sheet())
	if not text.contains(EffectsStrip.money_text(float(moves["spending_bn"]))):
		_fail("the sheet's spending total is not the footer's figure %s" % EffectsStrip.money_text(float(moves["spending_bn"])))
	if not text.contains(EffectsStrip.money_text(float(moves["revenue_bn"]))):
		_fail("the sheet's revenue total is not the footer's figure")
	# Each row's balance is its own pending's priced balance (the sum is the net up to interaction).
	for entry in [["health", FinanceDraft.SPENDING], ["vat", FinanceDraft.TAX]]:
		var own := {entry[1]: {entry[0]: draft.value(entry[1], entry[0])}}
		var row := _sheet().find_child("SheetRow_%s_%s" % [entry[1], entry[0]], true, false)
		if row == null or not _text_of(row).contains(EffectsStrip.sum_text(price.balance_bn(own))):
			_fail("the %s row does not show its own balance" % entry[0])


## The deficit runs from today's books to the draft's, and a rise is the bad way.
func _check_the_deficit_runs_from_now_to_after() -> void:
	var price := FinancePrice.new()
	price.setup(_state)
	var now := price.now()
	var after := price.after(_panel.shared_draft().pending())
	var want := "%s → %s" % [Num.f(float(now["deficit_pct_gdp"]) * float(now["gdp_eur_bn"]) / 100.0, 0), Num.f(float(after["deficit_pct_gdp"]) * float(after["gdp_eur_bn"]) / 100.0, 0)]
	if not _text_of(_sheet()).contains(want):
		_fail("the deficit figure is not '%s'" % want)


## A rise in a spending line pleases the blocs that weigh it and a cut angers them, a rise in a tax angers its payers:
## one phrase a side, the first three named and the rest counted (c-build.md section 2).
func _check_the_chips_follow_the_direction() -> void:
	for entry in [["health", "▲ ", "%s for", Tones.GOOD_SMALL], ["education", "▼ ", "%s against", Tones.BAD_SMALL]]:
		var blocs: Array = FinanceRead.line_blocs(_state, _loader, entry[0])["weights"].map(func(w: Array) -> String: return String(w[0]))
		var said := _who("SheetRow_spending_pct_gdp_" + entry[0])
		var want := [[entry[1] + Strings.t(entry[2]) % _named(blocs), entry[3]]]
		if blocs.is_empty() or said != want:
			_fail("the %s row says %s, want %s" % [entry[0], said, want])
	var payers: Array = _state.player().tax_library["vat"]["who_pays"]
	if payers.size() <= 3:
		_fail("premise: VAT has no payer past the third to count")
	var vat := _who("SheetRow_tax_rates_pct_vat")
	var angry := [["▼ " + Strings.t("%s against") % _named(payers), Tones.BAD_SMALL]]
	if vat != angry:
		_fail("a tax rise says %s, want %s" % [vat, angry])


## A row's for and against lines: [text, variation].
func _who(row_name: String) -> Array:
	return _sheet().find_child(row_name, true, false).find_children("*", "Label", true, false) \
		.filter(func(l) -> bool: return l.text.begins_with("▲") or l.text.begins_with("▼")) \
		.map(func(l) -> Array: return [l.text, String(l.theme_type_variation)])


func _named(blocs: Array) -> String:
	var names := ", ".join(blocs.slice(0, 3).map(func(b) -> String: return Labels.bloc(String(b))))
	return names + (", +%d" % (blocs.size() - 3) if blocs.size() > 3 else "")


func _check_a_ticked_force_survives_a_draft_move() -> void:
	_open_sheet()
	_settle()
	var force := _node("Force") as CheckBox
	force.button_pressed = true
	var draft = _panel.shared_draft()
	draft.set_value(FinanceDraft.SPENDING, "defence", draft.live(FinanceDraft.SPENDING, "defence") + 0.5)
	_panel._on_moved()
	_settle()
	var again := _node("Force") as CheckBox
	if again == null or not again.button_pressed:
		_fail("a draft move cleared the ticked force box")
	if not _text_of(_sheet()).to_lower().contains("without a vote"):
		_fail("a draft move put the division back under a ticked force box")
	draft.set_value(FinanceDraft.SPENDING, "defence", draft.live(FinanceDraft.SPENDING, "defence"))
	_panel._on_moved()
	again.button_pressed = false
	_settle()


## QA's K4 on #367: a draft emptied behind an open sheet (a row dragged back, the Budget's Revert) is not a sheet of
## "0 changed rows": the paint puts it away, and the keyboard it held is let go (no footer verb with nothing drafted).
func _check_an_emptied_draft_puts_the_sheet_away() -> void:
	_draft_three()
	_panel._process(0.0)
	_open_sheet()
	_settle()
	if _panel.get_viewport().gui_get_focus_owner() != _node("SheetTable"):
		_fail("setup: the sheet's Table has the keyboard")
	_panel.shared_draft().revert()
	_panel._on_moved()
	_settle()
	if _sheet().visible:
		_fail("a draft emptied behind the open sheet leaves it open")
	var held: Control = _panel.get_viewport().gui_get_focus_owner()
	if held != null and not held.is_visible_in_tree():
		_fail("the keyboard stays on a hidden control after the sheet is put away")


## The parent's ruling on #367 and QA's T1, T2, T4 on #368: on an amendment every figure on the sheet AND the footer's
## money describes the bill the vote decides (the rows at vote merged with the new ones, and a programme's yearly
## cost, which the vote counts as spending), through one pricing (FinancePrice.whole); the changed-rows list is the
## new rows alone. The expected figures here are built another way: the merged text's absolute pending priced by
## price.moves, plus the merged text's own cost.
func _check_an_amendment_prices_the_whole_bill() -> void:
	_amend({"tax_rates_pct": {"vat": 2.0}, "spending_pct_gdp": {"defence": 0.5}})
	var draft = _panel.shared_draft()
	var price := FinancePrice.new()
	price.setup(_state)
	var merged := FinanceBill.drafted(_state, _loader, draft.bill())
	var whole := FinanceBill.absolute(_state.player(), merged)
	var want := price.moves(whole)
	var new_only := price.moves(draft.pending())
	if is_equal_approx(float(want["spending_bn"]), float(new_only["spending_bn"])) or is_equal_approx(float(want["revenue_bn"]), float(new_only["revenue_bn"])):
		_fail("setup: the whole bill and the new rows alone price the same")
	_check_scope(want, price, whole)
	var rows := _sheet().find_children("SheetRow_*", "", true, false)
	if rows.size() != 1 or _sheet().find_child("SheetRow_tax_rates_pct_vat", true, false) != null:
		_fail("an amendment's changed-rows list is not the new rows alone (%d rows)" % rows.size())
	_unamend()


## A tabled programme's yearly cost is spending in the vote (FinanceBillLaw), so it is spending on the sheet and in
## the footer, and in the deficit after.
func _check_a_tabled_programme_is_priced_in_the_whole_bill() -> void:
	_amend({"programmes": {"industry": "industrial_renewal"}})
	var draft = _panel.shared_draft()
	var price := FinancePrice.new()
	price.setup(_state)
	var merged := FinanceBill.drafted(_state, _loader, draft.bill())
	var cost_bn := float(merged.get("verbs_pct_gdp", 0.0)) * float(_state.player().gdp_eur_bn) / 100.0
	if cost_bn <= 0.0:
		_fail("setup: the tabled programme has no yearly cost")
	var want := price.moves(FinanceBill.absolute(_state.player(), merged))
	want["spending_bn"] = float(want["spending_bn"]) + cost_bn
	_check_scope(want, price, FinanceBill.absolute(_state.player(), merged), cost_bn)
	_unamend()


## Table `tabled` first, then draft Health +1.5 on top and open the sheet.
func _amend(tabled: Dictionary) -> void:
	_panel._on_withdraw()
	_panel.shared_draft().revert()
	FinanceBill.table(_state, _loader, tabled)
	var draft = _panel.shared_draft()
	draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.5)
	_panel._on_moved()
	_panel._process(0.0)
	_open_sheet()
	_panel._sheet._stamp = ""
	_settle()


func _unamend() -> void:
	_panel._on_withdraw()
	_panel.shared_draft().revert()
	_panel._sheet.hide()


## The sheet's totals, its deficit and the footer's money are `want`; the seats are the merged bill's.
func _check_scope(want: Dictionary, price: FinancePrice, whole: Dictionary, extra_bn := 0.0) -> void:
	var now: Dictionary = price.now()
	var after: Dictionary = price.after(whole)
	var gdp := float(after["gdp_eur_bn"])
	var deficit_now := float(now["deficit_pct_gdp"]) * float(now["gdp_eur_bn"]) / 100.0
	var deficit_after := float(after["deficit_pct_gdp"]) * gdp / 100.0 + extra_bn
	var arrow := "%s → %s" % [Num.f(deficit_now, 0), Num.f(deficit_after, 0)]
	var sheet := _text_of(_sheet())
	var money := [EffectsStrip.money_text(float(want["spending_bn"])), EffectsStrip.money_text(float(want["revenue_bn"]))]
	for figure in money:
		if not sheet.contains(figure):
			_fail("the sheet lacks the whole bill's %s" % figure)
	if not sheet.contains(arrow):
		_fail("the sheet's deficit is not today -> the whole bill: wanted '%s'" % arrow)
	# The "% of GDP" figure is the whole bill's too (QA's surviving mutant on #368: the programme path's cost).
	var pct := Num.f(deficit_after / gdp * 100.0, 2) + " %"
	if not sheet.contains(pct):
		_fail("the sheet's deficit in %% of GDP is not the whole bill's: wanted '%s'" % pct)
	# One screen, one figure (the parent's ruling after #368): the rail's waterfall runs the same bill as the sheet's
	# arrow, not the new rows alone; the page's note no longer repeats it (#429 pass 2 T10: each number once).
	var chart = _panel._foot._chart
	var ends := "%s → %s" % [chart.figure(0), chart.figure(chart.row_count() - 1)]
	var sizes := "%s → %s" % [Strings.t("%s bn") % Num.f(absf(deficit_now), 0), Strings.t("%s bn") % Num.f(absf(deficit_after), 0)]
	if ends != sizes or not _panel._foot._pct.text.contains(Num.f(deficit_after / gdp * 100.0, 2)):
		_fail("the rail's waterfall is not the whole bill's (%s): %s, %s" % [arrow, ends, _panel._foot._pct.text])
	if var_to_str(_panel._forecast._want) != var_to_str(whole):
		_fail("the ranges forecast is not fed the whole bill: %s" % var_to_str(_panel._forecast._want))
	# The money each side is the sheet's to say; the rail says its figures are the whole bill's.
	var foot: String = _panel._foot._text.text
	if not foot.contains("whole bill"):
		_fail("the rail does not say an amendment's figures are the whole bill's: %s" % foot)
	var vote: Dictionary = FinanceRead.draft(_state, _loader, _panel.shared_draft().bill())["vote"]
	if not sheet.contains(str(int(vote["yes_seats"]))):
		_fail("the amendment's seats are not the merged bill's")


func _check_a_refusal_downs_table_and_the_force_box() -> void:
	_panel._on_withdraw()
	_draft_three()
	_state.player().tabled_bill = {"law_id": "workplace_safety_act", "vote_year": _state.year, "vote_month": _state.month, "vote_day": 28}
	_panel._process(0.0)
	_open_sheet()
	_panel._sheet._stamp = ""
	_settle()
	# G2: the sheet's verb queues, as the bar's does.
	var table := _node("SheetTable") as Button
	if table == null or table.disabled or table.text != Strings.t("Queue for %s") % BillVerbs.month_name(_state, 0):
		_fail("another bill holds the slot and the sheet's verb is not the queue's: '%s'" % (table.text if table != null else "<none>"))
	if not _text_of(_sheet()).contains("Another bill holds this month's slot."):
		_fail("a refused sheet does not say why")
	var force := _node("Force") as CheckBox
	if force != null and force.is_visible_in_tree():
		_fail("a refused draft offers a forced passage")
	if _panel.get_viewport().gui_get_focus_owner() != table:
		_fail("a sheet that can queue does not hand the keyboard to its verb")
	_state.player().bill_queue = [{"law_id": "law_a"}, {"law_id": "law_b"}, {"law_id": "law_c"}]
	_panel._sheet._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)
	_settle()
	table = _node("SheetTable") as Button
	if table == null or not table.disabled or not _text_of(_sheet()).contains(Strings.t("The queue holds three bills. Take one out first.")):
		_fail("full queue: the sheet's verb is up or says nothing")
	if _refusals() != ["bad"]:
		_fail("full queue: nothing can be pressed, the refusal says %s, want one red line with its glyph" % [_refusals()])
	_state.player().bill_queue = []
	_state.player().tabled_bill = {}
	_panel.shared_draft().revert()
	_panel._sheet.hide()


## The tone rule (c-build.md section 4, #464's R10 and R11): beside a live verb the held slot is amber and what the
## press would do is plain; one of tabling's checks refusing the queue too is said first, and both are red.
func _check_a_refusal_is_amber_beside_a_live_verb() -> void:
	var ns = _state.player()
	ns.tabled_bill = {"law_id": "workplace_safety_act", "vote_year": _state.year, "vote_month": _state.month, "vote_day": 28}
	ns.bill_queue = []
	_draft_three()
	_panel._process(0.0)
	_open_sheet()
	_panel._sheet._stamp = ""
	_settle()
	var lands := BillVerbs.division(_state, 0)
	var note := Strings.t("If queued, it divides on %s.") % DateText.day_month(int(lands["day"]), int(lands["month"]))
	var slot := Strings.t("Another bill holds this month's slot.")
	var said := _lines([slot, note])
	if said != [[slot, Tones.WARN_TEXT], [note, Tones.CHIP_TEXT]] or _refusals() != ["warn"]:
		_fail("a queueable draft's sheet says %s %s, want the slot amber with its glyph, then the queue note plain" % [said, _refusals()])
	_panel.shared_draft().set_value(FinanceDraft.TAX, "vat", float(ns.tax_library["vat"]["rate_range_pct"][1]) + 1.0)
	_panel._on_moved()
	_panel._sheet._stamp = ""
	_settle()
	var past := Strings.t("Outside the tax's range.")
	said = _lines([slot, past])
	if said != [[past, Tones.BAD_SMALL], [slot, Tones.BAD_SMALL]] or _refusals() != ["bad", "bad"]:
		_fail("a rate past its range: the sheet says %s %s, want the range then the slot, both red with a glyph" % [said, _refusals()])
	ns.tabled_bill = {}
	_panel.shared_draft().revert()
	_panel._sheet.hide()


## The sheet's refusal lines in order: their tone, and that each wears the warning glyph.
func _refusals() -> Array:
	return _sheet().find_children("*", "HBoxContainer", true, false) \
		.filter(func(b) -> bool: return b.has_meta("refusal")) \
		.map(func(b) -> String: return String(b.get_meta("refusal")) + ("" if b.find_children("*", "TextureRect", false, false).size() == 1 else " without a glyph"))


## The sheet's lines among `texts`, in its order: [text, variation].
func _lines(texts: Array) -> Array:
	return _sheet().find_children("*", "Label", true, false).filter(func(l) -> bool: return l.text in texts) \
		.map(func(l) -> Array: return [l.text, String(l.theme_type_variation)])


## The sheet's visible words on the picture's draft, for the PR's prose delta (the prose budget counts a tab at rest).
func _check_the_words_are_counted() -> void:
	var words := 0
	for token in _text_of(_sheet()).split(" ", false):
		for ch in token:
			if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z"):
				words += 1
				break
	print("test_finance_sheet: the open sheet shows %d words on a three-row draft" % words)


func _check_the_seats_are_the_forecast() -> void:
	var vote: Dictionary = FinanceRead.draft(_state, _loader, _panel.shared_draft().bill())["vote"]
	var text := _text_of(_sheet())
	for key in ["yes_seats", "no_seats", "abstain_seats"]:
		if not text.contains(str(int(vote[key]))):
			_fail("the sheet's seats lack %s = %d" % [key, int(vote[key])])


func _check_a_draft_move_repaints_the_open_sheet() -> void:
	var draft = _panel.shared_draft()
	draft.set_value(FinanceDraft.SPENDING, "defence", draft.live(FinanceDraft.SPENDING, "defence") + 0.5)
	_panel._on_moved()
	_settle()
	if _sheet().find_child("SheetRow_spending_pct_gdp_defence", true, false) == null:
		_fail("a row drafted while the sheet is open does not reach it")
	draft.set_value(FinanceDraft.SPENDING, "defence", draft.live(FinanceDraft.SPENDING, "defence"))
	_panel._on_moved()
	_settle()
	if _sheet().find_child("SheetRow_spending_pct_gdp_defence", true, false) != null:
		_fail("a row dragged back to its live value stays on the sheet")


## The retro review's item 2: the sheet's stamp hashed the priceable rows alone, so an abolition (or a new tax)
## drafted with the sheet open never reached it, and Table tabled rows the player had not been shown.
func _check_an_abolition_repaints_the_open_sheet() -> void:
	var draft = _panel.shared_draft()
	var kind := ""
	for key in _state.player().tax_rates_pct:
		if String(key) != "vat" and float(_state.player().tax_rates_pct[key]) > 0.0:
			kind = String(key)
			break
	var row_name := "SheetRow_" + FinanceRows.row_id(FinanceDraft.ABOLISH, kind).replace(":", "_")
	# The autumn month, or the panel's sweep takes the abolition out of the draft.
	var month := int(_state.month)
	_state.month = int(_loader.nations[_state.player().id].finance_autumn_month)
	_panel._on_moved()
	_settle()
	draft.toggle_abolish(kind)
	_panel._on_moved()
	_settle()
	if _sheet().find_child(row_name, true, false) == null:
		_fail("an abolition drafted while the sheet is open does not reach it (%s)" % kind)
	draft.toggle_abolish(kind)
	_panel._on_moved()
	_settle()
	if _sheet().find_child(row_name, true, false) != null:
		_fail("an abolition taken back stays on the open sheet (%s)" % kind)
	_state.month = month
	_panel._on_moved()
	_settle()


## Pass 2's T3 on #392: a new tax's rate moved with the sheet open reaches it (a birth is no pending() row either).
func _check_a_birth_rate_change_repaints_the_open_sheet() -> void:
	var draft = _panel.shared_draft()
	var ns = _state.player()
	var kind := ""
	for k in ns.tax_library:
		if not ns.tax_rates_pct.has(k) and ns.tax_library[k].has("rate_range_pct"):
			kind = String(k)
			break
	if kind == "":
		_fail("premise: every kind is in force")
		return
	var month := int(_state.month)
	_state.month = int(_loader.nations[ns.id].finance_autumn_month)
	_panel._on_moved()
	_settle()
	var span: Array = ns.tax_library[kind]["rate_range_pct"]
	draft.set_create(kind, float(span[0]) + (float(span[1]) - float(span[0])) * 0.25)
	_panel._on_moved()
	_settle()
	var row_name := "SheetRow_" + FinanceRows.row_id(FinanceDraft.TAX, kind).replace(":", "_")
	var row := _sheet().find_child(row_name, true, false)
	if row == null:
		_fail("a birth drafted while the sheet is open does not reach it (%s)" % kind)
	else:
		var before := _text_of(row)
		draft.set_value(FinanceDraft.TAX, kind, float(span[0]) + (float(span[1]) - float(span[0])) * 0.75)
		_panel._on_moved()
		_settle()
		var now := _sheet().find_child(row_name, true, false)
		if now == null or _text_of(now) == before:
			_fail("a new tax's rate moved while the sheet is open does not repaint it (%s)" % kind)
	draft.clear_create(kind)
	_state.month = month
	_panel._on_moved()
	_settle()


func _check_closing_keeps_the_draft() -> void:
	var close := _node("SheetClose") as Button
	close.grab_focus()  # a press takes the focus
	close.pressed.emit()
	if _sheet().visible:
		_fail("Close did not close the sheet")
	if _panel.get_viewport().gui_get_focus_owner() != _node("Review"):
		_fail("closing the sheet does not give the keyboard back to the footer's Review")
	if _panel.shared_draft().count() != 3:
		_fail("closing the sheet lost the draft (%d rows left)" % _panel.shared_draft().count())


func _check_france_may_force_and_says_the_censure() -> void:
	_open_sheet()
	_settle()
	var force := _node("Force") as CheckBox
	if force == null or not force.is_visible_in_tree():
		_fail("France's sheet offers no forced passage")
		return
	force.button_pressed = true
	_settle()
	var text := _text_of(_sheet())
	var censure: Dictionary = Government.resolve_censure(_state.player(), _loader.parties.get("FRA", []), true)
	if not text.contains("%d seats would move" % int(censure["for_seats"])) or not text.contains("%d are needed" % Government.censure_seats(_state.player())):
		_fail("the censure line does not carry the Government window's tally")
	if text.contains("It survives") != not bool(censure["carried"]):
		_fail("the censure outcome is not the resolver's")
	if not text.to_lower().contains("without a vote"):
		_fail("a forced bill does not say it is adopted without a vote")
	if not text.contains("censure") and not text.contains("Censure"):
		_fail("a forced bill does not say the censure it meets")
	force.button_pressed = false
	_settle()


func _check_table_from_the_sheet_tables_the_draft() -> void:
	var table := _node("SheetTable") as Button
	if table == null or table.disabled:
		_fail("the sheet's Table is missing or down on a legal draft")
		return
	table.pressed.emit()
	var ns = _state.player()
	if not FinanceBillLaw.is_finance(String(ns.tabled_bill.get("law_id", ""))):
		_fail("the sheet's Table did not table a finance bill")
	elif bool(ns.tabled_bill.get("forced", false)):
		_fail("an unforced Table wrote a forced bill")
	if _panel.shared_draft().count() != 0:
		_fail("the draft survives a tabling")
	if _sheet().visible:
		_fail("the sheet stays open after tabling")


func _check_forcing_writes_a_forced_bill() -> void:
	_panel._on_withdraw()
	_draft_three()
	_panel._process(0.0)
	_open_sheet()
	_settle()
	(_node("Force") as CheckBox).button_pressed = true
	_settle()
	(_node("SheetTable") as Button).pressed.emit()
	var ns = _state.player()
	if ns.tabled_bill.is_empty() or not bool(ns.tabled_bill.get("forced", false)):
		_fail("a ticked Force did not write a forced bill (%s)" % [ns.tabled_bill])


func _check_withdraw_only_while_a_bill_is_at_vote() -> void:
	_draft_three()
	_panel._process(0.0)
	_open_sheet()
	_settle()
	var withdraw := _node("SheetWithdraw") as Button
	if withdraw == null or not withdraw.is_visible_in_tree():
		_fail("a bill is at vote and the sheet offers no Withdraw")
		return
	withdraw.pressed.emit()
	if not _state.player().tabled_bill.is_empty():
		_fail("Withdraw left the bill at vote")
	_settle()
	if _panel.shared_draft().count() != 3:
		_fail("Withdraw dropped the draft")
	if _sheet().visible:
		_settle()
	var again := _node("SheetWithdraw") as Button
	if again != null and again.is_visible_in_tree():
		_fail("Withdraw stays offered with no bill at vote")
	_panel.shared_draft().revert()


## The author's chart rules (2026-11-28), on the rail and the document: zero is a line down the whole chart, at the
## right while the books run a deficit; a deficit reaches left of it; a change that widens the deficit steps left and
## one that narrows it steps right, each signed as the list signs it.
func _check_the_waterfall_is_mirrored() -> void:
	_draft_three()  # Health up widens it; Education down narrows it
	_panel._process(0.0)
	_open_sheet()
	_settle()
	for chart in [_panel._foot._chart, _document_chart()]:
		chart.size = Vector2(480.0, chart.custom_minimum_size.y)
		var zero: Rect2 = chart.zero_rect()
		if zero.position.y != 0.0 or zero.size != Vector2(1.0, chart.row_height() * chart.row_count()) or absf(zero.position.x - chart.x_of(0.0)) > 1.0:
			_fail("the zero line is not 1 px down the whole chart at zero: %s" % zero)
		for i in chart.row_count():
			if chart.bar_rect(i).end.x > zero.position.x + 1.0:
				_fail("in deficit, row %d reaches right of zero" % i)
		var today: Rect2 = chart.bar_rect(0)
		var health: Rect2 = chart.bar_rect(1)
		var education: Rect2 = chart.bar_rect(2)
		if absf(today.end.x - chart.x_of(0.0)) > 0.5 or today.position.x >= zero.position.x - 1.0:
			_fail("today's deficit does not reach left of zero: %s" % today)
		if absf(health.end.x - today.position.x) > 0.5 or health.position.x >= today.position.x - 0.5:
			_fail("a widening step does not step left: %s after %s" % [health, today])
		if absf(education.position.x - health.position.x) > 0.5 or education.end.x <= health.position.x + 0.5:
			_fail("a narrowing step does not step right: %s after %s" % [education, health])
		if not chart.figure(1).begins_with("-") or not chart.figure(2).begins_with("+") or chart.bar_color(1) != Tones.BAD or chart.bar_color(2) != Tones.GOOD:
			_fail("the steps read %s and %s" % [chart.figure(1), chart.figure(2)])
	_panel.close_sheet()


func _document_chart() -> Control:
	return _sheet().find_children("*", "Control", true, false).filter(func(c) -> bool: return c is ChartWaterfall and not c.is_queued_for_deletion())[0]


## The author's rule (2026-11-28): the two deficit figures print a size and the caption's word carries the sign, so a
## surplus is never a negative deficit; each side of "now -> after" has its word. Fresh books each time: FinancePrice
## keeps today's by the day. A case is [pensions moved on the books, then drafted, the captions' words].
func _check_a_surplus_says_surplus() -> void:
	for case in [[0.0, -0.5, "Deficit"], [0.0, -8.0, "Deficit → surplus"], [-8.0, -0.5, "Surplus"], [-8.0, 8.0, "Surplus → deficit"]]:
		var state = GameState.new_game(_loader, "FRA")
		var ns = state.player()
		ns.spending_pct_gdp["pensions"] = float(ns.spending_pct_gdp["pensions"]) + float(case[0])
		Budget.recompute(state, ns)
		_panel.setup(state, _loader)
		_state = state
		var draft = _panel.shared_draft()
		draft.revert()
		draft.set_value(FinanceDraft.SPENDING, "pensions", draft.live(FinanceDraft.SPENDING, "pensions") + float(case[1]))
		_panel._on_moved()
		_panel._process(0.0)
		_open_sheet()
		_settle()
		var price := FinancePrice.new()
		price.setup(state)
		var now := price.now()
		var after := price.after(draft.pending())
		var was := float(now["deficit_pct_gdp"])
		var will := float(after["deficit_pct_gdp"])
		var words := String(case[2])
		if (was < 0.0) != words.begins_with("Surplus") or (will < 0.0) != (words.ends_with("surplus") or words == "Surplus"):
			_fail("premise (%s): the books run %.2f to %.2f %% of GDP" % [words, was, will])
		var want := [
			"%s → %s bn" % [Num.f(absf(was * float(now["gdp_eur_bn"]) / 100.0), 0), Num.f(absf(will * float(after["gdp_eur_bn"]) / 100.0), 0)], words + ", a year",
			"%s → %s %%" % [Num.f(absf(was), 2), Num.f(absf(will), 2)], words + ", of GDP"]
		var got := []
		for box in _node("SheetTotals").get_children().slice(2):
			got.append_array([box.get_child(0).text, box.get_child(1).text])
		if got != want:
			_fail("%s: the sheet says %s, want %s" % [words, got, want])
		# The chart's end is the size too, on its own side of the zero line.
		var chart := _document_chart()
		chart.size = Vector2(480.0, chart.custom_minimum_size.y)
		var last: int = chart.row_count() - 1
		var end: Rect2 = chart.bar_rect(last)
		var size_said := Strings.t("%s bn") % Num.f(absf(will * float(after["gdp_eur_bn"]) / 100.0), 0)
		if chart.figure(last) != size_said or (will < 0.0) != (end.position.x >= chart.zero_rect().position.x - 1.0):
			_fail("%s: the chart ends '%s' at %s (zero %s), want %s" % [words, chart.figure(last), end, chart.zero_rect().position.x, size_said])
		_panel.close_sheet()


## The author's rule (2026-11-28): a change under a tenth of a billion reads in millions, never "0.0 bn": in both
## lists of changes and on both charts.
func _check_a_small_change_reads_in_millions() -> void:
	_state = GameState.new_game(_loader, "FRA")
	_panel.setup(_state, _loader)
	_panel._dirty = true
	_panel._process(0.0)
	var draft = _panel.shared_draft()
	draft.revert()
	draft.set_value(FinanceDraft.TAX, "capital_gains", draft.live(FinanceDraft.TAX, "capital_gains") + 0.1)
	_panel._on_moved()
	_panel._process(0.0)
	_open_sheet()
	_settle()
	var price := FinancePrice.new()
	price.setup(_state)
	var said := EffectsStrip.sum_text(price.row_balance_bn(draft.rows()[0]))
	if not said.ends_with(" m"):
		_fail("premise: a 0.1 point of capital gains moves %s, not millions" % said)
	var rail := _panel._foot.find_child("Money_tax_rates_pct_capital_gains", true, false) as Label
	var listed := _sheet().find_child("SheetRow_tax_rates_pct_capital_gains", true, false).find_child("Money", true, false) as Label
	var got := [rail.text, listed.text, _panel._foot._chart.figure(1), _document_chart().figure(1)]
	if got != [said, said, said, said]:
		_fail("a small change reads %s on the rail's list, the document's list and the two charts, want %s" % [got, said])
	_panel.close_sheet()


func _check_britain_has_no_forcing() -> void:
	var state = GameState.new_game(_loader, "GBR")
	_panel.setup(state, _loader)
	_state = state
	_panel._dirty = true
	_panel._process(0.0)
	var draft = _panel.shared_draft()
	draft.set_value(FinanceDraft.SPENDING, "health", draft.live(FinanceDraft.SPENDING, "health") + 1.0)
	_panel._on_moved()
	_panel._process(0.0)
	_open_sheet()
	_settle()
	var force := _node("Force") as CheckBox
	if force != null and force.is_visible_in_tree():
		_fail("Britain's sheet offers a forced passage")
	if _sheet() == null or not _sheet().visible:
		_fail("Britain's sheet did not open")


## Every label and button text under a node, one string.
func _text_of(node: Node) -> String:
	var out := PackedStringArray()
	for child in node.find_children("*", "", true, false):
		if child is Label:
			out.append((child as Label).text)
		elif child is RichTextLabel:
			out.append((child as RichTextLabel).get_parsed_text())
		elif child is Button:
			out.append((child as Button).text)
	if node is Label:
		out.append((node as Label).text)
	return " ".join(out)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: " + message)


func _finish() -> bool:
	for failure in _failures:
		print("FAIL ", failure)
	print("test_finance_sheet: %s" % ("FAILED (%d)" % _failures.size() if not _failures.is_empty() else "ok"))
	quit(1 if not _failures.is_empty() else 0)
	return true
