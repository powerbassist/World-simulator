extends SceneTree

## V5.3 c' slice B1 (docs/design/v5.3-c-register.md sections 4 and 7): a programme
## priced, tabled as a row of the finance bill, voted, built and opened, and a
## closure. The quote is fixed at tabling (a reshuffle before the vote changes
## nothing), the contract price is drawn once at the vote inside the range shown,
## the capital is billed evenly over the build, the running cost joins the line's
## spending at the opening and moves the nation's figure by the lever's own path.
## Reads tests/fixtures/units/ (round numbers, never a source).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const UnitsLoader = preload("res://src/core/loaders/units_loader.gd")
const Units = preload("res://src/sim/units.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UK = preload("res://src/sim/units_constants.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")
const Sectors = preload("res://src/sim/sectors.gd")
const Budget = preload("res://src/sim/budget.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

const FIXTURE := "res://tests/fixtures/units"
const TYPE := "fixture_school"

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	UnitsLoader.load_units(_loader, FIXTURE)
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_estimate_is_n_times_the_cost_when_spread()
	_test_concentration_costs_more_in_that_region()
	_test_the_range_widens_with_a_vacant_seat()
	_test_the_odds_are_clamped()
	_test_refusals()
	_test_the_bill_carries_the_quote_and_a_reshuffle_changes_nothing()
	_test_the_vote_draws_a_contract_inside_the_range()
	_test_the_build_bills_its_capital_then_opens()
	_test_the_running_cost_moves_the_nation_by_the_lever()
	_test_a_closure_saves_its_running_cost()
	_test_the_game_month_runs_it()
	_test_the_gap_pass_leads()
	_finish()


func _state():
	return GameState.new_game(_loader, "FRA")


func _build(rows: Array) -> Dictionary:
	return {"type": TYPE, "op": UK.OP_BUILD, "rows": rows}


func _test_the_estimate_is_n_times_the_cost_when_spread() -> void:
	var state = _state()
	var ns = state.player()
	# Ten units of stock in each region: CONC_FREE (5 %) of ten is half a unit, so
	# ONE unit per region is already past it. Spread over two regions, one each.
	var q := UnitPrice.quote(state, ns, _loader, _build([{"region": "FR1", "units": 1}, {"region": "FRB", "units": 1}]))
	var free := 2.0 * 50.0 * (1.0 + UK.UNIT_CONC_SLOPE * (0.1 - UK.UNIT_CONC_FREE))
	if not bool(q["ok"]) or absf(float(q["estimate_eur_m"]) - free) > 1e-9:
		_fail("two spread schools are estimated at %s, not %.4f" % [q.get("estimate_eur_m"), free])
	if absf(float(q["lo_eur_m"]) - float(q["estimate_eur_m"]) * (1.0 - float(q["width"]))) > 1e-9 \
			or absf(float(q["hi_eur_m"]) - float(q["estimate_eur_m"]) * (1.0 + float(q["width"]))) > 1e-9:
		_fail("the range is not the estimate x (1 -/+ w): %s" % q)


func _test_concentration_costs_more_in_that_region() -> void:
	var state = _state()
	var ns = state.player()
	var one := UnitPrice.quote(state, ns, _loader, _build([{"region": "FR1", "units": 1}]))
	var four := UnitPrice.quote(state, ns, _loader, _build([{"region": "FR1", "units": 4}]))
	if float(four["estimate_eur_m"]) / 4.0 <= float(one["estimate_eur_m"]):
		_fail("four schools in one region cost no more each than one: %.2f vs %.2f" % [
			float(four["estimate_eur_m"]) / 4.0, float(one["estimate_eur_m"])])
	if float(four["surcharge"]["FR1"]) <= float(one["surcharge"]["FR1"]):
		_fail("the surcharge does not rise with the units ordered: %s" % four["surcharge"])
	# A programme voted in the last twelve months counts toward the region's orders.
	ns.unit_programmes.assign([{"id": "x", "type": TYPE, "op": UK.OP_BUILD, "state": UK.STATE_BUILDING,
		"voted": UnitBuild.now(state), "rows": [{"region": "FR1", "units": 3}]}])
	var after := UnitPrice.quote(state, ns, _loader, _build([{"region": "FR1", "units": 1}]))
	if float(after["estimate_eur_m"]) <= float(one["estimate_eur_m"]):
		_fail("a school ordered after three others this year costs no more")


func _test_the_range_widens_with_a_vacant_seat() -> void:
	var state = _state()
	var ns = state.player()
	Cabinet.vacate(state, "education")
	var q := UnitPrice.quote(state, ns, _loader, _build([{"region": "FR1", "units": 1}]))
	if float(q["width"]) != UK.UNIT_FOG_MAX:
		_fail("a vacant seat gives width %.4f, not the widest %.4f" % [float(q["width"]), UK.UNIT_FOG_MAX])
	var c := UnitPrice.competence(state, ns, _loader, "education")
	if c != 0.0:
		_fail("a vacant seat reads competence %.4f" % c)


func _test_the_odds_are_clamped() -> void:
	var state = _state()
	var ns = state.player()
	var q := UnitPrice.quote(state, ns, _loader, _build([{"region": "FR1", "units": 1}]))
	var c := UnitPrice.competence(state, ns, _loader, "education")
	var want := clampf(0.2 * (UK.UNIT_ODDS_BASE - c), UK.UNIT_ODDS_MIN, UK.UNIT_ODDS_MAX)
	if absf(float(q["odds"]) - want) > 1e-12:
		_fail("the odds read %.4f, not %.4f" % [float(q["odds"]), want])


func _test_refusals() -> void:
	var state = _state()
	var ns = state.player()
	for bad in [
			_build([{"region": "FRM", "units": 1}]),  # no stock: nothing to build on
			_build([{"region": "FR1", "units": 0}]),
			_build([{"region": "UKI", "units": 1}]),
			_build([]),
			{"type": "high_speed_rail", "op": UK.OP_BUILD, "rows": [{"region": "FR1", "units": 1}]},
			{"type": TYPE, "op": UK.OP_DEMOLISH, "rows": [{"region": "FR1", "capacity": 11000}]}]:
		if UnitBuild.refusal(state, ns, _loader, [bad]) == "":
			_fail("a bad row is legal: %s" % bad)
	if UnitBuild.refusal(state, ns, _loader, [{"type": TYPE, "op": UK.OP_DEMOLISH, "rows": [{"region": "FR1", "capacity": 10000}]}]) != "":
		_fail("closing the region's whole stock is refused")
	var many: Array = []
	for i in UK.UNIT_PROGRAMMES_MAX_OPEN + 1:
		many.append(_build([{"region": "FR1", "units": 1}]))
	if UnitBuild.refusal(state, ns, _loader, many) == "":
		_fail("%d programmes at once are legal" % many.size())


func _test_the_bill_carries_the_quote_and_a_reshuffle_changes_nothing() -> void:
	var state = _state()
	var ns = state.player()
	var tabled := FinanceBill.table(state, _loader, {FinanceRows.UNITS: [_build([{"region": "FR1", "units": 2}])]})
	if not bool(tabled.get("tabled", false)):
		_fail("a units row did not table: %s" % tabled)
		return
	var text: Dictionary = ns.tabled_bill["finance"]
	var row: Dictionary = text[FinanceRows.UNITS][0]
	if not row.has("quote") or float(row["quote"]["estimate_eur_m"]) <= 0.0:
		_fail("the tabled row carries no quote: %s" % row)
		return
	var lines: Dictionary = text.get(FinanceRows.UNITS_COST, {})
	if float(lines.get("education", 0.0)) <= 0.0:
		_fail("the bill reads no rise of the education line: %s" % lines)
	var pos := FinanceBillLaw.position(ns, text)
	var empty := FinanceBillLaw.position(ns, {})
	if pos == empty:
		_fail("a units row moves the bill's position nowhere")
	var width := float(row["quote"]["width"])
	Cabinet.vacate(state, "education")
	if float(ns.tabled_bill["finance"][FinanceRows.UNITS][0]["quote"]["width"]) != width:
		_fail("a reshuffle after tabling changed the tabled range")
	# An amendment re-drafts the whole text: the first row keeps its quote.
	FinanceBill.table(state, _loader, {FinanceRows.UNITS: [_build([{"region": "FRB", "units": 1}])]})
	var rows: Array = ns.tabled_bill["finance"][FinanceRows.UNITS]
	if rows.size() != 2 or float(rows[0]["quote"]["width"]) != width:
		_fail("an amendment re-quoted the first row (width %s, was %.4f)" % [rows[0]["quote"]["width"], width])
	if float(rows[1]["quote"]["width"]) != UK.UNIT_FOG_MAX:
		_fail("the row tabled after the reshuffle is not quoted at the vacant seat's width")


func _test_the_vote_draws_a_contract_inside_the_range() -> void:
	var prices := {}
	for run in 2:
		var state = _state()
		var ns = state.player()
		var tabled := FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [_build([{"region": "FR1", "units": 2}])]})
		FinanceRows.apply(state, _loader, ns, tabled)
		if ns.unit_programmes.size() != 1:
			_fail("the vote opened %d programmes" % ns.unit_programmes.size())
			return
		var p: Dictionary = ns.unit_programmes[0]
		var q: Dictionary = tabled[FinanceRows.UNITS][0]["quote"]
		if float(p["contract_eur_m"]) < float(q["lo_eur_m"]) or float(p["contract_eur_m"]) > float(q["hi_eur_m"]):
			_fail("the contract %.4f is outside [%.4f, %.4f]" % [float(p["contract_eur_m"]), float(q["lo_eur_m"]), float(q["hi_eur_m"])])
		if String(p["state"]) != UK.STATE_BUILDING or int(p["months_left"]) != 36:
			_fail("the programme is not building for 36 months: %s" % p)
		prices[run] = float(p["contract_eur_m"])
	if prices[0] != prices[1]:
		_fail("the contract draw is not seeded: %s" % prices)
	# Over many programmes the draw stays inside the range and spans it (band U3's rule).
	var state = _state()
	var ns = state.player()
	var row: Dictionary = FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [_build([{"region": "FR1", "units": 1}])]})[FinanceRows.UNITS][0]
	var lo := float(row["quote"]["lo_eur_m"])
	var hi := float(row["quote"]["hi_eur_m"])
	var low := INF
	var high := -INF
	for i in 200:
		var p: Dictionary = UnitBuild.open(state, ns, _loader, row)
		var c := float(p["contract_eur_m"])
		if c < lo or c > hi:
			_fail("contract %.4f outside [%.4f, %.4f]" % [c, lo, hi])
			break
		low = minf(low, c)
		high = maxf(high, c)
	var bare: Dictionary = UnitBuild.open(state, ns, _loader, _build([{"region": "FRB", "units": 1}]))
	if float(bare["contract_eur_m"]) <= 0.0:
		_fail("a row with no quote opens at %s" % bare.get("contract_eur_m"))
	if low > lo + 0.1 * (hi - lo) or high < hi - 0.1 * (hi - lo):
		_fail("200 draws span only [%.4f, %.4f] of [%.4f, %.4f]" % [low, high, lo, hi])


