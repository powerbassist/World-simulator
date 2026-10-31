extends SceneTree

## V5.3-0. The staff kind (docs/design/v5.3-0-readability.md section 2.1): the
## chief of staff is a person record of the played nation that MOVES NO NUMBER.
## The rule is by kind, never by id -- CharacterK.KIND_STAFF -- and this file
## pins its three halves:
##
##   - THE KIND LOADS, and the loader refuses what would let a staff person act:
##     a want, a party, a slot (a nation's leader or head, a party's leader).
##   - A STAFF PERSON MOVES NOTHING. A tempting one (ambition 1, `ambitious`,
##     social skill 1, the first id and the first row of the played nation) is
##     injected into the real register, and 24 months of the game's own month
##     must leave the saved state byte for byte what it is without them. This is
##     the structural half of band RF8; the balance table's cmp is the other.
##   - EVERY WALKER FACES THE RULE. The sites that read loader.people in src/sim
##     and src/core are pinned by count, so a new walker cannot read every kind
##     without someone deciding it goes through Staff.cast() (which drops
##     the staff) or filters by a kind of its own.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Person = preload("res://src/core/person.gd")
const PeopleLoader = preload("res://src/core/loaders/people_loader.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")
const Staff = preload("res://src/sim/staff.gd")
const President = preload("res://src/sim/president.gd")
const Audiences = preload("res://src/sim/audiences.gd")

const PLAYER := "FRA"
const STAFF_ID := "FRA_aaa_test_chief_of_staff"
## Two years: an audience lane's month-3 guarantee, a few act thresholds and an
## election-year boundary all fall inside it.
const MONTHS := 24

