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
const Cycle = preload("res://src/sim/cycle.gd")
const Asks = preload("res://src/sim/process_asks.gd")
const Negotiation = preload("res://src/sim/negotiation.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")

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
	_test_a_referral_saved_before_the_asks_is_still_ruled()
	_test_a_sale_saved_before_the_asks_is_still_priced()
	_test_a_price_ask_offers_three_counters()
	_test_a_counter_is_accepted_comes_back_or_walks()
	_test_a_counter_that_comes_back_reopens_the_ask()
	_test_a_sale_that_comes_back_keeps_its_old_price()
	_test_an_offer_and_a_sale_land_at_their_counter_or_old_price()
	_test_the_cycle_moves_a_purchase_counter_not_a_sale()
	_test_no_answer_is_dominated()
	_test_a_counter_survives_a_save()
	_test_an_answered_counter_cannot_be_stopped()
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


func _company(ns, company_id: String):
	for c in Companies.majors_of(_loader, ns.id):
		if String(c.id) == company_id:
			return c
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
	if _answer_ids(ask) != ["accept", "walk"] + NEGOTIATE_IDS or String(ask["default"]) != "accept":
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
	if _answer_ids(ask) != ["pay", "stop"] + NEGOTIATE_IDS or String(ask.get("default", "")) != "pay":
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
	if _answer_ids(ask) != ["accept", "hold"] + NEGOTIATE_IDS or String(ask.get("default", "")) != "accept":
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
## referral-then-settle would be a fine collected again every year. The parent's
## call: the refusal holds for PROCESS_SETTLED_COOLDOWN_MONTHS after the settlement,
## then the firm can be referred again. The refusal is the door's own line, read
## before the press (A5).
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
	if Processes.refusal(state, ns, firm, verb) != Processes.SETTLED:
		_fail("a settled firm's break-up is not refused before the press")
	# The firm panel's button greys with the same line before the press (A5).
	var button: Button = CompanyVerb.button(state, _loader, ns, _company(ns, firm), verb)
	if not button.disabled or not button.tooltip_text.contains(Processes.SETTLED):
		_fail("the break-up button of a settled firm is not greyed with SETTLED")
	button.free()
	if bool(Processes.start(state, ns, _loader, verb, firm).get("applied", false)):
		_fail("a settled firm was referred again")
	# The last month of the cooldown still refuses; the month after it does not.
	var settled_at := int(row["closed"])
	# The parent's 36 months, as literals (QA on #248: a test that read the constant
	# stayed green at 35 and 37).
	_at(state, settled_at + 35)
	if Processes.refusal(state, ns, firm, verb) != Processes.SETTLED:
		_fail("a settled firm could be referred again before its cooldown ended")
	_at(state, settled_at + 36)
	if Processes.refusal(state, ns, firm, verb) != "":
		_fail("a settled firm is still refused after its cooldown")
	if not bool(Processes.start(state, ns, _loader, verb, firm).get("applied", false)):
		_fail("a settled firm could not be referred again after its cooldown")


func _at(state, month_index: int) -> void:
	state.year = (month_index - 1) / 12
	state.month = month_index - state.year * 12


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



## QA on #248: a row saved before the asks merged, loaded in its stage's last month,
## reaches its end with no ask posted. A referral draws its ruling there (on the
## same seed), instead of always closing cleared.
func _test_a_referral_saved_before_the_asks_is_still_ruled() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("break_up"), firm)
	var row := _row(ns, firm)
	row["odds"] = 1.0
	for i in range(int(row["months_left"]) - 1):
		_month(state)
	# The pre-#248 row: no ruling drawn, no ask.
	row.erase("ruled")
	row.erase("ask")
	_month(state)
	if String(row["stage"]) != "remedy":
		_fail("a pre-asks referral at its end did not draw its ruling: %s" % row)


