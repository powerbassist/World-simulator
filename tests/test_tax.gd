extends SceneTree

## Headless test: godot --headless --script res://tests/test_tax.gd
## Non-zero exit on any failure.
##
## V1.6d. The fourth and fifth taxes, the bracket lever, and the discharge of
## docs/unrest-model.md's declared Gini stopgap. Behavioural checks plus the
## architectural ones read off the source -- docs/credit-model.md's idiom one session on.
##
## The architectural checks are what stop a later session quietly undoing this session's
## decisions: every new channel reads EXACTLY 0.0 at new game (so the re-baseline stays
## bounded and the existing regimes stay reachable-identical), src/sim/tax.gd is
## STATELESS (so the distribution never grows an accumulator), brackets write NO revenue
## line of their own (so section 6's "without a fourth revenue channel" is a check rather
## than a sentence), the erosion curve BITES on a tax invented from nothing (so the
## zero-rate exploit stays closed), and the model bound and the panel's own control
## cannot drift apart.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const Tax = preload("res://src/sim/tax.gd")
const K = preload("res://src/sim/tax_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")
const TaxPanel = preload("res://src/ui/tax_panel.gd")

const START_YEAR := 2026

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_five_taxes_and_the_tables_agree()
	_check_zero_at_new_game()
	_check_the_residual_absorbs_the_two_new_taxes()
	_check_brackets_write_no_revenue_line()
	_check_brackets_cost_revenue_through_the_base()
	_check_the_zero_rate_erosion_bites()
	_check_the_base_factor_has_one_formula()
	_check_progressivity_is_bounded()
	_check_the_wealth_lever_matches_the_model_bound()
	_check_the_wealth_scale_is_not_incomes()
	_check_the_policy_offset_moves_both_ways()
	_check_the_offset_is_blind_to_what_section_6_does_not_own()
	_check_the_clamp_is_slack_on_a_reachable_budget()
	_check_stateless()
	_check_preloads()

	_finish()


## Five keys, and every table keyed by tax has all five. A missing entry is a crash at the
## first tick rather than a wrong number, but the check is cheap and it is the one that
## catches a sixth tax added to TAX_KEYS alone.
func _check_five_taxes_and_the_tables_agree() -> void:
	if C.TAX_KEYS.size() != 5:
		_fail("TAX_KEYS has %d entries -- docs/tiers/v1.md section 6's target is five taxes" % C.TAX_KEYS.size())
	for key in C.TAX_KEYS:
		if not C.TAX_BASE_SHARE.has(key):
			_fail("economy_constants.TAX_BASE_SHARE has no entry for the tax '%s'" % key)
		if not C.TAX_EROSION.has(key):
			_fail("economy_constants.TAX_EROSION has no entry for the tax '%s'" % key)
		if not C.MULT_TAX.has(key):
			_fail("economy_constants.MULT_TAX has no entry for the tax '%s'" % key)
		if not C.EROSION_ZERO_REF_PCT.has(key):
			_fail("economy_constants.EROSION_ZERO_REF_PCT has no entry for the tax '%s'" % key)
		# opinion.gd writes sat["tax_%s"] for every TAX_KEYS entry, so a key with no
		# ISSUE_KEYS entry is a satisfaction nothing reads -- docs/diplomacy-model.md's
		# named failure. This is the check that makes "add the tax but not the issue"
		# impossible to do quietly.
		if not OpinionK.ISSUE_KEYS.has("tax_%s" % key):
			_fail("the tax '%s' has no ISSUE_KEYS entry, so opinion.gd computes a satisfaction nothing reads" % key)
		# AT LEAST ONE BLOC, not all six, and the first draft of this check demanded all
		# six -- which contradicts the model rather than merely over-testing it.
		# BLOC_SALIENCE_BASE is sparse ON PURPOSE: its own comment says an issue a bloc
		# has no entry for carries no weight for that bloc, and that sparsity is what
		# makes "fixing something nobody cares about buys nothing" true. `tax_corporate`
		# has appeared in exactly one row since S5. What must not happen is a tax NO row
		# mentions, because then the satisfaction reaches no weight anywhere and the
		# ISSUE_KEYS entry above is a label on a number nothing reads.
		var weighted_by := 0
		for bloc in OpinionK.BLOC_KEYS:
			var row: Dictionary = OpinionK.BLOC_SALIENCE_BASE[bloc]
			if row.has("tax_%s" % key):
				weighted_by += 1
		if weighted_by == 0:
			_fail("no bloc weights the tax '%s' at all, so its satisfaction reaches no approval score anywhere" % key)


