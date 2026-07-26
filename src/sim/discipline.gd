extends RefCounted

## Party discipline as a live quantity, and the seat-level rebellions it allows.
##
## Until V1.1b `discipline` was a number in data/parties/*.json that never moved
## and did one job: scaling government.gd's coalition bonus. A party voted as one
## bloc, always. This module makes it state -- eroded by an unpopular government
## and by an approaching legislative election, recovering by inertia when both
## ease -- and makes a division resolvable seat by seat rather than party by
## party.
##
## Two rules from the rest of src/sim/ are kept exactly:
##
## No randomness. A rebellion is a pure function of state, so a vote is still
## reproducible from that state alone -- the discipline economy.gd, budget.gd,
## opinion.gd, elections.gd, legislature.gd and government.gd all keep, and what
## Budget.project()'s projection-equals-reality guarantee depends on.
##
## No accumulator. The one stored quantity is discipline itself, bounded to
## [DISCIPLINE_MIN, the authored figure] by construction, and every event effect
## is a step within those bounds that inertia then pulls back. See
## docs/discipline-model.md.

const DK = preload("res://src/sim/discipline_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")


## Seed live discipline from the authored figure. Runs for all ten nations, same
## as Opinion/Elections/Government/Legislature.init_nation -- a second playable
## nation is then a data change, not a change here.
static func init_nation(ns, party_list: Array) -> void:
	ns.party_discipline = {}
	for party in party_list:
		ns.party_discipline[party.id] = party.discipline


## The live figure, falling back to the authored one. The fallback is not
## decoration: government.gd reads this for every nation, and only the player's
## has a reason to have been ticked.
static func of(ns, party) -> float:
	return float(ns.party_discipline.get(party.id, party.discipline))


## The authored figure -- the party at its best, and the ceiling on the target
## below. Read from the roster rather than stored, so editing a party file moves
## the ceiling without touching a save.
static func base_of(party) -> float:
	return float(party.discipline)


## Where a party's discipline is heading, given how the government is doing and
## how close the members are to defending their own seats.
##
## Only ever at or below the authored figure: content is the ceiling and the
## model only takes away. Both terms read state that already exists -- approval
## from opinion.gd, the date from the legislative election schedule -- so this
## adds no quantity of its own.
static func target(state, ns, party) -> float:
	var base := base_of(party)

	# The LEGISLATIVE clock, not the executive's: it is the members' own seats
	# that are on the ballot, and in France those two dates are years apart.
	var months := months_to_legislative(state, ns)
	var proximity: float = clampf(1.0 - float(months) / float(DK.ELECTION_HORIZON_MONTHS), 0.0, 1.0)

	var t := base - DK.APPROVAL_TERM * unpopularity(ns) - DK.ELECTION_TERM * proximity
	return clampf(t, DK.DISCIPLINE_MIN, base)


## How badly the government is doing, in [0, 1]. Zero for any government at or
## above neutral approval, one at the floor of the approval model's own range,
## so it is expressed in the units opinion.gd already reasons in rather than in
## raw percentage points.
##
## Read twice: here, where it pulls discipline down over months, and by
## government.gd's hostility(), where it decides whether a partner would rather
## not be attached to this government at all. Same quantity, two time scales.
static func unpopularity(ns) -> float:
	return clampf(
		(OpinionK.APPROVAL_NEUTRAL - ns.overall_approval_pct) / OpinionK.APPROVAL_SPAN,
		0.0, 1.0
	)


## Months from the current date to the next legislative election. Negative once
## it is overdue, which clamps to full proximity above.
static func months_to_legislative(state, ns) -> int:
	return (ns.next_election_year - int(state.year)) * 12 + (ns.next_election_month - int(state.month))


## Move every party toward its target. Gated on has_budget, the same flag every
## other opinion-reading system uses -- the other nine nations have no approval
## figure for the target to read.
static func tick_month(state, loader) -> void:
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		for party in loader.parties.get(ns.id, []):
			var current := of(ns, party)
			var t := target(state, ns, party)
			ns.party_discipline[party.id] = clampf(
				current + (t - current) * DK.DISCIPLINE_INERTIA,
				DK.DISCIPLINE_MIN, base_of(party)
			)


## Step a set of parties' discipline down (or up, for a positive amount). Clamped
## to the same bounds the tick keeps, so no event can put discipline outside the
## range the model reasons about.
static func penalise(ns, party_ids: Array, amount: float, by_id: Dictionary) -> void:
	for pid in party_ids:
		if not by_id.has(pid):
			continue
		var ceiling := base_of(by_id[pid])
		ns.party_discipline[pid] = clampf(
			float(ns.party_discipline.get(pid, ceiling)) + amount,
			DK.DISCIPLINE_MIN, ceiling
		)


## What a division actually costs the parties that split, scaled by how large
## each rebellion was against REBEL_MAX. Applied by the mutating caller --
## Legislature.propose() and the censure path -- so resolve_vote() and
## resolve_censure() stay pure.
static func penalise_rebellions(ns, party_rebels: Dictionary, by_id: Dictionary) -> void:
	for pid in party_rebels:
		var rebels: int = int(party_rebels[pid])
		if rebels <= 0:
			continue
		var seats: int = int(ns.seats_by_party.get(pid, 0))
		if seats <= 0:
			continue
		var severity: float = clampf(float(rebels) / float(seats) / DK.REBEL_MAX, 0.0, 1.0)
		penalise(ns, [pid], DK.REBELLION_PENALTY * severity, by_id)


## How many of a party's seats vote their own way rather than the party's, on a
## division where the party votes `line` and its members left alone would vote
## `own`.
##
## The strain is the gap between those two -- the whip's pull, and nothing else.
## An opposition party has no gap, because nothing is dragging its members away
## from their own position, so it never rebels. That is the model speaking rather
## than a hole in it; see docs/discipline-model.md.
##
## int(round()) rather than floor, so a party a hair over half a seat's worth of
## strain loses that seat rather than always rounding in the government's favour.
static func rebel_seats(ns, party, line: float, own: float) -> int:
	var seats: int = int(ns.seats_by_party.get(party.id, 0))
	if seats <= 0:
		return 0
	var rebels := int(round(float(seats) * rebel_fraction(ns, party, line, own)))
	return clampi(rebels, 0, seats)


## The share of a party's seats that breaks ranks, in [0, REBEL_MAX]. Zero at
## perfect discipline and zero at zero strain, which between them cover every
## case where a rebellion would be incoherent.
static func rebel_fraction(ns, party, line: float, own: float) -> float:
	var strain: float = absf(line - own) / DK.REBEL_STRAIN_SCALE
	return clampf(DK.REBEL_MAX * (1.0 - of(ns, party)) * strain, 0.0, DK.REBEL_MAX)
