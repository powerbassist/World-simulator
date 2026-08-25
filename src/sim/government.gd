extends RefCounted

## Government formation, coalition cohesion, and the censure arithmetic.
##
## A government is no longer one party id. It is a set of parties, a seat count,
## and an agreed position -- and that position lives in the SAME two-axis
## ideology space election_constants.gd's SLOT_POSITION already puts every party
## on and every law in. No second vocabulary, the rule
## docs/legislature-model.md set for laws, kept here for coalitions.
##
## Formation dispatches on nation.formation_method, never on the nation id --
## docs/engine-decision.md Rule 1, the same pattern electoral_systems.gd uses.
##
## No engine access, no node references, no signals, and no randomness. A
## formation is exactly reproducible from state, the same discipline
## economy.gd, budget.gd, opinion.gd, elections.gd and legislature.gd all keep.
##
## The model, and the justification for every constant, is
## docs/government-model.md.

const GK = preload("res://src/sim/government_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const DK = preload("res://src/sim/discipline_constants.gd")

const NEUTRAL_POSITION := {"economic": 0.0, "social": 0.0}


## Seed formation state and form the starting government. Runs for all ten
## nations, same as Opinion/Elections/Legislature.init_nation -- a second
## playable nation is then a data change, not a change here.
static func init_nation(ns, nation, party_list: Array) -> void:
	ns.formation_method = nation.formation_method
	ns.censure_rule = nation.censure_rule
	ns.amendment_rule = nation.amendment_rule
	ns.referendum_mode = nation.referendum_mode
	ns.permits_system_change = nation.permits_system_change
	ns.head_of_government_title = nation.head_of_government_title
	ns.start_head_of_government_person_id = nation.head_of_government_person_id

	ns.system_id = nation.system_id
	ns.head_of_state_kind = nation.head_of_state_kind
	ns.head_of_state_title = nation.head_of_state_title
	ns.head_of_state_person_id = nation.head_of_state_person_id
	ns.head_of_state_next_year = nation.head_of_state_next_year
	ns.head_of_state_next_month = nation.head_of_state_next_month
	ns.term_limit = nation.term_limit

	ns.coalition_party_ids = []
	ns.coalition_seats = 0
	ns.coalition_position = NEUTRAL_POSITION.duplicate()
	ns.pm_party_id = ""
	ns.pm_person_id = ""
	ns.is_cohabitation = false
	ns.is_minority = false
	ns.last_formation = {}

	ns.force_cooldown_months = 0
	ns.censure_barred_party_ids = []
	ns.governments_fallen = 0
	ns.last_censure = {}

	form(ns, party_list)


## Assemble a government against the assembly the nation currently has, write it
## onto `ns`, and return the same description as a Dictionary for the UI to read.
## Idempotent: calling it twice on unchanged state produces the same government.
static func form(ns, party_list: Array) -> Dictionary:
	var by_id := {}
	for party in party_list:
		by_id[party.id] = party

	var result: Dictionary
	match ns.formation_method:
		"directorial":
			result = _form_directorial(ns, party_list)
		"presidential_appointment":
			result = _form_presidential(ns, party_list, by_id)
		"chancellor_election", "investiture", "coalition_negotiation", "largest_party":
			result = _form_from_largest(ns, party_list, by_id)
		_:
			push_error("government: unknown formation method '%s'" % ns.formation_method)
			result = _empty_result()

	ns.coalition_party_ids = result["coalition_party_ids"]
	ns.coalition_seats = result["coalition_seats"]
	ns.coalition_position = result["position"]
	ns.pm_party_id = result["pm_party_id"]
	ns.pm_person_id = result["pm_person_id"]
	ns.is_cohabitation = result["cohabitation"]
	ns.is_minority = result["minority"]
	ns.last_formation = result
	return result


static func _empty_result() -> Dictionary:
	return {
		"coalition_party_ids": [],
		"coalition_seats": 0,
		"position": NEUTRAL_POSITION.duplicate(),
		"pm_party_id": "",
		"pm_person_id": "",
		"cohabitation": false,
		"minority": true,
		"method": "",
	}


## Seats a coalition must EXCEED to be a majority government. Anything at or
## below is a minority government, which is a legal outcome and not a failure --
## docs/government-model.md.
static func majority_seats(ns) -> int:
	return int(floor(float(ns.assembly_seats) * GK.MAJORITY_FRACTION))


## Seats a censure motion must reach to bring the government down. Only
## meaningful for the two absolute rules; `simple_present` compares supporters
## against opponents instead, and `none` cannot be reached at all. Returned as
## assembly_seats + 1 for `none` so any caller comparing against it fails safe.
static func censure_seats(ns) -> int:
	if ns.censure_rule == "none":
		return ns.assembly_seats + 1
	if GK.ABSOLUTE_CENSURE_RULES.has(ns.censure_rule):
		return int(floor(float(ns.assembly_seats) * GK.CENSURE_ABSOLUTE_FRACTION)) + 1
	# simple_present has no fixed seat threshold; the panel shows the majority
	# line as the nearest honest equivalent.
	return majority_seats(ns) + 1


## The seat-weighted mean of the coalition's members' ideology positions -- the
## agreed position of the government. The one new quantity this module defines,
## and it is a mean of numbers that already existed.
static func position_of(seats_by_party: Dictionary, party_ids: Array, by_id: Dictionary) -> Dictionary:
	var total := 0.0
	var econ := 0.0
	var social := 0.0
	for pid in party_ids:
		if not by_id.has(pid):
			continue
		var seats := float(seats_by_party.get(pid, 0))
		if seats <= 0.0:
			continue
		var pos: Dictionary = K.SLOT_POSITION.get(by_id[pid].ideology_slot, NEUTRAL_POSITION)
		econ += seats * float(pos["economic"])
		social += seats * float(pos["social"])
		total += seats
	if total <= 0.0:
		return NEUTRAL_POSITION.duplicate()
	return {"economic": econ / total, "social": social / total}


## Symmetric: a cordon is authored once, on the party that draws it, and read
## from both directions so authoring order cannot change the outcome.
static func _refuses(a, b) -> bool:
	return a.excluded_partners.has(b.id) or b.excluded_partners.has(a.id)


static func _compatible(candidate, member_ids: Array, by_id: Dictionary) -> bool:
	for pid in member_ids:
		if by_id.has(pid) and _refuses(candidate, by_id[pid]):
			return false
	return true


static func _seats(ns, party_id: String) -> int:
	return int(ns.seats_by_party.get(party_id, 0))


static func _distance(pos_a: Dictionary, pos_b: Dictionary) -> float:
	var d_econ: float = float(pos_a["economic"]) - float(pos_b["economic"])
	var d_social: float = float(pos_a["social"]) - float(pos_b["social"])
	return sqrt(d_econ * d_econ + d_social * d_social)


## Greedy formation outward from an anchor party. After every addition the
## agreed position is recomputed, so the coalition drifts toward whoever has
## already joined -- a third partner is judged against the government being
## built, not against the anchor alone.
##
## Ties are broken by seat count and then by party id, so the search is fully
## deterministic with no rand() anywhere.
static func _grow(ns, anchor_id: String, party_list: Array, by_id: Dictionary, barred: Array = []) -> Array:
	if not by_id.has(anchor_id):
		return []
	var chosen: Array = [anchor_id]
	var target := majority_seats(ns)
	var total := _seats(ns, anchor_id)

	while total <= target:
		var position := position_of(ns.seats_by_party, chosen, by_id)
		var best = null
		var best_key: Array = []
		for party in party_list:
			if chosen.has(party.id) or barred.has(party.id):
				continue
			if _seats(ns, party.id) <= 0:
				continue
			if not _compatible(party, chosen, by_id):
				continue
			var pos: Dictionary = K.SLOT_POSITION.get(party.ideology_slot, NEUTRAL_POSITION)
			var dist := _distance(position, pos)
			# A partner too far from the line refuses regardless of arithmetic.
			# Without this the search buys any seat that closes the gap.
			if dist > GK.MAX_PARTNER_DISTANCE:
				continue
			var key := [dist, -_seats(ns, party.id), party.id]
			if best == null or _key_less(key, best_key):
				best = party
				best_key = key
		if best == null:
			break
		chosen.append(best.id)
		total += _seats(ns, best.id)

	return chosen


## Lexicographic compare on [distance, -seats, id]. Written out rather than
## sorted, because the candidate set is rebuilt each round against a position
## that has moved.
static func _key_less(a: Array, b: Array) -> bool:
	if not is_equal_approx(float(a[0]), float(b[0])):
		return float(a[0]) < float(b[0])
	if int(a[1]) != int(b[1]):
		return int(a[1]) < int(b[1])
	return String(a[2]) < String(b[2])


static func _describe(ns, chosen: Array, by_id: Dictionary, pm_party_id: String, cohabitation: bool) -> Dictionary:
	var total := 0
	for pid in chosen:
		total += _seats(ns, pid)

	# A person id, never a name: src/sim/ handles no names at all after U6b, and
	# the UI resolves against loader.person_by_id. That is what the re-key bought
	# -- this function used to reach into a Party for a display string.
	var pm_person_id := ""
	if by_id.has(pm_party_id):
		# The head of government named in the nation file holds office at game
		# start and comes back whenever the executive's own party takes the
		# premiership -- in France the President is not the Prime Minister, so
		# that party's authored leader is the wrong person to name.
		if pm_party_id == ns.incumbent_party_id and ns.start_head_of_government_person_id != "":
			pm_person_id = ns.start_head_of_government_person_id
		else:
			pm_person_id = by_id[pm_party_id].leader_person_id

	return {
		"coalition_party_ids": chosen,
		"coalition_seats": total,
		"position": position_of(ns.seats_by_party, chosen, by_id),
		"pm_party_id": pm_party_id,
		"pm_person_id": pm_person_id,
		"cohabitation": cohabitation,
		"minority": total <= majority_seats(ns),
		"method": ns.formation_method,
	}


## The premiership goes to the biggest party at the table. Ties broken by id,
## so the outcome never depends on the order the search happened to add them.
static func _largest_coalition_party(ns, chosen: Array) -> String:
	var best_id := ""
	var best_seats := -1
	for pid in chosen:
		var s := _seats(ns, pid)
		if s > best_seats or (s == best_seats and pid < best_id):
			best_seats = s
			best_id = pid
	return best_id


## Public entry point onto _largest_party_id() below, for a reader outside
## this file -- Legislature's system-transition head-of-state derivation
## (docs/transition-model.md) needs "who is the largest party" exactly as
## formation already computes it, not a second implementation.
static func largest_party_id(ns, party_list: Array) -> String:
	return _largest_party_id(ns, party_list)


static func _largest_party_id(ns, party_list: Array, exclude: String = "") -> String:
	var best_id := ""
	var best_seats := -1
	for party in party_list:
		if party.id == exclude:
			continue
		var s := _seats(ns, party.id)
		# Ties broken by id so the result never depends on roster order.
		if s > best_seats or (s == best_seats and party.id < best_id):
			best_seats = s
			best_id = party.id
	return best_id


## France. The President appoints a Prime Minister and there is no investiture
## vote, so a government stands until it is censured. Three outcomes, in order:
## the President's own bloc reaches a majority; it does not but an opposing bloc
## does, which is cohabitation; or nobody does, which is a minority government
## under the President's own party.
static func _form_presidential(ns, party_list: Array, by_id: Dictionary) -> Dictionary:
	var own := _grow(ns, ns.incumbent_party_id, party_list, by_id, ns.censure_barred_party_ids)
	var own_seats := 0
	for pid in own:
		own_seats += _seats(ns, pid)
	if own_seats > majority_seats(ns):
		return _describe(ns, own, by_id, _largest_coalition_party(ns, own), false)

	# Cohabitation is not a grand coalition. The question is whether a bloc
	# organised AGAINST the President commands the chamber, so the President's
	# own party is barred from the rival search rather than merely not anchoring
	# it. Without that bar the greedy search hands a centrist President's party
	# straight back into the opposition's coalition as its nearest available
	# partner, and cohabitation becomes unreachable — France 1986, 1993 and 1997
	# were opposition majorities, not power-sharing deals.
	var rival_anchor := _largest_party_id(ns, party_list, ns.incumbent_party_id)
	if rival_anchor != "":
		var rival_barred: Array = [ns.incumbent_party_id]
		rival_barred.append_array(ns.censure_barred_party_ids)
		var rival := _grow(ns, rival_anchor, party_list, by_id, rival_barred)
		var rival_seats := 0
		for pid in rival:
			rival_seats += _seats(ns, pid)
		if rival_seats > majority_seats(ns):
			return _describe(ns, rival, by_id, _largest_coalition_party(ns, rival), true)

	return _describe(ns, own, by_id, _largest_coalition_party(ns, own), false)


## Germany, Spain, Italy, Belgium, the Netherlands, Austria, Luxembourg and the
## UK. The head of government comes out of the chamber, so formation anchors on
## the largest party whether the rule is an investiture vote, a chancellor
## election, open coalition negotiation, or nothing at all.
static func _form_from_largest(ns, party_list: Array, by_id: Dictionary) -> Dictionary:
	var anchor := _largest_party_id(ns, party_list)
	if anchor == "":
		return _empty_result()
	var chosen := _grow(ns, anchor, party_list, by_id, ns.censure_barred_party_ids)
	return _describe(ns, chosen, by_id, anchor, false)


## Switzerland. The Federal Council seats every party above a fixed share of the
## chamber and does not depend on parliamentary confidence, so there is no
## search and no anchor -- the formula is the government.
static func _form_directorial(ns, party_list: Array) -> Dictionary:
	var by_id := {}
	for party in party_list:
		by_id[party.id] = party

	var chosen: Array = []
	for party in party_list:
		if ns.assembly_seats <= 0:
			continue
		var share := float(_seats(ns, party.id)) / float(ns.assembly_seats)
		if share >= GK.DIRECTORIAL_MIN_SEAT_SHARE:
			chosen.append(party.id)
	chosen.sort()

	var pm := _largest_party_id(ns, party_list)
	return _describe(ns, chosen, by_id, pm, false)


## How closely a party's own position sits to the government's agreed one, in
## (0, 1] -- a Gaussian on distance, the same falloff shape
## election_constants.AFFINITY_SIGMA gives bloc-to-slot affinity. Meaningful
## for any party, not only a coalition member: src/sim/cabinet.gd reads this
## for exactly the parties coalition_bonus() would score, but asks a different
## question of the same number -- how loyal a portfolio-holder is, rather than
## how much its vote is worth.
static func cohesion(ns, party) -> float:
	var pos: Dictionary = K.SLOT_POSITION.get(party.ideology_slot, NEUTRAL_POSITION)
	var dist := _distance(ns.coalition_position, pos)
	return exp(-pow(dist / GK.COALITION_SIGMA, 2.0))


## How much a party's membership of the government adds to its support for a
## government bill, in [0, COALITION_BONUS_MAX]. Replaces the flat
## GOVERNMENT_BONUS legislature.gd gave the single incumbent party: the bonus is
## now earned, falling off with the party's distance from the agreed position
## and scaled by how reliably it delivers its seats.
##
## Zero for any party outside the coalition -- opposition gets no bonus, exactly
## as before.
##
## Since V1.1b the discipline factor is the LIVE one, not the authored one: a
## coalition whose members have stopped listening to their whips delivers less on
## the government's own bills. See docs/discipline-model.md.
static func coalition_bonus(ns, party) -> float:
	if not ns.coalition_party_ids.has(party.id):
		return 0.0
	return GK.COALITION_BONUS_MAX * cohesion(ns, party) * Discipline.of(ns, party)


## How much a party wants this government gone, in [-1, +1]. The same Gaussian
## on distance from the agreed position that coalition_bonus() uses, inverted:
## a party sitting on the line scores -1 and a party far from it scores +1. No
## new equation and no new constant.
##
## A party inside the government subtracts its live `discipline`, so a
## disciplined partner does not vote down the government it signed up to and an
## ill-disciplined one that has drifted might. `forced` adds
## FORCE_HOSTILITY_BONUS -- that term is the entire risk in Article 49.3.
##
## V1.1b adds the DISAFFECTION term, and it is the only term here that can turn a
## partner *against* a government it agrees with: distance asks whether a party
## likes the policy, disaffection asks whether its members want to be standing
## next to this government at the next election. It is gated on (1 - discipline),
## so it is discipline erosion -- not unpopularity on its own -- that costs the
## player their coalition. Exactly zero for a government at or above neutral
## approval, which is why nothing in the V1.1a balance moves. See
## docs/discipline-model.md for why the model could not reach censure without it.
##
## `whipped = false` reads the same party with no leadership on its shoulder:
## the discipline subtraction goes, and disaffection runs at full strength
## instead of being damped by discipline. The gap between the two readings is
## exactly the strain the rebellion split measures.
static func hostility(ns, party, forced := false, whipped := true) -> float:
	var h: float = 1.0 - 2.0 * cohesion(ns, party)
	if ns.coalition_party_ids.has(party.id):
		var d: float = Discipline.of(ns, party) if whipped else 0.0
		h -= d
		h += DK.DISAFFECTION * Discipline.unpopularity(ns) * (1.0 - d)
	if forced:
		h += GK.FORCE_HOSTILITY_BONUS
	return clampf(h, -1.0, 1.0)


## How a hostility score reads as a vote, against the same ABSTAIN_BAND
## legislature.gd uses for bills -- a party near indifferent neither saves the
## government nor sinks it.
static func censure_vote(h: float) -> String:
	if h > LK.ABSTAIN_BAND:
		return "for"
	if h < -LK.ABSTAIN_BAND:
		return "against"
	return "abstain"


## Resolve a censure motion against the sitting government.
##
## Since V1.1b a party is not one bloc. Its line is `hostility()` and its members
## unwhipped are `hostility(whipped = false)`; where those disagree, a share of
## the party's seats set by discipline.gd votes the second reading. `party_votes`
## still names the party's line -- the tallies are what actually went through the
## division lobbies.
##
## Does not mutate state; fall() below does that after reading the result. No
## rand() anywhere, the same discipline as every other module in src/sim/.
static func resolve_censure(ns, party_list: Array, forced := false) -> Dictionary:
	var for_seats := 0
	var against_seats := 0
	var abstain_seats := 0
	var votes := {}
	var rebels_by_party := {}
	var defectors: Array = []

	for party in party_list:
		var seats := _seats(ns, party.id)
		if seats <= 0:
			continue

		var h := hostility(ns, party, forced)
		var h_own := hostility(ns, party, forced, false)
		var line := censure_vote(h)
		var own := censure_vote(h_own)

		var rebels := 0
		if own != line:
			rebels = Discipline.rebel_seats(ns, party, h, h_own)
		if rebels > 0:
			rebels_by_party[party.id] = rebels

		match line:
			"for": for_seats += seats - rebels
			"against": against_seats += seats - rebels
			_: abstain_seats += seats - rebels
		match own:
			"for": for_seats += rebels
			"against": against_seats += rebels
			_: abstain_seats += rebels

		votes[party.id] = line
		# A partner whose LINE is to bring the government down is no longer in
		# it. This is the mechanical cost of a censure the player survives.
		# Rebels inside a partner whose line held are not a defection: the party
		# did not break the agreement, some of its members did.
		if line == "for" and ns.coalition_party_ids.has(party.id):
			defectors.append(party.id)

	var threshold := censure_seats(ns)
	var carried: bool
	match ns.censure_rule:
		"none":
			carried = false
		"simple_present":
			# A simple majority of those actually voting; abstentions do not count.
			carried = for_seats > against_seats
		_:
			# absolute_members and constructive_absolute both measure against the
			# chamber's whole membership, so abstentions and absences count as
			# against. France's 289 of 577 is exactly this.
			carried = for_seats >= threshold

	return {
		"carried": carried,
		"forced": forced,
		"rule": ns.censure_rule,
		"for_seats": for_seats,
		"against_seats": against_seats,
		"abstain_seats": abstain_seats,
		"threshold": threshold,
		"seats_total": ns.assembly_seats,
		"party_votes": votes,
		"party_rebels": rebels_by_party,
		"defectors": defectors,
		# The censured premier, as an id rather than the frozen name string this
		# used to carry. A historical record keyed by id stays resolvable; a name
		# copied into a save was a label nothing could ever re-read.
		"pm_person_id": ns.pm_person_id,
		"pm_party_id": ns.pm_party_id,
	}


## Bring the government down. Parties that voted for censure are barred from the
## replacement -- they have just demonstrated they will not support it -- and the
## bar lasts until the next legislative election, which is a new assembly and a
## clean slate.
##
## The player keeps their office where the executive is elected separately: a
## censured French government costs the President their Prime Minister, not the
## presidency. Where the head of government IS the player, a carried censure ends
## the run.
static func fall(ns, party_list: Array, result: Dictionary) -> void:
	ns.governments_fallen += 1

	for pid in result["defectors"]:
		if not ns.censure_barred_party_ids.has(pid):
			ns.censure_barred_party_ids.append(pid)

	penalise_blocs(ns, GK.FALLEN_BLOC_PENALTY)

	if ns.has_executive:
		form(ns, party_list)
	else:
		ns.in_government = false


## Shift every bloc's approval target by `amount`, through the bloc_offset
## accumulator opinion.gd already reads. Added to the *target*, not to approval
## directly, so INERTIA_RATE and every bound in docs/opinion-model.md still
## apply -- a political event cannot make approval jump in one month any more
## than a law can.
static func penalise_blocs(ns, amount: float) -> void:
	for bloc in OpinionK.BLOC_KEYS:
		ns.bloc_offset[bloc] = clampf(
			float(ns.bloc_offset.get(bloc, 0.0)) + amount,
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX
		)


## True when the government may force a bill through without a vote. Article 49.3
## belongs to the French constitution, so it is gated on the formation method
## rather than on the nation id -- docs/engine-decision.md Rule 1.
static func can_force(ns) -> bool:
	return ns.formation_method == "presidential_appointment" and ns.force_cooldown_months <= 0
