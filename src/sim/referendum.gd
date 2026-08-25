extends RefCounted

## The referendum: a constitutional amendment ratified by the people instead of by a
## supermajority of the assembly. Built at V1.7c, the last session of the V1.7 block,
## and it discharges a stopgap declared at V1.2c and left standing for five blocks --
## src/core/nation.gd's KNOWN_AMENDMENT_RULES carried `referendum_required` with
## "no referendum mechanic exists yet (V1.1f/V1.7)" written beside it, and
## legislature_constants.AMENDMENT_RULE_FRACTIONS deliberately had no entry for it.
##
## The model and both constants are docs/referendum-model.md.
##
## ============================================================================
## A SECOND RATIFICATION STAGE AT A LOWER ASSEMBLY BAR, NOT A BYPASS OF IT
## ============================================================================
## The design that suggests itself is "put it to the people INSTEAD of the assembly",
## and not one of the ten constitutions works that way. Every citation was already in
## the nation files' own government.amendment._note, authored at V1.2c for a mechanic
## that did not exist:
##
##   FRA  Art. 89: a revision bill must pass both chambers, then EITHER a popular
##        referendum OR -- the President's choice -- Congress at 3/5.
##   ITA  Art. 138: a second vote at absolute majority is open to a referendum
##        petition; only a 2/3 second vote is referendum-proof.
##   LUX  Art. 114: two simple-majority votes then a binding referendum, unless the
##        second vote itself carries by 3/4.
##   CHE  Art. 195: a mandatory popular vote, with no seats-only path at all.
##
## All four are the SAME SHAPE: the referendum replaces the SUPERMAJORITY with an
## ordinary majority plus a popular vote. So route A (the assembly at the nation's own
## amendment_rule) is untouched, and route B is ABSOLUTE_MAJORITY_FRACTION in the
## chamber and then REFERENDUM_MAJORITY at the ballot box. Neither is a subset of the
## other: route B is easier in the chamber and harder outside it.
##
## ============================================================================
## THE POPULAR VOTE IS Elections.vote_share() WITH TWO OPTIONS
## ============================================================================
## Not a new model. Per bloc, exactly the structure that file already uses for parties:
##
##   YES sits at the law's own authored `position`, on the same two-axis space
##       election_constants.SLOT_POSITION uses. Every amendment in
##       data/laws/amendments.json has carried one since V1.2c.
##   NO  sits at status_quo_position(), the SIZE-WEIGHTED MEAN of BLOC_IDEAL. Derived
##       from a table written at S5 for unrelated reasons, not authored --
##       docs/media-model.md's V1.5d mean anchor, one block on. A start-anchored or
##       per-nation NO would have been a second content decision with no dataset
##       behind it, which is the clustered coalition_position failure V1.3e recorded.
##   Both weighted by affinity at the existing AFFINITY_SIGMA, renormalised per bloc,
##       and the bloc's weight is BLOC_SIZE x Campaign.turnout_of().
##   YES carries the incumbent's PER-BLOC approval pull on the existing
##       INCUMBENT_SWING, because a referendum called by an unpopular president is a
##       vote on the president. De Gaulle resigned on one in 1969 and the arithmetic
##       says so without a term authored for it.
##
## TWO PROPERTIES NOBODY AUTHORED FALL OUT OF THAT. A referendum held inside V1.7a's
## presidential run-up reads whatever mobilisation the campaign bought, for free and
## with no edge anywhere -- so WHEN to hold it is a real decision. And one held outside
## the run-up reads election_constants.BLOC_TURNOUT bit-for-bit, because
## Campaign.turnout_of() returns the authored constant exactly at mobilisation 0.0.
##
## ============================================================================
## A LEAF, AND THE TEST READS THIS FILE TO SAY SO
## ============================================================================
## Preloads its own constants, election_constants, opinion_constants,
## legislature_constants (for the bloc_offset clamp alone) and campaign.gd. It does NOT
## preload legislature.gd: resolve_due() returns the verdict as DATA and legislature.gd
## applies the law, which is src/sim/calendar.gd's due() one block on and the reason
## that file could preload nothing. tests/test_referendum.gd extracts this header's
## claim from the source and fails if `legislature.gd` appears in it.