## The same for a sale: priced at the stage's end with the cycle's discount then,
## not at the start's rate of 0.
func _test_a_sale_saved_before_the_asks_is_still_priced() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	(ns.companies[firm] as Dictionary)["state_share"] = 1.0
	Bills.adopt(state, ns, _loader, {"action_id": "privatisation", "company_id": firm})
	for i in range(K.PROCESS_SALE_MONTHS - 1):
		_month(state)
	var row := _row(ns, firm)
	row.erase("ask")
	row["rate"] = 0.0
	# A downturn deep enough for the whole discount range.
	ns.gdp_eur_bn = ns.potential_gdp_eur_bn * (1.0 - K.PROCESS_DISCOUNT_GAP_PCT / 100.0)
	# Pass 1 on #257: with no discount at this gap the fix and its absence book the
	# same money, and the test would pass without the fix.
	if Asks.discount(ns) <= 0.0:
		_fail("the downturn fixture gives the sale no discount")
		return
	var debt := float(ns.debt_eur_bn)
	_month(state)
	var want := -float(row["base_eur_bn"]) * (1.0 - Asks.discount(ns))
	if String(row["status"]) != "done" or not is_equal_approx(float(ns.debt_eur_bn) - debt, want):
		_fail("a pre-asks sale at its end booked %.4f, not the discounted %.4f" % [float(ns.debt_eur_bn) - debt, want])


# --- Negotiate (V5.3 b, src/sim/negotiation.gd; the author's idea, the parent's calls) ---

const NEGOTIATE_IDS := ["negotiate_5", "negotiate_10", "negotiate_15"]


## Every price ask offers three counters beside its own answers: the price moved by
## the counter (less to pay, more to receive), the old price if the other side comes
## back, the true odds (never shown) inside the range the strip shows, the walk risk,
## and the deal's own bloc move.
func _test_a_price_ask_offers_three_counters() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("minority_stake"), firm)
	_month(state)
	_check_counters(ns, _row(ns, firm), false, "the stake")
	var s2 = _new_state()
	var ns2 = s2.player()
	Bills.adopt(s2, ns2, _loader, {"action_id": "full_nationalisation", "company_id": firm})
	_month(s2)
	_check_counters(ns2, _row(ns2, firm), false, "the offer")
	var s3 = _new_state()
	var ns3 = s3.player()
	(ns3.companies[firm] as Dictionary)["state_share"] = 1.0
	Bills.adopt(s3, ns3, _loader, {"action_id": "privatisation", "company_id": firm})
	for i in range(K.PROCESS_SALE_MONTHS - 1):
		_month(s3)
	_check_counters(ns3, _row(ns3, firm), true, "the sale")


func _check_counters(ns, row: Dictionary, sale: bool, label: String) -> void:
	var ask: Dictionary = row.get("ask", {})
	var answers: Array = ask.get("answers", [])
	if answers.size() != 5 or _answer_ids(ask).slice(2) != NEGOTIATE_IDS:
		_fail("%s's ask offers %s, not its two answers and the three counters" % [label, _answer_ids(ask)])
		return
	var deal: Dictionary = answers[0]
	var price := float(deal["debt_eur_bn"])
	for i in 3:
		var a: Dictionary = answers[2 + i]
		var c := float(K.NEGOTIATE_COUNTERS[i])
		var want := price * (1.0 + c) if sale else price * (1.0 - c)
		var p := float(a.get("odds", -1.0))
		if float(a.get("counter", -1.0)) != c or not is_equal_approx(float(a.get("debt_eur_bn", 0.0)), want) \
				or float(a.get("back_debt_eur_bn", 0.0)) != price or a.get("bloc_offset") != deal["bloc_offset"] \
				or float(a.get("walk", -1.0)) != K.NEGOTIATE_WALK:
			_fail("%s's %s reads %s against the deal's price %.4f" % [label, a["id"], a, price])
		if not is_equal_approx(p, Negotiation.odds(c, Negotiation.leverage(ns, String(row["stage"])))):
			_fail("%s's %s carries odds %.4f, not the counter's at the cycle's leverage" % [label, a["id"], p])
		if p < float(a.get("odds_lo", 2.0)) or p > float(a.get("odds_hi", -1.0)) \
				or not is_equal_approx(float(a["odds_hi"]) - float(a["odds_lo"]), 2.0 * K.NEGOTIATE_FOG):
			_fail("%s's %s shows %s..%s for a true %.4f" % [label, a["id"], a.get("odds_lo"), a.get("odds_hi"), p])


