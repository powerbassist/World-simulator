extends RefCounted

## The autumn bill's reads for the Finances page -- V5.3 screen 4, slice 4. Out of finances_panel.gd (at its size
## ceiling). Reads only: whether a tax may be put in force or abolished now, what rate a kind enters the draft at, and
## which rows a finance bill at vote already holds (locked, as every row at vote is).

const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")


## Whether the autumn bill is open: a tax may be put in force or abolished only in the nation's autumn month. ONE place,
## to be replaced by the sim's own read (FinanceBill.autumn_open) when Systems lands it: the page must not hold a rule.
static func open(state, loader) -> bool:
	var month := int(loader.nations[state.player().id].finance_autumn_month)
	return month > 0 and month == int(state.month)


## The rate a kind put in force enters the draft at: its own step, inside its range (the smallest sensible one).
static func default_rate(ns, kind: String) -> float:
	var span: Array = ns.tax_library[kind]["rate_range_pct"]
	return clampf(TaxLibrary.step_pct(ns, kind), float(span[0]), float(span[1]))


## The tabled bill's rows as {row id: delta}: those rows are at vote, and locked. A birth at vote is a row from nothing
## to its rate, an abolition one down to nothing.
static func tabled_rows(ns) -> Dictionary:
	var out := {}
	var finance: Dictionary = ns.tabled_bill.get("finance", {})
	for channel in [FinanceDraft.TAX, FinanceDraft.SPENDING]:
		for key in finance.get(channel, {}):
			out[FinanceRows.row_id(channel, String(key))] = float(finance[channel][key])
	for kind in finance.get(FinanceBill.CREATE, {}):
		out[FinanceRows.row_id(FinanceDraft.TAX, String(kind))] = float(finance[FinanceBill.CREATE][kind])
	for kind in finance.get(FinanceBill.ABOLISH, []):
		out[FinanceRows.row_id(FinanceDraft.TAX, String(kind))] = -float(ns.tax_rates_pct.get(kind, 0.0))
	return out
