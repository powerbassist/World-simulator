extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. data/commodities/ and data/world/: the goods, the recipes, the endowments and the outline nations.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too), every register lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim (now <ThisLoader>.<name>), its members read
## through `loader.`.


## V4.6's seven, closed. The granularity rule behind the list is
## docs/tiers/v4.md's: a good exists if a player decision can move its price. An
## entry naming an eighth is a load error rather than a new category, because the
## seven are what the production tick and the surfaces iterate -- adding one is a
## deliberate edit HERE and in the model, not a data edit that silently widens
## every loop. Declared on the loader rather than in a constants file because the
## closed-seven validation is the loader's own job (this list is its vocabulary);
## the surfaces also iterate it (the Commodities panel groups its ledger and its
## tree by these categories), which is the second half of the same placement.
const COMMODITY_CATEGORIES := ["raw", "agri", "energy", "intermediate", "capital", "consumer", "services"]

## The producer id the endowment file uses for the sources' unnamed remainder.
const WORLD_OTHER := "WORLD_OTHER"


## data/commodities/goods.json, one file and global (data/energy-sources.json's
## shape and its reason: a good names no place and no nation). An entry is a
## dictionary and not a typed value type at region_graph's own precedent -- the
## one reader takes it as DATA, and a type here would be a second record of a
## file that already states its own shape. What this function can see that a
## runtime never would is a duplicate id (one good silently overwriting another)
## and a category outside the seven.
static func load_commodity_goods(loader, path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		loader.errors.append("data/commodities/goods.json: could not read file")
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("goods")) != TYPE_ARRAY:
		loader.errors.append("data/commodities/goods.json: expected {\"goods\": [...]}")
		return

	for i in (parsed as Dictionary)["goods"].size():
		var entry = (parsed as Dictionary)["goods"][i]
		if typeof(entry) != TYPE_DICTIONARY:
			loader.errors.append("data/commodities/goods.json: goods[%d] is not an object" % i)
			continue
		var e: Dictionary = entry
		var gid := String(e.get("id", ""))
		if gid == "":
			loader.errors.append("data/commodities/goods.json: goods[%d] missing or invalid string field 'id'" % i)
			continue
		var where := "goods.json: %s" % gid
		if not e.has("name") or typeof(e["name"]) != TYPE_STRING or String(e["name"]).strip_edges() == "":
			loader.errors.append("%s missing or invalid string field 'name'" % where)
		var category := String(e.get("category", ""))
		if not COMMODITY_CATEGORIES.has(category):
			loader.errors.append("%s category '%s' is not one of %s" % [where, category, str(COMMODITY_CATEGORIES)])
		var price := float(e.get("base_price", 0.0))
		if price <= 0.0:
			loader.errors.append("%s base_price must be positive -- a free good has no price for a shortage to move" % where)
		if not e.has("unit") or typeof(e["unit"]) != TYPE_STRING or String(e["unit"]).strip_edges() == "":
			loader.errors.append("%s missing or invalid string field 'unit'" % where)
		if loader.commodity_goods.has(gid):
			loader.errors.append("data/commodities/goods.json: duplicate good id '%s'" % gid)
		else:
			loader.commodity_goods[gid] = e


## data/commodities/recipes.json, goods.json's shape. THE CROSS-FILE HALF IS THE
## WHOLE POINT of loading this after goods: an output or an input naming a good
## nobody declares would sit in the file looking like a recipe and produce nothing
## at tick time -- the expensive silent class every data check in this project
## exists to close. Raw, agri and services therefore carry NO recipe at all: they
## are primary producers, and a row for one would be a second way to declare the
## same output.
static func load_commodity_recipes(loader, path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		loader.errors.append("data/commodities/recipes.json: could not read file")
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("recipes")) != TYPE_ARRAY:
		loader.errors.append("data/commodities/recipes.json: expected {\"recipes\": [...]}")
		return

	for i in (parsed as Dictionary)["recipes"].size():
		var entry = (parsed as Dictionary)["recipes"][i]
		if typeof(entry) != TYPE_DICTIONARY:
			loader.errors.append("data/commodities/recipes.json: recipes[%d] is not an object" % i)
			continue
		var e: Dictionary = entry
		var rid := String(e.get("id", ""))
		if rid == "":
			loader.errors.append("data/commodities/recipes.json: recipes[%d] missing or invalid string field 'id'" % i)
			continue
		var where := "recipes.json: %s" % rid
		var output := String(e.get("output", ""))
		if not loader.commodity_goods.has(output):
			loader.errors.append("%s output '%s' is not a good in data/commodities/goods.json" % [where, output])
		if typeof(e.get("inputs", null)) != TYPE_DICTIONARY:
			loader.errors.append("%s missing or invalid object field 'inputs' -- {} is legal and means a primary producer, which is why it must be stated" % where)
		else:
			for inp in (e["inputs"] as Dictionary):
				if not loader.commodity_goods.has(inp):
					loader.errors.append("%s input '%s' is not a good in data/commodities/goods.json" % [where, inp])
				elif float(e["inputs"][inp]) <= 0.0:
					loader.errors.append("%s input '%s' quantity must be positive" % [where, inp])
		# Positive rather than non-negative, per the contract: a route with no
		# labour and no capital behind it is a transformation out of nothing.
		if float(e.get("labour_per_unit", 0.0)) <= 0.0:
			loader.errors.append("%s labour_per_unit must be positive" % where)
		if float(e.get("capital_per_unit", 0.0)) <= 0.0:
			loader.errors.append("%s capital_per_unit must be positive" % where)
		if loader.commodity_recipes.has(rid):
			loader.errors.append("data/commodities/recipes.json: duplicate recipe id '%s'" % rid)
		else:
			loader.commodity_recipes[rid] = e


