extends SceneTree

## Headless test: godot --headless --script res://tests/test_budget.gd
## Non-zero exit on any failure.
##
## One test per S4 done-when condition that is about the budget: revenue and
## growth respond to a tax rise, deficits accumulate into debt and debt service,
## and the projection shown before committing is what actually happens.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Energy = preload("res://src/sim/energy.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Events = preload("res://src/sim/events.gd")
const Statute = preload("res://src/sim/statute.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const Relations = preload("res://src/core/relations.gd")
const C = preload("res://src/sim/economy_constants.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_calibration()
	_check_france_unchanged_by_v1_2a()
	_check_second_nation_calibrates()
	_check_income_tax_rise()
	_check_debt_accumulates()
	_check_projection_matches()
	_check_projection_matches_after_diplomacy()
	_check_projection_matches_under_unrest()
	_check_projection_matches_under_defence_and_companies()

	_finish()


## The revenue residual exists so a fresh game starts on the real figure rather
## than near it. If a tuning pass ever breaks that, this is what says so.
func _check_calibration() -> void:
	var state = GameState.new_game(_loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported errors: %s" % [state.errors])
		return

	var fra = state.player()
	var authored: float = _loader.nations["FRA"].tax_revenue_pct_gdp
	if absf(fra.total_revenue_pct_gdp - authored) > 0.01:
		_fail("FRA starting revenue is %.2f%% of GDP, expected the authored %.2f%%" % [fra.total_revenue_pct_gdp, authored])

	if fra.deficit_pct_gdp <= 0.0:
		_fail("FRA starts with a surplus of %.2f%% of GDP; the default budget is supposed to deficit" % -fra.deficit_pct_gdp)

	if fra.debt_service_pct_gdp <= 0.0:
		_fail("FRA starts with no debt service, expected roughly 2.3%% of GDP")

	# Every nation must calibrate, not just the playable ones — the United
	# Kingdom's 35.3% total against its modelled 25.1% is the tightest margin
	# of the ten once starting policy went per-nation at V1.2a.
	for ns in state.nations.values():
		if ns.other_revenue_pct_gdp < 0.0:
			_fail("%s: revenue residual is negative (%.2f)" % [ns.id, ns.other_revenue_pct_gdp])


## V1.2a moved starting fiscal policy from one shared data/policy_defaults.json
## into each nation's own fiscal block, and threaded the tax-erosion reference
## through as an explicit per-nation argument instead of a shared constant
## (economy_constants.TAX_REF_RATE_PCT, deleted). France was the anchor both
## changes were built around and its own numbers were never meant to move --
## this is that promise, checked to float precision rather than eyeballed.
func _check_france_unchanged_by_v1_2a() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var fra = state.player()

	if absf(fra.tax_rates_pct["income"] - 20.0) > 1e-9 or \
		absf(fra.tax_rates_pct["corporate"] - 25.0) > 1e-9 or \
		absf(fra.tax_rates_pct["vat"] - 20.0) > 1e-9:
		_fail("FRA's starting tax rates moved: %s" % [fra.tax_rates_pct])

	# Erosion is centred on the nation's own start, so at new-game it must be
	# exactly 1.0 -- the modelled revenue line is then TAX_BASE_SHARE * rate,
	# nothing else, checked to float precision.
	for key in C.TAX_KEYS:
		var expected: float = float(C.TAX_BASE_SHARE[key]) * float(fra.tax_rates_pct[key])
		var actual: float = float(fra.revenue_pct_gdp[key])
		if absf(actual - expected) > 1e-9:
			_fail("FRA's %s revenue line is %.9f, expected erosion-free %.9f at new-game" % [key, actual, expected])


## The second half of the V1.2a promise: a nation whose starting policy is
## genuinely different from France's still calibrates cleanly, and its
## starting deficit is not France's by coincidence.
func _check_second_nation_calibrates() -> void:
	var state = GameState.new_game(_loader, "DEU")
	if not state.errors.is_empty():
		_fail("new_game(DEU) reported errors: %s" % [state.errors])
		return

	var deu = state.player()
	var authored: float = _loader.nations["DEU"].tax_revenue_pct_gdp
	if absf(deu.total_revenue_pct_gdp - authored) > 0.01:
		_fail("DEU starting revenue is %.2f%% of GDP, expected the authored %.2f%%" % [deu.total_revenue_pct_gdp, authored])

	var fra = GameState.new_game(_loader, "FRA").player()
	if is_equal_approx(deu.deficit_pct_gdp, fra.deficit_pct_gdp):
		_fail("DEU's starting deficit (%.2f) exactly matches FRA's (%.2f) -- per-nation policy did not take" % [
			deu.deficit_pct_gdp, fra.deficit_pct_gdp
		])


## Done-when: raising income tax increases revenue and reduces growth over the
## following months.
func _check_income_tax_rise() -> void:
	var base := _run(GameState.new_game(_loader, "FRA"), {}, 12)
	var hi := _run(GameState.new_game(_loader, "FRA"), {"tax_rates_pct": {"income": 25.0}}, 12)

	var base_rev_eur: float = base[0]["total_revenue_pct_gdp"] / 100.0 * base[0]["gdp_eur_bn"]
	var hi_rev_eur: float = hi[0]["total_revenue_pct_gdp"] / 100.0 * hi[0]["gdp_eur_bn"]
	if hi_rev_eur <= base_rev_eur:
		_fail("income tax +5pp: revenue in month 1 went %.1f -> %.1f EUR bn, expected a rise" % [base_rev_eur, hi_rev_eur])

	for i in range(12):
		if hi[i]["growth_annual_pct"] >= base[i]["growth_annual_pct"]:
			_fail("income tax +5pp: growth in month %d was %.4f%%, not below the baseline %.4f%%" % [
				i + 1, hi[i]["growth_annual_pct"], base[i]["growth_annual_pct"]
			])
			break

	if hi[11]["gdp_eur_bn"] >= base[11]["gdp_eur_bn"]:
		_fail("income tax +5pp: GDP after a year is %.1f, not below the baseline %.1f" % [
			hi[11]["gdp_eur_bn"], base[11]["gdp_eur_bn"]
		])

	# And the effect must fade rather than compound: the impulse decays, so by
	# year five growth is back at or above the baseline path.
	var long_base := _run(GameState.new_game(_loader, "FRA"), {}, 60)
	var long_hi := _run(GameState.new_game(_loader, "FRA"), {"tax_rates_pct": {"income": 25.0}}, 60)
	if long_hi[59]["growth_annual_pct"] < long_base[59]["growth_annual_pct"] - 0.05:
		_fail("income tax +5pp: growth still %.3f%% below baseline after five years; the impulse should have decayed" % [
			long_base[59]["growth_annual_pct"] - long_hi[59]["growth_annual_pct"]
		])


## Done-when: spending beyond revenue accumulates debt, and debt service appears
## as a growing spending line.
func _check_debt_accumulates() -> void:
	var snaps := _run(GameState.new_game(_loader, "FRA"), {}, 60)

	for i in range(1, snaps.size()):
		if snaps[i]["debt_eur_bn"] <= snaps[i - 1]["debt_eur_bn"]:
			_fail("debt did not grow between month %d and %d (%.2f -> %.2f)" % [
				i, i + 1, snaps[i - 1]["debt_eur_bn"], snaps[i]["debt_eur_bn"]
			])
			break
		if snaps[i]["debt_service_pct_gdp"] <= snaps[i - 1]["debt_service_pct_gdp"]:
			_fail("debt service did not grow between month %d and %d (%.4f -> %.4f)" % [
				i, i + 1, snaps[i - 1]["debt_service_pct_gdp"], snaps[i]["debt_service_pct_gdp"]
			])
			break

	if snaps[59]["debt_to_gdp_pct"] <= snaps[0]["debt_to_gdp_pct"]:
		_fail("debt ratio did not rise over five years of the default deficit")

	# Debt service is a spending line, so it must show up inside total spending.
	var last: Dictionary = snaps[59]
	if last["total_spending_pct_gdp"] <= last["debt_service_pct_gdp"]:
		_fail("total spending does not include debt service")


## Done-when: the projection shown before committing matches what happens.
## It holds by construction — project() runs the same two tick functions on a
## deep copy — and this is the test that keeps it that way.
func _check_projection_matches() -> void:
	var pending := {
		"tax_rates_pct": {"income": 28.0, "vat": 17.0},
		"spending_pct_gdp": {"health": 13.5, "infrastructure": 6.0},
	}

	var state = GameState.new_game(_loader, "FRA")
	var projected := Budget.project(state, pending, 24, _loader)

	# The projection must not have touched the live state.
	if state.player().tax_rates_pct["income"] != 20.0:
		_fail("project() mutated live state: income rate is now %s" % state.player().tax_rates_pct["income"])

	var actual := _run(state, pending, 24)

	if projected.size() != actual.size():
		_fail("projection has %d months, actual has %d" % [projected.size(), actual.size()])
		return

	for i in range(projected.size()):
		for key in projected[i].keys():
			if key == "sectors":
				for sector in projected[i][key].keys():
					_close("month %d sectors.%s" % [i + 1, sector], projected[i][key][sector], actual[i][key][sector])
			else:
				_close("month %d %s" % [i + 1, key], projected[i][key], actual[i][key])


## V1.3b. The same check, from a state the player has already acted diplomatically
## from -- which is where the projection could newly diverge and where the check
## above cannot see it.
##
## Budget.project() runs Economy + Budget on a copy and does NOT tick Diplomacy;
## it has no loader to do it with, while main.gd does. So relations are frozen in
## the projection and drifting in the real game, and since V1.3b relations feed
## the trade weight, the two could disagree. They do not, and the reason is
## structural rather than lucky: relations move the normalised MIX, the mix only
## reaches the impulse through partners' deviations from their own baselines, and
## those are ~0. The gap is bounded by drift over the projection horizon rather
## than by anything the player can do.
##
## Pinned here so that if a later session gives relations a level effect, this
## fails rather than the budget panel quietly starting to lie. The panel is the
## one surface in the game that promises "this is what will happen".
func _check_projection_matches_after_diplomacy() -> void:
	var state = GameState.new_game(_loader, "FRA")

	# Displaced hard and unevenly, so a projection that ignores relations drift has
	# the largest possible disagreement with one that does not.
	for id in state.nations.keys():
		if id == "FRA":
			continue
		state.relations[Relations.key("FRA", id)] = 95.0 if id < "G" else 5.0

	var pending := {"tax_rates_pct": {"vat": 23.0}}
	var projected := Budget.project(state, pending, 24, _loader)
	var actual := _run(state, pending, 24)

	if projected.size() != actual.size():
		_fail("displaced projection has %d months, actual has %d" % [projected.size(), actual.size()])
		return
	for i in range(projected.size()):
		for key in projected[i].keys():
			if key == "sectors":
				continue
			_close("displaced month %d %s" % [i + 1, key], projected[i][key], actual[i][key])


## V1.5c, and the THIRD displaced check on this list. The other two exist because a
## projection that froze relations or the council would disagree with the real game;
## this one exists because a projection that froze UNREST would be silent about an act
## nobody chose.
##
## Displaced above the threshold rather than run into it, which is the whole reason
## there is a third check: from an undisplaced state the grievance is exactly 0.0, the
## agent never fires inside a 24-month window, and the projection agrees with reality
## for the boring reason. That is _check_projection_matches()'s blind spot, stated as a
## test rather than as a comment -- and it is the same blind spot at a larger scale that
## made all twenty-five balance regimes report zero acts.
func _check_projection_matches_under_unrest() -> void:
	var state = GameState.new_game(_loader, "FRA")
	state.player().unrest_pct = UnrestK.UNREST_MAX
	if not Unrest.would_act(state.player()):
		_fail("the displaced state does not want to act, so this check proves nothing")
		return

	var pending := {"tax_rates_pct": {"vat": 23.0}}
	var projected := Budget.project(state, pending, 24, _loader)
	var actual := _run(state, pending, 24)

	if projected.size() != actual.size():
		_fail("unrest projection has %d months, actual has %d" % [projected.size(), actual.size()])
		return
	for i in range(projected.size()):
		for key in projected[i].keys():
			if key == "sectors":
				continue
			_close("unrest month %d %s" % [i + 1, key], projected[i][key], actual[i][key])


## The FOURTH displaced check, and it exists because the mirror below was INCOMPLETE
## for two whole blocks. Budget.project() has called Defence.tick_month() since V1.3g
## and Companies.tick_month() since V1.4a; _run() called neither, and the 1e-9
## agreement held anyway because both are inert from an undisplaced start -- no pact,
## no deployment, no subsidy, no state holding. That is exactly the accident V1.3f
## found in Diplomacy, surviving two sessions longer because nothing displaced these
## two before projecting.
##
## Displacing four registers at once rather than writing two thin checks: the point is
## not which system diverges but that the mirror is COMPLETE, and one check that would
## fail if either line were removed says that more directly than two that each say half
## of it. Capability is set off its equilibrium deliberately -- a deployment whose cost
## is constant makes the bill a fixed offset both loops would carry identically, where
## a converging capability moves the bill every month of the window.
func _check_projection_matches_under_defence_and_companies() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var fra = state.player()

	# Written straight into the registers, the idiom the three checks above use. The
	# pact is what stops _close_orphans() erasing the deployment on the first tick.
	state.pacts[Relations.key("FRA", "DEU")] = {
		"action_id": "test_pact",
		"action_name": "Test pact",
		"since_year": state.year,
		"since_month": state.month,
	}
	Defence.open_deployment(state, "FRA", "DEU", DefenceK.DEPLOYMENT_CHOSEN, null)
	fra.military_capability = 0.5 * Defence.capability_target(fra)

	var firms: Array = Companies.firms_of(_loader, "FRA")
	if firms.size() < 2:
		_fail("FRA has %d firms, so this check cannot displace the register" % firms.size())
		return
	fra.companies[firms[0].id]["subsidy"] = 1.0
	fra.companies[firms[1].id]["state_share"] = 0.6

	# Guards, for the reason the unrest check has one: an inert displacement would let
	# this check pass by agreeing about nothing.
	if Defence.deployment_bill_pct_gdp(state, fra) <= 0.0:
		_fail("the displaced state carries no deployment bill, so this check proves nothing")
		return
	if Companies.subsidised_count(fra) == 0 or Companies.state_owned_count(fra) == 0:
		_fail("the displaced firm register is empty, so this check proves nothing")
		return

	var pending := {"tax_rates_pct": {"vat": 23.0}}
	var projected := Budget.project(state, pending, 24, _loader)
	var actual := _run(state, pending, 24)

	if projected.size() != actual.size():
		_fail("defence/companies projection has %d months, actual has %d" % [projected.size(), actual.size()])
		return
	for i in range(projected.size()):
		for key in projected[i].keys():
			if key == "sectors":
				continue
			_close("defence/companies month %d %s" % [i + 1, key], projected[i][key], actual[i][key])


## main.gd's chain, which is also project()'s. Every system project() advances on
## its copy has to be advanced here, or the test compares a projection that ran
## the model against a reality that did not.
##
## > [!note] V1.3f collapsed two runners into this one, and the reason is the
## > point of the check rather than tidying
## > There used to be a second runner, `_run_with_diplomacy()`, used only by the
## > displaced check below. It existed because Diplomacy.tick_month() was a NO-OP
## > from an undisplaced state -- drift moves nothing when every pair is already at
## > rest -- so the plain runner agreed with the projection by accident rather than
## > by construction, and only a displaced state could tell them apart.
## >
## > V1.3f ends that: the agenda acts from month one whatever the relations are, so
## > a runner without Diplomacy in it now disagrees with the projection immediately.
## > Adding it here is the same repair V1.3d made one session earlier for Bloc, and
## > this file caught both. What the displaced check still buys is the MAGNITUDE --
## > it is where a divergence would be largest.
func _run(state, pending: Dictionary, months: int) -> Array[Dictionary]:
	if not pending.is_empty():
		Budget.commit(state, pending)
	var out: Array[Dictionary] = []
	for _i in range(months):
		# V1.6a. This runner froze the clock, and so did Budget.project() -- which is
		# why the two agreed to 1e-9 for eleven sessions while BOTH were wrong. Nothing
		# in either loop computed a figure from the date until the business cycle did:
		# bloc.gd, defence.gd and cabinet.gd read state.year only to stamp a record.
		# The projection now advances its copy, so this runner has to advance too, and
		# the agreement means something it did not mean before.
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		# V2.8 review. Energy leads, in project()'s own slot and for its own stated
		# reason: economy.gd READS ns.energy_impulse_pct rather than computing it, so
		# an energy tick after the economy prices this month's mix against last
		# month's growth.
		var access_by_nation: Dictionary = {}
		for nation_id in state.nations.keys():
			access_by_nation[nation_id] = Regions.accessibility_for(
				state.nations[nation_id], state.regions.get(nation_id, []),
				state.region_graph)
		Energy.tick_month(state, _loader, access_by_nation)
		Economy.tick_month(state)
		Budget.tick_month(state)
		Orgs.tick_month(state, _loader)
		Diplomacy.tick_month(state, _loader)
		# Added after the fact: project() has called both since V1.3g and V1.4a and this
		# mirror never did. The omission was invisible because both are inert from an
		# undisplaced start -- no pact, no deployment, no subsidy, no state holding -- so
		# the 1e-9 agreement below held by accident, exactly the way Diplomacy's did
		# before V1.3f. _check_projection_matches_under_defence_and_companies() displaces
		# both so the mirror's completeness is exercised rather than assumed.
		Defence.tick_month(state)
		# The ultra pass-10 finding: the mirror copies project()'s ORDER, and
		# project() moved Statute before Companies -- a division's
		# company-channel burden is priced by the same month's Companies/
		# Industry passes, so both legs must write it before they run.
		Statute.tick_month(state, _loader)
		Companies.tick_month(state, _loader)
		# V4.7b. The autonomy machine, in project()'s slot between Companies and
		# Migration -- a failure, rescue or break-up inside the projected window
		# writes failed/share, and a mirror that skipped it would agree with the
		# projection only while no firm ever acted.
		Industry.tick_month(state, _loader)
		# The ultra pass-1 projection finding, PR 47 finding 1's class a third
		# time: project() has ticked the assembly's own life and this mirror
		# never did, so the 1e-9 agreement below held only while the backbench
		# never legislated. The PMB hazard is Cycle-keyed over the absolute
		# month like Events' -- which this loop already runs for exactly that
		# reason -- so both legs see the same bills and the same divisions, and
		# a carried division applies through Budget.commit() into the very
		# revenue and spending keys the comparison walks. PMB_MONTHS_TO_VOTE is
		# 1, so any bill staged inside a 24-month window divides inside it too:
		# the checks above exercise this line rather than assuming it inert.
		# V2.8 review. Five more that project() has ticked and this mirror never did.
		# Four are inert from an undisplaced start, which is why the 1e-9 agreement
		# held by accident yet again -- but Events is NOT structurally inert: its
		# hazard is a pure function of (nation, event, absolute month) and this loop
		# advances the clock, so an event whose preconditions hold inside the window
		# fires on one side only, and the check would then be measuring the omission
		# rather than the model. Exactly what the comment further down warns about.
		Migration.tick_month(state, _loader)
		Investment.tick_month(state)
		Projects.tick_month(state, _loader)
		Campaign.tick_month(state, _loader)
		# V1.5c. Three more, and only the last one can move a fiscal figure: an unrest
		# act writes a growth impulse, and growth reaches GDP, revenue and the deficit.
		# The two above it are its inputs, so leaving them out would make the runner and
		# the projection disagree about the grievance rather than about the budget.
		Demography.tick_month(state)
		Society.tick_month(state)
		Unrest.tick_month(state)
		Events.tick_month(state, _loader)
		# V1.6b. Added to BOTH lists in one commit. This runner is a hand-written mirror
		# of Budget.project()'s tick list, so a system added to one and not the other
		# makes the two disagree -- and the 1e-9 check below would then be measuring the
		# omission rather than the model. Inflation belongs here for the reason the
		# others do and one sharper: it writes a growth addend, so it reaches every
		# fiscal figure this test compares.
		Inflation.tick_month(state)
		out.append(Budget.snapshot(state))
	return out


func _close(where: String, projected: float, actual: float) -> void:
	var tolerance: float = 1.0e-9 * maxf(absf(actual), 1.0)
	if absf(projected - actual) > tolerance:
		_fail("projection mismatch at %s: projected %s, actual %s" % [where, projected, actual])


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_budget: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
