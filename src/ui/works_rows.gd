extends RefCounted

## Public works' rows (G3 S4 PR 2c, the author's "A calendrier", works-a-calendar.png): every
## work the register knows -- building, on offer, finished -- with the figures the calendar
## draws. The one reader the page, its lanes, its bill chart and its sheet share.
##
## Nothing is estimated. A work being built opens `months_left` from today, the very count
## Calendar.fixed_dates turns into the diary's date (and the same arithmetic: months added to
## an absolute month, year x 12 + month); an offer opens its build from today "if started
## now". A cost a year in bn is the authored share of GDP times today's GDP; the region is
## Projects.site_region's (empty: the page says none). Offers are what Projects.available
## returns, as the tab always listed them: a work locked behind a full register is not drawn.

const Projects = preload("res://src/sim/projects.gd")
const Strings = preload("res://src/ui/strings.gd")

const BUILDING := "building"
const OFFER := "offer"
const DONE := "done"


## Today as an absolute month (year x 12 + month).
static func now(state) -> int:
	return int(state.year) * 12 + int(state.month)


## [{id, name, state, opens (absolute month, -1 when finished), left, months, cost_pct, cost_bn,
## all_bn, growth_pct, region, blocs, start, cancel, summary}], building first, then the offers,
## then the finished works; `start` and `cancel` are the sim's actions or null.
static func rows(state, loader, ns) -> Array:
	var verbs := {}
	for action in Projects.available(state, ns, loader.project_actions):
		var terms: Dictionary = action.effects.get("project", {})
		verbs[String(terms.get("project_id", "")) + "|" + String(terms.get("op", ""))] = action
	var out: Array = []
	var today := now(state)
	for pid in Projects.building(ns):
		var r := _row(loader, ns, String(pid), BUILDING, verbs)
		r["left"] = Projects.months_left(ns, String(pid))
		r["opens"] = today + int(r["left"])
		out.append(r)
	for key in verbs:
		if String(key).ends_with("|start"):
			var action = verbs[key]
			var pid := String(action.effects["project"]["project_id"])
			var r := _row(loader, ns, pid, OFFER, verbs)
			r["opens"] = today + int(r["months"])
			r["blocs"] = action.effects.get("bloc_offset", {})
			r["summary"] = Strings.row_summary("project-actions", action)
			out.append(r)
	for pid in Projects.completed(ns):
		out.append(_row(loader, ns, String(pid), DONE, verbs))
	return out


static func _row(loader, ns, pid: String, kind: String, verbs: Dictionary) -> Dictionary:
	var terms := Projects.terms_of(loader, pid)
	var months := int(terms.get("build_months", 0))
	var bn := float(terms.get("cost_pct_gdp", 0.0)) / 100.0 * float(ns.gdp_eur_bn)
	return {"id": pid, "state": kind, "months": months, "left": months, "opens": -1,
		"name": Strings.noun("project-actions", loader.project_actions, "project", "project_id", pid, "project_name", Projects.name_of(loader, pid)),
		"cost_pct": float(terms.get("cost_pct_gdp", 0.0)), "cost_bn": bn, "all_bn": bn * months / 12.0,
		"growth_pct": float(terms.get("potential_growth_pct", 0.0)), "region": Projects.site_region(loader, String(ns.id), pid),
		"blocs": {}, "summary": "", "start": verbs.get(pid + "|start"), "cancel": verbs.get(pid + "|abandon")}


## The works' bill in `month`, in % of GDP a year: every work being built pays until the month
## it opens; `with_id` adds an offer as if started now.
static func bill_at(rows: Array, month: int, with_id := "") -> float:
	var sum := 0.0
	for r in rows:
		var paying := String(r["state"]) == BUILDING or (String(r["state"]) == OFFER and String(r["id"]) == with_id)
		if paying and month < int(r["opens"]):
			sum += float(r["cost_pct"])
	return sum


## How many works can be built at once: a start asks `project_count <= N` in the data (N + 1
## slots), so the number is the content's, never typed here; 0 when no start gates on it.
static func slots(loader) -> int:
	var most := -1
	for action in loader.project_actions:
		for cond in action.preconditions:
			if String(cond["field"]) == "project_count" and String(cond["op"]) == "<=":
				most = maxi(most, int(cond["value"]))
	return most + 1


## The work picked when nothing is: the first offer, else the first work being built.
static func first_pick(rows: Array) -> String:
	for kind in [OFFER, BUILDING]:
		for r in rows:
			if String(r["state"]) == kind:
				return String(r["id"])
	return ""
