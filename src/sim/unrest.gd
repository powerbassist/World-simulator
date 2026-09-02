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
## all use. V1.6d discharges section 6's stopgap on the Gini WITHOUT touching that
## property: the player's tax policy reaches the index as a second READ inside
## inequality_deviation() below, and Demography.tick_month() is still the only thing
## that writes it.

const K = preload("res://src/sim/unrest_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")
# V1.6d, and the fifth preload rather than a reverse edge. tax.gd is a LEAF --
# it preloads two constants files and nothing else -- so this adds no cycle and no
# ordering question. The edge runs this way because the grievance is what the
# distribution COSTS, and docs/tax-model.md owns what it is.
const Tax = preload("res://src/sim/tax.gd")

## V1.1e, for unrest_load() alone -- the grievance reads the judiciary the way it
## reads the press, and judiciary.gd knows nothing about a grievance. One direction.
const Judiciary = preload("res://src/sim/judiciary.gd")

## V2.6b1, and the three that give the grievance a PLACE. siting.gd preloads
## nothing at all, regions.gd preloads two constants files, and migration.gd
## preloads those two plus companies.gd -- so none of them can reach economy.gd and
## the one edge this file must never have is still absent. tests/test_unrest.gd's
## closed-set assertion widens by exactly these THREE names and says why. There is
## no siting_constants.gd to preload: the one constant this session would have added
## was measured, failed its own band and was deleted -- see opinion_load() below.
const Siting = preload("res://src/sim/siting.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")


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
		- K.SETTLEMENT_BETA * float(ns.settlement_stance)
		# V1.5d, and the MINUS is the term: press_freedom is negative when the press is
		# restricted, so censorship ADDS grievance and a freer-than-baseline press takes
		# a little away. Read by no opinion issue, which is what puts it with the other
		# two independent terms rather than with hardship -- section 5's "second approval
		# number" warning is answered by a fourth term the approval figure cannot see, on
		# exactly the argument the third one was added on.
		- K.PRESS_UNREST_BETA * float(ns.press_freedom)
		# V1.1e, and it is the FIFTH term and the fourth the approval figure cannot
		# see. Legitimacy is willingness to accept your rule outside the ballot box,
		# which is why docs/media-model.md sent press freedom's legitimacy cost here
		# rather than inventing a quantity -- and a government that captures its own
		# courts is doing the same thing to the same two blocs. Judiciary.unrest_load()
		# carries the sign and reads the DEVIATION from the nation's own start, so a
		# country whose courts have always been weak is not permanently rioting about
		# it and this term is exactly 0.0 for all ten at new game.
		+ Judiciary.unrest_load(ns),
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
		# V1.5d. The UNFRAMED gain, stated explicitly, and this line is the session's
		# real anti-double-count. Passing ns.framing_gain here would let press_freedom
		# reach the grievance target twice -- once through this term and once through
		# media_constants.PRESS_UNREST_BETA -- which is the same act, the same landing
		# site and the same units, the first-kind double count law.gd's three refusals
		# are all examples of. It is refused in the SIGNATURE rather than at load,
		# because it is one register reaching one number twice through code and not two
		# keys on one law; see Opinion.salience_weights(). The distinction is also the
		# right one on the merits: framing is about what the electorate NOTICES, and
		# this term is about what two rows of it actually SUFFER.
		var weights: Dictionary = Opinion.salience_weights(
			OpinionK.BLOC_SALIENCE_BASE[bloc], sat, OpinionK.SALIENCE_GAIN
		)
		var row := 0.0
		for issue in weights:
			row += float(weights[issue]) * float(sat.get(issue, 0.0))
		total += size * row
		share_sum += size
	if share_sum <= 0.0:
		return 0.0
	return -total / share_sum


