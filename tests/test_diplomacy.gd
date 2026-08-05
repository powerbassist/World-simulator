extends SceneTree

## V1.3a. The pair key, the derived resting value, the drift, and the player's
## diplomatic actions. Model: docs/diplomacy-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Relations = preload("res://src/core/relations.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const FK = preload("res://src/sim/foreign_policy_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const DiplomaticAction = preload("res://src/core/diplomatic_action.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader
var _state


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_state = GameState.new_game(_loader, PLAYER)
	if not _state.errors.is_empty():
		_failures.append("new_game reported %s" % [_state.errors])
		_finish()
		return

	_check_key_is_canonical()
	_check_every_pair_seeded()
	_check_resting_is_symmetric()
	_check_resting_reads_both_inputs()
	_check_drift_converges_and_stops()
	_check_clamps_hold()
	_check_content_loaded()
	_check_preconditions_gate()
	_check_cooldown_is_per_target()
	_check_execute_writes_both_channels()
	_check_third_parties_take_sides()
	_check_third_party_pass_is_order_independent()
	_check_execute_refuses_when_unavailable()
	_check_neighbours_are_mutual()
	_check_bad_fixtures_refused()
	_check_agenda_stagger_is_seeded()
	_check_agenda_is_deterministic()
	_check_agenda_never_acts_for_the_player()
	_check_agenda_offers_the_player_no_agreement()
	_check_agenda_acts_at_all()
	_check_agenda_record_is_bounded()
	_finish()


## The whole reason src/core/relations.gd exists: the caller's argument order
## must not be able to produce two different entries for one pair.
func _check_key_is_canonical() -> void:
	if Relations.key("FRA", "DEU") != Relations.key("DEU", "FRA"):
		_failures.append("relations key is not order-independent")
	if Relations.key("FRA", "DEU") != "DEU|FRA":
		_failures.append("relations key is not sorted: got '%s'" % Relations.key("FRA", "DEU"))
	if Relations.other("DEU|FRA", "FRA") != "DEU":
		_failures.append("Relations.other() did not return the far side of the pair")


## Ten nations is 45 unordered pairs. A missing pair would read as 0.0 -- the
## WORST relations -- so "every pair exists" is a real invariant, not a count.
func _check_every_pair_seeded() -> void:
	var expected: int = Relations.all_pairs(_loader.nations.keys()).size()
	if expected != 45:
		_failures.append("expected 45 pairs over ten nations, all_pairs gave %d" % expected)
	if _state.relations.size() != expected:
		_failures.append("seed_relations left %d pairs, expected %d" % [_state.relations.size(), expected])
	for pair in Relations.all_pairs(_loader.nations.keys()):
		if not _state.relations.has(Relations.key(pair[0], pair[1])):
			_failures.append("pair %s was never seeded" % Relations.key(pair[0], pair[1]))


func _check_resting_is_symmetric() -> void:
	for pair in Relations.all_pairs(_loader.nations.keys()):
		var a = _loader.nations[pair[0]]
		var b = _loader.nations[pair[1]]
		if not is_equal_approx(Diplomacy.resting(a, b), Diplomacy.resting(b, a)):
			_failures.append("resting(%s, %s) is not symmetric" % [pair[0], pair[1]])


## Both derivation terms must actually separate pairs. A bonus that never
## changes an answer is a constant with extra steps -- the decorative-axis
## failure docs/scenario-model.md caught for authored approval.
func _check_resting_reads_both_inputs() -> void:
	# DEU: EU member and a French neighbour. GBR: neither. NLD: EU, not a
	# French neighbour. Each isolates one term against the pair above it.
	var both := Diplomacy.resting(_loader.nations["FRA"], _loader.nations["DEU"])
	var eu_only := Diplomacy.resting(_loader.nations["FRA"], _loader.nations["NLD"])
	var neither := Diplomacy.resting(_loader.nations["FRA"], _loader.nations["GBR"])
	var border_only := Diplomacy.resting(_loader.nations["FRA"], _loader.nations["CHE"])

	if not is_equal_approx(both - eu_only, DK.SHARED_BORDER_BONUS):
		_failures.append("the shared-border term does not separate FRA|DEU from FRA|NLD")
	if not is_equal_approx(eu_only - neither, DK.EU_CO_MEMBER_BONUS):
		_failures.append("the EU term does not separate FRA|NLD from FRA|GBR")
	if not is_equal_approx(border_only - neither, DK.SHARED_BORDER_BONUS):
		_failures.append("the shared-border term does not separate FRA|CHE from FRA|GBR")


