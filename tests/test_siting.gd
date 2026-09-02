extends SceneTree

## V2.6b1. The siting contract, and the two prices that were designed for it -- one
## shipped, one deleted. Model: docs/siting-model.md.
##
## The load-bearing assertions here are again the ones about what does NOT happen:
##
##   - normalised() is mean-one to 1e-12, because a multiplier whose mean is not one
##     is a silent retune of whatever constant it multiplies, and V1.5c measured
##     UNREST_IMPULSE_SCALE with a band that a silent retune would void;
##   - a FLAT signal produces NO SITE, and no site produces a concentration of
##     EXACTLY 1.0 -- which is what makes Britain's and Luxembourg's bounds
##     arithmetic rather than a branch anywhere;
##   - the answer does not depend on Dictionary insertion order, asserted by building
##     the same input twice in opposite orders;
##   - act_impulse() at an index of exactly 1.0 returns the pre-V2.6b1 figure with
##     EXACT equality, which is what keeps every unsited case bit-identical;
##   - src/sim/siting_constants.gd DOES NOT EXIST. V2.6b1's one candidate constant
##     was designed, banded, swept and deleted when the interval came back empty, and
##     this pins the deletion so a later session re-adding it has to come and say why
##     -- V1.3c's device, pointed forward rather than left to memory.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Siting = preload("res://src/sim/siting.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")

