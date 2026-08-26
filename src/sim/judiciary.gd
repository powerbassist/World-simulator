extends RefCounted

## The court: whether a passed bill survives, and the rule-of-law stock that decides.
##
## Built at V1.1e. docs/tiers/v1.md section 1 asks for "courts that can strike down laws,
## a check the player cannot simply outvote", and that bullet ALSO owns section 5's "rule
## of law -- institutional strength gating what the player can get away with", handed
## here at V1.5's decomposition on the argument that two uncontestable gates on player
## action would be one machine claimed twice. So this file is one machine wearing both
## labels rather than two sharing a page.
##
## The model and both constants are docs/judiciary-model.md.
##
## ============================================================================
## A LEAF, LIKE chambers.gd, AND THE TEST READS THIS FILE TO SAY SO
## ============================================================================
## It preloads its own constants and nothing else -- not legislature.gd, not law.gd, not
## unrest.gd. A law's REACH is computed at load and carried on the Law object itself
## (src/core/law.gd), because it is a property of the law and of clamps that do not move;
## the grievance term is read FROM unrest.gd rather than pushed to it, which is
## `deployment_opinion_load`'s and `unrest_opinion_load`'s arrangement a fourth time.
##
## ============================================================================
## THE COURT IS TRANSPARENT, AND THAT IS THE DESIGN
## ============================================================================
## docs/legislature-model.md blurs the VOTE forecast on purpose, and this gate is not
## blurred. A division is a body of people whose minds the player is trying to read; a
## court is a RULE, and a rule the player cannot read is not a check on their power, it
## is a trap. So the doomed bill stays on the law list with the verdict printed beside it
## rather than being filtered out of available(): a lock taken out of view teaches nobody
## that there is a key.
##
## What makes it a decision rather than a filter is that the gate MOVES.
## `judicial_independence` is the fifth effects.society term, signed both ways, so the
## set of laws a president can pass is a function of a stock they can change -- at a
## price paid in the grievance, which is where docs/media-model.md put legitimacy at
## V1.5d and for the same reason.

const JK = preload("res://src/sim/judiciary_constants.gd")


## Copy the review rule and seat the stock. Runs for all ten.
static func init_nation(ns, nation) -> void:
	ns.judicial_review = nation.judicial_review
	ns.judicial_independence = clampf(
		float(nation.institutions.get("rule_of_law_score", 0.0)),
		JK.INDEPENDENCE_MIN, JK.INDEPENDENCE_MAX
	)
	ns.start_judicial_independence = ns.judicial_independence


## Whether this bill is reviewable at all.
##
## TWO EXCLUSIONS, BOTH REAL AND BOTH CITED. A nation whose courts may not review
## primary legislation is `REVIEW_NONE` -- Britain by parliamentary sovereignty, the
## Netherlands by Art. 120 of the Grondwet in terms, Switzerland by Art. 190's
## binding-force clause, which is three doctrines reaching one answer and is recorded in
## docs/judiciary-model.md rather than smoothed over.
##
## And a CONSTITUTIONAL AMENDMENT is never reviewable, because once it passes it becomes
## the standard the court applies. The Conseil constitutionnel has declined jurisdiction
## over revisions since 2003; Germany's eternity clause is the apparent exception and is
## already modelled, as `permits_system_change: false`. It is also what stops this
## function needing a reach for `effects.institutional`, which sets an absolute value and
## so has no magnitude to take a fraction of. The two reasons agree, which is why neither
## is doing the other's work.
static func reviews(ns, law) -> bool:
	if ns.judicial_review != JK.REVIEW_CONSTITUTIONAL:
		return false
	return not law.constitutional


## How much of a law's reach this nation's courts will tolerate, in [0, 1].
##
## INVERSELY PROPORTIONAL to the nation's own rule of law, against the roster's
## measured mean: a court twice as independent tolerates half as much. One dial.
## The linear form this replaced amplified the roster's spread instead of preserving
## it; judiciary_constants.JUDICIAL_TOLERANCE carries that correction, the five-clause
## band, and what the shipped value buys.
##
## The floor guards a nation whose courts have been driven to nothing: dividing by a
## near-zero independence would hand it a tolerance of 1.0, which is the same answer as
## `no review` reached from the opposite direction, so it needs no branch of its own.
static func tolerance(ns) -> float:
	var independence: float = clampf(
		ns.judicial_independence, JK.INDEPENDENCE_MIN, JK.INDEPENDENCE_MAX
	)
	if independence <= 1.0:
		return 1.0
	return clampf(
		JK.JUDICIAL_TOLERANCE * JK.ROSTER_MEAN_RULE_OF_LAW / independence, 0.0, 1.0
	)


## The verdict. Deterministic and readable, for the reason in this file's header.
static func strikes_down(ns, law) -> bool:
	if not reviews(ns, law):
		return false
	return law.reach > tolerance(ns)


## How far this nation's rule of law has moved from where the game found it, in points of
## score. Negative is a captured court.
##
## THE DEVIATION AND NOT THE LEVEL, for start_service_quality's reason: a country whose
## courts have always been weak is not permanently rioting about it, and Italy is not
## angrier than Switzerland on frame one. tests/test_judiciary.gd asserts this reads
## exactly 0.0 for all ten at new game.
static func independence_deviation(ns) -> float:
	return ns.judicial_independence - ns.start_judicial_independence


## What a captured court does to the grievance stock, read by Unrest.unrest_target().
##
## LEGITIMACY IS THE GRIEVANCE, and V1.5d is why: docs/media-model.md sent press
## freedom's legitimacy cost there rather than inventing a quantity, on the argument that
## legitimacy is willingness to accept your rule OUTSIDE the ballot box -- and
## unrest_constants.UNREST_BLOCS is ["workers", "students"], who are exactly who marches
## when a government captures its own courts.
##
## NOT A SECOND PRESS FREEDOM WITH A DIFFERENT LABEL. Press freedom moves `framing_gain`,
## how loudly bad news travels; this moves whether a passed law survives. Different
## landing site, different units, so docs/legislature-model.md's `same act, same landing
## site, same units` criterion is not met and the two are two mechanisms. That check is
## written down rather than assumed, because law.gd already records that the next session
## will reach for a fourth anti-double-count pair BY SYMMETRY and that symmetry is not
## the test.
static func unrest_load(ns) -> float:
	return -independence_deviation(ns) * JK.JUDICIAL_UNREST_BETA
