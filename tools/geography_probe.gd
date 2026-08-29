extends SceneTree

## V2.2a. Run: godot --headless --script res://tools/geography_probe.gd
##
## The register, measured. Model: docs/geography-model.md.
##
## THIS PROBE RUNS NO MONTHS AT ALL, and that is worth saying rather than leaving to
## be noticed. Every probe on this project since V1.3f has had to be checked against
## the state it measures -- tools/nav_probe.gd's fourteen-year loop stops at month 136
## because a president who never touches anything loses office there, and V1.3f,
## V1.5c, V1.7b and V1.7c each measured the wrong state at least once. A register that
## no tick writes has no wrong state to measure: this is a read over loader content
## and a single new game, so there is nothing here for a clock to invalidate.
##
## What it prints is the four tables docs/geography-model.md carries, plus the one
## finding neither the tier row nor the plan anticipated -- where the jobs are.
##
## The population cut itself is swept OUTSIDE this file, against
## tools/import_data.py's own select_cities(), because the candidate cities do not
## survive the import: a threshold sweep over the shipped register could only ever
## measure the threshold that produced it. That is V1.6b's finding -- a probe whose
## table is not independent of the constant it chooses -- and the sweep is recorded in
## the model doc and in the constant's own comment rather than re-run here.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Region = preload("res://src/core/region.gd")
const Companies = preload("res://src/sim/companies.gd")

const NATIONS := ["FRA", "DEU", "ITA", "ESP", "BEL", "NLD", "LUX", "CHE", "GBR", "AUT"]


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [loader.errors])
		quit(1)
		return

	_table_a(loader)
	_table_b(loader)
	_table_c(loader)
	_table_d(loader)
	quit(0)


## (a) THE PARTITION. What each nation is cut into, and how much of it nobody names.
## The residual is extra-regio output plus the overseas regions the map's bounding box
## has dropped since S8, so it is non-zero for exactly two nations and that is a fact
## about France and Spain rather than about the import.
func _table_a(loader) -> void:
	print("")
	print("(a) the national partition")
	print("nat  regions  smallest  largest   residual")
	var total := 0
	for nation_id in NATIONS:
		var list: Array = loader.regions[nation_id]
		total += list.size()
		var smallest := 1.0
		var largest := 0.0
		for region in list:
			smallest = minf(smallest, region.share)
			largest = maxf(largest, region.share)
		print("%s  %7d  %8.4f  %7.4f  %9.6f" % [
			nation_id, list.size(), smallest, largest, Region.national_residual(list),
		])
	print("     %7d regions" % total)


## (b) THE CITY PARTITION, and the structural bound this session records rather than
## tunes against. Coverage is the share of a nation's population living in a city the
## register names, and it spans a factor of four across the roster for reasons no
## constant can reach: Luxembourg has ONE city and it is 11.9 % of the country, and
## Swiss communes are administratively small. Both sit under any floor a sweep could
## write, at every candidate cut, which is why the worst-nation clause was deleted --
## see CITY_MIN_POP in tools/import_data.py.
func _table_b(loader) -> void:
	print("")
	print("(b) the city partition")
	print("nat   cities  coverage  fullest region       thinnest region")
	var total := 0
	var sum_cov := 0.0
	for nation_id in NATIONS:
		var list: Array = loader.regions[nation_id]
		var count := 0
		var coverage := 0.0
		var fullest := 0.0
		var fullest_id := ""
		var thinnest := 1.0
		var thinnest_id := ""
		for region in list:
			count += region.cities.size()
			var named: float = 1.0 - region.city_residual()
			coverage += region.share * named
			if named > fullest:
				fullest = named
				fullest_id = region.id
			if named < thinnest:
				thinnest = named
				thinnest_id = region.id
		total += count
		sum_cov += coverage
		print("%s  %7d  %8.4f  %-6s %7.4f      %-6s %7.4f" % [
			nation_id, count, coverage, fullest_id, fullest, thinnest_id, thinnest,
		])
	print("      %7d cities, roster mean coverage %.4f" % [total, sum_cov / NATIONS.size()])


## (c) WHERE THE JOBS ARE, and this is the table the row did not ask for. A firm's
## domicile is the only thing making Company.city load-bearing before V2.2b draws it,
## and what it says is that the eighteen firms this game names are concentrated in a
## way nothing authored: a single city can hold most of a nation's named payroll,
## which is what makes docs/tiers/v2.md section 6's migration a decision rather than a
## diffusion.
func _table_c(loader) -> void:
	print("")
	print("(c) named jobs by city")
	for nation_id in ["FRA", "DEU", "GBR"]:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var payroll := 0.0
		var by_city := {}
		for company in loader.companies[nation_id]:
			payroll += company.headcount
			by_city[company.city] = by_city.get(company.city, 0.0) + company.headcount
		var ids: Array = by_city.keys()
		ids.sort_custom(func(a, b): return by_city[a] > by_city[b])
		for city_id in ids:
			var city = Region.find_city(loader.regions[nation_id], city_id)
			var region = Region.region_of_city(loader.regions[nation_id], city_id)
			print("%s  %-22s %-24s %8.0f jobs  %5.1f %% of named payroll  city is %5.2f %% of %s" % [
				nation_id,
				city.city_name if city != null else "?",
				city_id,
				Companies.headcount_in_city(ns, loader, city_id),
				100.0 * by_city[city_id] / payroll,
				100.0 * (city.share if city != null else 0.0),
				region.region_name if region != null else "?",
			])


## (d) THE SPINE V2.5 INHERITS. The largest region of each nation as a share of it,
## which is the number that decides whether a regional economy is a partition worth
## having or one region and a rounding error. Vlaams Gewest is 57.8 % of Belgium
## against Brussels' 10.6 %, the widest single region on the roster and a fact about
## Belgium rather than about the cut -- and the other end is Italy, whose largest
## region is 16.8 % of it.
func _table_d(loader) -> void:
	print("")
	print("(d) the largest region of each nation")
	for nation_id in NATIONS:
		var largest = null
		for region in loader.regions[nation_id]:
			if largest == null or region.share > largest.share:
				largest = region
		var top = largest.cities[0] if not largest.cities.is_empty() else null
		print("%s  %-6s %-30s %6.4f of the nation   largest city %s (%.4f of the region)" % [
			nation_id, largest.id, largest.region_name, largest.share,
			top.city_name if top != null else "-", top.share if top != null else 0.0,
		])
