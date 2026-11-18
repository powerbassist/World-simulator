extends SceneTree

## V5.3 c' slice B2 (docs/design/v5.3-c-register.md section 6): the Union's envelope.
## A member's cofinanced programme reserves, at the vote, the rate of each region's
## category on that row's share of the estimate, capped by what is left of the period's
## envelope (the game's declared share of the real one, and for the period under way at
## the start the years left over its years). It is paid over the twelve months after the
## opening as a receipt Budget subtracts, never more than the reservation; a shrink gives
## back; an opening after the period's last payment year is paid nothing; a note warns
## warn_months before that year ends. Reads tests/fixtures/units/ (period p1: 2020-2026,
## paid until 2029, 10 bn for FRA; FR1 more developed 0.4, FRB transition 0.6).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const UnitsLoader = preload("res://src/core/loaders/units_loader.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UnitEnvelope = preload("res://src/sim/unit_envelope.gd")
const UnitOverrun = preload("res://src/sim/unit_overrun.gd")
const UK = preload("res://src/sim/units_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")

const FIXTURE := "res://tests/fixtures/units"
const SCHOOL := "fixture_school"
const HOSPITAL := "fixture_hospital"

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
	_test_the_game_envelope()
	_test_the_vote_reserves_the_rate_of_each_category()
	_test_the_reservation_is_capped_by_what_is_left()
	_test_no_member_no_type_no_line()
	_test_paid_over_twelve_months_after_the_opening()
	_test_a_shrink_gives_back()
	_test_an_opening_after_the_date_is_paid_nothing()
	_test_the_warning_names_the_sum_about_to_lapse()
	_test_the_receipt_survives_a_save()
	_finish()


func _state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 1
	return state


func _open(state, type_id: String, rows: Array) -> Dictionary:
	var ns = state.player()
	FinanceRows.apply(state, _loader, ns, FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [{"type": type_id, "op": UK.OP_BUILD, "rows": rows}]}))
	return ns.unit_programmes[ns.unit_programmes.size() - 1]


## The fixture's period p1 runs 2020-2026 and the game starts in 2026: one year of seven.
func _envelope() -> float:
	return 10.0 * 1000.0 * UK.UNIT_ENVELOPE_GAME_SHARE * 1.0 / 7.0


