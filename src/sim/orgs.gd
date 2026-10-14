extends RefCounted

## The supranational organisations, V3.2: membership as live data, one register
## per council, one composition rule for the channels several orgs share.
##
## This file generalises src/sim/bloc.gd -- the V1.3d machine, hardcoded to the
## one EU object -- and REPLACES it. Model: docs/orgs-model.md.
##
## The FOURTH kind of live state in this project. Per-nation state is on
## NationState, pair state is GameState.relations and .agreements, directed pair
## state is GameState.measures -- and an org's rules belong to none of those,
## because they are one object shared by N nations at once. GameState.orgs
## holds one register per council org; this module is the only thing that
## writes it.
##
## COMPOSITION (pre-declared in the plan before any content existed):
##   - Opinion is ONE price. ns.bloc_burden sums every org's rules' breach
##     contributions and clamps ONCE at BURDEN_MAX; the `europe` issue reads
##     that total and nothing else -- a second approval number is structurally
##     impossible because no second channel is touched (V1.5c).
##   - Transfers are PER ORG: each org charges its own base, its own rules'
##     transfers, and a fine on its own clamped burden; the budget line is the
##     sum. Two clubs each fining their own defiers is the honest reading.
##   - External measures are per org, aimed at that org's outsiders, and the
##     first adopted holds the pair (coercion-model's one-measure-per-pair).
##   - Standing bonuses (resting relations, gravity trade) sum over the orgs
##     two nations SHARE -- Org.shared_bonus().
##
## No UI knowledge, no engine access, no signals, and no randomness -- each
## council's schedule is a countdown and its agenda is an index, both of which
## survive a save and a reload without an RNG state to serialise.
##
## Runs AFTER Budget.tick_month() and before Opinion.tick_month(), and the order
## is load-bearing rather than incidental: a rule on the deficit produces a fine,
## and a fine widens the deficit. Reading the settled figure and charging the fine
## into NEXT month's recompute breaks that loop structurally, instead of by
## picking a fixed-point iteration count. It is also the honest reading -- the
## Commission judges the books you closed, not the ones you are still writing.

const K = preload("res://src/sim/bloc_constants.gd")
const RK = preload("res://src/core/relations.gd")

## V1.3e. Safe to preload here and NOT safe in coercion.gd: foreign_policy.gd
## preloads trade.gd, which preloads coercion.gd, so the cycle closes there and
## not here. Nothing preloads orgs.gd except budget.gd.
const FP = preload("res://src/sim/foreign_policy.gd")
const CK = preload("res://src/sim/coercion_constants.gd")
const Referendum = preload("res://src/sim/referendum.gd")
## V4.5a. A leaf: council.gd preloads nothing of this file's.
const Council = preload("res://src/sim/council.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")

const VOTE_FOR := "for"
const VOTE_AGAINST := "against"
const VOTE_ABSTAIN := "abstain"
const VOTE_CHOICES := [VOTE_FOR, VOTE_AGAINST, VOTE_ABSTAIN]


## New-game state: one register per council org, the static effects snapshot,
## and every nation's membership plus per-org base transfer.
##
## Called from GameState.new_game() after every nation exists, for the same
## reason Diplomacy.seed_relations() is: the council is not any one nation's
## property, so it cannot be built inside the per-nation loop. Nothing is in
## force at new-game, so every nation's burden is exactly zero and
## start_bloc_burden is too -- which is what makes the europe issue exactly
## zero at new-game like every other, with no calibration term.
static func init_state(state, loader) -> void:
	state.orgs = {}
	state.org_effects = {}
	state.accessions = []
	for org in loader.orgs:
		if org.council:
			state.orgs[org.id] = {
				"rules": {},
				"pending": {},
				"last_vote": {},
				"next_index": 0,
				"months_to_next": K.PROPOSAL_INTERVAL_MONTHS,
				# V4.5a -- the contested layer's registers, empty at new-game.
				# Each one's absence reads correctly for an older save (nothing
				# was chosen, tabled, ratifying, paid or owed before V4.5),
				# which is the SAVE_VERSION argument in game_state.gd.
				"agenda_choice": "",
				"tabled": {},
				"ratifying": {},
				"aid": [],
				"debts": [],
			}
		state.org_effects[org.id] = {
			"relations_bonus": org.relations_bonus,
			"trade_bonus": org.trade_bonus,
		}

	for ns in state.nations.values():
		ns.orgs = []
		ns.org_base_transfer_pct_gdp = {}
		ns.org_seats = {}
	for org in loader.orgs:
		var positions := net_positions(loader, org.id) if org.net_transfers else {}
		for ns in state.nations.values():
			if org.is_member(ns.id):
				ns.orgs.append(org.id)
				# Seat weight is LIVE state seeded from the authored table: the
				# council's division reads it, so what a member weighs and who is
				# a member come from the same register.
				ns.org_seats[org.id] = org.seats(ns.id)
				if org.net_transfers:
					ns.org_base_transfer_pct_gdp[org.id] = float(positions.get(ns.id, 0.0))
	# Sorted, because every reader -- shared_bonus(), the transfer sum, the
	# panel -- iterates memberships and the iteration must be reproducible
	# rather than dependent on loader file order.
	for ns in state.nations.values():
		ns.orgs.sort()
		ns.bloc_burden = 0.0
		ns.start_bloc_burden = 0.0
		ns.bloc_transfer_pct_gdp = 0.0
		for org_id in ns.orgs:
			ns.bloc_transfer_pct_gdp += float(ns.org_base_transfer_pct_gdp.get(org_id, 0.0))