const TOLERANCE := 1.0e-12

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_normalised_is_mean_one()
	_test_flat_signal_has_no_site()
	_test_no_site_is_exactly_neutral()
	_test_walk_order_cannot_reach_the_answer()
	_test_margin_reports_its_degeneracies()
	_test_pick_only_returns_scoring_ids()
	_test_the_two_structural_bounds_on_real_data()
	_test_output_multiplier_is_mean_one_on_real_data()
	_test_unsited_impulse_is_bit_identical()
	_test_no_register_is_exactly_neutral()
	_test_the_deleted_constant_stays_deleted()
	_finish()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("\ntest_siting: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr(message)
	printerr("\ntest_siting: %d failure(s)" % _failures.size())
	quit(1)


# --- The primitive ---------------------------------------------------------------

## THE ANTI-RESCALE CHECK. Asserted at 1e-12 ABSOLUTE, which is the tolerance
## docs/migration-model.md section 4 uses for the same class of claim: nothing here is
## exponentiated, so there is no second-order term to excuse a larger one.
func _test_normalised_is_mean_one() -> void:
	var cases: Array = [
		[{"a": 1.0, "b": 2.0, "c": 3.0}, {"a": 0.5, "b": 0.3, "c": 0.2}],
		[{"a": 0.01, "b": 900.0}, {"a": 0.999, "b": 0.001}],
		[{"a": 7.0}, {"a": 1.0}],
	]
	for case in cases:
		var out: Dictionary = Siting.normalised(case[0], case[1])
		var weighted := 0.0
		var total := 0.0
		for id in out:
			weighted += float(case[1][id]) * float(out[id])
			total += float(case[1][id])
		var mean: float = weighted / total
		if absf(mean - 1.0) > TOLERANCE:
			_fail("normalised() weighted mean is %.17f, off unity by more than 1e-12 -- that is a silent rescale of whatever constant it multiplies" % mean)


# --- The no-site answer ------------------------------------------------------------

## A flat signal is not a missing signal, and the empty answer is the honest one.
func _test_flat_signal_has_no_site() -> void:
	var weights := {"a": 0.5, "b": 0.3, "c": 0.2}
	var flat := {"a": 4.0, "b": 4.0, "c": 4.0}
	var over: Dictionary = Siting.excess(flat, weights)
	if not over.is_empty():
		_fail("a flat signal produced an excess of %s -- nothing can stand above its own mean when everything equals it" % [over])
	if Siting.site(weights, over) != "":
		_fail("a flat signal still chose a site")


## EXACT equality, not is_equal_approx, and this is the assertion the two recorded
## bounds rest on: an unpriced nation must be unpriced by ARITHMETIC. A concentration
## of 1.0000000001 would make Britain's price differ from one in the last digits, and
## a re-run pinned at the bit level would then move for a nation that has no site.
func _test_no_site_is_exactly_neutral() -> void:
	var weights := {"a": 0.5, "b": 0.3, "c": 0.2}
	if Siting.concentration(weights, "") != 1.0:
		_fail("concentration() on an empty site is %s rather than exactly 1.0" % str(Siting.concentration(weights, "")))
	if Siting.concentration({}, "") != 1.0:
		_fail("concentration() with no weights at all is not exactly 1.0")


## A Dictionary's key order is its insertion order, so an arg-max that walked it
## naively would let two runs reaching the same state by different routes disagree.
## Built twice in opposite orders, including an exact tie, which is the case a walk
## order can actually reach.
func _test_walk_order_cannot_reach_the_answer() -> void:
	var forward := {}
	var backward := {}
	for id in ["a", "b", "c", "d"]:
		forward[id] = 1.0
	for id in ["d", "c", "b", "a"]:
		backward[id] = 1.0
	var weights_f := {"a": 0.25, "b": 0.25, "c": 0.25, "d": 0.25}
	var weights_b := {"d": 0.25, "c": 0.25, "b": 0.25, "a": 0.25}
	var first: String = Siting.site(weights_f, forward)
	var second: String = Siting.site(weights_b, backward)
	if first != second:
		_fail("site() returned %s one way and %s the other on an exact tie -- the walk order reached the answer" % [first, second])
	if first != "a":
		_fail("site() broke a tie on %s rather than on the lowest id" % first)


func _test_margin_reports_its_degeneracies() -> void:
	if Siting.margin({"a": 1.0}, {"a": 1.0}) != INF:
		_fail("margin() with exactly one scoring entry should be INF -- there is no runner-up to be ahead of")
	if Siting.margin({"a": 1.0, "b": 1.0}, {}) != 0.0:
		_fail("margin() with no site at all should be 0.0")
	var m: float = Siting.margin({"a": 1.0, "b": 1.0}, {"a": 2.0, "b": 1.0})
	if absf(m - 1.0) > 1.0e-9:
		_fail("margin() should read 1.0 when the winner scores twice the runner-up, and reads %s" % str(m))


func _test_pick_only_returns_scoring_ids() -> void:
	var weights := {"a": 0.5, "b": 0.5, "c": 0.5}
	var signals := {"a": 1.0, "b": 3.0, "c": 0.0}
	for step in range(21):
		var u: float = float(step) / 20.0
		var got: String = Siting.pick(weights, signals, u)
		if got == "c":
			_fail("pick() returned an entry scoring exactly 0.0 at u=%s" % str(u))
		if got != "a" and got != "b":
			_fail("pick() returned %s, which scores nothing, at u=%s" % [got, str(u)])
	if Siting.pick(weights, {}, 0.5) != "":
		_fail("pick() with nothing scoring should return the empty site")


# --- On the real register ----------------------------------------------------------

## THE TWO BOUNDS AS ASSERTIONS RATHER THAN AS PROSE, which is what V2.6a did for its
## own two and the reason they survive a later session's edit.
##
## Britain's regions carry unemployment_rel exactly 1.0 -- V2.5 section 8's ITL1 index
## proxy -- and Luxembourg is one region. Both therefore have no site at MONTH ONE and
## both are unpriced there. Deliberately NOT asserted over a whole run: the probe
## measured Britain acquiring a site later, because the GDP weights that set the mean
## trend move under V2.5's divergence, and a test claiming Britain is permanently
## unsited would be asserting something the model does not do.
func _test_the_two_structural_bounds_on_real_data() -> void:
	for id in ["GBR", "LUX"]:
		var state = GameState.new_game(_loader, id)
		var ns = state.player()
		var region_list: Array = state.regions.get(id, [])
		var report: Dictionary = Unrest.site_report(ns, region_list)
		if String(report["region_id"]) != "":
			_fail("%s has a site at month one (%s), and both recorded bounds say it should have none" % [id, report["region_id"]])
		if float(report["concentration"]) != 1.0:
			_fail("%s is unsited and its concentration is %s rather than exactly 1.0" % [id, str(report["concentration"])])
		if float(report["output_index"]) != 1.0:
			_fail("%s is unsited and its output index is %s rather than exactly 1.0" % [id, str(report["output_index"])])


## The multiplier that actually ships. Its mean must be one on the real register for
## every nation, or UNREST_IMPULSE_SCALE has been quietly rescaled per nation.
func _test_output_multiplier_is_mean_one_on_real_data() -> void:
	for id in _loader.nations.keys():
		var state = GameState.new_game(_loader, id)
		var ns = state.player()
		var region_list: Array = state.regions.get(id, [])
		if region_list.is_empty():
			continue
		var weights: Dictionary = Unrest.site_weights(ns, region_list)
		var raw := {}
		for region in region_list:
			raw[region.id] = Regions.gdp_per_head_index(
				ns, region_list, region.id, Migration.region_share(ns, region.id)
			)
		var indexed: Dictionary = Siting.normalised(raw, weights)
		var weighted := 0.0
		var total := 0.0
		for rid in indexed:
			weighted += float(weights[rid]) * float(indexed[rid])
			total += float(weights[rid])
		var mean: float = weighted / total
		if absf(mean - 1.0) > TOLERANCE:
			_fail("%s's output multiplier has a share-weighted mean of %.17f -- that silently rescales UNREST_IMPULSE_SCALE for that nation" % [id, mean])


# --- The shipped price -------------------------------------------------------------

## EXACT equality. An index of 1.0 is an average place or no place, and the impulse
## there must be the figure V1.5c measured to the bit -- otherwise every nation with
## no site moves in a re-run that has no reason to move.
func _test_unsited_impulse_is_bit_identical() -> void:
	for unrest in [0.0, 12.5, 45.0, 52.0, 100.0]:
		var sited: float = Unrest.act_impulse(float(unrest), 1.0)
		var plain: float = -UnrestK.UNREST_IMPULSE_SCALE * clampf(float(unrest) / UnrestK.UNREST_MAX, 0.0, 1.0)
		if sited != plain:
			_fail("act_impulse(%s, 1.0) is %s and the unsited figure is %s -- an index of one must be exactly neutral" % [
				str(unrest), str(sited), str(plain),
			])
	# And it scales, so the factor is doing something rather than being decorative.
	if Unrest.act_impulse(50.0, 2.0) != Unrest.act_impulse(50.0, 1.0) * 2.0:
		_fail("act_impulse() does not scale linearly in the output index")


## A state with no register at all -- which a probe or a fixture can build -- must be
## exactly neutral rather than crashing or reading zero.
func _test_no_register_is_exactly_neutral() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var report: Dictionary = Unrest.site_report(state.player(), [])
	if String(report["region_id"]) != "" or String(report["city_id"]) != "":
		_fail("a nation with no register produced a site")
	if float(report["concentration"]) != 1.0 or float(report["output_index"]) != 1.0:
		_fail("a nation with no register is not exactly neutral: %s" % [report])


# --- The deletion ------------------------------------------------------------------

## V1.3c'S DEVICE, POINTED FORWARD. src/sim/siting_constants.gd was written, its band
## was fixed before the sweep, the sweep came back with an EMPTY interval on three
## grids, and the file was deleted rather than shipped at an unused 0.0 -- because a
## tuned constant nothing reads is a number a later session finds and reasons from
## (V1.3e's AGREEMENT_ACCEPT_MIN).
##
## The numbers that closed it, from tools/siting_probe.gd table (d): the WHOLE unrest
## opinion price is worth 2.9825 points on the worst bloc row, one settlement law is
## worth 0.4450, and a term readable on the panel that prints it needs 1.0 -- so a
## readable siting term must be a third of the entire unrest price and 2.25x what
## settling the strike is worth. The two clauses are inconsistent rather than badly
## tuned.
##
## A session that re-adds the file turns this red, which is the point: it must come
## with a fresh measurement rather than with a fresh opinion.
func _test_the_deleted_constant_stays_deleted() -> void:
	if FileAccess.file_exists("res://src/sim/siting_constants.gd"):
		_fail("src/sim/siting_constants.gd is back. V2.6b1 deleted it because its band's passing interval was EMPTY -- see docs/siting-model.md section 5. Re-adding it needs a new measurement, not a new opinion")
	var src := FileAccess.get_file_as_string("res://src/sim/unrest.gd")
	if src.contains("SITE_VISIBILITY_BETA"):
		_fail("unrest.gd still names SITE_VISIBILITY_BETA, the constant this session measured and deleted")
