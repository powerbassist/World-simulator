extends SceneTree

## V1.8's headless sweep: godot --headless --script res://tools/events_probe.gd
##
## THE ORDER OF THE TABLES IS THE DISCIPLINE, AND E0 IS WHY.
## docs/referendum-model.md's table R1 swept an approval range no French president can
## hold and cleared its own kill switch on states nobody reaches; R6 then measured the
## reachable range and the crossover sat outside it. V1.7c's correction was that the
## reachable range is measured FIRST and every band is written inside it -- and here that
## correction applies to CONTENT rather than to a constant, which is a place it has never
## been applied before. An event whose precondition is written outside the reachable
## range of its field is a crisis that never happens, and no test in this project would
## have caught it: the content loads, the machine works, and nothing fires.
##
## So E0 runs before a single threshold is authored, and it does a second job the plan
## names: it PREDICTS which balance regimes the re-run will move, before the re-run is
## run. A prediction written afterwards is not a prediction.
##
## E1  cadence, and the session's one tuned constant (EVENT_COOLDOWN_MONTHS).
## E2  legibility, two-sided, against a ruler that was MEASURED rather than invented.
## E3  dominance, on a live path rather than off the authored numbers.
##
## Elections run in this loop and the run STOPS when the player leaves office. That is
## not a detail: tools/unrest_probe.gd's own loop had no elections, so every table it
## printed described a government that had already been thrown out, and the balance
## harness had to catch it. V1.3f's measuring-the-wrong-state error, five times on this
## project's record, and this file is written against it rather than after it.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Events = preload("res://src/sim/events.gd")
const EventsK = preload("res://src/sim/events_constants.gd")

const START_YEAR := 2026
const RUN_MONTHS := 168
const TERM_MONTHS := 60

## The poll-noise floor this project has priced legibility against since S10.
const NOISE_FLOOR := 3.0

## What a full-term pledge breach was MEASURED to cost at V1.7b: 3.4 to 5.8 points.
## E2's ceiling is the top of that, so an event is never worth more than a promise
## broken for four years. docs/campaign-model.md's correction -- the first band clause
## it wrote was a number picked because it sounded like a margin, and the fix was to
## write the band in units of something already measured.
const PLEDGE_BREACH_CEILING := 5.8

## The six fields an event may be preconditioned on. `overall_approval_pct` is the
## seventh entry in legislature_constants.PRECONDITION_FIELDS and is REFUSED here --
## see src/sim/events_constants.gd. It is printed anyway, greyed by the marker, because
## a table that silently omits a row is how a later session re-adds it.
const FIELDS := [
	"debt_to_gdp_pct", "unemployment_pct", "deficit_pct_gdp",
	"growth_annual_pct", "unrest_pct", "terms_served",
	"overall_approval_pct",
]

## balance_probe.gd's own deltas, copied rather than imported -- tools/ files do not
## preload each other, and tools/unrest_probe.gd states the same reason.
const REGIMES := {
	"hands_off": {},
	"managed": {
		"spending_pct_gdp": {"defence": -1.4},
		"tax_rates_pct": {"vat": 3.0},
	},
	"austerity": {
		"spending_pct_gdp": {
			"health": -2.5, "education": -2.0, "defence": -1.0,
			"pensions": -3.5, "infrastructure": -2.0,
		},
		"tax_rates_pct": {"income": 6.0, "corporate": 5.0, "vat": 4.0},
	},
	"spendthrift": {
		"spending_pct_gdp": {
			"health": 3.0, "education": 2.5, "defence": 1.5,
			"pensions": 3.5, "infrastructure": 2.5,
		},
		"tax_rates_pct": {"income": -6.0, "corporate": -7.0, "vat": -4.0},
	},
	"tinkering": {
		"spending_pct_gdp": {
			"education": 1.0, "pensions": -1.0, "infrastructure": 1.5,
		},
		"tax_rates_pct": {"income": 1.0, "corporate": -1.0, "vat": 1.0},
	},
	"tax_max": {"tax_rates_pct": {"income": 40.0, "corporate": 25.0, "vat": 15.0}},
	"spend_zero": {
		"spending_pct_gdp": {
			"health": -11.0, "education": -5.5, "defence": -2.0,
			"pensions": -14.5, "infrastructure": -3.5,
		},
	},
	"ruinous": {
		"spending_pct_gdp": {
			"health": 19.0, "education": 14.5, "defence": 18.0,
			"pensions": 15.5, "infrastructure": 16.5,
		},
		"tax_rates_pct": {"income": -20.0, "corporate": -25.0, "vat": -20.0},
	},
}