## The load path's OTHER half, and the fight machine's save-safety net. A fight
## in its referendum phase advances by reading `ns.last_referendum_result`,
## which is deliberately NOT serialised -- `last_project_result`'s case, a
## display record of something that has already happened. So a game saved in
## the one-month window after a vote resolved but before this machine consumed
## it reloads with the pending register empty and the answer gone. The honest
## resolution is the failed vote's: end the fight with membership unchanged.
## The domestic price was charged at the resolve, before the save; no outcome
## is invented; the player is not stranded -- the review's critical finding
## had `phase` dropped at load, which left fights matching NOTHING and every
## membership verb refused forever. A fight in negotiation reloads intact: its
## countdown is serialised state and needs no result to advance.
static func reconcile_on_load(state, loader) -> void:
	var doomed := []
	for i in state.accessions.size():
		var fight: Dictionary = state.accessions[i]
		if String(fight.get("phase", "")) != "referendum":
			continue
		var ns = state.nations.get(String(fight.get("nation_id", "")))
		var question := String(fight.get("kind", "")) + ":" + String(fight.get("org_id", ""))
		# Still campaigning -- the pending register round-trips and the vote has
		# not happened yet. Leave it alone.
		if ns != null and String(ns.referendum_pending.get("law_id", "")) == question:
			continue
		doomed.append(i)
	doomed.reverse()
	for i in doomed:
		state.accessions.remove_at(i)


## The load-path half of init_state: GameState.org_effects is a snapshot of
## STATIC content and is not serialised (project_sited_pct's case), so a
## reloaded game re-derives it here. Membership and the council registers are
## LIVE state and travel in the save -- re-deriving those would erase the
## accession the player fought for.
static func rebuild_static(state, loader) -> void:
	state.org_effects = {}
	for org in loader.orgs:
		state.org_effects[org.id] = {
			"relations_bonus": org.relations_bonus,
			"trade_bonus": org.trade_bonus,
		}


## Each member's standing net contribution as a percent of its own GDP,
## derived from starting prosperity against THIS ORG'S OWN mean. Same shape,
## same reason, as the one-org figure bloc.gd computed: richer than the org
## mean pays more, poorer receives, and a non-member reads exactly 0.0 by
## construction rather than rounding. Per-org means are why Luxembourg's line
## to the EU is not its line to a hypothetical rich clubs' alliance.
## `live_members` is empty at new-game, where the AUTHORED roster is the truth.
## The accession flip passes the post-flip LIVE roster, because the mean the
## formula divides by moved with the new member and the content table did not:
## a re-derive over the static roster writes back identical values, which is
## the no-op-in-a-derivative's-clothing the review caught.
static func net_positions(loader, org_id: String, live_members: Array = []) -> Dictionary:
	var out := {}
	var org = loader.orgs_by_id.get(org_id)
	if org == null:
		return out

	var roster: Array = live_members
	if roster.is_empty():
		for n in loader.nations.values():
			if org.is_member(n.id):
				roster.append(n.id)
		roster.sort()

	var total_gdp := 0.0
	var total_pop := 0.0
	for member_id in roster:
		var n = loader.nations.get(member_id)
		if n == null:
			continue
		total_gdp += float(n.gdp_eur_bn)
		total_pop += float(n.population)
	if total_pop <= 0.0 or total_gdp <= 0.0:
		return out
	if total_pop <= 0.0 or total_gdp <= 0.0:
		return out
	var mean: float = total_gdp / total_pop

	for member_id in roster:
		var n = loader.nations.get(member_id)
		if n == null or float(n.population) <= 0.0:
			continue
		var per_capita: float = float(n.gdp_eur_bn) / float(n.population)
		out[n.id] = clampf(
			K.CONTRIBUTION_BASE_PCT_GDP
			+ K.CONTRIBUTION_PROSPERITY_SPAN * (per_capita / mean - 1.0),
			K.CONTRIBUTION_MIN_PCT_GDP,
			K.CONTRIBUTION_MAX_PCT_GDP
		)
	return out


# --- membership queries (live state, not content) ---------------------------------

## The LIVE members of one org that are on the roster, sorted -- reproducible
## iteration for everything that walks a membership, the same reason
## Relations.all_pairs() sorts. Reads NationState.orgs, never the content
## table: the two agree at new-game and diverge the day a fight is won.
static func members(state, org_id: String) -> Array:
	var out: Array = []
	for id in state.nations.keys():
		if state.nations[id].orgs.has(org_id):
			out.append(id)
	out.sort()
	return out


static func is_member(state, org_id: String, nation_id: String) -> bool:
	var ns = state.nations.get(nation_id)
	return ns != null and ns.orgs.has(org_id)


