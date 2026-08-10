extends RefCounted

## Unrest — V1.5c, the third session of the V1.5 block. A grievance stock, and the
## unions, protests and strikes that act on it. The model and every constant's rationale
## is docs/unrest-model.md; src/sim/unrest_constants.gd is the values.
##
## THE BLOCK'S ONE TRUE ACTING AGENT, and the session where two rules that have been
## pulling against each other finally agree. V1.3a's rule was that state ships WITH A
## VERB or it decays to nothing; docs/tiers/v1.md section 5 contains at most two player
## verbs across nine bullets, so ROADMAP.md inverted it for this block into *every
## session ships a statistic and the price it charges*. Here the statistic is the
## grievance and the verb is the union's, not the player's — which is what a rule about
## live state needing something to act on it always meant.
##
## THE TARGET READS TWO ROWS OF THE ELECTORATE, NOT SIX, and that is the design's load
## bearing call rather than a weighting detail. A national anger index already exists:
## Discipline.unpopularity() is a [0, 1] read off overall_approval_pct, and it is
## already consumed by discipline.gd, government.gd and cabinet.gd. A grievance built on
## the whole electorate's satisfaction would be that quantity a second time, under a new
## name — military_capability and potential_shift_pct's failure a fifth time — and it is
## also exactly what section 5's own bullet warns against: *"unrest driven by nothing the
## average voter does not already feel is a second approval number with a different
## label."* Two mobilised blocs plus two terms no opinion issue reads is the answer to
## that sentence, and it is mechanical rather than asserted.
##
## THE PRICE IS OUTPUT ONLY. A strike writes a decaying impulse into economy.gd's growth
## sum and approval falls through `growth` and `jobs`, which are issues that already
## exist and that elections.gd can already attribute on the result screen. No thirteenth
## ISSUE_KEYS entry, and the reason it is NO is prior to V1.3d's four tests rather than
## an answer to test 4: there is no direct opinion term here to key. See
## opinion_constants.gd, where the reasons are recorded beside ISSUE_KEYS itself.
##
## THIS SCHEDULER IS EXPLICITLY NON-GENERIC, and docs/tiers/v1.md section 8 says that
## has to be said out loud rather than left silent. There is no preconditions table, no
## authored choice list and no content directory: one float crosses one threshold, one
## cooldown gates it, and three labels are chosen by evenly dividing the span above the
## threshold. Section 8's event schema is not being written here under another name.
##
## Preloads opinion.gd for issue_satisfaction() and salience_weights(), and its own
## constants. NOT a leaf — demography.gd is the strictest in the project and society.gd
## preloads two — and tests/test_unrest.gd asserts this exact list, because the one
## preload that would be wrong is economy.gd: this file WRITES an impulse Economy reads
## next month, and a reverse edge would make the lag a convention instead of a fact.
##
## WRITES ns.unrest_pct, ns.unrest_cooldown_months, ns.unrest_impulse_pct and
## state.unrest_acts. `settlement_stance` has exactly one writer and it is
## Legislature.apply(); `gini_index` has one and it is Demography.tick_month(). This file
## only ever reads both, and tests/test_unrest.gd asserts it by reading the file — the
## idiom people-model.md, calendar-model.md, society-model.md and demography-model.md
## all use.

const K = preload("res://src/sim/unrest_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")


## Zero, explicitly, and the explicitness is the point.
##
## Unlike Society and Defence this stock's equilibrium genuinely IS zero, because every
## term of its target is a deviation against the nation's own starting figure and all of
## them are exactly 0.0 at new game. So this function could be deleted and nothing would
## change today — it is here so that a later session adding an authored starting
## grievance has somewhere for it to go, and so the claim "exactly 0.0 at new game" is
## written down beside the code that makes it true rather than only in a test.
##
## Runs for all ten nations even though only the player's grievance ticks, so the state
## shape is uniform and duplicate_state() has nothing conditional to copy — the reason
## opinion.gd's own init_nation() gives.
static func init_nation(ns) -> void:
	ns.unrest_pct = 0.0
	ns.unrest_cooldown_months = 0
	ns.unrest_impulse_pct = 0.0