const K = preload("res://src/sim/referendum_constants.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const Campaign = preload("res://src/sim/campaign.gd")


## Seeds the live register: nothing called and nothing decided.
##
## Every nation gets the fields rather than only the player, Campaign.init_nation()'s
## and Projects.init_nation()'s call: what keeps the nine inert is that nothing ever
## calls a referendum for them, and tests/test_referendum.gd pins that there is no AI
## agenda term for this verb -- docs/defence-model.md's honest limitation, recorded a
## fifth time.
static func init_nation(ns) -> void:
	ns.referendum_pending = {}
	ns.last_referendum_result = {}


# --- The route -------------------------------------------------------------------

## Whether this nation's constitution offers the referendum route at all.
static func mode_of(ns) -> String:
	var mode := String(ns.referendum_mode)
	return mode if K.KNOWN_MODES.has(mode) else K.MODE_NONE


## True where the head of state may CHOOSE the referendum -- so a UI offers a button and
## legislature.gd offers a second route. False under `mandatory` as well as `none`,
## because a mandatory referendum is not a choice: it is what proposing the amendment
## already means, and offering it as an alternative would imply a seats-only path that
## Art. 195 says does not exist.
static func may_choose(ns) -> bool:
	return mode_of(ns) == K.MODE_OPTIONAL


## True where the referendum is the ONLY path, so route A does not exist.
static func is_mandatory(ns) -> bool:
	return mode_of(ns) == K.MODE_MANDATORY


## A referendum is called for one amendment at a time, and the register is the whole of
## that rule -- there is no constant bounding concurrency, because one is not a bound,
## it is what "the country votes on this question" means.
static func is_pending(ns) -> bool:
	return not ns.referendum_pending.is_empty()


static func pending_law_id(ns) -> String:
	return String(ns.referendum_pending.get("law_id", ""))


static func months_left(ns) -> int:
	return int(ns.referendum_pending.get("months_left", 0))


# --- The popular vote -------------------------------------------------------------

## Where the status quo sits: the size-weighted mean of every bloc's ideal point.
##
## DERIVED, NOT AUTHORED, and that is the whole reason this module ships no constant for
## the popular vote. The alternative considered and refused was a per-nation authored
## status-quo position, which is ten numbers with no dataset behind them -- V1.5b's
## refusal of ten authored age structures, in the one place where a dataset could never
## exist because the quantity is invented.
##
## Computed on every call rather than cached on NationState, because caching it would
## put a derived constant in the save -- the property tests/test_save_load.gd pins for
## Campaign._terms_by_effort() and for V1.4a, V1.6e and V1.6f before it.
static func status_quo_position() -> Dictionary:
	var econ := 0.0
	var social := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		var size: float = float(OpinionK.BLOC_SIZE[bloc])
		var ideal: Dictionary = ElectionK.BLOC_IDEAL[bloc]
		econ += size * float(ideal["economic"])
		social += size * float(ideal["social"])
	return {"economic": econ, "social": social}


## One bloc's yes share, in [0, 1]. Elections.vote_share()'s inner loop with two
## options rather than a party list, and the incumbent multiplier on YES rather than on
## a named party -- the government is what proposed it.
static func bloc_yes(ns, bloc: String, position: Dictionary) -> float:
	var ideal: Dictionary = ElectionK.BLOC_IDEAL[bloc]
	var yes_weight := _affinity(position, ideal)
	# The status quo is weighted by more than its position, because it IS the status
	# quo -- see K.STATUS_QUO_PULL, which the probe fired rather than the design
	# assuming. At 1.0 this line is inert and the model is the un-escalated one.
	var no_weight: float = _affinity(status_quo_position(), ideal) * K.STATUS_QUO_PULL

	var approval: float = float(ns.bloc_approval.get(bloc, OpinionK.APPROVAL_NEUTRAL))
	var pull: float = clampf(
		(approval - OpinionK.APPROVAL_NEUTRAL) / OpinionK.APPROVAL_NEUTRAL, -1.0, 1.0
	)
	yes_weight *= (1.0 + ElectionK.INCUMBENT_SWING * pull)

	var total := yes_weight + no_weight
	if total <= 0.0:
		return 0.0
	return yes_weight / total


## The national yes share, in [0, 1]: every bloc's own answer, weighted by its size and
## by how much of it turns out. Reads Campaign.turnout_of() rather than the raw
## BLOC_TURNOUT, so a referendum held inside a presidential run-up counts the electorate
## the campaign actually mobilised.
static func yes_share(ns, position: Dictionary) -> float:
	var total := 0.0
	var weight_total := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		var weight: float = float(OpinionK.BLOC_SIZE[bloc]) * Campaign.turnout_of(ns, bloc)
		weight_total += weight
		total += weight * bloc_yes(ns, bloc, position)
	if weight_total <= 0.0:
		return 0.0
	return total / weight_total


## Squared-exponential affinity on the two-axis ideology space, at the same
## AFFINITY_SIGMA Elections.vote_share() uses. Not re-derived: one falloff, one number.
static func _affinity(a: Dictionary, b: Dictionary) -> float:
	var d_econ: float = float(a.get("economic", 0.0)) - float(b["economic"])
	var d_social: float = float(a.get("social", 0.0)) - float(b["social"])
	var dist: float = sqrt(d_econ * d_econ + d_social * d_social)
	return exp(-pow(dist / ElectionK.AFFINITY_SIGMA, 2.0))


# --- The register ------------------------------------------------------------------

## Put an amendment to the country. Called by Legislature.propose() AFTER the chamber
## has given it an absolute majority, never before -- route B is a second stage, not a
## bypass, and this file does not know how a chamber votes.
##
## `position` is copied into the register rather than re-read from the loader at
## resolution, so the question the country answers is the question it was asked. Content
## cannot change under a live referendum, and the register carries no other authored
## fact -- tests/test_referendum.gd asserts a serialised entry has exactly these three
## keys, V1.4a's discipline.
static func announce(ns, law_id: String, position: Dictionary) -> void:
	ns.referendum_pending = {
		"law_id": law_id,
		"months_left": K.REFERENDUM_DELAY_MONTHS,
		"position": {
			"economic": float(position.get("economic", 0.0)),
			"social": float(position.get("social", 0.0)),
		},
	}


## Count the register down and hand back whatever fell due, as DATA. Empty when nothing
## resolved this month, which is every month for the nine and most months for the
## player.
##
## Called from Legislature.tick_month(), which every harness in this project already
## calls -- src/ui/main.gd, tools/balance_probe.gd, tests/test_balance.gd and eight
## probes. That is docs/cycle-model.md's V1.6a argument taken deliberately: V1.5d
## shipped with neither balance harness calling Media.tick_month(), so both ran the
## pre-session model and their agreement about a bit-identical re-run was about nothing.
## A referendum reached through a call they all already make cannot repeat it.
static func resolve_due(ns) -> Dictionary:
	if not is_pending(ns):
		return {}
	var left := months_left(ns) - 1
	if left > 0:
		ns.referendum_pending["months_left"] = left
		return {}

	var position: Dictionary = ns.referendum_pending.get("position", {})
	var share := yes_share(ns, position)
	var result := {
		"law_id": pending_law_id(ns),
		"passed": share > K.REFERENDUM_MAJORITY,
		"yes_share": share,
		"withdrawn": false,
	}
	ns.referendum_pending = {}
	_charge(ns, result["passed"])
	ns.last_referendum_result = result
	return result


## Call it off. Costs EXACTLY what losing costs and sets the same cooldown, so holding
## the vote WEAKLY DOMINATES withdrawing by construction: the two outcomes are identical
## except that holding it might carry.
##
## That is a proof rather than a fitted second constant, and it is why this file has one
## price and not two. A withdrawal priced BELOW a loss is strictly better than governing
## through a referendum you might lose -- the free-hedge shape this project has killed
## ten times -- and one priced above it needs a number solved against the first, which
## is what src/core/investment_action.gd refuses as one strength written twice.
##
## What withdrawal actually buys is the register slot back this month rather than in
## REFERENDUM_DELAY_MONTHS. Small, real, and never free.
static func withdraw(ns) -> Dictionary:
	if not is_pending(ns):
		return {}
	var result := {
		"law_id": pending_law_id(ns),
		"passed": false,
		"yes_share": 0.0,
		"withdrawn": true,
	}
	ns.referendum_pending = {}
	_charge(ns, false)
	ns.last_referendum_result = result
	return result


## The price, on ns.bloc_offset -- docs/pledge-model.md's V1.7b landing site, because
## trust in a promise and the standing of a president who called a vote and lost it are
## both squarely AT the ballot box rather than outside it. Applied to every bloc alike:
## a rebuke is not selective, and a per-bloc table here would be a second BLOC_SIZE with
## nothing measured behind it.
static func _charge(ns, passed: bool) -> void:
	var delta: float = K.REFERENDUM_RESULT_OFFSET if passed else -K.REFERENDUM_RESULT_OFFSET
	for bloc in OpinionK.BLOC_KEYS:
		ns.bloc_offset[bloc] = clampf(
			float(ns.bloc_offset.get(bloc, 0.0)) + delta,
			LegislatureK.BLOC_OFFSET_MIN, LegislatureK.BLOC_OFFSET_MAX
		)
