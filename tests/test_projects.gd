extends SceneTree

## V1.6f. Infrastructure projects: the in-flight register, the construction
## countdown, the completion payoff, the computed bill and the verb. Model:
## docs/projects-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen, and each
## is a property this session's shape rests on:
##
##   - the payoff and the bill read EXACTLY 0.0 -- not approximately -- for a
##     fourteen-year run in which nobody builds, which is what lets the whole layer go
##     live with the balance harness bit-identical across every existing regime;
##   - a project pays on COMPLETION and not before. A half-built motorway is worth
##     nothing, and a test that only checked the end state would pass on a lever that
##     paid the day it was signed;
##   - the bill STOPS the month the work does. Every other computed line in this game
##     is a standing rate; this is the first one that ends, and it is the whole reason
##     a project is a commitment rather than a policy;
##   - structural unemployment is BIT-IDENTICAL between a building run and a quiet one.
##     The row states "no employment term" as a prohibition; it is a consequence, and
##     this is where that is pinned -- V1.6e's assertion inherited one landing site
##     further out;
##   - src/sim/projects.gd is a LEAF and src/sim/calendar.gd is still one, which is
##     what makes the diary's project row a reuse of the surface rather than a second
##     scheduler;
##   - the nine never build anything, so the verb is the player's -- V1.3g's and
##     V1.6e's honest limitation, pinned rather than described.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Projects = preload("res://src/sim/projects.gd")
const K = preload("res://src/sim/projects_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Investment = preload("res://src/sim/investment.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Region = preload("res://src/core/region.gd")

const PLAYER := "FRA"
## The shortest project in the shipped ladder, so a completion fits comfortably inside
## a test run. Named rather than derived, because a test that picks its own subject
## silently changes what it measures when the content moves.
const SMALL := "flood_defence"
const SMALL_START := "start_flood_defence"
const SMALL_ABANDON := "abandon_flood_defence"
const BIG_START := "start_high_speed_rail"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_content_loads()
	_test_every_project_can_be_abandoned()
	_test_register_seeds_empty()
	_test_unbuilt_reads_exactly_zero()
	_test_a_long_run_stays_exactly_zero()
	_test_a_project_pays_only_on_completion()
	_test_the_bill_reaches_the_budget_and_then_stops()
	_test_the_payoff_reaches_trend()
	_test_no_employment_term()
	_test_abandon_erases_and_pays_nothing()
	_test_a_project_is_built_once()
	_test_the_concurrency_gate_is_content()
	_test_the_accumulator_is_clamped()
	_test_the_diary_shows_work_in_progress()
	_test_projects_is_a_leaf()
	_test_calendar_is_still_a_leaf()
	_test_the_nine_never_build()
	_test_the_register_carries_no_content()
	_check_site_region()
	_check_enclaves()
	_finish()


## V2.7. A project names a place now, and the place is the one its authored
## coordinate falls in -- U6c's project_sites block, read for a second purpose. The
## site is DERIVED and stored nowhere: Siting.site()'s rule, and it is why
## SAVE_VERSION does not move for this.
func _check_site_region() -> void:
	var site: String = Projects.site_region(_loader, "FRA", "high_speed_rail")
	if site == "":
		_fail("FRA's high_speed_rail has an authored site and no region was found for it")
	var known := false
	for region in _loader.regions.get("FRA", []):
		if region.id == site:
			known = true
	if not known:
		_fail("high_speed_rail sites at '%s', which is not a French region" % site)
	# A nation with no project_sites block reads "" rather than erroring: the block is
	# optional (data/companies/'s coverage rule) and seven of the ten carry none.
	if Projects.site_region(_loader, "LUX", "high_speed_rail") != "":
		_fail("LUX has no project_sites block and returned a site anyway")


func _finish() -> void:
	if _failures.is_empty():
		print("test_projects: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


## THE ENCLAVE CASE, and it is the whole reason the cast is hole-aware. Berlin (DE3)
## sits inside Brandenburg's (DE4) outer ring, so a cast over outer rings alone files
## it under its host and NOTHING CRASHES -- which is why this is a test and not a
## comment. Vienna inside Niederösterreich and Brussels inside Vlaams Gewest are the
## same shape and are checked with it.
func _check_enclaves() -> void:
	# Berlin ~13.40E 52.52N, Vienna ~16.37E 48.21N, Brussels ~4.35E 50.85N.
	for row in [["DE3", 13.40, 52.52], ["AT13", 16.37, 48.21], ["BE1", 4.35, 50.85]]:
		var got := Region.region_at_lonlat(_loader.region_rings, float(row[1]), float(row[2]))
		if got != String(row[0]):
			_fail("point (%.2f, %.2f) resolved to '%s', expected the enclave '%s'"
				% [float(row[1]), float(row[2]), got, String(row[0])])
	# A point in the Atlantic belongs to nobody, and "" is a real answer rather than
	# a missing one -- Siting.site()'s own no-site rule one module over.
	if Region.region_at_lonlat(_loader.region_rings, -30.0, 45.0) != "":
		_fail("a point in the Atlantic resolved to a region")


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state():
	return GameState.new_game(_loader, PLAYER)


func _action(id: String):
	for a in _loader.project_actions:
		if a.id == id:
			return a
	return null


func _terms(project_id: String) -> Dictionary:
	return Projects.terms_of(_loader, project_id)


## One month of everything this layer touches, in main.gd's order.
func _tick(state) -> void:
	Economy.tick_month(state)
	Budget.tick_month(state)
	Investment.tick_month(state)
	Projects.tick_month(state, _loader)


# --- Content ---------------------------------------------------------------------

func _test_content_loads() -> void:
	if _loader.project_actions.is_empty():
		_fail("no project actions loaded")
		return
	for id in [SMALL_START, SMALL_ABANDON, BIG_START]:
		if _action(id) == null:
			_fail("project action '%s' is missing" % id)

	for a in _loader.project_actions:
		var terms: Dictionary = a.effects.get("project", {})
		var op := String(terms.get("op", ""))
		if not K.PROJECT_OPS.has(op):
			_fail("%s carries op '%s'" % [a.id, op])
		if String(terms.get("project_id", "")).is_empty():
			_fail("%s names no project" % a.id)
		if op == "abandon":
			for banned in K.PROJECT_OP_TERMS["start"]:
				if terms.has(banned):
					_fail("%s is an abandon and carries %s" % [a.id, banned])
		else:
			for required in K.PROJECT_OP_TERMS["start"]:
				if not terms.has(required):
					_fail("%s is a start and is missing %s" % [a.id, required])


## Every project must have a way out while it is building. The loader already refuses
## an abandon that names nothing; this is the other direction, which no cross-file
## check can express -- a project with no abandon is a commitment the player can never
## reverse, and abandonment is this lever's whole downside.
func _test_every_project_can_be_abandoned() -> void:
	var starts := {}
	var abandons := {}
	for a in _loader.project_actions:
		var terms: Dictionary = a.effects.get("project", {})
		var pid := String(terms.get("project_id", ""))
		if String(terms.get("op", "")) == "start":
			starts[pid] = true
		else:
			abandons[pid] = true
	for pid in starts.keys():
		if not abandons.has(pid):
			_fail("project '%s' can be begun and never abandoned" % pid)


# --- The register ------------------------------------------------------------------

func _test_register_seeds_empty() -> void:
	var state = _new_state()
	for id in state.nations.keys():
		var ns = state.nations[id]
		if not (ns.projects as Dictionary).is_empty():
			_fail("%s seeded a project register with entries" % id)
		if ns.project_potential_target_pct != 0.0:
			_fail("%s seeded a project payoff" % id)
		if ns.project_bill_pct_gdp != 0.0:
			_fail("%s seeded a project bill" % id)


## EXACT equality, not is_zero_approx. This is the property the balance re-run's
## bit-identity rests on: nothing this session adds may move a single bit of a run in
## which no project verb was issued, and "approximately zero" would not prove it.
func _test_unbuilt_reads_exactly_zero() -> void:
	var state = _new_state()
	for id in state.nations.keys():
		var ns = state.nations[id]
		if ns.project_potential_target_pct != 0.0:
			_fail("%s has a project payoff with nothing built" % id)
		if Projects.bill_pct_gdp(ns, _loader) != 0.0:
			_fail("%s is billed with nothing under construction" % id)


func _test_a_long_run_stays_exactly_zero() -> void:
	var state = _new_state()
	for _m in range(168):
		_tick(state)
	for id in state.nations.keys():
		var ns = state.nations[id]
		if ns.project_potential_target_pct != 0.0 or ns.project_bill_pct_gdp != 0.0:
			_fail("%s moved over fourteen years with nobody building" % id)


# --- Construction --------------------------------------------------------------------

## THE CENTRAL ASSERTION OF THE SESSION. A project pays on COMPLETION and not one month
## before it. Every other stock in this project -- V1.6e's capital, V1.5a's service
## quality, V1.3g's military capability -- converges continuously, so a test written by
## analogy with any of them would pass on a lever that paid out as it built.
func _test_a_project_pays_only_on_completion() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))
	var build := int(_terms(SMALL).get("build_months", 0))
	if Projects.months_left(ns, SMALL) != build:
		_fail("a project did not start at its authored build length")

	for m in range(build - 1):
		_tick(state)
		if ns.project_potential_target_pct != 0.0:
			_fail("a project paid out in month %d of a %d-month build" % [m + 1, build])
		if not Projects.is_building(ns, SMALL):
			_fail("a project finished early, in month %d of %d" % [m + 1, build])

	_tick(state)
	if not Projects.is_done(ns, SMALL):
		_fail("a project did not complete on its own build month")
	var want := float(_terms(SMALL).get("potential_growth_pct", 0.0))
	if not is_equal_approx(ns.project_potential_target_pct, want):
		_fail("a completed project paid %.4f, expected %.4f" % [ns.project_potential_target_pct, want])

	# And it does not go on paying. The accumulator is a step, not a stock that grows.
	for _m2 in range(24):
		_tick(state)
	if not is_equal_approx(ns.project_potential_target_pct, want):
		_fail("a completed project kept paying: %.4f against %.4f" % [ns.project_potential_target_pct, want])


