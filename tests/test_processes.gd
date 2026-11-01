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

const PLAYER := "FRA"

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
