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
	_test_unowned_dividend_is_exactly_zero()
	_test_nationalising_pays_the_debt_and_not_the_deficit()
	_test_a_holding_pays_a_dividend_and_privatising_stops_it()
	_test_ownership_shields_jobs_in_both_directions()
	_test_no_law_ever_moves_state_share()
	_test_ownership_verbs_refuse_when_unavailable()
	_test_the_nine_never_nationalise()
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

	# The rule CompaniesLoader.validate_companies() enforces, asserted here as a
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
	# V4.7a: MAJORS only. The sparse register seeds majors and leaves body
	# firms out until something touches them -- an untouched body firm reading
	# its authored share is share_of_company's fallback, not a register entry,
	# and iterating the whole roster here would demand density the design
	# refuses.
	for company in _loader.companies[PLAYER]:
		if not Companies.is_major(company):
			continue
		if not is_equal_approx(Companies.share_of(ns, company.id), company.share):
			_fail("%s seeded at share %.4f against authored %.4f" % [
				company.id, Companies.share_of(ns, company.id), company.share
			])
		if Companies.subsidy_of(ns, company.id) != 0.0:
			_fail("%s seeded with a subsidy standing" % company.id)

		if Companies.state_share_of(ns, company.id) != 0.0:
			_fail("%s seeded already in public hands" % company.id)

	# The register carries the LIVE half only. A copied baseline would be the same
	# fact in two places, and the copy in the save is the one that would drift.
	# Three keys since V1.4c, and three writers -- one apiece.
	for entry in ns.companies.values():
		for key in entry.keys():
			if not ["share", "subsidy", "state_share"].has(key):
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
	# V4.7a: the fallback read again -- see the regulation check above.
	for company in _loader.companies[PLAYER]:
		if Companies.share_of_company(ns_player, company) != company.share:
			_fail("%s share moved with no subsidy: %s against authored %s" % [
				company.id, str(Companies.share_of_company(ns_player, company)), str(company.share)
			])


func _test_nations_without_a_file_are_untouched() -> void:
	# V4.7a rewrote this check: A3's content gives every nation a companies
	# file, so the "find a fileless nation" premise is dead -- a GOOD problem,
	# but the loader's absent-file legality still needs covering. The path is
	# exercised directly now: _load_companies on an id with no file yields an
	# empty list and no error, which is the whole contract.
	_loader._load_companies("ZZZ_absent_probe", "res://data/companies")
	if not _loader.companies.get("ZZZ_absent_probe", []).is_empty():
		_fail("an absent companies file did not read as an empty list")
	var direct_errors := 0
	for e in _loader.errors:
		if String(e).find("ZZZ_absent_probe") != -1:
			direct_errors += 1
	if direct_errors > 0:
		_fail("an absent companies file produced %d load error(s)" % direct_errors)



# --- The partition -------------------------------------------------------------

func _named_share(ns, sector: String) -> float:
	# V4.7a: the fallback read -- the named partition includes body firms,
	# whose register-absent entries still hold their authored share.
	var total := 0.0
	for company in Companies.firms_in_sector(_loader, ns.id, sector):
		total += Companies.share_of_company(ns, company)
	return total


func _test_subsidy_conserves_the_named_share() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	var before := _named_share(ns, "industry")

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG, _loader)
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

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG, _loader)
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

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG, _loader)
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
		_action("strategic_rescue"), BIG, _loader
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

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG, _loader)
	for _m in range(36):
		Companies.tick_month(state, _loader)
	var won := Companies.share_of(ns, BIG)

	Companies.execute(state, ns, _loader.company_actions, _action("withdraw_support"), BIG, _loader)
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
		state, ns, _loader.company_actions, _action("withdraw_support"), BIG, _loader
	)
	if refused.get("applied", true) or not refused.get("refused", false):
		_fail("withdrawing support from an unsubsidised firm was applied")

	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG, _loader)
	# And subsidising twice: `subsidy_active == 0` is now unmet, so going from the
	# smaller package to the larger one costs a withdrawal first.
	var twice := Companies.execute(
		state, ns, _loader.company_actions, _action("industrial_subsidy"), BIG, _loader
	)
	if twice.get("applied", true):
		_fail("a second subsidy was stacked on a firm that already had one")


