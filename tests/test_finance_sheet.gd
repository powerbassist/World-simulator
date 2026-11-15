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
const FinancePrice = preload("res://src/ui/finance_price.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Government = preload("res://src/sim/government.gd")
const Labels = preload("res://src/ui/labels.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

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
			_check_closing_keeps_the_draft()
			_check_france_may_force_and_says_the_censure()
			_check_table_from_the_sheet_tables_the_draft()
			_check_forcing_writes_a_forced_bill()
			_check_withdraw_only_while_a_bill_is_at_vote()
			_check_a_refusal_downs_table_and_the_force_box()
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
		if row == null or not _text_of(row).contains(EffectsStrip.money_text(price.balance_bn(own))):
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


## A rise in a spending line pleases the blocs that weigh it, a rise in a tax angers its payers; four payers are three chips and "+1".
func _check_the_chips_follow_the_direction() -> void:
	var health := _text_of(_sheet().find_child("SheetRow_spending_pct_gdp_health", true, false))
	var weights: Array = FinanceRead.line_blocs(_state, _loader, "health")["weights"]
	if weights.is_empty() or not health.contains("▲ " + Strings.t("%s for") % Labels.bloc(String(weights[0][0]))):
		_fail("a spending rise does not please the blocs that weigh the line: %s" % health)
	if health.contains("▼"):
		_fail("a spending rise angers someone on the sheet: %s" % health)
	var vat := _sheet().find_child("SheetRow_tax_rates_pct_vat", true, false)
	var payers: Array = _state.player().tax_library["vat"]["who_pays"]
	var angered := vat.find_children("*", "Label", true, false).filter(func(n: Node) -> bool: return (n as Label).text.begins_with("▼"))
	if angered.size() != mini(payers.size(), 3):
		_fail("a tax rise shows %d payer chips, wanted %d of %d" % [angered.size(), mini(payers.size(), 3), payers.size()])
	if payers.size() > 3 and not _text_of(vat).contains("+%d" % (payers.size() - 3)):
		_fail("the chips past three are not counted")
	if _text_of(vat).contains("▲"):
		_fail("a tax rise pleases someone on the sheet")


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


func _check_a_refusal_downs_table_and_the_force_box() -> void:
	_panel._on_withdraw()
	_draft_three()
	_state.player().tabled_bill = {"law_id": "workplace_safety_act", "vote_year": _state.year, "vote_month": _state.month, "vote_day": 28}
	_panel._process(0.0)
	_open_sheet()
	_panel._sheet._stamp = ""
	_settle()
	var table := _node("SheetTable") as Button
	if table == null or not table.disabled:
		_fail("another bill holds the slot and the sheet's Table is still up")
	if not _text_of(_sheet()).contains("Another bill holds this month's slot."):
		_fail("a refused sheet does not say why")
	var force := _node("Force") as CheckBox
	if force != null and force.is_visible_in_tree():
		_fail("a refused draft offers a forced passage")
	_state.player().tabled_bill = {}
	_panel.shared_draft().revert()
	_panel._sheet.hide()


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


func _check_closing_keeps_the_draft() -> void:
	(_node("SheetClose") as Button).pressed.emit()
	if _sheet().visible:
		_fail("Close did not close the sheet")
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
