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
const Coercion = preload("res://src/sim/coercion.gd")
const CK = preload("res://src/sim/coercion_constants.gd")

## V1.3e's interest model. Preloaded here rather than in coercion.gd, which is
## what decides where the retaliation DECISION lives: foreign_policy.gd preloads
## trade.gd, trade.gd preloads coercion.gd, so a coercion.gd that reached back for
## the interest model would close a cycle GDScript refuses. _tick_retaliation()
## below already owned the loop, so the decision belongs here and Coercion keeps
## only the terms it builds.
const FP = preload("res://src/sim/foreign_policy.gd")


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

	_tick_retaliation(state)

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


## Answer every measure that has been in force long enough and has not yet been
## answered. Runs inside tick_month(), which already runs for all ten nations and
## whose own comment anticipated exactly this.
##
## > [!success] V1.3c's DECLARED STOPGAP, discharged at V1.3e.
## > A measure used to be mirrored back at a fixed RETALIATION_FRACTION whatever
## > the target's position was. The target now decides how hard to answer -- from
## > how much the imposer depends on it (how much the answer would hurt) against
## > how much it depends on the imposer (how much the answer would cost) -- and can
## > decide not to answer at all. RETALIATION_FRACTION survives as the ceiling.
## > See docs/foreign-policy-model.md.
## >
## > Still one step and still never first: escalation past the single exchange and
## > acting on its own initiative are V1.3f's, and the `retaliated` flag that bounds
## > the exchange is unchanged.
##
## Deliberately no rand(): the same discipline the rest of this file holds to, so
## the budget projection -- which ticks Diplomacy since V1.3b -- and a reloaded
## save agree with a played game.
static func _tick_retaliation(state) -> void:
	# Collected before writing, because the loop below adds entries to the very
	# dictionary it iterates. The mirror's own `retaliated: true` would stop the
	# recursion in any case, but mutating a Dictionary mid-iteration is undefined
	# in Godot rather than merely subtle.
	var answers: Array = []
	for directed in state.measures.keys():
		var terms: Dictionary = state.measures[directed]
		if bool(terms.get("retaliated", false)):
			continue
		if Coercion.months_in_force(terms, state.year, state.month) < CK.RETALIATION_DELAY_MONTHS:
			continue
		var parts := RK.directed_parts(String(directed))
		if parts.size() != 2:
			continue
		answers.append({"imposer": parts[0], "target": parts[1], "key": directed, "terms": terms})

	for answer in answers:
		var imposer: String = answer["imposer"]
		var target: String = answer["target"]

		# Flagged whether or not an answer lands, so a measure is considered for
		# retaliation exactly once. Without this a target that already had a
		# measure of its own in place would be re-examined every month forever.
		state.measures[answer["key"]]["retaliated"] = true

		# One measure per directed pair, the same rule agreements have. A nation
		# that has already imposed something on the imposer does not stack a
		# second entry on top; it has answered already, whatever its reason was.
		var back := RK.directed_key(target, imposer)
		if state.measures.has(back):
			continue

		# The decision V1.3c did not make. Read here rather than inside Coercion
		# because the interest model needs the trade weights and coercion.gd
		# cannot reach them without closing a preload cycle -- see the FP const
		# at the top of this file.
		var fraction := FP.retaliation_fraction(
			state, imposer, target, CK.RETALIATION_FRACTION
		)
		var mirror := Coercion.retaliation_terms(
			answer["terms"], fraction, state.year, state.month
		)
		if mirror.is_empty():
			continue
		state.measures[back] = mirror

		# The second hit on a pair that has already paid for the original measure,
		# which is why it is small next to an action's own effects.relations.
		RK.adjust(
			state, imposer, target, CK.RETALIATION_RELATIONS_COST,
			DK.RELATIONS_MIN, DK.RELATIONS_MAX
		)


