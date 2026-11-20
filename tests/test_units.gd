extends SceneTree

## V5.3 c' slice A (docs/design/v5.3-c-register.md sections 2, 3 and 8): the
## construction register's data and reads. A catalogue of unit types
## (data/units/<type>.json), a start stock and a regional level per nation
## (data/units/stock/<NAT>.json), the Union's co-financing rule
## (data/units/cofinancing.json), the five projects re-expressed as `potential`
## rows built at load from data/project-actions (one source, no copy: the
## parent's ruling, 2026-11-17), and what a region shows once units stand.
##
## Content's real data lands on its own branch; this file reads the fixture under
## tests/fixtures/units/, whose numbers are round and say so, never a source.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const UnitsLoader = preload("res://src/core/loaders/units_loader.gd")
const Units = preload("res://src/sim/units.gd")
const UK = preload("res://src/sim/units_constants.gd")
const Sectors = preload("res://src/sim/sectors.gd")
const Region = preload("res://src/core/region.gd")
const ProjectAction = preload("res://src/core/project_action.gd")
const RK = preload("res://src/sim/region_constants.gd")

const FIXTURE := "res://tests/fixtures/units"
const TYPE := "fixture_school"
const HOSPITAL := "fixture_hospital"

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_shipped_tree_offers_nothing_until_content_lands()
	_test_the_projects_are_potential_rows()
	UnitsLoader.load_units(_loader, FIXTURE)
	if not _loader.errors.is_empty():
		_failures.append("the fixture did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_fixture_loads()
	_test_a_type_is_offered_only_where_a_stock_file_has_it()
	_test_the_member_warning_reads_the_fixture()
	_test_the_level_is_normalised_to_the_people()
	_test_bad_rows_are_refused()
	_test_cohesion_category_is_read_and_checked()
	_test_nothing_built_reads_the_nation_times_the_level()
	_test_a_built_unit_lifts_its_region_and_the_nation_holds()
	_test_a_closed_unit_reverses_a_built_one()
	_test_a_region_with_no_stock_gains_nothing()
	_test_fill_by_population()
	_test_fill_by_need_starts_with_the_worst()
	_test_fill_by_need_reads_one_basis_a_step()
	_test_the_preview_reads_units_not_yet_built()
	_test_a_higher_is_better_figure()
	_test_the_register_is_saved()
	_finish()


func _state():
	return GameState.new_game(_loader, "FRA")


func _named(state) -> Array:
	var out: Array = []
	for r in state.regions.get("FRA", []):
		if r.id != RK.RESIDUAL_KEY:
			out.append(String(r.id))
	return out


## No data/units/ in the tree yet: a missing directory is no type at all, never an
## error, and so the game reads exactly what it read before c' (band U1).
func _test_the_shipped_tree_offers_nothing_until_content_lands() -> void:
	if not _loader.unit_types.is_empty() and not DirAccess.dir_exists_absolute("res://data/units"):
		_fail("no data/units/ yet the loader holds %d types" % _loader.unit_types.size())
	if not DirAccess.dir_exists_absolute("res://data/units") and Units.offered(_loader, "FRA", TYPE):
		_fail("a type is offered with no data/units/")


## Section 8: each project is a catalogue row of payoff `potential`, quantity 1,
## its own build months, cost and payoff, no range width and no overrun odds.
func _test_the_projects_are_potential_rows() -> void:
	var starts := 0
	for action in _loader.project_actions:
		if String(action.effects["project"].get("op", "")) != "start":
			continue
		starts += 1
		var terms: Dictionary = action.effects["project"]
		var row: Dictionary = Units.row(_loader, String(terms["project_id"]))
		if row.is_empty():
			_fail("project %s has no potential row" % terms["project_id"])
			continue
		if String(row["payoff"]) != UK.PAYOFF_POTENTIAL or int(row["quantity"]) != 1 \
				or int(row["build_months"]) != int(terms["build_months"]) \
				or float(row["cost_pct_gdp"]) != float(terms["cost_pct_gdp"]) \
				or float(row["potential_growth_pct"]) != float(terms["potential_growth_pct"]) \
				or float(row["range_width"]) != 0.0 or float(row["overrun_odds"]) != 0.0:
			_fail("project %s's potential row is not its own terms: %s" % [terms["project_id"], row])
		if String(row["name"]) != String(terms["project_name"]):
			_fail("project %s's potential row is named '%s'" % [terms["project_id"], row["name"]])
	var potential := 0
	for row in Units.catalogue(_loader):
		if String(row["payoff"]) == UK.PAYOFF_POTENTIAL:
			potential += 1
	if not Units.row(_loader, "no_such_type").is_empty():
		_fail("an unknown id reads a row")
	if starts == 0 or potential != starts:
		_fail("%d projects, %d potential rows" % [starts, potential])
	var broken = ProjectAction.new()
	broken.effects = {"project": {"op": "start", "project_id": "broken", "build_months": "soon"}}
	var unpaid = ProjectAction.new()
	unpaid.effects = {"project": {"op": "start", "project_id": "unpaid", "build_months": 24, "cost_pct_gdp": 0.1}}
	var rows: Array = UnitsLoader.potential_rows([broken, unpaid] + Array(_loader.project_actions))
	if rows.size() != starts:
		_fail("a refused project action is read as a potential row: %d rows" % rows.size())


func _test_the_fixture_loads() -> void:
	var row: Dictionary = Units.row(_loader, TYPE)
	if row.is_empty() or String(row["payoff"]) != UK.PAYOFF_CAPACITY or Units.unit_capacity(_loader, "FRA", TYPE) != 1000.0:
		_fail("the fixture type did not load: %s" % row)
	if float(Units.start_capacity(_loader, "FRA", TYPE, "FR1")) != 10000.0 or Units.start_units(_loader, "FRA", TYPE, "FR1") != 10:
		_fail("FR1's start stock reads %s capacity, %d units" % [Units.start_capacity(_loader, "FRA", TYPE, "FR1"), Units.start_units(_loader, "FRA", TYPE, "FR1")])
	if float(_loader.unit_national["FRA"][TYPE]) <= 0.0:
		_fail("the type's national figure did not load")
	var rule: Dictionary = _loader.unit_cofinancing.get("eu", {})
	# The fixture carries `_` labels at every level (Content's stand-in notes): read past, kept out.
	if float(rule.get("rates", {}).get("transition", 0.0)) != 0.6 or (rule.get("periods", []) as Array).size() != 1 \
			or (rule["rates"] as Dictionary).has("_note") or (rule["periods"][0]["envelope_eur_bn"] as Dictionary).has("_note"):
		_fail("the co-financing rule did not load: %s" % rule)
	# One type per figure (section 3): a second type answering a taken figure is refused.
	var dup = DataLoader.new()
	dup.load_all()
	UnitsLoader.load_units(dup, "res://tests/fixtures/units_dup")
	var refused := false
	for e in dup.errors:
		if String(e).contains("is already answered by type"):
			refused = true
	if not refused or dup.unit_types.size() != 1:
		_fail("two types answering one figure both load: %s" % [dup.errors])


## The member warning (the parent's ruling on #409; T1 and T6 on #410): one line for a
## member nation WITH a stock file whose regions all lack a category, none once one
## region has one, none for a member with no stock file. The categories are set here,
## never read from data/regions, so the day the real ones land changes nothing.
func _test_the_member_warning_reads_the_fixture() -> void:
	var held := {}
	for nation_id in ["FRA", "DEU"]:
		for r in _loader.regions[nation_id]:
			held[r] = r.cohesion_category
			r.cohesion_category = ""
	UnitsLoader.warn_uncategorised(_loader)
	var lines: Array = _loader.unit_warnings.duplicate()
	_loader.regions["FRA"][0].cohesion_category = "transition"
	UnitsLoader.warn_uncategorised(_loader)
	var after: Array = _loader.unit_warnings.duplicate()
	for r in held:
		r.cohesion_category = held[r]
	var fra := 0
	for line in lines:
		if String(line).contains(" FRA is a member"):
			fra += 1
		if String(line).contains(" DEU is a member"):
			_fail("a member with no stock file warns: %s" % line)
	if fra != 1:
		_fail("France warns %d times with no category, not once: %s" % [fra, lines])
	for line in after:
		if String(line).contains(" FRA is a member"):
			_fail("France warns with one region categorised: %s" % line)


func _test_a_type_is_offered_only_where_a_stock_file_has_it() -> void:
	if not Units.offered(_loader, "FRA", TYPE):
		_fail("France has a stock file for the type and is not offered it")
	if Units.offered(_loader, "GBR", TYPE):
		_fail("Britain has no stock file and is offered the type")
	if Units.offered(_loader, "FRA", "high_speed_rail"):
		_fail("a potential row is offered as a unit type")




func _test_the_level_is_normalised_to_the_people() -> void:
	var state = _state()
	var ns = state.player()
	if absf(_people_mean(state, ns, "level") - 1.0) > 1e-12:
		_fail("the population-weighted level is %.12f, not 1" % _people_mean(state, ns, "level"))
	if Units.level(ns, _loader, TYPE, "FRB") <= Units.level(ns, _loader, TYPE, "FR1"):
		_fail("FRB's 20 pupils should read above FR1's 15")
	# Live shares: migration moves the people, the basis follows.
	ns.region_pop_share["FR1"] = float(ns.region_pop_share["FR1"]) * 1.3
	if absf(_people_mean(state, ns, "level") - 1.0) > 1e-12:
		_fail("after a move of people the weighted level is %.12f, not 1" % _people_mean(state, ns, "level"))
	# A priority on the sector, units built: the shown figure's people-weighted mean is
	# the type's national figure.
	Sectors.set_priority(state, ns, _loader, "education", "schools", "FRB")
	ns.unit_programmes.assign([_done("p1", UK.OP_BUILD, "FR1", 2), _done("p2", UK.OP_BUILD, "FRC", 1)])
	var nation := Units.national_figure(ns, _loader, TYPE)
	if absf(_people_mean(state, ns, "shown") - nation) > 1e-12 * nation:
		_fail("with a priority and units the regions' mean is %.12f, not the national %.12f" % [_people_mean(state, ns, "shown"), nation])
	# At the floor: a region that closed all it held. The floor is in f, before the mean.
	ns.unit_programmes.assign([_done("p3", UK.OP_DEMOLISH, "FR1", 10000)])
	if absf(Units.factor(ns, _loader, TYPE, "FR1") - pow(0.01, -1.0)) > 1e-9:
		_fail("a region that closed all it held reads f = %.6f" % Units.factor(ns, _loader, TYPE, "FR1"))
	if absf(_people_mean(state, ns, "shown") - nation) > 1e-12 * nation:
		_fail("at the floor the regions' mean is %.12f, not the national %.12f" % [_people_mean(state, ns, "shown"), nation])
	# A nation the type is not offered to reads level 1.
	var gbr = GameState.new_game(_loader, "GBR").player()
	if Units.level(gbr, _loader, TYPE, "UKI") != 1.0:
		_fail("a region with no level row reads %s, not 1" % Units.level(gbr, _loader, TYPE, "UKI"))


func _people_mean(state, ns, what: String) -> float:
	var weighted := 0.0
	var people := 0.0
	for region in _named(state):
		var p := float(ns.region_pop_share[region])
		var v: float
		if what == "level":
			v = Units.level(ns, _loader, TYPE, region) * Sectors.regional_quantity(ns, _loader, "education", "schools", region) \
				/ Sectors.quantity(ns, _loader, "education", "schools")
		else:
			v = Units.shown_figure(ns, _loader, TYPE, region)
		weighted += p * v
		people += p
	return weighted / people


func _test_bad_rows_are_refused() -> void:
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE.path_join(TYPE + ".json")))
	var errors: Array[String] = []
	if UnitsLoader.parse_type(_loader, good, TYPE + ".json", errors).is_empty() or not errors.is_empty():
		_fail("the good fixture row is refused: %s" % [errors])
	for case in [["capacity", {"FRA": 0}], ["capacity", 1000], ["sector", "nowhere"], ["figure", "pupils"],
			["figure", {"id": "x", "unit": "u", "better": "middle"}],
			["payoff", "network"], ["overrun_odds", 1.5], ["figure_elasticity", 1.0], ["cost_eur_m", {"FRA": -1}], ["cost_eur_m", {"FRA": {"x": 1}}], ["cost_eur_m", {"FRA": 0}],
			["build_months", 0], ["build_months", 12.5], ["id", "other_school"], ["cofinanced", "yes"], ["bloc_offset_per_pop_share", {"nobody": 1.0}]]:
		var bad := good.duplicate(true)
		bad[case[0]] = case[1]
		errors = []
		if not UnitsLoader.parse_type(_loader, bad, TYPE + ".json", errors).is_empty() or errors.is_empty():
			_fail("a row with %s = %s is accepted" % [case[0], case[1]])
	var missing := good.duplicate(true)
	missing.erase("running_eur_m")
	errors = []
	if not UnitsLoader.parse_type(_loader, missing, TYPE + ".json", errors).is_empty():
		_fail("a row without running_eur_m is accepted")
	var types := {TYPE: good}
	var full: Array = []
	for r in _loader.regions["FRA"]:
		full.append({"region": r.id, "level": 15.0})
	var fig := {"figure": "fixture_pupils_per_teacher", "national": 15.0, "levels": full}
	var one := [{"region": "FR1", "type": TYPE, "units": 1, "capacity": 10}]
	var fine := {"stock": one, "figures": {TYPE: fig}}
	errors = []
	UnitsLoader.parse_stock(_loader, "FRA", fine, types, "stock/FRA.json", errors)
	if not errors.is_empty():
		_fail("a good stock file is refused: %s" % [errors])
	var with_level := func(extra: Array, national: float) -> Dictionary:
		return {"stock": one, "figures": {TYPE: {"figure": "fixture_pupils_per_teacher", "national": national, "levels": full + extra}}}
	for stock in [
			{"stock": [{"region": "UKI", "type": TYPE, "units": 1, "capacity": 10}], "figures": {TYPE: fig}},
			{"stock": [{"region": "FR1", "type": "nothing", "units": 1, "capacity": 10}], "figures": {TYPE: fig}},
			{"stock": [{"region": "FR1", "type": TYPE, "units": -1, "capacity": 10}], "figures": {TYPE: fig}},
			{"stock": one + one, "figures": {TYPE: fig}},
			{"stock": one, "figures": {}},
			{"stock": one, "figures": {TYPE: {"figure": "pupils_per_teacher", "national": 15.0, "levels": full}}},
			with_level.call([{"region": "FRB", "level": 0.0}], 15.0),
			with_level.call([{"region": "FRB", "level": 16.0}], 15.0),
			with_level.call([], 16.0),
			{"stock": one, "figures": {TYPE: {"figure": "fixture_pupils_per_teacher", "national": 15.0,
				"levels": [{"region": "FR1", "level": 15.0}]}}}]:
		errors = []
		UnitsLoader.parse_stock(_loader, "FRA", stock, types, "stock/FRA.json", errors)
		if errors.is_empty():
			_fail("a bad stock file is accepted: %s" % stock)
	# Within the tolerance a national a little off the weighted levels loads.
	errors = []
	UnitsLoader.parse_stock(_loader, "FRA", with_level.call([], 15.3), types, "stock/FRA.json", errors)
	if not errors.is_empty():
		_fail("a national 2 %% off the levels is refused: %s" % [errors])
	var unpriced := good.duplicate(true)
	unpriced["cost_eur_m"] = {"DEU": 50.0}
	errors = []
	UnitsLoader.parse_stock(_loader, "FRA", fine, {TYPE: unpriced}, "stock/FRA.json", errors)
	if errors.is_empty():
		_fail("a stocked type with no price for the nation is accepted")
	var unsized := good.duplicate(true)
	unsized["capacity"] = {"DEU": 1000}
	errors = []
	UnitsLoader.parse_stock(_loader, "FRA", fine, {TYPE: unsized}, "stock/FRA.json", errors)
	if errors.is_empty():
		_fail("a stocked type with no capacity for the nation is accepted")
	# The fixture's own file must be put back: parse_stock writes the loader's registers.
	UnitsLoader.load_units(_loader, FIXTURE)