## THE REACHABLE SET, and the distinction E1's band rests on. A regime that loses office
## in its first term is a state no player holds for long, so a cadence measured over it
## is a cadence measured over sixteen months of a fourteen-year horizon. `managed` is
## the budget docs/unrest-model.md calls the one a player who reads the polling panel
## converges on; `hands_off` is the one that requires no reading at all.
const REACHABLE := ["hands_off", "managed"]

## Candidate thresholds per field, printed as a hit table so a threshold is chosen off
## measured occupancy rather than off a number that sounds like a crisis.
const CANDIDATES := {
	"debt_to_gdp_pct": [110.0, 120.0, 130.0, 140.0, 150.0, 160.0, 180.0, 200.0],
	"unemployment_pct": [7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0, 11.0, 12.0],
	"deficit_pct_gdp": [3.0, 4.0, 5.0, 5.5, 6.0, 6.5, 7.0, 8.0, 10.0],
	"growth_annual_pct": [1.5, 1.0, 0.5, 0.0, -0.5, -1.0, -2.0],
	"unrest_pct": [10.0, 20.0, 30.0, 40.0, 45.0, 50.0, 60.0],
	"terms_served": [1.0, 2.0, 3.0],
	"overall_approval_pct": [30.0, 35.0, 40.0, 45.0, 50.0],
}

## Which way each field points at a crisis, and E0'S FIRST RUN CORRECTED THIS TABLE
## BEFORE A LINE OF CONTENT EXISTED, which is the whole argument for running it first.
## The plan had `deficit_pct_gdp` as a `<=` field on the assumption that a shortfall is
## negative. It is not: Budget.tick_month() sets it to
## `total_spending_pct_gdp - total_revenue_pct_gdp`, so a SHORTFALL IS POSITIVE and
## `austerity` reads -9.41 because it runs a surplus. balance_probe.gd's own _print_row()
## negates it for display, which is why every figure quoted in AGENTS.md and in the model
## docs carries the opposite sign from the field -- and bloc.gd's rule, the one V1.3d's
## screenshot pass caught being printed at a player raw, reads `deficit_pct_gdp <= 3.0`.
## An event authored on the plan's sign would have fired only on a SURPLUS.
const DIRECTION := {
	"debt_to_gdp_pct": ">=",
	"unemployment_pct": ">=",
	"deficit_pct_gdp": ">=",
	"growth_annual_pct": "<=",
	"unrest_pct": ">=",
	"terms_served": ">=",
	"overall_approval_pct": "<=",
}

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	var paths := _all_paths()
	_table_e0_range(paths)
	_table_e0b_occupancy(paths)
	_table_e0c_prediction(paths)
	_table_e1_cadence()
	_table_e1b_accumulation()
	_table_e2_legibility()
	_table_e3_dominance()
	quit(0)


# --- Harness ---------------------------------------------------------------------

func _new_state(nation_id: String):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	return state


func _commit(state, delta: Dictionary) -> void:
	if delta.is_empty():
		return
	var ns = state.player()
	var pending := {}
	if delta.has("tax_rates_pct"):
		var rates := {}
		for key in delta["tax_rates_pct"]:
			rates[key] = clampf(
				float(ns.start_tax_rates_pct.get(key, 0.0)) + float(delta["tax_rates_pct"][key]),
				0.0, 100.0
			)
		pending["tax_rates_pct"] = rates
	if delta.has("spending_pct_gdp"):
		var lines := {}
		for key in delta["spending_pct_gdp"]:
			lines[key] = maxf(
				float(ns.start_spending_pct_gdp.get(key, 0.0)) + float(delta["spending_pct_gdp"][key]),
				0.0
			)
		pending["spending_pct_gdp"] = lines
	Budget.commit(state, pending)


## src/ui/main.gd's order. Elections included and the run stops when the player leaves
## office -- see this file's header.
func _step(state, months_in: int) -> void:
	var year: int = START_YEAR + int(months_in / 12)
	var month: int = (months_in % 12) + 1
	state.year = year
	state.month = month
	Economy.tick_month(state)
	Budget.tick_month(state)
	Orgs.tick_month(state, _loader)
	Inflation.tick_month(state)
	Media.tick_month(state, _loader)
	Opinion.tick_month(state)
	var entry := Budget.snapshot(state)
	entry.merge(Opinion.snapshot(state))
	state.append_history(entry)
	Discipline.tick_month(state, _loader)
	Legislature.tick_month(state, _loader)
	Dissolution.tick_month(state)
	Diplomacy.tick_month(state, _loader)
	Defence.tick_month(state)
	Companies.tick_month(state, _loader)
	Investment.tick_month(state)
	Projects.tick_month(state, _loader)
	Campaign.tick_month(state, _loader)
	Pledges.tick_month(state, _loader)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, _loader)
	Elections.tick_month(state, _loader)