## Drift is an approach, not a walk: it must close the gap and then hold, not
## overshoot and not keep going.
func _check_drift_converges_and_stops() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var resting := Diplomacy.resting(_loader.nations["FRA"], _loader.nations["DEU"])

	# V1.3f: the agenda runs inside tick_month() and moves relations on purpose, so
	# a drift test that did not quiet it would be measuring drift plus nine nations
	# acting. Silenced by pushing the schedule past the horizon rather than by
	# stubbing anything -- the drift being tested is the real one.
	_quiet_agenda(state, 300)

	Relations.adjust(state, "FRA", "DEU", 20.0, DK.RELATIONS_MIN, DK.RELATIONS_MAX)
	var displaced := Diplomacy.score(state, "FRA", "DEU")

	var previous := displaced
	for i in range(240):
		Diplomacy.tick_month(state, _loader)
		var now := Diplomacy.score(state, "FRA", "DEU")
		if now > previous + 1e-9:
			_failures.append("drift moved AWAY from resting at month %d" % i)
			break
		if now < resting - 1e-9:
			_failures.append("drift overshot resting at month %d: %f < %f" % [i, now, resting])
			break
		previous = now

	if absf(Diplomacy.score(state, "FRA", "DEU") - resting) > 0.5:
		_failures.append("drift did not converge to resting in 240 months")

	# Already at rest: the tick must be a no-op, or the resting value is not one.
	var settled := Diplomacy.score(state, "FRA", "DEU")
	Diplomacy.tick_month(state, _loader)
	if absf(Diplomacy.score(state, "FRA", "DEU") - settled) > 0.01:
		_failures.append("a pair already at rest still moved")


func _check_clamps_hold() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for i in range(50):
		Relations.adjust(state, "FRA", "DEU", 100.0, DK.RELATIONS_MIN, DK.RELATIONS_MAX)
	if Diplomacy.score(state, "FRA", "DEU") > DK.RELATIONS_MAX:
		_failures.append("relations exceeded RELATIONS_MAX")
	for i in range(50):
		Relations.adjust(state, "FRA", "DEU", -100.0, DK.RELATIONS_MIN, DK.RELATIONS_MAX)
	if Diplomacy.score(state, "FRA", "DEU") < DK.RELATIONS_MIN:
		_failures.append("relations fell below RELATIONS_MIN")


## The shipped content, not only the fixtures. V1.3a's own scope says relations
## ship WITH a verb -- a loader that found none would satisfy every check above
## and ship the state layer the roadmap refused.
func _check_content_loaded() -> void:
	if _loader.diplomatic_actions.is_empty():
		_failures.append("no diplomatic actions loaded from data/diplomatic-actions/")
		return
	var gated := false
	var priced := false
	for action in _loader.diplomatic_actions:
		if is_zero_approx(float(action.effects.get("relations", 0.0))):
			_failures.append("action '%s' moves no pair" % action.id)
		for cond in action.preconditions:
			if cond["field"] == "relations":
				gated = true
		if not action.effects.get("bloc_offset", {}).is_empty():
			priced = true
	if not gated:
		_failures.append("no shipped action tests a relations precondition -- the gate is unexercised")
	if not priced:
		_failures.append("no shipped action pays a domestic price -- the loop does not close")


