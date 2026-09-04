extends RefCounted

## The supranational bloc: what the council votes on, what a rule in force
## requires, what defying it costs, and what membership charges.
##
## The FOURTH kind of live state in this project. Per-nation state is on
## NationState, pair state is GameState.relations and .agreements, directed pair
## state is GameState.measures -- and a bloc rule belongs to none of those,
## because it is one object shared by eight nations at once. GameState.bloc is
## where it lives, and this module is the only thing that writes it.
##
## No UI knowledge, no engine access, no signals, and no randomness -- the
## council's schedule is a countdown and its agenda is an index, both of which
## survive a save and a reload without an RNG state to serialise. See
## docs/economy-model.md's determinism rule, which this file is held to like
## every other in src/sim/.
##
## Runs AFTER Budget.tick_month() and before Opinion.tick_month(), and the order
## is load-bearing rather than incidental: a rule on the deficit produces a fine,
## and a fine widens the deficit. Reading the settled figure and charging the fine
## into NEXT month's recompute breaks that loop structurally, instead of by
## picking a fixed-point iteration count. It is also the honest reading -- the
## Commission judges the books you closed, not the ones you are still writing.
##
## The model, and the justification for every constant, is docs/bloc-model.md.

const K = preload("res://src/sim/bloc_constants.gd")
const RK = preload("res://src/core/relations.gd")

## V1.3e. Safe to preload here and NOT safe in coercion.gd: foreign_policy.gd
## preloads trade.gd, which preloads coercion.gd, so the cycle closes there and
## not here. Nothing preloads bloc.gd except budget.gd.
const FP = preload("res://src/sim/foreign_policy.gd")
const CK = preload("res://src/sim/coercion_constants.gd")

const VOTE_FOR := "for"
const VOTE_AGAINST := "against"
const VOTE_ABSTAIN := "abstain"
const VOTE_CHOICES := [VOTE_FOR, VOTE_AGAINST, VOTE_ABSTAIN]


## The bloc's own starting state. Called from GameState.new_game() AFTER every
## nation exists, for the same reason Diplomacy.seed_relations() is: the council
## is not any one nation's property, so it cannot be built inside the per-nation
## loop.
static func init_state(state) -> void:
	state.bloc = {
		"rules": {},
		"pending": {},
		"last_vote": {},
		"next_index": 0,
		"months_to_next": K.PROPOSAL_INTERVAL_MONTHS,
	}
	for ns in state.nations.values():
		ns.bloc_burden = 0.0
		ns.start_bloc_burden = 0.0


## Each member's standing net contribution as a percent of its own GDP, derived
## from starting prosperity rather than authored.
##
## Derived for the reason docs/trade-model.md gives for the trade weight and
## docs/diplomacy-model.md for resting relations: an authored table of ten net
## positions is frozen, and this one moves if the roster does. Richer than the
## bloc mean pays more, poorer receives -- which is what the real budget does and
## what makes Luxembourg's line look nothing like Spain's without a word of
## content saying so.
##
## Reads the LOADER's Nation objects, not live state, and is copied onto
## NationState once at new-game. That is the same static-fact treatment
## `eu_member` and `neighbours` get, and it is what keeps this figure inside
## `start_deficit_pct_gdp` -- an inherited contribution is a permanent drag the
## player did not choose, exactly like an inherited debt.
static func net_positions(loader) -> Dictionary:
	var out := {}
	var total_gdp := 0.0
	var total_pop := 0.0
	for n in loader.nations.values():
		if not n.eu_member:
			continue
		total_gdp += float(n.gdp_eur_bn)
		total_pop += float(n.population)

	if total_pop <= 0.0 or total_gdp <= 0.0:
		return out
	var mean_gdp_per_capita: float = total_gdp / total_pop

	for n in loader.nations.values():
		# Exactly 0.0 for a non-member, by construction rather than by rounding --
		# the same property that keeps Budget._tariff_revenue() off the books when
		# nothing is imposed, and half of what a balance re-run needs to be
		# readable.
		if not n.eu_member or float(n.population) <= 0.0:
			out[n.id] = 0.0
			continue
		var per_capita: float = float(n.gdp_eur_bn) / float(n.population)
		out[n.id] = clampf(
			K.CONTRIBUTION_BASE_PCT_GDP
			+ K.CONTRIBUTION_PROSPERITY_SPAN * (per_capita / mean_gdp_per_capita - 1.0),
			K.CONTRIBUTION_MIN_PCT_GDP,
			K.CONTRIBUTION_MAX_PCT_GDP
		)
	return out


