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

const NATIONS := ["FRA", "DEU", "ITA", "ESP", "BEL", "NLD", "LUX", "CHE", "GBR", "AUT", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "GRC", "HUN", "IRL", "LTU", "LVA", "MLT", "POL", "PRT", "ROU", "SVK", "SVN", "SWE"]

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
	_check_the_tick_moves_toward_the_pull()
	_check_both_harnesses_tick()
	_check_the_copy_carries_both()
	_check_one_tuned_constant()
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
		var access: Dictionary = Regions.accessibility_for(ns, list, state.region_graph)
		var sites: Dictionary = state.project_sited_pct.get(nation_id, {})
		for region in list:
			var per_head: float = Regions.share_of(ns, region.id) / maxf(Migration.region_share(ns, region.id), 0.000001)
			var employed: float = 1.0 - Regions.unemployment_pct(ns, list, region.id, access, sites) / 100.0
			var expected: float = per_head * employed
			var actual: float = Migration.region_pull(ns, list, region.id, access, sites)
			if absf(actual - expected) > 0.000000001:
				_fail("%s region '%s' pull %f against an expected income of %f" % [
					nation_id, region.id, actual, expected,
				])

	var gbr = GameState.new_game(_loader, "GBR")
	var gbr_ns = gbr.nations["GBR"]
	var gbr_list: Array = _loader.regions.get("GBR", [])
	var gbr_access: Dictionary = Regions.accessibility_for(gbr_ns, gbr_list, gbr.region_graph)
	var gbr_sites: Dictionary = gbr.project_sited_pct.get("GBR", {})
	var first: float = Migration.region_pull(gbr_ns, gbr_list, gbr_list[0].id, gbr_access, gbr_sites)
	for region in gbr_list:
		if absf(Migration.region_pull(gbr_ns, gbr_list, region.id, gbr_access, gbr_sites) - first) > 0.000000001:
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
## on it -- and the tolerance is 1e-12 ABSOLUTE rather than V2.5's 1e-9, because
## nothing here has a Jensen term: no quantity is exponentiated.
##
## THIS DRIVES Migration.tick_month() ALONE, 168 times, with no Economy or Companies
## call between ticks -- so every pull stays frozen at its new-game value for the
## whole run and the margin measured below comes from that static-pull trajectory.
## tools/migration_probe.gd's table (c) asserts the same invariant over the real
## Economy -> Companies -> Migration order every month, and its margin is measured on
## a DIFFERENT path: neither number is evidence for the other.
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
## would pass all three unchanged, because those invariants are sign-INSENSITIVE:
## they constrain what the flow conserves, never which way it runs. That is also why
## the two direction checks are complementary rather than redundant: this one calls
## share_delta() directly, at a rate this test supplies itself, and
## _check_the_tick_moves_toward_the_pull() reaches the same claim through the live
## tick_month(), which is the only way to cover the call sites -- they hand their
## arguments to share_delta() positionally, and no test of the extracted expression
## alone can see what order they hand it in.
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