## The one org whose content carries a parliament, or null. The loader
## validates that at most one exists, so "the EP parliament" stays a well-formed
## phrase without this file ever naming an id. Content query, not a flag test.
static func parliament(loader):
	for org in loader.orgs:
		if not org.parliament.is_empty():
			return org
	return null


## A nation's voting weight in one org, LIVE: 0 for a non-member. The council's
## division weighs members by this, never by the content table -- the authored
## seats are where a member STARTS (seeded into NationState.org_seats at
## new-game), and the accession flip writes the org's authored
## `accession_seats` for a joiner, who is on no content table at all.
static func live_seats(state, org_id: String, nation_id: String) -> int:
	var ns = state.nations.get(nation_id)
	if ns == null or not ns.orgs.has(org_id):
		return 0
	return int(ns.org_seats.get(org_id, 0))


## A nation's seats in the parliament org, live: 0 for a non-member or where no
## org carries a parliament. Read at election time rather than copied, so a
## nation that accedes mid-game resolves its first EP election with the seats
## the flip wrote -- the same live_seats read under the parliament org's id.
static func ep_seats(state, loader, nation_id: String) -> int:
	var parl = parliament(loader)
	if parl == null:
		return 0
	return live_seats(state, parl.id, nation_id)


## The orgs that hold a council, as sorted ids. state.orgs carries exactly the
## council orgs' registers, so the register keys ARE the answer -- no loader
## needed, and a save's registers cannot disagree with the question.
static func council_ids(state) -> Array:
	var out: Array = state.orgs.keys()
	out.sort()
	return out


# --- one month --------------------------------------------------------------------

## One month of every council, then one month of what every org's rules cost.
static func tick_month(state, loader) -> void:
	# The ids are computed once and passed down, so every consumer below reads
	# the same snapshot of what holds a council rather than re-asking.
	var council_ids := council_ids(state)
	for org_id in council_ids:
		_tick_council(state, loader, org_id)
	_tick_accessions(state, loader)

	# Gated on has_budget rather than on the player id, the same flag
	# Budget.tick_month and Opinion.tick_month use -- a second playable nation is
	# a data change, not a change here.
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		ns.bloc_burden = burden(state, ns, council_ids)
		var total := 0.0
		for org_id in ns.orgs:
			total += _org_transfer(state, ns, org_id)
		ns.bloc_transfer_pct_gdp = total


## One org's line: its standing base, what its rules in force move it by, and
## the penalties it charges for defying THEM. Reduces to today's single-org
## arithmetic bit-for-bit: with one org, org_burden == ns.bloc_burden and the
## base dict holds the one entry. A nation outside the org (or outside any org
## with a register) sums to exactly 0.0 -- the exact-zero property the old
## base field carried, per org.
static func _org_transfer(state, ns, org_id: String) -> float:
	if not state.orgs.has(org_id):
		return float(ns.org_base_transfer_pct_gdp.get(org_id, 0.0))
	var register: Dictionary = state.orgs[org_id]
	var contributions := 0.0
	var rule_transfers := 0.0
	for rule in (register.get("rules", {}) as Dictionary).values():
		rule_transfers += float(rule.get("transfer_pct_gdp", 0.0))
		contributions += float(rule_breach(state, ns, org_id, rule)["contribution"])
	return (
		float(ns.org_base_transfer_pct_gdp.get(org_id, 0.0))
		+ rule_transfers
		+ K.FINE_PCT_GDP_PER_BURDEN * clampf(contributions, 0.0, K.BURDEN_MAX)
	)


# --- the council ------------------------------------------------------------------

## Open a proposal when one is due, and divide when the window closes.
## The scheduler is PER ORG -- each council's countdown and agenda index live
## in its own register, so two councils tick independently and neither waits
## on the other.
static func _tick_council(state, loader, org_id: String) -> void:
	var register: Dictionary = state.orgs[org_id]

	var pending: Dictionary = register.get("pending", {})
	if not pending.is_empty():
		if int(pending["months_left"]) > 1:
			pending["months_left"] = int(pending["months_left"]) - 1
			return
		_resolve(state, loader, org_id)
		return

	register["months_to_next"] = int(register.get("months_to_next", 0)) - 1
	if int(register["months_to_next"]) > 0:
		return

	# V4.5a. Three pickers in precedence order, and the order is the design: a
	# proposal someone PAID to table outranks the chair's own pick, and the
	# chair's pick outranks the rotation. With no presidency and nothing tabled
	# only the rotation runs -- the inertness clause, bit-identical to V4.4.
	var sponsor := ""
	var proposal = null
	var tabled: Dictionary = register.get("tabled", {})
	if not tabled.is_empty():
		register["tabled"] = {}
		var tp = _proposal_by_id(loader, org_id, String(tabled.get("proposal_id", "")))
		if tp != null and _eligible(state, org_id, tp):
			proposal = tp
			sponsor = String(tabled.get("by", ""))
	if proposal == null:
		proposal = _presidency_pick(state, loader, org_id)
	if proposal == null:
		proposal = _next_proposal(state, loader, org_id)
	if proposal == null:
		# Nothing left to put to the council. Try again next interval rather than
		# every month: a council with no agenda is quiet, not busy.
		register["months_to_next"] = K.PROPOSAL_INTERVAL_MONTHS
		return
	if sponsor == "":
		sponsor = Council.live_sponsor(state, proposal)

	register["pending"] = {
		"proposal_id": proposal.id,
		"name": proposal.proposal_name,
		"summary": proposal.summary,
		"org_id": org_id,
		"org_name": loader.orgs_by_id[org_id].name,
		"months_left": K.VOTE_DELAY_MONTHS,
		"player_vote": VOTE_ABSTAIN,
		"opened_year": state.year,
		"opened_month": state.month,
		"sponsor": sponsor,
	}
	register["months_to_next"] = K.PROPOSAL_INTERVAL_MONTHS


