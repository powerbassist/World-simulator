extends SceneTree

## Headless test: godot --headless --script res://tests/test_migration.gd
## Non-zero exit on any failure.
##
## V2.6a, people move. Model: docs/migration-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Migration = preload("res://src/sim/migration.gd")
const MigrationK = preload("res://src/sim/migration_constants.gd")
const Regions = preload("res://src/sim/regions.gd")
const Companies = preload("res://src/sim/companies.gd")

const NATIONS := ["AUT", "BEL", "CHE", "DEU", "ESP", "FRA", "GBR", "ITA", "LUX", "NLD"]

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_seed_matches_the_content()
	_check_pull_is_expected_income()
	_check_city_pull_matches_named_payroll()
	_check_both_partitions_close()
	_check_the_national_figure_is_untouched()
	_check_no_share_goes_negative()
	_check_share_delta_direction()
	_check_both_harnesses_tick()
	_finish()


## THE SEED IS THE CONTENT, EXACTLY. The authored share is where a region STARTED,
## and the whole session is the difference between that and where it ends -- so if
## the seed disagreed with the file on the first frame the divergence would be
## measured against the wrong thing.
func _check_seed_matches_the_content() -> void:
	for nation_id in NATIONS:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = _loader.regions.get(nation_id, [])
		for region in list:
			if absf(Migration.region_share(ns, region.id) - region.share) > 0.000000000001:
				_fail("%s region '%s' seeded at %f against an authored %f" % [
					nation_id, region.id, Migration.region_share(ns, region.id), region.share,
				])
			for city in region.cities:
				if absf(Migration.city_share(ns, city.id) - city.share) > 0.000000000001:
					_fail("%s city '%s' seeded at %f against an authored %f" % [
						nation_id, city.id, Migration.city_share(ns, city.id), city.share,
					])


## THE PULL IS A PRODUCT OF TWO RATIOS AND CARRIES NO AUTHORED WEIGHT, so it can be
## recomputed here from the register's own published quantities and compared. If this
## ever needs a coefficient to agree, a coefficient has been added to migration.gd and
## the model's central claim is no longer true.
##
## Britain is asserted FLAT rather than excluded: docs/region-economy-model.md section
## 8 records that its gdp_share IS its population share and its unemployment_rel is
## exactly 1.0, so every British region's expected income is identical by
## construction. That is a bound with a number beside it, and the day somebody
## authors the twelve ITL1 figures this assertion turns red and says so.
func _check_pull_is_expected_income() -> void:
	for nation_id in NATIONS:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = _loader.regions.get(nation_id, [])
		for region in list:
			var per_head: float = Regions.share_of(ns, region.id) / maxf(Migration.region_share(ns, region.id), 0.000001)
			var employed: float = 1.0 - Regions.unemployment_pct(ns, list, region.id) / 100.0
			var expected: float = per_head * employed
			var actual: float = Migration.region_pull(ns, list, region.id)
			if absf(actual - expected) > 0.000000001:
				_fail("%s region '%s' pull %f against an expected income of %f" % [
					nation_id, region.id, actual, expected,
				])

	var gbr = GameState.new_game(_loader, "GBR")
	var gbr_ns = gbr.nations["GBR"]
	var gbr_list: Array = _loader.regions.get("GBR", [])
	var first: float = Migration.region_pull(gbr_ns, gbr_list, gbr_list[0].id)
	for region in gbr_list:
		if absf(Migration.region_pull(gbr_ns, gbr_list, region.id) - first) > 0.000000001:
			_fail("a British region's expected income differs from another's -- section 8's proxy says every one of them is identical, so either the proxy moved or this test is measuring the wrong thing")


## THE CITY PULL IS A SECOND SIGNAL AT A SECOND LEVEL, and city_pull() carries no
## test at all until this one -- so it is recomputed here from the register's own
## published quantities the same way the region pull is above. A division inverted
## inside city_pull() (heads over payroll rather than payroll over heads) would
## still return a float and still run; only an independent recomputation catches it.
##
## The seven nations with no data/companies/<ID>.json name no employer anywhere, so
## every one of their cities' pull must come back EXACT zero -- src/ui/region_panel.gd's
## own distinction between a present-and-empty figure and an absent one, checked here
## rather than only drawn there. Which seven those are is read off loader.companies
## rather than named, so an eleventh companies file changes this test's answer without
## changing its text.
func _check_city_pull_matches_named_payroll() -> void:
	for nation_id in NATIONS:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = _loader.regions.get(nation_id, [])
		var has_employers: bool = not _loader.companies.get(nation_id, []).is_empty()
		for region in list:
			for city in region.cities:
				var heads: float = Migration.city_population(ns, region.id, city.id)
				var payroll: float = Companies.headcount_in_city(ns, _loader, city.id)
				var expected: float = payroll / heads if heads > 0.0 else 0.0
				var actual: float = Migration.city_pull(ns, _loader, region, city.id)
				if absf(actual - expected) > 0.000000001:
					_fail("%s city '%s' pull %f against a recomputed %f" % [
						nation_id, city.id, actual, expected,
					])
				if not has_employers and actual != 0.0:
					_fail("%s city '%s' pull %f against an expected exact 0.0 -- %s names no employers" % [
						nation_id, city.id, actual, nation_id,
					])


