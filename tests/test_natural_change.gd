extends SceneTree

## Headless test: godot --headless --script res://tests/test_natural_change.gd
## Non-zero exit on any failure.
##
## V2.6c, natural change. Model: docs/natural-change-model.md.

## suite-shard-checks: _check_the_content_is_measured,_check_share_delta_direction,_check_conservation_is_exact,_check_the_national_figure_is_untouched,_check_luxembourg_cannot_differ_from_itself,_check_cities_ride_but_are_not_pushed,_check_the_flow_moves_where_births_are,_check_the_composition_is_the_call_site

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Migration = preload("res://src/sim/migration.gd")
const NaturalChange = preload("res://src/sim/natural_change.gd")

## The register is the list (V4 handoff): a literal 29-id roster here went
## stale the moment V4.11 grew the roster -- five test files at once.
func _nations() -> Array:
	var ids: Array = _loader.nations.keys()
	ids.sort()
	return ids

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	# V3.3 scratch: -- check-name runs ONE check (the crash isolation harness).
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]

	var _matched := 0
	if only == "" or only == "_check_the_content_is_measured":
		_matched += 1
		_check_the_content_is_measured()
	if only == "" or only == "_check_share_delta_direction":
		_matched += 1
		_check_share_delta_direction()
	if only == "" or only == "_check_conservation_is_exact":
		_matched += 1
		_check_conservation_is_exact()
	if only == "" or only == "_check_the_national_figure_is_untouched":
		_matched += 1
		_check_the_national_figure_is_untouched()
	if only == "" or only == "_check_luxembourg_cannot_differ_from_itself":
		_matched += 1
		_check_luxembourg_cannot_differ_from_itself()
	if only == "" or only == "_check_cities_ride_but_are_not_pushed":
		_matched += 1
		_check_cities_ride_but_are_not_pushed()
	if only == "" or only == "_check_the_flow_moves_where_births_are":
		_matched += 1
		_check_the_flow_moves_where_births_are()
	if only == "" or only == "_check_the_composition_is_the_call_site":
		_matched += 1
		_check_the_composition_is_the_call_site()
	if only != "" and _matched == 0:
		_fail("unknown check name '%s' -- the filter ran nothing, and green-over-nothing is the V2.1c class" % only)
	_finish()


## THE FIELD IS MEASURED FOR EVERY REGION THE REGISTER NAMES, and the loader's own
## validator makes an absent one an error -- this check is the same contract read
## from the loaded objects rather than from the parse, plus the two bounds the
## import records: Britain at exactly zero everywhere (UKM publishes no rates, and a
## differential mixing measured and invented rates invents flows), and every nation
## but Britain carrying a real spread, because a register whose rates all agreed
## would be a register whose flow was dead on arrival.
func _check_the_content_is_measured() -> void:
	for nation_id in _nations():
		var list: Array = _loader.regions.get(nation_id, [])
		var spread_min := INF
		var spread_max := -INF
		for region in list:
			var rate: float = region.natural_change_pct
			if absf(rate) > 3.0:  # region.gd's catch, widened at V4.11 for TRC's measured +2.07
				_fail("%s region '%s' carries natural_change_pct %f -- outside the range any measured rate in the roster approaches" % [nation_id, region.id, rate])
			spread_min = minf(spread_min, rate)
			spread_max = maxf(spread_max, rate)
		if nation_id == "GBR":
			if spread_min != 0.0 or spread_max != 0.0:
				_fail("Britain carries a natural differential -- UKM publishes no rates, so the import's bound is zero everywhere")
		elif list.size() > 1 and spread_max - spread_min <= 0.0 and not _is_proxy_shape(list):
			# One region cannot spread against itself, which is Luxembourg's case and
			# why the bound is read off the register's size rather than named: a
			# nation with no spread and more than one region is either a broken
			# import or a bound that stopped being recorded.
			_fail("%s carries no natural spread at all -- the field is measured for every multi-region nation but Britain" % nation_id)


## CONSERVATION AND DIRECTION ARE ORTHOGONAL FAILURES, test_migration.gd's sentence
## verbatim. The direction of THIS flow is asserted directly, at rates this test
## supplies, because the shipped rates sit inside a band the sweep could one day
## narrow to zero -- and a flow driven only through tick_month() would pass whatever
## sign the model had, which is the exact reason migration's own direction check
## calls its expression directly.
func _check_share_delta_direction() -> void:
	var share := 0.10

	var up: float = NaturalChange.share_delta(share, 0.75, 0.15)
	if up <= 0.0:
		_fail("a rate above the mean produced a delta of %f -- births above the nation's own rate must GROW a region's share" % [up])

	var down: float = NaturalChange.share_delta(share, -0.82, 0.15)
	if down >= 0.0:
		_fail("a rate below the mean produced a delta of %f -- deaths must SHRINK a region's share against the mean" % [down])

	var flat: float = NaturalChange.share_delta(share, 0.15, 0.15)
	if flat != 0.0:
		_fail("a rate equal to the mean produced a nonzero delta of %f" % [flat])


