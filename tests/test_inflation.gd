extends SceneTree

## Headless test: godot --headless --script res://tests/test_inflation.gd
## Non-zero exit on any failure.
##
## V1.6b. Inflation. Behavioural checks plus FOUR architectural ones read off the
## source -- the idiom docs/people-model.md, docs/calendar-model.md and
## docs/cycle-model.md all use. One of the four is new to this project and exists
## because of a specific past failure: _check_every_harness_ticks_it() enumerates the
## harnesses and fails if any has stopped calling the tick. V1.5d shipped with two
## harnesses that never called Media.tick_month(), so both ran the pre-session model
## and their bit-identical agreement was about nothing. V1.6a could make that
## impossible by having no tick at all; a stock cannot, so it is checked instead.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const K = preload("res://src/sim/inflation_constants.gd")

const MONTHS := 168
const START_YEAR := 2026

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_zero_at_new_game()
	_check_the_anchor_is_content()
	_check_the_phillips_sign_both_ways()
	_check_convergence_is_a_lag_not_a_step()
	_check_the_nine_stay_near_their_anchors()
	_check_the_opinion_price_is_signed()
	_check_the_issue_is_reachable_and_labelled()
	_check_the_clamp_is_slack()
	_check_the_cost_is_one_sided()
	_check_single_writer()
	_check_preloads()
	_check_no_nominal_layer()
	_check_every_harness_ticks_it()

	_finish()


## EXACTLY 0.0 for all ten, and exact equality rather than is_zero_approx() because
## this is V1.4a's inert-channel property rather than an approximation: at new game
## unemployment_pct == structural_unemployment_pct, so the gap is zero, the target is
## the anchor, and the stock is seeded there. The whole register goes live without
## moving a figure until something moves unemployment.
func _check_zero_at_new_game() -> void:
	var state = _new_state("FRA")
	for ns in state.nations.values():
		if ns.inflation_pct != ns.inflation_anchor_pct:
			_fail("%s starts at %s against an anchor of %s -- init seeds a transient" % [
				ns.id, ns.inflation_pct, ns.inflation_anchor_pct
			])
		if Inflation.inflation_deviation(ns) != 0.0:
			_fail("%s starts with a non-zero inflation deviation (%s)" % [
				ns.id, Inflation.inflation_deviation(ns)
			])
		if Inflation.output_cost_pct(ns) != 0.0:
			_fail("%s starts with a non-zero growth cost (%s)" % [
				ns.id, Inflation.output_cost_pct(ns)
			])
	var sat := Opinion.issue_satisfaction(state.player())
	if float(sat["inflation"]) != 0.0:
		_fail("the inflation issue starts at %s, not exactly 0" % sat["inflation"])


## The anchor is imported per-nation content, not one roster constant -- the property
## that keeps this off docs/foreign-policy-model.md's clustered `coalition_position`
## failure. Switzerland's measured 1.117 against Spain's 2.903 is a 2.6x spread, and
## a run with nothing happening leaves each nation at its OWN figure.
func _check_the_anchor_is_content() -> void:
	var state = _new_state("FRA")
	var che = state.nations["CHE"]
	var esp = state.nations["ESP"]
	if che.inflation_anchor_pct >= esp.inflation_anchor_pct:
		_fail("CHE's anchor (%s) is not below ESP's (%s) -- the content is not being read" % [
			che.inflation_anchor_pct, esp.inflation_anchor_pct
		])
	if is_equal_approx(che.inflation_anchor_pct, esp.inflation_anchor_pct):
		_fail("every nation has the same anchor -- the spread is not being read")


