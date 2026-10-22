extends RefCounted

## THE MONTH. Every system's tick_month(), in the one order the game runs them.
##
## Until this file, the order lived in src/ui/main.gd's _on_month_elapsed and
## every harness carried a hand copy of it. The copies drifted -- V1.5d's two
## harnesses never called Media, tick_budget_probe never timed Commodities,
## events_probe's E4/E5 chain never ticked Commodities -- and a harness that
## omits a machine measures a world the game never runs (AGENTS.md, "green is
## not measured"). Now main.gd, the balance harnesses and the probes call this,
## so a system added here is added everywhere at once.
##
## The UI side of the month (cards, the pause, mark_all_dirty; src/ui/effects_ledger.gd
## measures recent_effects) stays in main.gd and runs through `on_step`, called before and after every
## step as `on_step.call(step, after, report)`: `step` is a name from STEPS,
## `after` is false before the step and true after it, and `report` is the
## Dictionary this function returns, filled as the month goes. That is what lets
## a card read the record a system wrote at the point it wrote it, and a probe act
## at a fixed slot, without either reaching into this file. It is also the timing
## seam: a probe that stamps the clock on both calls times every system without a
## copy of the order.
##
## `report` keys, each present once its step has run:
##   history_entry     Budget.snapshot merged with Opinion.snapshot, undated
##   character_acts    Characters.tick_month's acts (Array)
##   election_results  Elections.tick_month's results (Array)
##
## The caller sets state.year and state.month first: the clock is the caller's,
## a harness counts its own months and the game takes them from Clock.
##
## V5.1-0a. THE MONTH IS A CURSOR. begin() returns a Month, run_unit() runs its
## next unit of work and done() says when it is over; tick_month() is the three
## in a loop, so the cursor IS the month rather than a second copy of it. A unit
## is a whole step, except where a step comes in slices: Economy (its pre-pass,
## then one unit per nation) and Diplomacy (its settling pass, then one unit per
## actor), each from its own month_units(). src/ui/month_runner.gd runs the units
## across frames while the clock is held, which turns a ~245 ms month from one
## frozen frame into frames a player can watch -- and because it is the same code
## in the same order with nothing written between two units, the month spread
## over frames is the month run in one, byte for byte (tests/test_world_month.gd
## compares them). The hooks fire as they always did: `before` ahead of a step's
## first unit, `after` behind its last.