## How far this nation's Gini index has drifted since the game began, in points —
## the measured drift plus what the player's own tax policy has done to it.
##
## THE DECLARED STOPGAP IS DISCHARGED HERE, AT V1.6d, AND THE TRIPWIRE FIRED AS
## DESIGNED. V1.5c shipped this as a pure read of two fields Demography writes, with
## docs/tiers/v1.md section 6 named as the real writer, and wrote
## tests/test_unrest.gd's insensitivity assertion so that it would go RED the day
## section 6 landed rather than being edited quietly. It was watched going red before
## it was rewritten.
##
## WHAT CHANGED IS A SECOND READ, NOT A SECOND WRITER, and that is the V1.6
## decomposition's own call 4 — which asked for a second FIELD, and did not need one.
## Tax.gini_policy_offset() is a pure function of `tax_progressivity` and two tax rates
## the save already carries, so:
##
##   - Demography.tick_month() is still the ONLY writer of `gini_index`, and both this
##     file's and test_demography.gd's read-the-file checks pass unchanged;
##   - there is no accumulator, no field and no save entry on either side of the sum;
##   - the effective index stays Defence.allies()' shape, which is what V1.5c chose it
##     for and what the discharge had to preserve rather than spend.
##
## TWO THIRDS OF THE OLD ASSERTION SURVIVES, and the surviving two thirds is the
## interesting half. Section 6's instruments are brackets, capital gains and wealth;
## the CORPORATE rate is not on that list, and neither is a state holding or a sector
## burden. So the index is still exactly blind to all three, and the rewritten test
## asserts that blindness alongside the new sensitivity rather than dropping it.
static func inequality_deviation(ns) -> float:
	return (
		float(ns.gini_index) + Tax.gini_policy_offset(ns) - float(ns.start_gini_index)
	)


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
##
## V2.6b1 SITED THIS PRICE, MEASURED IT, AND DELETED THE SITING TERM. Unchanged from
## V1.5c, and the deletion is the session's result rather than a retreat from it.
##
## The design was that a demonstration in a more concentrated place is more visible
## and costs the president more, through a factor on this load with one tuned
## constant behind it. Two clauses were fixed before the sweep, both model criteria:
## the sited load must differ from the unsited one by at least ONE DIGIT OF THE PANEL
## THAT PRINTS IT (src/ui/polling_panel.gd formats a bloc row as "%.0f%%", so one
## point), and it must stay below what settling the strike is worth, because a model
## in which WHERE the strike is matters more than WHETHER YOU SETTLED IT is not one
## to defend.
##
## THE INTERVAL IS EMPTY, AND THE TWO CLAUSES ARE INCONSISTENT RATHER THAN BADLY
## TUNED. Measured on FRA austerity over sixty months (tools/siting_probe.gd table
## (d)): the WHOLE unrest opinion price is worth 2.9825 points on the worst bloc row,
## one settlement law is worth 0.4450, and clause (i) crosses at beta ~3.1 while
## clause (ii) is crossed at ~1.3. So a readable siting term has to be a THIRD of the
## entire unrest price and 2.25 TIMES what settling is worth. No candidate on any of
## three grids passes both.
##
## The reason is V1.5c's own finding read from the other side: the opinion model
## prices rates and ratios, the whole unrest channel only just clears the poll floor
## at three points, and a MODULATION of a three-point channel is a fraction of a
## fraction. That is docs/cycle-model.md's legibility floor in a fourth place, and
## the response is V1.5b's deletion of DEPENDENCY_ELASTICITY["health"] rather than
## tuning against an arithmetic impossibility -- the kill switch was declared before
## the sweep and it is honoured.
##
## SO src/sim/siting_constants.gd DOES NOT EXIST. It was written, the band was run
## against it, and it was deleted rather than left at an unused 0.0 -- V1.3e's
## treatment of AGREEMENT_ACCEPT_MIN and SUPPORT_SIGMA, because a tuned constant
## nothing reads is a number a later session finds and reasons from. V2.6b1 ships NO
## TUNED CONSTANT AT ALL, which is projects_constants.gd's and pledges_constants.gd's
## position a third time.
##
## What survives is the OUTPUT price, act_impulse() below, which needed no constant
## and therefore no band: it is a definitional correction rather than a coefficient.
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


# --- The place ------------------------------------------------------------------

