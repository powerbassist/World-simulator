extends SceneTree

## V5.3 a (docs/design/v5.3-ab.md 2.3 and 3.2, bands A3 and A4): the ownership and
## structure verbs are PROCESSES. A press (or an adopted bill) opens a row on
## ns.processes and changes no firm, no debt and no state share in that month;
## each stage ends on its month; the realised duration and price fall inside the
## range the strip showed at the start. Driven through Processes.tick_month() a
## month at a time, the step WorldMonth runs before Companies.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Companies = preload("res://src/sim/companies.gd")
const Processes = preload("res://src/sim/processes.gd")
const Bills = preload("res://src/sim/bills.gd")
const K = preload("res://src/sim/companies_constants.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Budget = preload("res://src/sim/budget.gd")
const Industry = preload("res://src/sim/industry.gd")
const Economy = preload("res://src/sim/economy.gd")
const EC = preload("res://src/sim/economy_constants.gd")

const PLAYER := "FRA"
const OK_BLOCS := ["workers", "pensioners", "urban", "rural", "business", "students"]

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_stake_takes_two_months_and_its_price_brackets()
	_test_nationalisation_pays_at_transfer_and_owns_after_transition()
	_test_privatisation_sells_after_six_months_at_a_discount()
	_test_break_up_rules_then_remedies()
	_test_break_up_cleared_costs_the_fees_only()
	_test_stops_cost_what_the_spec_says()
	_test_one_process_per_firm()
	_test_a_failed_firm_voids_its_process()
	_test_the_step_runs_before_companies()
	_test_the_register_round_trips_and_absent_reads_empty()
	_test_the_forecast_runs_the_processes()
	_test_a_ruling_on_a_firm_that_no_longer_qualifies_moves_nothing()
	_test_a_reopened_process_has_its_own_id()
	_test_a_remedy_refused_undoes_the_rulings_bloc_move()
	_test_the_press_door_routes_by_verb()
	_test_a_failure_in_the_transition_lands_the_ownership()
	_test_the_odds_window_does_not_centre_on_the_truth()
	_test_no_bid_opens_on_a_firm_in_a_process()
	_test_the_transition_drags_the_firms_output()
	_test_the_drag_reaches_growth()
	_test_the_realised_loss_is_the_strips()
	_finish()


# --- helpers --------------------------------------------------------------------

func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 3
	return state


func _action(id: String):
	for a in _loader.company_actions:
		if String(a.id) == id:
			return a
	return null


## The player's largest major by share -- one that clears break-up's 10 % gate.
func _big(ns) -> String:
	var best := ""
	var share := -1.0
	for company in Companies.majors_of(_loader, ns.id):
		var s := Companies.share_of_company(ns, company)
		if s > share:
			share = s
			best = String(company.id)
	return best


func _company(ns, company_id: String):
	for company in Companies.firms_of(_loader, ns.id):
		if String(company.id) == company_id:
			return company
	return null


## One month: the clock moves, then the register's step runs.
func _month(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	Processes.tick_month(state, _loader)


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _row(ns, company_id: String) -> Dictionary:
	for row in ns.processes:
		if String(row["company_id"]) == company_id:
			return row
	return {}


func _offsets(ns) -> Dictionary:
	return (ns.bloc_offset as Dictionary).duplicate()


# --- A3 + A4, kind by kind ---------------------------------------------------------

func _test_stake_takes_two_months_and_its_price_brackets() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var stake = _action("minority_stake")
	var est: Dictionary = Processes.estimate(state, ns, _loader, stake, firm)
	var value := Companies.value_eur_bn(ns, _company(ns, firm))
	if not is_equal_approx(float(est["price_lo"]), value * float(stake.effects["company"]["stake"]) * (1.0 + K.PROCESS_STAKE_PREMIUM.x)) \
			or not is_equal_approx(float(est["price_hi"]), value * float(stake.effects["company"]["stake"]) * (1.0 + K.PROCESS_STAKE_PREMIUM.y)):
		_fail("the stake's price range is %s..%s, not value x stake x (1 + premium)" % [est["price_lo"], est["price_hi"]])
	if int(est["months_lo"]) != K.PROCESS_STAKE_MONTHS or int(est["months_hi"]) != K.PROCESS_STAKE_MONTHS:
		_fail("the stake's duration range is not %d months: %s" % [K.PROCESS_STAKE_MONTHS, est])
	var debt := float(ns.debt_eur_bn)
	var offsets := _offsets(ns)
	var started := _now(state)
	var r: Dictionary = Processes.start(state, ns, _loader, stake, firm)
	if not bool(r.get("applied", false)):
		_fail("the stake did not start: %s" % r)
		return
	# A3: nothing lands the month it is pressed -- but half the bloc move does.
	if Companies.state_share_of(ns, firm) != 0.0 or float(ns.debt_eur_bn) != debt:
		_fail("the stake moved the state share or the debt the month it was pressed")
	var half := float((stake.effects["bloc_offset"] as Dictionary)["workers"]) * 0.5
	if not is_equal_approx(float(ns.bloc_offset.get("workers", 0.0)) - float(offsets.get("workers", 0.0)), half):
		_fail("the offer did not land half the stake's bloc move")
	_month(state)
	if Companies.state_share_of(ns, firm) != 0.0 or float(ns.debt_eur_bn) != debt:
		_fail("the stake landed after one month of a two-month negotiation")
	_month(state)
	var row := _row(ns, firm)
	if Companies.state_share_of(ns, firm) != float(stake.effects["company"]["stake"]):
		_fail("the stake did not transfer at the end of its negotiation: share %s" % Companies.state_share_of(ns, firm))
	var paid := float(ns.debt_eur_bn) - debt
	if paid < float(est["price_lo"]) - 1e-9 or paid > float(est["price_hi"]) + 1e-9:
		_fail("A4: the stake cost %.4f, outside its strip's %.4f..%.4f" % [paid, est["price_lo"], est["price_hi"]])
	if String(row.get("status", "")) != "done" or int(row["closed"]) - started != K.PROCESS_STAKE_MONTHS:
		_fail("A3: the stake's row did not close done after %d months: %s" % [K.PROCESS_STAKE_MONTHS, row])
	var full := float((stake.effects["bloc_offset"] as Dictionary)["workers"])
	if not is_equal_approx(float(ns.bloc_offset.get("workers", 0.0)) - float(offsets.get("workers", 0.0)), full):
		_fail("the stake's bloc move did not total the action's offset once")


func _test_nationalisation_pays_at_transfer_and_owns_after_transition() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var buy = _action("full_nationalisation")
	var est: Dictionary = Processes.estimate(state, ns, _loader, buy, firm)
	var debt := float(ns.debt_eur_bn)
	var started := _now(state)
	# The adopted bill opens the process (Bills.adopt is the law's door).
	Bills.adopt(state, ns, _loader, {"action_id": "full_nationalisation", "company_id": firm})
	if _row(ns, firm).is_empty() or float(ns.debt_eur_bn) != debt or Companies.state_share_of(ns, firm) != 0.0:
		_fail("A3: the adopted bill bought the firm at once, or opened no process")
		return
	for i in range(K.PROCESS_OFFER_MONTHS):
		_month(state)
	var paid := float(ns.debt_eur_bn) - debt
	if paid < float(est["price_lo"]) - 1e-9 or paid > float(est["price_hi"]) + 1e-9:
		_fail("A4: the nationalisation paid %.4f at the transfer, outside %.4f..%.4f" % [paid, est["price_lo"], est["price_hi"]])
	if Companies.state_share_of(ns, firm) != 0.0 or String(_row(ns, firm)["stage"]) != "transition":
		_fail("the transfer handed over control before the transition: %s" % _row(ns, firm))
	for i in range(K.PROCESS_TRANSITION_MONTHS):
		_month(state)
	var row := _row(ns, firm)
	if Companies.state_share_of(ns, firm) != 1.0 or not is_equal_approx(float(ns.debt_eur_bn) - debt, paid):
		_fail("the transition's end did not hand over the firm without a second payment")
	var months := int(row.get("closed", -1)) - started
	if String(row.get("status", "")) != "done" or months < int(est["months_lo"]) or months > int(est["months_hi"]):
		_fail("A3: the nationalisation took %d months against %s..%s" % [months, est["months_lo"], est["months_hi"]])


func _test_privatisation_sells_after_six_months_at_a_discount() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	(ns.companies[firm] as Dictionary)["state_share"] = 1.0
	var sell = _action("privatisation")
	var est: Dictionary = Processes.estimate(state, ns, _loader, sell, firm)
	var value := Companies.value_eur_bn(ns, _company(ns, firm))
	if not is_equal_approx(float(est["price_lo"]), -value) \
			or not is_equal_approx(float(est["price_hi"]), -value * (1.0 - K.PROCESS_PRIVATISE_DISCOUNT.y)):
		_fail("the sale's range is %s..%s, not -value..-value x (1 - max discount)" % [est["price_lo"], est["price_hi"]])
	var debt := float(ns.debt_eur_bn)
	Bills.adopt(state, ns, _loader, {"action_id": "privatisation", "company_id": firm})
	if float(ns.debt_eur_bn) != debt or Companies.state_share_of(ns, firm) != 1.0:
		_fail("A3: the privatisation sold the month its bill was adopted")
	for i in range(K.PROCESS_SALE_MONTHS):
		_month(state)
	var got := float(ns.debt_eur_bn) - debt
	if Companies.state_share_of(ns, firm) != 0.0:
		_fail("the sale did not close after %d months" % K.PROCESS_SALE_MONTHS)
	if got < float(est["price_lo"]) - 1e-9 or got > float(est["price_hi"]) + 1e-9:
		_fail("A4: the windfall moved the debt by %.4f, outside %.4f..%.4f" % [got, est["price_lo"], est["price_hi"]])


func _test_break_up_rules_then_remedies() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var split = _action("break_up")
	var est: Dictionary = Processes.estimate(state, ns, _loader, split, firm)
	if float(est["odds_lo"]) > float(est["odds"]) or float(est["odds_hi"]) < float(est["odds"]):
		_fail("the ruling's shown odds %s..%s do not bracket its truth %s" % [est["odds_lo"], est["odds_hi"], est["odds"]])
	var debt := float(ns.debt_eur_bn)
	var started := _now(state)
	var offsets := _offsets(ns)
	Processes.start(state, ns, _loader, split, firm)
	var row := _row(ns, firm)
	if bool((ns.companies[firm] as Dictionary).get("failed", false)) or float(ns.debt_eur_bn) != debt:
		_fail("A3: the break-up landed the month it was referred")
	var inquiry := int(row["months_left"])
	if inquiry < K.PROCESS_INVESTIGATION_MONTHS.x or inquiry > K.PROCESS_INVESTIGATION_MONTHS.y:
		_fail("the investigation's %d months fall outside %s" % [inquiry, K.PROCESS_INVESTIGATION_MONTHS])
	row["odds"] = 1.0  # the authority rules for the break-up
	var share := Companies.share_of_company(ns, _company(ns, firm))
	var rivals_before := 0.0
	for company in Companies.majors_of(_loader, ns.id):
		if String(company.id) != firm and Companies.share_of_company(ns, company) > 0.0:
			rivals_before += Companies.share_of_company(ns, company)
	for i in range(inquiry):
		_month(state)
	if not is_equal_approx(float(ns.debt_eur_bn) - debt, K.PROCESS_LEGAL_COST_EUR_BN):
		_fail("the ruling did not charge the legal costs once")
	if String(row["stage"]) != "remedy" or float(ns.bloc_offset.get("business", 0.0)) == float(offsets.get("business", 0.0)):
		_fail("a ruling for the break-up did not open the remedy with its bloc move")
	for i in range(K.PROCESS_REMEDY_MONTHS):
		_month(state)
	if not bool((ns.companies[firm] as Dictionary).get("failed", false)):
		_fail("the remedy did not break the firm up")
	var rivals_after := 0.0
	for company in Companies.majors_of(_loader, ns.id):
		if String(company.id) != firm:
			rivals_after += Companies.share_of_company(ns, company)
	if not is_equal_approx(rivals_after - rivals_before, share * K.BREAK_UP_ABSORBED):
		_fail("the rivals absorbed %.4f of a %.4f share, not %.0f %%" % [rivals_after - rivals_before, share, 100.0 * K.BREAK_UP_ABSORBED])
	var months := int(row["closed"]) - started
	if months < int(est["months_lo"]) or months > int(est["months_hi"]) or not is_equal_approx(float(ns.debt_eur_bn) - debt, K.PROCESS_LEGAL_COST_EUR_BN):
		_fail("A3/A4: the break-up took %d months (%s..%s) or cost more than its fees" % [months, est["months_lo"], est["months_hi"]])


func _test_break_up_cleared_costs_the_fees_only() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var debt := float(ns.debt_eur_bn)
	var offsets := _offsets(ns)
	Processes.start(state, ns, _loader, _action("break_up"), firm)
	var row := _row(ns, firm)
	row["odds"] = 0.0  # the firm wins
	for i in range(int(row["months_left"])):
		_month(state)
	if String(row["status"]) != "cleared" or bool((ns.companies[firm] as Dictionary).get("failed", false)):
		_fail("a ruling against the break-up did not clear the firm: %s" % row)
	if not is_equal_approx(float(ns.debt_eur_bn) - debt, K.PROCESS_LEGAL_COST_EUR_BN) or _offsets(ns) != offsets:
		_fail("a cleared referral cost more than its legal fees")


func _test_stops_cost_what_the_spec_says() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	# A nationalisation stopped in its offer: the break fee, 10 % of the premium.
	Bills.adopt(state, ns, _loader, {"action_id": "full_nationalisation", "company_id": firm})
	var row := _row(ns, firm)
	var price: Dictionary = Processes.stop_price(state, ns, _loader, String(row["id"]))
	var premium := float(row["base_eur_bn"]) * float(row["rate"])
	if not is_equal_approx(float(price["debt_eur_bn"]), K.PROCESS_BREAK_FEE * premium):
		_fail("the offer's break fee is %s, not 10 %% of the premium %s" % [price["debt_eur_bn"], premium])
	var debt := float(ns.debt_eur_bn)
	var r: Dictionary = Processes.stop(state, ns, _loader, String(row["id"]))
	if not bool(r.get("ok", false)) or String(row["status"]) != "stopped" \
			or not is_equal_approx(float(ns.debt_eur_bn) - debt, K.PROCESS_BREAK_FEE * premium):
		_fail("stopping the offer did not charge the break fee and close the row: %s" % r)
	_month(state)
	if Companies.state_share_of(ns, firm) != 0.0:
		_fail("a stopped nationalisation still transferred")
	# Past the transfer there is nothing to stop.
	var state2 = _new_state()
	var ns2 = state2.player()
	Bills.adopt(state2, ns2, _loader, {"action_id": "full_nationalisation", "company_id": firm})
	for i in range(K.PROCESS_OFFER_MONTHS):
		_month(state2)
	if bool(Processes.stop(state2, ns2, _loader, String(_row(ns2, firm)["id"])).get("ok", true)):
		_fail("a nationalisation in its transition could be stopped")
	# A break-up stopped in its investigation pays the fees spent so far.
	var state3 = _new_state()
	var ns3 = state3.player()
	Processes.start(state3, ns3, _loader, _action("break_up"), firm)
	var row3 := _row(ns3, firm)
	var total := int(row3["months_left"])
	_month(state3)
	_month(state3)
	var debt3 := float(ns3.debt_eur_bn)
	Processes.stop(state3, ns3, _loader, String(row3["id"]))
	if not is_equal_approx(float(ns3.debt_eur_bn) - debt3, K.PROCESS_LEGAL_COST_EUR_BN * 2.0 / float(total)):
		_fail("a stopped investigation did not pay the fees spent pro rata")


func _test_one_process_per_firm() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("minority_stake"), firm)
	if bool(Processes.start(state, ns, _loader, _action("break_up"), firm).get("applied", true)):
		_fail("a second process opened on a firm already in one")
	if not Processes.blocks(ns, firm, _action("break_up")) or Processes.blocks(ns, firm, _action("industrial_subsidy")):
		_fail("blocks() does not refuse the structure verbs alone on a firm in process")
	if not Bills.ownership(state, ns, _loader, firm).is_empty():
		_fail("an ownership bill is offered for a firm already in a process")


func _test_a_failed_firm_voids_its_process() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("minority_stake"), firm)
	var debt := float(ns.debt_eur_bn)
	(ns.companies[firm] as Dictionary)["failed"] = true
	_month(state)
	_month(state)
	var row := _row(ns, firm)
	if String(row["status"]) != "void" or float(ns.debt_eur_bn) != debt or Companies.state_share_of(ns, firm) != 0.0:
		_fail("a firm that failed mid-negotiation was still bought: %s" % row)


