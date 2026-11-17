extends RefCounted

## V5.3 c' (docs/design/v5.3-c-register.md section 2): data/units/, the
## construction register's content. Three kinds of file, Content's facts, each
## refused loudly on a bad row:
##
##   data/units/<type_id>.json      one catalogue row per unit type (flat object)
##   data/units/stock/<NAT>.json    {stock: [{region, type, units, capacity}],
##                                   levels: [{region, figure, level}]}
##   data/units/cofinancing.json    {organisations: {<org_id>: {rates: {category: rate},
##                                   warn_months, periods: [{id, first_year, last_year,
##                                   pays_until_year, envelope_eur_bn: {NAT: bn}}]}}}
##
## A MISSING DIRECTORY IS NO TYPE AT ALL, never an error (DomainsLoader's rule): a
## nation is offered a type only where its stock file names it, so the 37 nations
## nobody has sourced need nothing, and a tree with no data/units/ reads exactly the
## game before c' (band U1).
##
## THE FIVE PROJECTS ARE NOT IN data/units/ (section 8, the parent's ruling of
## 2026-11-17): their `potential` rows are built here from data/project-actions'
## start effects, one source with no copy, so a project's terms cannot drift between
## two files. Projects keep their own register; these rows are what the register's
## list reads over both.
##
## THE LEVEL IS STORED RELATIVE (section 2): a region's sourced figure over the
## population-weighted mean of its nation's regions, so the weighted mean is exactly
## 1 -- the rule Region.unemployment_rel follows, applied here at load because the
## figure is Content's raw value, not an importer's ratio. The nation's figure in
## data/domains stays the single truth; the level only places the regions around it.

const UK = preload("res://src/sim/units_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Region = preload("res://src/core/region.gd")

const TYPE_NUMBERS := ["capacity", "figure_elasticity", "staff", "overrun_odds", "overrun_share",
	"demolish_cost_share"]
const TYPE_MONTHS := ["build_months", "demolish_months", "band_units"]
const TYPE_SHARES := ["overrun_odds", "overrun_share", "demolish_cost_share"]


static func load_units(loader, dir: String) -> void:
	loader.unit_types = {}
	loader.unit_stock = {}
	loader.unit_levels = {}
	loader.unit_cofinancing = {}
	loader.unit_potential = potential_rows(loader)
	var da := DirAccess.open(dir)
	if da == null:
		return
	var files: Array[String] = []
	for f in da.get_files():
		var name := String(f)
		if name.ends_with(".json") and name != UK.COFINANCING_FILE and name != UK.COHESION_FILE:
			files.append(name)
	files.sort()
	for fname in files:
		var errors: Array[String] = []
		var row := parse_type(loader, JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(fname))), fname, errors)
		loader.errors.append_array(errors)
		if errors.is_empty():
			loader.unit_types[String(row["id"])] = row
	var stock_dir := dir.path_join(UK.STOCK_DIR)
	var sd := DirAccess.open(stock_dir)
	if sd != null:
		var stocks: Array[String] = []
		for f in sd.get_files():
			if String(f).ends_with(".json"):
				stocks.append(String(f))
		stocks.sort()
		for fname in stocks:
			var errors: Array[String] = []
			parse_stock(loader, fname.get_basename(), JSON.parse_string(FileAccess.get_file_as_string(stock_dir.path_join(fname))),
				loader.unit_types, "stock/" + fname, errors)
			loader.errors.append_array(errors)
	var cof_path := dir.path_join(UK.COFINANCING_FILE)
	if FileAccess.file_exists(cof_path):
		var errors: Array[String] = []
		loader.unit_cofinancing = parse_cofinancing(loader, JSON.parse_string(FileAccess.get_file_as_string(cof_path)),
			UK.COFINANCING_FILE, errors)
		loader.errors.append_array(errors)


