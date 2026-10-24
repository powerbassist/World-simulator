extends RefCounted

## Five portfolios, keyed to the spending lines, held by coalition parties.
##
## A portfolio's position in the ideology space is DERIVED, not authored: the
## size-and-salience-weighted mean of the ideal points of the blocs that
## actually weight that spending line, reusing election_constants.BLOC_IDEAL
## and opinion_constants.BLOC_SALIENCE_BASE exactly the way BLOC_IDEAL itself
## documents reusing BLOC_SALIENCE_BASE. No portfolio coordinate is written
## down anywhere in this file.
##
## A party's effectiveness on a portfolio is its authored `competence` scaled
## by affinity -- how close its own ideology_slot sits to that derived
## position. Effectiveness multiplies the spending delta opinion.gd already
## reads; it does not touch the economy channel, which is deliberately not
## built this block.
##
## Loyalty reads Government.cohesion() and Discipline.of() -- both already
## exist -- plus one new term, shortfall: how far below its d'Hondt entitlement
## a coalition party is held. An unpopular government with a shorted partner
## can lose that partner's minister to resignation.
##
## No engine access, no node references, no signals, no randomness -- the same
## discipline every other module in src/sim/ keeps. Depends on Government (for
## cohesion() and penalise_blocs()) but Government never depends on this file,
## which is why Cabinet.seat() is called by the ORCHESTRATOR right after
## Government.form()/fall() (game_state.gd, elections.gd, legislature.gd)
## rather than from inside government.gd itself -- the reverse would be a
## preload() cycle.
##
## The model, and the section 1 measurement that set every constant in
## cabinet_constants.gd before this file was written, is docs/cabinet-model.md.

const CK = preload("res://src/sim/cabinet_constants.gd")
const EK = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const ElectoralSystems = preload("res://src/sim/electoral_systems.gd")
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")

const NEUTRAL_POSITION := {"economic": 0.0, "social": 0.0}


## Seed empty cabinet state. Runs for all ten nations, same as every other
## init_nation() in src/sim/ -- a second playable nation is then a data
## change, not a change here. seat() is called separately, after
## Government.init_nation() has formed the starting coalition.
static func init_nation(ns) -> void:
	ns.cabinet = {}
	ns.cabinet_effectiveness = {}
	for f in CK.PORTFOLIO_KEYS:
		ns.cabinet[f] = ""
		ns.cabinet_effectiveness[f] = CK.VACANT_EFFECTIVENESS
	ns.cabinet_entitlement = {}
	ns.reshuffles_called = 0
	ns.resignations_count = 0
	ns.last_resignation = {}


## The size-and-salience-weighted mean of the ideal points of the blocs that
## weight this portfolio's spending line. Every table read here already
## exists; this is the third time the project has taken this exact move --
## election_constants.BLOC_IDEAL documents doing it once for blocs, and
## docs/government-model.md and docs/election-model.md both rejected an
## authored matrix for the same reason a 6x5x10 competence table was rejected
## for this block. A salience retune moves the portfolios with it, rather than
## silently desynchronising them.
static func portfolio_position(portfolio: String) -> Dictionary:
	var econ := 0.0
	var social := 0.0
	var weight := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		var salience: float = float(OpinionK.BLOC_SALIENCE_BASE[bloc].get(portfolio, 0.0))
		if salience <= 0.0:
			continue
		var w: float = float(OpinionK.BLOC_SIZE[bloc]) * salience
		var ideal: Dictionary = EK.BLOC_IDEAL[bloc]
		econ += w * float(ideal["economic"])
		social += w * float(ideal["social"])
		weight += w
	if weight <= 0.0:
		return NEUTRAL_POSITION.duplicate()
	return {"economic": econ / weight, "social": social / weight}


static func _distance(a: Dictionary, b: Dictionary) -> float:
	var d_econ: float = float(a["economic"]) - float(b["economic"])
	var d_social: float = float(a["social"]) - float(b["social"])
	return sqrt(d_econ * d_econ + d_social * d_social)


## How close a party's own ideology_slot sits to a portfolio's derived
## position, in (0, 1]. The same Gaussian falloff shape
## election_constants.AFFINITY_SIGMA gives bloc-to-slot affinity --
## CABINET_SIGMA reuses that constant's scale rather than inventing a fourth.
static func affinity(party, portfolio: String) -> float:
	var pos: Dictionary = EK.SLOT_POSITION.get(party.ideology_slot, NEUTRAL_POSITION)
	var target := portfolio_position(portfolio)
	var dist := _distance(pos, target)
	return exp(-pow(dist / CK.CABINET_SIGMA, 2.0))


