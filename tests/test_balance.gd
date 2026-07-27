extends SceneTree

## Headless test: godot --headless --script res://tests/test_balance.gd
## Non-zero exit on any failure.
##
## S10's regression test. Every other test asks whether a system computes what it
## says it computes; this one asks whether the *numbers* still produce a game —
## which is the only thing tuning can break and nothing else would catch.
##
## Three failure modes, all of them things the S4/S5 constants actually did
## before the balance pass and would do again if a constant drifted:
##
##   1. A value goes non-finite, negative, or lands on one of the model's guard
##      clamps and stays there. A clamp that binds means the clamp, not the
##      model, is setting the number.
##   2. Fiscal discipline is dominated — a budget that runs a ruinous deficit
##      wins elections anyway, so there is no reason to open the budget screen.
##   3. Losing is unattributable — the result screen names issues from the base
##      salience table rather than the one the player actually broke.
##
## Runs the real monthly tick sequence src/ui/main.gd wires the clock through.
## tools/balance_probe.gd is the exploratory version of the same harness, kept
## separate because it prints trajectories rather than asserting on them.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const DK = preload("res://src/sim/discipline_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")

const START_YEAR := 2026

## France's inherited term ends June 2029; full terms then end June 2034 and June
## 2039. 168 months reaches the third, so a run that survives it has played two
## consecutive full terms after the one it started mid-way through.
const MONTHS := 168
const TEN_YEARS := 120

## Never touch the budget.
const IGNORED := {}

## Cut the one line a single bloc weights, fund it with the tax that carries no
## labour-market cost, leave health/education/pensions alone.
const MANAGED := {
	"spending_pct_gdp": {
		"health": 11.0, "education": 5.5, "defence": 0.6,
		"pensions": 14.5, "infrastructure": 3.5,
	},
	"tax_rates_pct": {"income": 21.0, "corporate": 25.0, "vat": 23.0},
}

## Every spending line maxed, every tax at zero: a deficit around 90% of GDP.
const RUINOUS := {
	"spending_pct_gdp": {
		"health": 30.0, "education": 20.0, "defence": 20.0,
		"pensions": 30.0, "infrastructure": 20.0,
	},
	"tax_rates_pct": {"income": 0.0, "corporate": 0.0, "vat": 0.0},
}

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_ten_years_stay_off_every_clamp()
	_check_two_full_terms_without_softlock()
	_check_managing_beats_ignoring()
	_check_a_ruinous_budget_loses()
	_check_losing_names_the_number_the_player_moved()
	_check_a_dissolution_stays_off_every_clamp()
	_finish()


## Done-when: "A ten-year playthrough (two terms) runs with no value diverging to
## infinity or pinning at zero." Checked every month, not just at the end — a
## value that pins and then recovers still means the model stopped working.
func _check_ten_years_stay_off_every_clamp() -> void:
	var run := _play(IGNORED, TEN_YEARS)
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("ten-year run: %s" % p)
	if ns.gdp_eur_bn <= 0.0:
		_fail("ten-year run ended with GDP %.3f" % ns.gdp_eur_bn)
	if run["months"] < TEN_YEARS:
		_fail("ten-year run stopped after %d months" % run["months"])


## Done-when: "A full five-year term is playable start to finish without a crash
## or a softlock", and S10's "two consecutive full terms play without a
## softlock". Three national elections resolve in 168 months; a player who never
## opens the budget screen should survive all three.
func _check_two_full_terms_without_softlock() -> void:
	var run := _play(IGNORED, MONTHS)
	var ns = run["state"].player()

	if run["months"] < MONTHS:
		_fail("ignoring the budget lost government after %d months; a do-nothing run should survive two full terms" % run["months"])
		return
	if run["elections"].size() < 3:
		_fail("expected three national elections in %d months, saw %d" % [MONTHS, run["elections"].size()])
	if ns.terms_served < 3:
		_fail("terms_served is %d after three held elections" % ns.terms_served)
	if not ns.in_government:
		_fail("in_government is false after a run in which every election was held")