func _test_the_build_bills_its_capital_then_opens() -> void:
	var state = _state()
	var ns = state.player()
	FinanceRows.apply(state, _loader, ns, FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [_build([{"region": "FR1", "units": 2}])]}))
	var p: Dictionary = ns.unit_programmes[0]
	UnitBuild.tick_month(state, _loader)
	var want: float = 100.0 * float(p["contract_eur_m"]) / 1000.0 / 36.0 * 12.0 / ns.gdp_eur_bn
	if absf(ns.unit_bill_pct_gdp - want) > 1e-12:
		_fail("the capital bill is %.6f %% of GDP, not %.6f" % [ns.unit_bill_pct_gdp, want])
	for i in 35:
		UnitBuild.tick_month(state, _loader)
	if String(ns.unit_programmes[0]["state"]) != UK.STATE_DONE:
		_fail("the programme did not open after 36 months: %s" % ns.unit_programmes[0])
	if Units.capacity_delta(ns, _loader, TYPE, "FR1") != 2000.0:
		_fail("the opened programme stands as %s capacity" % Units.capacity_delta(ns, _loader, TYPE, "FR1"))
	if absf(float(ns.unit_programmes[0]["paid_eur_m"]) - float(p["contract_eur_m"])) > 1e-9:
		_fail("the build paid %.4f of a %.4f contract" % [float(ns.unit_programmes[0]["paid_eur_m"]), float(p["contract_eur_m"])])
	UnitBuild.tick_month(state, _loader)
	if ns.unit_bill_pct_gdp != 0.0:
		_fail("an opened programme still bills capital: %.6f" % ns.unit_bill_pct_gdp)


