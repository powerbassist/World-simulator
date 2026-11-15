extends RefCounted

## The autumn bill's reads for the Finances page -- V5.3 screen 4, slice 4. Out of finances_panel.gd (at its size
## ceiling). Reads only: whether a tax may be put in force or abolished now, what rate a kind enters the draft at, and
## which rows a finance bill at vote already holds (locked, as every row at vote is).

const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")


## Out of the autumn month the draft may hold no creation or abolition (tabling would refuse them as "autumn", and no verb
## reaches them to take them back): they leave it. True when something did, so the page says so.
static func sweep(state, loader, draft) -> bool:
	return not FinanceBill.autumn_open(state, loader) and draft.drop_autumn()


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