## THE BILL STOPS. This is the one thing separating a project from every other computed
## line on the budget -- the bloc transfer, the deployment bill, the subsidy bill and
## V1.6e's investment bill are all standing rates -- and it is what makes the deficit a
## bulge rather than a step.
func _test_the_bill_reaches_the_budget_and_then_stops() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))
	# TWO ticks, and the second one is the lag rather than a rounding allowance.
	# Budget.recompute() runs BEFORE Projects.tick_month() in main.gd's order, so a
	# build begun this month is priced next month -- `deficit_pct_gdp` is one of this
	# verb's own precondition fields and a bill that widened the deficit inside the
	# month would close a loop. A test that ticked once would read 0.0000 and be
	# measuring the lag while claiming to measure the bill.
	_tick(state)
	_tick(state)

	var want := float(_terms(SMALL).get("cost_pct_gdp", 0.0))
	if not is_equal_approx(ns.project_bill_pct_gdp, want):
		_fail("a running project billed %.4f, expected %.4f" % [ns.project_bill_pct_gdp, want])
	if ns.total_spending_pct_gdp <= 0.0:
		_fail("total spending did not compute")
	# The control is ticked through the SAME loop, one month for one month. The first
	# version ran Economy and Budget by hand for two months against a state that had
	# had one full tick, so the two rows differed for a reason that had nothing to do
	# with the bill -- tests/test_trade.gd's own missing control at V1.6a.
	var quiet = _new_state()
	_tick(quiet)
	_tick(quiet)
	var gap: float = ns.total_spending_pct_gdp - quiet.nations[PLAYER].total_spending_pct_gdp
	if not is_equal_approx(gap, want):
		_fail("the project bill reached total spending as %.4f, expected %.4f" % [gap, want])

	var build := int(_terms(SMALL).get("build_months", 0))
	for _m2 in range(build + 2):
		_tick(state)
	if not Projects.is_done(ns, SMALL):
		_fail("the project did not complete")
	if ns.project_bill_pct_gdp != 0.0:
		_fail("a finished project is still billing %.4f" % ns.project_bill_pct_gdp)


