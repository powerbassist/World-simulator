extends RefCounted

## The supranational organisations, V3.2: membership as live data, one register
## per council, one composition rule for the channels several orgs share.
##
## This file generalises src/sim/bloc.gd -- the V1.3d machine, hardcoded to the
## one EU object -- and REPLACES it: the council machinery moves in as Task 3
## of the block, and bloc.gd is deleted. Model: docs/orgs-model.md.
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
##   - External measures are per org and first-adopted holds the pair.
##   - Standing bonuses (resting relations, gravity trade) sum over the orgs
##     two nations SHARE -- Org.shared_bonus().
##
## No UI knowledge, no engine access, no signals, no randomness. Runs AFTER
## Budget.tick_month() and BEFORE Opinion.tick_month(), where bloc.gd sat --
## the placement comment there is load-bearing and moves with the machine.

const K = preload("res://src/sim/bloc_constants.gd")
const Org = preload("res://src/core/org.gd")


## New-game state: one register per council org, the static effects snapshot,
## and every nation's membership plus per-org base transfer.
##
## Called from GameState.new_game() after every nation exists, next to
## Bloc.init_state() while that still stands: the council is not any one
## nation's property, so it cannot be built inside the per-nation loop.
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
			}
		state.org_effects[org.id] = {
			"relations_bonus": org.relations_bonus,
			"trade_bonus": org.trade_bonus,
		}

	for ns in state.nations.values():
		ns.orgs = []
		ns.org_base_transfer_pct_gdp = {}
	for org in loader.orgs:
		var positions := net_positions(loader, org.id) if org.net_transfers else {}
		for ns in state.nations.values():
			if org.is_member(ns.id):
				ns.orgs.append(org.id)
				if org.net_transfers:
					ns.org_base_transfer_pct_gdp[org.id] = float(positions.get(ns.id, 0.0))
	# Sorted, because every reader -- shared_bonus(), the transfer sum, the
	# panel -- iterates memberships and the iteration must be reproducible
	# rather than dependent on loader file order.
	for ns in state.nations.values():
		ns.orgs.sort()


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
static func net_positions(loader, org_id: String) -> Dictionary:
	var out := {}
	var org = loader.orgs_by_id.get(org_id)
	if org == null:
		return out

	var total_gdp := 0.0
	var total_pop := 0.0
	for n in loader.nations.values():
		if not org.is_member(n.id):
			continue
		total_gdp += float(n.gdp_eur_bn)
		total_pop += float(n.population)
	if total_pop <= 0.0 or total_gdp <= 0.0:
		return out
	var mean: float = total_gdp / total_pop

	for n in loader.nations.values():
		if not org.is_member(n.id) or float(n.population) <= 0.0:
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


## The orgs that hold a council, as sorted ids. state.orgs carries exactly the
## council orgs' registers, so the register keys ARE the answer -- no loader
## needed, and a save's registers cannot disagree with the question.
static func council_ids(state) -> Array:
	var out: Array = state.orgs.keys()
	out.sort()
	return out
