extends SceneTree

## Headless test: godot --headless --script res://tests/test_budget_forecast.gd
## Non-zero exit on any failure.
##
## V5.1-0a: the budget window's 24-month forecast runs off the frame
## (src/ui/budget_forecast.gd). The V5.0 play gate scored it as "budget levers
## are broken or freeze the game": every lever move ran two Budget.project()
## calls of the real model inside one frame, ~10 s at 41 nations. What must hold:
##
##   - the panel draws its levers and books without projecting -- the forecast
##     rows say they are computing, and one frame advances the projection only
##     a slice of the way;
##   - what the forecast finally shows IS Budget.project(), to the last bit, for
##     "now" and for the proposed budget (the Tax Code draft merged in);
##   - a lever being moved projects nothing until the levers have been still,
##     however they were moved;
##   - a change of state keeps the last forecast on screen, marked as updating,
##     rather than blanking it;
##   - a closed panel computes nothing, and a new game drops the old one's job.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")
const TaxPanel = preload("res://src/ui/tax_panel.gd")
const Budget = preload("res://src/sim/budget.gd")
const Forecast = preload("res://src/ui/budget_forecast.gd")

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _tax_panel
var _frame := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_state = GameState.new_game(_loader, "FRA")
	_panel = BudgetPanel.new()
	root.add_child(_panel)
	_tax_panel = TaxPanel.new()
	root.add_child(_tax_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_panel.setup(_state, _loader)
	_panel.tax_panel = _tax_panel
	_tax_panel.setup(_state, _loader)
	_panel.show()
	var forecast = _panel._forecast
	_check_the_panel_draws_without_projecting(forecast)
	_check_the_forecast_is_the_projection(forecast)
	_check_a_lever_waits_for_quiet(forecast)
	_check_a_state_change_keeps_the_last_forecast(forecast)
	_check_a_closed_panel_waits(forecast)
	_check_a_new_game_drops_the_job(forecast)
	_finish()
	return true


func _check_the_panel_draws_without_projecting(forecast) -> void:
	_panel._refresh()
	if not forecast.busy() or not forecast.now_path().is_empty():
		_fail("the panel's first draw projected inside the call")
	if not String(_panel._figures["proj_growth"][0]).contains(Forecast.COMPUTING):
		_fail("the forecast row reads '%s' before any projection ran, not computing" % _panel._figures["proj_growth"][0])
	forecast._process(0.0)
	if not forecast.busy():
		_fail("one frame ran a whole 24-month projection -- the freeze, moved one frame later")


func _check_the_forecast_is_the_projection(forecast) -> void:
	forecast.drain()
	if forecast.busy():
		_fail("drain() returned with the forecast still computing")
	if _json(forecast.now_path()) != _json(Budget.project(_state, {}, BudgetPanel.PROJECTION_MONTHS, _loader)):
		_fail("the forecast's 'now' path is not Budget.project()'s")
	_panel._refresh()
	var cell := String(_panel._figures["proj_growth"][0])
	if cell.contains(Forecast.COMPUTING) or cell.contains(Forecast.UPDATING):
		_fail("a finished forecast still reads '%s'" % cell)
	# Nothing edited: the proposed column is the current budget's own forecast.
	if _panel._figures["proj_growth"][1] != _panel._figures["proj_growth"][0]:
		_fail("with nothing edited the proposed forecast reads '%s' against '%s'" % [
			_panel._figures["proj_growth"][1], _panel._figures["proj_growth"][0]])


func _check_a_lever_waits_for_quiet(forecast) -> void:
	var key: String = _panel._lever_keys()[0]
	var slider: HSlider = _panel._sliders[key]
	slider.value = slider.value + 1.0
	_panel._refresh()
	forecast._process(0.0)
	if forecast._job != null:
		_fail("a lever still moving started a projection")
	if not String(_panel._figures["proj_growth"][1]).contains(Forecast.COMPUTING):
		_fail("the proposed forecast reads '%s' for a budget not yet projected" % _panel._figures["proj_growth"][1])
	for _i in range(Forecast.QUIET_FRAMES + 1):
		forecast._process(0.0)
	if forecast._job == null and forecast.busy():
		_fail("the levers were still for %d frames and no projection began" % Forecast.QUIET_FRAMES)
	forecast.drain()
	var pending: Dictionary = _panel._merged_pending()
	if _json(forecast.proposed_path()) != _json(Budget.project(_state, pending, BudgetPanel.PROJECTION_MONTHS, _loader)):
		_fail("the forecast's proposed path is not Budget.project() of the panel's pending")


func _check_a_state_change_keeps_the_last_forecast(forecast) -> void:
	_panel.mark_dirty()
	if not forecast.busy():
		_fail("a change of state left the forecast settled")
	if forecast.now_path().is_empty():
		_fail("a change of state blanked the last forecast")
	_panel._refresh()
	if not String(_panel._figures["proj_growth"][0]).ends_with(Forecast.UPDATING):
		_fail("the last forecast is shown as '%s', not marked as updating" % _panel._figures["proj_growth"][0])


func _check_a_closed_panel_waits(forecast) -> void:
	forecast.drain()
	_panel.mark_dirty()
	_panel.hide()
	forecast._process(0.0)
	if forecast._job != null:
		_fail("a closed panel began a projection")
	_panel.show()
	forecast._process(0.0)
	if forecast._job == null:
		_fail("the reopened panel did not resume its forecast")


func _check_a_new_game_drops_the_job(forecast) -> void:
	var other = GameState.new_game(_loader, "FRA")
	_panel.setup(other, _loader)
	if forecast._job != null or not forecast.now_path().is_empty():
		_fail("a new game kept the old game's projection")


func _json(path: Array) -> String:
	return JSON.stringify(path, "", true, true)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_budget_forecast: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr(message)
	printerr("test_budget_forecast: %d check(s) failed" % _failures.size())
	quit(1)
