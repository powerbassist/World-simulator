extends SceneTree

## V5.3 c' slice B2 (docs/design/v5.3-c-register.md section 5): a programme's overrun.
## Drawn once at the vote with the odds shown at tabling, landed as one card in a seeded
## month of the build's middle third, sized as the type's share of the capital still to
## pay, answered pay / shrink / delay, defaulted to pay at its date with a note, and at
## most UNIT_OVERRUN_CARDS_A_YEAR cards in a calendar year. Also the first item of B2: two
## identical units rows in ONE incoming bill are refused, never collapsed.
## Reads tests/fixtures/units/ (round numbers, never a source).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const UnitsLoader = preload("res://src/core/loaders/units_loader.gd")
const Units = preload("res://src/sim/units.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UnitOverrun = preload("res://src/sim/unit_overrun.gd")
const UK = preload("res://src/sim/units_constants.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")
const QuietMonth = preload("res://src/sim/quiet_month.gd")

const FIXTURE := "res://tests/fixtures/units"
const TYPE := "fixture_school"

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	UnitsLoader.load_units(_loader, FIXTURE)
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_two_equal_rows_in_one_bill_are_refused()
	_test_the_overrun_is_drawn_once_at_the_vote()
	_test_the_card_lands_in_its_month()
	_test_pay_spreads_the_overrun_over_the_months_left()
	_test_delay_keeps_the_rate_and_moves_the_opening()
	_test_shrink_drops_units_until_the_first_budget_holds()
	_test_unanswered_is_pay_with_a_note()
	_test_two_cards_a_year_a_third_waits()
	_test_no_card_inside_the_window()
	_finish()


func _state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 1
	return state


func _build(rows: Array) -> Dictionary:
	return {"type": TYPE, "op": UK.OP_BUILD, "rows": rows}


## A state with one programme voted, whose overrun falls (`falls`) or not: the game's seed
## is walked until the draw says so, the way two games differ.
func _voted(rows: Array, falls: bool) -> Dictionary:
	for seed in range(1, 400):
		var state = _state()
		var ns = state.player()
		ns.draw_seed = seed
		FinanceRows.apply(state, _loader, ns, FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [_build(rows)]}))
		var p: Dictionary = ns.unit_programmes[0]
		if p.has("overrun") == falls:
			return {"state": state, "ns": ns, "p": p}
	_fail("no seed in 400 gives an overrun that %s" % ("falls" if falls else "does not fall"))
	return {}


## Ticks until the programme's card is posted; the notes of that month.
func _until_card(state, p: Dictionary) -> Array:
	for i in 60:
		_next(state)
		var notes: Array = UnitBuild.tick_month(state, _loader)
		if p.has("ask"):
			return notes
	_fail("the card never landed: %s" % p)
	return []