## Each named region's LIVE share of the nation's population -- V2.6a's register,
## read through Migration rather than off the field.
##
## THE FIRST VERSION OF THIS COMMENT CLAIMED THIS FILE NAMES NO REGISTER FIELD AT
## ALL, AND THAT WAS FALSE: site_report() below reads `region.id`,
## `region.region_name`, `region.cities` and a city's own id and name to put a mark
## on a map. What it does not touch is the ECONOMIC field contract --
## `.gdp_share`, `unemployment_rel`, `sector_mix`, `region_gdp_eur_bn` -- which is
## what tests/test_geography.gd guards and why V2.5 can still be the register's one
## simulating reader. Every regional QUANTITY here comes back through a Regions
## function; only navigation is read directly. The distinction is the check's, and
## it is written down because the loose version of the claim was wrong.
##
## These are the WEIGHTS. A demonstration is people, so how many are there is the
## first half of where it happens.
static func site_weights(ns, region_list: Array) -> Dictionary:
	var out: Dictionary = {}
	for region in region_list:
		out[region.id] = Migration.region_share(ns, region.id)
	return out


## The SIGNAL: how far each region's unemployment stands above its nation's own
## share-weighted mean, and absent for every region at or below it.
##
## Passed to Siting.excess() as the raw rate rather than as a ratio to the national
## figure, because excess() subtracts its own weighted mean and a uniform rescale
## changes neither the arg-max nor the margin. One operation fewer and the same
## answer, which is worth a sentence because the model doc calls it "relative
## regional unemployment" and a reader would otherwise look for the division.
##
## SCORED ON THE DEVIATION AND NOT ON THE LEVEL, and that is the session's sharpest
## content call rather than a detail. On the level the demonstration goes wherever
## the most people are, which is a fact about population: France's site would be
## Ile-de-France for ever. On the deviation it goes to Hauts-de-France, which is
## where France's unemployment actually is -- and because a high-unemployment region
## is systematically a poor and small one, the two prices built on it come out BELOW
## one rather than above. The choice flips the sign of the whole session's price and
## both tables are in docs/siting-model.md section 3.
##
## RETURNS {} FOR BRITAIN, which is a real answer and not a gap: every British
## region carries unemployment_rel exactly 1.0 (V2.5 section 8's ITL1 index proxy),
## so nothing is above its own mean. Luxembourg returns {} for a different reason --
## one region cannot differ from itself. Both nations are then unpriced by
## arithmetic, because Siting.concentration() reads 1.0 on an empty site.
static func site_signal(ns, region_list: Array) -> Dictionary:
	var rates: Dictionary = {}
	for region in region_list:
		rates[region.id] = Regions.unemployment_pct(ns, region_list, region.id)
	return Siting.excess(rates, site_weights(ns, region_list))


