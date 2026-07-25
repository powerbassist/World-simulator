extends Control

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")

const PLAYER_NATION_ID := "FRA"

@onready var _clock: Node = $Clock
@onready var _hud: Label = $HUD

const MONTH_NAMES: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

var _state
var _budget_panel


func _ready() -> void:
	var loader := DataLoader.new()
	loader.load_all()

	if not loader.errors.is_empty():
		for e in loader.errors:
			push_error(e)
		return

	var ids := loader.nations.keys()
	ids.sort()
	for id in ids:
		var n: Nation = loader.nations[id]
		var pop_m := n.population / 1_000_000.0
		print("%s %-15s pop %5.1fM   GDP EUR %5.0fbn   debt %5.1f%%" % [
			n.id, n.nation_name, pop_m, n.gdp_eur_bn, n.debt_to_gdp_pct
		])

	_state = GameState.new_game(loader, PLAYER_NATION_ID)
	if not _state.errors.is_empty():
		for e in _state.errors:
			push_error(e)
		return
	_state.year = _clock.year
	_state.month = _clock.month

	_budget_panel = BudgetPanel.new()
	add_child(_budget_panel)
	_budget_panel.setup(_state)
	_budget_panel.hide()
	_budget_panel.committed.connect(_update_hud)

	_clock.day_advanced.connect(_on_day_advanced)
	_clock.month_elapsed.connect(_on_month_elapsed)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_SPACE:
			_clock.toggle_pause()
			_update_hud()
		KEY_1:
			_clock.set_speed(1)
			_update_hud()
		KEY_2:
			_clock.set_speed(2)
			_update_hud()
		KEY_3:
			_clock.set_speed(3)
			_update_hud()
		KEY_B:
			if _budget_panel != null:
				_budget_panel.visible = not _budget_panel.visible
				if _budget_panel.visible:
					_budget_panel.mark_dirty()


## The simulation's whole entry point. Economy first so budget percentages apply
## to this month's GDP; S5 opinion hooks in after both. See docs/economy-model.md.
func _on_month_elapsed(year: int, month: int) -> void:
	if _state == null:
		return
	_state.year = year
	_state.month = month
	Economy.tick_month(_state)
	Budget.tick_month(_state)
	_state.append_history(Budget.snapshot(_state))
	if _budget_panel != null:
		_budget_panel.mark_dirty()


func _on_day_advanced(_year: int, _month: int, _day: int) -> void:
	_update_hud()


func _update_hud() -> void:
	var month_name: String = MONTH_NAMES[_clock.month - 1]
	var state_text := "paused" if _clock.paused else "speed %d" % _clock.speed
	var line := "%s %d, %d — %s" % [month_name, _clock.day, _clock.year, state_text]

	if _state != null:
		var ns = _state.player()
		line += "\nGDP EUR %.0fbn   growth %+.2f%%   unemployment %.1f%%" % [
			ns.gdp_eur_bn, ns.growth_annual_pct, ns.unemployment_pct
		]
		line += "\ndebt %.1f%% of GDP   deficit %+.2f%% of GDP   [B] budget" % [
			ns.debt_to_gdp_pct(), -ns.deficit_pct_gdp
		]

	_hud.text = line