func _test_the_step_runs_before_companies() -> void:
	var i := WorldMonth.STEPS.find("Processes")
	if i < 0 or i != WorldMonth.STEPS.find("Companies") - 1:
		_fail("Processes is not the step just before Companies: %s" % [WorldMonth.STEPS])


func _test_the_register_round_trips_and_absent_reads_empty() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("break_up"), firm)
	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var row := _row(kept.player(), firm)
	if row.is_empty() or int(row["months_left"]) != int(_row(ns, firm)["months_left"]) \
			or String(row["stage"]) != "investigation":
		_fail("the process register did not survive the round trip: %s" % row)
	var without: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(without["nations"][PLAYER] as Dictionary).erase("processes")
	if not GameState.from_dict(without).player().processes.is_empty():
		_fail("an absent register did not read as nothing in progress")
	# The loaded row ticks on: its months_left survived as a number.
	Processes.tick_month(kept, _loader)
	if int(_row(kept.player(), firm)["months_left"]) != int(_row(ns, firm)["months_left"]) - 1:
		_fail("a loaded process did not tick on")


## Review pass 1: the 24-month forecast runs the processes, so a pending transfer
## is in the figures the budget panel promises (Budget.project's month).
func _test_the_forecast_runs_the_processes() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var est: Dictionary = Processes.estimate(state, ns, _loader, _action("full_nationalisation"), firm)
	Bills.adopt(state, ns, _loader, {"action_id": "full_nationalisation", "company_id": firm})
	var without = state.duplicate_state()
	without.player().processes.clear()
	var with_it: Array = Budget.project(state, {}, K.PROCESS_OFFER_MONTHS, _loader)
	var none: Array = Budget.project(without, {}, K.PROCESS_OFFER_MONTHS, _loader)
	var gap := float(with_it[-1]["debt_eur_bn"]) - float(none[-1]["debt_eur_bn"])
	if gap < float(est["price_lo"]) - 0.01 or gap > float(est["price_hi"]) + 0.01:
		_fail("the forecast's debt at the transfer differs by %.4f, not the transfer's %.4f..%.4f" % [gap, est["price_lo"], est["price_hi"]])


