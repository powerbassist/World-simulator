extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_of_which.gd
## Non-zero exit on any failure.
##
## V5.3 Finances slice 5: the Budget tab's "of which" lines live on the Books under "Other revenue" and "Other spending"
## (finance_of_which.gd): money the player did not set with a slider, never listed at zero, shut to one line naming the
## parts and opened to each with its figure, signed. Pinned: the read drops a zero and a part under the threshold and keeps
## the sign; a game that uses none of the verbs shows no such line; a part the Budget books shows up shut and then open.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceOfWhich = preload("res://src/ui/finance_of_which.gd")
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
	_check_the_read()
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
			_check_a_quiet_game_lists_nothing()
			_check_the_union_shut_then_open()
			_finish()
	return false


## Zero and a rounding crumb are no part, a net receiver's figure keeps its sign, and each side reads its own keys.
func _check_the_read() -> void:
	var snap := {"gdp_eur_bn": 1000.0, "bloc_transfer_pct_gdp": -0.2, "subsidy_bill_pct_gdp": 0.000001, "energy_bill_pct_gdp": 0.0,
		"tariff_revenue_pct_gdp": 0.3, "rescue_bill_pct_gdp": 0.5}
	var read := FinanceOfWhich.read(snap)
	var names: Array = (read["spending"] as Array).map(func(p) -> String: return String(p["part"]))
	if names != ["the Union", "plant rescues"]:
		_fail("spending parts %s, expected the Union and plant rescues only" % [names])
	if absf(float(read["spending"][0]["bn"]) + 2.0) > 0.0001:
		_fail("the Union's receipt is not signed: %s" % [read["spending"][0]])
	var revenue: Array = (read["revenue"] as Array).map(func(p) -> String: return String(p["part"]))
	if revenue != ["tariffs"]:
		_fail("revenue parts %s, expected tariffs only" % [revenue])


func _of_which_buttons(box: Control) -> Array:
	return box.find_children("OfWhich", "Button", true, false)


## Nothing imposed, nothing deployed, nothing subsidised, no membership: no line at all (a part at zero is never listed).
func _check_a_quiet_game_lists_nothing() -> void:
	var ns = _state.player()
	var snap := Budget.snapshot(_state)
	var read := FinanceOfWhich.read(snap)
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)
	var shut := _of_which_buttons(_panel._spending_box).size() + _of_which_buttons(_panel._revenue_box).size()
	var parts: int = (read["spending"] as Array).size() + (read["revenue"] as Array).size()
	var sides := int(not (read["spending"] as Array).is_empty()) + int(not (read["revenue"] as Array).is_empty())
	if shut != sides:
		_fail("a line for each side with parts: %d of them, %d lines (%d parts, %s)" % [sides, shut, parts, ns.id])


## The Union's contribution is a part for a member: shut, one line naming it; opened, its figure.
func _check_the_union_shut_then_open() -> void:
	var read := FinanceOfWhich.read(Budget.snapshot(_state))
	var union := false
	for p in read["spending"]:
		if String(p["part"]) == "the Union":
			union = true
	if not union:
		_fail("premise: France books no Union contribution at the start")
		return
	var button: Button = _of_which_buttons(_panel._spending_box)[0]
	if not button.tooltip_text.contains(Strings.t("the Union")):
		_fail("the shut line does not name the Union on its hover ('%s')" % button.tooltip_text)
	button.pressed.emit()
	_panel._process(0.0)
	var text := ""
	for label in _panel._spending_box.find_children("*", "Label", true, false):
		text += (label as Label).text + " "
	if not text.contains("of which the Union:"):
		_fail("the opened part does not carry its line ('%s')" % text.left(200))
	if not _of_which_buttons(_panel._spending_box).is_empty():
		_fail("the shut line is still there once the part is opened")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_finance_of_which: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
