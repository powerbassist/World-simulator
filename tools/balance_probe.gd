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
## (any family since V5.0c0). `--list` prints the serial order, one
## `REGIME <name>` line each, and runs nothing -- tools/balance_parallel.py
## runs one probe per name and splices the tables back in that order.
##
## Pass `--json=PATH` (absolute, or res://) to also write the outcome table: one
## row per verdict the text prints and one per run, which tools/balance_diff.py
## compares between two trees -- a re-baseline read off a diff of the verdicts
## rather than by eye across the whole text. Nothing extra goes to stdout, so the
## text of a run that writes the table is byte-identical to one that does not.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const BlocK = preload("res://src/sim/bloc_constants.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const Characters = preload("res://src/sim/characters.gd")
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
const Bills = preload("res://src/sim/bills.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const CampaignK = preload("res://src/sim/campaign_constants.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Events = preload("res://src/sim/events.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const DemographyK = preload("res://src/sim/demography_constants.gd")
const SocietyK = preload("res://src/sim/society_constants.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const Migration = preload("res://src/sim/migration.gd")
const Regions = preload("res://src/sim/regions.gd")
const Energy = preload("res://src/sim/energy.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

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
##
## V5.2 b+ R14: the nationalisation is a bill. `managed_nationalises` tables it and
## the Assembly may refuse it -- the honest record of what an ordinary bill meets.
## `managed_nationalises_493` carries the same bill by Article 49.3 (`force`), so
## the ownership channel stays measured whatever the Assembly thinks of it.
const OWNERSHIP_REGIMES := {
	"managed_nationalises": {"budget": REGIMES["managed"], "nationalise_month": 6},
	"managed_nationalises_493": {"budget": REGIMES["managed"], "nationalise_month": 6, "force": true},
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

## V1.6d. *** THREE NEW REGIMES, AND THEY ARE NEEDED FOR THE REASON V1.5c's BLIND SPOT
## WAS: the twenty-nine regimes above set three tax keys and no schedule, so the whole of
## this session is STRUCTURALLY UNREACHABLE BY EVERY ONE OF THEM. *** (a), (b) and (c)
## each needed none because a statistic is not a verb; a tax is, which is V1.3a's rule
## coming back for the first time in this block.
##
## The third takes docs/unrest-model.md's own mid-run switch shape, because a
## distributional lever is slow and the reachable case is *govern well, win, then
## redistribute* rather than *provoke in month 1 and lose in 2027*.
const TAX_REGIMES := {
	"redistributive": {
		"budget": {
			"tax_rates_pct": {"capital_gains": 10.0, "wealth": 0.5},
			"tax_progressivity": 0.5,
		},
	},
	"flat_tax": {
		"budget": {
			"tax_rates_pct": {"capital_gains": -15.0},
			"tax_progressivity": -0.7,
		},
	},
	"managed_then_redistributive": {
		"budget": REGIMES["managed"],
		"switch_month": 20,
		"switch_delta": {
			"tax_rates_pct": {"capital_gains": 10.0, "wealth": 0.5},
			"tax_progressivity": 0.5,
		},
	},
}

## V1.6e. *** TWO NEW REGIMES, AND THEY ARE THE EXPENSIVE KIND. *** An investment
## programme is a verb no budget regime issues, so the harness had to learn it exactly
## as V1.3c, V1.3g, U6a, V1.4a and V1.4c each did; V1.4b's and V1.5a's were the cheap
## kind only because a law at a month was already a shape this file knew. Every one of
## the thirty-two regimes above is structurally unreachable by this session.
##
## `industrial_policy` backs the largest sector at the harshest authored intensity from
## month 6 and never withdraws -- the reachable worst case for the bill, the trend
## channel and the guard rail at once, which is the shape the subsidy and the burden
## regimes both take.
##
## `managed_then_invest` takes docs/unrest-model.md's mid-run switch shape for
## docs/tax-model.md's reason: this lever's t90 is sixty months, so the reachable case
## is *govern well, win the first election, then commit* rather than *commit in month 1
## and be thrown out in 2027 before a single point of capital has been built*. That is
## V1.5c's blind spot named in advance rather than discovered by a probe that ran a
## government already out of office.
const INVESTMENT_REGIMES := {
	"industrial_policy": {"budget": REGIMES["managed"], "invest_month": 6},
	"managed_then_invest": {"budget": REGIMES["managed"], "invest_month": 30},
}

## V1.6f. *** TWO NEW REGIMES, AND THEY ARE THE EXPENSIVE KIND AGAIN. *** A project is
## a verb no budget regime issues, so the harness has to learn it exactly as V1.3c,
## V1.3g, U6a, V1.4a, V1.4c and V1.6e each did. Every one of the thirty-four regimes
## above is structurally unreachable by this session.
##
## `public_works` begins the two projects the content gate permits from month 6 and
## never abandons either -- the reachable worst case for the bill, the payoff and the
## accumulator's guard rail at once, which is the shape the subsidy, the burden, the
## nationalisation and the investment programme all take.
##
## `managed_then_build` takes the mid-run switch shape V1.5c invented and V1.6e reused,
## and it matters more here than in either: the largest project takes ninety-six months
## to open, so a government that commits in month 1 and loses in 2027 has measured a
## build nobody ever collected. Month 30 is after the first presidential election and
## leaves the shorter of the two projects finishing inside the run. V1.5c's blind spot
## named in advance rather than discovered by a probe that ran a government already out
## of office.
const PROJECT_REGIMES := {
	"public_works": {"budget": REGIMES["managed"], "build_month": 6},
	"managed_then_build": {"budget": REGIMES["managed"], "build_month": 30},
}

## V1.7a: the campaign phase. TWO regimes and not one, because the whole decision the
## lever poses is about TIMING and one regime cannot show a decision. `campaigns_early`
## puts two efforts in the field the month the run-up opens and pays for all eight;
## `campaigns_late` puts the same two in with two months to go. Same budget, same
## efforts, different month -- so the pair isolates exactly what the window is for.
##
## France's first executive election is May 2027, index 16 of this loop, and
## campaign_constants.CAMPAIGN_WINDOW_MONTHS is 8, so the run-up is indices 8 to 16.
## Early takes the whole eight months; late takes two. A month outside the window would
## report a verb refused, which is a test of the refusal and not of the campaign --
## tests/test_campaign.gd owns that one.
##
## THE FIRST PAIR OF MONTHS WAS 9 AND 16 AND BOTH WERE WRONG, which the run showed
## rather than the reading: 16 IS the month of the vote, so "late" campaigned for zero
## months and printed a presidential result identical to "early" to the digit.
## V2.8's two, and the expensive kind again: a plant is a verb no budget regime
## issues. One order at month 6, repeated at the source's own build length --
## nuclear every 120 months, gas every 30 -- so the nuclear run raises the
## nuclear share and the gas run the fossil share, on the identical managed
## budget. The pair is what makes the dependency channel legible: two runs whose
## ONLY difference is which branch the verb builds.
const ENERGY_REGIMES := {
	"managed_builds_nuclear": {"budget": REGIMES["managed"], "energy_month": 6, "energy_action": "order_nuclear_epr", "energy_repeat": 120},
	"managed_builds_gas": {"budget": REGIMES["managed"], "energy_month": 6, "energy_action": "order_gas_ccgt", "energy_repeat": 30},
}

const CAMPAIGN_REGIMES := {
	"managed_campaigns_early": {"budget": REGIMES["managed"], "campaign_month": 8},
	"managed_campaigns_late": {"budget": REGIMES["managed"], "campaign_month": 14},
	# V2.6b2: the tour. Opens at the same month as `early`, then four months in STOPS
	# the effort and starts the next-ranked one at its own best site -- which is the
	# decision the saturation counter exists to make, and the one the other two
	# regimes cannot show because they never re-choose a place. `campaign_month` is
	# what feeds _run's existing hook; `campaign_tour_month` is the new one.
	"managed_campaigns_tour": {"budget": REGIMES["managed"], "campaign_month": 8,
		"campaign_tour_month": 12},
}

## V1.7b: does a promise change anything, and does BREAKING it change anything else?
## Two regimes, the same budget and THE SAME PROMISE, differing only in whether the
## president keeps it -- which is the only comparison that isolates the price from the
## reward, because both regimes pay the reward.
##
## `pledge_month` is 9 because that is the month France's run-up opens on a 2026 start,
## and a promise can only be made inside it. The breaking regime reuses V1.5c's
## `switch_month` / `switch_delta` rather than adding a mechanism: govern well, win the
## vote, then raise the income tax the tax lock forbids. That is the reachable way to
## break a promise, and V1.5c built the harness for it a block early.
## V1.7c: the referendum and the electoral system. TWO regimes, and both are the
## EXPENSIVE kind -- a referendum and an electoral-reform Act are verbs no budget regime
## issues, so neither could be reached by any of the thirty-eight already here.
##
## `referendum_month` is 6 rather than the first month, because route B needs the
## assembly to carry the bill by an ordinary majority first and the run has to be past
## its opening budget shock for that to mean anything. The vote lands
## REFERENDUM_DELAY_MONTHS later, which is inside the first presidential term by
## construction -- that is band (ii) in src/sim/referendum_constants.gd, exercised here
## rather than only measured there.
##
## `electoral_month` is 6 for the same reason and is a DIFFERENT verb: an ordinary Act,
## carried in the chamber, changing how the NEXT legislative election allocates seats.
## Its effect is invisible until June 2029, which is index 41, so a regime that stopped
## at the first election would print an identical run -- the reason the horizon here is
## fourteen years and not one term.
const REFERENDUM_REGIMES := {
	"managed_calls_a_referendum": {"budget": REGIMES["managed"], "referendum_month": 6, "electoral_month": -1},
	"managed_reforms_the_ballot": {"budget": REGIMES["managed"], "referendum_month": -1, "electoral_month": 6},
}

## V1.8. THE ONLY THING THAT VARIES ACROSS THESE THREE IS WHETHER THE PLAYER OPENS
## THE WINDOW, which is what docs/pledge-model.md's own regime pair failed to hold: it
## differed in two things at once and needed a third regime to separate them. Here the
## budget is identical, the events are identical, and the arrival month of every one of
## them is identical -- the hazard is a pure function of (nation, event, absolute month),
## so an answering run and a defaulting run face the SAME crises on the SAME dates.
##
## `managed` itself is the control and needs no entry: a regime that never answers is a
## regime that takes every default, which is exactly what the base run already does.
const EVENT_REGIMES := {
	"managed_answers_softly": {"budget": REGIMES["managed"], "answer": "soft"},
	"managed_answers_hard": {"budget": REGIMES["managed"], "answer": "hard"},
}

## V1.1e's regimes, and they are the EXPENSIVE kind: a bill is a verb and no budget
## regime issues one. Three, because the session's three outcomes are three different
## machines and folding them into one regime would be docs/pledge-model.md's confounded
## pair repeating -- a run that differs in two things at once cannot say which one moved.
##
##   held       the second chamber refuses a bill the Assembly carried, it comes into
##              force UPPER_HOLD_MONTHS later, and the release charges the override.
##   struck     both chambers carry a bill and the court stops it, so the player pays
##              the division and gets nothing.
##   captured   the whole three-Act ladder, which is the only run in this harness that
##              moves rule of law at all.
const CHAMBER_REGIMES := {
	"managed_bill_is_held": {"budget": REGIMES["managed"], "kind": "held"},
	"managed_bill_is_struck": {"budget": REGIMES["managed"], "kind": "struck"},
	"managed_captures_the_courts": {"budget": REGIMES["managed"], "kind": "captured"},
}

const PLEDGE_REGIMES := {
	"managed_keeps_its_word": {
		"budget": REGIMES["managed"],
		"pledge_month": 9,
		"switch_month": -1,
		"switch_delta": {},
	},
	"managed_breaks_its_word": {
		"budget": REGIMES["managed"],
		"pledge_month": 9,
		"switch_month": 30,
		"switch_delta": {"tax_rates_pct": {"income": 8.0}, "spending_pct_gdp": {"health": -4.0}},
	},
	# THE CONTROL, and the first run without it demonstrated the wrong thing. The
	# breaking regime raises the income tax and cuts the health line, and BOTH of those
	# move approval on their own through issues S5 built -- so `breaks_its_word` against
	# `keeps_its_word` prints the budget and the promise added together and attributes
	# all of it to the promise. This regime runs the identical switch and promises
	# NOTHING, so the pair that isolates the price is this one against `breaks_its_word`.
	# tests/test_trade.gd needed the same control at V1.6a and V1.6c needed it twice.
	"managed_breaks_nothing": {
		"budget": REGIMES["managed"],
		"pledge_month": -1,
		"switch_month": 30,
		"switch_delta": {"tax_rates_pct": {"income": 8.0}, "spending_pct_gdp": {"health": -4.0}},
	},
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


## The outcome table `--json=PATH` writes: see the header.
var _outcomes: Array = []
var _runs: Array = []

## V5.0c0's selection: the one regime asked for ("" = all), whether this run only
## lists the serial order, the names seen, and how many ran.
var _only := ""
var _listing := false
var _listed: Array = []
var _ran := 0


func _want(name: String) -> bool:
	_listed.append(name)
	if _listing or (_only != "" and name != _only):
		return false
	_ran += 1
	return true


func _init() -> void:
	var only := ""
	var nation_id := "FRA"
	var json_path := ""
	# Either bare token may be the regime name or the nation id -- a nation id
	# is always three uppercase letters, which no regime name is, so order
	# doesn't matter: `-- managed DEU` and `-- DEU managed` both work.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--json="):
			json_path = arg.substr("--json=".length())
			continue
		if arg == "--list":
			_listing = true
			continue
		if arg.length() == 3 and arg == arg.to_upper():
			nation_id = arg
		else:
			only = arg
	_only = only

	# V5.0c0. EVERY regime is runnable on its own now, by name, in any family --
	# tools/balance_parallel.py runs one probe per regime and merges their tables
	# in the order below, which `--list` prints. Each loop asks _want(); a plain
	# run wants everything, so its order and its output are what they always were.
	var names: Array = REGIMES.keys()
	for name in names:
		if not _want(name):
			continue
		_run(nation_id, name, REGIMES[name])

	for name in DISSOLUTION_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = DISSOLUTION_REGIMES[name]
		_run(nation_id, name, regime["budget"], int(regime["dissolve_month"]))
	for name in CABINET_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = CABINET_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, int(regime["shortfall_month"]))
	for name in AMENDMENT_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = AMENDMENT_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, int(regime["amend_month"]), String(regime["amendment_id"]))
	for name in TRANSITION_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = TRANSITION_REGIMES[name]
		_run(String(regime["nation_id"]), name, regime["budget"], -1, -1, int(regime["amend_month"]), String(regime["amendment_id"]))
	for name in TRADE_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = TRADE_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, -1, "", int(regime["agreement_month"]))
	for name in COERCION_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = COERCION_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, int(regime["tariff_month"]))
	for name in DEFENCE_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = DEFENCE_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, int(regime["pact_month"]), int(regime["deploy_month"]))
	for name in CALENDAR_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = CALENDAR_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, int(regime["book_month"]))
	for name in COMPANY_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = COMPANY_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, int(regime["subsidy_month"]))
	for name in REGULATION_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = REGULATION_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, int(regime["regulate_month"]))
	for name in OWNERSHIP_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = OWNERSHIP_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, int(regime["nationalise_month"]))
	for name in SOCIETY_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = SOCIETY_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, int(regime["corrupt_month"]))
	for name in DEMOGRAPHY_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = DEMOGRAPHY_REGIMES[name]
		_run(nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, int(regime["migrate_month"]))
	for name in MEDIA_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = MEDIA_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, {},
			int(regime["censor_month"])
		)
	for name in UNREST_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = UNREST_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
			int(regime["settle_month"]),
			int(regime.get("switch_month", -1)), regime.get("switch_delta", {})
		)
	for name in TAX_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = TAX_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
			int(regime.get("switch_month", -1)), regime.get("switch_delta", {})
		)
	for name in INVESTMENT_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = INVESTMENT_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, {}, -1,
			int(regime["invest_month"])
		)
	for name in PROJECT_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = PROJECT_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, {}, -1,
			-1, int(regime["build_month"])
		)

	for name in ENERGY_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = ENERGY_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, {}, -1,
			-1, -1, -1, -1, -1, -1, "", "", -1,
			int(regime["energy_month"]), String(regime["energy_action"]), int(regime["energy_repeat"])
		)

	for name in CAMPAIGN_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = CAMPAIGN_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, {}, -1,
			-1, -1, int(regime["campaign_month"]), -1, -1, -1, "", "",
			int(regime.get("campaign_tour_month", -1))
		)

	for name in PLEDGE_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = PLEDGE_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
			int(regime["switch_month"]), regime["switch_delta"], -1,
			-1, -1, -1, int(regime["pledge_month"])
		)

	for name in EVENT_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = EVENT_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, {}, -1,
			-1, -1, -1, -1, -1, -1, String(regime["answer"])
		)

	for name in CHAMBER_REGIMES.keys():
		if not _want(name):
			continue
		var chamber_regime: Dictionary = CHAMBER_REGIMES[name]
		_run(
			nation_id, name, chamber_regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, {}, -1,
			-1, -1, -1, -1, -1, -1, "", String(chamber_regime["kind"])
		)

	for name in REFERENDUM_REGIMES.keys():
		if not _want(name):
			continue
		var regime: Dictionary = REFERENDUM_REGIMES[name]
		_run(
			nation_id, name, regime["budget"], -1, -1, -1, "", -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, {}, -1,
			-1, -1, -1, -1, int(regime["referendum_month"]), int(regime["electoral_month"])
		)

	# One name, one regime: a name two families shared would run twice here and
	# be ambiguous to the sharded runner.
	var seen := {}
	for listed in _listed:
		if seen.has(listed):
			printerr("regime name '%s' is defined twice" % listed)
			quit(1)
			return
		seen[listed] = true
	if _listing:
		for listed in _listed:
			print("REGIME %s" % listed)
		quit(0)
		return
	if only != "" and _ran == 0:
		printerr("unknown regime '%s'; known: %s" % [only, _listed])
		quit(1)
		return
	_write_outcomes(json_path)
	quit(0)


