extends SceneTree

## Investment.refusal_reason (the parent's card, 2026-11-16): a disabled verb shows the
## sim's own refusal reason, as Companies, Cabinet, Diplomacy and Dissolution already do.
## One case per reason, and the reason is empty exactly when execute() applies the action
## (every shipped action, in a fresh game and with each sector's programme running).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Investment = preload("res://src/sim/investment.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_a_running_programme_refuses_a_second()
	_test_ending_needs_a_running_programme()
	_test_a_sector_with_no_register_refuses()
	_test_every_other_field_has_its_reason()
	_test_empty_exactly_when_execute_applies()
	_finish()


func _state():
	return GameState.new_game(_loader, "FRA")


func _action(id: String):
	for a in _loader.investment_actions:
		if a.id == id:
			return a
	return null


func _test_a_running_programme_refuses_a_second() -> void:
	var state = _state()
	var ns = state.player()
	if Investment.refusal_reason(state, ns, _loader, _action("farm_modernisation")) != "":
		_failures.append("a fresh game refuses a farm programme: %s" % Investment.refusal_reason(state, ns, _loader, _action("farm_modernisation")))
	Investment.execute(state, ns, _loader.investment_actions, _action("farm_modernisation"))
	var why := Investment.refusal_reason(state, ns, _loader, _action("agricultural_transformation"))
	if why != "a programme already runs in this sector":
		_failures.append("a second farm programme reads '%s'" % why)


func _test_ending_needs_a_running_programme() -> void:
	var state = _state()
	var ns = state.player()
	var why := Investment.refusal_reason(state, ns, _loader, _action("end_farm_programme"))
	if why != "no programme runs in this sector":
		_failures.append("ending a programme that never started reads '%s'" % why)


func _test_a_sector_with_no_register_refuses() -> void:
	var state = _state()
	var ns = state.player()
	ns.sector_investment.erase("agriculture")
	var why := Investment.refusal_reason(state, ns, _loader, _action("farm_modernisation"))
	if why != "this nation runs no programme register for this sector":
		_failures.append("a sector with no register reads '%s'" % why)
	if bool(Investment.execute(state, ns, _loader.investment_actions, _action("farm_modernisation"))["applied"]):
		_failures.append("execute applied an action its sector has no register for")


## The fields a precondition may read beside investment_active (Investment._read_field):
## no shipped action uses them today, so each is put on a shipped action, then restored.
func _test_every_other_field_has_its_reason() -> void:
	var cases := {
		"investment_count": "too many programmes already run",
		"deficit_pct_gdp": "the deficit does not allow it",
		"debt_to_gdp_pct": "the debt does not allow it",
		"unemployment_pct": "unemployment does not allow it",
		"overall_approval_pct": "approval does not allow it",
	}
	for field in cases:
		var state = _state()
		var ns = state.player()
		var action = _action("farm_modernisation")
		var shipped: Array = action.preconditions
		action.preconditions = [{"field": field, "op": "<", "value": -1.0e9}]
		var why := Investment.refusal_reason(state, ns, _loader, action)
		action.preconditions = shipped
		if why != cases[field]:
			_failures.append("a failed %s precondition reads '%s', not '%s'" % [field, why, cases[field]])


func _test_empty_exactly_when_execute_applies() -> void:
	for running in [false, true]:
		for action in _loader.investment_actions:
			var state = _state()
			var ns = state.player()
			if running:
				for start in ["farm_modernisation", "industrial_renewal", "digital_services_push"]:
					Investment.execute(state, ns, _loader.investment_actions, _action(start))
			var why := Investment.refusal_reason(state, ns, _loader, action)
			var applied := bool(Investment.execute(state, ns, _loader.investment_actions, action)["applied"])
			if (why == "") != applied:
				_failures.append("%s (programmes running: %s): reason '%s' but execute applied=%s" % [action.id, running, why, applied])


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_investment_refusal")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