## A party's authored skill, scaled by how naturally suited it is to this
## particular portfolio. The rejected alternative -- a 6x5x10 competence
## matrix authored directly -- is exactly what government-model.md and
## election-model.md already rejected for coalition preferences and
## bloc-to-slot affinity, for the same reason: numbers nobody could
## individually defend, retuned as a group at every balance pass.
static func competence(party, portfolio: String) -> float:
	return float(party.competence) * affinity(party, portfolio)


static func _effectiveness_for(party, portfolio: String) -> float:
	var comp := competence(party, portfolio)
	return 1.0 + CK.COMPETENCE_SPAN * (comp - CK.COMPETENCE_NEUTRAL)


## Reads the cache seat()/assign()/tick_month() maintain -- the same pattern
## government.gd's coalition_position uses so legislature.gd never needs a
## party_list to read a government's agreed line. opinion.gd calls this
## without ever needing to know a Party object exists.
static func effectiveness(ns, portfolio: String) -> float:
	return float(ns.cabinet_effectiveness.get(portfolio, CK.VACANT_EFFECTIVENESS))


## How many of the five portfolios each coalition party is entitled to, by
## d'Hondt over coalition seats -- ElectoralSystems.pr_dhondt() given five
## "seats" to distribute, rather than a second allocation routine.
static func entitlement(ns, party_list: Array) -> Dictionary:
	var vote_share := {}
	var total := 0.0
	for pid in ns.coalition_party_ids:
		var seats := float(ns.seats_by_party.get(pid, 0))
		vote_share[pid] = seats
		total += seats
	if total <= 0.0:
		return {}
	for pid in vote_share:
		vote_share[pid] = float(vote_share[pid]) / total
	return ElectoralSystems.pr_dhondt(vote_share, CK.PORTFOLIO_KEYS.size(), 0.0)


## How far below its entitlement a party is currently held, in [0, 1]. Zero for
## a party with no entitlement or holding all of it; one for a party entitled
## to at least one portfolio and holding none. This is the term that makes
## resignation attributable to the player's own assignment rather than to
## general unpopularity -- see docs/cabinet-model.md.
static func shortfall(ns, party_id: String) -> float:
	var ent := int(ns.cabinet_entitlement.get(party_id, 0))
	if ent <= 0:
		return 0.0
	var held := 0
	for f in ns.cabinet:
		if String(ns.cabinet[f]) == party_id:
			held += 1
	return clampf(float(maxi(0, ent - held)) / float(ent), 0.0, 1.0)


## Discipline scaled by cohesion, minus a penalty for being held below
## entitlement. Both Discipline.of() and Government.cohesion() already exist;
## shortfall is the one new term. See docs/cabinet-model.md for why this term
## and not a second equation inside hostility() carries loyalty.
static func loyalty(ns, party) -> float:
	var d := Discipline.of(ns, party)
	var coh := Government.cohesion(ns, party)
	var sf := shortfall(ns, party.id)
	return clampf(d * coh - CK.SHORTFALL_PENALTY * sf, 0.0, 1.0)


## Assemble a cabinet against the coalition the nation currently has. Called by
## the orchestrator immediately after Government.form()/fall() -- game_state.gd,
## elections.gd, legislature.gd -- never from inside government.gd, which would
## make a preload() cycle out of Cabinet depending on Government.
##
## Deterministic: entitlement by d'Hondt, then each party in entitlement-then-id
## order takes its highest-affinity remaining portfolio, one at a time. Ties on
## affinity break on portfolio key. Two calls on unchanged state produce an
## identical cabinet -- the same guarantee Government.form() already carries.
static func seat(ns, party_list: Array) -> void:
	ns.cabinet = {}
	ns.cabinet_effectiveness = {}
	for f in CK.PORTFOLIO_KEYS:
		ns.cabinet[f] = ""
		ns.cabinet_effectiveness[f] = CK.VACANT_EFFECTIVENESS

	if ns.coalition_party_ids.is_empty():
		ns.cabinet_entitlement = {}
		return

	var by_id := {}
	for p in party_list:
		by_id[p.id] = p

	var ent := entitlement(ns, party_list)
	ns.cabinet_entitlement = ent

	var order: Array = ns.coalition_party_ids.duplicate()
	order.sort_custom(func(a, b):
		var ea := int(ent.get(a, 0))
		var eb := int(ent.get(b, 0))
		if ea != eb:
			return ea > eb
		return String(a) < String(b)
	)

	var remaining: Array = CK.PORTFOLIO_KEYS.duplicate()
	for pid in order:
		if not by_id.has(pid):
			continue
		var party = by_id[pid]
		var slots := int(ent.get(pid, 0))
		for _i in range(slots):
			if remaining.is_empty():
				break
			var best_f := ""
			var best_score := -1.0
			for f in remaining:
				var score := affinity(party, f)
				if score > best_score or (is_equal_approx(score, best_score) and (best_f == "" or f < best_f)):
					best_score = score
					best_f = f
			if best_f != "":
				ns.cabinet[best_f] = pid
				ns.cabinet_effectiveness[best_f] = _effectiveness_for(party, best_f)
				remaining.erase(best_f)


