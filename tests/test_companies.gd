extends SceneTree

## V1.4a. The firm register as a partition of a sector, the subsidy verb, and the
## two channels through which a firm reaches the national economy.
## Model: docs/companies-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen, and
## each one is a property this session's whole shape rests on:
##
##   - both deviation channels read EXACTLY 0.0 -- not approximately -- for a
##     fourteen-year run in which nobody subsidises anybody. That is what lets the
##     entire register go live with the balance harness bit-identical across all
##     fourteen existing regimes, and a test that accepted 1e-9 would not prove it;
##   - a sector's named shares SUM TO THE SAME NUMBER after a subsidy as before it.
##     A subsidised firm takes share from its named rivals and never from the
##     unnamed residual, which is what makes the register additive: a later session
##     naming a seventh firm moves no existing number;
##   - headcount moves with SHARE and not with sector output, so a growing economy
##     does not quietly hire. Read off the level, the jobs channel would be non-zero
##     in every run ever played and would be a second answer to Okun's law;
##   - the seven nations with no companies file run the model they always ran;
##   - a firm's authored share and headcount are CONTENT and are never copied into
##     the register, so there is exactly one baseline and it cannot drift.
##
## V1.4b WIDENS THE FIRST OF THOSE AND SHARPENS THE SECOND. Both channels now read
## exactly 0.0 only while no subsidy stands AND no sector carries a burden -- the
## widening is deliberate and docs/companies-model.md says so. What replaces the
## lost strength is a stronger claim about `share`: a regulation moves both channels
## while leaving every share EXACTLY where the content put it, because share
## movement is the subsidy's persistent channel and a second writer of it would be
## two answers to who is winning the sector.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Companies = preload("res://src/sim/companies.gd")
const K = preload("res://src/sim/companies_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Legislature = preload("res://src/sim/legislature.gd")

const PLAYER := "FRA"
## Two industrial rivals of unequal labour intensity. The pair the jobs channel is
## about: Aurignac employs 112 000 at 0.14 of the sector, Sevrenne 74 000 at 0.10,
## so share moving between them changes total employment.
const BIG := "FRA_aurignac"
const RIVAL := "FRA_sevrenne"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_content_loads()
	_test_register_seeds_from_content()
	_test_unsubsidised_channels_are_exactly_zero()
	_test_a_long_run_stays_exactly_zero()
	_test_nations_without_a_file_are_untouched()
	_test_subsidy_conserves_the_named_share()
	_test_subsidy_moves_share_to_the_subsidised_firm()
	_test_headcount_follows_share_not_output()
	_test_bill_reaches_the_budget()
	_test_impulse_reaches_growth()
	_test_withdraw_stops_the_bill_and_keeps_the_share()
	_test_verb_refuses_when_unavailable()
	_test_rivals_never_fall_below_the_floor()
	_test_the_nine_never_subsidise()
	_test_a_burden_moves_jobs_and_growth_and_no_share()
	_test_a_burden_sheds_staff_without_moving_share()
	_test_deregulation_is_the_other_direction()
	_test_the_burden_clamp_holds_both_ways()
	_test_the_nine_are_never_regulated()
	_finish()


func _new_state():
	return GameState.new_game(_loader, PLAYER)


func _action(id: String):
	for a in _loader.company_actions:
		if a.id == id:
			return a
	return null


# --- Content -------------------------------------------------------------------

func _test_content_loads() -> void:
	if _loader.company_actions.is_empty():
		_fail("no company actions loaded")
	for id in ["industrial_subsidy", "strategic_rescue", "withdraw_support"]:
		if _action(id) == null:
			_fail("company action '%s' is missing" % id)

	# The rule DataLoader._validate_companies() enforces, asserted here as a
	# property of the shipped content rather than only of the checker: a sector with
	# one named firm has no rival to take share from, so a subsidy pointed at it is
	# a sector lever wearing a company's name -- which is what keeps V1.4's subsidy
	# and V1.6's sectoral investment distinguishable.
	for nation_id in _loader.companies.keys():
		var by_sector := {}
		for company in _loader.companies[nation_id]:
			by_sector[company.sector] = int(by_sector.get(company.sector, 0)) + 1
		for sector in by_sector.keys():
			if int(by_sector[sector]) < 2:
				_fail("%s sector '%s' has only one named firm" % [nation_id, sector])


func _test_register_seeds_from_content() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	for company in _loader.companies[PLAYER]:
		if not is_equal_approx(Companies.share_of(ns, company.id), company.share):
			_fail("%s seeded at share %.4f against authored %.4f" % [
				company.id, Companies.share_of(ns, company.id), company.share
			])
		if Companies.subsidy_of(ns, company.id) != 0.0:
			_fail("%s seeded with a subsidy standing" % company.id)

	# The register carries the LIVE half only. A copied baseline would be the same
	# fact in two places, and the copy in the save is the one that would drift.
	for entry in ns.companies.values():
		for key in entry.keys():
			if key != "share" and key != "subsidy":
				_fail("register entry carries '%s' -- the baseline is content, not state" % key)


# --- The zero property ---------------------------------------------------------

func _test_unsubsidised_channels_are_exactly_zero() -> void:
	var state = _new_state()
	Companies.tick_month(state, _loader)
	for id in state.nations.keys():
		var ns = state.nations[id]
		if ns.firm_impulse_pct != 0.0:
			_fail("%s firm_impulse_pct is %s with no subsidy standing, not exactly 0.0" % [
				id, str(ns.firm_impulse_pct)
			])
		if ns.firm_jobs_offset_pct != 0.0:
			_fail("%s firm_jobs_offset_pct is %s with no subsidy standing, not exactly 0.0" % [
				id, str(ns.firm_jobs_offset_pct)
			])
		if ns.subsidy_bill_pct_gdp != 0.0:
			_fail("%s subsidy_bill_pct_gdp is %s with no subsidy standing" % [
				id, str(ns.subsidy_bill_pct_gdp)
			])


## Fourteen years, the balance harness's own horizon. EXACT equality, deliberately:
## the claim V1.4a makes is that the register changes nothing at all until a player
## acts, and `is_zero_approx` would let a slow drift through.
func _test_a_long_run_stays_exactly_zero() -> void:
	var state = _new_state()
	for _m in range(168):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Companies.tick_month(state, _loader)
	for id in state.nations.keys():
		var ns = state.nations[id]
		if ns.firm_impulse_pct != 0.0 or ns.firm_jobs_offset_pct != 0.0:
			_fail("%s drifted off zero over 168 months: impulse %s, jobs %s" % [
				id, str(ns.firm_impulse_pct), str(ns.firm_jobs_offset_pct)
			])

	# And the shares themselves have not moved, which is the stronger half: the
	# channels could read zero because the arithmetic cancels rather than because
	# nothing happened.
	var ns_player = state.nations[PLAYER]
	for company in _loader.companies[PLAYER]:
		if Companies.share_of(ns_player, company.id) != company.share:
			_fail("%s share moved with no subsidy: %s against authored %s" % [
				company.id, str(Companies.share_of(ns_player, company.id)), str(company.share)
			])


func _test_nations_without_a_file_are_untouched() -> void:
	var state = _new_state()
	var found := false
	for id in state.nations.keys():
		if _loader.companies.get(id, []).is_empty():
			found = true
			if not state.nations[id].companies.is_empty():
				_fail("%s has no companies file but a non-empty register" % id)
	if not found:
		_fail("every nation has a companies file, so the absent-file path asserts nothing")


# --- The partition -------------------------------------------------------------

func _named_share(ns, sector: String) -> float:
	var total := 0.0
	for company in Companies.firms_in_sector(_loader, ns.id, sector):
		total += Companies.share_of(ns, company.id)
	return total


func _test_subsidy_conserves_the_named_share() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	var before := _named_share(ns, "industry")

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG)
	for _m in range(60):
		Companies.tick_month(state, _loader)

	var after := _named_share(ns, "industry")
	if absf(after - before) > 0.000001:
		_fail("industry's named share moved from %s to %s -- a subsidy took share from the unnamed residual" % [
			str(before), str(after)
		])


