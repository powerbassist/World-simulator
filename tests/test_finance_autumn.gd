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
const Budget = preload("res://src/sim/budget.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Clock = preload("res://src/core/clock.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_france_has_an_october_gate_and_italy_none()
	_test_a_birth_outside_the_autumn_is_refused()
	_test_a_nation_with_no_autumn_month_never_creates()
	_test_every_autumn_refusal()
	_test_a_carried_birth_puts_the_kind_in_force()
	_test_a_carried_abolition_takes_the_kind_out()
	_test_a_birth_moves_the_bill_position()
	_test_a_reshaped_tax_code_runs_a_year_and_reloads()
	_test_autumn_open_reads_the_gate()
	_test_preview_prices_a_birth_as_the_division_lands_it()
	_test_preview_prices_an_abolition_as_the_division_lands_it()
	_finish()


func _state(nation_id: String, month: int):
	var state = GameState.new_game(_loader, nation_id)
	state.year = 2026
	state.month = month
	return state


## A kind on this nation's library only, named so no shipped data levies it: a birth
## needs a kind that exists and is not levied (the four playable nations levy the
## researched kinds of data/taxes/, so a real kind is no longer free of data).
func _with_test_levy(ns) -> void:
	var row: Dictionary = (_loader.taxes["vat"] as Dictionary).duplicate(true)
	row["id"] = "test_levy"
	row["bloc_salience"] = {"workers": 0.02}
	row["who_pays"] = ["workers"]
	ns.tax_library["test_levy"] = row


func _test_france_has_an_october_gate_and_italy_none() -> void:
	if int(_loader.nations["FRA"].finance_autumn_month) != 10:
		_failures.append("France's autumn month reads %s, not 10 (the PLF's tabling month)" % _loader.nations["FRA"].finance_autumn_month)
	if int(_loader.nations["ITA"].finance_autumn_month) != 0:
		_failures.append("Italy carries an autumn month its data does not list")


func _test_a_birth_outside_the_autumn_is_refused() -> void:
	var state = _state("FRA", 9)
	_with_test_levy(state.player())
	var got := FinanceBill.table(state, _loader, {"create": {"test_levy": 8.0}})
	if not bool(got.get("refused", false)) or not bool(got.get("autumn", false)):
		_failures.append("a birth tabled in September was not refused as out of season: %s" % [got])
	if not state.player().tabled_bill.is_empty():
		_failures.append("a refused birth was written to the register")
	got = FinanceBill.table(state, _loader, {"abolish": ["wealth"]})
	if not bool(got.get("autumn", false)):
		_failures.append("an abolition tabled in September was not refused as out of season")


func _test_a_nation_with_no_autumn_month_never_creates() -> void:
	for month in range(1, 13):
		var state = _state("ITA", month)
		var got := FinanceBill.table(state, _loader, {"abolish": ["wealth"]})
		if not bool(got.get("autumn", false)):
			_failures.append("Italy, with no autumn month, abolished a tax in month %d" % month)
			return


func _test_every_autumn_refusal() -> void:
	var cases := {
		"a birth of a kind already in force": {"create": {"vat": 10.0}},
		"a birth of a kind the library lacks": {"create": {"poll_tax": 1.0}},
		"a birth past the kind's ceiling": {"create": {"test_levy": 41.0}},
		"a birth at a negative rate": {"create": {"test_levy": -1.0}},
		"an abolition of a kind not in force": {"abolish": ["test_levy"]},
		"a kind both created and abolished": {"create": {"test_levy": 5.0}, "abolish": ["test_levy"]},
		"a rate change on a kind not in force": {"tax_rates_pct": {"test_levy": 2.0}},
		"a rate change on a kind being abolished": {"abolish": ["wealth"], "tax_rates_pct": {"wealth": 0.5}},
	}
	for label in cases:
		var state = _state("FRA", 10)
		_with_test_levy(state.player())
		var got := FinanceBill.table(state, _loader, cases[label])
		if not bool(got.get("refused", false)) or not state.player().tabled_bill.is_empty():
			_failures.append("the autumn bill accepted %s: %s" % [label, got])


func _test_a_carried_birth_puts_the_kind_in_force() -> void:
	var state = _state("FRA", 10)
	var ns = state.player()
	_with_test_levy(ns)
	var impulse := float(ns.demand_impulse_pct)
	var got := FinanceBill.table(state, _loader, {"create": {"test_levy": 8.0}})
	if not bool(got.get("tabled", false)):
		_failures.append("an October birth was refused: %s" % [got])
		return
	var result := Division.divide(state, _loader)
	if not bool(result.get("passed", false)):
		_failures.append("a small October birth did not carry in France at the start: %s" % [result])
		return
	if float(ns.tax_rates_pct.get("test_levy", -1.0)) != 8.0 or ns.start_tax_rates_pct.has("test_levy"):
		_failures.append("the born kind reads rate %s, start %s; want 8 from nothing" % [ns.tax_rates_pct.get("test_levy"), ns.start_tax_rates_pct.get("test_levy")])
	var expected := 0.53 * 8.0 * clampf(1.0 - 0.25 * (8.0 - 20.0) / 20.0, EK.EROSION_MIN, EK.EROSION_MAX)
	if float(ns.revenue_pct_gdp.get("test_levy", -1.0)) != expected:
		_failures.append("the born kind yields %s, not %s on the zero-reference curve" % [ns.revenue_pct_gdp.get("test_levy"), expected])
	if float(ns.demand_impulse_pct) >= impulse:
		_failures.append("a new tax raised no contractionary impulse")
	if float(Opinion.issue_satisfaction(ns).get("tax_test_levy", 0.0)) >= 0.0:
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
	_with_test_levy(ns)
	var centroid: Dictionary = ns.coalition_position
	var born := FinanceBillLaw.position(ns, {"create": {"test_levy": 8.0}})
	var raised := FinanceBillLaw.position(ns, {"tax_rates_pct": {"vat": 8.0}})
	if born == centroid or born != raised:
		_failures.append("a birth at 8 reads %s; a VAT-like kind's 8-point rise reads %s" % [born, raised])
	var abolished := FinanceBillLaw.position(ns, {"abolish": ["vat"]})
	var cut := FinanceBillLaw.position(ns, {"tax_rates_pct": {"vat": -float(ns.tax_rates_pct["vat"])}})
	if abolished != cut:
		_failures.append("an abolition reads %s, not a cut to zero %s" % [abolished, cut])


## The whole machine, not one division: a sixth kind in the library (as Content's rows
## will ship), born in October beside the wealth tax's abolition, then twelve months of
## the game's own tick order and a save and a load through SaveManager. Every reader
## that still assumed exactly the five would crash or drop the born kind here.
func _test_a_reshaped_tax_code_runs_a_year_and_reloads() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	var row: Dictionary = (loader.taxes["vat"] as Dictionary).duplicate(true)
	row["id"] = "test_levy"
	row["bloc_salience"] = {"workers": 0.02}
	row["who_pays"] = ["workers"]
	loader.taxes["test_levy"] = row
	var state = GameState.new_game(loader, "FRA")
	state.year = 2026
	state.month = 10
	var ns = state.player()
	FinanceBill.table(state, loader, {"create": {"test_levy": 8.0}, "abolish": ["wealth"]})
	if not bool(Division.divide(state, loader).get("passed", false)):
		_failures.append("year: the October bill did not carry")
		return
	for i in 12:
		WorldMonth.tick_month(state, loader)
	if not ns.tax_rates_pct.has("test_levy") or ns.tax_rates_pct.has("wealth") 			or float(ns.revenue_pct_gdp.get("test_levy", 0.0)) <= 0.0 or ns.revenue_pct_gdp.has("wealth"):
		_failures.append("year: after twelve months the code reads %s, revenue %s" % [ns.tax_rates_pct, ns.revenue_pct_gdp.keys()])
	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 1
	var err := SaveManager.save_game(state, clock, "autumn_reshaped")
	clock.free()
	if err != "":
		_failures.append("year: the save failed: %s" % err)
		return
	var got: Dictionary = SaveManager.load_game("autumn_reshaped", loader)
	if not bool(got.get("ok", false)):
		_failures.append("year: the load was refused: %s" % got.get("error"))
		return
	var back = got["state"].player()
	if back.tax_rates_pct != ns.tax_rates_pct or not back.tax_library.has("test_levy"):
		_failures.append("year: the reloaded code reads %s" % [back.tax_rates_pct])
	Budget.recompute(got["state"], back)
	if float(back.revenue_pct_gdp.get("test_levy", 0.0)) != float(ns.revenue_pct_gdp["test_levy"]):
		_failures.append("year: the reloaded born kind yields %s, not %s" % [back.revenue_pct_gdp.get("test_levy"), ns.revenue_pct_gdp["test_levy"]])


## The gate table() applies, as a question a screen can ask before offering a birth.
func _test_autumn_open_reads_the_gate() -> void:
	if not FinanceBill.autumn_open(_state("FRA", 10), _loader):
		_failures.append("autumn_open: France's October reads closed")
	if FinanceBill.autumn_open(_state("FRA", 9), _loader):
		_failures.append("autumn_open: France's September reads open")
	for month in range(1, 13):
		if FinanceBill.autumn_open(_state("ITA", month), _loader):
			_failures.append("autumn_open: Italy, with no autumn month, reads open in month %d" % month)
			return


## What a reader would see change if preview() wrote through to the live state.
func _fingerprint(state) -> String:
	var ns = state.player()
	return JSON.stringify([state.to_dict(), ns.tax_library, ns.revenue_pct_gdp, ns.tax_rates_pct,
		ns.start_tax_rates_pct, ns.demand_impulse_pct])


## The births road (the card of 2026-11-15, Interface's Finances slice 4): a kind France
## does not levy, priced by preview(), reads what the vote then lands. Before preview()
## the only road was Budget.preview(), which refuses the rate out loud (an ERROR line the
## runner fails) and prices nothing.
func _test_preview_prices_a_birth_as_the_division_lands_it() -> void:
	var state = _state("FRA", 10)
	var ns = state.player()
	if ns.tax_rates_pct.has("bank_levy") or not ns.tax_library.has("bank_levy"):
		_failures.append("birth preview: the fixture needs bank_levy in France's library and not in force")
		return
	var bill := {"create": {"bank_levy": 0.5}}
	var kept := bill.duplicate(true)
	var before := _fingerprint(state)
	var priced := FinanceBill.preview(state, bill)
	if _fingerprint(state) != before or bill != kept:
		_failures.append("birth preview: the live state or the bill moved under preview()")
	if float(priced.get("total_revenue_pct_gdp", 0.0)) <= float(Budget.snapshot(state)["total_revenue_pct_gdp"]):
		_failures.append("birth preview: the born kind adds no revenue")
	if not bool(FinanceBill.table(state, _loader, bill).get("tabled", false)):
		_failures.append("birth preview: the October birth was refused")
		return
	if not bool(Division.divide(state, _loader).get("passed", false)):
		_failures.append("birth preview: the October birth did not carry")
		return
	var landed := Budget.snapshot(state)
	if priced != landed:
		_failures.append("birth preview: priced %s, the vote landed %s" % [_diff(priced, landed), _diff(landed, priced)])


## An abolition: preview() reads what the vote lands, kind erased from force included. A
## kind levied at the start and read by the Gini offset (Tax.gini_policy_offset reads the
## rate against the start rate), so a kind left in force at 0 would read a cut of 30 points
## where the vote lands no kind at all: the erase is visible in the snapshot.
func _test_preview_prices_an_abolition_as_the_division_lands_it() -> void:
	var state = _state("FRA", 10)
	var ns = state.player()
	if float(ns.start_tax_rates_pct.get("capital_gains", 0.0)) <= 0.0:
		_failures.append("abolition preview: the fixture needs capital_gains levied at France's start")
		return
	var bill := {"abolish": ["capital_gains"]}
	var before := _fingerprint(state)
	var priced := FinanceBill.preview(state, bill)
	if _fingerprint(state) != before:
		_failures.append("abolition preview: the live state moved under preview()")
	FinanceBill.table(state, _loader, bill)
	if not bool(Division.divide(state, _loader).get("passed", false)):
		_failures.append("abolition preview: abolishing the wealth tax did not carry")
		return
	var landed := Budget.snapshot(state)
	if priced != landed:
		_failures.append("abolition preview: priced %s, the vote landed %s" % [_diff(priced, landed), _diff(landed, priced)])


## The keys of `a` whose value differs in `b`, for a readable failure.
func _diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for key in a:
		if not b.has(key) or b[key] != a[key]:
			out[key] = a[key]
	return out


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_finance_autumn")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
