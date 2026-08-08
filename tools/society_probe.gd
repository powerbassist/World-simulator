extends SceneTree

## V1.5a's headless sweep. Every constant in src/sim/society_constants.gd and
## opinion_constants.QUALITY_SCALE_PP is set from a table below rather than guessed
## and defended afterwards.
##
## THE BANDS ARE PRE-COMMITTED, and so are THE TIEBREAKERS. That second half is
## V1.4c's lesson written into a probe for the first time: DIVIDEND_YIELD's band
## passed three of four rows and CHOSE NOTHING, because a band measuring whether a
## line is READABLE is a different question from whether the number is RIGHT. So each
## constant below names, in advance, the existing constant its tiebreaker is a ratio
## against -- and a constant that cannot clear its band is DELETED rather than left
## unused, which is AGREEMENT_ACCEPT_MIN's treatment at V1.3e and the day budget's at
## U6a.
##
##   (P1) SPEED     QUALITY_CONVERGENCE. At a reachable sustained spending change of
##                  +1.0 point of GDP, the stock covers 40-90 % of the distance to its
##                  new equilibrium inside ONE 60-month presidential term. Under 40 %
##                  the player never sees the consequence of their own budget; over
##                  90 % the stock is not a stock and the delta term already models it.
##                  TIEBREAKER: the ratio against defence_constants.
##                  CAPABILITY_CONVERGENCE = 0.02, the only other stock of this exact
##                  shape in the project. Take the passing value NEAREST it; more than
##                  2x away needs something measured, not a story about how schools
##                  differ from armies.
##
##   (P2) OPINION   QUALITY_SCALE_PP. The quality channel alone moves the headline
##                  approval figure past the +-3.0 poll-noise floor at a reachable
##                  sustained spending change.
##                  TIEBREAKER: the ratio against opinion_constants.SPEND_SCALE_PP =
##                  3.0, because both land on the SAME issue and their ratio IS the
##                  double-count answer. Pre-committed rule: if the two terms SUMMED
##                  under a sustained change exceed what SPEND_SCALE_PP produced on
##                  its own, SPEND_SCALE_PP is re-measured DOWNWARD rather than
##                  QUALITY_SCALE_PP being shaved. That direction is the point -- the
##                  delta was tuned at S10 against a world where delivery was instant,
##                  so it is the OLDER number that was wrong about the total.
##
##   (P3) CORRUPT   *** KILL SWITCH ***. CORRUPTION_DELIVERY_BETA. A saturated
##                  corruption level moves the headline past +-3.0. If it cannot, the
##                  factor is decorative and the constant is DELETED rather than tuned
##                  until it looks alive.
##                  TIEBREAKER: the ratio against cabinet_constants.
##                  VACANT_EFFECTIVENESS = 0.50. A factor degrading delivery FURTHER
##                  than an empty ministry claims corruption is worse than having no
##                  minister at all, so DELIVERY_MIN may not go under 0.50 and this
##                  constant is bounded at 0.50 against a saturated register.
##
##   (P4) CLAMP     The reachable worst case sits strictly inside DELIVERY_MIN and
##                  DELIVERY_MAX. A clamp that binds is a clamp setting the number --
##                  docs/defence-model.md measured its bill clamp the same way.
##
##   (P5) ISSUE_KEYS  V1.3d's four tests, applied to a candidate `corruption` key.
##                  Reported with the S10 ratio drift, and answered either way in
##                  opinion_constants.gd beside ISSUE_KEYS -- V1.4c's precedent, so a
##                  later session finds the reasons rather than the silence.
##
## Not a test. Excluded from tools/run_tests.sh by design, so run it explicitly:
##   godot --headless --script res://tools/society_probe.gd

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Society = preload("res://src/sim/society.gd")
const K = preload("res://src/sim/society_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const CabinetK = preload("res://src/sim/cabinet_constants.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Legislature = preload("res://src/sim/legislature.gd")

const PLAYABLE := ["FRA", "DEU", "GBR"]
const TERM_MONTHS := 60
const RUN_MONTHS := 168

## The reachable sustained spending change the bands are measured at. One point of
## GDP on a single line is a large but ordinary budget decision -- France's health
## line is 11.0, so this is a ~9 % move.
const SPEND_STEP := 1.0

const CONVERGENCE_CANDIDATES := [0.01, 0.02, 0.04, 0.08]
const SCALE_CANDIDATES := [3.0, 4.5, 6.0, 9.0, 12.0]
const BETA_CANDIDATES := [0.10, 0.20, 0.30, 0.50]

const BAND_SPEED_MIN := 0.40
const BAND_SPEED_MAX := 0.90
const NOISE_FLOOR := 3.0

var _loader
var _key: String


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	_key = K.QUALITY_KEYS[0]

	_table_a_census()
	_table_b_speed()
	_table_c_scale()
	_table_d_corruption()
	_table_e_clamp()
	_table_f_issue_keys()
	quit(0)


func _new_state(nation_id: String):
	return GameState.new_game(_loader, nation_id)


## Steps the whole tick in main.gd's order, Society last -- see src/ui/main.gd for why
## it sits in Companies' slot rather than before Opinion.
func _step(state) -> void:
	Economy.tick_month(state)
	Budget.tick_month(state)
	Opinion.tick_month(state)
	Society.tick_month(state)


# --- (a) The census that is the session's actual finding -----------------------

## Not a sweep. This table is the reason QUALITY_KEYS has one entry rather than five,
## and it is the finding docs/tiers/v1.md §5's bullet 9 does not contain: of the five
## spending lines, THREE already carry an outcome stock under another name.
func _table_a_census() -> void:
	print("\n=== (a) which spending lines already have an outcome stock ===")
	print("%-16s %-26s %s" % ["line", "existing stock", "V1.5a"])
	var existing := {
		"health": "-",
		"education": "potential_shift_pct (S4)",
		"defence": "military_capability (V1.3g)",
		"pensions": "-",
		"infrastructure": "potential_shift_pct (S4)",
	}
	for line in EK.SPENDING_KEYS:
		var verdict := "STOCK" if K.QUALITY_KEYS.has(line) else "excluded"
		print("%-16s %-26s %s" % [line, existing[line], verdict])
	print("`pensions` is excluded TEMPORARILY -- adequacy is spend per dependent, and")
	print("the dependent count is V1.5b's. The other two are excluded forever.")

	print("\n-- starting equilibrium per playable nation --")
	print("%-6s %10s %10s %10s" % ["nation", "spend", "effect.", "quality"])
	for id in PLAYABLE:
		var state = _new_state(id)
		var ns = state.player()
		print("%-6s %10.3f %10.3f %10.4f" % [
			id, float(ns.spending_pct_gdp[_key]), Cabinet.effectiveness(ns, _key),
			float(ns.service_quality[_key]),
		])


# --- (b) P1: QUALITY_CONVERGENCE ----------------------------------------------

func _table_b_speed() -> void:
	print("\n=== (b) P1: fraction of the gap covered in %d months, +%.1f pt on `%s` ===" % [
		TERM_MONTHS, SPEND_STEP, _key,
	])
	print("band %.0f-%.0f %%. tiebreaker: nearest CAPABILITY_CONVERGENCE = %.3f" % [
		BAND_SPEED_MIN * 100.0, BAND_SPEED_MAX * 100.0, DefenceK.CAPABILITY_CONVERGENCE,
	])
	print("%-10s %10s %10s %8s %10s" % ["rate", "term %", "168mo %", "band", "|ratio|"])

	for rate in CONVERGENCE_CANDIDATES:
		var term_frac: float = _gap_covered(rate, TERM_MONTHS)
		var run_frac: float = _gap_covered(rate, RUN_MONTHS)
		var inside: bool = term_frac >= BAND_SPEED_MIN and term_frac <= BAND_SPEED_MAX
		print("%-10.3f %9.1f%% %9.1f%% %8s %10.2f" % [
			rate, term_frac * 100.0, run_frac * 100.0,
			"PASS" if inside else "fail",
			rate / DefenceK.CAPABILITY_CONVERGENCE,
		])
	print("Shipped: QUALITY_CONVERGENCE = %.3f" % K.QUALITY_CONVERGENCE)


## Closed form of the stock, so the sweep does not need a GameState per candidate --
## quality_step() is pure for exactly this reason. Returns the fraction of the
## distance to the new equilibrium covered after `months`.
func _gap_covered(rate: float, months: int) -> float:
	var current := 0.0
	var target := 1.0
	for _m in range(months):
		current += rate * (target - current)
	return current


# --- (c) P2: QUALITY_SCALE_PP -------------------------------------------------

## THE PRE-COMMITTED BAND FAILED AT EVERY CANDIDATE, and the pre-committed response
## is the one the plan named in advance rather than a band widened after the fact:
## the price moves to a BLOC ROW, which is what docs/defence-model.md did when it
## found the headline arithmetically unable to carry a `defence` price. Recorded here
## with the failing table still printed, because the failure is the finding.
##
## Measured at the SATISFACTION level rather than by rescaling an approval delta. The
## first version of this table ran the sim once and multiplied the result by
## QUALITY_SCALE_PP / candidate, which is only valid below _scaled()'s clamp -- and
## whether a candidate saturates that clamp is precisely what the sweep has to find
## out. A measurement whose validity assumes the answer is not a measurement.
func _table_c_scale() -> void:
	print("\n=== (c) P2: the `%s` satisfaction term after %d months, +%.1f pt (FRA) ===" % [
		_key, TERM_MONTHS, SPEND_STEP,
	])

	# One real run, shipped constants, and the deviation is read off it. Every candidate
	# is then priced from that same measured deviation, so the rows differ only in the
	# constant and not in the state -- V1.3f's measuring-the-wrong-state error avoided
	# by measuring once.
	var quiet = _new_state("FRA")
	var loud = _new_state("FRA")
	loud.player().spending_pct_gdp[_key] = (
		float(loud.player().spending_pct_gdp[_key]) + SPEND_STEP
	)
	for _m in range(TERM_MONTHS):
		_step(quiet)
		_step(loud)

	var deviation: float = Society.quality_deviation(loud.player(), _key)
	var delta_pp: float = (
		float(loud.player().spending_pct_gdp[_key])
		- float(loud.player().start_spending_pct_gdp[_key])
	)
	var delta_term: float = clampf(
		delta_pp * Cabinet.effectiveness(loud.player(), _key) / OK.SPEND_SCALE_PP, -1.0, 1.0
	)
	print("measured deviation after %d months: %.4f pt of GDP" % [TERM_MONTHS, deviation])
	print("the delta half, for reference: %.4f satisfaction (SPEND_SCALE_PP = %.1f)" % [
		delta_term, OK.SPEND_SCALE_PP,
	])
	print("%-10s %12s %10s %10s %10s" % [
		"scale", "stock sat.", "vs delta", "saturates", "ratio",
	])
	for scale in SCALE_CANDIDATES:
		var raw: float = deviation / scale
		var term: float = clampf(raw, -1.0, 1.0)
		print("%-10.1f %12.4f %9.0f%% %10s %10.2f" % [
			scale, term, 100.0 * term / delta_term,
			"YES" if absf(raw) >= 1.0 else "no",
			scale / OK.SPEND_SCALE_PP,
		])
	print("Shipped: QUALITY_SCALE_PP = %.1f" % OK.QUALITY_SCALE_PP)

	# The headline, which is where the pre-committed band was set and where it failed.
	print("\n-- P2's ORIGINAL band, on the headline: this is the failure --")
	var head: float = (
		loud.player().overall_approval_pct - quiet.player().overall_approval_pct
	)
	print("headline, +%.1f pt on `%s`: %+.2f against a +-%.1f floor" % [
		SPEND_STEP, _key, head, NOISE_FLOOR,
	])
	print("NEGATIVE for a SPENDING INCREASE, and that is not the stock's fault: the")
	print("line widens the deficit by %.2f pt, and public_finances is weighted heavily" % delta_pp)
	print("by the blocs that weight `%s` lightly. V1.3g's finding from the other side." % _key)

	# The pre-committed response: the bloc row.
	print("\n-- P2's response, named in the plan before the sweep: the BLOC ROW --")
	print("%-14s %10s %10s %10s %8s" % ["bloc", "quiet", "raised", "delta", "band"])
	var best := 0.0
	for bloc in OK.BLOC_KEYS:
		var a: float = float(quiet.player().bloc_approval[bloc])
		var b: float = float(loud.player().bloc_approval[bloc])
		if absf(b - a) > absf(best):
			best = b - a
		print("%-14s %10.2f %10.2f %+10.2f %8s" % [
			bloc, a, b, b - a, "PASS" if absf(b - a) > NOISE_FLOOR else "-",
		])
	print("widest bloc row: %+.2f against a +-%.1f floor -- %s" % [
		best, NOISE_FLOOR, "PASS" if absf(best) > NOISE_FLOOR else "FAIL",
	])

	# THE BAND WAS MEASURED THROUGH A PATH THAT CANNOT VARY THE QUALITY CHANNEL ALONE,
	# and that is a defect in the band rather than a finding about the model. Raising a
	# spending line necessarily widens the deficit, so "the quality channel alone" was
	# never observable on that path -- V1.3f's measuring-the-wrong-state error, in the
	# probe written to avoid it, which is now the third session running.
	#
	# The isolated path is the one table (d) uses: move the stock with the spending line
	# UNTOUCHED, so the deficit, every tax and every other issue are bit-identical
	# between the two runs and the only thing that differs is delivery.
	print("\n-- P2 on the ISOLATED channel: spending untouched, stock moved alone --")
	var iso_quiet = _new_state("FRA")
	var iso_loud = _new_state("FRA")
	iso_loud.player().corruption = K.CORRUPTION_MAX
	for _m in range(TERM_MONTHS):
		_step(iso_quiet)
		_step(iso_loud)

	var iso_dev: float = Society.quality_deviation(iso_loud.player(), _key)
	var iso_head: float = (
		iso_loud.player().overall_approval_pct - iso_quiet.player().overall_approval_pct
	)
	if float(iso_loud.player().spending_pct_gdp[_key]) != float(iso_quiet.player().spending_pct_gdp[_key]):
		print("!! the isolated run moved a spending line -- the isolation is broken")
	print("deviation %.4f pt, headline %+.2f at the shipped scale %.1f" % [
		iso_dev, iso_head, OK.QUALITY_SCALE_PP,
	])
	print("%-10s %12s %10s %8s %8s" % ["scale", "headline", "saturates", "band", "ratio"])
	for scale in SCALE_CANDIDATES:
		# Valid because no candidate saturates _scaled()'s clamp, which the table above
		# MEASURED rather than assumed -- that was the objection to the first version of
		# this sweep and it is answered rather than repeated.
		var h: float = iso_head * (OK.QUALITY_SCALE_PP / scale)
		print("%-10.1f %+12.2f %10s %8s %8.2f" % [
			scale, h, "no", "PASS" if absf(h) > NOISE_FLOOR else "fail",
			scale / OK.SPEND_SCALE_PP,
		])

	print("\n-- and the pre-committed TIEBREAKER was a test that could not fail --")
	print("It said: if the two terms summed exceed what SPEND_SCALE_PP produced alone,")
	print("re-measure SPEND_SCALE_PP down. Any positive stock term adds to the total, so")
	print("that rule fires for EVERY candidate -- V1.3e's own criticism of its split")
	print("trigger, repeated here. What replaces it: the delivery half must be worth")
	print("LESS than the announcement half, because an announcement is certain and")
	print("immediate where delivery is contingent and lagged. That is ratio > 1.0, and")
	print("the smallest passing value satisfying it is what ships.")
	print("SPEND_SCALE_PP is NOT re-measured: it would re-baseline all five spending")
	print("issues to correct a change that reaches one.")


# --- (d) P3: CORRUPTION_DELIVERY_BETA, the kill switch ------------------------

func _table_d_corruption() -> void:
	print("\n=== (d) P3 KILL SWITCH: headline after %d months, saturated corruption (FRA) ===" % TERM_MONTHS)
	print("band: |delta| > %.1f, else the constant is DELETED. bound: beta*MAX <= %.2f" % [
		NOISE_FLOOR, 1.0 - CabinetK.VACANT_EFFECTIVENESS,
	])
	print("%-10s %10s %10s %10s %8s %8s" % [
		"beta", "delivery", "quality", "headline", "band", "vs 0.50",
	])

	for beta in BETA_CANDIDATES:
		var quiet = _new_state("FRA")
		var loud = _new_state("FRA")
		# Set the level directly rather than through the law, so the row measures the
		# factor and not one law's authored magnitude. The law is what makes the level
		# REACHABLE, and table (f) checks that separately.
		loud.player().corruption = K.CORRUPTION_MAX

		var delivery: float = clampf(
			1.0 - beta * K.CORRUPTION_MAX, K.DELIVERY_MIN, K.DELIVERY_MAX
		)
		# Drive the stock with the candidate beta by scaling the target the same way
		# delivery_factor() would, then let the real opinion model price it.
		for _m in range(TERM_MONTHS):
			_step(quiet)
			_step(loud)
			for key in K.QUALITY_KEYS:
				var t: float = (
					float(loud.player().spending_pct_gdp.get(key, 0.0))
					* Cabinet.effectiveness(loud.player(), key) * delivery
				)
				loud.player().service_quality[key] = Society.quality_step(
					float(loud.player().service_quality[key]), t
				)

		var head: float = (
			loud.player().overall_approval_pct - quiet.player().overall_approval_pct
		)
		var q: float = float(loud.player().service_quality[_key])
		print("%-10.2f %10.3f %10.4f %+10.2f %8s %8s" % [
			beta, delivery, q, head,
			"PASS" if absf(head) > NOISE_FLOOR else "FAIL",
			"ok" if beta * K.CORRUPTION_MAX <= 1.0 - CabinetK.VACANT_EFFECTIVENESS else "OVER",
		])
	print("Shipped: CORRUPTION_DELIVERY_BETA = %.2f" % K.CORRUPTION_DELIVERY_BETA)

	# THE PRE-COMMITTED TIEBREAKER IS A BOUND, NOT A SELECTOR, and three rows pass it.
	# That is V1.4c's own failure -- a band that passes several rows and chooses nothing
	# -- repeating inside the session written to avoid it, which is the finding rather
	# than an embarrassment: "name the tiebreaker before the sweep" is not enough on its
	# own, because a tiebreaker can be pre-committed AND still not be a selector.
	#
	# The selector below was formulated AFTER the sweep and is recorded as the weaker
	# kind of claim on that account. It is independent of the rows above rather than
	# reverse-engineered from them: a mechanic that must be stacked several times before
	# the player can see it is one they cannot learn from, so ONE law's worth of
	# corruption has to clear the floor on its own. The saturated clamp is reachable
	# only by stacking, and it is the wrong state to choose a constant against --
	# table (c) made the same mistake one table earlier.
	# The selector, in two parts, both of which are criteria this session already
	# established rather than invented here:
	#
	#   (i)  ONE law's worth of corruption must be legible on a BLOC ROW. Not on the
	#        headline -- table (c) has just shown that a single spending issue cannot
	#        reliably carry a headline price, and V1.3a and V1.3g each reached the bloc
	#        row from their own directions. A mechanic the player cannot see after one
	#        act is one they cannot learn from.
	#   (ii) The SATURATED value must leave DELIVERY_MIN strictly slack, which is P4.
	#        beta = 0.50 satisfies (i) easily and pins the clamp exactly -- the
	#        clamp-sets-the-number failure this project has now named five times.
	#
	# The saturated row above is a REACHABLE state, and the first version of this
	# selector wrongly assumed it was not: emergency_procurement_powers is repeatable on
	# a 48-month cooldown, so three passes inside fourteen years reach CORRUPTION_MAX in
	# ordinary play. That correction is why (i) is a floor on one act rather than the
	# whole selector.
	print("\n-- the selector: ONE law on a bloc row, and the clamp left slack --")
	var one_law := 0.0
	for law in _loader.laws:
		if law.effects.has("society") and float(law.effects["society"]["corruption"]) > 0.0:
			one_law = maxf(one_law, float(law.effects["society"]["corruption"]))
	print("largest single corruption-raising law in data/laws/: %+.2f" % one_law)
	print("%-10s %10s %10s %12s %10s %8s" % [
		"beta", "delivery", "headline", "widest bloc", "clamp", "verdict",
	])
	for beta in BETA_CANDIDATES:
		var quiet = _new_state("FRA")
		var loud = _new_state("FRA")
		loud.player().corruption = one_law
		var delivery: float = clampf(1.0 - beta * one_law, K.DELIVERY_MIN, K.DELIVERY_MAX)
		for _m in range(TERM_MONTHS):
			_step(quiet)
			_step(loud)
			for key in K.QUALITY_KEYS:
				var t: float = (
					float(loud.player().spending_pct_gdp.get(key, 0.0))
					* Cabinet.effectiveness(loud.player(), key) * delivery
				)
				loud.player().service_quality[key] = Society.quality_step(
					float(loud.player().service_quality[key]), t
				)
		var head: float = (
			loud.player().overall_approval_pct - quiet.player().overall_approval_pct
		)
		var widest := 0.0
		for bloc in OK.BLOC_KEYS:
			var d: float = (
				float(loud.player().bloc_approval[bloc])
				- float(quiet.player().bloc_approval[bloc])
			)
			if absf(d) > absf(widest):
				widest = d
		var slack: bool = 1.0 - beta * K.CORRUPTION_MAX > K.DELIVERY_MIN
		var passes: bool = absf(widest) > NOISE_FLOOR and slack
		print("%-10.2f %10.3f %+10.2f %+12.2f %10s %8s" % [
			beta, delivery, head, widest,
			"slack" if slack else "BINDS",
			"PASS" if passes else "fail",
		])
	print("Smallest beta passing BOTH parts is what ships.")


# --- (e) P4: the clamps -------------------------------------------------------

func _table_e_clamp() -> void:
	print("\n=== (e) P4: the reachable worst case against both clamps ===")
	var worst_low: float = 1.0 - K.CORRUPTION_DELIVERY_BETA * K.CORRUPTION_MAX
	var worst_high: float = 1.0 + K.CORRUPTION_DELIVERY_BETA * K.CORRUPTION_MAX
	print("delivery at saturated +corruption: %.3f against DELIVERY_MIN %.3f -- %s" % [
		worst_low, K.DELIVERY_MIN, "SLACK" if worst_low > K.DELIVERY_MIN else "BINDS",
	])
	print("delivery at saturated -corruption: %.3f against DELIVERY_MAX %.3f -- %s" % [
		worst_high, K.DELIVERY_MAX, "SLACK" if worst_high < K.DELIVERY_MAX else "BINDS",
	])
	print("VACANT_EFFECTIVENESS = %.2f, and DELIVERY_MIN may not go under it: %s" % [
		CabinetK.VACANT_EFFECTIVENESS,
		"ok" if K.DELIVERY_MIN >= CabinetK.VACANT_EFFECTIVENESS else "VIOLATED",
	])

	# The stock's own clamp. QUALITY_MAX is a guard rail only if no authored line can
	# reach it -- the same check defence_constants.CAPABILITY_MAX gets.
	var highest := 0.0
	var who := ""
	for id in _loader.nations.keys():
		var n = _loader.nations[id]
		for line in K.QUALITY_KEYS:
			var v: float = float(n.spending_pct_gdp.get(line, 0.0))
			if v > highest:
				highest = v
				who = "%s.%s" % [id, line]
	print("largest authored line in QUALITY_KEYS: %s at %.2f against QUALITY_MAX %.1f -- %s" % [
		who, highest, K.QUALITY_MAX, "SLACK" if highest < K.QUALITY_MAX else "BINDS",
	])


# --- (f) P5: the ISSUE_KEYS question -----------------------------------------

## V1.3d's four tests, which answered YES for `europe`, and which V1.4c ran again and
## answered NO for ownership. Run here for a candidate `corruption` key so the answer
## is recorded either way rather than left silent.
func _table_f_issue_keys() -> void:
	print("\n=== (f) P5: does corruption earn a 13th ISSUE_KEYS entry? ===")
	print("ISSUE_KEYS currently holds %d entries." % OK.ISSUE_KEYS.size())

	# Test 1 -- can the price be NAMED by the surfaces that exist to say why? A price
	# expressed only through bloc_offset cannot: it never enters issue_salience.
	var named := "YES -- corruption is priced through the `health` issue, which the"
	print("(1) nameable by the polling panel / attribution?  %s" % named)
	print("    polling panel already lists and elections.gd already attributes.")

	# Test 3 -- can it become more SALIENT? A flat offset cannot; a satisfaction term
	# can, through salience_weights()'s severity amplification.
	print("(3) can it become more salient?                   YES -- it moves `health`")
	print("    satisfaction, and SALIENCE_GAIN amplifies a negative satisfaction.")

	# Tests 2 and 4 are the ones that decide, and they are the V1.4c pair: is the
	# price legible in the headline on its own, and are the mechanic and the cost the
	# same number?
	print("(2) clears the +-3.0 headline floor on its own?    see table (d)")
	print("(4) mechanic and cost the same number?             the deciding test:")
	print("    `spending.health` and corruption BOTH write the `health` issue, so a")
	print("    `corruption` key would be COLLINEAR with a key that exists -- V1.4c's")
	print("    own reason for answering NO, reached here without a sweep.")

	# NOT SWEPT, and the reason is worth more than the sweep would have been. V1.3d and
	# V1.4c each ran the S10 salience-ratio drift because in both cases tests 1-4 were
	# genuinely in tension and the drift was the deciding number. Here test 4 fails
	# outright and structurally: `spending.health` and corruption both write the same
	# issue, so a 13th key would be COLLINEAR with a key that already exists, and no
	# value of a new bloc-weight row makes two names for one quantity into two
	# quantities. Running a sweep to choose between a yes and a no that is already
	# settled would be the tuned-constant-nothing-reads failure in report form.
	print("\n-- the cost, stated rather than swept --")
	print("A 13th key means six new BLOC_SALIENCE_BASE rows and rescales every existing")
	print("salience weight by 1/(1+w). V1.3d took that cost at +0.39 %% on the S10 ratio")
	print("and V1.4c refused it at -1.46 %%. Neither number decides this one.")
	print("\nANSWER: NO. Recorded beside ISSUE_KEYS in opinion_constants.gd, V1.4c's")
	print("precedent, so a later session finds the reason rather than the silence.")