## One catalogue row, validated against data/domains (its line, sector and figure).
## Public so tests/test_units.gd refuses each bad field on a dictionary with no file.
## Returns the row ({} with errors appended when it refuses).
static func parse_type(loader, parsed, fname: String, errors: Array[String]) -> Dictionary:
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("units/%s: missing or invalid JSON" % fname)
		return {}
	var d: Dictionary = parsed
	var id := String(d.get("id", ""))
	if id == "" or fname.get_basename() != id:
		errors.append("units/%s: 'id' must be the file's name" % fname)
		return {}
	for key in ["name", "summary"]:
		if typeof(d.get(key)) != TYPE_STRING or String(d[key]) == "":
			errors.append("units/%s: missing text '%s'" % [fname, key])
			return {}
	if not UK.CATALOGUE_PAYOFFS.has(String(d.get("payoff", ""))):
		errors.append("units/%s: 'payoff' must be one of %s" % [fname, str(UK.CATALOGUE_PAYOFFS)])
		return {}
	var line := String(d.get("line", ""))
	var sector := _sector(loader, line, String(d.get("sector", "")))
	if not EK.SPENDING_KEYS.has(line) or sector.is_empty():
		errors.append("units/%s: 'line' and 'sector' must name a sector of data/domains" % fname)
		return {}
	if String(d.get("figure", "")) != String(sector["quantity"]["id"]):
		errors.append("units/%s: 'figure' must be the sector's quantity, '%s'" % [fname, sector["quantity"]["id"]])
		return {}
	for key in TYPE_NUMBERS + TYPE_MONTHS:
		if not _is_number(d.get(key)):
			errors.append("units/%s: missing or non-numeric '%s'" % [fname, key])
			return {}
	for key in TYPE_MONTHS:
		if float(d[key]) < 1.0 or float(d[key]) != floorf(float(d[key])):
			errors.append("units/%s: '%s' must be a whole number from 1" % [fname, key])
			return {}
	for key in TYPE_SHARES:
		if float(d[key]) < 0.0 or float(d[key]) > 1.0:
			errors.append("units/%s: '%s' must be between 0 and 1" % [fname, key])
			return {}
	if float(d["capacity"]) <= 0.0 or float(d["staff"]) < 0.0 or float(d["figure_elasticity"]) == 0.0:
		errors.append("units/%s: 'capacity' must be above 0, 'staff' at least 0, 'figure_elasticity' not 0" % fname)
		return {}
	for key in ["cost_eur_m", "running_eur_m"]:
		var by_nation = d.get(key)
		if typeof(by_nation) != TYPE_DICTIONARY or (by_nation as Dictionary).is_empty():
			errors.append("units/%s: '%s' must be {NATION: EUR million}" % [fname, key])
			return {}
		for nation in by_nation:
			var floor_ok: bool = float(by_nation[nation]) > 0.0 if key == "cost_eur_m" else float(by_nation[nation]) >= 0.0
			if not loader.nations.has(String(nation)) or not _is_number(by_nation[nation]) or not floor_ok:
				errors.append("units/%s: '%s' has a bad entry for '%s'" % [fname, key, nation])
				return {}
	if typeof(d.get("cofinanced")) != TYPE_BOOL:
		errors.append("units/%s: 'cofinanced' must be true or false" % fname)
		return {}
	var offsets = d.get("bloc_offset_per_pop_share")
	if typeof(offsets) != TYPE_DICTIONARY:
		errors.append("units/%s: missing object 'bloc_offset_per_pop_share'" % fname)
		return {}
	for bloc in offsets:
		if not OpinionK.BLOC_KEYS.has(bloc) or not _is_number(offsets[bloc]):
			errors.append("units/%s: bloc_offset_per_pop_share names an unknown bloc or a non-number: %s" % [fname, bloc])
			return {}
	var row := {}
	for key in d:
		if not String(key).begins_with("_"):
			row[String(key)] = d[key]
	for key in TYPE_MONTHS:
		row[key] = int(d[key])
	row["capacity"] = float(d["capacity"])
	return row


## One nation's stock file into loader.unit_stock and loader.unit_levels. Every
## region is one of the nation's, every type a loaded catalogue row priced for the
## nation, and every figure of a stocked type has a level for every region (a
## missing one would place a region nowhere around the nation).
static func parse_stock(loader, nation_id: String, parsed, types: Dictionary, fname: String, errors: Array[String]) -> void:
	if not loader.nations.has(nation_id):
		errors.append("units/%s: no nation with id '%s'" % [fname, nation_id])
		return
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("stock")) != TYPE_ARRAY or typeof(parsed.get("levels")) != TYPE_ARRAY:
		errors.append("units/%s: expected {\"stock\": [...], \"levels\": [...]}" % fname)
		return
	var shares := {}
	for r in loader.regions.get(nation_id, []):
		shares[r.id] = r.share
	var stock := {}
	var figures := {}
	for row in parsed["stock"]:
		var region := String(row.get("region", "")) if typeof(row) == TYPE_DICTIONARY else ""
		var type_id := String(row.get("type", "")) if typeof(row) == TYPE_DICTIONARY else ""
		if not shares.has(region) or not types.has(type_id) \
				or not _is_number(row.get("units")) or float(row["units"]) < 0.0 or float(row["units"]) != floorf(float(row["units"])) \
				or not _is_number(row.get("capacity")) or float(row["capacity"]) < 0.0:
			errors.append("units/%s: bad stock row %s" % [fname, str(row)])
			return
		if not (types[type_id]["cost_eur_m"] as Dictionary).has(nation_id) or not (types[type_id]["running_eur_m"] as Dictionary).has(nation_id):
			errors.append("units/%s: type '%s' has no cost or running cost for %s" % [fname, type_id, nation_id])
			return
		var by_region: Dictionary = stock.get(type_id, {})
		if by_region.has(region):
			errors.append("units/%s: two stock rows for %s, %s" % [fname, region, type_id])
			return
		by_region[region] = {"units": int(row["units"]), "capacity": float(row["capacity"])}
		stock[type_id] = by_region
		figures[String(types[type_id]["figure"])] = true
	var raw := {}
	for row in parsed["levels"]:
		var region := String(row.get("region", "")) if typeof(row) == TYPE_DICTIONARY else ""
		var figure := String(row.get("figure", "")) if typeof(row) == TYPE_DICTIONARY else ""
		if not shares.has(region) or not figures.has(figure) or not _is_number(row.get("level")) or float(row["level"]) <= 0.0:
			errors.append("units/%s: bad level row %s" % [fname, str(row)])
			return
		var by_region: Dictionary = raw.get(figure, {})
		by_region[region] = float(row["level"])
		raw[figure] = by_region
	var levels := {}
	for figure in figures:
		var by_region: Dictionary = raw.get(figure, {})
		var weighted := 0.0
		var people := 0.0
		for region in shares:
			if not by_region.has(region):
				errors.append("units/%s: figure '%s' has no level for region %s" % [fname, figure, region])
				return
			weighted += float(shares[region]) * float(by_region[region])
			people += float(shares[region])
		var mean := weighted / people
		var rel := {}
		for region in by_region:
			rel[region] = float(by_region[region]) / mean
		levels[figure] = rel
	loader.unit_stock[nation_id] = stock
	loader.unit_levels[nation_id] = levels


