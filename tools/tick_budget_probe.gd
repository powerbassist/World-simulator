extends SceneTree

## Tick-budget probe: godot --headless --script res://tools/tick_budget_probe.gd
##
## The V3 performance pass step-0. AGENTS.md's V4 notes say it straight: nothing
## in this project has ever timed a simulation month. The player's complaint
## (2026-09-14) is "a lot of freezes", and the clock runs at 1/3/7 days per
## second -- a month every ~4.3 s at speed 3 -- so a month tick that costs
## hundreds of ms IS a visible freeze at every month boundary, and no re-run
## would have caught it because every harness prints invariants, never time.
##
## This times each system call in main.gd's exact _on_month_elapsed order (the
## balance_probe.gd mirror, which tests/test_inflation.gd holds to the same
## sequence) over 60 months on the live V3.3 roster -- 29 nations, 213 regions,
## 1065 cities -- and prints per-system totals, means and worst months.
##
## Not a test, excluded from run_tests.sh: it is the committed instrument beside
## the verdict it produces, measure_austerity_peak.gd's precedent. The numbers
## it prints are wall-clock on one dev machine -- read the RATIO between rows,
## not the absolute ms.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Regions = preload("res://src/sim/regions.gd")
const Energy = preload("res://src/sim/energy.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Migration = preload("res://src/sim/migration.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Events = preload("res://src/sim/events.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Elections = preload("res://src/sim/elections.gd")
const Trade = preload("res://src/sim/trade.gd")

const MONTHS := 60
const START_YEAR := 2026

## name -> [total_us, calls, max_us]
var _us: Dictionary = {}


func _time(name: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	var dt := Time.get_ticks_usec() - t0
	if not _us.has(name):
		_us[name] = [0, 0, 0]
	var row: Array = _us[name]
	row[0] += dt
	row[1] += 1
	row[2] = maxi(int(row[2]), dt)


func _initialize() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return
	var state = GameState.new_game(loader, "FRA")
	state.year = START_YEAR
	state.month = 1
	print("nations=%d regions=%d cities=%d" % [
		state.nations.size(),
		state.regions.keys().reduce(func(a: int, k: String) -> int: return a + (state.regions[k] as Array).size(), 0),
		0,
	])

	var month := 1
	var year := START_YEAR
	# One warmup month OUTSIDE the timer: the first tick pays one-time lazy
	# caches (network.gd's per-graph Dijkstra table among them), and counting it
	# would pin a phantom 100x outlier on whichever system ran first. Clearing
	# the accumulator is the "outside the timer" the comment always claimed:
	# _tick records through _time, so without the clear the warmup's ~2 s build
	# landed in the accessibility row's max and mean denominator -- the 2026-09-16
	# playtest read that artifact as a live 2.24 s month-boundary freeze.
	_tick(state, loader, year, month)
	_us.clear()

	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month
		_tick(state, loader, year, month)

	_report()
	quit(0)


func _tick(state, loader, year: int, month: int) -> void:
	# --- main.gd _on_month_elapsed, in order ---
	var access_by_nation: Dictionary = {}
	_time("accessibility loop", func() -> void:
		for member_id in state.nations.keys():
			access_by_nation[member_id] = Regions.accessibility_for(
				state.nations[member_id], state.regions.get(member_id, []), state.region_graph))
	_time("Energy", func() -> void: Energy.tick_month(state, loader, access_by_nation))
	_time("Economy", func() -> void: Economy.tick_month(state))
	_time("Budget", func() -> void: Budget.tick_month(state))
	_time("Orgs", func() -> void: Orgs.tick_month(state, loader))
	_time("Inflation", func() -> void: Inflation.tick_month(state))
	_time("Media", func() -> void: Media.tick_month(state, loader))
	_time("Opinion", func() -> void: Opinion.tick_month(state))
	var entry: Dictionary
	_time("history snapshot", func() -> void:
		entry = Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry))
	_time("Discipline", func() -> void: Discipline.tick_month(state, loader))
	_time("Legislature", func() -> void: Legislature.tick_month(state, loader))
	_time("Dissolution", func() -> void: Dissolution.tick_month(state))
	_time("Diplomacy", func() -> void: Diplomacy.tick_month(state, loader))
	_time("Defence", func() -> void: Defence.tick_month(state))
	_time("Companies", func() -> void: Companies.tick_month(state, loader))
	_time("Migration", func() -> void: Migration.tick_month(state, loader))
	_time("Investment", func() -> void: Investment.tick_month(state))
	_time("Projects", func() -> void: Projects.tick_month(state, loader))
	_time("Campaign", func() -> void: Campaign.tick_month(state, loader))
	_time("Pledges", func() -> void: Pledges.tick_month(state, loader))
	_time("Demography", func() -> void: Demography.tick_month(state))
	_time("Society", func() -> void: Society.tick_month(state))
	_time("Unrest", func() -> void: Unrest.tick_month(state))
	_time("Events", func() -> void: Events.tick_month(state, loader))
	_time("Cabinet", func() -> void: Cabinet.tick_month(state, loader))
	_time("Calendar", func() -> void: Calendar.tick_month(state))
	_time("Elections", func() -> void: Elections.tick_month(state, loader))
	# --- the monthly UI-side reads main.gd also pays (map Flows.refresh's parts
	# and the action bar's read), kept because they are month-boundary work the
	# frame pays even though no sim system owns them ---
	_time("Trade.weight_table", func() -> void: Trade.weight_table(state))


func _report() -> void:
	var total := 0
	var worst := 0
	var worst_rows: Array = []
	for name in _us:
		var row: Array = _us[name]
		total += int(row[0])
	for name in _us:
		var row: Array = _us[name]
		var mean := float(row[0]) / float(row[1])
		worst_rows.append({"name": name, "mean": mean, "max": float(row[2]), "total": float(row[0])})
	worst_rows.sort_custom(func(a, b) -> bool: return float(a["mean"]) > float(b["mean"]))
	print("%d months timed (warmup excluded)" % MONTHS)
	print("%-22s %10s %10s %10s" % ["system", "mean us", "max us", "total ms"])
	for r in worst_rows:
		print("%-22s %10.0f %10.0f %10.1f" % [r["name"], r["mean"], r["max"], float(r["total"]) / 1000.0])
	print("%-22s %10.0f %10s %10.1f" % ["MONTH TOTAL (mean)", float(total) / float(MONTHS), "-", float(total) / 1000.0])