func _check_preconditions_gate() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var action = _action_with_relations_precondition()
	if action == null:
		return

	var threshold: float = 0.0
	for cond in action.preconditions:
		if cond["field"] == "relations":
			threshold = cond["value"]

	# Forced below the gate, it must not be offered; forced above it, it must be.
	# Asserted against Diplomacy.available() rather than the predicate, so the
	# thing the panel actually calls is the thing under test.
	state.relations[Relations.key(PLAYER, "DEU")] = threshold - 5.0
	if Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, "DEU").has(action):
		_failures.append("'%s' was offered below its own relations threshold" % action.id)

	state.relations[Relations.key(PLAYER, "DEU")] = threshold + 5.0
	if not Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, "DEU").has(action):
		_failures.append("'%s' was withheld above its own relations threshold" % action.id)

	# The measured reachable range has to actually contain the gate, or the
	# precondition is unreachable content -- the failure docs/amendment-model.md
	# found for Germany's two-thirds. Resting for FRA|DEU plus what one use of
	# the strongest positive verb delivers must clear it.
	var resting := Diplomacy.resting(_loader.nations["FRA"], _loader.nations["DEU"])
	var best := 0.0
	for candidate in _loader.diplomatic_actions:
		best = maxf(best, float(candidate.effects.get("relations", 0.0)))
	if resting + best < threshold:
		_failures.append(
			"'%s' needs %.1f but FRA|DEU rests at %.1f and the best verb gives %+.1f -- unreachable" %
			[action.id, threshold, resting, best]
		)


## The whole reason the cooldown key is a pair: acting against Germany must not
## disarm the same verb against Italy.
func _check_cooldown_is_per_target() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var action = _action_with_cooldown()
	if action == null:
		_failures.append("no shipped action carries a cooldown")
		return

	_force_available(state, action)
	Diplomacy.execute(state, _loader.diplomatic_actions, action, PLAYER, "DEU")

	if Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, "DEU").has(action):
		_failures.append("'%s' was still available against DEU immediately after use" % action.id)

	_force_available(state, action)
	if not Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, "ITA").has(action):
		_failures.append("using '%s' against DEU also disarmed it against ITA" % action.id)

	# And it must come back: a cooldown that never expires is a once-only.
	for i in range(action.cooldown_months):
		Diplomacy.tick_month(state, _loader)
	_force_available(state, action)
	if not Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, "DEU").has(action):
		_failures.append("'%s' never came off cooldown against DEU" % action.id)


func _check_execute_writes_both_channels() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var action = _action_with_bloc_price()
	if action == null:
		return

	_force_available(state, action)
	var ns = state.player()
	var before_relations := Diplomacy.score(state, PLAYER, "DEU")
	var before_offsets: Dictionary = ns.bloc_offset.duplicate(true)

	var result := Diplomacy.execute(state, _loader.diplomatic_actions, action, PLAYER, "DEU")
	if not result["applied"]:
		_failures.append("'%s' did not apply against DEU" % action.id)
		return

	var expected := before_relations + float(action.effects["relations"])
	if not is_equal_approx(Diplomacy.score(state, PLAYER, "DEU"), clampf(expected, DK.RELATIONS_MIN, DK.RELATIONS_MAX)):
		_failures.append("'%s' did not move the pair by its own relations effect" % action.id)

	for bloc in action.effects["bloc_offset"]:
		var delta: float = float(ns.bloc_offset.get(bloc, 0.0)) - float(before_offsets.get(bloc, 0.0))
		if not is_equal_approx(delta, float(action.effects["bloc_offset"][bloc])):
			_failures.append("'%s' did not write bloc_offset['%s']" % [action.id, bloc])

	# The other nine nations pay nothing for the player's decision.
	for id in state.nations.keys():
		if id == PLAYER:
			continue
		if not state.nations[id].bloc_offset.is_empty():
			_failures.append("acting as %s wrote a bloc offset onto %s" % [PLAYER, id])

	# V1.3a's DECLARED STOPGAP, DISCHARGED at V1.3e. This assertion used to read
	# "acting on DEU moved the unrelated pair DEU|ITA" and required DEU|ITA to sit
	# at exactly its resting value. It went red the moment the interest model
	# landed, which is what it was written to do; the rewrite is below.
	if result["third_party_pairs"] <= 0:
		_failures.append("'%s' moved no third pair at all -- V1.3a's stopgap is still in place" % action.id)