## Done-when: "Ignoring the budget for a full term produces a visibly worse
## outcome than managing it." Before the S10 pass this was false in both
## directions at once — profligacy won elections and consolidation lost them —
## so a budget that manages the deficit must now finish ahead on both the number
## the player is managing and the number the electorate scores them on.
func _check_managing_beats_ignoring() -> void:
	var ignored := _play(IGNORED, MONTHS)
	var managed := _play(MANAGED, MONTHS)

	if managed["months"] < MONTHS:
		_fail("the managed budget lost government after %d months" % managed["months"])
		return

	var i = ignored["state"].player()
	var m = managed["state"].player()

	if m.debt_to_gdp_pct() >= i.debt_to_gdp_pct():
		_fail("managing the budget did not beat ignoring it on debt: %.1f%% managed vs %.1f%% ignored" % [
			m.debt_to_gdp_pct(), i.debt_to_gdp_pct()
		])
	if m.overall_approval_pct <= i.overall_approval_pct:
		_fail("managing the budget did not beat ignoring it on approval: %.1f managed vs %.1f ignored" % [
			m.overall_approval_pct, i.overall_approval_pct
		])
	if int(m.seats_by_party.get(m.incumbent_party_id, 0)) <= int(i.seats_by_party.get(i.incumbent_party_id, 0)):
		_fail("managing the budget did not beat ignoring it on seats: %d managed vs %d ignored" % [
			int(m.seats_by_party.get(m.incumbent_party_id, 0)),
			int(i.seats_by_party.get(i.incumbent_party_id, 0)),
		])


## Done-when: "The player can lose." The specific loss that matters is the one
## the S5 constants got wrong: a budget with every line maxed and every tax at
## zero used to hold approval at 57 and win three consecutive elections.
func _check_a_ruinous_budget_loses() -> void:
	var run := _play(RUINOUS, MONTHS)
	if run["months"] >= MONTHS:
		_fail("a budget running a deficit near 90%% of GDP survived %d months" % MONTHS)
		return

	var results: Array = run["elections"]
	if results.is_empty():
		_fail("the ruinous run ended without resolving an election")
		return
	if results[-1]["incumbent_largest"]:
		_fail("the ruinous run's final election was held rather than lost")


## Done-when: "losing is attributable to their decisions rather than to noise",
## and S10's "losing feels attributable, not random". The result screen reads
## Elections.attribution(), which is the most-salient issues at the moment of the
## vote — so this asserts that two different bad budgets are blamed on two
## different numbers, and on the numbers they actually moved.
func _check_losing_names_the_number_the_player_moved() -> void:
	_expect_blamed_on(RUINOUS, "public_finances", "a deficit near 90% of GDP")

	var slash_the_state := {
		"spending_pct_gdp": {
			"health": 0.0, "education": 0.0, "defence": 0.0,
			"pensions": 0.0, "infrastructure": 0.0,
		},
	}
	_expect_blamed_on(slash_the_state, "pensions", "abolishing every spending line")


func _expect_blamed_on(pending: Dictionary, issue: String, description: String) -> void:
	var run := _play(pending, MONTHS)
	var results: Array = run["elections"]
	if results.is_empty() or results[-1]["incumbent_largest"]:
		_fail("expected %s to lose an election" % description)
		return

	var named: Array = []
	for a in results[-1]["attribution"]:
		named.append(a["issue"])
	if not named.has(issue):
		_fail("losing after %s was attributed to %s, not to '%s'" % [description, named, issue])
		return

	# Naming the issue is not enough — it has to be named because it is bad.
	for a in results[-1]["attribution"]:
		if a["issue"] == issue and float(a["satisfaction"]) >= 0.0:
			_fail("'%s' was named after %s but its satisfaction was %+.2f" % [
				issue, description, a["satisfaction"]
			])


## V1.1c: a managed budget that also dissolves early stays inside every
## invariant this file checks, and the snap election it calls actually resolves
## and reads as one. `dissolve_at_month` is well clear of
## DISSOLUTION_BLACKOUT_MONTHS (2029-06 is 40 months out at month 3), so this
## exercises the ordinary case rather than a refusal.
func _check_a_dissolution_stays_off_every_clamp() -> void:
	var run := _play(MANAGED, MONTHS, 3)

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("dissolution run: %s" % p)

	var snapped := false
	for r in run["all_results"]:
		if r["kind"] == "national" and bool(r.get("snap", false)):
			snapped = true
	if not snapped:
		_fail("a dissolution called at month 3 never produced a snap-flagged legislative result")

	var ns = run["state"].player()
	if ns.dissolutions_called != 1:
		_fail("dissolutions_called is %d after calling exactly one" % ns.dissolutions_called)


