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

		if n.leader_name == "":
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