## A counter is answered at the ask's due month on its own seed: accepted lands the
## countered price inside the strip's range; back runs one more month at the old price
## and asks again without the counters; walked ends the deal with nothing paid, no
## U-turn (the start's half of the bloc move stays) and the firm's purchases held for
## 24 months (the parent's call 1, pinned as the literal; _check_hold).
func _test_a_counter_is_accepted_comes_back_or_walks() -> void:
	var seen := {}
	for trial in 60:
		var state = _new_state()
		state.month = 1 + trial % 12
		state.year = 2026 + floori(trial / 12.0)
		var ns = state.player()
		var firm := _big(ns)
		Processes.start(state, ns, _loader, _action("minority_stake"), firm)
		_month(state)
		var row := _row(ns, firm)
		var id := String(NEGOTIATE_IDS[trial % 3])
		var a := Asks.answer_of(row, id)
		if a.is_empty():
			_fail("the stake's ask offers no %s" % id)
			return
		var outcome := Negotiation.draw(float(a["odds"]), "%s|%s" % [String(row["id"]), id], int(row["ask"]["due"]))
		if seen.has(outcome):
			continue
		seen[outcome] = true
		var debt := float(ns.debt_eur_bn)
		var blocs: Dictionary = (ns.bloc_offset as Dictionary).duplicate()
		if not bool(Processes.answer(state, ns, _loader, String(row["id"]), id).get("ok", false)):
			_fail("answering %s was refused" % id)
			return
		_month(state)
		var record: Dictionary = row.get("negotiation", {})
		if String(record.get("outcome", "")) != outcome or String(record.get("answer", "")) != id:
			_fail("the row records %s, not the %s drawn for %s" % [record, outcome, id])
		match outcome:
			"accepted":
				var paid := float(ns.debt_eur_bn) - debt
				if String(row["status"]) != "done" or not is_equal_approx(paid, float(a["debt_eur_bn"])) \
						or Companies.state_share_of(ns, firm) <= 0.0 or float(row.get("countered", -1.0)) != float(a["counter"]):
					_fail("an accepted %s paid %.4f (not %.4f) or did not transfer: %s" % [id, paid, float(a["debt_eur_bn"]), row["status"]])
				if paid < float(row["price_lo"]) - 1e-9 or paid > float(row["price_hi"]) + 1e-9:
					_fail("A4: an accepted %s paid %.4f, outside the strip's %.4f..%.4f" % [id, paid, float(row["price_lo"]), float(row["price_hi"])])
			"back":
				var again: Dictionary = row.get("ask", {})
				if String(row["status"]) != "open" or int(row["months_left"]) != 1 or float(ns.debt_eur_bn) != debt \
						or _answer_ids(again) != ["accept", "walk"] or int(again.get("posted", -1)) != _now(state):
					_fail("a %s that came back is %s, months left %s, asking %s" % [id, row["status"], row["months_left"], again])
				_month(state)
				if String(row["status"]) != "done" or not is_equal_approx(float(ns.debt_eur_bn) - debt, float(a["back_debt_eur_bn"])):
					_fail("a stake that came back did not land at its old price %.4f (paid %.4f)" % [float(a["back_debt_eur_bn"]), float(ns.debt_eur_bn) - debt])
				var months := int(row["closed"]) - int(row["started"])
				if months > int(row["months_hi"]):
					_fail("A3: a stake that came back took %d months against %s" % [months, row["months_hi"]])
			"walked":
				if String(row["status"]) != "walked" or float(ns.debt_eur_bn) != debt or Companies.state_share_of(ns, firm) != 0.0 \
						or ns.bloc_offset != blocs:
					_fail("a walked %s is %s, paid %.4f, or moved the blocs" % [id, row["status"], float(ns.debt_eur_bn) - debt])
				_check_hold(state, ns, row, "the stake's walked %s" % id)
		if seen.size() == 3:
			break
	if seen.size() < 3:
		_fail("60 seeded trials drew only %s" % [seen.keys()])


