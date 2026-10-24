extends RefCounted

## What kind of act a diplomatic action is, and who refused it: three leaf
## reads moved verbatim out of diplomacy.gd (V5.0c) so that file could take the
## month-tick lever without growing past its size baseline, and a fourth,
## measure_kind(), for the same reason when available() took its read memo.
## Pure functions of the action and the state; diplomacy.gd is the caller.

const FP = preload("res://src/sim/foreign_policy.gd")
const RK = preload("res://src/core/relations.gd")
const Coercion = preload("res://src/sim/coercion.gd")


## The kind of measure `actor` has in force against `target`, or "" for none.
## The register's own read, kept in one place so Diplomacy._read_field()'s three
## measure fields cannot drift apart.
static func measure_kind(state, actor_id: String, target_id: String) -> String:
	var terms = state.measures.get(RK.directed_key(actor_id, target_id))
	if terms == null:
		return ""
	return String(terms.get("kind", ""))


## measure_kind() for the measure `actor` holds by its OWN act -- an org's levy on
## the same key reads "" (Coercion.own_measure()). What the lift verbs gate on; the
## impose gate keeps measure_kind(), because the org's entry still occupies the pair.
static func own_measure_kind(state, actor_id: String, target_id: String) -> String:
	var terms = Coercion.own_measure(state, RK.directed_key(actor_id, target_id))
	if terms == null:
		return ""
	return String(terms.get("kind", ""))


## Which counterparty said no, and why. One place rather than a ternary at the call
## site, so a sixth channel with a gate of its own has somewhere obvious to go.
static func refusal_reason_for(
	state, actor_id: String, target_id: String, terms: Dictionary, pact_terms: Dictionary
) -> String:
	if String(pact_terms.get("op", "")) == "sign":
		return FP.pact_refusal_reason(state, actor_id, target_id)
	return FP.refusal_reason(state, actor_id, target_id, terms)


## Whether an action asks a counterparty to SIGN a pact -- read off the op rather
## than off the channel being non-empty, which is where is_agreement_verb() sits.
##
## The distinction is load-bearing rather than tidy. Only signing needs consent:
## abandoning is unilateral, and deploying happens under a pact already agreed. Read
## as "the channel is non-empty", the Diplomacy._best_act() exclusion below would mean an AI
## can never ABANDON a pact with the player -- a human locked into an alliance the
## other side hates, permanently, with no exit on its own side.
##
## > [!note] An existing consequence this uncovered, recorded rather than fixed here
## > is_agreement_verb() DOES have the non-empty shape, so `withdraw_from_compact`
## > is skipped whenever the target is the player: an AI can never withdraw from a
## > trade agreement with the player. Out of V1.3g's scope; written down so it is
## > not rediscovered as new.
static func is_pact_signing_verb(action) -> bool:
	var pact: Dictionary = action.effects.get("pact", {})
	return String(pact.get("op", "")) == "sign"


## Whether an action writes GameState.agreements in either direction. Read off the
## effects rather than off a list of action ids, so a new agreement verb in
## data/diplomatic-actions/ is covered without an edit here -- the data-not-code
## rule docs/engine-decision.md states first.
static func is_agreement_verb(action) -> bool:
	return not (action.effects.get("agreement", {}) as Dictionary).is_empty()
