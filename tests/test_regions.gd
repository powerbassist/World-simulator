extends SceneTree

## Headless test: godot --headless --script res://tests/test_regions.gd
## Non-zero exit on any failure.
##
## V2.5, the economy from below. Model: docs/region-economy-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_schema()
	_finish()


func _check_schema() -> void:
	for nation_id in _loader.regions.keys():
		for region in _loader.regions[nation_id]:
			if region.gdp_share <= 0.0 or region.gdp_share > 1.0:
				_fail("%s region '%s' gdp_share %f is not in (0, 1]" % [nation_id, region.id, region.gdp_share])
			if region.unemployment_rel <= 0.0:
				_fail("%s region '%s' unemployment_rel %f is not positive" % [nation_id, region.id, region.unemployment_rel])
			var total: float = 0.0
			for key in ["agriculture", "industry", "services"]:
				if not region.sector_mix.has(key):
					_fail("%s region '%s' sector_mix has no '%s'" % [nation_id, region.id, key])
					continue
				total += float(region.sector_mix[key])
			if absf(total - 1.0) > 0.000000001:
				_fail("%s region '%s' sector_mix sums to %f, not 1.0" % [nation_id, region.id, total])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	for message in _failures:
		printerr("FAIL: " + message)
	if _failures.is_empty():
		print("test_regions: all checks passed")
		quit(0)
	else:
		printerr("test_regions: %d failure(s)" % _failures.size())
		quit(1)