func _next(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _test_the_game_envelope() -> void:
	var state = _state()
	var ns = state.player()
	if absf(UnitEnvelope.left_eur_m(_loader, ns, 2026) - _envelope()) > 1e-9:
		_fail("the game's envelope is %.4f, not %.4f" % [UnitEnvelope.left_eur_m(_loader, ns, 2026), _envelope()])
	if UnitEnvelope.left_eur_m(_loader, ns, 2031) != 0.0:
		_fail("a year with no period has an envelope")
	# A later period is whole; one ended before the start is nothing.
	var later := {"first_year": 2030, "last_year": 2036, "envelope_eur_bn": {"FRA": 7.0}}
	if absf(UnitEnvelope.envelope_eur_m(later, "FRA") - 7000.0 * UK.UNIT_ENVELOPE_GAME_SHARE) > 1e-9:
		_fail("a later period's envelope is %.4f" % UnitEnvelope.envelope_eur_m(later, "FRA"))
	if UnitEnvelope.envelope_eur_m({"first_year": 2014, "last_year": 2020, "envelope_eur_bn": {"FRA": 7.0}}, "FRA") != 0.0:
		_fail("a period ended before the start has an envelope")


func _test_the_vote_reserves_the_rate_of_each_category() -> void:
	var state = _state()
	var p := _open(state, SCHOOL, [{"region": "FR1", "units": 1}, {"region": "FRB", "units": 1}])
	# Each row's share of the estimate, at its own concentration surcharge.
	var want := 0.4 * 50.0 * (1.0 + float(p["surcharge"]["FR1"])) + 0.6 * 50.0 * (1.0 + float(p["surcharge"]["FRB"]))
	var union: Dictionary = p.get("union", {})
	if absf(float(union.get("reserved_eur_m", 0.0)) - want) > 1e-9:
		_fail("the vote reserved %.4f, not the categories' %.4f: %s" % [float(union.get("reserved_eur_m", 0.0)), want, union])
	if String(union.get("period", "")) != "p1" or int(union.get("pays_until", 0)) != 2029:
		_fail("the reservation names %s" % union)
	if absf(UnitEnvelope.left_eur_m(_loader, state.player(), 2026) - (_envelope() - want)) > 1e-9:
		_fail("what is left did not fall by the reservation")


func _test_the_reservation_is_capped_by_what_is_left() -> void:
	var state = _state()
	var first := _open(state, SCHOOL, [{"region": "FRB", "units": 5}])
	if absf(float(first["union"]["reserved_eur_m"]) - minf(_envelope(), 0.6 * float(first["estimate_eur_m"]))) > 1e-9:
		_fail("the first programme reserved %.4f" % float(first["union"]["reserved_eur_m"]))
	var second := _open(state, SCHOOL, [{"region": "FRC", "units": 5}])
	var left := _envelope() - float(first["union"]["reserved_eur_m"])
	if absf(float(second.get("union", {}).get("reserved_eur_m", 0.0)) - maxf(0.0, left)) > 1e-9:
		_fail("the second reserved %.4f with %.4f left" % [float(second.get("union", {}).get("reserved_eur_m", 0.0)), left])
	# Nothing left: no Union money, so no Union line (pass 1 on #421).
	if left <= 0.0 and second.has("union"):
		_fail("a programme reserving nothing carries a Union line: %s" % second["union"])
	if UnitEnvelope.left_eur_m(_loader, state.player(), 2026) < -1e-9:
		_fail("the envelope went below zero")


func _test_no_member_no_type_no_line() -> void:
	var state = _state()
	state.player().orgs.erase("eu")
	var p := _open(state, SCHOOL, [{"region": "FRB", "units": 1}])
	if p.has("union"):
		_fail("a non-member reserved %s" % p["union"])
	state = _state()
	_loader.unit_types[SCHOOL]["cofinanced"] = false
	p = _open(state, SCHOOL, [{"region": "FRB", "units": 1}])
	_loader.unit_types[SCHOOL]["cofinanced"] = true
	if p.has("union"):
		_fail("a type the Union does not pay reserved %s" % p["union"])
	# A hospital (60 months) voted in 2026 opens in 2031, past 2029: no Union line.
	state = _state()
	p = _open(state, HOSPITAL, [{"region": "FRB", "units": 1}])
	if p.has("union"):
		_fail("a build that cannot open before the last payment year reserved %s" % p["union"])


func _test_paid_over_twelve_months_after_the_opening() -> void:
	var state = _state()
	var ns = state.player()
	var p := _open(state, SCHOOL, [{"region": "FRB", "units": 2}])
	p.erase("overrun")
	var reserved := float(p["union"]["reserved_eur_m"])
	var due := minf(reserved, 0.6 * float(p["contract_eur_m"]))
	var received := 0.0
	var months := 0
	var opened := false
	for i in 60:
		_next(state)
		UnitBuild.tick_month(state, _loader)
		if String(p["state"]) == UK.STATE_DONE and not opened:
			opened = true
			if ns.unit_receipt_pct_gdp != 0.0:
				_fail("the receipt began in the month of the opening")
			continue
		if ns.unit_receipt_pct_gdp > 0.0:
			months += 1
			var month: float = ns.unit_receipt_pct_gdp / 100.0 * ns.gdp_eur_bn * 1000.0 / 12.0
			received += month
			if absf(month - due / 12.0) > 1e-6:
				_fail("a month's receipt is %.4f, not %.4f" % [month, due / 12.0])
				break
			# Budget subtracts it from the spending.
			Budget.recompute(state, ns)
			var with_it: float = ns.total_spending_pct_gdp
			var r: float = ns.unit_receipt_pct_gdp
			ns.unit_receipt_pct_gdp = 0.0
			Budget.recompute(state, ns)
			if absf((ns.total_spending_pct_gdp - with_it) - r) > 1e-12:
				_fail("Budget did not subtract the receipt")
			ns.unit_receipt_pct_gdp = r
	if months != UK.UNIT_RECEIPT_MONTHS or absf(received - due) > 1e-6:
		_fail("the Union paid %.4f over %d months, not %.4f over 12" % [received, months, due])
	if float(p["union"]["paid_eur_m"]) > reserved + 1e-9:
		_fail("the Union paid %.4f over its reservation %.4f" % [float(p["union"]["paid_eur_m"]), reserved])


func _test_a_shrink_gives_back() -> void:
	var state = _state()
	var ns = state.player()
	var p := _open(state, SCHOOL, [{"region": "FRB", "units": 3}])
	var before := float(p["union"]["reserved_eur_m"])
	p["overrun"] = {"month": UnitBuild.now(state) + 1}
	_next(state)
	UnitBuild.tick_month(state, _loader)
	var preview: Dictionary = UnitOverrun.answer_of(p, UK.OVERRUN_SHRINK)
	UnitOverrun.answer(state, ns, _loader, String(p["id"]), UK.OVERRUN_SHRINK)
	var after := float(p["union"]["reserved_eur_m"])
	if after >= before or absf(after - before * float(p["rows"][0]["units"]) / 3.0) > 1e-9:
		_fail("a shrink to %d units kept %.4f of %.4f" % [int(p["rows"][0]["units"]), after, before])
	if absf(float(preview.get("union_eur_m", -1.0)) - after) > 1e-9:
		_fail("the card's shrink says %.4f from the Union, the register %.4f" % [float(preview.get("union_eur_m", -1.0)), after])


func _test_an_opening_after_the_date_is_paid_nothing() -> void:
	var state = _state()
	var ns = state.player()
	var p := _open(state, SCHOOL, [{"region": "FRB", "units": 2}])
	p.erase("overrun")
	# Pushed past 2029: the opening lands in 2030.
	p["months_left"] = int(p["months_left"]) + 24
	var lapsed := false
	for i in 90:
		_next(state)
		var notes: Array = UnitBuild.tick_month(state, _loader)
		for n in notes:
			lapsed = lapsed or (String(n.get("kind", "")) == "union_lapsed" and String(n.get("id", "")) == String(p["id"]))
		if ns.unit_receipt_pct_gdp != 0.0:
			_fail("a programme opened after 2029 was paid")
			return
	if not lapsed or float(p["union"]["paid_eur_m"]) != 0.0 or float(p["union"]["reserved_eur_m"]) != 0.0:
		_fail("the lapse was not said or not given back: %s" % p["union"])
	# A delay that pushes the opening past the date says so on the card.
	state = _state()
	ns = state.player()
	p = _open(state, SCHOOL, [{"region": "FRB", "units": 2}])
	p["months_left"] = 2029 * 12 + 12 - UnitBuild.now(state)
	p["overrun"] = {"month": UnitBuild.now(state) + 1}
	_next(state)
	UnitBuild.tick_month(state, _loader)
	if not bool(UnitOverrun.answer_of(p, UK.OVERRUN_DELAY).get("union_lost", false)):
		_fail("the card's delay does not say the Union's share is lost: %s" % UnitOverrun.answer_of(p, UK.OVERRUN_DELAY))
	if bool(UnitOverrun.answer_of(p, UK.OVERRUN_PAY).get("union_lost", true)):
		_fail("the card's pay says the Union's share is lost")


func _test_the_warning_names_the_sum_about_to_lapse() -> void:
	var state = _state()
	var ns = state.player()
	var p := _open(state, SCHOOL, [{"region": "FRB", "units": 1}])
	var left := _envelope() - float(p["union"]["reserved_eur_m"])
	# Opening in May 2029, inside the date: its reservation is not about to lapse.
	p["months_left"] = 6
	state.year = 2028
	state.month = 12
	if not _warned(UnitBuild.tick_month(state, _loader)).is_empty():
		_fail("the warning came before its month")
	state.year = 2029
	state.month = 1
	var w := _warned(UnitBuild.tick_month(state, _loader))
	if w.is_empty() or absf(float(w["eur_m"]) - left) > 1e-9 or int(w["year"]) != 2029:
		_fail("the warning of January 2029 is %s, not %.4f by 2029" % [w, left])
	state.month = 2
	if not _warned(UnitBuild.tick_month(state, _loader)).is_empty():
		_fail("the warning came twice")
	# A build reserved in time that will now open after 2029 is about to lapse too.
	state = _state()
	ns = state.player()
	p = _open(state, SCHOOL, [{"region": "FRB", "units": 1}])
	left = _envelope() - float(p["union"]["reserved_eur_m"])
	p["months_left"] = 40
	state.year = 2029
	state.month = 1
	w = _warned(UnitBuild.tick_month(state, _loader))
	if w.is_empty() or absf(float(w["eur_m"]) - (left + float(p["union"]["reserved_eur_m"]))) > 1e-9:
		_fail("the warning omits a reservation that will open too late: %s" % w)
	# A non-member is never warned.
	state = _state()
	state.player().orgs.erase("eu")
	state.year = 2029
	state.month = 1
	if not _warned(UnitBuild.tick_month(state, _loader)).is_empty():
		_fail("a non-member was warned")


func _test_the_receipt_survives_a_save() -> void:
	var state = _state()
	var ns = state.player()
	ns.unit_receipt_pct_gdp = 0.0125
	var back = ns.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	if back.unit_receipt_pct_gdp != 0.0125:
		_fail("the receipt came back as %s" % back.unit_receipt_pct_gdp)
	var d: Dictionary = ns.to_dict()
	d.erase("unit_receipt_pct_gdp")
	if ns.from_dict(d).unit_receipt_pct_gdp != 0.0:
		_fail("an older save's receipt is not 0")


func _warned(notes: Array) -> Dictionary:
	for n in notes:
		if String(n.get("kind", "")) == "lapse_warning":
			return n
	return {}


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_unit_envelope: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)
