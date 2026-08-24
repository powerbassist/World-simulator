extends SceneTree

## V1.7b's headless sweep. Everything in data/pledges/ and every bound in
## src/sim/pledges_constants.gd is set from a table below rather than guessed and
## defended afterwards.
##
## Run: godot --headless --script res://tools/pledge_probe.gd
##
## *** THE BANDS AND THE TIEBREAKERS ARE BOTH PRE-COMMITTED. *** Ten corrections to
## that discipline are inherited rather than rediscovered:
##
##   V1.4c  fix the TIEBREAKER as well as the band.
##   V1.5a  a tiebreaker must strictly ORDER the survivors; a clause that passes at
##          every candidate is a BOUND, not a selector.
##   V1.5b  its answer must not MOVE when the candidate range is widened. A value
##          sitting at an endpoint of the swept range is a suspect, not a result.
##   V1.5c  a nearest-to-X tiebreaker is only as good as the grid's RESOLUTION.
##   V1.5d  when the model edge is a smooth CROSSING rather than a plateau, neither
##          edge selects and the interior governs.
##   V1.6a  where something outside the model measures the same quantity, prefer a FIT
##          to a band: a band edge moves under widening, a fit converges.
##   V1.6c  check each term against the MODEL'S OWN BOUNDARY before the band.
##   V1.6d  a band that passes at every candidate with the identical measurement is
##          measuring a CLAMP. Say so and replace it.
##   V1.6e  where an edge is closed form, SOLVE IT; the grid is a legibility column.
##   V1.7a  where two model criteria bound a quantity from opposite sides, take the
##          candidate whose WORST RELATIVE SLACK is largest -- the interior of the
##          FEASIBLE REGION, which needs no grid.
##
## ============================================================================
## STEP 0 RUNS BEFORE ANY CONTENT EXISTS, AND IT IS WHAT DECIDES WHETHER THE ROW
## SPLITS
## ============================================================================
## ROADMAP.md's V1.7 decomposition records (b) as the row most likely to split, on
## the TRUST QUANTITY: "if the price cannot land on an existing register the way
## V1.5d landed legitimacy on the grievance, then the ledger and the price are two
## sessions."
##
## The claim under test is that it CAN, and that the register is ns.bloc_offset --
## V1.5d's own criterion applied in the other direction. Legitimacy went to the
## grievance because it is willingness to accept your rule OUTSIDE the ballot box;
## trust in a promise is squarely AT the ballot box, so it lands on the thing that
## reaches the ballot box. Table (a0) measures that before a line of content is
## authored, and if it fails, the trigger fires and the row splits.
##
## ============================================================================
## THE BANDS
## ============================================================================
##
##   (i)  NOT FREE MONEY. A pledge pays an upfront bloc_offset for making it and
##        charges an accrued one for breaking it. If a full-term breach costs LESS
##        than the largest legal reward pays, pledging is free money and every pledge
##        is strictly dominant -- the shape this project has killed eight times. The
##        edge is MEASURED off diplomacy_constants.MAX_ACTION_BLOC_OFFSET rather than
##        invented, which is V1.7a's correction (a) inherited.
##
##   (ii) READABLE. A full-term breach must move the headline past POLL_FLOOR_PTS.
##        A price the published polls cannot resolve is a price the player cannot
##        attribute -- and attribution is the whole standard docs/election-model.md
##        and docs/opinion-model.md are judged on.
##
##   (iii) IT MUST NOT SUBSTITUTE FOR THE RECORD. A full-term breach must cost at
##        most what one term of GOVERNING moves the headline, measured in table (d0)
##        as the reachable spread between two real budgets at the same election. If
##        one broken promise can move approval further than the whole record can,
##        the promise is the game. V1.7a's upper edge -- "above the poll floor a
##        campaign substitutes for the record" -- in a new place.
##
##   (iv) THE CLAMP IS A GUARD RAIL AND NOT A SELECTOR. legislature_constants'
##        BLOC_OFFSET_MIN bounds the accumulator. If the worst reachable accrual
##        sits ON it, the clamp and not the content is setting the number --
##        docs/economy-model.md's IMPULSE_MAX finding, caught eight times now.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const DiplomacyK = preload("res://src/sim/diplomacy_constants.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const CampaignK = preload("res://src/sim/campaign_constants.gd")
const Elections = preload("res://src/sim/elections.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const PledgeK = preload("res://src/sim/pledges_constants.gd")

const PLAYER := "FRA"
const START_YEAR := 2026

## One presidential term, in months.
const TERM_MONTHS := 60

const POLL_FLOOR_PTS := 3.0

## V1.7a's measured anchor, quoted rather than recomputed: one point of approval is
## worth this much of the incumbent's vote share through Elections.vote_share()'s
## `pull` term. docs/campaign-model.md table (c4). Recomputing it here would be one
## quantity with two writers.
const APPROVAL_POINT_IN_SHARE := 0.3415

## The budgets table (d0) measures the governing span between. Quoted from
## tools/balance_probe.gd's own REGIMES rather than re-invented.
const MANAGED := {
	"spending_pct_gdp": {"defence": -1.4},
	"tax_rates_pct": {"vat": 3.0},
}
const SPENDTHRIFT := {
	"spending_pct_gdp": {
		"health": 3.0, "education": 2.5, "defence": 1.5,
		"pensions": 3.5, "infrastructure": 2.5,
	},
	"tax_rates_pct": {"income": -6.0, "corporate": -7.0, "vat": -4.0},
}
const AUSTERITY := {
	"spending_pct_gdp": {
		"health": -2.5, "education": -2.0, "defence": -1.0,
		"pensions": -3.5, "infrastructure": -2.0,
	},
	"tax_rates_pct": {"income": 6.0, "corporate": 5.0, "vat": 4.0},
}

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		for e in _loader.errors:
			printerr(e)
		quit(1)
		return

	print("=== V1.7b pledge probe ===")
	print("BLOC_OFFSET_MIN            %.4f" % LegislatureK.BLOC_OFFSET_MIN)
	print("MAX_ACTION_BLOC_OFFSET     %.4f" % DiplomacyK.MAX_ACTION_BLOC_OFFSET)
	print("APPROVAL_SPAN              %.4f" % OpinionK.APPROVAL_SPAN)
	print("INERTIA_RATE               %.4f" % OpinionK.INERTIA_RATE)
	print("CAMPAIGN_WINDOW_MONTHS     %d" % CampaignK.CAMPAIGN_WINDOW_MONTHS)
	print("")

	_table_a0_reachability()
	_table_b0_landing_site()
	_table_c0_volatility()
	_table_d0_governing_span()
	_table_e0_ladder()
	_table_f0_dominance()
	_table_g0_guard_rail()
	_table_h0_kill_switch()

	quit(0)


# ============================================================================
# (a0) REACHABILITY -- can a pledge be made, and is it ever judged?
# ============================================================================

## U6a's finding, checked rather than hoped: the page every player sees first was the
## page with nothing on it. A pledge is made inside Campaign.is_open() and binds the
## term that run-up is for, so this counts the windows and the judgements a
## fourteen-year run actually reaches.
func _table_a0_reachability() -> void:
	print("(a0) REACHABILITY -- 168 months from %d-01, %s, under `managed`" % [START_YEAR, PLAYER])
	print("  *** THE FIRST VERSION OF THIS TABLE MEASURED THE WRONG STATE, which is")
	print("  *** V1.3f's error in the probe written to avoid it: _tick() deliberately")
	print("  *** omits Elections, so next_executive_* never moved and 168 months showed")
	print("  *** ONE run-up and ZERO judgements. The schedule IS the thing under test.")
	print("")
	print("  yyyy-mm   to_vote  note")

	var state = _new_state()
	var ns = state.player()
	_commit(state, ns, MANAGED)
	var windows := 0
	var in_window := false
	var opens: Array = []
	var elections := 0

	for m in range(168):
		var open: bool = Campaign.is_open(state, ns)
		if open and not in_window:
			windows += 1
			opens.append("%04d-%02d" % [state.year, state.month])
			print("  %04d-%02d   %6d  run-up %d begins" % [
				state.year, state.month, Campaign.months_to_election(state, ns), windows])
		in_window = open

		_advance(state)
		_tick(state)
		for r in Elections.tick_month(state, _loader):
			if String(r.get("kind", "")) in ["executive", "termed_out"]:
				elections += 1
				print("  %04d-%02d           %s%s" % [
					state.year, state.month, String(r["kind"]),
					"" if bool(r.get("incumbent_largest", false)) else "  -- INCUMBENT LOST"])
		if not ns.in_government:
			print("  %04d-%02d           run ends: out of government" % [state.year, state.month])
			break

	print("  run-ups reached: %d  at %s" % [windows, str(opens)])
	# A pledge made in run-up N binds the term run-up N is for, so the number of FULL
	# judgements a run reaches is one fewer than the number of run-ups.
	print("  executive verdicts: %d" % elections)
	print("  full judgements reachable: %d" % maxi(0, windows - 1))
	print("")


# ============================================================================
# (b0) THE LANDING SITE -- the split trigger, measured before any content exists
# ============================================================================

## Charge a candidate per-month accrual onto a candidate bloc set for `months`, run
## the real tick, and measure what the headline does against a control that is
## identical in every other respect.
##
## THE ACCRUAL IS APPLIED THROUGH ns.bloc_offset AND NOT SIMULATED HERE, so this
## measures the model that will ship rather than an approximation of it -- V1.6b's
## correction, which is that a probe reimplementing the channel has the answer inside
## its own question.
func _table_b0_landing_site() -> void:
	print("(b0) LANDING SITE -- what a monthly bloc_offset accrual is worth")
	print("  the split trigger: if no reachable row clears POLL_FLOOR_PTS (%.1f)" % POLL_FLOOR_PTS)
	print("  without saturating BLOC_OFFSET_MIN (%.2f), the price does not land here." % LegislatureK.BLOC_OFFSET_MIN)
	print("")

	var sets := {
		"workers            (0.30)": ["workers"],
		"workers+pensioners (0.54)": ["workers", "pensioners"],
		"urban+students     (0.23)": ["urban", "students"],
		"all six            (1.00)": ["workers", "pensioners", "urban", "rural", "business", "students"],
	}
	var rates: Array = [0.001, 0.002, 0.004, 0.006, 0.008, 0.010]
	var horizons: Array = [12, 24, 36, 60]

	for label in sets:
		print("  blocs %s" % label)
		print("    rate/mo  |  %s" % "  ".join(horizons.map(func(h): return "%2dmo headline" % h)))
		for r in rates:
			var cells: Array = []
			for h in horizons:
				var d: Dictionary = _accrual_run(sets[label], float(r), int(h))
				cells.append("%+9.3f pts" % d["headline_delta"])
			var peak: Dictionary = _accrual_run(sets[label], float(r), 60)
			print("    %7.4f  |  %s   worst offset %.4f (%.0f %% of clamp)" % [
				r, "  ".join(cells), peak["worst_offset"],
				100.0 * absf(peak["worst_offset"]) / absf(LegislatureK.BLOC_OFFSET_MIN),
			])
		print("")

	# (i)'s edge, measured rather than invented.
	var reward_headline: float = _reward_headline()
	print("  (i)  the largest legal single-act reward is worth %+.3f headline pts" % reward_headline)
	print("       -- a full-term breach costing less than this is free money.")
	print("  (ii) the readability edge is POLL_FLOOR_PTS = %.1f pts." % POLL_FLOOR_PTS)
	print("")


## What one act at MAX_ACTION_BLOC_OFFSET on the largest bloc is worth on the
## headline, once approval has converged. Closed form: the target moves by
## APPROVAL_SPAN * offset for that bloc, and the headline is the BLOC_SIZE-weighted
## roll-up -- so this needs no run, and V1.6e's rule says solve it rather than sweep.
func _reward_headline() -> float:
	var best := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		best = maxf(best, float(OpinionK.BLOC_SIZE[bloc]))
	return DiplomacyK.MAX_ACTION_BLOC_OFFSET * OpinionK.APPROVAL_SPAN * best


## One run: `months` months of `rate` charged onto every bloc in `blocs`, against a
## control run that charges nothing. Returns the headline deviation and the worst
## accumulated offset.
func _accrual_run(blocs: Array, rate: float, months: int) -> Dictionary:
	var per_month := {}
	for b in blocs:
		per_month[b] = -rate
	var control := _offset_run(months, {}, {})
	var charged := _offset_run(months, per_month, {})
	return {
		"headline_delta": charged["headline"] - control["headline"],
		"worst_offset": charged["worst_offset"],
	}


## One run of `months` months with `once` applied to ns.bloc_offset on the first month
## and `per_month` applied on every month, through the same clamp Pledges.tick_month()
## uses. Returns the headline, the worst accumulated offset, and what the vote would
## see if it were held at the end.
func _offset_run(months: int, per_month: Dictionary, once: Dictionary) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties.get(PLAYER, [])

	for bloc in once:
		ns.bloc_offset[bloc] = clampf(
			float(ns.bloc_offset.get(bloc, 0.0)) + float(once[bloc]),
			LegislatureK.BLOC_OFFSET_MIN, LegislatureK.BLOC_OFFSET_MAX
		)

	for m in range(months):
		for bloc in per_month:
			ns.bloc_offset[bloc] = clampf(
				float(ns.bloc_offset.get(bloc, 0.0)) + float(per_month[bloc]),
				LegislatureK.BLOC_OFFSET_MIN, LegislatureK.BLOC_OFFSET_MAX
			)
		_advance(state)
		_tick(state)

	var worst := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		if absf(float(ns.bloc_offset.get(bloc, 0.0))) > absf(worst):
			worst = float(ns.bloc_offset.get(bloc, 0.0))

	var shares := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
	var mine: float = float(shares.get(ns.incumbent_party_id, 0.0))
	var best_other := 0.0
	for pid in shares:
		if String(pid) != ns.incumbent_party_id:
			best_other = maxf(best_other, float(shares[pid]))

	return {
		"headline": float(ns.overall_approval_pct),
		"worst_offset": worst,
		"share": 100.0 * mine,
		"gap": 100.0 * (mine - best_other),
	}


# ============================================================================
# (c0) FIELD VOLATILITY -- which fields can honestly be promised
# ============================================================================

## A pledge is judged EVERY MONTH it is live, so a field that bounces in and out of
## breach on its own makes the price a coin toss rather than a consequence. Measured
## over one term under a real budget, per candidate field, as the number of sign
## flips against a plausible threshold.
func _table_c0_volatility() -> void:
	print("(c0) FIELD VOLATILITY -- over %d months, three real budgets" % TERM_MONTHS)
	print("  A pledge is judged EVERY MONTH it is live, so a field splits two ways:")
	print("    LUCK   = the widest span WITHIN one budget -- what the world does to you")
	print("    CHOICE = the span ACROSS budgets at the end -- what you do to yourself")
	print("  A field with no luck is a self-imposed constraint; a field with no choice")
	print("  is a field the player cannot honestly be held to.")
	print("")
	print("  field                     luck    choice   flips   min       max")

	var fields := [
		"unemployment_pct", "deficit_pct_gdp", "debt_to_gdp_pct",
		"growth_annual_pct", "inflation_pct", "unrest_pct",
		"tax_income_pct", "tax_vat_pct", "spending_health_pct_gdp",
	]
	var budgets := {"managed": MANAGED, "austerity": AUSTERITY, "hands_off": {}}

	var per_budget := {}
	for name in budgets:
		per_budget[name] = _field_series(budgets[name], fields)

	for f in fields:
		var luck := 0.0
		var lo := INF
		var hi := -INF
		var flips := 0
		var ends: Array = []
		for name in budgets:
			var vals: Array = per_budget[name][f]
			var blo: float = INF
			var bhi: float = -INF
			for v in vals:
				blo = minf(blo, float(v))
				bhi = maxf(bhi, float(v))
			luck = maxf(luck, bhi - blo)
			lo = minf(lo, blo)
			hi = maxf(hi, bhi)
			ends.append(float(vals[vals.size() - 1]))
			var mid: float = 0.5 * (blo + bhi)
			var above: bool = float(vals[0]) >= mid
			for v in vals:
				var now: bool = float(v) >= mid
				if now != above:
					flips += 1
					above = now
		var choice: float = ends.max() - ends.min()
		print("  %-22s %7.3f  %7.3f    %2d   %8.3f  %8.3f" % [f, luck, choice, flips, lo, hi])
	print("")


func _field_series(delta: Dictionary, fields: Array) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	if not delta.is_empty():
		_commit(state, ns, delta)
	var series := {}
	for f in fields:
		series[f] = []
	for m in range(TERM_MONTHS):
		_advance(state)
		_tick(state)
		for f in fields:
			series[f].append(_read_field(ns, String(f)))
	return series


func _read_field(ns, field: String) -> float:
	match field:
		"unemployment_pct": return float(ns.unemployment_pct)
		"deficit_pct_gdp": return float(ns.deficit_pct_gdp)
		"debt_to_gdp_pct": return float(ns.debt_to_gdp_pct())
		"growth_annual_pct": return float(ns.growth_annual_pct)
		"inflation_pct": return float(ns.inflation_pct)
		"unrest_pct": return float(ns.unrest_pct)
		"tax_income_pct": return float(ns.tax_rates_pct.get("income", 0.0))
		"tax_vat_pct": return float(ns.tax_rates_pct.get("vat", 0.0))
		"spending_health_pct_gdp": return float(ns.spending_pct_gdp.get("health", 0.0))
		_: return 0.0


# ============================================================================
# (d0) THE GOVERNING SPAN -- band (iii)'s upper edge, measured
# ============================================================================

## What one term of governing is worth on the headline, as the spread between two
## real budgets at the same month. Band (iii) says a broken promise must cost at most
## this: if one promise can move approval further than the whole record can, the
## promise is the game rather than a stake in it.
func _table_d0_governing_span() -> void:
	print("(d0) GOVERNING SPAN -- headline at month %d under two real budgets" % TERM_MONTHS)
	var a: float = _budget_run(MANAGED)
	var b: float = _budget_run(AUSTERITY)
	var c: float = _budget_run({})
	print("  hands_off   %6.2f" % c)
	print("  managed     %6.2f" % a)
	print("  austerity   %6.2f" % b)
	var span: float = maxf(maxf(a, b), c) - minf(minf(a, b), c)
	print("  span        %6.2f pts  <- band (iii)'s upper edge" % span)
	print("  in vote share that is %.4f pts" % (span * APPROVAL_POINT_IN_SHARE))
	print("")


func _budget_run(delta: Dictionary) -> float:
	var state = _new_state()
	var ns = state.player()
	if not delta.is_empty():
		_commit(state, ns, delta)
	for m in range(TERM_MONTHS):
		_advance(state)
		_tick(state)
	return float(ns.overall_approval_pct)


# ============================================================================
# (e0) THE LADDER -- every authored promise against every band
# ============================================================================

## What each promise pays for being made and charges for being broken, measured
## through the same clamp Pledges.tick_month() writes through rather than computed
## closed form -- the closed form ignores that Opinion clamps `score + law_offset` to
## [-1, +1], which is exactly where a heavy promise would stop being linear.
func _table_e0_ladder() -> void:
	print("(e0) THE LADDER -- %d authored promises" % _loader.pledges.size())
	print("  reward = the upfront bloc_offset, converged. breach = %d months broken." % TERM_MONTHS)
	print("")
	print("  promise                 field                     reward   breach   ratio  clamp   (i)  (ii) (iii)")

	var control := _offset_run(TERM_MONTHS, {}, {})
	var span: float = _governing_span()
	_rows = []

	for action in _loader.pledges:
		var terms: Dictionary = action.effects.get("pledge", {})
		var reward: Dictionary = action.effects.get("bloc_offset", {})
		var breach: Dictionary = terms.get("breach_offset", {})

		var negated := {}
		for b in breach:
			negated[b] = -float(breach[b])

		var r := _offset_run(TERM_MONTHS, {}, reward)
		var b_run := _offset_run(TERM_MONTHS, negated, {})

		var reward_pts: float = r["headline"] - control["headline"]
		var breach_pts: float = control["headline"] - b_run["headline"]
		var ratio: float = 0.0 if reward_pts <= 0.0 else breach_pts / reward_pts
		var clamp_frac: float = absf(b_run["worst_offset"]) / absf(LegislatureK.BLOC_OFFSET_MIN)

		var pass_i: bool = breach_pts > reward_pts
		var pass_ii: bool = breach_pts >= POLL_FLOOR_PTS
		var pass_iii: bool = breach_pts <= span

		print("  %-22s  %-24s %+7.3f  %7.3f  %5.2fx %4.0f%%   %s  %s  %s" % [
			String(terms.get("pledge_name", "?")), String(terms.get("field", "?")),
			reward_pts, breach_pts, ratio, 100.0 * clamp_frac,
			"ok " if pass_i else "NO ", "ok " if pass_ii else "NO ", "ok " if pass_iii else "NO ",
		])
		_rows.append({
			"name": String(terms.get("pledge_name", "?")),
			"field": String(terms.get("field", "?")),
			"reward": reward_pts, "breach": breach_pts, "ratio": ratio,
			"share": r["share"] - control["share"],
			"gap": r["gap"] - control["gap"],
			"breach_share": b_run["share"] - control["share"],
			"breach_gap": b_run["gap"] - control["gap"],
		})

	print("")
	print("  bands: (i) breach > reward   (ii) breach >= %.2f pts   (iii) breach <= %.2f pts" % [POLL_FLOOR_PTS, span])
	print("")
	print("  AT THE BALLOT BOX -- what each promise is worth to Elections.vote_share()")
	print("  promise                  made: d share   d gap  |  broken: d share   d gap")
	for row in _rows:
		print("  %-22s  %+11.4f %+7.4f  |  %+14.4f %+7.4f" % [
			row["name"], row["share"], row["gap"], row["breach_share"], row["breach_gap"]])
	print("")

	# The ordering nobody could author into a single row: the price-to-reward ratio
	# should FALL as the field gets luckier, because you are paid more per unit of risk
	# for a promise you cannot control.
	# *** THE ORDERING STATISTIC WAS LUCK AND IT HAD TO BE EXPOSURE. *** The first
	# version of this check ordered on table (c0)'s luck column alone and the ladder
	# failed it on one adjacent pair: deficit_pct_gdp measures 1.284 of luck against
	# unemployment_pct's 1.182, eight per cent apart, while its CHOICE column is
	# 16.445 against 0.656 -- twenty-five times as large. Luck in isolation says the
	# deficit is the more uncontrollable of the two; luck as a SHARE of luck plus
	# choice says the opposite, and says it by a factor of nine. Exposure is the share
	# of the outcome the president does not control, and on it the ladder is monotone.
	print("  RATIO AGAINST EXPOSURE -- luck / (luck + choice), checked rather than asserted")
	var last := -99.0
	var monotone := true
	var ordered: Array = _rows.duplicate()
	ordered.sort_custom(func(a, b): return _exposure_of(String(a["field"])) > _exposure_of(String(b["field"])))
	for row in ordered:
		var e: float = _exposure_of(String(row["field"]))
		if float(row["ratio"]) < last - 0.0001:
			monotone = false
		last = float(row["ratio"])
		print("    %-22s  exposure %5.3f   ratio %5.2fx" % [row["name"], e, row["ratio"]])
	print("  monotone (ratio falls as exposure rises): %s" % ("YES" if monotone else "NO"))
	print("")


var _rows: Array = []
var _luck_cache := {}
var _exposure_cache := {}
var _span_cache := -1.0


## Table (c0)'s two columns as one number: the share of a field's movement that the
## president does not control. 0.0 is a rate nothing but the player touches; near 1.0
## is a field the budget barely reaches.
func _exposure_of(field: String) -> float:
	if _luck_cache.is_empty():
		var fields: Array = PledgeK.PLEDGE_FIELDS
		var ends := {}
		for f in fields:
			ends[f] = []
		for budget in [MANAGED, AUSTERITY, {}]:
			var series: Dictionary = _field_series(budget, fields)
			for f in fields:
				var vals: Array = series[f]
				var lo: float = INF
				var hi: float = -INF
				for v in vals:
					lo = minf(lo, float(v))
					hi = maxf(hi, float(v))
				_luck_cache[f] = maxf(float(_luck_cache.get(f, 0.0)), hi - lo)
				ends[f].append(float(vals[vals.size() - 1]))
		for f in fields:
			var choice: float = ends[f].max() - ends[f].min()
			var luck: float = float(_luck_cache[f])
			_exposure_cache[f] = 0.0 if luck + choice <= 0.0 else luck / (luck + choice)
	return float(_exposure_cache.get(field, 0.0))


func _governing_span() -> float:
	if _span_cache < 0.0:
		var a: float = _budget_run(MANAGED)
		var b: float = _budget_run(AUSTERITY)
		var c: float = _budget_run({})
		_span_cache = maxf(maxf(a, b), c) - minf(minf(a, b), c)
	return _span_cache


# ============================================================================
# (f0) DOMINANCE -- is any promise strictly worse than another?
# ============================================================================

## A promise dominates another when it pays MORE for being made and costs LESS for
## being broken. If any pair is ordered that way the ladder is a ranking rather than a
## choice, and the loser is content nobody would ever pick -- V1.7a's check on the
## campaign ladder, and V1.6f's on the project one.
func _table_f0_dominance() -> void:
	print("(f0) DOMINANCE -- and the FIRST VERSION OF THIS TEST WAS THE WRONG TEST")
	print("  It compared the authored pair (reward, breach) and reported FIVE dominated")
	print("  pairs -- the tax lock beaten by the growth pledge, the hospitals beaten by")
	print("  both. Every one of those is an artefact: the pair is not the decision,")
	print("  because the third quantity is HOW OFTEN THE PROMISE IS ACTUALLY BROKEN, and")
	print("  that is nowhere in the content. It is a property of the budget the player")
	print("  intends to run. V1.7a's `share is not winning` in a new place.")
	print("")
	print("  So: net vote share at the 2032 vote, per promise, per POST-ELECTION policy.")
	print("  A president wins 2027 on `managed` and then governs as the column says --")
	print("  V1.5c's mid-run switch, which is the reachable way to break a promise.")
	print("")

	var columns := {"hold managed": {}, "switch to austerity": AUSTERITY, "switch to spendthrift": SPENDTHRIFT}
	var base := {}
	for col in columns:
		base[col] = _pledge_run("", MANAGED, columns[col])

	var header := "  promise                "
	for col in columns:
		header += "  %-22s" % col
	print(header)

	var best_in := {}
	for col in columns:
		best_in[col] = -INF

	var results := {}
	for action in _loader.pledges:
		var name := String(action.effects.get("pledge", {}).get("pledge_name", "?"))
		var line := "  %-22s" % name
		results[name] = {}
		for col in columns:
			var run := _pledge_run(action.id, MANAGED, columns[col])
			var net: float = run["share"] - float(base[col]["share"])
			results[name][col] = net
			best_in[col] = maxf(float(best_in[col]), net)
			line += "  %+7.4f (%2d/%2d)     " % [net, int(run["breach_months"]), int(run["months_live"])]
		print(line)

	print("")
	var dominated := 0
	for a in results:
		for b in results:
			if a == b:
				continue
			var strictly := true
			for col in columns:
				if float(results[b][col]) < float(results[a][col]):
					strictly = false
			if strictly:
				dominated += 1
				print("    %s is dominated by %s in EVERY column" % [a, b])
	print("  promises dominated in every column: %d" % dominated)
	print("  best promise per column:")
	for col in columns:
		for name in results:
			if is_equal_approx(float(results[name][col]), float(best_in[col])):
				print("    %-22s -> %s" % [col, name])
	print("")


# ============================================================================
# (g0) THE GUARD RAIL -- declared, not a selector
# ============================================================================

## legislature_constants.BLOC_OFFSET_MIN bounds the accumulator this model charges
## through, and it is SHARED -- laws, a fallen government, a scenario's authored
## approval, a diplomatic act and V1.7a's campaign all write it too. So the reachable
## stack measured here is a FLOOR on the real exposure, not a ceiling, and the report
## says so rather than leaving it to be discovered.
func _table_g0_guard_rail() -> void:
	print("(g0) GUARD RAIL -- BLOC_OFFSET_MIN = %.2f, and it is a bound not a selector" % LegislatureK.BLOC_OFFSET_MIN)

	# The concurrency gate is `pledge_count <= 1`, so at most TWO promises stand at
	# once. The worst stack is the pair whose breach rates overlap hardest on one bloc.
	var worst := 0.0
	var worst_pair := "(none)"
	var list: Array = _loader.pledges
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Dictionary = list[i].effects.get("pledge", {}).get("breach_offset", {})
			var b: Dictionary = list[j].effects.get("pledge", {}).get("breach_offset", {})
			for bloc in OpinionK.BLOC_KEYS:
				var stack: float = (float(a.get(bloc, 0.0)) + float(b.get(bloc, 0.0))) * TERM_MONTHS
				if stack > worst:
					worst = stack
					worst_pair = "%s + %s on %s" % [
						String(list[i].effects["pledge"].get("pledge_name", "?")),
						String(list[j].effects["pledge"].get("pledge_name", "?")), bloc]
	print("  worst reachable two-promise stack: %.4f  (%s)" % [worst, worst_pair])
	print("  against the clamp: %.0f %% used, %.4f of slack" % [
		100.0 * worst / absf(LegislatureK.BLOC_OFFSET_MIN),
		absf(LegislatureK.BLOC_OFFSET_MIN) - worst])
	print("  largest authored rate %.4f against MAX_BREACH_OFFSET_PER_MONTH %.4f" % [
		_max_authored_rate(), PledgeK.MAX_BREACH_OFFSET_PER_MONTH])
	print("  NOTE: bloc_offset is shared with laws, government penalties, scenarios,")
	print("  diplomatic acts and V1.7a's campaign, so this is a FLOOR on the exposure.")
	print("")


func _max_authored_rate() -> float:
	var best := 0.0
	for action in _loader.pledges:
		for bloc in action.effects.get("pledge", {}).get("breach_offset", {}):
			best = maxf(best, float(action.effects["pledge"]["breach_offset"][bloc]))
	return best


# ============================================================================
# (h0) THE KILL SWITCH -- does a broken promise reach a voter?
# ============================================================================

## The whole session is one register and one price. If a promise made and then broken
## over a real term does not move what the vote sees, there is no lever here and the
## row should have split. Run END TO END through the real verb, the real tick and the
## real election rather than through table (e0)'s displaced offsets.
func _table_h0_kill_switch() -> void:
	print("(h0) KILL SWITCH -- promise made in the 2026 run-up, judged over the 2027-2032 term")
	print("  budget       promise                 broken  approval   d share    d gap")

	for budget_name in ["managed", "austerity"]:
		var budget: Dictionary = MANAGED if budget_name == "managed" else AUSTERITY
		var base := _pledge_run("", budget, {})
		print("  %-11s  %-22s   -    %6.2f        -        -" % [budget_name, "(none)", base["headline"]])
		for action in _loader.pledges:
			var terms: Dictionary = action.effects.get("pledge", {})
			var run := _pledge_run(action.id, budget, {})
			print("  %-11s  %-22s %3d/%-3d %6.2f  %+8.4f %+8.4f" % [
				budget_name, String(terms.get("pledge_name", "?")),
				int(run["breach_months"]), int(run["months_live"]),
				run["headline"], run["share"] - base["share"], run["gap"] - base["gap"]])
		print("")


## A full run: start of the game, commit the budget, make the named promise the month
## the run-up opens, and run to just before the 2032 vote. Uses Pledges.execute() and
## Pledges.tick_month() rather than reimplementing either -- V1.6b's correction, that a
## probe reimplementing the channel has the answer inside its own question.
func _pledge_run(action_id: String, budget: Dictionary, switch: Dictionary = {}) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties.get(PLAYER, [])
	if not budget.is_empty():
		_commit(state, ns, budget)

	var made: bool = action_id == ""
	var breach_months := 0
	var months_live := 0

	# 2026-01 to just before the 2032 vote.
	for m in range(75):
		if not made:
			for a in Pledges.available(state, ns, _loader.pledges):
				if a.id == action_id:
					Pledges.execute(state, ns, _loader.pledges, a)
					made = true
					break
		_advance(state)
		_tick(state)
		Pledges.tick_month(state, _loader)
		for entry in ns.pledges:
			breach_months = maxi(breach_months, int(entry["breach_months"]))
			months_live = maxi(months_live, int(entry["months_live"]))
		for r in Elections.tick_month(state, _loader):
			# The switch fires on the executive verdict the promise was made for, which
			# is the only moment a president is both re-elected and free to govern
			# differently. Committed through the real Budget.commit().
			if String(r.get("kind", "")) == "executive" and bool(r.get("incumbent_largest", false)):
				if not switch.is_empty():
					_commit(state, ns, switch)
		if not ns.in_government:
			break

	var shares := Elections.vote_share(ns, party_list, ns.incumbent_party_id)
	var mine: float = float(shares.get(ns.incumbent_party_id, 0.0))
	var best_other := 0.0
	for pid in shares:
		if String(pid) != ns.incumbent_party_id:
			best_other = maxf(best_other, float(shares[pid]))

	return {
		"headline": float(ns.overall_approval_pct),
		"share": 100.0 * mine,
		"gap": 100.0 * (mine - best_other),
		"breach_months": breach_months,
		"months_live": months_live,
	}


# ============================================================================
# Harness
# ============================================================================

func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = START_YEAR
	state.month = 1
	return state


## balance_probe.gd's nation-relative deltas, applied through the real Budget.commit()
## so a regime here means what it means there.
func _commit(state, ns, delta: Dictionary) -> void:
	var pending := {
		"tax_rates_pct": ns.tax_rates_pct.duplicate(),
		"spending_pct_gdp": ns.spending_pct_gdp.duplicate(),
	}
	for key in delta.get("tax_rates_pct", {}):
		pending["tax_rates_pct"][key] = float(pending["tax_rates_pct"].get(key, 0.0)) + float(delta["tax_rates_pct"][key])
	for key in delta.get("spending_pct_gdp", {}):
		pending["spending_pct_gdp"][key] = float(pending["spending_pct_gdp"].get(key, 0.0)) + float(delta["spending_pct_gdp"][key])
	Budget.commit(state, pending)


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


## One month, in main.gd's order. Elections is deliberately NOT run: every table here
## measures a term in progress, and a resolved election would move the schedule the
## window is read against.
func _tick(state) -> void:
	Economy.tick_month(state)
	Budget.tick_month(state)
	Bloc.tick_month(state, _loader)
	Inflation.tick_month(state)
	Media.tick_month(state, _loader)
	Opinion.tick_month(state)
	Defence.tick_month(state)
	Companies.tick_month(state, _loader)
	Investment.tick_month(state)
	Projects.tick_month(state, _loader)
	Campaign.tick_month(state, _loader)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, _loader)