func _test_cohesion_category_is_read_and_checked() -> void:
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/regions/FRA.json"))["regions"][0]
	base.erase("cohesion_category")
	var errors: Array[String] = []
	var r = Region.from_dict(base, 0, "test", errors)
	if r.cohesion_category != "":
		_fail("a region without the field reads category '%s'" % r.cohesion_category)
	var with := base.duplicate(true)
	with["cohesion_category"] = "transition"
	errors = []
	r = Region.from_dict(with, 0, "test", errors)
	if not errors.is_empty() or r.cohesion_category != "transition":
		_fail("a transition region reads '%s' (%s)" % [r.cohesion_category, errors])
	with["cohesion_category"] = "rich"
	errors = []
	Region.from_dict(with, 0, "test", errors)
	if errors.is_empty():
		_fail("an unknown cohesion category is accepted")


func _test_nothing_built_reads_the_nation_times_the_level() -> void:
	var state = _state()
	var ns = state.player()
	var nation := Units.national_figure(ns, _loader, TYPE)
	if nation != float(_loader.unit_national["FRA"][TYPE]):
		_fail("at the start the type's national figure is %.6f, not its stock file's %.6f" % [nation, _loader.unit_national["FRA"][TYPE]])
	for region in _named(state):
		var want: float = nation * Units.level(ns, _loader, TYPE, region)
		if Units.netted_factor(ns, _loader, TYPE, region) != 1.0 or Units.shown_figure(ns, _loader, TYPE, region) != want:
			_fail("%s shows %.6f with nothing built, not %.6f" % [region, Units.shown_figure(ns, _loader, TYPE, region), want])
	# The type rides the sector's path: more money on the line moves its national figure.
	ns.spending_pct_gdp["education"] = float(ns.spending_pct_gdp["education"]) * 1.1
	if Units.national_figure(ns, _loader, TYPE) >= nation:
		_fail("more money on education did not lower the type's pupils per teacher")




