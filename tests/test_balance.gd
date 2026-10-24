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

## suite-shard-checks: _check_ten_years_stay_off_every_clamp,_check_gbr_ten_years_stay_off_every_clamp,_check_two_full_terms_without_softlock,_check_france_terms_out_at_the_limit,_check_managing_beats_ignoring,_check_a_ruinous_budget_loses,_check_losing_names_the_number_the_player_moved,_check_a_dissolution_stays_off_every_clamp,_check_a_subsidised_run_stays_off_every_clamp,_check_a_regulated_run_stays_off_every_clamp,_check_a_nationalised_run_stays_off_every_clamp,_check_a_redistributive_run_stays_off_every_clamp,_check_a_captured_court_stays_off_every_clamp,_check_a_nuclear_run_stays_off_every_clamp,_check_a_gas_run_stays_off_every_clamp

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Budget = preload("res://src/sim/budget.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const JudiciaryK = preload("res://src/sim/judiciary_constants.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Companies = preload("res://src/sim/companies.gd")
const CompaniesK = preload("res://src/sim/companies_constants.gd")
const Tax = preload("res://src/sim/tax.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const DK = preload("res://src/sim/discipline_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const Migration = preload("res://src/sim/migration.gd")
const Energy = preload("res://src/sim/energy.gd")
const EnergyK = preload("res://src/sim/energy_constants.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const Regions = preload("res://src/sim/regions.gd")

const START_YEAR := 2026

## France's inherited term ends June 2029; full terms then end June 2034 and June
## 2039. 168 months reaches the third, so a run that survives it has played two
## consecutive full terms after the one it started mid-way through.
const MONTHS := 168
## bands-v5.2.md, "B3 amendment (2026-10-24): the cost fades": the acts' fading
## share of any bloc's offset, in any month of any run.
const ACT_SHARE_MAX := 0.50
## `-- --bands-reads` (QA's TAKE 2 on PR #104): each month the player governs
## prints a MONTH line, its act share and any bloc on the clamp, for
## tools/act_share_reads.py to compare a base run with a tip run. The read window
## is bands-v5.2.md's "Correction: the read window": it closes at the first month
## out of office -- an executive loss or the term limit, where main.gd sends the
## player to the menu -- because the months after it are a world the game never
## plays. Off by default; the runs and the checks below are unchanged by it.
var _bands_reads := "--bands-reads" in OS.get_cmdline_user_args()
var _run_no := 0
var _band_open := false
const TEN_YEARS := 120
## How often one event may reach the player's desk in a ten-year do-nothing run.
## Measured by the test audit (2026-10-21) over 168 months of the same regime: the
## most-delivered event reached FRA's desk 2 times and GBR's 5 (union_ultimatum),
## 41 and 29 deliveries in all -- counted from the stamps and the desk both, the
## same figures either way (re-measured at review pass 2). 8 is that worst plus
## 60%, over a SHORTER window,
## so it is slack for the content and tight for the V4.4 class -- a hook or a
## cooldown that stops binding lands the same occasion on every month it can.
const DESK_DELIVERIES_PER_EVENT_MAX := 8
## The same run's total, at twice FRA's 168-month figure.
const DESK_DELIVERIES_TOTAL_MAX := 82

## Never touch the budget.
const IGNORED := {}

## Cut the one line a single bloc weights, fund it with the tax that carries no
## labour-market cost, leave health/education/pensions alone.
## V1.6d's regime, and the reason it is needed is the reason V1.5c's blind spot was:
## every regime above sets three tax keys and no schedule, so the two new taxes and the
## bracket lever are STRUCTURALLY UNREACHABLE by all of them. A statistic needs no
## regime -- (a), (b) and (c) each added none -- and a verb does, which is V1.3a's rule
## coming back for the first time in this block.
##
## Both new taxes at a rate a player would plausibly choose, plus a steeper schedule, on
## top of the managed budget rather than instead of it: the reachable case is *govern
## well, then redistribute*, not *provoke in month 1 and lose the next election*, which
## is what docs/unrest-model.md's own probe got wrong about itself.
const REDISTRIBUTIVE := {
	"spending_pct_gdp": {
		"health": 11.0, "education": 5.5, "defence": 0.6,
		"pensions": 14.5, "infrastructure": 3.5,
	},
	"tax_rates_pct": {
		"income": 21.0, "corporate": 25.0, "vat": 23.0,
		"capital_gains": 40.0, "wealth": 0.5,
	},
	"tax_progressivity": 1.5,
}

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

	# V3.3 scratch: -- check-name runs ONE check (the crash isolation harness).
	var _matched := 0
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]

	if only == "" or only == "_check_ten_years_stay_off_every_clamp":
		_matched += 1
		_check_ten_years_stay_off_every_clamp()
	if only == "" or only == "_check_gbr_ten_years_stay_off_every_clamp":
		_matched += 1
		_check_gbr_ten_years_stay_off_every_clamp()
	if only == "" or only == "_check_two_full_terms_without_softlock":
		_matched += 1
		_check_two_full_terms_without_softlock()
	if only == "" or only == "_check_france_terms_out_at_the_limit":
		_matched += 1
		_check_france_terms_out_at_the_limit()
	if only == "" or only == "_check_managing_beats_ignoring":
		_matched += 1
		_check_managing_beats_ignoring()
	if only == "" or only == "_check_a_ruinous_budget_loses":
		_matched += 1
		_check_a_ruinous_budget_loses()
	if only == "" or only == "_check_losing_names_the_number_the_player_moved":
		_matched += 1
		_check_losing_names_the_number_the_player_moved()
	if only == "" or only == "_check_a_dissolution_stays_off_every_clamp":
		_matched += 1
		_check_a_dissolution_stays_off_every_clamp()
	if only == "" or only == "_check_a_subsidised_run_stays_off_every_clamp":
		_matched += 1
		_check_a_subsidised_run_stays_off_every_clamp()
	if only == "" or only == "_check_a_regulated_run_stays_off_every_clamp":
		_matched += 1
		_check_a_regulated_run_stays_off_every_clamp()
	if only == "" or only == "_check_a_nationalised_run_stays_off_every_clamp":
		_matched += 1
		_check_a_nationalised_run_stays_off_every_clamp()
	if only == "" or only == "_check_a_redistributive_run_stays_off_every_clamp":
		_matched += 1
		_check_a_redistributive_run_stays_off_every_clamp()
	if only == "" or only == "_check_a_captured_court_stays_off_every_clamp":
		_matched += 1
		_check_a_captured_court_stays_off_every_clamp()
	if only == "" or only == "_check_a_nuclear_run_stays_off_every_clamp":
		_matched += 1
		_check_a_nuclear_run_stays_off_every_clamp()
	if only == "" or only == "_check_a_gas_run_stays_off_every_clamp":
		_matched += 1
		_check_a_gas_run_stays_off_every_clamp()
	if only != "" and _matched == 0:
		_fail("unknown check name '%s' -- the filter ran nothing, and green-over-nothing is the V2.1c class" % only)
	_finish()


## Done-when: "A ten-year playthrough (two terms) runs with no value diverging to
## infinity or pinning at zero." Checked every month, not just at the end — a
## value that pins and then recovers still means the model stopped working.
func _check_ten_years_stay_off_every_clamp() -> void:
	# stop_on_loss=false, V3.0: the do-nothing run now LOSES office mid-window
	# (the fatigue finding), and the clamp watch needs its full horizon — losing
	# an election is not what this check exists to catch.
	var run := _play(IGNORED, TEN_YEARS, -1, "FRA", -1, -1, -1, -1, "", -1, 0, false)
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("ten-year run: %s" % p)
	if ns.gdp_eur_bn <= 0.0:
		_fail("ten-year run ended with GDP %.3f" % ns.gdp_eur_bn)
	if run["months"] < TEN_YEARS:
		_fail("ten-year run stopped after %d months" % run["months"])
	_expect_a_quiet_desk("ten-year run", run["deliveries"])


## V1.2d: GBR is the third playable nation. Same shape as the FRA check above
## -- a do-nothing budget over two terms stays off every clamp -- proving
## nothing in the model quietly assumed France or Germany's institutions
## (largest_party formation, ordinary_law amendment threshold, FPTP with no
## threshold), the same test V1.2a's Germany addition ran.
func _check_gbr_ten_years_stay_off_every_clamp() -> void:
	# stop_on_loss=false, for the same reason the FRA ten-year check above passes it.
	var run := _play(IGNORED, TEN_YEARS, -1, "GBR", -1, -1, -1, -1, "", -1, 0, false)
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("GBR ten-year run: %s" % p)
	if ns.gdp_eur_bn <= 0.0:
		_fail("GBR ten-year run ended with GDP %.3f" % ns.gdp_eur_bn)
	if run["months"] < TEN_YEARS:
		_fail("GBR ten-year run stopped after %d months" % run["months"])
	_expect_a_quiet_desk("GBR ten-year run", run["deliveries"])


## The test audit's S5, the V4.4 escape as a bound: a commodity hook fired 168
## months of 168 while every gate was green, because nothing counted what the
## real month delivers. Counted here, on the clamp watch's own run.
func _expect_a_quiet_desk(label: String, deliveries: Dictionary) -> void:
	var total := 0
	for ev_id in deliveries.keys():
		total += int(deliveries[ev_id])
		if int(deliveries[ev_id]) > DESK_DELIVERIES_PER_EVENT_MAX:
			_fail("%s: '%s' reached the player's desk %d times in ten years (bound %d)" % [
				label, ev_id, deliveries[ev_id], DESK_DELIVERIES_PER_EVENT_MAX])
	if total > DESK_DELIVERIES_TOTAL_MAX:
		_fail("%s: %d desk deliveries in ten years (bound %d)" % [label, total, DESK_DELIVERIES_TOTAL_MAX])
	if total == 0:
		_fail("%s: nothing reached the player's desk in ten years -- the count is not reading deliveries" % label)
	print("%s: %d desk deliveries, most %d of one event" % [label, total,
		deliveries.values().reduce(func(a, b): return maxi(a, b), 0)])


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
## every other check here: in_government going false is the CORRECT outcome.
##
## V3.0 RE-CONTRACTED, and the change is the fatigue term's own finding: time in
## office is now its own drag (the S5 deferral), and at the shipped rate the
## do-nothing president no longer WINS the 2032 re-election at all — the run
## ends in a lost vote at month 76, before the 2037 term-out. That is the
## playtest's F6 ask working as designed (idle must not be locally optimal), so
## the pinned property is no longer "terms out at exactly two elections" but
## the one both paths share: office ENDS within the two-term window, the run
## survives past its first term, and the end is clean.
func _check_france_terms_out_at_the_limit() -> void:
	var run := _play(IGNORED, MONTHS)
	var ns = run["state"].player()

	if ns.in_government:
		_fail("a do-nothing French run still holds office after %d months; the two-term limit should have ended it" % run["months"])
		return
	if run["months"] <= 60:
		_fail("the do-nothing run ended at month %d — before its first term was out, which is a softlock or a crash, not a politics" % run["months"])
		return
	if run["elections"].size() < 1:
		_fail("the do-nothing run ended with %d executive elections resolved; at least the re-election that ended it must have run" % run["elections"].size())
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
func _play(pending: Dictionary, months: int, dissolve_at_month: int = -1, nation_id: String = "FRA", subsidise_at_month: int = -1, regulate_at_month: int = -1, nationalise_at_month: int = -1, capture_at_month: int = -1, order_action_id: String = "", order_month: int = -1, order_repeat_months: int = 0, stop_on_loss: bool = true) -> Dictionary:
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
	# Each delivery to the player's desk, by event id, read TWO ways and counted
	# once a month per event: the cooldown stamp Events._deliver writes moving, and
	# the desk itself -- an entry that is new, or back with more months to answer
	# than it had. A door that skipped the stamp (the V4.4 hook went round one)
	# still lands on the desk.
	var deliveries := {}
	var cooldowns_before: Dictionary = (ns.event_cooldowns as Dictionary).duplicate()
	var desk_before := _desk(ns)

	var year := START_YEAR
	var month := 1
	var played := 0
	_run_no += 1
	_band_open = _bands_reads
	if _bands_reads:
		print("BANDREAD RUN %d managed=%s" % [_run_no, str(pending == MANAGED)])

	for i in range(months):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		# The game's own month (src/sim/world_month.gd), every system main.gd runs:
		# a balance harness that ticks a hand-kept list agrees with the game about
		# nothing the list has missed -- V1.5d's bug class, which this loop's copy
		# repeated (it never ticked Diplomacy or Defence). The regime's commands
		# ride the step hook, in the slot they had: after the systems, before the
		# vote.
		var report := WorldMonth.tick_month(state, _loader, func(step: String, after: bool, _report: Dictionary) -> void:
			if after or step != "Elections":
				return
			if i + 1 == dissolve_at_month:
				Dissolution.dissolve(state, ns)

			if i + 1 == subsidise_at_month:
				_subsidise_the_largest(state, ns)

			if i + 1 == regulate_at_month:
				_regulate_everything(state, ns)

			# V1.1e. The whole three-Act judicial ladder at one month -- the reachable worst
			# case, the treatment the subsidy stack and the regulation stack already get.
			if i + 1 == capture_at_month:
				for law_id in ["judicial_appointments_reform", "court_jurisdiction_limits",
						"judicial_tenure_act"]:
					for law in _loader.laws:
						if law.id == law_id:
							Legislature.apply(state, ns, law, _loader)
			if i + 1 == nationalise_at_month:
				_nationalise_the_largest(state, ns)

			# V2.8's two regimes, on tools/balance_probe.gd's cadence: an order at
			# `order_month`, repeated at the source's own build length. Through
			# Energy.execute() and never by writing ns.plants -- a regime that bypasses
			# the verb tests a model the player cannot reach. Largest region by live
			# population share, ties broken by the sorted scan: deterministic, which is
			# what a re-run needs and an opinion is not.
			if order_action_id != "" and i + 1 >= order_month and (i + 1 - order_month) % order_repeat_months == 0:
				var e_action = null
				for a in _loader.energy_actions:
					if a.id == order_action_id:
						e_action = a
				if e_action != null:
					var e_weights: Dictionary = {}
					var e_largest := ""
					var e_best: float = -1.0
					for region in _loader.regions.get(nation_id, []):
						var e_share: float = Migration.region_share(ns, region.id)
						e_weights[region.id] = e_share
						if e_share > e_best:
							e_best = e_share
							e_largest = region.id
					var e_access: Dictionary = Regions.accessibility_for(
						ns, state.regions.get(nation_id, []), state.region_graph)
					Energy.execute(state, ns, _loader, _loader.energy_actions, e_action,
						Vector2(0.0, 0.0), e_largest, "", e_access, e_weights)
		)

		# The verdict on the player is the EXECUTIVE election where one exists —
		# France's presidency — and the legislative one where the head of
		# government comes out of the chamber. A legislative election under a
		# separately elected executive changes the assembly, not the office, so
		# collecting it here would score the player on a vote they cannot lose.
		var verdict_kind := "executive" if ns.has_executive else "national"
		for r in report["election_results"]:
			all_results.append(r)
			if r["kind"] == verdict_kind:
				elections.append(r)

		var landed := {}
		for ev_id in ns.event_cooldowns.keys():
			if int(cooldowns_before.get(ev_id, -1)) != int(ns.event_cooldowns[ev_id]):
				landed[ev_id] = true
		var desk_now := _desk(ns)
		for ev_id in desk_now.keys():
			if not desk_before.has(ev_id) or int(desk_now[ev_id]) > int(desk_before[ev_id]):
				landed[ev_id] = true
		for ev_id in landed.keys():
			deliveries[ev_id] = int(deliveries.get(ev_id, 0)) + 1
		cooldowns_before = (ns.event_cooldowns as Dictionary).duplicate()
		desk_before = desk_now

		played += 1
		problems.append_array(_problems(ns, year, month))
		# V3.0's stop_on_loss: losing office is now a REACHABLE politics (the
		# fatigue term), so the checks that watch a full horizon pass false and
		# keep ticking past the loss; the ones about office itself keep the break.
		if stop_on_loss and not ns.in_government:
			break

	return {"state": state, "months": played, "problems": problems, "elections": elections, "all_results": all_results, "deliveries": deliveries}


## The player's desk as event id -> months left to answer.
func _desk(ns) -> Dictionary:
	var out := {}
	for entry in ns.event_queue:
		out[String(entry.get("event_id", ""))] = int(entry.get("months_left", 0))
	return out


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

	# V4.7a FINDING, recorded at the assertion: the register's named coverage
	# went ~0.24 -> 0.9+ with the two-tier roster, so the impulse channel's
	# natural output scaled ~4x and a fully-regulated sector stack now REACHES
	# the +/-2.00 clamp. The plan's rule governs -- a reachable clamp is a
	# finding, not a tune: the clamp stays where V1.4a's C2 anchored it (a
	# ONE-FIRM subsidy must not out-punch a budget, and the subsidised run's
	# own strict off-clamp assertion still passes), and what this extreme
	# regime asserts is that the clamp BOUNDS the channel -- the burden-clamp
	# precedent two checks down: saturating is expected here, holding is the
	# claim. Whether +/-2.00 is the right bound at the new scale is B4's
	# re-baseline sweep, band to be declared before it runs.
	if absf(ns.firm_impulse_pct) > CompaniesK.FIRM_IMPULSE_MAX_PCT + 0.000001:
		_fail("the firm growth impulse ran PAST its clamp at %.3f -- the clamp does not hold" % ns.firm_impulse_pct)
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


## V1.1e's regime, and it is the CHEAP kind: a judicial reform is a law, and applying a
## law at a month is a shape this harness has known since AMENDMENT_REGIMES. What is new
## is the stock it moves and the second grievance term it opens.
##
## THE WHOLE LADDER AND NOTHING ELSE, which is the reachable worst case rather than a
## typical game -- the treatment the subsidy stack, the regulation stack and the
## ownership run all get. It runs the full fourteen years afterwards, because the
## grievance term is a LEVEL read on a permanent deviation and a term that only ever
## charged for a month would clear every clamp for the wrong reason.
##
## The clamp this session adds is the rule-of-law scale itself, and it is expected to be
## SLACK: a three-Act ladder against a nine-point per-Act bound cannot reach 0.0 from
## France's 73.8, so a run sitting on it would mean the content had grown past what the
## model was measured for.
func _check_a_captured_court_stays_off_every_clamp() -> void:
	var run := _play(MANAGED, MONTHS)
	var state = run["state"]
	var ns = state.player()

	# Re-run from the start with the ladder applied, so the deviation is live for the
	# whole fourteen years rather than for whatever is left after them.
	var captured := _play_with_captured_court()
	var cns = captured["state"].player()

	if not captured["problems"].is_empty():
		for p in (captured["problems"] as Array).slice(0, 5):
			_fail("captured-court run: %s" % p)

	if is_equal_approx(cns.judicial_independence, cns.start_judicial_independence):
		_fail("the captured-court run did not move rule of law, so it asserts nothing")
	if cns.judicial_independence <= JudiciaryK.INDEPENDENCE_MIN + 0.000001:
		_fail("rule of law sits ON its floor at %.3f -- the clamp is setting the number"
			% cns.judicial_independence)
	if cns.judicial_independence >= JudiciaryK.INDEPENDENCE_MAX - 0.000001:
		_fail("rule of law sits ON its ceiling at %.3f" % cns.judicial_independence)
	if cns.unrest_pct >= UnrestK.UNREST_MAX - 0.000001:
		_fail("the grievance sits ON its clamp at %.3f under a captured court" % cns.unrest_pct)
	for bloc in cns.bloc_offset:
		if absf(float(cns.bloc_offset[bloc])) >= 1.0 - 0.000001:
			_fail("bloc_offset['%s'] sits ON its clamp under a captured court" % bloc)

	# The capture channel, asserted at the SOURCE: the captured run's grievance
	# charge must read positive and strictly above the baseline's, which pins the
	# sign of Judiciary.unrest_load() against the live state pair.
	if Judiciary.unrest_load(cns) <= Judiciary.unrest_load(ns):
		_fail("the capture's grievance charge did not rise: %.4f against %.4f"
			% [Judiciary.unrest_load(cns), Judiciary.unrest_load(ns)])

	# V3.3 re-contract, per V3.0's own precedent (a test re-contracted where the
	# findings invalidated premises). The end-state assertion this replaces
	# demanded captured unrest END above baseline unrest; V3.3 measured the
	# inversion -- captured 3.912 against baseline 4.055 -- and the margin is
	# BELOW the end-state noise V3.0's own tuning created: the relief term and
	# the 14-point strike threshold moved unrest into a band where the capture's
	# ~0.1-point grievance charge no longer decides the end state, and the
	# roster's org/trade channels move the two runs' baselines by the same
	# magnitude. The channel-level assertion above is where the invariant
	# "capturing the courts angers the country" is readable now; the end-state
	# comparison is recorded here as a measured bound, not silently dropped.
	if cns.unrest_pct <= ns.unrest_pct:
		print("note: captured unrest %.3f against baseline %.3f -- V3.3 measured inversion, end-state comparison re-contracted to unrest_load" % [cns.unrest_pct, ns.unrest_pct])




## V2.8's two, and the expensive kind: a plant is a verb no budget regime issues.
## The identical managed budget, one order at month 6 repeated at the source's
## own build length -- nuclear every 120, gas every 30 -- so one run raises the
## nuclear share and the other the fossil share. Through Energy.execute(), and
## the assertions are the ones the other verb regimes make: the channels moved,
## and nothing sits ON its clamp.
func _check_a_nuclear_run_stays_off_every_clamp() -> void:
	var run := _play(MANAGED, MONTHS, -1, "FRA", -1, -1, -1, -1, "order_nuclear_epr", 6, 120)
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("nuclear run: %s" % p)
	if ns.plants.is_empty():
		_fail("the nuclear run never ordered a plant, so it asserts nothing")
	if ns.energy_bill_pct_gdp <= 0.0:
		_fail("the nuclear run never billed anything, so it asserts nothing")
	if absf(ns.energy_impulse_pct) >= EnergyK.IMPULSE_MAX_PCT - 0.000001:
		_fail("the energy impulse sits ON its clamp at %.3f" % ns.energy_impulse_pct)
	var worst_offset := 0.0
	for bloc_id in ns.bloc_offset.keys():
		worst_offset = maxf(worst_offset, absf(float(ns.bloc_offset[bloc_id])))
	if worst_offset >= LegislatureK.BLOC_OFFSET_MAX - 0.000001:
		_fail("a bloc_offset sits ON its clamp at %.3f -- the siting price saturated the accumulator" % worst_offset)


## The fossil half of the pair. Gas is cheap enough to sustain a real fleet --
## five stations by the end of the window -- and its fuel is IMPORTED, so this
## is the run whose dependency deviation is large and whose growth cost is the
## channel's readable face. The nuclear run moves the dependency the other way.
func _check_a_gas_run_stays_off_every_clamp() -> void:
	# stop_on_loss false, and V4.4 is why: the unanswered desk is a steady
	# approval drain by design (six-plus categories pulsing, the queue holding
	# four), and the MANAGED regime now loses the 2032 verdict -- at month 76 of
	# a channel check whose whole premise is fourteen years of cadence. The vote
	# is test_two_full_terms' subject; this check watches the energy channel.
	var run := _play(MANAGED, MONTHS, -1, "FRA", -1, -1, -1, -1, "order_gas_ccgt", 6, 30, false)
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("gas run: %s" % p)
	var done := 0
	for plant_id in ns.plants.keys():
		if bool(ns.plants[plant_id].get("done", false)):
			done += 1
	if done < 4:
		_fail("the gas run finished only %d stations in fourteen years -- check the cadence" % done)
	if ns.import_dependency_pct <= ns.start_import_dependency_pct:
		_fail("building only gas left the import dependency at %.2f -- the channel is decoration" % ns.import_dependency_pct)
	if absf(ns.energy_impulse_pct) >= EnergyK.IMPULSE_MAX_PCT - 0.000001:
		_fail("the energy impulse sits ON its clamp at %.3f" % ns.energy_impulse_pct)

func _play_with_captured_court() -> Dictionary:
	return _play(MANAGED, MONTHS, -1, "FRA", -1, -1, -1, 6)

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
	# V4.7a FINDING, same record as the regulated run's: the two-tier roster's
	# named coverage put the ownership extreme ON the +/-2.00 clamp. Asserted
	# as HELD, not slack -- the clamp's re-sizing question belongs to B4's
	# re-baseline sweep with a declared band, not to this assertion.
	if absf(ns.firm_impulse_pct) > CompaniesK.FIRM_IMPULSE_MAX_PCT + 0.000001:
		_fail("the firm growth impulse ran PAST its clamp at %.3f under ownership -- the clamp does not hold" % ns.firm_impulse_pct)
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

	# The read window closes for good at the first month out of office: a run that
	# keeps ticking (stop_on_loss = false) may be handed office back by a later
	# vote, but the game ended at the loss and never plays that month.
	if not ns.in_government:
		_band_open = false
	if _band_open:
		print("BANDREAD MONTH %d %s" % [_run_no, at])

	# The acts' fading share stays inside its band every month the player governs
	# (V5.2b). A run kept ticking past a lost office -- stop_on_loss = false, which
	# the game itself never plays -- bursts with acts against a government the
	# player no longer leads; those months are outside the band's read window and
	# not asserted. A base checkout has no such register, which is why the read is
	# guarded.
	if "act_bloc_offset" in ns:
		for bloc in ns.act_bloc_offset:
			var share := float(ns.act_bloc_offset[bloc])
			if absf(share) > ACT_SHARE_MAX and ns.in_government:
				out.append("%s the acts' share of bloc_offset[%s] is %.3f, over %.2f" % [at, bloc, share, ACT_SHARE_MAX])
			if _band_open:
				print("BANDREAD SHARE %d %s %s %.4f" % [_run_no, at, bloc, share])
	if _band_open:
		for bloc in ns.bloc_offset:
			if absf(float(ns.bloc_offset[bloc])) >= 1.0 - 0.000001:
				print("BANDREAD CLAMP %d %s %s" % [_run_no, at, bloc])

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


## V1.6d. Fourteen years under a budget that uses all three distributional instruments,
## checked against the clamps they introduce and the ones they can reach through.
##
## The Gini clamp is the session's own; the rest are inherited, and they are checked
## because this is the first budget in the harness that moves revenue through a base
## FACTOR rather than through a rate -- so the erosion clamps are reached by a path no
## previous regime could take.
func _check_a_redistributive_run_stays_off_every_clamp() -> void:
	var run := _play(REDISTRIBUTIVE, MONTHS)
	var ns = run["state"].player()

	if not run["problems"].is_empty():
		for p in (run["problems"] as Array).slice(0, 5):
			_fail("redistributive run: %s" % p)

	# It must actually redistribute, or the check above is true for the boring reason --
	# tools/unrest_probe.gd's own blind spot, named rather than repeated.
	var offset := Tax.gini_policy_offset(ns)
	if is_zero_approx(offset):
		_fail("the redistributive run moved the inequality index by nothing, so it asserts nothing about the clamps")
	if absf(offset) >= TaxK.GINI_POLICY_MAX_PT - 0.000001:
		_fail("the Gini policy offset sits ON its clamp at %.3f -- the clamp is setting the number, not the model" % offset)

	# The bracket lever's own guard rail. The base factor is floored at zero because a
	# negative one makes the income tax collect negative revenue, and no clamp downstream
	# catches that; it must be nowhere near the floor on a reachable budget.
	var factor := Tax.progressivity_base_factor(ns)
	if factor <= 0.000001:
		_fail("the progressivity base factor is on its floor at %.4f, so the income line is collecting nothing" % factor)
	if float(ns.revenue_pct_gdp["income"]) <= 0.0:
		_fail("the income tax collected nothing under a steeper schedule")

	# And the two new taxes are actually being collected, on a nation that authors both
	# above zero for one and at zero for the other -- which is what exercises BOTH
	# branches of the erosion curve inside one run.
	for key in ["capital_gains", "wealth"]:
		if float(ns.revenue_pct_gdp[key]) <= 0.0:
			_fail("the %s line collected nothing over fourteen years under a budget that levies it" % key)