func _test_the_running_cost_moves_the_nation_by_the_lever() -> void:
	var state = _state()
	var ns = state.player()
	var before := Sectors.quantity(ns, _loader, "education", "schools")
	ns.unit_programmes.assign([{"id": "x", "type": TYPE, "op": UK.OP_BUILD, "state": UK.STATE_DONE,
		"voted": 0, "rows": [{"region": "FR1", "units": 4}]}])
	UnitBuild.tick_month(state, _loader)
	var want: float = 100.0 * 4.0 * 5.0 / 1000.0 / ns.gdp_eur_bn
	if absf(float(ns.unit_running_pct_gdp.get("education", 0.0)) - want) > 1e-12:
		_fail("four schools run %.6f %% of GDP, not %.6f" % [float(ns.unit_running_pct_gdp.get("education", 0.0)), want])
	if Sectors.quantity(ns, _loader, "education", "schools") >= before:
		_fail("the running cost did not lower the nation's pupils per teacher")
	var total: float = ns.total_spending_pct_gdp
	Budget.recompute(state, ns)
	if ns.total_spending_pct_gdp <= total - 1e-12 or absf(ns.total_spending_pct_gdp - total - want) > 1e-9:
		_fail("the budget does not carry the running cost: %.6f -> %.6f" % [total, ns.total_spending_pct_gdp])