func _test_a_built_unit_lifts_its_region_and_the_nation_holds() -> void:
	var state = _state()
	var ns = state.player()
	var before := Units.shown_figure(ns, _loader, TYPE, "FR1")
	var other_before := Units.shown_figure(ns, _loader, TYPE, "FRB")
	ns.unit_programmes.assign([_done("p1", UK.OP_BUILD, "FR1", 2)])
	if Units.capacity_delta(ns, _loader, TYPE, "FR1") != 2000.0:
		_fail("two units of 1000 pupils add %s capacity" % Units.capacity_delta(ns, _loader, TYPE, "FR1"))
	if absf(Units.factor(ns, _loader, TYPE, "FR1") - 1.0 / 1.2) > 1e-12:
		_fail("2000 pupils' capacity on 10000 gives f = %.6f, not 1/1.2" % Units.factor(ns, _loader, TYPE, "FR1"))
	if Units.shown_figure(ns, _loader, TYPE, "FR1") >= before:
		_fail("FR1's pupils per teacher did not fall: %.4f -> %.4f" % [before, Units.shown_figure(ns, _loader, TYPE, "FR1")])
	if Units.shown_figure(ns, _loader, TYPE, "FRB") <= other_before:
		_fail("FRB did not give a little back: %.4f -> %.4f" % [other_before, Units.shown_figure(ns, _loader, TYPE, "FRB")])
	var nation := Units.national_figure(ns, _loader, TYPE)
	if absf(_people_mean(state, ns, "shown") - nation) > 1e-12 * nation:
		_fail("the regions' weighted mean is %.12f, not the national %.12f" % [_people_mean(state, ns, "shown"), nation])
	if Units.shown_figure(ns, _loader, "high_speed_rail", "FR1") != 0.0:
		_fail("a project's potential row reads a regional figure")
	# A unit still building moves nothing.
	ns.unit_programmes.assign([_row("p2", UK.OP_BUILD, UK.STATE_BUILDING, "FR1", 2)])
	if Units.factor(ns, _loader, TYPE, "FR1") != 1.0:
		_fail("a building unit already lifts its region")


