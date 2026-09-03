extends SceneTree

## Siting probe: godot --headless --script res://tools/siting_probe.gd
##
## V2.6b1's evidence generator. The tables ARE the model's evidence, and table (b)
## is the one the session exists to produce: whether a sited quantity's place ever
## MOVES, which V2.6b's ROADMAP row asserted and no check in this project could
## previously contradict.
##
## Not a test. tests/test_siting.gd asserts the invariants this probe is used to
## FIND; this prints tables a human reads while deciding. Kept in tools/ and
## excluded from run_tests.sh for that reason.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Companies = preload("res://src/sim/companies.gd")
const Migration = preload("res://src/sim/migration.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Siting = preload("res://src/sim/siting.gd")
const Regions = preload("res://src/sim/regions.gd")
const K = preload("res://src/sim/unrest_constants.gd")
const SitingK = preload("res://src/sim/siting_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")

const START_YEAR := 2026
const RUN_MONTHS := 168
const TERM_MONTHS := 60

## The regime that reaches a grievance worth pricing. docs/unrest-model.md table (b):
## austerity peaks at 53.3 and fires twelve acts over fourteen years.
const AUSTERITY := {
	"spending_pct_gdp": {
		"health": -2.5, "education": -2.0, "defence": -1.0,
		"pensions": -3.5, "infrastructure": -2.0,
	},
	"tax_rates_pct": {"income": 6.0, "corporate": 5.0, "vat": 4.0},
}

## Four grids, coarse to fine. An answer that moves under refinement is a statement
## about the grid rather than a result -- V1.5b's diagnostic.
const BETA_GRIDS := [
	[0.0, 0.5, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0],
	[0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0],
	[0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0, 1.2, 1.5, 2.0, 2.5, 3.0],
	[],
]

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	_table_a_the_site()
	_table_b_does_it_move()
	_table_c_normalisation()
	_table_d_beta_sweep()
	quit(0)


# --- Harness -------------------------------------------------------------------

func _new_state(nation_id: String):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	return state


func _commit(state, delta: Dictionary) -> void:
	var ns = state.player()
	var pending := {}
	var rates := {}
	for key in delta["tax_rates_pct"]:
		rates[key] = clampf(
			float(ns.start_tax_rates_pct.get(key, 0.0)) + float(delta["tax_rates_pct"][key]), 0.0, 100.0
		)
	pending["tax_rates_pct"] = rates
	var lines := {}
	for key in delta["spending_pct_gdp"]:
		lines[key] = maxf(
			float(ns.start_spending_pct_gdp.get(key, 0.0)) + float(delta["spending_pct_gdp"][key]), 0.0
		)
	pending["spending_pct_gdp"] = lines
	Budget.commit(state, pending)


## src/ui/main.gd's order for the systems that reach a site: Companies and Migration
## before Unrest, so the shares the site reads are the month's own settled ones.
func _step(state, months_in: int) -> void:
	state.year = START_YEAR + int(months_in / 12)
	state.month = (months_in % 12) + 1
	Economy.tick_month(state)
	Budget.tick_month(state)
	Inflation.tick_month(state)
	Opinion.tick_month(state)
	Companies.tick_month(state, _loader)
	Migration.tick_month(state, _loader)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, _loader)


func _regions_of(state, nation_id: String) -> Array:
	return state.regions.get(nation_id, [])


func _nation_ids() -> Array:
	var ids: Array = _loader.nations.keys()
	ids.sort()
	return ids


# --- (a) the site, under both forms -------------------------------------------

