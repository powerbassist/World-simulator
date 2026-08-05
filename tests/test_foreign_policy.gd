extends SceneTree

## Headless test: godot --headless --script res://tests/test_foreign_policy.gd
## Non-zero exit on any failure.
##
## V1.3e. The interest model: stake, amity, and the four decisions that replaced
## the four declared stopgaps. Model: docs/foreign-policy-model.md.
##
## The decisions themselves are asserted where they are READ -- tests/test_trade.gd
## for the accept gate, tests/test_coercion.gd for the answer, tests/test_bloc.gd
## for the council, tests/test_diplomacy.gd for the third-party pass. What is
## asserted HERE is the model underneath all four, and the two properties the whole
## session rests on: that the nine differ from each other, and that ideology is the
## weak term rather than the strong one.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Relations = preload("res://src/core/relations.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const K = preload("res://src/sim/foreign_policy_constants.gd")
const CK = preload("res://src/sim/coercion_constants.gd")
const Trade = preload("res://src/sim/trade.gd")

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

	_check_stake_normalises()
	_check_stake_is_directed()
	_check_resting_agrees_with_diplomacy()
	_check_amity_is_exactly_zero_at_new_game()
	_check_amity_is_signed_and_bounded()
	_check_ideology_is_the_weak_term()
	_check_third_party_floor_holds()
	_check_third_party_effects_are_signed()
	_check_retaliation_is_bounded()
	_check_reason_keys_are_declared()
	_finish()


# --- stake -------------------------------------------------------------------------

func _check_stake_normalises() -> void:
	for id in _state.nations.keys():
		var vector := ForeignPolicy.stake_vector(_state, String(id))
		if vector.size() != _state.nations.size() - 1:
			_failures.append("%s's stake vector has %d entries, expected %d" % [
				id, vector.size(), _state.nations.size() - 1,
			])
		var total := 0.0
		for partner in vector.keys():
			if float(vector[partner]) < 0.0:
				_failures.append("%s -> %s stake is negative" % [id, partner])
			total += float(vector[partner])
		if not is_equal_approx(total, 1.0):
			_failures.append("%s's stake vector sums to %f, not 1.0" % [id, total])


## The property the whole model is built on, and the one a symmetric relations
## score could never express. Luxembourg's foreign policy is mostly about Germany;
## Germany's is barely about Luxembourg.
func _check_stake_is_directed() -> void:
	var lux_on_deu := ForeignPolicy.stake(_state, "LUX", "DEU")
	var deu_on_lux := ForeignPolicy.stake(_state, "DEU", "LUX")
	if not (lux_on_deu > deu_on_lux):
		_failures.append("stake(LUX->DEU) %f is not above stake(DEU->LUX) %f -- the model is not directed" % [
			lux_on_deu, deu_on_lux,
		])


## src/sim/foreign_policy.gd carries its OWN copy of the resting derivation,
## because it cannot preload src/sim/diplomacy.gd -- that file preloads this one,
## and GDScript refuses the cycle. The copy reads NationState where the original
## reads loader Nation objects.
##
## Duplication declared in the comment there and PINNED here rather than trusted:
## if the two ever disagree, amity stops being zero at rest for the pairs they
## disagree about, and every threshold in the model quietly shifts under those
## pairs alone. Asserted over all forty-five.
func _check_resting_agrees_with_diplomacy() -> void:
	for pair in Relations.all_pairs(_loader.nations.keys()):
		var a: String = pair[0]
		var b: String = pair[1]
		var by_diplomacy := Diplomacy.resting(_loader.nations[a], _loader.nations[b])
		# The seeded value IS Diplomacy.resting(), so a non-zero amity at new-game
		# is exactly the two derivations disagreeing.
		var drift := ForeignPolicy.amity(_state, a, b) - K.AMITY_IDEOLOGY_WEIGHT * (
			2.0 * _alignment(a, b) - 1.0
		)
		if absf(drift) > 1.0e-9:
			_failures.append(
				"ForeignPolicy's resting derivation disagrees with Diplomacy.resting() for %s|%s (Diplomacy says %.4f, amity is off by %.9f)" % [
					a, b, by_diplomacy, drift,
				]
			)
			return


# --- amity -------------------------------------------------------------------------

