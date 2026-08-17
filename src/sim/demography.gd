extends RefCounted

## The demography layer -- V1.5b, the second session of the V1.5 block. An age
## structure that drifts at a measured rate, the dependency ratio that falls out of
## it, and the migration lever that is the only thing able to close it. The model and
## every constant's rationale is docs/demography-model.md;
## src/sim/demography_constants.gd is the values.
##
## THE MOTION IS MEASURED, NOT MODELLED, and that is the session's central call.
## docs/tiers/v1.md section 5 asks for "ageing driving pension and health costs on an
## unavoidable curve", and the obvious build is a cohort machine: births from
## fertility, maturation, retirement, deaths from life expectancy. It was designed and
## then cut, on evidence rather than on taste. Fertility and life expectancy are
## INPUTS to a demographic projection; the 65+ share is its OUTPUT, and the World Bank
## publishes the output over a ten-year window tools/import_data.py was already
## downloading. A uniform 15-64 bucket also gets the roster's most distinctive nation
## backwards -- it predicts Luxembourg ages fastest of the ten, and measured,
## Luxembourg ages slowest (+0.142 points per year against France's +0.366).
##
## So this file carries EXACTLY ONE TUNED CONSTANT, the migration lever's, and the
## drift needs no convergence rate, no band and no sweep.
##
## NOT capability_target()/capability_step()'s shape, deliberately, and the difference
## is worth stating because three other stocks in this project do use it. Those
## converge on a target the player sets; a population does not converge on anything a
## president decides. The drift is linear at its own measured rate and bounded by a
## guard rail whose slack is measured -- which is the honest description, and forcing
## the precedent here would have added a constant to buy a resemblance.
##
## Takes no loader, the discipline defence.gd, trade.gd, coercion.gd and society.gd all
## hold to. Preloads its own constants AND NOTHING ELSE from src/sim/ -- a leaf, and
## the strictest one in the project: society.gd preloads cabinet.gd, this preloads
## nobody. tests/test_demography.gd reads this file and fails if that changes, the
## read-the-file idiom test_society.gd, test_people.gd and test_calendar.gd all use.
##
## WRITES ns.young_share, ns.old_share and (V1.5c) ns.gini_index, and nothing else.
## `migration_stance` has exactly one writer in the project and it is
## Legislature.apply(); this file only ever reads it. That is `corruption`'s discipline
## at V1.5a and `regulation_burden`'s at V1.4b, and tests/test_demography.gd asserts it
## by reading the file.
##
## V1.5c PUT THE GINI DRIFT HERE RATHER THAN IN unrest.gd, and the split is V1.5b's own
## one made again: this layer owns measured facts about the POPULATION that drift on
## their own, and the session that prices a fact owns the price rather than the fact.
## Demography owns the dependency ratio and Society owns the denominator it becomes;
## Demography owns the Gini drift and Unrest owns what it costs. It also keeps
## unrest.gd free of any accumulator of its own, which is what its own test asserts.

const K = preload("res://src/sim/demography_constants.gd")


## Seeds the two shares from imported content and captures the references every
## deviation is measured against.
##
## The starting structure IS the equilibrium in the sense that matters here: it is
## measured, so it is what that country's age structure actually is on the day the
## game starts, and dependency_factor() below reads EXACTLY 1.0 for all ten nations
## at new game. That is what lets the whole register go live with no figure moving
## until the clock runs -- defence.gd's init_nation() argument and society.gd's,
## reached by a different route, because those two derive a stock from a spending line
## and this one reads a fact off the content.
##
## start_young_share and start_old_share are captured HERE rather than derived later,
## the treatment start_deficit_pct_gdp, start_bloc_burden and start_service_quality
## already get. The reference cannot then drift by its own baseline moving.
##
## Runs for all ten nations even though only the player's opinion ticks, so the state
## shape is uniform and duplicate_state() has nothing conditional to copy -- the reason
## opinion.gd's own init_nation() gives.
static func init_nation(ns, nation) -> void:
	var cohorts: Dictionary = nation.cohorts
	ns.young_share = clampf(float(cohorts.get("young_pct", 0.0)) / 100.0, K.SHARE_MIN, K.SHARE_MAX)
	ns.old_share = clampf(float(cohorts.get("old_pct", 0.0)) / 100.0, K.SHARE_MIN, K.SHARE_MAX)
	ns.start_young_share = ns.young_share
	ns.start_old_share = ns.old_share

	# Static per-nation facts copied onto NationState the way `eu_member` and
	# `neighbours` are, so the tick and Budget.project() need no loader. They are
	# content and round-trip through data/nations/, which is why they earn no
	# SAVE_VERSION bump -- see tests/test_save_load.gd.
	ns.young_share_per_yr = float(cohorts.get("young_pct_per_yr", 0.0)) / 100.0
	ns.old_share_per_yr = float(cohorts.get("old_pct_per_yr", 0.0)) / 100.0
	ns.participation_share = float(cohorts.get("participation_pct", 0.0)) / 100.0
	ns.pop_growth_pct = float(cohorts.get("pop_growth_pct", 0.0))

	# V1.5c. The same treatment one block down: a measured level, a measured slope, and
	# the reference the deviation is taken against captured here so it cannot drift by
	# its own baseline moving. The slope is content and signed -- six of the ten nations
	# are growing more equal and four less -- so a one-sided model would be wrong about
	# most of the roster. Unrest.inequality_deviation() reads exactly these two.
	var inequality: Dictionary = nation.inequality
	ns.gini_index = float(inequality.get("gini_index", 0.0))
	ns.start_gini_index = ns.gini_index
	ns.gini_index_per_yr = float(inequality.get("gini_index_per_yr", 0.0))