## The next thing worth putting to THIS council, or null.
##
## Deterministic: a rotating index over the org's loaded list in authored order,
## with no RNG anywhere. A proposal already in force is skipped; one that FAILED
## can come back, because a council that never revisits a defeat is a council
## that runs out of politics after one pass.
static func _next_proposal(state, loader, org_id: String):
	var all: Array = loader.org_proposals.get(org_id, [])
	if all.is_empty():
		return null

	var start := int(state.orgs[org_id].get("next_index", 0))
	for offset in all.size():
		var i: int = (start + offset) % all.size()
		var p = all[i]
		# The ceiling bounds rules that BIND POLICY, not proposals -- see
		# _eligible(). A transfer or an external measure adds no constraint row
		# and no burden term, so capping those too would make the council fall
		# silent for most of a long run with content still unused.
		if not _eligible(state, org_id, p):
			continue
		state.orgs[org_id]["next_index"] = (i + 1) % all.size()
		return p
	return null


## Whether this proposal may open now: not already in force, not the treaty
## this council is ratifying, and -- for a proposal that binds policy -- under
## the rules-in-force ceiling. One rule for all three pickers, so the tabled
## path and the chair cannot open what the rotation would refuse.
static func _eligible(state, org_id: String, p) -> bool:
	var register: Dictionary = state.orgs[org_id]
	var rules: Dictionary = (register.get("rules", {}) as Dictionary)
	if rules.has(p.id):
		return false
	if String((register.get("ratifying", {}) as Dictionary).get("proposal_id", "")) == p.id:
		return false
	if p.constraint.is_empty():
		return true
	var constrained := 0
	for r in rules.values():
		if not (r as Dictionary).get("field", "").is_empty():
			constrained += 1
	return constrained < K.MAX_RULES_IN_FORCE


## The chair's pick, or null to fall through to the rotation.
##
## An AI chair opens the eligible proposal it supports most -- the presidency's
## real power is the agenda, and a chair that put forward what it wanted least
## would be a rotation in costume. Strict `>` keeps authored order on ties. A
## human chair opens what it chose with set_agenda(), or nothing (the rotation)
## if it chose nothing; a choice left over from a presidency that has ended is
## cleared, so a stale pick never surfaces years later under the next one.
static func _presidency_pick(state, loader, org_id: String):
	var chair := Council.presiding_nation(state, loader, org_id)
	var register: Dictionary = state.orgs[org_id]
	var choice := String(register.get("agenda_choice", ""))
	register["agenda_choice"] = ""
	if chair == "":
		return null
	var cns = state.nations[chair]
	if cns.has_budget:
		if choice == "":
			return null
		var cp = _proposal_by_id(loader, org_id, choice)
		return cp if cp != null and _eligible(state, org_id, cp) else null
	var best = null
	var best_s := -INF
	for p in loader.org_proposals.get(org_id, []):
		if not _eligible(state, org_id, p):
			continue
		var s: float = support(state, cns, p)
		if s > best_s:
			best_s = s
			best = p
	return best


## The loaded proposal with this id on this org's agenda, or null. Linear over a
## list of single digits' length -- a dictionary keyed by id would be a second
## index to keep in step with the ordered list the agenda rotates over, and the
## list is the authority.
static func _proposal_by_id(loader, org_id: String, proposal_id: String):
	for p in loader.org_proposals.get(org_id, []):
		if p.id == proposal_id:
			return p
	return null