## Every pair reads exactly zero sentiment at new-game, because amity is
## displacement from rest and nothing has acted yet. Exactly, not approximately:
## this is what keeps the balance harness's question answerable, the same property
## docs/trade-model.md's openness index and docs/coercion-model.md's trade
## multiplier have.
##
## The ideology term is the one thing that is non-zero at rest, so it is subtracted
## before the comparison rather than the assertion being weakened.
func _check_amity_is_exactly_zero_at_new_game() -> void:
	for pair in Relations.all_pairs(_loader.nations.keys()):
		var a: String = pair[0]
		var b: String = pair[1]
		var relations_part := ForeignPolicy.amity(_state, a, b) - K.AMITY_IDEOLOGY_WEIGHT * (
			2.0 * _alignment(a, b) - 1.0
		)
		if relations_part != 0.0:
			_failures.append("%s|%s carries %.17f of sentiment at new-game, not exactly 0.0" % [
				a, b, relations_part,
			])
			return

	# And the GBR case specifically, because it is the one a global neutral got
	# wrong: Britain rests at the floor with all nine, and that must read as
	# UNATTACHED rather than as HOSTILE. The probe measured the alternative closing
	# agreements to Britain entirely, 0 of 9.
	for id in _state.nations.keys():
		if id == "GBR":
			continue
		if ForeignPolicy.amity(_state, "GBR", String(id)) < 0.0:
			_failures.append(
				"GBR reads as hostile toward %s at new-game (%.3f) -- structure is being counted as sentiment" % [
					id, ForeignPolicy.amity(_state, "GBR", String(id)),
				]
			)
			return


func _check_amity_is_signed_and_bounded() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var key := Relations.key(PLAYER, "DEU")
	var rest := float(state.relations[key])

	state.relations[key] = rest + 15.0
	var warm := ForeignPolicy.amity(state, PLAYER, "DEU")
	state.relations[key] = rest - 15.0
	var cold := ForeignPolicy.amity(state, PLAYER, "DEU")
	if not (warm > 0.0 and cold < 0.0):
		_failures.append("amity is not signed around rest: +15 gave %.3f, -15 gave %.3f" % [warm, cold])

	for extreme in [0.0, 100.0]:
		state.relations[key] = extreme
		var value := ForeignPolicy.amity(state, PLAYER, "DEU")
		if value < -1.0 or value > 1.0:
			_failures.append("amity left [-1, 1] at relations %.0f: %.3f" % [extreme, value])


# --- the session's central call ------------------------------------------------------

## THE assertion this whole session rests on. tools/bloc_probe.gd table (d) shows
## the eight non-player members clustered in ideology space -- economic spans 0.87,
## social 1.13 -- so a model that leaned on coalition_position would give nine
## nations that behave alike, which is docs/trade-model.md's GBR-at-0.000 finding
## in a new place.
##
## Asserted as a COMPARISON rather than as a weight, because a weight is a number a
## later session can move without noticing what it was for: moving a nation's whole
## ideology from one corner of the space to the other must move its stake vector
## LESS than moving one partner's trade weight does.
func _check_ideology_is_the_weak_term() -> void:
	var base := ForeignPolicy.stake_vector(_state, PLAYER)

	var ideological = GameState.new_game(_loader, PLAYER)
	for id in ideological.nations.keys():
		if id == PLAYER:
			continue
		ideological.nations[id].coalition_position = {"economic": 1.0, "social": 1.0}
	ideological.nations[PLAYER].coalition_position = {"economic": -1.0, "social": -1.0}
	var ideology_move := _l1(base, ForeignPolicy.stake_vector(ideological, PLAYER))

	# The material comparison: one pair's relations moved as far as sustained play
	# can move it. Deliberately ONE pair against the ideology test's TEN nations,
	# so the comparison is generous to ideology and still has to come out the other
	# way.
	var material = GameState.new_game(_loader, PLAYER)
	var key := Relations.key(PLAYER, "DEU")
	material.relations[key] = float(material.relations[key]) - 25.0
	var material_move := _l1(base, ForeignPolicy.stake_vector(material, PLAYER))

	if not (material_move > ideology_move):
		_failures.append(
			"moving every nation to an ideological extreme moved the stake vector by %.4f, at least as much as moving ONE pair's relations by 25 points (%.4f) -- ideology is not the weak term and the nine will behave alike" % [
				ideology_move, material_move,
			]
		)


# --- the third-party pass -------------------------------------------------------------