func _test_subsidy_moves_share_to_the_subsidised_firm() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	var big_before := Companies.share_of(ns, BIG)
	var rival_before := Companies.share_of(ns, RIVAL)

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG)
	for _m in range(24):
		Companies.tick_month(state, _loader)

	if Companies.share_of(ns, BIG) <= big_before:
		_fail("a subsidised firm did not gain share over two years")
	if Companies.share_of(ns, RIVAL) >= rival_before:
		_fail("the unsubsidised rival did not lose share")


## The call the whole jobs channel rests on. If headcount were read off the sector
## LEVEL, a firm would hire every month the economy grew -- which is a second answer
## to the Okun term in Economy._update_unemployment() and would make
## firm_jobs_offset_pct non-zero in every run ever played.
func _test_headcount_follows_share_not_output() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	var company = _loader.companies[PLAYER][2]
	var before := Companies.headcount(ns, company)

	# Double the sector without touching a single share.
	ns.sector_output[company.sector] = float(ns.sector_output[company.sector]) * 2.0

	if not is_equal_approx(Companies.headcount(ns, company), before):
		_fail("headcount moved when the sector doubled and no share changed")
	if Companies.output_eur_bn(ns, company) <= 0.0:
		_fail("output did not follow the sector, which it must")


# --- The three prices ----------------------------------------------------------

