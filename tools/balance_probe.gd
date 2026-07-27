extends SceneTree

## Balance probe: godot --headless --script res://tools/balance_probe.gd
##
## S10's evidence generator. Runs the real monthly tick — the same
## Economy/Budget/Opinion/Legislature/Elections sequence src/ui/main.gd wires the
## clock through — for fourteen simulated years under several fixed policy
## regimes, and reports what every headline number did.
##
## Not a test. tests/test_balance.gd asserts the invariants this probe is used to
## *find*; this prints trajectories a human reads while tuning. Kept in tools/
## rather than tests/ for exactly that reason, and excluded from run_tests.sh.
##
## Pass a regime name to run one: --headless --script ... -- hands_off

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Government = preload("res://src/sim/government.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")

const MONTHS := 168  # fourteen years: covers the inherited term plus two full ones
const START_YEAR := 2026


## Each regime is a budget committed once, in month 1, and then left alone —
## the crudest possible player, which is the point: if a constant policy blows
## the model up, a real player certainly will.
const REGIMES := {
	"hands_off": {},
	"spendthrift": {
		"spending_pct_gdp": {
			"health": 14.0, "education": 8.0, "defence": 3.5,
			"pensions": 18.0, "infrastructure": 6.0,
		},
		"tax_rates_pct": {"income": 14.0, "corporate": 18.0, "vat": 16.0},
	},
	"austerity": {
		"spending_pct_gdp": {
			"health": 8.5, "education": 3.5, "defence": 1.0,
			"pensions": 11.0, "infrastructure": 1.5,
		},
		"tax_rates_pct": {"income": 26.0, "corporate": 30.0, "vat": 24.0},
	},
	# The budget a player who reads the polling panel should converge on: cut the
	# line only one bloc weights (defence), fund it with the tax that carries no
	# labour-market cost (VAT), leave the three lines every bloc weights alone,
	# and take the deficit down to where the debt ratio stops climbing.
	"managed": {
		"spending_pct_gdp": {
			"health": 11.0, "education": 5.5, "defence": 0.6,
			"pensions": 14.5, "infrastructure": 3.5,
		},
		"tax_rates_pct": {"income": 21.0, "corporate": 25.0, "vat": 23.0},
	},
	# The same player getting it wrong: churn every line, upset the blocs that
	# weight them, and end up with a *worse* deficit than doing nothing.
	"tinkering": {
		"spending_pct_gdp": {
			"health": 11.0, "education": 6.5, "defence": 2.0,
			"pensions": 13.5, "infrastructure": 5.0,
		},
		"tax_rates_pct": {"income": 21.0, "corporate": 24.0, "vat": 21.0},
	},
	"tax_max": {"tax_rates_pct": {"income": 60.0, "corporate": 50.0, "vat": 35.0}},
	"tax_zero": {"tax_rates_pct": {"income": 0.0, "corporate": 0.0, "vat": 0.0}},
	"spend_max": {
		"spending_pct_gdp": {
			"health": 30.0, "education": 20.0, "defence": 20.0,
			"pensions": 30.0, "infrastructure": 20.0,
		},
	},
	"spend_zero": {
		"spending_pct_gdp": {
			"health": 0.0, "education": 0.0, "defence": 0.0,
			"pensions": 0.0, "infrastructure": 0.0,
		},
	},
	# Both giveaways at once. The hardest case in the set, and not because it is
	# the most extreme: public_finances saturates at -1 under spend_max alone, so
	# zeroing every tax on top of it adds three saturated *positives* and a jobs
	# boost against a negative that cannot get any worse. If the weights are
	# wrong, making the fiscal position strictly worse makes the player strictly
	# more popular.
	"ruinous": {
		"spending_pct_gdp": {
			"health": 30.0, "education": 20.0, "defence": 20.0,
			"pensions": 30.0, "infrastructure": 20.0,
		},
		"tax_rates_pct": {"income": 0.0, "corporate": 0.0, "vat": 0.0},
	},
}

