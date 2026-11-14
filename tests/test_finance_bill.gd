extends SceneTree

## The finance bill (docs/design/finance-bill.md, the parent's go of 2026-11-14 on
## calls 1-6 (a)): pending budget and tax changes are one bill in the month's slot,
## as deltas, divided as the first step of the close and applied there; read like a
## law and whipped like a confidence vote; forced only at the close, censure first;
## no second chamber; a defeat costs the slot and the rebels only.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Division = preload("res://src/sim/division.gd")
const Bills = preload("res://src/sim/bills.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const FK = preload("res://src/sim/finance_bill_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const DK = preload("res://src/sim/discipline_constants.gd")

const START_YEAR := 2026

## tools/balance_probe.gd's `managed`, as deltas: the reading's measured case (a partner
## whose own members would vote no follows its whip, and some of its seats rebel).
const MANAGED := {"spending_pct_gdp": {"defence": -1.4}, "tax_rates_pct": {"vat": 3.0}}
## tools/balance_probe.gd's `tinkering`: fails in France once the social democrats leave.
const TINKERING := {
	"spending_pct_gdp": {"education": 1.0, "pensions": -1.0, "infrastructure": 1.5},
	"tax_rates_pct": {"income": 1.0, "corporate": -1.0, "vat": 1.0},
}

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_from_pending_is_deltas_against_the_live_register()
	_check_tabling_takes_the_slot_and_changes_no_book()
	_check_the_slot_is_shared_with_laws()
	_check_a_second_tabling_amends_the_same_bill()
	_check_an_empty_bill_is_refused()
	_check_a_carried_bill_applies_at_the_division()
	_check_the_deltas_ride_on_a_rate_moved_after_tabling()
	_check_the_reading_whips_partners_and_not_the_opposition()
	_check_the_rebels_are_charged_to_discipline()
	_check_a_failed_bill_leaves_the_books_and_no_cooldown()
	_check_forcing_waits_for_the_close_and_ignores_the_cooldown()
	_check_forcing_is_refused_where_the_formation_rule_forbids()
	_check_a_carried_censure_kills_the_forced_bill()
	_check_the_second_chamber_is_skipped()
	_check_the_position_follows_the_size_and_the_anchors()
	_check_the_forecast_is_the_division()
	_check_the_tabled_bill_is_an_open_law()
	_check_the_tabled_bill_survives_a_save()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_finance_bill.gd")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL " + f)
	quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state(nation_id := "FRA"):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	return state


