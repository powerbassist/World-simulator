extends SceneTree

## V5.3 e: the tax library (docs/design/finance-bill.md section 9) and the parent's
## rulings of 2026-11-14: a kind absent from a nation's tax_rates_pct is not in force
## (no revenue line, no issue, no weight, the bloc's other weights NOT renormalised); a
## kind in force the core salience table has no slot for weighs outside the normalised
## sum; a nation may override base_share for a kind in force. The loader's parse step is
## public, so every refusal is tested on a dictionary with no file on disk.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const TaxesLoader = preload("res://src/core/loaders/taxes_loader.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")

## Today's five as the model carried them before the library (economy_constants,
## opinion_constants, the Tax Code's LEVER_MAX, finance_bill_constants.ANCHOR): base,
## erosion, zero reference, demand multiplier, opinion scale, ceiling, progressive,
## the economic anchor of a rise. A golden table on purpose: the library must reproduce
## these to the bit, or every balance regime moves.
const GOLDEN := {
	"income": [0.50, 0.35, 20.0, 0.60, 24.0, 70.0, true, -0.6],
	"corporate": [0.18, 0.55, 25.0, 0.40, 16.0, 70.0, false, -0.6],
	"vat": [0.53, 0.25, 20.0, 0.70, 16.0, 40.0, false, 0.3],
	"capital_gains": [0.02, 0.75, 25.0, 0.35, 4.80, 60.0, false, -0.5],
	"wealth": [4.00, 0.80, 0.50, 0.25, 0.48, 3.0, false, -0.7],
}

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_five_load_first_in_order()
	_test_the_five_reproduce_todays_model()
	_test_every_row_refusal()
	_test_every_nation_refusal()
	_test_a_kind_absent_is_not_in_force()
	_test_a_kind_not_in_force_does_not_renormalise()
	_test_a_new_kind_weighs_outside_the_sum()
	_test_an_override_reaches_revenue_and_not_the_library()
	_test_a_rate_for_a_kind_not_in_force_is_skipped()
	_test_the_library_is_not_saved_and_reattaches()
	_finish()


func _fra():
	var state = GameState.new_game(_loader, "FRA")
	return [state, state.nations["FRA"]]


func _test_the_five_load_first_in_order() -> void:
	var ids: Array = _loader.taxes.keys()
	if ids.slice(0, 5) != TaxesLoader.FIRST:
		_failures.append("the library loads %s first, not today's five in today's order" % [ids.slice(0, 5)])


func _test_the_five_reproduce_todays_model() -> void:
	for id in GOLDEN:
		var g: Array = GOLDEN[id]
		var row: Dictionary = _loader.taxes[id]
		var got := [float(row["base_share"]), float(row["erosion"]), float(row["zero_ref_pct"]),
			float(row["demand_multiplier"]), float(row["opinion_scale_pp"]),
			float(row["rate_range_pct"][1]), bool(row["progressive"]),
			float(row["finance_anchor"]["up"]["economic"])]
		if got != g:
			_failures.append("%s reads %s, today's model is %s" % [id, got, g])
		if float(row["finance_anchor"]["down"]["economic"]) != -float(g[7]):
			_failures.append("%s: a cut's anchor does not mirror a rise's" % id)
		for bloc in OpinionK.BLOC_KEYS:
			var core: Dictionary = OpinionK.BLOC_SALIENCE_BASE[bloc]
			var issue := "tax_%s" % id
			if float(core.get(issue, 0.0)) != float((row["bloc_salience"] as Dictionary).get(bloc, 0.0)):
				_failures.append("%s's %s weight differs from the core table's" % [id, bloc])


func _row() -> Dictionary:
	return (_loader.taxes["vat"] as Dictionary).duplicate(true)


func _refuses(label: String, row: Dictionary, fname := "taxes/vat.json") -> void:
	var errors: Array[String] = []
	TaxesLoader.parse_row(row, fname, errors)
	if errors.is_empty():
		_failures.append("the loader accepted %s" % label)


