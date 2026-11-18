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
const UnitOverrun = preload("res://src/sim/unit_overrun.gd")
const UnitEnvelope = preload("res://src/sim/unit_envelope.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const C = preload("res://src/sim/economy_constants.gd")


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
	var seen: Array = []
	for row in rows:
		# Two equal rows in one text are refused, never collapsed (the parent's ruling on
		# #413): the player meant one programme or two, and the sheet cannot tell which.
		# A row equal to one already HELD never reaches here twice: FinanceRows.merge keeps it once.
		var same := [String(row.get("type", "")), String(row.get("op", "")), row.get("rows", [])]
		if seen.has(same):
			return "Two identical rows in one bill: put the units in one row."
		seen.append(same)
		var type_id := String(row.get("type", ""))
		if not loader.unit_types.has(type_id) or not Units.offered(loader, ns.id, type_id):
			return "This nation does not build that kind of unit."
		var op := String(row.get("op", ""))
		if op != UK.OP_BUILD and op != UK.OP_DEMOLISH:
			return "A programme builds or closes units."
		if (row.get("rows", []) as Array).is_empty():
			return "A programme names at least one region."
		var named := {}
		for r in row["rows"]:
			var region := String(r.get("region", ""))
			if not regions.has(region):
				return "That is not one of this nation's regions."
			# One entry per region in a row (T1 on #413): its price is on its whole order.
			if named.has(region):
				return "A programme names each region once."
			named[region] = true
			if Units.start_capacity(loader, ns.id, type_id, region) <= 0.0:
				return "This region has none of these to build on or close."
			if op == UK.OP_BUILD:
				var units := float(r.get("units", 0))
				if units < 1.0 or units != floorf(units):
					return "Each region's row is a whole number of units, at least one."
			if op == UK.OP_DEMOLISH:
				# A closure is entered in capacity and cannot exceed what the region holds.
				if float(r.get("capacity", 0.0)) <= 0.0:
					return "Each region's row closes some capacity."
				var key := "%s|%s" % [type_id, region]
				closing[key] = float(closing.get(key, 0.0)) + float(r["capacity"])
				if float(closing[key]) > standing(ns, loader, type_id, region):
					return "That closes more than the region holds."
		open += 1
	if open > UK.UNIT_PROGRAMMES_MAX_OPEN:
		return "Too many programmes would be under way at once."
	return ""


## The capacity of the type standing in the region: the start stock and the player's
## done rows (the capacity still being closed is counted by refusal()).
static func standing(ns, loader, type_id: String, region: String) -> float:
	return Units.start_capacity(loader, ns.id, type_id, region) + Units.capacity_delta(ns, loader, type_id, region)


## The vote carried: the row becomes a programme. Its contract price is drawn once,
## uniformly inside the range its quote showed at tabling (Cycle.unit on its id, the
## game's seed salted in), so it is inside the range in every run by construction.
## A row reaching the vote without a quote (built by hand, not through
## FinanceBill.drafted) is quoted now, so the vote never reads a missing range.
static func open(state, ns, loader, row: Dictionary) -> Dictionary:
	var q: Dictionary = row["quote"] if row.has("quote") else UnitPrice.quote(state, ns, loader, row)
	# Unique for the game (T9 on #413): a saved counter, never the list's size, which a
	# later prune could reuse.
	ns.unit_programme_seq += 1
	var id := "%s:%d" % [String(row["type"]), ns.unit_programme_seq]
	var u := Cycle.unit(Cycle.salted("unit|%s|price" % id, int(ns.draw_seed)), 0)
	var contract := float(q["lo_eur_m"]) + u * (float(q["hi_eur_m"]) - float(q["lo_eur_m"]))
	var months := int(q["build_months"])
	var p := {"id": id, "type": String(row["type"]), "op": String(row["op"]), "state": UK.STATE_BUILDING,
		"rows": (row["rows"] as Array).duplicate(true), "voted": now(state), "months_left": months,
		"build_months": months, "estimate_eur_m": float(q["estimate_eur_m"]), "lo_eur_m": float(q["lo_eur_m"]),
		"hi_eur_m": float(q["hi_eur_m"]), "odds": float(q["odds"]), "contract_eur_m": contract,
		"capital_month_eur_m": contract / months, "paid_eur_m": 0.0,
		"surcharge": (q.get("surcharge", {}) as Dictionary).duplicate()}
	# Section 5: the overrun is drawn here, once. Section 6: the Union's share reserved
	# here, before the row joins the register (what is left does not count it yet).
	UnitOverrun.draw(ns, p)
	UnitEnvelope.reserve(loader, ns, p)
	ns.unit_programmes.append(p)
	return p


## A month of every programme: each building one pays its month and counts down,
## opening (DONE) when its months run out; then the overrun cards and the Union's
## receipts and warning; then the lines are rewritten. Returns the month's notes
## (WorldMonth's report key "units"), each {kind, id or org, ...}:
##   opened             {id, type, realised_eur_m, estimate_eur_m}
##   overrun_landed     {id, eur_m}   a card posted (UnitOverrun)
##   overrun_defaulted  {id, eur_m}   an unanswered card paid at its date
##   union_lapsed       {id, eur_m}   an opening after the period's last payment year
##   lapse_warning      {org, period, eur_m, year}  warn_months before that year ends
static func tick_month(state, loader) -> Array:
	var notes: Array = []
	var ns = state.player()
	if ns == null:
		return notes
	var month := now(state)
	var paid := 0.0
	for p in ns.unit_programmes:
		if String(p["state"]) != UK.STATE_BUILDING:
			continue
		var pay := float(p["capital_month_eur_m"])
		p["paid_eur_m"] = float(p["paid_eur_m"]) + pay
		p["paid_month"] = month
		paid += pay
		p["months_left"] = int(p["months_left"]) - 1
		if int(p["months_left"]) <= 0:
			p["state"] = UK.STATE_DONE
			p["opened"] = month
			notes.append({"kind": "opened", "id": String(p["id"]), "type": String(p["type"]),
				"realised_eur_m": float(p["paid_eur_m"]), "estimate_eur_m": float(p["estimate_eur_m"])})
			UnitEnvelope.opening(loader, ns, p, month, notes)
	UnitOverrun.tick(state, ns, loader, month, notes)
	var gdp_m := float(ns.gdp_eur_bn) * 1000.0
	var receipt := UnitEnvelope.receipts(ns, month)
	ns.unit_receipt_pct_gdp = 100.0 * receipt * 12.0 / gdp_m if receipt != 0.0 and gdp_m > 0.0 else 0.0
	UnitEnvelope.warn(loader, ns, month, notes)
	var was: float = ns.unit_bill_pct_gdp + ns.unit_running_total_pct_gdp()
	ns.unit_bill_pct_gdp = 100.0 * paid * 12.0 / gdp_m if paid != 0.0 and gdp_m > 0.0 else 0.0
	var running := {}
	for p in ns.unit_programmes:
		if String(p["state"]) != UK.STATE_DONE or not loader.unit_types.has(String(p["type"])):
			continue
		var t: Dictionary = loader.unit_types[String(p["type"])]
		# Every rule reads capacity: a unit's running cost per unit of its capacity.
		var capacity := 0.0
		for r in p["rows"]:
			capacity += Units.row_capacity(ns, loader, p, r)
		# Keyed by the type's SECTOR (T2 on #413): Sectors.effective_spending lifts that
		# sector alone, never the line's others.
		var sector := String(t["sector"])
		running[sector] = float(running.get(sector, 0.0)) \
			+ capacity / Units.unit_capacity(loader, ns.id, String(p["type"])) * float(t["running_eur_m"].get(ns.id, 0.0))
	for sector in running:
		running[sector] = 100.0 * float(running[sector]) / gdp_m if gdp_m > 0.0 else 0.0
	ns.unit_running_pct_gdp = running
	# The programmes' spending moves demand as a fund's does (RegionFunds.tick_month, T7 on
	# #413): Budget.commit()'s spending term on the change of both lines, so the start, the
	# end and GDP's drift telescope and a programme leaves no lasting impulse. No change, no
	# write: a game with no programme reads the impulse exactly as before c'.
	var change: float = ns.unit_bill_pct_gdp + ns.unit_running_total_pct_gdp() - was
	if change != 0.0:
		ns.demand_impulse_pct = clampf(ns.demand_impulse_pct + change * C.MULT_SPENDING / C.impulse_level_factor(),
			-C.IMPULSE_MAX_PCT, C.IMPULSE_MAX_PCT)
	return notes


static func _add(closing: Dictionary, p: Dictionary) -> void:
	for r in p.get("rows", []):
		var key := "%s|%s" % [String(p["type"]), String(r["region"])]
		closing[key] = float(closing.get(key, 0.0)) + float(r.get("capacity", 0.0))
