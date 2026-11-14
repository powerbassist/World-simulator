extends RefCounted

## What Article 49.3 charges, whatever it forces: one function, so an ordinary bill's
## forcing (Legislature._force) and the finance bill's (FinanceBill, docs/design/
## finance-bill.md section 4) cannot drift on the price. The ORDER around it is the
## caller's: an ordinary bill applies first and is charged after; the finance bill is
## charged first and applies only if the censure fails. The cooldown is the caller's
## too: the finance bill neither reads nor writes it (Art. 49.3 al. 3, 2008).

const Government = preload("res://src/sim/government.gd")
const GK = preload("res://src/sim/government_constants.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const DK = preload("res://src/sim/discipline_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")


## Charge the article and resolve the censure motion it opens. Returns the censure, also
## written to ns.last_censure; a carried one has already brought the government down.
static func charge(ns, party_list: Array) -> Dictionary:
	var by_id := {}
	for party in party_list:
		by_id[party.id] = party

	# Bypassing the assembly costs something whether or not the censure motion
	# carries. Without this, a government that can cover the threshold would
	# force every bill it could not win, for free.
	Government.penalise_blocs(ns, GK.FORCE_BLOC_PENALTY)

	# The second price of the article, and the one paid in the chamber rather
	# than in the polls: a government that goes over its own majority's head
	# finds that majority less willing the next time it asks. Applied before the
	# censure motion resolves, because the insult is the reason for the motion.
	Discipline.penalise(ns, ns.coalition_party_ids, DK.FORCE_DISCIPLINE_PENALTY, by_id)

	# Resolved against the government the bill was forced through for, and
	# before any collapse re-forms it, so the vote reads the coalition that
	# actually did the forcing.
	var censure := Government.resolve_censure(ns, party_list, true)
	Discipline.penalise_rebellions(ns, censure["party_rebels"], by_id)
	if censure["carried"]:
		Government.fall(ns, party_list, censure)
		# Cabinet.seat() is called here rather than from inside government.gd
		# itself -- Cabinet depends on Government (cohesion(), penalise_blocs()),
		# so the reverse would be a preload() cycle. See docs/cabinet-model.md.
		Cabinet.seat(ns, party_list)

	ns.last_censure = censure
	return censure