## One month of drift, for all ten nations.
##
## Runs immediately BEFORE Society.tick_month() in src/ui/main.gd's order, and
## Budget.project() runs it in the same slot: the quality stock divides by this
## layer's dependency factor, so demography must have settled before quality reads it.
##
## Both sit after Opinion, which is society.gd's argument inherited whole -- quality
## feeds an opinion issue, opinion feeds overall_approval_pct, and that is an entry in
## legislature_constants.PRECONDITION_FIELDS, so approval -> which laws are available
## -> a `society` law -> migration -> shares -> quality is a closed loop that the
## one-month lag breaks structurally rather than by being careful.
static func tick_month(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		_tick_nation(state.nations[id])


# --- The structure ------------------------------------------------------------

## The 15-64 share, DERIVED as the residual and never stored.
##
## That is _apply_growth_to_sectors()'s discipline lifted verbatim -- it keeps sector
## output summing to GDP exactly with no reconciliation -- and here it means the three
## shares sum to 1.0 by construction, so a conservation bug is structurally impossible
## rather than prevented by a check somebody has to remember to run. It is also why
## data/nations/ authors two shares and not three: a stored working share would be a
## second answer to a question these two already answer.
##
## NO CLAMP HERE, and that is load-bearing rather than an omission. A maxf() against
## WORKING_SHARE_MIN was the first version and tests/test_demography.gd caught it: the
## moment the floor binds, `young + old + working` stops summing to 1.0 and the whole
## structural argument above becomes false exactly when the numbers get extreme. The
## floor is enforced on the PAIR in _tick_nation() instead, where it can hold the sum
## by construction.
static func working_share(ns) -> float:
	return 1.0 - float(ns.young_share) - float(ns.old_share)


## Old-age dependency: retired people per person of working age. The statistic this
## session ships, and the one docs/tiers/v1.md section 5 needs in order for "ageing
## driving pension and health costs" to mean anything, because spending_pct_gdp is a
## player-set RATE and a rate cannot be driven by anything.
##
## A FUNCTION AND NOT A CACHED FIELD -- GameState.debt_to_gdp_pct()'s shape. A stored
## ratio is a second answer to a question two live shares already answer, and it would
## need a writer, a serialised entry and a tick of its own to stay in step with them.
static func dependency_ratio(ns) -> float:
	var working: float = working_share(ns)
	# Guarded at the point of DIVISION rather than by clamping working_share() itself,
	# which is the distinction the sum-to-1.0 property rests on: the residual must stay
	# the honest residual for every reader, and only the two callers that divide by it
	# need a floor. _tick_nation() keeps it well above this in play and src/core/nation.gd
	# refuses content that starts near it -- but from_dict() bypasses that validator, so
	# a hand-edited save is the reachable path to a zero here.
	if working <= 0.0:
		return 0.0
	return float(ns.old_share) / working


## The nation's current dependency against its OWN starting value. Exactly 1.0 at new
## game for all ten, so it is inert until the clock runs.
##
## This is the "required rate the set rate is measured against" the decomposition
## asked for, and it arrives as a DENOMINATOR rather than as a new quantity: a nation's
## own starting spending is by definition adequate for its own starting dependency, so
## the required rate scales with the ratio and nothing has to be authored. There is no
## per-capita benefit, no beneficiary count and no cost side anywhere in src/sim/, and
## this adds none of the three.
##
## Everything that prices ageing reads it through here, so the measured-against-its-own
## -start anchoring cannot be bypassed by a caller dividing by something else. That is
## Defence.capability_ratio()'s discipline and Society.quality_deviation()'s.
static func start_dependency_ratio(ns) -> float:
	var start_working: float = 1.0 - float(ns.start_young_share) - float(ns.start_old_share)
	if start_working <= 0.0:
		return 0.0
	return float(ns.start_old_share) / start_working


static func dependency_factor(ns) -> float:
	var start_ratio: float = start_dependency_ratio(ns)
	if start_ratio <= 0.0:
		return 1.0
	return clampf(
		dependency_ratio(ns) / start_ratio,
		K.DEPENDENCY_FACTOR_MIN, K.DEPENDENCY_FACTOR_MAX
	)


## Heads in the labour force. Unemployment is a percent of THIS, and population is a
## head count, so something has to convert between them.
##
## Replaces companies_constants.LABOUR_FORCE_SHARE, one flat 0.45 for all ten. That
## constant's own comment called it "the measured participation-times-working-age
## figure for the roster, not a dial" -- and the claim checks out for France
## (0.7407 x 0.6134 = 0.4543) and fails for Germany (0.7994 x 0.6289 = 0.5027). The
## roster spans Italy 0.423 to the Netherlands 0.551, so one number right for one
## nation becomes two measured facts for all ten, and the session ends with fewer
## constants than it started with.
##
## Now MOVES over a run, which the flat constant could not: an ageing nation's labour
## force shrinks as a share of its population even where the population grows.
static func labour_force(ns) -> float:
	# maxf rather than the caller's own guard: this one is a MULTIPLICAND, so a negative
	# residual would produce a negative labour force and firm_jobs_offset_pct() would
	# flip sign rather than divide by zero -- a wrong answer instead of an obvious one,
	# which is the worse failure of the two.
	return float(ns.population) * maxf(working_share(ns), 0.0) * float(ns.participation_share)


# --- The lever ----------------------------------------------------------------

## Points of dependent share removed per month by the standing migration stance,
## EXACTLY 0.0 for every nation in every game in which no migration law has ever
## passed -- `trade_baseline_by_partner`'s idiom, `firm_impulse_pct`'s and
## `delivery_factor`'s, and what lets this register go live with the shared balance
## regimes moving only through the channel this session means to move.
##
## Migrants arrive of working age. Raising the working share IS lowering the other two,
## because working is the residual, so the stance is applied to `young` and `old` in
## proportion to their current sizes rather than to a fourth quantity. A tightening is
## the negative direction on the same accumulator and pushes both shares up -- V1.4b's
## deregulation argument, and there is no repeal verb here either.
static func migration_drift(ns) -> float:
	return K.MIGRATION_SHARE_BETA * float(ns.migration_stance) / 12.0


static func _tick_nation(ns) -> void:
	var young: float = float(ns.young_share) + float(ns.young_share_per_yr) / 12.0
	var old: float = float(ns.old_share) + float(ns.old_share_per_yr) / 12.0

	# Split pro rata by current size, so a nation with almost no young people does not
	# have migration take its dependent share out of a cohort that is not there.
	var dependent: float = young + old
	var drift: float = migration_drift(ns)
	if drift != 0.0 and dependent > 0.0:
		young -= drift * young / dependent
		old -= drift * old / dependent

	young = clampf(young, K.SHARE_MIN, K.SHARE_MAX)
	old = clampf(old, K.SHARE_MIN, K.SHARE_MAX)

	# The working-share floor is enforced HERE, on the pair, rather than inside
	# working_share() -- and the difference is the one tests/test_demography.gd caught.
	# Clamping the residual at its point of use silently breaks the sum-to-1.0 property
	# the whole residual design rests on, and breaks it precisely in the extreme states
	# where somebody would be relying on it. Scaling the two shares down together
	# preserves both the floor and the sum, and preserves their ratio with it, so the
	# dependency ratio at the floor is still the ratio this nation actually has.
	var dependent_max: float = 1.0 - K.WORKING_SHARE_MIN
	var total: float = young + old
	if total > dependent_max and total > 0.0:
		var scale: float = dependent_max / total
		young *= scale
		old *= scale

	ns.young_share = young
	ns.old_share = old

	# V1.5c. Linear at its own measured rate, for section 2's reason exactly: an index is
	# not a stock and does not compound, and nothing a president decides moves it. The
	# clamp is the index's own definitional range rather than a tuned bound -- it is not
	# reachable from any starting value in the roster over any run length this game has,
	# and it is here because docs/economy-model.md's divergence rule is per-quantity.
	ns.gini_index = clampf(
		float(ns.gini_index) + float(ns.gini_index_per_yr) / 12.0,
		K.GINI_MIN, K.GINI_MAX
	)
