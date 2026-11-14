extends RefCounted

## V5.3 e: the finance bill's spending-verb rows (docs/design/finance-bill.md section 12;
## the author's "par la loi de finances" for screen 5, the parent's ruling for screen 6).
## A sector programme and a regional fund ride the bill instead of applying at the press:
##   "programmes": {sector: action_id}   an *_invest action at a stop, or an end_* action
##   "funds": {"start": [{region_id, share_pct, years}], "stop": [fund_id]}
## Checked by the verbs' own legality at tabling (Investment.available, RegionFunds.refusal),
## applied by their own commands at the division if the bill carries (Investment.execute,
## RegionFunds.start / stop), which stay the appliers and the harnesses' setup verbs, as
## Budget.commit does for rates. Their costs are booked by their own steps, unchanged.
##
## `verbs_pct_gdp` is the rows' cost a year in % of GDP, written on the bill at each
## tabling so the bill's position reads it (FinanceBillLaw.position, call 2: a rise of the
## infrastructure line) as a function of the bill alone.

const Investment = preload("res://src/sim/investment.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")

const PROGRAMMES := "programmes"
const FUNDS := "funds"
const COST := "verbs_pct_gdp"


## `bill`'s rows merged into `merged` (the tabled bill's copy): a sector's newer action
## replaces the older; a fund start or stop is appended once.
static func merge(merged: Dictionary, bill: Dictionary) -> void:
	if bill.has(PROGRAMMES):
		var rows: Dictionary = merged.get(PROGRAMMES, {})
		for sector in bill[PROGRAMMES]:
			rows[sector] = String(bill[PROGRAMMES][sector])
		merged[PROGRAMMES] = rows
	if bill.has(FUNDS):
		var funds: Dictionary = merged.get(FUNDS, {})
		for side in ["start", "stop"]:
			var list: Array = funds.get(side, [])
			for row in bill[FUNDS].get(side, []):
				if not list.has(row):
					list.append(row)
			if not list.is_empty():
				funds[side] = list
		merged[FUNDS] = funds


## Whether any row is illegal on the live state now: true refuses the tabling (`verb`).
static func illegal(state, loader, ns, bill: Dictionary) -> bool:
	var open: Array = Investment.available(state, ns, loader.investment_actions)
	for sector in bill.get(PROGRAMMES, {}):
		var action = _action(loader, String(bill[PROGRAMMES][sector]))
		if action == null or not open.has(action) or String(action.effects["investment"].get("sector", "")) != String(sector):
			return true
	var regions := {}
	for row in bill.get(FUNDS, {}).get("start", []):
		if regions.has(String(row["region_id"])) or RegionFunds.refusal(state, ns, loader, String(row["region_id"]),
				float(row["share_pct"]), int(row["years"])) != "":
			return true
		regions[String(row["region_id"])] = true
	var running := {}
	for row in RegionFunds.open_funds(ns):
		running[String(row["id"])] = true
	for id in bill.get(FUNDS, {}).get("stop", []):
		if not running.has(String(id)):
			return true
	return false


## The rows' cost a year in % of GDP: each programme's change to Investment.bill_pct_gdp,
## each fund opened at its estimate, each fund stopped as a saving.
static func cost_pct_gdp(state, loader, ns, bill: Dictionary) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var total := 0.0
	for sector in bill.get(PROGRAMMES, {}):
		var entry: Dictionary = ns.sector_investment[sector]
		var was := float(entry.get("intensity", 0.0))
		var terms: Dictionary = _action(loader, String(bill[PROGRAMMES][sector])).effects["investment"]
		var before := Investment.bill_pct_gdp(ns)
		# The verb's own arithmetic on the live register, put back at once: RegionFunds.
		# estimate's road (a temporary write, never seen outside this line).
		entry["intensity"] = float(terms.get("intensity", 0.0)) if String(terms.get("op", "")) == "invest" else 0.0
		total += Investment.bill_pct_gdp(ns) - before
		entry["intensity"] = was
	for row in bill.get(FUNDS, {}).get("start", []):
		var est: Dictionary = RegionFunds.estimate(state, ns, loader, String(row["region_id"]), float(row["share_pct"]), int(row["years"]))
		total += 100.0 * float(est.get("eur_bn_per_year", 0.0)) / ns.gdp_eur_bn
	for row in RegionFunds.open_funds(ns):
		if bill.get(FUNDS, {}).get("stop", []).has(String(row["id"])):
			total -= 100.0 * float(row["eur_bn_per_year"]) / ns.gdp_eur_bn
	return total


## A carried bill's rows, through the verbs' own commands; stops first, so a stop frees
## the cap for a start. A row no longer legal (call 3) is skipped and named.
static func apply(state, loader, ns, bill: Dictionary) -> Array:
	var skipped := []
	for sector in bill.get(PROGRAMMES, {}):
		var action = _action(loader, String(bill[PROGRAMMES][sector]))
		var done := Investment.execute(state, ns, loader.investment_actions, action)
		if not bool(done.get("applied", false)):
			skipped.append({"programme": String(sector), "action_id": String(action.id), "reason": "no longer on offer"})
	for id in bill.get(FUNDS, {}).get("stop", []):
		var stopped := RegionFunds.stop(state, ns, String(id))
		if not bool(stopped.get("ok", false)):
			skipped.append({"fund_id": String(id), "reason": String(stopped.get("reason", ""))})
	for row in bill.get(FUNDS, {}).get("start", []):
		var opened := RegionFunds.start(state, ns, loader, String(row["region_id"]), float(row["share_pct"]), int(row["years"]))
		if not bool(opened.get("ok", false)):
			skipped.append({"region_id": String(row["region_id"]), "reason": String(opened.get("reason", ""))})
	return skipped


static func _action(loader, action_id: String):
	for action in loader.investment_actions:
		if String(action.id) == action_id:
			return action
	return null
