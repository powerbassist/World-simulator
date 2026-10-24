extends SceneTree

## Headless test: godot --headless --script res://tests/test_phone.gd
## Non-zero exit on any failure.
##
## V5.2b b3, the phone (src/sim/phone.gd; docs/audiences-model.md "The phone").
## What this file holds:
##
##   - ONE CALL PER PERSON PER MONTH, through a save: the scarcity a call has
##     instead of a diary day (the spec's phone table).
##   - THE SAME LEVER, LOWER ODDS (B5's channel row): every lever offered by phone
##     is exactly CALL_ODDS_PENALTY below the audience's, a lever too long a shot
##     for a call is not offered, and the printed range still holds the truth.
##   - A LEVER NEEDS AN ASK: the person's open request. A call that wins answers it
##     with no decline price and no knowledge (no hold); one that loses leaves it
##     open. A topic needs nothing and teaches the topic only.
##   - A refused call writes nothing and does not spend the month.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Phone = preload("res://src/sim/phone.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const Levers = preload("res://src/sim/levers.gd")
const President = preload("res://src/sim/president.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")

const PLAYER := "FRA"
const METERS := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_one_call_per_person_per_month()
	_check_a_lever_needs_an_open_request()
	_check_the_odds_sit_one_penalty_below_the_audience()
	_check_a_won_call_answers_the_request()
	_check_a_lost_call_leaves_the_request_open()
	_check_a_promise_by_phone_is_a_promise()
	_check_a_booked_request_won_by_phone_frees_its_day()
	_check_topics_teach_the_topic_only()
	_check_who_can_be_called()
	_check_twin_states_ring_alike()

	_finish()


## A topic call spends the person's month; a second call that month is refused
## and writes nothing; the next month the line is open again -- and the stamp
## survives a save as an int.
func _check_one_call_per_person_per_month() -> void:
	var state = _plain_game()
	var ns = state.player()
	var pid := _someone(ns)
	if not bool(Phone.dial(state, ns, _loader, pid, "opinion").get("ok", false)):
		_fail("a first call of the month was refused")
		return
	var before := _snapshot(ns, pid)
	var again: Dictionary = Phone.dial(state, ns, _loader, pid, "family")
	if bool(again.get("ok", true)) or String(again.get("error", "")) == "":
		_fail("a second call in one month was accepted: %s" % [again])
	if _snapshot(ns, pid) != before:
		_fail("a refused second call wrote a register")
	var shown: Dictionary = Phone.options(state, ns, _loader, pid)
	if String(shown.get("why_not", "")) == "":
		_fail("options() offers a second call this month")
	var loaded = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	if typeof(loaded.phone_calls.get(pid)) != TYPE_INT or int(loaded.phone_calls[pid]) != _now(state):
		_fail("the call's month came back from a save as %s" % [loaded.phone_calls.get(pid)])
	state.nations[PLAYER] = loaded
	if bool(Phone.dial(state, loaded, _loader, pid, "family").get("ok", true)):
		_fail("a loaded game forgot this month's call")
	_advance(state)
	if not bool(Phone.dial(state, loaded, _loader, pid, "family").get("ok", false)):
		_fail("the next month's call was refused")


## No open request, no ask: a lever by phone is refused, writes nothing, and the
## month stays unspent (a topic still goes through).
func _check_a_lever_needs_an_open_request() -> void:
	var state = _plain_game()
	var ns = state.player()
	var pid := _someone(ns)
	var before := _snapshot(ns, pid)
	var r: Dictionary = Phone.dial(state, ns, _loader, pid, "argue")
	if bool(r.get("ok", true)) or String(r.get("error", "")) == "":
		_fail("a lever by phone with no request was accepted: %s" % [r])
	if _snapshot(ns, pid) != before:
		_fail("a refused lever call wrote a register")
	for row in Phone.options(state, ns, _loader, pid).get("levers", []):
		if bool(row["offered"]):
			_fail("options() offers %s with no request open" % String(row["lever"]))
	if not bool(Phone.dial(state, ns, _loader, pid, "opinion").get("ok", false)):
		_fail("the refused lever spent the month: the topic call was refused")


