extends RefCounted

## The electricity mix, its import dependency, and the fleet that moves them --
## V2.8. Model: docs/energy-model.md.
##
## V3.5: the mix now has THREE derived reads -- dependency, impulse, emissions --
## each a pure read over the same partition.
##
## THE MIX IS A PARTITION, NOT A STOCK. The measured national shares are the
## baseline and built capacity is the deviation, so with an empty register every
## quantity here reads EXACTLY its measured content -- trade_baseline_by_partner's
## idiom at V1.3b and credit.gd's spread-reads-exactly-0.0 at V1.6c. That is what
## makes the balance re-run bit-identical until a player builds something, and it is
## a claim tests/test_energy.gd asserts at 0.0 rather than at 1e-9.
##
## THE GRID IS NATIONAL, AND THE REFUSAL IS THE MODEL. A power station serves a
## grid, so energy adds NO fourth zero-mean term to Regions.trend_deviation_pct().
## What the PLACE buys is priced at commit instead -- the connection cost and the
## local opposition -- so U6c's rule that a lon/lat nothing reads carries no
## information is satisfied without a fourth partition to keep zero-mean.
## tests/test_energy.gd reads this file and fails if it ever preloads regions.gd.
##
## TAKES access AND weights AS PLAIN DICTIONARIES, network.gd's and siting.gd's
## rule: this file never learns that a graph or a region register exists. It takes
## the LOADER, as projects.gd does, because the source catalogue is content and a
## register entry names a source by id.

const K = preload("res://src/sim/energy_constants.gd")
const Siting = preload("res://src/sim/siting.gd")
const LK = preload("res://src/sim/legislature_constants.gd")


## The nation's electricity consumption in TWh a year: the measured per-capita
## figure against the LIVE population.
##
## LIVE rather than measured on both sides, and that costs no bit-identity: with an
## empty register the denominator cancels out of mix() entirely. What it buys is
## that a plant's share of a growing country shrinks on its own, which is correct
## and which no constant had to express.
static func national_twh(ns) -> float:
	return ns.energy_kwh_per_capita * ns.population / 1.0e9


## branch -> TWh a year of DONE plants. A plant under construction generates
## nothing, which is why `done` is on the register entry rather than inferred from
## months_left -- projects.gd's own split, and the half that earned its bump there.
static func built_twh(ns, loader) -> Dictionary:
	var out: Dictionary = {}
	for branch in K.BRANCHES:
		out[branch] = 0.0
	var ids: Array = ns.plants.keys()
	ids.sort()
	for plant_id in ids:
		var entry: Dictionary = ns.plants[plant_id]
		if not bool(entry.get("done", false)):
			continue
		var source = loader.energy_sources.get(String(entry.get("source_id", "")))
		if source == null:
			continue
		out[source.branch] = float(out[source.branch]) + source.output_twh
	return out


## branch -> share of generation, summing to EXACTLY 1.0 by construction.
##
## Exact because the denominator is the sum of the same numerators: there is no
## reconciliation term and nothing to normalise twice. V1.4a's partition, one
## quantity over.
static func mix(ns, loader) -> Dictionary:
	var base: float = national_twh(ns)
	var built: Dictionary = built_twh(ns, loader)
	var extra: float = 0.0
	for branch in K.BRANCHES:
		extra += float(built[branch])
	var total: float = base + extra
	var out: Dictionary = {}
	if total <= 0.0:
		# A nation with no measured consumption and nothing built. The content
		# validator refuses this at load, so reaching it means a fixture -- return
		# the authored shares rather than inventing a mix.
		for branch in K.BRANCHES:
			out[branch] = float(ns.start_energy_mix.get(branch, 0.0))
		return out
	for branch in K.BRANCHES:
		out[branch] = (float(ns.start_energy_mix.get(branch, 0.0)) * base + float(built[branch])) / total
	return out