## One playthrough. `pending` is committed once, in the first month, and then
## left alone — the crudest possible player, which is the point: a constant
## policy that breaks the model means a real one certainly will. Stops early if
## the incumbent is voted out, the same way main.gd's clock does.
## `dissolve_at_month` (1-indexed simulated month, -1 to never) calls
## Dissolution.dissolve() once that month is reached, in the same tick position
## main.gd and balance_probe.gd use: after Legislature, before Elections.
func _play(pending: Dictionary, months: int, dissolve_at_month: int = -1) -> Dictionary:
	var state = GameState.new_game(_loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported errors: %s" % [state.errors])
	state.year = START_YEAR
	state.month = 1

	if not pending.is_empty():
		Budget.commit(state, pending)

	var ns = state.player()
	var problems: Array[String] = []
	var elections: Array = []
	var all_results: Array = []

	var year := START_YEAR
	var month := 1
	var played := 0

	for i in range(months):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)
		Discipline.tick_month(state, _loader)
		Legislature.tick_month(state)
		Dissolution.tick_month(state)

		if i + 1 == dissolve_at_month:
			Dissolution.dissolve(state, ns)

		# The verdict on the player is the EXECUTIVE election where one exists —
		# France's presidency — and the legislative one where the head of
		# government comes out of the chamber. A legislative election under a
		# separately elected executive changes the assembly, not the office, so
		# collecting it here would score the player on a vote they cannot lose.
		var verdict_kind := "executive" if ns.has_executive else "national"
		for r in Elections.tick_month(state, _loader):
			all_results.append(r)
			if r["kind"] == verdict_kind:
				elections.append(r)

		played += 1
		problems.append_array(_problems(ns, year, month))
		if not ns.in_government:
			break

	return {"state": state, "months": played, "problems": problems, "elections": elections, "all_results": all_results}


## Non-finite, non-positive, or resting on a guard clamp. The clamps are
## deliberately set where sane play never reaches them, so touching one is a
## finding rather than a safety net doing its job.
func _problems(ns, year: int, month: int) -> Array[String]:
	var out: Array[String] = []
	var at := "%d-%02d" % [year, month]

	var scalars := {
		"gdp": ns.gdp_eur_bn, "potential_gdp": ns.potential_gdp_eur_bn,
		"growth": ns.growth_annual_pct, "trend": ns.trend_annual_pct,
		"unemployment": ns.unemployment_pct, "structural": ns.structural_unemployment_pct,
		"population": ns.population, "debt": ns.debt_eur_bn,
		"deficit": ns.deficit_pct_gdp, "revenue": ns.total_revenue_pct_gdp,
		"spending": ns.total_spending_pct_gdp, "demand_impulse": ns.demand_impulse_pct,
		"potential_shift": ns.potential_shift_pct, "approval": ns.overall_approval_pct,
	}
	for key in scalars:
		var v: float = float(scalars[key])
		if is_nan(v) or is_inf(v):
			out.append("%s %s is %s" % [at, key, v])

	for key in ns.sector_output:
		var v: float = float(ns.sector_output[key])
		if is_nan(v) or is_inf(v) or v <= 0.0:
			out.append("%s sector %s is %s" % [at, key, v])
	for bloc in K.BLOC_KEYS:
		var v: float = float(ns.bloc_approval[bloc])
		if is_nan(v) or is_inf(v):
			out.append("%s bloc %s approval is %s" % [at, bloc, v])

	if ns.gdp_eur_bn <= 0.0:
		out.append("%s GDP pinned at %.3f" % [at, ns.gdp_eur_bn])
	if ns.population <= 0.0:
		out.append("%s population pinned at %.3f" % [at, ns.population])
	if ns.unemployment_pct <= C.UNEMP_MIN_PCT or ns.unemployment_pct >= C.UNEMP_MAX_PCT:
		out.append("%s unemployment on its clamp at %.2f" % [at, ns.unemployment_pct])
	if ns.overall_approval_pct <= K.APPROVAL_MIN or ns.overall_approval_pct >= K.APPROVAL_MAX:
		out.append("%s approval on its clamp at %.2f" % [at, ns.overall_approval_pct])
	if absf(ns.growth_annual_pct) >= C.GROWTH_MAX_PCT - 0.01:
		out.append("%s growth on its clamp at %.2f" % [at, ns.growth_annual_pct])

	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_balance: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
