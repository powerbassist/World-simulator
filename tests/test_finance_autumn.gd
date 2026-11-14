extends SceneTree

## V5.3 e: the autumn finance bill (docs/design/finance-bill.md sections 5 and 9, the
## author's call: a tax is created or abolished only in the autumn finance bill). A
## nation's `government.finance_bill.autumn_month` names the month; a nation with none
## has no autumn gate. A bill tabled that month may carry {"create": {kind: rate}} and
## {"abolish": [kind]}; any other month refuses them. At passage a created kind goes into
## force from a start of 0 (the zero-reference curve prices it), an abolished one is cut
## to 0 and leaves force.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Division = preload("res://src/sim/division.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const EK = preload("res://src/sim/economy_constants.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_france_has_an_october_gate_and_germany_none()
	_test_a_birth_outside_the_autumn_is_refused()
	_test_a_nation_with_no_autumn_month_never_creates()
	_test_every_autumn_refusal()
	_test_a_carried_birth_puts_the_kind_in_force()
	_test_a_carried_abolition_takes_the_kind_out()
	_test_a_birth_moves_the_bill_position()
	_finish()


func _state(nation_id: String, month: int):
	var state = GameState.new_game(_loader, nation_id)
	state.year = 2026
	state.month = month
	return state


## A sixth kind on this nation's library only: the shipped data holds today's five,
## all in force everywhere, so a birth needs a kind that exists and is not levied.
func _with_fuel_duty(ns) -> void:
	var row: Dictionary = (_loader.taxes["vat"] as Dictionary).duplicate(true)
	row["id"] = "fuel_duty"
	row["bloc_salience"] = {"workers": 0.02}
	row["who_pays"] = ["workers"]
	ns.tax_library["fuel_duty"] = row


func _test_france_has_an_october_gate_and_germany_none() -> void:
	if int(_loader.nations["FRA"].finance_autumn_month) != 10:
		_failures.append("France's autumn month reads %s, not 10 (the PLF's tabling month)" % _loader.nations["FRA"].finance_autumn_month)
	if int(_loader.nations["DEU"].finance_autumn_month) != 0:
		_failures.append("Germany carries an autumn month its data does not list")


func _test_a_birth_outside_the_autumn_is_refused() -> void:
	var state = _state("FRA", 9)
	_with_fuel_duty(state.player())
	var got := FinanceBill.table(state, _loader, {"create": {"fuel_duty": 8.0}})
	if not bool(got.get("refused", false)) or not bool(got.get("autumn", false)):
		_failures.append("a birth tabled in September was not refused as out of season: %s" % [got])
	if not state.player().tabled_bill.is_empty():
		_failures.append("a refused birth was written to the register")
	got = FinanceBill.table(state, _loader, {"abolish": ["wealth"]})
	if not bool(got.get("autumn", false)):
		_failures.append("an abolition tabled in September was not refused as out of season")


func _test_a_nation_with_no_autumn_month_never_creates() -> void:
	for month in range(1, 13):
		var state = _state("DEU", month)
		var got := FinanceBill.table(state, _loader, {"abolish": ["wealth"]})
		if not bool(got.get("autumn", false)):
			_failures.append("Germany, with no autumn month, abolished a tax in month %d" % month)
			return


func _test_every_autumn_refusal() -> void:
	var cases := {
		"a birth of a kind already in force": {"create": {"vat": 10.0}},
		"a birth of a kind the library lacks": {"create": {"poll_tax": 1.0}},
		"a birth past the kind's ceiling": {"create": {"fuel_duty": 41.0}},
		"a birth at a negative rate": {"create": {"fuel_duty": -1.0}},
		"an abolition of a kind not in force": {"abolish": ["fuel_duty"]},
		"a kind both created and abolished": {"create": {"fuel_duty": 5.0}, "abolish": ["fuel_duty"]},
		"a rate change on a kind not in force": {"tax_rates_pct": {"fuel_duty": 2.0}},
		"a rate change on a kind being abolished": {"abolish": ["wealth"], "tax_rates_pct": {"wealth": 0.5}},
	}
	for label in cases:
		var state = _state("FRA", 10)
		_with_fuel_duty(state.player())
		var got := FinanceBill.table(state, _loader, cases[label])
		if not bool(got.get("refused", false)) or not state.player().tabled_bill.is_empty():
			_failures.append("the autumn bill accepted %s: %s" % [label, got])