## One verdict as a row. `margin` is the incumbent's vote share less the best
## rival's, so a HELD verdict reads positive and a LOST one negative, and a
## shrinking lead shows up before it flips.
func _outcome_row(regime_name: String, nation_id: String, r: Dictionary, kind: String, verdict: String) -> Dictionary:
	var shares: Dictionary = r.get("vote_share", {})
	var incumbent := String(r["incumbent_party_id"])
	var own := float(shares.get(incumbent, 0.0))
	var rival := 0.0
	for party_id in shares:
		if String(party_id) != incumbent:
			rival = maxf(rival, float(shares[party_id]))
	return {
		"regime": regime_name, "nation": nation_id,
		"year": int(r["year"]), "month": int(r["month"]),
		"kind": kind, "verdict": verdict,
		"vote_share": own, "margin": own - rival,
		"incumbent_seats": int(r["incumbent_seats"]), "seats_total": int(r["seats_total"]),
	}


func _write_outcomes(path: String) -> void:
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("could not write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify({"elections": _outcomes, "runs": _runs}, "  ", false))
	f.close()


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
	# V1.6d. A DELTA like the two above it, against the nation's own start, which is what
	# keeps a regime nation-relative. Clamped to the model's band rather than to [0, 100],
	# because the schedule is an index and not a rate.
	if delta.has("tax_progressivity"):
		pending["tax_progressivity"] = clampf(
			float(ns.start_tax_progressivity) + float(delta["tax_progressivity"]),
			TaxK.PROGRESSIVITY_MIN, TaxK.PROGRESSIVITY_MAX
		)
	return pending


func _run(nation_id: String, regime_name: String, delta: Dictionary, dissolve_month: int = -1, cabinet_shortfall_month: int = -1, amend_month: int = -1, amendment_id: String = "", agreement_month: int = -1, tariff_month: int = -1, pact_month: int = -1, deploy_month: int = -1, book_month: int = -1, subsidy_month: int = -1, regulate_month: int = -1, nationalise_month: int = -1, corrupt_month: int = -1, migrate_month: int = -1, settle_month: int = -1, switch_month: int = -1, switch_delta: Dictionary = {}, censor_month: int = -1, invest_month: int = -1, build_month: int = -1, campaign_month: int = -1, pledge_month: int = -1, referendum_month: int = -1, electoral_month: int = -1, answer_events: String = "", chamber_kind: String = "", campaign_tour_month: int = -1,
		energy_month: int = -1, energy_action_id: String = "", energy_repeat_months: int = 0) -> void:
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
	# A Dictionary, not a float: the step hook below is a lambda, and a lambda
	# captures a local by value.
	var run := {"peak_unrest": 0.0}
	var out_of_government := ""

	var year := START_YEAR
	var month := 1
	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		# The month is src/sim/world_month.gd's: main.gd's order, every system in
		# it, so a re-run cannot agree with the game about a model the game no
		# longer runs (V1.5d's bug class, which this loop's hand copy repeated
		# system by system until the copy was retired). What this harness adds runs
		# through the step hook, at the slot it ran in when the loop was a copy.
		var report := WorldMonth.tick_month(state, loader, func(step: String, after: bool, step_report: Dictionary) -> void:
			if after and step == "Unrest":
				run["peak_unrest"] = maxf(float(run["peak_unrest"]), float(ns.unrest_pct))
				return
			if after and step == "Events":
				# V1.8. Answered ON ARRIVAL rather than at some month before the
				# deadline, and that is deliberate: tests/test_events.gd pins that
				# answering early and answering late cost the same, so a regime that
				# waited would differ from this one in nothing except how long the
				# card sat there.
				if answer_events != "":
					_answer_event(state, loader, ns, answer_events, regime_name, year, month)
				return
			if after and step == "Characters":
				# V4.3. The acts are PRINTED (one line per act) so the re-run's
				# prediction -- idle regimes fire ~zero acts, act lines are the only
				# new output -- is checkable from the diff itself.
				for _act in step_report["character_acts"]:
					print("characters: %s %s" % [regime_name, String(_act["act"])])
				return
			if after or step != "Elections":
				return

			# Everything a regime DOES, after the month's systems and before the vote:
			# the slot it has always had.
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
			if i + 1 == invest_month:
				_invest(state, loader, ns, regime_name, year, month)
			if i + 1 == build_month:
				_break_ground(state, loader, ns, regime_name, year, month)

			# V2.8's two regimes, on the same cadence the plan wrote for them: an order
			# at `energy_month`, repeated at the source's own build length, so a
			# fourteen-year run sustains a FLEET rather than a single station. Through
			# Energy.execute() and never by writing ns.plants -- a regime that bypasses
			# the verb tests a model the player cannot reach. The siting region is the
			# nation's largest by live population share, ties broken by the sorted scan,
			# because a regime needs a deterministic answer and not an opinion.
			if energy_action_id != "" and i + 1 >= energy_month and (i + 1 - energy_month) % energy_repeat_months == 0:
				var e_action = null
				for a in loader.energy_actions:
					if a.id == energy_action_id:
						e_action = a
				if e_action != null:
					var e_weights: Dictionary = {}
					var e_largest := ""
					var e_best: float = -1.0
					for region in loader.regions.get(nation_id, []):
						var share: float = Migration.region_share(ns, region.id)
						e_weights[region.id] = share
						if share > e_best:
							e_best = share
							e_largest = region.id
					var e_access: Dictionary = Regions.accessibility_for(
						ns, state.regions.get(nation_id, []), state.region_graph)
					Energy.execute(state, ns, loader, loader.energy_actions, e_action,
						Vector2(0.0, 0.0), e_largest, "", e_access, e_weights)
			if i + 1 == campaign_month:
				_campaign(state, loader, ns, regime_name, year, month)
			# V2.6b2: four months into the field, stand the effort down and start the
			# next-ranked one at ITS best site -- the tour the saturation counter makes
			# worth taking.
			if i + 1 == campaign_tour_month:
				_campaign_tour(state, loader, ns, regime_name, year, month)
			if i + 1 == pledge_month:
				_promise(state, loader, ns, regime_name, year, month)
			if i + 1 == referendum_month:
				_call_referendum(state, loader, ns, regime_name, year, month)
			if i + 1 == electoral_month:
				_reform_the_ballot(state, loader, ns, regime_name, year, month)
			# V1.1e. At month 6, the same month every other law regime fires.
			if i + 1 == 6 and chamber_kind != "":
				_meet_the_second_chamber(state, loader, ns, regime_name, chamber_kind, year, month)

			# U6a. The day loop this file has never had, and it runs for EVERY regime
			# rather than only the one that books -- a dispatch that only ever executes
			# under the regime designed to exercise it is not a dispatch anybody has
			# tested. With an empty register Calendar.due() is one is_empty() check, so
			# the thirteen regimes above are provably unchanged by it. The month's
			# Calendar.tick_month() prune has already run inside WorldMonth; it never
			# drops an open booking, so this loop dispatches what it did when the prune
			# ran after it.
			state.day = 0
			for d in range(_days_in_month(month, year)):
				state.day = d + 1
				for appointment in Calendar.due(state, year, month, state.day):
					_keep_appointment(state, loader, appointment, regime_name)

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
		)

		var results: Array = report["election_results"]
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
				var standing := "COHABITATION" if ns.is_cohabitation else ("MINORITY" if ns.is_minority else "majority")
				elections.append("%d-%02d %s: legislative — incumbent %d/%d seats, government %d/%d %s" % [
					r["year"], r["month"], regime_name,
					r["incumbent_seats"], r["seats_total"],
					ns.coalition_seats, ns.assembly_seats,
					standing,
				])
				_outcomes.append(_outcome_row(regime_name, nation_id, r, "legislative", standing))
				continue
			var verdict_kind := "executive" if ns.has_executive else "national"
			if r["kind"] != verdict_kind:
				continue
			var verdict := "HELD" if r["incumbent_largest"] else "LOST"
			if r["kind"] == "executive":
				# One office, no seats to report.
				elections.append("%d-%02d %s: presidential — incumbent %.1f%% vote — %s" % [
					r["year"], r["month"], regime_name,
					r["incumbent_vote_share"] * 100.0,
					verdict,
				])
			else:
				elections.append("%d-%02d %s: incumbent %.1f%% vote, %d/%d seats — %s" % [
					r["year"], r["month"], regime_name,
					r["incumbent_vote_share"] * 100.0, r["incumbent_seats"],
					r["seats_total"], verdict,
				])
			_outcomes.append(_outcome_row(regime_name, nation_id, r, String(r["kind"]), verdict))
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
			out_of_government = "%d-%02d" % [year, month]
			break

	for line in elections:
		print("  " + line)

	# V1.5c. The reachability column, printed for EVERY regime rather than only the two
	# that settle. A channel whose act never fires makes twenty-five bit-identical
	# regimes prove nothing about it -- U6a's day-loop finding, and it is measured here
	# rather than assumed because tools/unrest_probe.gd's own harness has no elections
	# and so cannot see a run that ENDS before the grievance matures.
	print("  unrest: peak %.2f, ended at %.2f, acts %d (threshold %.1f)" % [
		float(run["peak_unrest"]), ns.unrest_pct, state.unrest_acts.size(), UnrestK.UNREST_THRESHOLD_PCT,
	])
	_runs.append({
		"regime": regime_name, "nation": nation_id,
		"out_of_government": out_of_government,
		"problems": problems.size(),
		"unrest_acts": state.unrest_acts.size(),
	})
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
## V1.8. Answer whatever is on the desk, softly or hard, and print what was chosen.
##
## `soft` takes the non-default choice with the largest size-weighted `bloc_offset` and
## `hard` takes the smallest. THE FIRST VERSION OF THIS FUNCTION CALLED THEM `best` AND
## `worst`, AND THE RUN REFUTED THE NAMES: over fourteen years the SOFT run ends 0.4
## points of approval BELOW the hard one and 0.33 points of deficit worse, because the
## choices that buy the most approval on the day are the ones that concede money -- a
## settlement, an underwriting, a spending line -- and the books are something the
## electorate weighs too.
##
## That is docs/campaign-model.md's own finding in a new place: maximising the thing you
## can see at the moment of the decision is not the same as being better off a term
## later. Both still beat the control, which is the property the deadline needs.
##
## V4.4: the slot is a desk of up to QUEUE_MAX entries, and five shipped events carry
## `respond_months == 1`, so a second same-month arrival would default unanswered if only
## the head were taken. Every entry on the desk is answered, by id, each under the same
## rule; the ids are snapshotted first because answering removes entries and re-orders.
func _answer_event(state, loader, ns, mode: String, regime_name: String, year: int, month: int) -> void:
	var ids: Array[String] = []
	for entry in ns.event_queue:
		var entry_id := String(entry.get("event_id", ""))
		if entry_id != "" and not ids.has(entry_id):
			ids.append(entry_id)
	for event_id in ids:
		var ev = Events.event_by_id(loader, event_id)
		if ev == null:
			continue
		var pick: Dictionary = {}
		var pick_score := 0.0
		for c in ev.choices:
			if bool(c["is_default"]):
				continue
			var score := 0.0
			var terms: Dictionary = (c["effects"] as Dictionary).get("bloc_offset", {})
			for bloc in terms:
				score += float(K.BLOC_SIZE.get(bloc, 0.0)) * float(terms[bloc])
			if pick.is_empty() or (score > pick_score if mode == "soft" else score < pick_score):
				pick = c
				pick_score = score
		if pick.is_empty():
			continue
		var record := Events.answer(state, loader, event_id, String(pick["id"]))
		if record.is_empty():
			continue
		print("  %d-%02d %s: '%s' -> %s" % [
			year, month, regime_name, ev.event_name, String(pick["label"]),
		])


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


## V1.7c. Route B: carry the amendment in the chamber by an ordinary majority, then the
## country votes REFERENDUM_DELAY_MONTHS later. Nothing is applied at the press --
## Legislature.tick_month() settles it, which is why this regime needs no second hook.
func _call_referendum(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var law = _find_law(loader, "single_term_reform")
	if law == null:
		print("  %s: single_term_reform is not in the law list" % regime_name)
		return
	if not Legislature.can_put_to_referendum(ns, law):
		print("  %s: no referendum route at %04d-%02d" % [regime_name, year, month])
		return
	var result := Legislature.propose(state, loader, law, false, true)
	print("  %s: %04d-%02d referendum on %s -- chamber %d/%d, called=%s" % [
		regime_name, year, month, law.id,
		int(result.get("yes_seats", 0)), int(result.get("seats_total", 0)),
		result.get("referendum_called", false),
	])


## V1.7c. An ORDINARY Act changing how the assembly is elected. Not an amendment: the
## bar is the chamber's own absolute majority, which is instance forty-three's
## correction exercised rather than only argued.
func _reform_the_ballot(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var law = _find_law(loader, "proportional_representation_act")
	if law == null:
		print("  %s: proportional_representation_act is not in the law list" % regime_name)
		return
	var before: String = ns.election_system
	var result := Legislature.propose(state, loader, law, false)
	print("  %s: %04d-%02d electoral reform -- %d/%d, %s -> %s" % [
		regime_name, year, month,
		int(result.get("yes_seats", 0)), int(result.get("seats_total", 0)),
		before, ns.election_system,
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

	# The heaviest partner the verb is OFFERED against: since R10 a fellow member of
	# a customs union is refused (FRA's heaviest, DEU, shares the EU), and a refused
	# verb would quietly turn this regime into `managed` -- a run that measures no
	# coercion at all while the table still names it.
	var best := ""
	var best_weight := -1.0
	var weights := Trade.weights(state, ns.id)
	for id in weights.keys():
		if not Diplomacy.available(state, loader.diplomatic_actions, ns.id, id).has(action):
			continue
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

	# V5.2 b+ R14: a full nationalisation is a bill -- tabled for the largest firm,
	# it divides like any law, and the purchase lands only if it carries.
	var bills: Array = Bills.ownership(state, ns, loader, best)
	if bills.is_empty():
		printerr("  no ownership bill is offered for %s" % best)
		return
	var debt_before: float = ns.debt_eur_bn
	var forced := bool(OWNERSHIP_REGIMES.get(regime_name, {}).get("force", false))
	var result: Dictionary = Legislature.propose(state, loader, bills[0], forced)
	print("  %d-%02d %s: nationalisation bill for %s%s %s (yes %d / no %d), stake %.2f (%.1f bn, debt %+.1f bn)" % [
		year, month, regime_name, best, " by 49.3" if forced else "", "CARRIED" if bool(result.get("passed", false)) else ("HELD" if bool(result.get("held_by_upper", false)) else "DEFEATED"),
		int(result.get("yes_seats", 0)), int(result.get("no_seats", 0)),
		Companies.state_share_of(ns, best), best_output, ns.debt_eur_bn - debt_before,
	])

func _meet_the_second_chamber(state, loader, ns, regime_name: String, kind: String,
		year: int, month: int) -> void:
	var party_list: Array = loader.parties.get(ns.id, [])

	if kind == "captured":
		for law_id in ["judicial_appointments_reform", "court_jurisdiction_limits",
				"judicial_tenure_act"]:
			for law in loader.laws:
				if law.id != law_id:
					continue
				var rung := Legislature.propose(state, loader, law)
				print("  %d-%02d %s: '%s' %s -- rule of law now %.1f" % [
					year, month, regime_name, law.id,
					"passed" if bool(rung["passed"]) else "did not pass",
					ns.judicial_independence,
				])
		return

	for law in loader.laws:
		if law.constitutional:
			continue
		if not bool(Legislature.resolve_vote(ns, party_list, law, false)["passed"]):
			continue
		var upper_agrees: bool = bool(Legislature.resolve_upper(ns, party_list, law)["passed"])
		if kind == "held" and upper_agrees:
			continue
		if kind == "struck" and (not upper_agrees or not Judiciary.strikes_down(ns, law)):
			continue
		var result := Legislature.propose(state, loader, law)
		print("  %d-%02d %s: '%s' -- %s" % [
			year, month, regime_name, law.id, _chamber_verdict(result)])
		return
	printerr("  no law in the content reaches the '%s' outcome" % kind)


func _chamber_verdict(result: Dictionary) -> String:
	if bool(result.get("held_by_upper", false)):
		return "held by the second chamber for %d months" % int(result.get("held_months", 0))
	if bool(result.get("blocked_by_upper", false)):
		return "blocked by the second chamber"
	if bool(result.get("struck_down", false)):
		return "struck down: reach %.2f against a tolerance of %.2f" % [
			float(result.get("reach", 0.0)), float(result.get("tolerance", 0.0))]
	return "passed" if bool(result["passed"]) else "defeated"


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
				# execute() returns `applied` -- V2.4a, same correction main.gd
				# needed; the probe copies the orchestrator faithfully.
				ok = bool(result.get("applied", false))
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


## V1.6e. Backs the LARGEST sector by output at the harshest authored intensity and
## leaves the programme standing for the rest of the run -- _subsidise()'s shape and
## for its reason: a regime that backs a sector too small to move anything measures
## the content rather than the channel.
##
## Largest by output rather than by name, so this stays nation-relative the way every
## other regime in this file is.
## V1.6f. Begins every project the content's own `project_count` gate permits, longest
## first, and never abandons one. The gate is read off Projects.available() rather than
## counted here, so a content change that widens or narrows it moves this regime with
## it -- the concurrency ceiling is content, which is why projects_constants.gd ships no
## constant for it.
func _break_ground(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var starts: Array = []
	for a in loader.project_actions:
		if String(a.effects.get("project", {}).get("op", "")) == "start":
			starts.append(a)
	starts.sort_custom(func(x, y):
		return (
			int(x.effects["project"]["build_months"]) > int(y.effects["project"]["build_months"])
		)
	)

	var begun: Array[String] = []
	for a2 in starts:
		if Projects.execute(state, ns, loader.project_actions, a2).get("applied", false):
			begun.append("%s (%d mo)" % [a2.id, int(a2.effects["project"]["build_months"])])
	if begun.is_empty():
		printerr("  no project could be begun")
		return
	print("  %d-%02d %s: broke ground on %s" % [year, month, regime_name, ", ".join(begun)])


## Puts every effort the concurrency gate will take into the field, best first.
##
## *** ORDERED BY A LIVE SCORE AND NOT BY PRICE, AND THE FIRST VERSION WAS ORDERED BY
## PRICE. *** That version reasoned that a regime picking the optimal pair would be
## measuring tools/campaign_probe.gd's answer rather than the model -- and it produced
## a presidential result identical to `managed` to the digit, because cheapest-first
## picks the pair that probe's table (h) measures at +0.058 points, the weakest positive
## of the ten. A demonstration of nothing is not a demonstration. Every other verb in
## this harness is exercised at something a president would plausibly do, and this is
## the correction that brings the campaign into line with them.
##
## The score is DERIVED at the moment of acting rather than hard-coded: each effort's
## own mobilisation vector is applied over a full window as a hypothetical, and the
## efforts are ranked by what it does to the incumbent's LEAD over the runner-up. The
## lead and not the share, because a plurality verdict turns on the lead -- and probe
## table (h) found the two objectives disagree, so choosing on the share would have been
## choosing the wrong one. Nothing about this rule names an effort or a nation.
func _campaign(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var party_list: Array = loader.parties.get(ns.id, [])
	var base_gap: float = _incumbent_gap(Elections.vote_share(ns, party_list, ns.incumbent_party_id), ns.incumbent_party_id)

	# V2.6b2: the ranking is over (effort x site) PAIRS now -- the place is half the
	# decision, and ranking efforts alone would answer a question nobody is asking.
	# The pre-apply multiplies by the site's AVERAGE factor over a full-window camp
	# (_camp_window_factor), the same approximation the raw window multiplication made
	# before siting: honest about being a ranking score and not a prediction.
	var starts: Array = []
	var score := {}
	var site_of_pair := {}
	for a in loader.campaign_actions:
		var terms: Dictionary = a.effects.get("campaign", {})
		if String(terms.get("op", "")) != "start":
			continue
		starts.append(a)
		for region in loader.regions.get(ns.id, []):
			var rid := String(region.id)
			var site_scale: float = _camp_window_factor(ns, loader, rid)
			var truth: Dictionary = ns.campaign_mobilisation.duplicate()
			for bloc in terms.get("mobilisation", {}):
				ns.campaign_mobilisation[bloc] = clampf(
					float(terms["mobilisation"][bloc]) * float(CampaignK.CAMPAIGN_WINDOW_MONTHS) * site_scale,
					-CampaignK.MOBILISATION_MAX, CampaignK.MOBILISATION_MAX
				)
			var key := "%s|%s" % [a.id, rid]
			score[key] = _incumbent_gap(
				Elections.vote_share(ns, party_list, ns.incumbent_party_id), ns.incumbent_party_id
			) - base_gap
			site_of_pair[key] = rid
			ns.campaign_mobilisation = truth

	var pairs: Array = []
	for key in score:
		pairs.append(key)
	pairs.sort_custom(func(x, y): return float(score[x]) > float(score[y]))

	var begun: Array[String] = []
	for key in pairs:
		var action_id := String(key).split("|")[0]
		var a2 = null
		for a3 in starts:
			if String(a3.id) == action_id:
				a2 = a3
				break
		if a2 == null:
			continue
		if Campaign.execute(state, ns, loader.campaign_actions, a2, String(site_of_pair[key])).get("applied", false):
			# The score is the RANKING score -- what a full window of this effort alone
			# would do to the lead -- and not a prediction of this run. A regime opening
			# with two months to go collects a fraction of it, which is the whole point
			# of the window, so the label says "full window" rather than leaving a reader
			# to compare it against a result it was never about.
			begun.append("%s @ %s (%.3f%%, %+.3f pts over a full window)" % [
				a2.id, String(site_of_pair[key]),
				float(a2.effects["campaign"]["cost_pct_gdp"]), float(score[key]) * 100.0,
			])
	if begun.is_empty():
		printerr("  no campaign effort could be started (%d months to the vote)" % Campaign.months_to_election(state, ns))
		return
	print("  %d-%02d %s: campaign opens with %s" % [year, month, regime_name, ", ".join(begun)])


## The tour's second leg: stop whatever is running, then let _campaign start the
## best-ranked remaining (effort x site) pair. `campaign_started` keeps the stood-down
## effort spent, so the second leg genuinely moves -- effort and place both, which is
## the saturation counter's whole point.
func _campaign_tour(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var stopped := ""
	for eid in Campaign.running(ns):
		var action = _campaign_stop_action(loader, String(eid))
		if action != null and Campaign.execute(state, ns, loader.campaign_actions, action).get("applied", false):
			stopped = String(eid)
	if stopped == "":
		printerr("  %d-%02d %s: tour leg found nothing running to stop" % [year, month, regime_name])
		return
	print("  %d-%02d %s: tour stands down %s" % [year, month, regime_name, stopped])
	_campaign(state, loader, ns, regime_name, year, month)


func _campaign_stop_action(loader, effort_id: String) -> Variant:
	for a in loader.campaign_actions:
		var terms: Dictionary = a.effects.get("campaign", {})
		if String(terms.get("op", "")) == "stop" and String(terms.get("effort_id", "")) == effort_id:
			return a
	return null


## The average per-month factor one effort camping at this site delivers over a full
## window: the fresh factor times the saturation discount as it decays under the
## meeting it holds every month. The ranking score's scale, not a prediction.
func _camp_window_factor(ns, loader, site: String) -> float:
	var fresh: float = Campaign.fresh_factor(ns, loader, site)
	var spoken := 0.0
	var total := 0.0
	for month in CampaignK.CAMPAIGN_WINDOW_MONTHS:
		total += fresh * (1.0 - spoken)
		spoken = minf(1.0, spoken + 1.0)
		spoken *= pow(0.5, 1.0 / CampaignK.SATURATION_HALF_LIFE_MONTHS)
	return total / float(CampaignK.CAMPAIGN_WINDOW_MONTHS)


## The incumbent's lead over the best other party -- what a plurality verdict turns on.
func _incumbent_gap(shares: Dictionary, incumbent: String) -> float:
	var mine: float = float(shares.get(incumbent, 0.0))
	var best_other := 0.0
	for pid in shares:
		if String(pid) != incumbent:
			best_other = maxf(best_other, float(shares[pid]))
	return mine - best_other
## V1.7b. One promise, named rather than chosen: the tax lock is the only entry on the
## ladder whose field a BUDGET regime can move, so it is the only one where "kept" and
## "broken" are two runs of the same harness rather than two different worlds.
##
## Made through Pledges.execute() rather than by writing the register, so the run
## exercises the window gate, the concurrency gate and the reward exactly as a click
## would. It prints its refusal rather than failing silently, because a regime whose
## verb never fired is a regime that demonstrates nothing -- V1.5c's finding, and the
## reason balance_probe.gd prints a reachability column at all.
func _promise(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	for action in loader.pledges:
		if action.id != "pledge_no_new_taxes":
			continue
		var result := Pledges.execute(state, ns, loader.pledges, action)
		if bool(result.get("applied", false)):
			print("  %d-%02d %s: promised '%s', binds to %s" % [
				year, month, regime_name,
				String(result.get("pledge_name", "?")), String(result.get("binds_until", "?")),
			])
		else:
			print("  %d-%02d %s: the promise was REFUSED -- %d months to the vote" % [
				year, month, regime_name, Campaign.months_to_election(state, ns),
			])
		return
	printerr("  pledge 'pledge_no_new_taxes' not found in data/pledges")




func _invest(state, loader, ns, regime_name: String, year: int, month: int) -> void:
	var best := ""
	var best_output := -1.0
	for sector in ns.sector_investment.keys():
		var out: float = float(ns.sector_output.get(sector, 0.0))
		if out > best_output:
			best_output = out
			best = String(sector)

	var action = null
	for a in loader.investment_actions:
		var terms: Dictionary = a.effects.get("investment", {})
		if String(terms.get("op", "")) != "invest" or String(terms.get("sector", "")) != best:
			continue
		if action == null or float(terms["intensity"]) > float(action.effects["investment"]["intensity"]):
			action = a
	if action == null:
		printerr("  no 'invest' action is authored for sector '%s'" % best)
		return

	var result := Investment.execute(state, ns, loader.investment_actions, action)
	print("  %d-%02d %s: investment '%s' in %s — %s (intensity %.2f)" % [
		year, month, regime_name, action.id, best,
		"APPLIED" if result.get("applied", false) else "REFUSED",
		float(result.get("intensity_after", 0.0)),
	])
