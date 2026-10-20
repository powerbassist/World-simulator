extends RefCounted

## Which firms a month's price walk must visit -- V5.0c2. companies.gd's three
## walks (firm_impulse_pct, firm_jobs_offset_pct, dividend_revenue_pct_gdp) visit
## every firm of the nation, ~95 a nation and 3,860 a month, and nine firms in ten
## are body firms with no register entry (the body is inert by design, so nothing
## writes one). In a nation with NO regulation burden such a firm adds EXACTLY 0.0
## to every walk:
##
##   - impulse: subsidy 0.0 and burden 0.0, the walk's own `continue`;
##   - dividend: state share 0.0, the walk's own `continue`;
##   - jobs: at a live share s, headcount() is h * (s / s) * maxf(1.0 - beta * 0.0
##     * 1.0, 0.0) = h * 1.0 * 1.0 = h -- s / s is 1.0 in IEEE for every finite
##     nonzero s, the invariant headcount()'s own comment rests on -- so its term
##     h - h is +0.0. Adding +0.0 changes no bit of a sum that is not -0.0, and
##     a sum that starts at +0.0 never becomes -0.0 (x + y is -0.0 only when
##     both are).
##
## So the walk skips them and every float is the one the full walk computes. A
## firm at share <= 0.0 stays in (its headcount is 0.0, its term -h is not zero),
## and so does every firm of a nation with any burden entry at all -- the filter
## returns the whole roster there rather than reason about which sectors bite.
## Order is the roster's: each walk sums in the order it always did.
##
## A leaf: it reads the register and the roster it is handed, nothing else, and
## companies.gd is its only caller.


static func priced(ns, firms: Array) -> Array:
	if not ns.regulation_burden.is_empty():
		return firms
	var out: Array = []
	for company in firms:
		if company.share <= 0.0 or ns.companies.has(company.id):
			out.append(company)
	return out