## QA on #280: a counter that comes back reopens the ask ("A counter that comes back
## reopens it"). The answered counter is cleared, so the re-ask reaches the player, the
## deal can be stopped again, and walking closes it stopped with the U-turn's blocs and
## no money. Without the clearing the deal lands at the old price with no way to refuse.
func _test_a_counter_that_comes_back_reopens_the_ask() -> void:
	for trial in 60:
		var state = _new_state()
		state.month = 1 + trial % 12
		state.year = 2026 + floori(trial / 12.0)
		var ns = state.player()
		var firm := _big(ns)
		Processes.start(state, ns, _loader, _action("minority_stake"), firm)
		_month(state)
		var row := _row(ns, firm)
		var id := String(NEGOTIATE_IDS[trial % 3])
		var a := Asks.answer_of(row, id)
		if Negotiation.draw(float(a["odds"]), "%s|%s" % [String(row["id"]), id], int(row["ask"]["due"])) != "back":
			continue
		Processes.answer(state, ns, _loader, String(row["id"]), id)
		_month(state)
		var listed := false
		for asked in Processes.asks(ns):
			listed = listed or String(asked["id"]) == String(row["id"])
		if not listed:
			_fail("a counter that came back does not reach the player: %s" % [row.get("answer", "")])
		var price: Dictionary = Processes.stop_price(state, ns, _loader, String(row["id"]))
		if not bool(price.get("ok", false)):
			_fail("a counter that came back cannot be stopped: %s" % price)
			return
		var debt := float(ns.debt_eur_bn)
		var workers := float(ns.bloc_offset.get("workers", 0.0))
		var r: Dictionary = Processes.answer(state, ns, _loader, String(row["id"]), "walk")
		if not bool(r.get("ok", false)) or String(row["status"]) != "stopped":
			_fail("walking from a counter that came back did not stop the deal: %s, %s" % [r, row["status"]])
		if float(ns.debt_eur_bn) != debt or float(ns.bloc_offset.get("workers", 0.0)) >= workers:
			_fail("walking from a counter that came back cost money, or no U-turn on the blocs")
		_month(state)
		if Companies.state_share_of(ns, firm) != 0.0:
			_fail("a deal walked from after its counter came back still transferred")
		return
	_fail("60 seeded trials drew no stake counter that comes back")


## A sale's counter that comes back keeps the bid's OLD price, though the cycle turned
## between the bid and the answer (the re-posted ask is not re-priced).
func _test_a_sale_that_comes_back_keeps_its_old_price() -> void:
	for trial in 60:
		var state = _new_state()
		state.month = 1 + trial % 12
		state.year = 2026 + floori(trial / 12.0)
		var ns = state.player()
		var firm := _big(ns)
		(ns.companies[firm] as Dictionary)["state_share"] = 1.0
		Bills.adopt(state, ns, _loader, {"action_id": "privatisation", "company_id": firm})
		for i in range(K.PROCESS_SALE_MONTHS - 1):
			_month(state)
		var row := _row(ns, firm)
		var id := String(NEGOTIATE_IDS[trial % 3])
		var a := Asks.answer_of(row, id)
		if a.is_empty() or Negotiation.draw(float(a["odds"]), "%s|%s" % [String(row["id"]), id], int(row["ask"]["due"])) != "back":
			continue
		var rate := float(row["rate"])
		Processes.answer(state, ns, _loader, String(row["id"]), id)
		# A downturn between the bid and the answer: a fresh bid would be discounted.
		ns.potential_gdp_eur_bn = float(ns.gdp_eur_bn) * 1.03
		_month(state)
		var deal := Asks.answer_of(row, "accept")
		if float(row["rate"]) != rate or deal.is_empty() or float(deal["debt_eur_bn"]) != float(a["back_debt_eur_bn"]):
			_fail("a sale that came back re-priced its bid: rate %.4f -> %.4f, accept %s" % [rate, float(row["rate"]), deal])
		return
	_fail("60 seeded trials drew no sale counter that comes back")


## QA on #280: the counter's price and the strips' widening hold on the offer and the
## sale as on the stake. On each verb seeded trials find each outcome: accepted books
## the counter's price inside the strip's range (A4) -- on the offer the largest
## counter, the one that books under the premium's floor; back books the old price a
## month later, and a sale that comes back and is then held sells at a new bid, its
## longest road; every deal run to its end closes inside the strip's months (A3). A walk
## holds its own side's verbs only (_check_hold). Each outcome is said for one month.
func _test_an_offer_and_a_sale_land_at_their_counter_or_old_price() -> void:
	for kind in ["full_nationalisation", "privatisation"]:
		var legs := {}
		for trial in 120:
			var row: Dictionary = _at_the_price_ask(kind, trial)[2]
			for id in NEGOTIATE_IDS:
				var a := Asks.answer_of(row, id)
				if a.is_empty():
					_fail("the %s's ask offers no %s" % [kind, id])
					return
				var outcome := Negotiation.draw(float(a["odds"]), Negotiation.key(row, id), int(row["ask"]["due"]))
				if legs.has(outcome) or (outcome == "accepted" and kind == "full_nationalisation" and id != "negotiate_15"):
					continue
				legs[outcome] = true
				_check_leg(kind, trial, id, outcome, "accept")
				if outcome == "back" and kind == "privatisation":
					_check_leg(kind, trial, id, outcome, "hold")
			if legs.size() == 3:
				break
		if legs.size() < 3:
			_fail("120 seeded %s trials drew only %s" % [kind, legs.keys()])


