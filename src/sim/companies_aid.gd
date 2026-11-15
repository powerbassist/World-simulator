extends RefCounted

## V5.3 PR 3, the author's call 4 (2026-11-14; docs/design/finance-bill.md, the industry
## brief): aid priced BY THE FIRM, a share of its payroll a year, never a share of GDP.
## The firm verbs' yearly price and the subsidy bill's one term. Split out of
## companies.gd, which sits at its size ratchet; Companies preloads this file for the
## bill's writer (_recompute_prices), and this file reads the firm through Companies.

const Companies = preload("res://src/sim/companies.gd")
const K = preload("res://src/sim/companies_constants.gd")
const Demography = preload("res://src/sim/demography.gd")


## Points of GDP per year. Read by Budget.recompute() as a computed spending line,
## NOT as a sixth entry in economy_constants.SPENDING_KEYS -- that list is keyed
## 1:1 to cabinet portfolios, so a sixth line is a sixth minister, and
## docs/tiers/v1.md section 6 rules it out. V1.3c's tariff revenue and V1.3g's
## deployment bill both took this route first.
##
## V5.3 PR 3: each subsidy is priced by its firm (per_year), so the bill
## needs the firms themselves, not the register alone.
static func subsidy_bill_pct_gdp(ns, loader) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var bill := 0.0
	for company in Companies.firms_of(loader, ns.id):
		var intensity := Companies.subsidy_of(ns, String(company.id))
		if intensity != 0.0:
			bill += 100.0 * per_year(ns, company, intensity) / ns.gdp_eur_bn
	return minf(bill, K.SUBSIDY_BILL_MAX_PCT_GDP)


## EUR bn a year the state pays to keep `company` subsidised at `intensity`: a share of
## its payroll (K.AID_PAYROLL_SHARE at full intensity). The verbs' price (the firm
## sheet's "a year") and the subsidy bill's one term.
static func per_year(ns, company, intensity: float) -> float:
	return K.AID_PAYROLL_SHARE * intensity * payroll_eur_bn(ns, company)


## EUR bn a year `company` pays its staff: its live jobs at the nation's compensation
## per job.
static func payroll_eur_bn(ns, company) -> float:
	return Companies.headcount(ns, company) * compensation_per_job_eur(ns) / 1e9


## EUR a year per job: K.COMPENSATION_SHARE_OF_GDP of GDP over the employed, live, so a
## nation's wages follow its output.
static func compensation_per_job_eur(ns) -> float:
	var employed: float = Demography.labour_force(ns) * (1.0 - ns.unemployment_pct / 100.0)
	if employed <= 0.0:
		return 0.0
	return K.COMPENSATION_SHARE_OF_GDP * ns.gdp_eur_bn * 1e9 / employed
