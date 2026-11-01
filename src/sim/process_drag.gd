extends RefCounted

## V5.3 a (docs/design/v5.3-ab.md 3.2): "during the transition the firm's output is
## 4 % below its path (management turnover), then recovers". Its own file because
## companies.gd sits at its size ratchet and processes.gd at the 300-line ceiling.
## Processes.tick_month() writes drag() onto `ns.process_drag_pct` every month and
## Economy adds it to growth a month later (its eleventh addend); the estimate shows
## loss_eur_bn() before the press. One formula, read by both.

const Companies = preload("res://src/sim/companies.gd")
const K = preload("res://src/sim/companies_constants.gd")
const EC = preload("res://src/sim/economy_constants.gd")


## The output a firm's transition loses in total: PROCESS_TRANSITION_OUTPUT_LOSS of a
## year of its live output, bn EUR. What the strip shows, and what drag() delivers.
static func loss_eur_bn(ns, company) -> float:
	return K.PROCESS_TRANSITION_OUTPUT_LOSS * Companies.output_eur_bn(ns, company)


## The growth drag of the firms in a transition now, points of GDP a year, negative,
## bounded at PROCESS_DRAG_MAX_PCT; exactly 0.0 with none.
##
## Scaled by GAP_CLOSE over the transition's length in years, because the drag moves
## growth and the output gap closes at GAP_CLOSE a year: a drag d held for T years
## opens a gap the economy then closes, and the GDP it loses over the transition and
## that closing, summed, is d * T / GAP_CLOSE. Unscaled, that was 3.3 times the strip
## (QA's call 2 on #264); scaled, it is loss_eur_bn() up to the monthly compounding,
## whatever GAP_CLOSE or the transition's length become. tests/test_processes.gd sums
## it over Economy's own months.
static func drag(ns, loader) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var loss := 0.0
	for row in ns.processes:
		if String(row["status"]) != "open" or String(row["stage"]) != "transition":
			continue
		for company in Companies.firms_of(loader, ns.id):
			if String(company.id) == String(row["company_id"]):
				loss += 100.0 * loss_eur_bn(ns, company) / ns.gdp_eur_bn
	if loss == 0.0:
		return 0.0
	var years := float(K.PROCESS_TRANSITION_MONTHS) / 12.0
	return -minf(loss * EC.GAP_CLOSE / years, K.PROCESS_DRAG_MAX_PCT)
