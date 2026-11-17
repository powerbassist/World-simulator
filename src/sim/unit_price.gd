extends RefCounted

## V5.3 c' (docs/design/v5.3-c-register.md section 4): a programme's price, quoted
## at tabling and fixed there, so a reshuffle before the vote changes neither the
## range nor the odds (the quote rides the tabled bill's row).
##
##   estimate   sum over the rows of units x cost_eur_m x (1 + the region's
##              concentration surcharge);
##   range      the estimate x (1 - w) to (1 + w), w from the competence of the
##              minister of the type's line (a vacant seat at the widest);
##   odds       the type's overrun_odds x (ODDS_BASE - competence), clamped;
##   capital    the estimate spread evenly over build_months, as % of GDP a year;
##   running    units x running_eur_m a year, from the opening, for good.
##
## A closure (op demolish) is entered in capacity (section 7 as amended) and priced as
## demolish_cost_share of the cost of that much new capacity, once, with no range and
## no odds; it saves the same share of a unit's running cost.
##
## CONCENTRATION READS CAPACITY: the capacity of the type ordered in one region within
## CONC_MONTHS (the programmes voted since, and this row), beyond CONC_FREE of the
## region's start capacity, raises the unit price there by CONC_SLOPE points per further
## point of it. Spreading is cheaper; concentrating is faster where it is needed.

const UK = preload("res://src/sim/units_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Units = preload("res://src/sim/units.gd")


static func now(state) -> int:
	return int(state.year) * 12 + int(state.month)


## The competence of the minister holding `line`, 0..1; 0 for a vacant seat.
static func competence(state, ns, loader, line: String) -> float:
	var holder := String(ns.cabinet.get(line, ""))
	if holder == "":
		return 0.0
	for party in loader.parties.get(ns.id, []):
		if party.id == holder:
			return clampf(Cabinet.competence(party, line), 0.0, 1.0)
	return 0.0


## The quote for one legal row ({type, op, rows: [{region, units}]}); `earlier` are the
## rows of the same bill tabled before it, whose units count toward concentration.
static func quote(state, ns, loader, row: Dictionary, earlier: Array = []) -> Dictionary:
	var t: Dictionary = loader.unit_types[String(row["type"])]
	var cost := float(t["cost_eur_m"][ns.id])
	var running := float(t["running_eur_m"][ns.id])
	var gdp_m := float(ns.gdp_eur_bn) * 1000.0
	if String(row["op"]) == UK.OP_DEMOLISH:
		# The capacity closed, as a number of units' worth of new capacity.
		var worth := 0.0
		for r in row["rows"]:
			worth += float(r["capacity"]) / Units.unit_capacity(loader, ns.id, String(row["type"]))
		var once := worth * cost * float(t["demolish_cost_share"])
		var months := int(t["demolish_months"])
		return {"ok": true, "estimate_eur_m": once, "lo_eur_m": once, "hi_eur_m": once, "width": 0.0, "odds": 0.0,
			"surcharge": {}, "build_months": months, "running_eur_m_year": -worth * running,
			"capital_pct_gdp_year": 100.0 * once / months * 12.0 / gdp_m,
			"line_pct_gdp_year": -100.0 * worth * running / gdp_m}
	var units := 0
	for r in row["rows"]:
		units += int(r["units"])
	var c := competence(state, ns, loader, String(t["line"]))
	var width := UK.UNIT_FOG_MAX - (UK.UNIT_FOG_MAX - UK.UNIT_FOG_MIN) * c
	var surcharge := {}
	var estimate := 0.0
	for r in row["rows"]:
		var region := String(r["region"])
		var s := _surcharge(state, ns, loader, String(row["type"]), region, int(r["units"]), earlier)
		surcharge[region] = s
		estimate += float(r["units"]) * cost * (1.0 + s)
	var months := int(t["build_months"])
	var capital := 100.0 * estimate / months * 12.0 / gdp_m
	return {"ok": true, "estimate_eur_m": estimate, "lo_eur_m": estimate * (1.0 - width),
		"hi_eur_m": estimate * (1.0 + width), "width": width,
		"odds": clampf(float(t["overrun_odds"]) * (UK.UNIT_ODDS_BASE - c), UK.UNIT_ODDS_MIN, UK.UNIT_ODDS_MAX),
		"surcharge": surcharge, "build_months": months, "running_eur_m_year": float(units) * running,
		"capital_pct_gdp_year": capital, "line_pct_gdp_year": capital}


static func _surcharge(state, ns, loader, type_id: String, region: String, units: int, earlier: Array) -> float:
	var stock := Units.start_capacity(loader, ns.id, type_id, region)
	if stock <= 0.0:
		return 0.0
	var ordered := units
	var since := now(state) - UK.UNIT_CONC_MONTHS
	for p in ns.unit_programmes:
		if String(p.get("type", "")) == type_id and String(p.get("op", "")) == UK.OP_BUILD and int(p.get("voted", -1)) > since:
			ordered += _units_in(p, region)
	for row in earlier:
		if String(row.get("type", "")) == type_id and String(row.get("op", "")) == UK.OP_BUILD:
			ordered += _units_in(row, region)
	return UK.UNIT_CONC_SLOPE * maxf(0.0, float(ordered) * Units.unit_capacity(loader, ns.id, type_id) / stock - UK.UNIT_CONC_FREE)


static func _units_in(row: Dictionary, region: String) -> int:
	var n := 0
	for r in row.get("rows", []):
		if String(r.get("region", "")) == region:
			n += int(r.get("units", 0))
	return n