func _test_a_closed_unit_reverses_a_built_one() -> void:
	var state = _state()
	var ns = state.player()
	# A closure is entered in capacity (section 7): 2000 pupils closed undoes two schools.
	ns.unit_programmes.assign([_done("p1", UK.OP_BUILD, "FR1", 2), _done("p2", UK.OP_DEMOLISH, "FR1", 2000)])
	if Units.capacity_delta(ns, _loader, TYPE, "FR1") != 0.0 or Units.factor(ns, _loader, TYPE, "FR1") != 1.0:
		_fail("two schools built and 2000 pupils closed net %s" % Units.capacity_delta(ns, _loader, TYPE, "FR1"))
	ns.unit_programmes.assign([_done("p2", UK.OP_DEMOLISH, "FR1", 3000)])
	if Units.factor(ns, _loader, TYPE, "FR1") <= 1.0:
		_fail("closing 3000 pupils did not raise FR1's pupils per teacher")


func _test_a_region_with_no_stock_gains_nothing() -> void:
	var state = _state()
	var ns = state.player()
	ns.unit_programmes.assign([_done("p1", UK.OP_BUILD, "FRM", 1)])
	if Units.factor(ns, _loader, TYPE, "FRM") != 1.0:
		_fail("a region with no stock row reads f = %.4f" % Units.factor(ns, _loader, TYPE, "FRM"))
	if Units.start_capacity(_loader, "FRA", TYPE, "FRM") != 0.0:
		_fail("FRM reads a start capacity with no stock row")


