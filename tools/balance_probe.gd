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
const Bloc = preload("res://src/sim/bloc.gd")
const BlocK = preload("res://src/sim/bloc_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Government = preload("res://src/sim/government.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const TK = preload("res://src/sim/trade_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const CoercionK = preload("res://src/sim/coercion_constants.gd")
const Defence = preload("res://src/sim/defence.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Companies = preload("res://src/sim/companies.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Media = preload("res://src/sim/media.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const DemographyK = preload("res://src/sim/demography_constants.gd")
const SocietyK = preload("res://src/sim/society_constants.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")

## The largest share of the +-SHIFT_MAX_PCT potential-shift budget that trade
## openness may claim on its own. Half: openness shares that budget with
## infrastructure, education and corporate tax, and a trade term that could take
## most of it would make a treaty out-earn every fiscal lever in the game.
const TRADE_SHIFT_BUDGET := 0.5

const MONTHS := 168  # fourteen years: covers the inherited term plus two full ones
const START_YEAR := 2026


## Each regime is a budget committed once, in month 1, and then left alone —
## the crudest possible player, which is the point: if a constant policy blows
## the model up, a real player certainly will.
##
## Expressed as DELTAS in percentage points from the nation's own starting
## rates/spending, not absolute figures -- V1.2a made starting fiscal policy
## per-nation, so an absolute "vat: 23.0" regime meant something different (or
## nothing) for a nation that starts somewhere other than France's 20.0. A
## delta is nation-relative by construction: "managed" always means "cut
## defence by 1.4 points of GDP and raise VAT by 3", whichever nation is under
## test. _resolve_pending() turns a delta back into the absolute values
## Budget.commit() expects, clamped to the loader's valid ranges.
const REGIMES := {
	"hands_off": {},
	"spendthrift": {
		"spending_pct_gdp": {
			"health": 3.0, "education": 2.5, "defence": 1.5,
			"pensions": 3.5, "infrastructure": 2.5,
		},
		"tax_rates_pct": {"income": -6.0, "corporate": -7.0, "vat": -4.0},
	},
	"austerity": {
		"spending_pct_gdp": {
			"health": -2.5, "education": -2.0, "defence": -1.0,
			"pensions": -3.5, "infrastructure": -2.0,
		},
		"tax_rates_pct": {"income": 6.0, "corporate": 5.0, "vat": 4.0},
	},
	# The budget a player who reads the polling panel should converge on: cut the
	# line only one bloc weights (defence), fund it with the tax that carries no
	# labour-market cost (VAT), leave the three lines every bloc weights alone,
	# and take the deficit down to where the debt ratio stops climbing.
	"managed": {
		"spending_pct_gdp": {"defence": -1.4},
		"tax_rates_pct": {"vat": 3.0},
	},
	# The same player getting it wrong: churn every line, upset the blocs that
	# weight them, and end up with a *worse* deficit than doing nothing.
	"tinkering": {
		"spending_pct_gdp": {
			"education": 1.0, "pensions": -1.0, "infrastructure": 1.5,
		},
		"tax_rates_pct": {"income": 1.0, "corporate": -1.0, "vat": 1.0},
	},
	"tax_max": {"tax_rates_pct": {"income": 40.0, "corporate": 25.0, "vat": 15.0}},
	# Deltas that land exactly on France's own zero -- not the clamp floor,
	# which would pin every nation's rate at 0 regardless of where it started
	# and turn a "give away every tax" regime into "every nation converges on
	# the identical absolute number", the opposite of what a nation-relative
	# regime is for.
	"tax_zero": {"tax_rates_pct": {"income": -20.0, "corporate": -25.0, "vat": -20.0}},
	"spend_max": {
		"spending_pct_gdp": {
			"health": 19.0, "education": 14.5, "defence": 18.0,
			"pensions": 15.5, "infrastructure": 16.5,
		},
	},
	"spend_zero": {
		"spending_pct_gdp": {
			"health": -11.0, "education": -5.5, "defence": -2.0,
			"pensions": -14.5, "infrastructure": -3.5,
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
			"health": 19.0, "education": 14.5, "defence": 18.0,
			"pensions": 15.5, "infrastructure": 16.5,
		},
		"tax_rates_pct": {"income": -20.0, "corporate": -25.0, "vat": -20.0},
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

## V1.2c: does a constitutional amendment actually pass, and does the run stay
## sane once it has rewritten one of its own institutional fields mid-play?
## FRA's real three_fifths is the only playable nation measured reachable --
## docs/amendment-model.md's reachability sweep found Germany's real
## two_thirds unreachable even at full term-start cohesion, so no regime
## targets DEU here.
const AMENDMENT_REGIMES := {
	"managed_amends_term_limit": {"budget": REGIMES["managed"], "amend_month": 12, "amendment_id": "abolish_term_limits"},
}

## V1.2d: does a system transition actually pass, and does the run stay sane
## once it has rewritten system_id, formation_method, censure_rule,
## dissolution_rule, amendment_rule, term_limit and the head of state all at
## once? Pinned to GBR regardless of the CLI's own nation_id -- GBR is the
## only playable nation this mechanic targets, docs/transition-model.md.
const TRANSITION_REGIMES := {
	"managed_abolishes_the_monarchy": {"budget": REGIMES["managed"], "amend_month": 12, "amendment_id": "abolish_the_monarchy", "nation_id": "GBR"},
}

## V1.3b: the only regime in this file that signs a trade agreement, and therefore
## the only one where the openness index is not exactly 1.0 and
## potential_shift_pct has a fourth writer contributing anything.
##
## That is the point of keeping it separate rather than folding trade into the ten
## budget regimes. Openness is a ratio against a no-agreement counterfactual, so
## every regime above is provably unchanged from V1.3a -- which turns the balance
## re-run from "has anything moved materially?" into "has anything moved at all?",
## and the answer has to be no. This regime is where the trade channel gets its
## fourteen years of sanity checking.
## How many times the trade regime will lift a pair to reach the counterparty
## gate before giving up.
##
## V1.3e. This was an unbounded `while` against AGREEMENT_ACCEPT_MIN, which was
## safe only because that gate read relations alone and lifting relations always
## eventually cleared it. The counterparty now weighs trade dependence and the
## terms on the table as well, so a partner can refuse for a reason no amount of
## relations work fixes -- and an unbounded loop would hang the probe rather than
## report the refusal.
const GATE_LIFT_ATTEMPTS := 12


const TRADE_REGIMES := {
	"managed_signs_agreement": {"budget": REGIMES["managed"], "agreement_month": 6},
}

## V1.3c's own fourteen years, and the eleventh regime. Same argument as the tenth:
## none of the ten budget regimes imposes a measure, so the register is empty, the
## trade multiplier is exactly 1.0, the coercion impulse exactly 0.0 and the tariff
## revenue line exactly 0.0 in every one of them -- which is what lets this
## session's re-run ask "has anything moved at all?" rather than "has anything
## moved materially?". This regime is where the coercion channel earns its keep,
## and it runs the FULL exchange: the player tariffs their largest partner, the
## partner retaliates three months later, and both sit in force for the rest of the
## term while the harness watches the clamps.
const COERCION_REGIMES := {
	"managed_imposes_tariffs": {"budget": REGIMES["managed"], "tariff_month": 6},
}

## V1.3g's own fourteen years, and the THIRTEENTH regime. Same argument as the
## eleventh and twelfth, and this session needed one where V1.3d and V1.3f did not:
## a pact and a deployment are VERBS, and no budget regime issues a command. The
## council is an institution and meets whether or not the player engages, which is
## why the bloc needed no regime of its own; an alliance does not sign itself.
##
## Signs with the player's largest partner and then deploys under it, so the run
## carries a live bill for most of the term -- the channel this session added to the
## budget, exercised once rather than nowhere.
const DEFENCE_REGIMES := {
	"managed_signs_pact": {"budget": REGIMES["managed"], "pact_month": 6, "deploy_month": 12},
}

## U6a's fourteen years, and the FOURTEENTH regime. Same argument as the
## eleventh, twelfth and thirteenth: a booking is a VERB, and no budget regime
## issues a command.
##
## But this one exists for a second reason the others did not have, and it is the
## structural one. Every regime above is a MONTH LOOP WITH NO CLOCK -- this file
## has never once called advance_one_day() -- so a diary that fires on a day is
## invisible to all thirteen, and their coming back bit-identical would mean
## nothing rather than something. The regime below steps days itself so that the
## day-resolution dispatch main.gd runs is exercised at least once here.
##
## The other thirteen call Calendar nowhere at all, so their bit-identity is a
## property of the code rather than a measurement: with an empty register the
## dispatch is one is_empty() check, and no regime books.
const CALENDAR_REGIMES := {
	"managed_books_ahead": {"budget": REGIMES["managed"], "book_month": 6},
}


## V1.4a's regime, and it is needed for the reason V1.3g's and U6a's were and
## V1.3d's and V1.3f's were not: a subsidy is a VERB, and no budget regime issues a
## command. An institution meets whether or not the player engages; a verb does not
## fire unless somebody presses it.
##
## Points at the player's largest firm by output, which is the case both channels
## are widest for -- the growth impulse scales with the firm's weight in the economy,
## and the jobs channel with the gap in labour intensity between it and the rival it
## takes share from. Left standing for the rest of the run, so the bill this regime
## reaches is the reachable worst case the clamp is measured against.
const COMPANY_REGIMES := {
	"managed_subsidises": {"budget": REGIMES["managed"], "subsidy_month": 6},
}


## V1.4b's regime, and it is the CHEAP kind of new regime: a regulation is a verb
## and no budget regime passes a law, but AMENDMENT_REGIMES and TRANSITION_REGIMES
## above already apply a law at a month, so the shape existed and only the content
## is new. That is the difference between this row and V1.3c's, V1.3g's and V1.4a's,
## each of which had to teach the harness a verb it had never seen.
##
## Applies the heaviest positive-burden rule on EVERY sector at once and never
## repeals it -- the reachable worst case the burden clamp is measured against,
## exactly as the subsidy regime above is left standing.
const REGULATION_REGIMES := {
	"managed_regulates": {"budget": REGIMES["managed"], "regulate_month": 6},
}


## V1.4c's regime, and it is the EXPENSIVE kind again: an ownership op is a verb no
## budget regime issues, so the harness had to learn it, exactly as V1.3c, V1.3g,
## U6a and V1.4a each did. V1.4b's was the cheap kind only because a law was already
## a shape the harness knew.
##
## Nationalises the largest firm and never sells it, which is the reachable worst
## case for both new numbers at once: the debt jump the bloc's own `debt_to_gdp_pct`
## rule reads, and the dividend line the clamp is measured against. Left standing
## for the same reason the subsidy and the burden are.
const OWNERSHIP_REGIMES := {
	"managed_nationalises": {"budget": REGIMES["managed"], "nationalise_month": 6},
}


## V1.5a's regime, and it is the CHEAP kind for V1.4b's reason: corruption reaches the
## quality stock through a LAW, and applying a law at a month is a shape this harness
## has known since AMENDMENT_REGIMES. Only the content is new.
##
## Applies every corruption-RAISING law and never repeals it, which is the reachable
## worst case the delivery clamp is measured against -- the treatment the subsidy, the
## burden and the nationalisation all get.
##
## THE SEVENTEEN REGIMES ABOVE ARE NOT BIT-IDENTICAL AFTER V1.5a, and this file is
## where that shows. Every session since V1.3d has had a channel reading exactly 0.0
## until a player COMMAND fired; this one's second trigger is the budget slider, which
## `managed` and `austerity` both move, so the quality stock diverges from its own
## reference in every regime that touches a spending line. Predicted in the plan before
## the run rather than discovered in the diff.
const SOCIETY_REGIMES := {
	"managed_corrupts": {"budget": REGIMES["managed"], "corrupt_month": 6},
}

## V1.5b's regime, the NINETEENTH, and it is the CHEAP kind for the same reason V1.5a's
## was: a migration stance reaches the dependency ratio through a LAW, and applying a
## law at a month is a shape this harness has known since AMENDMENT_REGIMES. Only the
## content is new.
##
## Applies every migration-TIGHTENING law and never repeals it -- the direction that
## makes the country age faster, which is the reachable worst case the dependency
## clamp is measured against, and the treatment the subsidy, the burden, the
## nationalisation and the corruption register all get.
##
## THE EIGHTEEN REGIMES ABOVE ARE NOT BIT-IDENTICAL AFTER V1.5b EITHER, and the cause
## is narrower than V1.5a's: `pensions` joined QUALITY_KEYS with a denominator that
## begins drifting in month one, so every regime moves through the pensions issue with
## no player command at all. What does NOT move any regime is the labour-force change,
## because firm_jobs_offset_pct() returns before its denominator unless a firm has
## moved, and the bloc transfer, because Bloc.net_positions() is loader-side and called
## once. Predicted in the plan before the run rather than read off the diff.
const DEMOGRAPHY_REGIMES := {
	"managed_tightens_migration": {"budget": REGIMES["managed"], "migrate_month": 6},
}

## V1.5c's regimes, the TWENTIETH and TWENTY-FIRST, and they are two DIFFERENT kinds --
## the first time this list has needed both in one session.
##
## `managed_settles` is the cheap kind, V1.5a's and V1.5b's: a settlement reaches the
## grievance through a LAW, and applying a law at a month is a shape this harness has
## known since AMENDMENT_REGIMES. It is also the legibility evidence, in `managed`
## vs `managed_corrupts` form -- same budget, one law, and the grievance path differs.
##
## `austerity_provokes` is the honest kind, and it exists because the probe MEASURED
## that it had to. tools/unrest_probe.gd table (a) reports the unforced grievance peak
## per existing regime: `hands_off` 6.7, `managed` 5.3, `spendthrift` 33.0, `ruinous`
## 23.5 -- all under a threshold of 45 -- against `austerity` 53.9, `spend_zero` 49.3
## and `tax_max` 79.7. So the channel IS reachable by three existing regimes and this
## one adds the settlement verb on top of the budget that provokes, which is the
## combination no other regime produces: a player who causes a strike and then answers
## it. Without the measurement the reachability would have been assumed, and if it had
## been wrong every shared regime would have come back bit-identical and their
## bit-identity would have meant nothing -- U6a's day-loop finding in a new place.
## V1.5d, and it is the CHEAP kind of new regime -- a law applied at a month, which is a
## shape this harness has known since AMENDMENT_REGIMES, so only the content is new.
## V1.3c, V1.3g, U6a and V1.4a each had to teach it a verb; this one teaches it nothing.
##
## The point of it is the legibility comparison: identical budget, identical everything,
## one censorship law the only difference.
const MEDIA_REGIMES := {
	"managed_censors": {"budget": REGIMES["managed"], "censor_month": 24},
}

const UNREST_REGIMES := {
	"managed_settles": {"budget": REGIMES["managed"], "settle_month": 6},
	"managed_then_austerity": {
		"budget": REGIMES["managed"],
		"switch_month": 20,
		"switch_delta": REGIMES["austerity"],
		"settle_month": -1,
	},
	"managed_then_austerity_settles": {
		"budget": REGIMES["managed"],
		"switch_month": 20,
		"switch_delta": REGIMES["austerity"],
		"settle_month": 60,
	},
}


func _init() -> void:
	var only := ""
	var nation_id := "FRA"
	# Either bare token may be the regime name or the nation id -- a nation id
	# is always three uppercase letters, which no regime name is, so order
	# doesn't matter: `-- managed DEU` and `-- DEU managed` both work.
	for arg in OS.get_cmdline_user_args():
		if arg.length() == 3 and arg == arg.to_upper():
			nation_id = arg
		else:
			only = arg

	var names: Array = REGIMES.keys()
	if only != "":
		if not REGIMES.has(only):
			printerr("unknown regime '%s'; known: %s" % [only, names])
			quit(1)
			return
		names = [only]

	for name in names:
		_run(nation_id, name, REGIMES[name])

	if only == "":
		for name in DISSOLUTION_REGIMES.keys():
			var regime: Dictionary = DISSOLUTION_REGIMES[name]
			_run(nation_id, name, regime["budget"], int(regime["dissolve_month"]))
		for name in CABINET_REGIMES.keys():
			var regime: Dictionary = CABINET_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, int(regime["shortfall_month"]))
		for name in AMENDMENT_REGIMES.keys():
			var regime: Dictionary = AMENDMENT_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, int(regime["amend_month"]), String(regime["amendment_id"]))
		for name in TRANSITION_REGIMES.keys():
			var regime: Dictionary = TRANSITION_REGIMES[name]
			_run(String(regime["nation_id"]), name, regime["budget"], -1, -1, int(regime["amend_month"]), String(regime["amendment_id"]))
		for name in TRADE_REGIMES.keys():
			var regime: Dictionary = TRADE_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, -1, "", int(regime["agreement_month"]))
		for name in COERCION_REGIMES.keys():
			var regime: Dictionary = COERCION_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, int(regime["tariff_month"]))
		for name in DEFENCE_REGIMES.keys():
			var regime: Dictionary = DEFENCE_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, int(regime["pact_month"]), int(regime["deploy_month"]))
		for name in CALENDAR_REGIMES.keys():
			var regime: Dictionary = CALENDAR_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, int(regime["book_month"]))
		for name in COMPANY_REGIMES.keys():
			var regime: Dictionary = COMPANY_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, int(regime["subsidy_month"]))
		for name in REGULATION_REGIMES.keys():
			var regime: Dictionary = REGULATION_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, int(regime["regulate_month"]))
		for name in OWNERSHIP_REGIMES.keys():
			var regime: Dictionary = OWNERSHIP_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, int(regime["nationalise_month"]))
		for name in SOCIETY_REGIMES.keys():
			var regime: Dictionary = SOCIETY_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, int(regime["corrupt_month"]))
		for name in DEMOGRAPHY_REGIMES.keys():
			var regime: Dictionary = DEMOGRAPHY_REGIMES[name]
			_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, int(regime["migrate_month"]))
		for name in MEDIA_REGIMES.keys():
			var regime: Dictionary = MEDIA_REGIMES[name]
			_run(
				nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, {},
				int(regime["censor_month"])
			)
		for name in UNREST_REGIMES.keys():
			var regime: Dictionary = UNREST_REGIMES[name]
			_run(
				nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
				int(regime["settle_month"]),
				int(regime.get("switch_month", -1)), regime.get("switch_delta", {})
			)

	quit(0)


