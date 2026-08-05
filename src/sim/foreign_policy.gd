extends RefCounted

## The interest model: why a nation the player does not govern answers one way
## rather than another. Built at V1.3e, the fifth session of the V1.3 block.
##
## The model, and the justification for every constant, is
## docs/foreign-policy-model.md. This file is the rules;
## foreign_policy_constants.gd is the numbers.
##
## This module replaces FOUR declared stopgaps, one from each session before it:
##
##   V1.3a  the target does not REACT      -> third_party_effects()
##   V1.3b  the target does not DECIDE     -> would_accept_agreement()
##   V1.3c  it answers by a fixed rule     -> retaliation_fraction()
##   V1.3d  the council votes its priors   -> appraise()
##
## Each was named in advance rather than approximated, and each is pinned by a
## test that mutates the thing the stopgap ignores and asserts the answer does not
## move. All four of those tests had to FAIL before this file was written; see
## docs/foreign-policy-model.md for the assertions they carried.
##
## > [!important] Interest is MATERIAL. Ideology is one weak term.
## > tools/bloc_probe.gd table (d) prints the eight non-player members'
## > coalition_position and they are clustered -- economic spans -0.54..+0.33,
## > social -0.50..+0.63. An interest function resting on that alone is
## > docs/trade-model.md's GRAVITY_EXPONENT = 1.0 finding in a new place: nine
## > vectors that are arithmetically one vector. So the spine of every function
## > here is the directed trade weight, which spans 0.007 to 0.421 with 13.1x
## > asymmetries, plus the pair's own history, plus each nation's own books.
##
## Stateless, and takes no loader -- the same property src/sim/trade.gd has and
## for the same reasons. There is no ForeignPolicy.tick_month(), nothing on
## NationState that this module owns, and no new field on GameState, so
## SAVE_VERSION does not move. Every answer is derived at read time from live
## state, which is also what lets the budget projection run it forward on a copy
## and get the real answer.
##
## No rand() anywhere, the same discipline diplomacy.gd, economy.gd and opinion.gd
## hold to.
##
## Preloads Trade and nothing else in src/sim/. That is a constraint rather than a
## preference: trade.gd preloads coercion.gd, so a coercion.gd that preloaded THIS
## file would close a cycle GDScript refuses outright. It is why the retaliation
## DECISION lives in diplomacy.gd's _tick_retaliation() -- which already owned the
## loop -- while coercion.gd keeps only the terms it builds. The split is the
## honest one anyway: Coercion says what a measure does, Diplomacy decides to
## impose one, and this file says why.

