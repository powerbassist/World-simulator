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
const C = preload("res://src/sim/economy_constants.gd")

const SAVE_VERSION := 1

var save_version: int = SAVE_VERSION
var player_nation_id: String = ""

## Mirrored from the Clock on each monthly tick, so history entries are stamped.
## The Clock stays authoritative for the date; folding it in here is S9's call.
var year: int = 0
var month: int = 0

var nations := {}  # String id -> NationState
var history: Array[Dictionary] = []

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
		gs.nations[id] = _build_nation(loader.nations[id], loader.policy_defaults, id == player_id, gs.errors)

	if not gs.nations.has(player_id):
		gs.errors.append("player nation '%s' was not loaded" % player_id)
		return gs

	var baseline := Economy.neighbour_weighted_growth(gs)
	for ns in gs.nations.values():
		ns.trade_baseline_pct = baseline

	return gs


static func _build_nation(n, defaults: Dictionary, is_player: bool, errors: Array[String]):
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

	ns.tax_rates_pct = (defaults.get("tax_rates_pct", {}) as Dictionary).duplicate(true)
	ns.start_tax_rates_pct = ns.tax_rates_pct.duplicate(true)
	ns.spending_pct_gdp = (defaults.get("spending_pct_gdp", {}) as Dictionary).duplicate(true)
	ns.start_spending_pct_gdp = ns.spending_pct_gdp.duplicate(true)
	ns.other_spending_pct_gdp = float(defaults.get("other_spending_pct_gdp", 0.0))

	# Calibrate the residual so starting revenue equals the authored real figure.
	var modelled := Budget.modelled_revenue_total(ns.tax_rates_pct)
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
