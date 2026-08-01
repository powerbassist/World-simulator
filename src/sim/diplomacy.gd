extends RefCounted

## Pair-keyed relations, their monthly drift, and the player's diplomatic
## actions.
##
## The model, and the justification for every constant, is
## docs/diplomacy-model.md. This file is the rules; diplomacy_constants.gd is
## the numbers; src/core/relations.gd is the key.
##
## No rand() anywhere, the same discipline economy.gd, opinion.gd and
## legislature.gd hold to: a relations figure is exactly reproducible from
## state, so the budget projection and a reloaded save agree with a played game.
##
## > [!warning] The counterparty response here is a DECLARED STOPGAP.
## > An action's own `effects.relations` IS the entire reaction: the target
## > nation does not reason, does not retaliate, and third pairs do not move.
## > This is deliberate and named rather than quietly approximated, the same
## > shape `lose_condition: "never"` and `referendum_required` already use for a
## > rule the model declares and does not yet resolve. V1.3e replaces it, and
## > opens with a checklist of these rather than a discovery. See ROADMAP.md.

const RK = preload("res://src/core/relations.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")


## Reset one nation's own diplomacy state. Runs for all ten, same as
## Legislature.init_nation() -- what is per-nation here is the record of what
## this nation has recently DONE, not the relations themselves, which are
## pair-keyed on GameState.
static func init_nation(ns) -> void:
	ns.diplo_cooldown_months = {}
	ns.last_diplomatic_result = {}


## Where a pair's relations settle if nobody acts. Derived from the two inputs
## docs/data-sources.md can actually supply -- EU co-membership, which every
## nation file already carries, and a shared land border, which V1.3a adds as a
## fact rather than a tuning number.
##
## `a` and `b` are loader Nation objects, not NationState: neither input is live
## state and neither ever changes, so re-deriving from static data is correct
## and re-deriving from a played game's state would not be. Symmetric by
## construction -- swapping the arguments cannot change the answer, which is
## what lets src/core/relations.gd's key stay sorted.
static func resting(a, b) -> float:
	var value := DK.REST_BASE
	if a.eu_member and b.eu_member:
		value += DK.EU_CO_MEMBER_BONUS
	if a.neighbours.has(b.id):
		value += DK.SHARED_BORDER_BONUS
	return clampf(value, DK.RELATIONS_MIN, DK.RELATIONS_MAX)


## Seed every unordered pair at its resting value. Called once by
## GameState.new_game(), after every nation exists.
static func seed_relations(state, loader) -> void:
	for pair in RK.all_pairs(loader.nations.keys()):
		var a = loader.nations[pair[0]]
		var b = loader.nations[pair[1]]
		state.relations[RK.key(pair[0], pair[1])] = resting(a, b)


## The pair's current score. Distinct from Relations.score()'s raw dictionary
## read: this one is what the model and the UI should call, and an absent pair
## is a bug rather than a 0.0 -- 0.0 is the WORST possible relations, so a
## silent default here would read as mutual hatred.
static func score(state, a: String, b: String) -> float:
	var k := RK.key(a, b)
	if not state.relations.has(k):
		push_error("diplomacy: no relations entry for '%s' -- seed_relations() did not run" % k)
		return DK.REST_BASE
	return float(state.relations[k])


## Drift every pair toward its resting value, and count down every nation's
## action cooldowns.
##
## `loader` is required rather than defaulted: the resting value is derived from
## static nation data, and a defaulted argument would let the drift silently
## pull toward REST_BASE for every pair -- erasing the EU and border terms that
## are the entire content of the derivation. The same not-defaulted reasoning
## Legislature.apply() gives for its own loader argument.
static func tick_month(state, loader) -> void:
	for pair_key in state.relations.keys():
		# Explicitly String()-wrapped: Dictionary.keys() is untyped, and `:=`
		# cannot infer a type through it.
		var ids: PackedStringArray = String(pair_key).split(RK.SEPARATOR)
		if ids.size() != 2:
			continue
		var a = loader.nations.get(ids[0])
		var b = loader.nations.get(ids[1])
		if a == null or b == null:
			continue
		var current := float(state.relations[pair_key])
		var target := resting(a, b)
		state.relations[pair_key] = clampf(
			current + (target - current) * DK.DRIFT_RATE,
			DK.RELATIONS_MIN, DK.RELATIONS_MAX
		)

	# Cooldowns tick for every nation, not just the player's -- V1.3e will have
	# the other nine acting through this same path, and a counter that only
	# counts down for one nation would be a bug that only surfaced then.
	for ns in state.nations.values():
		var expired: Array = []
		for cooldown_key in ns.diplo_cooldown_months:
			var remaining: int = int(ns.diplo_cooldown_months[cooldown_key]) - 1
			if remaining <= 0:
				expired.append(cooldown_key)
			else:
				ns.diplo_cooldown_months[cooldown_key] = remaining
		for cooldown_key in expired:
			ns.diplo_cooldown_months.erase(cooldown_key)


