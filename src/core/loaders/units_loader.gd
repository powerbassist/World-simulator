extends RefCounted

## V5.3 c' (docs/design/v5.3-c-register.md section 2): data/units/, the
## construction register's content. Three kinds of file, Content's facts, each
## refused loudly on a bad row:
##
##   data/units/<type_id>.json      one catalogue row per unit type (flat object):
##                                  every root *.json but cofinancing.json
##   data/units/stock/<NAT>.json    {stock: [{region, type, units, capacity}],
##                                   figures: {<type>: {figure, national, levels}}}
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
## EACH TYPE ANSWERS ITS OWN FIGURE (section 1 as amended): its national value and its
## regional levels come from one table, in its stock file, stored relative to the
## national value and normalised again at read (Units.level, T3 on #410) over the LIVE
## people and the priority term, the one basis the screen multiplies. The sector's row
## in data/domains is untouched: the type rides its path, never its figure.

const UK = preload("res://src/sim/units_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Region = preload("res://src/core/region.gd")

const TYPE_NUMBERS := ["figure_elasticity", "staff", "overrun_odds", "overrun_share",
	"demolish_cost_share"]
const TYPE_MONTHS := ["build_months", "demolish_months", "band_units"]
const TYPE_SHARES := ["overrun_odds", "overrun_share", "demolish_cost_share"]


static func load_units(loader, dir: String) -> void:
	loader.unit_types = {}
	loader.unit_stock = {}
	loader.unit_levels = {}
	loader.unit_national = {}
	loader.unit_cofinancing = {}
	loader.unit_warnings.clear()
	loader.unit_potential = potential_rows(loader.project_actions)
	var da := DirAccess.open(dir)
	if da == null:
		return
	var files: Array[String] = []
	for f in da.get_files():
		var name := String(f)
		if name.ends_with(".json") and name != UK.COFINANCING_FILE:
			files.append(name)
	files.sort()
	# One type per figure in c' (section 3): a second type answering a figure already
	# taken would show its own gain beside the first's.
	var figures := {}
	for fname in files:
		var errors: Array[String] = []
		var row := parse_type(loader, JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(fname))), fname, errors)
		if errors.is_empty() and figures.has(String(row["figure"]["id"])):
			errors.append("units/%s: figure '%s' is already answered by type '%s'" % [fname, row["figure"]["id"], figures[String(row["figure"]["id"])]])
		loader.errors.append_array(errors)
		if errors.is_empty():
			loader.unit_types[String(row["id"])] = row
			figures[String(row["figure"]["id"])] = String(row["id"])
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
		warn_uncategorised(loader)


## An absent cohesion_category reads as no rate (0 %), the right reading for a region
## outside the Union's map, so a member nation whose regions ALL lack one would get
## nothing in silence (the parent's ruling on #409): one warning per such nation and
## organisation with a stock file, kept on loader.unit_warnings and printed once. A warning, not a load
## error, because the categories land in data/regions after this loader does.
static func warn_uncategorised(loader) -> void:
	loader.unit_warnings.clear()
	for org_id in loader.unit_cofinancing:
		var org = loader.orgs_by_id.get(org_id)
		if org == null:
			continue
		var members: Array = org.members.keys()
		members.sort()
		for nation_id in members:
			# Only a nation the register can build in (T6 on #410): no stock file, no
			# unit to co-finance, nothing to warn about.
			var regions: Array = loader.regions.get(nation_id, [])
			if regions.is_empty() or not loader.unit_stock.has(nation_id):
				continue
			var any := false
			for r in regions:
				if r.cohesion_category != "":
					any = true
					break
			if not any:
				var line := "units/%s: %s is a member of %s and none of its regions has a cohesion_category -- its co-financing reads 0 %%" % [
					UK.COFINANCING_FILE, nation_id, org_id]
				loader.unit_warnings.append(line)
				push_warning(line)