## The council divides. Every member votes, the player's own vote is whatever
## they cast, and a qualified majority of member seats carries it.
static func _resolve(state, loader, org_id: String) -> void:
	var register: Dictionary = state.orgs[org_id]
	var pending: Dictionary = register["pending"]
	var proposal = _proposal_by_id(loader, org_id, String(pending["proposal_id"]))
	if proposal == null:
		register["pending"] = {}
		return

	var seats_for := 0
	var seats_against := 0
	var seats_total := 0
	var by_nation := {}
	var reasons := {}

	for id in members(state, org_id):
		var seats: int = live_seats(state, org_id, id)
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
	# tests/test_orgs.gd catches before this ships. Against cast seats the three
	# choices genuinely differ: backing it adds to the numerator, opposing it adds
	# to the denominator and blocks, and abstaining removes you from both and lets
	# it through on a smaller base. That is constructive abstention, and it is what
	# the real Council does.
	var cast: int = seats_for + seats_against
	var passed: bool = cast > 0 and float(seats_for) >= K.PASS_SEAT_FRACTION * float(cast)

	register["last_vote"] = {
		"proposal_id": proposal.id,
		"name": proposal.proposal_name,
		"org_id": org_id,
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
	register["pending"] = {}

	if passed:
		_adopt(state, loader, org_id, proposal)


## A passed proposal becomes a rule in force. The TERMS are stored, not the
## proposal id alone -- the same call docs/trade-model.md made for an agreement
## and docs/coercion-model.md for a measure, and for the same reason: what binds
## you is what the council adopted, not what the content file says later.
static func _adopt(state, loader, org_id: String, proposal) -> void:
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

	state.orgs[org_id]["rules"][proposal.id] = entry

	if not proposal.external_measure.is_empty():
		_apply_external_measure(state, loader, org_id, proposal)


## An org setting an external tariff collectively -- the first reader of
## V1.3c's directed register from outside src/sim/coercion.gd, and the item
## docs/coercion-model.md parked here by name.
##
## One entry per (member, non-member) ordered pair OF THIS ORG, written on the
## SAME directed key a player's own tariff uses, so nothing in src/sim/coercion.gd
## or src/sim/trade.gd needed a line changed to read it. A pair that already
## carries a measure is left alone: one measure per directed pair is a bound
## docs/coercion-model.md states, and two sets of terms would need a rule for how
## they compose that no content wants. The entry carries the adopting org's id,
## which is what a withdrawal reads to remove exactly the org's own measures.
static func _apply_external_measure(state, loader, org_id: String, proposal) -> void:
	var org_members := members(state, org_id)
	for member_id in org_members:
		for other_id in state.nations.keys():
			if org_members.has(other_id):
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
				"org": org_id,
				# The org does not answer a retaliation of its own; the target
				# mirrors each member individually through Diplomacy's own rule.
				"retaliated": true,
			}
			# A measure ends the treaty on that pair, exactly as
			# Diplomacy.execute() does for a player-imposed one. Symmetric key
			# deliberately: the contract had two sides even though the measure has
			# one. See docs/coercion-model.md.
			state.agreements.erase(RK.key(member_id, other_id))


## How one nation votes. The player casts; the others appraise.
static func _vote_of(state, nation_id: String, proposal, pending: Dictionary) -> String:
	if nation_id == state.player_nation_id:
		return String(pending.get("player_vote", VOTE_ABSTAIN))
	return VOTE_FOR if support(state, state.nations[nation_id], proposal) >= K.SUPPORT_THRESHOLD else VOTE_AGAINST


## How much a member's government wants a proposal adopted.
##
## The appraisal is foreign_policy.gd's -- this file's own interest model is
## deliberately none of the arithmetic, because foreign_policy.gd cannot preload
## this file (this one preloads it), so Bloc kept sole ownership of the breach
## arithmetic and passed the cost down. Same shape now: the cost is computed
## HERE against the PROPOSING ORG's membership, and passed down.
static func support(state, ns, proposal) -> float:
	return FP.appraise(state, ns, proposal, _proposed_rule_cost(state, ns, proposal))


## Why a member voted as it did, as a key src/ui/orgs_panel.gd turns into words.
static func vote_reason(state, ns, proposal) -> String:
	return FP.vote_reason(state, ns, proposal, _proposed_rule_cost(state, ns, proposal))


## What this proposal's constraint would add to this nation's burden if adopted,
## against its books as they stand now. Zero for a proposal that binds nobody's
## policy, and zero for a member already inside the rule -- or outside the org
## proposing it, which cannot happen: only members are asked to vote.
static func _proposed_rule_cost(state, ns, proposal) -> float:
	if proposal.constraint.is_empty():
		return 0.0
	return float(rule_breach(state, ns, proposal.org_id, proposal.constraint)["contribution"])


## The player's command. Returns false if there is nothing to vote on, if the
## choice is not one of the three, or if the player is not a member of the org
## whose council is voting -- refused rather than silently recorded, the same
## shape Diplomacy.execute() uses.
static func cast_vote(state, org_id: String, choice: String) -> bool:
	if not VOTE_CHOICES.has(choice):
		return false
	if not state.orgs.has(org_id):
		return false
	var pending: Dictionary = (state.orgs[org_id].get("pending", {}) as Dictionary)
	if pending.is_empty():
		return false
	var ns = state.player()
	if ns == null or not ns.orgs.has(org_id):
		return false
	state.orgs[org_id]["pending"]["player_vote"] = choice
	return true


## Public lookup for ratification.gd and the panel; the private name stays for
## the callers this file already has.
static func proposal_by_id(loader, org_id: String, proposal_id: String):
	return _proposal_by_id(loader, org_id, proposal_id)


## The player, chairing, chooses what opens next. Refused when the player does
## not chair this council now, or the proposal could not open -- the same
## refuse-rather-than-record shape cast_vote() uses.
static func set_agenda(state, loader, org_id: String, proposal_id: String) -> bool:
	if not state.orgs.has(org_id):
		return false
	var ns = state.player()
	if ns == null or Council.presiding_nation(state, loader, org_id) != ns.id:
		return false
	var p = _proposal_by_id(loader, org_id, proposal_id)
	if p == null or not _eligible(state, org_id, p):
		return false
	state.orgs[org_id]["agenda_choice"] = proposal_id
	return true