## One month of the council, then one month of what its rules cost.
static func tick_month(state, loader) -> void:
	_tick_council(state, loader)

	# Gated on has_budget rather than on the player id, the same flag
	# Budget.tick_month and Opinion.tick_month use -- a second playable nation is
	# a data change, not a change here.
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		ns.bloc_burden = burden(state, ns)
		ns.bloc_transfer_pct_gdp = (
			ns.bloc_base_transfer_pct_gdp
			+ _rule_transfers(state, ns)
			+ K.FINE_PCT_GDP_PER_BURDEN * ns.bloc_burden
		)


## Open a proposal when one is due, and divide when the window closes.
static func _tick_council(state, loader) -> void:
	var bloc: Dictionary = state.bloc
	if bloc.is_empty():
		return

	var pending: Dictionary = bloc.get("pending", {})
	if not pending.is_empty():
		if int(pending["months_left"]) > 1:
			pending["months_left"] = int(pending["months_left"]) - 1
			return
		_resolve(state, loader)
		return

	bloc["months_to_next"] = int(bloc.get("months_to_next", 0)) - 1
	if int(bloc["months_to_next"]) > 0:
		return

	var proposal = _next_proposal(state, loader)
	if proposal == null:
		# Nothing left to put to the council. Try again next interval rather than
		# every month: a council with no agenda is quiet, not busy.
		bloc["months_to_next"] = K.PROPOSAL_INTERVAL_MONTHS
		return

	bloc["pending"] = {
		"proposal_id": proposal.id,
		"name": proposal.proposal_name,
		"summary": proposal.summary,
		"months_left": K.VOTE_DELAY_MONTHS,
		"player_vote": VOTE_ABSTAIN,
		"opened_year": state.year,
		"opened_month": state.month,
	}
	bloc["months_to_next"] = K.PROPOSAL_INTERVAL_MONTHS


## The next thing worth putting to the council, or null.
##
## Deterministic: a rotating index over the loaded list in authored order, with
## no RNG anywhere. A proposal already in force is skipped; one that FAILED can
## come back, because a council that never revisits a defeat is a council that
## runs out of politics after one pass.
static func _next_proposal(state, loader):
	var all: Array = loader.bloc_proposals
	if all.is_empty():
		return null

	var rules: Dictionary = state.bloc.get("rules", {})
	var constrained := 0
	for r in rules.values():
		if not (r as Dictionary).get("field", "").is_empty():
			constrained += 1

	var start := int(state.bloc.get("next_index", 0))
	for offset in all.size():
		var i: int = (start + offset) % all.size()
		var p = all[i]
		if rules.has(p.id):
			continue
		# The ceiling bounds rules that BIND POLICY, not proposals. A transfer or
		# an external measure adds no constraint row to the panel and no term to
		# the burden, so capping those too would make the council fall silent for
		# most of a long run with content still unused.
		if not p.constraint.is_empty() and constrained >= K.MAX_RULES_IN_FORCE:
			continue
		state.bloc["next_index"] = (i + 1) % all.size()
		return p
	return null


## The loaded proposal with this id, or null. Linear over a list of single
## digits' length -- a dictionary keyed by id would be a second index to keep in
## step with the ordered list the agenda rotates over, and the list is the
## authority.
static func _proposal_by_id(loader, proposal_id: String):
	for p in loader.bloc_proposals:
		if p.id == proposal_id:
			return p
	return null


