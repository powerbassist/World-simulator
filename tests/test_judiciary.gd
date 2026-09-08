extends SceneTree

## V1.1e. The court, and docs/tiers/v1.md section 5's rule-of-law statistic, which section
## 1's judiciary bullet inherited at V1.5's decomposition on the argument that two
## uncontestable gates on player action would be one machine claimed twice.
## Model: docs/judiciary-model.md.
##
## The load-bearing assertions are the ones about what does NOT happen:
##
##   - a law's REACH is derived from clamps that already existed and reads NEITHER
##     `bloc_offset` NOR a budget lever. The first version read bloc_offset and came back
##     numerically equal to it, which is a court striking down whatever is unpopular;
##   - the gate is in propose() and _force(), NOT in apply(), NOT in apply_effects() and
##     NOT in _settle_referendum(). apply_effects() has had two callers since V1.8 and the
##     second is an event choice, which is section 1's "Decree / executive order";
##   - a constitutional AMENDMENT is never reviewable, because it becomes the standard the
##     court applies;
##   - three nations have no review at all, by three different doctrines, and Britain's
##     score is computed and never read;
##   - the grievance term reads the DEVIATION and is exactly 0.0 for all ten at new game;
##   - src/sim/judiciary.gd is a LEAF -- it does not name legislature.gd, law.gd or
##     unrest.gd -- and it is STATELESS beyond the two fields it seeds;
##   - and `judicial_independence` has exactly ONE writer, Legislature.apply_effects().

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const JK = preload("res://src/sim/judiciary_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Law = preload("res://src/core/law.gd")

const PLAYER := "FRA"

## The court-weakening ladder. Named rather than searched for: a content edit that removes
## one should turn this red rather than quietly test less.
const WEAKEN := ["judicial_appointments_reform", "court_jurisdiction_limits", "judicial_tenure_act"]
const STRENGTHEN := "judicial_independence_act"

var _loader: DataLoader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_review_is_authored_for_all_ten()
	_test_independence_is_imported_and_spread()
	_test_reach_ignores_popularity_and_the_budget()
	_test_an_amendment_is_never_reviewable()
	_test_no_review_means_no_gate()
	_test_a_far_reaching_bill_is_struck()
	_test_a_struck_bill_leaves_nothing_behind()
	_test_the_gate_is_not_in_apply()
	_test_a_ratified_law_is_not_reviewable()
	_test_the_ladder_moves_the_gate()
	_test_capture_is_not_a_master_key()
	_test_the_grievance_reads_the_deviation()
	_test_judiciary_is_a_leaf()
	_test_one_writer()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("test_judiciary: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _state():
	return GameState.new_game(_loader, PLAYER)


func _law(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null


# ---------------------------------------------------------------------------

## Required for all ten, unlike `government.upper`: every state has SOME answer to whether
## its courts may strike a statute down, and three of the ten answer `none` for three
## different doctrines. An absent block would make a silence indistinguishable from
## Britain's parliamentary sovereignty, which is a position rather than an omission.
func _test_review_is_authored_for_all_ten() -> void:
	var state = _state()
	var none_count := 0
	for ns in state.nations.values():
		if not JK.KNOWN_REVIEWS.has(ns.judicial_review):
			_fail("%s judicial_review '%s' is not a recognised value" % [ns.id, ns.judicial_review])
		if ns.judicial_review == JK.REVIEW_NONE:
			none_count += 1
	# V3.3: SWE joins them -- Sweden has no constitutional court and its courts
	# cannot strike down statutes, which is the same parliamentary-sovereignty
	# family as the other three rather than an authoring gap.
	if none_count != 4:
		_fail("expected four nations with no judicial review, got %d" % none_count)
	for nation_id in ["GBR", "NLD", "CHE", "SWE"]:
		if state.nations[nation_id].judicial_review != JK.REVIEW_NONE:
			_fail("%s should have no review of primary legislation" % nation_id)


## Imported per nation from GOV_WGI_RL.SC, and the SPREAD is the point: ten identical
## numbers would be the clustered `coalition_position` failure docs/foreign-policy-model.md
## recorded, and V1.5b and V1.5c each found a row's "no dataset" premise wrong the same way.
func _test_independence_is_imported_and_spread() -> void:
	var state = _state()
	var lowest := 100.0
	var highest := 0.0
	for ns in state.nations.values():
		if ns.judicial_independence <= JK.INDEPENDENCE_MIN or ns.judicial_independence > JK.INDEPENDENCE_MAX:
			_fail("%s rule of law %.1f is outside the scale" % [ns.id, ns.judicial_independence])
		if absf(ns.judicial_independence - ns.start_judicial_independence) > 1e-12:
			_fail("%s starts with a deviation already on it" % ns.id)
		lowest = minf(lowest, ns.judicial_independence)
		highest = maxf(highest, ns.judicial_independence)
	if highest - lowest < 10.0:
		_fail("the roster spans only %.1f points of rule of law -- it is clustered" % (highest - lowest))


## THE PROBE'S FIRST CORRECTION, pinned. `bloc_offset` is the law's authored DOMESTIC
## PRICE and a court does not rule on popularity; a budget lever is a budget change and
## the budget is Parliament's. A law carrying only those two must reach EXACTLY 0.000.
func _test_reach_ignores_popularity_and_the_budget() -> void:
	var checked := 0
	for law in _loader.laws:
		var effects: Dictionary = law.effects
		var only_price := true
		for channel in effects:
			if channel != "bloc_offset" and channel != "tax_rates_pct" \
					and channel != "spending_pct_gdp" and channel != "institutional":
				only_price = false
		if not only_price:
			continue
		checked += 1
		if law.reach != 0.0:
			_fail("%s reaches %.3f on nothing but a price and a lever" % [law.id, law.reach])
	if checked == 0:
		_fail("no law in the content carries only a price and a lever -- the check is inert")

	# And a law that DOES move a clamped channel must reach something.
	var moved := 0
	for law in _loader.laws:
		if law.effects.has("society") and law.reach > 0.0:
			moved += 1
	if moved == 0:
		_fail("no law with an effects.society term has a reach above zero")


## A revision becomes the standard the court applies. Two reasons agree -- the Conseil
## constitutionnel has declined jurisdiction over revisions since 2003, and
## `effects.institutional` sets an absolute value with no magnitude to take a fraction of
## -- so neither is doing the other's work.
func _test_an_amendment_is_never_reviewable() -> void:
	var ns = _state().player()
	var checked := 0
	for law in _loader.laws:
		if not law.constitutional:
			continue
		checked += 1
		if Judiciary.reviews(ns, law):
			_fail("%s is a constitutional amendment and the court claimed it" % law.id)
		if Judiciary.strikes_down(ns, law):
			_fail("%s is a constitutional amendment and was struck down" % law.id)
	if checked == 0:
		_fail("no constitutional amendment in the content -- the check is inert")


## Britain's 78.8 is computed and never read. That IS parliamentary sovereignty.
func _test_no_review_means_no_gate() -> void:
	var state = _state()
	for nation_id in ["GBR", "NLD", "CHE"]:
		var ns = state.nations[nation_id]
		for law in _loader.laws:
			if Judiciary.reviews(ns, law) or Judiciary.strikes_down(ns, law):
				_fail("%s has no judicial review and struck %s" % [nation_id, law.id])
				return


func _test_a_far_reaching_bill_is_struck() -> void:
	var ns = _state().player()
	var tolerance := Judiciary.tolerance(ns)
	var struck := 0
	var survives := 0
	for law in _loader.laws:
		if law.constitutional:
			continue
		if Judiciary.strikes_down(ns, law):
			struck += 1
			if law.reach <= tolerance:
				_fail("%s was struck at reach %.3f against a tolerance of %.3f"
					% [law.id, law.reach, tolerance])
		elif law.reach > 0.0:
			survives += 1
	if struck < 1:
		_fail("France's court strikes NOTHING down -- the gate is inert")
	if survives < 1:
		_fail("France's court strikes EVERYTHING down -- the country cannot legislate")


## A struck bill applies nothing at all: no `once` flag, no channel written, and the
## cooldown of a defeat. It cost the player the division and gave them nothing.
func _test_a_struck_bill_leaves_nothing_behind() -> void:
	var state = _state()
	var ns = state.player()
	var law = _struck_law(ns)
	if law == null:
		_fail("no law in the content is carried by both chambers and struck by the court")
		return

	var before_offset: float = float(ns.bloc_offset.get("workers", 0.0))
	var before_structural: float = ns.law_structural_offset_pct
	var result := Legislature.propose(state, _loader, law)
	if not bool(result.get("struck_down", false)):
		_fail("%s was not struck: %s" % [law.id, result])
		return
	if bool(result["passed"]):
		_fail("a struck bill reported passed")
	if ns.passed_law_ids.has(law.id):
		_fail("a struck bill set its `once` flag")
	if absf(float(ns.bloc_offset.get("workers", 0.0)) - before_offset) > 1e-12:
		_fail("a struck bill wrote bloc_offset")
	if absf(ns.law_structural_offset_pct - before_structural) > 1e-12:
		_fail("a struck bill wrote the structural offset")
	if law.cooldown_months > 0 and not ns.law_cooldown_months.has(law.id):
		_fail("a struck bill carries no cooldown")


## DELIBERATELY NOT IN apply() -- tests, probes, tools/screenshot.gd and
## tools/balance_probe.gd all call it directly to set up state -- and deliberately not in
## apply_effects(), whose second caller since V1.8 is an event choice. Read off the source
## as well as behaviour, so a later session moving the gate has to come and say why.
func _test_the_gate_is_not_in_apply() -> void:
	var state = _state()
	var ns = state.player()
	var law = _struck_law(ns)
	if law != null:
		# Read on the CHANNELS rather than on `passed_law_ids`, because the first version
		# of this check did the latter and a `once: false` law never sets that flag -- so
		# it reported the gate in the wrong place on a law apply() had applied correctly.
		var before := _fingerprint(ns)
		Legislature.apply(state, ns, law, _loader)
		if _fingerprint(ns) == before:
			_fail("apply() refused a law the court would strike -- the gate is in the wrong place")

	var src := FileAccess.get_file_as_string("res://src/sim/legislature.gd")
	if src.is_empty():
		_fail("could not read src/sim/legislature.gd")
		return
	var in_apply_effects := false
	for line in src.split("\n"):
		if line.begins_with("static func apply_effects("):
			in_apply_effects = true
		elif line.begins_with("static func ") and in_apply_effects:
			in_apply_effects = false
		elif in_apply_effects and line.contains("Judiciary."):
			_fail("apply_effects() calls the court -- an event choice would be gated too")


## A law the country has ratified is not reviewable: the Conseil constitutionnel declined
## jurisdiction over a referendum law in 1962. It agrees with the amendment exclusion,
## since a referendum in this game only ever ratifies one -- so the source is read for the
## call rather than the behaviour tested through a route that cannot reach it.
func _test_a_ratified_law_is_not_reviewable() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/legislature.gd")
	if src.is_empty():
		return
	var in_settle := false
	for line in src.split("\n"):
		if line.begins_with("static func _settle_referendum("):
			in_settle = true
		elif line.begins_with("static func ") and in_settle:
			in_settle = false
		elif in_settle and line.contains("_review_and_apply"):
			_fail("_settle_referendum() sends a ratified law to the court")


## The gate MOVES, which is what makes it a decision rather than a filter. Each rung is
## itself passable at the independence it is reached at -- the ladder has a first step --
## and the set of laws the court blocks shrinks as the ladder is climbed.
func _test_the_ladder_moves_the_gate() -> void:
	var state = _state()
	var ns = state.player()
	var blocked_before: int = _blocked_count(ns)
	var independence_before: float = ns.judicial_independence

	for law_id in WEAKEN:
		var law = _law(law_id)
		if law == null:
			_fail("the ladder names %s and the content does not have it" % law_id)
			return
		if Judiciary.strikes_down(ns, law):
			_fail("%s is struck by the court it weakens -- the ladder has no first step" % law_id)
			return
		Legislature.apply(state, ns, law, _loader)

	if ns.judicial_independence >= independence_before:
		_fail("the ladder did not weaken the court")
	if _blocked_count(ns) >= blocked_before:
		_fail("capturing the court unlocked nothing -- the key does not work")

	# And the strengthening rung is not inert on a clean state, which is what
	# docs/companies-model.md's V1.4b argument buys and what a one-way level would lose.
	var fresh = _state().player()
	var up = _law(STRENGTHEN)
	if up == null:
		_fail("no strengthening rung in the content")
		return
	Legislature.apply(_state(), fresh, up, _loader)
	if fresh.judicial_independence <= fresh.start_judicial_independence:
		_fail("the strengthening Act is inert on a clean state")


func _test_capture_is_not_a_master_key() -> void:
	var state = _state()
	var ns = state.player()
	for law_id in WEAKEN:
		var law = _law(law_id)
		if law != null:
			Legislature.apply(state, ns, law, _loader)
	if _blocked_count(ns) < 1:
		_fail("a fully captured court blocks nothing -- capture is a master key")


## The DEVIATION and not the level: Italy is not angrier than Switzerland on frame one.
func _test_the_grievance_reads_the_deviation() -> void:
	var state = _state()
	for ns in state.nations.values():
		if absf(Judiciary.independence_deviation(ns)) > 1e-12:
			_fail("%s carries a judicial deviation at new game" % ns.id)
		if absf(Judiciary.unrest_load(ns)) > 1e-12:
			_fail("%s carries a judicial grievance load at new game" % ns.id)

	var ns = state.player()
	var quiet := Unrest.unrest_target(ns)
	var law = _law(WEAKEN[0])
	if law == null:
		return
	Legislature.apply(state, ns, law, _loader)
	if Unrest.unrest_target(ns) <= quiet:
		_fail("weakening the courts did not raise the grievance")


func _test_judiciary_is_a_leaf() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/judiciary.gd")
	if src.is_empty():
		_fail("could not read src/sim/judiciary.gd")
		return
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("const"):
			continue
		if line.contains("res://src/sim/") and not line.contains("judiciary_constants.gd"):
			_fail("judiciary.gd preloads a system: %s" % line.strip_edges())
		if line.contains("res://src/core/"):
			_fail("judiciary.gd preloads a core type: %s" % line.strip_edges())


## `judicial_independence` has exactly ONE writer, and it is the function that owns the
## other five effects.society registers. A second would be the divergence the symmetric
## pair key exists to make impossible.
func _test_one_writer() -> void:
	var writers: Array[String] = []
	for path in ["res://src/sim/judiciary.gd", "res://src/sim/legislature.gd",
			"res://src/sim/unrest.gd", "res://src/sim/society.gd",
			"res://src/sim/chambers.gd", "res://src/sim/elections.gd",
			"res://src/sim/government.gd"]:
		var src := FileAccess.get_file_as_string(path)
		for line in src.split("\n"):
			var text := line.strip_edges()
			if text.begins_with("#"):
				continue
			if text.contains("ns.judicial_independence =") or text.contains("ns.judicial_independence +="):
				writers.append("%s: %s" % [path, text])
	# judiciary.gd's init_nation seeds it; legislature.gd's apply_effects moves it.
	if writers.size() != 2:
		_fail("judicial_independence has %d writers, expected 2 (seed + apply_effects): %s"
			% [writers.size(), writers])


## Everything Legislature.apply_effects() can write, as one comparable string.
func _fingerprint(ns) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		ns.bloc_offset, ns.law_structural_offset_pct, ns.law_potential_target_pct,
		ns.law_other_revenue_pct_gdp, ns.regulation_burden, ns.corruption,
		ns.migration_stance, ns.settlement_stance, ns.press_freedom,
	]


func _blocked_count(ns) -> int:
	var count := 0
	for law in _loader.laws:
		if Judiciary.strikes_down(ns, law):
			count += 1
	return count


## The first law both chambers carry and the court then strikes. Found in the content
## rather than named, so a content edit cannot leave the test measuring nothing.
func _struck_law(ns):
	var party_list: Array = _loader.parties.get(PLAYER, [])
	for law in _loader.laws:
		if law.constitutional:
			continue
		if not Judiciary.strikes_down(ns, law):
			continue
		if not bool(Legislature.resolve_vote(ns, party_list, law, false)["passed"]):
			continue
		if not bool(Legislature.resolve_upper(ns, party_list, law)["passed"]):
			continue
		return law
	return null