func _test_every_row_refusal() -> void:
	var errors: Array[String] = []
	TaxesLoader.parse_row(_row(), "taxes/vat.json", errors)
	if not errors.is_empty():
		_failures.append("today's VAT row was refused: %s" % [errors])
	var r := _row()
	r["id"] = "Fuel|Duty"
	_refuses("an id outside [a-z0-9_]{2,24}", r, "taxes/Fuel|Duty.json")
	r = _row()
	r["id"] = "other"
	_refuses("a computed revenue line's id", r, "taxes/other.json")
	_refuses("a file not named after its kind", _row(), "taxes/fuel.json")
	r = _row()
	r["who_pays"] = ["business"]
	_refuses("a payer with no salience weight", r)
	r = _row()
	r["bloc_salience"]["farmers"] = 0.1
	_refuses("a bloc that does not exist", r)
	r = _row()
	r["bloc_salience"]["workers"] = -0.1
	_refuses("a negative weight", r)
	r = _row()
	r["bloc_salience"]["workers"] = 0.09
	_refuses("a core kind whose weight differs from the core table", r)
	r = _row()
	r["rate_range_pct"] = [10.0, 10.0]
	_refuses("a range with no room", r)
	for key in ["base_share", "zero_ref_pct", "opinion_scale_pp"]:
		r = _row()
		r[key] = 0.0
		_refuses("a zero %s" % key, r)
	r = _row()
	r["erosion"] = -0.1
	_refuses("a negative erosion", r)
	r = _row()
	r["progressive"] = 1
	_refuses("a non-boolean progressive", r)
	r = _row()
	r["finance_anchor"] = {"up": {"economic": 0.3}}
	_refuses("an anchor with no social axis and no cut", r)
	r = _row()
	r["name"] = ""
	_refuses("an empty name", r)
	# A new kind with no core slot carries its own weights freely.
	r = _row()
	r["id"] = "fuel_duty"
	r["who_pays"] = ["workers"]
	r["bloc_salience"] = {"workers": 0.02, "rural": 0.04}
	errors = []
	TaxesLoader.parse_row(r, "taxes/fuel_duty.json", errors)
	if not errors.is_empty():
		_failures.append("a new kind with its own weights was refused: %s" % [errors])


class FakeLoader:
	var nations := {}
	var taxes := {}
	var errors: Array[String] = []


func _nation_errors(edit: Callable) -> Array[String]:
	var fake := FakeLoader.new()
	fake.taxes = _loader.taxes
	var n = (_loader.nations["FRA"] as Object).get_script().new()
	n.tax_rates_pct = (_loader.nations["FRA"].tax_rates_pct as Dictionary).duplicate()
	n.tax_revenue_pct_gdp = _loader.nations["FRA"].tax_revenue_pct_gdp
	edit.call(n)
	fake.nations["FRA"] = n
	TaxesLoader.validate_nations(fake)
	return fake.errors


func _test_every_nation_refusal() -> void:
	if not _nation_errors(func(_n): pass).is_empty():
		_failures.append("France's own fiscal block was refused")
	var cases := {
		"a kind the library does not define": func(n): n.tax_rates_pct["poll_tax"] = 1.0,
		"a rate past the kind's ceiling": func(n): n.tax_rates_pct["wealth"] = 3.5,
		"an override on a kind not in force": func(n):
			n.tax_rates_pct.erase("wealth")
			n.tax_base_share["wealth"] = 4.0,
		"an override of 0": func(n): n.tax_base_share["vat"] = 0.0,
		"an autumn month of 13": func(n): n.finance_autumn_month = 13,
		"kinds explaining more than the nation collects": func(n): n.tax_revenue_pct_gdp = 5.0,
	}
	for label in cases:
		if _nation_errors(cases[label]).is_empty():
			_failures.append("the loader accepted %s" % label)
	# Library order, whatever the file's order.
	var fake := FakeLoader.new()
	fake.taxes = _loader.taxes
	var n = (_loader.nations["FRA"] as Object).get_script().new()
	n.tax_rates_pct = {"wealth": 0.0, "vat": 20.0}
	n.tax_revenue_pct_gdp = 40.0
	fake.nations["FRA"] = n
	TaxesLoader.validate_nations(fake)
	if n.tax_rates_pct.keys() != ["vat", "wealth"]:
		_failures.append("a nation's kinds load in file order %s, not library order" % [n.tax_rates_pct.keys()])


func _test_a_kind_absent_is_not_in_force() -> void:
	var pair: Array = _fra()
	var ns = pair[1]
	ns.tax_rates_pct.erase("wealth")
	ns.start_tax_rates_pct.erase("wealth")
	Budget.recompute(pair[0], ns)
	if ns.revenue_pct_gdp.has("wealth"):
		_failures.append("a kind not in force still has a revenue line")
	if Opinion.issue_satisfaction(ns).has("tax_wealth"):
		_failures.append("a kind not in force still has an issue")
	if TaxLibrary.in_force(ns).has("wealth") or not TaxLibrary.in_force(ns).has("vat"):
		_failures.append("in_force reads %s" % [TaxLibrary.in_force(ns)])


func _test_a_kind_not_in_force_does_not_renormalise() -> void:
	var pair: Array = _fra()
	var ns = pair[1]
	var sat := Opinion.issue_satisfaction(ns)
	var full := Opinion.salience_weights(OpinionK.BLOC_SALIENCE_BASE["business"], sat, OpinionK.SALIENCE_GAIN,
		TaxLibrary.salience_patch(ns, "business"))
	if not TaxLibrary.salience_patch(ns, "business").is_empty():
		_failures.append("a nation levying today's five has a non-empty salience patch")
	ns.tax_rates_pct.erase("corporate")
	sat = Opinion.issue_satisfaction(ns)
	var patched := Opinion.salience_weights(OpinionK.BLOC_SALIENCE_BASE["business"], sat, OpinionK.SALIENCE_GAIN,
		TaxLibrary.salience_patch(ns, "business"))
	if float(patched["tax_corporate"]) != 0.0:
		_failures.append("an abolished corporate tax still weighs %s for business" % patched["tax_corporate"])
	for issue in full:
		if issue != "tax_corporate" and float(patched[issue]) != float(full[issue]):
			_failures.append("abolishing corporate tax re-weighted business's %s: %s -> %s" % [issue, full[issue], patched[issue]])