## The share of the nation's energy it must buy abroad, in points.
##
## The measured baseline plus what the mix has moved since, weighted by each
## source's own import intensity. NOT CLAMPED ABOVE AT 100: Luxembourg's measured
## figure is 109.6 because it re-exports, and a clamp there is a number no dataset
## produced.
static func import_dependency_pct(ns, loader) -> float:
	return ns.start_import_dependency_pct + dependency_deviation_pct(ns, loader)


## How far the mix has moved the dependency against the nation's OWN start.
##
## EXACTLY 0.0 with an empty register, and that is the property the whole re-run
## prediction rests on: mix() returns start_energy_mix term by term, so every
## difference below is exactly 0.0 and their sum is exactly 0.0 -- not nearly.
static func dependency_deviation_pct(ns, loader) -> float:
	var live: Dictionary = mix(ns, loader)
	var intensity: Dictionary = _branch_intensity(loader)
	var moved: float = 0.0
	for branch in K.BRANCHES:
		var delta: float = float(live.get(branch, 0.0)) - float(ns.start_energy_mix.get(branch, 0.0))
		moved += delta * float(intensity.get(branch, 0.0))
	return 100.0 * moved


## branch -> the import intensity of that branch, as the OUTPUT-WEIGHTED mean over
## the sources in it.
##
## Weighted rather than flat because a branch holding a 6 TWh coal station and a
## 5 TWh gas station is not equally described by either; unweighted, adding a
## seventh source would silently retune the branch it joins.
static func _branch_intensity(loader) -> Dictionary:
	var num: Dictionary = {}
	var den: Dictionary = {}
	for branch in K.BRANCHES:
		num[branch] = 0.0
		den[branch] = 0.0
	var ids: Array = loader.energy_sources.keys()
	ids.sort()
	for source_id in ids:
		var source = loader.energy_sources[source_id]
		num[source.branch] = float(num[source.branch]) + source.output_twh * source.import_intensity
		den[source.branch] = float(den[source.branch]) + source.output_twh
	var out: Dictionary = {}
	for branch in K.BRANCHES:
		out[branch] = 0.0 if float(den[branch]) <= 0.0 else float(num[branch]) / float(den[branch])
	return out


## branch -> tonnes CO2e per TWh, output-weighted over the branch's sources --
## _branch_intensity()'s exact idiom over the emission key, so a branch holding a
## 6 TWh coal station and a 5 TWh gas one is described by neither alone.
static func emission_branch_intensity(loader) -> Dictionary:
	var num: Dictionary = {}
	var den: Dictionary = {}
	for branch in K.BRANCHES:
		num[branch] = 0.0
		den[branch] = 0.0
	var ids: Array = loader.energy_sources.keys()
	ids.sort()
	for source_id in ids:
		var source = loader.energy_sources[source_id]
		num[source.branch] = float(num[source.branch]) + source.output_twh * source.emission_t_per_twh
		den[source.branch] = float(den[source.branch]) + source.output_twh
	var out: Dictionary = {}
	for branch in K.BRANCHES:
		out[branch] = 0.0 if float(den[branch]) <= 0.0 else float(num[branch]) / float(den[branch])
	return out


## How far the fleet has moved national emissions against the nation's OWN start,
## in tonnes CO2e a year. Share-based, like dependency_deviation_pct: the baseline
## is the nation's measured TOTAL and the fleet is the lever that moves it, so a
## renewable TWh displaces the fossil share it erodes -- EXACTLY 0.0 at an empty
## register, dependency_deviation_pct()'s own property.
static func emissions_deviation_tonnes(ns, loader) -> float:
	var live: Dictionary = mix(ns, loader)
	var intensity: Dictionary = emission_branch_intensity(loader)
	var twh: float = national_twh(ns)
	var moved: float = 0.0
	for branch in K.BRANCHES:
		var delta: float = float(live.get(branch, 0.0)) - float(ns.start_energy_mix.get(branch, 0.0))
		moved += delta * float(intensity.get(branch, 0.0)) * twh
	return moved