## The player, not chairing, pays the chair to put a proposal first. One tabled
## item per council at a time; refused in a council with no presidency (nobody
## to ask) and to the chair itself (set_agenda() is free for a reason).
static func table_proposal(state, loader, org_id: String, proposal_id: String) -> bool:
	if not state.orgs.has(org_id):
		return false
	var ns = state.player()
	if ns == null or not ns.orgs.has(org_id):
		return false
	var chair := Council.presiding_nation(state, loader, org_id)
	if chair == "" or chair == ns.id:
		return false
	if not (state.orgs[org_id].get("tabled", {}) as Dictionary).is_empty():
		return false
	var p = _proposal_by_id(loader, org_id, proposal_id)
	if p == null or not _eligible(state, org_id, p):
		return false
	Council.spend_relations(state, ns.id, chair, CouncilK.TABLE_RELATIONS_COST)
	state.orgs[org_id]["tabled"] = {"proposal_id": proposal_id, "by": ns.id}
	return true


# --- what the rules cost ----------------------------------------------------------

## How far outside the rules in force this nation is sitting, in [0, BURDEN_MAX].
## THE ONE OPINION PRICE: summed over every org's rules and clamped once, which
## is what the `europe` issue reads (V1.5c's no-second-approval-number). Zero
## for a non-member of every council org, for a council with nothing in force,
## and for a member that complies -- a complying player pays for membership in
## the policy they could not run, and that shows up on the spending lines they
## had to cut rather than here.
static func burden(state, ns, council_ids: Array) -> float:
	var total := 0.0
	for org_id in council_ids:
		if not ns.orgs.has(org_id):
			continue
		for rule in ((state.orgs[org_id].get("rules", {}) as Dictionary).values()):
			total += float(rule_breach(state, ns, org_id, rule)["contribution"])
	return clampf(total, 0.0, K.BURDEN_MAX)


## One org's share of the burden, clamped on its own -- the line the panel
## prints per org and the basis of that org's fine. With one council org this
## equals burden() exactly.
static func org_burden(state, ns, org_id: String) -> float:
	if not state.orgs.has(org_id) or not ns.orgs.has(org_id):
		return 0.0
	var total := 0.0
	for rule in ((state.orgs[org_id].get("rules", {}) as Dictionary).values()):
		total += float(rule_breach(state, ns, org_id, rule)["contribution"])
	return clampf(total, 0.0, K.BURDEN_MAX)


## How far one rule -- in force or merely PROPOSED -- puts this nation outside it,
## as {breach, contribution}. `breach` is the raw overshoot in the field's own
## units; `contribution` is what it adds to the burden, severity-weighted and
## tolerance-scaled.
##
## Extracted at V1.3e -- it was already written three times before that. Takes a
## rule DICTIONARY rather than a proposal, so a rule in force and a proposal's
## `constraint` block both go through it. Gated on membership OF THE ORG THAT
## HOLDS THE RULE, which is the one change from the eu_member gate it carried:
## a rule binds the org's members and nobody else, and a nation outside the org
## reads exactly 0.0.
static func rule_breach(state, ns, org_id: String, rule: Dictionary) -> Dictionary:
	var out := {"breach": 0.0, "contribution": 0.0}
	if ns == null or not is_member(state, org_id, ns.id):
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
		"co2e_per_capita_t": return ns.co2e_per_capita_t
		_:
			# Loud, like every sibling _read_field(). This was the one that returned
			# 0.0 in silence while its own comment claimed it behaved like the others
			# -- a mistyped rule field then read as a nation scoring zero on it, which
			# for a deficit rule is perfect compliance.
			push_error("orgs: unknown rule field '%s'" % field)
			return 0.0


# --- accession and withdrawal -----------------------------------------------------

## The fight, as someday.md's row named it: a domestic referendum first -- the
## mandate -- and then a negotiation countdown authored per org, after which
## membership actually flips. The referendum machinery is reused WHOLE:
## Referendum.announce() takes any question id, its campaign is the domestic
## fight, and losing it charges the president the same way losing an amendment
## vote does. What is new here is only the countdown and the flip.
##
## PLAYER-INITIATED ONLY. The nine never begin a fight -- there is no desire
## term for membership in any agenda model, and inventing one unmeasured is
## exactly the synthetic-appetite shape foreign-policy-model refuses.
## referendum.gd's own precedent, pinned by test.

const FIGHT_ACCESSION := "accession"
const FIGHT_WITHDRAWAL := "withdrawal"


## Ask the country whether to join. Refused loudly, never silently recorded.
static func begin_accession(state, loader, ns, org_id: String) -> Dictionary:
	return _begin_fight(state, loader, ns, org_id, FIGHT_ACCESSION)


## Ask the country whether to leave.
static func begin_withdrawal(state, loader, ns, org_id: String) -> Dictionary:
	return _begin_fight(state, loader, ns, org_id, FIGHT_WITHDRAWAL)