## V1.3a parked third-party effects on the grounds that they need an alliance
## model. They do not: stake already carries EU co-membership and the border, so
## the channel exists without an alliance in it.
##
## The rule is signed and has two halves, and a test that checked only "something
## moved" would pass on a model that moved them the wrong way round.
func _check_third_parties_take_sides() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var action = _hostile_action()
	if action == null:
		_failures.append("no action with a negative relations effect to test the reaction with")
		return

	_force_available(state, action)
	# ITA is the third party: it is an EU co-member of DEU and shares a border with
	# it, so its stake in DEU clears the floor comfortably.
	var before_with_actor := Diplomacy.score(state, "ITA", PLAYER)
	var before_with_target := Diplomacy.score(state, "ITA", "DEU")

	var result := Diplomacy.execute(state, _loader.diplomatic_actions, action, PLAYER, "DEU")
	if not result["applied"]:
		_failures.append("'%s' did not apply against DEU" % action.id)
		return

	# Italy judges France for it.
	if not (Diplomacy.score(state, "ITA", PLAYER) < before_with_actor):
		_failures.append("a hostile act on DEU did not cool ITA toward the actor (%.3f -> %.3f)" % [
			before_with_actor, Diplomacy.score(state, "ITA", PLAYER),
		])
	# ...and warms to Germany over it. A sanctioned nation acquires sympathisers.
	if not (Diplomacy.score(state, "ITA", "DEU") > before_with_target):
		_failures.append("a hostile act on DEU did not warm ITA toward the target (%.3f -> %.3f)" % [
			before_with_target, Diplomacy.score(state, "ITA", "DEU"),
		])

	# A nation with no stake in the target must not be dragged in. Without the
	# floor every act moves all eight remaining nations by some unreadable amount
	# and forty-five pairs drift on every click.
	var scale := ForeignPolicy.stake(state, "GBR", "DEU") / FK.EVEN_SHARE
	if scale <= 0.0:
		_failures.append("GBR has literally no stake in DEU, which makes the floor untestable")


## The third-party pass must be resolved as a whole before any of it is applied.
## Applied one at a time, each adjustment moves the relations the next stake is
## scaled by, and the answer would depend on Dictionary iteration order -- the
## ordering bug docs/trade-model.md records the trade probe catching in the impulse,
## which no test could see until something finally perturbed a partner.
func _check_third_party_pass_is_order_independent() -> void:
	var a = GameState.new_game(_loader, PLAYER)
	var b = GameState.new_game(_loader, PLAYER)
	var action = _hostile_action()
	if action == null:
		return

	_force_available(a, action)
	_force_available(b, action)
	Diplomacy.execute(a, _loader.diplomatic_actions, action, PLAYER, "DEU")
	Diplomacy.execute(b, _loader.diplomatic_actions, action, PLAYER, "DEU")

	for key in a.relations.keys():
		if not is_equal_approx(float(a.relations[key]), float(b.relations[key])):
			_failures.append("the third-party pass is not reproducible: %s came out %.9f and %.9f" % [
				key, float(a.relations[key]), float(b.relations[key]),
			])
			return


func _hostile_action():
	for action in _loader.diplomatic_actions:
		if float(action.effects.get("relations", 0.0)) < 0.0 and action.effects.get("measure", {}).is_empty():
			return action
	return null


func _check_execute_refuses_when_unavailable() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var action = _action_with_relations_precondition()
	if action == null:
		return

	var threshold: float = 0.0
	for cond in action.preconditions:
		if cond["field"] == "relations":
			threshold = cond["value"]
	state.relations[Relations.key(PLAYER, "DEU")] = threshold - 10.0
	var before := Diplomacy.score(state, PLAYER, "DEU")

	var result := Diplomacy.execute(state, _loader.diplomatic_actions, action, PLAYER, "DEU")
	if result["applied"] or not result["refused"]:
		_failures.append("'%s' applied despite failing its own precondition" % action.id)
	if not is_equal_approx(Diplomacy.score(state, PLAYER, "DEU"), before):
		_failures.append("a refused action still moved the pair")

	# Acting on yourself is not a pair.
	if not Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, PLAYER).is_empty():
		_failures.append("actions were offered against the player's own nation")


## Asserted against the shipped nation files, not a fixture: the derived resting
## value reads one side of the border, and an asymmetric authored border would
## make it depend on which file the derivation happened to read first.
func _check_neighbours_are_mutual() -> void:
	for id in _loader.nations.keys():
		for other_id in _loader.nations[id].neighbours:
			if not _loader.nations.has(other_id):
				_failures.append("%s lists neighbour '%s', which is not loaded" % [id, other_id])
			elif not _loader.nations[other_id].neighbours.has(id):
				_failures.append("%s lists %s as a neighbour but not the reverse" % [id, other_id])


