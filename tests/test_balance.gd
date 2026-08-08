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
const Bloc = preload("res://src/sim/bloc.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Companies = preload("res://src/sim/companies.gd")
const CompaniesK = preload("res://src/sim/companies_constants.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
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
	_check_gbr_ten_years_stay_off_every_clamp()
	_check_two_full_terms_without_softlock()
	_check_france_terms_out_at_the_limit()
	_check_managing_beats_ignoring()
	_check_a_ruinous_budget_loses()
	_check_losing_names_the_number_the_player_moved()
	_check_a_dissolution_stays_off_every_clamp()
	_check_a_subsidised_run_stays_off_every_clamp()
	_check_a_regulated_run_stays_off_every_clamp()
	_check_a_nationalised_run_stays_off_every_clamp()
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


## V1.2d: GBR is the third playable nation. Same shape as the FRA check above
## -- a do-nothing budget over two terms stays off every clamp -- proving
## nothing in the model quietly assumed France or Germany's institutions
## (largest_party formation, ordinary_law amendment threshold, FPTP with no
## threshold), the same test V1.2a's Germany addition ran.
func _check_gbr_ten_years_stay_off_every_clamp() -> void:
	var run := _play(IGNORED, TEN_YEARS, -1, "GBR")
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("GBR ten-year run: %s" % p)
	if ns.gdp_eur_bn <= 0.0:
		_fail("GBR ten-year run ended with GDP %.3f" % ns.gdp_eur_bn)
	if run["months"] < TEN_YEARS:
		_fail("GBR ten-year run stopped after %d months" % run["months"])


## Done-when: "A full five-year term is playable start to finish without a crash
## or a softlock".
##
## Run on Germany, not France, since V1.2b: France's two-term limit caps a
## do-nothing run at two elections regardless of outcome (see
## _check_france_terms_out_at_the_limit() below), so it cannot exercise a third.
## Germany has no such limit -- but a do-nothing German budget does not keep
## winning either. tools/balance_probe.gd's own hands_off/DEU trajectory shows
## the chancellor's party sliding under 50% and losing "largest party" at the
## second legislative election, 2033-02 — a real, previously-measured
## divergence from France (see docs/data-architecture.md's bloc-weight note),
## not a softlock. So this checks what the done-when actually asks for: however
## many elections a 168-month run resolves, none of them produces a crash, a
## non-finite value, or a value stuck on a guard clamp.
func _check_two_full_terms_without_softlock() -> void:
	var run := _play(IGNORED, MONTHS, -1, "DEU")

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("Germany do-nothing run: %s" % p)
	if run["elections"].is_empty():
		_fail("Germany's do-nothing run resolved no legislative elections in %d months" % run["months"])


## V1.2b: France's own two-term limit ends what would otherwise be an
## indefinitely-survivable do-nothing run -- the President is termed out at the
## third executive election (2037-05) rather than losing a vote. Distinct from
## every other check here: in_government going false is the CORRECT outcome,
## and the failure modes are firing early, firing late, or being
## indistinguishable from an actual election defeat.
func _check_france_terms_out_at_the_limit() -> void:
	var run := _play(IGNORED, MONTHS)
	var ns = run["state"].player()

	if ns.in_government:
		_fail("a do-nothing French run still holds office after %d months; the two-term limit should have ended it" % run["months"])
		return
	if run["elections"].size() != 2:
		_fail("expected exactly 2 executive elections before the term limit barred a third, saw %d" % run["elections"].size())
	if ns.terms_served != 2:
		_fail("terms_served is %d when termed out; France's term_limit is 2" % ns.terms_served)
	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("termed-out run: %s" % p)


## Done-when: "Ignoring the budget for a full term produces a visibly worse
## outcome than managing it." Before the S10 pass this was false in both
## directions at once — profligacy won elections and consolidation lost them —
## so a budget that manages the deficit must now finish ahead on both the number
## the player is managing and the number the electorate scores them on.
func _check_managing_beats_ignoring() -> void:
	var ignored := _play(IGNORED, MONTHS)
	var managed := _play(MANAGED, MONTHS)

	# Both regimes win every election here, so both are termed out by France's
	# two-term limit at the same real-calendar month regardless of budget --
	# see _check_france_terms_out_at_the_limit(). A managed run stopping short
	# of THAT month is the regression this guards; stopping at it is expected.
	if managed["months"] < ignored["months"]:
		_fail("the managed budget lost government at month %d, before the do-nothing run's month %d" % [managed["months"], ignored["months"]])
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
func _play(pending: Dictionary, months: int, dissolve_at_month: int = -1, nation_id: String = "FRA", subsidise_at_month: int = -1, regulate_at_month: int = -1, nationalise_at_month: int = -1) -> Dictionary:
	var state = GameState.new_game(_loader, nation_id)
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
		Bloc.tick_month(state, _loader)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)
		Discipline.tick_month(state, _loader)
		Legislature.tick_month(state)
		Dissolution.tick_month(state)
		# V1.4a, in main.gd's slot. Inert for every regime here that subsidises
		# nobody -- the share shift is exactly zero with no subsidy standing and all
		# three prices are exactly 0.0 -- so the checks above are unchanged by it.
		Companies.tick_month(state, _loader)
		# V1.5a, in main.gd's slot, and NOT inert where the four above it were: the
		# quality stock reads the live spending line, so any regime that moves one moves
		# the `health` satisfaction term with it.
		# V1.5b, immediately before Society: the quality stock divides by this layer's
		# dependency factor, so demography must have settled before quality reads it.
		Demography.tick_month(state)
		Society.tick_month(state)
		Cabinet.tick_month(state, _loader)

		if i + 1 == dissolve_at_month:
			Dissolution.dissolve(state, ns)

		if i + 1 == subsidise_at_month:
			_subsidise_the_largest(state, ns)

		if i + 1 == regulate_at_month:
			_regulate_everything(state, ns)

		if i + 1 == nationalise_at_month:
			_nationalise_the_largest(state, ns)

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
## V1.4a's regime, and it exists for the reason V1.3g's and U6a's did: a subsidy is
## a VERB, and no budget regime issues a command. The other eight checks here prove
## the register is inert; this one is the only place the channels are ever non-zero,
## so it is the only place their clamps can be reached.
##
## Fourteen years of a subsidy nobody withdraws, which is the reachable worst case
## rather than a typical game: if the bill clamp or either channel clamp BINDS here,
## the clamp and not the model is setting the number -- the IMPULSE_MAX failure
## docs/economy-model.md records, and the escalation this session declared in
## advance.
func _check_a_subsidised_run_stays_off_every_clamp() -> void:
	var run := _play(MANAGED, MONTHS, -1, "FRA", 6)
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("subsidised run: %s" % p)

	if ns.subsidy_bill_pct_gdp <= 0.0:
		_fail("the subsidised run never billed anything, so it asserts nothing about the clamps")
	if ns.subsidy_bill_pct_gdp >= CompaniesK.SUBSIDY_BILL_MAX_PCT_GDP - 0.000001:
		_fail("the subsidy bill sits ON its clamp at %.3f -- the clamp is setting the number, not the model" % ns.subsidy_bill_pct_gdp)
	if absf(ns.firm_impulse_pct) >= CompaniesK.FIRM_IMPULSE_MAX_PCT - 0.000001:
		_fail("the firm growth impulse sits ON its clamp at %.3f" % ns.firm_impulse_pct)
	if absf(ns.firm_jobs_offset_pct) >= CompaniesK.FIRM_JOBS_MAX_PCT - 0.000001:
		_fail("the firm jobs offset sits ON its clamp at %.3f" % ns.firm_jobs_offset_pct)


## V1.4b's regime: fourteen years of every sector saturated with rules nobody
## repeals, WITH the subsidy stack live underneath it. Both verbs at once, because
## they share the two channels and their clamps -- a burden that only ever ran on a
## clean register would never test the case the model actually allows.
func _check_a_regulated_run_stays_off_every_clamp() -> void:
	var run := _play(MANAGED, MONTHS, -1, "FRA", 6, 12)
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("regulated run: %s" % p)

	var burdened := 0
	for sector in ns.regulation_burden.keys():
		if absf(float(ns.regulation_burden[sector])) > 0.0:
			burdened += 1
	if burdened == 0:
		_fail("the regulated run carries no burden, so it asserts nothing about the clamps")

	if absf(ns.firm_impulse_pct) >= CompaniesK.FIRM_IMPULSE_MAX_PCT - 0.000001:
		_fail("the firm growth impulse sits ON its clamp at %.3f under regulation" % ns.firm_impulse_pct)
	if absf(ns.firm_jobs_offset_pct) >= CompaniesK.FIRM_JOBS_MAX_PCT - 0.000001:
		_fail("the firm jobs offset sits ON its clamp at %.3f under regulation" % ns.firm_jobs_offset_pct)

	# The burden clamp itself, which is the one this session added. Saturating it is
	# EXPECTED here -- four copies of every rule is not a reachable game -- so what is
	# asserted is that it holds rather than that it is slack.
	for sector in ns.regulation_burden.keys():
		if absf(float(ns.regulation_burden[sector])) > CompaniesK.REGULATION_BURDEN_MAX + 0.000001:
			_fail("%s burden ran past REGULATION_BURDEN_MAX at %.3f" % [
				sector, ns.regulation_burden[sector],
			])


## The harshest authored subsidy, pointed at the largest firm by output -- the case
## both channels are widest for.
func _subsidise_the_largest(state, ns) -> void:
	var action = null
	for a in _loader.company_actions:
		if String(a.effects.get("company", {}).get("op", "")) != "subsidise":
			continue
		if action == null or float(a.effects["company"]["intensity"]) > float(action.effects["company"]["intensity"]):
			action = a
	if action == null:
		_fail("no 'subsidise' company action is authored")
		return

	var best := ""
	var best_output := -1.0
	for company in Companies.firms_of(_loader, ns.id):
		var out: float = Companies.output_eur_bn(ns, company)
		if out > best_output:
			best_output = out
			best = String(company.id)
	if best == "":
		_fail("the player's nation has no named firms, so the subsidised regime asserts nothing")
		return

	var result := Companies.execute(state, ns, _loader.company_actions, action, best, _loader)
	if not result.get("applied", false):
		_fail("the subsidy was refused, so the subsidised regime asserts nothing")


## V1.4b's regime. A regulation is a VERB and no budget regime passes a law, which
## is why V1.3c, V1.3g, U6a and V1.4a each needed one of these -- but this one is
## the cheap kind: tools/balance_probe.gd already carries AMENDMENT_REGIMES and
## TRANSITION_REGIMES, both of which apply a law at a month, so the shape existed.
##
## Legislature.apply() rather than propose(): the assembly division is
## tests/test_legislature.gd's subject, and a clamp assertion that only holds on the
## months the chamber agrees asserts nothing on the months it does not.
##
## EVERY positive-burden law at once, which saturates all three sectors -- the
## reachable worst case rather than a typical game, exactly as the subsidised regime
## above is.
func _regulate_everything(state, ns) -> void:
	var applied := 0
	for law in _loader.laws:
		if law.theme != "business":
			continue
		if float(law.effects.get("company", {}).get("burden", 0.0)) <= 0.0:
			continue
		for _repeat in range(4):
			Legislature.apply(state, ns, law, _loader)
		applied += 1
	if applied == 0:
		_fail("no positive-burden business law is authored, so the regulated regime asserts nothing")


## V1.4c's regime, and the expensive kind again: an ownership op is a verb no budget
## regime issues, so this had to be taught the way V1.3c's, V1.3g's, U6a's and
## V1.4a's were -- V1.4b's was cheap only because a law was a shape the harness knew.
##
## Fourteen years of a holding nobody sells, WITH the subsidy stack and the whole
## regulation stack live underneath it. All three verbs at once, for the reason the
## regulated run runs two: they share one register, the jobs channel is where the
## ownership shield and the regulation burden meet, and a holding that only ever ran
## on a clean register would never test the case the model allows.
##
## The clamp this session added is the dividend one, and unlike the burden clamp it
## is expected to be SLACK: a reachable stack sitting on it means the clamp and not
## the model is setting the number.
func _check_a_nationalised_run_stays_off_every_clamp() -> void:
	var run := _play(MANAGED, MONTHS, -1, "FRA", 6, 12, 18)
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("nationalised run: %s" % p)

	if Companies.state_owned_count(ns) == 0:
		_fail("the nationalised run holds nothing, so it asserts nothing about the clamps")
	if ns.dividend_revenue_pct_gdp <= 0.0:
		_fail("the nationalised run collected no dividend, so it asserts nothing about the clamp")
	if ns.dividend_revenue_pct_gdp >= CompaniesK.DIVIDEND_MAX_PCT_GDP - 0.000001:
		_fail("the dividend line sits ON its clamp at %.3f -- the clamp is setting the number, not the model" % ns.dividend_revenue_pct_gdp)
	if absf(ns.firm_impulse_pct) >= CompaniesK.FIRM_IMPULSE_MAX_PCT - 0.000001:
		_fail("the firm growth impulse sits ON its clamp at %.3f under ownership" % ns.firm_impulse_pct)
	if absf(ns.firm_jobs_offset_pct) >= CompaniesK.FIRM_JOBS_MAX_PCT - 0.000001:
		_fail("the firm jobs offset sits ON its clamp at %.3f under ownership" % ns.firm_jobs_offset_pct)


## The stake the register can actually reach, on the firm the two other verbs are
## already pointed at -- so the shield, the burden and the subsidy all meet on one
## company rather than on three that never interact.
func _nationalise_the_largest(state, ns) -> void:
	var action = null
	for a in _loader.company_actions:
		if String(a.effects.get("company", {}).get("op", "")) != "nationalise":
			continue
		if action == null or float(a.effects["company"]["stake"]) > float(action.effects["company"]["stake"]):
			action = a
	if action == null:
		_fail("no 'nationalise' company action is authored")
		return

	var best := ""
	var best_output := -1.0
	for company in Companies.firms_of(_loader, ns.id):
		var out: float = Companies.output_eur_bn(ns, company)
		if out > best_output:
			best_output = out
			best = String(company.id)
	if best == "":
		_fail("the player's nation has no named firms, so the nationalised regime asserts nothing")
		return

	var result := Companies.execute(state, ns, _loader.company_actions, action, best, _loader)
	if not result.get("applied", false):
		_fail("the nationalisation was refused, so the regime asserts nothing")


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

	# Cabinet: no portfolio held outside the coalition, and every cached
	# effectiveness figure inside the range the formula can actually produce --
	# see docs/cabinet-model.md.
	var max_effectiveness: float = 1.0 + CK.COMPETENCE_SPAN * (1.0 - CK.COMPETENCE_NEUTRAL)
	for f in CK.PORTFOLIO_KEYS:
		var holder: String = String(ns.cabinet.get(f, ""))
		if holder != "" and not ns.coalition_party_ids.has(holder):
			out.append("%s portfolio %s held by %s, outside the coalition" % [at, f, holder])
		var eff: float = float(ns.cabinet_effectiveness.get(f, CK.VACANT_EFFECTIVENESS))
		if is_nan(eff) or is_inf(eff):
			out.append("%s cabinet effectiveness for %s is %s" % [at, f, eff])
		elif eff < CK.VACANT_EFFECTIVENESS - 0.001 or eff > max_effectiveness + 0.001:
			out.append("%s cabinet effectiveness for %s is %.3f, outside [%.3f, %.3f]" % [
				at, f, eff, CK.VACANT_EFFECTIVENESS, max_effectiveness
			])

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
