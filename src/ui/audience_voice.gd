extends RefCounted

## V5.3-0 (c), 4.2 (closing gate R17: no audience spoke). The person in an audience
## or on the phone says their archetype's own four lines: greet when it opens,
## agree or refuse on a lever's result, farewell when it closes. The 56 clips exist
## (data/voices/archetypes.json, all voiced); no credit is spent.
##
## A line is SHOWN as well as played: Voice plays a clip only when its manifest
## hash is the hash of the text on screen, so a line with no caption would be
## silent by design, and a French player reads the line in French and hears
## nothing rather than English under it.

const Strings = preload("res://src/ui/strings.gd")
const Voice = preload("res://src/ui/voice.gd")
const Voices = preload("res://src/core/voices.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")

const LINES := ["greet", "agree", "refuse", "farewell"]  # i18n: ok the archetype table's line ids


## line id -> {text, clip} for `person_id`: their own archetype's line; where it
## has no clip, the same line of their kind's archetype in their own sex, then the
## kind's default (Voice.clip_for's net, the parent's call on QA's #206). A person
## with no archetype at all gets {} and the scene stays silent and captionless.
static func lines(loader, person_id: String) -> Dictionary:
	var own := Voices.archetype_of(loader, person_id)
	var person = loader.person_by_id.get(person_id, null)
	var fallback := String(loader.voice_defaults.get(String(person.kind), "")) if person != null else ""
	var out := {}
	for id in LINES:
		var said := {}
		for arch in [own, Voice.same_sex(loader, own, fallback), fallback]:
			var english := String((loader.voice_archetypes.get(arch, {}).get("lines", {}) as Dictionary).get(id, ""))
			if english == "":
				continue
			var shown := Strings.row("voices", String(arch), "lines.%s" % id, english)
			var clip := Voice.line_clip(String(arch), id, shown)
			if said.is_empty() or clip != "":
				said = {"text": shown, "clip": clip}
			if clip != "":
				break
		if not said.is_empty():
			out[id] = said
	return out


## The line a lever's result draws, by its tone: GOOD and RISKY agree (they said
## yes; the risk is the player's), BAD and BLOCKED refuse, a neutral result says
## nothing.
static func reaction(tone: String) -> String:
	match tone:
		ResultTone.GOOD, ResultTone.RISKY:
			return "agree"  # i18n: ok a line id
		ResultTone.BAD, ResultTone.BLOCKED:
			return "refuse"  # i18n: ok a line id
	return ""


## Shows `id`'s line of `voice` (lines() above) in `caption` and plays its clip
## under `parent`, in turn: while a line is still playing, the next waits for it to
## end (the newest one wins the wait), so the caption never says what the sound
## does not and Voice.speak's never-cut rule needs no change.
static func say(parent: Node, caption: Label, voice: Dictionary, id: String) -> void:
	if id == "" or not voice.has(id):
		return
	var player := parent.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player != null and (player.playing or bool(player.get_meta("pending", false))):
		var waiting := not String(player.get_meta("next", "")).is_empty()
		player.set_meta("next", id)
		if not waiting:
			player.finished.connect(func() -> void:
				var next := String(player.get_meta("next", ""))
				player.set_meta("next", "")
				if is_instance_valid(caption):
					say(parent, caption, voice, next), CONNECT_ONE_SHOT)
		return
	caption.text = Strings.t("“%s”") % String(voice[id]["text"])
	caption.visible = true
	Voice.speak(parent, String(voice[id]["clip"]))
