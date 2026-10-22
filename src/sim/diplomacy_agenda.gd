extends RefCounted

## Diplomacy's two heavy reads, fanned out on WorkerThreadPool -- V5.0c2.
##
## An acting nation scores every target (one ForeignPolicy.target_terms() each:
## the target's own trade vector, two amity reads, the retaliation model), and the
## act it takes is judged by every observer (a trade vector and a stake vector
## each). Each target's terms and each observer's terms are a pure read of a state
## nothing writes until the act executes, so they are built on worker threads,
## one Parallel slot per target or observer, and combined HERE, serially, in the
## order the serial loop visited them -- the same comparisons and the same floats
## (src/core/parallel.gd holds the rules; tests/test_diplomacy_parallel.gd runs
## both paths on one state and compares).
##
## Moved out of diplomacy.gd with the lever, verbatim but for the fan-out, so that
## file could take it without growing past its size baseline. It reaches
## available() through the `offers_of` callable Diplomacy hands it, never by
## preloading diplomacy.gd: foreign_policy.gd's one-way rule, kept.

const FP = preload("res://src/sim/foreign_policy.gd")
const FPK = preload("res://src/sim/foreign_policy_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const Verbs = preload("res://src/sim/diplomacy_verbs.gd")
const Parallel = preload("res://src/core/parallel.gd")


## The best (action, target) `actor_id` could take right now, or {} if nothing
## clears AGENDA_ACT_MIN. `offers_of.call(target_id)` is Diplomacy.available()
## for this actor.
##
## One ForeignPolicy.target_terms() per target rather than per candidate: the pair
## terms cost a trade-weight read each and the verbs do not move them. See that
## function for why the split is not a micro-optimisation.
static func best_act(state, actor_id: String, ids: Array, offers_of: Callable) -> Dictionary:
	var best_score: float = FPK.AGENDA_ACT_MIN
	var best: Dictionary = {}
	var targets: Array = []
	for target_id in ids:
		if target_id != actor_id:
			targets.append(target_id)
	var slots: Array = score_targets(state, actor_id, targets, offers_of)
	for i in targets.size():
		var slot: Dictionary = slots[i]
		for candidate in slot.get("candidates", []):
			var score_v: float = candidate[1]
			# Strictly greater, so the sorted iteration order breaks ties and the
			# answer is reproducible.
			if score_v > best_score:
				best_score = score_v
				best = {
					"action": candidate[0],
					"target_id": targets[i],
					"reason": FP.act_reason(slot["terms"], candidate[0].effects),
				}
	return best


## One slot per target, in `targets` order: {} for a target with nothing on offer,
## else {"terms": its pair terms, "candidates": [action, score] per eligible offer
## in offer order}. Public so tests/test_diplomacy_parallel.gd can compare the
## threaded slots with the serial ones whole, scores included.
static func score_targets(state, actor_id: String, targets: Array, offers_of: Callable) -> Array:
	# Once per acting nation, not once per target: the stake vector and the
	# actor's own before-measures weights are invariant across this loop, and
	# rebuilding them per target was ~112 full trade-vector builds per acting
	# nation at the 29-nation roster -- the largest single line in the month
	# tick's measured budget. target_terms() carries the same reasoning.
	var sv: Dictionary = FP.stake_vector(state, actor_id)
	var wbm: Dictionary = Trade.weights_before_measures(state, actor_id)
	var even: float = FP.even_share(state, actor_id)

	# The path's two pow()s, taken HERE on the calling thread, because pow() is not
	# bit-stable on a worker (Trade.masses_open() has the measurement): each
	# target's stake factor, and every partner's gravity mass.
	var factors: Array = []
	for target_id in targets:
		factors.append(FP.stake_factor(sv, target_id, even))
	# G2b: every target's offers on the calling thread, and only the targets with
	# one fanned out. A target with none leaves its slot empty, as it always did;
	# the fan-out's element 0 is then a target that reaches target_terms(), so
	# Parallel rule 5 primes the scoring path rather than an early return.
	var offers: Array = []
	var live: Array[int] = []
	for i in targets.size():
		var target_offers: Array = offers_of.call(targets[i])
		offers.append(target_offers)
		if not target_offers.is_empty():
			live.append(i)
	var slots: Array = Parallel.slots(targets.size())
	Trade.masses_open(state)
	Parallel.each(live.size(), func(k: int) -> void:
		var i: int = live[k]
		_score_target(state, actor_id, targets[i], offers[i], sv, wbm, even, factors[i], slots[i]))
	Trade.masses_close()
	return slots


## One target's half of best_act(), on whichever thread runs it: its pair terms
## and every eligible offer's score, into `slot` and nowhere else. `offers` is
## never empty: score_targets() fans out only the targets that have one.
## Element 0 primes only the kinds of offer ITS target has (parallel.gd rule 5).
## Code that FP.desire_from() runs for one kind of effect, when only a later
## target is offered that kind, runs first on a worker, so a branch added here
## or in desire_from() compares typed values only.
static func _score_target(state, actor_id: String, target_id: String, offers: Array, sv: Dictionary,
		wbm: Dictionary, even: float, factor: float, slot: Dictionary) -> void:
	var terms := FP.target_terms(state, actor_id, target_id, sv, wbm, even, factor)
	var candidates: Array = []
	for action in offers:
		# Agreements between an AI and the PLAYER are out of scope, and the
		# reason is that there is nobody to ask. would_accept_agreement() is the
		# COUNTERPARTY's decision -- so an AI proposing to the player would have
		# the interest model answer on the player's behalf, which is the one
		# thing a single-player game must not do with the player's own foreign
		# policy. An offer the player answers needs pending state, an expiry and
		# an accept/refuse surface: a second machine, and the split V1.3e's own
		# machine-count test would have caught. AI-to-AI agreements are unaffected
		# and do run.
		if Verbs.is_agreement_verb(action) and state.nations[target_id].has_budget:
			continue

		# V1.3g inherits that exclusion exactly, for the same reason and with the
		# narrower test Verbs.is_pact_signing_verb() explains: would_accept_pact() is
		# the COUNTERPARTY's decision, so an AI offering the player an alliance
		# would have the interest model answer on the player's behalf. AI-to-AI
		# pacts are unaffected and do run, and an AI can still abandon a pact with
		# the player -- which is the half the agreement version gets wrong.
		if Verbs.is_pact_signing_verb(action) and state.nations[target_id].has_budget:
			continue

		candidates.append([action, FP.desire_from(terms, action.effects)])
	slot["terms"] = terms
	slot["candidates"] = candidates


## ForeignPolicy.third_party_effects(), its observers read on the pool: the same
## observers, each observer's terms in its own slot, then the same rule over them
## in the same order.
static func third_party_effects(state, actor_id: String, target_id: String, delta: float) -> Array:
	if is_zero_approx(delta):
		return []
	var others: Array = FP.observers(state, actor_id, target_id)
	var slots: Array = Parallel.slots(others.size())
	Trade.masses_open(state)
	Parallel.each(others.size(), func(i: int) -> void:
		var slot: Dictionary = slots[i]
		slot["seen"] = FP.observer_terms(state, others[i], target_id))
	Trade.masses_close()
	var seen: Array = []
	for slot in slots:
		seen.append(slot["seen"])
	return FP.third_party_from(others, seen, actor_id, target_id, delta)
