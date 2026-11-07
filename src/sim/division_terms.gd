extends RefCounted

## V5.3 b (docs/design/v5.3-ab.md 4.4, band B4): what a division reads besides a party's
## position. Beside legislature.gd because that file is at the size ratchet's ceiling; the
## seat tally and the majority rule moved here with the terms, unchanged.
##
## THE SIZE TERM. Only the change from a law's reference size counts, so a law with no
## magnitude, or at its reference, is the same division byte for byte. A bill ten times as
## big moves a party further the way it already leans, and charges a party that weighs the
## deficit for the cost beyond the reference. Lines are discrete, so a party moves whole:
## what flips is a partner the whip carried, or a party near the abstain band.
##
## THE PEEL (the parent's ruling, since lines alone left over half of the laws dividing alike
## at ten times). A bigger bill is harder to whip: seats on a yes line go to abstain, by the
## tenfolds above the reference, by how loose the party is. Seats, not the line, so the party
## still reads yes and a law's size still has no road to a whole party's flip here. It is not
## a rebellion: `party_rebels` is what discipline is charged for, and sitting out a bigger
## bill breaks no line. At or below the reference nothing peels, byte for byte.
##
## THE PLEDGE (the parent's ruling). A person's vote and their faction's, on one bill: SEATS,
## read from a `pledge` row in ns.commitments, not the party's line, because a line is yes,
## no or abstain and one backbencher must not flip a whole party. resolve_vote reads it, so
## every caller and the forecast see it with no new parameter. No row, the same division.
## Pure: the vote judges a pledge through judge_pledges(), at the real division alone.

