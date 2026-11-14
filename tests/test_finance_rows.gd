extends SceneTree

## V5.3 e: spending verbs as rows of the finance bill (docs/design/finance-bill.md section
## 12; the author's "par la loi de finances", the parent's go of 2026-11-14). A sector
## programme ({"programmes": {sector: action_id}}) and a regional fund ({"funds": {"start":
## [...], "stop": [...]}}) ride the bill: checked by their own verb at tabling, applied by
## their own command at the division if the bill carries, their cost booked by their own
## step. End to end per verb: tabled, carried, applied, booked; refused and withdrawn
## apply nothing; a row illegal by the division is skipped and named, the rest applies.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Government = preload("res://src/sim/government.gd")
const Division = preload("res://src/sim/division.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const Investment = preload("res://src/sim/investment.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

## test_finance_bill's TINKERING: fails in France once the social democrats leave.
const TINKERING := {
	"spending_pct_gdp": {"education": 1.0, "pensions": -1.0, "infrastructure": 1.5},
	"tax_rates_pct": {"income": 1.0, "corporate": -1.0, "vat": 1.0},
}

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_a_programme_through_the_bill()
	_check_a_fund_through_the_bill()
	_check_a_fund_stopped_through_the_bill()
	_check_an_illegal_row_refuses_the_tabling()
	_check_a_defeated_bill_applies_no_row()
	_check_a_withdrawn_bill_applies_no_row()
	_check_a_row_illegal_at_the_division_is_skipped_and_named()
	_check_a_row_moves_the_bill_toward_infrastructure()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_finance_rows.gd")
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
	state.month = 1
	return state


func _region(state) -> String:
	return String(state.regions["FRA"][0].id)


func _fund_rule() -> Dictionary:
	return RegionFunds.limits(_loader)


func _check_a_programme_through_the_bill() -> void:
	var state = _new_state()
	var ns = state.player()
	var blocs: Dictionary = ns.bloc_offset.duplicate()
	var tabled := FinanceBill.table(state, _loader, {"programmes": {"industry": "industrial_renewal"}})
	if not bool(tabled.get("tabled", false)):
		_fail("programme: the row was not tabled: %s" % [tabled])
		return
	if Investment.intensity_of(ns, "industry") != 0.0 or ns.bloc_offset != blocs:
		_fail("programme: the tabling started the programme or wrote its blocs")
	state.month = 2
	var report := WorldMonth.tick_month(state, _loader)
	var division: Dictionary = report.get("division", {})
	if not bool(division.get("passed", false)) or Investment.intensity_of(ns, "industry") != 0.55:
		_fail("programme: the carried bill did not start it at the division: %s, intensity %s" % [division.get("passed"), Investment.intensity_of(ns, "industry")])
	if float(ns.investment_bill_pct_gdp) <= 0.0:
		_fail("programme: the close the bill divided in booked no programme bill")
	if ns.bloc_offset == blocs:
		_fail("programme: the programme's bloc offsets were not written at the division")


func _check_a_fund_through_the_bill() -> void:
	var state = _new_state()
	var ns = state.player()
	var rule := _fund_rule()
	var start := {"region_id": _region(state), "share_pct": float(rule["share_pct"][0]), "years": int(rule["years"][0])}
	var tabled := FinanceBill.table(state, _loader, {"funds": {"start": [start]}})
	if not bool(tabled.get("tabled", false)) or not ns.region_funds.is_empty():
		_fail("fund: the row was not tabled, or the tabling opened it: %s" % [tabled])
		return
	state.month = 2
	WorldMonth.tick_month(state, _loader)
	if RegionFunds.open_funds(ns).size() != 1 or float(ns.region_fund_bill_pct_gdp) <= 0.0:
		_fail("fund: the carried bill did not open it and book its bill: %s, %s" % [RegionFunds.open_funds(ns).size(), ns.region_fund_bill_pct_gdp])


func _check_a_fund_stopped_through_the_bill() -> void:
	var state = _new_state()
	var ns = state.player()
	var rule := _fund_rule()
	var opened := RegionFunds.start(state, ns, _loader, _region(state), float(rule["share_pct"][0]), int(rule["years"][0]))
	var tabled := FinanceBill.table(state, _loader, {"funds": {"stop": [String(opened["id"])]}})
	if not bool(tabled.get("tabled", false)) or RegionFunds.open_funds(ns).size() != 1:
		_fail("stop: not tabled, or the tabling stopped it at once: %s" % [tabled])
		return
	Division.divide(state, _loader)
	if not RegionFunds.open_funds(ns).is_empty():
		_fail("stop: the carried bill left the fund running")


func _check_an_illegal_row_refuses_the_tabling() -> void:
	var cases := {
		"an end with no programme running": {"programmes": {"industry": "end_industrial_programme"}},
		"an action of another sector": {"programmes": {"industry": "farm_modernisation"}},
		"an action that does not exist": {"programmes": {"industry": "no_such_programme"}},
		"a fund in no region": {"funds": {"start": [{"region_id": "atlantis", "share_pct": 1.0, "years": 2}]}},
		"a stop of no fund": {"funds": {"stop": ["fund_0"]}},
	}
	for label in cases:
		var state = _new_state()
		var ns = state.player()
		var blocs: Dictionary = ns.bloc_offset.duplicate()
		var got := FinanceBill.table(state, _loader, cases[label])
		if bool(got.get("tabled", false)) or not bool(got.get("verb", false)):
			_fail("refused: %s was tabled: %s" % [label, got])
		if not ns.tabled_bill.is_empty() or ns.bloc_offset != blocs:
			_fail("refused: %s wrote something" % label)


func _minority(state) -> void:
	var ns = state.player()
	var by_id := {}
	for party in _loader.parties["FRA"]:
		by_id[party.id] = party
	ns.coalition_party_ids.erase("parti_social_uni")
	ns.coalition_position = Government.position_of(ns.seats_by_party, ns.coalition_party_ids, by_id)


func _check_a_defeated_bill_applies_no_row() -> void:
	var state = _new_state()
	var ns = state.player()
	_minority(state)
	var bill: Dictionary = TINKERING.duplicate(true)
	bill["programmes"] = {"industry": "industrial_renewal"}
	FinanceBill.table(state, _loader, bill)
	var blocs: Dictionary = ns.bloc_offset.duplicate()
	var result := Division.divide(state, _loader)
	if bool(result.get("passed", true)):
		_fail("defeated: the staged bill carried (stage broken)")
		return
	if Investment.intensity_of(ns, "industry") != 0.0 or ns.bloc_offset != blocs:
		_fail("defeated: a defeated bill started its programme or wrote its blocs")


func _check_a_withdrawn_bill_applies_no_row() -> void:
	var state = _new_state()
	var ns = state.player()
	FinanceBill.table(state, _loader, {"programmes": {"industry": "industrial_renewal"}})
	FinanceBill.withdraw(state)
	Division.divide(state, _loader)
	if Investment.intensity_of(ns, "industry") != 0.0:
		_fail("withdrawn: a withdrawn bill started its programme")


## A fund opened in the region by another way before the close: the bill's start is no
## longer legal there. It is skipped and named; the bill's rate and programme still apply.
func _check_a_row_illegal_at_the_division_is_skipped_and_named() -> void:
	var state = _new_state()
	var ns = state.player()
	var rule := _fund_rule()
	var region := _region(state)
	var start := {"region_id": region, "share_pct": float(rule["share_pct"][0]), "years": int(rule["years"][0])}
	var vat := float(ns.tax_rates_pct["vat"])
	FinanceBill.table(state, _loader, {"tax_rates_pct": {"vat": 1.0}, "programmes": {"industry": "industrial_renewal"},
		"funds": {"start": [start]}})
	RegionFunds.start(state, ns, _loader, region, float(rule["share_pct"][0]), int(rule["years"][0]))
	var result := Division.divide(state, _loader)
	if not bool(result.get("passed", false)):
		_fail("skipped: the staged bill did not carry (stage broken)")
		return
	if not is_equal_approx(float(ns.tax_rates_pct["vat"]), vat + 1.0) or Investment.intensity_of(ns, "industry") != 0.55:
		_fail("skipped: the rest of the bill did not apply")
	var skipped: Array = result.get("skipped", [])
	if skipped.size() != 1 or String(skipped[0].get("region_id", "")) != region or String(skipped[0].get("reason", "")) == "":
		_fail("skipped: the illegal fund is not named with its reason: %s" % [skipped])
	if RegionFunds.open_funds(ns).size() != 1:
		_fail("skipped: a second fund opened in the region")


## Call 2 (a): a row reads as a rise of the infrastructure line, sized by its cost.
func _check_a_row_moves_the_bill_toward_infrastructure() -> void:
	var state = _new_state()
	var ns = state.player()
	FinanceBill.table(state, _loader, {"programmes": {"industry": "reindustrialisation"}})
	var finance: Dictionary = ns.tabled_bill["finance"]
	var cost := float(finance.get("verbs_pct_gdp", 0.0))
	if cost <= 0.0:
		_fail("position: the programme's cost was not carried on the bill: %s" % [finance])
		return
	var as_line := FinanceBillLaw.position(ns, {"spending_pct_gdp": {"infrastructure": cost}})
	if FinanceBillLaw.position(ns, finance) != as_line or as_line == ns.coalition_position:
		_fail("position: the programme does not read as an infrastructure rise of its cost")