## One catalogue row, validated against data/domains (the line and sector whose path
## it rides) and against itself (its own figure, section 1 as amended). Public so
## tests/test_units.gd refuses each bad field on a dictionary with no file. Returns
## the row ({} with errors appended when it refuses).
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
	if not EK.SPENDING_KEYS.has(line) or _sector(loader, line, String(d.get("sector", ""))).is_empty():
		errors.append("units/%s: 'line' and 'sector' must name a sector of data/domains" % fname)
		return {}
	# The type's OWN figure (section 1 as amended): {id, unit, better}.
	var figure = d.get("figure")
	if typeof(figure) != TYPE_DICTIONARY or typeof(figure.get("id")) != TYPE_STRING or String(figure["id"]) == "" \
			or typeof(figure.get("unit")) != TYPE_STRING or not ["lower", "higher"].has(String(figure.get("better", ""))):
		errors.append("units/%s: 'figure' must be {id, unit, better: lower | higher}" % fname)
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
	if float(d["staff"]) < 0.0 or float(d["figure_elasticity"]) == 0.0:
		errors.append("units/%s: 'staff' must be at least 0, 'figure_elasticity' not 0" % fname)
		return {}
	# More capacity always improves the figure (T10 on #410): the sign follows `better`.
	var lower := String(figure["better"]) == "lower"
	if (float(d["figure_elasticity"]) < 0.0) != lower:
		errors.append("units/%s: 'figure_elasticity' must be %s for a figure where %s is better" % [
			fname, "below 0" if lower else "above 0", figure["better"]])
		return {}
	# By nation: the capacity of one new unit (in the stock's own unit) and what it costs.
	for key in ["capacity", "cost_eur_m", "running_eur_m"]:
		var by_nation = d.get(key)
		if typeof(by_nation) != TYPE_DICTIONARY or (by_nation as Dictionary).is_empty():
			errors.append("units/%s: '%s' must be {NATION: number}" % [fname, key])
			return {}
		for nation in by_nation:
			if String(nation).begins_with("_"):
				continue
			if not loader.nations.has(String(nation)) or not _is_number(by_nation[nation]) \
					or float(by_nation[nation]) < 0.0 or (key != "running_eur_m" and float(by_nation[nation]) == 0.0):
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
	for key in ["capacity", "cost_eur_m", "running_eur_m"]:
		row[key] = _data(d[key])
	return row


## One nation's stock file into loader.unit_stock, loader.unit_levels and
## loader.unit_national (section 2 as amended):
##   {stock: [{region, type, units, capacity}],
##    figures: {<type_id>: {figure, national, levels: [{region, level}]}}}
## Every region is one of the nation's, every type a loaded catalogue row priced and
## sized for the nation, and every stocked type has its figure: its id, its national
## value and one level per region, from one table. The levels are stored relative to
## `national`, and a file whose levels, weighted by the regions' people, do not give
## `national` back within UNIT_LEVEL_TOLERANCE is refused (unemployment_rel's check).
static func parse_stock(loader, nation_id: String, parsed, types: Dictionary, fname: String, errors: Array[String]) -> void:
	if not loader.nations.has(nation_id):
		errors.append("units/%s: no nation with id '%s'" % [fname, nation_id])
		return
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("stock")) != TYPE_ARRAY or typeof(parsed.get("figures")) != TYPE_DICTIONARY:
		errors.append("units/%s: expected {\"stock\": [...], \"figures\": {...}}" % fname)
		return
	var shares := {}
	for r in loader.regions.get(nation_id, []):
		shares[r.id] = r.share
	var stock := {}
	for row in parsed["stock"]:
		var region := String(row.get("region", "")) if typeof(row) == TYPE_DICTIONARY else ""
		var type_id := String(row.get("type", "")) if typeof(row) == TYPE_DICTIONARY else ""
		if not shares.has(region) or not types.has(type_id) \
				or not _is_number(row.get("units")) or float(row["units"]) < 0.0 or float(row["units"]) != floorf(float(row["units"])) \
				or not _is_number(row.get("capacity")) or float(row["capacity"]) < 0.0:
			errors.append("units/%s: bad stock row %s" % [fname, str(row)])
			return
		for key in ["capacity", "cost_eur_m", "running_eur_m"]:
			if not (types[type_id][key] as Dictionary).has(nation_id):
				errors.append("units/%s: type '%s' has no '%s' for %s" % [fname, type_id, key, nation_id])
				return
		var by_region: Dictionary = stock.get(type_id, {})
		if by_region.has(region):
			errors.append("units/%s: two stock rows for %s, %s" % [fname, region, type_id])
			return
		by_region[region] = {"units": int(row["units"]), "capacity": float(row["capacity"])}
		stock[type_id] = by_region
	var levels := {}
	var national := {}
	for type_id in stock:
		var entry = parsed["figures"].get(type_id)
		if typeof(entry) != TYPE_DICTIONARY or String(entry.get("figure", "")) != String(types[type_id]["figure"]["id"]) \
				or not _is_number(entry.get("national")) or float(entry["national"]) <= 0.0 or typeof(entry.get("levels")) != TYPE_ARRAY:
			errors.append("units/%s: type '%s' needs {figure: '%s', national, levels}" % [fname, type_id, types[type_id]["figure"]["id"]])
			return
		var raw := {}
		for row in entry["levels"]:
			var region := String(row.get("region", "")) if typeof(row) == TYPE_DICTIONARY else ""
			if not shares.has(region) or not _is_number(row.get("level")) or float(row["level"]) <= 0.0:
				errors.append("units/%s: bad level row %s for '%s'" % [fname, str(row), type_id])
				return
			if raw.has(region):
				errors.append("units/%s: two level rows for %s, %s" % [fname, region, type_id])
				return
			raw[region] = float(row["level"])
		var weighted := 0.0
		var people := 0.0
		for region in shares:
			if not raw.has(region):
				errors.append("units/%s: type '%s' has no level for region %s" % [fname, type_id, region])
				return
			weighted += float(shares[region]) * float(raw[region])
			people += float(shares[region])
		var nat := float(entry["national"])
		if people > 0.0 and absf(weighted / people - nat) > UK.UNIT_LEVEL_TOLERANCE * nat:
			errors.append("units/%s: '%s' levels weighted by people give %s, not its national %s" % [fname, type_id, str(weighted / people), str(nat)])
			return
		var rel := {}
		for region in raw:
			rel[region] = float(raw[region]) / nat
		levels[type_id] = rel
		national[type_id] = nat
	loader.unit_stock[nation_id] = stock
	loader.unit_levels[nation_id] = levels
	loader.unit_national[nation_id] = national