const K = preload("res://src/sim/election_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const President = preload("res://src/sim/president.gd")


## The size term on a party whose spatial view of the bill is `lean`. A smaller bill pulls
## toward zero and never past it: a party that likes forty lycees does not hate twenty.
static func of(lean: float, party, law) -> float:
	if law.magnitude.is_empty():
		return 0.0
	var ratio := LawMagnitude.ratio(law)
	var shift := LK.SIZE_SLOPE * log(ratio) / log(10.0)
	if shift < 0.0:
		shift = maxf(shift, -absf(lean))
	var economic := float(K.SLOT_POSITION[party.ideology_slot]["economic"])
	return signf(lean) * shift - LK.DEFICIT_WEIGHT * maxf(0.0, economic) * LawMagnitude.net_cost_pct_gdp(law) * (1.0 - 1.0 / ratio)


## The seats pledged to this bill from this party: each person brings party seats x their
## standing x PLEDGE_SEAT_SHARE, at least their own seat, the party's seats at most. A person
## who has left the party they pledged for brings nothing.
static func pledged_seats(ns, party, law) -> int:
	if ns.commitments.is_empty():
		return 0
	var seats := int(ns.seats_by_party.get(party.id, 0))
	var pledged := 0
	for row in President.pledges_on(ns, String(law.id)):
		if String(row["party_id"]) == String(party.id) and _delivers(ns, row):
			pledged += maxi(1, roundi(float(seats) * float(ns.person_standing.get(String(row["person_id"]), 0.0)) * LK.PLEDGE_SEAT_SHARE))
	return mini(pledged, seats)


## The share of a whipped yes line that peels on this bill. Clamped because a row's ratio is
## data, with no ceiling of its own: a grade stops at ten times, the row it grades does not.
static func peel_share(ns, party, law) -> float:
	var ratio := LawMagnitude.ratio(law)
	if ratio <= 1.0:
		return 0.0
	return minf(1.0, LK.PEEL_PER_TENFOLD * log(ratio) / log(10.0) * (1.0 - Discipline.of(ns, party)))


## [yes, no, abstain] from one party: the line's seats, the rebels', then what was pledged,
## from the party's no first, then its abstentions, then what peels off a yes line.
##
## A pledged seat is bound once. The pledge is spent first, and nothing has peeled yet, so it
## cannot draw a peeled seat back. What is left of it sits on seats already on the yes line
## and holds them: they leave the base the peel reads, so a pledged seat never peels. So a
## pledge on a yes line, worth nothing at the reference, is worth the seats it holds above it.
static func seats_of(line: String, rebel_line: String, seats: int, rebels: int, pledged: int, peel: float) -> Array:
	var tally := {"yes": 0, "no": 0, "abstain": 0}
	tally[line] += seats - rebels
	tally[rebel_line] += rebels
	var from_no := mini(pledged, int(tally["no"]))
	var from_abstain := mini(pledged - from_no, int(tally["abstain"]))
	var peeled := 0
	if line == "yes":
		peeled = roundi(float(seats - rebels - mini(pledged - from_no - from_abstain, seats - rebels)) * peel)
	return [int(tally["yes"]) + from_no + from_abstain - peeled, int(tally["no"]) - from_no, int(tally["abstain"]) - from_abstain + peeled]


## The real division's verdict on each pledge to this bill: off the live register and into
## the judged one, kept 12 months, which is the mark step 6's deal reads through
## President.pledge_verdict(). Kept if it delivered; broken if the person left the party or
## it holds no seat. Nothing is charged here: the deal prices its own broken word.
static func judge_pledges(ns, law, now: int) -> void:
	for row in President.pledges_on(ns, String(law.id)):
		var kept := _delivers(ns, row) and int(ns.seats_by_party.get(String(row["party_id"]), 0)) > 0
		President.withdraw_commitment(ns, "pledge", String(row["person_id"]), String(row["object"]))
		President.record_judged(ns, row, "kept" if kept else "broken", now)


static func _delivers(ns, row: Dictionary) -> bool:
	return String(ns.person_party_override.get(String(row["person_id"]), row["party_id"])) == String(row["party_id"])


## Whether the yes and no seats carry the law, by its majority. `referendum` is route B.
static func passed(ns, law, yes_seats: int, no_seats: int, referendum: bool) -> bool:
	var seats_total: int = ns.assembly_seats
	var passed_: bool
	match law.majority:
		"simple":
			passed_ = yes_seats > no_seats
		"absolute":
			passed_ = float(yes_seats) > LK.ABSOLUTE_MAJORITY_FRACTION * float(seats_total)
		"two_thirds":
			passed_ = float(yes_seats) >= LK.TWO_THIRDS_MAJORITY_FRACTION * float(seats_total)
		"amendment":
			# Reads the PROPOSING nation's own threshold, not a fixed fraction --
			# the whole point of amendment_rule being per-nation data. Every rule has
			# had a fraction since V1.7c gave referendum_required one; the check
			# stays because an unrecognised rule is still a content bug rather than a
			# runtime state a played game can produce.
			if not LK.AMENDMENT_RULE_FRACTIONS.has(ns.amendment_rule):
				push_error("legislature: amendment_rule '%s' has no seat fraction" % ns.amendment_rule)
				passed_ = false
			elif referendum:
				# Route B. The referendum replaces the SUPERMAJORITY, not the
				# division -- Art. 89 (FRA), Art. 138 (ITA), Art. 114 (LUX) and
				# Art. 195 (CHE) all put an ordinary chamber majority first. So
				# "passed" here means "carried in the chamber and now goes to the
				# country", and propose() is what turns that into a pending vote.
				#
				# `simple` and not `absolute`, and the probe is what settled it. Art.
				# 89's first stage is the ORDINARY legislative procedure, which is a
				# majority of votes CAST; the absolute reading counts abstentions
				# against and put route B at 270 of the 289 seats it needed in every
				# one of 168 months, so the verb was unreachable in a played run --
				# V1.3f's error, caught by tools/referendum_probe.gd's table R6 rather
				# than shipped. Luxembourg (Art. 114) and Switzerland (Art. 195) read
				# the same way; ITALY IS THE OUTLIER, whose Art. 138 second vote is
				# explicitly absolute, and that divergence is recorded in
				# docs/referendum-model.md the way docs/electoral-systems.md records a
				# per-method reduction rather than being modelled per nation.
				passed_ = yes_seats > no_seats
			else:
				# A rule at the absolute fraction is "more than half", like the
				# absolute arm above; the higher ones are "at least" bars (V5.0d:
				# >= let a GBR amendment carry at exactly 325 of 650).
				var bar: float = LK.AMENDMENT_RULE_FRACTIONS[ns.amendment_rule] * float(seats_total)
				passed_ = float(yes_seats) > bar if LK.AMENDMENT_RULE_FRACTIONS[ns.amendment_rule] <= LK.ABSOLUTE_MAJORITY_FRACTION else float(yes_seats) >= bar
		_:
			push_error("legislature: unknown majority type '%s'" % law.majority)
			passed_ = false

	return passed_