## V1.1c: does calling a dissolution actually gamble on how the player has
## governed? Two regimes, same budgets as above, each dissolving once well
## clear of DISSOLUTION_BLACKOUT_MONTHS and of the scheduled 2029-06 vote —
## `dissolve_month` is the simulated month count (1-indexed) at which
## Dissolution.dissolve() fires. `managed` should return a bigger coalition
## than the assembly it replaced; `austerity`, already discipline-eroded by the
## time it could plausibly call one, is the harder case.
const DISSOLUTION_REGIMES := {
	"managed_dissolves_early": {"budget": REGIMES["managed"], "dissolve_month": 8},
	"austerity_dissolves_late": {"budget": REGIMES["austerity"], "dissolve_month": 10},
}

## V1.1d: does a deliberately bad cabinet assignment survive contact with a
## full governed run, not just cabinet_probe.gd's isolated effectiveness sweep?
## Each regime strips the largest coalition partner's biggest portfolio and
## hands it to a weaker-fit partner at `shortfall_month` -- shorting the
## stripped party below its d'Hondt entitlement, the condition
## docs/cabinet-model.md ties to a reachable resignation.
const CABINET_REGIMES := {
	"managed_cabinet_shorted": {"budget": REGIMES["managed"], "shortfall_month": 6},
	"austerity_cabinet_shorted": {"budget": REGIMES["austerity"], "shortfall_month": 6},
}


func _init() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		only = arg

	var names: Array = REGIMES.keys()
	if only != "":
		if not REGIMES.has(only):
			printerr("unknown regime '%s'; known: %s" % [only, names])
			quit(1)
			return
		names = [only]

	for name in names:
		_run(name, REGIMES[name])

	if only == "":
		for name in DISSOLUTION_REGIMES.keys():
			var regime: Dictionary = DISSOLUTION_REGIMES[name]
			_run(name, regime["budget"], int(regime["dissolve_month"]))
		for name in CABINET_REGIMES.keys():
			var regime: Dictionary = CABINET_REGIMES[name]
			_run(name, regime["budget"], -1, int(regime["shortfall_month"]))

	quit(0)


func _run(regime_name: String, pending: Dictionary, dissolve_month: int = -1, cabinet_shortfall_month: int = -1) -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	var state = GameState.new_game(loader, "FRA")
	state.year = START_YEAR
	state.month = 1

	print("\n=== %s ===" % regime_name)
	_print_header()

	var ns = state.player()
	var party_list: Array = loader.parties.get("FRA", [])
	if not pending.is_empty():
		Budget.commit(state, pending)

	var elections: Array[String] = []
	var problems: Array[String] = []

	var year := START_YEAR
	var month := 1
	for i in range(MONTHS):
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
		Discipline.tick_month(state, loader)
		Legislature.tick_month(state)
		Dissolution.tick_month(state)
		Cabinet.tick_month(state, loader)

		if i + 1 == dissolve_month:
			var before_seats: int = ns.coalition_seats
			Dissolution.dissolve(state, ns)
			if ns.dissolution_pending:
				print("  %d-%02d %s: DISSOLVED — coalition %d/%d before the call" % [
					year, month, regime_name, before_seats, ns.assembly_seats,
				])
			else:
				print("  %d-%02d %s: dissolution REFUSED — %s" % [
					year, month, regime_name, Dissolution.refusal_reason(state, ns),
				])

		if i + 1 == cabinet_shortfall_month:
			_short_the_largest_partner(state, ns, party_list, regime_name, year, month)

		var results := Elections.tick_month(state, loader)
		for r in results:
			if r["kind"] == "national" and bool(r.get("snap", false)):
				print("  %d-%02d %s: SNAP resolved — coalition now %d/%d" % [
					r["year"], r["month"], regime_name, ns.coalition_seats, ns.assembly_seats,
				])
			# The verdict on the player is the EXECUTIVE election where one
			# exists — France's presidency, May 2027 and every five years after.
			# A legislative election reshapes the assembly and re-forms the
			# government but cannot remove the player, so it is reported
			# separately rather than scored as a win or a loss.
			if r["kind"] == "national" and ns.has_executive:
				elections.append("%d-%02d %s: legislative — incumbent %d/%d seats, government %d/%d %s" % [
					r["year"], r["month"], regime_name,
					r["incumbent_seats"], r["seats_total"],
					ns.coalition_seats, ns.assembly_seats,
					"COHABITATION" if ns.is_cohabitation else ("MINORITY" if ns.is_minority else "majority"),
				])
				continue
			var verdict_kind := "executive" if ns.has_executive else "national"
			if r["kind"] != verdict_kind:
				continue
			if r["kind"] == "executive":
				# One office, no seats to report.
				elections.append("%d-%02d %s: presidential — incumbent %.1f%% vote — %s" % [
					r["year"], r["month"], regime_name,
					r["incumbent_vote_share"] * 100.0,
					"HELD" if r["incumbent_largest"] else "LOST",
				])
			else:
				elections.append("%d-%02d %s: incumbent %.1f%% vote, %d/%d seats — %s" % [
					r["year"], r["month"], regime_name,
					r["incumbent_vote_share"] * 100.0, r["incumbent_seats"],
					r["seats_total"], "HELD" if r["incumbent_largest"] else "LOST",
				])
			# What the result screen tells the player. The point of printing it
			# here is that it must name the number the player actually moved.
			for a in r["attribution"]:
				elections.append("      %-16s salience %.2f  satisfaction %+.2f" % [
					a["issue"], a["salience"], a["satisfaction"],
				])

		problems.append_array(_check(ns, year, month))
		if (i + 1) % 12 == 0:
			_print_row(ns, year)
			_print_discipline_row(ns, loader.parties.get(ns.id, []))

		if not ns.in_government:
			print("  (out of government from %d-%02d; simulation stops)" % [year, month])
			break

	for line in elections:
		print("  " + line)
	if cabinet_shortfall_month > 0:
		print("  resignations over the run: %d (last: %s)" % [ns.resignations_count, ns.last_resignation])
	if problems.is_empty():
		print("  invariants: OK over %d months" % MONTHS)
	else:
		for p in problems.slice(0, 8):
			print("  PROBLEM " + p)
		if problems.size() > 8:
			print("  ... and %d more" % (problems.size() - 8))