## The payoff reaches Economy.trend_pct() through potential_shift_pct and NOT through a
## channel of its own. Measured against a quiet control rather than against zero --
## tests/test_trade.gd measured a partner recession against nothing at V1.6a and got a
## number that was about the rest of the model.
func _test_the_payoff_reaches_trend() -> void:
	var built = _new_state()
	var quiet = _new_state()
	var bns = built.nations[PLAYER]
	Projects.execute(built, bns, _loader.project_actions, _action(BIG_START))
	for _m in range(150):
		_tick(built)
		_tick(quiet)

	var qns = quiet.nations[PLAYER]
	if not Projects.is_done(bns, "high_speed_rail"):
		_fail("the large project did not finish inside the run")
	if bns.potential_shift_pct <= qns.potential_shift_pct:
		_fail("a completed project did not raise potential_shift_pct")
	if bns.trend_annual_pct <= qns.trend_annual_pct:
		_fail("a completed project did not raise trend")
	if bns.gdp_eur_bn <= qns.gdp_eur_bn:
		_fail("a completed project bought no GDP: %.2f against %.2f" % [bns.gdp_eur_bn, qns.gdp_eur_bn])

	# And the addend is bounded on the accumulator, so the quantity reaching trend is
	# still `potential_shift_pct` and still carries exactly one bound.
	if absf(bns.potential_shift_pct) > EK.SHIFT_MAX_PCT:
		_fail("potential_shift_pct left its own clamp: %.4f" % bns.potential_shift_pct)


