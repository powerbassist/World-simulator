extends SceneTree

## Headless test: godot --headless --script res://tests/test_voices.gd
## Non-zero exit on any failure.
##
## V5.2d, the voice archetypes (docs/design/v5.2-d-spec.md section 6). The table is read by
## tools/voice_pipeline.py, which never designs or picks a voice, so a bad row is silent
## there: a default naming no archetype voices nothing, a person's `voice` naming the wrong
## kind or sex would put a man's voice on a woman's portrait. This pins the table's own
## consistency against the people files and the portrait sidecar (sex is a portrait fact,
## tools/portraits_traits.json, not a game field). voice_id may be empty until the voices
## are designed; the pipeline reports those as no-voice.

const ARCHETYPES := "res://data/voices/archetypes.json"
const TRAITS := "res://tools/portraits_traits.json"
const SAFE_ID := "^[A-Za-z0-9_-]+$"
const UNVOICEABLE := r"\{\{|%[sdif%]|\[g="

var _failures: Array[String] = []


func _init() -> void:
	var table: Dictionary = _read(ARCHETYPES)
	var traits: Dictionary = _read(TRAITS)
	var by_id := {}
	var safe := RegEx.create_from_string(SAFE_ID)
	var bad_line := RegEx.create_from_string(UNVOICEABLE)
	for a in table.get("archetypes", []):
		var id := String(a.get("id", ""))
		if safe.search(id) == null:
			_fail("archetype id '%s' is not a safe path part" % id)
		if by_id.has(id):
			_fail("archetype id '%s' is used twice" % id)
		by_id[id] = a
		for key in ["kind", "sex", "age_band", "language", "provenance"]:
			if String(a.get(key, "")) == "":
				_fail("%s: missing %s" % [id, key])
		if not ["m", "f"].has(String(a.get("sex", ""))):
			_fail("%s: sex must be m or f" % id)
		if not a.has("voice_id"):
			_fail("%s: voice_id is absent (empty is allowed until the voice is designed)" % id)
		for line_id in a.get("lines", {}).keys():
			if safe.search(String(line_id)) == null:
				_fail("%s: line id '%s' is not a safe path part" % [id, line_id])
			var text := String(a["lines"][line_id])
			if text.strip_edges() == "" or bad_line.search(text) != null:
				_fail("%s/%s: a voiced line must be a plain variable-free sentence" % [id, line_id])
	var defaults: Dictionary = table.get("defaults", {})
	for key in defaults.keys():
		if not by_id.has(String(defaults[key])):
			_fail("default '%s' names no archetype '%s'" % [key, defaults[key]])
	var kinds := {}
	for a in by_id.values():
		kinds[String(a["kind"])] = true
	for kind in kinds.keys():
		if not defaults.has(kind):
			_fail("kind '%s' has no default archetype" % kind)
	var with_voice := 0
	var dir := DirAccess.open("res://data/people")
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		for p in _read("res://data/people/" + fname).get("people", []):
			var pid := String(p["id"])
			var female: bool = traits.has(pid) and String(traits[pid]["sex"]) == "female"
			var kind := String(p["kind"])
			# The kind's default is a man's voice, so exactly the portraits of women carry a field.
			if p.has("voice"):
				with_voice += 1
				var v := String(p["voice"])
				if not by_id.has(v):
					_fail("%s: voice '%s' is no archetype" % [pid, v])
					continue
				if String(by_id[v]["kind"]) != kind:
					_fail("%s: voice '%s' is another kind than '%s'" % [pid, v, kind])
				if String(by_id[v]["sex"]) != ("f" if female else "m"):
					_fail("%s: voice '%s' does not match the portrait's sex" % [pid, v])
			elif female:
				_fail("%s: a woman's portrait with no voice field would read in the kind's male default" % pid)
			elif defaults.has(kind) and by_id.has(String(defaults[kind])) and String(by_id[String(defaults[kind])]["sex"]) != "m":
				_fail("default for '%s' must be a male archetype (an absent voice means it)" % kind)
	if with_voice == 0:
		_fail("no person carries a voice field, this check is looking at nothing")
	if _failures.is_empty():
		print("test_voices: all checks passed")
		quit(0)
	else:
		for message in _failures:
			print("FAIL: %s" % message)
		quit(1)


func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("%s is not a JSON object" % path)
		return {}
	return parsed


func _fail(message: String) -> void:
	_failures.append(message)
