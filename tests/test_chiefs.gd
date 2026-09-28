extends SceneTree

## V4.7a Task A2: the majors' named chiefs. The firm→person edge is the block's
## first cross-register reference OUT of data/companies/, and the executive
## kind is the register's first DECLARED STOPGAP kind -- no meter, no wants,
## unable to act until V4.2's lobbying opens the lever (the reason lives beside
## KIND_KEYS in character_constants.gd and beside _check_kind_meter_coverage in
## test_people.gd). What is pinned here:
##
##   - every major carries a chief_id that resolves to an executive of its own
##     nation -- the count-is-the-design rule means a champion with no face is
##     a half-built register;
##   - every chief IS the stopgap: kind executive, no meter, no party, no
##     wants -- so the day someone gives a chief a want or a meter without
##     opening the V4.2 lever, this file says so;
##   - chiefs are bench people (bench: true) -- the met cast is the political
##     register, and 26 new five-emotion portraits is art debt nobody asked
##     for;
##   - one chief per major, no orphans: every executive is some firm's chief,
##     which is what keeps the kind from becoming a second way to author a
##     person nothing reads.

const DataLoader = preload("res://src/core/data_loader.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_test_every_major_has_a_resolving_chief()
		_test_chiefs_are_the_declared_stopgap()
		_test_no_orphan_executives()
	_finish()


func _test_every_major_has_a_resolving_chief() -> void:
	var majors := 0
	for nation_id in _loader.companies.keys():
		var people := {}
		for person in _loader.people.get(nation_id, []):
			people[person.id] = person
		for company in _loader.companies[nation_id]:
			if String(company.tier) != "major":
				continue
			majors += 1
			if company.chief_id == "":
				_fail("%s carries no chief" % company.id)
				continue
			var chief = people.get(company.chief_id)
			if chief == null:
				_fail("%s chief '%s' does not resolve" % [company.id, company.chief_id])
				continue
			if chief.kind != "executive":
				_fail("%s chief '%s' is kind '%s', not executive" % [
					company.id, company.chief_id, chief.kind])
	# A3 grew the majors to every nation: the A2 pin was exactly 26 (the four
	# authored nations); the A3 register holds 10-15 majors for each of the
	# 29, so the pin is now the BAND the tier doc authors, not a count.
	if majors < 290 or majors > 435:
		_fail("expected majors in [290, 435] (29 nations x [10, 15]), found %d" % majors)


func _test_chiefs_are_the_declared_stopgap() -> void:
	if not CharacterK.KIND_KEYS.has("executive"):
		_fail("executive is not in KIND_KEYS")
	if CharacterK.KIND_METERS.has("executive"):
		_fail("executive carries a meter -- the stopgap grew a lever without V4.2")
	for nation_id in _loader.companies.keys():
		for person in _loader.people.get(nation_id, []):
			if person.kind != "executive":
				continue
			if person.party_id != "":
				_fail("chief '%s' carries a party -- executives are the appoint pool, not a political bloc" % person.id)
			if not person.wants.is_empty():
				_fail("chief '%s' carries wants -- the stopgap's act channel is V4.2's, not this block's" % person.id)
			if not person.bench:
				_fail("chief '%s' is met cast -- five portraits of art debt nobody asked for" % person.id)


func _test_no_orphan_executives() -> void:
	var chief_ids := {}
	for nation_id in _loader.companies.keys():
		for company in _loader.companies[nation_id]:
			if company.chief_id != "":
				chief_ids[company.chief_id] = true
	for nation_id in _loader.people.keys():
		for person in _loader.people[nation_id]:
			if person.kind == "executive" and not chief_ids.has(person.id):
				_fail("executive '%s' fronts no firm -- an orphan chief is a person nothing reads" % person.id)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_chiefs: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)
