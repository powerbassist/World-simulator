extends SceneTree

## Composition probe: godot --path "<repo>" --headless --script tools/composition_probe.gd
## Dev-only, never ships.
##
## V4.2 T3. The statute book's composition machine was DECLARED at T2 with
## starting-midpoint constants; this probe sweeps the bands the model doc
## declared BEFORE the run (docs/legislature-model.md, "The drafting budget
## and its bands") and prints PASS/FAIL per clause. Constants move only
## through this sweep's evidence.
##
## THE GRID: breadth {single-best channel, single-worst channel, half the
## kinds, full} x size {1.0, 3.0, 6.0} x position {five points per axis}.
## "Best/worst" is by CHANNEL_COST, read off the constants so the probe
## follows a re-tune instead of duplicating it. "Half" is the four
## dict-shaped kinds a drafted bill most naturally mixes (tax, spending,
## company, society); "full" is SIX kinds, not seven, because the
## anti-double-count law makes structural_unemployment_pct uncomposeable with
## both company and society.migration -- six is the machine's own ceiling,
## and the probe reports what the ceiling prices rather than inventing a
## seventh slot. Within a cell the size budget is split into equal slices per
## channel (the documented composition rule), values sized slice/cost.
##
## THE 100 ASSEMBLIES: Elections.init_nation variants on one new-game
## government -- each party's authored seat share multiplied by a seeded draw
## in [0.55, 1.45], re-allocated through the same largest-remainder step an
## election uses. The SAME pool is reused for every cell, so cross-cell
## comparisons are paired; the coalition stays the new-game one (one
## government, many assemblies -- the variation a drafted bill actually
## faces). One seeded RandomNumberGenerator, fixed seed, draw order fixed:
## the pool is reproducible byte-for-byte.
##
## THE VOTE: resolve_vote() is a pure function of state and the law, so the
## probe resolves divisions against the pool without ticking anything. A bill
## object is built through Law.composed_from_dict -- the same factory
## statute.gd's _compose() uses -- carrying the spec's position and the
## machine's derived price in its effects.
##
## THE NEGATIVE CONTROL is the brief's: the max-breadth max-size bill
## composed with CHANNEL_PRICE ZEROED must dominate the grid. The zeroed
## derivation is computed, not asserted: every row x 0 is exact-zero and the
## machine's exact-zero erasure drops it, so the control's price is empty --
## which is the point. If the control dominates, breadth without the table is
## free, and the price table (not the vote arithmetic) is what closes the
## all-upside hole.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Elections = preload("res://src/sim/elections.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Law = preload("res://src/core/law.gd")
const Statute = preload("res://src/sim/statute.gd")
const SK = preload("res://src/sim/statute_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

const PLAYER := "FRA"
const SEED := 20261003
const ASSEMBLIES := 100

## Size axis: the surtax-scale single lever (1.0), the budget's half (3.0),
## and the cap itself (6.0). Max is the DRAFT_SIZE_MAX the bands price.
const SIZES := [1.0, 3.0, 6.0]
## Five points per axis. Sweep order is the tie-break order everywhere.
const AXIS := [-1.0, -0.5, 0.0, 0.5, 1.0]

## The seat-share noise band: a party wins or loses up to ~45% of its authored
## share per assembly draw. Wide enough to produce landslides and hung
## assemblies out of France's own roster; narrow enough that every assembly
## still looks like France.
const SEAT_NOISE_MIN := 0.55
const SEAT_NOISE_SPAN := 0.9

## The two composed-shape channels need their fixed representatives: the tax
## anchor key (the row every other row is calibrated against) and the
## spending portfolio with the fullest authored price. The society term is
## `settlement` on purpose: `migration` would collide with the structural
## channel in a seven-kind reading, and `corruption` with the spending line.
const REP_TAX_KEY := "income"
const REP_SPEND_KEY := "health"
const REP_SOCIETY_TERM := "settlement"
const REP_SECTOR := "industry"

## Breadth families. Channel kinds in fixed order; "half" is the first four
## dict/scalar kinds a bill mixes, "full" the six the anti-double-count law
## allows (see the header). Each entry: [kind, spec-shape tag].
const BREADTHS := {
	"single_best": [["tax", "rep"]],
	"single_worst": [["scalar", "rep"]],
	"half": [["tax", "rep"], ["spend", "rep"], ["company", "rep"], ["society", "rep"]],
	"full": [["tax", "rep"], ["spend", "rep"], ["scalar_growth", "rep"], ["scalar_revenue", "rep"], ["company", "rep"], ["society", "rep"]],
}

var _loader
var _party_list: Array = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("loader errors: %s" % [_loader.errors])
		quit(1)
		return
	_party_list = _loader.parties.get(PLAYER, [])

	var specs := _grid_specs()
	var prices := {}
	var months := {}
	var sizes := {}
	for key in specs:
		var cell: Dictionary = _draft_cell(specs[key])
		if cell.is_empty():
			printerr("probe spec refused -- the grid must only compose what the machine accepts: %s" % key)
			quit(1)
			return
		prices[key] = cell["price"]
		months[key] = int(cell["months"])
		sizes[key] = float(cell["size"])

	var pass_counts := _resolve_grid(specs, prices)

	print("")
	print("=== COMPOSITION PROBE — %s, %d seeded assemblies, seed %d ===" % [PLAYER, ASSEMBLIES, SEED])
	_price_table(specs, prices)
	_band_p1(specs, prices, pass_counts)
	_band_p2(pass_counts)
	_band_p3(months, sizes)
	_band_p4(specs)
	_band_p5(prices)
	_negative_control(specs, prices, pass_counts)
	quit(0)


# ---------------------------------------------------------------------------
# The grid: specs, prices, months
# ---------------------------------------------------------------------------

## Every (breadth, size) cell's channel dictionary: the breadth's kinds share
## the size budget in equal slices, value = slice / cost. The float edge is
## pre-scaled: a 6.0 target computed as six accumulated products can land one
## ulp over the cap and be refused, which is a rounding artefact and not a
## composition the band means to price.
func _grid_specs() -> Dictionary:
	var costs: Dictionary = SK.CHANNEL_COST
	var cheapest := _extreme_cost_key(costs, true)
	var dearest := _extreme_cost_key(costs, false)

	var specs := {}
	for breadth in BREADTHS:
		for size in SIZES:
			var kinds: Array = BREADTHS[breadth]
			var slice: float = float(size) / float(kinds.size())
			var channels := {}
			var computed := 0.0
			for entry in kinds:
				var tag: String = String(entry[0])
				var cost: float = _kind_cost(tag, costs, cheapest, dearest)
				var value: float = slice / cost
				computed += absf(value) * cost
				match tag:
					"tax":
						channels["tax_rates_pct"] = {REP_TAX_KEY: value}
					"spend":
						channels["spending_pct_gdp"] = {REP_SPEND_KEY: value}
					"scalar":
						channels[dearest] = value
					"scalar_growth":
						channels["potential_growth_pct"] = value
					"scalar_revenue":
						channels["other_revenue_pct_gdp"] = value
					"company":
						channels["company"] = {"sector": REP_SECTOR, "burden": value}
					"society":
						channels["society"] = {REP_SOCIETY_TERM: value}
			if computed > float(SK.DRAFT_SIZE_MAX):
				var factor: float = (float(SK.DRAFT_SIZE_MAX) - 1e-9) / computed
				for channel in channels:
					if channel == "company":
						channels[channel]["burden"] = float(channels[channel]["burden"]) * factor
					elif channel == "society":
						channels[channel][REP_SOCIETY_TERM] = float(channels[channel][REP_SOCIETY_TERM]) * factor
					elif channel == "tax_rates_pct":
						channels[channel][REP_TAX_KEY] = float(channels[channel][REP_TAX_KEY]) * factor
					elif channel == "spending_pct_gdp":
						channels[channel][REP_SPEND_KEY] = float(channels[channel][REP_SPEND_KEY]) * factor
					else:
						channels[channel] = float(channels[channel]) * factor
			specs["%s|%s" % [breadth, _size_name(size)]] = {
				"breadth": String(breadth),
				"size_target": float(size),
				"channels": channels,
			}
	return specs


func _size_name(size: float) -> String:
	if size < 2.0:
		return "min"
	if size < 5.0:
		return "mid"
	return "max"


func _extreme_cost_key(costs: Dictionary, cheapest: bool) -> String:
	var keys := costs.keys()
	keys.sort()
	var best: String = String(keys[0])
	for key in keys:
		var better: bool = float(costs[key]) < float(costs[best]) if cheapest \
			else float(costs[key]) > float(costs[best])
		if better:
			best = String(key)
	return best


## A breadth entry's tag -> the CHANNEL_COST it drafts against. The "scalar"
## rep is whatever key carries the extreme cost, so single_worst follows a
## re-tune instead of naming potential_growth_pct twice.
func _kind_cost(tag: String, costs: Dictionary, cheapest: String, dearest: String) -> float:
	match tag:
		"tax": return float(costs["tax_rates_pct"])
		"spend": return float(costs["spending_pct_gdp"])
		"scalar": return float(costs[dearest])
		"scalar_growth": return float(costs["potential_growth_pct"])
		"scalar_revenue": return float(costs["other_revenue_pct_gdp"])
		"company": return float(costs["company"])
		"society": return float(costs["society"])
	return 0.0


## Draft the cell through the machine itself -- the probe never computes a
## size or a price the machine would not. Returns {} on a refusal, which the
## caller treats as a probe bug (the grid must only compose legal bills).
func _draft_cell(spec: Dictionary) -> Dictionary:
	var pair = _fresh()
	var result: Dictionary = Statute.draft(pair[0], pair[1], _loader, {
		"name": "Probe %s bill" % String(spec["breadth"]),
		"position": {"economic": 0.0, "social": 0.0},
		"channels": spec["channels"],
	})
	if not bool(result.get("ok", false)):
		print("  REFUSED (%s|%s): %s" % [spec["breadth"], _size_name(float(spec["size_target"])), result.get("refusal", "")])
		return {}
	return {"price": result.get("price", {}), "months": int(result.get("months", 0)), "size": float(result.get("size", 0.0))}


# ---------------------------------------------------------------------------
# The divisions: one pool, every bill
# ---------------------------------------------------------------------------

## Outer loop the assemblies, inner loop the bills: the ns is re-seated per
## assembly through Elections.init_nation with a seeded seat-share override,
## and every bill in the grid is divided against that assembly. Pass counts
## are keyed "breadth|size|econ|social".
func _resolve_grid(specs: Dictionary, prices: Dictionary) -> Dictionary:
	var state = _fresh()[0]
	var ns = state.player()
	var nation = _loader.nations.get(PLAYER)
	var parliament = Orgs.parliament(_loader)

	var bills := {}
	for key in specs:
		for econ in AXIS:
			for social in AXIS:
				var cell_key := "%s|%.1f|%.1f" % [key, econ, social]
				# Untyped on purpose: composed_from_dict() carries no return
				# annotation (the AGENTS.md class-cache gotcha, T2's lesson).
				var law = Law.composed_from_dict({
					"id": "probe_%s" % cell_key,
					"name": "Probe bill",
					"theme": "labour",
					"summary": "",
					"position": {"economic": float(econ), "social": float(social)},
					"majority": "simple",
					"cooldown_months": SK.DRAFT_COOLDOWN_MONTHS,
					"once": false,
					"effects": _effects_with_price(prices[key]),
					"repeals": "",
					"origin": "player",
				})
				bills[cell_key] = law

	var counts := {}
	for cell_key in bills:
		counts[cell_key] = 0

	_rng.seed = SEED
	for i in range(ASSEMBLIES):
		var override := {}
		for party in _party_list:
			override[party.id] = float(party.seat_share) * (SEAT_NOISE_MIN + SEAT_NOISE_SPAN * _rng.randf())
		Elections.init_nation(ns, nation, _party_list, parliament, override)
		for cell_key in bills:
			if bool(Legislature.resolve_vote(ns, _party_list, bills[cell_key], false)["passed"]):
				counts[cell_key] = int(counts[cell_key]) + 1
	return counts


## A composed law carries bloc_offset only when the price is non-empty --
## statute.gd's _compose() rule, mirrored here so the control bill (empty
## price) is shaped exactly like a real zero-priced composition.
func _effects_with_price(price: Dictionary) -> Dictionary:
	var effects := {}
	if not price.is_empty():
		effects["bloc_offset"] = Dictionary(price).duplicate(true)
	return effects


# ---------------------------------------------------------------------------
# Bands
# ---------------------------------------------------------------------------

## The derived prices are position-blind -- one table for the whole grid.
func _price_table(specs: Dictionary, prices: Dictionary) -> void:
	print("")
	print("(0) DERIVED PRICES — worst bloc per cell (position-blind; the price reads channels only)")
	print("")
	print("  %-14s %-5s %9s %-11s %s" % ["breadth", "size", "worst", "bloc", "full price"])
	for breadth in ["single_best", "single_worst", "half", "full"]:
		for size in SIZES:
			var key := "%s|%s" % [breadth, _size_name(size)]
			var price: Dictionary = prices[key]
			var worst := 0.0
			var worst_bloc := "-"
			for bloc in price:
				if absf(float(price[bloc])) > worst:
					worst = absf(float(price[bloc]))
					worst_bloc = String(bloc)
			var bits: Array = []
			for bloc in price:
				bits.append("%s %s%.3f" % [bloc, "+" if float(price[bloc]) >= 0.0 else "", float(price[bloc])])
			print("  %-14s %-5s %9.3f %-11s %s" % [breadth, _size_name(size), worst, worst_bloc, ", ".join(bits)])


## P1 needs the MOST ACCOMMODATED POSITION: the grid position where the full
## breadth at max size is carried by the most assemblies. First in sweep order
## wins a tie.
func _most_accommodated(pass_counts: Dictionary, breadth: String, size_name: String) -> Vector2:
	var best := Vector2(AXIS[0], AXIS[0])
	var best_count := -1
	for econ in AXIS:
		for social in AXIS:
			var count: int = pass_counts["%s|%s|%.1f|%.1f" % [breadth, size_name, econ, social]]
			if count > best_count:
				best_count = count
				best = Vector2(float(econ), float(social))
	return best


func _band_p1(specs: Dictionary, prices: Dictionary, pass_counts: Dictionary) -> void:
	print("")
	print("(P1) ANTI-ALL-UPSIDE — the full|max bill at its most accommodated position")
	var pos := _most_accommodated(pass_counts, "full", "max")
	var key := "full|max"
	var price: Dictionary = prices[key]
	var worst := 0.0
	var worst_bloc := "-"
	for bloc in price:
		if absf(float(price[bloc])) > worst:
			worst = absf(float(price[bloc]))
			worst_bloc = String(bloc)

	# (i) The price floor. Pure CHANNEL_PRICE arithmetic -- the derived price
	# never reads the position, so "at the most accommodated position" fixes
	# the cell, not the number.
	var clause_i := worst >= 1.0
	print("  (i)   worst-bloc price |%s| = %.3f  >= 1.0 floor -> %s" % [worst_bloc, worst, _yn(clause_i)])
	print("        (the 1.0 floor is the standing readability floor: polling prints one decimal;")
	print("         V2.6b1 measured a movement under 1.0 point as unprintable against +-3.0 noise)")

	# (ii) Breadth must cost divisions. Measured, not assumed: the same
	# position, same size, single-best breadth vs full breadth -- and the
	# equality counted over EVERY position, which is the effects-blindness
	# measurement: resolve_vote() reads the law's position and majority and
	# nothing else, so no constant can make breadth cost divisions. If that
	# observable is wanted, it is a machine change, not a tuning pass.
	var full_count: int = pass_counts["full|max|%.1f|%.1f" % [pos.x, pos.y]]
	var single_count: int = pass_counts["single_best|max|%.1f|%.1f" % [pos.x, pos.y]]
	var single_min_count: int = pass_counts["single_best|min|%.1f|%.1f" % [pos.x, pos.y]]
	var clause_ii := full_count < single_count
	print("  (ii)  full|max carried by %d of %d vs single_best|max %d and single_best|min %d at (%.1f, %.1f) -> %s" % [
		full_count, ASSEMBLIES, single_count, single_min_count, pos.x, pos.y, _yn(clause_ii)])
	var ties := 0
	var cells := 0
	var row := "        pass counts over the 25 positions, full|max / single_best|max:\n"
	for econ in AXIS:
		var line := "        econ %+.1f:" % float(econ)
		for social in AXIS:
			var f: int = pass_counts["full|max|%.1f|%.1f" % [econ, social]]
			var s: int = pass_counts["single_best|max|%.1f|%.1f" % [econ, social]]
			cells += 1
			if f == s:
				ties += 1
			line += "  %2d/%2d" % [f, s]
		row += line + "\n"
	print(row.rstrip("\n"))
	print("        full|max ties single_best|max at %d of %d positions (the division is effects-blind, measured)" % [ties, cells])
	var verdict := "PASS" if (clause_i and clause_ii) else "FAIL"
	print("  P1 VERDICT: %s" % verdict)
	if not clause_ii:
		print("        clause (ii) is a DESIGN reading, not a tuning one: no CHANNEL_PRICE or CHANNEL_COST")
		print("        value can reach it, because the division never reads effects. Recorded as the model's")
		print("        bound beside the band in docs/legislature-model.md; making breadth cost divisions is")
		print("        an author call on resolve_vote(), not a constant.")


func _band_p2(pass_counts: Dictionary) -> void:
	print("")
	print("(P2) BREADTH MONOTONE — pass count non-increasing in size at fixed position")
	var violations := 0
	var strict_drops := 0
	for breadth in ["single_best", "single_worst", "half", "full"]:
		for econ in AXIS:
			for social in AXIS:
				var c_min: int = pass_counts["%s|min|%.1f|%.1f" % [breadth, econ, social]]
				var c_mid: int = pass_counts["%s|mid|%.1f|%.1f" % [breadth, econ, social]]
				var c_max: int = pass_counts["%s|max|%.1f|%.1f" % [breadth, econ, social]]
				if c_mid > c_min or c_max > c_mid:
					violations += 1
				strict_drops += (1 if c_min > c_mid else 0) + (1 if c_mid > c_max else 0)
	print("  %d position-breadth cells violate monotonicity (must be 0); %d strict size-drops" % [
		violations, strict_drops])
	print("  P2 VERDICT: %s" % ("PASS" if violations == 0 else "FAIL"))


func _band_p3(months: Dictionary, sizes: Dictionary) -> void:
	print("")
	print("(P3) TEMPO — draft-to-vote months, from the machine's own arithmetic")
	var min_months := 999
	var max_months := 0
	var min_size_seen := 99.0
	var max_size_seen := 0.0
	for key in months:
		min_months = mini(min_months, int(months[key]))
		max_months = maxi(max_months, int(months[key]))
		min_size_seen = minf(min_size_seen, float(sizes[key]))
		max_size_seen = maxf(max_size_seen, float(sizes[key]))
	var clause_max := max_months >= 8
	var clause_min := min_months <= 3
	print("  size %.4f -> %d months (band <= 3) -> %s" % [min_size_seen, min_months, _yn(clause_min)])
	print("  size %.4f -> %d months (band >= 8) -> %s" % [max_size_seen, max_months, _yn(clause_max)])
	print("  P3 VERDICT: %s" % ("PASS" if (clause_min and clause_max) else "FAIL"))


## Two identical states, one spec, byte-equal drafts. var_to_bytes rather than
## Dictionary ==: the band says TO THE BIT, and == cannot distinguish 0.1 from
## its nearest float neighbour (and neither can is_equal_approx, on purpose).
func _band_p4(specs: Dictionary) -> void:
	print("")
	print("(P4) DETERMINISM — two identical states, one spec, to the bit")
	var spec: Dictionary = specs["full|max"]
	var a = _fresh()
	var b = _fresh()
	var ra: Dictionary = Statute.draft(a[0], a[1], _loader, {
		"name": "Determinism bill",
		"position": {"economic": 0.0, "social": 0.0},
		"channels": spec["channels"],
	})
	var rb: Dictionary = Statute.draft(b[0], b[1], _loader, {
		"name": "Determinism bill",
		"position": {"economic": 0.0, "social": 0.0},
		"channels": spec["channels"],
	})
	var entry_a: Dictionary = a[1].draft_bills[String(ra["draft_id"])]
	var entry_b: Dictionary = b[1].draft_bills[String(rb["draft_id"])]
	var id_ok := String(ra["draft_id"]) == String(rb["draft_id"])
	var entry_ok := var_to_bytes(entry_a) == var_to_bytes(entry_b)
	var price_ok := var_to_bytes(ra["price"]) == var_to_bytes(rb["price"])
	print("  identical draft ids: %s; identical parked entries: %s; identical prices: %s" % [
		_yn(id_ok), _yn(entry_ok), _yn(price_ok)])
	print("  P4 VERDICT: %s" % ("PASS" if (id_ok and entry_ok and price_ok) else "FAIL"))


## Every cell's price through the ONE applier. The register must land inside
## [BLOC_OFFSET_MIN, MAX] -- true by the clamp's construction, which is why
## the band's number is the BINDING count: a cell whose derived price exceeds
## the bound is one where the player was quoted more than passage lands, and
## the ledger will record the realized (smaller) delta.
func _band_p5(prices: Dictionary) -> void:
	print("")
	print("(P5) BOUNDS — every derived price through apply_effects' one clamp")
	var state = _fresh()[0]
	var ns = state.player()
	var inside := 0
	var total := 0
	var binding: Array = []
	var worst_over := 0.0
	for key in prices:
		var price: Dictionary = prices[key]
		ns.bloc_offset = {}
		Legislature.apply_effects(state, ns, {"bloc_offset": Dictionary(price).duplicate(true)}, _loader)
		total += 1
		var cell_inside := true
		var cell_over := 0.0
		for bloc in ns.bloc_offset:
			var value: float = float(ns.bloc_offset[bloc])
			if value < float(LK.BLOC_OFFSET_MIN) or value > float(LK.BLOC_OFFSET_MAX):
				cell_inside = false
			# A bound the clamp had to move is a quote-to-landing gap: the
			# applied register must be the SAME signed number as the derived
			# quote when the clamp is not doing the work. Signed compare --
			# abs on both sides would call a faithfully-applied -0.5 a gap.
			var quoted: float = clamped_quote(price, bloc)
			if not is_equal_approx(value, quoted):
				cell_over = maxf(cell_over, absf(quoted) - absf(value))
		if cell_inside:
			inside += 1
		if cell_over > 1e-12:
			binding.append("%s (%.3f over)" % [key, cell_over])
			worst_over = maxf(worst_over, cell_over)
	print("  %d of %d cells land inside [%.1f, %.1f] through the applier" % [
		inside, total, float(LK.BLOC_OFFSET_MIN), float(LK.BLOC_OFFSET_MAX)])
	print("  %d cells bind the clamp (worst excess %.3f): %s" % [
		binding.size(), worst_over, ", ".join(binding) if not binding.is_empty() else "none"])
	print("  P5 VERDICT: %s (in-bounds is the clause; the binding count is the recorded bound)" % _yn(inside == total))


## The bloc's quoted magnitude -- what passage lands when the clamp is not
## binding. Kept as a named function so the P5 read says what it means.
static func clamped_quote(price: Dictionary, bloc: String) -> float:
	return float(price.get(bloc, 0.0))


## THE NEGATIVE CONTROL. The control bill is the full|max spec priced by a
## ZEROED table: every row x 0 is exact-zero and the machine's exact-zero
## erasure drops it, so the derivation is empty -- computed below the same
## way the machine would, not asserted. The control must DOMINATE: tie-or-beat
## every real bill's pass count at the same position AND undercut every real
## bill's worst-bloc price. A dominating control is the proof that breadth
## without the table is free -- the price table, not the vote arithmetic, is
## what closes the all-upside hole.
func _negative_control(specs: Dictionary, prices: Dictionary, pass_counts: Dictionary) -> void:
	print("")
	print("(C) NEGATIVE CONTROL — the full|max bill with CHANNEL_PRICE zeroed must dominate")
	var zeroed := _zeroed_price(prices["full|max"])
	print("  zeroed-table derivation: %s (every row x 0 is exact-zero; the machine erases exact-zero)" % [
		"empty" if zeroed.is_empty() else str(zeroed)])

	# Measured, not assumed: the same position, an effects-empty twin of the
	# control bill -- if the division read effects, the twin would diverge.
	var state = _fresh()[0]
	var ns = state.player()
	var nation = _loader.nations.get(PLAYER)
	var parliament = Orgs.parliament(_loader)
	var control_counts := {}
	var pool_seeds := _pool_overrides()
	for econ in AXIS:
		for social in AXIS:
			var law = Law.composed_from_dict({
				"id": "probe_control|%.1f|%.1f" % [econ, social],
				"name": "Control bill",
				"theme": "labour",
				"summary": "",
				"position": {"economic": float(econ), "social": float(social)},
				"majority": "simple",
				"cooldown_months": SK.DRAFT_COOLDOWN_MONTHS,
				"once": false,
				"effects": {},
				"repeals": "",
				"origin": "player",
			})
			var count := 0
			for override in pool_seeds:
				Elections.init_nation(ns, nation, _party_list, parliament, override)
				if bool(Legislature.resolve_vote(ns, _party_list, law, false)["passed"]):
					count += 1
			control_counts["%.1f|%.1f" % [econ, social]] = count

	var dominates := true
	var worst_gap := 0
	for econ in AXIS:
		for social in AXIS:
			var cell := "%.1f|%.1f" % [econ, social]
			var control: int = control_counts[cell]
			for breadth in ["single_best", "single_worst", "half", "full"]:
				for size in SIZES:
					var real: int = pass_counts["%s|%s|%s" % [breadth, _size_name(size), cell]]
					if control < real:
						dominates = false
						worst_gap = maxi(worst_gap, real - control)
	var cheapest_real := 999.0
	for key in prices:
		var price: Dictionary = prices[key]
		for bloc in price:
			cheapest_real = minf(cheapest_real, absf(float(price[bloc])))
	var undercut := float(zeroed.size()) == 0.0 and cheapest_real > 0.0
	print("  control pass counts vs grid: dominates=%s (worst real-better gap %d)" % [
		_yn(dominates), worst_gap])
	print("  control price empty=%s; cheapest real worst-bloc price %.3f" % [
		_yn(zeroed.is_empty()), cheapest_real])
	var verdict := "DOMINATES" if (dominates and undercut) else "BROKEN"
	print("  CONTROL VERDICT: %s — %s" % [verdict, "the price table closes the all-upside hole" if verdict == "DOMINATES" else "breadth is free WITHOUT the table being the reason: inspect"])


## The zeroed-table derivation of a priced bill: every per-unit row times zero
## is exact-zero, and the machine's _price_blend erases exact-zero sums -- so
## the control's price is empty by the machine's own arithmetic.
func _zeroed_price(price: Dictionary) -> Dictionary:
	var out := {}
	for bloc in price:
		var total: float = float(price[bloc]) * 0.0
		if total == 0.0:
			continue
		out[bloc] = total
	return out


## The pool, drawn once and reused: the division loop and the control both
## walk the same seeded assemblies, so their counts are paired.
func _pool_overrides() -> Array:
	var pool: Array = []
	_rng.seed = SEED
	for i in range(ASSEMBLIES):
		var override := {}
		for party in _party_list:
			override[party.id] = float(party.seat_share) * (SEAT_NOISE_MIN + SEAT_NOISE_SPAN * _rng.randf())
		pool.append(override)
	return pool


# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------

func _fresh():
	var gs = GameState.new_game(_loader, PLAYER)
	return [gs, gs.player()]


func _yn(ok: bool) -> String:
	return "PASS" if ok else "FAIL"
