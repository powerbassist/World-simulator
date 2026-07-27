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


## Set every bloc to the neutral baseline and record the starting deficit that
## the public_finances issue is measured against.
##
## Runs for all ten nations even though only the player's ticks, so the state
## shape is uniform and duplicate_state() has nothing conditional to copy.
static func init_nation(ns) -> void:
	ns.start_deficit_pct_gdp = ns.deficit_pct_gdp

	ns.bloc_approval = {}
	for bloc in K.BLOC_KEYS:
		ns.bloc_approval[bloc] = K.APPROVAL_NEUTRAL
	ns.overall_approval_pct = K.APPROVAL_NEUTRAL

	# Every satisfaction is zero at new-game, so this leaves approval exactly at
	# neutral and exists only to populate issue_salience.
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
		var law_offset: float = float(ns.law_bloc_offset.get(bloc, 0.0))
		var target: float = K.APPROVAL_NEUTRAL + K.APPROVAL_SPAN * clampf(score + law_offset, -1.0, 1.0)
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

	# Measured on the deficit, not the debt ratio. Debt walks upward every month
	# by construction (r > g), so a debt-level term would make every bloc slowly
	# unhappy no matter what the player did. The deficit answers to the player.
	sat["public_finances"] = _scaled(
		-(ns.deficit_pct_gdp - ns.start_deficit_pct_gdp), K.DEFICIT_SCALE_PP
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