## The sign, in BOTH directions, because a one-directional check passes on a model
## that only ever rises. Unemployment BELOW structural is a hot economy and must push
## inflation up; above it must push inflation down.
func _check_the_phillips_sign_both_ways() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var anchor: float = ns.inflation_anchor_pct

	ns.unemployment_pct = ns.structural_unemployment_pct - 2.0
	if Inflation.inflation_target(ns) <= anchor:
		_fail("a hot labour market did not raise the inflation target above the anchor")
	for _i in range(24):
		Inflation.tick_month(state)
	if ns.inflation_pct <= anchor:
		_fail("two years of a hot labour market left inflation at or below the anchor (%s)" % ns.inflation_pct)

	state = _new_state("FRA")
	ns = state.player()
	ns.unemployment_pct = ns.structural_unemployment_pct + 2.0
	if Inflation.inflation_target(ns) >= anchor:
		_fail("a slack labour market did not lower the inflation target below the anchor")
	for _i in range(24):
		Inflation.tick_month(state)
	if ns.inflation_pct >= anchor:
		_fail("two years of a slack labour market left inflation at or above the anchor (%s)" % ns.inflation_pct)


## A first-order lag, not a step: one month closes a FRACTION of the distance. This is
## what makes the thirteenth issue distinct from `jobs` rather than collinear with it
## -- `jobs` prices unemployment now, this prices where unemployment was a year ago.
func _check_convergence_is_a_lag_not_a_step() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	ns.unemployment_pct = ns.structural_unemployment_pct - 2.0
	var target: float = Inflation.inflation_target(ns)
	var before: float = ns.inflation_pct

	Inflation.tick_month(state)
	var moved: float = ns.inflation_pct - before
	var whole: float = target - before
	if moved <= 0.0 or moved >= whole:
		_fail("one month moved %s of a %s gap -- a lag closes a fraction, a step closes it all" % [moved, whole])

	# And the fraction is the measured one, not some other number.
	if not is_equal_approx(moved / whole, K.INFLATION_CONVERGENCE):
		_fail("one month closed %s of the gap, expected INFLATION_CONVERGENCE %s" % [
			moved / whole, K.INFLATION_CONVERGENCE
		])


## THE TRAP, AND IT IS WHY THIS CHECK IS NOT test_defence.gd's AND test_society.gd's.
## Those two assert the nine sit perfectly still, because the nine's spending lines
## never move. That assertion is WRONG here and would have to be deleted later: since
## V1.6a the business cycle moves growth for all ten, growth moves unemployment through
## Okun, and an unemployment gap moves inflation. The nine's inflation therefore DOES
## move, with nobody having done anything, and that is correct.
##
## What is asserted instead is that it stays BOUNDED near each nation's own anchor --
## the model's claim -- rather than still, which is a claim the model never made.
func _check_the_nine_stay_near_their_anchors() -> void:
	var state = _new_state("FRA")
	var moved := false
	for _i in range(MONTHS):
		_advance(state)
		Economy.tick_month(state)
		Inflation.tick_month(state)
	for ns in state.nations.values():
		if ns.has_budget:
			continue
		if not is_equal_approx(ns.inflation_pct, ns.inflation_anchor_pct):
			moved = true
		# The reachable band: the slope times the largest unemployment gap fourteen
		# years of an unforced cycle can open, generously bounded.
		if absf(ns.inflation_pct - ns.inflation_anchor_pct) > 3.0:
			_fail("%s drifted %s from its anchor with no player and no budget" % [
				ns.id, ns.inflation_pct - ns.inflation_anchor_pct
			])
		if not is_finite(ns.inflation_pct):
			_fail("%s's inflation is not finite" % ns.id)
	if not moved:
		_fail("no AI nation's inflation moved in fourteen years -- the cycle should be opening unemployment gaps, so this check is not measuring what it claims")


## Signed both ways, and measured against the nation's OWN start rather than an
## absolute target. A president who inherits high inflation and brings it down is
## rewarded, which is what a delta against the start means.
func _check_the_opinion_price_is_signed() -> void:
	var state = _new_state("FRA")
	var ns = state.player()

	ns.inflation_pct = ns.start_inflation_pct + 0.3
	if float(Opinion.issue_satisfaction(ns)["inflation"]) >= 0.0:
		_fail("rising prices did not read as a negative satisfaction")

	ns.inflation_pct = ns.start_inflation_pct - 0.3
	if float(Opinion.issue_satisfaction(ns)["inflation"]) <= 0.0:
		_fail("falling prices did not read as a positive satisfaction -- a president who disinflates should be rewarded")


