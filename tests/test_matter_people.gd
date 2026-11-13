extends SceneTree
## V5.3 audience reads (the parent's card of 2026-11-13, mockup C's "Ask her about"): the
## people in the matter of a request, from what the data links and nothing invented.
## Headless.
##
##   - At most MAX, never the asker, the president or a chief of staff, no one twice.
##   - Anchors first: a firm's chief.
##   - Then the others who want the same thing, the other stance first, each by standing.
##   - On a law or a programme goal with laws: the leaders of the parties with seats, the
##     other side of the asker's stance first (Legislature.support).
##   - On a meter: the people whose kind reads that meter (CharacterK.KIND_METERS).
##   - The same request reads the same people twice; an object nothing links reads none.
const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const AudK = preload("res://src/sim/audience_constants.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const Deal = preload("res://src/sim/deal.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const MatterPeople = preload("res://src/sim/matter_people.gd")
const President = preload("res://src/sim/president.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader
var _base


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_base = GameState.new_game(_loader, PLAYER)
	_check_the_people_are_few_and_never_the_asker()
	_check_a_firms_chief_comes_first()
	_check_the_same_want_the_other_stance_first()
	_check_a_goal_names_the_party_leaders_other_side_first()
	_check_a_meter_names_the_people_who_read_it()
	_check_nothing_linked_reads_no_one()
	_check_deal_reads_the_same()
	_finish()


func _row(pid: String, object: String, stance: String) -> Dictionary:
	var now := int(_base.year) * 12 + int(_base.month)
	return {"id": "%s|%d" % [pid, now], "person_id": pid, "object": object, "stance": stance,
		"arrived_month": now, "deadline_month": now + 3, "status": AudK.STATUS_PENDING, "date": {}, "resolved_month": -1}


func _of(row: Dictionary) -> Array:
	return MatterPeople.of(_base, _base.player(), _loader, row)


## Every want of the nation's people, as requests from their holders: none reads more than
## MAX people, the asker, the president or a chief of staff, or anyone twice; each reads
## the same people twice.
func _check_the_people_are_few_and_never_the_asker() -> void:
	var leader := President.leader_id(_base.player())
	var seen := 0
	for person in _loader.people[PLAYER]:
		for want in person.wants:
			var row := _row(String(person.id), String(want["object"]), String(want["stance"]))
			var got := _of(row)
			seen += 1
			_ok(got.size() <= MatterPeople.MAX, "%s on %s read %d people" % [person.id, want["object"], got.size()])
			_ok(not got.has(String(person.id)) and not got.has(leader), "%s on %s read the asker or the president: %s" % [person.id, want["object"], got])
			var once := {}
			for pid in got:
				_ok(not once.has(pid), "%s read twice for %s" % [pid, person.id])
				once[pid] = true
				var who = _loader.person_by_id.get(pid)
				_ok(who != null and String(who.kind) != "chief_of_staff", "%s is no one to talk about" % pid)
			_ok(got == _of(row), "%s on %s read two different lists" % [person.id, want["object"]])
	_ok(seen > 50, "only %d wants were read" % seen)


func _check_a_firms_chief_comes_first() -> void:
	var firm = Companies.majors_of(_loader, PLAYER)[0]
	var asker := _union_leader()
	var got := _of(_row(asker, "%s%s" % [AudK.FIRM_PREFIX, String(firm.id)], "want"))
	_ok(not got.is_empty() and String(got[0]) == String(firm.chief_id), "a firm's chief is not first: %s (chief %s)" % [got, firm.chief_id])
	var own := _of(_row(String(firm.chief_id), "%s%s" % [AudK.FIRM_PREFIX, String(firm.id)], "want"))
	_ok(not own.has(String(firm.chief_id)), "the chief asking about their own firm reads themselves")


## Two others want what the asker wants; the one on the other side comes first whatever
## the standings, then the same side, each by standing.
func _check_the_same_want_the_other_stance_first() -> void:
	var object := "meter:press_freedom"
	var holders: Array = []
	for person in _loader.people[PLAYER]:
		for want in person.wants:
			if String(want["object"]) == object:
				holders.append(person)
	if holders.size() < 3:
		_failures.append("the fixture needs three people wanting %s" % object)
		return
	holders.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var asker = holders[0]
	var other_side = holders[2]
	var flipped := {}
	for want in other_side.wants:
		if String(want["object"]) == object:
			flipped = want
	var kept := String(flipped["stance"])
	flipped["stance"] = "attack" if kept != "attack" else "defend"
	var ns = _base.player()
	var before: Dictionary = ns.person_standing.duplicate()
	ns.person_standing[String(other_side.id)] = 0.0
	ns.person_standing[String(holders[1].id)] = 0.9
	var got := _of(_row(String(asker.id), object, "defend"))
	flipped["stance"] = kept
	ns.person_standing = before
	_ok(got.size() >= 2 and String(got[0]) == String(other_side.id) and String(got[1]) == String(holders[1].id),
		"the other stance did not come first, then the same by standing: %s" % [got])


## The mockup's own case: a word that The Six And A Half Line stays off the programme. The
## goal names laws, so the leaders of the parties with seats come in, the goal's supporters
## first since the asker opposes it.
func _check_a_goal_names_the_party_leaders_other_side_first() -> void:
	var got := _of(_row("FRA_vasseur", "programme:prog_paybelt", "oppose"))
	_ok(not got.is_empty(), "the mockup's case reads no one")
	var ns = _base.player()
	var laws: Array = _loader.laws.filter(func(l): return ["labour_market_flexibilisation", "hiring_credit_act"].has(String(l.id)))
	_ok(laws.size() == 2, "the goal's two laws are not in the book")
	var support_of := {}
	for party in _loader.parties[PLAYER]:
		var mean := 0.0
		for law in laws:
			mean += Legislature.support(ns, party, law) / laws.size()
		support_of[String(party.leader_person_id)] = mean
	var last := INF
	for pid in got:
		if support_of.has(pid):
			_ok(float(support_of[pid]) <= last + 0.000001, "the party leaders are not the goal's supporters first: %s" % [got])
			last = float(support_of[pid])


func _check_a_meter_names_the_people_who_read_it() -> void:
	var got := _of(_row(_union_leader(), "meter:grievance", "defend"))
	_ok(not got.is_empty(), "a meter read no one")
	for pid in got:
		var who = _loader.person_by_id[pid]
		var wants_it := false
		for want in who.wants:
			wants_it = wants_it or String(want["object"]) == "meter:grievance"
		_ok(wants_it or String(CharacterK.KIND_METERS.get(String(who.kind), "")) == "grievance",
			"%s (%s) is in a grievance matter for no reason" % [pid, who.kind])


func _check_nothing_linked_reads_no_one() -> void:
	_ok(_of(_row(_union_leader(), "office:nothing_at_all", "want")).is_empty(), "an object nothing links read someone")


func _check_deal_reads_the_same() -> void:
	var row := _row("FRA_vasseur", "programme:prog_paybelt", "oppose")
	var ns = _base.player()
	ns.audience_requests.append(row)
	var session := {"request_id": String(row["id"]), "person_id": "FRA_vasseur"}
	_ok(Deal.people_in_matter(_base, ns, _loader, session) == _of(row), "Deal's door reads other people")
	ns.audience_requests.erase(row)


func _union_leader() -> String:
	var ids: Array = []
	for person in _loader.people[PLAYER]:
		if String(person.kind) == "union_leader":
			ids.append(String(person.id))
	ids.sort()
	return String(ids[0])


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_matter_people: OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		print("test_matter_people: FAIL (%d)" % _failures.size())
		quit(1)