## The register's own emptiness, which no per-entry read can see: an empty
## register puts nothing on the panel and nothing in any tile. Per-entry
## correctness is refused at load (references, positivity), and category
## coverage -- every category filled by some good -- is a suite-side gate in
## tests/test_commodities_data.gd, not a loader check.
static func validate_commodities(loader) -> void:
	if loader.commodity_goods.is_empty():
		loader.errors.append("data/commodities/goods.json defines no goods")
	if loader.commodity_recipes.is_empty():
		loader.errors.append("data/commodities/recipes.json defines no recipes")
	validate_endowments(loader)


## V4.11b. Both files may be absent (a fixture); a file that IS present must be a
## partition per good over producers the registers know, covering every raw and
## agri good -- a good it skipped would silently keep the synthetic capacity
## beside real ones, and the world would stop balancing.
static func load_commodity_endowments(loader, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("goods")) != TYPE_DICTIONARY:
		loader.errors.append("data/commodities/endowments.json: expected {\"goods\": {...}}")
		return
	var goods: Dictionary = (parsed as Dictionary)["goods"]
	for good_id in goods.keys():
		var entry = goods[good_id]
		if typeof(entry) != TYPE_DICTIONARY or typeof((entry as Dictionary).get("shares")) != TYPE_DICTIONARY:
			loader.errors.append("endowments.json: %s has no shares object" % good_id)
			continue
		var shares := {}
		for producer in (entry as Dictionary)["shares"].keys():
			shares[String(producer)] = float((entry as Dictionary)["shares"][producer])
		loader.commodity_endowments[String(good_id)] = shares


static func load_outlines(loader, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("outlines")) != TYPE_ARRAY:
		loader.errors.append("data/world/outlines.json: expected {\"outlines\": [...]}")
		return
	for entry in (parsed as Dictionary)["outlines"]:
		if typeof(entry) != TYPE_DICTIONARY or String((entry as Dictionary).get("id", "")) == "":
			loader.errors.append("outlines.json: an entry has no id")
			continue
		var e: Dictionary = entry
		var gdp = e.get("gdp_eur_bn", null)
		loader.outlines[String(e["id"])] = {
			"name": String(e.get("name", "")),
			"gdp_eur_bn": float(gdp) if gdp != null else -1.0,
		}


## The outline register against the map that draws it, one-for-one -- run from
## GeoLoader.validate_cross_file(), the first place world.geojson is in hand.
static func validate_outlines(loader) -> void:
	if loader.outlines.is_empty():
		return
	for id in loader.outlines.keys():
		if not loader.world_features.has(id):
			loader.errors.append("outlines.json: '%s' is not drawn by world.geojson" % id)
		if loader.nations.has(id):
			loader.errors.append("outlines.json: '%s' is a nation file too -- one grade per id" % id)
	for id in loader.world_features.keys():
		if not loader.outlines.has(id):
			loader.errors.append("world.geojson draws '%s' and outlines.json does not carry it" % id)


static func validate_endowments(loader) -> void:
	if loader.commodity_endowments.is_empty():
		return
	for good_id in loader.commodity_goods.keys():
		var category := String(loader.commodity_goods[good_id].get("category", ""))
		var natural := category == "raw" or category == "agri"
		if natural and not loader.commodity_endowments.has(good_id):
			loader.errors.append("endowments.json: raw/agri good '%s' has no endowment" % good_id)
		if not natural and loader.commodity_endowments.has(good_id):
			loader.errors.append("endowments.json: '%s' is %s, not raw or agri -- manufactures are made, not endowed" % [good_id, category])
	for good_id in loader.commodity_endowments.keys():
		if not loader.commodity_goods.has(good_id):
			loader.errors.append("endowments.json: '%s' is not a registered good" % good_id)
			continue
		var total := 0.0
		for producer in loader.commodity_endowments[good_id].keys():
			var share := float(loader.commodity_endowments[good_id][producer])
			if share < 0.0 or share > 1.0:
				loader.errors.append("endowments.json: %s share of %s is %s, outside [0, 1]" % [producer, good_id, str(share)])
			total += share
			if producer != WORLD_OTHER and not loader.nations.has(producer) and not loader.outlines.has(producer):
				loader.errors.append("endowments.json: %s names producer '%s', neither a nation nor an outline" % [good_id, producer])
		if absf(total - 1.0) > 1e-4:
			loader.errors.append("endowments.json: %s shares sum to %s, not 1" % [good_id, str(total)])
