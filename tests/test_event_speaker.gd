extends SceneTree

## V5.2d. Every event has a face (docs/design/v5.2-d-spec.md section 3): the
## `speaker` / `speaker_line` schema the loader holds content to.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameEvent = preload("res://src/core/event.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const GameState = preload("res://src/core/game_state.gd")
const Events = preload("res://src/sim/events.gd")
const K = preload("res://src/sim/events_constants.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")
const President = preload("res://src/sim/president.gd")
const Speakers = preload("res://src/sim/speakers.gd")

const PLAYER := "FRA"
const ARMED := "procurement_scandal"
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
	_check_kind_draws_from_the_top_three()
	_check_picks_read_rapport()
	_check_offices_skip_the_president()
	_check_missing_kind_is_the_narrator()
	_check_evidence_person_is_the_witness()
	_check_foreign_head_is_another_nations_head()
	_check_never_the_president()
	_check_speaker_fixed_while_the_card_waits()
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


# --- The resolution (section 3; D6) ------------------------------------------------------

func _state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	return state


func _index(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _loaded(speaker: Dictionary, on_action := "") -> GameEvent:
	var errors: Array[String] = []
	var ev = GameEvent.from_dict(_event(speaker, LINE, on_action), "probe.json", errors, [], [], OpinionK.BLOC_KEYS, [])
	if not errors.is_empty():
		_failures.append("probe event refused: %s" % [errors])
	return ev


func _people_of(kind: String) -> Array:
	var out: Array = []
	for person in _loader.people.get(PLAYER, []):
		if String(person.kind) == kind:
			out.append(String(person.id))
	return out


## The top three by standing, ties to id -- the rule's own pool, rebuilt here from
## the register so the test does not borrow the code's sort.
func _top_three(ns, kind: String) -> Array:
	var ids := _people_of(kind)
	ids.erase(President.leader_id(ns))
	ids.sort_custom(func(a, b):
		var sa := float(ns.person_standing.get(a, 0.0))
		var sb := float(ns.person_standing.get(b, 0.0))
		return sa > sb if sa != sb else a < b)
	return ids.slice(0, 3)


func _check_kind_draws_from_the_top_three() -> void:
	var state = _state()
	var ns = state.player()
	var ev := _loaded({"kind": "politician"})
	var pool := _top_three(ns, "politician")
	var seen := {}
	for m in range(48):
		var who := Speakers.resolve(state, ns, _loader, ev, _index(state) + m)
		if not pool.has(who):
			_failures.append("kind politician resolved %s, outside the top three by standing %s" % [who, pool])
			return
		seen[who] = true
		if Speakers.resolve(state, ns, _loader, ev, _index(state) + m) != who:
			_failures.append("the speaker draw is not a pure function of the event and the month")
			return
	if seen.size() < 2:
		_failures.append("48 months drew one face from the top three -- the draw does not vary")


func _check_picks_read_rapport() -> void:
	var state = _state()
	var ns = state.player()
	var owners := _people_of("press_owner")
	owners.sort()
	if owners.size() < 2:
		_failures.append("France needs two press owners for the pick check")
		return
	# Every rapport 0: ties go to id.
	var hostile := _loaded({"kind": "press_owner", "pick": "hostile"})
	var friendly := _loaded({"kind": "press_owner", "pick": "friendly"})
	if Speakers.resolve(state, ns, _loader, hostile, _index(state)) != owners[0]:
		_failures.append("hostile pick on equal rapport did not tie to the first id")
	ns.person_rapport[owners[1]] = -0.6
	ns.person_rapport[owners[0]] = 0.4
	if Speakers.resolve(state, ns, _loader, hostile, _index(state)) != owners[1]:
		_failures.append("hostile pick did not take the lowest rapport")
	if Speakers.resolve(state, ns, _loader, friendly, _index(state)) != owners[0]:
		_failures.append("friendly pick did not take the highest rapport")


func _check_offices_skip_the_president() -> void:
	var state = _state()
	var ns = state.player()
	var leader := President.leader_id(ns)
	var hos := _loaded({"office": "head_of_state"})
	var hog := _loaded({"office": "head_of_government"})
	if not ns.has_executive or String(ns.head_of_state_person_id) != leader:
		_failures.append("France's president should hold head_of_state for this check")
		return
	if Speakers.resolve(state, ns, _loader, hog, _index(state)) != String(ns.pm_person_id):
		_failures.append("head_of_government did not resolve to the prime minister")
	if Speakers.resolve(state, ns, _loader, hos, _index(state)) != String(ns.pm_person_id):
		_failures.append("head_of_state held by the president did not fall to the head of government")
	var party := _loaded({"office": "largest_party_leader"})
	var who := Speakers.resolve(state, ns, _loader, party, _index(state))
	if who == "" or who == leader:
		_failures.append("largest_party_leader resolved '%s'" % who)
	# A vacant office is the narrator, not a stand-in.
	var pm_before := String(ns.pm_person_id)
	ns.pm_person_id = ""
	if Speakers.resolve(state, ns, _loader, hog, _index(state)) != "":
		_failures.append("a vacant head_of_government did not fall to the narrator")
	ns.pm_person_id = pm_before
	# Both offices the president's: the narrator speaks.
	var pm := String(ns.pm_person_id)
	ns.pm_person_id = leader
	if Speakers.resolve(state, ns, _loader, hos, _index(state)) != "":
		_failures.append("with both offices the president's, the narrator did not speak")
	ns.pm_person_id = pm


func _check_missing_kind_is_the_narrator() -> void:
	var state = _state()
	var ns = state.player()
	var kept: Array = _loader.people[PLAYER]
	var without: Array = []
	for person in kept:
		if String(person.kind) != "union_leader":
			without.append(person)
	_loader.people[PLAYER] = without
	var who := Speakers.resolve(state, ns, _loader, _loaded({"kind": "union_leader"}), _index(state))
	_loader.people[PLAYER] = kept
	if who != "":
		_failures.append("a kind the nation lacks resolved %s, not the narrator" % who)


func _check_evidence_person_is_the_witness() -> void:
	var state = _state()
	var ns = state.player()
	var ev := _loaded({"evidence_person": true}, "exposure")
	if Speakers.resolve(state, ns, _loader, ev, _index(state)) != "":
		_failures.append("evidence_person with no exposure did not fall to the narrator")
	var witness: String = _people_of("politician")[3]
	var other: String = _people_of("politician")[4]
	ns.exposures.append({"kind": "affair", "route": "turned", "person_id": other, "size": 1.0,
			"made_month": _index(state) - 9, "exposed_month": _index(state) - 4})
	ns.exposures.append({"kind": "affair", "route": "turned", "person_id": witness, "size": 1.0,
			"made_month": _index(state) - 6, "exposed_month": _index(state) - 1})
	ns.exposures.append({"kind": "affair", "route": "press", "person_id": other, "size": 1.0,
			"made_month": _index(state) - 6, "exposed_month": _index(state) - 1})
	if Speakers.resolve(state, ns, _loader, ev, _index(state)) != witness:
		_failures.append("evidence_person did not resolve the latest exposure on the event's route")


func _check_foreign_head_is_another_nations_head() -> void:
	var state = _state()
	var ns = state.player()
	var who := Speakers.resolve(state, ns, _loader, _loaded({"foreign_head": true}), _index(state))
	var found := false
	for nation_id in state.nations:
		if nation_id != PLAYER and String(state.nations[nation_id].pm_person_id) == who:
			found = true
	if who == "" or not found:
		_failures.append("foreign_head resolved '%s', not another nation's head of government" % who)


## D6, first half: every form, every month of a term, never the president.
func _check_never_the_president() -> void:
	var state = _state()
	var ns = state.player()
	var leader := President.leader_id(ns)
	var forms: Array = [{"foreign_head": true}]
	for kind in CharacterK.KIND_KEYS:
		forms.append({"kind": kind})
		forms.append({"kind": kind, "pick": "hostile"})
		forms.append({"kind": kind, "pick": "friendly"})
	for office in K.SUBJECT_OFFICES:
		forms.append({"office": office})
	# The president at the top of every register a pick or a draw reads.
	ns.person_standing[leader] = 1.0
	ns.person_rapport[leader] = -1.0
	for form in forms:
		var ev := _loaded(form)
		for m in range(60):
			if Speakers.resolve(state, ns, _loader, ev, _index(state) + m) == leader:
				_failures.append("speaker %s resolved the president" % [form])
				break


## D6, second half: resolved at delivery and stored on the desk entry, so the
## registers moving under a waiting card do not change its face.
func _check_speaker_fixed_while_the_card_waits() -> void:
	var state = _state()
	var ns = state.player()
	var ev = Events.event_by_id(_loader, ARMED)
	var saved_speaker: Dictionary = ev.speaker
	ev.speaker = {"kind": "press_owner", "pick": "hostile"}
	Events.arm(ns, _loader, ARMED, _index(state) + 1)
	_next_month(state)
	var entry := _entry(ns, ARMED)
	var first := String(entry.get("speaker", ""))
	if first == "" or first == President.leader_id(ns):
		_failures.append("the delivered entry carries no speaker: %s" % [entry])
	for pid in _people_of("press_owner"):
		ns.person_rapport[pid] = 0.9
	ns.person_rapport[_people_of("press_owner")[-1] if first != _people_of("press_owner")[-1] else _people_of("press_owner")[0]] = -0.9
	_next_month(state)
	entry = _entry(ns, ARMED)
	if not entry.is_empty() and String(entry.get("speaker", "")) != first:
		_failures.append("the face changed while the card waited: %s -> %s" % [first, entry.get("speaker", "")])
	elif entry.is_empty():
		_failures.append("%s left the desk before the second month -- pick an event with a longer deadline" % ARMED)
	ev.speaker = saved_speaker


func _entry(ns, event_id: String) -> Dictionary:
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) == event_id:
			return entry
	return {}


func _next_month(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	Events.tick_month(state, _loader)


func _finish() -> void:
	if _failures.is_empty():
		print("test_event_speaker: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