## EXACTLY 0.0 for all ten, and exact equality rather than is_zero_approx(), because this
## is what keeps the twenty-nine existing balance regimes reachable-identical and every
## figure this project has measured against a three-tax world still meaningful.
## `trade_baseline_by_partner`'s idiom, the cycle's, inflation's, and the bond spread's
## at V1.6c.
func _check_zero_at_new_game() -> void:
	for nation_id in ["FRA", "DEU", "GBR"]:
		var ns = _new_state(nation_id).player()
		if Tax.progressivity_deviation(ns) != 0.0:
			_fail("%s starts with a non-zero bracket deviation: %.17f" % [nation_id, Tax.progressivity_deviation(ns)])
		if Tax.gini_policy_offset(ns) != 0.0:
			_fail("%s starts with a non-zero Gini policy offset: %.17f" % [nation_id, Tax.gini_policy_offset(ns)])
		if Tax.progressivity_base_factor(ns) != 1.0:
			_fail("%s starts with a base factor that is not exactly 1.0: %.17f" % [nation_id, Tax.progressivity_base_factor(ns)])


## The two new taxes come out of the residual rather than out of thin air, which is what
## makes total revenue at new game the nation's own authored figure and not that figure
## plus a windfall. GameState calibrates `other_revenue_pct_gdp` against
## modelled_revenue_total(), so this is that calibration surviving the two extra keys --
## and it is the reason the balance harness could be re-run at all.
func _check_the_residual_absorbs_the_two_new_taxes() -> void:
	for nation_id in ["FRA", "CHE", "NLD"]:
		var ns = _new_state(nation_id).player()
		var authored: float = float(_loader.nations[nation_id].tax_revenue_pct_gdp)
		if absf(ns.total_revenue_pct_gdp - authored) > 0.001:
			_fail("%s collects %.4f at new game against an authored %.4f -- the two new taxes are not coming out of the residual" % [nation_id, ns.total_revenue_pct_gdp, authored])
		if ns.other_revenue_pct_gdp < 0.0:
			_fail("%s's revenue residual went negative once the two new taxes were modelled" % nation_id)


## Brackets are NOT a fourth revenue channel, which is what docs/tiers/v1.md section 6
## asks for in those words. There is no `progressivity` entry in the revenue dictionary
## and there never should be: the whole of its revenue price is a coefficient inside the
## income line.
func _check_brackets_write_no_revenue_line() -> void:
	var state = _new_state("FRA")
	Budget.commit(state, {"tax_progressivity": K.PROGRESSIVITY_MAX})
	var ns = state.player()
	for forbidden in ["progressivity", "tax_progressivity", "brackets"]:
		if ns.revenue_pct_gdp.has(forbidden):
			_fail("committing a bracket change created a '%s' revenue line -- section 6's 'without a fourth revenue channel' is broken" % forbidden)
	if ns.revenue_pct_gdp.size() != C.TAX_KEYS.size() + 3:
		_fail("the revenue dictionary has %d lines against five taxes plus other, tariffs and dividends" % ns.revenue_pct_gdp.size())


## A steeper schedule collects LESS at the same headline rate, and a flatter one more.
## That is progressivity's first price and the reason it needs no channel of its own.
## Every other revenue line must be untouched -- the factor multiplies the income
## coefficient and nothing else's.
func _check_brackets_cost_revenue_through_the_base() -> void:
	var flat = _new_state("FRA")
	var steep = _new_state("FRA")
	Budget.commit(flat, {"tax_progressivity": K.PROGRESSIVITY_BASE - 0.5})
	Budget.commit(steep, {"tax_progressivity": K.PROGRESSIVITY_BASE + 0.5})

	var flat_income: float = float(flat.player().revenue_pct_gdp["income"])
	var steep_income: float = float(steep.player().revenue_pct_gdp["income"])
	if not (steep_income < flat_income):
		_fail("a steeper income schedule collected %.4f against a flatter one's %.4f -- the base price is missing or backwards" % [steep_income, flat_income])

	for key in C.TAX_KEYS:
		if key == "income":
			continue
		if float(steep.player().revenue_pct_gdp[key]) != float(flat.player().revenue_pct_gdp[key]):
			_fail("moving the income brackets moved the '%s' line -- the factor is reaching taxes it has no business in" % key)


