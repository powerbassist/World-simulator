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
const Relations = preload("res://src/core/relations.gd")

var _failures: Array[String] = []
var _state
var _loader
var _panel
var _frame := 0
var _revenue_before := ""
var _spending_before := ""
var _health_after := 0.0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_state = GameState.new_game(_loader, "FRA")
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
	_panel.setup(_state, _loader)
	_panel.show()
	_panel._refresh()

	_revenue_before = _panel._figures["revenue"][1]
	if _revenue_before.is_empty():
		_fail("proposed revenue is blank after setup")
	if _panel._figures["revenue"][0] != _revenue_before:
		_fail("with nothing pending, the now and proposed columns should agree")
	_spending_before = _panel._figures["spending"][1]
	if _spending_before.is_empty():
		_fail("proposed spending is blank after setup")
	if _panel._figures["proj_debt"][0].is_empty():
		_fail("the 24-month projection did not populate")

	# V1.3c. The tariff line reads an em dash rather than "0.00%" while nothing is
	# imposed, which is every game that has never used the verb. A zero invites the
	# player to wonder what they did wrong; a dash says the line is not in play.
	if _panel._figures["tariffs"][0] != "—":
		_fail("the tariff line reads '%s' with nothing imposed, expected an em dash" % _panel._figures["tariffs"][0])

	# And it must appear the moment a measure exists -- a revenue source the player
	# chose and cannot see on the panel is a decorative one.
	_state.measures[Relations.directed_key(_state.player_nation_id, "DEU")] = {
		"action_id": "test", "action_name": "Test", "kind": "tariff",
		"severity": 0.625, "since_year": _state.year, "since_month": _state.month,
		"retaliated": true,
	}
	_panel._refresh()
	if _panel._figures["tariffs"][0] == "—":
		_fail("the tariff line still reads an em dash with a tariff in force")
	_state.measures.clear()
	_panel._refresh()


func _move_a_lever() -> void:
	# V4.2 T5 moved the tax levers to the Tax Code window; the lever this
	# panel still owns is a spending one, and the test's shape is unchanged:
	# move it, watch the proposed column move and the live state hold still.
	# The figure is read off the state rather than named -- France's authored
	# health line is not a round thirty, and the move is a RISE of six so the
	# demand-impulse assertion below has a known sign.
	var start: float = float(_state.player().spending_pct_gdp["health"])
	_health_after = start + 6.0
	_panel._sliders["health"].value = _health_after
	_panel._refresh()

	if absf(float(_panel._pending["spending_pct_gdp"]["health"]) - _health_after) > 0.001:
		_fail("the slider's value_changed did not reach the panel; pending health is %s" % _panel._pending["spending_pct_gdp"]["health"])
	if _panel._figures["spending"][1] == _spending_before:
		_fail("proposed spending did not change when health moved")
	if absf(float(_state.player().spending_pct_gdp["health"]) - start) > 0.001:
		_fail("moving a slider mutated live state: health is now %s" % _state.player().spending_pct_gdp["health"])


func _commit() -> void:
	_panel._on_commit()

	if absf(float(_state.player().spending_pct_gdp["health"]) - _health_after) > 0.001:
		_fail("commit did not apply the pending health rate: %s" % _state.player().spending_pct_gdp["health"])
	if _state.player().demand_impulse_pct <= 0.0:
		_fail("a spending rise should have left a positive demand impulse, got %s" % _state.player().demand_impulse_pct)

	_panel._refresh()
	if _panel._figures["spending"][0] != _panel._figures["spending"][1]:
		_fail("after commit the now and proposed columns disagree: %s vs %s" % [
			_panel._figures["spending"][0], _panel._figures["spending"][1]
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