## The Union's rule (section 6), refused whole on a bad entry. Returns
## {org_id: {rates, warn_months, periods}} ({} with errors appended).
static func parse_cofinancing(loader, parsed, fname: String, errors: Array[String]) -> Dictionary:
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("organisations")) != TYPE_DICTIONARY:
		errors.append("units/%s: expected {\"organisations\": {...}}" % fname)
		return {}
	var out := {}
	for org_id in parsed["organisations"]:
		var rule = parsed["organisations"][org_id]
		if not loader.orgs_by_id.has(String(org_id)) or typeof(rule) != TYPE_DICTIONARY:
			errors.append("units/%s: '%s' is not an organisation of data/orgs" % [fname, org_id])
			return {}
		var rates = rule.get("rates")
		if typeof(rates) != TYPE_DICTIONARY or (rates as Dictionary).is_empty():
			errors.append("units/%s: %s has no 'rates'" % [fname, org_id])
			return {}
		for category in rates:
			if not Region.COHESION_CATEGORIES.has(String(category)) or not _is_number(rates[category]) \
					or float(rates[category]) < 0.0 or float(rates[category]) > 1.0:
				errors.append("units/%s: %s has a bad rate for '%s'" % [fname, org_id, category])
				return {}
		if not _is_number(rule.get("warn_months")) or float(rule["warn_months"]) < 1.0:
			errors.append("units/%s: %s needs 'warn_months' from 1" % [fname, org_id])
			return {}
		var periods: Array = []
		for p in rule.get("periods", []):
			if typeof(p) != TYPE_DICTIONARY or typeof(p.get("id")) != TYPE_STRING or typeof(p.get("envelope_eur_bn")) != TYPE_DICTIONARY \
					or not _is_number(p.get("first_year")) or not _is_number(p.get("last_year")) or not _is_number(p.get("pays_until_year")) \
					or float(p["first_year"]) > float(p["last_year"]) or float(p["last_year"]) > float(p["pays_until_year"]):
				errors.append("units/%s: %s has a bad period %s" % [fname, org_id, str(p)])
				return {}
			for nation in p["envelope_eur_bn"]:
				if not loader.nations.has(String(nation)) or not _is_number(p["envelope_eur_bn"][nation]) or float(p["envelope_eur_bn"][nation]) < 0.0:
					errors.append("units/%s: %s period %s has a bad envelope for '%s'" % [fname, org_id, p["id"], nation])
					return {}
			periods.append({"id": String(p["id"]), "first_year": int(p["first_year"]), "last_year": int(p["last_year"]),
				"pays_until_year": int(p["pays_until_year"]), "envelope_eur_bn": (p["envelope_eur_bn"] as Dictionary).duplicate()})
		if periods.is_empty():
			errors.append("units/%s: %s has no 'periods'" % [fname, org_id])
			return {}
		out[String(org_id)] = {"rates": (rates as Dictionary).duplicate(), "warn_months": int(rule["warn_months"]), "periods": periods}
	return out


## Section 8: each project's start terms as a `potential` row, quantity 1, no range
## width and no overrun odds, so nothing about a project changes.
static func potential_rows(loader) -> Array:
	var out: Array = []
	for action in loader.project_actions:
		var terms: Dictionary = action.effects.get("project", {})
		if String(terms.get("op", "")) != "start":
			continue
		out.append({"id": String(terms["project_id"]), "name": String(terms.get("project_name", "")),
			"payoff": UK.PAYOFF_POTENTIAL, "quantity": 1, "build_months": int(terms["build_months"]),
			"cost_pct_gdp": float(terms["cost_pct_gdp"]), "potential_growth_pct": float(terms["potential_growth_pct"]),
			"range_width": 0.0, "overrun_odds": 0.0})
	return out


static func _sector(loader, line: String, sector_id: String) -> Dictionary:
	for s in (loader.domains.get(line, {}) as Dictionary).get("sectors", []):
		if String(s["id"]) == sector_id:
			return s
	return {}


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