## The kind of measure `actor` has in force against `target`, or "" for none.
## The register's own read, kept in one place so the three precondition fields
## above cannot drift apart.
static func _measure_kind(state, actor_id: String, target_id: String) -> String:
	var terms = state.measures.get(RK.directed_key(actor_id, target_id))
	if terms == null:
		return ""
	return String(terms.get("kind", ""))


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
		# The second pair-state field, and the one that makes propose and withdraw
		# gate themselves with no trade knowledge in this module at all: an enter
		# verb asks for 0, an exit verb asks for 1.
		"agreement_active": return 1.0 if state.agreements.has(RK.key(ns.id, target_id)) else 0.0
		# The third piece of pair state and the first DIRECTED one: this nation's own
		# measure against this target, not the target's against it. An impose verb
		# asks measure_active for 0; a lift verb asks its OWN kind for 1, because
		# one measure per pair means "something is in force" cannot tell a tariff
		# from an embargo and a single field would let either lift clear either.
		"measure_active": return 1.0 if _measure_kind(state, ns.id, target_id) != "" else 0.0
		"tariff_active": return 1.0 if _measure_kind(state, ns.id, target_id) == "tariff" else 0.0
		"sanction_active": return 1.0 if _measure_kind(state, ns.id, target_id) == "sanction" else 0.0
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

	# The counterparty gate is folded into the same refusal as an unmet
	# precondition, deliberately. A verdict applied AFTER the effects would be a
	# third outcome -- available, executed, partner said no -- and would leave the
	# player +6 relations for a treaty that was refused. As a gate there is no
	# third outcome, no new result field, and no UI branch.
	var terms: Dictionary = action.effects.get("agreement", {})
	var blocked_by_partner: bool = (
		String(terms.get("op", "")) == "enter"
		and not would_accept_agreement(state, actor_id, target_id, terms)
	)

	if blocked_by_partner or not available(state, all_actions, actor_id, target_id).has(action):
		var refused := {
			"action_id": action.id,
			"target_id": target_id,
			"applied": false,
			"refused": true,
			"refused_by_partner": blocked_by_partner,
			# V1.3b shipped `refused_by_partner` and nothing in src/ui/ ever read
			# it, so a partner declining a treaty was silent to the player. Now
			# there is a reason to show, this carries it.
			"refusal_reason": refusal_reason(state, actor_id, target_id, terms) if blocked_by_partner else "",
			"relations_before": score(state, actor_id, target_id),
			"relations_after": score(state, actor_id, target_id),
		}
		ns.last_diplomatic_result = refused
		return refused

	var before := score(state, actor_id, target_id)
	var delta: float = float(action.effects.get("relations", 0.0))

	# V1.3a's stopgap was that this delta IS the entire reaction and no third pair
	# moves. It is discharged here: every nation with a stake in the target judges
	# the actor for it and warms to the target by the same measure.
	#
	# Computed BEFORE the pair itself moves, and as a whole list before any of it
	# is applied. Both matter: applying one adjustment moves the relations the next
	# stake is scaled by, so a resolved-as-you-go version would give an answer that
	# depended on Dictionary iteration order -- the ordering bug docs/trade-model.md
	# records the trade probe catching in the impulse, which was invisible until
	# something finally perturbed a partner.
	var third_party: Array = FP.third_party_effects(state, actor_id, target_id, delta)

	var after := RK.adjust(
		state, actor_id, target_id, delta, DK.RELATIONS_MIN, DK.RELATIONS_MAX
	)

	for effect in third_party:
		RK.adjust(
			state, String(effect["a"]), String(effect["b"]), float(effect["delta"]),
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

	# The third effect channel, added at V1.3b. Diplomacy owns this register
	# because it is pair state written by a player command, exactly like relations;
	# src/sim/trade.gd reads it and never writes it, so the two modules talk
	# through GameState and never preload each other.
	var pair_key := RK.key(actor_id, target_id)
	match String(terms.get("op", "")):
		"enter":
			state.agreements[pair_key] = {
				"action_id": action.id,
				"action_name": action.action_name,
				"since_year": state.year,
				"since_month": state.month,
				"weight_multiplier": float(terms.get("weight_multiplier", 1.0)),
				"sector_shift": (terms.get("sector_shift", {}) as Dictionary).duplicate(true),
			}
		"exit":
			state.agreements.erase(pair_key)

	# The fourth effect channel, added at V1.3c, on the DIRECTED key: a measure is
	# one nation's act against another, not a contract both sides read, so
	# FRA>DEU and DEU>FRA are separate entries and a retaliation is simply the
	# second one. See src/core/relations.gd's two key builders.
	var measure: Dictionary = action.effects.get("measure", {})
	var directed := RK.directed_key(actor_id, target_id)
	match String(measure.get("op", "")):
		"impose":
			state.measures[directed] = {
				"action_id": action.id,
				"action_name": action.action_name,
				"kind": measure.get("kind", "tariff"),
				"severity": float(measure.get("severity", 0.0)),
				"since_year": state.year,
				"since_month": state.month,
				"retaliated": false,
			}
			# A measure breaks an agreement on the same pair. This is the
			# agreement expiry docs/trade-model.md booked to V1.3c ("no agreement
			# duration or expiry -- V1.3c owns it, via a sanction breaking one"),
			# discharged in one line rather than by building a duration model.
			# Symmetric key, deliberately: the contract had two sides even though
			# the measure has one, so imposing on a partner ends the treaty for
			# both of you.
			state.agreements.erase(pair_key)
		"lift":
			state.measures.erase(directed)

	if action.cooldown_months > 0:
		ns.diplo_cooldown_months[cooldown_key(action.id, target_id)] = action.cooldown_months

	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"target_id": target_id,
		"applied": true,
		"refused": false,
		"refused_by_partner": false,
		"refusal_reason": "",
		"relations_before": before,
		"relations_after": after,
		# How many other pairs this act moved. The nation panel reads it so an
		# act with consequences beyond its target does not look like one without.
		"third_party_pairs": third_party.size(),
		"bloc_offset": offsets.duplicate(true),
		"agreement_op": terms.get("op", ""),
		"measure_op": measure.get("op", ""),
		"measure_kind": measure.get("kind", ""),
	}
	ns.last_diplomatic_result = result
	return result


## Whether `target_id` would sign the agreement `actor_id` is proposing.
##
## > [!success] V1.3b's DECLARED STOPGAP, discharged at V1.3e.
## > This used to be `score(a, b) >= AGREEMENT_ACCEPT_MIN` and nothing else. The
## > target now weighs how much of its own trade runs through the proposer, how
## > warm the pair is, and -- the part a relations threshold could never reach --
## > what is actually on the table. See docs/foreign-policy-model.md.
##
## Takes `terms` where it took none, which is the signature change carrying the
## whole difference: a verdict that cannot see the deal cannot be a verdict about
## the deal. Every caller already had them to hand.
##
## Still a GATE rather than a post-hoc verdict, unchanged from V1.3b and for the
## reason docs/trade-model.md gives: execute() has two outcomes, and a counterparty
## answer applied after the effects would be a third that left the player +6
## relations for a treaty that was refused.
static func would_accept_agreement(state, actor_id: String, target_id: String, terms: Dictionary) -> bool:
	return FP.would_accept_agreement(state, actor_id, target_id, terms)


## Which of the three terms is why they refused, as a key for the nation panel.
## Meaningless unless would_accept_agreement() returned false.
static func refusal_reason(state, actor_id: String, target_id: String, terms: Dictionary) -> String:
	return FP.refusal_reason(state, actor_id, target_id, terms)
