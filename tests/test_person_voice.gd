extends SceneTree

## V5.2d. A person's voice (docs/design/v5.2-d-spec.md section 6; data/voices/
## archetypes.json): `Person.voice` read by the loader, absent meaning the kind's
## default archetype, and the one resolver playback calls, Voices.archetype_of().
## Without it every woman spoke in her kind's male default.

const DataLoader = preload("res://src/core/data_loader.gd")
const Person = preload("res://src/core/person.gd")
const PeopleLoader = preload("res://src/core/loaders/people_loader.gd")
const Voices = preload("res://src/core/voices.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_the_table_loads()
	_check_own_voice_wins()
	_check_absent_voice_is_the_kind_default()
	_check_nobody_has_no_voice()
	_check_shape_refused()
	_check_cross_check_refuses_a_wrong_archetype()
	_finish()


func _check_the_table_loads() -> void:
	if _loader.voice_archetypes.size() < 2 or _loader.voice_defaults.is_empty():
		_failures.append("the archetype table did not load: %d archetypes, %d defaults" % [
			_loader.voice_archetypes.size(), _loader.voice_defaults.size()])


## Every authored `voice` reaches the Person and the resolver.
func _check_own_voice_wins() -> void:
	var raw_count := 0
	for path in DirAccess.get_files_at("res://data/people"):
		if not path.ends_with(".json"):
			continue
		var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/people/%s" % path))
		for row in doc.get("people", []):
			if not row.has("voice"):
				continue
			raw_count += 1
			var pid := String(row["id"])
			var person = _loader.person_by_id.get(pid, null)
			if person == null or String(person.voice) != String(row["voice"]):
				_failures.append("%s authored voice %s, the loader read '%s'" % [pid, row["voice"], person.voice if person else "<missing>"])
				return
			if Voices.archetype_of(_loader, pid) != String(row["voice"]):
				_failures.append("%s: the resolver ignored the person's own voice" % pid)
				return
	if raw_count == 0:
		_failures.append("no person in data/people carries a voice -- the check tested nothing")


func _check_absent_voice_is_the_kind_default() -> void:
	var checked := 0
	for pid in _loader.person_by_id:
		var person = _loader.person_by_id[pid]
		if String(person.voice) != "":
			continue
		checked += 1
		var expect := String(_loader.voice_defaults.get(String(person.kind), ""))
		if expect == "" or Voices.archetype_of(_loader, pid) != expect:
			_failures.append("%s (%s, no voice) resolved '%s', not the kind's default '%s'" % [
				pid, person.kind, Voices.archetype_of(_loader, pid), expect])
			return
	if checked == 0:
		_failures.append("every person carries a voice -- the default path tested nothing")


func _check_nobody_has_no_voice() -> void:
	if Voices.archetype_of(_loader, "") != "" or Voices.archetype_of(_loader, "NOPE_nobody") != "":
		_failures.append("the narrator (no person) resolved an archetype")


func _check_shape_refused() -> void:
	for bad in [7, "", "Spaces are not ids", "../escape"]:
		var errors: Array[String] = []
		Person.from_dict({"id": "FRA_probe", "name": "Probe", "voice": bad}, 0, "probe.json", errors)
		if errors.is_empty():
			_failures.append("a voice of %s loaded" % [bad])
	var ok: Array[String] = []
	var p = Person.from_dict({"id": "FRA_probe", "name": "Probe", "voice": "politician_f_50"}, 0, "probe.json", ok)
	if not ok.is_empty() or p.voice != "politician_f_50":
		_failures.append("a well-formed voice was refused: %s" % [ok])


## The loader holds a voice to the table: an archetype it defines, of the person's kind.
func _check_cross_check_refuses_a_wrong_archetype() -> void:
	var person = null
	for pid in _loader.person_by_id:
		if String(_loader.person_by_id[pid].kind) == "judge":
			person = _loader.person_by_id[pid]
			break
	var kept := String(person.voice)
	for bad in ["no_such_archetype", String(_loader.voice_defaults["politician"])]:
		person.voice = bad
		_loader.errors.clear()
		PeopleLoader.validate_voices(_loader)
		if _loader.errors.is_empty():
			_failures.append("a judge with voice '%s' passed the cross-check" % bad)
	person.voice = kept
	_loader.errors.clear()
	PeopleLoader.validate_voices(_loader)
	if not _loader.errors.is_empty():
		_failures.append("the shipped cast fails the voice cross-check: %s" % [_loader.errors])


func _finish() -> void:
	if _failures.is_empty():
		print("test_person_voice: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