## The council divides. Every member votes, the player's own vote is whatever
## they cast, and a qualified majority of member EP seats carries it.
static func _resolve(state, loader) -> void:
	var bloc: Dictionary = state.bloc
	var pending: Dictionary = bloc["pending"]
	var proposal = _proposal_by_id(loader, String(pending["proposal_id"]))
	if proposal == null:
		bloc["pending"] = {}
		return

	var seats_for := 0
	var seats_against := 0
	var seats_total := 0
	var by_nation := {}
	var reasons := {}

	for id in _members(state, loader):
		var seats: int = loader.eu.ep_seats(id)
		seats_total += seats
		var choice := _vote_of(state, id, proposal, pending)
		by_nation[id] = choice
		# Recorded at the moment of the division rather than recomputed by the
		# panel, because the books a member voted on are this month's and the panel
		# is read later. V1.3c's budget panel showed a tariff collecting nothing
		# for exactly this class of reason.
		if id != state.player_nation_id:
			reasons[id] = vote_reason(state, state.nations[id], proposal)
		if choice == VOTE_FOR:
			seats_for += seats
		elif choice == VOTE_AGAINST:
			seats_against += seats

	# The threshold is a share of the seats actually CAST, not of the council's
	# whole strength, and that is the one thing that makes abstention a third
	# option rather than a slower way of voting no.
	#
	# Under a whole-council denominator, abstaining and opposing produce an
	# identical `seats_for` and therefore an identical outcome, always -- abstention
	# would be mechanically indistinguishable from opposition, which
	# tests/test_bloc.gd caught before this shipped. Against cast seats the three
	# choices genuinely differ: backing it adds to the numerator, opposing it adds
	# to the denominator and blocks, and abstaining removes you from both and lets
	# it through on a smaller base. That is constructive abstention, and it is what
	# the real Council does.
	var cast: int = seats_for + seats_against
	var passed: bool = cast > 0 and float(seats_for) >= K.PASS_SEAT_FRACTION * float(cast)

	bloc["last_vote"] = {
		"proposal_id": proposal.id,
		"name": proposal.proposal_name,
		"passed": passed,
		"seats_for": seats_for,
		"seats_against": seats_against,
		"seats_total": seats_total,
		"player_vote": String(pending.get("player_vote", VOTE_ABSTAIN)),
		"votes": by_nation,
		"reasons": reasons,
		"year": state.year,
		"month": state.month,
	}
	bloc["pending"] = {}

	if passed:
		_adopt(state, loader, proposal)


## A passed proposal becomes a rule in force. The TERMS are stored, not the
## proposal id alone -- the same call docs/trade-model.md made for an agreement
## and docs/coercion-model.md for a measure, and for the same reason: what binds
## you is what the council adopted, not what the content file says later.
static func _adopt(state, loader, proposal) -> void:
	var entry := {
		"name": proposal.proposal_name,
		"field": "",
		"op": "",
		"value": 0.0,
		"tolerance": 1.0,
		"severity": 0.0,
		"transfer_pct_gdp": proposal.transfer_pct_gdp,
		"since_year": state.year,
		"since_month": state.month,
	}
	if not proposal.constraint.is_empty():
		entry["field"] = String(proposal.constraint["field"])
		entry["op"] = String(proposal.constraint["op"])
		entry["value"] = float(proposal.constraint["value"])
		entry["tolerance"] = float(proposal.constraint["tolerance"])
		entry["severity"] = float(proposal.constraint["severity"])

	state.bloc["rules"][proposal.id] = entry

	if not proposal.external_measure.is_empty():
		_apply_external_measure(state, loader, proposal)


## The bloc setting an external tariff collectively -- the first reader of
## V1.3c's directed register from outside src/sim/coercion.gd, and the item
## docs/coercion-model.md parked here by name.
##
## One entry per (member, non-member) ordered pair, written on the SAME directed
## key a player's own tariff uses, so nothing in src/sim/coercion.gd or
## src/sim/trade.gd needed a line changed to read it. A pair that already carries
## a measure is left alone: one measure per directed pair is a bound
## docs/coercion-model.md states, and two sets of terms would need a rule for how
## they compose that no content wants.
static func _apply_external_measure(state, loader, proposal) -> void:
	var members := _members(state, loader)
	for member_id in members:
		for other_id in state.nations.keys():
			if members.has(other_id):
				continue
			var directed := RK.directed_key(member_id, other_id)
			if state.measures.has(directed):
				continue
			state.measures[directed] = {
				"action_id": proposal.id,
				"action_name": proposal.proposal_name,
				"kind": String(proposal.external_measure["kind"]),
				"severity": float(proposal.external_measure["severity"]),
				"since_year": state.year,
				"since_month": state.month,
				# The bloc does not answer a retaliation of its own; the target
				# mirrors each member individually through Diplomacy's own rule.
				"retaliated": true,
			}
			# A measure ends the treaty on that pair, exactly as
			# Diplomacy.execute() does for a player-imposed one. Symmetric key
			# deliberately: the contract had two sides even though the measure has
			# one. See docs/coercion-model.md.
			state.agreements.erase(RK.key(member_id, other_id))