func _test_bill_reaches_the_budget() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	var deficit_before: float = ns.deficit_pct_gdp

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG)
	Companies.tick_month(state, _loader)
	Budget.recompute(state, ns)

	if not is_equal_approx(ns.subsidy_bill_pct_gdp, K.SUBSIDY_COST_PCT_GDP):
		_fail("one full-intensity subsidy billed %s, expected %s" % [
			str(ns.subsidy_bill_pct_gdp), str(K.SUBSIDY_COST_PCT_GDP)
		])
	if ns.deficit_pct_gdp <= deficit_before:
		_fail("the subsidy bill did not widen the deficit")


func _test_impulse_reaches_growth() -> void:
	var quiet = _new_state()
	var subsidised = _new_state()
	Companies.execute(
		subsidised, subsidised.nations[PLAYER], _loader.company_actions,
		_action("strategic_rescue"), BIG
	)
	Companies.tick_month(subsidised, _loader)

	for _m in range(12):
		Economy.tick_month(quiet)
		Economy.tick_month(subsidised)
		Companies.tick_month(subsidised, _loader)

	if subsidised.nations[PLAYER].firm_impulse_pct <= 0.0:
		_fail("a standing subsidy produced no growth impulse")
	if subsidised.nations[PLAYER].gdp_eur_bn <= quiet.nations[PLAYER].gdp_eur_bn:
		_fail("a year of subsidy left GDP no higher than the quiet run")


func _test_withdraw_stops_the_bill_and_keeps_the_share() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG)
	for _m in range(36):
		Companies.tick_month(state, _loader)
	var won := Companies.share_of(ns, BIG)

	Companies.execute(state, ns, _loader.company_actions, _action("withdraw_support"), BIG)
	Companies.tick_month(state, _loader)

	if ns.subsidy_bill_pct_gdp != 0.0:
		_fail("withdrawing left a bill of %s" % str(ns.subsidy_bill_pct_gdp))
	if ns.firm_impulse_pct != 0.0:
		_fail("withdrawing left a growth impulse of %s" % str(ns.firm_impulse_pct))
	# The persistent channel, and the reason this layer is not decorative: the firm
	# out-competed its rivals with public money and the market position is real.
	if not is_equal_approx(Companies.share_of(ns, BIG), won):
		_fail("the share won under subsidy was handed back when the money stopped")
	# The jobs it bought are still there too, so the deviation channel stays live
	# after the bill has stopped -- which is what makes the decision have a tail.
	if ns.firm_jobs_offset_pct == 0.0:
		_fail("the jobs the subsidy bought vanished with the subsidy")


# --- Refusals and floors -------------------------------------------------------

