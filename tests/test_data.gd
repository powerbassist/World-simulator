extends SceneTree

## Headless test: godot --headless --script res://tests/test_data.gd
## Non-zero exit on any failure.

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")

func _init() -> void:
	var failures: Array[String] = []

	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		failures.append("expected zero errors loading real data, got: %s" % [loader.errors])

	for id in loader.nations.keys():
		var n: Nation = loader.nations[id]
		var total := 0.0
		for v in n.sectors.values():
			total += v
		if absf(total - 1.0) > 0.001:
			failures.append("%s: sectors sum to %s, expected 1.0" % [id, total])

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

	if failures.is_empty():
		print("test_data: all checks passed")
		quit(0)
	else:
		for f in failures:
			printerr(f)
		quit(1)