func _next(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _test_two_equal_rows_in_one_bill_are_refused() -> void:
	var state = _state()
	var ns = state.player()
	var row := _build([{"region": "FR1", "units": 2}])
	var refused := FinanceBill.refusal(state, _loader, {FinanceRows.UNITS: [row, row.duplicate(true)]})
	if not bool(refused.get("refused", false)) or String(refused.get("reason", "")) != "One row per type and regions: put the units in one row.":
		_fail("two equal rows in one bill are not refused with the reason: %s" % refused)
	FinanceBill.table(state, _loader, {FinanceRows.UNITS: [row, row.duplicate(true)]})
	if not ns.tabled_bill.is_empty():
		_fail("a bill with two equal rows was tabled: %s" % ns.tabled_bill)
	# A row equal to one already HELD is the same text tabled again: kept once, not refused.
	FinanceBill.table(state, _loader, {FinanceRows.UNITS: [row]})
	var again := FinanceBill.table(state, _loader, {FinanceRows.UNITS: [row.duplicate(true)]})
	if bool(again.get("refused", false)) or (ns.tabled_bill["finance"][FinanceRows.UNITS] as Array).size() != 1:
		_fail("re-tabling a held row was refused or doubled: %s, %s" % [again, ns.tabled_bill["finance"][FinanceRows.UNITS]])
	# Same regions, other counts: two programmes, legal.
	var other := FinanceBill.refusal(_state(), _loader, {FinanceRows.UNITS: [row, _build([{"region": "FR1", "units": 3}])]})
	if not other.is_empty():
		_fail("two different rows were refused: %s" % other)


func _test_the_overrun_is_drawn_once_at_the_vote() -> void:
	var falls := 0
	var odds := 0.0
	for seed in range(1, 201):
		var state = _state()
		var ns = state.player()
		ns.draw_seed = seed
		FinanceRows.apply(state, _loader, ns, FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [_build([{"region": "FRB", "units": 1}])]}))
		var p: Dictionary = ns.unit_programmes[0]
		odds = float(p["odds"])
		if not p.has("overrun"):
			continue
		falls += 1
		var at := int(p["overrun"]["month"]) - int(p["voted"])
		if at < 12 or at >= 24:
			_fail("an overrun of a 36-month build lands at month %d, outside the middle third" % at)
			break
	# The band's 5 points are the probe's (U3, 200 seeded runs in the real month); here the
	# draw is only held to its odds loosely, so a broken comparison cannot pass.
	if absf(float(falls) / 200.0 - odds) > 0.08:
		_fail("%d of 200 programmes overran against odds %.3f" % [falls, odds])
	var a := _voted([{"region": "FRB", "units": 1}], true)
	if a.is_empty():
		return
	var state = _state()
	var ns = state.player()
	ns.draw_seed = a["ns"].draw_seed
	FinanceRows.apply(state, _loader, ns, FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [_build([{"region": "FRB", "units": 1}])]}))
	if ns.unit_programmes[0].get("overrun") != a["p"]["overrun"]:
		_fail("the overrun draw is not seeded: %s vs %s" % [ns.unit_programmes[0].get("overrun"), a["p"]["overrun"]])
	# A closure never overruns.
	var close := {"type": TYPE, "op": UK.OP_DEMOLISH, "rows": [{"region": "FR1", "capacity": 500.0}]}
	for seed in range(1, 60):
		state = _state()
		ns = state.player()
		ns.draw_seed = seed
		var p: Dictionary = UnitBuild.open(state, ns, _loader, close)
		if p.has("overrun"):
			_fail("a closure drew an overrun")
			break


func _test_the_card_lands_in_its_month() -> void:
	var v := _voted([{"region": "FRB", "units": 2}], true)
	if v.is_empty():
		return
	var state = v["state"]
	var ns = v["ns"]
	var p: Dictionary = v["p"]
	var landed := false
	for i in 40:
		_next(state)
		var notes: Array = UnitBuild.tick_month(state, _loader)
		if _now(state) < int(p["overrun"]["month"]):
			if p.has("ask"):
				_fail("the card landed early, month %d of %d" % [_now(state), int(p["overrun"]["month"])])
				return
			continue
		landed = p.has("ask")
		var ask: Dictionary = p.get("ask", {})
		var size := float(_loader.unit_types[TYPE]["overrun_share"]) * float(p["capital_month_eur_m"]) * int(p["months_left"])
		if int(ask.get("posted", -1)) != _now(state) or int(ask.get("due", -1)) != _now(state) + UK.UNIT_OVERRUN_WINDOW_MONTHS \
				or String(ask.get("default", "")) != UK.OVERRUN_PAY:
			_fail("the card's dates or default are wrong: %s" % ask)
		if absf(float(ask.get("eur_m", 0.0)) - size) > 1e-9:
			_fail("the overrun is %.4f, not the share of the capital still to pay %.4f" % [float(ask.get("eur_m", 0.0)), size])
		var ids: Array = []
		for a in ask.get("answers", []):
			ids.append(String(a["id"]))
		if ids != [UK.OVERRUN_PAY, UK.OVERRUN_SHRINK, UK.OVERRUN_DELAY]:
			_fail("the card offers %s" % [ids])
		if not _has_note(notes, "overrun_landed", String(p["id"])):
			_fail("the month's notes do not say the card landed: %s" % [notes])
		if UnitOverrun.asks(ns).size() != 1:
			_fail("the register lists %d asks" % UnitOverrun.asks(ns).size())
		# It is an arrival for the quiet-month call: the month is not empty.
		ns.in_government = true
		var with_it := QuietMonth.quiet(state, ns, _loader, _now(state))
		var posted := int(ask["posted"])
		ask["posted"] = -1
		var without := QuietMonth.quiet(state, ns, _loader, _now(state))
		ask["posted"] = posted
		if without and with_it:
			_fail("an overrun card leaves the month quiet")
		break
	if not landed:
		_fail("the card did not land in its month")


