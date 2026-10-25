extends SceneTree

## V5.2c Task 5. Lies: a lie on argue or a promise raises that attempt's odds; the
## listener's reading skill against the president's decides whether it is caught
## there and then; a lied promise the scene did not catch is revealed at its date,
## served or not. Caught or revealed, the price is b2's broken-promise price, paid
## once. The plan: .superpowers/sdd/v5.2c-plan.md, Task 5; the band: B8.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Characters = preload("res://src/sim/characters.gd")
const Levers = preload("res://src/sim/levers.gd")
const Lies = preload("res://src/sim/lies.gd")
const President = preload("res://src/sim/president.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const SC = preload("res://src/sim/shadow_constants.gd")

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
	_check_catch_band_high_reader()
	_check_catch_band_low_reader()
	_check_lie_raises_odds_by_exactly_LIE_ODDS()
	_check_caught_lie_priced_once()
	_check_a_caught_lie_fails_the_attempt()
	_check_uncaught_lie_leaves_nothing()
	_check_a_lied_promise_is_revealed_at_its_date_served_or_not()
	_check_a_caught_promise_is_withdrawn_and_priced_once()
	_check_the_phone_takes_no_lie()
	_check_the_card_shows_the_lie_variant()
	_finish()


func _state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	return state


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	state.day = 1


func _set_month(state, absolute: int) -> void:
	state.year = floori((absolute - 1) / 12.0)
	state.month = absolute - state.year * 12
	state.day = 1


## test_levers' path: the first request booked and opened on its day.
func _booked() -> Dictionary:
	var state = _state()
	var ns = state.player()
	for _m in range(24):
		Audiences.tick_month(state, _loader, METERS)
		var lane: Array[Dictionary] = Audiences.pending(ns)
		if lane.is_empty():
			_advance(state)
			continue
		var id := String(lane[0]["id"])
		_advance(state)
		for d in Audiences.offered_dates(state, ns, id):
			if bool(d["free"]) and bool(Audiences.book(state, ns, _loader, id, d).get("ok", false)):
				state.year = int(d["year"])
				state.month = int(d["month"])
				state.day = int(d["day"])
				var session: Dictionary = Levers.open(state, ns, _loader, id)
				if session.is_empty():
					break
				return {"state": state, "ns": ns, "pid": String(lane[0]["person_id"]), "session": session}
		break
	_failures.append("fixture: no audience could be booked and opened")
	return {}


## The listener and the president at the given reading skills, restored by the caller.
func _skills(b: Dictionary, listener: float, president: float) -> Array:
	var person = _loader.person_by_id[String(b["pid"])]
	var leader = _loader.person_by_id[President.leader_id(b["ns"])]
	var kept := [person.social_skill, leader.social_skill]
	person.social_skill = listener
	leader.social_skill = president
	return kept


func _restore(b: Dictionary, kept: Array) -> void:
	_loader.person_by_id[String(b["pid"])].social_skill = kept[0]
	_loader.person_by_id[President.leader_id(b["ns"])].social_skill = kept[1]


## B8, the first row: a reader above 0.67 against a middling president.
func _check_catch_band_high_reader() -> void:
	var p := Lies.catch_chance(0.8, 0.5)
	if p < 0.40 or p > 0.70:
		_failures.append("a 0.8 reader catches a 0.5 liar %.3f of the time, outside [0.40, 0.70]" % p)


## B8, the second row: a reader below 0.33.
func _check_catch_band_low_reader() -> void:
	var p := Lies.catch_chance(0.2, 0.5)
	if p < 0.05 or p > 0.20:
		_failures.append("a 0.2 reader catches a 0.5 liar %.3f of the time, outside [0.05, 0.20]" % p)


func _check_lie_raises_odds_by_exactly_LIE_ODDS() -> void:
	for lever in ["argue", "promise_date"]:
		if not is_equal_approx(Lies.odds_bonus(lever, {"lie": true}), SC.LIE_ODDS) or Lies.odds_bonus(lever, {}) != 0.0:
			_failures.append("a lie on %s does not add exactly LIE_ODDS" % lever)
	if Lies.odds_bonus("bargain", {"lie": true}) != 0.0 or Lies.odds_bonus("flatter", {"lie": true}) != 0.0:
		_failures.append("a lie raised the odds of a lever it is not told on")


## Caught: b2's reveal price, once -- rapport down LIE_RAPPORT, no evidence row.
func _check_caught_lie_priced_once() -> void:
	var b := _booked()
	if b.is_empty():
		return
	var kept := _skills(b, 1.0, 0.0)
	var ns = b["ns"]
	var pid := String(b["pid"])
	var tried := false
	for index in range(LK.ATTEMPTS):
		if String(b["session"]["won"]) != "":
			break
		var caught := Lies.caught(b["state"], ns, _loader, b["session"], "argue", index)
		var rapport := President.rapport(ns, pid)
		var r: Dictionary = Levers.attempt(b["state"], ns, _loader, b["session"], "argue", {"lie": true})
		if bool(r.get("caught", false)) != caught:
			_failures.append("the attempt's catch %s is not the roll's %s" % [r.get("caught", null), caught])
			break
		if caught:
			tried = true
			if not is_equal_approx(President.rapport(ns, pid) - rapport, maxf(-LK.LIE_RAPPORT, -1.0 - rapport)):
				_failures.append("a caught lie moved rapport by %.3f, not -LIE_RAPPORT once" % (President.rapport(ns, pid) - rapport))
			break
	_restore(b, kept)
	if not tried:
		_failures.append("fixture: three lies to a 1.0 reader were never caught")
	if not ns.exposure_evidence.is_empty():
		_failures.append("a lie left evidence (Call 4: the risk is the catch and the date)")


## #170's call 5 (Gameplay #171): a lie caught in the audience fails the attempt --
## the reveal is paid and the lever does not persuade. Over draw seeds, so some
## caught attempts carry a roll that would have won.
func _check_a_caught_lie_fails_the_attempt() -> void:
	var caught_tries := 0
	for draw in range(12):
		var b := _booked()
		if b.is_empty():
			return
		b["ns"].draw_seed = draw + 1
		# Known and liked, so the lie's own roll often wins: the catch must still sink it.
		President.learn(b["state"], b["ns"], _loader, String(b["pid"]), 1.0)
		President.adjust_rapport(b["state"], b["ns"], _loader, String(b["pid"]), 1.0)
		var kept := _skills(b, 1.0, 0.0)
		for index in range(LK.ATTEMPTS):
			if String(b["session"]["won"]) != "":
				break
			var r: Dictionary = Levers.attempt(b["state"], b["ns"], _loader, b["session"], "argue", {"lie": true})
			if bool(r.get("caught", false)):
				caught_tries += 1
				if bool(r["success"]) or String(b["session"]["won"]) != "":
					_failures.append("a caught lie persuaded (draw seed %d, attempt %d)" % [draw + 1, index])
		_restore(b, kept)
	if caught_tries == 0:
		_failures.append("fixture: no lie to a 1.0 reader was caught")


## Uncaught on argue: the odds were raised and nothing else happened.
func _check_uncaught_lie_leaves_nothing() -> void:
	var b := _booked()
	if b.is_empty():
		return
	var kept := _skills(b, 0.0, 1.0)
	var ns = b["ns"]
	var pid := String(b["pid"])
	if Lies.caught(b["state"], ns, _loader, b["session"], "argue", 0):
		_failures.append("fixture: a 0.0 reader caught a 1.0 liar on the first roll")
	else:
		var rapport := President.rapport(ns, pid)
		var knowledge := President.knowledge(ns, pid)
		var r: Dictionary = Levers.attempt(b["state"], ns, _loader, b["session"], "argue", {"lie": true})
		if bool(r.get("caught", true)) or President.rapport(ns, pid) != rapport or President.knowledge(ns, pid) != knowledge \
				or not ns.exposure_evidence.is_empty():
			_failures.append("an uncaught lie on argue cost something: %s" % [r])
	_restore(b, kept)


## B8's third row and B5's pricing: a lied promise is revealed at its date with no
## roll, even when the want happens to be served by then.
func _check_a_lied_promise_is_revealed_at_its_date_served_or_not() -> void:
	var state = _state()
	var ns = state.player()
	var leaders := {}
	for party in _loader.parties[PLAYER]:
		leaders[party.id] = party.leader_person_id
	var served := {}
	for person in _loader.people[PLAYER]:
		if person.id == President.leader_id(ns):
			continue
		for want in person.wants:
			if served.is_empty() and Characters.want_served(ns, person, want, METERS, leaders):
				served = {"id": String(person.id), "object": String(want["object"])}
	if served.is_empty():
		_failures.append("fixture: no France person has a served want")
		return
	var due := _now(state) + LK.PROMISE_MIN_MONTHS
	if not President.commit(state, ns, _loader, "promise", served["id"], served["object"], due, true):
		_failures.append("a lied promise was refused by the register")
		return
	var rapport := President.rapport(ns, served["id"])
	_set_month(state, due)
	var report: Dictionary = Levers.tick_month(state, _loader, METERS)
	if (report["broken"] as Array).size() != 1 or not (report["kept"] as Array).is_empty():
		_failures.append("a lied promise on a served want was judged %s" % [report])
	if not is_equal_approx(President.rapport(ns, served["id"]) - rapport, -LK.LIE_RAPPORT):
		_failures.append("a lied promise revealed at its date moved rapport by %.3f" % (President.rapport(ns, served["id"]) - rapport))


## Caught in the scene: priced now, and the promise is no promise -- its date
## prices nothing again.
func _check_a_caught_promise_is_withdrawn_and_priced_once() -> void:
	var b := _booked()
	if b.is_empty():
		return
	var kept := _skills(b, 1.0, 0.0)
	var ns = b["ns"]
	var pid := String(b["pid"])
	var due := _now(b["state"]) + LK.PROMISE_MIN_MONTHS
	var tried := false
	for index in range(LK.ATTEMPTS):
		if String(b["session"]["won"]) != "" or not Lies.caught(b["state"], ns, _loader, b["session"], "promise_date", index):
			Levers.attempt(b["state"], ns, _loader, b["session"], "argue", {})
			continue
		var rapport := President.rapport(ns, pid)
		var r: Dictionary = Levers.attempt(b["state"], ns, _loader, b["session"], "promise_date", {"lie": true, "due_month": due})
		tried = bool(r.get("caught", false))
		if not President.commitments_with(ns, pid).is_empty():
			_failures.append("a promise caught as a lie stayed on the register")
		var once := President.rapport(ns, pid) - rapport
		_set_month(b["state"], due)
		Levers.tick_month(b["state"], _loader, METERS)
		if not is_equal_approx(President.rapport(ns, pid) - rapport, once) or not is_equal_approx(once, maxf(-LK.LIE_RAPPORT, -1.0 - rapport)):
			_failures.append("a caught promise was priced %.3f now and %.3f by its date" % [once, President.rapport(ns, pid) - rapport])
		break
	_restore(b, kept)
	if not tried:
		_failures.append("fixture: no promise lie was caught by a 1.0 reader")


## The plan's Call 8: no lie down the phone.
func _check_the_phone_takes_no_lie() -> void:
	if Levers.arg_error("argue", {"lie": true}, 24312) == "" or Levers.arg_error("argue", {"lie": true}, 24312, true) != "" \
			or Levers.arg_error("bargain", {"lie": true}, 24312, true) == "":
		_failures.append("arg_error does not keep lies to argue and promise_date in the audience")


## The audience's argue and promise rows carry their lie variant at the raised odds;
## no other lever does.
func _check_the_card_shows_the_lie_variant() -> void:
	var b := _booked()
	if b.is_empty():
		return
	for row in Levers.offered(b["state"], b["ns"], _loader, b["session"]):
		var lever := String(row["lever"])
		var lie: Dictionary = row.get("lie", {})
		if not lie.is_empty() and float(lie["odds_hi"]) < float(row["odds_hi"]) - 1e-9:
			_failures.append("the %s row's lie variant is %s, below the honest odds" % [lever, lie])
		if SC.LIE_LEVERS.has(lever) and lie.is_empty():
			_failures.append("the %s row shows no lie variant" % lever)
		if not SC.LIE_LEVERS.has(lever) and not lie.is_empty():
			_failures.append("the %s row offers a lie" % lever)


func _finish() -> void:
	if _failures.is_empty():
		print("test_lies: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