## B5's channel row by construction: for every France person, knowledge band and
## lever, the phone's odds are the audience's minus CALL_ODDS_PENALTY where
## offered, and not offered where that would fall under ODDS_MIN; the printed
## range has the audience's width and holds the phone's truth.
func _check_the_odds_sit_one_penalty_below_the_audience() -> void:
	var state = _plain_game()
	var ns = state.player()
	var offered := 0
	var refused := 0
	for person in _loader.people[PLAYER]:
		if person.id == President.leader_id(ns):
			continue
		_ask(state, ns, person.id, "odds")
		for k in [0.0, 0.5, 1.0]:
			ns.person_knowledge[person.id] = k
			ns.person_bond[person.id] = "friend"
			var c := Levers.cell(state, ns, _loader, {"person_id": person.id, "object": "programme:none"})
			var rows: Array = Phone.options(state, ns, _loader, person.id).get("levers", [])
			for lever in LK.LEVERS:
				var audience := LeverOdds.odds(person, lever, c)
				var phone := Phone.odds(person, lever, c)
				var row := _row(rows, lever)
				if audience - LK.CALL_ODDS_PENALTY < LK.ODDS_MIN:
					refused += 1
					if phone != -1.0 or bool(row.get("offered", true)):
						_fail("%s by phone to %s at %.2f is offered at audience odds %.3f" % [lever, person.id, k, audience])
					continue
				offered += 1
				if absf(audience - phone - LK.CALL_ODDS_PENALTY) > 0.000001:
					_fail("%s by phone to %s: %.4f, not %.4f below %.4f" % [lever, person.id, phone, LK.CALL_ODDS_PENALTY, audience])
				var lo := float(row.get("odds_lo", -1.0))
				var hi := float(row.get("odds_hi", -1.0))
				if not bool(row.get("offered", false)) or phone < lo - 0.000001 or phone > hi + 0.000001 \
						or absf(hi - lo - LeverOdds.fog_width(k)) > 0.000001:
					_fail("%s by phone to %s at %.2f shows %s for true %.3f" % [lever, person.id, k, row, phone])
	if offered == 0 or refused == 0:
		_fail("the grid never exercised both sides of the floor (%d offered, %d refused)" % [offered, refused])
	if LK.CALL_ODDS_PENALTY < 0.10:
		_fail("CALL_ODDS_PENALTY %.2f is under B5's 0.10" % LK.CALL_ODDS_PENALTY)


## A call that works answers the request as an audience win does -- settled, the
## relief and the loyalty written, no decline price -- but teaches nothing: no
## hold, so no KNOW_AUDIENCE. The lever's own spend is paid (friendship's bond).
func _check_a_won_call_answers_the_request() -> void:
	var state = _plain_game()
	var ns = state.player()
	var pid := _someone(ns)
	for n in range(1, 30):
		ns.audience_requests.clear()
		var id := _ask(state, ns, pid, "win%d" % n)
		_warm(state, ns, pid)
		var k0 := President.knowledge(ns, pid)
		var g0 := 0.3
		ns.person_grudges[pid] = g0
		var l0 := float(ns.person_loyalty.get(pid, 0.0))
		var r: Dictionary = Phone.dial(state, ns, _loader, pid, "friendship")
		if not bool(r.get("ok", false)):
			_fail("a friendship call to a close friend was refused: %s" % [r])
			return
		if bool(r.get("success", false)):
			var row := Audiences.request(ns, id)
			if String(row["status"]) != AK.STATUS_SETTLED:
				_fail("a won call left the request '%s'" % String(row["status"]))
			if President.knowledge(ns, pid) != k0:
				_fail("a won call taught %.4f knowledge" % (President.knowledge(ns, pid) - k0))
			if float(ns.person_grudges[pid]) >= g0 or float(ns.person_loyalty.get(pid, 0.0)) <= l0:
				_fail("a won call did not relieve the grudge and raise loyalty (%.3f, %.3f)" % [float(ns.person_grudges[pid]), float(ns.person_loyalty.get(pid, 0.0))])
			if President.relationship(ns, pid) != "friend":
				_fail("friendship by phone did not spend the bond (%s)" % President.relationship(ns, pid))
			return
		_advance(state)
	_fail("a friendship call at 0.85 never worked in 29 months")


