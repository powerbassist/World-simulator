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
const Org = preload("res://src/core/org.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const K = preload("res://src/sim/foreign_policy_constants.gd")
const CK = preload("res://src/sim/coercion_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
## The CONSTANTS only, never src/sim/defence.gd itself. A constants file preloads
## nothing, so this edge is a leaf; preloading the module would make a defence.gd
## that ever needed stake() or amity() a cycle GDScript refuses outright.
const DFK = preload("res://src/sim/defence_constants.gd")

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
## V1.3g's, and the only one that is about the ASKER rather than the relationship:
## an alliance with a nation that cannot fight is a liability wearing a treaty's
## clothes, and it is the one refusal the player fixes with a budget rather than
## with diplomacy.
const REFUSAL_WEAK_PARTNER := "weak_partner"
const REFUSAL_KEYS := [
	REFUSAL_LOW_STAKE, REFUSAL_POOR_RELATIONS, REFUSAL_THIN_TERMS, REFUSAL_WEAK_PARTNER,
]

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

## Why a nation acted on its own initiative. V1.3f, and the same key-not-sentence
## contract the two sets above have.
##
## THREE keys against desire()'s four terms, and the missing two are deliberate.
## Cost and risk are reasons NOT to act, and an act that happened was not stopped
## by them -- so naming one as the reason would be the failure the balance re-run
## caught in vote_reason(), where every member was reported voting for a proposal
## because of the one cost term the politics had beaten by a factor of five. A
## reason that names a term the act went against is worse than no reason.
const ACT_REASON_INTEREST := "interest"
const ACT_REASON_GOODWILL := "goodwill"
const ACT_REASON_GRIEVANCE := "grievance"
const ACT_REASON_KEYS := [ACT_REASON_INTEREST, ACT_REASON_GOODWILL, ACT_REASON_GRIEVANCE]


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
## Every threshold in this model is expressed against even_share() below rather
## than against an absolute.

## The share that is "even" for nation A: EVEN_SHARE_SCALE times the Herfindahl
## of A's own trade-weight vector -- one over A's EFFECTIVE number of partners.
##
## History, because each step was a measured failure. The ten-era constant said
## 1/9 and went stale when the roster grew (V3.3: every stake term priced at a
## third of its meaning). V3.3 derived it as one over the partner COUNT -- and
## V4.11 measured that dilute: seven small neighbours took the count from 28 to 35,
## every big partner's stake read 25 % larger with nothing changed between them,
## and Britain's floor-relations deal with Italy started to pass
## (docs/foreign-policy-model.md, V4.11). The Herfindahl barely moves when a tiny
## partner joins, and it says what "a fair share of MY attention" means for a
## concentrated trader and a diffuse one alike. Read from the TRADE vector, not
## the stake vector, because stake is built on this number.
static func even_share(state, a_id: String) -> float:
	return even_share_of(Trade.weights(state, a_id))


## The same yardstick from a weight vector already in hand -- stake_vector() holds
## one, and recomputing it per partner would be the one-pass rule's violation.
static func even_share_of(weights: Dictionary) -> float:
	var hhi := 0.0
	for b_id in weights.keys():
		hhi += float(weights[b_id]) * float(weights[b_id])
	if hhi <= 0.0:
		return 1.0
	return K.EVEN_SHARE_SCALE * hhi


static func stake(state, a_id: String, b_id: String) -> float:
	var vector: Dictionary = stake_vector(state, a_id)
	return float(vector.get(b_id, 0.0))


## One nation's whole stake vector, {partner_id: share}, summing to 1.
##
## Computed together rather than per pair, for the reason Trade.weight_table()
## gives: the normalisation reads all nine, so resolving one pair at a time inside
## a loop that is also moving relations would normalise some partners against this
## month's state and some against last month's.
static func stake_vector(state, a_id: String, a_weights: Dictionary = {}) -> Dictionary:
	var a = state.nations.get(a_id)
	if a == null:
		return {}

	# A caller already holding A's live weights may pass them (third_party_effects
	# reads the same vector for its own yardstick); empty means build-your-own.
	var trade: Dictionary = a_weights if not a_weights.is_empty() else Trade.weights(state, a_id)
	var even: float = even_share_of(trade)
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
		var dependence: float = float(trade.get(b_id, 0.0)) / even

		# History: that somebody ACTED on this pair, whichever direction they went.
		# Zero for all forty-five pairs at new-game, by construction, and growing as
		# the game is played -- so a fresh game's interests are purely material and
		# a played one's carry what the player did.
		var displacement: float = absf(_score(state, a_id, b_id) - _resting(a, b, Org.shared_bonus(state, a_id, b_id, "relations_bonus")))
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
	var level: float = (_score(state, a_id, b_id) - _resting(a, b, Org.shared_bonus(state, a_id, b_id, "relations_bonus"))) / K.AMITY_SPAN
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
		K.ACCEPT_STAKE_WEIGHT * (stake(state, target_id, actor_id) / even_share(state, target_id) - 1.0)
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
	var stake_term: float = K.ACCEPT_STAKE_WEIGHT * (stake(state, target_id, actor_id) / even_share(state, target_id) - 1.0)
	var amity_term: float = K.ACCEPT_AMITY_WEIGHT * amity(state, target_id, actor_id)
	var deal_term: float = K.ACCEPT_DEAL_WEIGHT * (float(terms.get("weight_multiplier", 1.0)) - 1.0)

	if stake_term <= amity_term and stake_term <= deal_term:
		return REFUSAL_LOW_STAKE
	if amity_term <= deal_term:
		return REFUSAL_POOR_RELATIONS
	return REFUSAL_THIN_TERMS


# --- V1.3g: whether a partner signs a defensive pact -------------------------------------

## The three terms of a pact offer, signed as they enter the sum. One builder so
## would_accept_pact() and pact_refusal_reason() cannot drift apart -- the same
## reason _appraisal_terms() and _desire_parts() exist, and the same failure they
## exist to prevent (V1.3e shipped a vote_reason() naming a term that had lost by a
## factor of five).
##
## Every term reads ZERO at neutral, so PACT_ACCEPT_MIN is interpretable on its own:
## stake at an even ninth, a pair exactly at its resting value, a partner of exactly
## reference capability.
##
##   stake      - is this partner worth more than a ninth of my attention?
##   amity      - do I trust them, anchored on the pair's OWN resting value?
##   capability - can they actually fight, against CAPABILITY_REFERENCE?
##
## Capability is read on the ASKER, not the answerer, and that is the whole point of
## the term: a defensive pact is a promise to spend blood and money on somebody
## else's behalf, so what the answerer wants to know is what it is being offered.
## Expressed as a RATIO against the reference for the reason every threshold in this
## file is expressed against EVEN_SHARE -- an absolutely-anchored term would read
## every small nation as worthless by construction, which is V1.3e's GBR finding and
## has fired five times.
##
## Read through Defence.capability_ratio()? NO -- and deliberately. This file must
## never preload src/sim/defence.gd: defence.gd would then be unable to reach
## stake() or amity() if the pact rule ever moved there, and GDScript refuses the
## cycle outright. The field is read bare and divided here. See _resting() below,
## which makes the same argument about the same graph.
static func _pact_terms(state, actor_id: String, target_id: String) -> Dictionary:
	var asker = state.nations.get(actor_id)
	var asker_capability: float = 0.0 if asker == null else float(asker.military_capability)
	return {
		"stake": K.PACT_STAKE_WEIGHT * (stake(state, target_id, actor_id) / even_share(state, target_id) - 1.0),
		"amity": K.PACT_AMITY_WEIGHT * amity(state, target_id, actor_id),
		"capability": K.PACT_CAPABILITY_WEIGHT * (
			asker_capability / DFK.CAPABILITY_REFERENCE - 1.0
		),
	}


static func pact_accept_score(state, actor_id: String, target_id: String) -> float:
	var parts := _pact_terms(state, actor_id, target_id)
	return float(parts["stake"]) + float(parts["amity"]) + float(parts["capability"])


## Whether `target_id` would sign a defensive pact with `actor_id`.
##
## NOT a stopgap and not replacing one: V1.3f discharged the last of those, and this
## is a new counterparty decision written against the model that already exists.
static func would_accept_pact(state, actor_id: String, target_id: String) -> bool:
	return pact_accept_score(state, actor_id, target_id) >= K.PACT_ACCEPT_MIN


## Which term is why a pact was refused, as a key. Names the WEAKEST rather than the
## total, for refusal_reason()'s reason: the total is what the player cannot act on.
static func pact_refusal_reason(state, actor_id: String, target_id: String) -> String:
	var parts := _pact_terms(state, actor_id, target_id)
	var stake_term: float = float(parts["stake"])
	var amity_term: float = float(parts["amity"])
	var capability_term: float = float(parts["capability"])

	if stake_term <= amity_term and stake_term <= capability_term:
		return REFUSAL_LOW_STAKE
	if amity_term <= capability_term:
		return REFUSAL_POOR_RELATIONS
	return REFUSAL_WEAK_PARTNER


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
static func retaliation_fraction(state, imposer_id: String, target_id: String, ceiling: float,
		imposer_wbm: Dictionary = {}) -> float:
	# The imposer's own before-measures vector, hoistable by a caller already
	# holding it (target_terms does); empty means build-your-own.
	var iw: Dictionary = imposer_wbm if not imposer_wbm.is_empty() else Trade.weights_before_measures(state, imposer_id)
	var leverage: float = float(
		iw.get(target_id, 0.0)
	) / even_share_of(iw)
	# Numerator and yardstick from ONE vector, the target's before-measures one --
	# leverage's own convention two lines up. (The first V4.11 cut divided by the
	# post-measure even share, which disagrees whenever a measure is in force.)
	var tw: Dictionary = Trade.weights_before_measures(state, target_id)
	var exposure: float = float(tw.get(imposer_id, 0.0)) / even_share_of(tw)

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
##
## V5.0c2 split it in three so Diplomacy can read the observers on worker threads
## (src/sim/diplomacy_agenda.gd) and still apply THIS rule: observers(), each
## observer's observer_terms(), then third_party_from(). This serial composition
## is the reference the threaded one is tested against.
static func third_party_effects(state, actor_id: String, target_id: String, delta: float) -> Array:
	if is_zero_approx(delta):
		return []
	var others: Array = observers(state, actor_id, target_id)
	var seen: Array = []
	for x_id in others:
		seen.append(observer_terms(state, x_id, target_id))
	return third_party_from(others, seen, actor_id, target_id, delta)


## Everyone outside the pair, sorted, so the list is reproducible rather than
## dependent on Dictionary ordering -- the same reason Relations.all_pairs() and
## Bloc._members() sort.
static func observers(state, actor_id: String, target_id: String) -> Array:
	var others: Array = state.nations.keys()
	others.sort()
	var out: Array = []
	for x_id in others:
		if x_id != actor_id and x_id != target_id:
			out.append(x_id)
	return out


## [X's stake in the target, X's own even share]. One trade-vector build per
## observer, shared by its stake and its yardstick -- the floor is X's own even
## share since V4.11, because whether X notices is a question about X's attention,
## not the roster's. A pure read of the state.
static func observer_terms(state, x_id: String, target_id: String) -> Array:
	var xw: Dictionary = Trade.weights(state, x_id)
	return [float(stake_vector(state, x_id, xw).get(target_id, 0.0)), even_share_of(xw)]


## The rule, over `others` and their observer_terms() in the same order.
static func third_party_from(others: Array, seen: Array, actor_id: String, target_id: String, delta: float) -> Array:
	var out: Array = []
	for i in others.size():
		var x_id: String = others[i]
		var care: float = seen[i][0]
		var x_even: float = seen[i][1]
		if care < x_even * K.THIRD_PARTY_MIN_STAKE_SHARE:
			continue

		# CAPPED AT ONE, and V1.3f's agenda is what exposed the need for it.
		#
		# This was `care / EVEN_SHARE` uncapped, which reaches about 3.0 for the
		# roster's tightest pairs -- so a single act moved eight OTHER pairs by up to
		# three times the delta it moved its own. Invisible while only the player
		# acted a handful of times a term; with the nine acting on a cadence it
		# became the dominant force on the whole relations table, and fourteen years
		# put pairs on both clamps (measured 5.2 and 100.0, three pinned).
		#
		# The cap is the honest statement of the rule rather than a damping factor:
		# NOBODY TAKES AN ACT HARDER THAN THE NATION IT WAS AIMED AT.
		var reach: float = minf(1.0, care / x_even)

		out.append({
			"a": x_id,
			"b": actor_id,
			"delta": K.THIRD_PARTY_JUDGEMENT * delta * reach,
		})

		# SOLIDARITY IS FOR BEING WRONGED, so it applies to hostile acts only.
		#
		# The rule reads naturally in the direction it was written for -- sanctioning
		# Germany wins Germany sympathy from everyone who trades with Germany. Run
		# with a positive delta it says the opposite of anything intended: France
		# being NICE to Germany cools every other nation toward Germany, which is
		# jealousy rather than solidarity, and it has no defensible reading.
		#
		# It survived V1.3e because the only acts that ever reached this function
		# came from a player, and a player's hostile verbs are the memorable ones. An
		# agenda that mostly acts friendly ran the rule backwards a hundred times a
		# run, and that is what drove the recipients of goodwill to the floor.
		#
		# The judgement half above is unaffected and still signed: a nation is
		# credited for a friendly act and blamed for a hostile one, both by everyone
		# with a stake in whom it acted on.
		if delta < 0.0:
			out.append({
				"a": x_id,
				"b": target_id,
				"delta": -K.THIRD_PARTY_SOLIDARITY * delta * reach,
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
			# V3.2: "outside" is outside the ORG that is proposing -- read off the
			# NationState's own membership list, so no loader and no cycle is
			# needed here, and the term prices the right club's tariff.
			if other != null and not other.orgs.has(proposal.org_id):
				outside += float(weights[other_id])
		external = -K.APPRAISE_EXTERNAL_WEIGHT * outside * float(proposal.external_measure.get("severity", 0.0))

	return {
		"ideology": K.APPRAISE_IDEOLOGY_WEIGHT * _ideology_support(ns, proposal),
		"rule": -K.APPRAISE_RULE_WEIGHT * rule_burden,
		"transfer": -K.APPRAISE_TRANSFER_WEIGHT * proposal.transfer_pct_gdp * stress,
		"external": external,
	}


# --- V1.3f's agenda: acting first, rather than answering ---------------------------------

## How much `actor_id` wants to take this action against `target_id`, unprompted.
##
## Everything above this line in this file is REACTIVE: each function answers a
## question somebody else asked -- a treaty offered, a measure imposed, a proposal
## tabled, an act witnessed. This is the first function that starts a sentence.
##
## Takes the action's `effects` DICTIONARY rather than a DiplomaticAction, and
## that is structural rather than stylistic. diplomacy.gd preloads this file, so
## this file cannot preload diplomacy.gd -- it can never see available(),
## execute(), or the content class. It scores what it is handed and Diplomacy
## decides what to hand it, which is the same split would_accept_agreement() has
## already used for a whole session.
##
## Four terms, each documented at its weight in foreign_policy_constants.gd:
##
##   interest  is this partner worth more than a ninth of my attention
##   warmth    does the state of this relationship point at this KIND of verb
##   cost      what a hostile act would destroy of my OWN trade
##   risk      what the target would answer with, from the answering model itself
##
## Every term reads ZERO at neutral -- stake at exactly an even ninth, a pair
## exactly at its resting value, a purely rhetorical act -- which is what makes
## AGENDA_ACT_MIN interpretable on its own. The property accept_score() was built
## to have, held here for the same reason.
##
## The nine pay no domestic price for any of this and that asymmetry is declared
## rather than hidden: Opinion.tick_month() is gated on has_budget, so an AI's
## bloc_offset is written into state nothing reads. The player is checked at home,
## the nine are checked abroad, and the two checks are the cost and risk terms.
## See the note in foreign_policy_constants.gd's agenda section.
##
## The one-call form, for tests, the probe and any caller scoring a single
## candidate. Diplomacy's own loop uses target_terms() + desire_from() instead;
## see target_terms() for why that split is not a micro-optimisation.
static func desire(state, actor_id: String, effects: Dictionary, target_id: String) -> float:
	return desire_from(target_terms(state, actor_id, target_id), effects)


## Everything about a candidate act that depends on the PAIR and not on the VERB:
## {interest, amity, exposure, risk}. Computed once per target and reused across
## every action scored against it.
##
## Split out for cost, and the cost is real rather than theoretical. Each of the
## four reads runs Trade.weights() or weights_before_measures() over all ten
## nations, and an acting nation scores nine targets times ten verbs. Recomputing
## the pair terms inside that inner loop is ninety heavy reads where nine will do
## -- and Budget.project() ticks Diplomacy sixty times on a copy every time the
## budget panel refreshes, so this is on the path of a UI repaint, not only of a
## monthly tick.
##
## The split is also where the API stops being about a verb: Diplomacy holds one
## of these per target and asks desire_from() about each action it has.
static func target_terms(state, actor_id: String, target_id: String,
		stake_vec: Dictionary = {}, actor_wbm: Dictionary = {}, actor_even: float = -1.0, factor = null) -> Dictionary:
	# The AI agenda scores ~28 targets per acting nation, and stake_vector() plus
	# the actor's own before-measures weights do not vary across that loop --
	# nothing mutates state between scoring and the execute() that follows it.
	# The caller may therefore hoist both and pass them in; empty means
	# build-your-own, so every player-facing caller and test keeps its shape.
	# The read that genuinely varies per target -- the TARGET's before-measures
	# vector, inside retaliation_fraction -- stays built there.
	var sv: Dictionary = stake_vec if not stake_vec.is_empty() else stake_vector(state, actor_id)
	var aw: Dictionary = actor_wbm if not actor_wbm.is_empty() else Trade.weights_before_measures(state, actor_id)
	# V4.11: the actor's even share is a third per-actor invariant (it reads the
	# actor's whole trade vector), hoisted by the same caller for the same reason.
	var even: float = actor_even if actor_even > 0.0 else even_share(state, actor_id)
	return {
		# How much this partner matters, as a MULTIPLIER on the opportunity rather
		# than a term added to it. See _desire_parts() for why that distinction is
		# the whole shape of the model.
		#
		# Softened by an exponent for the reason trade_constants.GRAVITY_EXPONENT is,
		# and it is the same nation forcing it. Stake enters the agenda TWICE -- once
		# choosing which target to act on, and again valuing the act -- so a linear
		# read squares the spread, and the winner-takes-all pick then never descends
		# past a nation's top two partners. Measured: nobody acted on a GBR player in
		# fourteen years, at all, while it sat comfortably above AGENDA_ACT_MIN the
		# whole time. Being outranked forever is a different failure from being
		# unreachable, and only the second one a bar can fix.
		#
		# `factor` is this term handed in already taken: Diplomacy's fan-out takes it
		# on the calling thread (stake_factor(), V5.0c2), because pow() is not
		# bit-stable on a worker.
		"stake_factor": float(factor) if factor != null else stake_factor(sv, target_id, even),
		"amity": amity(state, actor_id, target_id),
		# Read BEFORE measures, for the reason docs/coercion-model.md gives at length
		# and retaliation_fraction() already follows: what a hostile act destroys is
		# the trade you had, not the trade that survives it. Reading the post-measure
		# vector is what made high severity strictly dominated at V1.3c.
		"exposure": float(aw.get(target_id, 0.0)) / even_share_of(aw),
		# The answering model, run from the acting side. Deliberately the real
		# function rather than a symmetric copy: an exchange whose two halves are
		# computed by two functions is two models that will disagree, and this one
		# was measured.
		#
		# Read as DETERRENCE -- how willing and able this target is to hit back at
		# all -- rather than as a prediction that this specific act draws a specific
		# tariff, which is why it scales a condemnation too.
		"risk": retaliation_fraction(state, actor_id, target_id, CK.RETALIATION_FRACTION, aw),
	}


## The stake term of target_terms(): the target's share of the actor's stake over
## the actor's even share, through AGENDA_STAKE_EXPONENT.
static func stake_factor(sv: Dictionary, target_id: String, even: float) -> float:
	return pow(float(sv.get(target_id, 0.0)) / even, K.AGENDA_STAKE_EXPONENT)


## One action scored against a target's pair terms. The cheap half of desire().
static func desire_from(terms: Dictionary, effects: Dictionary) -> float:
	var parts := _desire_parts(terms, effects)
	return (
		float(parts["deepen"])
		+ float(parts["mend"])
		+ float(parts["punish"])
		+ float(parts["cost"])
		+ float(parts["risk"])
		+ float(parts["domestic"])
	)


## Which term made a nation act, as a KEY. One of ACT_REASON_KEYS.
##
## Picked by largest POSITIVE contribution rather than largest absolute one, which
## is the one place this deliberately differs from vote_reason(). Cost and risk are
## reasons not to act; an act that cleared AGENDA_ACT_MIN was not stopped by them,
## so naming one would be a reason that refutes the act it explains -- the exact
## failure V1.3e's balance re-run caught in vote_reason() and fixed there.
##
## Only meaningful for an act that was actually taken. Reading it off a candidate
## that scored below the bar names the strongest argument for a case that lost.
static func act_reason(terms: Dictionary, effects: Dictionary) -> String:
	var parts := _desire_parts(terms, effects)

	var best_key: String = ACT_REASON_INTEREST
	var best: float = float(parts["deepen"])
	if float(parts["mend"]) > best:
		best = float(parts["mend"])
		best_key = ACT_REASON_GOODWILL
	if float(parts["punish"]) > best:
		best_key = ACT_REASON_GRIEVANCE
	return best_key


## The contributions of a desire, signed as they enter the sum. One builder, so
## desire_from() and act_reason() cannot drift apart -- the same reason
## _appraisal_terms() exists, and the same failure it exists to prevent.
##
## > [!warning] The probe's correction: interest as an ADDEND is a goodwill ratchet
## > The first version summed five terms, one of which was
## > `stake/EVEN_SHARE - 1` on its own. That made a partner's importance a
## > STANDING REASON TO ACT, and since a friendly verb has no hostility it also has
## > no cost and no risk -- so every nation state-visited its largest partner every
## > cycle, forever, with nothing anywhere in the arithmetic to stop it.
## >
## > Measured over fourteen years: mean relations **79.6** against resting tiers
## > that span 45 to 68, and a pair pinned at the RELATIONS_MAX clamp. The clamp
## > rather than the model setting the number, which is docs/economy-model.md's
## > IMPULSE_MAX failure in its fourth place -- and docs/trade-model.md's own
## > `state_visit` exploit, which V1.3b priced out of the PLAYER's economy and
## > nobody had yet priced out of an agent that acts forever.
## >
## > So interest MULTIPLIES an opportunity instead of adding to one. A nation acts
## > where its interests are, but only when there is something to be gained there,
## > and "something to be gained" is bounded by construction rather than by a bar.
## > An inert act now reads EXACTLY 0.0 rather than leaving the interest term
## > dangling, which makes AGENDA_ACT_MIN cleaner than it was before the correction.
##
## Three opportunities, and the sign of amity decides which are open:
##
##   deepen   a partner that matters, up to AGENDA_AMITY_TARGET and no further --
##            this is the term that closes as a relationship improves, and it is
##            what makes the ratchet structurally impossible rather than tuned away
##   mend     a soured relationship worth repairing
##   punish   a soured relationship worth answering
##
## At amity 0 -- every pair at new-game, by construction -- only `deepen` is open,
## so a fresh world opens cooperative and turns hostile only once somebody has
## acted. Above the target, none of the three is open and the pair is left alone.
static func _desire_parts(terms: Dictionary, effects: Dictionary) -> Dictionary:
	var intensity := _act_intensity(effects)
	var hostility: float = float(intensity["hostility"])
	var warmth: float = float(intensity["warmth"])
	var amity_v: float = float(terms["amity"])
	var weight: float = float(terms["stake_factor"])

	# Headroom, and the reason the ratchet cannot come back: once the pair is at or
	# above the target this is exactly 0.0, whatever the partner is worth.
	var room: float = maxf(0.0, K.AGENDA_AMITY_TARGET - amity_v)
	var grievance: float = maxf(0.0, -amity_v)

	return {
		"deepen": weight * warmth * room,
		"mend": weight * warmth * grievance * K.AGENDA_MEND_WEIGHT,
		"punish": weight * hostility * grievance * K.AGENDA_GRIEVANCE_WEIGHT,
		"cost": -K.AGENDA_COST_WEIGHT * float(terms["exposure"]) * hostility,
		"risk": -K.AGENDA_RISK_WEIGHT * float(terms["risk"]) * hostility,
		"domestic": -K.AGENDA_DOMESTIC_WEIGHT * _act_domestic_price(effects),
	}


## What an act costs its own government at home, read off the action's authored
## bloc_offset as a magnitude.
##
## > [!warning] The probe's second correction: free concessions get spent freely
## > The first version priced only HOSTILE acts, on the argument that the nine are
## > restrained abroad rather than at home. Measured over fourteen years,
## > `settle_dispute` was nineteen of the last twenty-four acts -- the LARGEST
## > friendly verb in the content and by far the most expensive, six blocs at -0.09,
## > which the content's own summary calls a climbdown every bloc reads as a
## > surrender. The player pays 0.54 of offset for it. The nine paid nothing, so
## > they conceded a long-running national quarrel roughly once a year each.
## >
## > This is NOT the synthetic appetite constant this session refused. It is the
## > action's own authored number, read the way accept_score() already reads
## > `weight_multiplier` -- the content states how hard an act is, and the nine were
## > the only ones not listening. No new field, no new content, and a verb whose
## > domestic price an author changes becomes correspondingly rarer in AI hands,
## > which is the data-not-code rule doing exactly what it is for.
##
## A magnitude rather than a signed sum, and deliberately: the two impose verbs are
## SPLIT prices that nearly cancel, so a signed read would score a tariff as almost
## free at home. What makes an act expensive is that it moves the country at all --
## docs/diplomacy-model.md's own finding that a split price is legible on the
## per-bloc rows and never in the headline figure, read from the other side.
static func _act_domestic_price(effects: Dictionary) -> float:
	var total: float = 0.0
	for value in (effects.get("bloc_offset", {}) as Dictionary).values():
		total += absf(float(value))
	return total


## How friendly and how hostile an action is, both on roughly [0, 1+].
##
## Read off the content rather than authored per action, so a new verb in
## data/diplomatic-actions/ is scored by the agenda with no change here -- the
## data-not-code rule docs/engine-decision.md states first.
##
## Hostility sums the relations damage and the measure severity because they are
## genuinely two different harms: a condemnation costs standing, a sanction costs
## standing AND trade. Against the shipped content that orders the four hostile
## verbs sanctions > tariffs > condemnation > withdrawal, which is the ordering a
## player would give unprompted.
static func _act_intensity(effects: Dictionary) -> Dictionary:
	var delta: float = float(effects.get("relations", 0.0))
	var hostility: float = maxf(0.0, -delta) / DK.MAX_ACTION_RELATIONS_DELTA

	var measure: Dictionary = effects.get("measure", {})
	if String(measure.get("op", "")) == "impose":
		hostility += float(measure.get("severity", 0.0)) / CK.MAX_MEASURE_SEVERITY

	return {
		"warmth": maxf(0.0, delta) / DK.MAX_ACTION_RELATIONS_DELTA,
		"hostility": hostility,
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
static func _resting(a, b, co_member_bonus: float) -> float:
	var value: float = DK.REST_BASE
	# V3.2: the co-membership bonus is content and rides in -- the same sum
	# Diplomacy.resting() adds, computed by the caller through Org.shared_bonus(),
	# so the two copies still agree by construction and the test still asserts it
	# for all forty-five pairs rather than trusting this comment.
	value += co_member_bonus
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