## Total national emissions in tonnes CO2e a year: the measured baseline against
## the LIVE population, plus the fleet's deviation. The accord's rule constrains
## the PER-CAPITA form; this is its numerator.
static func emissions_tonnes(ns, loader) -> float:
	return ns.start_co2e_per_capita_t * ns.population + emissions_deviation_tonnes(ns, loader)


## The constrained field. Baseline per-capita against the live population, so a
## growing country drifts up on its own -- correct, and no constant expresses it.
static func co2e_per_capita_t(ns, loader) -> float:
	if ns.population <= 0.0:
		return ns.start_co2e_per_capita_t
	return emissions_tonnes(ns, loader) / ns.population


## What building here costs, as a multiplier on the authored build cost.
##
## EXACTLY 1.0 AT THE MEAN ACCESSIBILITY, because network.gd's index is normalised
## to an output-weighted mean of one and this is that index to a negative power.
## A structural zero rather than a clamp -- and the reason this file ships no
## "connection cost floor" the way V1.7a ships no turnout clamp.
static func connection_multiplier(access: Dictionary, region_id: String) -> float:
	if K.ACCESS_ELASTICITY == 0.0:
		return 1.0
	return pow(maxf(float(access.get(region_id, 1.0)), K.ACCESS_MIN), -K.ACCESS_ELASTICITY)


## Points of bloc_offset a siting costs, before the action's own authored offset.
##
## Siting.concentration() IS THE WEIGHT, and V2.8 is its first pricer: V2.6b1
## built that function, measured it, designed a monthly price on it and found the
## interval EMPTY. This one charges ONCE, at commit, which is why an interval that
## was empty for a standing charge can be non-empty for a decision.
static func opposition_points(concentration: float, opposition: float) -> float:
	return K.OPPOSITION_SCALE * opposition * concentration


## What a nation is billed this month: every building plant's build cost times what
## its region charges to connect, plus every finished plant's run cost.
##
## THE CONNECTION MULTIPLIER RIDES THE BUILD AND NOT THE RUN, and that is the model:
## connecting a station to the grid is a capital job done once, where running it is
## the same job everywhere. Stored on the entry at commit rather than recomputed, so
## a region whose accessibility drifts later cannot retroactively re-price a
## contract the player already signed -- Projects.sited_map()'s opposite call, and
## the difference is that a payoff is a fact about now and a price is a fact about
## the day it was agreed.
static func bill_pct_gdp(ns, loader) -> float:
	var bill: float = 0.0
	var ids: Array = ns.plants.keys()
	ids.sort()
	for plant_id in ids:
		var entry: Dictionary = ns.plants[plant_id]
		var source = loader.energy_sources.get(String(entry.get("source_id", "")))
		if source == null:
			continue
		if bool(entry.get("done", false)):
			bill += source.run_cost_pct_gdp
		else:
			bill += source.build_cost_pct_gdp * float(entry.get("connection", 1.0))
	return bill


## Advance every build and rewrite the four derived readings.
##
## `access_by_nation` is nation id -> the accessibility index, built by the caller,
## because this file never learns that a graph exists. It is REQUIRED and NOT
## DEFAULTED, for Regions.trend_deviation_pct()'s reason: a defaulted {} would read
## as "no network" and every harness that forgot to pass one would silently run a
## different model and agree with itself about a re-run that measured nothing.
static func tick_month(state, loader, access_by_nation: Dictionary) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for nation_id in ids:
		var ns = state.nations[nation_id]
		var plant_ids: Array = ns.plants.keys()
		plant_ids.sort()
		for plant_id in plant_ids:
			var entry: Dictionary = ns.plants[plant_id]
			if bool(entry.get("done", false)):
				continue
			var left: int = int(entry.get("months_left", 0)) - 1
			entry["months_left"] = maxi(left, 0)
			if left <= 0:
				entry["done"] = true
			ns.plants[plant_id] = entry
		ns.energy_bill_pct_gdp = bill_pct_gdp(ns, loader)
		ns.import_dependency_pct = import_dependency_pct(ns, loader)
		ns.energy_impulse_pct = growth_impulse_pct(ns, loader)
		ns.co2e_per_capita_t = co2e_per_capita_t(ns, loader)