## DIRECTION THROUGH THE LIVE TICK, because the call sites are where a sign error
## would live now. _check_share_delta_direction() proves the extracted expression is
## signed, but both call sites in migration.gd hand it their arguments positionally,
## and a refactor that swapped pull and mean at either would reverse the flow while
## every conservation check in this file stayed green -- those invariants are
## sign-insensitive (the comment on _check_share_delta_direction says why), and the
## balance re-run is blind here too because migration touches no national figure.
## So this drives tick_month() for the same 168 months the partition checks run, at
## the shipped rate, and asserts the movement the model names at BOTH levels.
##
## THE PULLS ARE READ BEFORE THE TICKS, and that is the assertion's substance rather
## than a convenience. The flow equalises expected income: a region people move into
## divides its frozen output between more heads, so its pull falls back toward the
## mean while its share rises -- read the pulls at the END and the ranking has
## compressed toward the answer, with the run's biggest loser now among the biggest
## pulls. The initial pull is the cause; the share movement is the effect.
##
## Region level: every nation with a regional spread to rank. BRITAIN IS EXCLUDED
## and that is this file's own bound, not a convenience -- every British region's
## expected income is identical by construction (_check_pull_is_expected_income's
## flat assertion), so Britain has no region-level direction at all; a nation with
## one region (Luxembourg) offers no ranking either, which the spread guard skips.
##
## City level, the nations data/companies/ names employers in -- read off the loader
## rather than named, _check_city_pull_matches_named_payroll's own device. Within
## each region with two or more named cities, the city with the highest named
## payroll per head gains share of its region and the lowest loses it. The
## employerless nations have no city-level flow to assert on (that check's
## exact-zero bound), a region with one city cannot differ from its own mean --
## migration.gd skips it, so this does too -- and a region whose cities all carry
## the same payroll per head has no direction either and is skipped the same way.
##
## V2.6c: THE REGION-LEVEL ASSERTIONS ARE MIGRATION'S OWN, so the natural rates are
## zeroed for the tick and restored after -- the isolation the sweep uses, held by a
## test. In the combined model a worst-pull region can carry an ABOVE-mean natural
## rate (DEU's DEE and ITA's ITC3 both do: the east and the south are where the
## deaths are, but they are also where the pull is lowest), and natural change would
## then move its share the other way from migration -- the combined direction is a
## real quantity and it is test_natural_change.gd's, not this check's. City shares
## are untouched by natural change, so the city half needs no isolation.
func _check_the_tick_moves_toward_the_pull() -> void:
	for nation_id in NATIONS:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = _loader.regions.get(nation_id, [])

		# The claims, recorded BEFORE any tick: which places the model says should
		# gain, which should lose, and the share each one started from.
		var ranked_regions := false
		var best_id := ""
		var worst_id := ""
		var best_start := 0.0
		var worst_start := 0.0
		if nation_id != "GBR" and list.size() > 1:
			var best_pull := -INF
			var worst_pull := INF
			for region in list:
				var pull: float = Migration.region_pull(ns, list, region.id, Regions.accessibility_for(ns, list, state.region_graph), state.project_sited_pct.get(nation_id, {}))
				if pull > best_pull:
					best_pull = pull
					best_id = region.id
				if pull < worst_pull:
					worst_pull = pull
					worst_id = region.id
			if best_pull > worst_pull:
				ranked_regions = true
				best_start = Migration.region_share(ns, best_id)
				worst_start = Migration.region_share(ns, worst_id)

		# The isolation, spanning the ticks and both assertion halves below. _fail()
		# records and continues, so the restore runs on every path -- and the saved
		# rates go back whether or not the assertions passed, because the loader's
		# region objects are shared with every check after this one.
		var saved_rates: Dictionary = {}
		for region in list:
			saved_rates[region.id] = region.natural_change_pct
			region.natural_change_pct = 0.0

		var city_gainers: Dictionary = {}
		var city_losers: Dictionary = {}
		if not _loader.companies.get(nation_id, []).is_empty():
			for region in list:
				if region.cities.size() < 2:
					continue
				var top_pull := -INF
				var bottom_pull := INF
				var top_id := ""
				var bottom_id := ""
				for city in region.cities:
					var pull: float = Migration.city_pull(ns, _loader, region, city.id)
					if pull > top_pull:
						top_pull = pull
						top_id = city.id
					if pull < bottom_pull:
						bottom_pull = pull
						bottom_id = city.id
				if top_pull <= bottom_pull:
					continue
				city_gainers[top_id] = Migration.city_share(ns, top_id)
				city_losers[bottom_id] = Migration.city_share(ns, bottom_id)

		for i in 168:
			Migration.tick_month(state, _loader)

		if ranked_regions:
			var best_moved: float = Migration.region_share(ns, best_id) - best_start
			var worst_moved: float = Migration.region_share(ns, worst_id) - worst_start
			if best_moved <= 0.0:
				_fail("%s: '%s', the region with the highest expected income, moved %+.6f share points under the live tick -- migration must move people TOWARD the better place" % [nation_id, best_id, best_moved])
			if worst_moved >= 0.0:
				_fail("%s: '%s', the region with the lowest expected income, moved %+.6f share points under the live tick -- migration must move people AWAY from the worse place" % [nation_id, worst_id, worst_moved])

		for city_id in city_gainers:
			var moved: float = Migration.city_share(ns, city_id) - float(city_gainers[city_id])
			if moved <= 0.0:
				_fail("%s: city '%s' moved %+.8f of its region under the live tick after ranking highest in named payroll per head -- migration must move people TOWARD the better place" % [nation_id, city_id, moved])
		for city_id in city_losers:
			var moved: float = Migration.city_share(ns, city_id) - float(city_losers[city_id])
			if moved >= 0.0:
				_fail("%s: city '%s' moved %+.8f of its region under the live tick after ranking lowest in named payroll per head -- migration must move people AWAY from the worse place" % [nation_id, city_id, moved])

		for region in list:
			region.natural_change_pct = float(saved_rates[region.id])