## One regime's whole reachable life, as an array of per-month field readings.
func _path(regime: String) -> Array:
	var state = _new_state("FRA")
	_commit(state, REGIMES[regime])
	var out: Array = []
	for i in range(RUN_MONTHS):
		_step(state, i)
		var ns = state.player()
		if not ns.in_government:
			break
		var row := {}
		for f in FIELDS:
			row[f] = _read(ns, f)
		out.append(row)
	return out


func _all_paths() -> Dictionary:
	var out := {}
	for regime in REGIMES.keys():
		out[regime] = _path(regime)
	return out


func _read(ns, field: String) -> float:
	match field:
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"unemployment_pct": return ns.unemployment_pct
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"overall_approval_pct": return ns.overall_approval_pct
		"growth_annual_pct": return ns.growth_annual_pct
		"terms_served": return float(ns.terms_served)
		"unrest_pct": return ns.unrest_pct
	return 0.0


func _satisfied(value: float, threshold: float, direction: String) -> bool:
	return value >= threshold if direction == ">=" else value <= threshold


# --- E0 --------------------------------------------------------------------------

func _table_e0_range(paths: Dictionary) -> void:
	print("\n=== E0  REACHABLE RANGE OF EVERY LEGAL PRECONDITION FIELD (FRA, %d months max) ===" % RUN_MONTHS)
	print("Measured BEFORE any threshold is authored. A precondition written outside a")
	print("field's reachable range is a crisis that never happens -- V1.7c's R0/R6")
	print("correction, applied to content rather than to a constant.")
	print("`months` is how long the run lasted: a regime that loses office stops there.\n")
	print("%-14s %6s %s" % ["regime", "months", _header()])
	for regime in REGIMES.keys():
		var path: Array = paths[regime]
		var cells: Array[String] = []
		for f in FIELDS:
			if path.is_empty():
				cells.append("%18s" % "--")
				continue
			var lo: float = INF
			var hi: float = -INF
			for row in path:
				lo = minf(lo, float(row[f]))
				hi = maxf(hi, float(row[f]))
			cells.append("%8.2f..%-9.2f" % [lo, hi])
		print("%-14s %6d %s%s" % [
			regime, path.size(), " ".join(cells),
			"   [reachable]" if REACHABLE.has(regime) else "",
		])


func _header() -> String:
	var out: Array[String] = []
	for f in FIELDS:
		out.append("%-18s" % f.substr(0, 18))
	return " ".join(out)


func _table_e0b_occupancy(paths: Dictionary) -> void:
	print("\n=== E0b  THRESHOLD OCCUPANCY: share of months each candidate is satisfied ===")
	print("Per regime, the percentage of the run in which the condition holds. A")
	print("threshold at 0 %% everywhere is unreachable content; one at 100 %% everywhere")
	print("is not a precondition, it is a decoration. What an authored event wants is a")
	print("row that separates the regimes.\n")
	for f in FIELDS:
		var refused: String = "  *** REFUSED as an event precondition ***" if f == "overall_approval_pct" else ""
		print("-- %s %s%s" % [f, DIRECTION[f], refused])
		var head: Array[String] = ["%-14s" % "regime"]
		for c in CANDIDATES[f]:
			head.append("%8.1f" % c)
		print(" ".join(head))
		for regime in REGIMES.keys():
			var path: Array = paths[regime]
			var cells: Array[String] = ["%-14s" % regime]
			for c in CANDIDATES[f]:
				if path.is_empty():
					cells.append("%8s" % "--")
					continue
				var hits := 0
				for row in path:
					if _satisfied(float(row[f]), float(c), String(DIRECTION[f])):
						hits += 1
				cells.append("%7.0f%%" % (100.0 * float(hits) / float(path.size())))
			print(" ".join(cells))
		print("")