func _test_a_closure_saves_its_running_cost() -> void:
	var state = _state()
	var ns = state.player()
	var figure := Units.shown_figure(ns, _loader, TYPE, "FR1")
	FinanceRows.apply(state, _loader, ns, FinanceBill.drafted(state, _loader,
		{FinanceRows.UNITS: [{"type": TYPE, "op": UK.OP_DEMOLISH, "rows": [{"region": "FR1", "capacity": 2000}]}]}))
	var p: Dictionary = ns.unit_programmes[0]
	if int(p["months_left"]) != 12:
		_fail("a closure takes %s months, not the type's 12" % p.get("months_left"))
	UnitBuild.tick_month(state, _loader)
	var once := 2.0 * 50.0 * 0.1
	var want: float = 100.0 * once / 1000.0 / 12.0 * 12.0 / ns.gdp_eur_bn
	if absf(ns.unit_bill_pct_gdp - want) > 1e-12:
		_fail("a closure bills %.6f %% of GDP, not %.6f" % [ns.unit_bill_pct_gdp, want])
	for i in 11:
		UnitBuild.tick_month(state, _loader)
	if float(ns.unit_running_pct_gdp.get("education", 0.0)) >= 0.0:
		_fail("a closed school saves no running cost: %s" % ns.unit_running_pct_gdp)
	if Units.shown_figure(ns, _loader, TYPE, "FR1") <= figure:
		_fail("closing two schools did not raise FR1's pupils per teacher")


func _test_the_game_month_runs_it() -> void:
	if not WorldMonth.STEPS.has("Units"):
		_fail("WorldMonth has no Units step")
	var state = _state()
	var ns = state.player()
	FinanceRows.apply(state, _loader, ns, FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [_build([{"region": "FR1", "units": 1}])]}))
	WorldMonth.tick_month(state, _loader)
	if int(ns.unit_programmes[0]["months_left"]) != 35:
		_fail("a game month did not advance the build: %s" % ns.unit_programmes[0])