## THE FORM CHOICE FLIPS THE SIGN OF THE PRICE, so both are printed side by side
## rather than only the one that ships. The level form scores share x unemployment
## and puts the demonstration where the most people are; the deviation form scores
## share x (unemployment above the nation's own mean) and puts it where the excess
## unemployment is. The second is what ships.
func _table_a_the_site() -> void:
	print("""
=== (a) the site at month 1, under both scoring forms ===
  LEVEL = share x unemployment. DEVIATION = share x (unemployment - weighted mean), the shipped form.
  moves? = does the signal choose the place, or would the weights alone have chosen it?""")
	print("  %-4s %-26s %-9s %-26s %-9s %-6s %-7s %-7s" % [
		"nat", "LEVEL site", "margin", "DEVIATION site (shipped)", "margin", "moves?", "conc", "out/hd",
	])
	for id in _nation_ids():
		var state = _new_state(id)
		var ns = state.player()
		var region_list: Array = _regions_of(state, id)
		var weights: Dictionary = Unrest.site_weights(ns, region_list)
		var access: Dictionary = Regions.accessibility_for(ns, region_list, state.region_graph)

		var levels: Dictionary = {}
		for region in region_list:
			levels[region.id] = Regions.unemployment_pct(ns, region_list, region.id, access)
		var level_id: String = Siting.site(weights, levels)
		var dev: Dictionary = Unrest.site_signal(ns, region_list, access)
		var report: Dictionary = Unrest.site_report(ns, region_list, access)

		print("  %-4s %-26s %-9s %-26s %-9s %-6s %-7.3f %-7.3f" % [
			id,
			_name_of(region_list, level_id).substr(0, 26),
			_margin_text(Siting.margin(weights, levels)),
			(_name_of(region_list, String(report["region_id"])).substr(0, 26)
				if String(report["region_id"]) != "" else "(none)"),
			_margin_text(float(report["margin"])),
			str(Siting.signal_moves_site(weights, dev)),
			float(report["concentration"]),
			float(report["output_index"]),
		])
	print("""
  Britain and Luxembourg have NO deviation site, and each for its own reason: every
  British region carries unemployment_rel exactly 1.0 (V2.5 section 8's ITL1 index
  proxy, the construction that gave V2.6a `moved 0.000`), and Luxembourg is one
  region and cannot differ from itself. Both are then unpriced by ARITHMETIC --
  Siting.concentration() reads exactly 1.0 on an empty site -- rather than by a
  branch anywhere, which is what V2.6a's own two bounds did.""")


func _name_of(region_list: Array, region_id: String) -> String:
	for region in region_list:
		if region.id == region_id:
			return String(region.region_name)
	return "(none)"


func _margin_text(m: float) -> String:
	if m == INF:
		return "only one"
	return "%+.1f%%" % (m * 100.0)


# --- (b) does the place ever move? --------------------------------------------

## THE SESSION'S CENTRAL MEASUREMENT, and the one the ROADMAP row could not have
## contained. V2.6b's row says both halves "decide WHERE by reading V2.6a's live
## shares". This runs the real tick for fourteen years and counts how many distinct
## places each nation's demonstration is ever in.
func _table_b_does_it_move() -> void:
	print("""
=== (b) does the site MOVE over %d months? the real tick, austerity ===
  distinct = how many different regions the demonstration was ever sited in.
  A margin far above the migration budget (0.0164 share points, ~9%% relative)
  means the answer is structurally one, whatever the shares do.""" % RUN_MONTHS)
	print("  %-4s %-9s %-26s %-26s %-9s %-9s" % [
		"nat", "distinct", "site @1", "site @168", "margin@1", "margin@168",
	])
	for id in ["FRA", "DEU", "GBR"]:
		var state = _new_state(id)
		_commit(state, AUSTERITY)
		var region_list: Array = _regions_of(state, id)
		var seen := {}
		var first := ""
		var last := ""
		var margin_first := 0.0
		var margin_last := 0.0
		for i in range(RUN_MONTHS):
			_step(state, i)
			var report: Dictionary = Unrest.site_report(state.player(), region_list,
				Regions.accessibility_for(state.player(), region_list, state.region_graph))
			var site_id := String(report["region_id"])
			seen[site_id] = true
			if i == 0:
				first = site_id
				margin_first = float(report["margin"])
			last = site_id
			margin_last = float(report["margin"])
		var names: Array = []
		var seen_ids: Array = seen.keys()
		seen_ids.sort()
		for sid in seen_ids:
			names.append(_name_of(region_list, String(sid)) if String(sid) != "" else "(none)")
		print("  %-4s %-9d %-26s %-26s %-9s %-9s" % [
			id, seen.size(),
			(_name_of(region_list, first).substr(0, 26) if first != "" else "(none)"),
			(_name_of(region_list, last).substr(0, 26) if last != "" else "(none)"),
			_margin_text(margin_first), _margin_text(margin_last),
		])
		print("       every site seen: %s" % [", ".join(PackedStringArray(names))])


