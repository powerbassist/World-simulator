extends RefCounted

## Monthly opinion update: per-issue satisfaction, per-bloc salience, per-bloc
## approval with inertia, and the weighted roll-up.
##
## Runs *after* Economy.tick_month and Budget.tick_month, so it reacts to figures
## that have already settled this month rather than to last month's. See the tick
## order in docs/economy-model.md.
##
## No engine access, no node references, no signals, and — critically — no
## randomness. Polling noise is a display concern and lives in
## src/ui/poll_noise.gd; nothing in this file knows it exists. An RNG call here
## would break tests/test_budget.gd, which asserts the budget projection equals
## reality to 1e-9 by running the real tick functions on a deep copy.
##
## The model, and the justification for every constant, is docs/opinion-model.md.

const K = preload("res://src/sim/opinion_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
## V1.5a. Read-only, and one-way: society.gd does not preload this file, so the
## quality stock cannot see the opinion it moves. That is what keeps the double count
## resolvable in one place -- the block above.
const Society = preload("res://src/sim/society.gd")
const SK = preload("res://src/sim/society_constants.gd")
## For BLOC_OFFSET_MIN/MAX only -- init_nation() writes bloc_offset for a
## start scenario, and must respect the same bounds a law is held to.
const LK = preload("res://src/sim/legislature_constants.gd")


## Set every bloc to the neutral baseline and record the starting deficit that
## the public_finances issue is measured against.
##
## Runs for all ten nations even though only the player's ticks, so the state
## shape is uniform and duplicate_state() has nothing conditional to copy.
##
## `bloc_approval_override` is a start scenario's authored starting approval,
## {bloc key -> approval}, applied over the neutral baseline below. Partial: a
## bloc the scenario does not name stays neutral. Empty for a standard start.
## See docs/scenario-model.md.
static func init_nation(ns, bloc_approval_override: Dictionary = {}) -> void:
	ns.start_deficit_pct_gdp = ns.deficit_pct_gdp
	# The europe issue's reference, captured here beside the deficit's and for the
	# identical reason. Zero at new-game because nothing is in force yet -- written
	# rather than assumed, so a later session that lets a scenario author a rule
	# already binding gets the right answer without coming back here.
	ns.start_bloc_burden = ns.bloc_burden

	ns.bloc_approval = {}
	for bloc in K.BLOC_KEYS:
		ns.bloc_approval[bloc] = K.APPROVAL_NEUTRAL

	for bloc in bloc_approval_override.keys():
		var authored: float = float(bloc_approval_override[bloc])
		ns.bloc_approval[bloc] = authored

		# The authored figure has to set the EQUILIBRIUM as well as the starting
		# position, or it is not a difficulty lever at all. Every satisfaction
		# term is a delta against the nation's own starting figure, so a fresh
		# game's target is exactly APPROVAL_NEUTRAL -- an authored 38 with an
		# unshifted target would decay back to 50 on INERTIA_RATE's ~2.4-month
		# half-life and be gone inside a game year, while debt and seats persist.
		# Measured before it was built: see docs/scenario-model.md.
		#
		# Routed through bloc_offset because that IS the model's channel for
		# an opinion effect with no budget line behind it -- Government.
		# penalise_blocs() already uses it for a fallen government, which is no
		# more a law than a scenario is. Inverting _tick_nation()'s own target
		# formula gives the offset that makes `authored` the resting point; the
		# clamp is what bounds the sustainable band to [10, 90], the same band
		# APPROVAL_SPAN gives a pure satisfaction score.
		ns.bloc_offset[bloc] = clampf(
			(authored - K.APPROVAL_NEUTRAL) / K.APPROVAL_SPAN,
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX
		)

	ns.overall_approval_pct = K.APPROVAL_NEUTRAL

	# Every satisfaction is zero at new-game, so this leaves approval exactly at
	# neutral and exists only to populate issue_salience -- except under a
	# scenario, where the offset above holds the target at the authored figure
	# and this rolls the blocs up into overall_approval_pct, which is why the
	# roll-up is not authored directly.
	_tick_nation(ns)


## Gated on has_budget, not on the player id — the same flag Budget.tick_month
## uses. A second playable nation is then a data change, not a change here.
static func tick_month(state) -> void:
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		_tick_nation(ns)


static func _tick_nation(ns) -> void:
	var sat := issue_satisfaction(ns)

	var national := {}
	for issue in K.ISSUE_KEYS:
		national[issue] = 0.0

	for bloc in K.BLOC_KEYS:
		var weights := salience_weights(K.BLOC_SALIENCE_BASE[bloc], sat)

		var score := 0.0
		for issue in weights:
			score += float(weights[issue]) * float(sat.get(issue, 0.0))

		# law_offset is a law's direct opinion effect -- for laws with no budget
		# footprint and so no issue to be salient about. Combined with `score`
		# and clamped before scaling, so the target stays inside the same
		# [10, 90] bound a pure satisfaction score would produce on its own.
		var law_offset: float = float(ns.bloc_offset.get(bloc, 0.0))
		# V1.5c. Grievance, charged at the same site and clamped with it for the same
		# reason. UNIFORM across the six blocs: a general strike inconveniences
		# everybody, and an authored per-bloc row would be a table with no measurement
		# behind it. Which blocs GENERATE the grievance is a different question, and
		# unrest_constants.UNREST_BLOCS answers it out of BLOC_SALIENCE_BASE.
		#
		# Here rather than inside issue_satisfaction(), and that placement is the one
		# thing about this term worth being careful about. Subtracted from `jobs` --
		# deployment_opinion_load's shape, and the obvious move -- it would land inside
		# the dictionary Unrest.hardship() reads, closing a same-quantity loop through
		# the salience simplex that nothing bounds. This site is outside that read by
		# construction. See unrest_constants.UNREST_OPINION_SCALE for why the term
		# exists at all: an output-only price was designed, measured, and found unable
		# to reach a voter in a model that prices rates.
		var target: float = K.APPROVAL_NEUTRAL + K.APPROVAL_SPAN * clampf(
			score + law_offset - float(ns.unrest_opinion_load), -1.0, 1.0
		)
		var approval := float(ns.bloc_approval.get(bloc, K.APPROVAL_NEUTRAL))
		approval += (target - approval) * K.INERTIA_RATE
		ns.bloc_approval[bloc] = clampf(approval, K.APPROVAL_MIN, K.APPROVAL_MAX)

		var size := float(K.BLOC_SIZE[bloc])
		for issue in weights:
			national[issue] = float(national[issue]) + size * float(weights[issue])

	ns.issue_salience = national
	ns.overall_approval_pct = overall_approval(ns)


## How each issue stands, as a satisfaction in [-1, +1]. Every one is a delta
## against the nation's own starting figure, which is why a fresh game sits at
## exactly neutral with no calibration term.
static func issue_satisfaction(ns) -> Dictionary:
	var sat := {}

	sat["jobs"] = _scaled(ns.start_unemployment_pct - ns.unemployment_pct, K.JOBS_SCALE_PP)
	sat["growth"] = _scaled(ns.growth_annual_pct - ns.trend_annual_pct, K.GROWTH_SCALE_PP)

	for key in C.TAX_KEYS:
		var d_rate: float = (
			float(ns.tax_rates_pct.get(key, 0.0))
			- float(ns.start_tax_rates_pct.get(key, 0.0))
		)
		sat["tax_%s" % key] = _scaled(-d_rate, K.TAX_SCALE_PP)

	for key in C.SPENDING_KEYS:
		var d_spend: float = (
			float(ns.spending_pct_gdp.get(key, 0.0))
			- float(ns.start_spending_pct_gdp.get(key, 0.0))
		)
		# Effectiveness multiplies the DELTA, not the level -- see
		# docs/cabinet-model.md. A player who never touches this spending line
		# is untouched by the whole cabinet system, the same surgical property
		# the public_finances retune above argues for.
		sat[key] = _scaled(d_spend * Cabinet.effectiveness(ns, key), K.SPEND_SCALE_PP)

	# V1.3g. The deployments come off the `defence` issue, and the six-way split the
	# tier bullet asks for needs no new machinery: BLOC_SALIENCE_BASE already weights
	# `defence` differently for every bloc.
	#
	# Subtracted AFTER Cabinet.effectiveness() rather than multiplied through it, and
	# that is a model call rather than an ordering detail. Effectiveness is a claim
	# about how well a CHANGE OF POLICY is delivered; a deployment is a fact on the
	# ground. Run through it, a competent defence minister would quietly cancel the
	# whole price this session exists to charge.
	#
	# Re-clamped because _scaled() clamps its own argument and this arrives after it.
	sat["defence"] = clampf(sat["defence"] - ns.deployment_opinion_load, -1.0, 1.0)

	# V1.5a. The delivery half of a spending line, ADDED to the delta half above
	# rather than replacing or multiplying it — the row asks for "quality as an
	# outcome of spending, feeding back into opinion" and `health` was already an
	# opinion issue, so the double count had to be resolved rather than avoided.
	# Three of the four resolutions were rejected on this project's own record:
	#
	#   REPLACE  — this file's own APPROVAL_NEUTRAL comment commits to no lag and
	#              warns against "two lags in series", and a stock at
	#              QUALITY_CONVERGENCE has a ~34-month half-life. Replacing builds
	#              precisely the thing that comment exists to forbid.
	#   MULTIPLY — that is Cabinet.effectiveness() a second time on one expression,
	#              and two multipliers on one delta are unattributable: the player
	#              cannot tell an incompetent minister from a decayed service, and
	#              elections.gd's attribution has one slot per issue.
	#   A 13th   — `spending.health` writes both keys, so they are collinear and the
	#   ISSUE_KEY  salience simplex merely re-splits one issue's weight. That is the
	#              case V1.4c answered NO for, on the same test.
	#
	# So: additive and post-effectiveness, which is deployment_opinion_load's shape
	# directly above, and the argument transfers verbatim — the delta is a claim about
	# how well a CHANGE OF POLICY is delivered, quality is a FACT ON THE GROUND, and
	# running it through effectiveness would let a competent minister cancel it.
	#
	# The two then price DIFFERENT TIMES rather than the same thing twice: the delta
	# prices the announcement, the stock prices the delivery. Fast in, slow out.
	#
	# Exactly 0.0 at new game for all ten nations, because Society.init_nation()
	# captures the reference at the equilibrium — so this term is silent in every game
	# until the player moves a spending line or passes a `society` law.
	#
	# Loops QUALITY_KEYS rather than SPENDING_KEYS, so a line without a stock costs
	# nothing here and V1.5b adds `pensions` without touching this file.
	for key in SK.QUALITY_KEYS:
		var q: float = _scaled(Society.quality_deviation(ns, key), K.QUALITY_SCALE_PP)
		sat[key] = clampf(float(sat.get(key, 0.0)) + q, -1.0, 1.0)

	# Measured on the deficit, not the debt ratio. Debt walks upward every month
	# by construction (r > g), so a debt-level term would make every bloc slowly
	# unhappy no matter what the player did. The deficit answers to the player.
	sat["public_finances"] = _scaled(
		-(ns.deficit_pct_gdp - ns.start_deficit_pct_gdp), K.DEFICIT_SCALE_PP
	)

	# V1.3d. A delta against the nation's own starting burden, exactly like every
	# term above -- France may begin in real breach of a deficit rule and that is
	# politically free until the player moves it, the same way its real
	# 4.7%-of-GDP starting deficit is.
	#
	# ONE-SIGNED, and that is a property of the model rather than a simplification:
	# this satisfaction reaches all six blocs with the same sign, because nothing in
	# _tick_nation() lets a bloc weight an issue negatively. Europe divides the
	# country anyway, through the rows that were already here -- pensioners and
	# rural weight `growth` at nothing, so they take the sovereignty cost without
	# the single market's upside. See opinion_constants.BLOC_SALIENCE_BASE.
	#
	# Zero for a non-member, zero with nothing in force, and zero for a member that
	# COMPLIES. A complying player pays for the bloc in the policy they could not
	# run, and that shows up on the spending lines they had to cut -- which is the
	# same surgical property the public_finances row above is praised for.
	sat["europe"] = _scaled(
		-(ns.bloc_burden - ns.start_bloc_burden), K.EUROPE_SCALE
	)

	return sat


## Base weights amplified by bad news, then renormalised. The renormalisation is
## the whole stability argument: the result is a point on the simplex, so no
## amount of bad news makes the weights grow.
static func salience_weights(base: Dictionary, sat: Dictionary) -> Dictionary:
	var weights := {}
	var total := 0.0
	for issue in base:
		var severity: float = clampf(-float(sat.get(issue, 0.0)), 0.0, 1.0)
		var w: float = float(base[issue]) * (1.0 + K.SALIENCE_GAIN * severity)
		weights[issue] = w
		total += w

	if total <= 0.0:
		return weights

	for issue in weights:
		weights[issue] = float(weights[issue]) / total
	return weights


## The headline number: bloc approval weighted by bloc size. Sizes sum to 1.0, so
## this is an average rather than an arbitrary index.
static func overall_approval(ns) -> float:
	var total := 0.0
	for bloc in K.BLOC_KEYS:
		total += float(K.BLOC_SIZE[bloc]) * float(ns.bloc_approval.get(bloc, 0.0))
	return total


## Issues ordered by how much the electorate currently cares, most first.
static func top_issues(ns, count: int) -> Array:
	var ordered: Array = []
	for issue in K.ISSUE_KEYS:
		ordered.append([issue, float(ns.issue_salience.get(issue, 0.0))])
	ordered.sort_custom(func(a, b): return a[1] > b[1])
	return ordered.slice(0, count)


## The player nation's opinion figures. Merged into the history entry alongside
## Budget.snapshot() by the caller — deliberately kept out of Budget.snapshot()
## itself, because Budget.project() does not run opinion and folding these in
## would break the projection-equals-reality test.
static func snapshot(state) -> Dictionary:
	var ns = state.player()
	if ns == null:
		return {}
	return {
		"overall_approval_pct": ns.overall_approval_pct,
		"bloc_approval": ns.bloc_approval.duplicate(true),
		"issue_salience": ns.issue_salience.duplicate(true),
	}


static func _scaled(delta: float, scale: float) -> float:
	if scale <= 0.0:
		return 0.0
	return clampf(delta / scale, -1.0, 1.0)
