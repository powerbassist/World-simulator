extends RefCounted

## V5.3 c' (docs/design/v5.3-c-register.md sections 4 and 7): a programme's life.
## A row of the finance bill ({type, op, rows: [{region, units}], quote}) is checked
## at tabling (refusal), opened at the vote (open: the contract price drawn once,
## inside the range the quote showed), billed evenly over its months and opened
## (tick_month), after which its units stand for good and their running cost joins
## the line. A closure is the same row with op `demolish`: its one-off cost billed
## over demolish_months, then the units gone and their running cost saved.
##
## TWO LINES, BOTH WRITTEN HERE, BOTH BILLED A MONTH BEHIND (the project bill's
## rule, for its reason: the deficit is a precondition field):
##   ns.unit_bill_pct_gdp       the capital paid this month, as % of GDP a year;
##   ns.unit_running_pct_gdp    {line: % of GDP a year}, the standing units' running
##                              cost (negative for a closure of start stock), which
##                              Budget adds to the spending and Sectors.ratio() adds
##                              to the line, so the nation's figure moves by the
##                              lever's own path and no second channel.
## With no programme both are exactly 0.0 / {} and every number reads as before c'.
##
## Only the player builds in c' (the AI's use of the register is 0.6, with D12).

const UK = preload("res://src/sim/units_constants.gd")
const Units = preload("res://src/sim/units.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const Cycle = preload("res://src/sim/cycle.gd")


static func now(state) -> int:
	return UnitPrice.now(state)


## Why `rows` (a bill's units rows, in order) cannot be tabled now; "" when they can.
static func refusal(state, ns, loader, rows: Array) -> String:
	var open := 0
	var closing := {}
	for p in ns.unit_programmes:
		if String(p.get("state", "")) == UK.STATE_BUILDING:
			open += 1
			if String(p.get("op", "")) == UK.OP_DEMOLISH:
				_add(closing, p)
	var regions := {}
	for r in loader.regions.get(ns.id, []):
		regions[r.id] = true
	for row in rows:
		var type_id := String(row.get("type", ""))
		if not loader.unit_types.has(type_id) or not Units.offered(loader, ns.id, type_id):
			return "This nation does not build that kind of unit."
		var op := String(row.get("op", ""))
		if op != UK.OP_BUILD and op != UK.OP_DEMOLISH:
			return "A programme builds or closes units."
		if (row.get("rows", []) as Array).is_empty():
			return "A programme names at least one region."
		for r in row["rows"]:
			var region := String(r.get("region", ""))
			if not regions.has(region):
				return "That is not one of this nation's regions."
			if int(r.get("units", 0)) < 1:
				return "Each region's row is at least one unit."
			if Units.start_capacity(loader, ns.id, type_id, region) <= 0.0:
				return "This region has none of these to build on or close."
			if op == UK.OP_DEMOLISH:
				var key := "%s|%s" % [type_id, region]
				closing[key] = int(closing.get(key, 0)) + int(r["units"])
				if int(closing[key]) > standing(ns, loader, type_id, region):
					return "That closes more units than the region has."
		open += 1
	if open > UK.UNIT_PROGRAMMES_MAX_OPEN:
		return "Too many programmes would be under way at once."
	return ""


## The units of the type standing in the region: the start stock and the player's
## done rows (the units still being closed are counted by refusal()).
static func standing(ns, loader, type_id: String, region: String) -> int:
	var by_region: Dictionary = ((loader.unit_stock.get(ns.id, {}) as Dictionary).get(type_id, {}) as Dictionary)
	return int((by_region.get(region, {}) as Dictionary).get("units", 0)) + Units.net_units(ns, type_id, region)


## The vote carried: the row becomes a programme. Its contract price is drawn once,
## uniformly inside the range its quote showed at tabling (Cycle.unit on its id, the
## game's seed salted in), so it is inside the range in every run by construction.
static func open(state, ns, loader, row: Dictionary) -> Dictionary:
	var q: Dictionary = row["quote"]
	var id := "%s:%d:%d" % [String(row["type"]), now(state), ns.unit_programmes.size()]
	var u := Cycle.unit(Cycle.salted("unit|%s|price" % id, int(ns.draw_seed)), 0)
	var contract := float(q["lo_eur_m"]) + u * (float(q["hi_eur_m"]) - float(q["lo_eur_m"]))
	var months := int(q["build_months"])
	var p := {"id": id, "type": String(row["type"]), "op": String(row["op"]), "state": UK.STATE_BUILDING,
		"rows": (row["rows"] as Array).duplicate(true), "voted": now(state), "months_left": months,
		"build_months": months, "estimate_eur_m": float(q["estimate_eur_m"]), "lo_eur_m": float(q["lo_eur_m"]),
		"hi_eur_m": float(q["hi_eur_m"]), "odds": float(q["odds"]), "contract_eur_m": contract,
		"capital_month_eur_m": contract / months, "paid_eur_m": 0.0}
	ns.unit_programmes.append(p)
	return p


## A month of every programme: each building one pays its month and counts down,
## opening (DONE) when its months run out; then both lines are rewritten.
static func tick_month(state, loader) -> void:
	var ns = state.player()
	if ns == null:
		return
	var paid := 0.0
	for p in ns.unit_programmes:
		if String(p["state"]) != UK.STATE_BUILDING:
			continue
		var pay := float(p["capital_month_eur_m"])
		p["paid_eur_m"] = float(p["paid_eur_m"]) + pay
		paid += pay
		p["months_left"] = int(p["months_left"]) - 1
		if int(p["months_left"]) <= 0:
			p["state"] = UK.STATE_DONE
			p["opened"] = now(state)
	var gdp_m := float(ns.gdp_eur_bn) * 1000.0
	ns.unit_bill_pct_gdp = 100.0 * paid * 12.0 / gdp_m if paid != 0.0 and gdp_m > 0.0 else 0.0
	var running := {}
	for p in ns.unit_programmes:
		if String(p["state"]) != UK.STATE_DONE or not loader.unit_types.has(String(p["type"])):
			continue
		var t: Dictionary = loader.unit_types[String(p["type"])]
		var sign := -1.0 if String(p["op"]) == UK.OP_DEMOLISH else 1.0
		var units := 0
		for r in p["rows"]:
			units += int(r["units"])
		var line := String(t["line"])
		running[line] = float(running.get(line, 0.0)) + sign * float(units) * float(t["running_eur_m"].get(ns.id, 0.0))
	for line in running:
		running[line] = 100.0 * float(running[line]) / gdp_m if gdp_m > 0.0 else 0.0
	ns.unit_running_pct_gdp = running


static func _add(closing: Dictionary, p: Dictionary) -> void:
	for r in p.get("rows", []):
		var key := "%s|%s" % [String(p["type"]), String(r["region"])]
		closing[key] = int(closing.get(key, 0)) + int(r["units"])