## THE EXPLOIT THIS SESSION'S CONTENT MADE REACHABLE, closed and pinned. Budget._erosion()
## divided by the nation's own starting rate and returned a flat 1.0 when that was zero,
## so revenue was LINEAR IN THE RATE FOREVER for any tax the nation does not levy -- and
## Switzerland taxes no private capital gain, while eight of the ten start with no wealth
## tax at all. Left alone, the player's best move is to invent a tax and take it to the
## ceiling. The curve must bite, so doubling a rate from a zero start must collect less
## than twice as much.
func _check_the_zero_rate_erosion_bites() -> void:
	for pair in [["CHE", "capital_gains", 10.0], ["FRA", "wealth", 0.5]]:
		var nation_id: String = pair[0]
		var key: String = pair[1]
		var rate: float = pair[2]

		var start = _new_state(nation_id).player()
		if float(start.start_tax_rates_pct[key]) != 0.0:
			_fail("%s's starting %s rate is not zero, so this check is not measuring what it says" % [nation_id, key])
			continue

		var single = _new_state(nation_id)
		var double = _new_state(nation_id)
		Budget.commit(single, {"tax_rates_pct": {key: rate}})
		Budget.commit(double, {"tax_rates_pct": {key: rate * 2.0}})
		var one: float = float(single.player().revenue_pct_gdp[key])
		var two: float = float(double.player().revenue_pct_gdp[key])
		if one <= 0.0:
			_fail("%s's invented %s tax collects nothing at all at %.2f points" % [nation_id, key, rate])
			continue
		if two >= one * 2.0:
			_fail("%s's invented %s tax is still linear: %.4f at %.2f points against %.4f at %.2f -- the zero-rate erosion branch is not biting" % [nation_id, key, one, rate, two, rate * 2.0])


## One formula, one place. Budget.commit() needs the factor for a schedule that is not on
## the state yet, and the first version of this session inlined the expression there --
## two writers of one formula, which is exactly the discipline `share`, `state_share`,
## `regulation_burden` and `gini_index` are each held to a level up.
func _check_the_base_factor_has_one_formula() -> void:
	var ns = _new_state("FRA").player()
	ns.tax_progressivity = 1.7
	var live := Tax.progressivity_base_factor(ns)
	var at := Tax.base_factor_at(1.7, float(ns.start_tax_progressivity))
	if live != at:
		_fail("progressivity_base_factor() and base_factor_at() disagree at the live schedule: %.17f against %.17f" % [live, at])


## Commit clamps, and the read clamps again. The second is not redundant: a save may carry
## a value from outside the band, and an ABSENT field reads 0.0, which is
## PROGRESSIVITY_MIN rather than a neutral default.
func _check_progressivity_is_bounded() -> void:
	var state = _new_state("FRA")
	Budget.commit(state, {"tax_progressivity": 99.0})
	if state.player().tax_progressivity > K.PROGRESSIVITY_MAX:
		_fail("commit() let the bracket index past PROGRESSIVITY_MAX: %.3f" % state.player().tax_progressivity)
	Budget.commit(state, {"tax_progressivity": -99.0})
	if state.player().tax_progressivity < K.PROGRESSIVITY_MIN:
		_fail("commit() let the bracket index below PROGRESSIVITY_MIN: %.3f" % state.player().tax_progressivity)

	var ns = _new_state("FRA").player()
	ns.tax_progressivity = 500.0
	if Tax.progressivity(ns) != K.PROGRESSIVITY_MAX:
		_fail("a state carrying an out-of-band schedule was not clamped on read")


