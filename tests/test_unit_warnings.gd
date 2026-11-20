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
const EventDraw = preload("res://src/sim/event_draw.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")

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
	_test_the_band_is_the_worst_few()
	_test_the_fourth_worst_waits()
	_test_the_band_needs_the_gap()
	_test_the_answers_are_the_registers_numbers()
	_test_warned_again_after_exactly_a_year()
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
	if not Units.in_band(ns, _loader, type_id, String(w["region"])):
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
				ns.unit_warned["%s|%s" % [type_id, r.id]] = {"month": _now(state), "differs": true}
				stamped += 1
	if stamped == 0:
		_fail("the fixture has no region behind the nation")
	var got := _tick(state)
	if not got.is_empty():
		_fail("a month with no region in band brings %s" % [got])


## The rank rule (the parent's ruling, call 1): a region is in band when it is among the
## nation's UNIT_REGION_WORST worst for the type AND at least UNIT_REGION_BAND behind. The
## fixture holds six or seven tied bad regions a type: ties go to the regions' file order.
func _test_the_band_is_the_worst_few() -> void:
	var state = _state()
	var ns = state.player()
	for type_id in _loader.unit_types:
		var bad: Array = []
		var inside: Array = []
		for r in _loader.regions[ns.id]:
			if _behind(ns, type_id, r.id) >= UK.UNIT_REGION_BAND:
				bad.append(r.id)
			if Units.in_band(ns, _loader, type_id, r.id):
				inside.append(r.id)
		if bad.size() <= UK.UNIT_REGION_WORST:
			_fail("the fixture has %d regions behind for %s: the rank is not tested" % [bad.size(), type_id])
		if inside != bad.slice(0, UK.UNIT_REGION_WORST):
			_fail("%s in band: %s, not the first %d of %s" % [type_id, inside, UK.UNIT_REGION_WORST, bad])
	if Units.in_band(ns, _loader, "no_such_type", "FR1"):
		_fail("an unknown type is in band")


## Built past the nation everywhere but one bad region: the band holds that one alone, not
## the next-worst regions that stand ahead of the nation (the UNIT_REGION_BAND floor).
func _test_the_band_needs_the_gap() -> void:
	var state = _state()
	var ns = state.player()
	var type_id := "fixture_school"
	var bad: Array = []
	for r in _loader.regions[ns.id]:
		if _behind(ns, type_id, r.id) >= UK.UNIT_REGION_BAND:
			bad.append(r.id)
	var rows: Array = []
	for id in bad.slice(1):
		rows.append({"region": id, "units": 3})
	ns.unit_programmes.append({"id": "%s:1" % type_id, "type": type_id, "op": UK.OP_BUILD,
		"state": UK.STATE_DONE, "rows": rows})
	var band := Units.band(ns, _loader, type_id)
	if band.keys() != [bad[0]]:
		_fail("with one region left behind the band is %s, not [%s]" % [band, bad[0]])


## The few in band warned this year, the month brings nothing, though a fourth region
## stands as far behind: it is not among the worst few.
func _test_the_fourth_worst_waits() -> void:
	var state = _state()
	var ns = state.player()
	for type_id in _loader.unit_types:
		for r in _loader.regions[ns.id]:
			if Units.in_band(ns, _loader, type_id, r.id):
				ns.unit_warned["%s|%s" % [type_id, r.id]] = {"month": _now(state), "differs": true}
	var got := _tick(state)
	if not got.is_empty():
		_fail("a region outside the worst few is warned: %s" % [got])


## Re-armed at exactly UNIT_WARN_REARM_MONTHS, not a month before.
func _test_warned_again_after_exactly_a_year() -> void:
	var state = _state()
	var ns = state.player()
	var first := _tick(state)
	if first.is_empty():
		_fail("no first warning")
		return
	var key := "%s|%s" % [first[0]["type"], first[0]["region"]]
	var at := _now(state)
	# Every other region in band was warned just now: only the first can come back.
	for type_id in _loader.unit_types:
		for r in _loader.regions[ns.id]:
			var other := "%s|%s" % [type_id, r.id]
			if other != key:
				ns.unit_warned[other] = {"month": at + UK.UNIT_WARN_REARM_MONTHS, "differs": true}
	while _now(state) < at + UK.UNIT_WARN_REARM_MONTHS - 2:
		_tick(state)
	if not _tick(state).is_empty():
		_fail("warned again %d months after" % (_now(state) - at))
	var again := _tick(state)
	if again.size() != 1 or "%s|%s" % [again[0]["type"], again[0]["region"]] != key:
		_fail("not warned again at exactly %d months: %s" % [UK.UNIT_WARN_REARM_MONTHS, again])