## A call that fails leaves the request open, writes no price for argue (which
## spends nothing), and spends the month.
func _check_a_lost_call_leaves_the_request_open() -> void:
	var state = _plain_game()
	var ns = state.player()
	var pid := _someone(ns)
	for n in range(1, 30):
		ns.audience_requests.clear()
		var id := _ask(state, ns, pid, "lose%d" % n)
		ns.person_knowledge[pid] = 0.5
		var before := _snapshot(ns, pid)
		var r: Dictionary = Phone.dial(state, ns, _loader, pid, "argue")
		if not bool(r.get("ok", false)):
			_fail("an argue call with a request open was refused: %s" % [r])
			return
		if not bool(r.get("success", true)):
			if String(Audiences.request(ns, id)["status"]) != AK.STATUS_PENDING:
				_fail("a lost call closed the request")
			var after := _snapshot(ns, pid)
			after["calls"] = before["calls"]
			if after != before:
				_fail("a lost argue call wrote a register")
			if not bool(Audiences.answers(state, ns, _loader, id)["decline"]["ok"]):
				_fail("after a lost call the request cannot be declined")
			return
		_advance(state)
	_fail("an argue call never failed in 29 months")


## A promise won by phone closes the request as promised and binds a commitment.
func _check_a_promise_by_phone_is_a_promise() -> void:
	var state = _plain_game()
	var ns = state.player()
	var pid := _someone(ns)
	for n in range(1, 30):
		ns.audience_requests.clear()
		var id := _ask(state, ns, pid, "promise%d" % n)
		_warm(state, ns, pid)
		var due := _now(state) + LK.PROMISE_MIN_MONTHS
		var r: Dictionary = Phone.dial(state, ns, _loader, pid, "promise_date", {"due_month": due})
		if not bool(r.get("ok", false)):
			_fail("a promise call was refused: %s" % [r])
			return
		if bool(r.get("success", false)):
			if String(Audiences.request(ns, id)["status"]) != AK.STATUS_PROMISED:
				_fail("a promise won by phone left the request '%s'" % String(Audiences.request(ns, id)["status"]))
			var bound := false
			for c in President.commitments_with(ns, pid):
				bound = bound or (String(c["kind"]) == "promise" and int(c["due_month"]) == due)
			if not bound:
				_fail("a promise won by phone bound no commitment")
			return
		_advance(state)
	_fail("a promise call never worked in 29 months")


## A booked request answered by phone gives its day back to the diary.
func _check_a_booked_request_won_by_phone_frees_its_day() -> void:
	var state = _plain_game()
	var ns = state.player()
	for m in range(24):
		Audiences.tick_month(state, _loader, METERS)
		var lane: Array[Dictionary] = Audiences.pending(ns)
		if lane.is_empty():
			_advance(state)
			continue
		var id := String(lane[0]["id"])
		var pid := String(lane[0]["person_id"])
		var booked := false
		for d in Audiences.offered_dates(state, ns, id):
			if bool(d["free"]) and bool(Audiences.book(state, ns, _loader, id, d).get("ok", false)):
				booked = true
				break
		if not booked:
			_fail("the first request had no free day")
			return
		_warm(state, ns, pid)
		for n in range(20):
			if bool(Phone.dial(state, ns, _loader, pid, "friendship").get("success", false)):
				if String(Audiences.request(ns, id)["status"]) != AK.STATUS_SETTLED:
					_fail("a booked request won by phone is '%s'" % String(Audiences.request(ns, id)["status"]))
				for e in Calendar.booked(state):
					if String(e.get("kind", "")) == CalendarK.KIND_AUDIENCE and String(e.get("action_id", "")) == id:
						_fail("a booked request won by phone kept its diary day")
				return
			ns.phone_calls.erase(pid)
			_warm(state, ns, pid)
		_fail("a friendship call on a booked request never worked")
		return
	_fail("no request arrived in 24 months")