## Review pass 1: a firm that no longer qualifies at the ruling (its share under
## the gate) is not broken up, and the blocs pay nothing for it; the fees stay paid.
func _test_a_ruling_on_a_firm_that_no_longer_qualifies_moves_nothing() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var debt := float(ns.debt_eur_bn)
	Processes.start(state, ns, _loader, _action("break_up"), firm)
	var row := _row(ns, firm)
	row["odds"] = 1.0
	(ns.companies[firm] as Dictionary)["share"] = 0.05
	var offsets := _offsets(ns)
	for i in range(int(row["months_left"])):
		_month(state)
	if String(row["status"]) != "refused" or _offsets(ns) != offsets:
		_fail("a ruling on a firm under the gate moved the blocs or opened the remedy: %s" % row)
	if not is_equal_approx(float(ns.debt_eur_bn) - debt, K.PROCESS_LEGAL_COST_EUR_BN):
		_fail("the refused ruling did not keep its legal fees")


## A firm that drifts under the gate during the remedy (measured once in the probe:
## DEU_kellermann) is not broken up, and the ruling's bloc move is undone with it.
func _test_a_remedy_refused_undoes_the_rulings_bloc_move() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var offsets := _offsets(ns)
	Processes.start(state, ns, _loader, _action("break_up"), firm)
	var row := _row(ns, firm)
	row["odds"] = 1.0
	for i in range(int(row["months_left"])):
		_month(state)
	if String(row["stage"]) != "remedy":
		_fail("the ruling did not open the remedy")
		return
	(ns.companies[firm] as Dictionary)["share"] = 0.05
	for i in range(K.PROCESS_REMEDY_MONTHS):
		_month(state)
	if String(row["status"]) != "refused" or bool((ns.companies[firm] as Dictionary).get("failed", false)):
		_fail("a remedy on a firm under the gate broke it up or stayed open: %s" % row)
	for bloc in OK_BLOCS:
		if not is_equal_approx(float(ns.bloc_offset.get(bloc, 0.0)), float(offsets.get(bloc, 0.0))):
			_fail("the refused remedy left the ruling's move on %s" % bloc)