## The one channel energy has into the economy, in points of annual growth.
##
## NEGATIVE IN A RISING DEPENDENCY and exactly 0.0 at the nation's own start, so a
## country that never builds is charged nothing and a country that builds fossil
## capacity pays. Clamped by IMPULSE_MAX_PCT, which is a BOUND rather than a
## selector -- nothing chooses it, it only refuses an absurdity, V1.5a's rule.
##
## IT IS A GROWTH ADDEND AND NOT A TREND SHIFT, deliberately: energy prices reach
## employment, and V1.6e established that a trend-side lever has no permanent
## employment channel available to it at all. A dependency that could not move
## unemployment would be a fact about the budget wearing an economy's clothes.
static func growth_impulse_pct(ns, loader) -> float:
	if K.DEP_BETA == 0.0:
		return 0.0
	var raw: float = -K.DEP_BETA * dependency_deviation_pct(ns, loader)
	return clampf(raw, -K.IMPULSE_MAX_PCT, K.IMPULSE_MAX_PCT)


static func plants_in_region(ns, region_id: String) -> Array:
	var out: Array = []
	var ids: Array = ns.plants.keys()
	ids.sort()
	for plant_id in ids:
		if String(ns.plants[plant_id].get("region_id", "")) == region_id:
			out.append(plant_id)
	return out


static func plant_count(ns) -> int:
	return ns.plants.size()


static func available(state, ns, all_actions: Array) -> Array:
	var out: Array = []
	for action in all_actions:
		if _preconditions_met(state, ns, action):
			out.append(action)
	return out


static func _preconditions_met(state, ns, action) -> bool:
	for row in action.preconditions:
		var field: String = String(row["field"])
		var value: float = _read_field(state, ns, field)
		match String(row["op"]):
			"<=":
				if value > float(row["value"]):
					return false
			">=":
				if value < float(row["value"]):
					return false
			"<":
				if value >= float(row["value"]):
					return false
			">":
				if value <= float(row["value"]):
					return false
			"==":
				if value != float(row["value"]):
					return false
	return true


## The whitelist and this match are the SAME LIST IN TWO PLACES, which the suite
## caught V1.5c adding to only one of. tests/test_energy.gd walks
## K.PRECONDITION_FIELDS and fails on any key this function does not answer.
static func _read_field(state, ns, field: String) -> float:
	match field:
		"deficit_pct_gdp":
			return ns.deficit_pct_gdp
		"debt_to_gdp_pct":
			return 0.0 if ns.gdp_eur_bn <= 0.0 else 100.0 * ns.debt_eur_bn / ns.gdp_eur_bn
		"import_dependency_pct":
			return ns.import_dependency_pct
		"plant_count":
			return float(plant_count(ns))
		"overall_approval_pct":
			return ns.overall_approval_pct
	return 0.0


