extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. data/regions/ and the region
## graph: the places per nation, checked against the geometry and the graph.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too); every register
## lives on the loader, whose public surface did not move. Each function here
## is the body that used to be DataLoader._<name>() verbatim, now
## RegionsLoader.<name>(loader, ...), its members read through `loader.`.

const Region = preload("res://src/core/region.gd")
const GeoLoader = preload("res://src/core/loaders/geo_loader.gd")


## One data/regions/<NATION>.json per nation, {"regions": [...]}, on
## data/companies/*.json's per-nation shape -- V2.2a. See docs/geography-model.md.
##
## AN ABSENT FILE *IS* AN ERROR, and that is the one place this register departs from
## the two it copies. A nation with no companies has unpartitioned sectors and a nation
## with no outlets has no press, and both are models the roster ran before V1.4a and
## V1.5d respectively -- so an absent file there is a coverage decision a later session
## may take. There is no such prior model here: docs/tiers/v2.md section 5 makes
## national = sum of regions the economic spine, so a nation with no regions is one the
## rest of this tier cannot describe at all.
static func load_regions(loader, nation_id: String, regions_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := regions_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		loader.errors.append("regions/%s: could not read file" % fname)
		loader.regions[nation_id] = []
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("regions")) != TYPE_ARRAY:
		loader.errors.append("regions/%s: invalid regions file, expected {\"regions\": [...]}" % fname)
		loader.regions[nation_id] = []
		return

	var raw_list: Array = parsed["regions"]
	var parsed_regions: Array = []
	var per_file_errors: Array[String] = []
	var seen_ids := {}

	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			per_file_errors.append("regions/%s: regions[%d] is not an object" % [fname, i])
			continue
		var region = Region.from_dict(entry, i, "regions/" + fname, per_file_errors)
		if region.id == "":
			continue
		if seen_ids.has(region.id):
			per_file_errors.append("regions/%s: duplicate region id '%s'" % [fname, region.id])
		seen_ids[region.id] = true
		parsed_regions.append(region)

	loader.errors.append_array(per_file_errors)
	loader.regions[nation_id] = parsed_regions