## docs/tiers/v1.md section 6's "carries no employment term" is a CONSEQUENCE and not a
## prohibition -- Okun reads `growth - trend` and structural unemployment reads only the
## income-tax wedge, the law offset and the firm layer. Pinned both ways: measured
## bit-identically, and by reading the source, because a later session could add the
## channel and the measurement alone would then simply change.
func _test_no_employment_term() -> void:
	var built = _new_state()
	var quiet = _new_state()
	var bns = built.nations[PLAYER]
	Projects.execute(built, bns, _loader.project_actions, _action(BIG_START))
	for _m in range(150):
		_tick(built)
		_tick(quiet)

	var qns = quiet.nations[PLAYER]
	if bns.structural_unemployment_pct != qns.structural_unemployment_pct:
		_fail("structural unemployment moved: %.9f against %.9f" % [
			bns.structural_unemployment_pct, qns.structural_unemployment_pct,
		])

	var src := FileAccess.get_file_as_string("res://src/sim/projects.gd")
	if src.is_empty():
		_fail("could not read src/sim/projects.gd")
		return
	for line in src.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		# The WRITE forms, not the names. `unemployment_pct` alone matches
		# _read_field()'s precondition read, which is a lookup a content file asked
		# for and not a channel into the employment path -- test_sectors.gd made the
		# same distinction for the same reason.
		for forbidden in [
			"unemployment_pct =", "structural_unemployment_pct =", "headcount",
			"labour_force", "firm_jobs_offset_pct =",
		]:
			if line.contains(forbidden):
				_fail("projects.gd reaches the employment path via '%s'" % forbidden)


# --- Abandonment ----------------------------------------------------------------------

