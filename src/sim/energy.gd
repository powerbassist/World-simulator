extends RefCounted

## The electricity mix, its import dependency, and the fleet that moves them --
## V2.8. Model: docs/energy-model.md.
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
