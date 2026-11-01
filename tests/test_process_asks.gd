extends SceneTree

## V5.3 a, the author's call on #244 ("each stage asks you something"): every
## process asks the player one question at its key stage, posted in that stage's
## last month and due when the stage ends, so a player who never answers gets the
## default and #244's timetable unchanged. Each ask is a B7 arrival with a strip:
##   stake           the final price      accept (default) / walk away
##   nationalisation the offer's price    pay (default) / stop with the break fee
##   break-up        the ruling, contested press on (default) / settle (a fine,
##                                       half the bloc move, the firm intact)
##   privatisation   the best bid         accept (default) / hold 3 months

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Companies = preload("res://src/sim/companies.gd")
const Processes = preload("res://src/sim/processes.gd")
const Bills = preload("res://src/sim/bills.gd")
const K = preload("res://src/sim/companies_constants.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_stake_asks_its_price_in_its_last_month()
	_test_walking_away_closes_the_stake_with_a_u_turn()
	_test_the_offer_asks_to_pay_or_stop()
	_test_a_ruling_for_the_break_up_asks_to_press_on_or_settle()
	_test_a_cleared_referral_asks_nothing()
	_test_holding_the_sale_waits_for_a_new_bid()
	_test_an_ask_is_answered_once_and_survives_a_save()
	_test_a_settled_firm_is_not_referred_again()
	_test_a_drawn_ruling_cannot_be_stopped()
	_test_every_asking_stage_lasts_two_months()
	_test_rows_are_deep_copies()
	_finish()


func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 3
	return state


func _action(id: String):
	for a in _loader.company_actions:
		if String(a.id) == id:
			return a
	return null


func _big(ns) -> String:
	var best := ""
	var share := -1.0
	for company in Companies.majors_of(_loader, ns.id):
		var s := Companies.share_of_company(ns, company)
		if s > share:
			share = s
			best = String(company.id)
	return best


func _month(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	Processes.tick_month(state, _loader)


func _row(ns, company_id: String) -> Dictionary:
	for row in ns.processes:
		if String(row["company_id"]) == company_id:
			return row
	return {}


func _answer_ids(ask: Dictionary) -> Array:
	return (ask.get("answers", []) as Array).map(func(a) -> String: return String(a["id"]))


func _test_the_stake_asks_its_price_in_its_last_month() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("minority_stake"), firm)
	if not Processes.asks(ns).is_empty():
		_fail("the stake asked before its negotiation's last month")
	_month(state)
	var asks: Array = Processes.asks(ns)
	if asks.size() != 1:
		_fail("the stake's last month posted %d asks, not 1" % asks.size())
		return
	var ask: Dictionary = asks[0]["ask"]
	if _answer_ids(ask) != ["accept", "walk"] or String(ask["default"]) != "accept":
		_fail("the stake's ask is %s, not accept (default) / walk" % [ask])
	var accept: Dictionary = ask["answers"][0]
	var row := _row(ns, firm)
	if not is_equal_approx(float(accept["debt_eur_bn"]), float(row["base_eur_bn"]) * (1.0 + float(row["rate"]))):
		_fail("the accept answer's money is not the fixed price")
	# Unanswered, the default lands on #244's timetable.
	_month(state)
	if Companies.state_share_of(ns, firm) <= 0.0 or String(row["status"]) != "done":
		_fail("an unanswered price ask did not take its default (accept) on time")


func _test_walking_away_closes_the_stake_with_a_u_turn() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("minority_stake"), firm)
	_month(state)
	var row := _row(ns, firm)
	var debt := float(ns.debt_eur_bn)
	var workers := float(ns.bloc_offset.get("workers", 0.0))
	var r: Dictionary = Processes.answer(state, ns, _loader, String(row["id"]), "walk")
	if not bool(r.get("ok", false)) or String(row["status"]) != "stopped":
		_fail("walking away did not close the stake: %s" % r)
	if float(ns.debt_eur_bn) != debt or float(ns.bloc_offset.get("workers", 0.0)) >= workers:
		_fail("walking away cost money, or no U-turn on the blocs the stake pleased")
	_month(state)
	if Companies.state_share_of(ns, firm) != 0.0:
		_fail("a stake walked away from still transferred")


