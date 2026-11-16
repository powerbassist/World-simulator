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


## The author's answer (2) of 2026-11-16 (Design's F1, design-card1-aid-price.md section
## 9): an aid verb's bloc offsets scale by the firm's live jobs over the nation's largest
## major's, at most 1, so aid to a small firm buys a small political credit. Kept on the
## register entry at the grant (`aid_credit`, read AFTER a rescue's restore: a failed firm
## reads 0 until then), and the withdrawal hands back that same factor. An entry with no
## `aid_credit` was granted before PR 3 at the full credit, so absent reads 1.0: no bump.
## Any other verb: 1.0.
static func bloc_credit(ns, loader, company_id: String, entry: Dictionary, op: String) -> float:
	if op == "withdraw":
		return float(entry.get("aid_credit", 1.0))
	if op != "subsidise":
		return 1.0
	entry["aid_credit"] = credit_factor(ns, loader, company_id)
	return float(entry["aid_credit"])


## The credit factor `action` would grant `company_id` if pressed now: the verb run on a
## copy (Companies.preview) and the factor execute() itself writes there. The retro
## review's T2 on #380: a failed major in its rescue window reads 0 live jobs, so
## credit_factor() on the live state priced no bloc move, while execute() restores the
## firm before it books the credit. The live state is not written. A verb the copy
## refused reads the entry's earlier grant if it has one (a firm already aided, whose
## verb is not offered), else credit_factor().
static func granted_credit(state, ns, loader, action, company_id: String) -> float:
	var copy = Companies.preview(state, ns, loader.company_actions, action, company_id, loader)[0]
	var entry: Dictionary = copy.companies.get(company_id, {})
	return float(entry.get("aid_credit", credit_factor(ns, loader, company_id)))


## The factor an aid granted now would carry: `company_id`'s live jobs over the nation's
## largest major's, at most 1. Pure; the firm sheet's read for the scaled credit.
static func credit_factor(ns, loader, company_id: String) -> float:
	var top := 0.0
	var own := 0.0
	for company in Companies.majors_of(loader, ns.id):
		var jobs: float = Companies.headcount(ns, company)
		top = maxf(top, jobs)
		if String(company.id) == company_id:
			own = jobs
	return minf(own / top, 1.0) if top > 0.0 else 1.0


## The author's answer (3): the jobs an aid verb moves, for the firm sheet before the
## commit. On a copy (Companies.preview), the share pool alone runs until the shares stop
## moving (rivals at their floor or the firm at its cap; at most NET_JOBS_MAX_MONTHS):
## {gained, lost_at_rivals, net, months}, jobs. Its job is the reason to choose the firm:
## a lean firm's aid takes share from rivals that employ more per point of it.
const NET_JOBS_MAX_MONTHS := 240

static func net_jobs(state, ns, loader, action, company) -> Dictionary:
	var rivals: Array = Companies.firms_in_sector(loader, ns.id, company.sector).filter(
		func(other) -> bool: return other.id != company.id)
	var copy = Companies.preview(state, ns, loader.company_actions, action, String(company.id), loader)[0]
	var own_before: float = Companies.headcount(ns, company)
	var rivals_before := 0.0
	for other in rivals:
		rivals_before += Companies.headcount(ns, other)
	var months := 0
	while months < NET_JOBS_MAX_MONTHS:
		var held: float = Companies.share_of_company(copy, company)
		Companies._tick_shares(copy, loader)
		months += 1
		if absf(Companies.share_of_company(copy, company) - held) < 1e-12:
			break
	var rivals_after := 0.0
	for other in rivals:
		rivals_after += Companies.headcount(copy, other)
	var gained: float = Companies.headcount(copy, company) - own_before
	var lost: float = rivals_before - rivals_after
	return {"gained": gained, "lost_at_rivals": lost, "net": gained - lost, "months": months}