static func _begin_fight(state, loader, ns, org_id: String, kind: String) -> Dictionary:
	if not ns.has_budget:
		# has_budget means a human decides here; this gate is what keeps the
		# nine out, and it reads the OTHER way to every foreign-policy gate
		# because a human deciding is the exception, not the rule.
		return {"ok": false, "reason": "not the head of state's to call"}
	if ns.orgs.has(org_id) and kind == FIGHT_ACCESSION:
		return {"ok": false, "reason": "already a member"}
	if not ns.orgs.has(org_id) and kind == FIGHT_WITHDRAWAL:
		return {"ok": false, "reason": "not a member"}
	if not ns.referendum_pending.is_empty():
		# One question at a time -- the referendum register is the whole of that
		# rule, and a country cannot credibly fight two constitutions at once.
		return {"ok": false, "reason": "a referendum is already before the country"}
	for fight in state.accessions:
		if String(fight.get("nation_id", "")) == ns.id:
			return {"ok": false, "reason": "a membership fight is already running"}
	var org = loader.orgs_by_id.get(org_id)
	if org == null:
		return {"ok": false, "reason": "no such organisation"}

	var position: Dictionary = org.accession_position if kind == FIGHT_ACCESSION else org.withdrawal_position
	if position.is_empty():
		return {"ok": false, "reason": "this organisation carries no way in or out"}

	Referendum.announce(ns, kind + ":" + org_id, position)
	state.accessions.append({
		"nation_id": ns.id,
		"org_id": org_id,
		"kind": kind,
		"phase": "referendum",
		"months_left": 0,
		"months_total": org.accession_months if kind == FIGHT_ACCESSION else org.withdrawal_months,
	})
	return {"ok": true, "reason": ""}


## One month of every membership fight. Referendum results are consumed the
## month AFTER they resolve -- Orgs.tick_month() runs before
## Legislature.tick_month(), which is where Referendum.resolve_due() is called
## -- so a passed vote spends its resolution month as news and begins the
## negotiation countdown the next.
static func _tick_accessions(state, loader) -> void:
	var finished := []
	for i in state.accessions.size():
		var fight: Dictionary = state.accessions[i]
		var ns = state.nations.get(String(fight.get("nation_id", "")))
		if ns == null:
			finished.append(i)
			continue
		var question := String(fight.get("kind", "")) + ":" + String(fight.get("org_id", ""))

		if String(fight.get("phase", "")) == "referendum":
			var result: Dictionary = ns.last_referendum_result
			if String(result.get("law_id", "")) != question or bool(result.get("org_fight_consumed", false)):
				continue
			# Consumed exactly once: the flag lives on the result record, so a
			# long negotiation cannot be re-triggered by whatever referendum
			# overwrites last_referendum_result next.
			result["org_fight_consumed"] = true
			if bool(result.get("passed", false)):
				fight["phase"] = "negotiation"
				fight["months_left"] = int(fight.get("months_total", 0))
			else:
				# The people refused. _charge() already priced the loss; the
				# fight simply ends with membership where it was.
				finished.append(i)

		elif String(fight.get("phase", "")) == "negotiation":
			fight["months_left"] = int(fight.get("months_left", 0)) - 1
			if int(fight["months_left"]) <= 0:
				_flip_membership(state, loader, ns, fight)
				finished.append(i)

	finished.reverse()
	for i in finished:
		state.accessions.remove_at(i)