func _test_the_offer_asks_to_pay_or_stop() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Bills.adopt(state, ns, _loader, {"action_id": "full_nationalisation", "company_id": firm})
	_month(state)
	var row := _row(ns, firm)
	var ask: Dictionary = row.get("ask", {})
	if _answer_ids(ask) != ["pay", "stop"] or String(ask.get("default", "")) != "pay":
		_fail("the offer's ask is %s, not pay (default) / stop" % [ask])
		return
	var premium := float(row["base_eur_bn"]) * float(row["rate"])
	if not is_equal_approx(float(ask["answers"][1]["debt_eur_bn"]), K.PROCESS_BREAK_FEE * premium):
		_fail("the stop answer's money is not the break fee")
	var debt := float(ns.debt_eur_bn)
	Processes.answer(state, ns, _loader, String(row["id"]), "stop")
	if String(row["status"]) != "stopped" or not is_equal_approx(float(ns.debt_eur_bn) - debt, K.PROCESS_BREAK_FEE * premium):
		_fail("stopping at the offer's ask did not charge the break fee")


func _test_a_ruling_for_the_break_up_asks_to_press_on_or_settle() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("break_up"), firm)
	var row := _row(ns, firm)
	row["odds"] = 1.0
	var inquiry := int(row["months_left"])
	for i in range(inquiry - 1):
		_month(state)
	var ask: Dictionary = row.get("ask", {})
	if _answer_ids(ask) != ["press_on", "settle"] or String(ask.get("default", "")) != "press_on":
		_fail("a ruling for the break-up asked %s, not press on (default) / settle" % [ask])
		return
	var debt := float(ns.debt_eur_bn)
	var business := float(ns.bloc_offset.get("business", 0.0))
	Processes.answer(state, ns, _loader, String(row["id"]), "settle")
	_month(state)
	var value := Companies.value_eur_bn(ns, Companies.majors_of(_loader, "FRA").filter(func(c) -> bool: return String(c.id) == firm)[0])
	if String(row["status"]) != "settled" or bool((ns.companies[firm] as Dictionary).get("failed", false)):
		_fail("a settled break-up was not closed settled with the firm intact: %s" % row)
	var moved := float(ns.bloc_offset.get("business", 0.0)) - business
	var full := float((_action("break_up").effects["bloc_offset"] as Dictionary)["business"])
	if not is_equal_approx(moved, full * K.PROCESS_SETTLEMENT_BLOC):
		_fail("the settlement moved business by %.4f, not %.4f" % [moved, full * K.PROCESS_SETTLEMENT_BLOC])
	var expect := K.PROCESS_LEGAL_COST_EUR_BN - K.PROCESS_SETTLEMENT_FINE * value
	if absf(float(ns.debt_eur_bn) - debt - expect) > 1e-6:
		_fail("the settlement moved the debt by %.4f, not the fees less the fine %.4f" % [float(ns.debt_eur_bn) - debt, expect])


func _test_a_cleared_referral_asks_nothing() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("break_up"), firm)
	var row := _row(ns, firm)
	row["odds"] = 0.0
	for i in range(int(row["months_left"])):
		_month(state)
		if not (row.get("ask", {}) as Dictionary).is_empty():
			_fail("a referral the authority clears asked the player something")
			return
	if String(row["status"]) != "cleared":
		_fail("the cleared referral did not close cleared: %s" % row)


func _test_holding_the_sale_waits_for_a_new_bid() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	(ns.companies[firm] as Dictionary)["state_share"] = 1.0
	Bills.adopt(state, ns, _loader, {"action_id": "privatisation", "company_id": firm})
	for i in range(K.PROCESS_SALE_MONTHS - 1):
		_month(state)
	var row := _row(ns, firm)
	var ask: Dictionary = row.get("ask", {})
	if _answer_ids(ask) != ["accept", "hold"] or String(ask.get("default", "")) != "accept":
		_fail("the sale's ask is %s, not accept (default) / hold" % [ask])
		return
	Processes.answer(state, ns, _loader, String(row["id"]), "hold")
	_month(state)
	if Companies.state_share_of(ns, firm) != 1.0 or String(row["status"]) != "open":
		_fail("a held sale sold anyway")
	for i in range(K.PROCESS_HOLD_MONTHS - 1):
		_month(state)
	# One hold only (pass 1 on #248): the new bid is priced in its last month and
	# asks nothing, so a sale cannot be held without end.
	if not (row.get("ask", {}) as Dictionary).is_empty():
		_fail("a sale held once asked again: %s" % [row["ask"]])
	var windfall := -float(row["base_eur_bn"]) * (1.0 - float(row["rate"]))
	var debt := float(ns.debt_eur_bn)
	_month(state)
	if Companies.state_share_of(ns, firm) != 0.0 or not is_equal_approx(float(ns.debt_eur_bn) - debt, windfall):
		_fail("the new bid did not sell at the price it was priced at")
	# A3: the held sale still lands inside the duration its strip showed.
	var months := int(row["closed"]) - int(row["started"])
	if months < int(row["months_lo"]) or months > int(row["months_hi"]):
		_fail("A3: the held sale took %d months against %s..%s" % [months, row["months_lo"], row["months_hi"]])


