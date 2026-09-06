extends SceneTree

## Headless test: godot --headless --script res://tests/test_opinion.gd
## Non-zero exit on any failure.
##
## One test per S5 done-when condition that is about the model: a pension cut
## reaches pensioners and not students, unemployment reaches workers with no
## action aimed at them, the headline is a real weighted average, and nothing
## diverges over ten years of abuse.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const K = preload("res://src/sim/opinion_constants.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_starts_neutral()
	_check_time_in_office_offset_shape()
	_check_honeymoon_reaches_approval()
	_check_pension_cut()
	_check_unemployment_reaches_workers()
	_check_overall_is_weighted()
	_check_nothing_diverges()

	_finish()


## Every issue is a delta against a starting value, so a fresh game must sit on
## exactly the neutral baseline with no calibration term. If that stops being
## true, every threshold in this file is measuring from the wrong place.
func _check_starts_neutral() -> void:
	var state = GameState.new_game(_loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported errors: %s" % [state.errors])
		return

	var ns = state.player()
	for bloc in K.BLOC_KEYS:
		if absf(float(ns.bloc_approval[bloc]) - K.APPROVAL_NEUTRAL) > 1.0e-9:
			_fail("%s starts at %s, expected the neutral %s" % [
				bloc, ns.bloc_approval[bloc], K.APPROVAL_NEUTRAL
			])

	var sat := Opinion.issue_satisfaction(ns)
	for issue in K.ISSUE_KEYS:
		if absf(float(sat[issue])) > 1.0e-9:
			_fail("issue '%s' starts at satisfaction %s, expected 0" % [issue, sat[issue]])

	var size_total := 0.0
	for bloc in K.BLOC_KEYS:
		size_total += float(K.BLOC_SIZE[bloc])
	if absf(size_total - 1.0) > 1.0e-9:
		_fail("bloc sizes sum to %s, expected 1.0 — the roll-up is not an average" % size_total)


## V3.0 discharges the S5 deferral ("No honeymoon bonus — time in office as its
## own drag is V1", opinion_constants.gd). Done-when: the mandate-age offset is
## zero on day one, rises into a honeymoon peak inside the first half-year,
## turns negative as fatigue grows, and caps at FATIGUE_MAX — and an unknown
## mandate age reads exactly zero, so every pre-V3.0 caller keeps its figure.
func _check_time_in_office_offset_shape() -> void:
	if K.time_in_office_offset(0) != 0.0:
		_fail("the mandate offset at month 0 is %s, expected exactly 0 — init pins start approval and the scenario override machinery both read this" % K.time_in_office_offset(0))
	if K.time_in_office_offset(-1) != 0.0:
		_fail("an unknown mandate age must read 0.0, got %s" % K.time_in_office_offset(-1))

	var peak := -INF
	for t in range(1, 13):
		peak = maxf(peak, K.time_in_office_offset(t))
	if peak < 2.0:
		_fail("no honeymoon: the best the mandate offset ever reads is %.2f, expected a rise past +2 within the first year" % peak)
	if K.time_in_office_offset(2) <= K.time_in_office_offset(0):
		_fail("the honeymoon does not rise: offset(2) %.3f vs offset(0) %.3f" % [K.time_in_office_offset(2), K.time_in_office_offset(0)])

	if K.time_in_office_offset(36) >= 0.0:
		_fail("fatigue never dominates: offset(36) is %.3f, expected negative by year three" % K.time_in_office_offset(36))
	if K.time_in_office_offset(120) > -K.FATIGUE_MAX + 0.01 or K.time_in_office_offset(120) < -K.FATIGUE_MAX - 0.01:
		_fail("offset(120) is %.3f, expected settled at the -FATIGUE_MAX cap (%.1f)" % [K.time_in_office_offset(120), -K.FATIGUE_MAX])


## Done-when: a nation four months into its mandate reads approval ABOVE the
## neutral baseline with no governing act at all — the honeymoon is live in the
## real tick order, not only in the formula. Elections owns the counter, so the
## test advances it in Elections' own slot: AFTER opinion, once per month.
func _check_honeymoon_reaches_approval() -> void:
	var state = GameState.new_game(_loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported errors: %s" % [state.errors])
		return
	var ns = state.player()
	for _i in range(4):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		ns.months_in_term += 1  # Elections._tick_nation()'s own increment, later in the order
	if ns.overall_approval_pct <= K.APPROVAL_NEUTRAL + 1.0:
		_fail("a nation four months into its mandate reads %.2f with nothing done — the honeymoon is not reaching approval" % ns.overall_approval_pct)


## Done-when: cutting pension spending drops pensioner approval within three
## months and barely moves student approval.
##
## Compared as magnitudes rather than in absolute terms, because a cut that large
## is also a demand shock: students legitimately feel a little of it through the
## economy, and pretending otherwise would be testing a model nobody built.
func _check_pension_cut() -> void:
	var base := _run(GameState.new_game(_loader, "FRA"), {}, 3)
	var cut := _run(
		GameState.new_game(_loader, "FRA"),
		{"spending_pct_gdp": {"pensions": 11.5}},
		3
	)

	var pensioner_drop := _drop(base, cut, "pensioners")
	var student_drop := _drop(base, cut, "students")

	# V3.0 re-pin: SPEND_SCALE_PP went 3.0 -> 6.0 (the agency sweep's lever —
	# the S10 scales priced a spending line at twice what any B1 band could
	# survive), so the DIRECT channel's response halves by construction while
	# the demand channel students feel is unchanged. The S5 floor of 6.0 was
	# measured at the old scale; the targeted-response claim is re-measured at
	# 3.26 vs 1.72 and pinned with slack rather than re-derived from taste.
	if pensioner_drop < 3.0:
		_fail("pension cut of 3pp of GDP moved pensioner approval by only %.2f points in three months" % pensioner_drop)
	if student_drop > 3.5:
		_fail("pension cut moved student approval by %.2f points; students weight pensions at zero" % student_drop)
	if pensioner_drop < student_drop * 1.5:
		_fail("pension cut hit pensioners %.2f and students %.2f — not the targeted response the model claims" % [
			pensioner_drop, student_drop
		])


## Done-when: rising unemployment drops worker approval without any direct player
## action.
##
## The cut lands on defence and infrastructure, neither of which workers weight at
## all, so the only route to them is the economy: demand falls, unemployment
## rises, the jobs issue turns. This is also the combined-response-time check the
## S4 handoff asked for — it fails if opinion inertia stacked on the economy's own
## lag makes the game stop answering.
func _check_unemployment_reaches_workers() -> void:
	var months := 18
	var base := _run(GameState.new_game(_loader, "FRA"), {}, months)
	var austerity := _run(
		GameState.new_game(_loader, "FRA"),
		{"spending_pct_gdp": {"defence": 0.0, "infrastructure": 0.5}},
		months
	)

	var last: Dictionary = austerity[months - 1]
	var base_last: Dictionary = base[months - 1]

	if last["unemployment_pct"] <= base_last["unemployment_pct"]:
		_fail("austerity did not raise unemployment: %.2f%% vs baseline %.2f%%" % [
			last["unemployment_pct"], base_last["unemployment_pct"]
		])
		return

	var worker_drop := _drop(base, austerity, "workers")
	if worker_drop < 3.0:
		_fail("unemployment rose to %.2f%% but worker approval never moved more than %.2f points in %d months — opinion is too slow to be worth watching" % [
			last["unemployment_pct"], worker_drop, months
		])

	# Workers weight jobs at 0.42 and pensioners at 0.08, so the same shock must
	# land harder on workers. Pensioners may even gain: the deficit shrinks.
	var pensioner_drop := _drop(base, austerity, "pensioners")
	if worker_drop <= pensioner_drop:
		_fail("a jobs shock moved pensioners (%.2f) at least as much as workers (%.2f)" % [
			pensioner_drop, worker_drop
		])


## Done-when: overall approval is a defensible weighted function of bloc approval
## and bloc size.
func _check_overall_is_weighted() -> void:
	var snaps := _run(GameState.new_game(_loader, "FRA"), {"tax_rates_pct": {"vat": 26.0}}, 24)
	for i in snaps.size():
		var snap: Dictionary = snaps[i]
		var expected := 0.0
		for bloc in K.BLOC_KEYS:
			expected += float(K.BLOC_SIZE[bloc]) * float(snap["bloc_approval"][bloc])
		if absf(float(snap["overall_approval_pct"]) - expected) > 1.0e-9:
			_fail("month %d: overall approval %s is not the size-weighted mean %s" % [
				i + 1, snap["overall_approval_pct"], expected
			])
			return


## Ten years under the budgets that most stress the economy. Approval is bounded
## by construction, so this is checking the construction holds.
func _check_nothing_diverges() -> void:
	var budgets := [
		{},
		{"tax_rates_pct": {"income": 0.0, "corporate": 0.0, "vat": 0.0}},
		{"tax_rates_pct": {"income": 70.0, "corporate": 70.0, "vat": 40.0}},
		{"spending_pct_gdp": {"health": 30.0, "education": 30.0, "defence": 30.0, "pensions": 30.0, "infrastructure": 30.0}},
		{"spending_pct_gdp": {"health": 0.0, "education": 0.0, "defence": 0.0, "pensions": 0.0, "infrastructure": 0.0}},
	]

	for budget in budgets:
		var state = GameState.new_game(_loader, "FRA")
		if not budget.is_empty():
			Budget.commit(state, budget)
		for month in range(120):
			Economy.tick_month(state)
			Budget.tick_month(state)
			Opinion.tick_month(state)

			var ns = state.player()
			for bloc in K.BLOC_KEYS:
				var approval := float(ns.bloc_approval[bloc])
				if is_nan(approval) or is_inf(approval):
					_fail("%s: %s approval is %s at month %d" % [budget, bloc, approval, month + 1])
					return
				if approval < K.APPROVAL_MIN or approval > K.APPROVAL_MAX:
					_fail("%s: %s approval %s out of range at month %d" % [budget, bloc, approval, month + 1])
					return

			var salience_total := 0.0
			for issue in K.ISSUE_KEYS:
				salience_total += float(ns.issue_salience[issue])
			if absf(salience_total - 1.0) > 1.0e-6:
				_fail("%s: issue salience sums to %s at month %d, expected 1.0" % [
					budget, salience_total, month + 1
				])
				return

			if is_nan(ns.overall_approval_pct):
				_fail("%s: overall approval is NaN at month %d" % [budget, month + 1])
				return


## The worst a bloc felt against the baseline path at any point in the window.
## Positive means it fell.
##
## Worst rather than final, because approval recovers: a demand shock decays, so
## sampling only the last month of an eighteen-month window measures the recovery
## rather than the shock. Negative means the bloc was never worse off than the
## baseline at all.
func _drop(base: Array, other: Array, bloc: String) -> float:
	var worst := -INF
	for i in base.size():
		var d: float = float(base[i]["bloc_approval"][bloc]) - float(other[i]["bloc_approval"][bloc])
		worst = maxf(worst, d)
	return worst


## The real tick order — economy, budget, opinion — one snapshot per month.
func _run(state, pending: Dictionary, months: int) -> Array[Dictionary]:
	if not pending.is_empty():
		Budget.commit(state, pending)
	var out: Array[Dictionary] = []
	for _i in range(months):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		var snap := Budget.snapshot(state)
		snap.merge(Opinion.snapshot(state))
		out.append(snap)
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_opinion: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