## The cooldown key for one verb pointed at one counterparty. Per pair, not per
## action: condemning Germany is no reason to be unable to condemn Italy.
static func cooldown_key(action_id: String, target_id: String) -> String:
	return action_id + RK.SEPARATOR + target_id


## Every action in `all_actions` that `actor_id` may currently take against
## `target_id`: preconditions met, and not on cooldown against that target.
## Mirrors Legislature.available().
static func available(state, all_actions: Array, actor_id: String, target_id: String) -> Array:
	var out: Array = []
	if actor_id == target_id:
		return out
	var ns = state.nations.get(actor_id)
	if ns == null:
		return out

	for action in all_actions:
		if action.id == "":
			continue
		if ns.diplo_cooldown_months.has(cooldown_key(action.id, target_id)):
			continue
		if _preconditions_met(state, ns, action, target_id):
			out.append(action)
	return out


static func _preconditions_met(state, ns, action, target_id: String) -> bool:
	for cond in action.preconditions:
		var actual: float = _read_field(state, ns, cond["field"], target_id)
		var value: float = cond["value"]
		var ok: bool
		match cond["op"]:
			"<": ok = actual < value
			"<=": ok = actual <= value
			">": ok = actual > value
			">=": ok = actual >= value
			"==": ok = is_equal_approx(actual, value)
			_: ok = false
		if not ok:
			return false
	return true


## "relations" is the pair score against the action's own target; everything
## else is the acting nation's own state, read exactly as
## Legislature._read_field() reads it. Deliberately two lookups in one function
## rather than two functions: a precondition list mixes both freely, and the
## action content should not have to know which kind a field is.
static func _read_field(state, ns, field: String, target_id: String) -> float:
	match field:
		"relations": return score(state, ns.id, target_id)
		"overall_approval_pct": return ns.overall_approval_pct
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"growth_annual_pct": return ns.growth_annual_pct
		_:
			push_error("diplomacy: unknown precondition field '%s'" % field)
			return 0.0


## The player command: move the pair, pay the domestic price, set the cooldown,
## and record the result for the nation panel to read. Returns the result rather
## than mutating a panel, the same shape Legislature.propose() has.
##
## Refuses rather than half-applies when the action is not currently available:
## a UI that offered a stale button would otherwise produce an effect the
## precondition exists to prevent.
static func execute(state, all_actions: Array, action, actor_id: String, target_id: String) -> Dictionary:
	var ns = state.nations.get(actor_id)
	if ns == null:
		return {"action_id": action.id, "target_id": target_id, "applied": false, "refused": true}

	if not available(state, all_actions, actor_id, target_id).has(action):
		var refused := {
			"action_id": action.id,
			"target_id": target_id,
			"applied": false,
			"refused": true,
			"relations_before": score(state, actor_id, target_id),
			"relations_after": score(state, actor_id, target_id),
		}
		ns.last_diplomatic_result = refused
		return refused

	var before := score(state, actor_id, target_id)
	var after := RK.adjust(
		state, actor_id, target_id, float(action.effects.get("relations", 0.0)),
		DK.RELATIONS_MIN, DK.RELATIONS_MAX
	)

	# Through the same clamped accumulator a law, a censure, a reshuffle and a
	# dissolution already write. No new opinion channel and no new ISSUE_KEYS
	# entry -- that call belongs to V1.3d, and a new issue would reopen the
	# whole BLOC_SALIENCE_BASE measurement. See ROADMAP.md.
	var offsets: Dictionary = action.effects.get("bloc_offset", {})
	for bloc in offsets:
		ns.bloc_offset[bloc] = clampf(
			float(ns.bloc_offset.get(bloc, 0.0)) + float(offsets[bloc]),
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX
		)

	if action.cooldown_months > 0:
		ns.diplo_cooldown_months[cooldown_key(action.id, target_id)] = action.cooldown_months

	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"target_id": target_id,
		"applied": true,
		"refused": false,
		"relations_before": before,
		"relations_after": after,
		"bloc_offset": offsets.duplicate(true),
	}
	ns.last_diplomatic_result = result
	return result