func _test_an_ask_is_answered_once_and_survives_a_save() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("minority_stake"), firm)
	_month(state)
	var id := String(_row(ns, firm)["id"])
	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if Processes.asks(kept.player()).size() != 1:
		_fail("a posted ask did not survive the round trip")
	if bool(Processes.answer(state, ns, _loader, id, "nonsense").get("ok", true)):
		_fail("an answer the ask does not offer was taken")
	Processes.answer(state, ns, _loader, id, "accept")
	if bool(Processes.answer(state, ns, _loader, id, "walk").get("ok", true)):
		_fail("an ask was answered twice")
	if not Processes.asks(ns).is_empty():
		_fail("an answered ask is still listed as waiting")
	# The loaded copy answers and resolves too (its numbers came back through JSON).
	var kept_ns = kept.player()
	if not bool(Processes.answer(kept, kept_ns, _loader, id, "walk").get("ok", false)):
		_fail("the loaded ask could not be answered")
	if String(_row(kept_ns, firm)["status"]) != "stopped":
		_fail("walking away on the loaded ask did not stop the stake")


## Pass 1 on #248: a settlement leaves the firm intact, so without this rule a
## referral-then-settle would be a fine collected again every year. The refusal is
## the door's own line, read before the press (A5).
func _test_a_settled_firm_is_not_referred_again() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var verb = _action("break_up")
	Processes.start(state, ns, _loader, verb, firm)
	var row := _row(ns, firm)
	row["odds"] = 1.0
	for i in range(int(row["months_left"]) - 1):
		_month(state)
	Processes.answer(state, ns, _loader, String(row["id"]), "settle")
	_month(state)
	if String(row["status"]) != "settled":
		_fail("the settlement fixture did not settle: %s" % row)
		return
	if Processes.refusal(ns, firm, verb) != Processes.SETTLED:
		_fail("a settled firm's break-up is not refused before the press")
	if bool(Processes.start(state, ns, _loader, verb, firm).get("applied", false)):
		_fail("a settled firm was referred again")


## Pass 1 on #248: the ruling is drawn with its ask, a month before the
## investigation ends; once it is drawn the process is past stopping, as after any
## ruling, whichever way it went.
func _test_a_drawn_ruling_cannot_be_stopped() -> void:
	for odds in [1.0, 0.0]:
		var state = _new_state()
		var ns = state.player()
		var firm := _big(ns)
		Processes.start(state, ns, _loader, _action("break_up"), firm)
		var row := _row(ns, firm)
		row["odds"] = odds
		if not bool(Processes.stop_price(state, ns, _loader, String(row["id"]))["ok"]):
			_fail("an investigation could not be stopped before its ruling")
		for i in range(int(row["months_left"]) - 1):
			_month(state)
		if bool(Processes.stop_price(state, ns, _loader, String(row["id"]))["ok"]):
			_fail("an investigation was stoppable after its ruling was drawn (odds %.0f)" % odds)


## The ask (and the break-up's ruling) is posted when a stage reaches its last
## month by a decrement, so a stage of one month would ask nothing and rule nothing.
func _test_every_asking_stage_lasts_two_months() -> void:
	for months in [K.PROCESS_STAKE_MONTHS, K.PROCESS_OFFER_MONTHS, K.PROCESS_SALE_MONTHS,
			K.PROCESS_HOLD_MONTHS, K.PROCESS_INVESTIGATION_MONTHS.x]:
		if int(months) < 2:
			_fail("a stage that asks lasts %d month(s); the ask needs two" % int(months))


## rows() is what a panel reads: a deep copy, so nothing the panel does reaches the
## register (rule 2), the nested ask included.
func _test_rows_are_deep_copies() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("minority_stake"), firm)
	_month(state)
	var copy: Dictionary = Processes.rows(ns)[0]
	(copy["ask"]["answers"] as Array).clear()
	if ((_row(ns, firm)["ask"] as Dictionary)["answers"] as Array).is_empty():
		_fail("rows() handed the panel the register's own ask")


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_process_asks")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
