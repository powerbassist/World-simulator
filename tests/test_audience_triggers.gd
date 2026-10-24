extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_triggers.gd
## Non-zero exit on any failure.
##
## V5.2b b3, the meetings and the asks outside the hazard (src/sim/meetings.gd,
## src/sim/audience_triggers.gd; docs/audiences-model.md "The meetings" and "The
## triggers"). What this file holds:
##
##   - A MEETING TEACHES THE HEAD MET, ONCE: a state visit either way, or a summit,
##     stamps GameState.met_months; the month after, the president knows and likes
##     the other nation's head a little more. Any other stamp teaches nothing.
##   - AN OFFICE WANT ASKS AT A RESHUFFLE (the pre-mortem's third trigger): the
##     player's Cabinet.assign() that hands a portfolio to another party stamps the
##     month and the portfolio -- never a no-op assign, never a government's seating;
##     the month after, whoever wanted THAT portfolio and did not get it asks,
##     outside the hazard and under the lane's rules.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const RK = preload("res://src/core/relations.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Meetings = preload("res://src/sim/meetings.gd")
const President = preload("res://src/sim/president.gd")
const K = preload("res://src/sim/audience_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudienceTriggers = preload("res://src/sim/audience_triggers.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Characters = preload("res://src/sim/characters.gd")

const METERS := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_a_meeting_last_month_teaches_the_head()
	_check_other_stamps_teach_nothing()
	_check_the_month_runs_the_meetings()
	_check_only_the_players_reshuffle_is_stamped()
	_check_an_office_want_asks_after_a_reshuffle()
	_check_a_served_office_want_does_not_ask()

	_finish()


## A pair stamped in the month that just ended: the other nation's head is met --
## knowledge on the audience's curve, the meeting's rapport -- and named; the month
## after, the same stamp teaches nothing more.
func _check_a_meeting_last_month_teaches_the_head() -> void:
	var state = _game()
	var ns = state.player()
	var head := President.leader_id(state.nations["DEU"])
	state.met_months[RK.key(PLAYER, "DEU")] = _now(state) - 1
	var met: Array[String] = Meetings.tick_month(state, _loader)
	if met != [head]:
		_fail("the meeting named %s, not [%s]" % [met, head])
	if absf(President.knowledge(ns, head) - K.KNOW_MEETING) > 0.000001 or absf(President.rapport(ns, head) - K.RAPPORT_MEETING) > 0.000001:
		_fail("meeting %s taught knowledge %.4f and rapport %.4f" % [head, President.knowledge(ns, head), President.rapport(ns, head)])
	_advance(state)
	var k := President.knowledge(ns, head)
	if not Meetings.tick_month(state, _loader).is_empty() or President.knowledge(ns, head) != k:
		_fail("a meeting two months old taught again")


## A stamp this month (the tick's own, read next month), one two months old, and a
## pair the player is not in teach nobody; an older save's history of stamps
## teaches nothing beyond the month that just ended.
func _check_other_stamps_teach_nothing() -> void:
	var state = _game()
	var ns = state.player()
	var now := _now(state)
	state.met_months[RK.key(PLAYER, "DEU")] = now
	state.met_months[RK.key(PLAYER, "ITA")] = now - 2
	state.met_months[RK.key(PLAYER, "ESP")] = now - 30
	state.met_months[RK.key("DEU", "ITA")] = now - 1
	var knowledge: Dictionary = ns.person_knowledge.duplicate()
	var rapport: Dictionary = ns.person_rapport.duplicate()
	if not Meetings.tick_month(state, _loader).is_empty():
		_fail("a stamp outside the month that just ended taught someone")
	if ns.person_knowledge != knowledge or ns.person_rapport != rapport:
		_fail("a stamp outside the month that just ended wrote a register")


## Through the game's own month: a visit stamped last month is met in this month's
## Audiences step, and the report names the head.
func _check_the_month_runs_the_meetings() -> void:
	var state = _game()
	var head := President.leader_id(state.nations["ITA"])
	state.met_months[RK.key(PLAYER, "ITA")] = _now(state) - 1
	var report: Dictionary = WorldMonth.tick_month(state, _loader)
	if not (report.get("meetings", []) as Array).has(head):
		_fail("the month's report names %s as met, not %s" % [report.get("meetings", []), head])
	if President.knowledge(state.player(), head) <= 0.0:
		_fail("the month met %s and taught nothing" % head)


## Cabinet.assign() -- the player's reshuffle -- stamps the month; a government
## seated by an election or a formation (Cabinet.seat) does not.
func _check_only_the_players_reshuffle_is_stamped() -> void:
	var state = _game()
	var ns = state.player()
	if int(ns.reshuffle_month) != -1:
		_fail("a new game reads a reshuffle at %d" % int(ns.reshuffle_month))
	var party_list: Array = _loader.parties[PLAYER]
	Cabinet.seat(ns, party_list)
	if int(ns.reshuffle_month) != -1:
		_fail("seating a government stamped a reshuffle")
	var portfolio := ""
	for f in ns.cabinet:
		if String(ns.cabinet[f]) != "":
			portfolio = f
			break
	var other := ""
	for pid in ns.coalition_party_ids:
		if pid != String(ns.cabinet[portfolio]):
			other = pid
	if portfolio == "" or other == "":
		_fail("France's cabinet has no portfolio to hand to a second coalition party")
		return
	Cabinet.assign(state, portfolio, String(ns.cabinet[portfolio]), party_list)
	if int(ns.reshuffle_month) != -1:
		_fail("handing a portfolio to the party that holds it stamped a reshuffle")
	Cabinet.assign(state, portfolio, other, party_list)
	if int(ns.reshuffle_month) != _now(state) or String(ns.reshuffle_portfolio) != portfolio:
		_fail("a reshuffle stamped %d / '%s', not %d / '%s'" % [int(ns.reshuffle_month), ns.reshuffle_portfolio, _now(state), portfolio])


## The month after a reshuffle of a portfolio, whoever wanted it unserved is
## invited -- and arrives in the lane through the month -- while a stamp from this
## month or two months ago, a reshuffle of another portfolio, and a premiership
## want (a portfolio reshuffle never moves the premiership) invite nobody.
func _check_an_office_want_asks_after_a_reshuffle() -> void:
	var state = _game()
	var ns = state.player()
	var asker := _office_wanter(ns, false)
	if asker.is_empty():
		_fail("no France person has an unserved portfolio want to stage the reshuffle")
		return
	var key := String(asker["object"]).substr("office:portfolio:".length())
	var now := _now(state)
	ns.reshuffle_portfolio = key
	for stamp in [now, now - 2]:
		ns.reshuffle_month = stamp
		if _invited(state, ns).has(asker["id"]):
			_fail("a reshuffle stamped %d invited %s at %d" % [stamp, asker["id"], now])
	ns.reshuffle_month = now - 1
	ns.reshuffle_portfolio = "no_such_portfolio"
	if _invited(state, ns).has(asker["id"]):
		_fail("a reshuffle of another portfolio invited %s" % asker["id"])
	ns.reshuffle_portfolio = key
	var invited := _invited(state, ns)
	if String(invited.get(asker["id"], "")) != asker["object"]:
		_fail("the reshuffle did not invite %s about %s (%s)" % [asker["id"], asker["object"], invited])
	for pid in invited:
		if String(invited[pid]) == "office:premiership":
			_fail("a portfolio reshuffle invited %s about the premiership" % pid)
	var report: Dictionary = Audiences.tick_month(state, _loader, METERS)
	var arrived := false
	for row in report["arrived"]:
		arrived = arrived or (String(row["person_id"]) == asker["id"] and String(row["object"]) == asker["object"])
	if not arrived:
		_fail("the invited %s did not reach the lane: %s" % [asker["id"], report["arrived"]])


## A person whose party already holds the portfolio they want is not invited.
func _check_a_served_office_want_does_not_ask() -> void:
	var state = _game()
	var ns = state.player()
	var person = _loader.person_by_id.get("FRA_vasseur")
	if person == null:
		_fail("FRA_vasseur (an office want for pensions) is not in the content")
		return
	ns.cabinet["pensions"] = String(person.party_id)
	ns.reshuffle_month = _now(state) - 1
	ns.reshuffle_portfolio = "pensions"
	if _invited(state, ns).has(person.id):
		_fail("a served portfolio want was invited")


# --- Helpers ------------------------------------------------------------------------

## person id -> the object they are invited about this month.
func _invited(state, ns) -> Dictionary:
	var out := {}
	for pair in AudienceTriggers.invitations(state, ns, _loader, METERS, _leaders(), _now(state)):
		out[String(pair[0].id)] = String(pair[1]["object"])
	return out


## A France person with a portfolio want that is, or is not, served in this state:
## {id, object}, or {}.
func _office_wanter(ns, served: bool) -> Dictionary:
	for person in _loader.people[PLAYER]:
		if person.id == President.leader_id(ns):
			continue
		for want in person.wants:
			var object := String(want["object"])
			if object.begins_with("office:portfolio:") and Characters.want_served(ns, person, want, METERS, _leaders()) == served:
				return {"id": person.id, "object": object}
	return {}


func _leaders() -> Dictionary:
	var leaders := {}
	for party in _loader.parties[PLAYER]:
		leaders[party.id] = party.leader_person_id
	return leaders


func _game():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 3
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


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_audience_triggers: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
