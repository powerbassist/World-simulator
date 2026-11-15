extends RefCounted

## V5.3 e: the Finances screen's reads (Interface's direction A, the author's pick; Gameplay's
## brief, section 6). Reads only, each over a rule the game already runs; nothing here writes
## the game, and no second rule is written.
##
##   draft()       a finance draft before it is tabled: the refusal tabling would give
##                 (FinanceBill.refusal) and the division it would meet now, read on the very
##                 text the tabling would write (FinanceBill.drafted, merged with the bill
##                 already before the Assembly). The two-year ranges are the Budget window's
##                 own forecast (budget_forecast.gd), fed the same pending.
##   line_blocs()  who a spending line is for, and what a step of it does to each bloc:
##                 `weights`, each bloc's weight on the line's own issue (what Opinion weighs,
##                 Opinion.bloc_weights, live: the spending side's `who_pays`); `gains` and
##                 `loses`, each bloc's heading after the line rises by the goal read's step,
##                 the deficit's cost included (GoalRead.read on its copy, ~30 ms, so on demand,
##                 never each frame). At a game's start a rise is a net loss for nearly every
##                 bloc (measured: health +0.5 lowers all six), so the chips read `weights`.
##   step_yields() what one step of each kind in force yields a year, both ways: the Budget's
##                 own revenue arithmetic (Budget.revenue_lines), so equal to the deficit
##                 change a preview books. A step tabling would refuse (outside the kind's
##                 band, FinanceBill.range_refusal) has no figure.
##   other_parts() what the budget's two unset lines hold, as the parts the model keeps. Other
##                 revenue is the calibration residual (fixed at new game so the opening
##                 revenue equals the nation's real figure: social contributions, local taxes,
##                 everything no rate sets) and what laws have added. Other spending is one
##                 authored figure, kept whole: the data holds no split of it.

const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const GoalRead = preload("res://src/sim/goal_read.gd")
const GK = preload("res://src/sim/goal_read_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Tax = preload("res://src/sim/tax.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")


## {refusal, vote}: `refusal` "" when tabling would take `bill` now, else its flag; `vote` the
## division the drafted text would meet now (FinanceBill.resolve's shape), {} when refused.
static func draft(state, loader, bill: Dictionary) -> Dictionary:
	var ns = state.player()
	var why := FinanceBill.refusal(state, loader, bill)
	for key in why:
		if key != "tabled" and key != "refused":
			return {"refusal": String(key), "vote": {}}
	var held: Dictionary = ns.tabled_bill
	var id := String(held.get("law_id", "")) if not held.is_empty() else FinanceBillLaw.id_for(state)
	var law = FinanceBillLaw.law(ns, {"law_id": id, "finance": FinanceBill.drafted(state, loader, bill)})
	return {"refusal": "", "vote": FinanceBill.resolve(ns, loader.parties.get(ns.id, []), law)}


## {weights: [[bloc, weight], ...], gains: [[bloc, points], ...], loses: [[bloc, points], ...]},
## each most first: the blocs that weigh the line's issue (a bloc with no weight on it is
## absent), and each bloc's approval target moved by `key` rising one goal-read step (a bloc
## left still is in neither).
static func line_blocs(state, loader, key: String) -> Dictionary:
	var ns = state.player()
	var sat := Opinion.issue_satisfaction(ns)
	var weights := []
	for bloc in OpinionK.BLOC_KEYS:
		var w := float(Opinion.bloc_weights(ns, bloc, sat).get(key, 0.0))
		if w > 0.0:
			weights.append([String(bloc), w])
	weights.sort_custom(_most_first)
	var read := GoalRead.read(state, loader, {"kind": "line", "key": key, "step": GK.SPENDING_STEP})
	var gains := []
	var loses := []
	for bloc in read["bloc_target"]:
		var pts := float(read["bloc_target"][bloc])
		if pts > 0.0:
			gains.append([String(bloc), pts])
		elif pts < 0.0:
			loses.append([String(bloc), pts])
	gains.sort_custom(_most_first)
	loses.sort_custom(_most_first)
	return {"weights": weights, "gains": gains, "loses": loses}


## [bloc, value] pairs, the largest size first (a loss's size is its magnitude).
static func _most_first(a: Array, b: Array) -> bool:
	return absf(float(a[1])) > absf(float(b[1]))


## kind -> {step, up_bn, down_bn}, every kind in force: the revenue one step of its rate
## brings a year (bn EUR; down_bn is negative), at today's GDP. A direction tabling would
## refuse is absent.
static func step_yields(ns) -> Dictionary:
	var out := {}
	var factor := Tax.progressivity_base_factor(ns)
	var now := Budget.revenue_lines(ns.tax_rates_pct, ns.start_tax_rates_pct, ns.tax_library, factor)
	for kind in ns.tax_rates_pct:
		var step := TaxLibrary.step_pct(ns, kind)
		var row := {"step": step}
		for dir in [["up_bn", step], ["down_bn", -step]]:
			if not FinanceBill.range_refusal(ns, {"tax_rates_pct": {kind: dir[1]}}).is_empty():
				continue
			var rates: Dictionary = ns.tax_rates_pct.duplicate()
			rates[kind] = float(rates[kind]) + float(dir[1])
			var moved := Budget.revenue_lines(rates, ns.start_tax_rates_pct, ns.tax_library, factor)
			row[dir[0]] = (float(moved[kind]) - float(now[kind])) * float(ns.gdp_eur_bn) / 100.0
		out[kind] = row
	return out


## {revenue: [{key, bn}], spending: [{key, bn}]}: the parts of the unset lines, bn EUR a year.
## revenue: "residual" (the calibration residual) and "laws" (what laws in force add);
## spending: "unsplit" (the authored figure, no breakdown in the data).
static func other_parts(ns) -> Dictionary:
	var gdp := float(ns.gdp_eur_bn) / 100.0
	return {
		"revenue": [
			{"key": "residual", "bn": float(ns.other_revenue_pct_gdp) * gdp},
			{"key": "laws", "bn": float(ns.law_other_revenue_pct_gdp) * gdp},
		],
		"spending": [{"key": "unsplit", "bn": float(ns.other_spending_pct_gdp) * gdp}],
	}