## Without a floor, every act moves all eight remaining nations by some tiny amount
## and forty-five pairs drift on every click for reasons no readout could explain.
func _check_third_party_floor_holds() -> void:
	var effects := ForeignPolicy.third_party_effects(_state, PLAYER, "DEU", -8.0)
	var floor_share := K.EVEN_SHARE * K.THIRD_PARTY_MIN_STAKE_SHARE
	for effect in effects:
		var x: String = String(effect["a"])
		if ForeignPolicy.stake(_state, x, "DEU") < floor_share:
			_failures.append("%s was dragged into an act on DEU with a stake below the floor" % x)
			return

	# A zero-delta act moves nothing at all, or lifting a measure would ripple.
	if not ForeignPolicy.third_party_effects(_state, PLAYER, "DEU", 0.0).is_empty():
		_failures.append("an act with no relations effect still moved third pairs")


## One rule, two halves, and the signs must be opposite. A model that cooled
## everyone toward both parties would be "something moved" and wrong.
func _check_third_party_effects_are_signed() -> void:
	var hostile := ForeignPolicy.third_party_effects(_state, PLAYER, "DEU", -8.0)
	if hostile.is_empty():
		_failures.append("a hostile act on DEU moved no third pair at all")
		return

	for effect in hostile:
		var toward: String = String(effect["b"])
		var delta: float = float(effect["delta"])
		if toward == PLAYER and delta >= 0.0:
			_failures.append("a hostile act did not cool %s toward the actor" % effect["a"])
			return
		if toward == "DEU" and delta <= 0.0:
			_failures.append("a hostile act did not warm %s toward the target" % effect["a"])
			return

	# And the friendly direction is the same rule with the sign flipped, not a
	# second rule that could drift away from this one.
	for effect in ForeignPolicy.third_party_effects(_state, PLAYER, "DEU", 8.0):
		if String(effect["b"]) == PLAYER and float(effect["delta"]) <= 0.0:
			_failures.append("a friendly act did not warm %s toward the actor" % effect["a"])
			return


# --- the answer ------------------------------------------------------------------------

func _check_retaliation_is_bounded() -> void:
	for a in _state.nations.keys():
		for b in _state.nations.keys():
			if a == b:
				continue
			var f := ForeignPolicy.retaliation_fraction(
				_state, String(a), String(b), CK.RETALIATION_FRACTION
			)
			if f < 0.0 or f > CK.RETALIATION_FRACTION:
				_failures.append("%s answering %s gave %.4f, outside [0, %.2f]" % [
					b, a, f, CK.RETALIATION_FRACTION,
				])
				return


# --- the readouts -----------------------------------------------------------------------

## The panels dispatch on these, so a key the model can return and the panel has
## never heard of is a blank line where a reason should be.
func _check_reason_keys_are_declared() -> void:
	var terms := {"weight_multiplier": 1.35}
	for a in _state.nations.keys():
		for b in _state.nations.keys():
			if a == b:
				continue
			var reason := ForeignPolicy.refusal_reason(_state, String(a), String(b), terms)
			if not ForeignPolicy.REFUSAL_KEYS.has(reason):
				_failures.append("refusal_reason() returned '%s', which is not in REFUSAL_KEYS" % reason)
				return

	for p in _loader.bloc_proposals:
		for id in _state.nations.keys():
			var reason := ForeignPolicy.vote_reason(_state, _state.nations[id], p, 0.4)
			if not ForeignPolicy.VOTE_REASON_KEYS.has(reason):
				_failures.append("vote_reason() returned '%s', which is not in VOTE_REASON_KEYS" % reason)
				return


# --- helpers ---------------------------------------------------------------------------

func _alignment(a_id: String, b_id: String) -> float:
	var p1: Dictionary = _state.nations[a_id].coalition_position
	var p2: Dictionary = _state.nations[b_id].coalition_position
	var d_econ: float = float(p1.get("economic", 0.0)) - float(p2.get("economic", 0.0))
	var d_social: float = float(p1.get("social", 0.0)) - float(p2.get("social", 0.0))
	var dist: float = sqrt(d_econ * d_econ + d_social * d_social)
	return clampf(1.0 - dist / ForeignPolicy.MAX_IDEOLOGY_DISTANCE, 0.0, 1.0)


func _l1(a: Dictionary, b: Dictionary) -> float:
	var total := 0.0
	for id in a.keys():
		total += absf(float(a[id]) - float(b.get(id, 0.0)))
	return total


func _finish() -> void:
	if _failures.is_empty():
		print("test_foreign_policy: all checks passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
