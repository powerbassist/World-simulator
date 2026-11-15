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

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0
var _absent := ""


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
			_check_a_bill_at_vote_locks_its_births()
		5:
			return _finish()
	return false


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