# --- (c) the output multiplier is mean-one ------------------------------------

## The anti-rescale check. A multiplier whose share-weighted mean is not exactly one
## is a silent retune of UNREST_IMPULSE_SCALE, which V1.5c measured with a band.
func _table_c_normalisation() -> void:
	print("""
=== (c) is the output multiplier mean-one? share-weighted mean over the named regions ===
  Must be 1.0 to 1e-12, or the factor is silently rescaling UNREST_IMPULSE_SCALE.""")
	var worst := 0.0
	for id in _nation_ids():
		var state = _new_state(id)
		var ns = state.player()
		var region_list: Array = _regions_of(state, id)
		if region_list.is_empty():
			continue
		var weights: Dictionary = Unrest.site_weights(ns, region_list)
		var raw := {}
		for region in region_list:
			raw[region.id] = Regions.gdp_per_head_index(
				ns, region_list, region.id, Migration.region_share(ns, region.id)
			)
		var indexed: Dictionary = Siting.normalised(raw, weights)
		var weighted := 0.0
		var total := 0.0
		for rid in indexed:
			weighted += float(weights[rid]) * float(indexed[rid])
			total += float(weights[rid])
		var mean: float = weighted / total
		worst = maxf(worst, absf(mean - 1.0))
		# GDScript's format has no %e, so the error is printed scaled: a figure of
		# 1.0 here is 1e-15, and the 1e-12 tolerance is 1000.0 in this column.
		print("  %-4s mean %.17f   error x1e-15 %.4f" % [id, mean, absf(mean - 1.0) * 1.0e15])
	print("  worst error anywhere: %.4f x1e-15  (tolerance 1000.0 x1e-15 = 1e-12)" % (worst * 1.0e15))


# --- (d) SITE_VISIBILITY_BETA -------------------------------------------------

## Emulated rather than rescaled. The shipped beta is 0.0, so the load written by the
## tick IS the unsited base, and a candidate's load is base * pow(c, beta) EXACTLY --
## no division by a shipped constant, so V1.6b's "the range was choosing the
## constant" cannot arise here.
##
## Both clauses are read on the SAME observable and in the same unit: points of the
## worst bloc approval row, which src/ui/polling_panel.gd prints as "%.0f%%", so one
## digit of the panel is 1.0 point.
func _table_d_beta_sweep() -> void:
	var law_worth: float = _settlement_worth()
	print("""
=== (d) THE KILL SWITCH THAT FIRED: the visibility price, FRA, austerity, %d months ===
  This table is the EVIDENCE FOR A DELETION, not for a constant. SITE_VISIBILITY_BETA
  was designed, its band was fixed before the sweep, the interval came back EMPTY on
  every grid, and src/sim/siting_constants.gd was deleted rather than shipped at an
  unused 0.0 -- V1.3e's treatment of AGREEMENT_ACCEPT_MIN. The sweep is kept because
  a deletion with no table behind it is an assertion, and because the two clauses are
  INCONSISTENT rather than badly tuned: the scale line below is what says so.

  (i)  READABLE: the sited worst-bloc row must differ from the unsited one by
       >= 1.0 point -- one digit of polling_panel.gd's own "%%.0f%%%%".
  (ii) SITING MUST NOT OUTWEIGH GOVERNING: that difference must stay below what one
       settlement law is worth on the same row, measured at %.3f points.
  France's site is a DISCOUNT (concentration 0.897), so the sited row comes back
  ABOVE the unsited one and the clause is read on the absolute difference.""" % [
		TERM_MONTHS, law_worth,
	])
	var base_row: float = _run_beta(0.0)
	# The SCALE the two clauses are read against: what the whole unrest opinion price
	# is worth on this row. If siting has to be worth a large fraction of it to be
	# readable, then the clause asking siting to be smaller than governing and the
	# clause asking it to be visible are asking for opposite things -- which is a
	# fact about the model rather than about the grid, and the reason it is measured
	# here rather than inferred from the sweep.
	var no_load_row: float = _run_zero_load()
	print("  unsited worst-bloc row:            %.4f" % base_row)
	print("  the SAME row with no unrest price: %.4f  (the whole price is worth %.4f)" % [
		no_load_row, absf(no_load_row - base_row),
	])
	print("  one settlement law on the same row: %.4f" % law_worth)
	print("  %-8s %-12s %-12s %-8s" % ["beta", "worst row", "|diff|", "band"])

	var grids: Array = BETA_GRIDS.duplicate()
	for gi in range(grids.size()):
		var grid: Array = grids[gi]
		if grid.is_empty():
			continue
		print("  -- grid %d --" % (gi + 1))
		var passing: Array = []
		for beta in grid:
			var row: float = _run_beta(float(beta))
			var diff: float = absf(row - base_row)
			var ok: bool = diff >= 1.0 and diff < law_worth
			if ok:
				passing.append(float(beta))
			print("  %-8.3f %-12.4f %-12.4f %-8s" % [
				beta, row, diff, ("PASS" if ok else ("fail (i)" if diff < 1.0 else "fail (ii)")),
			])
		if passing.is_empty():
			print("  grid %d: NO PASSING CANDIDATE" % (gi + 1))
		else:
			passing.sort()
			print("  grid %d: passing [%.3f, %.3f], midpoint %.3f" % [
				gi + 1, passing[0], passing[passing.size() - 1],
				(passing[0] + passing[passing.size() - 1]) / 2.0,
			])