## [state, ns, row]: `kind` adopted by its bill in `trial`'s month and run to its price
## ask (a sale of a firm the state owns whole).
func _at_the_price_ask(kind: String, trial: int) -> Array:
	var state = _new_state()
	state.month = 1 + trial % 12
	state.year = 2026 + floori(trial / 12.0)
	var ns = state.player()
	var firm := _big(ns)
	if kind == "privatisation":
		(ns.companies[firm] as Dictionary)["state_share"] = 1.0
	Bills.adopt(state, ns, _loader, {"action_id": kind, "company_id": firm})
	var months := K.PROCESS_SALE_MONTHS if kind == "privatisation" else K.PROCESS_OFFER_MONTHS
	for i in range(months - 1):
		_month(state)
	return [state, ns, _row(ns, firm)]


## One seeded leg: `kind` on `trial`'s month, `id` answered at its price ask and drawn
## `outcome`; after a "back", `then` answers the ask posted again.
func _check_leg(kind: String, trial: int, id: String, outcome: String, then: String) -> void:
	var at: Array = _at_the_price_ask(kind, trial)
	var state = at[0]
	var ns = at[1]
	var row: Dictionary = at[2]
	var label := "the %s's %s %s (then %s)" % [kind, id, outcome, then]
	var a := Asks.answer_of(row, id)
	var debt := float(ns.debt_eur_bn)
	Processes.answer(state, ns, _loader, String(row["id"]), id)
	_month(state)
	if String((row.get("negotiation", {}) as Dictionary).get("outcome", "")) != outcome:
		_fail("%s: the row drew %s" % [label, row.get("negotiation")])
		return
	if String(_said(state, ns, row).get("outcome", "")) != outcome:
		_fail("%s: closed_last_month() says %s" % [label, _said(state, ns, row)])
	match outcome:
		"accepted":
			var paid := float(ns.debt_eur_bn) - debt
			if not is_equal_approx(paid, float(a["debt_eur_bn"])):
				_fail("%s booked %.4f, not the counter's %.4f" % [label, paid, float(a["debt_eur_bn"])])
			if paid < float(row["price_lo"]) - 1e-9 or paid > float(row["price_hi"]) + 1e-9:
				_fail("A4: %s booked %.4f, outside the strip's %.4f..%.4f" % [label, paid, float(row["price_lo"]), float(row["price_hi"])])
		"back":
			if then == "hold":
				Processes.answer(state, ns, _loader, String(row["id"]), "hold")
			debt = float(ns.debt_eur_bn)
			_month(state)
			var paid := float(ns.debt_eur_bn) - debt
			if then == "accept" and not is_equal_approx(paid, float(a["back_debt_eur_bn"])):
				_fail("%s booked %.4f a month later, not the old price %.4f" % [label, paid, float(a["back_debt_eur_bn"])])
		"walked":
			_check_hold(state, ns, row, label)
			return
	var ran := false
	for i in K.PROCESS_TRANSITION_MONTHS + K.PROCESS_HOLD_MONTHS + 2:
		if String(row["status"]) != "open":
			break
		_month(state)
		ran = true
	var months := int(row["closed"]) - int(row["started"])
	if String(row["status"]) != "done" or months < int(row["months_lo"]) or months > int(row["months_hi"]):
		_fail("A3: %s ended %s after %d months against %s..%s" % [label, row["status"], months, row["months_lo"], row["months_hi"]])
	# A landing after the counter's month is said as landed, not accepted again.
	if ran and String(_said(state, ns, row).get("outcome", "")) != "landed":
		_fail("%s: its landing is said as %s" % [label, _said(state, ns, row)])