const Regions = preload("res://src/sim/regions.gd")
const Energy = preload("res://src/sim/energy.gd")
const Economy = preload("res://src/sim/economy.gd")
const Commodities = preload("res://src/sim/commodities.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Programme = preload("res://src/sim/programme.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Statute = preload("res://src/sim/statute.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")
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
const Judiciary = preload("res://src/sim/judiciary.gd")
const Characters = preload("res://src/sim/characters.gd")
const Elections = preload("res://src/sim/elections.gd")

## The step names `on_step` receives, in run order. tests/test_world_month.gd
## holds tick_month() to this list by recording the calls, so the list cannot
## become a comment that disagrees with the code.
const STEPS: Array[String] = [
	"Access", "Energy", "Economy", "Commodities", "Budget", "Orgs", "Inflation",
	"Media", "Programme", "Opinion", "History", "Calendar", "Discipline",
	"Legislature", "Statute", "Dissolution", "Diplomacy", "Defence", "Companies",
	"Industry", "Migration", "Investment", "Projects", "Campaign", "Pledges",
	"Demography", "Society", "Unrest", "Events", "Cabinet", "Characters",
	"Elections",
]


## One month in progress: what run_unit() needs between two calls. Data only.
class Month extends RefCounted:
	var state
	var loader
	var on_step: Callable
	## What tick_month() returns, filled as the month goes (the keys above).
	var report: Dictionary = {}
	## Index into STEPS of the step running, or of the next one to run.
	var step := 0
	## The running step's units still to run, and how many it has run.
	var units: Array = []
	var unit := 0
	var running := false
	## Built by Access, read by Energy.
	var access_by_nation: Dictionary = {}


## Economy early so budget percentages apply to this month's GDP; Opinion after
## the figures it reacts to have settled rather than last month's; Elections
## last, on settled state. See docs/economy-model.md.
static func tick_month(state, loader, on_step: Callable = Callable()) -> Dictionary:
	var month := begin(state, loader, on_step)
	while not done(month):
		run_unit(month)
	return month.report


static func begin(state, loader, on_step: Callable = Callable()) -> Month:
	var month := Month.new()
	month.state = state
	month.loader = loader
	month.on_step = on_step
	return month


static func done(month: Month) -> bool:
	return month.step >= STEPS.size()


## Where the cursor stands, as "step:unit" -- the key a caller remembers a unit's
## cost under, so the same unit next month can be planned into a frame.
static func unit_key(month: Month) -> String:
	return "%d:%d" % [month.step, month.unit if month.running else 0]


## The next unit: a step's `before` hook ahead of its first, its `after` behind
## its last, and nothing else between two calls.
static func run_unit(month: Month) -> void:
	var step: String = STEPS[month.step]
	if not month.running:
		month.running = true
		month.unit = 0
		_before(month.on_step, step, month.report)
		month.units = _step(month, step)
	if not month.units.is_empty():
		(month.units.pop_front() as Callable).call()
	month.unit += 1
	if month.units.is_empty():
		month.running = false
		_after(month.on_step, step, month.report)
		month.step += 1


## One step. Run whole here, returning [] -- or, for a step that comes in
## slices, handed back as its own module's units for run_unit() to run one at a
## time. One match in STEPS order, so the source reads in the order it runs.
static func _step(month: Month, step: String) -> Array:
	var state = month.state
	var loader = month.loader
	match step:
		# V2.8. The accessibility index per nation, built here because energy.gd never
		# learns that a graph exists. Same index Regions already computes, so the
		# Dijkstra rows are served from network.gd's own per-graph cache and this
		# costs a lookup. Immediately BEFORE Economy, because economy.gd READS
		# ns.energy_impulse_pct rather than computing it -- an energy tick placed after
		# the economy would price this month's mix against last month's growth, a
		# one-month lag in a channel with no reason to have one.
		"Access":
			for nation_id in state.nations.keys():
				month.access_by_nation[nation_id] = Regions.accessibility_for(
					state.nations[nation_id], state.regions.get(nation_id, []), state.region_graph)
		"Energy":
			Energy.tick_month(state, loader, month.access_by_nation)
		"Economy":
			return Economy.month_units(state)
		# V4.6. Immediately AFTER Economy, from which it derives every nation's capacity
		# off the `sector_output` that call just settled -- a tick before it would price
		# this month's production off last month's mix. BEFORE Opinion, so a figure this
		# layer writes can be read in the SAME month rather than a month late: Inflation's
		# slot and Orgs' rule, both stated at their own calls below.
		#
		# Since V4.4 this module's output HAS a live sim reader (the register itself still
		# has none; the reader takes a stamp on the nation): the events machine's
		# commodity_price_high hook reads the `ns.commodity_high_month` crossing stamp this
		# call writes, inside Events.tick_month, which runs AFTER this slot -- so the
		# same-month read this slot exists for now has its consumer, and the order is
		# load-bearing where V4.6 could only pin it.
		# Said out loud because that is exactly when an order rots: tests/test_events.gd's
		# `_test_tick_order_pin` is what stops a later task placing Events before these
		# four modules by convenience -- its five hooks read registers Commodities,
		# Orgs, Statute and Industry wrote this same tick (the pin in
		# tests/test_commodities.gd holds only Economy < Commodities < Opinion).
		"Commodities":
			Commodities.tick_month(state, loader)
		"Budget":
			Budget.tick_month(state)
		# Between Budget and Opinion, and both halves of that are load-bearing. AFTER
		# Budget, because the burden reads the deficit that Budget has just settled and
		# charges its penalty into NEXT month's recompute -- which is what stops a rule
		# on the deficit feeding a fine that widens the deficit that deepens the breach.
		# BEFORE Opinion, because the `europe` issue reads the burden, and wired the
		# other way round every org reaction would carry a spurious extra month of lag.
		"Orgs":
			Orgs.tick_month(state, loader)
		# V1.5d, and BEFORE Opinion rather than after it, which is the opposite of where
		# Society and Unrest sit. Those two write a load Opinion consumes next month on
		# purpose, to break a loop that runs through approval. This one reads
		# coalition_position, which Elections and Government rewrite AFTER Opinion in this
		# same sequence -- so it is already reading last month's government and the loop
		# approval -> censure -> re-formation -> framing -> approval is broken structurally,
		# for free.
		# V1.6b. AFTER Economy, which settled the unemployment it reads, and BEFORE Opinion,
		# which prices it in the SAME month -- unlike Society and Unrest below, which sit
		# after Opinion and are read on the following one. Said here because a reader
		# comparing the two will otherwise assume symmetry.
		#
		# tests/test_inflation.gd reads this file's source and fails if the call is
		# missing, because V1.5d cost a session to two harnesses that never called
		# Media.tick_month() and therefore agreed about nothing. Budget.project() and
		# tests/test_budget.gd's mirror of it are the two harnesses left that tick a
		# subset of their own, and the same check reads them.
		"Inflation":
			Inflation.tick_month(state)
		"Media":
			Media.tick_month(state, loader)
		# V4.1, immediately before Opinion: the register concludes first, so a
		# conclusion and the pulse Opinion prices off it land in the SAME month --
		# programme_pulse() reads concluded_this_month(), which matches the
		# conclusion's stamped (terms_served, months_in_term) against the live pair.
		#
		# THE TERM-BOUNDARY GUARANTEE: no code between this call and the
		# Opinion.tick_month call below writes either counter, and the ONLY writer
		# of the pair anywhere in this month is Elections.tick_month, which runs
		# LAST -- so a conclusion landing in the election month is stamped and paid
		# before the vote can reset months_in_term. The pair cannot desync within a
		# tick by construction. If Elections ever moves between these two calls, a
		# won election stamps (T, m) and resets to (T+1, 0) between stamp and read,
		# concluded_this_month() matches nothing, and the pulse is silently unpaid --
		# move Elections back after the pair before trusting a conclusion again.
		# The two hooks between them are a caller's, and a caller writes neither
		# counter: main.gd hooks neither of them, and no harness does.
		"Programme":
			Programme.tick_month(state, loader)
		"Opinion":
			Opinion.tick_month(state)
		# Opinion is deliberately not folded into Budget.snapshot(): Budget.project()
		# runs only the economy and budget ticks on its copy, so a snapshot carrying
		# approval would make the projection-equals-reality test compare a real month
		# against a stale one. The history entry is the two snapshots merged.
		"History":
			var entry := Budget.snapshot(state)
			entry.merge(Opinion.snapshot(state))
			state.append_history(entry)
			month.report["history_entry"] = entry
		# U6a prunes resolved bookings older than the strip can reach. The register is
		# the diary's whole memory, so this is what keeps a save file finite. A booking
		# still open is never pruned, so the slot is free relative to the day loop that
		# resolves bookings: a harness that keeps appointments after this call reads the
		# same register it would have before it.
		"Calendar":
			Calendar.tick_month(state)
		# Discipline reads the approval Opinion has just settled, so it goes after
		# that and before anything that reads a coalition bonus or a censure vote.
		"Discipline":
			Discipline.tick_month(state, loader)
		# Cooldowns count down before the election check, same ordering reasoning as
		# everything else in this month: state settles top to bottom, elections read
		# it last.
		"Legislature":
			Legislature.tick_month(state, loader)
		# V4.2 T6. The assembly's own life -- private members' bills and the
		# chiefs' lobbying -- ticks AFTER the legislature, so a bill failing its
		# division writes its authored cooldown AFTER this month's countdown pass
		# has run and keeps its full length (the V2.8 ordering, one machine down).
		"Statute":
			Statute.tick_month(state, loader)
		"Dissolution":
			Dissolution.tick_month(state)
		# Relations drift and diplomatic cooldowns, alongside the other cooldown
		# ticks. After Opinion, which has already read the bloc offsets an action
		# wrote last month, and before Elections, which runs last on settled state.
		"Diplomacy":
			return Diplomacy.month_units(state, loader)
		# V1.3g: capability converges, and alliance obligations are reconciled against
		# the measures Diplomacy has just finished writing. AFTER Diplomacy so the
		# obligation arrives in the month the measure did -- that is the one thing here
		# with no lag, and it is what the whole feature is about. Both PRICES then lag by
		# exactly one month together, because Budget has already closed this month's
		# books: a same-month bill with a next-month opinion cost would be two lags where
		# one will do, and they would disagree about which month the deployment started.
		#
		# The lag also breaks a real loop structurally rather than by iterating: bill ->
		# deficit -> a PRECONDITION_FIELDS entry -> which verbs are available -> measures
		# -> obligations -> bill. src/sim/orgs.gd makes the same call for the same reason.
		"Defence":
			Defence.tick_month(state)
		# V1.4a: subsidised firms take share from their named rivals, and all three firm
		# prices are recomputed. In Defence's slot for Defence's reason -- Budget has
		# closed this month's books, so the bill and both deviation channels lag by
		# exactly one month TOGETHER rather than one of them lagging alone, and the lag
		# breaks the same loop structurally: bill -> deficit -> a PRECONDITION_FIELDS
		# entry -> which verbs are available -> a new subsidy -> bill.
		"Companies":
			Companies.tick_month(state, loader)
		# V4.7b: the autonomy machine ticks after Companies and before Migration.
		"Industry":
			Industry.tick_month(state, loader)
		# After Companies, because the city pull reads live headcount: a month in which a
		# subsidy moved a firm's hiring should move people in the same month rather than
		# the next one. After Economy for the same reason one level up -- the region pull
		# reads live regional output and unemployment, both settled in Economy's own tick.
		"Migration":
			Migration.tick_month(state, loader)
		# V1.6e: the capital each sector's standing programme has bought converges toward
		# the programme's intensity, and the bill is recomputed. In Companies' slot for
		# Companies' reason, and the loop it breaks is the identical one: bill -> deficit
		# -> a PRECONDITION_FIELDS entry -> which investment actions are available -> a
		# new programme -> bill. Sixth time this argument has been made.
		"Investment":
			Investment.tick_month(state)
		# V1.6f: every project under construction loses a month, any that run out COMPLETE
		# and write their permanent addend, and the bill is recomputed. In Investment's
		# slot for Investment's reason, and the loop is the identical one a seventh time:
		# bill -> deficit -> a PRECONDITION_FIELDS entry -> which project actions are
		# available -> a new build -> bill. Advance, complete, then price, so a project
		# that finishes this month stops billing this month.
		"Projects":
			Projects.tick_month(state, loader)
		# V1.7a: a month of every campaign effort in the field, onto the mobilisation the
		# vote reads, and the bill recomputed -- or the whole register cleared, if the
		# run-up is over. In Projects' slot for Projects' reason, and the loop is the
		# identical one an eighth time: bill -> deficit -> a PRECONDITION_FIELDS entry ->
		# which campaign actions are available -> a new effort -> bill.
		#
		# BEFORE Elections, which is what makes the month of the vote count: the window is
		# inclusive of it, so the last month of effort is accrued and read by the vote it
		# was bought for. Elections then pushes next_executive_* five years out, and NEXT
		# month this call finds the window closed and clears the register. That is the
		# whole of the clearing mechanism: a level read, so campaign.gd needs no hook at
		# the vote and elections.gd needs no knowledge of the window.
		"Campaign":
			Campaign.tick_month(state, loader)
		# V1.7b: every promise on the books judged against the state it named, and charged
		# for the month if it is being broken. Immediately after Campaign for the same
		# reason Campaign sits before Elections -- the last month of a term is judged, and
		# THEN the vote is held.
		#
		# There is no loop to break here and so no lag to argue about: a promise writes
		# ns.bloc_offset, which is not a spending line, not a deficit and not a
		# PRECONDITION_FIELDS entry of its own. It is also why this call is absent from
		# Budget.project(): a projection that charged a broken promise would be a budget
		# preview quietly moving approval.
		"Pledges":
			Pledges.tick_month(state, loader)
		# V1.5a: services converge on what the country actually spends on them, delivered.
		# In Companies' slot for Companies' reason and not for the general tick-order one:
		# quality reaches `overall_approval_pct`, which is a PRECONDITION_FIELDS entry, so
		# quality -> approval -> which laws are available -> a `society` law -> corruption
		# -> quality closes exactly the loop the one-month lag exists to break. Fifth time
		# this argument has been made, and the first where the loop runs through opinion
		# rather than through the deficit.
		# V1.5b, immediately before Society: the quality stock divides by this layer's
		# dependency factor, so demography must have settled before quality reads it.
		"Demography":
			Demography.tick_month(state)
		"Society":
			Society.tick_month(state)
		# V1.5c, immediately after Society: the grievance target reads the `health` and
		# `pensions` satisfactions, which read the quality stock the line above just settled.
		# It stays after Opinion for the same reason the two above it do, and the loop it
		# breaks is a second one -- `unrest_pct` is itself a PRECONDITION_FIELDS entry, so
		# unrest -> which laws are available -> a settlement law -> the stance -> unrest.
		"Unrest":
			Unrest.tick_month(state)
		# V1.8, immediately after Unrest and before Cabinet and Elections. AFTER Unrest
		# because `unrest_pct` is one of the fields an event may be preconditioned on and it
		# has only just settled; BEFORE Elections for the reason everything in this month
		# sits above it -- state settles top to bottom and the vote reads it last.
		"Events":
			Events.tick_month(state, loader)
		# Reads unpopularity Opinion already settled and discipline Discipline
		# already ticked -- a resignation this month is judged against this
		# month's numbers, not last month's.
		"Cabinet":
			Cabinet.tick_month(state, loader)
		# V4.3, after Cabinet (wants read Opinion-settled state and the cabinet's
		# vacancies) and before Elections (the stamp pair's only writer still runs
		# last, and a challenge's new party leader is in place before the vote
		# prices it). The meters are read here and handed in -- the leaf law keeps
		# unrest.gd/media.gd/judiciary.gd un-preloaded in characters.gd. The acts
		# are a record for the caller, not state.
		"Characters":
			var player = state.player()
			month.report["character_acts"] = Characters.tick_month(state, loader, {
				"grievance": float(player.unrest_pct),
				"press_freedom": float(player.press_freedom),
				"judicial_independence": Judiciary.independence_deviation(player),
			})
		# Elections run last, on the already-settled history entry, and can fire a
		# national and an EP result in the same month (France and Belgium, June 2029).
		"Elections":
			month.report["election_results"] = Elections.tick_month(state, loader)
	return []


static func _before(on_step: Callable, step: String, report: Dictionary) -> void:
	if on_step.is_valid():
		on_step.call(step, false, report)


static func _after(on_step: Callable, step: String, report: Dictionary) -> void:
	if on_step.is_valid():
		on_step.call(step, true, report)
