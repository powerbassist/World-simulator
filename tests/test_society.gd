extends SceneTree

## V1.5a. Service quality as a derived stock, corruption as the delivery factor, and
## the sixth effect channel. Model: docs/society-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen, and each
## one is a failure this session either found, deliberately declined, or inherited as
## a rule from an earlier block:
##
##   - the stock reads EXACTLY its own reference at new game, exact equality and not
##     is_zero_approx, which is V1.4a's standard and what lets the register go live;
##   - QUALITY_KEYS does NOT contain education, defence or infrastructure, because
##     each already has an outcome stock under another name -- the refusal IS the
##     design, src/core/law.gd's _extract_company() shape;
##   - corruption bites a player who NEVER MOVES A SPENDING LINE, which is the whole
##     reason it multiplies the stock's target rather than the satisfaction delta;
##   - quality does not REPLACE the spending delta, so both are live and they price
##     different times -- the announcement and the delivery;
##   - src/sim/society.gd never writes ns.corruption, asserted by reading the file,
##     which is what keeps the channel's single writer single;
##   - the nine's quality sits still for a whole run, the "no has_budget lift" call
##     stated as a property, exactly as tests/test_defence.gd states it.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Society = preload("res://src/sim/society.gd")
const K = preload("res://src/sim/society_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CabinetK = preload("res://src/sim/cabinet_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_registry_excludes_the_lines_that_already_have_a_stock()
	_test_seeds_at_equilibrium_exactly()
	_test_deviation_is_exactly_zero_at_new_game()
	_test_the_nine_never_move()
	_test_stock_converges_on_a_raised_line()
	_test_delivery_is_exactly_neutral_without_a_law()
	_test_corruption_bites_a_do_nothing_player()
	_test_corruption_is_signed_both_ways()
	_test_quality_does_not_replace_the_delta()
	_test_a_line_without_a_stock_costs_nothing()
	_test_the_channel_has_one_writer()
	_test_society_is_a_leaf()
	_test_content_loads()
	_finish()


func _new_state():
	return GameState.new_game(_loader, PLAYER)


# --- The registry -------------------------------------------------------------

## THE REFUSAL IS THE DESIGN. docs/tiers/v1.md §5 asks for "healthcare and education
## quality as outcomes of spending", and of the five spending lines THREE already
## carry an outcome stock under another name: defence has military_capability (V1.3g),
## and education and infrastructure share potential_shift_pct (S4). A second stock on
## any of them is that lever twice -- docs/companies-model.md's V1.4b collision in a
## new place -- so this asserts the exclusion rather than trusting the comment.
##
## `pensions` is excluded for a DIFFERENT and temporary reason: adequacy is spend per
## dependent and the dependent count is V1.5b's. When V1.5b adds it, this test loses
## one name from the list below and keeps the other three forever.
func _test_registry_excludes_the_lines_that_already_have_a_stock() -> void:
	for banned in ["education", "defence", "infrastructure"]:
		if K.QUALITY_KEYS.has(banned):
			_fail("QUALITY_KEYS contains '%s', which already has an outcome stock elsewhere -- that is the same lever twice" % banned)

	if K.QUALITY_KEYS.is_empty():
		_fail("QUALITY_KEYS is empty -- the whole channel is dead")

	for key in K.QUALITY_KEYS:
		if not EK.SPENDING_KEYS.has(key):
			_fail("QUALITY_KEYS contains '%s', which is not a spending line" % key)


# --- The stock ----------------------------------------------------------------

## Seeded AT equilibrium, not at zero -- src/sim/defence.gd's argument word for word.
## EXACT equality rather than is_equal_approx, and that is V1.4a's standard rather
## than pedantry: the claim the whole session rests on is that the deviation term is
## exactly 0.0 until the player acts, and an approximate seed makes it approximately
## zero, which is what a bit-identical balance re-run cannot survive.
func _test_seeds_at_equilibrium_exactly() -> void:
	var state = _new_state()
	for id in state.nations.keys():
		var ns = state.nations[id]
		for key in K.QUALITY_KEYS:
			var target: float = Society.quality_target(ns, key)
			if float(ns.service_quality[key]) != target:
				_fail("%s seeded quality['%s'] at %.17f against target %.17f -- not exact" % [
					id, key, float(ns.service_quality[key]), target
				])
			if float(ns.start_service_quality[key]) != target:
				_fail("%s seeded start_quality['%s'] at %.17f against target %.17f -- not exact" % [
					id, key, float(ns.start_service_quality[key]), target
				])


func _test_deviation_is_exactly_zero_at_new_game() -> void:
	var state = _new_state()
	for id in state.nations.keys():
		for key in K.QUALITY_KEYS:
			var d: float = Society.quality_deviation(state.nations[id], key)
			if d != 0.0:
				_fail("%s quality_deviation('%s') is %.17f at new game, not exactly 0.0" % [id, key, d])

	# And the consequence, which is the one that matters: the satisfaction term this
	# session adds is silent, so opinion at new game is what it was before V1.5a.
	var sat := Opinion.issue_satisfaction(state.player())
	for key in K.QUALITY_KEYS:
		var without_stock: float = Opinion._scaled(
			float(state.player().spending_pct_gdp.get(key, 0.0))
			- float(state.player().start_spending_pct_gdp.get(key, 0.0)),
			OK.SPEND_SCALE_PP
		)
		if not is_equal_approx(float(sat[key]), without_stock):
			_fail("the '%s' issue moved at new game -- the quality term is not silent" % key)


## The "no has_budget lift" call as a property, and tests/test_defence.gd makes the
## identical assertion about capability. The nine have no budget model, so their
## spending never moves and their quality must sit EXACTLY still for a whole run. If
## this fails, something has started writing the nine's spending lines.
func _test_the_nine_never_move() -> void:
	var state = _new_state()
	var before := {}
	for id in state.nations.keys():
		before[id] = (state.nations[id].service_quality as Dictionary).duplicate(true)

	for _i in range(168):
		Society.tick_month(state)

	for id in state.nations.keys():
		if state.nations[id].has_budget:
			continue
		for key in K.QUALITY_KEYS:
			if float(state.nations[id].service_quality[key]) != float(before[id][key]):
				_fail("%s quality['%s'] moved over 168 months with no budget model" % [id, key])


func _test_stock_converges_on_a_raised_line() -> void:
	var state = _new_state()
	var ns = state.player()
	var key: String = K.QUALITY_KEYS[0]
	ns.spending_pct_gdp[key] = float(ns.spending_pct_gdp[key]) + 2.0

	var first: float = float(ns.service_quality[key])
	Society.tick_month(state)
	if not (float(ns.service_quality[key]) > first):
		_fail("quality did not move toward a raised spending line")

	# 2000 rather than a game-length horizon on purpose: at QUALITY_CONVERGENCE = 0.02
	# a fourteen-year run leaves 3e-2 of the gap and 400 months leaves 3e-4, both
	# wider than is_equal_approx. This assertion is about the fixed point existing at
	# all, and the SPEED of approach is what tools/society_probe.gd measures instead.
	for _i in range(2000):
		Society.tick_month(state)
	if not is_equal_approx(float(ns.service_quality[key]), Society.quality_target(ns, key)):
		_fail("quality never converged: %.4f against target %.4f" % [
			float(ns.service_quality[key]), Society.quality_target(ns, key)
		])


# --- Corruption ---------------------------------------------------------------

## EXACTLY 1.0, not approximately. Same argument as the exact seed above: this factor
## is what makes the whole register inert in a game with no `society` law, and
## "approximately inert" is not a property a bit-identical re-run can rest on.
func _test_delivery_is_exactly_neutral_without_a_law() -> void:
	var state = _new_state()
	for id in state.nations.keys():
		if Society.delivery_factor(state.nations[id]) != 1.0:
			_fail("%s delivery_factor is %.17f with no law passed, not exactly 1.0" % [
				id, Society.delivery_factor(state.nations[id])
			])


## THE SESSION'S SECOND CALL, AS A TEST. docs/tiers/v1.md §5 says corruption degrades
## "policy effectiveness", which names Cabinet.effectiveness() -- but that function
## multiplies the spending DELTA only, deliberately, so a corruption factor placed
## there costs a player who never touches a spending line EXACTLY ZERO, which is free
## to precisely the player most likely to deserve it. Degrading the stock's target
## instead means a corrupt state's hospitals decay at unchanged spending.
##
## The spending line is never written below, and that omission is the whole test.
func _test_corruption_bites_a_do_nothing_player() -> void:
	var state = _new_state()
	var ns = state.player()
	var key: String = K.QUALITY_KEYS[0]

	var spend_before: float = float(ns.spending_pct_gdp[key])
	var health_before: float = float(Opinion.issue_satisfaction(ns)[key])

	ns.corruption = 0.6
	for _i in range(60):
		Society.tick_month(state)

	if float(ns.spending_pct_gdp[key]) != spend_before:
		_fail("the test moved a spending line -- it proves nothing about a do-nothing player")
	if not (float(ns.service_quality[key]) < float(ns.start_service_quality[key])):
		_fail("corruption did not degrade the stock at unchanged spending")
	if not (float(Opinion.issue_satisfaction(ns)[key]) < health_before):
		_fail("corruption reached no opinion -- it is decorative at the site it was placed")

	# And the counterfactual that makes it specific rather than incidental: placed at
	# Cabinet.effectiveness()'s own site, this player would have paid nothing, because
	# effectiveness multiplies a delta that is zero.
	var quiet = _new_state()
	if not is_zero_approx(
		float(quiet.player().spending_pct_gdp[key])
		- float(quiet.player().start_spending_pct_gdp[key])
	):
		_fail("the do-nothing player's spending delta is not zero, so the counterfactual does not hold")


## Signed, and the sign is the whole of anti-corruption -- V1.4b's deregulation
## argument plus one V1.4b did not need: a one-directional level would make an
## anti-corruption law INERT on a clean state, which breaks V1.3f's property that
## nothing on the law list does nothing.
func _test_corruption_is_signed_both_ways() -> void:
	var state = _new_state()
	var ns = state.player()

	ns.corruption = -0.5
	if not (Society.delivery_factor(ns) > 1.0):
		_fail("negative corruption did not raise delivery above 1.0 -- an anti-corruption law is inert on a clean state")

	ns.corruption = 0.5
	if not (Society.delivery_factor(ns) < 1.0):
		_fail("positive corruption did not lower delivery")

	# The floor may not go under VACANT_EFFECTIVENESS. A factor that degrades delivery
	# further than an EMPTY MINISTRY claims corruption is worse than having no minister
	# at all, which is the pre-committed tiebreaker in society_constants.gd.
	if K.DELIVERY_MIN < CabinetK.VACANT_EFFECTIVENESS:
		_fail("DELIVERY_MIN %.2f is below VACANT_EFFECTIVENESS %.2f -- corruption may not be worse than having no minister" % [
			K.DELIVERY_MIN, CabinetK.VACANT_EFFECTIVENESS
		])

	# ...and it is measured SLACK rather than assumed, the way docs/defence-model.md
	# measured its bill clamp: a saturated register does not reach either bound.
	ns.corruption = K.CORRUPTION_MAX
	if Society.delivery_factor(ns) <= K.DELIVERY_MIN:
		_fail("a saturated register pins DELIVERY_MIN -- the clamp is the number rather than a guard rail")


# --- The double count ---------------------------------------------------------

## Quality is ADDITIVE and post-effectiveness, so it does not replace the spending
## delta: both terms are live and they price different times, the delta the
## announcement and the stock the delivery. Fast in, slow out.
##
## Asserted as a sequence rather than as a formula: the issue must move on the month
## the line is raised (the delta, with no lag) and move FURTHER over the following
## years (the stock) without the line being touched again.
func _test_quality_does_not_replace_the_delta() -> void:
	var state = _new_state()
	var ns = state.player()
	var key: String = K.QUALITY_KEYS[0]

	var at_start: float = float(Opinion.issue_satisfaction(ns)[key])
	ns.spending_pct_gdp[key] = float(ns.spending_pct_gdp[key]) + 1.0

	var on_announcement: float = float(Opinion.issue_satisfaction(ns)[key])
	if not (on_announcement > at_start):
		_fail("raising the line moved the issue not at all in the same month -- the stock has REPLACED the delta, which this file's own comment rejects")

	for _i in range(60):
		Society.tick_month(state)
	if not (float(Opinion.issue_satisfaction(ns)[key]) > on_announcement):
		_fail("the issue did not move further over five years -- the stock reaches no opinion")


## opinion.gd loops QUALITY_KEYS rather than SPENDING_KEYS, so a line with no stock
## costs exactly nothing and V1.5b adds `pensions` without touching opinion.gd. That
## is what keeps the registry a registry.
func _test_a_line_without_a_stock_costs_nothing() -> void:
	var state = _new_state()
	for key in EK.SPENDING_KEYS:
		if K.QUALITY_KEYS.has(key):
			continue
		var d: float = Society.quality_deviation(state.player(), key)
		if d != 0.0:
			_fail("quality_deviation('%s') is %.17f for a line with no stock, not exactly 0.0" % [key, d])


# --- The channel --------------------------------------------------------------

## `corruption` has exactly ONE writer in the project and it is Legislature.apply().
## Asserted by reading the file, which is the idiom docs/people-model.md and
## docs/calendar-model.md both use for a property no runtime check can express --
## society.gd only ever READS the level it prices.
func _test_the_channel_has_one_writer() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/society.gd")
	if src == "":
		_fail("could not read src/sim/society.gd")
		return
	for line in src.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("corruption =") or stripped.contains("corruption +="):
			_fail("society.gd writes ns.corruption -- the channel's single writer is Legislature.apply(), and this is the second")

	# And the channel is reachable through a law rather than only through a test.
	var state = _new_state()
	var ns = state.player()
	var before: float = ns.corruption
	var found := false
	for law in _loader.laws:
		if not law.effects.has("society"):
			continue
		found = true
		Legislature.apply(state, ns, law, _loader)
	if not found:
		_fail("no law in data/laws/ carries effects.society -- the sixth channel has no content")
	if ns.corruption == before:
		_fail("applying every society law left corruption unchanged")


## A leaf. society.gd must be reachable from game_state.gd and budget.gd without
## dragging a preload chain behind it, and it must not preload opinion.gd -- opinion
## reads THIS file, and the reverse would make the double count circular.
func _test_society_is_a_leaf() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/society.gd")
	if src == "":
		_fail("could not read src/sim/society.gd")
		return
	# V1.5b added demography.gd, and the addition does not weaken the property: that
	# file is the strictest leaf in the project, preloading only its own constants, so
	# the chain this test exists to bound is still two deep and still ends.
	var allowed := [
		"res://src/sim/society_constants.gd",
		"res://src/sim/cabinet.gd",
		"res://src/sim/demography.gd",
	]
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("const"):
			continue
		if not line.contains("preload("):
			continue
		var ok := false
		for path in allowed:
			if line.contains(path):
				ok = true
		if not ok:
			_fail("society.gd preloads something outside its allowed set: %s" % line.strip_edges())


func _test_content_loads() -> void:
	var with_society: Array = []
	for law in _loader.laws:
		if law.effects.has("society"):
			with_society.append(law.id)
	if with_society.is_empty():
		_fail("no law carries effects.society")

	# Both directions must be reachable IN PLAY, not merely representable. Without a
	# corruption-RAISING law the positive half of CORRUPTION_MAX is unreachable and
	# the probe would be sweeping a state the game cannot produce -- V1.3f's
	# measuring-the-wrong-state error.
	#
	# V1.5b: `corruption` is no longer the only term on the channel, so the reads below
	# are guarded rather than assumed. A migration law carries no corruption figure at
	# all, and treating an absent key as a zero would silently pass a file in which
	# nothing raises corruption any more.
	var raises := false
	var lowers := false
	for law in _loader.laws:
		if not law.effects.has("society"):
			continue
		var society: Dictionary = law.effects["society"]
		if not society.has("corruption"):
			continue
		if float(society["corruption"]) > 0.0:
			raises = true
		if float(society["corruption"]) < 0.0:
			lowers = true
	if not raises:
		_fail("no law raises corruption -- the positive half of the clamp is unreachable in play")
	if not lowers:
		_fail("no law lowers corruption")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_society: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	print("test_society: %d failure(s)" % _failures.size())
	quit(1)