## The panel's one door (Processes.execute): a process verb opens its row and
## lands nothing; any other firm verb lands at once through Companies.execute().
func _test_the_press_door_routes_by_verb() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var r: Dictionary = Processes.execute(state, ns, _loader, _action("minority_stake"), firm)
	if not bool(r.get("applied", false)) or _row(ns, firm).is_empty() or Companies.state_share_of(ns, firm) != 0.0:
		_fail("the door did not open the stake's process: %s" % r)
	var subsidy = _action("industrial_subsidy")
	var s: Dictionary = Processes.execute(state, ns, _loader, subsidy, firm)
	if not bool(s.get("applied", false)) or float((ns.companies[firm] as Dictionary).get("subsidy", 0.0)) <= 0.0:
		_fail("the door did not land a subsidy at once: %s" % s)


## Parent pass 2, TAKE 2: after the transfer the state owns the firm. A failure in
## the transition lands the ownership now; it never voids what was paid.
func _test_a_failure_in_the_transition_lands_the_ownership() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Bills.adopt(state, ns, _loader, {"action_id": "full_nationalisation", "company_id": firm})
	for i in range(K.PROCESS_OFFER_MONTHS):
		_month(state)
	var debt := float(ns.debt_eur_bn)
	(ns.companies[firm] as Dictionary)["failed"] = true
	_month(state)
	var row := _row(ns, firm)
	if Companies.state_share_of(ns, firm) != 1.0 or String(row["status"]) != "done" or float(ns.debt_eur_bn) != debt:
		_fail("a firm failing in its transition did not hand the paid-for ownership to the state: %s" % row)