## The issue reaches the surfaces that exist to say WHY, which is the whole reason
## test 1 of the ISSUE_KEYS question is about nameability. The label is checked
## explicitly rather than left to a run that happens to surface it, because
## src/ui/election_panel.gd and src/ui/polling_panel.gd INDEX ISSUE_LABEL directly --
## a missing entry is a crash on the result screen, not a blank row.
func _check_the_issue_is_reachable_and_labelled() -> void:
	if not OpinionK.ISSUE_KEYS.has("inflation"):
		_fail("inflation is not in ISSUE_KEYS")
	if not OpinionK.ISSUE_LABEL.has("inflation"):
		_fail("ISSUE_LABEL has no 'inflation' entry -- election_panel.gd indexes this dictionary and would crash")
	for bloc in OpinionK.BLOC_KEYS:
		if not (OpinionK.BLOC_SALIENCE_BASE[bloc] as Dictionary).has("inflation"):
			_fail("bloc '%s' has no inflation weight -- the row would be invisible to that bloc" % bloc)

	var state = _new_state("FRA")
	var ns = state.player()
	ns.inflation_pct = ns.start_inflation_pct + 2.0
	Opinion.tick_month(state)
	var named := false
	for entry in Opinion.top_issues(ns, 3):
		if entry[0] == "inflation":
			named = true
	if not named:
		_fail("a two-point inflation shock did not put inflation in the top three issues, so the polling panel and elections.gd can never name it")


## The clamp is a GUARD RAIL and the slack is measured rather than asserted, because a
## clamp nobody has measured is a clamp that might be setting the model -- which is
## docs/economy-model.md's own IMPULSE_MAX finding. The target is an anchor plus a
## slope times a bounded gap, and a first-order lag on a bounded target is bounded, so
## nothing reachable should come near either end.
func _check_the_clamp_is_slack() -> void:
	var state = _new_state("FRA")
	var worst := 0.0
	for _i in range(MONTHS):
		_advance(state)
		Economy.tick_month(state)
		Inflation.tick_month(state)
		for ns in state.nations.values():
			worst = maxf(worst, absf(ns.inflation_pct))
	if worst >= K.INFLATION_MAX or worst <= K.INFLATION_MIN:
		_fail("inflation reached %s against clamps [%s, %s] -- the clamp is setting the model" % [
			worst, K.INFLATION_MIN, K.INFLATION_MAX
		])
	print("test_inflation: clamp slack -- worst reachable |inflation| %.3f against %.1f" % [
		worst, K.INFLATION_MAX
	])


## The growth cost is ONE-SIDED above the anchor, and the lower branch is exactly 0.0
## rather than merely small. That is the whole of the stability argument: a two-sided
## cost would make the deflationary branch self-amplifying, and this project's model
## contains no other term that feeds its own growth rate.
func _check_the_cost_is_one_sided() -> void:
	var state = _new_state("FRA")
	var ns = state.player()

	ns.inflation_pct = ns.inflation_anchor_pct + 1.0
	if Inflation.output_cost_pct(ns) >= 0.0:
		_fail("inflation above the anchor did not cost growth")

	ns.inflation_pct = ns.inflation_anchor_pct - 1.0
	if Inflation.output_cost_pct(ns) != 0.0:
		_fail("inflation BELOW the anchor cost %s -- the cost must be exactly one-sided, or the deflation branch is a self-amplifying loop" % Inflation.output_cost_pct(ns))

	ns.inflation_pct = ns.inflation_anchor_pct - 4.0
	if Inflation.output_cost_pct(ns) != 0.0:
		_fail("a deep deflation cost %s -- still not one-sided" % Inflation.output_cost_pct(ns))