const RK = preload("res://src/core/relations.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const K = preload("res://src/sim/foreign_policy_constants.gd")
const Trade = preload("res://src/sim/trade.gd")

## The largest distance between two points in the two-axis ideology space, used to
## normalise alignment onto [0, 1]. sqrt(2^2 + 2^2) over [-1, +1] on both axes.
const MAX_IDEOLOGY_DISTANCE := 2.8284271247

## Why a partner refused an agreement, and why a member voted as it did.
##
## Keys, not sentences: src/sim/ does not know the UI exists, and a test asserting
## a key survives a session that rewords the tooltip. The panels own the wording,
## the same split data/*.json and the panels already have for a law's summary.
const REFUSAL_LOW_STAKE := "low_stake"
const REFUSAL_POOR_RELATIONS := "poor_relations"
const REFUSAL_THIN_TERMS := "thin_terms"
const REFUSAL_KEYS := [REFUSAL_LOW_STAKE, REFUSAL_POOR_RELATIONS, REFUSAL_THIN_TERMS]

const VOTE_REASON_DRAWS_ON_IT := "draws_on_it"
const VOTE_REASON_ALREADY_IN_BREACH := "already_in_breach"
const VOTE_REASON_WOULD_PAY := "would_pay"
const VOTE_REASON_TRADES_OUTSIDE := "trades_outside"
const VOTE_REASON_POLITICS := "politics"
const VOTE_REASON_KEYS := [
	VOTE_REASON_DRAWS_ON_IT,
	VOTE_REASON_ALREADY_IN_BREACH,
	VOTE_REASON_WOULD_PAY,
	VOTE_REASON_TRADES_OUTSIDE,
	VOTE_REASON_POLITICS,
]


# --- Stake and amity: the two quantities everything else is built from ------------------

## How much B weighs in A's foreign policy, normalised over A's nine so the vector
## sums to 1. Directed: stake(LUX -> DEU) and stake(DEU -> LUX) are different
## numbers, which is the whole reason V1.3b's directed weight exists.
##
## Normalised deliberately, and it is what stops the model reading GBR as a nation
## that cares about nobody. Britain is in no EU pair, borders nothing in the
## roster and rests at 45 with all nine, so every ABSOLUTE term it has sits at the
## floor -- and an unnormalised interest function would hand it a foreign policy
## of pure indifference, which is docs/trade-model.md's measured-at-0.000 finding
## repeated. Normalised, the question becomes WHO MATTERS TO BRITAIN rather than
## HOW MUCH BRITAIN CARES, and that has an answer for every nation.
##
## Every threshold in this model is therefore expressed against
## foreign_policy_constants.EVEN_SHARE (1/9) rather than against an absolute.
static func stake(state, a_id: String, b_id: String) -> float:
	var vector: Dictionary = stake_vector(state, a_id)
	return float(vector.get(b_id, 0.0))


## One nation's whole stake vector, {partner_id: share}, summing to 1.
##
## Computed together rather than per pair, for the reason Trade.weight_table()
## gives: the normalisation reads all nine, so resolving one pair at a time inside
## a loop that is also moving relations would normalise some partners against this
## month's state and some against last month's.
static func stake_vector(state, a_id: String) -> Dictionary:
	var a = state.nations.get(a_id)
	if a == null:
		return {}

	var trade: Dictionary = Trade.weights(state, a_id)
	var raw: Dictionary = {}
	var total: float = 0.0

	for b_id in state.nations.keys():
		if b_id == a_id:
			continue
		var b = state.nations[b_id]

		# Economic exposure. Already carries partner size, EU co-membership, a
		# shared border and the pair's relations LEVEL, all measured at V1.3b --
		# which is exactly why the history term below reads displacement rather
		# than level. Writing the same fact twice is the redundancy
		# docs/coercion-model.md records the coercion probe cutting.
		var dependence: float = float(trade.get(b_id, 0.0)) / K.EVEN_SHARE

		# History: that somebody ACTED on this pair, whichever direction they went.
		# Zero for all forty-five pairs at new-game, by construction, and growing as
		# the game is played -- so a fresh game's interests are purely material and
		# a played one's carry what the player did.
		var displacement: float = absf(_score(state, a_id, b_id) - _resting(a, b))
		var history: float = minf(1.0, displacement / K.STAKE_HISTORY_SPAN)

		raw[b_id] = (
			K.STAKE_DEPENDENCE_WEIGHT * dependence
			+ K.STAKE_HISTORY_WEIGHT * history
			+ K.STAKE_IDEOLOGY_WEIGHT * _alignment(a, b)
		)
		total += float(raw[b_id])

	if total <= 0.0:
		return raw
	var out: Dictionary = {}
	for b_id in raw.keys():
		out[b_id] = float(raw[b_id]) / total
	return out


## How warm A is toward B, signed, roughly [-1, +1].
##
## Distinct from stake() and not a normalisation of it: stake is how much A cares,
## amity is whether that caring is friendly. A pair can be high-stake and hostile,
## which is precisely the interesting case and the one a single number could not
## express.
##
## Anchored on the PAIR'S OWN RESTING VALUE, not on a global neutral, and the
## probe forced that correction before any constant shipped.
##
## > [!warning] A global neutral double-counts structure and reads as sentiment
## > Anchored at the midpoint of the measured resting tiers (56.5), every GBR pair
## > sat at -0.575 forever -- because Britain has no EU tie and no land border in
## > this roster, so all nine of its pairs rest at the floor of 45. The model was
## > then saying BRITAIN HATES EVERYONE when the data says BRITAIN IS STRUCTURALLY
## > UNATTACHED, and the measured consequence was total: France signed 9 agreements
## > of 9, Germany 9 of 9, and Britain **0 of 9**, with every score negative and no
## > amount of play able to move it. docs/trade-model.md's own GBR trigger, fired a
## > fourth time, in a new place.
## >
## > It was also a double-count. EU co-membership and the shared border are already
## > inside the trade weight (V1.3b measured both) and inside stake through it.
## > Reading them a third time through a resting-derived relations level is the
## > "two numbers for one intensity" redundancy docs/coercion-model.md records the
## > coercion probe cutting between severity and an authored tariff rate.
##
## So: structure lives in the trade weight, sentiment lives in DISPLACEMENT from
## rest. Every pair reads exactly 0.0 at new-game and moves only because somebody
## acted -- the same property stake's history term has, from the same argument,
## which leaves this model with ONE notion of sentiment rather than two.
##
## What this costs, stated rather than discovered: at new-game an agreement's
## difficulty is carried entirely by how much of the target's trade runs through
## the proposer. For Britain that is still hard -- Germany's stake in Britain is
## 0.68x an even share -- but it is hard because NOBODY DEPENDS ON BRITAIN rather
## than because Britain is disliked, which is the same statement
## docs/coercion-model.md already makes about its leverage.
static func amity(state, a_id: String, b_id: String) -> float:
	var a = state.nations.get(a_id)
	var b = state.nations.get(b_id)
	if a == null or b == null:
		return 0.0
	var level: float = (_score(state, a_id, b_id) - _resting(a, b)) / K.AMITY_SPAN
	# _alignment() is [0, 1]; re-centred so two governments at opposite ends of the
	# ideology space read as a negative contribution rather than merely a small one.
	var ideology: float = K.AMITY_IDEOLOGY_WEIGHT * (2.0 * _alignment(a, b) - 1.0)
	return clampf(level + ideology, -1.0, 1.0)


# --- V1.3b's stopgap: whether a partner signs -------------------------------------------

## Whether `target_id` would sign the agreement `actor_id` is proposing.
##
## Replaces V1.3b's declared stopgap, which was `score(a, b) >= 52.0` and nothing
## else -- the target's economy, its alternatives, and the terms on the table were
## all unconsulted. tests/test_trade.gd asserted exactly that by mutation, and
## that assertion had to fail before this was written.
##
## Three terms, each written to read ZERO at neutral, which is what makes
## ACCEPT_MIN interpretable on its own rather than only against the other three:
##
##   stake  - is this partner worth more than a ninth of my attention?
##   amity  - do I trust them, at AMITY_NEUTRAL?
##   deal   - are the terms better than a multiplier of exactly 1.0?
##
## The deal term is the one V1.3b could not have: a generous agreement is now
## genuinely easier to sell than a thin one, so an author moving weight_multiplier
## moves how hard the content is to land rather than only what it pays.
static func accept_score(state, actor_id: String, target_id: String, terms: Dictionary) -> float:
	var multiplier: float = float(terms.get("weight_multiplier", 1.0))
	return (
		K.ACCEPT_STAKE_WEIGHT * (stake(state, target_id, actor_id) / K.EVEN_SHARE - 1.0)
		+ K.ACCEPT_AMITY_WEIGHT * amity(state, target_id, actor_id)
		+ K.ACCEPT_DEAL_WEIGHT * (multiplier - 1.0)
	)


static func would_accept_agreement(state, actor_id: String, target_id: String, terms: Dictionary) -> bool:
	return accept_score(state, actor_id, target_id, terms) >= K.ACCEPT_MIN


## Which of the three terms is why a partner refused, as a KEY rather than a
## sentence. One of REFUSAL_KEYS.
##
## A reason at all, because V1.3b shipped `refused_by_partner` and NOTHING in
## src/ui/ ever read it -- so a partner declining a treaty was, until this session,
## completely silent to the player. An interest model whose answers cannot be read
## is the decorative-effect failure docs/diplomacy-model.md records for a two-bloc
## offset, at the scale of a whole session.
##
## A key rather than prose because src/sim/ does not know the UI exists
## (engine-decision.md rule 2), and because a test can assert a key without
## matching on wording that a later session will reword. src/ui/nation_panel.gd
## owns the sentence.
##
## Names the WEAKEST of the three terms rather than the total: the total is the
## thing the player cannot act on, the weakest term is the thing they can.
static func refusal_reason(state, actor_id: String, target_id: String, terms: Dictionary) -> String:
	var stake_term: float = K.ACCEPT_STAKE_WEIGHT * (stake(state, target_id, actor_id) / K.EVEN_SHARE - 1.0)
	var amity_term: float = K.ACCEPT_AMITY_WEIGHT * amity(state, target_id, actor_id)
	var deal_term: float = K.ACCEPT_DEAL_WEIGHT * (float(terms.get("weight_multiplier", 1.0)) - 1.0)

	if stake_term <= amity_term and stake_term <= deal_term:
		return REFUSAL_LOW_STAKE
	if amity_term <= deal_term:
		return REFUSAL_POOR_RELATIONS
	return REFUSAL_THIN_TERMS


# --- V1.3c's stopgap: how hard a target answers -----------------------------------------

## The fraction of an imposed measure that `target_id` answers with, in
## [0, coercion_constants.RETALIATION_FRACTION].
##
## Replaces V1.3c's declared stopgap, which mirrored every measure back at that
## fixed fraction after a fixed delay while weighing nothing. RETALIATION_FRACTION
## survives as the CEILING rather than the answer.
##
##     leverage = w(imposer -> target) / EVEN_SHARE    how much my answer would hurt
##     exposure = w(target -> imposer) / EVEN_SHARE    how much it would cost me
##     fraction = clamp(leverage / (1 + damping * exposure) * grievance, 0, ceiling)
##
## Both weights are read BEFORE measures, for the reason docs/coercion-model.md
## gives at length: you hurt in proportion to the trade you destroy, not the trade
## that survives, and reading the post-measure vector is what made high severity
## strictly dominated at V1.3c.
##
## What falls out of it, rather than being authored: a small nation heavily
## dependent on a large one answers barely at all, because answering costs it more
## than it collects. France tariffing Luxembourg is answered at the floor;
## Luxembourg tariffing France is answered at the ceiling. That asymmetry is the
## thing V1.3b's directed table made SAYABLE and no session until this one could
## act on.
static func retaliation_fraction(state, imposer_id: String, target_id: String, ceiling: float) -> float:
	var leverage: float = float(
		Trade.weights_before_measures(state, imposer_id).get(target_id, 0.0)
	) / K.EVEN_SHARE
	var exposure: float = float(
		Trade.weights_before_measures(state, target_id).get(imposer_id, 0.0)
	) / K.EVEN_SHARE

	# A nation that already resents you answers harder than its books alone would
	# justify. The one place in this file where grievance is allowed to beat
	# arithmetic, and it is bounded: amity is clamped to [-1, +1], so this can at
	# most add RETALIATION_AMITY_GAIN.
	var grievance: float = 1.0 + K.RETALIATION_AMITY_GAIN * maxf(
		0.0, -amity(state, target_id, imposer_id)
	)

	var raw: float = leverage / (1.0 + K.RETALIATION_EXPOSURE_DAMPING * exposure) * grievance
	return clampf(raw, 0.0, ceiling)


# --- V1.3a's stopgap: what a third party makes of it -------------------------------------

## Every relations adjustment an act by `actor_id` on `target_id` causes OUTSIDE
## that pair, as a list of {a, b, delta}. Empty when nobody has a stake worth the
## floor.
##
## Replaces V1.3a's declared stopgap, which was that no third pair moves at all.
## tests/test_diplomacy.gd asserted that acting on Germany left DEU|ITA exactly at
## its resting value, and that assertion had to fail before this was written.
##
## One signed rule, and both halves of it come from the same number: an act by A
## on B is an act on everyone with a stake in B.
##
##   X's pair with the ACTOR moves WITH the sign of the act, scaled by stake(X->B)
##   X's pair with the TARGET moves AGAINST it, scaled by the same
##
## So sanctioning Germany costs France standing with everyone who trades with
## Germany, and wins Germany sympathy from exactly those nations. A sanctioned
## nation acquiring sympathisers is the most legible thing an interest model can
## produce, and U5c's relations map layer is already the readout for it.
##
## Returns the adjustments rather than applying them, deliberately. Applying one
## moves relations, which moves the stake the next one is scaled by -- so the
## answer would depend on Dictionary iteration order, which is the ordering bug
## docs/trade-model.md records the trade probe catching in the impulse. The caller
## applies the whole list after it is built.
static func third_party_effects(state, actor_id: String, target_id: String, delta: float) -> Array:
	var out: Array = []
	if is_zero_approx(delta):
		return out

	var floor_share: float = K.EVEN_SHARE * K.THIRD_PARTY_MIN_STAKE_SHARE

	# Sorted, so the list is reproducible rather than dependent on Dictionary
	# ordering -- the same reason Relations.all_pairs() and Bloc._members() sort.
	var others: Array = state.nations.keys()
	others.sort()

	for x_id in others:
		if x_id == actor_id or x_id == target_id:
			continue
		var care: float = stake(state, x_id, target_id)
		if care < floor_share:
			continue
		out.append({
			"a": x_id,
			"b": actor_id,
			"delta": K.THIRD_PARTY_JUDGEMENT * delta * care / K.EVEN_SHARE,
		})
		out.append({
			"a": x_id,
			"b": target_id,
			"delta": -K.THIRD_PARTY_SOLIDARITY * delta * care / K.EVEN_SHARE,
		})
	return out


# --- V1.3d's stopgap: how a council member votes ----------------------------------------

## How much a member's government wants a proposal adopted. Positive votes for.
##
## Replaces V1.3d's declared stopgap, which read coalition_position and NOTHING
## else -- so a member's answer to a joint fund it would pay for and one it would
## draw on was identical if the two sat at the same point in ideology space.
## tests/test_bloc.gd asserted that by mutating the member's whole economy, and
## that assertion had to fail before this was written.
##
## `rule_burden` is what this rule would add to THIS member's burden against its
## CURRENT books, computed by src/sim/bloc.gd and passed in. Passed rather than
## computed here for a structural reason, not a stylistic one: bloc.gd preloads
## this file, so this file cannot preload bloc.gd. The dependency runs one way,
## which is engine-decision.md's rule 3, and Bloc keeps sole ownership of the
## breach arithmetic it already used in two places.
##
## The ideology term is retained at a fraction of its former authority rather than
## deleted. A council that voted purely on its books would have no politics in it,
## and two members with identical economies genuinely should be able to disagree.
## What it must not do is DECIDE, which at APPRAISE_IDEOLOGY_WEIGHT against three
## material terms it cannot.
## The four terms, and each is documented at its weight in
## foreign_policy_constants.gd:
##
##   ideology  what a member's government thinks of it, the retained weak term
##   rule      what complying would cost me, ZERO if I already comply
##   transfer  what it would cost my books, SIGNED -- a fund I draw on is a reason
##             to vote for, and the only term whose sign varies across the eight
##   external  the share of MY OWN trade that runs to the nations it would target
##
## Summed here and read term by term by vote_reason(), from one builder, so the
## reason the panel prints cannot disagree with the vote the model cast.
static func appraise(state, ns, proposal, rule_burden: float) -> float:
	var terms := _appraisal_terms(state, ns, proposal, rule_burden)
	return (
		float(terms["ideology"])
		+ float(terms["rule"])
		+ float(terms["transfer"])
		+ float(terms["external"])
	)


## Which term decided a member's vote, as a KEY. One of VOTE_REASON_KEYS.
##
## Same reasoning as refusal_reason() on both counts: the deciding term rather
## than the total, and a key rather than prose because src/ui/bloc_panel.gd owns
## the sentence and a test should not assert on wording.
##
## > [!warning] The balance re-run caught this ordering a cascade of `if`s got wrong
## > The first version tested the terms in a fixed order and returned the first
## > that was non-zero. Every member then voted FOR `common_external_tariff` with
## > the reason "trades outside the bloc" -- naming the only COST term on the
## > proposal, which had lost to the politics by a factor of five. A reason that
## > names a term the vote went against is worse than no reason, because the
## > player reads it as the explanation and it is the refutation.
## >
## > Picked by LARGEST ABSOLUTE CONTRIBUTION instead. That is what "the term that
## > decided it" means, and unlike an ordering it cannot disagree with the
## > arithmetic in appraise() -- the two read the same four numbers.
static func vote_reason(state, ns, proposal, rule_burden: float) -> String:
	var terms := _appraisal_terms(state, ns, proposal, rule_burden)

	var best_key: String = VOTE_REASON_POLITICS
	var best: float = absf(float(terms["ideology"]))
	if absf(float(terms["rule"])) > best:
		best = absf(float(terms["rule"]))
		best_key = VOTE_REASON_ALREADY_IN_BREACH
	if absf(float(terms["transfer"])) > best:
		best = absf(float(terms["transfer"]))
		# The one term whose SIGN varies across the council, so it carries two
		# reasons rather than one: a fund you draw on and a fund you pay for are
		# different sentences about the same number.
		#
		# Read off the CONTRIBUTION TO THE SCORE, not off transfer_pct_gdp, and the
		# two have opposite signs -- a positive contribution is a fund this member
		# draws on. Inverted in the first version, which had every member reported
		# as drawing on the fund they pay into and paying for the one they draw on;
		# caught by looking at the probe's own per-member table.
		best_key = VOTE_REASON_WOULD_PAY if float(terms["transfer"]) < 0.0 else VOTE_REASON_DRAWS_ON_IT
	if absf(float(terms["external"])) > best:
		best = absf(float(terms["external"]))
		best_key = VOTE_REASON_TRADES_OUTSIDE
	return best_key


## The four terms of an appraisal, signed as they enter the sum. One function so
## appraise() and vote_reason() cannot drift apart -- the reason the panel prints
## and the arithmetic the vote used must be the same four numbers.
static func _appraisal_terms(state, ns, proposal, rule_burden: float) -> Dictionary:
	var stress: float = 1.0 + maxf(0.0, ns.deficit_pct_gdp - K.APPRAISE_DEFICIT_PIVOT) / K.APPRAISE_DEFICIT_PIVOT

	var external: float = 0.0
	if not proposal.external_measure.is_empty():
		var weights: Dictionary = Trade.weights(state, ns.id)
		var outside: float = 0.0
		for other_id in weights.keys():
			var other = state.nations.get(other_id)
			if other != null and not other.eu_member:
				outside += float(weights[other_id])
		external = -K.APPRAISE_EXTERNAL_WEIGHT * outside * float(proposal.external_measure.get("severity", 0.0))

	return {
		"ideology": K.APPRAISE_IDEOLOGY_WEIGHT * _ideology_support(ns, proposal),
		"rule": -K.APPRAISE_RULE_WEIGHT * rule_burden,
		"transfer": -K.APPRAISE_TRANSFER_WEIGHT * proposal.transfer_pct_gdp * stress,
		"external": external,
	}


# --- internals ---------------------------------------------------------------------------

## The pair's score, without Diplomacy.score()'s push_error path.
##
## An absent pair falls back to REST_BASE here rather than raising, because this
## module is called from inside probe sweeps and synthetic test fixtures that
## legitimately build partial states. Diplomacy.score() stays the loud one for the
## played game.
static func _score(state, a_id: String, b_id: String) -> float:
	return float(state.relations.get(RK.key(a_id, b_id), DK.REST_BASE))


## Where the pair would rest if nobody acted, read off NationState.
##
## Deliberately NOT a call into Diplomacy.resting(), and the reason is structural:
## diplomacy.gd preloads this file, so this file cannot preload diplomacy.gd
## without closing a cycle GDScript refuses. The two read the same two static
## facts -- eu_member and neighbours, copied onto NationState at new-game the way
## assembly_seats already is -- so they agree by construction rather than by
## maintenance, and tests/test_foreign_policy.gd asserts they agree for all
## forty-five pairs rather than trusting this comment.
static func _resting(a, b) -> float:
	var value: float = DK.REST_BASE
	if a.eu_member and b.eu_member:
		value += DK.EU_CO_MEMBER_BONUS
	if a.neighbours.has(b.id):
		value += DK.SHARED_BORDER_BONUS
	return clampf(value, DK.RELATIONS_MIN, DK.RELATIONS_MAX)


## How close two points in the two-axis ideology space sit, on [0, 1].
##
## LINEAR in distance rather than Gaussian, which is a deliberate departure from
## Bloc.support(), election_constants.AFFINITY_SIGMA and cabinet_constants'
## CABINET_SIGMA, all of which use the Gaussian shape on this same space. The
## reason is the clustering finding this whole model is built around: over
## positions spanning 0.87 and 1.13 a Gaussian is nearly flat, so it contributes a
## near-constant to every pair and separates nothing. Linear at least preserves
## the ordering that is there.
##
## One helper for both callers, because a nation's coalition_position and a
## proposal's position are the same two axes under two field names -- keeping two
## copies is how they drift apart.
static func _position_alignment(p1: Dictionary, p2: Dictionary) -> float:
	var d_econ: float = float(p1.get("economic", 0.0)) - float(p2.get("economic", 0.0))
	var d_social: float = float(p1.get("social", 0.0)) - float(p2.get("social", 0.0))
	var dist: float = sqrt(d_econ * d_econ + d_social * d_social)
	return clampf(1.0 - dist / MAX_IDEOLOGY_DISTANCE, 0.0, 1.0)


static func _alignment(a, b) -> float:
	return _position_alignment(a.coalition_position, b.coalition_position)


## Where Bloc.support()'s whole answer now sits: one term among four.
static func _ideology_support(ns, proposal) -> float:
	return _position_alignment(ns.coalition_position, proposal.position)