## `delta` is a REGIMES-shaped entry: tax_rates_pct / spending_pct_gdp deltas in
## percentage points, relative to `ns`'s own starting rates -- see REGIMES'
## header comment. Absent keys are left at the nation's start.
func _resolve_pending(ns, delta: Dictionary) -> Dictionary:
	var pending := {}
	if delta.has("tax_rates_pct"):
		var rates := {}
		for key in delta["tax_rates_pct"]:
			var start: float = float(ns.start_tax_rates_pct.get(key, 0.0))
			rates[key] = clampf(start + float(delta["tax_rates_pct"][key]), 0.0, 100.0)
		pending["tax_rates_pct"] = rates
	if delta.has("spending_pct_gdp"):
		var spending := {}
		for key in delta["spending_pct_gdp"]:
			var start: float = float(ns.start_spending_pct_gdp.get(key, 0.0))
			spending[key] = clampf(start + float(delta["spending_pct_gdp"][key]), 0.0, 100.0)
		pending["spending_pct_gdp"] = spending
	return pending


func _run(nation_id: String, regime_name: String, delta: Dictionary, dissolve_month: int = -1, cabinet_shortfall_month: int = -1, amend_month: int = -1, amendment_id: String = "", agreement_month: int = -1, tariff_month: int = -1, pact_month: int = -1, deploy_month: int = -1, book_month: int = -1, subsidy_month: int = -1, regulate_month: int = -1, nationalise_month: int = -1, corrupt_month: int = -1, migrate_month: int = -1, settle_month: int = -1, switch_month: int = -1, switch_delta: Dictionary = {}, censor_month: int = -1) -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	var state = GameState.new_game(loader, nation_id)
	state.year = START_YEAR
	state.month = 1

	print("\n=== %s (%s) ===" % [regime_name, nation_id])
	_print_header()

	var ns = state.player()
	var party_list: Array = loader.parties.get(nation_id, [])
	var pending := _resolve_pending(ns, delta)
	if not pending.is_empty():
		Budget.commit(state, pending)

	var elections: Array[String] = []
	var problems: Array[String] = []
	var peak_unrest := 0.0

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
		Bloc.tick_month(state, loader)
		# V1.5d, in main.gd's slot: BEFORE Opinion, which is this channel's only reader.
		# Added to the harness in the same commit as the model, because the balance re-run
		# came back BIT-IDENTICAL without it and the prediction said it would not -- the
		# harness was running the pre-session model and its agreement meant nothing. That
		# is U6a's day-loop finding: a system this loop never calls is a system whose
		# bit-identity proves nothing about it.
		# V1.6b. See src/ui/main.gd for why this sits after Economy and before Opinion.
		Inflation.tick_month(state)
		Media.tick_month(state, loader)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)
		Discipline.tick_month(state, loader)
		Legislature.tick_month(state)
		Dissolution.tick_month(state)
		# Added at V1.3b, and inert for every regime that does not sign anything:
		# relations start at their resting value and this drifts them toward it, so
		# with no diplomatic act the step is exactly zero. It matters only once a
		# regime moves a pair, and leaving it out would have let the trade weight
		# read a relations score that never decays -- a different simulation from
		# the one main.gd runs.
		Diplomacy.tick_month(state, loader)
		# Added at V1.3g, in main.gd's slot, and inert for every regime that signs no
		# pact: with an empty pact register there is nothing to reconcile and the
		# bill is exactly 0.0, so the ten budget regimes are provably unchanged.
		# Capability DOES move here -- "managed" cuts defence by 1.4 points -- but
		# nothing in the economy reads it, which is the "no economy reader" call
		# stated where it can be checked rather than only in the model doc.
		Defence.tick_month(state)
		# Added at V1.4a, in main.gd's slot, and inert for every regime that subsidises
		# nobody: with no subsidy standing the share shift is exactly zero for every
		# firm and all three prices are exactly 0.0, so the fourteen regimes above are
		# provably unchanged by it. Unlike Defence's capability, NOTHING here moves
		# under an unsubsidised run at all -- not even a figure the economy ignores.
		Companies.tick_month(state, loader)
		# V1.5a, in main.gd's slot. NOT inert for every other regime, unlike the four
		# additions above it, and that is the difference this row exists to record: the
		# quality stock reads the live spending line, so it diverges from its own
		# reference in every regime that moves one -- `managed` and `austerity` both do.
		# The seventeen regimes above are therefore NOT bit-identical after this session,
		# which the plan predicted before the run.
		# V1.5b, immediately before Society: the quality stock divides by this layer's
		# dependency factor, so demography must have settled before quality reads it.
		Demography.tick_month(state)
		Society.tick_month(state)
		Unrest.tick_month(state)
		peak_unrest = maxf(peak_unrest, float(ns.unrest_pct))
		Cabinet.tick_month(state, loader)

		if i + 1 == agreement_month:
			_sign_agreement(state, loader, ns, regime_name, year, month)

		if i + 1 == tariff_month:
			_impose_tariffs(state, loader, ns, regime_name, year, month)

		if i + 1 == pact_month:
			_sign_pact(state, loader, ns, regime_name, year, month)

		if i + 1 == deploy_month:
			_deploy_forces(state, loader, ns, regime_name, year, month)

		if i + 1 == book_month:
			_book_ahead(state, loader, regime_name, year, month)

		if i + 1 == subsidy_month:
			_subsidise(state, loader, ns, regime_name, year, month)

		if i + 1 == regulate_month:
			_regulate(state, loader, ns, regime_name, year, month)

		if i + 1 == nationalise_month:
			_nationalise(state, loader, ns, regime_name, year, month)

		if i + 1 == corrupt_month:
			_corrupt(state, loader, ns, regime_name, year, month)
		if i + 1 == migrate_month:
			_tighten_migration(state, loader, ns, regime_name, year, month)
		if i + 1 == switch_month:
			_switch_budget(state, ns, switch_delta, regime_name, year, month)
		if i + 1 == settle_month:
			_settle(state, loader, ns, regime_name, year, month)
		if i + 1 == censor_month:
			_censor(state, loader, ns, regime_name, year, month)

		# U6a. The day loop this file has never had, and it runs for EVERY regime
		# rather than only the one that books -- a dispatch that only ever executes
		# under the regime designed to exercise it is not a dispatch anybody has
		# tested. With an empty register Calendar.due() is one is_empty() check, so
		# the thirteen regimes above are provably unchanged by it.
		state.day = 0
		for d in range(_days_in_month(month, year)):
			state.day = d + 1
			for appointment in Calendar.due(state, year, month, state.day):
				_keep_appointment(state, loader, appointment, regime_name)
		Calendar.tick_month(state)

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

		if i + 1 == amend_month and amendment_id != "":
			var law = _find_law(loader, amendment_id)
			if law == null:
				printerr("  amendment '%s' not found in data/laws" % amendment_id)
			else:
				var result := Legislature.propose(state, loader, law)
				print("  %d-%02d %s: amendment '%s' — %s (%d/%d, needed %s)" % [
					year, month, regime_name, amendment_id,
					"PASSED" if result["passed"] else "failed",
					result["yes_seats"], result["seats_total"], ns.amendment_rule,
				])

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

		problems.append_array(_check(state, ns, year, month))
		if (i + 1) % 12 == 0:
			_print_row(ns, year)
			_print_discipline_row(ns, loader.parties.get(ns.id, []))

		if not ns.in_government:
			print("  (out of government from %d-%02d; simulation stops)" % [year, month])
			break

	for line in elections:
		print("  " + line)

	# V1.5c. The reachability column, printed for EVERY regime rather than only the two
	# that settle. A channel whose act never fires makes twenty-five bit-identical
	# regimes prove nothing about it -- U6a's day-loop finding, and it is measured here
	# rather than assumed because tools/unrest_probe.gd's own harness has no elections
	# and so cannot see a run that ENDS before the grievance matures.
	print("  unrest: peak %.2f, ended at %.2f, acts %d (threshold %.1f)" % [
		peak_unrest, ns.unrest_pct, state.unrest_acts.size(), UnrestK.UNREST_THRESHOLD_PCT,
	])
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


