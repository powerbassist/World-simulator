extends SceneTree

## Headless test: godot --headless --script res://tests/test_data.gd
## Non-zero exit on any failure.

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")
const GameState = preload("res://src/core/game_state.gd")
const C = preload("res://src/sim/economy_constants.gd")

func _init() -> void:
	var failures: Array[String] = []

	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		failures.append("expected zero errors loading real data, got: %s" % [loader.errors])

	var playable_count := 0
	for id in loader.nations.keys():
		var n: Nation = loader.nations[id]
		var total := 0.0
		for v in n.sectors.values():
			total += v
		if absf(total - 1.0) > 0.001:
			failures.append("%s: sectors sum to %s, expected 1.0" % [id, total])

		if n.leader_person_id == "":
			failures.append("%s: no leader name" % id)

		if n.dissolution_rule == "" or not Nation.KNOWN_DISSOLUTION_RULES.has(n.dissolution_rule):
			failures.append("%s: dissolution_rule '%s' is missing or unrecognised" % [id, n.dissolution_rule])

		if n.playable:
			playable_count += 1

		# V1.2a: starting fiscal policy is per-nation, not read from a single
		# shared policy_defaults.json -- every nation must carry its own.
		for key in C.TAX_KEYS:
			if not n.tax_rates_pct.has(key):
				failures.append("%s: fiscal.tax_rates_pct missing '%s'" % [id, key])
		for key in C.SPENDING_KEYS:
			if not n.spending_pct_gdp.has(key):
				failures.append("%s: fiscal.spending_pct_gdp missing '%s'" % [id, key])

		if not loader.parties.has(id):
			failures.append("%s: no parties loaded" % id)
			continue
		var party_list: Array = loader.parties[id]
		if party_list.size() < 4:
			failures.append("%s: fewer than 4 parties (%d)" % [id, party_list.size()])
		var seat_total := 0.0
		for party in party_list:
			seat_total += party.seat_share
		if absf(seat_total - 1.0) > 0.001:
			failures.append("%s: party seat_share sums to %s, expected 1.0" % [id, seat_total])

	var fixture_text := FileAccess.get_file_as_string("res://tests/fixtures/nation_bad_unemployment.json")
	var fixture_dict = JSON.parse_string(fixture_text)
	var fixture_errors: Array[String] = []
	Nation.from_dict(fixture_dict, "nation_bad_unemployment.json", fixture_errors)
	var names_field := false
	for e in fixture_errors:
		if e.find("unemployment_pct") != -1:
			names_field = true
	if not names_field:
		failures.append("corrupt fixture did not produce an error naming unemployment_pct: %s" % [fixture_errors])

	# V1.5b. The cohort check worth a fixture is the RESIDUAL one, because it is the
	# only one that cannot be read off the field it guards: young and old are each in
	# range on their own, and it is their sum that leaves Demography.working_share()
	# -- a denominator in dependency_ratio() AND in labour_force() -- near zero.
	var cohort_text := FileAccess.get_file_as_string("res://tests/fixtures/nation_bad_cohorts.json")
	var cohort_dict = JSON.parse_string(cohort_text)
	var cohort_errors: Array[String] = []
	Nation.from_dict(cohort_dict, "nation_bad_cohorts.json", cohort_errors)
	var names_working := false
	for e in cohort_errors:
		if e.find("working age") != -1:
			names_working = true
	if not names_working:
		failures.append("corrupt cohort fixture did not produce an error naming the working-age floor: %s" % [cohort_errors])

	# V3.5. The emissions block is required for all twenty-nine, because an absent
	# or key-less figure parses 0.0 t/capita against a live ~4-9 -- a decarbonised
	# country rather than an empty one, and the base term of
	# Energy.emissions_tonnes(). The fixture keeps the BLOCK and drops the KEY, so
	# the error names the field and not merely the block it lives in.
	var emissions_text := FileAccess.get_file_as_string("res://tests/fixtures/nation_bad_emissions.json")
	var emissions_dict = JSON.parse_string(emissions_text)
	var emissions_errors: Array[String] = []
	Nation.from_dict(emissions_dict, "nation_bad_emissions.json", emissions_errors)
	var names_co2e := false
	for e in emissions_errors:
		if e.find("co2e_per_capita_t") != -1:
			names_co2e = true
	if not names_co2e:
		failures.append("emissions fixture without co2e_per_capita_t did not produce an error naming it: %s" % [emissions_errors])

	if loader.nations.has("FRA"):
		var fra: Nation = loader.nations["FRA"]
		var expected_gdp := 2900.0
		var expected_debt := 113.0
		if absf(fra.gdp_eur_bn - expected_gdp) / expected_gdp > 0.05:
			failures.append("FRA gdp_eur_bn %s not within 5%% of %s" % [fra.gdp_eur_bn, expected_gdp])
		if absf(fra.debt_to_gdp_pct - expected_debt) / expected_debt > 0.05:
			failures.append("FRA debt_to_gdp_pct %s not within 5%% of %s" % [fra.debt_to_gdp_pct, expected_debt])
	else:
		failures.append("FRA not loaded")

	if playable_count < 3:
		failures.append("expected at least 3 playable nations (V1.2d), found %d" % playable_count)

	# V1.6a. EVERY nation fixture must carry EVERY required `imported` block, and this
	# check exists because three of them did not and would have passed anyway.
	#
	# The fixtures above are each written to produce ONE named error, and they assert
	# it by searching the error list for a substring. A fixture that predates a block
	# added since it was written therefore keeps passing while quietly also reporting
	# the missing block -- it still names its own defect, so nothing goes red, and it
	# is now testing two things one of which nobody chose. `_trend_from_year` at V1.5b,
	# `cohorts` at V1.5b and `inequality` at V1.5c were each retro-fitted by hand, and
	# the out-of-order key in every one of these files is the fingerprint.
	#
	# Required is derived from Nation.KNOWN_IMPORTED_KEYS rather than listed, so the
	# next session that adds a block is TOLD rather than expected to remember: the
	# leading-underscore keys are provenance and optional, everything else is a block
	# _extract_dict() will error on. That makes this check maintain itself.
	for fixture in ["nation_bad_cohorts", "nation_bad_formation_method", "nation_bad_unemployment", "nation_bad_emissions"]:
		var path := "res://tests/fixtures/%s.json" % fixture
		var raw := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("imported"):
			failures.append("%s: fixture has no `imported` block at all" % fixture)
			continue
		var block: Dictionary = (parsed as Dictionary)["imported"]
		for key in Nation.KNOWN_IMPORTED_KEYS:
			if key.begins_with("_"):
				continue
			if not block.has(key):
				failures.append(
					"%s: fixture is missing imported.%s -- it predates a block added since it was written, so it still passes and is now also reporting an error nobody chose" % [fixture, key]
				)

	# No nation's per-nation starting policy is calibrated below what its
	# modelled taxes yield -- the negative-residual guard game_state.gd's
	# _build_nation() reports as an error, checked here across every nation
	# rather than only the one actually played in a given game.
	for id in loader.nations.keys():
		var state = GameState.new_game(loader, id)
		for e in state.errors:
			if e.find("revenue residual would be negative") != -1:
				failures.append("%s: %s" % [id, e])

	if failures.is_empty():
		print("test_data: all checks passed")
		quit(0)
	else:
		for f in failures:
			printerr(f)
		quit(1)
