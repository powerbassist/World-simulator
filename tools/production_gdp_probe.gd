extends SceneTree

## V4.6 step-0 probe #1: GDP reproduction from recipes + endowments alone.
## godot --headless --script res://tools/production_gdp_probe.gd
##
## docs/tiers/v4.md §V4.6: "the E0 discipline applies — measure before
## authoring, not after. Can a production economy reproduce the observed GDP
## of twenty-nine nations within a declared band, from authored recipes
## alone, or is the block a recipe-writing exercise that no recipe can
## satisfy? The answer decides the block."
##
## DECLARED BAND, written before any recipe runs:
##   PASS    worst-case |model - observed| / observed <= 0.20 for all 29
##           nations. Twenty percent is the loosest bound that still means
##           "the model has the right shape" — any tighter and we are
##           tuning constants, not testing the shape.
##   FAIL    any nation above 0.20 — the recipe/endowment form cannot
##           reproduce the economy it claims to model.
##
## The model: three sectors (agriculture, industry, services), Leontief
## input recipes, labour + capital endowments, Cobb-Douglas production,
## world prices. GDP = sum of sector value added. The observed GDP from
## data/nations/*.json is the TARGET and never enters the model — no
## scaling to observed, no capital stock read off observed GDP. That was
## the first draft's defect: it reproduced GDP by construction and tested
## nothing. This version fits ONE set of global productivities (TFP per
## sector, shared across all 29 nations — the tier's "one recipe set, not
## 29") by least-squares against all nations at once, then checks each
## nation against the band with the model's own GDP, not the observed one.
##
## Endowments the model may use (the only ones the game has):
##   labour_force  = population * participation_rate (a single global
##                   constant, fitted — the game carries no participation
##                   data, so one number serves all 29)
##   capital_stock = labour_force * capital_per_worker (a single global
##                   constant, fitted — no capital data either)
##   sector labour shares = the nation's measured sector GVA shares, used
##                   to allocate its labour force across sectors (the one
##                   per-nation measured input — this is the register's own
##                   data, legitimate)
##
## The fit has 4 free parameters (TFP for 3 sectors + capital_per_worker)
## against 29 observed GDPs — overdetermined, which is what makes the band
## a real test and not a curve-fit.
##
## Not a test, not registered in run_tests.sh: the committed instrument
## beside its verdict, tick_budget_probe.gd's precedent.

const DataLoader = preload("res://src/core/data_loader.gd")

## Leontief recipes: input coefficient per unit of output (value terms),
## zero-diagonal. Global — one set for all 29 nations, the tier's rule.
const RECIPES := {
	"agriculture": {"industry": 0.15, "services": 0.05},
	"industry": {"agriculture": 0.10, "services": 0.20},
	"services": {"agriculture": 0.02, "industry": 0.12},
}

## World prices, arbitrary units (the probe tests shape, not level).
const PRICES := {
	"agriculture": 1.0,
	"industry": 2.5,
	"services": 3.0,
}

## Labour share of output (Cobb-Douglas alpha), fixed at the standard
## macro value — NOT a free parameter, so the fit can't hide in it.
const LABOUR_SHARE := 0.65

const SECTORS := ["agriculture", "industry", "services"]

var _loader