func _test_fill_by_population() -> void:
	var state = _state()
	var ns = state.player()
	var rows: Array = Units.fill_by_population(ns, _loader, TYPE, 20)
	var total := 0
	var biggest := ""
	var most := -1
	for row in rows:
		total += int(row["units"])
		if String(row["region"]) == "FRM":
			_fail("a region with no stock is filled")
		if int(row["units"]) > most:
			most = int(row["units"])
			biggest = String(row["region"])
	if total != 20:
		_fail("by population places %d units, not 20" % total)
	if biggest != "FR1":
		_fail("by population puts the most units in %s, not FR1 (the most people)" % biggest)
	# Two units: the largest remainders, FR1's and FRK's (the second most people).
	if not Units.fill_by_population(ns, _loader, TYPE, -3).is_empty() or not Units.fill_by_need(ns, _loader, TYPE, 0).is_empty():
		_fail("a fill of no units places some")
	# Equal shares: ties go to file order (T12), the first region first.
	var held: Dictionary = ns.region_pop_share.duplicate()
	for region in ns.region_pop_share:
		ns.region_pop_share[region] = 0.1
	var tie: Array = Units.fill_by_population(ns, _loader, TYPE, 1)
	if tie != [{"region": "FR1", "units": 1}]:
		_fail("a tie does not go to the first region in file order: %s" % [tie])
	# Shares summing to 0 (T13): all N placed, never short.
	for region in ns.region_pop_share:
		ns.region_pop_share[region] = 0.0
	var none := 0
	for row in Units.fill_by_population(ns, _loader, TYPE, 30):
		none += int(row["units"])
	if none != 30:
		_fail("with no people counted, by population places %d units, not 30" % none)
	ns.region_pop_share = held
	var two: Array = Units.fill_by_population(ns, _loader, TYPE, 2)
	if two != [{"region": "FR1", "units": 1}, {"region": "FRK", "units": 1}]:
		_fail("by population places two units as %s, not one in FR1 and one in FRK" % [two])