func _test_verb_refuses_when_unavailable() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]

	# Withdrawing from a firm with no subsidy: `subsidy_active == 1` is unmet.
	var refused := Companies.execute(
		state, ns, _loader.company_actions, _action("withdraw_support"), BIG
	)
	if refused.get("applied", true) or not refused.get("refused", false):
		_fail("withdrawing support from an unsubsidised firm was applied")

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG)
	# And subsidising twice: `subsidy_active == 0` is now unmet, so going from the
	# smaller package to the larger one costs a withdrawal first.
	var twice := Companies.execute(
		state, ns, _loader.company_actions, _action("industrial_subsidy"), BIG
	)
	if twice.get("applied", true):
		_fail("a second subsidy was stacked on a firm that already had one")


func _test_rivals_never_fall_below_the_floor() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG)
	# Far longer than a game: the floor has to hold under a subsidy nobody ever
	# withdraws, because that is the run in which it would be found broken.
	for _m in range(600):
		Companies.tick_month(state, _loader)

	for company in _loader.companies[PLAYER]:
		var share := Companies.share_of(ns, company.id)
		# The RELATIVE floor the probe forced into the model: a rival keeps at least
		# half of what it was authored with, so a two-firm sector can never collapse
		# into a one-firm sector -- which would hand V1.4b and V1.4c a register whose
		# rivals had already been driven out.
		if share < K.RIVAL_FLOOR_FRACTION * company.share - 0.000001:
			_fail("%s fell to %s, below half its authored share of %s" % [
				company.id, str(share), str(company.share)
			])
		if share > K.SHARE_MAX + 0.000001:
			_fail("%s rose to %s, above SHARE_MAX" % [company.id, str(share)])


## The nine have no budget and no verb reaches them, so their registers sit still
## for a full run. Stated as a property rather than left to a comment, which is the
## call tests/test_defence.gd made for capability.
func _test_the_nine_never_subsidise() -> void:
	var state = _new_state()
	for _m in range(168):
		Companies.tick_month(state, _loader)
	for id in state.nations.keys():
		if String(id) == PLAYER:
			continue
		var ns = state.nations[id]
		for company_id in ns.companies.keys():
			if Companies.subsidy_of(ns, String(company_id)) != 0.0:
				_fail("%s subsidised %s with no player behind it" % [id, company_id])


# --- V1.4b: the sector burden ---------------------------------------------------

## Every `business` law in data/laws/, applied to the player without a vote.
## Legislature.apply() rather than propose(), for tests/test_balance.gd's reason:
## the division is tests/test_legislature.gd's subject, and an assertion that only
## holds when the assembly agrees asserts nothing on the month it does not.
func _apply_business_laws(state, ns, only_id := "") -> int:
	var applied := 0
	for law in _loader.laws:
		if law.theme != "business":
			continue
		if only_id != "" and law.id != only_id:
			continue
		Legislature.apply(state, ns, law, _loader)
		applied += 1
	return applied


## THE SESSION'S CENTRAL PROPERTY. A regulation is sector-wide and a subsidy is
## firm-targeted, so a burden must move both channels while leaving every share
## exactly where the content put it. Exact equality, not is_equal_approx: share
## movement is the subsidy's persistent channel and "nearly unmoved" is a second
## writer of it that a tolerance would hide.
func _test_a_burden_moves_jobs_and_growth_and_no_share() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	if _apply_business_laws(state, ns, "emissions_standards") != 1:
		_fail("emissions_standards did not load, so the burden tests assert nothing")
		return

	for _m in range(24):
		Companies.tick_month(state, _loader)

	if Companies.regulation_burden_of(ns, "industry") <= 0.0:
		_fail("a passed regulation left industry's burden at %s" % [
			str(Companies.regulation_burden_of(ns, "industry"))
		])
	if ns.firm_impulse_pct >= 0.0:
		_fail("a burden on industry left firm_impulse_pct at %s, not negative" % [
			str(ns.firm_impulse_pct)
		])
	if ns.firm_jobs_offset_pct <= 0.0:
		_fail("a burden on industry left firm_jobs_offset_pct at %s, not positive" % [
			str(ns.firm_jobs_offset_pct)
		])
	if ns.subsidy_bill_pct_gdp != 0.0:
		_fail("a regulation billed the treasury %s -- a burden falls on firms, not on the budget" % [
			str(ns.subsidy_bill_pct_gdp)
		])

	for company in _loader.companies[PLAYER]:
		if Companies.share_of(ns, company.id) != company.share:
			_fail("%s share moved under a regulation: %s against authored %s" % [
				company.id, str(Companies.share_of(ns, company.id)), str(company.share)
			])


