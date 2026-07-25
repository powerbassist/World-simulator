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
	quit(0)


func _run(regime_name: String, pending: Dictionary) -> void:
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
		Legislature.tick_month(state)

		var results := Elections.tick_month(state, loader)
		for r in results:
			if r["kind"] != "national":
				continue
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

		if not ns.in_government:
			print("  (out of government from %d-%02d; simulation stops)" % [year, month])
			break

	for line in elections:
		print("  " + line)
	if problems.is_empty():
		print("  invariants: OK over %d months" % MONTHS)
	else:
		for p in problems.slice(0, 8):
			print("  PROBLEM " + p)
		if problems.size() > 8:
			print("  ... and %d more" % (problems.size() - 8))


func _print_header() -> void:
	print("  year   GDP      grow  trend  unemp  debt%%   defc%%  appr   worst bloc     spread")


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
