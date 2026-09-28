extends SceneTree

## Headless test: godot --headless --script res://tests/test_geography.gd
## Non-zero exit on any failure.
##
## V2.2a, the geographic register. Model: docs/geography-model.md.
##
## THE LOAD-BEARING ASSERTIONS ARE THE THREE THE RAW DATA BROKE while this session
## was being written, and each is here because reading the generated file caught it
## and no check did:
##
##   - A REGION CANNOT BE MORE THAN FULLY NAMED. GeoNames files London's twenty
##     boroughs alongside London and Brussels' communes alongside Brussels, which
##     took those two regions to 1.325 and 1.285 of themselves.
##   - A NATION CANNOT BE MORE THAN FULLY PARTITIONED. The Eurostat response
##     carries two NUTS vintages at once -- NL35 and NL36 are the 2024 codes for
##     Utrecht and Zuid-Holland and NL31/NL33 the 2021 ones, equal to the person --
##     so an unfiltered Netherlands is 5.1 M people too large.
##   - EVERY NAMED CITY IS INSIDE ITS OWN REGION. A mistyped digit, a bad join or a
##     geometry vintage that has moved under the figures all fail here, and nothing
##     else in the project could see any of them. tests/test_map_markers.gd makes
##     the same claim about project sites one level up.
##
## And three about what V2.2a deliberately does NOT do, which is what a later
## session has to come and argue with:
##
##   - NOTHING IN src/sim/ READS THE REGISTER except the firm domicile. A region
##     carries no GDP, no unemployment and no sector mix until docs/tiers/v2.md
##     section 5, and the register ships no behaviour at all. V2.5 IS THAT SESSION,
##     and the check is inverted and narrowed rather than deleted, V2.2b's
##     treatment of the geometry assertion one file over: exactly ONE file under
##     src/sim/ may reach the register, and the marker is the register's own field
##     contract -- because the one reader takes it as DATA (a duck-typed Array,
##     Calendar.due()'s shape) and never preloads region.gd at all, so V2.2a's
##     preload scan was green all along and a narrower check needs a sharper
##     marker. A second reader is how a region acquires two writers, which is the
##     failure companies.gd's share/state_share/regulation_burden split exists to
##     prevent one level down.
##   - THE NUTS LEVEL IS NOWHERE IN src/. France is imported at NUTS 1 and Italy at
##     NUTS 2; the loader never learns a level exists, which is AGENTS.md's first
##     rule.
##   - data/geo/regions.geojson WAS NOT LOADED AT STARTUP at V2.2a -- nothing drew
##     it, so paying for 180 KB of geometry on every launch bought nothing. V2.2b
##     draws it, so the loader loads it and the absence check this file carried
##     turned red and was flipped, exactly as its own message said it would. This
##     test still parses the file DIRECTLY with its own ray cast, which is what
##     keeps the geometry honestly checked rather than trusted.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Region = preload("res://src/core/region.gd")
const City = preload("res://src/core/city.gd")
const Companies = preload("res://src/sim/companies.gd")

const NATIONS := ["FRA", "DEU", "ITA", "ESP", "BEL", "NLD", "LUX", "CHE", "GBR", "AUT", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "GRC", "HUN", "IRL", "LTU", "LVA", "MLT", "POL", "PRT", "ROU", "SVK", "SVN", "SWE"]

## tools/import_data.py's CITY_SNAP_DEG. A coastal commune falls outside the GISCO
## 10M coastline -- Birkenhead, Portsmouth, A Coruna, Cadiz, Antibes -- so the
## containment check allows exactly what the importer allowed and no more. Written
## here as a literal rather than read from the tool, because the tool does not ship.
const SNAP_DEG := 0.25

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_register_loads()
	_check_ids_are_unique_and_namespaced()
	_check_national_partition()
	_check_city_partition()
	_check_cities_lie_inside_their_region()
	_check_firms_are_domiciled()
	_check_headcount_reaches_a_city()
	_check_no_level_in_src()
	_check_register_has_no_simulation()
	_check_geometry_loads_at_startup()
	_check_region_graph()
	_check_fixtures_refused()
	_finish()