func _initialize() -> void:
	_loader = DataLoader.new()
	_loader.load_all()

	# Collect the 29 nations' measured inputs.
	var nation_ids: Array = _loader.nations.keys()
	nation_ids.sort()

	# Fit the 4 global parameters by grid search over least-squares error
	# against all 29 observed GDPs at once. Coarse grid — the probe tests
	# the band, not the optimum.
	var best := {"err": 1e18, "tfp": {}, "kpw": 0.0, "part": 0.0}
	var part_grid := [0.40, 0.45, 0.50, 0.55]
	var kpw_grid := [100.0, 300.0, 1000.0, 3000.0]  # capital per worker, EUR thousands
	# TFP grid runs to 1000: the first fit pegged every sector at the 8.0
	# ceiling and undershot every nation ~30x -- a scale verdict, not a
	# shape one. The band tests the shape; the grid must reach the scale.
	var tfp_grid := [1.0, 4.0, 16.0, 64.0, 256.0, 1000.0]

	for part in part_grid:
		for kpw in kpw_grid:
			# fit the three TFPs independently given (part, kpw): each sector's
			# TFP scales its own output, and value added is additive, so the
			# least-squares-optimal TFP vector is found by one pass of
			# coordinate descent over a small grid.
			var tfp := {"agriculture": 2.0, "industry": 2.0, "services": 2.0}
			for round in 3:
				for s in SECTORS:
					var best_tfp: float = tfp[s]
					var best_err := 1e18
					for t in tfp_grid:
						tfp[s] = t
						var err := _total_error(nation_ids, part, kpw, tfp)
						if err < best_err:
							best_err = err
							best_tfp = t
					tfp[s] = best_tfp
			var err := _total_error(nation_ids, part, kpw, tfp)
			if err < best["err"]:
				best = {"err": err, "tfp": tfp.duplicate(), "kpw": kpw, "part": part}

	# Score every nation against the declared band with the fitted globals.
	var worst_ratio := 0.0
	var worst_nation := ""
	var lines: Array = []
	for nation_id in nation_ids:
		var model_gdp := _model_gdp(nation_id, best["part"], best["kpw"], best["tfp"])
		var observed: float = _loader.nations[nation_id].gdp_eur_bn
		var ratio: float = absf(model_gdp - observed) / observed
		lines.append("%s: observed %.1f, model %.1f, ratio %.3f" % [nation_id, observed, model_gdp, ratio])
		if ratio > worst_ratio:
			worst_ratio = ratio
			worst_nation = nation_id

	var verdict := "PASS" if worst_ratio <= 0.20 else "FAIL"

	var f := FileAccess.open("res://reports/production_gdp_probe.txt", FileAccess.WRITE)
	f.store_line("=== V4.6 STEP-0 PROBE #1: GDP REPRODUCTION FROM RECIPES ===")
	f.store_line("band: PASS <= 0.20 worst-case |model - observed| / observed")
	f.store_line("fitted globals: participation %.2f, capital/worker %.0f kEUR, TFP %s" % [best["part"], best["kpw"], str(best["tfp"])])
	f.store_line("")
	for line in lines:
		f.store_line(line)
	f.store_line("")
	f.store_line("worst: %s at %.3f" % [worst_nation, worst_ratio])
	f.store_line("VERDICT: %s" % verdict)
	f.close()

	print("VERDICT: %s | worst %s at %.3f | see reports/production_gdp_probe.txt" % [verdict, worst_nation, worst_ratio])
	quit(0 if verdict == "PASS" else 1)


func _model_gdp(nation_id: String, participation: float, kpw: float, tfp: Dictionary) -> float:
	## The nation's GDP as the model computes it — observed GDP never read.
	var nation = _loader.nations[nation_id]
	var pop: float = nation.population
	var shares: Dictionary = nation.sectors

	var labour_force: float = pop * participation
	var capital_stock: float = labour_force * kpw * 1000.0  # kEUR -> EUR

	# Allocate labour and capital across sectors by the measured GVA shares
	# (normalised — the shares carry rounding and need not sum to 1).
	var total_share := 0.0
	for s in SECTORS:
		total_share += float(shares.get(s, 0.0))
	if total_share <= 0.0:
		return 0.0

	var gdp := 0.0
	var gross_output := {}
	for s in SECTORS:
		var share: float = float(shares.get(s, 0.0)) / total_share
		var labour_s: float = labour_force * share
		var capital_s: float = capital_stock * share
		# Cobb-Douglas: Y = A * L^alpha * K^(1-alpha)
		var output: float = tfp[s] * pow(labour_s, LABOUR_SHARE) * pow(capital_s, 1.0 - LABOUR_SHARE)
		gross_output[s] = output

	# Value added per sector = output * price - intermediate input cost.
	for s in SECTORS:
		var va: float = gross_output[s] * PRICES[s]
		for input_s in RECIPES.get(s, {}):
			va -= RECIPES[s][input_s] * gross_output[input_s] * PRICES[input_s]
		gdp += va

	# Convert EUR-units to EUR billions to sit beside the observed figures.
	return gdp / 1e9


func _total_error(nation_ids: Array, part: float, kpw: float, tfp: Dictionary) -> float:
	## Sum of squared relative errors across all 29 nations — one number the
	## grid search minimises.
	var err := 0.0
	for nation_id in nation_ids:
		var model_gdp := _model_gdp(nation_id, part, kpw, tfp)
		var observed: float = _loader.nations[nation_id].gdp_eur_bn
		var rel: float = (model_gdp - observed) / observed
		err += rel * rel
	return err