## The re-run prediction, written before the re-run rather than after it.
##
## docs/media-model.md's V1.5d cost a session to a balance re-run that came back with a
## diff of exactly zero lines because neither harness called the new tick -- and the
## reassuring outcome is precisely the one nothing invites you to question. So the
## regimes this session expects to move are named here, from measured occupancy, and the
## re-run is checked against the list.
func _table_e0c_prediction(paths: Dictionary) -> void:
	print("\n=== E0c  RE-RUN PREDICTION ===")
	print("A regime moves in the balance re-run if any authored precondition can hold in")
	print("it. Printed as the widest occupancy each regime reaches on each field, so the")
	print("prediction can be re-read against whatever thresholds the content ends up")
	print("carrying.\n")
	for regime in REGIMES.keys():
		var path: Array = paths[regime]
		if path.is_empty():
			print("%-14s no months" % regime)
			continue
		var worst: Array[String] = []
		for f in FIELDS:
			if f == "overall_approval_pct" or f == "terms_served":
				continue
			var extreme: float = -INF if DIRECTION[f] == ">=" else INF
			for row in path:
				extreme = (
					maxf(extreme, float(row[f])) if DIRECTION[f] == ">="
					else minf(extreme, float(row[f]))
				)
			worst.append("%s %s %.2f" % [f, DIRECTION[f], extreme])
		print("%-14s %s" % [regime, "  |  ".join(worst)])


# --- E1: cadence, and the session's one tuned constant -----------------------------

## Candidate values for EVENT_COOLDOWN_MONTHS. Two-sided by construction (see the
## constant's own header), so V1.5c's correction governs -- the interior, not an edge --
## and V1.5b's diagnostic applies: a value at the endpoint of this grid is a suspect and
## not a result.
const COOLDOWN_CANDIDATES := [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 24]

## THE EMULATION IS EXACT AND THAT IS THE POINT. A probe cannot change a `const` at
## runtime, and docs/inflation-model.md records what happens when it works around that by
## rescaling a measured result: the passing interval MOVED when the shipped constant
## moved, so the sweep's own answer depended on the value it was choosing. This loop
## calls Events.hazard_passes() and Legislature.preconditions_met() -- the shipped
## functions -- and differs from Events.tick_month() in the cooldown alone.
func _sim_events(regime: String, months: int, cooldown: int, answer: bool) -> Dictionary:
	var state = _new_state("FRA")
	_commit(state, REGIMES[regime])
	var ns = state.player()
	var fired := 0
	var defaults := 0
	var quiet := 0
	var pending: Dictionary = {}
	var fired_once := {}

	for i in range(months):
		_step(state, i)
		if not ns.in_government:
			break
		if quiet > 0:
			quiet -= 1

		if not pending.is_empty():
			pending["months_left"] = int(pending["months_left"]) - 1
			if int(pending["months_left"]) <= 0:
				var ev = pending["event"]
				var choice: Dictionary = _best_choice(ev) if answer else ev.default_choice()
				if not answer:
					defaults += 1
				Legislature.apply_effects(state, ns, choice.get("effects", {}), _loader)
				pending = {}
				quiet = cooldown
			continue

		if quiet > 0:
			continue

		for ev in _loader.events:
			if ev.once and fired_once.has(ev.id):
				continue
			if not Legislature.preconditions_met(ns, ev.preconditions):
				continue
			if not Events.hazard_passes(ns.id, ev.id, int(state.year), int(state.month), float(ev.likelihood)):
				continue
			pending = {"event": ev, "months_left": int(ev.respond_months)}
			fired += 1
			if ev.once:
				fired_once[ev.id] = true
			break

	return {
		"fired": fired, "defaults": defaults, "months": _months_run(state),
		"state": state,
	}


func _months_run(state) -> int:
	return maxi(1, (int(state.year) - START_YEAR) * 12 + int(state.month) - 1)


## The choice with the largest size-weighted bloc_offset. A stand-in for a player who
## answers well, and NOT a claim that this is the right answer -- E3 is what checks
## whether the ladder has a right answer at all.
func _best_choice(ev) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for c in ev.choices:
		var score := _weighted_offset(c.get("effects", {}))
		if score > best_score:
			best_score = score
			best = c
	return best


func _weighted_offset(effects: Dictionary) -> float:
	var terms: Dictionary = effects.get("bloc_offset", {})
	var total := 0.0
	for bloc in terms:
		total += float(OpinionK.BLOC_SIZE.get(bloc, 0.0)) * float(terms[bloc])
	return total


## How much of the bloc_offset clamp the worst reachable career may use. Not a value
## solved against another value -- it is the statement that a guard rail has to stay a
## guard rail, which docs/defence-model.md measured for the deployment bill and V1.4a
## for the subsidy bill. At 0.60 the model keeps two fifths of the register free for the
## laws, referendums and campaigns that also write it.
const ACCUMULATION_CEILING := 0.60


