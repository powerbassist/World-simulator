extends RefCounted

## V5.2d. An event's `speaker` and `speaker_line` (docs/design/v5.2-d-spec.md
## section 3), validated for src/core/event.gd's loader -- its own file because
## event.gd sits at the size ratchet's 300 code lines. Writes `ev.speaker` and
## `ev.speaker_line` on a clean form, and appends to `errors` otherwise.

const K = preload("res://src/sim/events_constants.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")


## V5.2d. The speaker and the line come together: a face with nothing to say is a
## card that shows a portrait over the narrator's text, and a line with no face is a
## quote nobody says. Each form is refused loudly when malformed, because a typo'd
## kind or office would fall back to the narrator in silence -- the failure D5 counts.
static func extract(ev, d: Dictionary, filename: String, errors: Array[String]) -> void:
	var raw = d.get("speaker", null)
	var line = d.get("speaker_line", null)
	if raw == null and line == null:
		return
	if raw == null or line == null:
		errors.append("%s: %s 'speaker' and 'speaker_line' go together -- a face says its line" % [filename, ev.id])
		return
	if typeof(line) != TYPE_STRING or String(line).strip_edges() == "" or String(line).contains("{"):
		errors.append("%s: %s speaker_line must be one whole sentence with no variables" % [filename, ev.id])
		return
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s speaker must be an object, one of %s" % [filename, ev.id, K.SPEAKER_FORMS])
		return
	var forms: Array = []
	for key in raw.keys():
		if K.SPEAKER_FORMS.has(key):
			forms.append(key)
		elif key != "pick":
			errors.append("%s: %s speaker.%s is not a recognised field (%s, and pick)" % [filename, ev.id, str(key), K.SPEAKER_FORMS])
			return
	if forms.size() != 1:
		errors.append("%s: %s speaker needs exactly one of %s" % [filename, ev.id, K.SPEAKER_FORMS])
		return
	var form: String = forms[0]
	var value = raw[form]
	var ok := false
	match form:
		"kind":
			ok = typeof(value) == TYPE_STRING and CharacterK.KIND_KEYS.has(value) \
					and (not raw.has("pick") or (typeof(raw["pick"]) == TYPE_STRING and K.SPEAKER_PICKS.has(raw["pick"])))
		"office":
			ok = typeof(value) == TYPE_STRING and K.SUBJECT_OFFICES.has(value) and not raw.has("pick")
		_:
			ok = typeof(value) == TYPE_BOOL and bool(value) and not raw.has("pick")
	if not ok:
		errors.append("%s: %s speaker %s is malformed -- kind in %s (pick in %s), office in %s, or evidence_person / foreign_head true" % [
			filename, ev.id, str(raw), CharacterK.KIND_KEYS, K.SPEAKER_PICKS, K.SUBJECT_OFFICES
		])
		return
	# The witness is the exposure's evidence row: an event the exposure machine never
	# arms has no row, so the face would always be the narrator.
	if form == "evidence_person" and ev.on_action != "exposure":
		errors.append("%s: %s speaker evidence_person needs on_action 'exposure' -- only an exposure has a witness" % [filename, ev.id])
		return
	ev.speaker = (raw as Dictionary).duplicate()
	ev.speaker_line = String(line)