func _find_law(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null


func _absolute(ns, deltas: Dictionary) -> Dictionary:
	var pending := {}
	for channel in ["tax_rates_pct", "spending_pct_gdp"]:
		if deltas.has(channel):
			var register: Dictionary = ns.tax_rates_pct if channel == "tax_rates_pct" else ns.spending_pct_gdp
			var rows := {}
			for key in deltas[channel]:
				rows[key] = float(register.get(key, 0.0)) + float(deltas[channel][key])
			pending[channel] = rows
	return pending


func _check_from_pending_is_deltas_against_the_live_register() -> void:
	var ns = _new_state().player()
	var pending := {
		"tax_rates_pct": {"vat": float(ns.tax_rates_pct["vat"]) + 2.0, "income": float(ns.tax_rates_pct["income"])},
		"spending_pct_gdp": {"health": float(ns.spending_pct_gdp["health"]) - 0.5},
		"tax_progressivity": float(ns.tax_progressivity) + 0.2,
	}
	var bill := FinanceBill.from_pending(ns, pending)
	if not is_equal_approx(float(bill["tax_rates_pct"]["vat"]), 2.0) or bill["tax_rates_pct"].has("income"):
		_fail("from_pending: the tax deltas are not live-relative, or an unmoved key stayed: %s" % [bill])
	if not is_equal_approx(float(bill["spending_pct_gdp"]["health"]), -0.5):
		_fail("from_pending: the spending delta is wrong: %s" % [bill])
	if not is_equal_approx(float(bill["tax_progressivity"]), 0.2):
		_fail("from_pending: the progressivity delta is wrong: %s" % [bill])
	if not FinanceBill.from_pending(ns, {"spending_pct_gdp": ns.spending_pct_gdp.duplicate()}).is_empty():
		_fail("from_pending: a pending equal to the live register is not an empty bill")


func _check_tabling_takes_the_slot_and_changes_no_book() -> void:
	var state = _new_state()
	var ns = state.player()
	var vat := float(ns.tax_rates_pct["vat"])
	var deficit := float(ns.deficit_pct_gdp)
	var result := FinanceBill.table(state, _loader, MANAGED)
	if not bool(result.get("tabled", false)):
		_fail("table: MANAGED was not tabled: %s" % [result])
		return
	var id := String(ns.tabled_bill.get("law_id", ""))
	if id != FinanceBillLaw.PREFIX + str(START_YEAR * 12 + 1):
		_fail("table: the register's id is not finance:<absolute month>: %s" % [ns.tabled_bill])
	if (ns.tabled_bill.get("finance", {}) as Dictionary) != MANAGED:
		_fail("table: the register does not carry the bill's deltas: %s" % [ns.tabled_bill])
	if float(ns.tax_rates_pct["vat"]) != vat or float(ns.deficit_pct_gdp) != deficit:
		_fail("table: tabling moved the books before the division")
	if not (result.get("forecast", {}) as Dictionary).has("yes_seats"):
		_fail("table: the tabling carries no forecast: %s" % [result])


func _check_the_slot_is_shared_with_laws() -> void:
	var state = _new_state()
	Legislature.propose(state, _loader, _find_law("carbon_levy"))
	var refused := FinanceBill.table(state, _loader, MANAGED)
	if bool(refused.get("tabled", false)) or not bool(refused.get("already_tabled", false)):
		_fail("slot: a finance bill was tabled over a tabled law: %s" % [refused])
	state = _new_state()
	FinanceBill.table(state, _loader, MANAGED)
	var law_refused := Legislature.propose(state, _loader, _find_law("carbon_levy"))
	if not bool(law_refused.get("already_tabled", false)):
		_fail("slot: a law was tabled over the finance bill: %s" % [law_refused])


func _check_a_second_tabling_amends_the_same_bill() -> void:
	var state = _new_state()
	var ns = state.player()
	FinanceBill.table(state, _loader, {"spending_pct_gdp": {"defence": -1.4, "health": 0.5}})
	var second := FinanceBill.table(state, _loader, {"tax_rates_pct": {"vat": 3.0}, "spending_pct_gdp": {"defence": -1.0}})
	if not bool(second.get("tabled", false)):
		_fail("amend: a second tabling of the finance bill was refused: %s" % [second])
	var bill: Dictionary = ns.tabled_bill.get("finance", {})
	if bill != {"spending_pct_gdp": {"defence": -1.0, "health": 0.5}, "tax_rates_pct": {"vat": 3.0}}:
		_fail("amend: the second tabling did not replace per key into one bill: %s" % [bill])


func _check_an_empty_bill_is_refused() -> void:
	var state = _new_state()
	var result := FinanceBill.table(state, _loader, {})
	if bool(result.get("tabled", false)) or not state.player().tabled_bill.is_empty():
		_fail("empty: an empty finance bill was tabled: %s" % [result])


func _check_a_carried_bill_applies_at_the_division() -> void:
	var state = _new_state()
	var ns = state.player()
	var vat := float(ns.tax_rates_pct["vat"])
	var defence := float(ns.spending_pct_gdp["defence"])
	FinanceBill.table(state, _loader, MANAGED)
	var result := Division.divide(state, _loader)
	if not bool(result.get("passed", false)) or not bool(result.get("finance", false)):
		_fail("carried: MANAGED did not carry in France at the start: %s" % [result])
		return
	if not is_equal_approx(float(ns.tax_rates_pct["vat"]), vat + 3.0) or not is_equal_approx(float(ns.spending_pct_gdp["defence"]), defence - 1.4):
		_fail("carried: the division did not apply the deltas: vat %s defence %s" % [ns.tax_rates_pct["vat"], ns.spending_pct_gdp["defence"]])
	# The same books Budget.commit would have written from the same register.
	var twin = _new_state()
	Budget.commit(twin, _absolute(twin.player(), MANAGED))
	if float(twin.player().deficit_pct_gdp) != float(ns.deficit_pct_gdp) or float(twin.player().demand_impulse_pct) != float(ns.demand_impulse_pct):
		_fail("carried: the applied bill's books differ from Budget.commit's on the same deltas")
	if not ns.tabled_bill.is_empty() or ns.last_law_result.is_empty():
		_fail("carried: the register was not cleared or no result was written")


func _check_the_deltas_ride_on_a_rate_moved_after_tabling() -> void:
	var state = _new_state()
	var ns = state.player()
	var vat := float(ns.tax_rates_pct["vat"])
	FinanceBill.table(state, _loader, {"tax_rates_pct": {"vat": 3.0}})
	Legislature.apply_effects(state, ns, {"tax_rates_pct": {"vat": 1.0}}, _loader)
	Division.divide(state, _loader)
	if not is_equal_approx(float(ns.tax_rates_pct["vat"]), vat + 4.0):
		_fail("deltas: a rate moved after tabling was overwritten: vat %s, want %s" % [ns.tax_rates_pct["vat"], vat + 4.0])


func _check_the_reading_whips_partners_and_not_the_opposition() -> void:
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties["FRA"]
	var law = FinanceBillLaw.law(ns, {"law_id": "finance:1", "finance": MANAGED})
	var r := FinanceBill.resolve(ns, party_list, law)
	var whipped := 0
	for party in party_list:
		var spatial := Legislature.spatial_support(ns, party, law)
		var s := float(r["party_support"][party.id])
		if ns.coalition_party_ids.has(party.id):
			var d := Discipline.of(ns, party)
			var want := clampf(spatial + d - DK.DISAFFECTION * Discipline.unpopularity(ns) * (1.0 - d), -1.0, 1.0)
			if not is_equal_approx(s, want):
				_fail("reading: partner %s reads %.3f, not spatial + discipline %.3f" % [party.id, s, want])
			if spatial < -LK.ABSTAIN_BAND and String(r["party_votes"][party.id]) == "yes":
				whipped += 1
		elif not is_equal_approx(s, spatial):
			_fail("reading: opposition %s reads %.3f, not its spatial %.3f" % [party.id, s, spatial])
	if whipped == 0:
		_fail("reading: no partner whose own read is no follows the whip on MANAGED (the measured case)")
	if int(r["party_rebels"].values().reduce(func(a, b): return a + b, 0)) <= 0:
		_fail("reading: MANAGED in France sheds no rebel seats (measured 16): %s" % [r["party_rebels"]])


func _check_the_rebels_are_charged_to_discipline() -> void:
	var state = _new_state()
	var ns = state.player()
	var before: Dictionary = {}
	for party in _loader.parties["FRA"]:
		before[party.id] = Discipline.of(ns, party)
	FinanceBill.table(state, _loader, MANAGED)
	var result := Division.divide(state, _loader)
	var charged := false
	for party in _loader.parties["FRA"]:
		if (result["party_rebels"] as Dictionary).has(party.id) and Discipline.of(ns, party) < float(before[party.id]):
			charged = true
	if not charged:
		_fail("rebels: a carried budget's rebels were not charged to discipline: %s" % [result["party_rebels"]])


## The social democrats out of the coalition: a minority, and TINKERING fails (measured
## 208 to 265).
func _minority(state) -> void:
	var ns = state.player()
	var by_id := {}
	for party in _loader.parties["FRA"]:
		by_id[party.id] = party
	ns.coalition_party_ids.erase("parti_social_uni")
	ns.coalition_position = Government.position_of(ns.seats_by_party, ns.coalition_party_ids, by_id)


func _check_a_failed_bill_leaves_the_books_and_no_cooldown() -> void:
	var state = _new_state()
	var ns = state.player()
	_minority(state)
	var rates: Dictionary = ns.tax_rates_pct.duplicate()
	var spending: Dictionary = ns.spending_pct_gdp.duplicate()
	FinanceBill.table(state, _loader, TINKERING)
	var result := Division.divide(state, _loader)
	if bool(result.get("passed", true)):
		_fail("failed: TINKERING passed in a minority (measured to fail): %s" % [result])
		return
	if ns.tax_rates_pct != rates or ns.spending_pct_gdp != spending:
		_fail("failed: a defeated bill moved the books")
	if (result.get("finance_bill", {}) as Dictionary) != TINKERING:
		_fail("failed: the result does not carry the defeated bill's deltas: %s" % [result])
	if not ns.law_cooldown_months.is_empty():
		_fail("failed: a defeat wrote a cooldown: %s" % [ns.law_cooldown_months])
	if not bool(FinanceBill.table(state, _loader, TINKERING).get("tabled", false)):
		_fail("failed: the bill cannot be tabled again after a defeat")


func _check_forcing_waits_for_the_close_and_ignores_the_cooldown() -> void:
	var state = _new_state()
	var ns = state.player()
	_minority(state)
	ns.force_cooldown_months = 5
	var vat := float(ns.tax_rates_pct["vat"])
	var tabled := FinanceBill.table(state, _loader, TINKERING, true)
	if not bool(tabled.get("tabled", false)) or not bool(ns.tabled_bill.get("forced", false)):
		_fail("force: a forced finance bill was refused under the ordinary cooldown: %s" % [tabled])
		return
	if float(ns.tax_rates_pct["vat"]) != vat or not ns.last_censure.is_empty():
		_fail("force: forcing applied or censured before the close")
	var result := Division.divide(state, _loader)
	if not bool(result.get("forced", false)) or int(result.get("yes_seats", -1)) != 0 or ns.last_censure.is_empty():
		_fail("force: the close did not adopt without a vote and resolve the censure: %s" % [result])
	if bool(result.get("passed", false)) and not is_equal_approx(float(ns.tax_rates_pct["vat"]), vat + 1.0):
		_fail("force: a forced bill whose censure failed did not apply")
	if ns.force_cooldown_months != 5:
		_fail("force: the finance bill touched the ordinary cooldown: %d" % ns.force_cooldown_months)


func _check_forcing_is_refused_where_the_formation_rule_forbids() -> void:
	var state = _new_state("DEU")
	var result := FinanceBill.table(state, _loader, MANAGED, true)
	if bool(result.get("tabled", false)) or not state.player().tabled_bill.is_empty():
		_fail("force: Germany forced a finance bill: %s" % [result])


## The government alone: the social democrats sit out, the greens too, and a forced
## censure carries (259 + 104 of 289 needed).
func _check_a_carried_censure_kills_the_forced_bill() -> void:
	var state = _new_state()
	var ns = state.player()
	var by_id := {}
	for party in _loader.parties["FRA"]:
		by_id[party.id] = party
	ns.coalition_party_ids = ["renouveau_civique"]
	ns.coalition_position = Government.position_of(ns.seats_by_party, ns.coalition_party_ids, by_id)
	var rates: Dictionary = ns.tax_rates_pct.duplicate()
	FinanceBill.table(state, _loader, TINKERING, true)
	var result := Division.divide(state, _loader)
	if not bool(ns.last_censure.get("carried", false)):
		_fail("censure: the staged censure did not carry (stage broken): %s" % [ns.last_censure])
		return
	if bool(result.get("passed", true)) or ns.tax_rates_pct != rates:
		_fail("censure: a carried censure left the forced budget in force: %s" % [result])


func _check_the_second_chamber_is_skipped() -> void:
	var state = _new_state()
	var ns = state.player()
	if not ns.has_upper_house:
		_fail("upper: France has no second chamber in data (stage broken)")
		return
	FinanceBill.table(state, _loader, MANAGED)
	var result := Division.divide(state, _loader)
	if result.has("upper_chamber") or not ns.held_bills.is_empty():
		_fail("upper: the finance bill met the second chamber: %s" % [result])


func _check_the_position_follows_the_size_and_the_anchors() -> void:
	var ns = _new_state().player()
	var centroid: Dictionary = ns.coalition_position
	if FinanceBillLaw.position(ns, {}) != centroid:
		_fail("position: an empty bill does not sit at the coalition's place")
	# A VAT rise as big as the reference size reads wholly as VAT's anchor.
	var points := FK.REF_SIZE / 0.2
	var big := FinanceBillLaw.position(ns, {"tax_rates_pct": {"vat": points}})
	var anchor: Dictionary = FK.ANCHOR["tax_rates_pct"]["vat"]["up"]
	if not is_equal_approx(float(big["economic"]), float(anchor["economic"])) or not is_equal_approx(float(big["social"]), float(anchor["social"])):
		_fail("position: a reference-size VAT rise does not sit at its anchor: %s vs %s" % [big, anchor])
	var half := FinanceBillLaw.position(ns, {"tax_rates_pct": {"vat": points / 2.0}})
	var want := float(centroid["economic"]) + 0.5 * (float(anchor["economic"]) - float(centroid["economic"]))
	if not is_equal_approx(float(half["economic"]), want):
		_fail("position: a half-size bill is not halfway: %s, want %.3f" % [half, want])


func _check_the_forecast_is_the_division() -> void:
	var state = _new_state()
	var ns = state.player()
	FinanceBill.table(state, _loader, MANAGED)
	var forecast := Division.forecast(state, ns, _loader)
	var result := Division.divide(state, _loader)
	for key in ["passed", "yes_seats", "no_seats", "abstain_seats"]:
		if forecast.get(key) != result.get(key):
			_fail("forecast: %s %s is not the division's %s" % [key, forecast.get(key), result.get(key)])


func _check_the_tabled_bill_is_an_open_law() -> void:
	var state = _new_state()
	var ns = state.player()
	FinanceBill.table(state, _loader, MANAGED)
	var id := String(ns.tabled_bill["law_id"])
	if Legislature.open_law(state, ns, _loader, id) == null:
		_fail("open: the tabled finance bill is not found among the open bills")
	ns.tabled_bill = {}
	for law in Bills.open(state, ns, _loader):
		if String(law.id).begins_with(FinanceBillLaw.PREFIX):
			_fail("open: a finance bill is listed with none tabled")


func _check_the_tabled_bill_survives_a_save() -> void:
	var state = _new_state()
	FinanceBill.table(state, _loader, MANAGED)
	var copy = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var bill: Dictionary = copy.player().tabled_bill
	if String(bill.get("law_id", "")) != String(state.player().tabled_bill["law_id"]):
		_fail("save: the tabled finance bill's id did not survive: %s" % [bill])
	var deltas: Dictionary = bill.get("finance", {})
	if not is_equal_approx(float(deltas.get("tax_rates_pct", {}).get("vat", 0.0)), 3.0):
		_fail("save: the finance bill's deltas did not survive: %s" % [bill])