## The four inflation fields have exactly one writer each and it is this file. The
## discipline `share`, `state_share`, `regulation_burden`, `migration_stance`,
## `settlement_stance`, `gini_index` and `cycle_impulse_pct` all hold to -- and walked
## over the WHOLE directory rather than a hand-listed set, so a file added by a later
## session is covered without anyone remembering to add it here.
func _check_single_writer() -> void:
	var writers: Array[String] = []
	for path in _sim_files():
		if path == "res://src/sim/inflation.gd":
			continue
		var source := FileAccess.get_file_as_string(path)
		for line in source.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#") or stripped.begins_with("##"):
				continue
			for field in ["inflation_pct", "start_inflation_pct", "inflation_anchor_pct",
					"inflation_impulse_pct"]:
				if stripped.contains(field + " =") or stripped.contains(field + " +="):
					writers.append("%s: %s" % [path, stripped])
	if not writers.is_empty():
		_fail("single writer: an inflation field is assigned outside inflation.gd: %s" % [writers])


## inflation.gd preloads its own constants and NOTHING else. In particular it must not
## preload opinion.gd or economy.gd: both read this file's output through NationState,
## and a reverse edge would turn that one-way relationship from a fact into a
## convention. tests/test_unrest.gd's check, one session on.
func _check_preloads() -> void:
	var source := FileAccess.get_file_as_string("res://src/sim/inflation.gd")
	var found: Array[String] = []
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.begins_with("const ") and stripped.contains("preload("):
			found.append(stripped)
	if found.size() != 1 or not found[0].contains("inflation_constants.gd"):
		_fail("inflation.gd's preloads are %s -- it must be a leaf on its own constants alone" % [found])


## THE CONSTANT-PRICE BOUNDARY, CHECKED RATHER THAN STATED. Nothing in this project is
## nominal, so no file may deflate or index anything by the price level. The one
## legitimate reader of the stock outside this module is economy.gd's growth sum,
## which reads `inflation_impulse_pct` -- a growth addend, not a deflator -- and
## opinion.gd, which reads the deviation through inflation_deviation().
##
## A later session adding a nominal layer turns this red and has to come and say why,
## which is the point: the boundary is the session's central decision and prose alone
## would not survive it.
func _check_no_nominal_layer() -> void:
	var offenders: Array[String] = []
	for path in _sim_files():
		if path == "res://src/sim/inflation.gd":
			continue
		var source := FileAccess.get_file_as_string(path)
		for line in source.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#") or stripped.begins_with("##"):
				continue
			# Reading the raw stock outside inflation.gd is what a deflator looks like.
			# The impulse and the two functions above are the sanctioned surface.
			if stripped.contains(".inflation_pct") and not stripped.contains("start_inflation_pct"):
				offenders.append("%s: %s" % [path, stripped])
	if not offenders.is_empty():
		_fail("the price level is read outside inflation.gd, which is what a nominal layer looks like: %s" % [offenders])


## Every harness that ticks a per-nation system must tick this one. V1.5d's bug, made
## a check rather than a memory. The month every harness runs is world_month.gd's
## (tests/test_world_month.gd holds the game and the balance harnesses to it), so
## that file is read here, with the projection and its mirror -- the two that still
## tick a subset of their own, and whose silence would be invisible.
func _check_every_harness_ticks_it() -> void:
	for path in ["res://src/sim/world_month.gd", "res://src/sim/budget.gd",
			"res://tests/test_budget.gd"]:
		var source := FileAccess.get_file_as_string(path)
		var called := false
		for line in source.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if stripped.contains("Inflation.tick_month("):
				called = true
		if not called:
			_fail("%s never calls Inflation.tick_month() -- it is running the pre-V1.6b model and any agreement it reports is about nothing" % path)


func _sim_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://src/sim")
	if dir == null:
		_fail("could not open res://src/sim")
		return out
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append("res://src/sim/" + name)
	return out


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _new_state(nation_id: String):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	return state


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_inflation: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr(message)
	printerr("test_inflation: %d check(s) failed" % _failures.size())
	quit(1)
