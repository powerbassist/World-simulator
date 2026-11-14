extends SceneTree

## Headless test: godot --headless --script res://tests/test_screen_reads.gd
## Non-zero exit on any failure.
##
## V5.3 e PR B (docs/design/finance-bill.md section 13, the parent's go 2026-11-14):
## the reads screens 5 and 6 draw from, over what the sim already computes.
##   - the world price ring (`GameState.commodity_price_history`, 12 months, one copy)
##     and `GoodsRead.table()`: the price now, the series held, this month's trade in
##     units and in EUR bn a year;
##   - `ns.region_history`: each named region's unemployment, output per head and net
##     migration, 12 months, written at the Migration step from the reads that step
##     already takes;
##   - the fund strip's loss to the other regions (`RegionFunds.estimate()`'s new keys);
##   - the unrest site with its price and the region's net migration.
## Both series start EMPTY in a new game and say how many months they hold: nothing
## is invented before the first month. Nothing here is read back by the sim.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const GoodsRead = preload("res://src/sim/goods_read.gd")
const RegionRead = preload("res://src/sim/region_read.gd")
const RegionSample = preload("res://src/sim/region_sample.gd")
const Series = preload("res://src/sim/series.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")
const MK = preload("res://src/sim/migration_constants.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const MapLayers = preload("res://src/ui/map_layers.gd")

const EPS := 1e-9

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_series_push_keeps_twelve()
	_test_a_new_game_holds_nothing()
	_test_one_month_then_fourteen()
	_test_the_goods_table()
	_test_the_map_layer_reads_the_sim()
	_test_the_region_sample_is_the_migration_step()
	_test_the_sample_counts_persons()
	_test_the_save_carries_both_and_absence_is_empty()
	_test_the_fund_strip_names_the_others_loss()
	_test_the_unrest_read()
	_finish()


func _state(nation := "FRA"):
	return GameState.new_game(_loader, nation)


func _named(state, ns) -> Array:
	return state.regions.get(ns.id, [])


# --- the ring -----------------------------------------------------------------

func _test_series_push_keeps_twelve() -> void:
	var s: Array = []
	for i in 15:
		Series.push(s, float(i))
	if s.size() != Series.MONTHS:
		_fail("Series.push kept %d entries, not %d" % [s.size(), Series.MONTHS])
	elif float(s[0]) != 3.0 or float(s[-1]) != 14.0:
		_fail("Series.push did not drop the oldest first: %s" % [s])


func _test_a_new_game_holds_nothing() -> void:
	var state = _state()
	var ns = state.player()
	if not state.commodity_price_history.is_empty() or GoodsRead.months_held(state) != 0:
		_fail("a new game already holds a price series (%d months)" % GoodsRead.months_held(state))
	if not ns.region_history.is_empty() or RegionRead.months_held(ns) != 0:
		_fail("a new game already holds a region sample (%d months)" % RegionRead.months_held(ns))
	for row in GoodsRead.table(state, ns):
		if not (row["series"] as Array).is_empty() or int(row["months"]) != 0:
			_fail("a new game's goods table shows a series for %s" % row["good_id"])
			break


func _test_one_month_then_fourteen() -> void:
	var state = _state()
	var seen: Array = []  # the price vector after each month's Commodities step
	var hook := func(step: String, after: bool, _report: Dictionary) -> void:
		if step == "Commodities" and after:
			seen.append((state.player().commodity_state["price"] as Dictionary).duplicate())
	WorldMonth.tick_month(state, _loader, hook)
	if GoodsRead.months_held(state) != 1:
		_fail("after one month the price ring holds %d months" % GoodsRead.months_held(state))
	var ns = state.player()
	if RegionRead.months_held(ns) != 1:
		_fail("after one month the region sample holds %d months" % RegionRead.months_held(ns))
	for good_id in (ns.commodity_state["price"] as Dictionary).keys():
		var series: Array = state.commodity_price_history.get(good_id, [])
		if series.size() != 1 or float(series[0]) != float(seen[0][good_id]):
			_fail("month 1: %s's ring is %s, the step wrote %s" % [good_id, series, seen[0][good_id]])
			break
	for i in 13:
		WorldMonth.tick_month(state, _loader, hook)
	if GoodsRead.months_held(state) != Series.MONTHS:
		_fail("after fourteen months the ring holds %d, not %d" % [GoodsRead.months_held(state), Series.MONTHS])
	if RegionRead.months_held(ns) != Series.MONTHS:
		_fail("after fourteen months the region sample holds %d, not %d" % [RegionRead.months_held(ns), Series.MONTHS])
	# The ring is the LAST twelve months, oldest first, and holds values, not twelve
	# references to the one dictionary Commodities updates in place.
	var moved := false
	for good_id in (ns.commodity_state["price"] as Dictionary).keys():
		var series: Array = state.commodity_price_history[good_id]
		for k in Series.MONTHS:
			if float(series[k]) != float(seen[2 + k][good_id]):
				_fail("%s month %d: the ring holds %s, the step wrote %s" % [good_id, k, series[k], seen[2 + k][good_id]])
				return
		if float(series[0]) != float(series[-1]):
			moved = true
	if not moved:
		_fail("premise: no price moved in fourteen months, so the ring's order is untested")
	for region in _named(state, ns):
		var row: Dictionary = ns.region_history.get(region.id, {})
		for key in RegionRead.KEYS:
			if (row.get(key, []) as Array).size() != Series.MONTHS:
				_fail("%s.%s holds %d months" % [region.id, key, (row.get(key, []) as Array).size()])
				return


# --- the goods table ----------------------------------------------------------

func _test_the_goods_table() -> void:
	var state = _state()
	WorldMonth.tick_month(state, _loader)
	WorldMonth.tick_month(state, _loader)
	var ns = state.player()
	var cs: Dictionary = ns.commodity_state
	var rows: Array = GoodsRead.table(state, ns)
	if rows.size() != (cs["price"] as Dictionary).size():
		_fail("the goods table has %d rows for %d goods" % [rows.size(), (cs["price"] as Dictionary).size()])
		return
	var last := ""
	var traded := false
	for row in rows:
		var g := String(row["good_id"])
		if g <= last:
			_fail("the goods table is not sorted by good: %s after %s" % [g, last])
		last = g
		var price := float(cs["price"][g])
		var units := float(cs["trade"].get(g, 0.0))
		if float(row["price"]) != price:
			_fail("%s: the table's price %s is not the register's %s" % [g, row["price"], price])
		if float(row["trade_units"]) != units:
			_fail("%s: the table's trade %s is not the register's %s" % [g, row["trade_units"], units])
		# The register is a month in units, bought positive: a year's balance in EUR
		# bn is the month times twelve, sold positive.
		if absf(float(row["trade_eur_bn_year"]) - (-units * price * 12.0 / 1e9)) > EPS:
			_fail("%s: the table's EUR bn a year is %s" % [g, row["trade_eur_bn_year"]])
		if units != 0.0:
			traded = true
		if int(row["months"]) != 2 or (row["series"] as Array).size() != 2:
			_fail("%s: two months ticked, the row says %d" % [g, int(row["months"])])
	if not traded:
		_fail("premise: France trades nothing, so the EUR conversion is untested")
	# The series is the reader's copy: writing it does not write the ring.
	var row0: Dictionary = rows[0]
	(row0["series"] as Array)[0] = -1.0
	if float(state.commodity_price_history[row0["good_id"]][0]) == -1.0:
		_fail("GoodsRead.table() hands out the ring itself, not a copy")


func _test_the_map_layer_reads_the_sim() -> void:
	var state = _state()
	WorldMonth.tick_month(state, _loader)
	var any := false
	for id in state.nations.keys():
		var a := MapLayers.import_dependency(state, id)
		if a != GoodsRead.import_dependency(state, id):
			_fail("%s: the map layer's import dependency %s is not the sim reader's" % [id, a])
			return
		if a > 0.0:
			any = true
	if not any:
		_fail("premise: no nation imports anything, so the delegation is untested")


# --- the region sample --------------------------------------------------------

func _test_the_region_sample_is_the_migration_step() -> void:
	if MK.MIGRATION_RATE == 0.0:
		_fail("premise: MIGRATION_RATE is 0.0, so the Migration step writes no sample")
		return
	var state = _state()
	var ns = state.player()
	var list: Array = _named(state, ns)
	var before := {}
	var shares := {}
	var hook := func(step: String, after: bool, _report: Dictionary) -> void:
		if step != "Migration":
			return
		if not after:
			var access := Regions.accessibility_for(ns, list, state.region_graph)
			# merge, not assign: a lambda captures `before` by value.
			before.merge(Regions.unemployment_by_region(ns, list, access, state.project_sited_pct.get(ns.id, {})))
			for region in list:
				shares[region.id] = Migration.region_share(ns, region.id)
	WorldMonth.tick_month(state, _loader, hook)
	var flow := 0.0
	var gross := 0.0
	for region in list:
		var row: Dictionary = ns.region_history[region.id]
		var u := float(row["unemployment"][0])
		if u != float(before[region.id]):
			_fail("%s: the sample's unemployment %s is not the step's %s" % [region.id, u, before[region.id]])
		var g := float(row["gdp_per_head"][0])
		var want := Regions.gdp_per_head_index(ns, list, region.id, float(shares[region.id]))
		if g != want:
			_fail("%s: the sample's output per head %s is not %s" % [region.id, g, want])
		var m := float(row["migration"][0])
		flow += m
		gross += absf(m)
	# Migration moves people between regions and natural change is not in it, so the
	# month's flows telescope to zero in persons.
	if gross <= 0.0:
		_fail("premise: nobody moved in France's first month")
	elif absf(flow) > 1e-6 * gross:
		_fail("the region flows do not sum to zero: %s of %s" % [flow, gross])


## The migration series is persons: the share moved times the nation's population.
func _test_the_sample_counts_persons() -> void:
	var state = _state()
	var ns = state.player()
	var list: Array = _named(state, ns)
	var u := {}
	var s := {}
	for region in list:
		u[region.id] = 7.0
		s[region.id] = Migration.region_share(ns, region.id)
	var first: String = list[0].id
	RegionSample.record(ns, list, u, s, {first: 0.001})
	var want := 0.001 * float(ns.population)
	if float(ns.region_history[first]["migration"][0]) != want:
		_fail("the sample stores %s for a share of 0.001, not %s persons" % [ns.region_history[first]["migration"][0], want])
	if float(ns.region_history[list[1].id]["migration"][0]) != 0.0:
		_fail("a region with no delta did not read 0 persons")


# --- the save -----------------------------------------------------------------

func _test_the_save_carries_both_and_absence_is_empty() -> void:
	var state = _state()
	WorldMonth.tick_month(state, _loader)
	WorldMonth.tick_month(state, _loader)
	var ns = state.player()
	var full: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var loaded = GameState.from_dict(full)
	if var_to_str(loaded.commodity_price_history) != var_to_str(JSON.parse_string(JSON.stringify(state.commodity_price_history))):
		_fail("the price ring did not survive the save")
	if GoodsRead.months_held(loaded) != 2:
		_fail("a loaded ring holds %d months" % GoodsRead.months_held(loaded))
	if RegionRead.months_held(loaded.player()) != 2:
		_fail("a loaded region sample holds %d months" % RegionRead.months_held(loaded.player()))
	# Not shared with the payload it came from (to_dict hands out the live field).
	var direct = GameState.from_dict(state.to_dict())
	var good: String = state.commodity_price_history.keys()[0]
	direct.commodity_price_history[good][0] = -3.0
	if float(state.commodity_price_history[good][0]) == -3.0:
		_fail("from_dict() shares the price ring with the state it was saved from")
	var region_id: String = ns.region_history.keys()[0]
	direct.player().region_history[region_id]["migration"][0] = -4.0
	if float(ns.region_history[region_id]["migration"][0]) == -4.0:
		_fail("from_dict() shares the region sample with the state it was saved from")
	# Absent: nothing held yet, which is the truth about every earlier save.
	full.erase("commodity_price_history")
	(full["nations"]["FRA"] as Dictionary).erase("region_history")
	var old = GameState.from_dict(full)
	if not old.commodity_price_history.is_empty() or GoodsRead.months_held(old) != 0:
		_fail("an absent price ring did not read as empty")
	if not old.player().region_history.is_empty() or RegionRead.months_held(old.player()) != 0:
		_fail("an absent region sample did not read as empty")
	# The budget projection's copy has no past: neither the ring nor the sample is copied,
	# and the live state keeps both.
	var copy = state.duplicate_state()
	if not copy.commodity_price_history.is_empty():
		_fail("duplicate_state() carries the price ring into a projection")
	if not copy.player().region_history.is_empty():
		_fail("duplicate_state() carries the region sample into a projection")
	if GoodsRead.months_held(state) != 2 or RegionRead.months_held(ns) != 2:
		_fail("taking a copy emptied the live state's series")


# --- the fund strip -----------------------------------------------------------

func _test_the_fund_strip_names_the_others_loss() -> void:
	var state = _state()
	var ns = state.player()
	var list: Array = _named(state, ns)
	var region_id := ""
	for region in list:
		if Regions.output_eur_bn(ns, region.id) > 0.0:
			region_id = region.id
			break
	var shares: Array = _loader.region_fund_rule["share_pct"]
	var est := RegionFunds.estimate(state, ns, _loader, region_id, float(shares[1]), 2)
	if not bool(est.get("ok", false)):
		_fail("premise: the fund estimate refused (%s)" % est.get("reason", ""))
		return
	var others: Dictionary = est["others"]
	if others.has(region_id):
		_fail("the other regions' loss names the funded region")
	if others.size() != list.size() - 1:
		_fail("the other regions' loss names %d regions of %d" % [others.size(), list.size() - 1])
	# Against the live deviation with and without the fund's row: the read is the
	# game's own Regions function, nothing re-derived.
	var access := Regions.accessibility_for(ns, list, state.region_graph)
	var sites: Dictionary = state.project_sited_pct.get(ns.id, {})
	var now := Regions.deviation_by_region(ns, list, access, sites)
	var sum := 0.0
	var any_loss := false
	for id in others:
		var row: Dictionary = others[id]
		if float(row["pts"]) >= 0.0:
			_fail("%s gains from a fund elsewhere (%s pts)" % [id, row["pts"]])
		else:
			any_loss = true
		var eur := float(row["pts"]) / 100.0 * Regions.output_eur_bn(ns, id)
		if absf(float(row["eur_bn"]) - eur) > EPS:
			_fail("%s: the loss in EUR bn %s is not its points on its output %s" % [id, row["eur_bn"], eur])
		sum += float(row["eur_bn"])
	if not any_loss:
		_fail("premise: no other region loses")
	if absf(float(est["others_eur_bn"]) - sum) > EPS:
		_fail("others_eur_bn %s is not the sum of the rows %s" % [est["others_eur_bn"], sum])
	# Zero-mean over the nation's output: the funded region's gain is the others' loss.
	var here := float(est["here_eur_bn"])
	if here <= 0.0 or absf(here + sum) > 1e-9 * absf(here):
		_fail("the funded region gains %s EUR bn a year and the others lose %s" % [here, sum])
	# The estimate wrote nothing: the row it appended for the read is gone.
	if Regions.deviation_by_region(ns, list, access, sites) != now or not ns.region_funds.is_empty():
		_fail("the estimate left its row behind")


# --- the unrest site ----------------------------------------------------------

func _test_the_unrest_read() -> void:
	var state = _state()
	var ns = state.player()
	var empty := RegionRead.unrest_site(state, ns)
	if int(empty["months"]) != 0 or not (empty["migration"] as Array).is_empty():
		_fail("a new game's unrest read shows %d months of migration" % int(empty["months"]))
	WorldMonth.tick_month(state, _loader)
	# Off zero, so a read that dropped either register would show: a quiet first month
	# leaves both at 0.0.
	ns.unrest_impulse_pct = -0.25
	ns.unrest_opinion_load = 0.375
	var read := RegionRead.unrest_site(state, ns)
	var list: Array = _named(state, ns)
	var site := Unrest.site_report(ns, list, Regions.accessibility_for(ns, list, state.region_graph),
		state.project_sited_pct.get(ns.id, {}))
	for key in site:
		if var_to_str(read[key]) != var_to_str(site[key]):
			_fail("the unrest read's %s is %s, the site report's %s" % [key, read[key], site[key]])
	if float(read["impulse_pct"]) != float(ns.unrest_impulse_pct) or float(read["opinion_load"]) != float(ns.unrest_opinion_load):
		_fail("the unrest read's price is not the register's")
	var region_id := String(site["region_id"])
	if region_id == "":
		_fail("premise: France has no unrest site")
		return
	if var_to_str(read["migration"]) != var_to_str(ns.region_history[region_id]["migration"]) or int(read["months"]) != 1:
		_fail("the unrest read's migration is not the site region's sample")


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_screen_reads")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)
