extends RefCounted

## The live game. Everything that changes as the simulation runs, and nothing
## that does not — static content stays in data/ and is never mutated.
##
## Systems in src/sim/ read and write this. The UI reads it and never writes it;
## player intent comes back as an explicit command (Budget.commit). See
## docs/data-architecture.md and engine-decision.md Rule 2.
##
## Minimal on purpose: S5 adds opinion, S6 adds election state, S9 adds the
## serialisation. Fields are added by the session whose model reads them.

const NationState = preload("res://src/core/nation_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const C = preload("res://src/sim/economy_constants.gd")

## 6 as of V1.2b: political-system fields (system_id, head-of-state,
## lose_condition, term_limit) added to NationState, none of which a version-5
## save carries — a loaded game would read an empty lose_condition and never be
## able to end a run. 7 as of V1.2c: amendment_rule, mutable at runtime (an
## amendment may entrench its own threshold), so a version-6 save's absent
## value would silently read as "" -- no rule ever passes, an amendment law is
## proposable to no one, and the failure is silent rather than loud. 8 as of
## V1.2d: permits_system_change, and system_id/lose_condition/head-of-state
## become mutable at runtime for the first time (a system transition writes
## all of them) -- a version-7 save's absent permits_system_change would
## silently read as false, refusing a transition the nation's own data
## permits. SaveManager rejects an unknown version outright — see
## docs/data-architecture.md. 9 as of V1.3a: `relations` below, plus the
## `bloc_offset` -> `bloc_offset` rename on NationState. Relations earn the
## bump under this comment's own rule and `scenario_id`'s absence of one -- the
## test is not "a new field" but "would a missing field read as something
## wrong?". An absent relations dictionary reads as {}, every pair then resolves
## to 0.0, and 0.0 is the WORST possible relations rather than a neutral
## default: a version-8 save would load as ten nations who all hate each other.
## The rename is the same class of loud-vs-silent failure -- a version-8 save's
## `bloc_offset` key would be dropped on load, quietly discarding every
## accumulated approval offset a played game has earned.
const SAVE_VERSION := 9

var save_version: int = SAVE_VERSION
var player_nation_id: String = ""

## Which data/scenarios/*.json start this game was begun under; "" is the
## standard start. Read-only after new_game() -- a scenario is an authored
## STARTING state, applied once, so nothing mutates this and no system reads it
## except the UI, which shows the player which start they are in.
##
## No SAVE_VERSION bump for it: a scenario's effects live in the ordinary
## fields a save already carries, and a version-8 save with no scenario_id
## reads as "" -- which is correct for every save that exists, not silently
## wrong. That is the condition this file's SAVE_VERSION comment gives for a
## bump, and it does not hold here. See docs/scenario-model.md.
var scenario_id: String = ""

## Mirrored from the Clock on each monthly tick, so history entries are stamped.
## The Clock stays authoritative for the date; folding it in here is S9's call.
var year: int = 0
var month: int = 0

var nations := {}  # String id -> NationState

## Pair-keyed diplomatic relations, 0-100, one entry per unordered pair of the
## ten -- 45 in all. The FIRST live state in this project that is neither
## per-nation nor global, which is why it sits here rather than on NationState:
## a relations score belongs to a pair, and mirroring it onto both nations would
## double the write path and reintroduce a divergence the symmetric key makes
## impossible.
##
## Keys are built ONLY by src/core/relations.gd's key(), never by string
## concatenation at a call site. Seeded once by Diplomacy.seed_relations() from
## values derived at load, then owned by Diplomacy.tick_month() and by the
## player's own diplomatic actions. See docs/diplomacy-model.md.
var relations := {}  # sorted pair key, e.g. "DEU|FRA" -> float in [0, 100]

var history: Array[Dictionary] = []

## What the player's last few commands actually did -- U4. Newest first, each
## {label, year, month, movements}, movements in Trends.movements_between()
## shape. Appended by main.gd's _on_month_elapsed(), the one place a committed
## decision's baseline meets the history entry it is measured against.
var recent_effects: Array[Dictionary] = []

## Problems found while building the state. Surfaced the same way the loader's
## are — loudly, naming the nation and the field.
var errors: Array[String] = []


## Build live state by copying starting values out of loaded static data.
## `loader` is a DataLoader that has already run load_all() without errors.
##
## `scenario_id` names a data/scenarios/*.json start; "" is the standard start,
## which is what every existing caller wants and so what the default gives. A
## scenario applies to the PLAYER's nation only, once, here -- see
## docs/scenario-model.md.
static func new_game(loader, player_id: String, scenario_id: String = ""):
	var gs = new()
	gs.player_nation_id = player_id
	gs.scenario_id = scenario_id

	var scenario = null
	if scenario_id != "":
		scenario = loader.scenarios.get(scenario_id)
		if scenario == null:
			gs.errors.append("scenario '%s' was not loaded" % scenario_id)
		elif scenario.nation_id != player_id:
			# Refused, not silently ignored: a scenario authored for another
			# nation would otherwise produce a game that says it is running one
			# start and is running a different one.
			gs.errors.append("scenario '%s' is authored for nation '%s', not the player's '%s'" % [scenario_id, scenario.nation_id, player_id])
			scenario = null

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var party_list: Array = loader.parties.get(id, [])
		var applied = scenario if id == player_id else null
		gs.nations[id] = _build_nation(loader.nations[id], id == player_id, party_list, loader.eu, loader.political_systems, gs.errors, applied)

	if not gs.nations.has(player_id):
		gs.errors.append("player nation '%s' was not loaded" % player_id)
		return gs

	var baseline := Economy.neighbour_weighted_growth(gs)
	for ns in gs.nations.values():
		ns.trade_baseline_pct = baseline

	# After every nation exists, because a pair needs both halves, and outside
	# _build_nation() because relations are the one piece of starting state that
	# is not a nation's own. Reads the loader's Nation objects (eu_member,
	# neighbours) rather than NationState -- neither input is live state and
	# neither ever changes. See docs/diplomacy-model.md.
	Diplomacy.seed_relations(gs, loader)

	return gs


## `scenario` is a Scenario for the player's nation, or null for a standard
## start and for every non-player nation. It overrides exactly three things --
## debt, seat composition, starting approval -- each at the one point below
## where that value first enters live state. Everything downstream (discipline,
## the coalition, the cabinet, dissolution) then reads the overridden figures
## and needs no scenario awareness of its own. See docs/scenario-model.md.
static func _build_nation(n, is_player: bool, party_list: Array, eu, political_systems: Dictionary, errors: Array[String], scenario = null):
	var ns = NationState.new()
	ns.id = n.id
	ns.has_budget = is_player
	ns.population = float(n.population)

	# Sector shares sum to 1.0 only within the validator's tolerance, so GDP is
	# defined as the sum of sector output rather than the other way round. That
	# invariant then holds exactly, forever, and the economy tick preserves it.
	for key in C.SECTOR_TREND.keys():
		ns.sector_output[key] = n.gdp_eur_bn * float(n.sectors.get(key, 0.0))
	ns.gdp_eur_bn = _sum(ns.sector_output)
	ns.potential_gdp_eur_bn = ns.gdp_eur_bn  # start at a zero output gap

	ns.unemployment_pct = n.unemployment_pct
	ns.start_unemployment_pct = n.unemployment_pct
	ns.structural_unemployment_pct = n.unemployment_pct

	# Before Budget.recompute() below, so the debt service a scenario's debt
	# implies is in the starting deficit that Opinion then measures against --
	# an inherited debt is a permanent drag on the budget, which is the whole
	# point of the axis, rather than a number on a panel.
	var debt_to_gdp_pct: float = n.debt_to_gdp_pct
	if scenario != null and scenario.has_debt_to_gdp_pct:
		debt_to_gdp_pct = scenario.debt_to_gdp_pct
	ns.debt_eur_bn = debt_to_gdp_pct / 100.0 * ns.gdp_eur_bn

	ns.tax_rates_pct = n.tax_rates_pct.duplicate(true)
	ns.start_tax_rates_pct = ns.tax_rates_pct.duplicate(true)
	ns.spending_pct_gdp = n.spending_pct_gdp.duplicate(true)
	ns.start_spending_pct_gdp = ns.spending_pct_gdp.duplicate(true)
	ns.other_spending_pct_gdp = n.other_spending_pct_gdp

	# Calibrate the residual so starting revenue equals the authored real figure.
	var modelled := Budget.modelled_revenue_total(ns.tax_rates_pct, ns.start_tax_rates_pct)
	ns.other_revenue_pct_gdp = n.tax_revenue_pct_gdp - modelled
	if ns.other_revenue_pct_gdp < 0.0:
		errors.append(
			"%s: modelled taxes yield %.1f%% of GDP but the nation only collects %.1f%% — revenue residual would be negative, clamped to 0" %
			[n.id, modelled, n.tax_revenue_pct_gdp]
		)
		ns.other_revenue_pct_gdp = 0.0

	ns.trend_annual_pct = Economy.trend_pct(ns)
	ns.growth_annual_pct = ns.trend_annual_pct
	Budget.recompute(ns)

	# Before Opinion, which is the one init that now WRITES bloc_offset --
	# a scenario's authored approval is held at its target through that
	# accumulator, and Legislature.init_nation() zeroes it. Moved ahead of
	# Opinion rather than teaching Legislature to spare one key: it zeroes law
	# state and reads nothing, so it is order-independent against everything
	# here. See docs/scenario-model.md.
	Legislature.init_nation(ns)
	# Order-independent against everything here for the same reason Legislature
	# is: it zeroes this nation's own diplomacy record and reads nothing. The
	# relations themselves are pair state, seeded in new_game() once every
	# nation exists.
	Diplomacy.init_nation(ns)

	# After recompute, so the starting deficit opinion measures against is real.
	Opinion.init_nation(ns, scenario.bloc_approval if scenario != null else {})

	Elections.init_nation(ns, n, party_list, eu, scenario.seat_share if scenario != null else {})
	# Before Government, which reads discipline the moment it computes the first
	# coalition bonus — seeding after formation would score that one government
	# against an empty table.
	Discipline.init_nation(ns, party_list)
	# After Elections, which seeds seats_by_party and incumbent_party_id — the
	# two things a formation search reads.
	Government.init_nation(ns, n, party_list)

	# The template is a constraint the loader already enforced against this
	# nation's own flat fields (data_loader.gd's _validate_political_system) --
	# lose_condition is the one field only the template carries, so it is read
	# here rather than copied from Nation like formation_method/censure_rule
	# above. See docs/political-systems.md.
	var system = political_systems.get(n.system_id)
	ns.lose_condition = system.lose_condition if system != null else ""
	# After Government, which forms the starting coalition Cabinet.seat() reads.
	# Called here rather than from inside government.gd -- Cabinet depends on
	# Government, so the reverse would be a preload() cycle. See
	# docs/cabinet-model.md.
	Cabinet.init_nation(ns)
	Cabinet.seat(ns, party_list)
	Dissolution.init_nation(ns, n)

	return ns


static func _sum(d: Dictionary) -> float:
	var total := 0.0
	for v in d.values():
		total += float(v)
	return total


func player():
	return nations.get(player_nation_id)


## Deep copy for the budget projection: the same simulation, run forward on a
## throwaway. History is deliberately not copied — a projection has no past.
func duplicate_state():
	var gs = new()
	gs.save_version = save_version
	gs.player_nation_id = player_nation_id
	gs.scenario_id = scenario_id
	gs.year = year
	gs.month = month
	gs.relations = relations.duplicate(true)
	for id in nations.keys():
		gs.nations[id] = nations[id].duplicate_state()
	return gs


## Stamp a simulation snapshot with the current date and record it.
func append_history(snapshot: Dictionary) -> void:
	var entry := snapshot.duplicate(true)
	entry["year"] = year
	entry["month"] = month
	history.append(entry)


## Serialise the whole live state to a plain, JSON-safe Dictionary. Same field
## set as duplicate_state(), walked the same way, plus history — a save is not
## a projection, so unlike duplicate_state() the chart data comes along. errors
## does not: it is new-game diagnostics, meaningless once a game has been
## played and saved. See docs/data-architecture.md Persistence.
func to_dict() -> Dictionary:
	var nations_dict := {}
	for id in nations.keys():
		nations_dict[id] = nations[id].to_dict()

	return {
		"save_version": save_version,
		"player_nation_id": player_nation_id,
		"scenario_id": scenario_id,
		"year": year,
		"month": month,
		"nations": nations_dict,
		"relations": relations,
		"history": history,
		"recent_effects": recent_effects,
	}


## Inverse of to_dict(). Does not check save_version — the caller (SaveManager)
## checks it before this is ever called, since a mismatch must fail loudly
## rather than build a half-understood state.
static func from_dict(d: Dictionary):
	var gs = new()
	gs.save_version = int(d.get("save_version", SAVE_VERSION))
	gs.player_nation_id = d.get("player_nation_id", "")
	# Absent in a version-8 save, and "" is exactly right for one: those games
	# were all standard starts. See the field's own declaration for why this is
	# the one runtime-readable addition that does not earn a version bump.
	gs.scenario_id = d.get("scenario_id", "")
	gs.year = int(d.get("year", 0))
	gs.month = int(d.get("month", 0))

	var nations_dict: Dictionary = d.get("nations", {})
	for id in nations_dict.keys():
		gs.nations[id] = NationState.from_dict(nations_dict[id])

	# Re-floated key by key rather than taken wholesale: JSON round-trips a
	# whole-number score as an int, and a relations dictionary holding a mix of
	# ints and floats would make the drift arithmetic depend on how a value
	# happened to be saved.
	var rel: Dictionary = d.get("relations", {})
	for pair_key in rel.keys():
		gs.relations[pair_key] = float(rel[pair_key])

	var hist: Array = d.get("history", [])
	var typed_hist: Array[Dictionary] = []
	for entry in hist:
		typed_hist.append(entry as Dictionary)
	gs.history = typed_hist

	var effects: Array = d.get("recent_effects", [])
	var typed_effects: Array[Dictionary] = []
	for entry in effects:
		typed_effects.append(entry as Dictionary)
	gs.recent_effects = typed_effects

	return gs
