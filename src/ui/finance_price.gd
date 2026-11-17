extends RefCounted

## What a draft does to the books, priced once however many surfaces ask. A row editor's effect line and the
## footer's totals both read the live state against the SAME pending when one row is moved, and a drag asks a
## frame: one Budget.preview() is ~19 ms (V5.1-0a), so the last answers are kept, keyed by the pending and
## by the state's day, and the second asker costs nothing. A copy of the state is priced and never the
## state itself (engine-decision.md rule 2); a day later is another state.

const Budget = preload("res://src/sim/budget.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const SimRows = preload("res://src/sim/finance_rows.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")

## How many pendings are kept: a drag moves one row a frame, and the row's own and the whole draft's differ
## only when two rows are moved. The sheet prices each changed row alone and then the whole bill on every rebuild, so
## the cache holds a dozen (4 evicted a row it was about to ask for again).
const KEEP := 12

var _state
var _stamp := ""
var _now := {}
var _kept := {}


func setup(state) -> void:
	_state = state
	_stamp = ""


## The books with nothing pending: the live position, re-read once a day.
func now() -> Dictionary:
	_check()
	if _now.is_empty():
		_now = Budget.preview(_state, {})
	return _now


## The books with `pending` committed on a copy.
func after(pending: Dictionary) -> Dictionary:
	_check()
	var key := var_to_str(pending)
	if _kept.has(key):
		return _kept[key]
	if _kept.size() >= KEEP:
		_kept.erase(_kept.keys()[0])
	_kept[key] = Budget.preview(_state, pending)
	return _kept[key]


## The balance `pending` books a year, EUR bn (a gain positive), as the strip prints it.
func balance_bn(pending: Dictionary) -> float:
	return EffectsStrip.balance_bn(now(), after(pending))


## {spending_bn, revenue_bn, balance_bn}: how far `pending` moves each side a year.
func moves(pending: Dictionary) -> Dictionary:
	var a := now()
	var b := after(pending)
	return {
		"spending_bn": EffectsStrip.moved_bn(a, b, "total_spending_pct_gdp"),
		"revenue_bn": EffectsStrip.moved_bn(a, b, "total_revenue_pct_gdp"),
		"balance_bn": EffectsStrip.balance_bn(a, b),
	}


## The books with the finance text `bill` carried, on a copy, through the sim's own landing (FinanceBill.preview): the
## only pricing that takes a kind put in force, which Budget.preview refuses. `bill` is the merged text (deltas).
func after_bill(bill: Dictionary) -> Dictionary:
	_check()
	var key := "bill:" + var_to_str(bill)
	if _kept.has(key):
		return _kept[key]
	if _kept.size() >= KEEP:
		_kept.erase(_kept.keys()[0])
	_kept[key] = FinanceBill.preview(_state, bill)
	return _kept[key]


## The balance a bill of one row books a year (a kind put in force, a kind abolished), EUR bn, a gain positive.
func bill_balance_bn(bill: Dictionary) -> float:
	return EffectsStrip.balance_bn(now(), after_bill(bill))


## The WHOLE bill the vote will decide, priced once for every surface that says it (the footer's sentence and the
## sheet's figures, so they cannot drift): the rows at vote merged with the draft (FinanceBill.drafted), priced by
## FinanceBill.preview (births and abolitions included), plus the programmes' and funds' yearly cost, which the vote
## counts as spending (FinanceRows.COST, pct of GDP) and the preview does not apply. `refused` (a draft tabling would
## refuse has no merged text) prices the draft's own rows. {spending_bn, revenue_bn, deficit_now_bn, deficit_after_bn,
## deficit_after_pct, pending}: the moves each side a year, the deficit today (no bill) and with the whole bill passed,
## and the Budget-shaped pending the ranges forecast is fed (the same bill, less the births, which that forecast cannot
## take).
func whole(loader, draft, refused: bool) -> Dictionary:
	var bill: Dictionary = draft.bill()
	var cost_pct := 0.0
	if not refused:
		bill = FinanceBill.drafted(_state, loader, bill)
		cost_pct = SimRows.yearly_cost(bill)
	var a := now()
	var b := after_bill(bill)
	var gdp := float(b["gdp_eur_bn"])
	var extra := cost_pct * gdp / 100.0
	var deficit_after := float(b["deficit_pct_gdp"]) * gdp / 100.0 + extra
	var forecast_bill := bill.duplicate(true)
	forecast_bill.erase(FinanceBill.CREATE)
	return {
		"spending_bn": EffectsStrip.moved_bn(a, b, "total_spending_pct_gdp") + extra,
		"revenue_bn": EffectsStrip.moved_bn(a, b, "total_revenue_pct_gdp"),
		"deficit_now_bn": float(a["deficit_pct_gdp"]) * float(a["gdp_eur_bn"]) / 100.0,
		"deficit_after_bn": deficit_after,
		"deficit_after_pct": deficit_after / gdp * 100.0 if gdp > 0.0 else 0.0,
		"pending": FinanceBill.absolute(_state.player(), forecast_bill),
	}


## The state moved behind the page (a law, an event): both are due again.
func reset() -> void:
	_stamp = ""


func _check() -> void:
	var stamp := "%d|%d|%d|%s" % [_state.year, _state.month, _state.day, str(_state.player().tabled_bill)]
	if stamp != _stamp:
		_stamp = stamp
		_now = {}
		_kept = {}