## V1.1d: strips the largest coalition partner's biggest-affinity portfolio
## and hands it to the weakest-fit OTHER coalition partner -- the worst legal
## reassignment available, and the one most likely to short the stripped
## party below its d'Hondt entitlement. Prints what it did so the trajectory
## printed afterward is traceable to a concrete decision.
func _short_the_largest_partner(state, ns, party_list: Array, regime_name: String, year: int, month: int) -> void:
	var by_id := {}
	for p in party_list:
		by_id[p.id] = p

	var largest := ""
	var largest_seats := -1
	for pid in ns.coalition_party_ids:
		var seats := int(ns.seats_by_party.get(pid, 0))
		if seats > largest_seats:
			largest_seats = seats
			largest = pid
	if largest == "" or not by_id.has(largest):
		return

	var target_portfolio := ""
	for f in ns.cabinet:
		if String(ns.cabinet[f]) == largest:
			target_portfolio = f
			break
	if target_portfolio == "":
		return

	var weakest_fit := ""
	var weakest_affinity := 2.0
	for pid in ns.coalition_party_ids:
		if pid == largest or not by_id.has(pid):
			continue
		var a := Cabinet.affinity(by_id[pid], target_portfolio)
		if a < weakest_affinity:
			weakest_affinity = a
			weakest_fit = pid
	if weakest_fit == "":
		return

	Cabinet.assign(state, target_portfolio, weakest_fit, party_list)
	print("  %d-%02d %s: reassigned %s from %s to %s (shortfall %.2f)" % [
		year, month, regime_name, target_portfolio, largest, weakest_fit,
		Cabinet.shortfall(ns, largest),
	])


func _print_header() -> void:
	print("  year   GDP      grow  trend  unemp  debt%%   defc%%  appr   worst bloc     spread")