## Every read of `loader.people` in src/sim and src/core, by file. A walker
## that can write a number goes through Staff.cast(); the others filter by
## a kind of their own (an executive, a press owner, a politician, the event's
## speaker kind), are staff.gd's own two (the cast, the chief lookup) or are
## the loader's own validation.
const WALKERS := {
	"res://src/core/loaders/companies_loader.gd": 1,
	"res://src/core/loaders/people_loader.gd": 4,
	"res://src/sim/staff.gd": 2,
	"res://src/sim/companies.gd": 1,
	"res://src/sim/exposure.gd": 1,
	"res://src/sim/party_money.gd": 1,
	"res://src/sim/speakers.gd": 1,
}

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_kind_loads()
	_check_staff_moves_nothing()
	_check_staff_refusals()
	_check_walker_inventory()

	if _failures.is_empty():
		print("test_staff_kind: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _staff_person(extra: Dictionary = {}):
	var d := {
		"id": STAFF_ID, "name": "Test Chief", "kind": "chief_of_staff",
		"traits": ["ambitious", "networked"], "ambition": 1.0, "social_skill": 1.0,
	}
	d.merge(extra, true)
	var errors: Array[String] = []
	var person = Person.from_dict(d, 0, "%s.json" % PLAYER, errors)
	if not errors.is_empty():
		_fail("a staff record did not parse: %s" % [errors])
	return person


func _check_kind_loads() -> void:
	if not CharacterK.KIND_STAFF.has("chief_of_staff"):
		_fail("chief_of_staff is not in KIND_STAFF")
	for kind in CharacterK.KIND_STAFF:
		if not CharacterK.KIND_KEYS.has(kind):
			_fail("KIND_STAFF names '%s', which is not in KIND_KEYS" % kind)
		if CharacterK.KIND_METERS.has(kind):
			_fail("staff kind '%s' reads a meter -- staff never act" % kind)
	var person = _staff_person()
	if person != null and String(person.kind) != "chief_of_staff":
		_fail("the staff record loaded as kind '%s'" % person.kind)


## Run A on the register as authored, run B with the staff person injected at
## the head of the played nation's list. Same process, same seed, same months.
func _check_staff_moves_nothing() -> void:
	var clean := _run_months()
	var person = _staff_person()
	if person == null:
		return
	_loader.people[PLAYER].insert(0, person)
	_loader.person_by_id[STAFF_ID] = person
	_loader.errors.clear()
	PeopleLoader.validate_people(_loader)
	if not _loader.errors.is_empty():
		_fail("a clean staff record was refused: %s" % [_loader.errors])
	if Staff.chief_of(_loader, PLAYER) != person:
		_fail("Staff.chief_of() did not find the injected chief of staff")
	if Staff.cast(_loader, PLAYER).has(person) or Staff.cast(_loader, PLAYER).size() != _loader.people[PLAYER].size() - 1:
		_fail("Staff.cast() kept the staff person, or dropped someone else")
	if Staff.chief_of(_loader, "NOT_A_NATION") != null:
		_fail("Staff.chief_of() found a chief in a nation that does not exist")
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	for register in [ns.person_standing, ns.person_loyalty, ns.person_grudges]:
		if register.has(STAFF_ID):
			_fail("new_game seeded the staff person into a character register")
	# The run-against-run compare is relative: a cast that dropped EVERYONE would
	# leave both runs equal. The absolute half: everyone else is still seeded.
	if ns.person_standing.is_empty() or ns.person_standing.size() != Staff.cast(_loader, PLAYER).size():
		_fail("new_game seeded %d people, the cast holds %d" % [ns.person_standing.size(), Staff.cast(_loader, PLAYER).size()])
	# The player's verbs: no edge reaches the chief, and the chief never asks.
	# The positive control is the first other person the president covers.
	if President.covers(state, ns, _loader, STAFF_ID):
		_fail("President.covers() lets an edge reach the chief of staff")
	var other := ""
	for p in Staff.cast(_loader, PLAYER):
		if String(p.id) != President.leader_id(ns):
			other = String(p.id)
			break
	if other == "" or not President.covers(state, ns, _loader, other):
		_fail("President.covers() refused '%s', an ordinary person (the control)" % other)
	if bool(Audiences.invite(state, ns, _loader, STAFF_ID, "office:premiership", "want").get("ok", true)):
		_fail("Audiences.invite() made the chief of staff ask")
	var with_staff := _run_months()
	if with_staff != clean:
		_fail("a staff person moved the saved state over %d months (first difference at char %d)"
			% [MONTHS, _first_difference(clean, with_staff)])
	_loader.people[PLAYER].remove_at(0)
	_loader.person_by_id.erase(STAFF_ID)


func _run_months() -> String:
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	for i in range(MONTHS):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		WorldMonth.tick_month(state, _loader)
	return JSON.stringify(state.to_dict())


func _first_difference(a: String, b: String) -> int:
	for i in range(mini(a.length(), b.length())):
		if a[i] != b[i]:
			return i
	return mini(a.length(), b.length())


## A staff person with a want, a party, or in a slot is refused by name, each
## on its own: any one of them is a road into the walkers' arithmetic.
func _check_staff_refusals() -> void:
	var party = _loader.parties[PLAYER][0]
	var party_leader := String(party.leader_person_id)
	var cases := {
		"a want": func(p) -> void: p.wants.append({"object": "office:premiership", "stance": "want"}),
		"a party": func(p) -> void: p.party_id = String(party.id),
		"a nation's slot": func(_p) -> void: _loader.nations[PLAYER].pretender_person_id = STAFF_ID,
		"a party's leadership": func(_p) -> void: party.leader_person_id = STAFF_ID,
	}
	var pretender := String(_loader.nations[PLAYER].pretender_person_id)
	for label in cases:
		var person = _staff_person()
		if person == null:
			return
		(cases[label] as Callable).call(person)
		_loader.people[PLAYER].append(person)
		_loader.person_by_id[STAFF_ID] = person
		_loader.errors.clear()
		PeopleLoader.validate_people(_loader)
		var named := false
		for e in _loader.errors:
			if String(e).contains(STAFF_ID) and String(e).contains("staff"):
				named = true
		if not named:
			_fail("a staff person with %s loaded: %s" % [label, [_loader.errors]])
		_loader.people[PLAYER].remove_at(_loader.people[PLAYER].size() - 1)
		_loader.person_by_id.erase(STAFF_ID)
		_loader.nations[PLAYER].pretender_person_id = pretender
		party.leader_person_id = party_leader
	# Two chiefs in one nation: the briefing reads one, so the second is refused.
	var first = _staff_person()
	var second = _staff_person({"id": "%s_aab_test_chief_of_staff" % PLAYER})
	_loader.people[PLAYER].append(first)
	_loader.people[PLAYER].append(second)
	_loader.errors.clear()
	PeopleLoader.validate_people(_loader)
	if not str(_loader.errors).contains("at most one"):
		_fail("two chiefs of staff in %s loaded: %s" % [PLAYER, [_loader.errors]])
	_loader.people[PLAYER].remove_at(_loader.people[PLAYER].size() - 1)
	_loader.people[PLAYER].remove_at(_loader.people[PLAYER].size() - 1)
	_loader.errors.clear()


func _check_walker_inventory() -> void:
	var found := {}
	for dir in ["res://src/sim", "res://src/core"]:
		_count_reads(dir, found)
	for path in found:
		if int(found[path]) != int(WALKERS.get(path, 0)):
			_fail("%s reads loader.people %d times, the pin says %d: a walker that can write a number goes through Staff.cast() (it drops CharacterK.KIND_STAFF) or filters by a kind of its own; then update WALKERS"
				% [path, int(found[path]), int(WALKERS.get(path, 0))])
	for path in WALKERS:
		if not found.has(path):
			_fail("%s no longer reads loader.people; drop it from WALKERS" % path)


func _count_reads(dir_path: String, found: Dictionary) -> void:
	var re := RegEx.create_from_string("\\bloader\\.people\\b")
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_fail("cannot open %s" % dir_path)
		return
	for sub in dir.get_directories():
		_count_reads(dir_path.path_join(sub), found)
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var path := dir_path.path_join(file)
		var hits := re.search_all(FileAccess.get_file_as_string(path)).size()
		if hits > 0:
			found[path] = hits


func _fail(message: String) -> void:
	_failures.append(message)