func _test_the_warning_ends_the_quiet_month() -> void:
	var state = _state()
	var ns = state.player()
	ns.in_government = true
	if _tick(state).is_empty():
		_fail("no warning to test the quiet month with")
		return
	var key: String = ns.unit_warned.keys()[0]
	var parts := key.split("|")
	# The stamp is QuietMonth's filter over the warning's own answers, as for any arrival.
	var decides := EventDraw.answers_differ(ns, UnitWarnings.answers(state, ns, _loader, parts[0], parts[1]))
	if bool(ns.unit_warned[key]["differs"]) != decides:
		_fail("the stamp says differs %s, its answers say %s" % [ns.unit_warned[key]["differs"], decides])
	ns.unit_warned[key]["differs"] = true
	if QuietMonth.quiet(state, ns, _loader, _now(state)):
		_fail("a regional warning that is a decision leaves the month quiet")
	ns.unit_warned[key]["differs"] = false
	if not QuietMonth.quiet(state, ns, _loader, _now(state)):
		_fail("a regional warning that is no decision ends the quiet month")
	ns.unit_warned = {}
	if not QuietMonth.quiet(state, ns, _loader, _now(state)):
		_fail("the fixture month is not quiet without the warning: the test reads nothing")


## The build answer: the band's units there, the estimate as debt, the running cost a year
## on the line, the vote's blocs; leaving it is nothing. A build big enough on money decides.
func _test_the_answers_are_the_registers_numbers() -> void:
	var state = _state()
	var ns = state.player()
	var type_id := "fixture_hospital"
	var t: Dictionary = _loader.unit_types[type_id]
	var a := UnitWarnings.answers(state, ns, _loader, type_id, "FR1")
	var row := {"type": type_id, "op": UK.OP_BUILD, "rows": [{"region": "FR1", "units": int(t["band_units"])}]}
	if a.size() != 2 or not (a[0] as Dictionary).is_empty():
		_fail("the answers are not leave, build: %s" % [a])
		return
	if absf(float(a[1]["debt_eur_bn"]) - float(UnitPrice.quote(state, ns, _loader, row)["estimate_eur_m"]) / 1000.0) > 1e-12:
		_fail("the build's debt is not the quote's estimate: %s" % [a[1]])
	var running := 100.0 * float(t["band_units"]) * float(t["running_eur_m"]["FRA"]) / (float(ns.gdp_eur_bn) * 1000.0)
	if absf(float(a[1]["spending_pct_gdp"][String(t["line"])]) - running) > 1e-12:
		_fail("the build's running cost is not the band's units' on the line: %s" % [a[1]])
	if a[1]["bloc_offset"] != UnitBuild.blocs(ns, _loader, row):
		_fail("the build's blocs are not the vote's: %s" % [a[1]])


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
	if Units.in_band(ns, _loader, type_id, region):
		_fail("a region built past the nation is still in the band")


func _test_the_stamps_survive_a_save() -> void:
	var state = _state()
	var ns = state.player()
	_tick(state)
	if ns.unit_warned.is_empty():
		_fail("no stamp to save")
		return
	var back = ns.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	for key in ns.unit_warned:
		var was: Dictionary = ns.unit_warned[key]
		var now: Dictionary = back.unit_warned.get(key, {})
		# A JSON round trip reads numbers back as floats: compared as the readers read them.
		if int(now.get("month", -1)) != int(was["month"]) or bool(now.get("differs", not was["differs"])) != bool(was["differs"]):
			_fail("the stamp %s does not survive a save: %s vs %s" % [key, now, was])
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