func _test_rivals_never_fall_below_the_floor() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Companies.execute(state, ns, _loader.company_actions, _action("strategic_rescue"), BIG, _loader)
	# Far longer than a game: the floor has to hold under a subsidy nobody ever
	# withdraws, because that is the run in which it would be found broken.
	for _m in range(600):
		Companies.tick_month(state, _loader)

	for company in _loader.companies[PLAYER]:
		# V4.7a: the fallback read again -- the floor binds on the firm's true
		# partition share, and a sparse body firm's register read of 0.0 would
		# read every untouched body rival as floor-broken.
		var share := Companies.share_of_company(ns, company)
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

	# V4.7a: share_of_company, not share_of -- the sparse register means a
	# body firm's partition read is the authored fallback, and share_of's
	# 0.0-for-absent would read every untouched body firm as "moved".
	for company in _loader.companies[PLAYER]:
		if Companies.share_of_company(ns, company) != company.share:
			_fail("%s share moved under a regulation: %s against authored %s" % [
				company.id, str(Companies.share_of_company(ns, company)), str(company.share)
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
	# V4.7a: read through share_of_company -- the sparse register means a body
	# firm's partition read IS the authored fallback until something moves it,
	# and share_of's 0.0-for-absent would read every untouched body firm as
	# "moved". A genuinely moved firm still fails here on either tier.
	for company in _loader.companies[PLAYER]:
		if Companies.share_of_company(ns, company) != company.share:
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


# --- V1.4c: ownership -----------------------------------------------------------

## The zero property, extended to the third channel. EXACT equality for V1.4a's own
## reason: the claim is that the whole register changes nothing until a player acts,
## and is_zero_approx would let a drift through.
func _test_unowned_dividend_is_exactly_zero() -> void:
	var state = _new_state()
	for _m in range(168):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Companies.tick_month(state, _loader)
	for id in state.nations.keys():
		var ns = state.nations[id]
		if ns.dividend_revenue_pct_gdp != 0.0:
			_fail("%s dividend_revenue_pct_gdp is %s over 168 months with no holding, not exactly 0.0" % [
				id, str(ns.dividend_revenue_pct_gdp)
			])
		for entry in ns.companies.values():
			if float((entry as Dictionary).get("state_share", 0.0)) != 0.0:
				_fail("%s holds a stake nobody bought" % id)


## THE SESSION'S SHARPEST ASSERTION, and the reason V1.4c added no save field. A
## purchase is a balance-sheet swap: it moves the debt STOCK at once and the deficit
## by exactly zero. A one-off on the revenue side would have moved the deficit --
## which is a company action's own precondition field, so the verb list would answer
## to its own last use inside the same month.
func _test_nationalising_pays_the_debt_and_not_the_deficit() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	var big = _company(BIG)
	var expected: float = Companies.value_eur_bn(ns, big)
	if expected <= 0.0:
		_fail("%s is valued at nothing, so the purchase asserts nothing" % BIG)
		return

	var debt_before: float = ns.debt_eur_bn
	var deficit_before: float = ns.deficit_pct_gdp
	Companies.execute(state, ns, _loader.company_actions, _action("full_nationalisation"), BIG, _loader)

	if not is_equal_approx(ns.debt_eur_bn - debt_before, expected):
		_fail("nationalising %s moved the debt by %s against a derived price of %s" % [
			BIG, str(ns.debt_eur_bn - debt_before), str(expected)
		])
	if ns.deficit_pct_gdp != deficit_before:
		_fail("nationalising moved the deficit by %s in the month it happened" % [
			str(ns.deficit_pct_gdp - deficit_before)
		])
	if Companies.state_share_of(ns, BIG) != 1.0:
		_fail("a full nationalisation left the state holding %s" % [
			str(Companies.state_share_of(ns, BIG))
		])

	# And the windfall is the same machine run backwards: selling returns the debt to
	# where it was, because the price is read off the same live output both times.
	Companies.execute(state, ns, _loader.company_actions, _action("privatisation"), BIG, _loader)
	if not is_equal_approx(ns.debt_eur_bn, debt_before):
		_fail("selling %s left the debt at %s against %s before it was bought" % [
			BIG, str(ns.debt_eur_bn), str(debt_before)
		])


func _test_a_holding_pays_a_dividend_and_privatising_stops_it() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Companies.execute(state, ns, _loader.company_actions, _action("full_nationalisation"), BIG, _loader)
	Companies.tick_month(state, _loader)
	Budget.recompute(state, ns)

	var paid: float = ns.dividend_revenue_pct_gdp
	if paid <= 0.0:
		_fail("a wholly state-owned firm paid %s of GDP" % str(paid))
		return
	if not is_equal_approx(float(ns.revenue_pct_gdp.get("dividends", -1.0)), paid):
		_fail("the dividend line did not reach the budget's revenue table")

	# Sold, it is gone -- exactly, not nearly. "A permanent loss of control" is the
	# row's phrase and this is the whole of what it means in the model.
	Companies.execute(state, ns, _loader.company_actions, _action("privatisation"), BIG, _loader)
	Companies.tick_month(state, _loader)
	Budget.recompute(state, ns)
	if ns.dividend_revenue_pct_gdp != 0.0:
		_fail("a privatised firm still paid %s" % str(ns.dividend_revenue_pct_gdp))
	if float(ns.revenue_pct_gdp.get("dividends", -1.0)) != 0.0:
		_fail("the budget still carries a dividend line after the sale")


## ROW 14's ANSWER, asserted in BOTH DIRECTIONS. A state holding shields the firm's
## payroll from the sector's compliance cost -- and gives up the hiring a
## deregulation would have brought, which is what stops the shield being free. A
## test that only checked the helpful direction would pass on the strictly-dominated
## shape three probes have already caught.
func _test_ownership_shields_jobs_in_both_directions() -> void:
	var big = _company(BIG)

	var regulated = _new_state()
	var reg_ns = regulated.nations[PLAYER]
	if _apply_business_laws(regulated, reg_ns, "emissions_standards") != 1:
		_fail("emissions_standards did not load, so the shield asserts nothing")
		return
	var exposed := Companies.headcount(reg_ns, big)
	Companies.execute(regulated, reg_ns, _loader.company_actions, _action("full_nationalisation"), BIG, _loader)
	var sheltered := Companies.headcount(reg_ns, big)
	if sheltered <= exposed:
		_fail("a burdened firm carried %s staff in public hands against %s in private" % [
			str(sheltered), str(exposed)
		])
	if not is_equal_approx(sheltered, big.headcount):
		_fail("a wholly public firm shed %s staff to a rule it does not pay for" % [
			str(big.headcount - sheltered)
		])

	var freed = _new_state()
	var free_ns = freed.nations[PLAYER]
	_apply_business_laws(freed, free_ns, "industrial_deregulation")
	var hiring := Companies.headcount(free_ns, big)
	Companies.execute(freed, free_ns, _loader.company_actions, _action("full_nationalisation"), BIG, _loader)
	var forgone := Companies.headcount(free_ns, big)
	if forgone >= hiring:
		_fail("a deregulated firm in public hands carried %s staff against %s in private -- the shield only ever helps" % [
			str(forgone), str(hiring)
		])


## `state_share` has exactly ONE writer, the way `share` does. src/core/law.gd's
## _extract_company() names a sector and a burden and refuses any third key, so no
## `business` law can reach a firm at all -- asserted here as a property of the
## shipped content rather than only of the validator. Exact equality: "nearly
## unmoved" is a second writer a tolerance would hide.
func _test_no_law_ever_moves_state_share() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Companies.execute(state, ns, _loader.company_actions, _action("minority_stake"), BIG, _loader)
	var held := Companies.state_share_of(ns, BIG)

	for _i in range(20):
		_apply_business_laws(state, ns)
		Companies.tick_month(state, _loader)

	if Companies.state_share_of(ns, BIG) != held:
		_fail("%s state_share moved from %s to %s under twenty rounds of every business law" % [
			BIG, str(held), str(Companies.state_share_of(ns, BIG))
		])
	for company in _loader.companies[PLAYER]:
		if company.id == BIG:
			continue
		if Companies.state_share_of(ns, company.id) != 0.0:
			_fail("%s was taken into public ownership by a law" % company.id)


## A holding is standing state, so `state_owned` gates the buy exactly as
## `subsidy_active` gates the subsidy -- and the only route down is the sale. Without
## that, buying a minority stake in a wholly-owned firm would be a partial sale that
## paid no windfall.
func _test_ownership_verbs_refuse_when_unavailable() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]

	var early := Companies.execute(
		state, ns, _loader.company_actions, _action("privatisation"), BIG, _loader
	)
	if early.get("applied", true) or not early.get("refused", false):
		_fail("selling a firm the state does not own was applied")

	Companies.execute(state, ns, _loader.company_actions, _action("full_nationalisation"), BIG, _loader)
	var debt_after: float = ns.debt_eur_bn
	var down := Companies.execute(
		state, ns, _loader.company_actions, _action("minority_stake"), BIG, _loader
	)
	if down.get("applied", true):
		_fail("a minority stake was taken in a firm the state already owned outright")
	if ns.debt_eur_bn != debt_after:
		_fail("a refused ownership verb still moved the debt")


## The ownership verbs are player commands and nothing in src/sim/ issues one, which
## is what makes the balance harness bit-identical across every existing regime.
func _test_the_nine_never_nationalise() -> void:
	var state = _new_state()
	for _m in range(168):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Companies.tick_month(state, _loader)
	for id in state.nations.keys():
		if Companies.state_owned_count(state.nations[id]) != 0:
			_fail("%s nationalised something with no player behind it" % id)


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
