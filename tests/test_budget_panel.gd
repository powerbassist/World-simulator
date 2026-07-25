extends SceneTree

## Headless test: godot --headless --script res://tests/test_budget_panel.gd
## Non-zero exit on any failure.
##
## A smoke test for the budget screen — the one part of S4 no other headless test
## reaches. It does not check pixels; it checks that the control tree builds,
## that the figures populate, that moving a lever changes the proposed column
## without touching live state, and that Commit is the only thing that does.
##
## Driven a frame at a time through MainLoop's _process, because two things only
## happen once a node is actually in the tree: _ready() runs, and Range emits
## value_changed. Setting a slider's value outside the tree changes the number
## and fires nothing, which would make this test pass against a panel whose
## signals were never connected. See docs/engine-decision.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")

var _failures: Array[String] = []
var _state
var _panel
var _frame := 0
var _revenue_before := ""


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return

	_state = GameState.new_game(loader, "FRA")
	if not _state.errors.is_empty():
		_failures.append("new_game reported %s" % [_state.errors])
		_finish()
		return

	_panel = BudgetPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_setup()
		2:
			_move_a_lever()
		3:
			_commit()
			_finish()
	return false


func _setup() -> void:
	_panel.setup(_state)
	_panel.show()
	_panel._refresh()

	_revenue_before = _panel._figures["revenue"][1].text
	if _revenue_before.is_empty():
		_fail("proposed revenue is blank after setup")
	if _panel._figures["revenue"][0].text != _revenue_before:
		_fail("with nothing pending, the now and proposed columns should agree")
	if _panel._figures["proj_debt"][0].text.is_empty():
		_fail("the 24-month projection did not populate")


func _move_a_lever() -> void:
	_panel._sliders["income"].value = 28.0
	_panel._refresh()

	if float(_panel._pending["tax_rates_pct"]["income"]) != 28.0:
		_fail("the slider's value_changed did not reach the panel; pending income is %s" % _panel._pending["tax_rates_pct"]["income"])
	if _panel._figures["revenue"][1].text == _revenue_before:
		_fail("proposed revenue did not change when income tax moved 20 -> 28")
	if absf(float(_state.player().tax_rates_pct["income"]) - 20.0) > 0.001:
		_fail("moving a slider mutated live state: income rate is now %s" % _state.player().tax_rates_pct["income"])


func _commit() -> void:
	_panel._on_commit()

	if absf(float(_state.player().tax_rates_pct["income"]) - 28.0) > 0.001:
		_fail("commit did not apply the pending income rate: %s" % _state.player().tax_rates_pct["income"])
	if _state.player().demand_impulse_pct >= 0.0:
		_fail("a tax rise should have left a negative demand impulse, got %s" % _state.player().demand_impulse_pct)

	_panel._refresh()
	if _panel._figures["revenue"][0].text != _panel._figures["revenue"][1].text:
		_fail("after commit the now and proposed columns disagree: %s vs %s" % [
			_panel._figures["revenue"][0].text, _panel._figures["revenue"][1].text
		])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_budget_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
