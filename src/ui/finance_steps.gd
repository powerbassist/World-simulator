extends RefCounted

## The deficit walked change by change, the bill's rail (finance_foot.gd) and its document (finance_sheet.gd) alike:
## the same chart on both, so the two can never disagree. Today, the bill already before the Assembly (an
## amendment's first step), each drafted change a signed step, what the rows alone do not explain, the bill. It
## plots the BALANCE (the author, 2026-11-28): a deficit reaches left of zero, a change that widens it steps left,
## and a step is signed as the list signs it. The two totals print their size.

const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const ChartWaterfall = preload("res://src/ui/chart_waterfall.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

## A residual under this (bn a year) is rounding, not a step.
const RESIDUAL_BN := 0.05
## The chart's name column at text 100: a change and its figures ("Health, 11.0 → 12.5").
const LABEL_W := 190.0


## Fills `chart` from the draft's rows; `whole` is FinancePrice.whole of the same draft, `refused` whether tabling
## refuses it (a refused draft has no merged text, so the bill already tabled is no step of it).
static func setup(chart: ChartWaterfall, state, loader, draft, price, whole: Dictionary, refused: bool) -> void:
	var ns = state.player()
	var steps := []
	var walked := 0.0
	# An amendment's money is the whole bill's: the bill already tabled is its own first step (pass 2 T6 on #443).
	if FinanceBillLaw.tabled(ns) != null and not refused:
		var alone: Dictionary = price.tabled(loader)
		walked = float(alone["deficit_now_bn"]) - float(alone["deficit_after_bn"])
		steps.append({"label": Strings.t("The bill before the Assembly"), "value": walked})
	for row in draft.rows():
		var gain: float = price.row_balance_bn(row)
		steps.append({"label": "%s, %s" % [FinanceRows.change_label(ns, row), FinanceRows.change_figures(ns, row)], "value": gain})
		walked += gain
	var now := -float(whole["deficit_now_bn"])
	var after := -float(whole["deficit_after_bn"])
	if absf(after - now - walked) >= RESIDUAL_BN:
		steps.append({"label": Strings.t("Together, and what the rows alone miss"), "value": after - now - walked})
	chart.setup(_total(Strings.t("Today"), now), steps, _total(Strings.t("With the bill"), after), {"label_w": LABEL_W, "worse_up": false})


## A total's row: where the balance stands, printed as its size (its side of the zero line says which it is).
static func _total(label: String, balance: float) -> Dictionary:
	return {"label": label, "value": balance, "figure": Strings.t("%s bn") % Num.f(absf(balance), 0)}