## V1.1b's evidence line. A nominal majority is no longer the number that
## matters: what matters is how many seats a censure motion would actually
## collect once discipline has eroded and members have broken ranks, against the
## threshold the constitution sets.
##
## resolve_censure() is pure, so calling it here to look does not disturb the run
## -- the same property the law screen's forecast relies on.
func _print_discipline_row(ns, party_list: Array) -> void:
	var seats := 0
	var weighted := 0.0
	for pid in ns.coalition_party_ids:
		var s := int(ns.seats_by_party.get(pid, 0))
		seats += s
		weighted += float(s) * float(ns.party_discipline.get(pid, 0.0))
	var mean_discipline: float = weighted / float(seats) if seats > 0 else 0.0

	var forced := Government.resolve_censure(ns, party_list, true)
	var rebels := 0
	for pid in forced["party_rebels"]:
		rebels += int(forced["party_rebels"][pid])

	print("         discipline %.2f  coalition %3d/%d  49.3 censure %3d/%d %-6s  rebels %d" % [
		mean_discipline, ns.coalition_seats, ns.assembly_seats,
		forced["for_seats"], forced["threshold"],
		"CARRIES" if forced["carried"] else "holds", rebels,
	])


func _print_row(ns, year: int) -> void:
	var lo := 999.0
	var hi := -999.0
	var lo_bloc := ""
	for bloc in K.BLOC_KEYS:
		var v: float = float(ns.bloc_approval[bloc])
		if v < lo:
			lo = v
			lo_bloc = bloc
		hi = maxf(hi, v)
	print("  %d  %8.0f  %+5.2f  %+5.2f  %5.2f  %6.1f  %+6.2f  %5.1f  %-12s %5.1f" % [
		year, ns.gdp_eur_bn, ns.growth_annual_pct, ns.trend_annual_pct,
		ns.unemployment_pct, ns.debt_to_gdp_pct(), -ns.deficit_pct_gdp,
		ns.overall_approval_pct, "%s %.0f" % [lo_bloc.substr(0, 8), lo], hi - lo,
	])


## The three failure modes S10 is looking for: not-a-number, a value running
## away, and a value pinned against a clamp.
func _check(ns, year: int, month: int) -> Array[String]:
	var out: Array[String] = []
	var at := "%d-%02d" % [year, month]

	var scalars := {
		"gdp": ns.gdp_eur_bn, "potential": ns.potential_gdp_eur_bn,
		"growth": ns.growth_annual_pct, "trend": ns.trend_annual_pct,
		"unemployment": ns.unemployment_pct, "structural": ns.structural_unemployment_pct,
		"population": ns.population, "debt": ns.debt_eur_bn,
		"deficit": ns.deficit_pct_gdp, "revenue": ns.total_revenue_pct_gdp,
		"spending": ns.total_spending_pct_gdp, "impulse": ns.demand_impulse_pct,
		"shift": ns.potential_shift_pct, "approval": ns.overall_approval_pct,
	}
	for key in scalars:
		var v: float = float(scalars[key])
		if is_nan(v) or is_inf(v):
			out.append("%s %s is %f" % [at, key, v])
	for key in ns.sector_output:
		var v: float = float(ns.sector_output[key])
		if is_nan(v) or is_inf(v):
			out.append("%s sector %s is %f" % [at, key, v])
		elif v <= 0.0:
			out.append("%s sector %s pinned at %f" % [at, key, v])

	if ns.gdp_eur_bn <= 0.0:
		out.append("%s GDP pinned at %.3f" % [at, ns.gdp_eur_bn])
	if ns.population <= 0.0:
		out.append("%s population pinned at %.3f" % [at, ns.population])
	if ns.unemployment_pct <= 1.0 or ns.unemployment_pct >= 40.0:
		out.append("%s unemployment on its clamp at %.2f" % [at, ns.unemployment_pct])
	if ns.overall_approval_pct <= 0.5 or ns.overall_approval_pct >= 99.5:
		out.append("%s approval on its clamp at %.2f" % [at, ns.overall_approval_pct])
	if absf(ns.growth_annual_pct) >= 11.99:
		out.append("%s growth on its clamp at %.2f" % [at, ns.growth_annual_pct])
	if ns.debt_to_gdp_pct() > 1000.0:
		out.append("%s debt ratio running away at %.0f%%" % [at, ns.debt_to_gdp_pct()])

	return out