## A topic by phone teaches the topic's amount and nothing more (no hold); dinner
## is not a phone topic; gossip teaches the third person only.
func _check_topics_teach_the_topic_only() -> void:
	var state = _plain_game()
	var ns = state.player()
	var pid := _someone(ns)
	var other := _someone(ns, [pid])
	ns.person_knowledge[pid] = 0.2
	var r: Dictionary = Phone.dial(state, ns, _loader, pid, "opinion")
	var want := LK.KNOW_TOPIC * (1.0 - 0.2)
	if not bool(r.get("ok", false)) or absf(President.knowledge(ns, pid) - 0.2 - want) > 0.000001 \
			or absf(President.rapport(ns, pid) - LK.RAPPORT_TOPIC) > 0.000001:
		_fail("an opinion call taught %.4f (not %.4f) and rapport %.4f" % [President.knowledge(ns, pid) - 0.2, want, President.rapport(ns, pid)])
	var third := _someone(ns, [pid, other])
	var k_other := President.knowledge(ns, other)
	var g: Dictionary = Phone.dial(state, ns, _loader, other, "gossip", {"about": third})
	if not bool(g.get("ok", false)) or President.knowledge(ns, other) != k_other or President.knowledge(ns, third) <= 0.0:
		_fail("gossip by phone: %s, knowledge of the caller %.3f -> %.3f, of the third %.3f" % [g, k_other, President.knowledge(ns, other), President.knowledge(ns, third)])
	var fourth := _someone(ns, [pid, other, third])
	for topic in ["dinner", "flirt"]:
		var before := _snapshot(ns, fourth)
		if bool(Phone.dial(state, ns, _loader, fourth, topic).get("ok", true)) or _snapshot(ns, fourth) != before:
			_fail("%s by phone was accepted or wrote a register" % topic)


## The line reaches whom the registers cover: this nation's people and a foreign
## head; never the president, never a foreign backbencher.
func _check_who_can_be_called() -> void:
	var state = _plain_game()
	var ns = state.player()
	var head := President.leader_id(state.nations["DEU"])
	if not bool(Phone.dial(state, ns, _loader, head, "family").get("ok", false)):
		_fail("a call to the German head (%s) was refused" % head)
	var backbencher := ""
	for person in _loader.people["DEU"]:
		if not President.covers(state, ns, _loader, person.id):
			backbencher = person.id
			break
	for pid in [President.leader_id(ns), backbencher, "nobody"]:
		var before: Dictionary = ns.phone_calls.duplicate()
		if bool(Phone.dial(state, ns, _loader, pid, "family").get("ok", true)) or ns.phone_calls != before:
			_fail("a call to '%s' was accepted or stamped" % pid)


## I1: two identical states, the same calls, the same outcomes and registers.
func _check_twin_states_ring_alike() -> void:
	var outcomes := []
	var registers := []
	for twin in range(2):
		var state = _plain_game()
		var ns = state.player()
		var seen := []
		for person in _loader.people[PLAYER]:
			if person.id == President.leader_id(ns):
				continue
			_ask(state, ns, person.id, "twin")
			seen.append(Phone.dial(state, ns, _loader, person.id, "pressure"))
		outcomes.append(seen)
		registers.append([ns.person_rapport.duplicate(), ns.person_grudges.duplicate(), ns.audience_requests.duplicate(true)])
	if outcomes[0] != outcomes[1] or registers[0] != registers[1]:
		_fail("two identical states rang differently")


# --- Helpers ------------------------------------------------------------------------

## A pending request staged straight into the lane: its id.
func _ask(state, ns, pid: String, tag: String) -> String:
	var row := {"id": "%s|%s" % [pid, tag], "person_id": pid, "object": "programme:none", "stance": "sponsor",
		"arrived_month": _now(state), "deadline_month": _now(state) + 2, "status": AK.STATUS_PENDING,
		"date": {}, "resolved_month": -1}
	ns.audience_requests.append(row)
	return String(row["id"])


## The president knows and likes the person, and they are close.
func _warm(state, ns, pid: String) -> void:
	President.learn(state, ns, _loader, pid, 1.0)
	President.adjust_rapport(state, ns, _loader, pid, 2.0)
	President.set_bond(state, ns, _loader, pid, "close")


## A France person who is not the president nor any of `not_ids`.
func _someone(ns, not_ids := []) -> String:
	for person in _loader.people[PLAYER]:
		if person.id != President.leader_id(ns) and not not_ids.has(person.id):
			return person.id
	return ""


func _plain_game():
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


func _row(rows: Array, lever: String) -> Dictionary:
	for r in rows:
		if String(r.get("lever", "")) == lever:
			return r
	return {}


func _snapshot(ns, pid: String) -> Dictionary:
	return {
		"knowledge": ns.person_knowledge.duplicate(),
		"rapport": ns.person_rapport.duplicate(),
		"bond": ns.person_bond.duplicate(),
		"grudge": float(ns.person_grudges.get(pid, 0.0)),
		"loyalty": float(ns.person_loyalty.get(pid, 0.0)),
		"commitments": ns.commitments.duplicate(true),
		"requests": ns.audience_requests.duplicate(true),
		"calls": ns.phone_calls.duplicate(),
	}


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_phone: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