## Parent pass 2, TAKE 3: the odds range is the truth's fog, as the prices are: a
## fixed width with the truth seeded inside it, so its midpoint does not give it away.
func _test_the_odds_window_does_not_centre_on_the_truth() -> void:
	var state = _new_state()
	var ns = state.player()
	var split = _action("break_up")
	var off_centre := 0
	var seen := 0
	for company in Companies.majors_of(_loader, ns.id):
		for m in range(6):
			state.month = 1 + m
			var est: Dictionary = Processes.estimate(state, ns, _loader, split, String(company.id))
			if est.is_empty():
				continue
			seen += 1
			var lo := float(est["odds_lo"])
			var hi := float(est["odds_hi"])
			if lo > float(est["odds"]) + 1e-9 or hi < float(est["odds"]) - 1e-9 \
					or not is_equal_approx(hi - lo, 2.0 * K.PROCESS_ODDS_FOG):
				_fail("the odds window %.3f..%.3f does not hold the truth %.3f at the fixed width" % [lo, hi, est["odds"]])
			if absf((lo + hi) * 0.5 - float(est["odds"])) > 0.01:
				off_centre += 1
	if seen == 0 or off_centre == 0:
		_fail("the odds window's midpoint is the truth in all %d estimates" % seen)


## Parent pass 2, TAKE 4: no foreign bid opens on a firm with a live process (its
## allow is greyed BUSY, so the bid would be a dead card). Courted firms, so the
## hazard fires; the control run without processes shows it does.
func _test_no_bid_opens_on_a_firm_in_a_process() -> void:
	var bids := [0, 0]
	for with_processes in [false, true]:
		var state = _new_state()
		var ns = state.player()
		for company in Companies.majors_of(_loader, ns.id):
			(ns.companies[company.id] as Dictionary)["courted"] = 1.0
			if with_processes:
				Processes.start(state, ns, _loader, _action("minority_stake"), String(company.id))
		for m in range(240):
			state.month += 1
			if state.month > 12:
				state.month = 1
				state.year += 1
			Industry.tick_month(state, _loader)
			var now := int(state.year) * 12 + int(state.month)
			for company in Companies.majors_of(_loader, ns.id):
				if int((ns.companies[company.id] as Dictionary).get("bid_month", -1)) == now:
					bids[1 if with_processes else 0] += 1
	if bids[0] == 0:
		_fail("the control run opened no bid, so the gate is untested")
	if bids[1] != 0:
		_fail("%d bids opened on firms with a live process" % bids[1])


