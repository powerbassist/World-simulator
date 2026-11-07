extends SceneTree

## V5.3 a (docs/design/v5.3-ab.md 3.2, "New Industry decisions"): a plant closure
## announced. When a major's output has fallen by more than the rule's threshold
## over its window, the firm announces a closure in its live city, and the player
## answers: rescue the plant (paid per job for a term), find a buyer (a search of
## CLOSURE_BUYER_MONTHS with a seeded chance), or let it close (the default: a cut
## of the firm's share, so of its jobs in its city, and the rule's bloc move). The
## rule's numbers are data (data/industry/closures.json), never per firm.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Companies = preload("res://src/sim/companies.gd")
const Closures = preload("res://src/sim/closures.gd")
const Economy = preload("res://src/sim/economy.gd")
const Processes = preload("res://src/sim/processes.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const CK = preload("res://src/sim/closures_constants.gd")
const CompaniesLoader = preload("res://src/core/loaders/companies_loader.gd")
const Budget = preload("res://src/sim/budget.gd")
const Negotiation = preload("res://src/sim/negotiation.gd")
const NK = preload("res://src/sim/companies_constants.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	# Most of this file stages one fall and reads what it does, so the month's chance
	# is certain here; the tests of the chance itself read the shipped rule (_shipped).
	_loader.closure_rule["monthly_chance"] = 1000.0
	_test_the_rule_is_data()
	_test_the_chance_reads_the_fall_and_the_economy()
	_test_each_sector_draws_its_own_chance()
	_test_the_rate_follows_the_economy()
	_test_the_rate_follows_the_sectors_fall()
	_test_a_chance_that_does_not_come_up_announces_nothing()
	_test_a_void_row_does_not_cool_the_sector()
	_test_the_record_says_what_fell()
	_test_a_falling_major_announces_a_closure()
	_test_one_announcement_a_month_the_worst_first()
	_test_the_worst_fall_ranks_the_sectors()
	_test_an_unanswered_closure_lands_by_default()
	_test_a_rescue_keeps_the_plant_for_its_term_at_its_price()
	_test_a_buyer_search_resolves_on_its_seed()
	_test_a_closed_firm_does_not_announce_again_in_its_cooldown()
	_test_only_the_player_announces()
	_test_a_firm_in_a_process_does_not_announce()
	_test_answer_refusals()
	_test_a_closure_survives_a_save()
	_test_a_failed_firms_rescue_stops_paying()
	_test_a_rescue_is_a_budget_line()
	_test_the_forecast_sees_the_rescue_end()
	_test_a_failed_firm_drops_its_history()
	_test_the_record_follows_a_relocation()
	_test_the_three_answers_each_win_somewhere()
	_test_the_buyer_pays_its_search_and_its_sweetener()
	_test_a_landed_closures_bloc_move_fades()
	_test_the_cooldown_ends_on_its_month()
	_test_a_failed_firms_open_closure_is_voided()
	_test_the_loader_refuses_a_short_cooldown()
	_test_a_closure_offers_three_counters()
	_test_a_countered_buyer_accepts_comes_back_or_walks()
	_test_a_plain_buyer_is_not_said_as_a_counter()
	_test_a_countered_search_on_a_failed_firm_is_said()
	_test_a_firm_that_fails_in_the_re_ask_sells_nothing()
	_test_no_buyer_answer_is_dominated()
	_test_a_countered_closure_survives_a_save()
	_test_one_sector_fall_closes_one_plant()
	_test_a_sector_waits_for_every_open_plant()
	_test_the_fall_picks_by_jobs()
	_test_the_bloc_move_scales_with_the_plant()
	_finish()


## The stand-ins as shipped in data/industry/closures.json, pinned as literals.
const SHIPPED_COOLDOWN := 12
const SHIPPED_CHANCE := 0.18
const SHIPPED_REFERENCE := 0.10
const SHIPPED_SLOPE := 0.35


func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 3
	return state


func _rule() -> Dictionary:
	return _loader.closure_rule


func _majors(ns) -> Array:
	return Companies.majors_of(_loader, ns.id).filter(func(c) -> bool:
		return Companies.share_of_company(ns, c) > 0.0)


## A major with no subsidy, so the firm's own rescue verbs are on offer.
func _unsubsidised(ns):
	for c in _majors(ns):
		if Companies.subsidy_of(ns, String(c.id)) <= 0.0:
			return c
	return null


func _company(ns, company_id: String):
	for c in Companies.majors_of(_loader, ns.id):
		if String(c.id) == company_id:
			return c
	return null


## A history whose oldest month stood `fall` above the output the next tick reads,
## so the coming tick measures exactly that fall over the window.
func _falling(ns, company, fall: float) -> void:
	var now_out := Companies.output_eur_bn(ns, company)
	var h: Array = []
	for i in range(int(_rule()["window_months"])):
		h.append(now_out / (1.0 - fall))
	(ns.companies[String(company.id)] as Dictionary)["closure_watch"] = h


func _month(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	Closures.tick_month(state, _loader)


## The firm's closure record (the live dictionary on its register entry), {} if none.
func _row(ns, company_id: String) -> Dictionary:
	return (ns.companies.get(company_id, {}) as Dictionary).get("closure", {})


func _count(ns) -> int:
	var n := 0
	for company_id in ns.companies:
		if not ((ns.companies[company_id] as Dictionary).get("closure", {}) as Dictionary).is_empty():
			n += 1
	return n


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


## The rescue line's month in EUR bn: what the next Budget.tick_month() puts on the
## debt for it (the line is a percent of GDP, billed a month behind).
func _billed(ns) -> float:
	return float(ns.rescue_bill_pct_gdp) / 100.0 * float(ns.gdp_eur_bn) / 12.0


func _test_the_rule_is_data() -> void:
	var rule := _rule()
	for key in ["window_months", "fall", "cut", "cooldown_months", "bloc_offset", "reference_jobs", "monthly_chance", "reference_fall", "gap_slope"]:
		if not rule.has(key):
			_fail("the closure rule has no %s" % key)
	if int(rule.get("cooldown_months", 0)) < int(rule.get("window_months", 0)) + CK.ANSWER_MONTHS:
		_fail("the cooldown is shorter than a window and an answer: a landed closure would re-announce")


func _test_a_falling_major_announces_a_closure() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _unsubsidised(ns)
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	var jobs := Companies.headcount(ns, firm) * float(_rule()["cut"])
	_month(state)
	var row := _row(ns, String(firm.id))
	if row.is_empty():
		_fail("a major past the fall threshold announced nothing")
		return
	if String(row["status"]) != "announced" or int(row["announced"]) != _now(state) \
			or int(row["due"]) != _now(state) + CK.ANSWER_MONTHS:
		_fail("the closure's status or months are wrong: %s" % row)
	if String(row["city_id"]) != Companies.live_city_of(ns, firm):
		_fail("the closure is not in the firm's live city: %s" % row)
	if not is_equal_approx(float(row["jobs"]), jobs):
		_fail("the jobs at stake are %.1f, not the rule's cut of the payroll %.1f" % [float(row["jobs"]), jobs])
	if (ns.companies[String(firm.id)] as Dictionary).has("closure_watch"):
		_fail("the announcing firm's output history was kept, so its own cut would count as the next fall")
	var ids: Array = Closures.answers(state, ns, _loader, String(row["id"])).map(func(a) -> String: return String(a["id"]))
	if ids != ["close", "buyer"] + NEGOTIATE_IDS + ["rescue"]:
		_fail("the closure offers %s, not close, buyer, its three counters and the rescue" % [ids])
	if Closures.open(ns).size() != 1:
		_fail("the open closures list does not hold the announcement")
	# A fall under the threshold announces nothing.
	var calm = _new_state()
	var cns = calm.player()
	_falling(cns, _majors(cns)[0], 0.5 * float(_rule()["fall"]))
	_month(calm)
	if _count(cns) != 0:
		_fail("a fall under the threshold announced a closure")


func _test_one_announcement_a_month_the_worst_first() -> void:
	var state = _new_state()
	var ns = state.player()
	var a = _majors(ns)[0]
	var b = _majors(ns)[1]
	_falling(ns, a, 2.0 * float(_rule()["fall"]))
	_falling(ns, b, 3.0 * float(_rule()["fall"]))
	_month(state)
	if _count(ns) != 1 or _row(ns, String(b.id)).is_empty():
		_fail("two falling majors did not give one announcement, the worst first")
	if not (ns.companies[String(a.id)] as Dictionary).has("closure_watch"):
		_fail("the firm that did not announce lost its history")


## The rule as it ships, for the tests of the chance: _init makes the chance certain on
## the loaded one, and these must fail on a retune of the shipped numbers.
func _shipped() -> Dictionary:
	var errors: Array[String] = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/industry/closures.json"))
	return CompaniesLoader.parse_closure_rule(parsed, "closures.json", errors)


## The author's call on #286: a closure follows the economy. The month's chance for a
## falling sector reads how far its worst major fell and how far the nation runs below
## its potential. Literals, the stand-ins as shipped.
func _test_the_chance_reads_the_fall_and_the_economy() -> void:
	var rule := _shipped()
	if int(rule["cooldown_months"]) != SHIPPED_COOLDOWN or float(rule["monthly_chance"]) != SHIPPED_CHANCE \
			or float(rule["reference_fall"]) != SHIPPED_REFERENCE or float(rule["gap_slope"]) != SHIPPED_SLOPE:
		_fail("the rule reads %s, not the shipped stand-ins" % [rule])
	var at_rest := Closures.chance(rule, SHIPPED_REFERENCE, 0.0)
	if not is_equal_approx(at_rest, SHIPPED_CHANCE):
		_fail("the reference fall in an economy at its potential reads %.4f, not %.4f" % [at_rest, SHIPPED_CHANCE])
	if Closures.chance(rule, SHIPPED_REFERENCE, -3.0) <= at_rest or Closures.chance(rule, SHIPPED_REFERENCE, 1.0) >= at_rest:
		_fail("the chance does not rise in a slump and fall in a boom: %.4f / %.4f / %.4f" % [
			Closures.chance(rule, SHIPPED_REFERENCE, -3.0), at_rest, Closures.chance(rule, SHIPPED_REFERENCE, 1.0)])
	if Closures.chance(rule, 0.5 * SHIPPED_REFERENCE, 0.0) >= at_rest:
		_fail("a smaller fall is not a smaller chance")
	if Closures.chance(rule, 100.0, -100.0) > 1.0 or Closures.chance(rule, SHIPPED_REFERENCE, 100.0) <= 0.0:
		_fail("the chance leaves (0, 1]: %.4f, %.4f" % [Closures.chance(rule, 100.0, -100.0), Closures.chance(rule, SHIPPED_REFERENCE, 100.0)])
	# QA on #286: each bound, as a literal, at the extreme that reaches it.
	for row in [["the fall's cap", 100.0, 0.0, 1.5], ["the slump's cap", SHIPPED_REFERENCE, -100.0, 3.0],
			["the boom's floor", SHIPPED_REFERENCE, 100.0, 0.2]]:
		if not is_equal_approx(Closures.chance(rule, float(row[1]), float(row[2])), SHIPPED_CHANCE * float(row[3])):
			_fail("%s reads %.4f, not %.4f" % [row[0], Closures.chance(rule, float(row[1]), float(row[2])), SHIPPED_CHANCE * float(row[3])])


## QA on #286: each sector draws its own number. Two sectors falling alike, in a month
## where only one's draw is under the chance, then in one where only the other's is.
func _test_each_sector_draws_its_own_chance() -> void:
	var saved: Dictionary = _loader.closure_rule
	_loader.closure_rule = _shipped()
	var fall := 2.0 * float(_rule()["fall"])
	var odds := Closures.chance(_rule(), fall, 0.0)
	var ns = _new_state().player()
	var peers := _crowded_sector(ns)
	var other = null
	for c in _majors(ns):
		if other == null and c.sector != peers[0].sector:
			other = c
	var key := "closure|fire|FRA|%s"
	var found := {}
	for now in range(24400, 26000):
		var first := Cycle.unit(key % String(peers[0].sector), now) < odds
		var second := Cycle.unit(key % String(other.sector), now) < odds
		if first != second and not found.has(first):
			found[first] = now
	if found.size() != 2:
		_fail("no month stages the two draws apart: %s" % [found])
	for peers_win in found:
		var state = _new_state()
		_set_now(state, int(found[peers_win]) - 1)
		ns = state.player()
		ns.potential_gdp_eur_bn = float(ns.gdp_eur_bn)
		_falling(ns, _crowded_sector(ns)[0], fall)
		_falling(ns, other, fall)
		_month(state)
		var open := Closures.open(ns)
		if open.size() != 1 or (String(open[0]["company_id"]) != String(other.id)) != bool(peers_win):
			_fail("in month %d only one sector's draw came up, and the month announced %s" % [int(found[peers_win]), open])
	_loader.closure_rule = saved


## Announcements in `months` of the closure machine alone: every major of the crowded
## sector falling by `fall` each month, the economy held at `gap_pct` below or above its
## potential, the shipped rule. One seed, so the runs differ only by what they read.
func _rate(fall: float, gap_pct: float, months: int) -> int:
	var saved: Dictionary = _loader.closure_rule
	_loader.closure_rule = _shipped()
	var state = _new_state()
	var ns = state.player()
	var seen := {}
	for i in months:
		ns.potential_gdp_eur_bn = float(ns.gdp_eur_bn) / (1.0 + gap_pct / 100.0)
		for c in _crowded_sector(ns):
			_falling(ns, c, fall)
		_month(state)
		for c in _crowded_sector(ns):
			var row := _row(ns, String(c.id))
			if not row.is_empty():
				seen[String(row["id"])] = true
	_loader.closure_rule = saved
	return seen.size()


## The test that fails if the rate stops reading the economy (the author's call).
func _test_the_rate_follows_the_economy() -> void:
	var slump := _rate(0.10, -4.0, 480)
	var rest := _rate(0.10, 0.0, 480)
	var boom := _rate(0.10, 2.0, 480)
	if not (slump > rest and rest > boom) or float(slump) < 1.5 * float(boom):
		_fail("a sector closes %d plants in a slump, %d at potential, %d in a boom: the rate does not follow the economy" % [slump, rest, boom])


func _test_the_rate_follows_the_sectors_fall() -> void:
	var steep := _rate(0.20, 0.0, 480)
	var shallow := _rate(0.05, 0.0, 480)
	if float(steep) < 1.25 * float(shallow):
		_fail("a sector falling 20 %% closes %d plants, one falling 5 %% closes %d: the rate does not read the fall" % [steep, shallow])


func _test_a_chance_that_does_not_come_up_announces_nothing() -> void:
	var saved := float(_rule()["monthly_chance"])
	_rule()["monthly_chance"] = 0.0
	var state = _new_state()
	var ns = state.player()
	_falling(ns, _majors(ns)[0], 2.0 * float(_rule()["fall"]))
	_month(state)
	_rule()["monthly_chance"] = saved
	if _count(ns) != 0:
		_fail("a fall announced with no chance of it: the timer is back")


## QA's RECORD on #286: a void row is a firm that failed, nothing that closed. Its peers
## must not wait out a cooldown for a plant that never shut.
func _test_a_void_row_does_not_cool_the_sector() -> void:
	var state = _new_state()
	var ns = state.player()
	var peers := _crowded_sector(ns)
	(ns.companies[String(peers[0].id)] as Dictionary)["closure"] = {"id": "x|1", "company_id": String(peers[0].id),
		"city_id": "", "status": "void", "announced": _now(state), "due": _now(state), "ended": _now(state), "fall": 0.1, "jobs": 1.0}
	_falling(ns, peers[1], 2.0 * float(_rule()["fall"]))
	_month(state)
	if _row(ns, String(peers[1].id)).is_empty():
		_fail("a failed firm's void row cooled its sector")


## The author's call: the card's reason is true. The record keeps the picked firm's own
## fall, the months it fell over and the economy the month it was announced.
func _test_the_record_says_what_fell() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	ns.potential_gdp_eur_bn = float(ns.gdp_eur_bn) * 1.03
	_falling(ns, firm, 0.25)
	_month(state)
	var row := _row(ns, String(firm.id))
	if row.is_empty() or not is_equal_approx(float(row["fall"]), 0.25) or int(row["window_months"]) != int(_rule()["window_months"]) \
			or absf(float(row["gap_pct"]) - Economy.output_gap_pct(ns)) > 1e-9:
		_fail("the record does not say what fell: %s" % [row])


## QA on #286: the month's one announcement goes to the sector with the worst fall, and
## a sector's worst firm ranks it, whichever firm the month's loop reaches last. Written
## as multiples of the rule's fall: the two firms of the crowded sector, then the other
## sector's one, and whether the crowded sector should win.
func _test_the_worst_fall_ranks_the_sectors() -> void:
	for case in [[4.0, 2.0, 3.0, true], [2.0, 4.0, 3.0, true], [2.0, 1.5, 3.0, false]]:
		var state = _new_state()
		var ns = state.player()
		var peers := _crowded_sector(ns)
		var other = null
		for c in _majors(ns):
			if other == null and c.sector != peers[0].sector:
				other = c
		if peers.size() < 2 or other == null:
			_fail("no FRA sector holds two majors beside another sector: the case cannot be staged")
			return
		_falling(ns, peers[0], float(case[0]) * float(_rule()["fall"]))
		_falling(ns, peers[peers.size() - 1], float(case[1]) * float(_rule()["fall"]))
		_falling(ns, other, float(case[2]) * float(_rule()["fall"]))
		_month(state)
		var open := Closures.open(ns)
		if open.size() != 1:
			_fail("falls %s gave %d announcements, not one" % [case, open.size()])
			continue
		var crowded_won: bool = String(open[0]["company_id"]) != String(other.id)
		if crowded_won != bool(case[3]):
			_fail("falls %s announced %s" % [case, open[0]["company_id"]])


func _test_an_unanswered_closure_lands_by_default() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var row := _row(ns, String(firm.id))
	var share := Companies.share_of_company(ns, firm)
	var city_jobs := Companies.headcount_in_city(ns, _loader, String(row["city_id"]))
	var offsets: Dictionary = _rule()["bloc_offset"]
	var before := {}
	for bloc in offsets:
		before[bloc] = float(ns.bloc_offset.get(bloc, 0.0))
	for i in range(CK.ANSWER_MONTHS - 1):
		_month(state)
		if String(row["status"]) != "announced":
			_fail("the closure landed before its due month")
			return
	_month(state)
	if String(row["status"]) != "closed":
		_fail("an unanswered closure did not land at its due month: %s" % row)
		return
	if not is_equal_approx(Companies.share_of_company(ns, firm), share * (1.0 - float(_rule()["cut"]))):
		_fail("the landed closure did not cut the firm's share by the rule's cut")
	var lost := city_jobs - Companies.headcount_in_city(ns, _loader, String(row["city_id"]))
	if absf(lost - float(row["jobs"])) > 1e-6 * maxf(city_jobs, 1.0):
		_fail("the city lost %.1f jobs, not the %.1f the closure announced" % [lost, float(row["jobs"])])
	for bloc in offsets:
		var moved := float(offsets[bloc]) * float(row["jobs"]) / float(_rule()["reference_jobs"])
		if not is_equal_approx(float(ns.bloc_offset.get(bloc, 0.0)) - float(before[bloc]), moved):
			_fail("the landed closure did not move %s by the rule's offset for its plant" % bloc)
	if not Closures.open(ns).is_empty():
		_fail("a landed closure is still listed as open")


## QA's call on #270, the parent's ruling: a rescue is priced on the PLANT, not the
## firm's subsidy (which read EUR 5-9 bn a year to keep a 720-job plant). One answer,
## `rescue`: RESCUE_EUR_PER_JOB_YEAR for each job the closure would cut, for
## RESCUE_MONTHS, a Budget line of its own (rescue_bill_pct_gdp, the parent's call 4
## on #277) billed a month behind; the plant is kept for the term,
## announces nothing during it, and is watched afresh after it (a new window, no
## cooldown: the term was the wait). The firm's own subsidy verbs are not touched.
func _test_a_rescue_keeps_the_plant_for_its_term_at_its_price() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _unsubsidised(ns)
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var row := _row(ns, String(firm.id))
	var rescues: Array = Closures.answers(state, ns, _loader, String(row["id"])).filter(func(a) -> bool:
		return String(a["kind"]) == "rescue")
	if rescues.size() != 1 or String(rescues[0]["id"]) != "rescue":
		_fail("the closure offers %s as its rescue, not the one plant rescue" % [rescues])
		return
	var strip: Dictionary = rescues[0]
	var jobs := float(row["jobs"])
	var yearly := jobs * CK.RESCUE_EUR_PER_JOB_YEAR / 1e9
	if not is_equal_approx(float(strip["debt_eur_bn_per_year"]), yearly) or int(strip["months"]) != CK.RESCUE_MONTHS \
			or not is_equal_approx(float(strip["total_eur_bn"]), yearly * float(CK.RESCUE_MONTHS) / 12.0) \
			or int(strip["ends"]) != _now(state) + CK.RESCUE_MONTHS or float(strip["jobs_lost"]) != 0.0:
		_fail("the rescue's strip %s is not %.1f jobs x the plant's price for its term" % [strip, jobs])
	# QA's band for a job kept: EUR 90k to 950k over the deal.
	var per_job := 1e9 * float(strip["total_eur_bn"]) / jobs
	if per_job < 90000.0 or per_job > 950000.0:
		_fail("a job kept costs EUR %.0f over the rescue, outside 90k-950k" % per_job)
	var share := Companies.share_of_company(ns, firm)
	var booked := 0.0
	var r: Dictionary = Closures.answer(state, ns, _loader, String(row["id"]), "rescue")
	if not bool(r.get("ok", false)) or String(row["status"]) != "rescuing" or Closures.rescues(ns).size() != 1:
		_fail("the rescue did not start its term: %s %s" % [r, row])
		return
	if Companies.subsidy_of(ns, String(firm.id)) > 0.0:
		_fail("the plant rescue ran the firm's subsidy verb")
	for i in range(CK.RESCUE_MONTHS):
		_falling(ns, firm, 2.0 * float(_rule()["fall"]))
		_month(state)
		booked += _billed(ns)
		if Companies.share_of_company(ns, firm) < share or _row(ns, String(firm.id))["id"] != row["id"]:
			_fail("the rescued plant closed or announced again in month %d of its term" % (i + 1))
			return
	if absf(booked - float(strip["total_eur_bn"])) > 1e-9:
		_fail("the term billed %.6f bn, not the strip's %.6f" % [booked, float(strip["total_eur_bn"])])
	if String(row["status"]) != "rescued" or not Closures.rescues(ns).is_empty():
		_fail("the rescue did not end with its term: %s" % row)
	# Watched afresh: a fall over a new window announces again, with no cooldown.
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	if String(_row(ns, String(firm.id)).get("status", "")) != "announced":
		_fail("a plant still falling after its rescue was not re-evaluated")
	# The term's last month was billed by the tick that ended it (a month behind);
	# the month after it bills nothing.
	if float(ns.rescue_bill_pct_gdp) != 0.0:
		_fail("the rescue still bills %.6f %% of GDP the month after its term" % float(ns.rescue_bill_pct_gdp))


func _test_a_buyer_search_resolves_on_its_seed() -> void:
	var outcomes := {}
	for k in range(6):
		var state = _new_state()
		state.year = 2026 + k
		var ns = state.player()
		var firm = _majors(ns)[0]
		_falling(ns, firm, 2.0 * float(_rule()["fall"]))
		_month(state)
		var row := _row(ns, String(firm.id))
		var share := Companies.share_of_company(ns, firm)
		if not bool(Closures.answer(state, ns, _loader, String(row["id"]), "buyer").get("ok", false)) \
				or String(row["status"]) != "searching":
			_fail("answering buyer did not start the search: %s" % row)
			return
		for i in range(CK.BUYER_MONTHS - 1):
			_month(state)
			if String(row["status"]) != "searching":
				_fail("the buyer search ended before its months")
				return
		_month(state)
		var found := Cycle.unit("closure|%s|buyer" % String(row["id"]), _now(state)) < CK.BUYER_CHANCE
		var want := "sold" if found else "closed"
		if String(row["status"]) != want:
			_fail("the search ended %s, its seed says %s" % [row["status"], want])
		var cut := share * (1.0 - float(_rule()["cut"]))
		if found and not is_equal_approx(Companies.share_of_company(ns, firm), share):
			_fail("a plant sold to a buyer still lost its jobs")
		if not found and not is_equal_approx(Companies.share_of_company(ns, firm), cut):
			_fail("a search that found no buyer did not close the plant")
		outcomes[want] = true
	if outcomes.size() < 2:
		_fail("six searches all ended %s: the seed never varies" % [outcomes.keys()])


func _test_a_closed_firm_does_not_announce_again_in_its_cooldown() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	for i in range(CK.ANSWER_MONTHS):
		_month(state)
	if String(_row(ns, String(firm.id))["status"]) != "closed":
		_fail("the cooldown fixture did not close")
		return
	_falling(ns, firm, 3.0 * float(_rule()["fall"]))
	_month(state)
	if String(_row(ns, String(firm.id))["status"]) != "closed":
		_fail("a firm that just closed a plant announced again inside its cooldown")


func _test_only_the_player_announces() -> void:
	var state = _new_state()
	var other = state.nations["DEU"]
	for company in Companies.majors_of(_loader, "DEU"):
		_falling(other, company, 3.0 * float(_rule()["fall"]))
	_month(state)
	if _count(other) != 0:
		_fail("a nation the player does not lead announced a closure: nobody can answer it")


func _test_a_firm_in_a_process_does_not_announce() -> void:
	var state = _new_state()
	var ns = state.player()
	var stake = null
	for a in _loader.company_actions:
		if String(a.id) == "minority_stake":
			stake = a
	var firm = null
	for c in _majors(ns):
		if bool(Processes.start(state, ns, _loader, stake, String(c.id)).get("applied", false)):
			firm = c
			break
	if firm == null:
		_fail("no process opened, so the process gate asserts nothing")
		return
	_falling(ns, firm, 3.0 * float(_rule()["fall"]))
	_month(state)
	if not _row(ns, String(firm.id)).is_empty():
		_fail("a firm already in a process announced a closure")


func _test_answer_refusals() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var id := String(_row(ns, String(firm.id))["id"])
	if bool(Closures.answer(state, ns, _loader, "nothing|here", "close").get("ok", true)):
		_fail("an unknown closure took an answer")
	if bool(Closures.answer(state, ns, _loader, id, "nonsense").get("ok", true)):
		_fail("an answer the closure does not offer was taken")
	Closures.answer(state, ns, _loader, id, "buyer")
	if bool(Closures.answer(state, ns, _loader, id, "close").get("ok", true)):
		_fail("a closure was answered twice")



## The closure lives on the firm's register entry, which the field table deep-copies:
## a save keeps an announced closure and its history, and the loaded game lands it
## on time. No SAVE bump: an entry without the keys reads "no closure, no history",
## the truth for every save made before V5.3 a.
func _test_a_closure_survives_a_save() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	var other = _majors(ns)[1]
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var payload = JSON.parse_string(JSON.stringify(state.to_dict()))
	var kept = GameState.from_dict(payload)
	var kns = kept.player()
	if Closures.open(kns).size() != 1 or not (kns.companies[String(other.id)] as Dictionary).has("closure_watch"):
		_fail("the closure or the output history did not survive the round trip")
	for i in range(CK.ANSWER_MONTHS):
		_month(kept)
	if String(_row(kns, String(firm.id)).get("status", "")) != "closed":
		_fail("a loaded closure did not land at its due month")
	var without = JSON.parse_string(JSON.stringify(state.to_dict()))
	for company_id in without["nations"]["FRA"]["companies"]:
		(without["nations"]["FRA"]["companies"][company_id] as Dictionary).erase("closure")
		(without["nations"]["FRA"]["companies"][company_id] as Dictionary).erase("closure_watch")
	if not Closures.open(GameState.from_dict(without).player()).is_empty():
		_fail("an entry with no closure keys did not read as no closure")
	# A rescue's term survives a save mid-way: it keeps paying and ends on its month.
	var rescued = _new_state()
	var rns = rescued.player()
	_falling(rns, firm, 2.0 * float(_rule()["fall"]))
	_month(rescued)
	Closures.answer(rescued, rns, _loader, String(_row(rns, String(firm.id))["id"]), "rescue")
	_month(rescued)
	var mid = GameState.from_dict(JSON.parse_string(JSON.stringify(rescued.to_dict())))
	var mns = mid.player()
	var booked := 0.0
	var row := _row(mns, String(firm.id))
	if Closures.rescues(mns).size() != 1 or int(row.get("months_left", 0)) != CK.RESCUE_MONTHS - 1:
		_fail("a rescue's term did not survive the round trip: %s" % row)
		return
	for i in range(CK.RESCUE_MONTHS - 1):
		_month(mid)
		booked += _billed(mns)
	if String(row["status"]) != "rescued" or not is_equal_approx(booked,
			float(row["rescue_eur_bn_per_year"]) * float(CK.RESCUE_MONTHS - 1) / 12.0):
		_fail("a loaded rescue did not pay out and end on its month: %s" % row)



## Review pass 1: a failed firm's history stops with it, so a rescue months later
## starts a fresh window instead of comparing across the months it was gone.
func _test_a_failed_firm_drops_its_history() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	_falling(ns, firm, 0.5 * float(_rule()["fall"]))
	(ns.companies[String(firm.id)] as Dictionary)["failed"] = true
	_month(state)
	if (ns.companies[String(firm.id)] as Dictionary).has("closure_watch"):
		_fail("a failed firm kept its output history")


## Review pass 1: the record names the city the cut hits, so a relocation between
## the announcement and the cut moves the record with the payroll.
func _test_the_record_follows_a_relocation() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var row := _row(ns, String(firm.id))
	var elsewhere := ""
	for c in Companies.majors_of(_loader, ns.id):
		if Companies.live_city_of(ns, c) != String(row["city_id"]):
			elsewhere = Companies.live_city_of(ns, c)
			break
	if elsewhere == "":
		_fail("no second city to relocate to, so the check asserts nothing")
		return
	(ns.companies[String(firm.id)] as Dictionary)["city"] = elsewhere
	for i in range(CK.ANSWER_MONTHS):
		_month(state)
	if String(row["city_id"]) != elsewhere:
		_fail("the landed closure names %s, not the city its cut hit, %s" % [row["city_id"], elsewhere])


## Parent TAKE 1 on #251 (B5's no-dominated-pair rule), re-cut for the plant rescue
## (QA's call on #270): the three strips side by side on three figures, each better
## when smaller -- the expected money on the debt over the whole deal (the rescue's
## term; the buyer's search plus its chance of the sweetener), the expected jobs lost
## now, and the expected jobs not secured for good (a rescue keeps the plant only for
## its term, then it is re-evaluated; a buyer who takes it keeps it). No answer may be
## at least as good on all three and better on one: close is the cheapest, the
## rescue the surest now, the buyer the only lasting answer.
func _test_the_three_answers_each_win_somewhere() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _unsubsidised(ns)
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var row := _row(ns, String(firm.id))
	var strips := {}
	for a in Closures.answers(state, ns, _loader, String(row["id"])):
		var jobs := float(row["jobs"])
		match String(a["kind"]):
			"close":
				strips["close"] = [float(a["debt_eur_bn"]), jobs, jobs]
			"buyer":
				var kept := float(a["chance"]) * jobs
				strips["buyer"] = [float(a["debt_eur_bn"]) + float(a["chance"]) * float(a["sweetener_eur_bn"]), jobs - kept, jobs - kept]
			"rescue":
				strips["rescue"] = [float(a["total_eur_bn"]), float(a["jobs_lost"]), jobs]
	if strips.size() != 3:
		_fail("the closure does not offer close, buyer and a rescue: %s" % [strips.keys()])
		return
	if float(strips["buyer"][0]) <= 0.0 or float(strips["rescue"][0]) <= 0.0:
		_fail("a buyer or a rescue is free (%s): it dominates letting the plant close" % [strips])
	for a in strips:
		for b in strips:
			if a == b:
				continue
			var x: Array = strips[a]
			var y: Array = strips[b]
			var no_worse := true
			var better := false
			for i in 3:
				no_worse = no_worse and float(x[i]) <= float(y[i])
				better = better or float(x[i]) < float(y[i])
			if no_worse and better:
				_fail("%s %s dominates %s %s" % [a, x, b, y])


## The buyer's price: the plant's losses for the search months, paid at the answer,
## and the sweetener on the buyer's price, paid only if a buyer is found -- each the
## figure its strip showed.
func _test_the_buyer_pays_its_search_and_its_sweetener() -> void:
	var outcomes := {}
	for k in range(6):
		var state = _new_state()
		state.year = 2026 + k
		var ns = state.player()
		var firm = _majors(ns)[0]
		_falling(ns, firm, 2.0 * float(_rule()["fall"]))
		_month(state)
		var row := _row(ns, String(firm.id))
		var strip := {}
		for a in Closures.answers(state, ns, _loader, String(row["id"])):
			if String(a["kind"]) == "buyer":
				strip = a
		var debt := float(ns.debt_eur_bn)
		Closures.answer(state, ns, _loader, String(row["id"]), "buyer")
		if not is_equal_approx(float(ns.debt_eur_bn) - debt, float(strip["debt_eur_bn"])) or float(strip["debt_eur_bn"]) <= 0.0:
			_fail("the search booked %.5f, its strip showed %.5f" % [float(ns.debt_eur_bn) - debt, float(strip["debt_eur_bn"])])
		for i in range(CK.BUYER_MONTHS):
			_month(state)
		var paid := float(ns.debt_eur_bn) - debt
		var want := float(strip["debt_eur_bn"])
		if String(row["status"]) == "sold":
			want += float(strip["sweetener_eur_bn"])
		if not is_equal_approx(paid, want):
			_fail("a search that ended %s cost %.5f, not %.5f" % [row["status"], paid, want])
		outcomes[String(row["status"])] = true
	if outcomes.size() < 2:
		_fail("the sweetener was never tested both ways: %s" % [outcomes.keys()])


## Parent TAKE 2 on #251: a landed closure's bloc move is an act, not a standing
## condition, so it is booked on the act-fading register (#104's half-life,
## Characters fades it) rather than written on bloc_offset for good.
func _test_a_landed_closures_bloc_move_fades() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var row := _row(ns, String(firm.id))
	var before: Dictionary = (ns.bloc_offset as Dictionary).duplicate()
	var acts: Dictionary = (ns.act_bloc_offset as Dictionary).duplicate()
	Closures.answer(state, ns, _loader, String(row["id"]), "close")
	for bloc in _rule()["bloc_offset"]:
		var wrote := float(ns.bloc_offset.get(bloc, 0.0)) - float(before.get(bloc, 0.0))
		var booked := float(ns.act_bloc_offset.get(bloc, 0.0)) - float(acts.get(bloc, 0.0))
		if wrote == 0.0 or not is_equal_approx(booked, wrote):
			_fail("%s: the closure wrote %.4f and booked %.4f to fade" % [bloc, wrote, booked])


## QA's RECORD C2 on #251: the cooldown's first allowed month is the closure's end +
## cooldown_months. A month before it a fall is ignored; on it the firm announces.
func _test_the_cooldown_ends_on_its_month() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	for i in range(CK.ANSWER_MONTHS):
		_month(state)
	var row := _row(ns, String(firm.id))
	if String(row.get("status", "")) != "closed":
		_fail("the cooldown boundary fixture did not close: %s" % row)
		return
	var first := int(row["ended"]) + int(_rule()["cooldown_months"])
	_set_now(state, first - 1)
	_falling(ns, firm, 3.0 * float(_rule()["fall"]))
	Closures.tick_month(state, _loader)
	if String(_row(ns, String(firm.id))["status"]) != "closed":
		_fail("a firm announced a month before its cooldown ended")
	_set_now(state, first)
	_falling(ns, firm, 3.0 * float(_rule()["fall"]))
	Closures.tick_month(state, _loader)
	if String(_row(ns, String(firm.id))["status"]) != "announced":
		_fail("a firm did not announce on its cooldown's first allowed month")


## QA's RECORD C6 on #251: a firm that fails while its closure is open has nothing
## left to close. The record is voided at once, and no cut or bloc move lands later.
func _test_a_failed_firms_open_closure_is_voided() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _majors(ns)[0]
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	if String(_row(ns, String(firm.id)).get("status", "")) != "announced":
		_fail("the void fixture did not announce")
		return
	var offsets: Dictionary = (ns.bloc_offset as Dictionary).duplicate()
	(ns.companies[String(firm.id)] as Dictionary)["failed"] = true
	_month(state)
	if String(_row(ns, String(firm.id))["status"]) != "void" or not Closures.open(ns).is_empty():
		_fail("a failed firm's open closure is %s, not void" % _row(ns, String(firm.id))["status"])
	for i in range(CK.ANSWER_MONTHS):
		_month(state)
	if (ns.bloc_offset as Dictionary) != offsets:
		_fail("a voided closure moved a bloc")


## QA's RECORD C10 on #251: the loader refuses a cooldown shorter than a window and
## an answer. At the boundary: exactly a window and an answer loads; a month less is
## refused, and refused rules come back empty.
func _test_the_loader_refuses_a_short_cooldown() -> void:
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/industry/closures.json"))
	var least := float(good["window_months"]) + float(CK.ANSWER_MONTHS)
	var at := good.duplicate(true)
	at["cooldown_months"] = least
	var errors: Array[String] = []
	if CompaniesLoader.parse_closure_rule(at, "closures.json", errors).is_empty() or not errors.is_empty():
		_fail("a cooldown of exactly a window and an answer was refused: %s" % [errors])
	var short := good.duplicate(true)
	short["cooldown_months"] = least - 1.0
	var refused: Array[String] = []
	if not CompaniesLoader.parse_closure_rule(short, "closures.json", refused).is_empty() or refused.is_empty():
		_fail("a cooldown a month shorter than a window and an answer was accepted")
	for key in ["reference_jobs", "monthly_chance", "reference_fall", "gap_slope"]:
		var missing := good.duplicate(true)
		missing.erase(key)
		var unread: Array[String] = []
		if not CompaniesLoader.parse_closure_rule(missing, "closures.json", unread).is_empty() or unread.is_empty():
			_fail("a rule with no %s was accepted" % key)
	for key in ["monthly_chance", "reference_fall"]:
		var whole := good.duplicate(true)
		whole[key] = 1.0
		var refused_whole: Array[String] = []
		if not CompaniesLoader.parse_closure_rule(whole, "closures.json", refused_whole).is_empty() or refused_whole.is_empty():
			_fail("a rule with %s at 1 or more was accepted: the chance would be a timer" % key)


func _set_now(state, absolute_month: int) -> void:
	state.year = floori(float(absolute_month - 1) / 12.0)
	state.month = (absolute_month - 1) % 12 + 1


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_closures")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)


# --- One closure per sector fall (the parent's ruling on the majors PR) -----------------

## The FRA sector with the most majors.
func _crowded_sector(ns) -> Array:
	var by_sector := {}
	for c in _majors(ns):
		if not by_sector.has(c.sector):
			by_sector[c.sector] = []
		(by_sector[c.sector] as Array).append(c)
	var best: Array = []
	for sector in by_sector:
		if (by_sector[sector] as Array).size() > best.size():
			best = by_sector[sector]
	return best


## Adding real majors must not change the calibrated rate: one fall closes one plant.
## While it waits for an answer, and for the cooldown after it ends, the sector announces
## nothing, whichever of its majors falls; then it may again. Pinned over a sector of
## several majors, all falling every month.
func _test_one_sector_fall_closes_one_plant() -> void:
	var state = _new_state()
	var ns = state.player()
	var peers := _crowded_sector(ns)
	if peers.size() < 2:
		_fail("no FRA sector holds two majors: the rule's case cannot be staged")
		return
	var ids := {}
	var ended := -1
	var cooldown := int(_rule()["cooldown_months"])
	for i in CK.ANSWER_MONTHS + cooldown + 2:
		for c in peers:
			_falling(ns, c, 2.0 * float(_rule()["fall"]))
		_month(state)
		for c in peers:
			var row := _row(ns, String(c.id))
			if not row.is_empty():
				ids[String(row["id"])] = true
				if ended < 0 and int(row["ended"]) > 0:
					ended = int(row["ended"])
		if ended < 0 or _now(state) < ended + cooldown:
			if ids.size() > 1:
				_fail("the sector announced %d closures in month %d, its first ended in %d" % [ids.size(), _now(state), ended])
				return
	if ended < 0 or ids.size() != 2:
		_fail("the sector's second closure after the cooldown: %d announced, the first ended in %d" % [ids.size(), ended])


## QA's MUST at the merge with main: a plant still open holds its whole sector, whatever
## it waits for. An offered or rescuing row has ended = -1, so a cooldown test alone
## passes it and a sibling would announce while the plant is still open. A rescue that
## ended holds nothing (its term was the wait), nor does a void row (no plant closed).
func _test_a_sector_waits_for_every_open_plant() -> void:
	var state = _new_state()
	var ns = state.player()
	var peers := _crowded_sector(ns)
	if peers.size() < 2:
		_fail("no FRA sector holds two majors: the rule's case cannot be staged")
		return
	var now := _now(state)
	var cooldown := int(_rule()["cooldown_months"])
	var entry: Dictionary = ns.companies[String(peers[0].id)]
	for case in [[Closures.ANNOUNCED, -1, false], [Closures.SEARCHING, -1, false], [Closures.OFFERED, -1, false],
			[Closures.RESCUING, -1, false], ["closed", now - 1, false], ["sold", now - 1, false],
			["closed", now - cooldown, true], ["sold", now - cooldown, true], ["rescued", now - 1, true], ["void", now - 1, true]]:
		entry["closure"] = {"status": case[0], "ended": case[1]}
		if Closures._sector_may_announce(ns, _majors(ns), peers[0].sector, _rule(), now) != case[2]:
			_fail("a sibling's closure %s, ended %d: the sector may announce should read %s" % [case[0], case[1], case[2]])
	# The real road: a rescue running, the sibling falling every month, nothing announced;
	# the month the term ends, the sibling may (no cooldown: the term was the wait).
	state = _new_state()
	ns = state.player()
	peers = _crowded_sector(ns)
	_falling(ns, peers[0], 2.0 * float(_rule()["fall"]))
	_month(state)
	var row := _row(ns, String(peers[0].id))
	if row.is_empty() or not bool(Closures.answer(state, ns, _loader, String(row["id"]), "rescue").get("ok", false)):
		_fail("premise: no rescue to stage: %s" % row)
		return
	for i in 3:
		_falling(ns, peers[1], 2.0 * float(_rule()["fall"]))
		_month(state)
		if not _row(ns, String(peers[1].id)).is_empty():
			_fail("a sibling announced in month %d of its sector's running rescue" % (i + 1))
			return
	row["months_left"] = 1
	_falling(ns, peers[1], 2.0 * float(_rule()["fall"]))
	_month(state)
	if String(row["status"]) != "rescued" or _row(ns, String(peers[1].id)).is_empty():
		_fail("the term ended (%s) and the falling sibling announced nothing" % row["status"])


## One fall picks one of the majors past the threshold, weighted by its jobs. With all
## of a sector's majors falling, one with most of its payroll is picked that often.
func _test_the_fall_picks_by_jobs() -> void:
	var trials := 80
	var picks := 0
	var want := 0.0
	for k in trials:
		var state = _new_state()
		state.year = 2026 + k
		var ns = state.player()
		var peers := _crowded_sector(ns)
		var big = peers[0]
		(ns.companies[String(big.id)] as Dictionary)["share"] = 20.0 * Companies.share_of_company(ns, big)
		var total := 0.0
		for c in peers:
			total += Companies.headcount(ns, c)
			_falling(ns, c, 2.0 * float(_rule()["fall"]))
		want = Companies.headcount(ns, big) / total
		_month(state)
		if not _row(ns, String(big.id)).is_empty():
			picks += 1
	if want < 0.6 or absf(float(picks) / float(trials) - want) > 0.15:
		_fail("a major with %.0f %% of its sector's jobs was picked %d times of %d" % [100.0 * want, picks, trials])


## A landed closure's bloc move scales with the plant's jobs: the rule's -0.02 is the
## move of a plant of `reference_jobs` (a stand-in, data), so a small plant moves the
## workers less than a large one. The strip shows the move that lands. Literals: the
## parent's ruling restores #251's cooldown and move.
func _test_the_bloc_move_scales_with_the_plant() -> void:
	if float((_rule()["bloc_offset"] as Dictionary)["workers"]) != -0.02 or float(_rule()["reference_jobs"]) != 2500.0:
		_fail("the rule reads workers %s and reference jobs %s, not #251's -0.02 at 2500" % [
			_rule()["bloc_offset"], _rule()["reference_jobs"]])
	var moves: Array = []
	for scale in [1.0, 2.0]:
		var state = _new_state()
		var ns = state.player()
		var firm = _majors(ns)[0]
		(ns.companies[String(firm.id)] as Dictionary)["share"] = scale * Companies.share_of_company(ns, firm)
		_falling(ns, firm, 2.0 * float(_rule()["fall"]))
		_month(state)
		var row := _row(ns, String(firm.id))
		var want := -0.02 * float(row["jobs"]) / 2500.0
		var strip: Dictionary = Closures.answers(state, ns, _loader, String(row["id"]))[0]
		var before := float(ns.bloc_offset.get("workers", 0.0))
		Closures.answer(state, ns, _loader, String(row["id"]), "close")
		var moved := float(ns.bloc_offset.get("workers", 0.0)) - before
		if not is_equal_approx(moved, want) or not is_equal_approx(float(strip["bloc_offset"]["workers"]), want):
			_fail("a plant of %.0f jobs moved the workers %.5f (strip %s), not %.5f" % [float(row["jobs"]), moved, strip["bloc_offset"], want])
		moves.append(moved)
	if not is_equal_approx(float(moves[1]), 2.0 * float(moves[0])):
		_fail("twice the plant did not move the workers twice as far: %s" % [moves])


## QA's TAKE 1 on #277: a firm that fails during its plant's rescue voids the term,
## and nothing more is paid.
func _test_a_failed_firms_rescue_stops_paying() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _unsubsidised(ns)
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var row := _row(ns, String(firm.id))
	Closures.answer(state, ns, _loader, String(row["id"]), "rescue")
	for i in 3:
		_month(state)
	(ns.companies[String(firm.id)] as Dictionary)["failed"] = true
	_month(state)
	var booked := _billed(ns)
	for i in 3:
		_month(state)
		booked += _billed(ns)
	if String(row["status"]) != "void" or booked != 0.0:
		_fail("a failed firm's rescue still runs (%s) or still bills (%.6f bn more)" % [row["status"], booked])


## The parent's call 4 on #277: a running rescue is a Budget line of its own, read
## into the deficit like every computed line and carried on the snapshot the Budget
## panel reads (Interface shows it), so its cost is on the debt path the player sees.
func _test_a_rescue_is_a_budget_line() -> void:
	var plain = _new_state()
	var billed = _new_state()
	billed.player().rescue_bill_pct_gdp = 0.25
	Budget.tick_month(plain)
	Budget.tick_month(billed)
	var gap := float(billed.player().deficit_pct_gdp) - float(plain.player().deficit_pct_gdp)
	if not is_equal_approx(gap, 0.25):
		_fail("a rescue bill of 0.25 %% of GDP moved the deficit by %.6f" % gap)
	var snap: Dictionary = Budget.snapshot(billed)
	if not is_equal_approx(float(snap.get("rescue_bill_pct_gdp", -1.0)), 0.25):
		_fail("the Budget snapshot does not carry the rescue's bill: %s" % [snap.get("rescue_bill_pct_gdp")])


## Budget.project() counts the rescue terms down (Closures.tick_rescues), so the
## 24-month forecast books a rescue's bill while it runs and drops it when it ends.
func _test_the_forecast_sees_the_rescue_end() -> void:
	var still = _new_state()
	var rescued = _new_state()
	for state in [still, rescued]:
		var ns = state.player()
		_falling(ns, _unsubsidised(ns), 2.0 * float(_rule()["fall"]))
		_month(state)
	var rns = rescued.player()
	var row := _row(rns, String(_unsubsidised(rns).id))
	Closures.answer(rescued, rns, _loader, String(row["id"]), "rescue")
	row["months_left"] = 6
	var a: Array = Budget.project(still, {}, 24, _loader)
	var b: Array = Budget.project(rescued, {}, 24, _loader)
	var bill := 100.0 * float(row["rescue_eur_bn_per_year"]) / float(rns.gdp_eur_bn)
	var during := float(b[3]["total_spending_pct_gdp"]) - float(a[3]["total_spending_pct_gdp"])
	var after := float(b[20]["total_spending_pct_gdp"]) - float(a[20]["total_spending_pct_gdp"])
	if bill <= 0.0 or absf(during - bill) > 0.1 * bill:
		_fail("the forecast's spending in the rescue's fourth month is up %.6f, not about its bill %.6f" % [during, bill])
	if absf(after) > 0.1 * bill:
		_fail("the forecast still books %.6f of spending after the rescue ended" % after)
	if String(row["status"]) != Closures.RESCUING or int(row["months_left"]) != 6:
		_fail("the forecast moved the real rescue's term: %s" % row)


# --- Negotiate PR 2: the closing plant's buyer -----------------------------------------

const NEGOTIATE_IDS := ["negotiate_5", "negotiate_10", "negotiate_15"]


## [state, ns, firm, row]: the first major's closure announced in March of `year`.
func _announced(year: int) -> Array:
	var state = _new_state()
	state.year = year
	var ns = state.player()
	var firm = _majors(ns)[0]
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	return [state, ns, firm, _row(ns, String(firm.id))]


func _answer_of(answers: Array, answer_id: String) -> Dictionary:
	for a in answers:
		if String(a["id"]) == answer_id:
			return a
	return {}


## The parent's calls 3 and 4 on Negotiate: the closing plant's buyer can be
## countered, its sweetener cut by 5, 10 or 15 %. Each counter is the buyer's search
## (its chance, months and losses, paid at the answer) with the sweetener cut, the old
## one kept for a buyer that comes back, a month more on the longest road, and the
## buyer's odds at full strength (Negotiation.odds at leverage 1: 55, 35 and 15 %,
## stand-ins the parent accepted, pinned as literals) inside the range the strip
## shows -- fixed on the announcement's month, so it does not move as the answer waits.
func _test_a_closure_offers_three_counters() -> void:
	var at: Array = _announced(2026)
	var state = at[0]
	var ns = at[1]
	var row: Dictionary = at[3]
	var answers: Array = Closures.answers(state, ns, _loader, String(row["id"]))
	var ids: Array = answers.map(func(a) -> String: return String(a["id"]))
	if ids != ["close", "buyer"] + NEGOTIATE_IDS + ["rescue"]:
		_fail("the closure offers %s, not close, buyer, the three counters and the rescue" % [ids])
		return
	var buyer: Dictionary = answers[1]
	var want_odds := [0.55, 0.35, 0.15]
	for i in 3:
		var a: Dictionary = answers[2 + i]
		var c := float(NK.NEGOTIATE_COUNTERS[i])
		if String(a["kind"]) != "negotiate" or float(a["counter"]) != c \
				or not is_equal_approx(float(a["sweetener_eur_bn"]), float(buyer["sweetener_eur_bn"]) * (1.0 - c)) \
				or float(a["back_sweetener_eur_bn"]) != float(buyer["sweetener_eur_bn"]) or float(a["debt_eur_bn"]) != float(buyer["debt_eur_bn"]) \
				or float(a["chance"]) != float(buyer["chance"]) or int(a["months"]) != int(buyer["months"]) \
				or int(a["months_hi"]) != int(buyer["months"]) + 1 or float(a["jobs_lost"]) != float(buyer["jobs_lost"]) \
				or not (a["bloc_offset"] as Dictionary).is_empty() or float(a["walk"]) != NK.NEGOTIATE_WALK:
			_fail("%s reads %s against the buyer's %s" % [a["id"], a, buyer])
		if not is_equal_approx(float(a["odds"]), float(want_odds[i])):
			_fail("%s's buyer accepts at %.3f, not %.2f" % [a["id"], float(a["odds"]), float(want_odds[i])])
		if float(a["odds"]) < float(a["odds_lo"]) or float(a["odds"]) > float(a["odds_hi"]) \
				or not is_equal_approx(float(a["odds_hi"]) - float(a["odds_lo"]), 2.0 * NK.NEGOTIATE_FOG):
			_fail("%s shows %s..%s for a true %.3f" % [a["id"], a["odds_lo"], a["odds_hi"], float(a["odds"])])
	var shown: Array = answers.map(func(a) -> float: return float(a.get("odds_lo", -1.0)))
	_month(state)
	var later: Array = Closures.answers(state, ns, _loader, String(row["id"])).map(func(a) -> float: return float(a.get("odds_lo", -1.0)))
	if later != shown:
		_fail("the counters' ranges moved while the answer waited: %s -> %s" % [shown, later])


## A countered search ends on the buyer's own seed, as the plain one does: no buyer,
## the plant closes and nothing more is paid. A buyer found answers the counter on its
## own seed: accepted, the sale books the cut sweetener; walked, the buyer leaves and
## the plant closes; back (the parent's ruling (b)), the buyer comes back at the OLD
## sweetener and the player is asked once more, for a month: sell at it (the default)
## or close -- the closure's new status, offered.
func _test_a_countered_buyer_accepts_comes_back_or_walks() -> void:
	var seen := {}
	for k in 80:
		var at: Array = _announced(2026 + k)
		var row: Dictionary = at[3]
		var end := _now(at[0]) + CK.BUYER_MONTHS
		for answer_id in NEGOTIATE_IDS:
			var a := _answer_of(Closures.answers(at[0], at[1], _loader, String(row["id"])), answer_id)
			var leg := "none"
			if Cycle.unit("closure|%s|buyer" % String(row["id"]), end) < CK.BUYER_CHANCE:
				leg = Negotiation.draw(float(a["odds"]), Negotiation.key(row, answer_id), end)
			var legs: Array = ["back", "back_close"] if leg == "back" else [leg]
			for l in legs:
				if not seen.has(l):
					seen[l] = true
					_check_closure_leg(2026 + k, answer_id, String(l))
		if seen.size() == 5:
			return
	_fail("80 seeded closures drew only %s" % [seen.keys()])


func _check_closure_leg(year: int, answer_id: String, leg: String) -> void:
	var at: Array = _announced(year)
	var state = at[0]
	var ns = at[1]
	var firm = at[2]
	var row: Dictionary = at[3]
	var label := "%s %s" % [answer_id, leg]
	var a := _answer_of(Closures.answers(state, ns, _loader, String(row["id"])), answer_id)
	var share := Companies.share_of_company(ns, firm)
	var cut := share * (1.0 - float(_rule()["cut"]))
	var debt := float(ns.debt_eur_bn)
	if not bool(Closures.answer(state, ns, _loader, String(row["id"]), answer_id).get("ok", false)) \
			or String(row["status"]) != Closures.SEARCHING or not is_equal_approx(float(ns.debt_eur_bn) - debt, float(a["debt_eur_bn"])):
		_fail("%s: the counter did not start the search at its losses: %s" % [label, row])
		return
	debt = float(ns.debt_eur_bn)
	for i in range(CK.BUYER_MONTHS):
		# Pass 1: the firm's output falls again before the search ends, so only the
		# re-ask's own guard (_sector_may_announce) keeps a new announcement off it.
		if i == CK.BUYER_MONTHS - 1:
			_falling(ns, firm, 2.0 * float(_rule()["fall"]))
		_month(state)
		if i < CK.BUYER_MONTHS - 1 and not _said(state, ns, row).is_empty():
			_fail("%s: said before the answer: %s" % [label, _said(state, ns, row)])
	var record: Dictionary = row.get("negotiation", {})
	var outcome := "" if leg == "none" else ("back" if leg == "back_close" else leg)
	if String(record.get("outcome", "")) != outcome or (outcome != "" and String(record.get("answer", "")) != answer_id):
		_fail("%s: the row records %s" % [label, record])
	var outcomes := {"none": "no_buyer", "walked": "walked", "accepted": "accepted", "back": "back", "back_close": "back"}
	var money := {"accepted": float(a["sweetener_eur_bn"]), "back": float(a["back_sweetener_eur_bn"]), "back_close": float(a["back_sweetener_eur_bn"])}
	_check_said(state, ns, row, firm, String(outcomes[leg]), float(money.get(leg, 0.0)), label)
	match leg:
		"none", "walked":
			if String(row["status"]) != "closed" or not is_equal_approx(Companies.share_of_company(ns, firm), cut) or float(ns.debt_eur_bn) != debt:
				_fail("%s: ended %s, share %.5f (cut %.5f), paid %.5f more" % [label, row["status"], Companies.share_of_company(ns, firm), cut, float(ns.debt_eur_bn) - debt])
		"accepted":
			if String(row["status"]) != "sold" or not is_equal_approx(Companies.share_of_company(ns, firm), share) \
					or not is_equal_approx(float(ns.debt_eur_bn) - debt, float(a["sweetener_eur_bn"])):
				_fail("%s: ended %s, paid %.5f, not the cut sweetener %.5f" % [label, row["status"], float(ns.debt_eur_bn) - debt, float(a["sweetener_eur_bn"])])
		"back", "back_close":
			var again: Array = Closures.answers(state, ns, _loader, String(row["id"]))
			var buyer := _answer_of(again, "buyer")
			if String(row["status"]) != Closures.OFFERED or int(row["offered"]) != _now(state) or int(row["due"]) != _now(state) + 1 \
					or String(_row(ns, String(firm.id)).get("id", "")) != String(row["id"]) or float(ns.debt_eur_bn) != debt or again.map(func(x) -> String: return String(x["id"])) != ["close", "buyer"] \
					or float(buyer.get("sweetener_eur_bn", -1.0)) != float(a["back_sweetener_eur_bn"]) or float(buyer.get("chance", -1.0)) != 1.0 \
					or float(buyer.get("debt_eur_bn", -1.0)) != 0.0 or Closures.open(ns).size() != 1:
				_fail("%s: came back as %s, asking %s" % [label, row, again])
				return
			if bool(Closures.answer(state, ns, _loader, String(row["id"]), "rescue").get("ok", true)):
				_fail("%s: a buyer that came back took a rescue" % label)
			if leg == "back_close":
				Closures.answer(state, ns, _loader, String(row["id"]), "close")
				if String(row["status"]) != "closed" or not is_equal_approx(Companies.share_of_company(ns, firm), cut) or float(ns.debt_eur_bn) != debt:
					_fail("%s: closing the buyer that came back ended %s" % [label, row["status"]])
				_check_said(state, ns, row, firm, "closed", 0.0, label)
				return
			# Answered once, as every ask is: the buyer chosen, closing is no longer asked.
			Closures.answer(state, ns, _loader, String(row["id"]), "buyer")
			if bool(Closures.answer(state, ns, _loader, String(row["id"]), "close").get("ok", true)) \
					or not Closures.answers(state, ns, _loader, String(row["id"])).is_empty():
				_fail("%s: the re-ask took a second answer" % label)
			_month(state)
			if String(row["status"]) != "sold" or not is_equal_approx(Companies.share_of_company(ns, firm), share) \
					or not is_equal_approx(float(ns.debt_eur_bn) - debt, float(a["back_sweetener_eur_bn"])):
				_fail("%s: the buyer that came back ended %s, paid %.5f, not the old sweetener %.5f" % [
					label, row["status"], float(ns.debt_eur_bn) - debt, float(a["back_sweetener_eur_bn"])])
			_check_said(state, ns, row, firm, "sold", float(a["back_sweetener_eur_bn"]), label)
	# Said for its month, not after it.
	_month(state)
	if not _said(state, ns, row).is_empty():
		_fail("%s: still said a month later: %s" % [label, _said(state, ns, row)])


## The parent's ruling on #285, the same as #280's: a countered closure's result is said.
func _check_said(state, ns, row: Dictionary, firm, outcome: String, sweetener: float, label: String) -> void:
	var line := _said(state, ns, row)
	if String(line.get("outcome", "")) != outcome or String(line.get("company_id", "")) != String(firm.id) \
			or String(line.get("city_id", "")) != String(row["city_id"]) or int(line.get("month", -1)) != _now(state) \
			or float(line.get("jobs", -1.0)) != float(row["jobs"]) or not is_equal_approx(float(line.get("sweetener_eur_bn", -1.0)), sweetener):
		_fail("%s: closed_last_month() says %s, not %s at %.5f" % [label, line, outcome, sweetener])


## closed_last_month()'s line for `row` now, {} when it says nothing of it.
func _said(state, ns, row: Dictionary) -> Dictionary:
	var out := {}
	for line in Closures.closed_last_month(state, ns):
		if String(line["id"]) == String(row["id"]):
			out = line
	return out


func _test_a_countered_search_on_a_failed_firm_is_said() -> void:
	var at: Array = _announced(2026)
	var row: Dictionary = at[3]
	Closures.answer(at[0], at[1], _loader, String(row["id"]), "negotiate_10")
	(at[1].companies[String(at[2].id)] as Dictionary)["failed"] = true
	_month(at[0])
	_check_said(at[0], at[1], row, at[2], "void", 0.0, "a failed firm's counter")


## QA on #285: the buyer came back, the firm fails in the re-ask's month: there is
## nothing left to sell, so the row is void and the state pays no old sweetener.
func _test_a_firm_that_fails_in_the_re_ask_sells_nothing() -> void:
	for k in 80:
		var at: Array = _announced(2026 + k)
		var row: Dictionary = at[3]
		var end := _now(at[0]) + CK.BUYER_MONTHS
		if Cycle.unit("closure|%s|buyer" % String(row["id"]), end) >= CK.BUYER_CHANCE:
			continue
		for answer_id in NEGOTIATE_IDS:
			var a := _answer_of(Closures.answers(at[0], at[1], _loader, String(row["id"])), answer_id)
			if Negotiation.draw(float(a["odds"]), Negotiation.key(row, answer_id), end) != "back":
				continue
			Closures.answer(at[0], at[1], _loader, String(row["id"]), answer_id)
			for i in range(CK.BUYER_MONTHS):
				_month(at[0])
			if String(row["status"]) != Closures.OFFERED:
				_fail("premise: the buyer did not come back: %s" % row["status"])
				return
			var debt := float(at[1].debt_eur_bn)
			(at[1].companies[String(at[2].id)] as Dictionary)["failed"] = true
			_month(at[0])
			if String(row["status"]) != "void" or float(at[1].debt_eur_bn) != debt:
				_fail("a firm that failed in the re-ask ended %s and paid %.5f" % [row["status"], float(at[1].debt_eur_bn) - debt])
			_check_said(at[0], at[1], row, at[2], "void", 0.0, "a failed firm's re-ask")
			return
	_fail("80 seeded closures drew no buyer that came back")


func _test_a_plain_buyer_is_not_said_as_a_counter() -> void:
	var at: Array = _announced(2026)
	var row: Dictionary = at[3]
	Closures.answer(at[0], at[1], _loader, String(row["id"]), "buyer")
	for i in range(CK.BUYER_MONTHS):
		_month(at[0])
		if not Closures.closed_last_month(at[0], at[1]).is_empty():
			_fail("a plain buyer's search is said as a counter: %s" % [Closures.closed_last_month(at[0], at[1])])


## No answer of the buyer's is beaten on every figure (PR 1's gate, pin 7): the buyer
## and its three counters, by their expected cash (the search and the sweetener a sale
## pays), the chance the plant is sold, the sweetener if it is, and the jobs kept. The
## buyer wins the completion, a counter the cash.
func _test_no_buyer_answer_is_dominated() -> void:
	var at: Array = _announced(2026)
	var answers: Array = Closures.answers(at[0], at[1], _loader, String((at[3] as Dictionary)["id"]))
	var jobs := float((at[3] as Dictionary)["jobs"])
	var figures := {}
	for a in answers:
		var chance := float(a.get("chance", 0.0))
		match String(a["kind"]):
			"buyer":
				var sw := float(a["sweetener_eur_bn"])
				figures[a["id"]] = [-(float(a["debt_eur_bn"]) + chance * sw), chance, -sw, chance * jobs]
			"negotiate":
				var p := float(a["odds"])
				var back := (1.0 - p) * (1.0 - float(a["walk"]))
				var sold := p + back
				var paid := p * float(a["sweetener_eur_bn"]) + back * float(a["back_sweetener_eur_bn"])
				figures[a["id"]] = [-(float(a["debt_eur_bn"]) + chance * paid), chance * sold, -paid / sold, chance * sold * jobs]
	if figures.size() != 4:
		_fail("the buyer's answers are %s" % [figures.keys()])
		return
	for x in figures:
		for y in figures:
			if x == y:
				continue
			var no_worse := true
			var better := false
			for i in 4:
				no_worse = no_worse and float(figures[x][i]) >= float(figures[y][i]) - 1e-12
				better = better or float(figures[x][i]) > float(figures[y][i]) + 1e-12
			if no_worse and better:
				_fail("%s %s beats %s %s on every figure" % [x, figures[x], y, figures[y]])


## A countered search and a buyer that came back survive a save: the loaded game
## draws and lands exactly as the one that never saved. No SAVE bump: the keys live in
## the firm's closure record, absent in every older save, which never held "offered".
func _test_a_countered_closure_survives_a_save() -> void:
	for answer_id in NEGOTIATE_IDS:
		for k in 80:
			var at: Array = _announced(2026 + k)
			var state = at[0]
			var row: Dictionary = at[3]
			var end := _now(state) + CK.BUYER_MONTHS
			var a := _answer_of(Closures.answers(state, at[1], _loader, String(row["id"])), answer_id)
			if Cycle.unit("closure|%s|buyer" % String(row["id"]), end) >= CK.BUYER_CHANCE \
					or Negotiation.draw(float(a["odds"]), Negotiation.key(row, answer_id), end) != "back":
				continue
			Closures.answer(state, at[1], _loader, String(row["id"]), answer_id)
			var searching = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
			for i in range(CK.BUYER_MONTHS):
				_month(state)
				_month(searching)
			var offered = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
			var firm_id := String(at[2].id)
			for kept in [searching, offered]:
				if not _same_closure(_row(kept.player(), firm_id), row):
					_fail("a countered closure resolved differently after a save: %s against %s" % [_row(kept.player(), firm_id), row])
			_month(state)
			_month(offered)
			if not _same_closure(_row(offered.player(), firm_id), row) \
					or not is_equal_approx(float(offered.player().debt_eur_bn), float(at[1].debt_eur_bn)):
				_fail("a buyer that came back landed differently after a save: %s against %s" % [_row(offered.player(), firm_id), row])
			return
	_fail("no seeded closure came back to test the save")


## Two closure records alike on what the counter decides: its status, the drawn
## answer and the months it is due (a save's floats are compared within precision).
func _same_closure(a: Dictionary, b: Dictionary) -> bool:
	var na: Dictionary = a.get("negotiation", {})
	var nb: Dictionary = b.get("negotiation", {})
	return String(a.get("status", "")) == String(b.get("status", "")) and int(a.get("due", -1)) == int(b.get("due", -1)) \
			and String(na.get("answer", "")) == String(nb.get("answer", "")) and String(na.get("outcome", "")) == String(nb.get("outcome", "")) \
			and int(na.get("month", -1)) == int(nb.get("month", -1)) \
			and is_equal_approx(float(a.get("sweetener_eur_bn", 0.0)), float(b.get("sweetener_eur_bn", 0.0)))