## Order a plant into a region the PLAYER names, or close one it names.
##
## `site`, `region_id` and `plant_id` are arguments rather than content, V2.6b2's
## rule: the campaign meeting's region is the PLAYER's and never Siting.site()'s, and
## that is the one proof the two sited halves were never one shape. `access` and
## `pop_weights` are plain Dictionaries the caller builds, network.gd's rule.
##
## `site` IS A Vector2 OF (lon, lat), matching data/nations/'s own project_sites
## shape so the two coordinates in this game are the same type. The caller has
## already resolved it to `region_id` through Region.region_at_lonlat() -- this
## function does no geometry, which is what keeps it callable from a headless test
## with no map anywhere.
static func execute(state, ns, loader, all_actions: Array, action, site: Vector2,
		region_id: String, plant_id: String, access: Dictionary,
		pop_weights: Dictionary) -> Dictionary:
	var terms: Dictionary = action.effects.get("energy", {})
	var op: String = String(terms.get("op", ""))

	if not available(state, ns, all_actions).has(action):
		var refused := {"action_id": action.id, "applied": false, "refused": true}
		ns.last_energy_result = refused
		return refused

	var opposition: float = 0.0
	var new_id: String = ""

	match op:
		"order":
			var source = loader.energy_sources.get(String(terms.get("source_id", "")))
			if source == null or region_id == "":
				var bad := {"action_id": action.id, "applied": false, "refused": true}
				ns.last_energy_result = bad
				return bad
			ns.plant_seq += 1
			new_id = "%s#%d" % [source.id, ns.plant_seq]
			ns.plants[new_id] = {
				"source_id": source.id,
				"region_id": region_id,
				# The player's own point, stored. src/ui/map_plants.gd draws the glyph
				# here and nowhere else -- a marker placed at the region's centroid
				# would be the game telling the player their click did not matter.
				"lon": site.x,
				"lat": site.y,
				"months_left": source.build_months,
				"done": false,
				# The connection multiplier is FROZEN at commit -- see bill_pct_gdp().
				"connection": connection_multiplier(access, region_id),
			}
			opposition = opposition_points(
				Siting.concentration(pop_weights, region_id), source.opposition)
		"decommission":
			if not ns.plants.has(plant_id):
				var missing := {"action_id": action.id, "applied": false, "refused": true}
				ns.last_energy_result = missing
				return missing
			ns.plants.erase(plant_id)

	for bloc_id in action.effects.get("bloc_offset", {}).keys():
		# CLAMPED, like every other writer of this register (legislature.gd,
		# diplomacy.gd, government.gd, pledges.gd, referendum.gd). Written bare until
		# the V2.8 review, so an offset already at the bound could be pushed past it --
		# and _op_legal()'s own comment reasons about the exploit it fixed in terms of
		# BLOC_OFFSET_MAX, i.e. it assumes a bound this line did not enforce.
		ns.bloc_offset[bloc_id] = clampf(
			float(ns.bloc_offset.get(bloc_id, 0.0))
			+ float(action.effects["bloc_offset"][bloc_id]),
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX
		)

	# THE LOCAL PRICE LANDS ON THE SAME REGISTER AS THE NATIONAL ONE and is charged
	# to the blocs the action already names, scaled by the region's concentration.
	# No new channel, and no second accumulator -- V1.4b's "one verb, two prices"
	# where the second price is about WHERE rather than WHAT.
	if opposition != 0.0:
		for bloc_id in action.effects.get("bloc_offset", {}).keys():
			ns.bloc_offset[bloc_id] = clampf(
				float(ns.bloc_offset.get(bloc_id, 0.0)) - opposition,
				LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX
			)

	# ALL FOUR DERIVED READINGS, not just the bill. Recomputing some and leaving the
	# rest to the next tick was the inconsistent case: import_dependency_pct is
	# a live PRECONDITION field, so in the month a done fossil plant was
	# decommissioned the mix had already changed while the gate still read the
	# pre-decommission dependency -- enough to chain a second action the new mix no
	# longer qualifies for. Same four writes tick_month() makes, in the same order.
	ns.energy_bill_pct_gdp = bill_pct_gdp(ns, loader)
	ns.import_dependency_pct = import_dependency_pct(ns, loader)
	ns.energy_impulse_pct = growth_impulse_pct(ns, loader)
	ns.co2e_per_capita_t = co2e_per_capita_t(ns, loader)
	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"op": op,
		"plant_id": new_id if op == "order" else plant_id,
		"region_id": region_id,
		"opposition_points": opposition,
		"applied": true,
		"refused": false,
	}
	ns.last_energy_result = result
	return result
