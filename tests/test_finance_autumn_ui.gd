extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_autumn_ui.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4, Finances slice 4 (the UI half; the price of a birth is the sim's read, not here): in the nation's autumn
## month a kind outside the books is a row with a "Put in force" verb and a kind in force may be abolished from its editor;
## out of that month neither verb exists and the page says when a kind can be created. A kind put in force or abolished
## is a row of the draft, named on the sheet and in the footer, locked once the bill is at vote, and the bill the draft
## writes is the one that tables.

const GameState = preload("res://src/core/game_state.gd")
const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const Strings = preload("res://src/ui/strings.gd")
const Budget = preload("res://src/sim/budget.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Num = preload("res://src/ui/num.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceFoot = preload("res://src/ui/finance_foot.gd")
const FinancePrice = preload("res://src/ui/finance_price.gd")
const LedgerBox = preload("res://src/ui/ledger_box.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0
var _absent := ""
var _abolish_button: Button


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
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
			_check_no_verbs_outside_the_autumn()
			_state.month = int(_loader.nations["FRA"].finance_autumn_month)
			_rebuild()
			_check_the_verbs_in_the_autumn()
			_check_a_birth_is_a_row_named_everywhere()
			_check_taking_a_birth_back()
			_check_an_abolition()
			_check_a_clicked_verb_rebuilds_at_once()
			_check_births_and_abolitions_are_priced()
			_check_the_autumn_rows_leave_when_the_month_ends()
			_check_a_bill_at_vote_locks_its_births()
			# Pass 2's T1 and T3 on #392: a real mouse click on Abolish, frames apart, then Space.
			_mouse_abolish_start()
		4:
			# A frame after the build: the containers have placed the button.
			if _abolish_button != null:
				Click.half(_panel.get_viewport(), _abolish_button, true)
		5:
			if is_instance_valid(_abolish_button):
				Click.half(_panel.get_viewport(), _abolish_button, false)
		7:
			_panel.get_viewport().push_input(_space(true), true)
			_panel.get_viewport().push_input(_space(false), true)
		9:
			_check_space_after_a_mouse_abolish()
			_check_a_sweep_rebuilds_under_a_held_slider()
		11:
			return _finish()
	return false


func _space(down: bool) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = down
	return key


func _mouse_abolish_start() -> void:
	_panel.shared_draft().revert()
	if _panel._open_id != "tax_rates_pct:tobacco_duty":
		_panel._on_open("tax_rates_pct:tobacco_duty")
	_rebuild()
	_abolish_button = _node("AbolishTax") as Button
	if _abolish_button == null:
		_fail("setup: no Abolish to click")
		return


## A mouse press hands the keyboard to nothing: code focus on the rebuilt "Keep it" made the next Space press it, and
## the abolition went silently (before the PR, Space paused the clock).
func _check_space_after_a_mouse_abolish() -> void:
	var draft = _panel.shared_draft()
	if _node("KeepTax") == null:
		_fail("after a mouse click on Abolish and a Space, no abolition stands (the click missed or Space took it back)")
	elif not draft.is_abolished("tobacco_duty"):
		_fail("Space after a mouse click on Abolish took the abolition back")
	var held: Control = _panel.get_viewport().gui_get_focus_owner()
	if held != null and _panel.is_ancestor_of(held):
		_fail("a mouse click on Abolish left code focus on %s" % held.name)
	draft.revert()
	_rebuild()


## Pass 2's T2: the keyboard on a slider held every rebuild, so after the autumn month the editor still offered Abolish.
func _check_a_sweep_rebuilds_under_a_held_slider() -> void:
	var draft = _panel.shared_draft()
	if _panel._open_id != "tax_rates_pct:vat":
		_panel._on_open("tax_rates_pct:vat")
	_rebuild()
	if _panel._editor == null or _panel._editor._slider == null:
		_fail("setup: VAT's editor has no slider")
		return
	_panel._editor._slider.grab_focus()
	draft.toggle_abolish("tobacco_duty")
	var autumn := int(_state.month)
	_state.month = autumn % 12 + 1
	_panel._paint_due = true
	_panel._process(0.0)
	_panel._process(0.0)
	if _node("AbolishTax") != null:
		_fail("past the autumn month a held slider kept the editor offering Abolish")
	if draft.is_abolished("tobacco_duty"):
		_fail("the sweep left the abolition in the draft")
	_state.month = autumn
	draft.revert()
	_rebuild()


func _rebuild() -> void:
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)


func _node(node_name: String) -> Node:
	return _panel.find_child(node_name, true, false)


func _text_of(node: Node) -> String:
	var out := PackedStringArray()
	for child in node.find_children("*", "", true, false):
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
	return " ".join(out)


func _check_no_verbs_outside_the_autumn() -> void:
	if not _panel.find_children("PutInForce_*", "", true, false).is_empty():
		_fail("a kind can be put in force outside the autumn month")
	if not _text_of(_panel._revenue_box).contains("creatable in"):
		_fail("outside the autumn the page does not say when a kind can be created")
	_panel._on_open("tax_rates_pct:vat")
	_rebuild()
	if _node("Now") == null or not (_node("Now") as Label).text.begins_with("Now "):
		_fail("an in-force kind's editor does not read 'Now ...'")
	if _node("AbolishTax") != null:
		_fail("a tax can be abolished outside the autumn month")
	_panel._on_open("tax_rates_pct:vat")
	_rebuild()


func _check_the_verbs_in_the_autumn() -> void:
	var buttons: Array = _panel.find_children("PutInForce_*", "", true, false)
	var absent := []
	for kind in _state.player().tax_library:
		if not _state.player().tax_rates_pct.has(kind):
			absent.append(kind)
	if buttons.size() != absent.size() or absent.is_empty():
		_fail("the autumn offers %d verbs for %d kinds outside the books" % [buttons.size(), absent.size()])
	_absent = String(absent[0])


func _check_a_birth_is_a_row_named_everywhere() -> void:
	(_node("PutInForce_" + _absent) as Button).pressed.emit()
	_rebuild()
	var draft = _panel.shared_draft()
	if not draft.is_created(_absent):
		_fail("Put in force did not put %s in the draft" % _absent)
	if _panel._open_id != "tax_rates_pct:" + _absent:
		_fail("Put in force did not open the kind's editor (%s)" % _panel._open_id)
	if _node("TakeBack") == null:
		_fail("a kind in the draft has no way back")
	if _node("Now") == null or (_node("Now") as Label).text != "Not in force yet":
		_fail("a kind outside the books does not read 'Not in force yet'")
	var name: String = Strings.row_name("taxes", _state.player().tax_library[_absent])
	_panel._paint(_state.player())
	if not String(_panel._foot._text.text).contains("creation of " + name):
		_fail("the footer does not name the creation: %s" % _panel._foot._text.text)
	_panel._open_sheet()
	_panel._sheet._stamp = ""
	_panel._paint(_state.player())
	var row: Node = _panel._sheet.find_child("SheetRow_tax_rates_pct_" + _absent, true, false)
	if row == null or not _text_of(row).contains("Creation of " + name):
		_fail("the sheet does not list the creation")
	if row != null and _text_of(row).contains("▲"):
		_fail("a creation carries who-is-for chips before the sim prices it")
	_panel._sheet.hide()
	var table := FinanceBill.table(_state, _loader, draft.bill())
	if not bool(table.get("tabled", false)):
		_fail("the autumn bill the page drafted does not table: %s" % [table])
	_panel._on_withdraw()


func _check_taking_a_birth_back() -> void:
	var draft = _panel.shared_draft()
	_rebuild()
	if _node("TakeBack") == null:
		_fail("setup: the editor is closed")
		return
	(_node("TakeBack") as Button).pressed.emit()
	_rebuild()
	if draft.is_created(_absent) or not draft.is_empty():
		_fail("Take it back left the birth in the draft")
	if _node("PutInForce_" + _absent) == null:
		_fail("the kind has no Put in force verb after it was taken back")
	# No editor came back to send the keyboard to: the request dies with the rebuild, or the next row the mouse opens
	# takes the keyboard unasked.
	if _panel._focus_wanted:
		_fail("Take it back leaves a focus request standing with no editor to land on")


func _check_an_abolition() -> void:
	var draft = _panel.shared_draft()
	_panel._on_open("tax_rates_pct:tobacco_duty")
	_rebuild()
	var abolish := _node("AbolishTax") as Button
	if abolish == null:
		_fail("the autumn offers no way to abolish a kind in force")
		return
	abolish.pressed.emit()
	_rebuild()
	if not draft.is_abolished("tobacco_duty"):
		_fail("Abolish this tax did not put the kind in the draft")
	if _node("KeepTax") == null:
		_fail("an abolished kind has no way back")
	# An abolished kind's editor holds no slider: a refresh and a focus request on it must be harmless.
	_panel._editor.focus_lever()
	_panel._editor._sync()
	var cell := _panel._ctx["cells"]["tax_rates_pct:tobacco_duty"][0] as Label
	_panel._paint(_state.player())
	if cell.text != "abolish":
		_fail("the abolished row's figure reads '%s'" % cell.text)
	if not String(_panel._foot._text.text).contains("abolition of "):
		_fail("the footer does not name the abolition: %s" % _panel._foot._text.text)
	(_node("KeepTax") as Button).pressed.emit()
	_rebuild()
	if draft.is_abolished("tobacco_duty"):
		_fail("Keep it left the kind abolished")
	draft.revert()


## The retro review's item 4: a click gives the verb button the keyboard, and a focus inside the open editor read as
## "a hand on the lever", so the page never rebuilt: the button stayed up, a second click un-abolished the kind.
func _check_a_clicked_verb_rebuilds_at_once() -> void:
	var draft = _panel.shared_draft()
	draft.revert()
	if _panel._open_id != "tax_rates_pct:tobacco_duty":
		_panel._on_open("tax_rates_pct:tobacco_duty")
	_rebuild()
	var abolish := _node("AbolishTax") as Button
	if abolish == null:
		_fail("the autumn offers no way to abolish a kind in force")
		return
	abolish.grab_focus()  # the focus a press leaves on the verb
	abolish.gui_input.emit(_space(true))  # a KEYBOARD press: the last event the verb saw
	abolish.pressed.emit()
	# QA's RECORD on #392: a keyed press asks for the keyboard on the rebuilt editor (the button it was on is freed).
	if not _panel._focus_wanted:
		_fail("a keyed verb does not send the keyboard to the rebuilt editor")
	_panel._process(0.0)
	if _node("KeepTax") == null:
		_fail("a clicked Abolish does not rebuild its editor: no way back shown")
	elif _panel._editor != null:
		_panel._editor.focus_lever()
		if _panel.get_viewport().gui_get_focus_owner() != _node("KeepTax"):
			_fail("after Abolish the keyboard does not land on Keep it")
	var again := _node("AbolishTax") as Button
	if again != null and is_instance_valid(again) and again.is_visible_in_tree():
		again.pressed.emit()
		if not draft.is_abolished("tobacco_duty"):
			_fail("a second click on the still-shown Abolish took the abolition back")
	draft.revert()
	_rebuild()


## The sim's own read prices a bill with births (FinanceBill.preview; Budget.preview refuses an unborn kind): the sheet's
## totals, its deficit and each autumn row's balance are that preview's, the birth and the abolition included.
func _check_births_and_abolitions_are_priced() -> void:
	var ns = _state.player()
	var draft = _panel.shared_draft()
	draft.revert()
	var born := ""
	var rate := 0.0
	var now: Dictionary = Budget.preview(_state, {})
	for kind in ns.tax_library:
		if ns.tax_rates_pct.has(kind):
			continue
		var r: float = float(ns.tax_library[kind]["rate_range_pct"][1]) / 2.0
		if absf(EffectsStrip.balance_bn(now, FinanceBill.preview(_state, {"create": {kind: r}}))) > 0.2:
			born = String(kind)
			rate = r
			break
	if born == "":
		_fail("setup: no kind outside the books moves the balance by 0.2 bn at half its range")
		return
	draft.set_create(born, rate)
	draft.toggle_abolish("tobacco_duty")
	_panel._on_moved()
	_panel._open_sheet()
	_panel._sheet._stamp = ""
	_panel._paint(ns)
	var merged := FinanceBill.drafted(_state, _loader, draft.bill())
	var after: Dictionary = FinanceBill.preview(_state, merged)
	var sheet := _text_of(_panel._sheet)
	var revenue := EffectsStrip.money_text(EffectsStrip.moved_bn(now, after, "total_revenue_pct_gdp"))
	if not sheet.contains(revenue):
		_fail("the sheet's revenue is not the whole autumn bill's %s" % revenue)
	var arrow := "%s → %s" % [Num.f(float(now["deficit_pct_gdp"]) * float(now["gdp_eur_bn"]) / 100.0, 0), Num.f(float(after["deficit_pct_gdp"]) * float(after["gdp_eur_bn"]) / 100.0, 0)]
	if not sheet.contains(arrow):
		_fail("the sheet's deficit leaves the autumn rows out: wanted '%s'" % arrow)
	var birth_row: Node = _panel._sheet.find_child("SheetRow_tax_rates_pct_" + born, true, false)
	var birth_gain := EffectsStrip.money_text(EffectsStrip.balance_bn(now, FinanceBill.preview(_state, {"create": {born: rate}})))
	if birth_row == null or not _text_of(birth_row).contains(birth_gain):
		_fail("the creation row does not show its own balance %s" % birth_gain)
	var gone_row: Node = _panel._sheet.find_child("SheetRow_abolish_tobacco_duty", true, false)
	var gone_gain := EffectsStrip.money_text(EffectsStrip.balance_bn(now, FinanceBill.preview(_state, {"abolish": ["tobacco_duty"]})))
	if gone_row == null or not _text_of(gone_row).contains(gone_gain):
		_fail("the abolition row does not show its own balance %s" % gone_gain)
	# Neither autumn row names who is for and against: no chip under a creation or an abolition.
	for autumn_row in [birth_row, gone_row]:
		if autumn_row != null and (_text_of(autumn_row).contains("▲") or _text_of(autumn_row).contains("▼")):
			_fail("an autumn row carries for/against chips: %s" % _text_of(autumn_row))
	var gone_live := float(ns.tax_rates_pct["tobacco_duty"])
	var places := TaxLibrary.step_decimals(ns, "tobacco_duty")
	if gone_row == null or not _text_of(gone_row).contains("%s → %s" % [LedgerBox.text(gone_live, places), LedgerBox.text(0.0, places)]):
		_fail("the abolition row does not read its rate to nothing")
	# The ranges forecast is fed the bill without the kind put in force (it cannot take one) and with the abolition as a cut to 0.
	var fed: Dictionary = _panel._price.whole(_loader, draft, false)["pending"]
	var fed_taxes: Dictionary = fed.get("tax_rates_pct", {})
	if fed_taxes.has(born) or float(fed_taxes.get("tobacco_duty", -1.0)) != 0.0:
		_fail("the forecast's pending is not the bill less the birth, the abolition as 0: %s" % [fed_taxes])
	_panel._sheet.hide()
	draft.revert()
	# The cache answers for the bill asked, never for another (two bills, then the first again).
	var price := FinancePrice.new()
	price.setup(_state)
	for bill in [{"create": {born: rate}}, {"abolish": ["tobacco_duty"]}, {"create": {born: rate}}]:
		var got: Dictionary = price.after_bill(bill)
		if not is_equal_approx(float(got["deficit_pct_gdp"]), float(FinanceBill.preview(_state, bill)["deficit_pct_gdp"])):
			_fail("the bill cache answered a bill with another's books: %s" % [bill])
	# Past its keep, an evicted bill is priced afresh and a full cache never answers for another bill.
	for i in range(1, FinancePrice.KEEP + 3):
		var bill := {"create": {born: rate * (0.1 + 0.01 * float(i))}}
		var got: Dictionary = price.after_bill(bill)
		if not is_equal_approx(float(got["deficit_pct_gdp"]), float(FinanceBill.preview(_state, bill)["deficit_pct_gdp"])):
			_fail("bill %d past the cache's keep is priced as another bill" % i)


## QA's T1 on #371: a draft with autumn rows must not outlive the autumn month (nothing would reach them to take them back
## and tabling refuses them as "autumn"): when the month ends they leave the draft, the ordinary rows stay, the page says so
## and the refusal, if it is ever shown, names the autumn.
func _check_the_autumn_rows_leave_when_the_month_ends() -> void:
	var ns = _state.player()
	var autumn_month := int(_state.month)
	var draft = _panel.shared_draft()
	draft.revert()
	draft.set_create(_absent, 0.2)
	draft.toggle_abolish("sugar_drinks_levy")
	draft.set_value("spending_pct_gdp", "health", float(ns.spending_pct_gdp["health"]) + 0.5)
	_state.month = autumn_month + 1
	_panel._paint(ns)
	if not draft.births().is_empty() or not draft.abolitions().is_empty():
		_fail("the autumn rows outlived the autumn month: %s" % [draft.bill()])
	if draft.count() != 1:
		_fail("the ordinary row did not stay (%d rows)" % draft.count())
	if not _panel._with.text.contains("autumn month is over"):
		_fail("the page does not say the autumn rows were taken out: %s" % _panel._with.text)
	if not FinanceFoot.reason("autumn").contains("autumn month"):
		_fail("a refusal for the autumn does not name the month")
	_panel._on_moved()
	_panel._paint(ns)
	if _panel._with.text.contains("autumn month is over"):
		_fail("the note outlives the player's next move")
	# QA's T1 on #371 (the play): the note leaves with ANY change to the draft, not only a slider's, and with a load.
	for how in ["put in force", "an editor's verb", "a load"]:
		draft.revert()
		draft.set_create(_absent, 0.2)
		_state.month = autumn_month + 1
		_panel._paint(ns)
		if not _panel._with.text.contains("autumn month is over"):
			_fail("premise (%s): the sweep left no note" % how)
		_state.month = autumn_month
		match how:
			"put in force":
				_panel._on_create(_absent)
			"an editor's verb":
				_panel._on_structure_changed()
			"a load":
				_panel.setup(_state, _loader)
		_panel._paint_due = true
		_panel._dirty = true
		_panel._process(0.0)
		if _panel._with.text.contains("autumn month is over"):
			_fail("the note outlives %s" % how)
	_state.month = autumn_month
	draft.revert()


## The retro review's item 11: a kind IN FORCE at 0 % (the wealth tax, kept in sight) raised by a bill at vote read
## "new, at ..." -- the rows took any tabled row whose live rate is 0 for a birth.
func _check_a_raise_from_zero_at_vote_is_no_birth(ns) -> void:
	var kind := ""
	for k in ns.tax_rates_pct:
		if is_zero_approx(float(ns.tax_rates_pct[k])) and ns.tax_library[k].has("rate_range_pct"):
			kind = String(k)
			break
	if kind == "":
		_fail("premise: no kind in force at 0 %")
		return
	var step := float(ns.tax_library[kind]["rate_range_pct"][1]) / 4.0
	var tabled := FinanceBill.table(_state, _loader, {"tax_rates_pct": {kind: step}})
	if not bool(tabled.get("tabled", false)):
		_fail("setup: the raise does not table: %s" % [tabled])
		return
	_rebuild()
	var cell := _panel._ctx["cells"]["tax_rates_pct:" + kind][0] as Label
	_panel._paint(ns)
	if cell.text.begins_with("new"):
		_fail("a raise of %s, in force at 0 %%, reads '%s' as if the kind were new" % [kind, cell.text])
	_panel._on_withdraw()


func _check_a_bill_at_vote_locks_its_births() -> void:
	var ns = _state.player()
	var tabled := FinanceBill.table(_state, _loader, {"create": {_absent: float(ns.tax_library[_absent]["rate_range_pct"][1]) / 2.0}})
	if not bool(tabled.get("tabled", false)):
		_fail("setup: the birth does not table: %s" % [tabled])
		return
	_rebuild()
	if _node("PutInForce_" + _absent) != null:
		_fail("a kind at vote can be put in force again")
	if not (_panel._ctx["tabled"] as Dictionary).has("tax_rates_pct:" + _absent):
		_fail("a birth at vote is not a locked row")
	var birth_cell := _panel._ctx["cells"]["tax_rates_pct:" + _absent][0] as Label
	_panel._paint(ns)
	if not birth_cell.text.begins_with("new, at"):
		_fail("a birth at vote reads '%s', not 'new, at ...'" % birth_cell.text)
	_panel._on_withdraw()
	_check_a_raise_from_zero_at_vote_is_no_birth(ns)
	# An abolition at vote is a locked row too: its editor never opens and its figure reads from the rate to nothing.
	var abolished := FinanceBill.table(_state, _loader, {"abolish": ["tobacco_duty"]})
	if not bool(abolished.get("tabled", false)):
		_fail("setup: the abolition does not table: %s" % [abolished])
		return
	_panel.open_row("tax_rates_pct", "tobacco_duty")
	_rebuild()
	if _panel._open_id != "":
		_fail("an abolition at vote opened its editor")
	var abolish_cell := _panel._ctx["cells"]["tax_rates_pct:tobacco_duty"][0] as Label
	_panel._paint(ns)
	var rate_now := float(ns.tax_rates_pct["tobacco_duty"])
	var places := TaxLibrary.step_decimals(ns, "tobacco_duty")
	var want_cell: String = Strings.t("from %s to %s") % [LedgerBox.text(rate_now, places), LedgerBox.text(0.0, places) + FinanceRows.unit_text(String(ns.tax_library["tobacco_duty"]["unit"]))]
	if abolish_cell.text != want_cell:
		_fail("an abolition at vote reads '%s', wanted '%s'" % [abolish_cell.text, want_cell])
	_panel._on_withdraw()


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: " + message)


func _finish() -> bool:
	for failure in _failures:
		print("FAIL ", failure)
	print("test_finance_autumn_ui: %s" % ("FAILED (%d)" % _failures.size() if not _failures.is_empty() else "ok"))
	quit(1 if not _failures.is_empty() else 0)
	return true
