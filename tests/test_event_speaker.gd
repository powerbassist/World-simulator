extends SceneTree

## V5.2d. Every event has a face (docs/design/v5.2-d-spec.md section 3): the
## `speaker` / `speaker_line` schema the loader holds content to.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameEvent = preload("res://src/core/event.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

const LINE := "Mr President, the yards are out and they will not go back for a promise."

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_schema_accepts_every_form()
	_check_schema_refuses_malformed_speakers()
	_check_schema_pairs_speaker_and_line()
	_finish()


# --- The schema -----------------------------------------------------------------------

func _event(speaker = null, line = null, on_action := "") -> Dictionary:
	var d := {
		"id": "probe_speaker", "name": "Probe", "summary": "A probe.", "likelihood": 0.002,
		"respond_months": 2, "category": "industrial", "severity": 2,
		"choices": [
			{"id": "a", "label": "A", "summary": "A.", "default": true, "effects": {"bloc_offset": {"business": -0.02}}},
			{"id": "b", "label": "B", "summary": "B.", "effects": {"bloc_offset": {"workers": -0.02}}},
		],
	}
	if on_action == "exposure":
		d["category"] = "scandal"
		d["on_action"] = "exposure"
		d["exposure"] = {"route": "turned", "kinds": ["affair"]}
	if speaker != null:
		d["speaker"] = speaker
	if line != null:
		d["speaker_line"] = line
	return d


func _errors_of(d: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	GameEvent.from_dict(d, "probe.json", errors, [], [], OpinionK.BLOC_KEYS, [])
	return errors


func _check_schema_accepts_every_form() -> void:
	var forms := [
		[{"kind": "union_leader"}, ""],
		[{"kind": "press_owner", "pick": "hostile"}, ""],
		[{"kind": "politician", "pick": "friendly"}, ""],
		[{"kind": "judge"}, ""],
		[{"office": "head_of_government"}, ""],
		[{"office": "head_of_state"}, ""],
		[{"office": "largest_party_leader"}, ""],
		[{"foreign_head": true}, ""],
		[{"evidence_person": true}, "exposure"],
	]
	for form in forms:
		var errors := _errors_of(_event(form[0], LINE, form[1]))
		if not errors.is_empty():
			_failures.append("a valid speaker %s was refused: %s" % [form[0], errors])
	var d := _event({"kind": "union_leader"}, LINE)
	var ev = GameEvent.from_dict(d, "probe.json", [] as Array[String], [], [], OpinionK.BLOC_KEYS, [])
	if ev.speaker != {"kind": "union_leader"} or ev.speaker_line != LINE:
		_failures.append("the loaded event did not carry its speaker and line: %s / %s" % [ev.speaker, ev.speaker_line])
	# No speaker is the narrator, as every event before d.
	var bare = GameEvent.from_dict(_event(), "probe.json", [] as Array[String], [], [], OpinionK.BLOC_KEYS, [])
	if not bare.speaker.is_empty() or bare.speaker_line != "":
		_failures.append("an event with no speaker loaded one")


func _check_schema_refuses_malformed_speakers() -> void:
	var bad := [
		"union_leader",                                   # not an object
		{},                                               # no form
		{"kind": "plumber"},                              # a kind content does not define
		{"kind": "press_owner", "pick": "loudest"},       # a pick outside the two
		{"office": "mayor"},                              # an office outside SUBJECT_OFFICES
		{"office": "head_of_government", "pick": "hostile"},  # a pick on an office
		{"kind": "judge", "office": "head_of_state"},     # two forms
		{"foreign_head": false},                          # a flag that says nothing
		{"evidence_person": "yes"},                       # a flag that is not a bool
		{"kind": "judge", "mood": "stern"},               # an unknown key
	]
	for speaker in bad:
		if _errors_of(_event(speaker, LINE)).is_empty():
			_failures.append("a malformed speaker loaded: %s" % [speaker])
	# The witness exists only where the exposure machine names one.
	if _errors_of(_event({"evidence_person": true}, LINE)).is_empty():
		_failures.append("evidence_person loaded on an event the exposure machine never arms")


func _check_schema_pairs_speaker_and_line() -> void:
	if _errors_of(_event({"kind": "union_leader"})).is_empty():
		_failures.append("a speaker with no speaker_line loaded -- a face with nothing to say")
	if _errors_of(_event(null, LINE)).is_empty():
		_failures.append("a speaker_line with no speaker loaded -- a line nobody says")
	for line in ["", 7, "Mr {{president}}, the yards are out."]:
		if _errors_of(_event({"kind": "union_leader"}, line)).is_empty():
			_failures.append("a speaker_line that is not one variable-free sentence loaded: %s" % [line])


func _finish() -> void:
	if _failures.is_empty():
		print("test_event_speaker: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