func _table_e1_cadence() -> void:
	print("\n=== E1  CADENCE: events per five-year term, swept over EVENT_COOLDOWN_MONTHS ===")
	print("CLAUSE (i), cadence: between 2 and 6 per term in the median reachable regime.")
	print("Under 2 the machine is decorative -- section 8's own falsifier from the other")
	print("side. Over 6 the message column (six cards, oldest dropped) buries one event")
	print("under the next, and an occasion nobody read is not an occasion.")
	print("CLAUSE (ii), slack: the worst reachable career accumulation must leave the")
	print("bloc_offset clamp free by %.0f %%." % (100.0 * (1.0 - ACCUMULATION_CEILING)))
	print("")
	print("CLAUSE (i) ALONE PASSED EVERY CANDIDATE FROM 3 TO 18, which is the one-sided")
	print("failure V1.5a and V1.5b both recorded and which V1.5a's two-part selector is")
	print("the only thing on this project's record ever to answer. (ii) is what closes")
	print("the interval, and it closes it from the other end: a short cooldown is not")
	print("wrong because events are frequent, it is wrong because a career of them")
	print("saturates a permanent accumulator.\n")
	var head: Array[String] = ["%-10s" % "cooldown"]
	for regime in REACHABLE:
		head.append("%12s" % regime)
	head.append("%12s" % "median")
	head.append("%12s" % "|worst|")
	head.append("  verdict")
	print(" ".join(head))
	var passing: Array[int] = []
	for cd in COOLDOWN_CANDIDATES:
		var per_term: Array[float] = []
		var cells: Array[String] = ["%-10d" % cd]
		var worst := 0.0
		for regime in REACHABLE:
			var r := _sim_events(regime, RUN_MONTHS, cd, false)
			var rate: float = float(r["fired"]) * float(TERM_MONTHS) / float(r["months"])
			per_term.append(rate)
			cells.append("%12.2f" % rate)
			worst = maxf(worst, absf(float(_worst_offset(r["state"])["value"])))
			var a := _sim_events(regime, RUN_MONTHS, cd, true)
			worst = maxf(worst, absf(float(_worst_offset(a["state"])["value"])))
		per_term.sort()
		var median: float = (per_term[0] + per_term[per_term.size() - 1]) / 2.0
		var cadence_ok: bool = median >= 2.0 and median <= 6.0
		var slack_ok: bool = worst <= ACCUMULATION_CEILING
		cells.append("%12.2f" % median)
		cells.append("%12.3f" % worst)
		cells.append("  PASS" if cadence_ok and slack_ok else ("  cadence" if not cadence_ok else "  saturating"))
		if cadence_ok and slack_ok:
			passing.append(cd)
		print(" ".join(cells))
	if passing.is_empty():
		print("\nNO CANDIDATE PASSES BOTH CLAUSES -- the two criteria have no overlap, which")
		print("is V1.6a's legibility floor in a new place and is recorded, not tuned around.")
	else:
		var mid: float = (float(passing[0]) + float(passing[passing.size() - 1])) / 2.0
		print("\npassing %s -> midpoint %.1f, nearest candidate %d" % [
			str(passing), mid, _nearest(passing, mid),
		])
		if passing[0] == COOLDOWN_CANDIDATES[0] or passing[passing.size() - 1] == COOLDOWN_CANDIDATES[COOLDOWN_CANDIDATES.size() - 1]:
			print("the passing set touches an END of the swept grid -- V1.5b's suspect: widen it")
	print("shipped EVENT_COOLDOWN_MONTHS = %d" % EventsK.EVENT_COOLDOWN_MONTHS)


func _nearest(values: Array[int], target: float) -> int:
	var best: int = values[0]
	for v in values:
		if absf(float(v) - target) < absf(float(best) - target):
			best = v
	return best


# --- E1b: the accumulation bound, and it is a different constraint from E2 ---------