## The GLM test-gap pass's leads on #413, each checked against the diff.
func _test_the_gap_pass_leads() -> void:
	var state = _state()
	var ns = state.player()
	if UnitBuild.refusal(state, ns, _loader, [{"type": TYPE, "op": "gift", "rows": [{"region": "FR1", "units": 1}]}]) == "":
		_fail("an unknown op is legal")
	# A closure under way counts toward what stands.
	ns.unit_programmes.assign([{"id": "d", "type": TYPE, "op": UK.OP_DEMOLISH, "state": UK.STATE_BUILDING,
		"voted": UnitBuild.now(state), "rows": [{"region": "FR1", "capacity": 9000}]}])
	if UnitBuild.refusal(state, ns, _loader, [{"type": TYPE, "op": UK.OP_DEMOLISH, "rows": [{"region": "FR1", "capacity": 2000}]}]) == "":
		_fail("closing 2 more of 10 while 9 are being closed is legal")
	# A programme voted more than CONC_MONTHS ago no longer counts toward concentration.
	var fresh := UnitPrice.quote(_state(), _state().player(), _loader, _build([{"region": "FR1", "units": 1}]))
	ns.unit_programmes.assign([{"id": "o", "type": TYPE, "op": UK.OP_BUILD, "state": UK.STATE_DONE,
		"voted": UnitBuild.now(state) - UK.UNIT_CONC_MONTHS - 1, "rows": [{"region": "FR1", "units": 3}]}])
	var stale := UnitPrice.quote(state, ns, _loader, _build([{"region": "FR1", "units": 1}]))
	if float(stale["estimate_eur_m"]) != float(fresh["estimate_eur_m"]):
		_fail("an old programme still raises the price: %.4f vs %.4f" % [float(stale["estimate_eur_m"]), float(fresh["estimate_eur_m"])])
	# An illegal row does not table.
	state = _state()
	ns = state.player()
	var refused := FinanceBill.table(state, _loader, {FinanceRows.UNITS: [_build([{"region": "UKI", "units": 1}])]})
	if bool(refused.get("tabled", false)) or not ns.tabled_bill.is_empty():
		_fail("an illegal units row tabled: %s" % refused)
	# Two rows on one line add up on the bill's line map.
	var text := FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [_build([{"region": "FR1", "units": 1}]), _build([{"region": "FRB", "units": 1}])]})
	var sum := float(text[FinanceRows.UNITS][0]["quote"]["line_pct_gdp_year"]) + float(text[FinanceRows.UNITS][1]["quote"]["line_pct_gdp_year"])
	if absf(float(text[FinanceRows.UNITS_COST]["education"]) - sum) > 1e-12:
		_fail("the line map holds %.6f, not the rows' sum %.6f" % [float(text[FinanceRows.UNITS_COST]["education"]), sum])
	# A row legal at tabling and illegal at the vote is skipped and named.
	var closing := FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [{"type": TYPE, "op": UK.OP_DEMOLISH, "rows": [{"region": "FR1", "capacity": 10000}]}]})
	ns.unit_programmes.assign([{"id": "e", "type": TYPE, "op": UK.OP_DEMOLISH, "state": UK.STATE_DONE,
		"voted": 0, "rows": [{"region": "FR1", "capacity": 5000}]}])
	var skipped: Array = FinanceRows.apply(state, _loader, ns, closing)
	if ns.unit_programmes.size() != 1 or skipped.is_empty() or String(skipped[0].get("units", "")) != TYPE:
		_fail("a row no longer legal at the vote was not skipped: %s, %d programmes" % [skipped, ns.unit_programmes.size()])
	# A closure's quote: no range, no odds, a cut of its line.
	var q := UnitPrice.quote(state, ns, _loader, {"type": TYPE, "op": UK.OP_DEMOLISH, "rows": [{"region": "FRB", "capacity": 2000}]})
	if float(q["lo_eur_m"]) != float(q["estimate_eur_m"]) or float(q["hi_eur_m"]) != float(q["estimate_eur_m"]) 			or float(q["odds"]) != 0.0 or float(q["width"]) != 0.0 or float(q["line_pct_gdp_year"]) >= 0.0:
		_fail("a closure's quote has a range, odds or a rise: %s" % q)
	# The capital term is in the budget, and two lines run side by side.
	state = _state()
	ns = state.player()
	ns.unit_programmes.assign([
		{"id": "s", "type": TYPE, "op": UK.OP_BUILD, "state": UK.STATE_DONE, "voted": 0, "rows": [{"region": "FR1", "units": 1}]},
		{"id": "h", "type": "fixture_hospital", "op": UK.OP_BUILD, "state": UK.STATE_DONE, "voted": 0, "rows": [{"region": "FR1", "units": 1}]}])
	UnitBuild.tick_month(state, _loader)
	if ns.unit_running_pct_gdp.size() != 2 or absf(ns.unit_running_total_pct_gdp()
			- float(ns.unit_running_pct_gdp["education"]) - float(ns.unit_running_pct_gdp["health"])) > 1e-15:
		_fail("two lines' running costs read %s" % ns.unit_running_pct_gdp)
	ns.unit_bill_pct_gdp = 1.0
	Budget.recompute(state, ns)
	var with_bill: float = ns.total_spending_pct_gdp
	ns.unit_bill_pct_gdp = 0.0
	Budget.recompute(state, ns)
	if absf(with_bill - ns.total_spending_pct_gdp - 1.0) > 1e-9:
		_fail("the capital line is not in the budget: %.6f vs %.6f" % [with_bill, ns.total_spending_pct_gdp])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_unit_programmes: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)