## The burden reaches jobs through headcount() and therefore through the SAME
## channel a subsidy reaches, which is what makes V1.4b two lines rather than a
## second machine. Asserted on the firm rather than only on the aggregate, because
## the aggregate could move for the reason V1.4a's reallocation moves it.
func _test_a_burden_sheds_staff_without_moving_share() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	var big = _company(BIG)
	var before := Companies.headcount(ns, big)
	if before != big.headcount:
		_fail("%s did not start at its authored headcount" % BIG)
		return

	_apply_business_laws(state, ns, "emissions_standards")
	var after := Companies.headcount(ns, big)
	if after >= before:
		_fail("%s carried %s staff under a burden, against %s before it" % [
			BIG, str(after), str(before)
		])
	if Companies.share_of(ns, BIG) != big.share:
		_fail("%s share moved when only its headcount should have" % BIG)


## Deregulation is the negative direction on the same register, not a repeal verb.
## The burden must be able to come back down, and past zero: without that a burden
## is a permanent monotone charge and REGULATION_BURDEN_MAX stops being a guard
## rail and becomes the number -- docs/defence-model.md's own finding.
func _test_deregulation_is_the_other_direction() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	_apply_business_laws(state, ns, "emissions_standards")
	var regulated := Companies.regulation_burden_of(ns, "industry")

	_apply_business_laws(state, ns, "industrial_deregulation")
	var after := Companies.regulation_burden_of(ns, "industry")
	if after >= regulated:
		_fail("deregulation left industry's burden at %s against %s before it" % [
			str(after), str(regulated)
		])

	# And it runs past zero rather than flooring there.
	_apply_business_laws(state, ns, "industrial_deregulation")
	_apply_business_laws(state, ns, "industrial_deregulation")
	if Companies.regulation_burden_of(ns, "industry") >= 0.0:
		_fail("three deregulations could not take industry below an unregulated 0.0")

	Companies.tick_month(state, _loader)
	if ns.firm_impulse_pct <= 0.0:
		_fail("a deregulated industry gave no growth impulse: %s" % [str(ns.firm_impulse_pct)])


## Every authored burden stacks into one clamp, and the clamp holds in both
## directions. The magnitude test the constant exists for.
func _test_the_burden_clamp_holds_both_ways() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	for _i in range(20):
		_apply_business_laws(state, ns)
	for sector in EK.SECTOR_TREND.keys():
		var burden := Companies.regulation_burden_of(ns, String(sector))
		if absf(burden) > K.REGULATION_BURDEN_MAX + 1e-9:
			_fail("%s burden reached %s, past REGULATION_BURDEN_MAX %s" % [
				sector, str(burden), str(K.REGULATION_BURDEN_MAX)
			])

	# Every firm still holds exactly its authored share after twenty rounds of every
	# rule in the file: nothing on this path may reach the partition.
	for company in _loader.companies[PLAYER]:
		if Companies.share_of(ns, company.id) != company.share:
			_fail("%s share moved under a saturated burden" % company.id)


## A regulation is a LAW, so the nine -- who have no assembly the player can move
## and no autonomous agent that passes one -- must stay at zero burden for a full
## run. The property that keeps the balance harness bit-identical.
func _test_the_nine_are_never_regulated() -> void:
	var state = _new_state()
	for _m in range(168):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Companies.tick_month(state, _loader)
	for id in state.nations.keys():
		var ns = state.nations[id]
		if not ns.regulation_burden.is_empty():
			_fail("%s carries a burden with no law behind it: %s" % [id, str(ns.regulation_burden)])


func _company(company_id: String):
	for company in _loader.companies[PLAYER]:
		if company.id == company_id:
			return company
	return null


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_companies: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
