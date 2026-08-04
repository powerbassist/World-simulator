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

	for id in _members(state, loader):
		var seats: int = loader.eu.ep_seats(id)
		seats_total += seats
		var choice := _vote_of(state, id, proposal, pending)
		by_nation[id] = choice
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


## How one nation votes. The player casts; the other eight are the session's
## declared stopgap.
static func _vote_of(state, nation_id: String, proposal, pending: Dictionary) -> String:
	if nation_id == state.player_nation_id:
		return String(pending.get("player_vote", VOTE_ABSTAIN))
	return VOTE_FOR if support(state.nations[nation_id], proposal) >= K.SUPPORT_THRESHOLD else VOTE_AGAINST


## How much a member's government likes a proposal, in (0, 1].
##
## > DECLARED STOPGAP, replaced at V1.3e.
## >
## > This reads the member's coalition_position and NOTHING ELSE. It does not
## > weigh that nation's economy, does not ask what the proposal would cost it,
## > does not look at its trade weights or its relations with the proposer, does
## > not trade votes, and never proposes anything of its own. A member's answer to
## > a joint fund it would pay for and a joint fund it would draw on is identical
## > if the two sit at the same point in ideology space.
## >
## > Fourth on V1.3e's checklist, behind V1.3a's no-reaction, V1.3b's accept-gate
## > and V1.3c's fixed retaliation. The four compose rather than conflict: the
## > others say the target does not react, does not decide, and reacts by a fixed
## > rule -- this one says the council votes its priors.
## >
## > tests/test_bloc.gd asserts it BY MUTATION. That test must fail and be
## > rewritten at V1.3e.
##
## The Gaussian falloff is election_constants.AFFINITY_SIGMA's shape, reused
## rather than reinvented -- cabinet_constants.CABINET_SIGMA already made the
## same borrowing.
static func support(ns, proposal) -> float:
	var d_econ: float = float(ns.coalition_position.get("economic", 0.0)) - float(proposal.position.get("economic", 0.0))
	var d_social: float = float(ns.coalition_position.get("social", 0.0)) - float(proposal.position.get("social", 0.0))
	var dist := sqrt(d_econ * d_econ + d_social * d_social)
	return exp(-pow(dist / K.SUPPORT_SIGMA, 2.0))


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
		var field: String = String(rule.get("field", ""))
		if field == "":
			continue
		var actual := _read_field(ns, field)
		var target := float(rule["value"])
		var over := 0.0
		match String(rule["op"]):
			"<", "<=": over = maxf(0.0, actual - target)
			">", ">=": over = maxf(0.0, target - actual)
		if over <= 0.0:
			continue
		total += float(rule["severity"]) * clampf(over / float(rule["tolerance"]), 0.0, 1.0)
	return clampf(total, 0.0, K.BURDEN_MAX)


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
		_: return 0.0


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
		entry["breach"] = 0.0
		entry["contribution"] = 0.0
		var field: String = String(rule.get("field", ""))
		if field != "" and ns != null and ns.eu_member:
			var actual := _read_field(ns, field)
			var target := float(rule["value"])
			var over := 0.0
			match String(rule["op"]):
				"<", "<=": over = maxf(0.0, actual - target)
				">", ">=": over = maxf(0.0, target - actual)
			entry["breach"] = over
			entry["contribution"] = float(rule["severity"]) * clampf(over / float(rule["tolerance"]), 0.0, 1.0)
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