static func can_assign(ns, portfolio: String, party_id: String) -> bool:
	return refusal_reason(ns, portfolio, party_id).is_empty()


## The one place the rule is turned into words, so government_panel.gd does not
## re-derive it -- the same pair dissolution.gd established for its own
## refusals.
static func refusal_reason(ns, portfolio: String, party_id: String) -> String:
	if not CK.PORTFOLIO_KEYS.has(portfolio):
		return "no such portfolio"
	if not ns.coalition_party_ids.has(party_id):
		return "not a member of the governing coalition"
	return ""


## The player command -- the Budget.commit()/Legislature.propose() shape.
## Coalition parties only, refused through can_assign()/refusal_reason() above.
## Costs RESHUFFLE_BLOC_PENALTY through the same accumulator Article 49.3, a
## fallen government, a dissolution and a resignation all move, so
## opinion_constants.INERTIA_RATE and every bound in docs/opinion-model.md
## still apply -- approval does not move in the commit month.
static func assign(state, portfolio: String, party_id: String, party_list: Array) -> void:
	var ns = state.player()
	if ns == null:
		return
	if not can_assign(ns, portfolio, party_id):
		return
	var by_id := {}
	for p in party_list:
		by_id[p.id] = p
	if not by_id.has(party_id):
		return

	ns.cabinet[portfolio] = party_id
	ns.cabinet_effectiveness[portfolio] = _effectiveness_for(by_id[party_id], portfolio)
	ns.reshuffles_called += 1
	ns.reshuffle_month = int(state.year) * 12 + int(state.month)  # V5.2b b3: the office wants ask next month
	Government.penalise_blocs(ns, CK.RESHUFFLE_BLOC_PENALTY)


## Vacate any portfolio whose holder's resignation signal --
## unpopularity * (1 - loyalty) -- crosses RESIGNATION_THRESHOLD this month.
## Every check reads the state from BEFORE this tick's vacancies, so a
## resignation earlier in PORTFOLIO_KEYS order cannot change another
## portfolio's shortfall reading within the same tick -- deterministic, no
## rand() anywhere, the same discipline every other tick_month() in src/sim/
## keeps.
static func tick_month(state, loader) -> void:
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		if ns.coalition_party_ids.is_empty():
			continue
		var unpop := Discipline.unpopularity(ns)
		if unpop <= 0.0:
			continue

		var party_list: Array = loader.parties.get(ns.id, [])
		var by_id := {}
		for p in party_list:
			by_id[p.id] = p

		var to_vacate: Array = []
		for f in CK.PORTFOLIO_KEYS:
			var pid: String = String(ns.cabinet.get(f, ""))
			if pid == "" or not by_id.has(pid):
				continue
			var loy := loyalty(ns, by_id[pid])
			if unpop * (1.0 - loy) > CK.RESIGNATION_THRESHOLD:
				to_vacate.append(f)

		for f in to_vacate:
			var pid: String = String(ns.cabinet.get(f, ""))
			ns.cabinet[f] = ""
			ns.cabinet_effectiveness[f] = CK.VACANT_EFFECTIVENESS
			ns.resignations_count += 1
			ns.last_resignation = {
				"portfolio": f, "party_id": pid, "year": state.year, "month": state.month,
			}
			Government.penalise_blocs(ns, CK.RESIGNATION_BLOC_PENALTY)
