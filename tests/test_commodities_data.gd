extends SceneTree

## V4.6 Task 1. The goods register and the recipe table are CONTENT, so the only
## machine that can fail here is the loader: an input naming a good nobody
## declares would sit in the file looking like a recipe and produce nothing at
## tick time, which is the silent class every data check in this project exists to
## close. The counts are the plan's granularity rule made visible -- a good exists
## if a player decision can move its price.
##
## The brief's snippet used bare `assert()`; every other file in tests/ builds a
## `_failures` array and quits with a code instead, because an assert that fires
## ABORTS _init() before `quit()` runs and the engine's main loop keeps going --
## a failing assert HANGS the suite rather than failing it (measured this
## session). Same checks, house exit.

const DataLoader = preload("res://src/core/data_loader.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])

	# goods register loads and has ~70 entries across 7 categories
	if loader.commodity_goods.size() < 60:
		_fail("commodity_goods has %d entries, expected at least 60" % loader.commodity_goods.size())
	if loader.commodity_goods.size() > 80:
		_fail("commodity_goods has %d entries, expected at most 80" % loader.commodity_goods.size())

	var categories := {}
	for g in loader.commodity_goods.values():
		categories[g.category] = true
	if categories.size() != 7:
		_fail("goods cover %d categories, expected exactly 7: %s" % [categories.size(), str(categories.keys())])

	# every recipe's output is a known good; every input is a known good
	for r in loader.commodity_recipes.values():
		if not loader.commodity_goods.has(r.output):
			_fail("recipe '%s' output '%s' is not a known good" % [r.id, r.output])
		for inp in r.inputs:
			if not loader.commodity_goods.has(inp):
				_fail("recipe '%s' input '%s' is not a known good" % [r.id, inp])

	if _failures.is_empty():
		print("PASS test_commodities_data")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)