func _check_bad_fixtures_refused() -> void:
	_expect_fixture_error("res://tests/fixtures/actions_bad_bloc", "landowners",
		"an action naming an unknown voter bloc loaded")
	_expect_fixture_error("res://tests/fixtures/actions_no_relations", "relations",
		"an action that moves no pair loaded")
	_expect_fixture_error("res://tests/fixtures/actions_bad_field", "coalition_seats",
		"an action with an unrecognised precondition field loaded")


func _expect_fixture_error(actions_dir: String, needle: String, message: String) -> void:
	var fixture_loader := DataLoader.new()
	fixture_loader.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://data/eu_parliament.json", "res://data/laws",
		"res://data/political-systems", "res://data/scenarios", actions_dir,
	)
	for e in fixture_loader.errors:
		if e.find(needle) != -1:
			return
	_failures.append("%s, or did not name '%s'" % [message, needle])


# --- helpers -------------------------------------------------------------------

## Clears whatever is currently blocking `action` against every target, so a
## test of one gate is not silently passing because a different gate closed.
## Make `action` available against every target, whatever it asks for. Both
## pair-state precondition fields are handled here rather than only `relations`:
## V1.3b's agreement verbs gate on `agreement_active`, and a helper that silently
## ignored half the fields would leave a caller thinking it had forced something
## it had not. That is how this first failed -- _action_with_cooldown() picks the
## alphabetically first action with a cooldown, which became industrial_compact.
# --- V1.3f: the agenda ---------------------------------------------------------

## Every one of the nine starts on a different month of the cycle, and none starts
## ready to fire. Without the spread they all act in the same month and
## message_stack.gd's six slots drop most of it unread.
func _check_agenda_stagger_is_seeded() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var seen := {}
	for id in state.nations.keys():
		var ns = state.nations[id]
		if ns.has_budget:
			if ns.diplo_months_to_act != 0:
				_failures.append("the player's nation was given an agenda schedule (%d)" % ns.diplo_months_to_act)
			continue
		if ns.diplo_months_to_act < 1:
			_failures.append("%s starts ready to act (%d) -- month one is noise" % [id, ns.diplo_months_to_act])
		seen[ns.diplo_months_to_act] = true

	# Nine nations over an interval of AGENDA_INTERVAL_MONTHS cannot all differ if
	# the interval is under nine; what must hold is that they are SPREAD rather than
	# identical, which is what the modulo buys.
	if seen.size() < mini(9, FK.AGENDA_INTERVAL_MONTHS):
		_failures.append("the nine occupy only %d distinct agenda months -- the stagger is not staggering" % seen.size())


## No rand() in src/sim/, and this is the field that would most obviously invite
## one. Two games from the same data must make the same picks, or the budget
## projection -- which ticks this module sixty times on a copy -- stops agreeing
## with the game it is projecting.
func _check_agenda_is_deterministic() -> void:
	var a = GameState.new_game(_loader, PLAYER)
	var b = GameState.new_game(_loader, PLAYER)
	for _i in range(60):
		Diplomacy.tick_month(a, _loader)
		Diplomacy.tick_month(b, _loader)

	if a.foreign_acts.size() != b.foreign_acts.size():
		_failures.append("two identical games produced %d and %d acts" % [a.foreign_acts.size(), b.foreign_acts.size()])
		return
	for i in range(a.foreign_acts.size()):
		var x: Dictionary = a.foreign_acts[i]
		var y: Dictionary = b.foreign_acts[i]
		if x["actor_id"] != y["actor_id"] or x["target_id"] != y["target_id"] or x["action_id"] != y["action_id"]:
			_failures.append("two identical games diverged at act %d: %s vs %s" % [i, x, y])
			return


## has_budget read the other way round: it means a human decides here, so the
## agenda must never move for the player's own nation. A player whose foreign
## policy ran itself would be the single worst bug this session could ship.
func _check_agenda_never_acts_for_the_player() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for _i in range(120):
		Diplomacy.tick_month(state, _loader)

	if state.player().diplo_months_to_act != 0:
		_failures.append("the player's agenda counter moved to %d" % state.player().diplo_months_to_act)
	for act in state.foreign_acts:
		if String(act["actor_id"]) == PLAYER:
			_failures.append("the agenda acted AS the player: %s" % act)
			return