## *** THE SESSION'S SHARPEST CORRECTION LIVES IN THIS TABLE. ***
##
## E2 below prices ONE DECISION and E1b prices A CAREER, and the first authored ladder
## satisfied E2 while failing this by a factor of four. `bloc_offset` is a PERMANENT
## clamped accumulator: every previous writer of it either charges once for an act the
## player chose (a referendum, a law) or charges while a condition holds and stops when
## the player fixes it (a pledge breach). An event is neither -- it arrives whether or
## not it is wanted, it recurs, and its default charges without a decision. Ten defaults
## at the first ladder's magnitudes reached BLOC_OFFSET_MAX, and once the clamp is
## saturated EVERY REGIME CONVERGES ON THE SAME FLOOR: tests/test_balance.gd caught it as
## `managed` no longer beating `hands_off` on approval, which is the harness saying that
## a well-run budget and an ignored one had become indistinguishable.
##
## That is docs/projects-model.md's *a bill is not a cost* one block on -- a per-decision
## price is not a lifetime charge -- and economy-model.md's IMPULSE_MAX a sixth time.
##
## BAND: the worst bloc's accumulated event offset over a full reachable run must leave
## BLOC_OFFSET_MAX STRICTLY SLACK, on the all-defaults path, which is the worst case a
## player can actually produce. docs/defence-model.md's measured-and-slack discipline.
func _table_e1b_accumulation() -> void:
	print("\n=== E1b  LIFETIME ACCUMULATION against the bloc_offset clamp (+-%.2f) ===" % LegislatureK.BLOC_OFFSET_MAX)
	print("A per-decision price is not a lifetime charge. Measured on the ALL-DEFAULTS")
	print("path, which is what a player who never opens the window produces, and on the")
	print("answer-well path beside it. Saturation is not a big number: it is the point at")
	print("which every regime stops being distinguishable from every other.\n")
	print("%-14s %8s %8s   %-11s %9s   %-11s %9s" % [
		"regime", "months", "events", "worst(def)", "offset", "worst(ans)", "offset",
	])
	for regime in REGIMES.keys():
		var d := _sim_events(regime, RUN_MONTHS, EventsK.EVENT_COOLDOWN_MONTHS, false)
		var a := _sim_events(regime, RUN_MONTHS, EventsK.EVENT_COOLDOWN_MONTHS, true)
		var dw := _worst_offset(d["state"])
		var aw := _worst_offset(a["state"])
		print("%-14s %8d %8d   %-11s %9.4f   %-11s %9.4f%s" % [
			regime, int(d["months"]), int(d["fired"]),
			dw["bloc"], float(dw["value"]), aw["bloc"], float(aw["value"]),
			"   *** SATURATED ***" if absf(float(dw["value"])) >= LegislatureK.BLOC_OFFSET_MAX - 0.001 else "",
		])


## The bloc carrying the largest absolute offset. Read off the LIVE register rather than
## summed from the content, so it includes the clamp -- a table that added the authored
## numbers would report a charge the model never delivered.
func _worst_offset(state) -> Dictionary:
	var ns = state.player()
	var worst := ""
	var value := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		var v: float = float(ns.bloc_offset.get(bloc, 0.0))
		if absf(v) > absf(value):
			value = v
			worst = bloc
	return {"bloc": worst, "value": value}


# --- E2: legibility, and the axis it is measured on was corrected by the first run --

## The month the measurement starts from. Inside the first term, past the opening
## transient, and comfortably before the 2027 vote -- so the twelve months E2 and E3
## measure are twelve months of governing rather than twelve months of an election.
const PROBE_MONTH := 14
const HORIZON := 12

## Below this two outcomes are the SAME OUTCOME. Added after the first E3 run decided a
## dominance verdict on a difference in the ninth decimal place: `inquiry` and `dismiss`
## produced identical deficits to three figures, one of them was a hair lower, and the
## table therefore reported no dominance between two options that are in every readable
## sense identical on that axis. A dominance test with no tolerance is a test of float
## noise, and it fails in the DANGEROUS direction -- it stays silent.
const EPS_APPROVAL := 0.02
const EPS_DEFICIT := 0.005

