extends RefCounted

## The books as the Finances page draws them -- V5.3 screen 4's Finances, direction A ("in and
## out, to scale", the author's pick, 2026-11-14): where the money comes from, by base, and where
## it goes, by line. One read of the live state, cached by the page for the month; it writes nothing.
##
## What is real and what is arithmetic: revenue, spending, deficit, debt, debt service, each
## spending line and each kind's yield are the sim's (Budget.snapshot, the revenue lines of a
## committed copy). "Other revenue" (revenue less the kinds in force) and "other spending" (spending
## less the five lines and the debt service) are their DIFFERENCES: no row sets them, which is what
## the page says of them. A kind folds under its group when what it brings is small, except a kind
## at rate 0 -- "a lever any finance bill may raise" (docs/design/finance-bill.md 9.2): the wealth
## tax stays in sight.

const Budget = preload("res://src/sim/budget.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const TaxesLoader = preload("res://src/core/loaders/taxes_loader.gd")

## A kind brings less than this a year (bn) and is folded, unless its rate is 0.
const FOLD_BN := 5.0


## {gdp, revenue_bn, spending_bn, deficit_bn, deficit_pct, debt_pct, service_bn, other_revenue_bn,
##  other_spending_bn, groups: [{id, total, kinds: [..], folded: [..], not_in_force: [ids]}],
##  lines: [{key, pct, bn}]}.
static func read(state) -> Dictionary:
	var ns = state.player()
	var now := Budget.preview(state, {})
	var gdp := float(now["gdp_eur_bn"])
	var revenue_lines: Dictionary = EffectsStrip.books(state, {})["revenue_lines"]
	var out := {
		"gdp": gdp,
		"revenue_bn": float(now["total_revenue_pct_gdp"]) / 100.0 * gdp,
		"spending_bn": float(now["total_spending_pct_gdp"]) / 100.0 * gdp,
		"deficit_pct": float(now["deficit_pct_gdp"]),
		"debt_pct": float(now["debt_to_gdp_pct"]),
		"service_bn": float(now["debt_service_pct_gdp"]) / 100.0 * gdp,
	}
	out["deficit_bn"] = float(out["spending_bn"]) - float(out["revenue_bn"])
	var lines := []
	var lines_bn := 0.0
	for key in EK.SPENDING_KEYS:
		var pct := float(ns.spending_pct_gdp.get(key, 0.0))
		lines.append({"key": key, "pct": pct, "bn": pct / 100.0 * gdp})
		lines_bn += pct / 100.0 * gdp
	out["lines"] = lines
	out["other_spending_bn"] = float(out["spending_bn"]) - lines_bn - float(out["service_bn"])
	var groups := []
	var taxed := 0.0
	for gid in TaxesLoader.GROUPS:
		var group := {"id": gid, "total": 0.0, "kinds": [], "folded": [], "not_in_force": []}
		for kind in ns.tax_library:
			var row: Dictionary = ns.tax_library[kind]
			if String(row["group"]) != gid:
				continue
			if not ns.tax_rates_pct.has(kind):
				group["not_in_force"].append(kind)
				continue
			var yield_bn := float(revenue_lines.get(kind, 0.0)) / 100.0 * gdp
			var entry := {"id": kind, "rate": float(ns.tax_rates_pct[kind]), "yield_bn": yield_bn,
				"unit": String(row["unit"]), "who": row.get("who_pays", []), "decimals": TaxLibrary.step_decimals(ns, kind)}
			group["total"] += yield_bn
			(group["kinds"] if (entry["rate"] == 0.0 or yield_bn >= FOLD_BN) else group["folded"]).append(entry)
		(group["kinds"] as Array).sort_custom(func(a, b) -> bool: return float(a["yield_bn"]) > float(b["yield_bn"]))
		(group["folded"] as Array).sort_custom(func(a, b) -> bool: return float(a["yield_bn"]) > float(b["yield_bn"]))
		taxed += float(group["total"])
		groups.append(group)
	groups.sort_custom(func(a, b) -> bool: return float(a["total"]) > float(b["total"]))
	out["groups"] = groups
	out["other_revenue_bn"] = float(out["revenue_bn"]) - taxed
	return out