## How one nation votes. The player casts; the other eight appraise.
static func _vote_of(state, nation_id: String, proposal, pending: Dictionary) -> String:
	if nation_id == state.player_nation_id:
		return String(pending.get("player_vote", VOTE_ABSTAIN))
	return VOTE_FOR if support(state, state.nations[nation_id], proposal) >= K.SUPPORT_THRESHOLD else VOTE_AGAINST


## How much a member's government wants a proposal adopted.
##
## > [!success] V1.3d's DECLARED STOPGAP, discharged at V1.3e.
## > This used to read the member's coalition_position and NOTHING ELSE, so a
## > member's answer to a joint fund it would pay for and one it would draw on was
## > identical if the two sat at the same point in ideology space. It now appraises
## > the proposal against the member's OWN BOOKS -- what the rule would cost it
## > given its current deficit, what the transfer would cost or pay it, what an
## > external measure would cost its own trade -- with ideology retained as one
## > weak term among four. See docs/foreign-policy-model.md.
##
## Takes `state` where it used to take only `ns`, which is the signature change
## that makes the whole difference: a vote that cannot see the world cannot weigh
## anything in it.
##
## The rule's cost is computed HERE and passed down rather than computed inside
## the interest model, because foreign_policy.gd cannot preload this file -- this
## one preloads it. Bloc keeps sole ownership of the breach arithmetic, which is
## engine-decision.md's rule 3 with the dependency pointing the one way it can.
static func support(state, ns, proposal) -> float:
	return FP.appraise(state, ns, proposal, _proposed_rule_cost(ns, proposal))


## Why a member voted as it did, as a key src/ui/bloc_panel.gd turns into words.
static func vote_reason(state, ns, proposal) -> String:
	return FP.vote_reason(state, ns, proposal, _proposed_rule_cost(ns, proposal))


## What this proposal's constraint would add to this nation's burden if adopted,
## against its books as they stand now. Zero for a proposal that binds nobody's
## policy, and zero for a member already inside the rule.
static func _proposed_rule_cost(ns, proposal) -> float:
	if proposal.constraint.is_empty():
		return 0.0
	return float(rule_breach(ns, proposal.constraint)["contribution"])


## The player's command. Returns false if there is nothing to vote on, if the
## choice is not one of the three, or if the player is not a member -- refused
## rather than silently recorded, the same shape Diplomacy.execute() uses.
static func cast_vote(state, choice: String) -> bool:
	if not VOTE_CHOICES.has(choice):
		return false
	var bloc: Dictionary = state.bloc
	if bloc.is_empty() or (bloc.get("pending", {}) as Dictionary).is_empty():
		return false
	var ns = state.player()
	if ns == null or not ns.eu_member:
		return false
	bloc["pending"]["player_vote"] = choice
	return true


## How far outside the rules in force this nation is sitting, in [0, BURDEN_MAX].
## Zero for a non-member, for a member with nothing in force, and for a member
## that complies -- which is the point: a complying player pays for the bloc in
## the policy they could not run, and that shows up on the spending lines they
## had to cut rather than here.
static func burden(state, ns) -> float:
	if not ns.eu_member:
		return 0.0
	var rules: Dictionary = state.bloc.get("rules", {})
	var total := 0.0
	for rule in rules.values():
		total += float(rule_breach(ns, rule)["contribution"])
	return clampf(total, 0.0, K.BURDEN_MAX)


