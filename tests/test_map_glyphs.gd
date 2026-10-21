extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_glyphs.gd
## Non-zero exit on any failure.
##
## V4.10b, the tier register. A tier decides which mark a city gets and when its
## name is shown, so a wrong tier is silent twice over: the wrong glyph, and a
## name that never appears. What can go wrong without a red light is the capital
## lookup -- it is a NAME match between two files, and two of 41 nations did not
## match on the day it was written (MDA by a diacritic, MLT because Valletta is
## below the city register's cut). Both cases are pinned here by what they
## resolve to, not by a count, so a data edit that breaks the match fails.

const DataLoader = preload("res://src/core/data_loader.gd")
const MapGlyphs = preload("res://src/ui/map_glyphs.gd")
const Capital = preload("res://src/core/capital.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return
	_check_capitals(loader)
	_check_tiers()
	_check_glyph_rects()
	_finish()


func _city_named(loader, nation_id: String, city_name: String):
	for region in loader.regions.get(nation_id, []):
		for city in region.cities:
			if city.city_name == city_name:
				return city
	return null


func _largest_city_id(loader, nation_id: String) -> String:
	# Static share, not live population: the fallback is content, decided once.
	var best := ""
	var best_share := -1.0
	for region in loader.regions.get(nation_id, []):
		for city in region.cities:
			var s := float(region.share) * float(city.share)
			if s > best_share:
				best_share = s
				best = city.id
	return best


func _check_capitals(loader) -> void:
	var errors: Array[String] = MapGlyphs.capital_errors(loader)
	if not errors.is_empty():
		_failures.append("capital_errors: %s" % [errors])
	var caps: Dictionary = MapGlyphs.capitals(loader)
	var per_nation := {}
	for city_id in caps.keys():
		var nid := String(caps[city_id])
		per_nation[nid] = int(per_nation.get(nid, 0)) + 1
	for nid in loader.nations.keys():
		if int(per_nation.get(nid, 0)) != 1:
			_failures.append("nation %s has %d capitals, want 1" % [nid, int(per_nation.get(nid, 0))])
	if loader.nations.has("FRA"):
		var paris = _city_named(loader, "FRA", "Paris")
		if paris == null or not caps.has(paris.id):
			_failures.append("FRA's capital did not resolve to the city named Paris")
	if loader.nations.has("MDA"):
		var chisinau = _city_named(loader, "MDA", "Chisinau")
		if chisinau == null or String(caps.get(chisinau.id, "")) != "MDA":
			_failures.append("MDA's capital 'Chișinău' did not fold onto the city 'Chisinau'")
	# V5.1-0d: the diary and the campaign read this rule too, and its fallback is
	# silent -- so a capital that stops matching by name (a typo, a renamed city)
	# must fail here rather than quietly move the seat of government to the
	# largest city. MLT is the one recorded bound.
	var fell_back: Array = []
	for nid in loader.nations.keys():
		var want := Capital.fold(String(loader.nations[nid].capital))
		var c = Capital.city(loader, String(nid))
		if c == null or Capital.fold(c.city_name) != want:
			fell_back.append(String(nid))
	if fell_back != ["MLT"]:
		_failures.append("capitals that fall back to the largest city: %s, want only the recorded bound MLT" % [fell_back])
	if loader.nations.has("MLT"):
		var largest := _largest_city_id(loader, "MLT")
		if String(caps.get(largest, "")) != "MLT":
			_failures.append("MLT (Valletta not in the register) did not fall back to its largest city %s" % largest)


func _check_tiers() -> void:
	var caps := {"cap_small": "XXX"}
	var t := MapGlyphs.tier_of({"city_id": "cap_small", "population": 100_000.0}, caps)
	if t != 1:
		_failures.append("a capital of 100k is tier %d, want 1" % t)
	t = MapGlyphs.tier_of({"city_id": "big", "population": MapGlyphs.TIER2_POP}, caps)
	if t != 2:
		_failures.append("a city at TIER2_POP is tier %d, want 2" % t)
	t = MapGlyphs.tier_of({"city_id": "small", "population": MapGlyphs.TIER2_POP - 1.0}, caps)
	if t != 3:
		_failures.append("a city just under TIER2_POP is tier %d, want 3" % t)
	if MapGlyphs.TIER2_POP != 500_000.0:
		_failures.append("TIER2_POP is %f, the plan pinned 500 000" % MapGlyphs.TIER2_POP)


func _check_glyph_rects() -> void:
	var at := Vector2(400.0, 300.0)
	for tier in [1, 2, 3]:
		for pop in [10_000.0, 800_000.0, 9_000_000.0]:
			var r: Rect2 = MapGlyphs.glyph_rect(at, {"population": pop}, tier)
			if r.size.x <= 0.0 or r.size.y <= 0.0 or not r.has_point(at):
				_failures.append("glyph_rect tier %d pop %d is %s" % [tier, int(pop), r])
	var r1: Rect2 = MapGlyphs.glyph_rect(at, {"population": 800_000.0}, 1)
	var r2: Rect2 = MapGlyphs.glyph_rect(at, {"population": 800_000.0}, 2)
	if r1.size.x <= r2.size.x:
		_failures.append("a capital's ring does not widen its rect: %s vs %s" % [r1, r2])


func _finish() -> void:
	if _failures.is_empty():
		print("test_map_glyphs: OK")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		quit(1)