func _check_register_loads() -> void:
	for nation_id in NATIONS:
		if not _loader.regions.has(nation_id):
			_fail("no region register for '%s' -- an absent file is an error here, unlike companies and outlets" % nation_id)
			continue
		var list: Array = _loader.regions[nation_id]
		if list.is_empty():
			_fail("'%s' loaded zero regions" % nation_id)
		for region in list:
			if region.cities.is_empty():
				_fail("%s region '%s' names no city -- a region is a main city plus the smaller ones under it" % [nation_id, region.id])


func _check_ids_are_unique_and_namespaced() -> void:
	var region_ids := {}
	var city_ids := {}
	for nation_id in NATIONS:
		for region in _loader.regions.get(nation_id, []):
			if region_ids.has(region.id):
				_fail("region id '%s' is used by both %s and %s" % [region.id, region_ids[region.id], nation_id])
			region_ids[region.id] = nation_id
			for city in region.cities:
				if city_ids.has(city.id):
					_fail("city id '%s' is used twice" % city.id)
				city_ids[city.id] = nation_id
				if not city.id.begins_with(region.id + "_"):
					_fail("city '%s' is not namespaced by its region '%s'" % [city.id, region.id])


func _check_national_partition() -> void:
	for nation_id in NATIONS:
		var list: Array = _loader.regions.get(nation_id, [])
		var total := 0.0
		for region in list:
			total += region.share
		if total > 1.0:
			_fail("%s regions sum to %f of the nation" % [nation_id, total])
		var residual: float = Region.national_residual(list)
		if residual < 0.0:
			_fail("%s national residual is negative (%f)" % [nation_id, residual])


func _check_city_partition() -> void:
	for nation_id in NATIONS:
		for region in _loader.regions.get(nation_id, []):
			var total := 0.0
			for city in region.cities:
				total += city.share
			if total > 1.0:
				_fail("%s region '%s' names %f of itself" % [nation_id, region.id, total])
			if region.city_residual() < 0.0:
				_fail("%s region '%s' has a negative city residual" % [nation_id, region.id])


func _check_cities_lie_inside_their_region() -> void:
	var polygons := _region_polygons()
	if polygons.is_empty():
		_fail("data/geo/regions.geojson holds no features")
		return

	for nation_id in NATIONS:
		for region in _loader.regions.get(nation_id, []):
			if not polygons.has(region.id):
				_fail("region '%s' has a register entry and no geometry" % region.id)
				continue
			for city in region.cities:
				if _inside_any(city.lonlat, polygons[region.id]):
					continue
				var d: float = _distance_to(city.lonlat, polygons[region.id])
				if d > SNAP_DEG:
					_fail("city '%s' (%s) is %.3f deg outside region '%s'" % [
						city.id, city.city_name, d, region.id,
					])


func _check_firms_are_domiciled() -> void:
	for nation_id in _loader.companies.keys():
		var cities := {}
		for region in _loader.regions.get(nation_id, []):
			for city in region.cities:
				cities[city.id] = true
		for company in _loader.companies[nation_id]:
			if company.city == "":
				_fail("firm '%s' has no city" % company.id)
			elif not cities.has(company.city):
				_fail("firm '%s' is domiciled in '%s', which is not a city of %s" % [
					company.id, company.city, nation_id,
				])


## The domicile is load-bearing only through this function, so it is checked rather
## than assumed -- U6c's rule that a coordinate nothing reads carries no information.
func _check_headcount_reaches_a_city() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]

	var expected := 0.0
	for company in _loader.companies["FRA"]:
		if company.city == "FR1_paris":
			expected += company.headcount
	if expected <= 0.0:
		_fail("no French firm is domiciled in Paris -- this check is measuring nothing")
		return

	var live: float = Companies.headcount_in_city(ns, _loader, "FR1_paris")
	if absf(live - expected) > 0.5:
		_fail("headcount_in_city(FR1_paris) = %f, authored %f" % [live, expected])

	# A city no firm names is exactly zero, not a fallback and not an error: most of
	# the 1 065 cities in the register employ nobody the game has named.
	# V4.7a: the city is FOUND, not hardcoded -- Ajaccio carried the check until
	# the two-tier register generated a body firm into it, and a hardcoded city
	# would break again at every future content pass. The check walks the
	# register's own French cities for one no firm names; only if the register
	# ever fills EVERY French city does the premise itself need re-thinking,
	# and that day gets its own failure message rather than a silent pass.
	var empty_city := ""
	for region in _loader.regions.get("FRA", []):
		for city in region.cities:
			var taken := false
			for company in _loader.companies["FRA"]:
				if company.city == city.id:
					taken = true
					break
			if not taken:
				empty_city = city.id
				break
		if empty_city != "":
			break
	if empty_city == "":
		_fail("every French city carries a firm -- the zero-jobs path needs a new empty city to name")
	elif Companies.headcount_in_city(ns, _loader, empty_city) != 0.0:
		_fail("a city with no firm (%s) should report exactly zero jobs" % empty_city)