## "By need fills the regions whose shown figure is furthest behind the nation's,
## in that order": a pupils-per-teacher row is behind when it reads HIGHER.
func _test_fill_by_need_starts_with_the_worst() -> void:
	var state = _state()
	var ns = state.player()
	var rows: Array = Units.fill_by_need(ns, _loader, TYPE, 1)
	if rows.size() != 1 or int(rows[0]["units"]) != 1:
		_fail("by need for one unit gives %s" % [rows])
		return
	var placed := String(rows[0]["region"])
	var worst := ""
	var top := -INF
	for region in _named(state):
		if Units.start_capacity(_loader, "FRA", TYPE, region) <= 0.0:
			continue
		var f := Units.shown_figure(ns, _loader, TYPE, region)
		if f > top:
			top = f
			worst = region
	if placed != worst:
		_fail("by need puts its first unit in %s, not the worst region %s" % [placed, worst])
	var many: Array = Units.fill_by_need(ns, _loader, TYPE, 30)
	var total := 0
	for row in many:
		total += int(row["units"])
		if String(row["region"]) == "FRM":
			_fail("by need fills a region with no stock")
	if total != 30:
		_fail("by need places %d units, not 30" % total)
	# Each placed unit counts (T14): thirty units do not all land in one region.
	if many.size() < 2:
		_fail("by need puts all thirty units in one region: %s" % [many])



## QA TAKE on #420: the register refills by need on every count change, and at 200 units
## the fill froze the game 1-2 s, rebuilding the whole basis for every candidate region of
## every step. Every candidate of one step reads the SAME placed units, so one basis a step
## gives the same rows: pinned against the per-candidate fill, and at least 3x faster (a
## ratio on this machine, not a wall-clock bound; the old cost is about the region count).
func _test_fill_by_need_reads_one_basis_a_step() -> void:
	var state = _state()
	var ns = state.player()
	var n := 60
	var t0 := Time.get_ticks_usec()
	var rows: Array = Units.fill_by_need(ns, _loader, TYPE, n)
	var fast := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var want := _fill_per_candidate(ns, TYPE, n)
	var slow := Time.get_ticks_usec() - t0
	if rows != want:
		_fail("by need with one basis a step gives %s, the per-candidate fill %s" % [rows, want])
	if fast * 3 > slow:
		_fail("by need at %d units took %d us, the per-candidate fill %d us: not one basis a step" % [n, fast, slow])