## THE INVARIANT THE WHOLE SESSION RESTS ON, at both levels and over a real fourteen
## years rather than at new game, because float drift is what a one-month check cannot
## see. The flow is zero-sum by subtraction, so this is the model rather than a check
## on it -- and the tolerance is 1e-12 relative rather than V2.5's 1e-9, because
## nothing here has a Jensen term: no quantity is exponentiated.
func _check_both_partitions_close() -> void:
	for nation_id in ["FRA", "DEU", "GBR"]:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = _loader.regions.get(nation_id, [])
		var start_total: float = Migration.named_region_total(ns, list)
		var start_city_totals: Dictionary = {}
		for region in list:
			var region_total: float = 0.0
			for city in region.cities:
				region_total += Migration.city_share(ns, city.id)
			start_city_totals[region.id] = region_total

		for i in 168:
			Migration.tick_month(state, _loader)

		var end_total: float = Migration.named_region_total(ns, list)
		if absf(end_total - start_total) > 0.000000000001:
			_fail("%s: the named regions summed to %.15f and now sum to %.15f -- the national residual is frozen, so this may not move" % [
				nation_id, start_total, end_total,
			])
		for region in list:
			var region_total: float = 0.0
			for city in region.cities:
				region_total += Migration.city_share(ns, city.id)
			if absf(region_total - float(start_city_totals[region.id])) > 0.000000000001:
				_fail("%s region '%s': its named cities summed to %.15f and now sum to %.15f -- the rural residual carries the mean, so it neither drains nor fills" % [
					nation_id, region.id, float(start_city_totals[region.id]), region_total,
				])


## MIGRATION IS INTERNAL, so the head count it partitions may not move. This is what
## makes the balance re-run's bit-identity prediction a structural claim rather than
## a hope: ns.population is written by Economy.tick_month() alone and this system
## never touches it.
func _check_the_national_figure_is_untouched() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]
	var before: float = ns.population
	for i in 168:
		Migration.tick_month(state, _loader)
	if ns.population != before:
		_fail("the national population moved from %.15f to %.15f under migration alone" % [before, ns.population])


## The proportional form is what bounds a share, so this asserts the property rather
## than a clamp enforcing it -- src/sim/campaign.gd's argument that a bound with no
## number to set wrong beats a clamp.
func _check_no_share_goes_negative() -> void:
	for nation_id in ["FRA", "DEU", "GBR"]:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.nations[nation_id]
		for i in 168:
			Migration.tick_month(state, _loader)
		for key in ns.region_pop_share.keys():
			if float(ns.region_pop_share[key]) <= 0.0:
				_fail("%s region '%s' reached a share of %f" % [nation_id, key, float(ns.region_pop_share[key])])
		for key in ns.city_pop_share.keys():
			if float(ns.city_pop_share[key]) <= 0.0:
				_fail("%s city '%s' reached a share of %f" % [nation_id, key, float(ns.city_pop_share[key])])


## CONSERVATION AND DIRECTION ARE ORTHOGONAL FAILURES, and the three checks above
## this one prove it: negate every delta this module ever produces and the sum still
## telescopes to zero, ns.population is still untouched, and every share still stays
## positive -- a model that moved people TOWARD the poorer, higher-unemployment place
## would pass all three unchanged. And it cannot be caught by driving tick_month(),
## because MIGRATION_RATE is 0.0 in the shipped tree until a later task measures it,
## so any assertion reached through the tick passes vacuously whatever the sign is.
## share_delta() is checked directly instead, at a rate this test supplies itself.
func _check_share_delta_direction() -> void:
	var rate := 0.02
	var share := 0.10
	var mean := 1.0

	var up: float = Migration.share_delta(share, 1.5, mean, rate)
	if up <= 0.0:
		_fail("a pull above the mean produced a delta of %f -- migration should move people TOWARD the better place" % [up])

	var down: float = Migration.share_delta(share, 0.5, mean, rate)
	if down >= 0.0:
		_fail("a pull below the mean produced a delta of %f -- migration should move people AWAY from the worse place" % [down])

	var flat: float = Migration.share_delta(share, mean, mean, rate)
	if flat != 0.0:
		_fail("a pull equal to the mean produced a nonzero delta of %f" % [flat])

	var inert: float = Migration.share_delta(share, 1.5, mean, 0.0)
	if inert != 0.0:
		_fail("a rate of 0.0 produced a nonzero delta of %f -- this is why the shipped tree, at MIGRATION_RATE 0.0, is inert" % [inert])


## V1.5d SHIPPED WITH NEITHER HARNESS CALLING Media.tick_month(), so both ran the
## pre-session model and their agreement about a bit-identical re-run was about
## nothing. A bit-identical re-run is the REASSURING outcome, which is exactly why
## this is a test and not a habit -- tests/test_pledges.gd's idiom, and the reason it
## reads both files rather than one.
func _check_both_harnesses_tick() -> void:
	for path in ["res://tools/balance_probe.gd", "res://tests/test_balance.gd", "res://src/ui/main.gd"]:
		var text := FileAccess.get_file_as_string(path)
		if not text.contains("Migration.tick_month"):
			_fail("%s does not call Migration.tick_month -- a harness running the pre-session model agrees with the other about nothing" % path)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_migration: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr("FAIL: %s" % message)
	quit(1)
