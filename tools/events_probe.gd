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
## E1b lifetime accumulation, now on the real machine (defaults and answer-well).
## E4  cadence and the desk, swept over CATEGORY_QUIET_MONTHS -- the V4.4 dial.
##     E4/E5 run the game's whole month (_tick_events), so a hook arrival counts
##     beside the hazard ones. Before the world-month refactor their chain wrote no
##     hook stamps and they measured HAZARD arrivals only (hooks are witnessed in E6).
## E5  category spread over a full idle run at the shipped constants.
## E6  the hook vocabulary, staged register by register and witnessed landing.
## E7  chooser spread: what the other twenty-eight answered over a term.
## E2  legibility, two-sided, against a ruler that was MEASURED rather than invented.
## E3  dominance, on a live path rather than off the authored numbers.
##
## Elections run in this loop and the run STOPS when the player leaves office. That is
## not a detail: tools/unrest_probe.gd's own loop had no elections, so every table it
## printed described a government that had already been thrown out, and the balance
## harness had to catch it. V1.3f's measuring-the-wrong-state error, five times on this
## project's record, and this file is written against it rather than after it.

const DataLoader = preload("res://src/core/data_loader.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
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
const GameEvent = preload("res://src/core/event.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")

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

## Bands that failed, if any -- the exit contract: 0 = every declared band PASSED,
## 1 = at least one failed, with the findings printed beside their tables. V1.8's
## file had no exit contract because it guarded nothing; the V4.4 tables guard a
## landed machine, so they carry one.
var _band_failures: Array[String] = []


func _band_failed(msg: String) -> void:
	_band_failures.append(msg)


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
	_table_e1b_accumulation()
	_table_e4_cadence()
	_table_e5_categories()
	_table_e6_hooks()
	_table_e7_chooser()
	_table_e2_legibility()
	_table_e3_dominance()
	_table_d5_d7_voice()
	if not _band_failures.is_empty():
		printerr("")
		for f in _band_failures:
			printerr("BAND FAILED: %s" % f)
		printerr("events_probe: %d band failure(s) -- report the measured interval, do not tune silently" % _band_failures.size())
		quit(1)
		return
	print("\nevents_probe: every declared band PASSED")
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


## A DELIBERATELY REDUCED tick, not src/ui/main.gd's order. It omits Energy,
## Commodities, Programme, Calendar, Statute, Industry, Migration, Events and
## Characters -- E0/E2/E3 measure a world without them, which is the point, and
## Events is driven separately by _tick_events() below. Elections ARE included and
## the run stops when the player leaves office -- see this file's header.
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


# --- The real-machine driver, and the E4 surgery on the one V4.4 dial ---------------

## The game's own month (src/sim/world_month.gd). Until the world-month refactor
## this was tests/test_events.gd's minimal chain -- what an event reads and what
## reads an event -- and the chain never ticked Commodities, Orgs, Statute or
## Industry, so four of the five hooks tests/test_events.gd's tick-order pin names
## could not fire in what E4/E5 measured. The full _step above stays for the E0
## tables and E2/E3, whose premises are the field ranges and the outcome comparison
## -- and that chain deliberately does NOT tick the machine, which is why those
## tables keep reading the world they have always read. E1's local mirror is gone:
## its EVENT_COOLDOWN_MONTHS no longer exists in the machine's behaviour (the
## per-category quiet replaced it), and a mirror of a machine that no longer runs
## measures nothing -- V1.5d's harness-runs-the-old-model failure, pre-empted.
func _tick_events(state, months_in: int) -> Dictionary:
	state.year = START_YEAR + int(months_in / 12)
	state.month = (months_in % 12) + 1
	return WorldMonth.tick_month(state, _loader)


## One FRA run on the real machine, tallied from the desk. `answer_well` answers
## every entry with _best_choice() in the month it sits on the desk -- E1b's
## answer-well path, the player a probe can actually be. `quiet_override` > 0
## emulates a CATEGORY_QUIET_MONTHS the probe cannot set: the shipped code runs
## everywhere, and only the PLAYER's quiet register is rewritten after each tick,
## from a note of when each category last saw a delivery or a default.
##
## THE NOTE NEEDS NO HOOK INTO THE MACHINE: both quiet writes coincide with a
## queue transition -- announce() appends, _resolve() erases -- so a before/after
## diff of the desk is the whole witness. The rewrite is the identity when the
## override equals the shipped constant (left = K - (now - wrote) is the machine's
## own countdown), which is why the sweep runs the shipped row with the override
## OFF: that row stays a pure reading. The E4 sweep never answers, so the note's
## blindness to answer-driven resolutions is inert here.
##
## One known undercount, stated rather than hidden: a 1-month entry that expires
## and re-arrives inside one tick is neither an arrival nor an answer in a
## before/after diff. At the shipped quiet a same-category redelivery cannot land
## that fast; only override 1 could produce it.
func _run_machine(regime: String, months: int, answer_well: bool, quiet_override: int) -> Dictionary:
	var state = _new_state("FRA")
	_commit(state, REGIMES[regime])
	var ns = state.player()
	var tally := {
		"arrivals": 0, "answered": 0, "by_category": {},
		"max_depth": 0, "overfull": 0, "months": months, "windows": [0.0, 0.0, 0.0],
		"state": state,
		# V5.2d (D5, D7, D9): who brought each arrival, and the month's front page.
		"spoken": 0, "narrated": {}, "front_pages": 0, "two_tones": 0,
		"front_windows": [0.0, 0.0, 0.0], "front_by_kind": {},
	}
	var wrote := {}
	for i in range(months):
		var before := {}
		for entry in ns.event_queue:
			before[String(entry.get("event_id", ""))] = String(entry.get("category", ""))
		var report := _tick_events(state, i)
		var front: Dictionary = report.get("front_page", {})
		if not front.is_empty():
			tally["front_pages"] = int(tally["front_pages"]) + 1
			tally["front_windows"][mini(2, i / TERM_MONTHS)] += 1.0
			var story := "%s.%s" % [front["kind"], front["id"]]
			tally["front_by_kind"][story] = int(tally["front_by_kind"].get(story, 0)) + 1
			var papers: Array = front.get("papers", [])
			if papers.size() == 2 and String(papers[0]["tone"]) != String(papers[1]["tone"]):
				tally["two_tones"] = int(tally["two_tones"]) + 1
		var after := {}
		for entry in ns.event_queue:
			var id := String(entry.get("event_id", ""))
			after[id] = String(entry.get("category", ""))
			if not before.has(id):
				if String(entry.get("speaker", "")) != "":
					tally["spoken"] = int(tally["spoken"]) + 1
				else:
					tally["narrated"][id] = int(tally["narrated"].get(id, 0)) + 1
				tally["arrivals"] = int(tally["arrivals"]) + 1
				tally["by_category"][after[id]] = int(tally["by_category"].get(after[id], 0)) + 1
				wrote[after[id]] = i
		for id in before:
			if not after.has(id):
				tally["answered"] = int(tally["answered"]) + 1
				tally["windows"][mini(2, i / TERM_MONTHS)] += 1.0
				wrote[before[id]] = i
		if answer_well:
			var guard := 0
			while Events.is_pending(ns) and guard < EventsK.QUEUE_MAX + 1:
				guard += 1
				var ev = Events.event_by_id(_loader, Events.pending_event_id(ns))
				if ev == null:
					break
				var record := Events.answer(state, _loader, Events.pending_event_id(ns),
					String(_best_choice(ev).get("id", "")))
				if record.is_empty():
					break
		if quiet_override > 0 and quiet_override != EventsK.CATEGORY_QUIET_MONTHS:
			ns.event_category_quiet.clear()
			for category in wrote.keys():
				var left: int = int(quiet_override) - (i - int(wrote[category]))
				if left > 0:
					ns.event_category_quiet[category] = left
				else:
					wrote.erase(category)
		var depth: int = ns.event_queue.size()
		tally["max_depth"] = maxi(int(tally["max_depth"]), depth)
		if depth >= EventsK.QUEUE_MAX:
			tally["overfull"] = int(tally["overfull"]) + 1
	return tally


## The median over the run of each 60-month window's answers, scaled to a full
## term so the trailing 48-month window competes fairly -- "events answered per
## five-year term (median over the run)" is exactly this and nothing mystical.
func _median_term_rate(tally: Dictionary) -> float:
	var rates: Array[float] = []
	for w in range(3):
		var span: int = TERM_MONTHS if w < 2 else RUN_MONTHS - 2 * TERM_MONTHS
		rates.append(float(tally["windows"][w]) * float(TERM_MONTHS) / float(span))
	rates.sort()
	return rates[1]


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


# --- E4: cadence and the desk, swept over the V4.4 dial -----------------------------

## THE BANDS WERE DECLARED BEFORE THIS SWEEP RAN -- the plan's clause, restated in
## events_constants.gd beside the dial: cadence 6-18 answered per five-year term;
## the desk full on under 5% of months; the queue never past QUEUE_MAX. The last
## is a CONSTRUCTION, not a measurement (the tick's own delivery gate), so it is
## asserted here and never tuned against -- a row that breaks it is a machine
## defect, not a band failure.
##
## WHAT E4 (AND E5) MEASURE: the real Events.tick_month, but fed by _tick_events,
## whose chain runs NO machine that writes the hook stamps (no Legislature
## ledger, Cabinet resignations, Industry bids/failures, Commodities prices or
## Orgs accessions), so the hook doors never fire in these runs. The cadence and
## spread below are therefore HAZARD arrivals only (plus any chain a hazard
## choice arms); hook events are witnessed separately, in E6.
const QUIET_SWEEP := [1, 2, 3, 4, 5, 6]
const CADENCE_MIN := 6.0
const CADENCE_MAX := 18.0
const OVERFULL_MAX := 0.05


func _table_e4_cadence() -> void:
	print("\n=== E4  CADENCE AND THE DESK: hands-off FRA on the real machine, swept over CATEGORY_QUIET_MONTHS ===")
	print("V1.8's E1 swept EVENT_COOLDOWN_MONTHS, and that constant is gone from the")
	print("machine's behaviour -- the per-category quiet replaced it (events_constants'")
	print("own note). The shipped row runs the untouched machine; the other rows")
	print("emulate the override on the quiet register alone (see _run_machine).\n")
	var head: Array[String] = ["%-7s" % "quiet", "%9s" % "arrivals", "%9s" % "answered",
		"%9s" % "per term", "%8s" % "maxdesk", "%8s" % "overfull", "  verdict"]
	print(" ".join(head))
	for quiet in QUIET_SWEEP:
		var override: int = 0 if quiet == EventsK.CATEGORY_QUIET_MONTHS else quiet
		var t := _run_machine("hands_off", RUN_MONTHS, false, override)
		var rate := _median_term_rate(t)
		var overfull: float = float(t["overfull"]) / float(maxi(1, int(t["months"])))
		var cadence_ok: bool = rate >= CADENCE_MIN and rate <= CADENCE_MAX
		var overfull_ok: bool = overfull < OVERFULL_MAX
		var bound_ok: bool = int(t["max_depth"]) <= EventsK.QUEUE_MAX
		var ok := cadence_ok and overfull_ok and bound_ok
		var verdict := "PASS" if ok else (
			"BOUND BROKEN" if not bound_ok else ("cadence %.1f outside [%.0f, %.0f]" % [rate, CADENCE_MIN, CADENCE_MAX] if not cadence_ok else "overfull %.1f%% >= %.0f%%" % [100.0 * overfull, 100.0 * OVERFULL_MAX]))
		print("%-7d %9d %9d %9.2f %8d %7.1f%%   %s" % [
			quiet, int(t["arrivals"]), int(t["answered"]), rate,
			int(t["max_depth"]), 100.0 * overfull, verdict,
		])
		if quiet == EventsK.CATEGORY_QUIET_MONTHS and not ok:
			_band_failed("E4: the shipped quiet (%d) row fails its declared band -- %s" % [
				EventsK.CATEGORY_QUIET_MONTHS, verdict])
	print("\nshipped CATEGORY_QUIET_MONTHS = %d, QUEUE_MAX = %d (asserted, not measured)" % [
		EventsK.CATEGORY_QUIET_MONTHS, EventsK.QUEUE_MAX])


# --- E5: category spread -------------------------------------------------------------

## Declared with the dial: no category supplies more than 30% of the desk's
## arrivals over a full idle run. A category that crowds the rest out is the
## monoculture the weighted pick was built against, and NO machine constant can
## fix it -- the quiet quiets every category alike -- so a failure here is a
## CONTENT verdict (rebalance likelihoods/weights in data/events/), recorded
## rather than tuned.
const CATEGORY_SHARE_MAX := 0.30
## E5 shares the E4 driver, so it likewise counts HAZARD arrivals only -- the
## hook doors are never exercised here (E6 witnesses them).


func _table_e5_categories() -> void:
	print("\n=== E5  CATEGORY SPREAD: arrivals by category, %d-month idle run, shipped machine ===" % RUN_MONTHS)
	var t := _run_machine("hands_off", RUN_MONTHS, false, 0)
	var total := int(t["arrivals"])
	print("%d arrivals over %d months\n" % [total, int(t["months"])])
	print("%-12s %8s %7s   %s" % ["category", "arrivals", "share", "verdict"])
	var all_ok := total > 0
	for category in EventsK.CATEGORIES:
		var n := int(t["by_category"].get(category, 0))
		var share := float(n) / float(maxi(1, total))
		var ok := share <= CATEGORY_SHARE_MAX
		all_ok = all_ok and ok
		print("%-12s %8d %6.1f%%   %s" % [category, n, 100.0 * share, "PASS" if ok else "OVER %.0f%%" % (100.0 * CATEGORY_SHARE_MAX)])
	if not all_ok:
		_band_failed("E5: a category supplies more than %.0f%% of arrivals -- a content verdict, not a dial" % (100.0 * CATEGORY_SHARE_MAX))


# --- D5 / D7 / D9: the voice and the press (V5.2d) -------------------------------------

## docs/design/v5.2-d-spec.md section 5, declared before the build. D5: at least
## SPEAKER_SHARE_MIN of the deliveries to the played nation resolve a speaker (the
## narrator only on the fallback). D7: FRONT_PAGES_MIN to FRONT_PAGES_MAX front
## pages a term, the median over the run's windows like E4's cadence. D9's share of
## two-tone cards is reported, not gated. Both regimes on the real month: hands_off
## lets every deadline default, managed answers every entry the month it lands
## (E1b's answer-well player), so both the in-month and the between-month stories
## reach the press. Arrivals are the desk diff, so the undercount E4 states holds.
const SPEAKER_SHARE_MIN := 0.95
const FRONT_PAGES_MIN := 6.0
const FRONT_PAGES_MAX := 15.0


func _table_d5_d7_voice() -> void:
	print("\n=== D5 / D7 / D9  THE VOICE AND THE PRESS: FRA, %d months, the real month ===" % RUN_MONTHS)
	print("%-10s %8s %8s %7s   %11s %8s %9s   %s" % [
		"regime", "arrivals", "spoken", "share", "front pages", "per term", "two tones", "verdict"])
	for regime in ["hands_off", "managed"]:
		var t := _run_machine(regime, RUN_MONTHS, regime == "managed", 0)
		var arrivals := int(t["arrivals"])
		var share := float(t["spoken"]) / float(maxi(1, arrivals))
		var per_term := _median_term_rate({"windows": t["front_windows"]})
		var fronts := int(t["front_pages"])
		var two := float(t["two_tones"]) / float(maxi(1, fronts))
		var d5 := arrivals > 0 and share >= SPEAKER_SHARE_MIN
		var d7 := per_term >= FRONT_PAGES_MIN and per_term <= FRONT_PAGES_MAX
		print("%-10s %8d %8d %6.1f%%   %11d %8.1f %8.1f%%   %s" % [
			regime, arrivals, int(t["spoken"]), 100.0 * share, fronts, per_term, 100.0 * two,
			"PASS" if d5 and d7 else ("D5 FAIL " if not d5 else "") + ("D7 FAIL" if not d7 else "")])
		if not (t["narrated"] as Dictionary).is_empty():
			print("           narrator (fallback) by event: %s" % [t["narrated"]])
		print("           front pages by story: %s" % [t["front_by_kind"]])
		if not d5:
			_band_failed("D5 (%s): %.1f%% of deliveries resolve a speaker, under %.0f%%" % [regime, 100.0 * share, 100.0 * SPEAKER_SHARE_MIN])
		if not d7:
			_band_failed("D7 (%s): %.1f front pages a term, outside [%.0f, %.0f]" % [regime, per_term, FRONT_PAGES_MIN, FRONT_PAGES_MAX])


# --- E6: the hook vocabulary, witnessed at runtime -----------------------------------

## The no-name-without-a-branch pin has a source-level twin in tests/test_events.gd's
## `_test_the_hook_vocabulary_is_swept`; this table is its runtime witness. For each
## hook in events_constants.ON_ACTIONS, stage the exact register its emitter reads
## (copied from EventHooks.fired's (src/sim/event_hooks.gd) own match arms -- when the machine moves an
## emitter, this staging moves with it) and assert an on_action-bearing fixture lands
## on the desk for a stub loader at likelihood 1.0. The shipped book carries SIX
## on_action events beside these fixtures (commodity_price_high has none since pass
## 23, like law_passed -- a vocabulary name needs a witness, not a consumer); the fixtures remain the sweep because the
## shipped hooks fire on live register writes this probe does not stage, so the hand
## staging is what witnesses every name on every run.
class _StubLoader:
	var events: Array = []
	var commodity_goods: Dictionary = {}
	var regions: Dictionary = {}


func _hook_fixture(hook: String):
	var raw := {
		"id": "hook_witness_%s" % hook,
		"name": "The hook witness",
		"summary": "A probe fixture: proves the %s hook reaches the desk." % hook,
		"likelihood": EventsK.LIKELIHOOD_MAX,
		"category": "scandal",
		"respond_months": 2,
		"severity": 2,
		"on_action": hook,
		"choices": [
			{"id": "act", "label": "Act", "summary": "Act on it.",
				"effects": {"bloc_offset": {"workers": 0.02}}},
			{"id": "wait", "label": "Wait", "summary": "Let it pass.", "default": true,
				"effects": {"bloc_offset": {"business": -0.02}}},
		],
	}
	# V5.2c: an exposure event must name its route and the kinds it answers.
	if hook == "exposure":
		raw["exposure"] = {"route": "press", "kinds": ["personal_wealth"]}
	var errors: Array[String] = []
	var ev = GameEvent.from_dict(raw, "events_probe fixture", errors,
		EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS, EconomyK.SECTOR_TREND.keys())
	if not errors.is_empty():
		printerr("the %s fixture did not load: %s" % [hook, errors])
		return null
	# The stage must land whatever the hook hash draws -- the fixture rides the
	# loader as authored; the likelihood is the staging's business.
	ev.likelihood = 1.0
	return ev


func _stage_hook(state, hook: String, month_index: int) -> void:
	var ns = state.player()
	match hook:
		"law_passed":
			# The readable window is LAST month's passage -- the emitter's pure
			# one-month lag, the minister_resigned shape one arm down: the
			# ledger stamps at APPLY time and the machine first reads at M+1.
			ns.law_ledger["probe_law"] = {"months": [month_index - 1]}
		"law_repealed":
			# The emitter's pure one-month lag -- stamped last month, like law_passed.
			ns.repealed_at["probe_law"] = month_index - 1
		"member_bill_passed":
			# The hook reads its own stamp (nation_state.gd), written only where an
			# assembly bill comes into force -- not last_law_result, which a later
			# division of the month overwrites.
			ns.assembly_bill_passed_month = month_index
		"minister_resigned":
			# The readable window is LAST month's resignation -- the emitters' own
			# one-month lag -- so the stamp is the absolute month before this one.
			var previous: int = month_index - 1
			ns.last_resignation = {"year": int(previous / 12), "month": previous % 12}
		"takeover_bid":
			ns.companies["probe_co"] = {"bid_month": month_index}
		"firm_failed":
			ns.companies["probe_co"] = {"failed_month": month_index}
		"commodity_price_high":
			# An EDGE since pass 22: Commodities stamps the month a price
			# crossed up through its high line, and the hook reads that stamp.
			ns.commodity_high_month = month_index
		"accession_won":
			ns.last_accession = {"org": "eu", "month_index": month_index}


func _table_e6_hooks() -> void:
	print("\n=== E6  HOOK RATES: every name in ON_ACTIONS, staged onto its register ===")
	print("Six shipped events carry on_action beside these fixtures; each row is")
	print("still a fixture at likelihood 1.0 on a stub loader, because the shipped")
	print("hooks fire on live register writes this probe does not stage.\n")
	var passed := 0
	for hook in EventsK.ON_ACTIONS:
		var ev = _hook_fixture(hook)
		if ev == null:
			print("%-22s FIXTURE DID NOT LOAD" % hook)
			_band_failed("E6: the %s fixture did not load through the real from_dict" % hook)
			continue
		var stub := _StubLoader.new()
		stub.events = [ev]
		var state = _new_state("FRA")
		var month_index: int = Events._absolute_month(int(state.year), int(state.month))
		_stage_hook(state, hook, month_index)
		# V5.2c: no hook fires an exposure; its door is the chain door the exposure
		# machine arms (Events.arm), so the witness arms it for this month.
		if hook == "exposure":
			Events.arm(state.player(), stub, String(ev.id), month_index)
		Events._tick_nation(state, state.player(), stub, month_index, true)
		var landed: bool = Events.is_pending(state.player()) \
			and Events.pending_event_id(state.player()) == String(ev.id)
		if landed:
			passed += 1
		else:
			_band_failed("E6: the %s hook never delivered its event" % hook)
		print("%-22s %s" % [hook, "witnessed" if landed else "*** NEVER LANDED ***"])
	print("\nhook vocabulary: %d/%d witnessed" % [passed, EventsK.ON_ACTIONS.size()])


# --- E7: the chooser spread over a term ----------------------------------------------

## The chooser's SITUATING claim, measured over whole nations rather than staged
## at a unit (the unit pin is test_events' chooser test). Declared before this
## run: at least 10 of the 28 answered something over 168 months; NO nation took
## a default -- the chooser always answers, so a defaulted record is a chooser
## that did not run; and the per-event choice distribution is NOT constant across
## nations -- two nations in two positions differing on one shared event is the
## whole claim, and zero differences would make the chooser a second default
## button.
func _table_e7_chooser() -> void:
	print("\n=== E7  CHOOSER SPREAD: what the other twenty-eight answered over %d months ===" % RUN_MONTHS)
	var state = _new_state("FRA")
	var per_nation := {}
	var per_event := {}
	for i in range(RUN_MONTHS):
		_tick_events(state, i)
		var year := int(state.year)
		var month := int(state.month)
		for nation_id in state.nations:
			if String(nation_id) == String(state.player_nation_id):
				continue
			var ns = state.nations[nation_id]
			var key := String(nation_id)
			if not per_nation.has(key):
				per_nation[key] = {"answered": 0, "defaulted": 0, "by_category": {}}
			var row: Dictionary = per_nation[key]
			# Records carry their own resolution month, so this month's answers are
			# found by that pair -- which also survives the EVENTS_KEPT cap: today's
			# records are always the newest in the register.
			for record in ns.event_history:
				if int(record.get("year", -1)) != year or int(record.get("month", -1)) != month:
					continue
				row["answered"] = int(row["answered"]) + 1
				if bool(record.get("defaulted", false)):
					row["defaulted"] = int(row["defaulted"]) + 1
				row["by_category"][String(record.get("category", ""))] = \
					int(row["by_category"].get(String(record.get("category", "")), 0)) + 1
				var by_choice: Dictionary = per_event.get_or_add(String(record.get("event_id", "")), {})
				var choice_id := String(record.get("choice_id", ""))
				by_choice[choice_id] = int(by_choice.get(choice_id, 0)) + 1
	print("%-5s %9s %10s   %s" % ["nation", "answered", "defaulted", "by category"])
	var any_answered := 0
	var total_defaulted := 0
	for key in per_nation.keys():
		var row: Dictionary = per_nation[key]
		if int(row["answered"]) > 0:
			any_answered += 1
		total_defaulted += int(row["defaulted"])
		var summary: Array[String] = []
		var cats: Array = row["by_category"].keys()
		cats.sort()
		for category in cats:
			summary.append("%s %d" % [category, row["by_category"][category]])
		print("%-5s %9d %10d   %s" % [key, int(row["answered"]), int(row["defaulted"]), "  ".join(summary)])
	var split_event := ""
	var split_detail := ""
	for event_id in per_event.keys():
		var by_choice: Dictionary = per_event[event_id]
		if by_choice.size() >= 2:
			split_event = event_id
			var parts: Array[String] = []
			for choice_id in by_choice.keys():
				parts.append("%s x%d" % [choice_id, by_choice[choice_id]])
			split_detail = ", ".join(parts)
			break
	print("\nper-event choice spread (the situating witness):")
	if split_event == "":
		print("  none -- every nation that answered the same event answered it the same way")
	else:
		print("  %s: %s" % [split_event, split_detail])
	var spread_ok := not split_event.is_empty()
	var nations_ok := any_answered >= 10
	var defaults_ok := total_defaulted == 0
	print("\nnations answering: %d of %d (band >= 10)%s" % [
		any_answered, per_nation.size(), "" if nations_ok else "  *** UNDER THE BAND ***"])
	print("defaults taken: %d (band == 0)%s" % [
		total_defaulted, "" if defaults_ok else "  *** A CHOOSER DID NOT RUN ***"])
	if not nations_ok:
		_band_failed("E7: only %d of %d nations answered anything -- the chooser ships unreachable" % [any_answered, per_nation.size()])
	if not defaults_ok:
		_band_failed("E7: %d defaulted records -- the chooser always answers, so a default is a chooser that did not run" % total_defaulted)
	if not spread_ok:
		_band_failed("E7: no event's choice split across nations -- the chooser does not situate")


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
## BLOC_OFFSET_MAX STRICTLY SLACK, on BOTH paths: the all-defaults path (what a player
## who never opens the window produces) and the answer-well path (every entry answered
## with its best choice on arrival). A clamp reached on either fails the band.
## docs/defence-model.md's measured-and-slack discipline.
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
		# Both paths on the real machine now -- the defaults path is what a player
		# who never opens the window produces; the answer-well path answers every
		# entry with _best_choice() on its arrival month. The old table measured
		# answer-at-expiry; arrival-answering is the same choice set with the same
		# effects, applied when a responsive player actually applies them.
		var d := _run_machine(regime, RUN_MONTHS, false, 0)
		var a := _run_machine(regime, RUN_MONTHS, true, 0)
		var dw := _worst_offset(d["state"])
		var aw := _worst_offset(a["state"])
		var def_saturated: bool = absf(float(dw["value"])) >= LegislatureK.BLOC_OFFSET_MAX - 0.001
		var ans_saturated: bool = absf(float(aw["value"])) >= LegislatureK.BLOC_OFFSET_MAX - 0.001
		print("%-14s %8d %8d   %-11s %9.4f   %-11s %9.4f%s" % [
			regime, int(d["months"]), int(d["arrivals"]),
			dw["bloc"], float(dw["value"]), aw["bloc"], float(aw["value"]),
			"   *** SATURATED ***" if def_saturated else "",
		])
		# The band is the header's: STRICTLY SLACK of the clamp on both paths.
		# Printing the marker without failing it left the run exiting 0 over
		# "every declared band PASSED". The answer-well path adds the best choices'
		# own offsets, and a clamp reached there is the same convergence of regimes.
		if def_saturated:
			_band_failed("E1b: regime %s on the all-defaults path reaches the bloc_offset clamp -- bloc %s at %.4f against +-%.2f" % [
				regime, dw["bloc"], float(dw["value"]), LegislatureK.BLOC_OFFSET_MAX])
		if ans_saturated:
			_band_failed("E1b: regime %s on the answer-well path reaches the bloc_offset clamp -- bloc %s at %.4f against +-%.2f" % [
				regime, aw["bloc"], float(aw["value"]), LegislatureK.BLOC_OFFSET_MAX])


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