## *** THE BAND'S AXIS WAS WRONG AND E2'S FIRST RUN IS WHAT SAID SO. ***
##
## Written as "best choice minus default, on the HEADLINE approval figure, past +-3.0".
## Five events of six came back under the floor and the sixth came back NEGATIVE: on
## `emergency_budget_demand` the default -- refusing to fix the deficit -- is the most
## popular thing a president can do, which is not a defect in the content, it is the
## fiscal dilemma the event exists to pose.
##
## Two things are wrong with the original band and both are recorded failures of this
## project's own. It measures an observable the channel does not reach in one step: an
## event moves a FEW BLOCS HARD, and docs/defence-model.md moved its price to the rural
## row after finding five blocs of six weight `defence` at 0.00, docs/demography-model.md
## DELETED a term that could not clear the headline floor at any value, and
## docs/unrest-model.md measured on the workers row for the same reason. A headline
## figure is a size-weighted mean, and a decision that moves winners and losers in
## opposite directions is quietest exactly there. And "best minus default" presumes the
## best choice is the popular one, which for a fiscal decision it must not be.
##
## SO THE BAND IS THE WIDEST PER-BLOC SPREAD ACROSS THE WHOLE CHOICE SET: for each bloc,
## the highest approval any choice leaves it at minus the lowest, and then the largest of
## those. That is the honest statement of "a player can tell that answering mattered",
## and it does not care which choice is the popular one. The headline column is printed
## beside it and is expected to fail -- recorded as a structural bound, V1.6a's
## legibility floor a third time, rather than tuned against.
func _table_e2_legibility() -> void:
	print("\n=== E2  LEGIBILITY: how far apart this decision's choices leave the country ===")
	print("Band [%.1f, %.1f] on the WIDEST PER-BLOC SPREAD -- the poll floor, and what" % [NOISE_FLOOR, PLEDGE_BREACH_CEILING])
	print("docs/pledge-model.md measured a full-term promise breach to cost. The headline")
	print("column is printed beside it and is NOT the band: see this function's header.\n")
	print("%-26s %10s %-12s %10s   %s" % ["event", "spread", "on bloc", "headline", "band"])
	var base = _state_at(PROBE_MONTH)
	for ev in _loader.events:
		var rows: Array = []
		for c in ev.choices:
			rows.append(_outcome(base, ev, c))
		var widest := 0.0
		var widest_bloc := ""
		for bloc in OpinionK.BLOC_KEYS:
			var lo := 100.0
			var hi := -100.0
			for o in rows:
				var v: float = float((o["blocs"] as Dictionary).get(bloc, 0.0))
				lo = minf(lo, v)
				hi = maxf(hi, v)
			if hi - lo > widest:
				widest = hi - lo
				widest_bloc = bloc
		var head_lo := 100.0
		var head_hi := -100.0
		for o in rows:
			head_lo = minf(head_lo, float(o["approval"]))
			head_hi = maxf(head_hi, float(o["approval"]))
		print("%-26s %10.3f %-12s %10.3f   %s" % [
			ev.id, widest, widest_bloc, head_hi - head_lo,
			"PASS" if widest >= NOISE_FLOOR and widest <= PLEDGE_BREACH_CEILING
			else ("under floor" if widest < NOISE_FLOOR else "over ceiling"),
		])


## A `managed` France, `months` months in, with nothing pending. The base every E2 and
## E3 measurement branches from, so every row is measured against the same country.
func _state_at(months: int):
	var state = _new_state("FRA")
	_commit(state, REGIMES["managed"])
	for i in range(months):
		_step(state, i)
	return state


## Announce, answer, run HORIZON months, read the axes. Branches from a COPY, so every
## choice of every event is measured against the identical starting country --
## docs/credit-model.md's control, which its own second band was missing.
func _outcome(base, ev, choice: Dictionary) -> Dictionary:
	var state = base.duplicate_state()
	var ns = state.player()
	# The announce signature grew the month and the name map at V3.5; every event in
	# the content is non-sited today, so both are inert here -- filled exactly as
	# tick_month fills them, so that stays true when that changes.
	Events.announce(ns, ev, Events._absolute_month(int(base.year), int(base.month)),
		Events.region_names(ns, _loader))
	Legislature.apply_effects(state, ns, choice.get("effects", {}), _loader)
	# clear(), not a fresh []: the register is Array[Dictionary], and an untyped
	# empty literal assigned through an untyped reference fails its type check.
	ns.event_queue.clear()
	for i in range(HORIZON):
		_step(state, PROBE_MONTH + i)
	var blocs := {}
	var worst := 100.0
	for bloc in OpinionK.BLOC_KEYS:
		var v: float = float(ns.bloc_approval.get(bloc, 0.0))
		blocs[bloc] = v
		worst = minf(worst, v)
	return {
		"approval": float(ns.overall_approval_pct),
		"deficit": float(ns.deficit_pct_gdp),
		"worst_bloc": worst,
		"corruption": float(ns.corruption),
		"blocs": blocs,
	}


# --- E3: dominance, on a live path ------------------------------------------------