## One austerity run with the load emulated at `beta`, returning the worst bloc
## approval row at the end. The emulated load is written back onto NationState after
## each step, so the feedback the real model has -- load -> approval -> satisfaction
## -> hardship -> next month's grievance -- is in the measurement rather than
## approximated out of it.
func _run_beta(beta: float) -> float:
	var state = _new_state("FRA")
	_commit(state, AUSTERITY)
	var region_list: Array = _regions_of(state, "FRA")
	for i in range(TERM_MONTHS):
		_step(state, i)
		var ns = state.player()
		var report: Dictionary = Unrest.site_report(ns, region_list,
			Regions.accessibility_for(ns, region_list, state.region_graph))
		var c: float = float(report["concentration"])
		if c > 0.0:
			# The shipped beta is 0.0, so what the tick wrote is the unsited base.
			ns.unrest_opinion_load = float(ns.unrest_opinion_load) * pow(c, beta)
	return _worst_row(state.player())


## What one settlement law is worth on the same observable -- clause (ii)'s ruler,
## measured rather than borrowed. docs/unrest-model.md section 10 (e) measures it in
## grievance points; this re-measures it in the unit clause (i) uses, because a band
## whose two clauses are in different units cannot be read against each other.
func _settlement_worth() -> float:
	var plain: float = _run_with_stance(0.0)
	var settled: float = _run_with_stance(1.0)
	return absf(settled - plain)


## The same austerity run with the unrest opinion price suppressed entirely -- the
## scale both clauses are read against.
func _run_zero_load() -> float:
	var state = _new_state("FRA")
	_commit(state, AUSTERITY)
	for i in range(TERM_MONTHS):
		_step(state, i)
		state.player().unrest_opinion_load = 0.0
	return _worst_row(state.player())


func _run_with_stance(stance: float) -> float:
	var state = _new_state("FRA")
	_commit(state, AUSTERITY)
	for i in range(TERM_MONTHS):
		_step(state, i)
		state.player().settlement_stance = stance
	return _worst_row(state.player())


func _worst_row(ns) -> float:
	var worst := 999.0
	for bloc in OK.BLOC_KEYS:
		worst = minf(worst, float(ns.bloc_approval.get(bloc, 0.0)))
	return worst