## Review pass 1: stopped and reopened in one month, the new process is its own row.
func _test_a_reopened_process_has_its_own_id() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var stake = _action("minority_stake")
	var first: Dictionary = Processes.start(state, ns, _loader, stake, firm)
	Processes.stop(state, ns, _loader, String(first["process_id"]))
	var second: Dictionary = Processes.start(state, ns, _loader, stake, firm)
	if String(second.get("process_id", "")) == String(first["process_id"]):
		_fail("a process reopened the same month took the stopped one's id")
	if not bool(Processes.stop(state, ns, _loader, String(second.get("process_id", ""))).get("ok", false)):
		_fail("the reopened process could not be stopped")


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_processes")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)


## Spec 3.2: "during the transition the firm's output is 4 % below its path
## (management turnover), then recovers". As a growth addend, written by the tick:
## PROCESS_TRANSITION_OUTPUT_LOSS x the firm's output as points of GDP, scaled by the
## gap's closing (the next test sums what it loses), negative, in every month of the
## transition and in no other; the output gap's own closing is the recovery.
func _test_the_transition_drags_the_firms_output() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	# The strip shows the loss before the press (B2): a year of the firm's output x the share.
	var est: Dictionary = Processes.estimate(state, ns, _loader, _action("full_nationalisation"), firm)
	var loss_want := K.PROCESS_TRANSITION_OUTPUT_LOSS * Companies.output_eur_bn(ns, _company(ns, firm))
	if loss_want <= 0.0 or not is_equal_approx(float(est.get("output_loss_eur_bn", -1.0)), loss_want):
		_fail("the nationalisation's strip shows an output loss of %s, not %.4f bn" % [est.get("output_loss_eur_bn"), loss_want])
	Bills.adopt(state, ns, _loader, {"action_id": "full_nationalisation", "company_id": firm})
	var during := 0
	var before := true
	for i in range(K.PROCESS_OFFER_MONTHS + K.PROCESS_TRANSITION_MONTHS + 2):
		_month(state)
		var stage := String(_row(ns, firm).get("stage", ""))
		var open := String(_row(ns, firm).get("status", "")) == Processes.OPEN
		if open and stage == "transition":
			during += 1
			# Scaled by the gap's closing over the transition's years (process_drag.gd).
			var want := -K.PROCESS_TRANSITION_OUTPUT_LOSS * 100.0 * Companies.output_eur_bn(ns, _company(ns, firm)) / float(ns.gdp_eur_bn) \
				* EC.GAP_CLOSE * 12.0 / K.PROCESS_TRANSITION_MONTHS
			if want >= 0.0 or not is_equal_approx(float(ns.process_drag_pct), maxf(want, -K.PROCESS_DRAG_MAX_PCT)):
				_fail("the transition's drag is %.5f, not %.5f" % [float(ns.process_drag_pct), want])
		elif float(ns.process_drag_pct) != 0.0:
			_fail("a drag of %.5f outside the transition (stage %s, %s)" % [float(ns.process_drag_pct), stage, "before" if before else "after"])
		if stage == "transition":
			before = false
	if during != K.PROCESS_TRANSITION_MONTHS:
		_fail("the drag ran %d months, not the transition's %d" % [during, K.PROCESS_TRANSITION_MONTHS])