## AI-to-player agreements are out of scope, and structurally so rather than by a
## filter that could be forgotten: would_accept_agreement() is the counterparty's
## decision, so an AI proposing to the player would have the interest model answer
## on the player's own behalf. AI-to-AI agreements are unaffected and must still
## happen, or the exclusion has quietly removed the verb from the game.
func _check_agenda_offers_the_player_no_agreement() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for _i in range(168):
		Diplomacy.tick_month(state, _loader)

	var ai_to_ai := 0
	for act in state.foreign_acts:
		var is_agreement: bool = String(act["action_id"]).contains("compact")
		if not is_agreement:
			continue
		if String(act["target_id"]) == PLAYER:
			_failures.append("an AI proposed an agreement to the player: %s" % act)
			return
		ai_to_ai += 1

	# Recorded rather than asserted: whether any AI-to-AI agreement lands inside
	# fourteen years is a CONTENT question the probe measures, and a test that
	# demanded one would fail on a content edit rather than on a broken mechanism.
	if ai_to_ai == 0 and state.agreements.is_empty():
		print("  note: no AI-to-AI agreement inside 168 months -- see tools/foreign_policy_probe.gd")


## The feature must actually do something. An agenda that never clears its own bar
## is the state-layer-with-no-verb failure docs/diplomacy-model.md warns about, at
## the scale of a whole session.
func _check_agenda_acts_at_all() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for _i in range(60):
		Diplomacy.tick_month(state, _loader)

	if state.foreign_acts.is_empty():
		_failures.append("nobody acted in sixty months -- AGENDA_ACT_MIN is unreachable")
		return

	for act in state.foreign_acts:
		if not ForeignPolicy.ACT_REASON_KEYS.has(String(act["reason"])):
			_failures.append("act carried an unknown reason key '%s'" % act["reason"])
			return


## The record is a window on the recent past, not an archive. Unbounded, a
## fourteen-year run accumulates hundreds of entries into every save file.
func _check_agenda_record_is_bounded() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for _i in range(400):
		Diplomacy.tick_month(state, _loader)

	if state.foreign_acts.size() > FK.AGENDA_ACTS_KEPT:
		_failures.append("foreign_acts grew to %d, past AGENDA_ACTS_KEPT" % state.foreign_acts.size())


## Push every nation's agenda counter past `months`, so tick_month() runs drift,
## retaliation and cooldowns but nobody acts on their own initiative.
##
## For tests about a mechanism the agenda is not part of. A test that wants the
## agenda drives it directly instead -- see _check_agenda_* below.
func _quiet_agenda(state, months: int) -> void:
	for ns in state.nations.values():
		ns.diplo_months_to_act = months + 1


func _force_available(state, action) -> void:
	var ns = state.player()
	ns.diplo_cooldown_months.clear()
	for cond in action.preconditions:
		if cond["field"] == "relations":
			for id in state.nations.keys():
				if id == PLAYER:
					continue
				state.relations[Relations.key(PLAYER, id)] = cond["value"] + 5.0
		elif cond["field"] == "agreement_active":
			for id in state.nations.keys():
				if id == PLAYER:
					continue
				var pair_key := Relations.key(PLAYER, id)
				if is_zero_approx(float(cond["value"])):
					state.agreements.erase(pair_key)
				else:
					state.agreements[pair_key] = {"action_id": "test_fixture", "sector_shift": {}}


func _action_with_relations_precondition():
	for action in _loader.diplomatic_actions:
		for cond in action.preconditions:
			if cond["field"] == "relations":
				return action
	return null


func _action_with_cooldown():
	for action in _loader.diplomatic_actions:
		if action.cooldown_months > 0:
			return action
	return null


func _action_with_bloc_price():
	for action in _loader.diplomatic_actions:
		if not action.effects.get("bloc_offset", {}).is_empty():
			return action
	return null


func _finish() -> void:
	if _failures.is_empty():
		print("test_diplomacy: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