## The day membership actually changes. Every consequence flows from the two
## live reads: NationState.orgs (the trade weight, resting relations, the
## appraisal's outside term, the councils) and the per-org base transfer, which
## is re-derived for EVERY member of a transfer org because its own mean moved
## with the roster.
static func _flip_membership(state, loader, ns, fight) -> void:
	var org_id := String(fight.get("org_id", ""))
	var org = loader.orgs_by_id.get(org_id)
	if org == null:
		return

	if String(fight.get("kind", "")) == FIGHT_ACCESSION:
		if not ns.orgs.has(org_id):
			ns.orgs.append(org_id)
			ns.orgs.sort()
		# V4.4: the accession_won hook's stamp. The finished fight is deleted from
		# state.accessions the same tick this runs, so nothing else records WHEN a
		# nation joined -- events.gd's emitter reads this and nothing else does, and
		# it fires only for the Union ("eu"), though the stamp is written for every org.
		ns.last_accession = {"org": org_id, "month_index": int(state.year) * 12 + int(state.month)}
		# The joiner's weight: the org's authored `accession_seats`, written as
		# LIVE seat state. The content table is the authored START and lists no
		# joiner; a member whose vote weighs zero is a member in name only --
		# the review's second-class-member finding, fixed at the write rather
		# than patched at each reader.
		ns.org_seats[org_id] = org.accession_seats
		# Membership ends the org's collective measures aimed AT this nation:
		# the common external tariff cannot keep levying on a fellow member,
		# and there is no repeal path that would ever lift it otherwise. The
		# mirror of the withdrawal cleanup below -- one direction each.
		var doomed := []
		for directed in state.measures.keys():
			var terms: Dictionary = state.measures[directed]
			if String(terms.get("org", "")) == org_id and String(directed).ends_with(">" + ns.id):
				doomed.append(directed)
		for directed in doomed:
			state.measures.erase(directed)
		var parl = parliament(loader)
		if parl != null and String(parl.id) == org_id:
			# Joining the parliament org picks up its clock -- rolled forward in
			# whole terms until it is in the FUTURE, because the authored date
			# is static content and a nation acceding after it would otherwise
			# carry a deadline that has already passed and never vote again.
			var next_e: Dictionary = parl.parliament.get("next_election", {})
			var year := int(next_e.get("year", 0))
			var month := int(next_e.get("month", 0))
			var term := int(parl.parliament.get("term_years", 5))
			while year < state.year or (year == state.year and month <= state.month):
				year += term
			ns.next_ep_election_year = year
			ns.next_ep_election_month = month
	else:
		ns.orgs.erase(org_id)
		# The ex-member's standing contribution and seat weight die with the
		# membership; the re-derive below writes the REMAINING members' lines
		# at the new mean.
		ns.org_base_transfer_pct_gdp.erase(org_id)
		ns.org_seats.erase(org_id)
		var parl = parliament(loader)
		if parl != null and String(parl.id) == org_id:
			ns.next_ep_election_year = 0
			ns.next_ep_election_month = 0
		# Withdrawal stops THIS nation levying the org's collective measures;
		# measures the org's remaining members aim AT it stand, which is the
		# common external tariff working as designed the day after exit.
		var doomed := []
		for directed in state.measures.keys():
			var terms: Dictionary = state.measures[directed]
			if String(terms.get("org", "")) == org_id and String(directed).begins_with(ns.id + ">"):
				doomed.append(directed)
		for directed in doomed:
			state.measures.erase(directed)

	if org.net_transfers:
		# Re-derive the org's whole net-position table over the LIVE roster: the
		# mean the formula divides by moved with the membership, and the content
		# table did not -- a re-derive over the authored roster writes back
		# identical values, which is a no-op wearing a derivative's clothes.
		var live_roster := members(state, org_id)
		var positions := net_positions(loader, org_id, live_roster)
		for id in positions.keys():
			var member = state.nations.get(id)
			# Live membership, not content: net_positions() over the live roster
			# already excludes the leaver, but the guard keeps the write honest
			# if the roster and the bases ever disagree.
			if member != null and member.orgs.has(org_id):
				member.org_base_transfer_pct_gdp[org_id] = float(positions[id])





# --- queries, for the UI and the tests -------------------------------------------

## Rules in force across every org this nation belongs to, as [{id, org_id,
## name, field, op, value, severity, transfer_pct_gdp, breach, contribution}],
## sorted by (org, rule id) so the panel's order is stable across repaints.
## `breach` and `contribution` are this nation's, so the panel can say which
## rule is costing what rather than only what the total is.
static func rules_in_force(state, ns) -> Array:
	var out: Array = []
	for org_id in council_ids(state):
		if not ns.orgs.has(org_id):
			continue
		var ids: Array = (state.orgs[org_id].get("rules", {}) as Dictionary).keys()
		ids.sort()
		for id in ids:
			var rule: Dictionary = state.orgs[org_id]["rules"][id]
			var entry := rule.duplicate(true)
			entry["id"] = id
			entry["org_id"] = org_id
			var scored: Dictionary = rule_breach(state, ns, org_id, rule)
			entry["breach"] = scored["breach"]
			entry["contribution"] = scored["contribution"]
			out.append(entry)
	return out


static func pending(state, org_id: String) -> Dictionary:
	if not state.orgs.has(org_id):
		return {}
	return (state.orgs[org_id].get("pending", {}) as Dictionary)


static func last_vote(state, org_id: String) -> Dictionary:
	if not state.orgs.has(org_id):
		return {}
	return (state.orgs[org_id].get("last_vote", {}) as Dictionary)


## What the player's contribution breaks down into, for the budget panel: the
## standing net position per org, what each org's rules in force moved it by,
## and the penalties being charged for defying them. Sums to
## ns.bloc_transfer_pct_gdp.
static func transfer_breakdown(state, ns) -> Dictionary:
	var orgs := {}
	var total := 0.0
	for org_id in ns.orgs:
		var register: Dictionary = state.orgs.get(org_id, {})
		var contributions := 0.0
		var rule_transfers := 0.0
		for rule in (register.get("rules", {}) as Dictionary).values():
			rule_transfers += float(rule.get("transfer_pct_gdp", 0.0))
			contributions += float(rule_breach(state, ns, org_id, rule)["contribution"])
		var line := (
			float(ns.org_base_transfer_pct_gdp.get(org_id, 0.0))
			+ rule_transfers
			+ K.FINE_PCT_GDP_PER_BURDEN * clampf(contributions, 0.0, K.BURDEN_MAX)
		)
		orgs[org_id] = {
			"base": float(ns.org_base_transfer_pct_gdp.get(org_id, 0.0)),
			"rules": rule_transfers,
			"fine": K.FINE_PCT_GDP_PER_BURDEN * clampf(contributions, 0.0, K.BURDEN_MAX),
		}
		total += line
	return {
		"total": total,
		"orgs": orgs,
	}
