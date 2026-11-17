extends SceneTree

## V5.3 e: what one measure would do (src/sim/goal_read.gd): applied once on a copy through
## the game's own appliers and read for every goal at once. Since the Bills second pass the
## read is all that remains (the month's list, its ranking and the two years left with the
## goal tiles); Finances reads it for a line. Pinned: a step costs what the budget preview
## books, the division is the forecast's, a rate step reads through the copy's satisfaction,
## a law put forward reads as gone, and nothing here writes the game.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Bills = preload("res://src/sim/bills.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const GoalRead = preload("res://src/sim/goal_read.gd")
const GK = preload("res://src/sim/goal_read_constants.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	var state = _new_state()
	_check_a_step_costs_what_the_preview_books(state)
	_check_the_division_is_the_forecast(state)
	_check_a_rate_step_reads_through_the_copys_satisfaction(state)
	_check_a_law_put_forward_reads_as_gone()
	_check_the_reads_write_nothing()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_goal_read.gd")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL " + f)
	quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 3
	return state


func _open_laws(state) -> Array:
	return Legislature.available(state.player(), Bills.open(state, state.player(), _loader))


func _check_a_step_costs_what_the_preview_books(state) -> void:
	var ns = state.player()
	var read := GoalRead.read(state, _loader, {"kind": "line", "key": "health", "step": GK.SPENDING_STEP})
	var now := Budget.preview(state, {})
	var after := Budget.preview(state, {"spending_pct_gdp": {"health": float(ns.spending_pct_gdp["health"]) + GK.SPENDING_STEP}})
	var want := (float(now["deficit_pct_gdp"]) * float(now["gdp_eur_bn"]) - float(after["deficit_pct_gdp"]) * float(after["gdp_eur_bn"])) / 100.0
	if not is_equal_approx(float(read["cost_bn"]), want):
		_fail("step: the health step reads %s bn a year, the preview books %s" % [read["cost_bn"], want])


func _check_the_division_is_the_forecast(state) -> void:
	var ns = state.player()
	var parties: Array = _loader.parties["FRA"]
	for law in _open_laws(state).slice(0, 10):
		var forecast := Legislature.resolve_vote(ns, parties, law, Legislature.takes_route(ns, law, false))
		var read := GoalRead.read(state, _loader, {"kind": "law", "id": law.id})
		if bool(read["passes"]) != bool(forecast["passed"]) or int(read["yes"]) != int(forecast["yes_seats"]):
			_fail("chance: %s reads %s, the forecast %s" % [law.id, [read["passes"], read["yes"]], [forecast["passed"], forecast["yes_seats"]]])


func _check_a_rate_step_reads_through_the_copys_satisfaction(state) -> void:
	var ns = state.player()
	var band: Array = ns.tax_library["vat"]["rate_range_pct"]
	var step: float = minf(8.0, float(band[1]) - float(ns.tax_rates_pct["vat"]))
	var measure := {"kind": "rate", "key": "vat", "step": step}
	var read := GoalRead.read(state, _loader, measure)
	var sim = state.duplicate_state()
	var sns = sim.player()
	Budget.recompute(sim, sns)
	Budget.commit(sim, {"tax_rates_pct": {"vat": float(ns.tax_rates_pct["vat"]) + step}})
	Budget.recompute(sim, sns)
	var sat_now := Opinion.issue_satisfaction(ns)
	var sat_then := Opinion.issue_satisfaction(sns)
	var lowered := false
	var weights_matter := false
	for bloc in OpinionK.BLOC_KEYS:
		var today := Opinion.target_of(ns, bloc, sat_now, Opinion.bloc_weights(ns, bloc, sat_now))
		var want := Opinion.target_of(sns, bloc, sat_then, Opinion.bloc_weights(sns, bloc, sat_then)) - today
		var todays_weights := Opinion.target_of(sns, bloc, sat_then, Opinion.bloc_weights(ns, bloc, sat_now)) - today
		if not is_equal_approx(float(read["bloc_target"][bloc]), want):
			_fail("rate: VAT +%s moves %s's heading by %s, Opinion on the copy says %s" % [step, bloc, read["bloc_target"][bloc], want])
		if want < 0.0:
			lowered = true
		if not is_equal_approx(todays_weights, want):
			weights_matter = true
	if not lowered:
		_fail("rate: premise, VAT +%s lowers no bloc's heading" % step)
	if not weights_matter:
		_fail("rate: premise, VAT +%s leaves every bloc's weights as they are today, so the copy's weights are untested" % step)


func _check_a_law_put_forward_reads_as_gone() -> void:
	var state = _new_state()
	var ns = state.player()
	var laws := _open_laws(state)
	var tabled := String(laws[0].id)
	var queued := String(laws[1].id)
	ns.tabled_bill = {"law_id": tabled, "referendum": false, "vote_year": state.year, "vote_month": state.month, "vote_day": 28}
	ns.bill_queue = [{"law_id": queued, "scale": 1.0, "referendum": false, "force": false}]
	for id in [tabled, queued]:
		if not bool(GoalRead.read(state, _loader, {"kind": "law", "id": id}).get("unavailable", false)):
			_fail("held: %s was read as a measure to propose" % id)


func _check_the_reads_write_nothing() -> void:
	var state = _new_state()
	var before := JSON.stringify(state.to_dict())
	for law in _open_laws(state).slice(0, 5):
		GoalRead.read(state, _loader, {"kind": "law", "id": law.id})
	GoalRead.read(state, _loader, {"kind": "line", "key": "health", "step": -GK.SPENDING_STEP})
	if JSON.stringify(state.to_dict()) != before:
		_fail("write: reading measures changed the game")