## Where this month's grievance is, and what it is worth -- one call, because the
## opinion load and the act impulse must read the SAME site in the same month and
## computing it twice is two answers to one question waiting to disagree.
##
## Keys: region_id, region_name, city_id, city_name, concentration, output_index,
## margin. A nation with no register or no site comes back with empty strings and
## BOTH factors at exactly 1.0, so every caller can multiply unconditionally.
##
## The city is the site region's largest by LIVE city share -- V2.6a's second
## register, and the only reason this function touches it: a region has no single
## point and a city carries a lonlat, so the mark on the map has somewhere to go.
## It moves with the people, which is the one part of the site that genuinely does
## (see margin below).
##
## `margin` rides the report so the probe and the panel read the same number the
## price does. It is the degeneracy detector: measured at 0.781 for France, meaning
## the runner-up would need to gain 78 % to take the place, against a migration
## budget worth about 9 % over fourteen years. THE REGION DOES NOT MOVE. Recorded
## here beside the code rather than only in the doc, because V2.6b's own ROADMAP row
## claimed it did.
static func site_report(ns, region_list: Array) -> Dictionary:
	var empty := {
		"region_id": "", "region_name": "", "city_id": "", "city_name": "",
		"concentration": 1.0, "output_index": 1.0, "margin": 0.0,
	}
	if region_list.is_empty():
		return empty

	var weights: Dictionary = site_weights(ns, region_list)
	var signals: Dictionary = site_signal(ns, region_list)
	var region_id: String = Siting.site(weights, signals)
	if region_id == "":
		return empty

	# Normalised over the named regions, so the share-weighted mean multiplier is
	# EXACTLY 1.0 and this factor cannot silently rescale UNREST_IMPULSE_SCALE.
	var raw: Dictionary = {}
	for region in region_list:
		raw[region.id] = Regions.gdp_per_head_index(
			ns, region_list, region.id, Migration.region_share(ns, region.id)
		)
	var indexed: Dictionary = Siting.normalised(raw, weights)

	var out := empty.duplicate()
	out["region_id"] = region_id
	out["concentration"] = Siting.concentration(weights, region_id)
	out["output_index"] = float(indexed.get(region_id, 1.0))
	out["margin"] = Siting.margin(weights, signals)
	for region in region_list:
		if region.id != region_id:
			continue
		out["region_name"] = String(region.region_name)
		var best_share: float = -1.0
		for city in region.cities:
			var share: float = Migration.city_share(ns, city.id)
			if share > best_share:
				best_share = share
				out["city_id"] = String(city.id)
				out["city_name"] = String(city.city_name)
		break
	return out


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
##
## V2.6b1 MULTIPLIES BY THE SITE'S OUTPUT PER HEAD, and this price needed no constant
## at all: V2.5 already ships Regions.gdp_per_head_index() normalised to 1.0 at the
## national average, and Siting.normalised() makes the share-weighted mean of the
## multiplier exactly 1.0 rather than approximately so. So the EXPECTED price is
## unchanged and only the per-nation variation is new -- UNREST_IMPULSE_SCALE keeps
## the calibration V1.5c measured for it, which is the whole reason the factor is
## normalised rather than raw.
##
## The same required-argument rule as opinion_load(): 1.0 means an average place or
## no place, and a caller says so rather than omitting it.
##
## Measured, and the sign is the finding: the site is where the EXCESS unemployment
## is, which is systematically a POOR region, so the index is 0.759 for France and
## 0.644 for Italy. A strike sited where the grievance is costs the country LESS
## output than the same strike in its capital would. See docs/siting-model.md
## section 3 -- the choice of site form flips the sign of this price.
static func act_impulse(unrest: float, output_index: float) -> float:
	return -K.UNREST_IMPULSE_SCALE * clampf(unrest / K.UNREST_MAX, 0.0, 1.0) * output_index


static func _tick_nation(state, ns) -> void:
	ns.unrest_pct = unrest_step(float(ns.unrest_pct), unrest_target(ns))

	# ONE site read per nation-month, shared by both prices. The opinion load is a
	# STOCK read and fires every month; the impulse is an ACT read and fires on a
	# cooldown -- so computing the site here rather than inside the act branch is
	# what guarantees the two price the same place in the month they coincide.
	var report: Dictionary = site_report(ns, state.regions.get(ns.id, []))
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
		float(ns.unrest_impulse_pct) + act_impulse(float(ns.unrest_pct), float(report["output_index"])),
		-K.UNREST_IMPULSE_MAX_PCT, K.UNREST_IMPULSE_MAX_PCT
	)
	ns.unrest_cooldown_months = K.UNREST_COOLDOWN_MONTHS

	# A display record and not a memory. src/sim/ never reads this back — the grievance
	# number IS the memory, which is V1.3e's *no grievance ledger* property arriving in
	# the one session that could have been tempted to build the ledger literally.
	#
	# V2.6b1 adds the place, and it is written onto the RECORD rather than looked up
	# later because a past act's site cannot be re-derived once the shares have moved.
	# The three new keys earn no SAVE_VERSION bump: absent, they read as "no place",
	# which is the truth about every version-29 save because those games could not
	# site one -- `measures`' case at V1.3c, a seventh time. They stay DISPLAY only,
	# and tests/test_unrest.gd's read-the-directory assertion is what keeps them so:
	# GameState.duplicate_state() does not carry this array, so a sim-side reader
	# would make Budget.project() and the live tick disagree in silence.
	state.unrest_acts.append({
		"nation_id": ns.id,
		"year": int(state.year),
		"month": int(state.month),
		"label": act_label(float(ns.unrest_pct)),
		"unrest_pct": float(ns.unrest_pct),
		"region_id": String(report["region_id"]),
		"region_name": String(report["region_name"]),
		"city_id": String(report["city_id"]),
		"city_name": String(report["city_name"]),
	})
	while state.unrest_acts.size() > K.ACTS_KEPT:
		state.unrest_acts.remove_at(0)