## THE COMBINED SUM IS EXACT, checked over the live tick on all ten nations. The
## natural flow telescopes to zero in the live weights it reads and migration's two
## levels telescope in theirs, so the named total is invariant however the three
## flows interact -- and the pairing of shares to rates at the call site is what
## makes it so: a swapped argument still returns floats and still runs, but
## `sum s_i (r_i - mean)` ceases to telescope the moment the mean is taken in
## weights the deltas do not use. Conservation IS the call-site assertion.
func _check_conservation_is_exact() -> void:
	# ONE game for every nation: Migration.tick_month() ticks all of them each call,
	# so a fresh game and 168 months per nation (asserting one) was 29x the work for
	# the same claim -- the suite audit's F4.
	var state = GameState.new_game(_loader, "FRA")
	var start: Dictionary = {}
	for nation_id in _nations():
		start[nation_id] = Migration.named_region_total(state.nations[nation_id], _loader.regions.get(nation_id, []))
	for i in 168:
		Migration.tick_month(state, _loader)
	for nation_id in _nations():
		var list: Array = _loader.regions.get(nation_id, [])
		var drift: float = absf(Migration.named_region_total(state.nations[nation_id], list) - float(start[nation_id]))
		if drift > 0.000000000001:
			_fail("%s: the named regions' total drifted %f over 168 months -- the combined flow does not telescope" % [nation_id, drift])


func _check_the_national_figure_is_untouched() -> void:
	for nation_id in ["FRA", "DEU"]:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.nations[nation_id]
		var before: float = ns.population
		for i in 168:
			Migration.tick_month(state, _loader)
		if ns.population != before:
			_fail("%s: the national population moved under the combined flow -- natural change redistributes the differential, and the LEVEL stays Economy's measured compound" % nation_id)


## One region cannot differ from its own mean, so the deltas come back empty and the
## share cannot move at all -- Luxembourg's bound made arithmetic rather than a
## special case, asserted EXACTLY because anything else would mean the skip had
## quietly grown arithmetic under it.
func _check_luxembourg_cannot_differ_from_itself() -> void:
	var state = GameState.new_game(_loader, "LUX")
	var ns = state.nations["LUX"]
	var list: Array = _loader.regions.get("LUX", [])
	var before: float = Migration.region_share(ns, list[0].id)
	for i in 168:
		Migration.tick_month(state, _loader)
	if Migration.region_share(ns, list[0].id) != before:
		_fail("Luxembourg's one region moved %+.15f -- a region alone cannot differ from its own mean, and the skip exists so this is exact" % (Migration.region_share(ns, list[0].id) - before))


## CITIES RIDE THEIR REGION: city_population() multiplies the live region share, so
## Paris's head count grows because Ile-de-France's does, and no city carries a rate
## of its own -- there is no data below NUTS 3, and inventing a per-city rate would
## be a number nobody measured. The paired run proves the ride; the "not pushed"
## half is the source check below, because city shares are NOT identical between
## the two runs -- migration's city pull reads city_population(), which rides the
## region share the flow just moved, so the ride reaches the cities through the
## existing machinery or it does not reach them at all.
func _check_cities_ride_but_are_not_pushed() -> void:
	var shipped = GameState.new_game(_loader, "FRA")
	var stripped = GameState.new_game(_loader, "FRA")
	_capture_shipped_rates()
	for region in _loader.regions.get("FRA", []):
		region.natural_change_pct = 0.0
	for i in 168:
		Migration.tick_month(stripped, _loader)
	for region in _loader.regions.get("FRA", []):
		region.natural_change_pct = float(_shipped_rates[region.id])
	for i in 168:
		Migration.tick_month(shipped, _loader)
	var grown: float = Migration.city_population(shipped.nations["FRA"], "FR1", "FR1_paris")
	var base: float = Migration.city_population(stripped.nations["FRA"], "FR1", "FR1_paris")
	if grown <= base:
		_fail("Paris ends at %.0f heads with natural change against %.0f without -- the city must ride its region's share upward, Ile-de-France's rate leading the nation" % [grown, base])
	_shipped_rates.clear()