func _test_pay_spreads_the_overrun_over_the_months_left() -> void:
	var v := _voted([{"region": "FRB", "units": 2}], true)
	if v.is_empty():
		return
	var state = v["state"]
	var ns = v["ns"]
	var p: Dictionary = v["p"]
	_until_card(state, p)
	var size := float(p["ask"]["eur_m"])
	var rate := float(p["capital_month_eur_m"])
	var left := int(p["months_left"])
	var contract := float(p["contract_eur_m"])
	var done := UnitOverrun.answer(state, ns, _loader, String(p["id"]), UK.OVERRUN_PAY)
	if not bool(done.get("ok", false)):
		_fail("pay was refused: %s" % done)
	if absf(float(p["capital_month_eur_m"]) - (rate + size / left)) > 1e-9 or int(p["months_left"]) != left:
		_fail("pay billed %.4f a month for %d months, not %.4f for %d" % [float(p["capital_month_eur_m"]), int(p["months_left"]), rate + size / left, left])
	if bool(UnitOverrun.answer(state, ns, _loader, String(p["id"]), UK.OVERRUN_PAY).get("ok", true)):
		_fail("a card answered twice")
	if UnitOverrun.asks(ns).size() != 0:
		_fail("an answered card is still listed")
	var opened := {}
	for n in _run_out(state, p):
		if String(n.get("kind", "")) == "opened" and String(n.get("id", "")) == String(p["id"]):
			opened = n
	if absf(float(opened.get("realised_eur_m", -1.0)) - float(p["paid_eur_m"])) > 1e-9 			or float(opened.get("estimate_eur_m", -1.0)) != float(p["estimate_eur_m"]):
		_fail("the opening's note says %s, the register paid %.4f" % [opened, float(p["paid_eur_m"])])
	if absf(float(p["paid_eur_m"]) - (contract + size)) > 1e-6:
		_fail("pay realised %.4f, not the contract and the overrun %.4f" % [float(p["paid_eur_m"]), contract + size])


func _test_delay_keeps_the_rate_and_moves_the_opening() -> void:
	var v := _voted([{"region": "FRB", "units": 2}], true)
	if v.is_empty():
		return
	var state = v["state"]
	var ns = v["ns"]
	var p: Dictionary = v["p"]
	_until_card(state, p)
	var size := float(p["ask"]["eur_m"])
	var rate := float(p["capital_month_eur_m"])
	var left := int(p["months_left"])
	var contract := float(p["contract_eur_m"])
	var preview: Dictionary = UnitOverrun.answer_of(p, UK.OVERRUN_DELAY)
	UnitOverrun.answer(state, ns, _loader, String(p["id"]), UK.OVERRUN_DELAY)
	var extra := int(ceilf(size / rate))
	if int(p["months_left"]) != left + extra or float(p["capital_month_eur_m"]) > rate + 1e-12:
		_fail("delay gave %d months at %.4f, not %d at no more than %.4f" % [int(p["months_left"]), float(p["capital_month_eur_m"]), left + extra, rate])
	if int(preview.get("opens", -1)) != _now(state) + left + extra:
		_fail("the card's delay opens at %d, the programme at %d" % [int(preview.get("opens", -1)), _now(state) + left + extra])
	_run_out(state, p)
	if absf(float(p["paid_eur_m"]) - (contract + size)) > 1e-6:
		_fail("delay realised %.4f, not %.4f" % [float(p["paid_eur_m"]), contract + size])


func _test_shrink_drops_units_until_the_first_budget_holds() -> void:
	var v := _voted([{"region": "FR1", "units": 5}, {"region": "FRB", "units": 3}], true)
	if v.is_empty():
		return
	var state = v["state"]
	var ns = v["ns"]
	var p: Dictionary = v["p"]
	_until_card(state, p)
	var size := float(p["ask"]["eur_m"])
	var contract := float(p["contract_eur_m"])
	var keep := contract / (contract + size)
	var want := {"FR1": int(floorf(5 * keep)), "FRB": int(floorf(3 * keep))}
	UnitOverrun.answer(state, ns, _loader, String(p["id"]), UK.OVERRUN_SHRINK)
	for r in p["rows"]:
		if int(r["units"]) != int(want[String(r["region"])]):
			_fail("shrink left %s with %d units, not %d" % [r["region"], int(r["units"]), int(want[String(r["region"])])])
	_run_out(state, p)
	if float(p["paid_eur_m"]) > contract + 1e-6:
		_fail("shrink realised %.4f over the first budget %.4f" % [float(p["paid_eur_m"]), contract])
	var units := 0
	for r in want:
		units += int(want[r])
	if Units.capacity_delta(ns, _loader, TYPE, "FR1") != float(want["FR1"]) * 1000.0:
		_fail("FR1 gained %s capacity, not %d units' worth" % [Units.capacity_delta(ns, _loader, TYPE, "FR1"), want["FR1"]])
	# A region cut to no unit leaves the programme's rows.
	var small := _voted([{"region": "FR1", "units": 6}, {"region": "FRB", "units": 1}], true)
	if small.is_empty():
		return
	_until_card(small["state"], small["p"])
	UnitOverrun.answer(small["state"], small["ns"], _loader, String(small["p"]["id"]), UK.OVERRUN_SHRINK)
	for r in small["p"]["rows"]:
		if String(r["region"]) == "FRB" or int(r["units"]) <= 0:
			_fail("a region cut to no unit stays in the rows: %s" % [small["p"]["rows"]])
	# A programme of one unit cannot shrink: the card does not offer it.
	var one := _voted([{"region": "FRB", "units": 1}], true)
	if one.is_empty():
		return
	_until_card(one["state"], one["p"])
	if not UnitOverrun.answer_of(one["p"], UK.OVERRUN_SHRINK).is_empty():
		_fail("a one-unit programme offers to shrink")
	if bool(UnitOverrun.answer(one["state"], one["ns"], _loader, String(one["p"]["id"]), UK.OVERRUN_SHRINK).get("ok", true)):
		_fail("a one-unit programme shrank")


