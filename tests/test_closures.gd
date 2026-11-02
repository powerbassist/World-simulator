extends SceneTree

## V5.3 a (docs/design/v5.3-ab.md 3.2, "New Industry decisions"): a plant closure
## announced. When a major's output has fallen by more than the rule's threshold
## over its window, the firm announces a closure in its live city, and the player
## answers: rescue it (the firm's own subsidy verbs), find a buyer (a search of
## CLOSURE_BUYER_MONTHS with a seeded chance), or let it close (the default: a cut
## of the firm's share, so of its jobs in its city, and the rule's bloc move). The
## rule's numbers are data (data/industry/closures.json), never per firm.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Companies = preload("res://src/sim/companies.gd")
const Closures = preload("res://src/sim/closures.gd")
const Processes = preload("res://src/sim/processes.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const CK = preload("res://src/sim/closures_constants.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_the_rule_is_data()
	_test_a_falling_major_announces_a_closure()
	_test_one_announcement_a_month_the_worst_first()
	_test_an_unanswered_closure_lands_by_default()
	_test_a_rescue_runs_the_firms_subsidy_verb()
	_test_a_buyer_search_resolves_on_its_seed()
	_test_a_closed_firm_does_not_announce_again_in_its_cooldown()
	_test_only_the_player_announces()
	_test_a_firm_in_a_process_does_not_announce()
	_test_answer_refusals()
	_test_a_closure_survives_a_save()
	_test_a_failed_firm_drops_its_history()
	_test_the_record_follows_a_relocation()
	_test_the_three_answers_each_win_somewhere()
	_test_the_buyer_pays_its_search_and_its_sweetener()
	_test_a_landed_closures_bloc_move_fades()
	_finish()


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


func _test_the_rule_is_data() -> void:
	var rule := _rule()
	for key in ["window_months", "fall", "cut", "cooldown_months", "bloc_offset"]:
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
	if not ids.has("close") or not ids.has("buyer") or ids.size() < 3:
		_fail("the closure offers %s, not close, buyer and a rescue verb" % [ids])
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
		if not is_equal_approx(float(ns.bloc_offset.get(bloc, 0.0)) - float(before[bloc]), float(offsets[bloc])):
			_fail("the landed closure did not move %s by the rule's offset" % bloc)
	if not Closures.open(ns).is_empty():
		_fail("a landed closure is still listed as open")


func _test_a_rescue_runs_the_firms_subsidy_verb() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _unsubsidised(ns)
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var row := _row(ns, String(firm.id))
	var rescue := ""
	for a in Closures.answers(state, ns, _loader, String(row["id"])):
		if String(a["kind"]) == "rescue":
			rescue = String(a["id"])
	if rescue == "":
		_fail("no rescue answer on an unsubsidised major")
		return
	var share := Companies.share_of_company(ns, firm)
	var r: Dictionary = Closures.answer(state, ns, _loader, String(row["id"]), rescue)
	if not bool(r.get("ok", false)) or String(row["status"]) != "rescued":
		_fail("the rescue did not close the closure rescued: %s %s" % [r, row])
	if Companies.subsidy_of(ns, String(firm.id)) <= 0.0:
		_fail("the rescue did not run the firm's subsidy verb")
	for i in range(CK.ANSWER_MONTHS):
		_month(state)
	if Companies.share_of_company(ns, firm) < share:
		_fail("a rescued plant closed anyway")


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


## Parent TAKE 1 on #251 (B5's no-dominated-pair rule): the three strips side by
## side. Money is the expected cost on the debt (the rescue's first year; the buyer's
## search plus its chance of the sweetener), jobs the expected jobs lost. No answer
## may be at least as good on both and better on one: close is the cheapest, the
## rescue the surest, the buyer between them.
func _test_the_three_answers_each_win_somewhere() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm = _unsubsidised(ns)
	_falling(ns, firm, 2.0 * float(_rule()["fall"]))
	_month(state)
	var row := _row(ns, String(firm.id))
	var strips := {}
	for a in Closures.answers(state, ns, _loader, String(row["id"])):
		var money := 0.0
		var jobs := float(a["jobs_lost"])
		match String(a["kind"]):
			"close":
				money = float(a["debt_eur_bn"])
			"buyer":
				money = float(a["debt_eur_bn"]) + float(a["chance"]) * float(a["sweetener_eur_bn"])
				jobs = (1.0 - float(a["chance"])) * jobs
			"rescue":
				money = float(a["debt_eur_bn_per_year"])
		if not strips.has(String(a["kind"])):
			strips[String(a["kind"])] = [money, jobs]
	if strips.size() != 3:
		_fail("the closure does not offer close, buyer and a rescue: %s" % [strips.keys()])
		return
	if float(strips["buyer"][0]) <= 0.0:
		_fail("finding a buyer is free (%s): it dominates letting the plant close" % [strips["buyer"]])
	for a in strips:
		for b in strips:
			if a == b:
				continue
			var x: Array = strips[a]
			var y: Array = strips[b]
			if x[0] <= y[0] and x[1] <= y[1] and (x[0] < y[0] or x[1] < y[1]):
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
