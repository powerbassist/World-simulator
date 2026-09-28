extends SceneTree

## Natural change probe: godot --headless --script res://tools/natural_change_probe.gd
##
## V2.6c's evidence generator for the flow itself: what the measured rates say, how
## much movement the natural flow owns against migration's at the shipped rate, and
## where the two flows disagree. Not a test: tests/test_natural_change.gd asserts the
## invariants. Excluded from run_tests.sh, so run it before trusting it (V1.3e).
##
## THE MIRROR CARRIES THE COMBINED MODEL at a candidate migration rate, the same
## emulation tools/migration_probe.gd's table (e) drives and the same caveat: it is
## checked against Migration.tick_month() there, and this file trusts that check
## rather than repeating it. The rate-0.0 row of table (b) below IS clause (0).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Regions = preload("res://src/sim/regions.gd")
const Projects = preload("res://src/sim/projects.gd")
const Migration = preload("res://src/sim/migration.gd")
const MigrationK = preload("res://src/sim/migration_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Companies = preload("res://src/sim/companies.gd")
const NaturalChange = preload("res://src/sim/natural_change.gd")

const NATIONS := ["AUT", "BEL", "CHE", "DEU", "ESP", "FRA", "GBR", "ITA", "LUX", "NLD"]
const MONTHS := 168

## The ruler, tools/region_drift.py's measurement -- the same number clause (ii)
## reads, restated here because the natural flow is judged against it alone.
const DRIFT_CEILING := 0.0164


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("data did not load: %s" % [loader.errors])
		quit(1)
		return

	_table_a(loader)
	_table_b(loader)
	_table_c(loader)
	quit(0)


## (a) WHAT THE CONTENT SAYS: the measured rates themselves, weighted by the
## authored shares because that is the mean the flow anchors on at month 0. The
## spread is the flow's whole fuel -- a nation whose regions all carry the same rate
## has a dead natural flow (Britain by bound, Luxembourg by arithmetic), and the
## spread column is where that is visible rather than assumed.
func _table_a(loader) -> void:
	print("\n=== (a) the measured rates: demo_r_gind3 NATGROWRT, window-averaged ===")
	print("  nation  high                       low                        spread   share-wtd mean")
	for nation_id in NATIONS:
		var list: Array = loader.regions.get(nation_id, [])
		if list.is_empty():
			continue
		var rows: Array = []
		var wsum := 0.0
		var wmean := 0.0
		for region in list:
			rows.append([region.natural_change_pct, region.region_name, region.share])
			wmean += region.share * region.natural_change_pct
			wsum += region.share
		rows.sort_custom(func(a, b): return a[0] < b[0])
		var mean: float = wmean / wsum if wsum > 0.0 else 0.0
		print("  %s     %-26s %+.3f   %-26s %+.3f   %+.3f   %+.3f" % [
			nation_id,
			rows[rows.size() - 1][1], rows[rows.size() - 1][0],
			rows[0][1], rows[0][0],
			rows[rows.size() - 1][0] - rows[0][0],
			mean,
		])


## (b) ATTRIBUTION AT THE SHIPPED RATE: how much of the register's movement is
## births and deaths, how much is the pull. Three runs per nation --
##   natural-only:  the combined model at migration rate 0.0 (clause (0)'s row);
##   migration-only: the shipped tick with the natural rates zeroed on the content;
##   combined:      the shipped tick untouched.
## The three are measured on the same quantity Migration.worst_share_drift() returns,
## and the ceiling verdict is read on the COMBINED column -- the clause the band
## swept against.
func _table_b(loader) -> void:
	print("\n=== (b) attribution at MIGRATION_RATE %.4f, worst drift @%d months ===" % [
		MigrationK.MIGRATION_RATE, MONTHS])
	print("  nation  natural-only   migration-only   combined   ceiling %.4f" % DRIFT_CEILING)
	for nation_id in NATIONS:
		var list: Array = loader.regions.get(nation_id, [])
		if list.is_empty():
			continue

		var saved: Dictionary = {}
		for region in list:
			saved[region.id] = region.natural_change_pct
			region.natural_change_pct = 0.0
		var migration_only: float = _run_shipped(loader, nation_id)["drift"]
		for region in list:
			region.natural_change_pct = float(saved[region.id])

		var natural_only: float = _run_mirror(loader, nation_id, 0.0)["drift"]
		var combined: float = _run_shipped(loader, nation_id)["drift"]
		print("  %s     %.4f         %.4f           %.4f     %s" % [
			nation_id, natural_only, migration_only, combined,
			"PASS" if combined <= DRIFT_CEILING else "FAIL",
		])


## (c) WHERE THE FLOWS DISAGREE, which is the finding the re-sweep rests on. For
## each nation the region with the most positive natural differential against the
## live mean and the one with the most negative, beside each one's EXPECTED-INCOME
## rank. When the same region tops both rankings the flows compound (FRA:
## Ile-de-France is the richest and the most natal, so the ceiling holds the sum);
## when they invert -- DEU and ITA, where the deaths are in the poor east and south
## and the differential therefore runs AGAINST the pull -- natural change is the
## only term in the model that moves people toward the region the pull rejects.
func _table_c(loader) -> void:
	print("\n=== (c) the differential against the pull, at new game ===")
	print("  nation  most natal region (rate-mean)   pull rank  | least natal region              pull rank")
	for nation_id in NATIONS:
		var list: Array = loader.regions.get(nation_id, [])
		if list.size() < 2:
			continue
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var shares: Dictionary = {}
		var rates: Dictionary = {}
		var pulls: Dictionary = {}
		var access: Dictionary = Regions.accessibility_for(ns, list, state.region_graph)
		var sites: Dictionary = state.project_sited_pct.get(nation_id, {})
		for region in list:
			shares[region.id] = Migration.region_share(ns, region.id)
			rates[region.id] = Regions.natural_change(region)
			pulls[region.id] = Migration.region_pull(ns, list, region.id, access, sites)
		var mean: float = NaturalChange.named_mean(shares, rates)
		var ranked_pulls: Array = pulls.keys()
		ranked_pulls.sort_custom(func(a, b): return float(pulls[a]) > float(pulls[b]))
		var rank_of := {}
		for i in ranked_pulls.size():
			rank_of[ranked_pulls[i]] = i + 1

		var top_id := ""
		var bot_id := ""
		var top_gap := -INF
		var bot_gap := INF
		for id in rates.keys():
			var gap: float = float(rates[id]) - mean
			if gap > top_gap:
				top_gap = gap
				top_id = id
			if gap < bot_gap:
				bot_gap = gap
				bot_id = id
		var top_name := _region_name(list, top_id)
		var bot_name := _region_name(list, bot_id)
		print("  %s     %-22s %+.3f       %2d of %2d  | %-26s %+.3f    %2d of %2d" % [
			nation_id, top_name, top_gap * 100.0, rank_of[top_id], list.size(),
			bot_name, bot_gap * 100.0, rank_of[bot_id], list.size(),
		])


func _region_name(list: Array, id: String) -> String:
	for region in list:
		if region.id == id:
			return region.region_name
	return id


## The shipped tick, unchanged. Content may have been zeroed by the caller (table
## b's migration-only column) -- that is the caller's business, this just runs.
func _run_shipped(loader, nation_id: String) -> Dictionary:
	var state = GameState.new_game(loader, nation_id)
	var ns = state.nations[nation_id]
	var list: Array = loader.regions.get(nation_id, [])
	for i in MONTHS:
		Economy.tick_month(state)
		Companies.tick_month(state, loader)
		Migration.tick_month(state, loader)
	return {"drift": Migration.worst_share_drift(ns, list)}


## The combined model at a candidate migration rate -- tools/migration_probe.gd's
## emulation, carried here because this probe's whole point is candidates the
## shipped constant is not at. Trusts table (e2) there for the equality check.
func _run_mirror(loader, nation_id: String, rate: float) -> Dictionary:
	var state = GameState.new_game(loader, nation_id)
	var ns = state.nations[nation_id]
	var list: Array = loader.regions.get(nation_id, [])
	for i in MONTHS:
		Economy.tick_month(state)
		Companies.tick_month(state, loader)
		_tick_combined(ns, list, loader, rate)
	return {"drift": Migration.worst_share_drift(ns, list)}


func _tick_combined(ns, list: Array, loader, rate: float) -> void:
	if list.is_empty():
		return
	var access: Dictionary = Regions.accessibility_for(ns, list, loader.region_graph)
	var sites: Dictionary = Projects.sited_pct(ns, loader)
	for region in list:
		if region.cities.size() < 2:
			continue
		var city_pulls: Dictionary = {}
		var city_shares: Dictionary = {}
		var city_weighted: float = 0.0
		var city_total: float = 0.0
		for city in region.cities:
			var pull: float = Migration.city_pull(ns, region, city.id, Migration._jobs_by_city(ns, loader))
			var share: float = Migration.city_share(ns, city.id)
			city_pulls[city.id] = pull
			city_shares[city.id] = share
			city_weighted += share * pull
			city_total += share
		if city_total <= 0.0:
			continue
		var city_mean: float = city_weighted / city_total
		for city in region.cities:
			var share: float = float(city_shares[city.id])
			ns.city_pop_share[city.id] = share + Migration.share_delta(share, float(city_pulls[city.id]), city_mean, rate)

	var pulls: Dictionary = {}
	var shares: Dictionary = {}
	var weighted: float = 0.0
	var total: float = 0.0
	for region in list:
		var pull: float = Migration.region_pull(ns, list, region.id, access, sites)
		var share: float = Migration.region_share(ns, region.id)
		pulls[region.id] = pull
		shares[region.id] = share
		weighted += share * pull
		total += share
	if total > 0.0:
		var mean: float = weighted / total
		for region in list:
			var share: float = float(shares[region.id])
			ns.region_pop_share[region.id] = share + Migration.share_delta(share, float(pulls[region.id]), mean, rate)

	var rates: Dictionary = {}
	var nat_shares: Dictionary = {}
	for region in list:
		rates[region.id] = Regions.natural_change(region)
		nat_shares[region.id] = Migration.region_share(ns, region.id)
	var nat_deltas: Dictionary = NaturalChange.deltas(nat_shares, rates)
	for region in list:
		ns.region_pop_share[region.id] += float(nat_deltas.get(region.id, 0.0))