func _test_a_carried_birth_puts_the_kind_in_force() -> void:
	var state = _state("FRA", 10)
	var ns = state.player()
	_with_fuel_duty(ns)
	var impulse := float(ns.demand_impulse_pct)
	var got := FinanceBill.table(state, _loader, {"create": {"fuel_duty": 8.0}})
	if not bool(got.get("tabled", false)):
		_failures.append("an October birth was refused: %s" % [got])
		return
	var result := Division.divide(state, _loader)
	if not bool(result.get("passed", false)):
		_failures.append("a small October birth did not carry in France at the start: %s" % [result])
		return
	if float(ns.tax_rates_pct.get("fuel_duty", -1.0)) != 8.0 or ns.start_tax_rates_pct.has("fuel_duty"):
		_failures.append("the born kind reads rate %s, start %s; want 8 from nothing" % [ns.tax_rates_pct.get("fuel_duty"), ns.start_tax_rates_pct.get("fuel_duty")])
	var expected := 0.53 * 8.0 * clampf(1.0 - 0.25 * (8.0 - 20.0) / 20.0, EK.EROSION_MIN, EK.EROSION_MAX)
	if float(ns.revenue_pct_gdp.get("fuel_duty", -1.0)) != expected:
		_failures.append("the born kind yields %s, not %s on the zero-reference curve" % [ns.revenue_pct_gdp.get("fuel_duty"), expected])
	if float(ns.demand_impulse_pct) >= impulse:
		_failures.append("a new tax raised no contractionary impulse")
	if float(Opinion.issue_satisfaction(ns).get("tax_fuel_duty", 0.0)) >= 0.0:
		_failures.append("a new tax is not a grievance on its own issue")


func _test_a_carried_abolition_takes_the_kind_out() -> void:
	var state = _state("FRA", 10)
	var ns = state.player()
	ns.tax_rates_pct["wealth"] = 1.0
	var impulse := float(ns.demand_impulse_pct)
	FinanceBill.table(state, _loader, {"abolish": ["wealth"]})
	var result := Division.divide(state, _loader)
	if not bool(result.get("passed", false)):
		_failures.append("abolishing the wealth tax did not carry in France at the start: %s" % [result])
		return
	if ns.tax_rates_pct.has("wealth") or ns.start_tax_rates_pct.has("wealth") or ns.revenue_pct_gdp.has("wealth"):
		_failures.append("the abolished kind is still in force: %s" % [ns.tax_rates_pct])
	if float(ns.demand_impulse_pct) <= impulse:
		_failures.append("abolishing a levied tax raised no expansionary impulse")
	if Opinion.issue_satisfaction(ns).has("tax_wealth"):
		_failures.append("the abolished kind still carries an issue")


func _test_a_birth_moves_the_bill_position() -> void:
	var state = _state("FRA", 10)
	var ns = state.player()
	_with_fuel_duty(ns)
	var centroid: Dictionary = ns.coalition_position
	var born := FinanceBillLaw.position(ns, {"create": {"fuel_duty": 8.0}})
	var raised := FinanceBillLaw.position(ns, {"tax_rates_pct": {"vat": 8.0}})
	if born == centroid or born != raised:
		_failures.append("a birth at 8 reads %s; a VAT-like kind's 8-point rise reads %s" % [born, raised])
	var abolished := FinanceBillLaw.position(ns, {"abolish": ["vat"]})
	var cut := FinanceBillLaw.position(ns, {"tax_rates_pct": {"vat": -float(ns.tax_rates_pct["vat"])}})
	if abolished != cut:
		_failures.append("an abolition reads %s, not a cut to zero %s" % [abolished, cut])


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_finance_autumn")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