func _find_law(loader, law_id: String):
	for law in loader.laws:
		if law.id == law_id:
			return law
	return null


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


## Sign the first authored "enter" agreement against whichever partner this nation
## already has the best relations with. Deliberately not a fixed target: the point
## is to exercise the trade channel for whichever nation the CLI was given, and
## GBR's best partner rests at 45 where France's rests at 68.
## V1.3c. Tariff the largest trade partner -- the pair where the revenue is worth
## collecting and the retaliation worth feeling. No gate to earn, unlike the
## agreement regime above: a hostile verb has no relations floor, which is the
## direction inverting that tools/coercion_probe.gd's table (e) records.
func _impose_tariffs(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var action = null
	for candidate in loader.diplomatic_actions:
		var m: Dictionary = candidate.effects.get("measure", {})
		if String(m.get("op", "")) == "impose" and String(m.get("kind", "")) == "tariff":
			action = candidate
			break
	if action == null:
		printerr("  no impose/tariff action is authored")
		return

	var best := ""
	var best_weight := -1.0
	var weights := Trade.weights(state, ns.id)
	for id in weights.keys():
		if float(weights[id]) > best_weight:
			best_weight = float(weights[id])
			best = id

	var result := Diplomacy.execute(state, loader.diplomatic_actions, action, ns.id, best)
	if not result["applied"]:
		printerr("  %d-%02d %s: could not impose tariffs on %s" % [year, month, regime_name, best])
		return
	print("  %d-%02d %s: TARIFFS on %s (w %.3f) — relations %.0f -> %.0f" % [
		year, month, regime_name, best, best_weight,
		result["relations_before"], result["relations_after"],
	])


func _sign_agreement(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var action = null
	for candidate in loader.diplomatic_actions:
		if String(candidate.effects.get("agreement", {}).get("op", "")) == "enter":
			action = candidate
			break
	if action == null:
		printerr("  no 'enter' agreement action is authored")
		return

	var best := ""
	var best_score := -1.0
	for id in state.nations.keys():
		if id == ns.id:
			continue
		var value := Diplomacy.score(state, ns.id, id)
		if value > best_score:
			best_score = value
			best = id

	# Earn the counterparty gate first if the partner will not sign yet. Every GBR
	# pair rests at the floor, so without this the regime is a refusal for one
	# playable nation in three and the trade channel gets no fourteen-year run
	# there at all. This is what a GBR player would have to do, and doing it here
	# is the difference between testing the gate and testing the model behind it.
	#
	# V1.3e: asks the counterparty rather than comparing against a relations
	# constant. AGREEMENT_ACCEPT_MIN was that constant and is deleted -- the target
	# now weighs its own trade dependence and the terms on the table too, so there
	# is no number to compare a pair score against. Bounded rather than `while`,
	# because a partner can now refuse for a reason relations cannot fix and this
	# loop would never have exited.
	var agreement_terms: Dictionary = action.effects.get("agreement", {})
	for attempt in range(GATE_LIFT_ATTEMPTS):
		if Diplomacy.would_accept_agreement(state, ns.id, best, agreement_terms):
			break
		var lift = _strongest_positive(loader)
		if lift == null:
			break
		var lifted := Diplomacy.execute(state, loader.diplomatic_actions, lift, ns.id, best)
		if not lifted["applied"]:
			break
		print("  %d-%02d %s: '%s' with %s to reach the gate — relations now %.1f" % [
			year, month, regime_name, lift.id, best, Diplomacy.score(state, ns.id, best),
		])
		ns.diplo_cooldown_months.erase(Diplomacy.cooldown_key(lift.id, best))

	var result := Diplomacy.execute(state, loader.diplomatic_actions, action, ns.id, best)
	if result["applied"]:
		# Re-read rather than reusing best_score: the loop above may have lifted it.
		print("  %d-%02d %s: signed '%s' with %s at relations %.1f — openness now %.4f" % [
			year, month, regime_name, action.id, best,
			float(result["relations_before"]), Trade.openness_index(state, ns.id),
		])
	else:
		print("  %d-%02d %s: '%s' with %s REFUSED at relations %.1f — %s" % [
			year, month, regime_name, action.id, best, best_score,
			"partner declined" if result.get("refused_by_partner", false) else "precondition or cooldown",
		])


## V1.3g. Sign with the largest trade partner, lifting the pair first if the
## counterparty would refuse -- _sign_agreement()'s shape and for its reason: a
## regime that measures the GATE rather than the model behind it tells the balance
## harness nothing about the channel this session added to the budget.
## V1.4a. Subsidises the largest firm by output at the harshest authored intensity
## and leaves it standing for the rest of the run.
func _subsidise(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var action = null
	for a in loader.company_actions:
		if String(a.effects.get("company", {}).get("op", "")) != "subsidise":
			continue
		if action == null or float(a.effects["company"]["intensity"]) > float(action.effects["company"]["intensity"]):
			action = a
	if action == null:
		printerr("  no 'subsidise' company action is authored")
		return

	var best := ""
	var best_output := -1.0
	for company in Companies.firms_of(loader, ns.id):
		var out: float = Companies.output_eur_bn(ns, company)
		if out > best_output:
			best_output = out
			best = String(company.id)
	if best == "":
		print("  %d-%02d %s: no firms are named for this nation" % [year, month, regime_name])
		return

	var result := Companies.execute(state, ns, loader.company_actions, action, best, loader)
	if result["applied"]:
		print("  %d-%02d %s: subsidised %s at intensity %.2f (%.1f bn)" % [
			year, month, regime_name, best, float(result["subsidy_after"]), best_output,
		])
	else:
		print("  %d-%02d %s: subsidy for %s REFUSED" % [year, month, regime_name, best])


## V1.4c. Nationalises the largest firm by output at the largest authored stake and
## never sells it -- _subsidise()'s shape, and left standing for its reason. Both of
## this session's numbers reach their reachable worst case this way: the debt jump at
## once and the dividend line for the rest of the run.
func _nationalise(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var action = null
	for a in loader.company_actions:
		if String(a.effects.get("company", {}).get("op", "")) != "nationalise":
			continue
		if action == null or float(a.effects["company"]["stake"]) > float(action.effects["company"]["stake"]):
			action = a
	if action == null:
		printerr("  no 'nationalise' company action is authored")
		return

	var best := ""
	var best_output := -1.0
	for company in Companies.firms_of(loader, ns.id):
		var out: float = Companies.output_eur_bn(ns, company)
		if out > best_output:
			best_output = out
			best = String(company.id)
	if best == "":
		print("  %d-%02d %s: no firms are named for this nation" % [year, month, regime_name])
		return

	var debt_before: float = ns.debt_eur_bn
	var result := Companies.execute(state, ns, loader.company_actions, action, best, loader)
	if result["applied"]:
		print("  %d-%02d %s: nationalised %s at stake %.2f (%.1f bn, debt %+.1f bn)" % [
			year, month, regime_name, best, float(result["state_share_after"]),
			best_output, ns.debt_eur_bn - debt_before,
		])
	else:
		print("  %d-%02d %s: nationalisation of %s REFUSED" % [year, month, regime_name, best])


## Legislature.apply() rather than propose(), for tests/test_balance.gd's reason:
## the assembly division belongs to tests/test_legislature.gd, and a balance row
## whose numbers depend on a chamber agreeing is a row that measures two things.
## V1.5a. Every corruption-raising law at once, never repealed -- the reachable worst
## case for the delivery factor, and the treatment _regulate() and _nationalise() both
## get. `emergency_procurement_powers` carries a 48-month cooldown, so applying it
## directly here rather than through the cooldown gate is what makes "worst case" mean
## the clamp rather than one pass of one law.
## V1.5d. Put the press under state oversight, once, and let the run carry it.
##
## ONE PASS RATHER THAN THE CLAMP, unlike _corrupt() directly below: corruption's worst
## case is what its probe needed, where this regime exists to show what ONE ordinary law
## does to an ordinary run. Saturating it would answer a question media_probe.gd already
## answers and would make the comparison against `managed` unreadable.
func _censor(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	for law in loader.laws:
		if float(law.effects.get("society", {}).get("press_freedom", 0.0)) < 0.0:
			Legislature.apply(state, ns, law, loader)
			print("  %d-%02d %s: '%s' applied -- press_freedom now %+.2f" % [
				year, month, regime_name, law.id, ns.press_freedom,
			])
			return
	printerr("  no press-restricting society law is authored")


func _corrupt(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var applied := 0
	var laws: Array = []
	for law in loader.laws:
		if float(law.effects.get("society", {}).get("corruption", 0.0)) > 0.0:
			laws.append(law)
	if laws.is_empty():
		printerr("  no corruption-raising society law is authored")
		return

	# Repeated until the register saturates, so the regime measures the clamp rather
	# than the content's own magnitude.
	while ns.corruption < SocietyK.CORRUPTION_MAX and applied < 20:
		for law in laws:
			Legislature.apply(state, ns, law, loader)
		applied += 1

	print("  [%s] %04d-%02d corruption %.2f, delivery %.3f after %d rounds" % [
		regime_name, year, month, ns.corruption, Society.delivery_factor(ns), applied,
	])


## V1.5b. Every migration-tightening law at once, never repealed -- the reachable worst
## case for the dependency ratio, and _corrupt()'s treatment one register over. Both
## migration laws carry a 24-month cooldown, so applying them directly here rather than
## through the cooldown gate is what makes "worst case" mean the clamp rather than one
## pass of one law.
func _tighten_migration(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var applied := 0
	var laws: Array = []
	for law in loader.laws:
		if float(law.effects.get("society", {}).get("migration", 0.0)) < 0.0:
			laws.append(law)
	if laws.is_empty():
		printerr("  no migration-tightening society law is authored")
		return

	while ns.migration_stance > -DemographyK.MIGRATION_STANCE_MAX and applied < 20:
		for law in laws:
			Legislature.apply(state, ns, law, loader)
		applied += 1

	print("  [%s] %04d-%02d migration stance %.2f, dependency ratio %.4f after %d rounds" % [
		regime_name, year, month, ns.migration_stance,
		Demography.dependency_ratio(ns), applied,
	])


## Applies every settlement law that CALMS, and never the ones that impose. Same call
## the subsidy, the burden, the nationalisation, the corruption register and the
## migration stance all get: the harness drives the direction the session's own bands
## are measured against, so the regime and the probe describe the same world.
## V1.5c. A budget change PART-WAY THROUGH A RUN, which this harness has never had.
##
## Every regime above commits at month 1 and never moves again, so every provocative
## budget meets the 2027 presidential election with its full damage already done and
## loses -- the run stops around month 16 and the grievance, which converges at
## UNREST_CONVERGENCE on a target it takes two years to approach, never matures. All
## twenty-five shared regimes therefore reported ZERO acts, and their bit-identity said
## nothing whatever about the channel this session added: U6a's day-loop finding, third
## instance, and this time the probe that was supposed to catch it had the same blind
## spot (tools/unrest_probe.gd's own loop has no elections, so it happily ran a losing
## government for fourteen years and reported twelve acts).
##
## What a player can actually do and no regime could express: govern well, WIN, and then
## spend the second term on a budget that provokes. That is the reachability question,
## and it needs a mid-run switch to ask.
func _switch_budget(state, ns, delta: Dictionary, regime_name: String, year: int, month: int) -> void:
	if delta.is_empty():
		return
	var pending := _resolve_pending(ns, delta)
	if pending.is_empty():
		return
	Budget.commit(state, pending)
	print("  %d-%02d %s: budget switched mid-run" % [year, month, regime_name])


func _settle(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var applied := 0
	var laws: Array = []
	for law in loader.laws:
		if float(law.effects.get("society", {}).get("settlement", 0.0)) > 0.0:
			laws.append(law)
	if laws.is_empty():
		printerr("  no calming settlement law is authored")
		return

	while ns.settlement_stance < UnrestK.SETTLEMENT_STANCE_MAX and applied < 20:
		for law in laws:
			Legislature.apply(state, ns, law, loader)
		applied += 1

	print("  [%s] %04d-%02d settlement stance %.2f, unrest %.2f after %d rounds" % [
		regime_name, year, month, ns.settlement_stance, ns.unrest_pct, applied,
	])


func _regulate(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var heaviest := {}
	for law in loader.laws:
		if law.theme != "business":
			continue
		var burden: float = float(law.effects.get("company", {}).get("burden", 0.0))
		if burden <= 0.0:
			continue
		var sector: String = String(law.effects["company"]["sector"])
		if not heaviest.has(sector) or burden > float(heaviest[sector].effects["company"]["burden"]):
			heaviest[sector] = law
	if heaviest.is_empty():
		printerr("  no positive-burden business law is authored")
		return

	var sectors: Array = heaviest.keys()
	sectors.sort()
	for sector in sectors:
		Legislature.apply(state, ns, heaviest[sector], loader)
		print("  %d-%02d %s: applied %s -- %s burden now %+.2f" % [
			year, month, regime_name, heaviest[sector].id, sector,
			float(ns.regulation_burden.get(sector, 0.0)),
		])


func _sign_pact(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var action = _pact_action(loader, "sign")
	if action == null:
		printerr("  no 'sign' pact action is authored")
		return

	var best := ""
	var best_weight := -1.0
	for id in Trade.weights(state, ns.id).keys():
		var w: float = float(Trade.weights(state, ns.id)[id])
		if w > best_weight:
			best_weight = w
			best = String(id)

	for _attempt in range(GATE_LIFT_ATTEMPTS):
		if ForeignPolicy.would_accept_pact(state, ns.id, best):
			break
		var lift = _strongest_positive(loader)
		if lift == null:
			break
		var lifted := Diplomacy.execute(state, loader.diplomatic_actions, lift, ns.id, best)
		if not lifted["applied"]:
			break
		ns.diplo_cooldown_months.erase(Diplomacy.cooldown_key(lift.id, best))

	var result := Diplomacy.execute(state, loader.diplomatic_actions, action, ns.id, best)
	if result["applied"]:
		print("  %d-%02d %s: signed a pact with %s at relations %.1f" % [
			year, month, regime_name, best, float(result["relations_before"]),
		])
	else:
		print("  %d-%02d %s: pact with %s REFUSED — %s" % [
			year, month, regime_name, best,
			result.get("refusal_reason", "precondition or cooldown"),
		])


func _deploy_forces(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var action = _pact_action(loader, "deploy")
	if action == null:
		printerr("  no 'deploy' pact action is authored")
		return

	var allies: Array = Defence.allies(state, ns.id)
	if allies.is_empty():
		print("  %d-%02d %s: no pact to deploy under" % [year, month, regime_name])
		return

	var result := Diplomacy.execute(
		state, loader.diplomatic_actions, action, ns.id, String(allies[0])
	)
	if result["applied"]:
		# The bill is deliberately NOT printed here. Defence.tick_month() runs after
		# this point in the month and Budget reads the figure the month after that,
		# so a bill printed now reads 0.000 and looks like a broken feature rather
		# than the one-month lag docs/defence-model.md argues for.
		print("  %d-%02d %s: deployed to %s — %d deployment(s), billed from next month" % [
			year, month, regime_name, String(allies[0]),
			Defence.deployment_count(state, ns.id),
		])
	else:
		print("  %d-%02d %s: deployment to %s refused" % [
			year, month, regime_name, String(allies[0]),
		])


func _pact_action(loader, op: String):
	for action in loader.diplomatic_actions:
		if String(action.effects.get("pact", {}).get("op", "")) == op:
			return action
	return null


func _strongest_positive(loader):
	var best = null
	var best_delta := 0.0
	for action in loader.diplomatic_actions:
		if not action.effects.get("agreement", {}).is_empty():
			continue
		var delta := float(action.effects.get("relations", 0.0))
		if delta > best_delta:
			best_delta = delta
			best = action
	return best


## The three failure modes S10 is looking for: not-a-number, a value running
## away, and a value pinned against a clamp.
func _check(state, ns, year: int, month: int) -> Array[String]:
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
		"external": ns.external_impulse_pct,
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
	# V1.3b. potential_shift_pct gained a fourth writer, trade openness, and its
	# clamp is the single most important guard in the model -- docs/economy-model.md
	# says so in as many words, because it is the only term feeding back into trend.
	#
	# Checks the TRADE CONTRIBUTION rather than the total, deliberately. The total
	# already sits on the clamp under `ruinous` and `spend_max`, through the
	# infrastructure writer and since S10 -- that is the guard rail doing its job on
	# a budget no sane player commits, and it is not this session's to relabel as a
	# failure. What V1.3b has to answer for is its own term, which must stay a small
	# part of the same budget rather than crowding the other three out.
	var trade_share: float = absf(TK.TRADE_OPENNESS_BETA * (Trade.openness_index(state, ns.id) - 1.0))
	if trade_share >= C.SHIFT_MAX_PCT * TRADE_SHIFT_BUDGET:
		out.append("%s trade openness claims %.3f of the +-%.1f potential-shift budget" % [
			at, trade_share, C.SHIFT_MAX_PCT,
		])
	# V1.3c. The coercion impulse is the fifth writer into growth and the first that
	# is something DONE TO the player rather than chosen by them. Bounded here for
	# the same reason the trade share above is: docs/economy-model.md's divergence
	# argument is per-quantity, so a new quantity is asserted against its own clamp
	# rather than left for GROWTH_MIN_PCT to catch downstream. Sitting ON the clamp
	# would mean the clamp and not the model is setting the growth rate.
	if absf(ns.coercion_impulse_pct) >= CoercionK.COERCION_IMPULSE_MAX:
		out.append("%s coercion impulse is ON its clamp at %.3f -- the guard rail is setting growth" % [
			at, ns.coercion_impulse_pct,
		])
	# V1.3d. Scoped DIFFERENTLY from the two above, and the difference is the point.
	# BURDEN_MAX is reached exactly when every rule in force is breached to its full
	# tolerance, because the authored severities sum to exactly it -- so touching it
	# is the model working, not a guard rail taking over. What would be a failure is
	# EXCEEDING it, which would mean a fifth rule had been authored without the sum
	# being rechecked, or the per-rule term had stopped being clamped.
	if ns.bloc_burden > BlocK.BURDEN_MAX + 1.0e-9:
		out.append("%s bloc burden %.6f is ABOVE its ceiling of %.2f -- the severities no longer sum to it" % [
			at, ns.bloc_burden, BlocK.BURDEN_MAX,
		])
	# The transfer is the fourth writer on the spending side and the first the player
	# does not set. Bounded against the same panel every other line is read on: a
	# contribution worth more than two tax points would out-weigh most of the budget
	# screen without appearing on it as anything the player can move.
	if absf(ns.bloc_transfer_pct_gdp) > 2.0 * 0.50:
		out.append("%s the Union is charging %.3f%% of GDP, over two tax points" % [
			at, ns.bloc_transfer_pct_gdp,
		])
	if ns.debt_to_gdp_pct() > 1000.0:
		out.append("%s debt ratio running away at %.0f%%" % [at, ns.debt_to_gdp_pct()])

	return out


## U6a. Books three acts three months out -- one of each bookable kind, so the
## dispatch below runs every branch of its own match rather than only the
## diplomatic one.
func _book_ahead(state, loader, regime_name: String, year: int, month: int) -> void:
	var ns = state.player()
	var when := _months_ahead(year, month, 3)
	var booked := 0

	var partners: Array = state.nations.keys()
	partners.sort()
	for target_id in partners:
		if String(target_id) == ns.id:
			continue
		var acts := Diplomacy.available(state, loader.diplomatic_actions, ns.id, String(target_id))
		if acts.is_empty():
			continue
		if bool(Calendar.book(state, Calendar.make_entry(
			CalendarK.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 7,
			String(acts[0].id), String(target_id)
		))["ok"]):
			booked += 1
		break

	var laws := Legislature.available(ns, loader.laws)
	if not laws.is_empty():
		if bool(Calendar.book(state, Calendar.make_entry(
			CalendarK.KIND_LAW, int(when["year"]), int(when["month"]), 14,
			"", "", String(laws[0].id)
		))["ok"]):
			booked += 1

	if not ns.coalition_party_ids.is_empty():
		var party_id := String(ns.coalition_party_ids[0])
		for portfolio in ns.cabinet.keys():
			if not Cabinet.can_assign(ns, String(portfolio), party_id):
				continue
			if bool(Calendar.book(state, Calendar.make_entry(
				CalendarK.KIND_RESHUFFLE, int(when["year"]), int(when["month"]), 21,
				"", "", "", String(portfolio), party_id
			))["ok"]):
				booked += 1
			break

	print("  %d-%02d %s: booked %d appointment(s) for %d-%02d" % [
		year, month, regime_name, booked, int(when["year"]), int(when["month"]),
	])


## main.gd's _resolve_appointments() dispatch, in a probe that has no orchestrator.
## Kept deliberately close to it: the point of the fourteenth regime is that the
## day-resolution path the game runs is exercised here at least once, and a
## dispatch that diverged from main.gd's would exercise something else.
func _keep_appointment(state, loader, entry: Dictionary, regime_name: String) -> void:
	var ns = state.player()
	var party_list: Array = loader.parties.get(ns.id, [])
	var ok := false
	var label := ""

	match String(entry.get("kind", "")):
		CalendarK.KIND_DIPLOMATIC:
			for action in loader.diplomatic_actions:
				if String(action.id) != String(entry.get("action_id", "")):
					continue
				var result := Diplomacy.execute(
					state, loader.diplomatic_actions, action, ns.id,
					String(entry.get("target_id", ""))
				)
				ok = bool(result.get("ok", false))
				label = String(action.action_name)
		CalendarK.KIND_LAW:
			var law = _find_law(loader, String(entry.get("law_id", "")))
			if law != null:
				var result := Legislature.propose(state, loader, law)
				ok = bool(result.get("passed", false))
				label = String(law.law_name)
		CalendarK.KIND_RESHUFFLE:
			var portfolio := String(entry.get("portfolio", ""))
			var party_id := String(entry.get("party_id", ""))
			if Cabinet.can_assign(ns, portfolio, party_id):
				Cabinet.assign(state, portfolio, party_id, party_list)
				ok = true
			label = portfolio

	Calendar.resolve(state, Calendar.verb_key(entry), ok)
	print("  %d-%02d-%02d %s: kept '%s' — %s" % [
		state.year, state.month, state.day, regime_name, label,
		"carried" if ok else "did not carry",
	])


func _months_ahead(year: int, month: int, delta: int) -> Dictionary:
	var total := year * 12 + (month - 1) + delta
	return {"year": total / 12, "month": total % 12 + 1}


## Duplicated from src/core/clock.gd rather than reached for: this file preloads
## no Node, and a probe that instantiated a Clock to ask how long February is
## would be carrying a scene-tree object through a headless month loop.
func _days_in_month(m: int, y: int) -> int:
	if m == 2 and (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)):
		return 29
	return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
