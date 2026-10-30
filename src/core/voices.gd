extends RefCounted

## Which voice a person speaks in -- V5.2d, docs/design/v5.2-d-spec.md section 6.
## The ONE resolver: playback (src/ui) calls archetype_of() with the speaker id an
## event's desk entry carries (src/sim/speakers.gd). tools/voice_pipeline.py's
## voices_for(), which cannot call GDScript, applies the same rule to the same table
## ("a person's own `voice`, else their kind's default") and must stay in step with it.
##
## A value-type helper over the loader, like src/core/relations.gd: no model, no
## tunable, and presentation only -- nothing in src/sim/ reads a voice.


## The archetype id (data/voices/archetypes.json) the person speaks in: their own
## `voice`, else their kind's default. "" for no person (the narrator) or a kind the
## table has no default for.
static func archetype_of(loader, person_id: String) -> String:
	var person = loader.person_by_id.get(person_id, null)
	if person == null:
		return ""
	if String(person.voice) != "":
		return String(person.voice)
	return String(loader.voice_defaults.get(String(person.kind), ""))


## An event's speaker (GameEvent.speaker, the authored form) as resolved at delivery
## (`person_id`, the desk entry's "speaker"): the PERSON's voice whenever there is
## one -- an office holder or a foreign head is a person, so a woman prime minister
## speaks in her own voice, not the office's default (QA's RECORD on #199) -- and
## otherwise the form's default in the table (a vacant office, a kind the nation
## lacks): the kind, "office:<office>" (else the politician's, an office being a
## politician's), "evidence_person" or "foreign_head". "" for no form: the narrator.
static func speaker_archetype(loader, form: Dictionary, person_id: String) -> String:
	var own := archetype_of(loader, person_id)
	if own != "" or form.is_empty():
		return own
	var defaults: Dictionary = loader.voice_defaults
	if form.has("kind"):
		return String(defaults.get(String(form["kind"]), ""))
	if form.has("office"):
		return String(defaults.get("office:%s" % form["office"], defaults.get("politician", "")))
	for key in ["evidence_person", "foreign_head"]:
		if form.has(key):
			return String(defaults.get(key, ""))
	return ""