## The fill as it stood before the TAKE: one basis per candidate per step.
func _fill_per_candidate(ns, type_id: String, n: int) -> Array:
	var open: Array = []
	for r in _loader.regions.get(ns.id, []):
		if Units.start_capacity(_loader, ns.id, type_id, r.id) > 0.0:
			open.append(String(r.id))
	var behind := 1.0 if String(_loader.unit_types[type_id]["figure"]["better"]) == "lower" else -1.0
	var placed := {}
	for i in n:
		var worst := ""
		var top := -INF
		for id in open:
			var f := behind * Units._shown(ns, _loader, type_id, id, placed)
			if f > top:
				top = f
				worst = id
		placed[worst] = int(placed.get(worst, 0)) + 1
	var out: Array = []
	for id in open:
		if int(placed.get(id, 0)) > 0:
			out.append({"region": id, "units": int(placed[id])})
	return out

## A beds-per-1000 row is behind when it reads LOWER, and a built hospital raises it.
func _test_a_higher_is_better_figure() -> void:
	var state = _state()
	var ns = state.player()
	var rows: Array = Units.fill_by_need(ns, _loader, HOSPITAL, 1)
	var worst := ""
	var low := INF
	for region in _named(state):
		var f := Units.shown_figure(ns, _loader, HOSPITAL, region)
		if f < low:
			low = f
			worst = region
	if rows.size() != 1 or String(rows[0]["region"]) != worst:
		_fail("by need puts its first hospital in %s, not the fewest beds, %s" % [rows, worst])
	var before := Units.shown_figure(ns, _loader, HOSPITAL, "FR1")
	ns.unit_programmes.assign([{"id": "h1", "type": HOSPITAL, "op": UK.OP_BUILD, "state": UK.STATE_DONE,
		"rows": [{"region": "FR1", "units": 1}]}])
	if Units.shown_figure(ns, _loader, HOSPITAL, "FR1") <= before:
		_fail("a built hospital did not raise FR1's beds")


func _test_the_register_is_saved() -> void:
	var state = _state()
	var ns = state.player()
	if not ns.unit_programmes.is_empty():
		_fail("a new game starts with programmes: %s" % [ns.unit_programmes])
	ns.unit_programmes.assign([_done("p1", UK.OP_BUILD, "FR1", 2)])
	var back = ns.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	if back.unit_programmes.size() != 1 or Units.capacity_delta(back, _loader, TYPE, "FR1") != 2000.0:
		_fail("the register did not survive a save: %s" % [back.unit_programmes])


func _done(id: String, op: String, region: String, units: int) -> Dictionary:
	return _row(id, op, UK.STATE_DONE, region, units)


func _row(id: String, op: String, state: String, region: String, amount: int) -> Dictionary:
	# A build row counts units; a closure row is entered in capacity (section 7).
	var r := {"region": region, "capacity": amount} if op == UK.OP_DEMOLISH else {"region": region, "units": amount}
	return {"id": id, "type": TYPE, "op": op, "state": state, "rows": [r]}



## The register sheet's before/after (V5.3 c' slice 1): preview() is the shown figure with
## units placed but not built, from one basis, so the sheet's "after" is the very figure the
## region shows once they stand, and with nothing placed it is the shown figure itself.
func _test_the_preview_reads_units_not_yet_built() -> void:
	var state = _state()
	var ns = state.player()
	var none: Dictionary = Units.preview(ns, _loader, TYPE, {})
	var placed := {"FR1": 3}
	var some: Dictionary = Units.preview(ns, _loader, TYPE, placed)
	for region in _named(state):
		if absf(float(none.get(region, -1.0)) - Units.shown_figure(ns, _loader, TYPE, region)) > 1e-9:
			_fail("preview with nothing placed differs from the shown figure in %s" % region)
		if absf(float(some.get(region, -1.0)) - Units._shown(ns, _loader, TYPE, region, placed)) > 1e-9:
			_fail("preview with units placed differs from the basis in %s" % region)
	if float(some["FR1"]) >= float(none["FR1"]):
		_fail("three schools placed in FR1 did not lower its pupils per teacher: %s -> %s" % [none["FR1"], some["FR1"]])
	if Units.preview(ns, _loader, "no_such_type", placed) != {}:
		_fail("preview of an unknown type is not empty")

func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_units: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)