## V1.5d SHIPPED WITH NEITHER HARNESS CALLING Media.tick_month(), so both ran the
## pre-session model and their agreement about a bit-identical re-run was about
## nothing. A bit-identical re-run is the REASSURING outcome, which is exactly why
## this is a test and not a habit -- tests/test_pledges.gd's idiom, and the reason it
## reads both files rather than one.
##
## Presence alone is not enough: a grep for a call cannot see the order it runs in.
## Migration.tick_month() reads live regional output and unemployment settled by
## Economy.tick_month(), and live firm headcount settled by Companies.tick_month(),
## so order matters structurally. A future edit moving the call ahead of either would
## pass the presence check silently.
func _check_both_harnesses_tick() -> void:
	for path in ["res://tools/balance_probe.gd", "res://tests/test_balance.gd", "res://src/ui/main.gd"]:
		var text := FileAccess.get_file_as_string(path)
		if not text.contains("Migration.tick_month"):
			_fail("%s does not call Migration.tick_month -- a harness running the pre-session model agrees with the other about nothing" % path)

		# Check that Migration.tick_month runs AFTER both Economy.tick_month and Companies.tick_month
		var migration_idx: int = text.find("Migration.tick_month")
		var economy_idx: int = text.find("Economy.tick_month")
		var companies_idx: int = text.find("Companies.tick_month")

		if migration_idx != -1 and economy_idx != -1 and migration_idx < economy_idx:
			_fail("%s: Migration.tick_month appears before Economy.tick_month, but it reads settled output" % path)

		if migration_idx != -1 and companies_idx != -1 and migration_idx < companies_idx:
			_fail("%s: Migration.tick_month appears before Companies.tick_month, but it reads settled headcount" % path)


## V2.5's own bug, prevented rather than repeated: GameState.duplicate_state()
## dropping region_gdp_eur_bn collapsed Budget.project() to the residual alone -- a
## France losing 98 % of its output in the panel's own forecast -- and
## tests/test_budget.gd caught it only because the spine had already moved.
func _check_the_copy_carries_both() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var copy = state.nations["FRA"].duplicate_state()
	if copy.region_pop_share.is_empty() or copy.city_pop_share.is_empty():
		_fail("duplicate_state() dropped a share register -- Budget.project() runs on the copy")


## THE PULL CARRIES NO AUTHORED WEIGHT, and the file is read rather than trusted --
## tests/test_regions.gd's own check one session on. A second const here is a second
## strength written twice, which is what src/core/investment_action.gd refuses by name.
func _check_one_tuned_constant() -> void:
	var text := FileAccess.get_file_as_string("res://src/sim/migration_constants.gd")
	var count := 0
	for line in text.split("\n"):
		if line.begins_with("const "):
			count += 1
	if count != 2:
		_fail("src/sim/migration_constants.gd declares %d consts -- one rate and one bound, and a third is a weight the pull was designed not to need" % count)


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