## The eleventh addend: Economy's growth reads the drag, a month after the tick
## that wrote it (Processes runs after Economy), with nothing else moved.
func _test_the_drag_reaches_growth() -> void:
	var still = _new_state()
	var dragged = _new_state()
	dragged.player().process_drag_pct = -0.5
	Economy.tick_month(still)
	Economy.tick_month(dragged)
	var moved := float(dragged.player().growth_annual_pct) - float(still.player().growth_annual_pct)
	if not is_equal_approx(moved, -0.5):
		_fail("a drag of -0.5 moved growth by %.5f" % moved)


## The strip must say the truth (QA's call 2 on #264, the parent's ruling): what the
## economy loses IN TOTAL, over the transition and the gap's closing after it, is the
## output loss the strip shows before the press. The drag is a growth addend and the
## gap closes at GAP_CLOSE a year, so an unscaled drag would lose its own sum divided
## by GAP_CLOSE (about 3.3 times the strip). Two worlds, Economy then Processes each
## month (the game's order) and nothing else, so their difference is the drag's alone,
## summed as GDP-years against the untreated world and compared as shares of GDP.
func _test_the_realised_loss_is_the_strips() -> void:
	var control = _new_state()
	var treated = _new_state()
	var ns = treated.player()
	var firm := _big(ns)
	var est: Dictionary = Processes.estimate(treated, ns, _loader, _action("full_nationalisation"), firm)
	var shown := float(est.get("output_loss_eur_bn", 0.0)) / float(ns.gdp_eur_bn)
	Bills.adopt(treated, ns, _loader, {"action_id": "full_nationalisation", "company_id": firm})
	var lost := 0.0
	# 20 years: the gap's tail left after the transfer is under 0.5 % of the total.
	for i in range(240):
		for state in [control, treated]:
			Economy.tick_month(state)
			_month(state)
		var c: float = float(control.player().gdp_eur_bn)
		lost += (c - float(ns.gdp_eur_bn)) / c / 12.0
	if shown <= 0.0 or absf(lost / shown - 1.0) > 0.02:
		_fail("the economy loses %.4f x the strip's output loss over the transition and its tail" % (lost / shown if shown > 0.0 else 0.0))