## *** THE KILL SWITCH FOR THE CONTENT, AND ITS RULE WAS CORRECTED BY ITS OWN FIRST RUN. ***
##
## The rule as written was "no choice may weakly dominate another on all three axes",
## and the first run reported five violations of which FOUR ARE THE DESIGN: in every one
## an active choice dominated the DEFAULT. That is not a trap, it is the pressure -- a
## default nothing beats is a deadline with nothing behind it, which this table's second
## clause requires. The failure this project has killed eleven times is an option that is
## never worth TAKING, and a default is not taken, it is suffered.
##
## So dominance is counted between ALTERNATIVES only, and the default is checked by the
## opposite test: it must be beaten on at least one axis. One real violation survived
## the correction -- `cut` dominated `raise` on the fiscal event -- and it was fixed in
## the CONTENT, by making the tax rise collect more than the spending cut, so the two
## trade against each other instead of one being strictly better.
##
## MEASURED ON A LIVE PATH RATHER THAN READ OFF THE AUTHORED NUMBERS, which is
## docs/pledge-model.md's own correction: its first dominance test compared authored
## pairs and reported five dominated promises, every one an artefact, because the
## deciding quantity was nowhere in the content.
func _table_e3_dominance() -> void:
	print("\n=== E3  DOMINANCE: every choice, +%d months, on three axes ===" % HORIZON)
	print("approval higher is better; deficit LOWER is better (positive is a shortfall);")
	print("worst-bloc higher is better. Tolerances %.3f / %.4f -- see EPS_APPROVAL.\n" % [EPS_APPROVAL, EPS_DEFICIT])
	var base = _state_at(PROBE_MONTH)
	var dominated := 0
	var toothless := 0
	for ev in _loader.events:
		print("-- %s" % ev.id)
		var rows: Array = []
		for c in ev.choices:
			var o := _outcome(base, ev, c)
			rows.append({"choice": c, "o": o})
			print("   %-16s%s approval %7.3f   deficit %7.3f   worst %7.3f   corrupt %+6.3f" % [
				String(c["id"]), " (default)" if bool(c["is_default"]) else "         ",
				float(o["approval"]), float(o["deficit"]), float(o["worst_bloc"]),
				float(o["corruption"]),
			])
		for i in rows.size():
			for j in rows.size():
				if i == j:
					continue
				if bool(rows[i]["choice"]["is_default"]) or bool(rows[j]["choice"]["is_default"]):
					continue
				if _dominates(rows[i]["o"], rows[j]["o"]):
					dominated += 1
					print("   *** '%s' dominates '%s' on all three axes" % [
						rows[i]["choice"]["id"], rows[j]["choice"]["id"],
					])
		var default_row: Dictionary = {}
		for r in rows:
			if bool(r["choice"]["is_default"]):
				default_row = r
		var beaten := false
		for r in rows:
			if r == default_row:
				continue
			if _better_somewhere(r["o"], default_row["o"]):
				beaten = true
		if not beaten:
			toothless += 1
			print("   *** the default is beaten on no axis: the deadline has no teeth")
	print("\ndominated alternatives: %d    toothless defaults: %d" % [dominated, toothless])
	print("(an ACTIVE choice dominating the DEFAULT is the design, not a violation)")


## THE FOURTH AXIS IS `corruption`, AND WHICH REGISTERS BELONG HERE IS AN ARGUMENT
## RATHER THAN A LIST. A choice may be measured on a register only where that register
## has an UNAMBIGUOUS better direction, because dominance is a claim about being better
## off and a signed dial is not.
##
##   corruption          LOWER IS BETTER, unambiguously. V1.5a made it multiply the
##                       delivery target, so cleaning up buys something real that a
##                       twelve-month approval read cannot see -- which is exactly why it
##                       belongs: without it `inquiry` dominated `dismiss` while being
##                       the choice that leaves the state dirtier.
##   press_freedom       NO direction. It buys legitimacy through the grievance and costs
##                       approval through the framing gain; which way a president wants it
##                       is the decision, not the axis.
##   settlement_stance   NO direction either, and refusing it is what keeps `settle`
##                       against `partial` a real choice: a settlement is BOUGHT, and what
##                       it is worth depends on how angry the country is.
##   regulation_burden   NO direction. Signed by design since V1.4b.
func _dominates(a: Dictionary, b: Dictionary) -> bool:
	var app_ge: bool = float(a["approval"]) >= float(b["approval"]) - EPS_APPROVAL
	var def_le: bool = float(a["deficit"]) <= float(b["deficit"]) + EPS_DEFICIT
	var worst_ge: bool = float(a["worst_bloc"]) >= float(b["worst_bloc"]) - EPS_APPROVAL
	var corr_le: bool = float(a["corruption"]) <= float(b["corruption"]) + EPS_DEFICIT
	var strict: bool = (
		float(a["approval"]) > float(b["approval"]) + EPS_APPROVAL
		or float(a["deficit"]) < float(b["deficit"]) - EPS_DEFICIT
		or float(a["worst_bloc"]) > float(b["worst_bloc"]) + EPS_APPROVAL
		or float(a["corruption"]) < float(b["corruption"]) - EPS_DEFICIT
	)
	return app_ge and def_le and worst_ge and corr_le and strict


func _better_somewhere(a: Dictionary, b: Dictionary) -> bool:
	return (
		float(a["approval"]) > float(b["approval"]) + EPS_APPROVAL
		or float(a["deficit"]) < float(b["deficit"]) - EPS_DEFICIT
		or float(a["worst_bloc"]) > float(b["worst_bloc"]) + EPS_APPROVAL
		or float(a["corruption"]) < float(b["corruption"]) - EPS_DEFICIT
	)