## A PROGRAMME YOU CAN STOP; A PROJECT YOU CAN ONLY ABANDON. V1.6e's withdrawal leaves
## 63 % of the capital standing a year on; this must leave nothing at all, and the
## register must forget the build ever happened -- otherwise `project_started` would
## read true forever and abandoning would be a way to lock a project out of a later
## term.
func _test_abandon_erases_and_pays_nothing() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))
	for _m in range(12):
		_tick(state)
	if not Projects.is_building(ns, SMALL):
		_fail("the project was not building when the abandon was issued")

	Projects.execute(state, ns, _loader.project_actions, _action(SMALL_ABANDON))
	if Projects.is_started(ns, SMALL):
		_fail("an abandoned project is still in the register")
	if ns.project_potential_target_pct != 0.0:
		_fail("an abandoned project paid out %.4f" % ns.project_potential_target_pct)

	_tick(state)
	if ns.project_bill_pct_gdp != 0.0:
		_fail("an abandoned project is still billing")

	# And it can be begun again, at full length. A year of work bought nothing.
	var result := Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))
	if not result.get("applied", false):
		_fail("an abandoned project could not be begun again")
	if Projects.months_left(ns, SMALL) != int(_terms(SMALL).get("build_months", 0)):
		_fail("restarting an abandoned project kept some of its progress")


## Built once, and the register is what enforces it -- which is why
## src/core/project_action.gd carries neither `once` nor `cooldown_months`.
func _test_a_project_is_built_once() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))
	var again := Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))
	if again.get("applied", false):
		_fail("a project already under construction could be begun a second time")

	for _m in range(int(_terms(SMALL).get("build_months", 0)) + 1):
		_tick(state)
	if not Projects.is_done(ns, SMALL):
		_fail("the project did not complete")

	var rebuilt := Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))
	if rebuilt.get("applied", false):
		_fail("a finished project could be built again")
	var demolish := Projects.execute(state, ns, _loader.project_actions, _action(SMALL_ABANDON))
	if demolish.get("applied", false):
		_fail("a finished project could be abandoned -- a built motorway is not un-built")


## THE CEILING IS CONTENT, which is why src/sim/projects_constants.gd ships no
## concurrency constant. If a session ever adds one, this test is where the duplication
## shows up: the gate must still be readable off the preconditions.
func _test_the_concurrency_gate_is_content() -> void:
	var gate := -1
	for a in _loader.project_actions:
		if String(a.effects.get("project", {}).get("op", "")) != "start":
			continue
		var found := false
		for cond in a.preconditions:
			if String(cond["field"]) == "project_count":
				found = true
				gate = maxi(gate, int(cond["value"]))
		if not found:
			_fail("%s has no project_count precondition, so nothing bounds the stack" % a.id)
	if gate < 0:
		_fail("no project action gates on project_count")
		return

	var state = _new_state()
	var ns = state.nations[PLAYER]
	var started := 0
	for a in _loader.project_actions:
		if String(a.effects.get("project", {}).get("op", "")) != "start":
			continue
		if Projects.execute(state, ns, _loader.project_actions, a).get("applied", false):
			started += 1
	if started != gate + 1:
		_fail("the gate permits %d concurrent projects but %d started" % [gate + 1, started])


func _test_the_accumulator_is_clamped() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	ns.project_potential_target_pct = K.PROJECT_POTENTIAL_MAX_PCT
	Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))
	for _m in range(int(_terms(SMALL).get("build_months", 0)) + 1):
		_tick(state)
	if ns.project_potential_target_pct > K.PROJECT_POTENTIAL_MAX_PCT:
		_fail("the accumulator passed its own clamp: %.4f" % ns.project_potential_target_pct)


# --- The diary ---------------------------------------------------------------------

