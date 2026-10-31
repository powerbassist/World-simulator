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
const MoodBadge = preload("res://src/ui/mood_badge.gd")

## The lines waiting for another player's voice to end (parent meta), and their poll.
const WAITING := "voice_waiting"  # i18n: ok a meta key
const WAIT := "VoiceWait"  # i18n: ok a node name

const LINES := ["greet", "agree", "refuse", "farewell", "mood_pleased", "mood_cold", "mood_angry"]  # i18n: ok the archetype table's line ids
## V5.3-0 (e): the mood line a face says on reaching an emotion (MoodBadge's four,
## #226's three lines): warm says pleased, wary or annoyed says cold, cold or
## resentful says angry. Back to neutral says nothing of its own.
const MOODS := {
	MoodBadge.Portrait.Emotion.PLEASED: "mood_pleased",  # i18n: ok a line id
	MoodBadge.Portrait.Emotion.WORRIED: "mood_cold",  # i18n: ok a line id
	MoodBadge.Portrait.Emotion.STERN: "mood_angry",  # i18n: ok a line id
}


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


## The ONE line a result draws (the parent's call: never a mood line queued behind
## agree or refuse): when the face's emotion has changed from `before` (an
## emotion_of() value, -1 for no face yet) to `feel`'s, its mood line, which says
## more than yes or no; otherwise, or for a voice without that line, the tone's.
static func answer(voice: Dictionary, tone: String, before: int, feel: Dictionary) -> String:
	if before >= 0 and not feel.is_empty():
		var now := MoodBadge.emotion_of(feel)
		var mood := String(MOODS.get(now, ""))
		if now != before and voice.has(mood):
			return mood
	return reaction(tone)


## Shows `id`'s line of `voice` (lines() above) in `caption` and plays its clip
## under `parent`, in turn: while a line is still playing, the next waits for it to
## end (the newest one wins the wait), so the caption never says what the sound
## does not and Voice.speak's never-cut rule needs no change. A voice still talking
## under ANOTHER player (the chief under main, a desk messenger) is waited for too,
## and nothing waiting is dropped (the parent's call on #229, rule 4 across players).
static func say(parent: Node, caption: Label, voice: Dictionary, id: String) -> void:
	if id == "" or not voice.has(id):
		return
	if String(voice[id]["clip"]) != "" and (Voice.others_busy(parent) or parent.has_meta(WAITING)):
		_wait(parent, caption, voice, id)
		return
	var player := parent.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player != null and (player.playing or bool(player.get_meta("pending", false))):
		var waiting := not String(player.get_meta("next", "")).is_empty()
		# The voice waits beside its id: a scene reused for the next person must
		# not have its greeting read from the last one's lines (#222 pass 1).
		player.set_meta("next", id)
		player.set_meta("next_voice", voice)
		player.set_meta("next_caption", caption)
		if not waiting:
			player.finished.connect(_said_next.bind(parent, player), CONNECT_ONE_SHOT)
		return
	if caption == null:
		return
	caption.text = Strings.t("“%s”") % String(voice[id]["text"])
	caption.visible = true
	Voice.speak(parent, String(voice[id]["clip"]))


## The queued line, once the one playing has ended: read from the queue as it is
## now, so a newer caller's voice and caption win (#222 passes 1 and 2).
static func _said_next(parent: Node, player: AudioStreamPlayer) -> void:
	var next := String(player.get_meta("next", ""))
	var voice: Dictionary = player.get_meta("next_voice", {})
	var caption = player.get_meta("next_caption", null)
	_clear(player)
	# A queued line never plays into a scene that has gone. Defence only: Leave and
	# close_scene already hush the queue (#222 QA withdrew TAKE A, a harness timing).
	if is_instance_valid(parent) and parent is CanvasItem and not (parent as CanvasItem).is_visible_in_tree():
		return
	if is_instance_valid(parent) and is_instance_valid(caption):
		say(parent, caption, voice, next)


## In line behind another player's voice, in order: a Timer the parent owns polls
## (kept, stopped, once the line is empty -- Voice.speak_queued's reason).
static func _wait(parent: Node, caption: Label, voice: Dictionary, id: String) -> void:
	var waiting: Array = parent.get_meta(WAITING, [])
	waiting.append([caption, voice, id])
	parent.set_meta(WAITING, waiting)
	var wait := parent.get_node_or_null(WAIT) as Timer
	if wait == null:
		wait = Timer.new()
		wait.name = WAIT
		wait.one_shot = true
		wait.wait_time = Voice.QUEUE_POLL_S
		wait.timeout.connect(_waited.bind(parent, wait))
		parent.add_child(wait)
	if wait.is_stopped():
		wait.start()


## The other voice has ended: the waiting lines are said in order (the first plays,
## the next queue behind it on the parent's own player), unless the parent has gone
## from the screen, which cancels them.
static func _waited(parent: Node, wait: Timer) -> void:
	if not parent.has_meta(WAITING):
		return
	if Voice.others_busy(parent):
		wait.start()
		return
	var waiting: Array = parent.get_meta(WAITING)
	parent.remove_meta(WAITING)
	if parent is CanvasItem and not (parent as CanvasItem).is_visible_in_tree():
		return
	for line in waiting:
		if is_instance_valid(line[0]):
			say(parent, line[0], line[1], line[2])


## Drops the queued line and the one-shot waiting for it (an audience opening on
## someone new). With `stop`, the line playing ends too (the call is over):
## Voice.stop emits no `finished`, so the one-shot would fire on the next line.
static func hush(parent: Node, stop := false) -> void:
	if parent.has_meta(WAITING):
		parent.remove_meta(WAITING)
	var player := parent.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player == null:
		return
	_clear(player)
	for c in player.finished.get_connections():
		if (c["callable"] as Callable).get_method() == "_said_next":
			player.finished.disconnect(c["callable"])
	if stop:
		Voice.stop(parent)


static func _clear(player: AudioStreamPlayer) -> void:
	player.set_meta("next", "")
	player.set_meta("next_voice", {})
	player.set_meta("next_caption", null)