## The cross-file half, and every one of these three checks exists because the raw
## data broke it during the session that wrote them.
##
## The national partition: named regions summing past 1.0 claim more of the country
## than there is. The Eurostat response carries TWO NUTS VINTAGES AT ONCE -- `NL35`
## and `NL36` are the 2024 codes for Utrecht and Zuid-Holland and `NL31`/`NL33` the
## 2021 ones, equal to the person -- so a Netherlands built without filtering to the
## geometry's own roster is 5.1 M people too large.
##
## The domicile: a firm's `city` naming a place the register does not hold is
## docs/tiers/v2.md section 2's own claim -- *"a city's employment is already written
## in data/companies/"* -- failing silently, and it is the ONLY thing making that field
## load-bearing before V2.2b draws it. U6c's rule about a coordinate nothing reads.
##
## The orphan file: OutletsLoader.validate_outlets()' scan, for its reason. A per-nation lookup
## structurally cannot see data/regions/FRE.json, because that file is simply never
## opened -- which is tools/check_names.sh's zero-files-scanned burn in a new place.
##
## The geometry: every register region must have a polygon, because the register is
## the set of NUTS codes carrying BOTH a figure and a GISCO polygon -- that single
## rule is what resolved extra-regio, the two Dutch vintages and the overseas
## regions, so a region with figures and no geometry is an import that has drifted
## from its own authority. V2.2a shipped the file unopened (nothing drew it, so a
## launch should not pay 180 KB for it); V2.2b draws it, and this is where the
## load happens -- GeoLoader.validate_cross_file's precedent, the load and the check it
## exists for arriving together.
static func validate_regions(loader, regions_dir: String, regions_geo_path: String, regions_graph_path: String) -> void:
	var city_ids := {}
	for nation_id in loader.regions.keys():
		var total := 0.0
		var gdp_total := 0.0
		for region in loader.regions[nation_id]:
			total += region.share
			gdp_total += region.gdp_share
			for city in region.cities:
				if city_ids.has(city.id):
					loader.errors.append(
						"regions/%s.json: city id '%s' is already used by %s -- a city id is read bare off a firm's `city` and has to be globally unique"
						% [nation_id, city.id, city_ids[city.id]]
					)
				city_ids[city.id] = nation_id
		if total > 1.0 + 0.000001:
			loader.errors.append(
				"regions/%s.json: region shares sum to %s, above 1.0 -- the named regions would hold more people than the nation does"
				% [nation_id, str(total)]
			)
		if gdp_total > 1.0 + 0.000001:
			loader.errors.append(
				"regions/%s.json: region GDP shares sum to %s, above 1.0 -- the named regions would produce more than the nation does"
				% [nation_id, str(gdp_total)]
			)

	for nation_id in loader.companies.keys():
		for company in loader.companies[nation_id]:
			if company.city == "":
				continue
			if not city_ids.has(company.city):
				loader.errors.append(
					"companies/%s.json: firm '%s' is domiciled in '%s', which is not a city in data/regions/"
					% [nation_id, company.id, company.city]
				)
			elif city_ids[company.city] != nation_id:
				loader.errors.append(
					"companies/%s.json: firm '%s' is domiciled in '%s', which is a city of %s"
					% [nation_id, company.id, company.city, city_ids[company.city]]
				)

	GeoLoader.load_geo(loader, regions_geo_path, loader.region_features, true, loader.region_rings)
	load_region_graph(loader, regions_graph_path)
	for nation_id in loader.regions.keys():
		for region in loader.regions[nation_id]:
			if not loader.region_features.has(region.id):
				loader.errors.append(
					"regions/%s.json: region '%s' has no polygon in %s -- the geometry is the authority on the roster, and a region that cannot be drawn is one the register cannot hold"
					% [nation_id, region.id, regions_geo_path]
				)

	# FIFTH RULE, V2.7. Every graph id is a register id and every register id has an
	# endowment. V2.2b's fourth rule cross-checks the register against the GEOMETRY at
	# load time; this is the same check against the GRAPH, and it is what catches an
	# importer run that wrote one file and not the other -- the two are generated
	# together and can only disagree by a partial run.
	if not loader.region_graph.is_empty():
		var endowment: Dictionary = loader.region_graph.get("endowment", {})
		for nation_id in loader.regions.keys():
			for region in loader.regions[nation_id]:
				if not endowment.has(region.id):
					loader.errors.append("regions/%s.json: region '%s' has no entry in data/geo/region_graph.json -- re-run tools/import_data.py" % [nation_id, region.id])
		for region_id in endowment.keys():
			var known := false
			for nation_id in loader.regions.keys():
				for region in loader.regions[nation_id]:
					if region.id == region_id:
						known = true
						break
			if not known:
				loader.errors.append("geo/region_graph.json: names region '%s', which no data/regions/ file carries" % region_id)

	var da := DirAccess.open(regions_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % regions_dir)
		return
	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if not da.current_is_dir() and file_name.ends_with(".json"):
			var nation_id := file_name.get_basename()
			if not loader.nations.has(nation_id):
				loader.errors.append(
					"regions/%s: no nation with id '%s' -- the file is never opened"
					% [file_name, nation_id]
				)
		file_name = da.get_next()
	da.list_dir_end()


## The graph, refused loudly rather than defaulted. An absent file is an error and not
## an empty graph: a nation whose regions cannot reach each other has every
## accessibility read collapse to its own output, which is a different model running
## silently -- data/regions/'s own rule ("there is no prior model in which a nation
## has no places") one file over.
static func load_region_graph(loader, path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		loader.errors.append("geo/region_graph.json: could not read file")
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		loader.errors.append("geo/region_graph.json: expected an object")
		return
	var raw_edges = (parsed as Dictionary).get("edges", null)
	var raw_endowment = (parsed as Dictionary).get("endowment", null)
	if typeof(raw_edges) != TYPE_ARRAY or typeof(raw_endowment) != TYPE_DICTIONARY:
		loader.errors.append("geo/region_graph.json: expected 'edges' array and 'endowment' object")
		return
	var edges: Array = []
	for i in (raw_edges as Array).size():
		var entry = raw_edges[i]
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 4:
			loader.errors.append("geo/region_graph.json: edges[%d] is not [a, b, km, kind]" % i)
			continue
		edges.append([String(entry[0]), String(entry[1]), float(entry[2]), String(entry[3])])
	var endowment: Dictionary = {}
	for key in (raw_endowment as Dictionary).keys():
		endowment[String(key)] = float(raw_endowment[key])
	loader.region_graph = {"edges": edges, "endowment": endowment}