## A walk holds the walked side's verbs on the firm -- the purchases after the seller
## walks, the sale after the buyers do -- and only them (the parent's ruling on #280),
## until the line's hold_ends, the first month they open again: 24 months on (the
## parent's call 1, pinned as the literal). The line is said in the walk's month only.
func _check_hold(state, ns, row: Dictionary, label: String) -> void:
	var said := _said(state, ns, row)
	var sale := String(row["action_id"]) == "privatisation"
	var closed := int(row["closed"])
	if String(row["status"]) != "walked" or String(said.get("outcome", "")) != "walked" \
			or String(said.get("side", "")) != ("buyers" if sale else "seller") or int(said.get("hold_ends", -1)) != closed + 24:
		_fail("%s: the row is %s, said %s" % [label, row["status"], said])
		return
	var held: Array = ["privatisation"] if sale else ["minority_stake", "full_nationalisation"]
	var free: Array = ["minority_stake", "full_nationalisation"] if sale else ["privatisation"]
	var firm := String(row["company_id"])
	for now in [closed, closed + 23, closed + 24]:
		_set_now(state, now)
		var why := (Negotiation.BUYERS_WALKED if sale else Negotiation.SELLER_WALKED) if now < closed + 24 else ""
		for verb in held:
			if Processes.refusal(state, ns, firm, _action(verb)) != why:
				_fail("%s: %d months on, %s is refused with '%s', not '%s'" % [label, now - closed, verb, Processes.refusal(state, ns, firm, _action(verb)), why])
		for verb in free:
			if Processes.refusal(state, ns, firm, _action(verb)) != "":
				_fail("%s: the other side's %s is held: '%s'" % [label, verb, Processes.refusal(state, ns, firm, _action(verb))])
	_set_now(state, closed + 1)
	if not _said(state, ns, row).is_empty():
		_fail("%s: the walk is still said a month later" % label)
	_set_now(state, closed)


## closed_last_month()'s line for `row` now, {} when it says nothing of it.
func _said(state, ns, row: Dictionary) -> Dictionary:
	var out := {}
	for line in Asks.closed_last_month(state, ns):
		if String(line["id"]) != String(row["id"]):
			continue
		if not out.is_empty():
			_fail("closed_last_month() says %s twice" % row["id"])
		out = line
		if int(out["month"]) != _now(state) or String(out["company_id"]) != String(row["company_id"]) \
				or String(out["action_id"]) != String(row["action_id"]):
			_fail("closed_last_month()'s line %s does not match its row" % [out])
	return out


## The other side's strength follows the cycle on a purchase (a seller is strong in a
## boom, weak in a downturn: the discount's own PROCESS_DISCOUNT_GAP_PCT) and is none
## on a sale (the parent's call 2: the discount already carries the cycle).
func _test_the_cycle_moves_a_purchase_counter_not_a_sale() -> void:
	var state = _new_state()
	var ns = state.player()
	for pair in [[-3.0, -1.0], [0.0, 0.0], [3.0, 1.0], [-1.5, -0.5]]:
		ns.potential_gdp_eur_bn = float(ns.gdp_eur_bn) / (1.0 + float(pair[0]) / 100.0)
		for stage in ["negotiation", "offer"]:
			if not is_equal_approx(Negotiation.leverage(ns, stage), float(pair[1])):
				_fail("a %.1f %% gap gives the %s leverage %.4f, not %.1f" % [float(pair[0]), stage, Negotiation.leverage(ns, stage), float(pair[1])])
		if Negotiation.leverage(ns, "sale") != 0.0:
			_fail("a %.1f %% gap moves a sale's leverage" % float(pair[0]))


## No answer of a price ask is beaten on every figure (the parent's merge gate), over
## the counters and the cycle. Four figures, from the posted answers: the expected
## cash booked (lower is better), the chance the deal completes, the price if it
## lands (lower is better; none for a walk or a stop) and the expected bloc move.
## Walking wins the cash, accepting the completion, a counter the price. Holding a
## sale sells later at a new bid; with no forecast of the cycle its expected figures
## are the bid's, so it ties accept. (Net of the asset bought, a 15 % counter on a
## 5 % premium would beat walking on every figure: that is why the price, not the
## net position, is a figure.)
func _test_no_answer_is_dominated() -> void:
	var firm := ""
	for gap in [-3.0, 0.0, 3.0]:
		for kind in ["minority_stake", "full_nationalisation", "privatisation"]:
			var state = _new_state()
			var ns = state.player()
			firm = _big(ns)
			ns.potential_gdp_eur_bn = float(ns.gdp_eur_bn) / (1.0 + float(gap) / 100.0)
			if kind == "minority_stake":
				Processes.start(state, ns, _loader, _action(kind), firm)
				_month(state)
			elif kind == "full_nationalisation":
				Bills.adopt(state, ns, _loader, {"action_id": kind, "company_id": firm})
				_month(state)
			else:
				(ns.companies[firm] as Dictionary)["state_share"] = 1.0
				Bills.adopt(state, ns, _loader, {"action_id": kind, "company_id": firm})
				for i in range(K.PROCESS_SALE_MONTHS - 1):
					_month(state)
			var answers: Array = (_row(ns, firm).get("ask", {}) as Dictionary).get("answers", [])
			if answers.size() != 5:
				_fail("%s at a %.0f %% gap asks %d answers, not 5" % [kind, gap, answers.size()])
				continue
			var figures: Array = []
			for a in answers:
				figures.append(_figures(a, answers[0]))
			for i in figures.size():
				for j in figures.size():
					if i != j and _dominates(figures[j], figures[i]):
						_fail("%s at a %.0f %% gap: %s beats %s on every figure (%s against %s)" % [
							kind, gap, answers[j]["id"], answers[i]["id"], figures[j], figures[i]])


