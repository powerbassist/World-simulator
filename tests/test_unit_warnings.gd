extends SceneTree

## V5.3 c' slice C (docs/design/v5.3-c-register.md section 9, "The regional warning"): a
## region whose shown figure stands far enough behind the nation's arrives as a warning.
## At most one a month, the worst region not warned in the last twelve months; the
## month's stamp ends the quiet month; a region ahead of the nation never warns; a build
## that closes the gap takes the region out of the band; the stamps survive a save.
## Reads tests/fixtures/units/ (round numbers, never a source): half the regions sit at
## the bad level of each type, so the band always has candidates.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const UnitsLoader = preload("res://src/core/loaders/units_loader.gd")
const Units = preload("res://src/sim/units.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UnitWarnings = preload("res://src/sim/unit_warnings.gd")
const UK = preload("res://src/sim/units_constants.gd")
const QuietMonth = preload("res://src/sim/quiet_month.gd")

const FIXTURE := "res://tests/fixtures/units"
const KIND := "region_warning"

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	UnitsLoader.load_units(_loader, FIXTURE)
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_worst_region_arrives_first()
	_test_one_a_month_and_none_again_within_a_year()
	_test_a_region_ahead_never_warns()
	_test_nothing_in_band_nothing_arrives()
	_test_the_warning_ends_the_quiet_month()
	_test_a_build_that_closes_the_gap_leaves_the_band()
	_test_the_stamps_survive_a_save()
	_test_a_nation_with_no_stock_gets_none()
	_finish()


func _state(nation := "FRA"):
	var state = GameState.new_game(_loader, nation)
	state.year = 2026
	state.month = 1
	return state


## How far the region's shown figure stands behind the nation's, as a share of it,
## + when worse, computed here from the figures the screen shows (not through UnitWarnings).
func _behind(ns, type_id: String, region: String) -> float:
	var sign := 1.0 if String(_loader.unit_types[type_id]["figure"]["better"]) == "lower" else -1.0
	return sign * (Units.shown_figure(ns, _loader, type_id, region) / Units.national_figure(ns, _loader, type_id) - 1.0)


func _warnings(notes: Array) -> Array:
	var out: Array = []
	for n in notes:
		if String(n.get("kind", "")) == KIND:
			out.append(n)
	return out


func _tick(state) -> Array:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	return _warnings(UnitBuild.tick_month(state, _loader))


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _test_the_worst_region_arrives_first() -> void:
	var state = _state()
	var ns = state.player()
	var worst := -INF
	var expected := ""
	var types: Array = _loader.unit_types.keys()
	types.sort()
	for type_id in types:
		for r in _loader.regions[ns.id]:
			if Units.start_capacity(_loader, ns.id, type_id, r.id) <= 0.0:
				continue
			var b := _behind(ns, type_id, r.id)
			if b > worst:
				worst = b
				expected = "%s|%s" % [type_id, r.id]
	var got := _tick(state)
	if got.size() != 1:
		_fail("the first month brings %d warnings, not one: %s" % [got.size(), got])
		return
	var w: Dictionary = got[0]
	if "%s|%s" % [w["type"], w["region"]] != expected:
		_fail("the first warning is %s|%s, not the worst region %s (%.4f behind)" % [w["type"], w["region"], expected, worst])
	var type_id := String(w["type"])
	if absf(float(w["figure"]) - Units.shown_figure(ns, _loader, type_id, String(w["region"]))) > 1e-9 \
			or absf(float(w["national"]) - Units.national_figure(ns, _loader, type_id)) > 1e-9:
		_fail("the warning's figures are not the screen's: %s" % [w])
	if not UnitWarnings.in_band(ns, _loader, type_id, String(w["region"])):
		_fail("the warned region is not in the band")


func _test_one_a_month_and_none_again_within_a_year() -> void:
	var state = _state()
	var last := {}
	var count := 0
	for i in 36:
		var got := _tick(state)
		if got.size() > 1:
			_fail("month %d brings %d warnings" % [i, got.size()])
		for w in got:
			count += 1
			var key := "%s|%s" % [w["type"], w["region"]]
			if last.has(key) and _now(state) - int(last[key]) < UK.UNIT_WARN_REARM_MONTHS:
				_fail("%s warned again after %d months" % [key, _now(state) - int(last[key])])
			last[key] = _now(state)
	if count < 2:
		_fail("three years bring %d warnings: the band never re-arms" % count)


func _test_a_region_ahead_never_warns() -> void:
	var state = _state()
	var ns = state.player()
	for i in 36:
		for w in _tick(state):
			if _behind(ns, String(w["type"]), String(w["region"])) <= 0.0:
				_fail("%s warned while ahead of the nation" % [w])


## Every region behind the nation was warned this year: the regions left are ahead or
## level, out of the band, and the month brings nothing rather than the least bad of them.
func _test_nothing_in_band_nothing_arrives() -> void:
	var state = _state()
	var ns = state.player()
	var stamped := 0
	for type_id in _loader.unit_types:
		for r in _loader.regions[ns.id]:
			if _behind(ns, type_id, r.id) > 0.0:
				ns.unit_warned["%s|%s" % [type_id, r.id]] = _now(state)
				stamped += 1
	if stamped == 0:
		_fail("the fixture has no region behind the nation")
	var got := _tick(state)
	if not got.is_empty():
		_fail("a month with no region in band brings %s" % [got])


func _test_the_warning_ends_the_quiet_month() -> void:
	var state = _state()
	var ns = state.player()
	ns.in_government = true
	if _tick(state).is_empty():
		_fail("no warning to test the quiet month with")
		return
	var stamps: Dictionary = ns.unit_warned.duplicate()
	if QuietMonth.quiet(state, ns, _loader, _now(state)):
		_fail("a regional warning leaves the month quiet")
	ns.unit_warned = {}
	if not QuietMonth.quiet(state, ns, _loader, _now(state)):
		_fail("the fixture month is not quiet without the warning: the test reads nothing")
	ns.unit_warned = stamps


func _test_a_build_that_closes_the_gap_leaves_the_band() -> void:
	var state = _state()
	var ns = state.player()
	var got := _tick(state)
	if got.is_empty():
		_fail("no warning to build against")
		return
	var type_id := String(got[0]["type"])
	var region := String(got[0]["region"])
	# A unit is one tenth of the region's stock in the fixture: three lift it past the nation.
	ns.unit_programmes.append({"id": "%s:1" % type_id, "type": type_id, "op": UK.OP_BUILD,
		"state": UK.STATE_DONE, "rows": [{"region": region, "units": 3}]})
	if _behind(ns, type_id, region) > 0.0:
		_fail("the fixture build does not close the gap (%.4f)" % _behind(ns, type_id, region))
	if UnitWarnings.in_band(ns, _loader, type_id, region):
		_fail("a region built past the nation is still in the band")


func _test_the_stamps_survive_a_save() -> void:
	var state = _state()
	var ns = state.player()
	_tick(state)
	if ns.unit_warned.is_empty():
		_fail("no stamp to save")
		return
	var back = ns.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	if back.unit_warned != ns.unit_warned:
		_fail("the stamps do not survive a save: %s vs %s" % [back.unit_warned, ns.unit_warned])
	var d: Dictionary = ns.to_dict()
	d.erase("unit_warned")
	if not ns.from_dict(d).unit_warned.is_empty():
		_fail("an older save without stamps does not read as nothing warned")


func _test_a_nation_with_no_stock_gets_none() -> void:
	var state = _state("DEU")
	for i in 3:
		if not _tick(state).is_empty():
			_fail("a nation with no stock file is warned")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_unit_warnings: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)
