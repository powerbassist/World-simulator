extends RefCounted

## V5.3 a (docs/design/v5.3-ab.md 3.2): "during the transition the firm's output is
## 4 % below its path (management turnover), then recovers". Its own file because
## companies.gd sits at its size ratchet and processes.gd at the 300-line ceiling.
## Processes.tick_month() writes drag() onto `ns.process_drag_pct` every month and
## Economy adds it to growth a month later (its eleventh addend); the estimate shows
## loss_eur_bn() before the press. One formula, read by both.

const Companies = preload("res://src/sim/companies.gd")
const K = preload("res://src/sim/companies_constants.gd")


## The output a firm's transition loses: PROCESS_TRANSITION_OUTPUT_LOSS of a year of
## its live output, bn EUR.
static func loss_eur_bn(ns, company) -> float:
	return K.PROCESS_TRANSITION_OUTPUT_LOSS * Companies.output_eur_bn(ns, company)


## The growth drag of the firms in a transition now: their losses as points of GDP
## a year, negative, bounded at PROCESS_DRAG_MAX_PCT; exactly 0.0 with none.
static func drag(ns, loader) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var loss := 0.0
	for row in ns.processes:
		if String(row["status"]) != "open" or String(row["stage"]) != "transition":
			continue
		for company in Companies.firms_of(loader, ns.id):
			if String(company.id) == String(row["company_id"]):
				# The measured expression's own order (the balance table at 7cba6e5e), so
				# moving it here moved no float.
				loss += K.PROCESS_TRANSITION_OUTPUT_LOSS * 100.0 * Companies.output_eur_bn(ns, company) / ns.gdp_eur_bn
	if loss == 0.0:
		return 0.0
	return -minf(loss, K.PROCESS_DRAG_MAX_PCT)