## An answer's four figures, each oriented so that higher is better.
func _figures(a: Dictionary, deal: Dictionary) -> Array:
	var id := String(a["id"])
	if id == "hold":
		a = deal
	var bloc := 0.0
	for b in a["bloc_offset"]:
		bloc += float(a["bloc_offset"][b])
	if id.begins_with("negotiate_"):
		var p := float(a["odds"])
		var lands := p + (1.0 - p) * (1.0 - float(a["walk"]))
		var cash := p * float(a["debt_eur_bn"]) + (1.0 - p) * (1.0 - float(a["walk"])) * float(a["back_debt_eur_bn"])
		return [-cash, lands, -cash / lands, lands * bloc]
	if id == "walk" or id == "stop":
		return [-float(a["debt_eur_bn"]), 0.0, -INF, bloc]
	return [-float(a["debt_eur_bn"]), 1.0, -float(a["debt_eur_bn"]), bloc]


## `a` is no worse than `b` on every figure and better on one.
func _dominates(a: Array, b: Array) -> bool:
	var better := false
	for k in a.size():
		if float(a[k]) < float(b[k]) - 1e-12:
			return false
		if float(a[k]) > float(b[k]) + 1e-12:
			better = true
	return better


## A counter answered before a save is drawn after the load exactly as without it.
func _test_a_counter_survives_a_save() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("minority_stake"), firm)
	_month(state)
	Processes.answer(state, ns, _loader, String(_row(ns, firm)["id"]), "negotiate_10")
	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	_month(state)
	_month(kept)
	var a := _row(ns, firm)
	var b := _row(kept.player(), firm)
	if String(a["status"]) != String(b["status"]) or a.get("negotiation") != b.get("negotiation") \
			or not is_equal_approx(float(ns.debt_eur_bn), float(kept.player().debt_eur_bn)):
		_fail("a counter answered before a save resolved differently after it: %s against %s" % [a.get("negotiation"), b.get("negotiation")])


## Pass 1 on #280: Budget.project() runs the seeded draw on its copy, so the forecast
## shows a counter's answer before it is due; a known answer must not be dodged, so a
## price stage with an answered counter cannot be stopped (the drawn ruling's rule).
func _test_an_answered_counter_cannot_be_stopped() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Processes.start(state, ns, _loader, _action("minority_stake"), firm)
	_month(state)
	var row := _row(ns, firm)
	if not bool(Processes.stop_price(state, ns, _loader, String(row["id"])).get("ok", false)):
		_fail("a stake's price ask cannot be stopped before any counter")
	Processes.answer(state, ns, _loader, String(row["id"]), "negotiate_10")
	var price: Dictionary = Processes.stop_price(state, ns, _loader, String(row["id"]))
	var debt := float(ns.debt_eur_bn)
	var r: Dictionary = Processes.stop(state, ns, _loader, String(row["id"]))
	if bool(price.get("ok", true)) or String(price.get("reason", "")) == "" or bool(r.get("ok", true)) \
			or String(row["status"]) != "open" or float(ns.debt_eur_bn) != debt:
		_fail("a stake with an answered counter was stopped: %s, %s" % [price, row["status"]])


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _set_now(state, now: int) -> void:
	state.year = floori((now - 1) / 12.0)
	state.month = now - 12 * int(state.year)


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