func _check_no_level_in_src() -> void:
	# Checked in the DATA rather than by grepping src/ for the word, which was the
	# first version of this check and failed on the comments explaining why the level
	# is absent. A level cannot reach src/ unless a file carries it, region.gd's
	# unrecognised-key error refuses one inside a region, and this covers the file's
	# own top level -- which nothing else does.
	var allowed := ["_source", "_year", "_note", "regions"]
	for nation_id in NATIONS:
		var text := FileAccess.get_file_as_string("res://data/regions/%s.json" % nation_id)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			_fail("data/regions/%s.json is not an object" % nation_id)
			continue
		for key in (parsed as Dictionary).keys():
			if not allowed.has(key):
				_fail("data/regions/%s.json carries '%s' -- the NUTS level is an import decision and no field in data/regions/ may state it" % [nation_id, key])
	for path in _gd_files("res://src"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("nuts_level") or text.contains("region_level"):
			_fail("%s reads a region level -- src/ must not learn one exists" % path)


## V2.2a asserted the ABSENCE of any sim reader and named section 5 as the session
## that would come and argue with it. This is that session, and the check is inverted
## rather than deleted -- V2.2b's treatment of the geometry-load assertion, one file
## over.
##
## WHAT V2.2a WAS PROTECTING SURVIVES, and it is the narrow half: exactly ONE file
## under src/sim/ may reach the register. A second reader is how a region acquires
## two writers, which is the failure companies.gd's share/state_share/regulation_burden
## split exists to prevent one level down. The marker is the field contract rather
## than a preload, because the one reader takes the register as data and preloads
## nothing -- V2.2a's scan was green on the day V2.5 landed and would have stayed
## green the day a SECOND reader arrived the same duck-typed way, which is the
## failure this check now exists to catch.
func _check_register_has_no_simulation() -> void:
	var readers: Array[String] = []
	for path in _gd_files("res://src/sim"):
		# V2.6b1: COMMENT LINES ARE STRIPPED BEFORE THE SCAN, and that is this check
		# repeating the correction its own sibling above already records making. The
		# level check's first version grepped src/ for a word and "failed on the
		# comments explaining why the level is absent"; this one grepped src/ for a
		# field name and failed on the comments explaining why Britain has no site --
		# src/sim/siting.gd and src/sim/unrest.gd each NAME `unemployment_rel` in a
		# docstring while neither touches it in code. Stripping comments makes this
		# STRICTER rather than looser: it measures what a file does rather than what
		# it says, and a real read still fires.
		var text := _code_only(FileAccess.get_file_as_string(path))
		# `.gdp_share` with the dot: a bare "gdp_share" would name companies.gd's
		# own subsidy-pricing local, which has carried the word since V1.4a and
		# reaches no region. `natural_change_pct` is V2.6c's addition to the same
		# contract: the rate reaches the flow through Regions.natural_change(), an
		# accessor named for the quantity rather than the field, so a file that
		# spells the field is a second reader by definition.
		if text.contains(".gdp_share") or text.contains("unemployment_rel") \
			or text.contains("sector_mix") or text.contains("region_gdp_eur_bn") \
			or text.contains("natural_change_pct"):
			readers.append(path)
	if readers != ["res://src/sim/regions.gd"]:
		_fail("the register is read by %s -- V2.5 gives exactly one system a region, and a second reader is a second writer waiting to happen" % [readers])

	# V2.5 did NOT give a city an economy, and city.gd's own doc says section 6 is
	# what comes here to change that.
	var regions_src := FileAccess.get_file_as_string("res://src/sim/regions.gd")
	for city_marker in ["city.gd", "city_share", "city_residual"]:
		if regions_src.contains(city_marker):
			_fail("src/sim/regions.gd reaches a city (%s) -- a city still holds a share of its region's population and nothing else" % city_marker)

	# V2.6a. migration.gd is the second file allowed to reach a city, and it is
	# allowed because it is the session that gives a city something that moves.
	# The one-reader assertion above is UNCHANGED and stays green: migration.gd
	# names no register field at all -- every regional quantity it reads comes back
	# through a Regions function -- so the marker list did not have to grow.
	var migration_src := FileAccess.get_file_as_string("res://src/sim/migration.gd")
	for marker in [".gdp_share", "unemployment_rel", "sector_mix", "region_gdp_eur_bn", "natural_change_pct"]:
		if migration_src.contains(marker):
			_fail("src/sim/migration.gd names `%s` -- it reads the register through Regions' own functions, and naming a field here makes it a second reader" % marker)

	# regions.gd is a LEAF: economy_constants and its own constants, nothing else.
	for forbidden in ["src/sim/economy.gd", "src/sim/trade.gd", "src/sim/demography.gd", "src/core/data_loader.gd"]:
		if regions_src.contains("preload(\"res://%s\")" % forbidden):
			_fail("src/sim/regions.gd preloads %s -- it is a leaf, and the caller holds the loader" % forbidden)

	var region_src := FileAccess.get_file_as_string("res://src/core/region.gd")
	if region_src.contains("preload(\"res://src/sim/"):
		_fail("region.gd reaches into src/sim/ -- that inverts data -> sim -> ui")


## V2.2a asserted the ABSENCE of this load ("nothing draws it until V2.2b, so a
## launch should not pay for it") and that check is the one this session came here
## to flip: the map draws the regions now, so the loader loads them. What the flip
## must not lose is the second half of the old claim -- that the geometry is read
## honestly. The containment check above still parses the file with its own ray
## cast, so the loader's copy is cross-checked against an independent one rather
## than against itself.
func _check_geometry_loads_at_startup() -> void:
	var expected := 0
	var register_ids := {}
	for nation_id in NATIONS:
		for region in _loader.regions.get(nation_id, []):
			register_ids[region.id] = true
			expected += 1

	if _loader.region_features.is_empty():
		_fail("region_features is empty -- data/geo/regions.geojson did not load")
		return
	for id in register_ids.keys():
		if not _loader.region_features.has(id):
			_fail("region '%s' is in the register but not in the loader's geometry" % id)
	var loaded: int = _loader.region_features.size()
	if loaded != expected:
		_fail("region_features holds %d polygons against %d register regions -- the geometry is the authority on the roster, so the two sets must be equal" % [loaded, expected])


## V2.7. The graph loads, it is connected, and its ids are the register's own.
##
## V2.2a pinned the geojson's ABSENCE from the loader ("nothing draws it, so a
## launch should not pay for it") and V2.2b flipped that pin to a presence check
## the day the map drew it. This is the same shape one register over: the graph is
## loaded because src/sim/network.gd reads it every tick, and a graph whose ids have
## drifted from the register is an import that has come apart -- which is exactly
## what _validate_regions()'s fifth rule catches for the graph.
func _check_region_graph() -> void:
	var graph: Dictionary = _loader.region_graph
	if graph.is_empty():
		_fail("loader.region_graph is empty -- data/geo/region_graph.json did not load")
		return
	var edges: Array = graph.get("edges", [])
	var endowment: Dictionary = graph.get("endowment", {})
	if edges.is_empty() or endowment.is_empty():
		_fail("region_graph carries %d edges and %d endowments" % [edges.size(), endowment.size()])
		return

	var register_ids: Dictionary = {}
	for nation_id in _loader.regions.keys():
		for region in _loader.regions[nation_id]:
			register_ids[region.id] = true
	if endowment.size() != register_ids.size():
		_fail("region_graph endowment has %d entries against %d register regions" % [
			endowment.size(), register_ids.size(),
		])
	for region_id in endowment.keys():
		if not register_ids.has(region_id):
			_fail("region_graph names '%s', which the register does not carry" % region_id)

	# CONNECTED, and the assertion is the whole reason the eight sea links exist.
	# Adjacency alone leaves nine components; a graph that has quietly lost a link
	# leaves Corsica unreachable and every accessibility read there collapses to its
	# own output, which is a silent wrong answer rather than a crash.
	var adjacency: Dictionary = {}
	for region_id in endowment.keys():
		adjacency[region_id] = []
	for edge in edges:
		(adjacency[edge[0]] as Array).append(edge[1])
		(adjacency[edge[1]] as Array).append(edge[0])
	var start: String = String(endowment.keys()[0])
	var seen: Dictionary = {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var current: String = String(stack.pop_back())
		for other in adjacency[current]:
			if not seen.has(other):
				seen[other] = true
				stack.append(other)
	if seen.size() != endowment.size():
		_fail("region_graph reaches %d of %d regions -- a link is missing" % [seen.size(), endowment.size()])


func _check_fixtures_refused() -> void:
	_expect_fixture_error("res://tests/fixtures/regions_share_sum",
		"above 1.0", "regions summing past the nation")
	_expect_fixture_error("res://tests/fixtures/regions_city_overflow",
		"more than fully named", "cities summing past their region")
	_expect_fixture_error("res://tests/fixtures/regions_bad_domicile",
		"is not a city in data/regions/", "a firm domiciled nowhere")
	_expect_fixture_error("res://tests/fixtures/regions_orphan_file",
		"the file is never opened", "a regions file for a nation that does not exist")


func _expect_fixture_error(regions_dir: String, needle: String, what: String) -> void:
	var fixture := DataLoader.new()
	fixture.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://data/laws",
		"res://data/political-systems", "res://data/scenarios",
		"res://data/diplomatic-actions", "res://data/geo/world.geojson",
		"res://data/bloc-proposals", "res://data/people", "res://data/companies",
		"res://data/company-actions", "res://data/outlets",
		"res://data/investment-actions", "res://data/project-actions",
		"res://data/campaign-actions", "res://data/pledges", "res://data/events",
		regions_dir
	)
	for e in fixture.errors:
		if e.contains(needle):
			return
	_fail("%s loaded without the expected error (%s): %s" % [what, needle, fixture.errors])


# --- geometry helpers ----------------------------------------------------------
#
# Parsed here rather than through the loader, deliberately: see the header. A
# duplicate of the importer's ray cast, and that duplication is the point -- a
# containment check written against the same code that placed the point would
# always pass.

func _region_polygons() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/geo/regions.geojson")
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var out := {}
	for feature in parsed.get("features", []):
		var id: String = feature["properties"]["id"]
		out[id] = feature["geometry"]["coordinates"]
	return out


func _inside_any(point: Vector2, polygons: Array) -> bool:
	for polygon in polygons:
		if not _in_ring(point, polygon[0]):
			continue
		var in_hole := false
		for i in range(1, polygon.size()):
			if _in_ring(point, polygon[i]):
				in_hole = true
				break
		if not in_hole:
			return true
	return false


func _in_ring(point: Vector2, ring: Array) -> bool:
	var inside := false
	var n: int = ring.size()
	var j: int = n - 1
	for i in n:
		var xi: float = ring[i][0]
		var yi: float = ring[i][1]
		var xj: float = ring[j][0]
		var yj: float = ring[j][1]
		if (yi > point.y) != (yj > point.y) \
				and point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi:
			inside = not inside
		j = i
	return inside


func _distance_to(point: Vector2, polygons: Array) -> float:
	var best := INF
	for polygon in polygons:
		for ring in polygon:
			for pt in ring:
				var d: float = point.distance_to(Vector2(pt[0], pt[1]))
				if d < best:
					best = d
	return best


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)
		if da.current_is_dir():
			out.append_array(_gd_files(path))
		elif entry.ends_with(".gd"):
			out.append(path)
		entry = da.get_next()
	da.list_dir_end()
	return out


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_geography: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("  FAIL: %s" % f)
	printerr("test_geography: %d failure(s)" % _failures.size())
	quit(1)


## Source with whole-line comments removed, so a check about what a file READS is not
## answered by what a file SAYS. Whole lines only: an inline `#` after code cannot be
## cut safely without parsing strings, and every marker this file scans for has only
## ever appeared in doc comments.
func _code_only(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("
"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "
".join(out)
