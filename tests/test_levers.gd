extends SceneTree

## Headless test: godot --headless --script res://tests/test_levers.gd
## Non-zero exit on any failure.
##
## V5.2b b2, the audience (src/sim/levers.gd, src/sim/lever_odds.gd;
## docs/audiences-model.md "The audience"). What this file holds:
##
##   - THE ODDS READ THE PERSON (the spec's lever table and dominance matrix): each
##     trait moves the lever it names, the right way, and nothing leaves [0.05, 0.95].
##   - THE FOG NARROWS AND NEVER LIES (B4): a stranger's range is at least 0.30
##     wide, a known person's at most 0.10, and the true odds are always inside.
##   - A HIDDEN TRAIT READS AS UNKNOWN, NEVER WRONG (the spec's fog call).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Person = preload("res://src/core/person.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const Levers = preload("res://src/sim/levers.gd")
const President = preload("res://src/sim/president.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Characters = preload("res://src/sim/characters.gd")

const PLAYER := "FRA"
const BANDS := [0.165, 0.5, 0.835]
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

	_check_odds_follow_the_traits()
	_check_the_fog_narrows_and_never_lies()
	_check_known_traits_never_lie()
	_check_open_holds_and_teaches()
	_check_offered_reads_the_registers()
	_check_three_attempts_then_no_more()
	_check_a_success_settles_without_the_decline_price()
	_check_failures_close_as_one_decline()
	_check_each_lever_pays_its_spend()
	_check_the_rolls_are_seeded()
	_check_a_stale_session_is_refused()
	_check_topics_teach_and_spend_an_attempt()
	_check_gossip_writes_only_the_third_person()
	_check_flirt_waits_for_the_shadows()

	_finish()


## Each trait the spec's table names moves its lever the way the table says, from
## one plain person in one plain cell.
func _check_odds_follow_the_traits() -> void:
	var cell := _cell()
	var plain = _person([], 0.5)
	if not LeverOdds.odds(_person(["stubborn"], 0.5), "argue", cell) < LeverOdds.odds(plain, "argue", cell):
		_fail("stubborn does not lower argue")
	if not LeverOdds.odds(plain, "argue", _cell({"aligned": false})) < LeverOdds.odds(plain, "argue", cell):
		_fail("an ask against a want does not lower argue")
	if not LeverOdds.odds(plain, "argue", _cell({"knowledge": 0.9})) > LeverOdds.odds(plain, "argue", _cell({"knowledge": 0.1})):
		_fail("knowledge does not raise argue")
	var bargain := LeverOdds.odds(plain, "bargain", cell)
	if not LeverOdds.odds(_person(["pragmatic"], 0.5), "bargain", cell) > bargain:
		_fail("pragmatic does not raise bargain")
	if not LeverOdds.odds(_person(["principled"], 0.5), "bargain", cell) < bargain:
		_fail("principled does not lower bargain")
	if not LeverOdds.odds(_person(["ambitious"], 0.5), "promise_date", cell) > LeverOdds.odds(plain, "promise_date", cell):
		_fail("ambitious does not raise a promise")
	if not LeverOdds.odds(_person([], 0.9), "promise_date", cell) < LeverOdds.odds(plain, "promise_date", cell):
		_fail("a skilled reader does not lower a promise")
	if not LeverOdds.odds(plain, "pressure", _cell({"standing": 0.2})) > LeverOdds.odds(plain, "pressure", _cell({"standing": 0.8})):
		_fail("pressure does not fall as standing rises")
	if not LeverOdds.odds(plain, "pressure", _cell({"approval": 70.0})) > LeverOdds.odds(plain, "pressure", _cell({"approval": 30.0})):
		_fail("pressure does not rise with the president's approval")
	if not LeverOdds.odds(_person(["networked"], 0.5), "pressure", cell) < LeverOdds.odds(plain, "pressure", cell):
		_fail("networked does not lower pressure")
	if not LeverOdds.odds(_person(["vain"], 0.5), "flatter", cell) > LeverOdds.odds(plain, "flatter", cell):
		_fail("vain does not raise flatter")
	if not LeverOdds.odds(_person([], 0.9), "flatter", cell) < LeverOdds.odds(_person([], 0.2), "flatter", cell):
		_fail("a skilled reader does not lower flatter")
	if LeverOdds.odds(plain, "friendship", cell) != -1.0:
		_fail("friendship is offered to an acquaintance")
	var friend := LeverOdds.odds(plain, "friendship", _cell({"relationship": "friend"}))
	if friend < 0.0 or not LeverOdds.odds(plain, "friendship", _cell({"relationship": "close"})) > friend:
		_fail("friendship is not offered to a friend, or is no stronger at close (%.3f)" % friend)
	if not LeverOdds.odds(plain, "argue", _cell({"rapport": 0.8})) > LeverOdds.odds(plain, "argue", _cell({"rapport": -0.8})):
		_fail("rapport does not raise the odds")
	var extremes := [
		_cell({"knowledge": 1.0, "rapport": 1.0, "relationship": "close", "standing": 0.0, "approval": 100.0}),
		_cell({"knowledge": 0.0, "rapport": -1.0, "aligned": false, "standing": 1.0, "approval": 0.0}),
	]
	for person in [plain, _person(["vain", "pragmatic", "ambitious"], 0.0), _person(["stubborn", "principled", "networked"], 1.0)]:
		for c in extremes:
			for lever in LK.LEVERS:
				var p := LeverOdds.odds(person, lever, c)
				if p != -1.0 and (p < LK.ODDS_MIN or p > LK.ODDS_MAX):
					_fail("%s's odds %.3f left [%.2f, %.2f]" % [lever, p, LK.ODDS_MIN, LK.ODDS_MAX])


## B4's widths at the band edges, and the range holds the truth for every France
## person, lever and band -- placed by a seeded offset, so not always centred.
func _check_the_fog_narrows_and_never_lies() -> void:
	if LeverOdds.fog_width(0.0) < 0.30 or LeverOdds.fog_width(0.32) < 0.30:
		_fail("a stranger's range is narrower than 0.30 (%.3f at 0, %.3f at 0.32)" % [LeverOdds.fog_width(0.0), LeverOdds.fog_width(0.32)])
	if LeverOdds.fog_width(0.67) > 0.10 or LeverOdds.fog_width(1.0) > 0.10:
		_fail("a known person's range is wider than 0.10 (%.3f at 0.67)" % LeverOdds.fog_width(0.67))
	var off_centre := 0
	var ranges := 0
	for person in _loader.people[PLAYER]:
		for k in BANDS:
			var c := _cell({"knowledge": k, "relationship": "friend", "standing": 0.5})
			for lever in LK.LEVERS:
				var p := LeverOdds.odds(person, lever, c)
				var r: Vector2 = LeverOdds.shown_range(person.id, lever, p, k)
				ranges += 1
				if p < r.x - 0.000001 or p > r.y + 0.000001:
					_fail("%s %s at %.3f: the true odds %.3f are outside [%.3f, %.3f]" % [person.id, lever, k, p, r.x, r.y])
					return
				if r.x < 0.0 or r.y > 1.0:
					_fail("%s %s: the range [%.3f, %.3f] leaves [0, 1]" % [person.id, lever, r.x, r.y])
					return
				var at := (p - r.x) / maxf(r.y - r.x, 0.000001)
				if at < 0.4 or at > 0.6:
					off_centre += 1
	if off_centre == 0:
		_fail("every one of %d ranges is centred on the truth: the fog says the answer" % ranges)


## A trait shows once the president knows the person well enough, and only a real
## one: nothing at 0, everything at "known", and the set only grows.
func _check_known_traits_never_lie() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	for person in _loader.people[PLAYER]:
		if person.id == President.leader_id(ns):
			continue
		var before: Array[String] = []
		for k in [0.0, 0.2, 0.4, 0.6, 0.67, 1.0]:
			ns.person_knowledge[person.id] = k
			var shown: Array[String] = LeverOdds.known_traits(ns, person)
			for t in shown:
				if not person.traits.has(t):
					_fail("%s shows a trait they do not have: %s" % [person.id, t])
			for t in before:
				if not shown.has(t):
					_fail("%s's trait %s disappeared as knowledge rose to %.2f" % [person.id, t, k])
			if k == 0.0 and not shown.is_empty():
				_fail("%s shows traits to a stranger: %s" % [person.id, shown])
			if k >= 0.67 and shown.size() != person.traits.size():
				_fail("%s at knowledge %.2f still hides traits (%s of %s)" % [person.id, k, shown, person.traits])
			before = shown


## The booked day comes and the scene opens: the request is held, the president
## learns the person a little, and the session has three attempts.
func _check_open_holds_and_teaches() -> void:
	var c := _booked()
	if c.is_empty():
		return
	var ns = c["ns"]
	var s: Dictionary = c["session"]
	var pid := String(s.get("person_id", ""))
	if String(Audiences.request(ns, String(c["id"]))["status"]) != AK.STATUS_HELD:
		_fail("opening an audience did not hold the request")
	if not President.knowledge(ns, pid) > float(c["k0"]):
		_fail("holding an audience taught the president nothing about %s" % pid)
	if int(s.get("attempts_left", 0)) != LK.ATTEMPTS:
		_fail("a session opened with %d attempts, not %d" % [int(s.get("attempts_left", 0)), LK.ATTEMPTS])
	if not Levers.open(c["state"], ns, _loader, String(c["id"])).is_empty():
		_fail("a held audience opened a second time")


## The shown levers read the registers: friendship waits for a friend, the fog is
## the knowledge band, and the truth sits inside every printed range.
func _check_offered_reads_the_registers() -> void:
	var c := _booked()
	if c.is_empty():
		return
	var state = c["state"]
	var ns = c["ns"]
	var s: Dictionary = c["session"]
	var pid := String(s["person_id"])
	var person = _loader.person_by_id[pid]
	if _row(Levers.offered(state, ns, _loader, s), "friendship").get("offered", true):
		_fail("friendship was offered to someone who is not a friend")
	President.set_bond(state, ns, _loader, pid, "friend")
	var shown: Array[Dictionary] = Levers.offered(state, ns, _loader, s)
	if shown.size() != LK.LEVERS.size() or not bool(_row(shown, "friendship").get("offered", false)):
		_fail("a friend was not offered friendship, or the list is not the six levers (%d)" % shown.size())
	var cell: Dictionary = Levers.cell(state, ns, _loader, s)
	for r in shown:
		if String(r["fog"]) != President.knowledge_band(ns, pid):
			_fail("%s's fog '%s' is not the knowledge band" % [r["lever"], r["fog"]])
		var p := LeverOdds.odds(person, String(r["lever"]), cell)
		if p >= 0.0 and (p < float(r["odds_lo"]) - 0.000001 or p > float(r["odds_hi"]) + 0.000001):
			_fail("%s's true odds %.3f are outside the shown [%.3f, %.3f]" % [r["lever"], p, r["odds_lo"], r["odds_hi"]])


## Three attempts an audience, shared by levers and topics; the fourth is refused
## and writes nothing.
func _check_three_attempts_then_no_more() -> void:
	var c := _booked()
	if c.is_empty():
		return
	var state = c["state"]
	var ns = c["ns"]
	var s: Dictionary = c["session"]
	for i in range(LK.ATTEMPTS):
		if not bool(Levers.talk(state, ns, _loader, s, "opinion").get("ok", false)):
			_fail("topic %d of %d was refused" % [i + 1, LK.ATTEMPTS])
			return
	var before := _snapshot(ns, String(s["person_id"]))
	if bool(Levers.attempt(state, ns, _loader, s, "argue").get("ok", true)) or bool(Levers.talk(state, ns, _loader, s, "family").get("ok", true)):
		_fail("a fourth attempt was accepted")
	if _snapshot(ns, String(s["person_id"])) != before:
		_fail("a refused fourth attempt wrote the registers")


## A lever that works settles the request with no decline price, and buys loyalty
## and a grudge's relief; friendship spends a step of the bond.
func _check_a_success_settles_without_the_decline_price() -> void:
	var c := _booked()
	if c.is_empty():
		return
	var state = c["state"]
	var ns = c["ns"]
	var s: Dictionary = c["session"]
	var pid := String(s["person_id"])
	President.learn(state, ns, _loader, pid, 1.0)
	President.adjust_rapport(state, ns, _loader, pid, 1.0)
	President.set_bond(state, ns, _loader, pid, "close")
	ns.person_grudges[pid] = 0.3
	var loyalty0 := float(ns.person_loyalty.get(pid, 0.0))
	var r: Dictionary = Levers.attempt(state, ns, _loader, s, "friendship")
	if not bool(r.get("ok", false)) or not bool(r.get("success", false)):
		_fail("friendship at odds %.2f with a close friend did not work: %s" % [LK.ODDS_MAX, r])
		return
	if absf(float(ns.person_loyalty[pid]) - loyalty0 - LK.LOYALTY_ACCEPT) > 0.000001:
		_fail("a success moved loyalty by %.4f, not %.4f" % [float(ns.person_loyalty[pid]) - loyalty0, LK.LOYALTY_ACCEPT])
	if absf(float(ns.person_grudges[pid]) - (0.3 - LK.GRUDGE_ACCEPT_RELIEF)) > 0.000001:
		_fail("a success left the grudge at %.4f" % float(ns.person_grudges[pid]))
	if President.relationship(ns, pid) != "friend":
		_fail("an appeal to a close friend left the bond at '%s', not friend" % President.relationship(ns, pid))
	if bool(Levers.attempt(state, ns, _loader, s, "argue").get("ok", true)):
		_fail("a lever was tried after the person had already agreed")
	var grudge := float(ns.person_grudges[pid])
	var closed: Dictionary = Levers.close(state, ns, _loader, s)
	if String(closed.get("outcome", "")) != AK.STATUS_SETTLED or String(Audiences.request(ns, String(c["id"]))["status"]) != AK.STATUS_SETTLED:
		_fail("a won audience closed as '%s'" % closed.get("outcome", ""))
	if float(ns.person_grudges[pid]) != grudge:
		_fail("closing a won audience priced a decline")


## No lever works: closing is ONE decline, priced as Audiences prices it, and a
## second close is refused and writes nothing.
func _check_failures_close_as_one_decline() -> void:
	var c := _booked()
	if c.is_empty():
		return
	var state = c["state"]
	var ns = c["ns"]
	var s: Dictionary = c["session"]
	var pid := String(s["person_id"])
	President.adjust_rapport(state, ns, _loader, pid, -1.0)
	var person = _loader.person_by_id[pid]
	var cell: Dictionary = Levers.cell(state, ns, _loader, s)
	var weakest := "argue"
	for lever in ["bargain", "pressure", "flatter"]:
		var p := LeverOdds.odds(person, lever, cell)
		if p < LeverOdds.odds(person, weakest, cell):
			weakest = lever
	for i in range(LK.ATTEMPTS):
		var r: Dictionary = Levers.attempt(state, ns, _loader, s, weakest, {"currency": "favour"})
		if bool(r.get("success", false)):
			_fail("%s at odds %.2f worked on attempt %d; the seed needs another case" % [weakest, LeverOdds.odds(person, weakest, cell), i + 1])
			return
	var expected := float(Audiences.decline_price(ns, _loader, String(c["id"]))["grudge"])
	var grudge0 := float(ns.person_grudges.get(pid, 0.0))
	var closed: Dictionary = Levers.close(state, ns, _loader, s)
	if String(closed.get("outcome", "")) != AK.STATUS_DECLINED:
		_fail("an audience with no success closed as '%s'" % closed.get("outcome", ""))
	if absf(float(ns.person_grudges.get(pid, 0.0)) - grudge0 - expected) > 0.000000001:
		_fail("the failed audience cost %.4f of grudge, the decline price is %.4f" % [float(ns.person_grudges.get(pid, 0.0)) - grudge0, expected])
	var before := _snapshot(ns, pid)
	if bool(Levers.close(state, ns, _loader, s).get("ok", true)) or _snapshot(ns, pid) != before:
		_fail("a closed audience closed again, or the second close wrote the registers")


## Each lever's own spend, paid win or lose (the spec's levers table).
func _check_each_lever_pays_its_spend() -> void:
	var c := _booked()
	if c.is_empty():
		return
	var state = c["state"]
	var ns = c["ns"]
	var pid := String(c["session"]["person_id"])
	var r0 := President.rapport(ns, pid)
	Levers.attempt(state, ns, _loader, c["session"], "bargain", {"currency": "favour"})
	if absf(President.rapport(ns, pid) - r0 + LK.BARGAIN_FAVOUR_RAPPORT) > 0.000001:
		_fail("a favour moved rapport by %.4f, not -%.2f" % [President.rapport(ns, pid) - r0, LK.BARGAIN_FAVOUR_RAPPORT])
	c = _booked()
	state = c["state"]
	ns = c["ns"]
	pid = String(c["session"]["person_id"])
	var before := _snapshot(ns, pid)
	if bool(Levers.attempt(state, ns, _loader, c["session"], "bargain", {"currency": "aid"}).get("ok", true)) or _snapshot(ns, pid) != before:
		_fail("aid was accepted, or its refusal wrote the registers")
	Levers.attempt(state, ns, _loader, c["session"], "bargain", {"currency": "vote_trade"})
	if _count(ns, pid, "iou") != 1:
		_fail("a vote trade left %d IOUs, not 1" % _count(ns, pid, "iou"))
	c = _booked()
	state = c["state"]
	ns = c["ns"]
	pid = String(c["session"]["person_id"])
	before = _snapshot(ns, pid)
	var now := int(state.year) * 12 + int(state.month)
	for bad in [now, now + LK.PROMISE_MIN_MONTHS - 1, now + LK.PROMISE_MAX_MONTHS + 1, -1]:
		if bool(Levers.attempt(state, ns, _loader, c["session"], "promise_date", {"due_month": bad}).get("ok", true)):
			_fail("a promise due at month %d (now %d) was accepted" % [bad, now])
	if _snapshot(ns, pid) != before:
		_fail("refused promises wrote the registers")
	Levers.attempt(state, ns, _loader, c["session"], "promise_date", {"due_month": now + LK.PROMISE_MIN_MONTHS})
	var rows: Array[Dictionary] = President.commitments_with(ns, pid)
	if rows.size() != 1 or rows[0]["kind"] != "promise" or int(rows[0]["due_month"]) != now + LK.PROMISE_MIN_MONTHS:
		_fail("a promise left %s" % [rows])
	c = _booked()
	state = c["state"]
	ns = c["ns"]
	pid = String(c["session"]["person_id"])
	r0 = President.rapport(ns, pid)
	var g0 := float(ns.person_grudges.get(pid, 0.0))
	var pressed: Dictionary = Levers.attempt(state, ns, _loader, c["session"], "pressure")
	var relief := LK.GRUDGE_ACCEPT_RELIEF if bool(pressed.get("success", false)) else 0.0
	var person = _loader.person_by_id[pid]
	var pulse := LK.PRESSURE_GRUDGE * Characters.grudge_intake(person)
	if absf(President.rapport(ns, pid) - r0 + LK.PRESSURE_RAPPORT) > 0.000001:
		_fail("pressure moved rapport by %.4f" % (President.rapport(ns, pid) - r0))
	if absf(float(ns.person_grudges.get(pid, 0.0)) - maxf(0.0, g0 + pulse - relief)) > 0.000001:
		_fail("pressure left the grudge at %.4f (pulse %.4f, relief %.4f)" % [float(ns.person_grudges.get(pid, 0.0)), pulse, relief])


## Two identical states, the same three attempts: the same rolls and the same
## printed ranges (I1).
func _check_the_rolls_are_seeded() -> void:
	var a := _booked()
	var b := _booked()
	if a.is_empty() or b.is_empty():
		return
	if Levers.offered(a["state"], a["ns"], _loader, a["session"]) != Levers.offered(b["state"], b["ns"], _loader, b["session"]):
		_fail("two identical states showed different ranges")
	var ra: Array = []
	var rb: Array = []
	for lever in ["argue", "pressure", "flatter"]:
		ra.append(Levers.attempt(a["state"], a["ns"], _loader, a["session"], lever).get("success", null))
		rb.append(Levers.attempt(b["state"], b["ns"], _loader, b["session"], lever).get("success", null))
	if ra != rb:
		_fail("two identical states rolled differently: %s vs %s" % [ra, rb])


## A session handed back after its audience ended -- closed, or lapsed as a
## no-show -- is refused everywhere and writes nothing.
func _check_a_stale_session_is_refused() -> void:
	var c := _booked()
	if c.is_empty():
		return
	var state = c["state"]
	var ns = c["ns"]
	var s: Dictionary = c["session"]
	var pid := String(s["person_id"])
	Levers.close(state, ns, _loader, s)
	_expect_refused(state, ns, s, pid, "after close")
	c = _booked()
	state = c["state"]
	ns = c["ns"]
	s = c["session"]
	pid = String(s["person_id"])
	_advance(state)
	Audiences.tick_month(state, _loader, METERS)
	if String(Audiences.request(ns, String(c["id"]))["status"]) == AK.STATUS_HELD:
		_fail("an audience held across a month boundary was not closed as a no-show")
	_expect_refused(state, ns, s, pid, "after a no-show")


## A topic spends an attempt and buys knowledge and rapport; dinner is once.
func _check_topics_teach_and_spend_an_attempt() -> void:
	var c := _booked()
	if c.is_empty():
		return
	var state = c["state"]
	var ns = c["ns"]
	var s: Dictionary = c["session"]
	var pid := String(s["person_id"])
	var k0 := President.knowledge(ns, pid)
	var r0 := President.rapport(ns, pid)
	var r: Dictionary = Levers.talk(state, ns, _loader, s, "opinion")
	if not bool(r.get("ok", false)) or int(s["attempts_left"]) != LK.ATTEMPTS - 1:
		_fail("an opinion topic was refused or did not spend an attempt: %s" % [r])
	if absf(President.knowledge(ns, pid) - k0 - LK.KNOW_TOPIC * (1.0 - k0)) > 0.000001:
		_fail("a topic taught %.4f, not %.4f" % [President.knowledge(ns, pid) - k0, LK.KNOW_TOPIC * (1.0 - k0)])
	if absf(President.rapport(ns, pid) - r0 - LK.RAPPORT_TOPIC) > 0.000001:
		_fail("a topic moved rapport by %.4f, not %.4f" % [President.rapport(ns, pid) - r0, LK.RAPPORT_TOPIC])
	if not bool(Levers.talk(state, ns, _loader, s, "dinner").get("ok", false)):
		_fail("a first dinner was refused")
	if bool(Levers.talk(state, ns, _loader, s, "dinner").get("ok", true)):
		_fail("a second dinner in one audience was accepted")


## Gossip writes the president's knowledge of the third person and nothing else:
## every edge starts at the president (spec C1).
func _check_gossip_writes_only_the_third_person() -> void:
	var c := _booked()
	if c.is_empty():
		return
	var state = c["state"]
	var ns = c["ns"]
	var s: Dictionary = c["session"]
	var pid := String(s["person_id"])
	var about := ""
	for person in _loader.people[PLAYER]:
		if person.id != pid and person.id != President.leader_id(ns):
			about = person.id
			break
	var before := _snapshot(ns, pid)
	for bad in [{}, {"about": pid}, {"about": President.leader_id(ns)}, {"about": "DEU_nobody_at_all"}]:
		if bool(Levers.talk(state, ns, _loader, s, "gossip", bad).get("ok", true)):
			_fail("gossip with %s was accepted" % [bad])
	if _snapshot(ns, pid) != before or int(s["attempts_left"]) != LK.ATTEMPTS:
		_fail("refused gossip wrote a register or spent an attempt")
	var k_room := President.knowledge(ns, pid)
	var k_about := President.knowledge(ns, about)
	Levers.talk(state, ns, _loader, s, "gossip", {"about": about})
	if absf(President.knowledge(ns, about) - k_about - LK.KNOW_GOSSIP * (1.0 - k_about)) > 0.000001:
		_fail("gossip about %s taught %.4f" % [about, President.knowledge(ns, about) - k_about])
	if President.knowledge(ns, pid) != k_room:
		_fail("gossip taught the president about the person telling it")
	for key in ns.person_knowledge:
		if not _loader.person_by_id.has(key):
			_fail("a knowledge register is keyed by '%s', not a person" % key)


func _check_flirt_waits_for_the_shadows() -> void:
	var c := _booked()
	if c.is_empty():
		return
	if bool(_row(Levers.topics(c["state"], c["ns"], _loader, c["session"]), "flirt", "topic").get("offered", true)):
		_fail("flirting was offered before V5.2c")
	if bool(Levers.talk(c["state"], c["ns"], _loader, c["session"], "flirt").get("ok", true)):
		_fail("a flirt was accepted before V5.2c")


func _expect_refused(state, ns, s: Dictionary, pid: String, when: String) -> void:
	var before := _snapshot(ns, pid)
	if bool(Levers.attempt(state, ns, _loader, s, "argue").get("ok", true)):
		_fail("an attempt was accepted %s" % when)
	if bool(Levers.talk(state, ns, _loader, s, "opinion").get("ok", true)):
		_fail("a topic was accepted %s" % when)
	if bool(Levers.close(state, ns, _loader, s).get("ok", true)):
		_fail("a close was accepted %s" % when)
	if _snapshot(ns, pid) != before:
		_fail("a refused session wrote the registers %s" % when)


## A France game with its first request booked on an offered free day and the
## scene opened on that day: {state, ns, id, k0, session}, or {} with a failure.
func _booked() -> Dictionary:
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	var ns = state.player()
	for m in range(24):
		Audiences.tick_month(state, _loader, METERS)
		var lane: Array[Dictionary] = Audiences.pending(ns)
		if not lane.is_empty():
			var id := String(lane[0]["id"])
			_advance(state)
			for d in Audiences.offered_dates(state, ns, id):
				if bool(d["free"]) and bool(Audiences.book(state, ns, _loader, id, d).get("ok", false)):
					state.year = int(d["year"])
					state.month = int(d["month"])
					state.day = int(d["day"])
					var pid := String(lane[0]["person_id"])
					var k0 := President.knowledge(ns, pid)
					var session: Dictionary = Levers.open(state, ns, _loader, id)
					if session.is_empty():
						_fail("a booked audience on its day did not open")
						return {}
					return {"state": state, "ns": ns, "id": id, "k0": k0, "session": session}
			_fail("the first request had no free offered day in an empty diary")
			return {}
		_advance(state)
	_fail("no request arrived in 24 months")
	return {}


func _row(rows: Array, key: String, field := "lever") -> Dictionary:
	for r in rows:
		if String(r.get(field, "")) == key:
			return r
	return {}


func _count(ns, pid: String, kind: String) -> int:
	var n := 0
	for row in President.commitments_with(ns, pid):
		if String(row["kind"]) == kind:
			n += 1
	return n


func _snapshot(ns, pid: String) -> Dictionary:
	return {
		"knowledge": ns.person_knowledge.duplicate(),
		"rapport": ns.person_rapport.duplicate(),
		"bond": ns.person_bond.duplicate(),
		"grudge": float(ns.person_grudges.get(pid, 0.0)),
		"loyalty": float(ns.person_loyalty.get(pid, 0.0)),
		"commitments": ns.commitments.duplicate(true),
		"requests": ns.audience_requests.duplicate(true),
	}


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	state.day = 1


func _cell(over := {}) -> Dictionary:
	var c := {"knowledge": 0.5, "rapport": 0.0, "relationship": "acquaintance", "aligned": true, "standing": 0.5, "approval": 50.0}
	c.merge(over, true)
	return c


func _person(traits: Array, skill: float):
	var p = Person.new()
	p.id = "TST_person"
	var t: Array[String] = []
	for x in traits:
		t.append(String(x))
	p.traits = t
	p.social_skill = skill
	return p


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_levers: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