## The model bound and the control cannot drift apart. tax_panel.LEVER_MAX reads
## economy_constants.WEALTH_RATE_MAX_PCT rather than authoring 3.0 a second time, and this
## is the check that keeps it that way. V4.2 T5 moved the tax levers off
## budget_panel into their own surface, so the identity moved with them -- and
## the old panel staying clean of tax keys is pinned beside it, so a lever
## cannot quietly grow back in two places.
func _check_the_wealth_lever_matches_the_model_bound() -> void:
	if float(TaxPanel.LEVER_MAX["wealth"]) != C.WEALTH_RATE_MAX_PCT:
		_fail("the wealth slider runs to %.2f against a model bound of %.2f" % [float(TaxPanel.LEVER_MAX["wealth"]), C.WEALTH_RATE_MAX_PCT])
	if float(TaxPanel.LEVER_MAX[TaxPanel.PROGRESSIVITY_KEY]) != K.PROGRESSIVITY_MAX:
		_fail("the bracket slider and PROGRESSIVITY_MAX disagree")
	for key in C.TAX_KEYS:
		if BudgetPanel.LEVER_MAX.has(key) or BudgetPanel.LEVER_LABELS.has(key):
			_fail("budget_panel still carries the '%s' tax lever the Tax Code window owns" % key)


## THE UNITS DECISION, PINNED. A wealth rate is not on income's scale -- its whole
## reachable span is three points against income's seventy -- so sharing TAX_SCALE_PP
## would make the largest wealth tax in Europe read as a fraction of a satisfaction. The
## check is that the wealth scale sits well inside the reachable lever, so a real wealth
## tax can actually saturate its issue.
func _check_the_wealth_scale_is_not_incomes() -> void:
	var scale: float = float(OpinionK.TAX_SCALE_PP_BY_KEY.get("wealth", OpinionK.TAX_SCALE_PP))
	if scale >= C.WEALTH_RATE_MAX_PCT:
		_fail("the wealth issue saturates at %.2f points against a lever that only reaches %.2f -- it can never saturate" % [scale, C.WEALTH_RATE_MAX_PCT])
	if scale == OpinionK.TAX_SCALE_PP:
		_fail("the wealth issue shares income's rate scale, which is the units error TAX_SCALE_PP_BY_KEY exists to fix")
	# And the remaining S5 measured must be untouched by the table existing at all.
	# V3.0 deliberately ends this for `income`: the agency probe (V2.9b F1)
	# measured the fiscal pain against the public_finances credit and income's
	# rate scale is the lever that re-weighted it — the sweep is recorded in
	# docs/opinion-model.md and BALANCE_PLAN.md's band table. Corporate and vat
	# remain on the shared constant, and the bar for adding a key stays what it
	# was: a per-key override must carry its own measured scale, not a taste.
	for key in ["corporate", "vat"]:
		if OpinionK.TAX_SCALE_PP_BY_KEY.has(key):
			_fail("'%s' gained a per-key scale override, so the constant S5 measured no longer describes it" % key)
	if float(OpinionK.TAX_SCALE_PP_BY_KEY.get("income", OpinionK.TAX_SCALE_PP)) <= OpinionK.TAX_SCALE_PP:
		_fail("income's per-key scale (%s) does not exceed the shared constant (%s) — the V3.0 re-weight made income pain WEAKER than the S5 default, not stronger" % [
			OpinionK.TAX_SCALE_PP_BY_KEY.get("income", OpinionK.TAX_SCALE_PP), OpinionK.TAX_SCALE_PP])