## How far one rule -- in force or merely PROPOSED -- puts this nation outside it,
## as {breach, contribution}. `breach` is the raw overshoot in the field's own
## units; `contribution` is what it adds to the burden, severity-weighted and
## tolerance-scaled.
##
## Extracted at V1.3e, and it was already written three times before that: in
## burden(), in rules_in_force() for the panel, and it would have been a fourth in
## the council's own appraisal. Three copies of a formula is how the panel and the
## model come to disagree about what a breach is.
##
## Takes a rule DICTIONARY rather than a proposal, so a rule in force and a
## proposal's `constraint` block both go through it -- which is what lets a member
## price a rule it is being asked to adopt against the same arithmetic that will
## bind it afterwards. A member already inside a proposed rule scores exactly
## 0.0, by construction, and that is the whole reason the council stopped voting
## its priors.
static func rule_breach(ns, rule: Dictionary) -> Dictionary:
	var out := {"breach": 0.0, "contribution": 0.0}
	if ns == null or not ns.eu_member:
		return out
	var field: String = String(rule.get("field", ""))
	if field == "":
		return out

	var actual := _read_field(ns, field)
	var target := float(rule["value"])
	var over := 0.0
	match String(rule["op"]):
		"<", "<=": over = maxf(0.0, actual - target)
		">", ">=": over = maxf(0.0, target - actual)
	if over <= 0.0:
		return out

	out["breach"] = over
	out["contribution"] = float(rule["severity"]) * clampf(over / float(rule["tolerance"]), 0.0, 1.0)
	return out


## What the rules in force add to or take off this nation's standing transfer.
## Zero for a non-member: a rule binds the members that adopted it.
static func _rule_transfers(state, ns) -> float:
	if not ns.eu_member:
		return 0.0
	var total := 0.0
	for rule in (state.bloc.get("rules", {}) as Dictionary).values():
		total += float(rule.get("transfer_pct_gdp", 0.0))
	return total


## Every field a constraint may name, read off the constrained nation's own
## state -- exactly the way Legislature._read_field() and Diplomacy._read_field()
## read theirs. An unknown field cannot reach here: bloc_proposal.gd refuses one
## at load against bloc_constants.CONSTRAINT_FIELDS.
static func _read_field(ns, field: String) -> float:
	match field:
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"total_spending_pct_gdp": return ns.total_spending_pct_gdp
		"spending_defence": return float(ns.spending_pct_gdp.get("defence", 0.0))
		"spending_infrastructure": return float(ns.spending_pct_gdp.get("infrastructure", 0.0))
		"tax_corporate": return float(ns.tax_rates_pct.get("corporate", 0.0))
		"tax_vat": return float(ns.tax_rates_pct.get("vat", 0.0))
		_:
			# Loud, like every sibling _read_field(). This was the one that returned
			# 0.0 in silence while its own comment claimed it behaved like the others
			# -- a mistyped rule field then read as a nation scoring zero on it, which
			# for a deficit rule is perfect compliance.
			push_error("bloc: unknown rule field '%s'" % field)
			return 0.0


# --- queries, for the UI and the tests -------------------------------------------

## The bloc's members that are actually in the roster, sorted, so anything that
## iterates them is reproducible rather than dependent on Dictionary ordering --
## the same reason Relations.all_pairs() sorts.
static func _members(state, loader) -> Array:
	var out: Array = []
	for id in state.nations.keys():
		if loader.eu.is_member(id):
			out.append(id)
	out.sort()
	return out


static func members(state, loader) -> Array:
	return _members(state, loader)


## Rules in force as [{id, name, field, op, value, severity, transfer_pct_gdp,
## breach, contribution}], sorted by id so the panel's order is stable across
## repaints. `breach` and `contribution` are this nation's, so the panel can say
## which rule is costing what rather than only what the total is.
static func rules_in_force(state, ns) -> Array:
	var ids: Array = (state.bloc.get("rules", {}) as Dictionary).keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		var rule: Dictionary = state.bloc["rules"][id]
		var entry := rule.duplicate(true)
		entry["id"] = id
		var scored: Dictionary = rule_breach(ns, rule)
		entry["breach"] = scored["breach"]
		entry["contribution"] = scored["contribution"]
		out.append(entry)
	return out


static func pending(state) -> Dictionary:
	return state.bloc.get("pending", {})


static func last_vote(state) -> Dictionary:
	return state.bloc.get("last_vote", {})


## What the player's contribution breaks down into, for the budget panel: the
## standing net position, what the rules in force moved it by, and the penalties
## being charged for defying them. Sums to ns.bloc_transfer_pct_gdp.
static func transfer_breakdown(state, ns) -> Dictionary:
	return {
		"base": ns.bloc_base_transfer_pct_gdp,
		"rules": _rule_transfers(state, ns),
		"fine": K.FINE_PCT_GDP_PER_BURDEN * ns.bloc_burden,
	}
