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
const C = preload("res://src/sim/economy_constants.gd")

## 6 as of V1.2b: political-system fields (system_id, head-of-state,
## lose_condition, term_limit) added to NationState, none of which a version-5
## save carries — a loaded game would read an empty lose_condition and never be
## able to end a run. SaveManager rejects an unknown version outright — see
## docs/data-architecture.md.
const SAVE_VERSION := 6

var save_version: int = SAVE_VERSION
var player_nation_id: String = ""

## Mirrored from the Clock on each monthly tick, so history entries are stamped.
## The Clock stays authoritative for the date; folding it in here is S9's call.
var year: int = 0
var month: int = 0

var nations := {}  # String id -> NationState
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
static func new_game(loader, player_id: String):
	var gs = new()
	gs.player_nation_id = player_id

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var party_list: Array = loader.parties.get(id, [])
		gs.nations[id] = _build_nation(loader.nations[id], id == player_id, party_list, loader.eu, loader.political_systems, gs.errors)

	if not gs.nations.has(player_id):
		gs.errors.append("player nation '%s' was not loaded" % player_id)
		return gs

	var baseline := Economy.neighbour_weighted_growth(gs)
	for ns in gs.nations.values():
		ns.trade_baseline_pct = baseline

	return gs


static func _build_nation(n, is_player: bool, party_list: Array, eu, political_systems: Dictionary, errors: Array[String]):
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

	ns.debt_eur_bn = n.debt_to_gdp_pct / 100.0 * ns.gdp_eur_bn

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

	# After recompute, so the starting deficit opinion measures against is real.
	Opinion.init_nation(ns)

	Elections.init_nation(ns, n, party_list, eu)
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
	Legislature.init_nation(ns)
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
	gs.year = year
	gs.month = month
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
		"year": year,
		"month": month,
		"nations": nations_dict,
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
	gs.year = int(d.get("year", 0))
	gs.month = int(d.get("month", 0))

	var nations_dict: Dictionary = d.get("nations", {})
	for id in nations_dict.keys():
		gs.nations[id] = NationState.from_dict(nations_dict[id])

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
