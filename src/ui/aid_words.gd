extends RefCounted

## State aid, said the way the player weighs it -- V5.3 screen 5 slice 2, the aid card's ask
## (card-h-aid-price.md: "show the price as EUR per job a year, beside the jobs the firm
## holds and the bill as a share of one tax point") on Systems' PR 3 reads (#380).
##
## Every figure is the sim's: the yearly price is CompaniesAid.per_year (a share of the
## firm's payroll), the jobs moved are CompaniesAid.net_jobs (on a copy, the share pool run
## to its endpoint) and the political credit is the action's bloc offsets times
## CompaniesAid.credit_factor (aid to a small firm buys a small credit). The UI multiplies
## the offsets it prints; it does not re-derive the factor.
##
## ONE TAX POINT is a point of income tax: its base_share in data/taxes/income.json, 0.5 %
## of GDP (about 14.5 bn in France), the measure the aid card and coercion_constants.gd
## both name. Read from the loader, so a data edit moves it.

const CompaniesAid = preload("res://src/sim/companies_aid.gd")
const Companies = preload("res://src/sim/companies.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")

const TAX_POINT_KIND := "income"


## Whether `action` is state aid (the subsidise op: the subsidy and the rescue).
static func is_aid(action) -> bool:
	return String(action.effects.get("company", {}).get("op", "")) == "subsidise"


static func intensity(action) -> float:
	return float(action.effects.get("company", {}).get("intensity", 0.0))


## EUR bn of GDP one tax point raises, 0 when the loader carries no income tax row.
static func tax_point_eur_bn(loader, ns) -> float:
	var row = loader.taxes.get(TAX_POINT_KIND, {})
	return float(row.get("base_share", 0.0)) * float(ns.gdp_eur_bn) / 100.0


## "15 100 € a job · 0.13 tax point": the aid's yearly price per job the firm holds, and
## as a share of one tax point. "" for a firm with no jobs.
static func caption(loader, ns, company, action) -> String:
	var per_year := CompaniesAid.per_year(ns, company, intensity(action))
	var jobs := Companies.headcount(ns, company)
	var point := tax_point_eur_bn(loader, ns)
	if jobs <= 0.0 or point <= 0.0:
		return ""
	return Strings.t("%s € a job · %s tax point") % [CompanyVerb.thousands(roundf(per_year * 1e9 / jobs / 100.0) * 100.0), Num.f(per_year / point, 2)]


## The action's bloc offsets as the press would book them (CompaniesAid.bloc_credit's
## rule, read without its write): aid times the firm's credit factor now; a withdrawal
## times the factor the grant kept on the entry (`aid_credit`, absent 1.0, QA's T1 on
## #381); any other verb as it is.
static func offsets(loader, ns, company, action) -> Dictionary:
	var raw: Dictionary = action.effects.get("bloc_offset", {})
	var op := String(action.effects.get("company", {}).get("op", ""))
	var factor := 1.0
	if op == "subsidise":
		factor = CompaniesAid.credit_factor(ns, loader, String(company.id))
	elif op == "withdraw":
		factor = float((ns.companies.get(String(company.id), {}) as Dictionary).get("aid_credit", 1.0))
	else:
		return raw
	var out := {}
	for bloc in raw:
		out[bloc] = float(raw[bloc]) * factor
	return out


## "Jobs here +231 000, at rivals -121 500: net +109 500 in 45 months." On a copy; "" when
## the aid moves no share.
static func net_jobs_line(state, loader, ns, company, action) -> String:
	var moved: Dictionary = CompaniesAid.net_jobs(state, ns, loader, action, company)
	if absf(float(moved["gained"])) < 1.0 and absf(float(moved["lost_at_rivals"])) < 1.0:
		return ""
	return Strings.tn("Jobs here %s, at rivals %s: net %s in %d month.", "Jobs here %s, at rivals %s: net %s in %d months.", int(moved["months"])) % [
		_signed_jobs(float(moved["gained"])), _signed_jobs(-float(moved["lost_at_rivals"])), _signed_jobs(float(moved["net"])), int(moved["months"])]


static func _signed_jobs(value: float) -> String:
	var rounded := roundf(value / 100.0) * 100.0
	return ("+" if rounded > 0.0 else "−" if rounded < 0.0 else "") + CompanyVerb.thousands(absf(rounded))