## THE FLOW'S DIRECTION THROUGH THE LIVE CALL SITE, and the paired-run form is the
## only one available: MIGRATION_RATE is a const, so natural change cannot be
## isolated by zeroing the other flow -- it is isolated by zeroing the FIELD, the
## same move the sweep's attribution uses. For every nation checked, the region
## with the most positive differential against the live mean ends ABOVE its
## zero-rate twin and the most negative ends BELOW, in both the nation where the
## two flows agree (FRA: Ile-de-France pulls migrants AND births) and the one where
## they oppose (DEU: the east has the lowest pull and an above-mean rate, because
## the deaths are where the pull is not). A region's differential is computed
## against the same live shares the flow reads, so the ranking here is the one the
## model acts on.
func _check_the_flow_moves_where_births_are() -> void:
	for nation_id in ["FRA", "DEU", "ESP"]:
		var list: Array = _loader.regions.get(nation_id, [])
		var shares: Dictionary = {}
		var rates: Dictionary = {}
		for region in list:
			shares[region.id] = float(region.share)
			rates[region.id] = region.natural_change_pct
		var mean: float = NaturalChange.named_mean(shares, rates)
		var top_id := ""
		var bottom_id := ""
		var top_gap := -INF
		var bottom_gap := INF
		for id in rates.keys():
			var gap: float = float(rates[id]) - mean
			if gap > top_gap:
				top_gap = gap
				top_id = id
			if gap < bottom_gap:
				bottom_gap = gap
				bottom_id = id

		var shipped = GameState.new_game(_loader, nation_id)
		var stripped = GameState.new_game(_loader, nation_id)
		for region in list:
			region.natural_change_pct = 0.0
		for i in 168:
			Migration.tick_month(stripped, _loader)
		for region in list:
			region.natural_change_pct = float(rates[region.id])
		for i in 168:
			Migration.tick_month(shipped, _loader)

		var ns = shipped.nations[nation_id]
		var stripped_ns = stripped.nations[nation_id]
		var top_moved: float = Migration.region_share(ns, top_id) - Migration.region_share(stripped_ns, top_id)
		var bottom_moved: float = Migration.region_share(ns, bottom_id) - Migration.region_share(stripped_ns, bottom_id)
		if top_moved <= 0.0:
			_fail("%s: '%s', the region %+.3f %%/yr above the mean, moved %+.6f against its zero-rate twin -- natural change must grow the region whose births outpace the nation" % [nation_id, top_id, top_gap * 100.0, top_moved])
		if bottom_moved >= 0.0:
			_fail("%s: '%s', the region %+.3f %%/yr below the mean, moved %+.6f against its zero-rate twin -- natural change must shrink the region whose births lag the nation" % [nation_id, bottom_id, bottom_gap * 100.0, bottom_moved])


## THE LEAF AND THE WRITER, read from source. natural_change.gd preloads nothing,
## writes nothing and names no register; migration.gd is the file that applies what
## comes back -- the single-writer property the conservation check above can measure
## only at runtime, pinned at the source as well because a second apply loop in
## another file would conserve too.
func _check_the_composition_is_the_call_site() -> void:
	var leaf := FileAccess.get_file_as_string("res://src/sim/natural_change.gd")
	if leaf.contains("preload("):
		_fail("src/sim/natural_change.gd preloads something -- it is the strictest leaf in src/sim/, and the caller freezes the snapshot")
	for marker in ["region_pop_share", "city_pop_share"]:
		if leaf.contains(marker):
			_fail("src/sim/natural_change.gd names `%s` -- the leaf computes deltas and the writer applies them" % marker)
	var host := FileAccess.get_file_as_string("res://src/sim/migration.gd")
	if not host.contains("NaturalChange.deltas("):
		_fail("src/sim/migration.gd never calls NaturalChange.deltas -- the flow is composed in the register's one writer, or it is not live at all")


var _shipped_rates: Dictionary = {}


func _capture_shipped_rates() -> void:
	_shipped_rates.clear()
	for region in _loader.regions.get("FRA", []):
		_shipped_rates[region.id] = region.natural_change_pct


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_natural_change: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr("FAIL: %s" % message)
	quit(1)


## V4.11: the POPULATION-PROXY shape, read off the register rather than named.
## Britain was the one nation importing it (V2.2a) and the test said "GBR"; the
## neighbourhood's five non-NUTS nations import it too. A register whose every
## region carries gdp_share == share and unemployment_rel == 1.0 has no regional
## divergence BY CONSTRUCTION (docs/data-sources.md records each as a bound), so
## there is no pull to move people and no measured spread to assert.
func _is_proxy_shape(list: Array) -> bool:
	for region in list:
		if absf(region.gdp_share - region.share) > 1e-6 or absf(region.unemployment_rel - 1.0) > 1e-9:
			return false
	return true