## B1, pinned rather than described. A project under construction reaches
## Calendar.fixed_dates() because the register counts MONTHS REMAINING -- the idiom
## every countdown in this project already uses -- and a finished one does not, because
## a diary is about what is coming.
func _test_the_diary_shows_work_in_progress() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))

	var rows := 0
	var ref := ""
	for row in Calendar.fixed_dates(state):
		if String(row.get("kind", "")) == CalendarK.FIXED_PROJECT:
			rows += 1
			ref = String(row.get("ref", ""))
	if rows != 1:
		_fail("the diary lists %d project rows for one build" % rows)
	if ref != SMALL:
		_fail("the diary's project row names '%s'" % ref)

	for _m in range(int(_terms(SMALL).get("build_months", 0)) + 1):
		_tick(state)
	for row2 in Calendar.fixed_dates(state):
		if String(row2.get("kind", "")) == CalendarK.FIXED_PROJECT:
			_fail("the diary still lists a project that has opened")


# --- Structure -----------------------------------------------------------------------

func _test_projects_is_a_leaf() -> void:
	# V2.8. `src/core/region.gd` is allowed and is NOT a crack in the leaf: it is a
	# VALUE TYPE beneath sim in the data -> sim -> ui order, carrying no loader and
	# no system -- the same standing city.gd has on the panel side. What the leaf
	# check exists to refuse is sim -> sim coupling, and the cast this preload
	# reaches is the shared hole-aware predicate V2.8 lifted out of this file
	# precisely so a second caller would not own a copy of it.
	_assert_preloads("res://src/sim/projects.gd", [
		"res://src/sim/projects_constants.gd",
		"res://src/core/region.gd",
	])


## B1's other half. src/sim/calendar.gd preloads nothing but its own constants, and
## V1.6f added a row to fixed_dates() without changing that -- which is what makes the
## diary a REUSE of a surface rather than a second scheduler. If a later session gives
## the calendar a preload to resolve a project's name or cost, this turns red: naming
## belongs to the panel.
func _test_calendar_is_still_a_leaf() -> void:
	_assert_preloads("res://src/sim/calendar.gd", ["res://src/sim/calendar_constants.gd"])


func _assert_preloads(path: String, allowed: Array) -> void:
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		_fail("could not read %s" % path)
		return
	for line in src.split("\n"):
		if not line.begins_with("const ") or not line.contains("preload("):
			continue
		var target := line.get_slice("\"", 1)
		if not allowed.has(target):
			_fail("%s preloads '%s', which would stop it being a leaf" % [path, target])


## The verb is the player's. The nine have no agenda term for it -- V1.3g's four verbs
## and V1.6e's programmes recorded the same limitation -- and this is what keeps the
## balance re-run bit-identical across every existing regime.
func _test_the_nine_never_build() -> void:
	var state = _new_state()
	for _m in range(168):
		_tick(state)
	for id in state.nations.keys():
		if id == PLAYER:
			continue
		if not (state.nations[id].projects as Dictionary).is_empty():
			_fail("%s began a project with no player command" % id)

	for path in ["res://src/sim/foreign_policy.gd", "res://src/sim/diplomacy.gd", "res://src/sim/diplomacy_agenda.gd"]:
		var src := FileAccess.get_file_as_string(path)
		if src.contains("Projects.") or src.contains("projects.gd"):
			_fail("%s reaches the project verb -- an AI agenda for it is a session, not a line" % path)


## A register entry carries exactly Projects.ENTRY_KEYS and no authored content. The
## cost, the duration and the payoff round-trip through data/project-actions/, so a
## session caching any of them here is putting content in the save -- V1.4a's device
## pointed at a fourth register.
func _test_the_register_carries_no_content() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Projects.execute(state, ns, _loader.project_actions, _action(SMALL_START))
	var entry: Dictionary = ns.projects[SMALL]
	for key in entry.keys():
		if not Projects.ENTRY_KEYS.has(key):
			_fail("a register entry carries '%s' -- %s is the whole register" % [key, str(Projects.ENTRY_KEYS)])
	if entry.size() != Projects.ENTRY_KEYS.size():
		_fail("a register entry has %d keys, expected %d" % [entry.size(), Projects.ENTRY_KEYS.size()])