## The Union's rule (section 6), refused whole on a bad entry. Returns
## {org_id: {rates, warn_months, periods}} ({} with errors appended).
static func parse_cofinancing(loader, parsed, fname: String, errors: Array[String]) -> Dictionary:
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("organisations")) != TYPE_DICTIONARY:
		errors.append("units/%s: expected {\"organisations\": {...}}" % fname)
		return {}
	var out := {}
	# A `_` key is a label for a reader at any level (a stand-in period's note), never data.
	for org_id in parsed["organisations"]:
		if String(org_id).begins_with("_"):
			continue
		var rule = parsed["organisations"][org_id]
		if not loader.orgs_by_id.has(String(org_id)) or typeof(rule) != TYPE_DICTIONARY:
			errors.append("units/%s: '%s' is not an organisation of data/orgs" % [fname, org_id])
			return {}
		var rates = rule.get("rates")
		if typeof(rates) != TYPE_DICTIONARY or (rates as Dictionary).is_empty():
			errors.append("units/%s: %s has no 'rates'" % [fname, org_id])
			return {}
		# Every category priced (T4 on #410): a missing one would read 0 % in silence.
		for category in Region.COHESION_CATEGORIES:
			if not (rates as Dictionary).has(category):
				errors.append("units/%s: %s has no rate for '%s'" % [fname, org_id, category])
				return {}
		for category in rates:
			if String(category).begins_with("_"):
				continue
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
				if String(nation).begins_with("_"):
					continue
				if not loader.nations.has(String(nation)) or not _is_number(p["envelope_eur_bn"][nation]) or float(p["envelope_eur_bn"][nation]) < 0.0:
					errors.append("units/%s: %s period %s has a bad envelope for '%s'" % [fname, org_id, p["id"], nation])
					return {}
			periods.append({"id": String(p["id"]), "first_year": int(p["first_year"]), "last_year": int(p["last_year"]),
				"pays_until_year": int(p["pays_until_year"]), "envelope_eur_bn": _data(p["envelope_eur_bn"])})
		if periods.is_empty():
			errors.append("units/%s: %s has no 'periods'" % [fname, org_id])
			return {}
		out[String(org_id)] = {"rates": _data(rates), "warn_months": int(rule["warn_months"]), "periods": periods}
	return out


## Section 8: each project's start terms as a `potential` row, quantity 1, no range
## width and no overrun odds, so nothing about a project changes. An action whose
## terms the verb loader refused (T7 on #410) is skipped: that refusal is already a
## load error there, and a second read of bad terms here would be a script error.
static func potential_rows(actions: Array) -> Array:
	var out: Array = []
	for action in actions:
		var terms = action.effects.get("project", {}) if typeof(action.effects) == TYPE_DICTIONARY else {}
		if typeof(terms) != TYPE_DICTIONARY or String(terms.get("op", "")) != "start" \
				or typeof(terms.get("project_id")) != TYPE_STRING or String(terms["project_id"]) == "" \
				or not _is_number(terms.get("build_months")) or not _is_number(terms.get("cost_pct_gdp")) \
				or not _is_number(terms.get("potential_growth_pct")):
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


## A dictionary without its `_` labels.
static func _data(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		if not String(key).begins_with("_"):
			out[key] = d[key]
	return out


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
