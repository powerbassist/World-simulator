extends SceneTree

## V5.2 c1c (docs/design/bands-v5.2.md "c1c"). Rule 1: a crossed accomplice is a broken
## word -- a person holding evidence on the sitting president, left before their
## request arrived (or before the commitment was made), pays the revealed lie's
## rapport and grudge on top of the refusal when the president does not serve them:
## a decline, a lapse, an audience settled as declined, a broken delegation or IOU.
## A delegation itself is not a crossing. Rule 2: a win bought in a corrupt currency
## buys the act, not the person -- no loyalty, no grudge relief.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Levers = preload("res://src/sim/levers.gd")
const President = preload("res://src/sim/president.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const LK = preload("res://src/sim/lever_constants.gd")

const PLAYER := "FRA"
const METERS := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_a_declined_accomplice_pays_a_broken_word()
	_check_only_evidence_from_before_the_request_counts()
	_check_the_affair_and_another_leader_do_not_count()
	_check_a_delegation_is_not_a_crossing()
	_check_a_lapse_is_a_crossing()
	_check_a_broken_delegation_to_an_accomplice_pays_on_top()
	_check_a_corrupt_win_buys_the_act_not_the_person()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("test_accomplice: OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	state.day = 1


## The first request of this nation's people to arrive, from a fresh game: the same
## request every call (the seeded lane), so two fixtures differ only in what a check
## writes on one of them.
func _pending() -> Dictionary:
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	var ns = state.player()
	for _m in range(24):
		Audiences.tick_month(state, _loader, METERS)
		for row in Audiences.pending(ns):
			if _loader.person_by_id.has(String(row["person_id"])) and not String(row["object"]).begins_with("measure:"):
				return {"state": state, "ns": ns, "id": String(row["id"]), "pid": String(row["person_id"]),
					"arrived": int(Audiences.request(ns, String(row["id"])).get("arrived_month", _now(state)))}
		_advance(state)
	_failures.append("fixture: no request arrived in 24 months")
	return {}


## An evidence row on `pid`, as President.leave_evidence writes one, stamped `month`.
func _evidence(f: Dictionary, month: int, kind := "favour", leader := "") -> void:
	f["ns"].exposure_evidence.append({"kind": kind, "person_id": f["pid"], "size": 1.0, "month": month,
		"leader_id": leader if leader != "" else President.leader_id(f["ns"])})


func _check_a_declined_accomplice_pays_a_broken_word() -> void:
	var plain := _pending()
	var held := _pending()
	if plain.is_empty() or held.is_empty() or plain["id"] != held["id"]:
		_failures.append("fixture: the two lanes differ, so this check measures nothing")
		return
	_evidence(held, int(held["arrived"]) - 1)
	var shown: Dictionary = Audiences.decline_price(held["ns"], _loader, held["id"])
	if not bool(shown.get("broken_word", false)):
		_failures.append("the card does not flag an accomplice's broken word")
	var base: Dictionary = Audiences.decline(plain["state"], plain["ns"], _loader, plain["id"])["price"]
	var paid: Dictionary = Audiences.decline(held["state"], held["ns"], _loader, held["id"])["price"]
	if not is_equal_approx(float(paid["rapport"]), float(base["rapport"]) - LK.LIE_RAPPORT):
		_failures.append("an accomplice's decline cost %f rapport, not the decline's %f less LIE_RAPPORT" % [paid["rapport"], base["rapport"]])
	if not (float(paid["grudge"]) > float(base["grudge"])):
		_failures.append("an accomplice's decline added no LIE_GRUDGE pulse (%f vs %f)" % [paid["grudge"], base["grudge"]])
	if not is_equal_approx(float(shown["rapport"]), float(paid["rapport"])) or not is_equal_approx(float(shown["grudge"]), float(paid["grudge"])):
		_failures.append("the card priced %s, the decline wrote %s" % [str(shown), str(paid)])


func _check_only_evidence_from_before_the_request_counts() -> void:
	var f := _pending()
	if f.is_empty():
		return
	_evidence(f, int(f["arrived"]))  # the same month: a deal that failed, not a betrayal
	if bool(Audiences.decline_price(f["ns"], _loader, f["id"]).get("broken_word", false)):
		_failures.append("evidence written in the request's own month made it a crossing")


func _check_the_affair_and_another_leader_do_not_count() -> void:
	var f := _pending()
	if f.is_empty():
		return
	_evidence(f, int(f["arrived"]) - 1, "affair")
	_evidence(f, int(f["arrived"]) - 1, "favour", "SOMEONE_ELSE")
	if bool(Audiences.decline_price(f["ns"], _loader, f["id"]).get("broken_word", false)):
		_failures.append("an affair, or another leader's evidence, made the decline a crossing")


func _check_a_delegation_is_not_a_crossing() -> void:
	var plain := _pending()
	var held := _pending()
	if plain.is_empty() or held.is_empty():
		return
	_evidence(held, int(held["arrived"]) - 1)
	var a: Dictionary = Audiences.delegate(plain["state"], plain["ns"], _loader, plain["id"])
	var b: Dictionary = Audiences.delegate(held["state"], held["ns"], _loader, held["id"])
	if not is_equal_approx(float(a["price"]["rapport"]), float(b["price"]["rapport"])) \
			or not is_equal_approx(float(a["price"]["grudge"]), float(b["price"]["grudge"])):
		_failures.append("delegating an accomplice's request paid a broken word: %s vs %s" % [str(b["price"]), str(a["price"])])


func _check_a_lapse_is_a_crossing() -> void:
	var plain := _pending()
	var held := _pending()
	if plain.is_empty() or held.is_empty():
		return
	_evidence(held, int(held["arrived"]) - 1)
	var deadline := int(Audiences.request(plain["ns"], plain["id"]).get("deadline_month", 0))
	for f in [plain, held]:
		while _now(f["state"]) < deadline:
			_advance(f["state"])
		Audiences.tick_month(f["state"], _loader, METERS)
	var a := President.rapport(plain["ns"], plain["pid"])
	var b := President.rapport(held["ns"], held["pid"])
	if String(Audiences.request(held["ns"], held["id"]).get("status", "")) != AK.STATUS_LAPSED:
		_failures.append("fixture: the request did not lapse, so this check measures nothing")
	elif not is_equal_approx(b, a - LK.LIE_RAPPORT):
		_failures.append("an accomplice's lapse left rapport %f, not %f" % [b, a - LK.LIE_RAPPORT])


## A delegated commitment broken at its date to someone whose evidence predates it
## pays the broken word on top of the IOU betrayal (GLM's finding 1, kept): otherwise
## "delegate and let it lapse" is the free way to cross an accomplice.
func _check_a_broken_delegation_to_an_accomplice_pays_on_top() -> void:
	var plain := _pending()
	var held := _pending()
	if plain.is_empty() or held.is_empty():
		return
	_evidence(held, int(held["arrived"]) - 1)
	var verdicts := []
	for f in [plain, held]:
		Audiences.delegate(f["state"], f["ns"], _loader, f["id"])
		var due := 0
		for row in President.commitments_with(f["ns"], f["pid"]):
			if String(row["kind"]) == "delegated":
				due = int(row["due_month"])
		while _now(f["state"]) < due:
			_advance(f["state"])
		var out: Dictionary = Levers.tick_month(f["state"], _loader, METERS)
		verdicts.append((out.get("broken", []) as Array).size())
	if verdicts != [1, 1]:
		_failures.append("fixture: the delegations were not both broken at their date (%s), so this check measures nothing" % str(verdicts))
		return
	var a := President.rapport(plain["ns"], plain["pid"])
	var b := President.rapport(held["ns"], held["pid"])
	if not is_equal_approx(b, a - LK.LIE_RAPPORT):
		_failures.append("a broken delegation to an accomplice left rapport %f, not %f" % [b, a - LK.LIE_RAPPORT])


func _check_a_corrupt_win_buys_the_act_not_the_person() -> void:
	var f := _pending()
	if f.is_empty():
		return
	var person = _loader.person_by_id[f["pid"]]
	var ns = f["ns"]
	var before := float(ns.person_loyalty.get(f["pid"], 0.0))
	var bought: Dictionary = Levers.outcome(f["state"], ns, _loader, person, "bargain", true, {"currency": LK.CURRENCY_BACKROOM})
	if not bought.is_empty() or float(ns.person_loyalty.get(f["pid"], 0.0)) != before:
		_failures.append("a backroom win bought loyalty or relief: %s" % str(bought))
	var won: Dictionary = Levers.outcome(f["state"], ns, _loader, person, "bargain", true, {"currency": LK.CURRENCY_FAVOUR})
	if not (float(won.get("loyalty", 0.0)) > 0.0):
		_failures.append("an honest bargain's win bought no loyalty: %s" % str(won))