func _test_unanswered_is_pay_with_a_note() -> void:
	var v := _voted([{"region": "FRB", "units": 2}], true)
	if v.is_empty():
		return
	var state = v["state"]
	var p: Dictionary = v["p"]
	_until_card(state, p)
	var size := float(p["ask"]["eur_m"])
	var contract := float(p["contract_eur_m"])
	var due := int(p["ask"]["due"])
	var noted := false
	while _now(state) < due:
		_next(state)
		var notes: Array = UnitBuild.tick_month(state, _loader)
		noted = noted or _has_note(notes, "overrun_defaulted", String(p["id"]))
	if not noted or String(p.get("answer", "")) != UK.OVERRUN_PAY:
		_fail("an unanswered card did not default to pay with a note at its date: %s" % p.get("answer"))
	_run_out(state, p)
	if absf(float(p["paid_eur_m"]) - (contract + size)) > 1e-6:
		_fail("the default realised %.4f, not %.4f" % [float(p["paid_eur_m"]), contract + size])


func _test_two_cards_a_year_a_third_waits() -> void:
	var state = _state()
	var ns = state.player()
	for region in ["FR1", "FRB", "FRC"]:
		UnitBuild.open(state, ns, _loader, _build([{"region": region, "units": 1}]))
	for p in ns.unit_programmes:
		p["overrun"] = {"month": _now(state) + 13}
	var posted := []
	for i in 30:
		_next(state)
		UnitBuild.tick_month(state, _loader)
		for p in ns.unit_programmes:
			if p.has("ask") and not posted.has(p["id"]):
				posted.append(p["id"])
				p["ask"]["at"] = _now(state)
	if posted.size() != 3:
		_fail("%d of 3 cards landed" % posted.size())
		return
	var months := []
	for p in ns.unit_programmes:
		months.append(int(p["ask"]["at"]))
	months.sort()
	var feb := 2027 * 12 + 2
	if months != [feb, feb, 2028 * 12 + 1]:
		_fail("the cards landed in months %s, not two in February 2027 and the third in January 2028" % [months])


## An overrun whose month comes with no more than the card's window left to build is
## never posted: an answer must land on a building programme.
func _test_no_card_inside_the_window() -> void:
	var state = _state()
	var ns = state.player()
	var p: Dictionary = UnitBuild.open(state, ns, _loader, _build([{"region": "FRB", "units": 1}]))
	p["overrun"] = {"month": _now(state) + int(p["months_left"]) - UK.UNIT_OVERRUN_WINDOW_MONTHS}
	_run_out(state, p)
	if p.has("ask"):
		_fail("a card was posted %d months before the opening" % UK.UNIT_OVERRUN_WINDOW_MONTHS)


## Ticks a programme to its opening; the notes of the month it opened.
func _run_out(state, p: Dictionary) -> Array:
	for i in 120:
		if String(p["state"]) != UK.STATE_BUILDING:
			return []
		_next(state)
		var notes: Array = UnitBuild.tick_month(state, _loader)
		if String(p["state"]) != UK.STATE_BUILDING:
			return notes
	_fail("the programme never opened: %s" % p)
	return []


func _has_note(notes: Array, kind: String, id: String) -> bool:
	for n in notes:
		if String(n.get("kind", "")) == kind and String(n.get("id", "")) == id:
			return true
	return false


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_unit_overrun: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)