## Runs immediately AFTER Society.tick_month() in src/ui/main.gd's order, and
## Budget.project() runs it in the same slot.
##
## After Society because the hardship term reads the `health` and `pensions`
## satisfactions, which read V1.5a's quality stock through V1.5b's dependency
## denominator; after Opinion for society.gd's reason inherited whole, and here the loop
## it breaks is a second one: unrest feeds overall_approval_pct AND `unrest_pct` is
## itself an entry in legislature_constants.PRECONDITION_FIELDS, so unrest -> which laws
## are available -> a settlement law -> the stance -> unrest closes twice over. The
## one-month lag breaks both structurally rather than by being careful.
##
## GATED ON has_budget, which is Opinion.tick_month()'s own gate and Discipline's, and
## the reason transfers exactly: this target is built out of Opinion.issue_satisfaction(),
## and a grievance figure for a nation that has no opinion model is a number with no
## meaning. It also keeps the nine's GDP untouched, which is what lets a channel that
## writes a growth impulse ship without moving a single figure in the nine.
static func tick_month(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		if not ns.has_budget:
			continue
		_tick_nation(state, ns)


# --- The stock ----------------------------------------------------------------

## What the grievance is converging on, in points of a 0–100 index.
##
## Three terms, and NO WEIGHTS BETWEEN THEM beyond the two betas — the hardship term
## arrives already normalised because it is a satisfaction, so UNREST_MAX multiplying it
## is a unit conversion rather than a tuned coefficient. That is what keeps this file
## free of the three-way weight table V1.3d's rule severities warn about, where three
## numbers nobody can sweep independently sum to something nobody checked.
##
## Terms two and three are the answer to section 5's "second approval number" warning:
## the Gini drift is read by no opinion issue, and neither is the settlement stance, so
## a country can be angry for reasons its approval figure does not contain.
static func unrest_target(ns) -> float:
	var sat: Dictionary = Opinion.issue_satisfaction(ns)
	return clampf(
		K.UNREST_MAX * hardship(sat)
		+ K.INEQUALITY_BETA * inequality_deviation(ns)
		- K.SETTLEMENT_BETA * float(ns.settlement_stance),
		K.UNREST_MIN, K.UNREST_MAX
	)


## How angry the mobilised blocs are, as a satisfaction turned upside down, in [-1, +1].
##
## Reads each named bloc's OWN salience row rather than the national roll-up, and
## weights the rows by those blocs' existing BLOC_SIZE shares renormalised over the set.
## Two existing tables and no new numbers — and the political map falls out of a table
## written at S5 for reasons that had nothing to do with strikes, which is
## docs/bloc-model.md's finding a second time. Workers weight `defence` at nothing and
## `tax_vat` at 0.08, so a government that governs by moving those two is quiet here
## whatever it does to them.
##
## Runs through salience_weights() and not the base row, deliberately: SALIENCE_GAIN
## amplifies the issue a bloc is actually suffering on, so a country angry about one
## thing is angrier than the flat weights would say. That is the same amplification the
## polling panel and the result screen already show the player, reused rather than
## re-derived.
static func hardship(sat: Dictionary) -> float:
	var total := 0.0
	var share_sum := 0.0
	for bloc in K.UNREST_BLOCS:
		var size: float = float(OpinionK.BLOC_SIZE.get(bloc, 0.0))
		var weights: Dictionary = Opinion.salience_weights(OpinionK.BLOC_SALIENCE_BASE[bloc], sat)
		var row := 0.0
		for issue in weights:
			row += float(weights[issue]) * float(sat.get(issue, 0.0))
		total += size * row
		share_sum += size
	if share_sum <= 0.0:
		return 0.0
	return -total / share_sum


## How far this nation's Gini index has drifted since the game began, in points.
##
## A PURE READ of two fields Demography writes and content seeds — no accumulator here,
## no writer here, and no save entry of its own beyond the drift Demography already owns.
## Defence.allies()' shape, which ROADMAP.md's decomposition named for this statistic in
## advance.
##
## THE DECLARED STOPGAP. docs/tiers/v1.md section 6 owns the instruments — brackets,
## wealth, capital gains — and nothing that exists today moves this number: not the
## corporate rate, not a state holding, not a sector burden. That insensitivity is
## asserted in tests/test_unrest.gd against all three, which turns "declared stopgap"
## into a tripwire that goes red the day section 6 lands instead of a sentence in a doc.
static func inequality_deviation(ns) -> float:
	return float(ns.gini_index) - float(ns.start_gini_index)


## What the country's grievance takes off every bloc's approval target, on the [-1, +1]
## scale opinion.gd's satisfaction terms use. Zero for a calm country, so this term is
## silent in every game that never earns one.
##
## Written onto ns.unrest_opinion_load by _tick_nation() and read by opinion.gd from
## there, rather than opinion.gd calling this -- `deployment_opinion_load`'s arrangement
## exactly, and here it is load-bearing rather than stylistic: this file preloads
## opinion.gd for issue_satisfaction(), so a call the other way would be a preload cycle.
##
## See unrest_constants.UNREST_OPINION_SCALE for why an output-only price was designed,
## measured, and found structurally unable to reach a voter.
static func opinion_load(ns) -> float:
	return K.UNREST_OPINION_SCALE * clampf(float(ns.unrest_pct) / K.UNREST_MAX, 0.0, 1.0)


## One month of convergence. Pure, so tools/unrest_probe.gd can sweep the rate over a
## fourteen-year horizon without building a GameState — society.gd's quality_step() and
## defence.gd's capability_step() have the same signature for the same reason.
static func unrest_step(current: float, target: float) -> float:
	return clampf(
		current + K.UNREST_CONVERGENCE * (target - current),
		K.UNREST_MIN, K.UNREST_MAX
	)


# --- The agent ----------------------------------------------------------------

## Whether the unions act this month. Deterministic, and diplomacy.gd's _tick_agenda()
## shape: a level to clear and a cooldown to have expired. No randomness anywhere,
## because the balance harness's whole value is that two runs differing in one decision
## differ in nothing else.
##
## A LEVEL READ RATHER THAN AN EDGE TRIGGER, which is defence.gd's obligation argument
## reused: an act that fired only on the month the threshold was crossed would be silent
## for a government that inherited a country already over it.
static func would_act(ns) -> bool:
	return (
		float(ns.unrest_pct) >= K.UNREST_THRESHOLD_PCT
		and int(ns.unrest_cooldown_months) <= 0
	)


## What the act is called at this grievance. The span from the threshold to the ceiling
## is divided evenly by the number of labels, so the tiers are a property of the list
## rather than two more tuned constants — add a fourth name and the three re-space
## themselves.
##
## DISPLAY ONLY. src/ui/message_stack.gd reads it; nothing in src/sim/ does, and
## tests/test_unrest.gd asserts that by reading every file in the directory. This is what
## makes protests and strikes one machine with three names instead of three machines
## wearing the row's vocabulary — V1.3c's *one verb, two prices* in the noun rather than
## in the mechanism, and V1.3f's foreign_acts property enforcing it.
static func act_label(unrest: float) -> String:
	var span: float = K.UNREST_MAX - K.UNREST_THRESHOLD_PCT
	if span <= 0.0:
		return String(K.ACT_LABELS[K.ACT_LABELS.size() - 1])
	var over: float = clampf((unrest - K.UNREST_THRESHOLD_PCT) / span, 0.0, 1.0)
	var index: int = mini(int(over * K.ACT_LABELS.size()), K.ACT_LABELS.size() - 1)
	return String(K.ACT_LABELS[index])


## Points of annual growth this month's action costs, negative. Scales linearly with the
## stock, so a protest at the threshold costs its share of what a general strike at the
## ceiling costs and UNREST_IMPULSE_SCALE means one legible thing: the price of the
## worst case.
static func act_impulse(unrest: float) -> float:
	return -K.UNREST_IMPULSE_SCALE * clampf(unrest / K.UNREST_MAX, 0.0, 1.0)


static func _tick_nation(state, ns) -> void:
	ns.unrest_pct = unrest_step(float(ns.unrest_pct), unrest_target(ns))
	ns.unrest_opinion_load = opinion_load(ns)

	# Decayed HERE and not in economy.gd, unlike demand_impulse_pct which Economy owns
	# both ends of. The field then has one writer, which is the discipline every register
	# added since V1.4a has kept, and Economy stays a pure reader of it.
	ns.unrest_impulse_pct = clampf(
		float(ns.unrest_impulse_pct) * EconomyK.IMPULSE_DECAY,
		-K.UNREST_IMPULSE_MAX_PCT, K.UNREST_IMPULSE_MAX_PCT
	)

	if int(ns.unrest_cooldown_months) > 0:
		ns.unrest_cooldown_months = int(ns.unrest_cooldown_months) - 1

	if not would_act(ns):
		return

	# Accumulated rather than assigned: a second act arriving while the first is still
	# decaying is a country in a rolling dispute, and overwriting would make the second
	# strike cheaper than the first. The clamp is what bounds it.
	ns.unrest_impulse_pct = clampf(
		float(ns.unrest_impulse_pct) + act_impulse(float(ns.unrest_pct)),
		-K.UNREST_IMPULSE_MAX_PCT, K.UNREST_IMPULSE_MAX_PCT
	)
	ns.unrest_cooldown_months = K.UNREST_COOLDOWN_MONTHS

	# A display record and not a memory. src/sim/ never reads this back — the grievance
	# number IS the memory, which is V1.3e's *no grievance ledger* property arriving in
	# the one session that could have been tempted to build the ledger literally.
	state.unrest_acts.append({
		"nation_id": ns.id,
		"year": int(state.year),
		"month": int(state.month),
		"label": act_label(float(ns.unrest_pct)),
		"unrest_pct": float(ns.unrest_pct),
	})
	while state.unrest_acts.size() > K.ACTS_KEPT:
		state.unrest_acts.remove_at(0)