## THE DISCHARGE. All three of section 6's instruments must move the effective index, and
## in the right direction: redistributing lowers it.
func _check_the_policy_offset_moves_both_ways() -> void:
	var base = _new_state("FRA")
	var baseline := Unrest.inequality_deviation(base.player())

	var cases := {
		"steeper brackets": {"tax_progressivity": K.PROGRESSIVITY_BASE + 0.5},
		"a higher capital-gains rate": {"tax_rates_pct": {"capital_gains": 45.0}},
		"a wealth tax": {"tax_rates_pct": {"wealth": 1.0}},
	}
	for label in cases:
		var state = _new_state("FRA")
		Budget.commit(state, cases[label])
		var moved := Unrest.inequality_deviation(state.player())
		if not (moved < baseline):
			_fail("%s did not lower the inequality index (%.4f against %.4f) -- section 6's stopgap is not discharged" % [label, moved, baseline])

	# Signed both ways, which is docs/companies-model.md's deregulation argument: a
	# FLATTER schedule must raise it, or the instrument is a one-way ratchet and every
	# regressive budget is politically free.
	var flatter = _new_state("FRA")
	Budget.commit(flatter, {"tax_progressivity": K.PROGRESSIVITY_BASE - 0.5})
	if not (Unrest.inequality_deviation(flatter.player()) > baseline):
		_fail("flattening the brackets did not raise the inequality index, so the instrument is one-directional")


## THE TWO THIRDS OF V1.5c's ASSERTION THAT SURVIVES. Section 6 owns brackets, capital
## gains and wealth -- and nothing else. A state holding, a sector burden and the
## CORPORATE rate are all outside that list, docs/companies-model.md refused an ownership
## channel into the distribution by name, and the index stays exactly blind to all three.
func _check_the_offset_is_blind_to_what_section_6_does_not_own() -> void:
	var base = _new_state("FRA")
	var mutated = _new_state("FRA")
	var ns = mutated.player()
	ns.tax_rates_pct["corporate"] = 60.0
	for firm_id in ns.companies:
		(ns.companies[firm_id] as Dictionary)["state_share"] = 1.0
	for sector in ns.regulation_burden:
		ns.regulation_burden[sector] = 1.0

	if Tax.gini_policy_offset(ns) != Tax.gini_policy_offset(base.player()):
		_fail("the corporate rate, a state holding or a sector burden moved the Gini policy offset -- section 6's instrument list is brackets, capital gains and wealth")


## docs/defence-model.md's and docs/companies-model.md's treatment of their own clamps: if
## the reachable stack sits ON the clamp, the clamp and not the model is setting the
## number. Measured on the largest redistributive budget a player can actually commit.
func _check_the_clamp_is_slack_on_a_reachable_budget() -> void:
	var state = _new_state("FRA")
	Budget.commit(state, {
		"tax_progressivity": K.PROGRESSIVITY_MAX,
		"tax_rates_pct": {"capital_gains": 60.0, "wealth": C.WEALTH_RATE_MAX_PCT},
	})
	var offset := absf(Tax.gini_policy_offset(state.player()))
	if offset >= K.GINI_POLICY_MAX_PT:
		_fail("the most redistributive reachable budget sits ON GINI_POLICY_MAX_PT (%.3f of %.3f) -- the clamp and not the model is setting the number" % [offset, K.GINI_POLICY_MAX_PT])


## STATELESS, read off the source. No tick_month(), and nothing in this file assigns to a
## NationState -- which is what keeps the whole distribution a derived read and the save
## format free of it. src/sim/credit.gd's check at V1.6c, one session on.
func _check_stateless() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/tax.gd")
	if src == "":
		_fail("could not read src/sim/tax.gd")
		return
	for line in src.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.begins_with("static func tick_month") or stripped.begins_with("func tick_month"):
			_fail("tax.gd grew a tick_month() -- the distribution is a derived read, and a stateful one needs a save field and a session to say why")
		if stripped.begins_with("ns.") and stripped.contains("="):
			_fail("tax.gd assigns to a NationState: %s" % stripped)


## A LEAF. Two constants files and nothing else, which is what lets unrest.gd preload it
## without reopening the dependency graph -- tests/test_unrest.gd checks the same property
## from the other side, because that file's whole preload argument depends on it.
func _check_preloads() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/tax.gd")
	for line in src.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("const") or not stripped.contains("preload("):
			continue
		if not stripped.contains("_constants.gd"):
			_fail("tax.gd preloads a non-constants file and is no longer a leaf: %s" % stripped)


func _new_state(nation_id: String):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	return state


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_tax: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr(message)
	printerr("test_tax: %d check(s) failed" % _failures.size())
	quit(1)