func _sixth(ns, rate: float) -> void:
	var row := _row()
	row["id"] = "fuel_duty"
	row["bloc_salience"] = {"workers": 0.02}
	row["who_pays"] = ["workers"]
	ns.tax_library["fuel_duty"] = row
	ns.tax_rates_pct["fuel_duty"] = rate


func _test_a_new_kind_weighs_outside_the_sum() -> void:
	var pair: Array = _fra()
	var ns = pair[1]
	var base: Dictionary = OpinionK.BLOC_SALIENCE_BASE["workers"]
	var gain := OpinionK.SALIENCE_GAIN
	var before := Opinion.salience_weights(base, Opinion.issue_satisfaction(ns), gain, TaxLibrary.salience_patch(ns, "workers"))
	_sixth(ns, 8.0)
	var sat := Opinion.issue_satisfaction(ns)
	if not sat.has("tax_fuel_duty") or float(sat["tax_fuel_duty"]) >= 0.0:
		_failures.append("a new kind raised from nothing reads no grievance: %s" % sat.get("tax_fuel_duty"))
	var after := Opinion.salience_weights(base, sat, gain, TaxLibrary.salience_patch(ns, "workers"))
	var total := 0.0
	for issue in base:
		total += float(base[issue]) * (1.0 + gain * clampf(-float(sat.get(issue, 0.0)), 0.0, 1.0))
	var severity := clampf(-float(sat["tax_fuel_duty"]), 0.0, 1.0)
	if not is_equal_approx(float(after.get("tax_fuel_duty", 0.0)), 0.02 * (1.0 + gain * severity) / total):
		_failures.append("the new kind weighs %s, not its own weight over the core total" % after.get("tax_fuel_duty"))
	for issue in before:
		if float(after[issue]) != float(before[issue]):
			_failures.append("a new kind re-weighted workers' %s" % issue)
	Budget.recompute(pair[0], ns)
	var expected := 0.53 * 8.0 * clampf(1.0 - 0.25 * (8.0 - 20.0) / 20.0, EK.EROSION_MIN, EK.EROSION_MAX)
	if float(ns.revenue_pct_gdp.get("fuel_duty", -1.0)) != expected:
		_failures.append("the new kind yields %s, not %s on the zero-reference curve" % [ns.revenue_pct_gdp.get("fuel_duty"), expected])


func _test_an_override_reaches_revenue_and_not_the_library() -> void:
	var n = _loader.nations["FRA"]
	var kept: Dictionary = n.tax_base_share.duplicate()
	n.tax_base_share["vat"] = 0.60
	var state = GameState.new_game(_loader, "FRA")
	n.tax_base_share = kept
	var ns = state.nations["FRA"]
	if float(ns.tax_library["vat"]["base_share"]) != 0.60 or float(_loader.taxes["vat"]["base_share"]) != 0.53:
		_failures.append("the override did not stay on France's own row")
	if float(state.nations["DEU"].tax_library["vat"]["base_share"]) != 0.53:
		_failures.append("France's override leaked into Germany's library")
	if float(ns.revenue_pct_gdp["vat"]) != 0.60 * float(ns.tax_rates_pct["vat"]):
		_failures.append("revenue reads %s, not the overridden base" % ns.revenue_pct_gdp["vat"])


func _test_a_rate_for_a_kind_not_in_force_is_skipped() -> void:
	var pair: Array = _fra()
	var ns = pair[1]
	ns.tax_rates_pct.erase("wealth")
	var impulse := float(ns.demand_impulse_pct)
	Budget.apply_pending(ns, {"tax_rates_pct": {"wealth": 1.0}})
	if ns.tax_rates_pct.has("wealth"):
		_failures.append("a law's rate put a kind in force; only the autumn finance bill may")
	if float(ns.demand_impulse_pct) != impulse:
		_failures.append("a skipped rate still raised a demand impulse")


func _test_the_library_is_not_saved_and_reattaches() -> void:
	var pair: Array = _fra()
	var state = pair[0]
	state.nations["FRA"].tax_rates_pct.erase("wealth")
	var copy = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var ns = copy.nations["FRA"]
	if ns.tax_rates_pct.has("wealth"):
		_failures.append("an abolished kind came back on load")
	if JSON.stringify(state.to_dict()).contains("bloc_salience"):
		_failures.append("the library was written into the save")
	if TaxLibrary.reattach(copy, _loader) != "" or ns.tax_library.keys() != _loader.taxes.keys():
		_failures.append("reattach did not rebuild the library")
	ns.tax_rates_pct["poll_tax"] = 1.0
	if TaxLibrary.reattach(copy, _loader) == "":
		_failures.append("a save levying a kind the library lacks was not refused")


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_tax_library")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
