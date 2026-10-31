extends "res://src/ui/mood_icon.gd"

## V5.3-0 (c), 4.2: how a person feels about the president, as a mood icon on the
## corner of their face (person card, audience, request column, desk speaker,
## People, the chief). The author asked for faces that react WITHOUT generated
## expressions: the badge is drawn, and the met cast's five mood portraits (V5.2,
## #106-#110) show only where one exists.
##
## The mood reads Feelings.band(), the cut the card's own words read, so the badge
## and the word cannot disagree; its tooltip IS those words, so colour and mouth
## are never the only sign.

const Feelings = preload("res://src/ui/feelings.gd")

## Grudge bands (Feelings.BANDS): 1 annoyed, 2 resentful and up. Rapport: 0 cold,
## 1 wary, 3 warm and up. Indices, not figures: a cut moved in Feelings moves here.
const GRUDGE_SORE := 1
const GRUDGE_HOSTILE := 2
const RAPPORT_COLD := 0
const RAPPORT_WARY := 1
const RAPPORT_WARM := 3


## Portrait.Emotion for `feel` (Feelings.of()): STERN for a cold or resentful
## person, WORRIED for a wary or annoyed one, PLEASED for a warm one, else NEUTRAL.
static func emotion_of(feel: Dictionary) -> int:
	var grudge := Feelings.band("grudge", float(feel.get("grudge", 0.0)))
	var rapport := Feelings.band("rapport", float(feel.get("rapport", 0.0)))
	if grudge >= GRUDGE_HOSTILE or rapport == RAPPORT_COLD:
		return Portrait.Emotion.STERN
	if grudge >= GRUDGE_SORE or rapport == RAPPORT_WARY:
		return Portrait.Emotion.WORRIED
	if rapport >= RAPPORT_WARM:
		return Portrait.Emotion.PLEASED
	return Portrait.Emotion.NEUTRAL


## The badge's words: the person's rapport and grudge words, as their card says them.
static func words_of(feel: Dictionary) -> String:
	var said := PackedStringArray()
	for register in ["rapport", "grudge"]:
		var word := Feelings.word(register, float(feel.get(register, 0.0)))
		if word != "":
			said.append(word)
	return Strings.t("Feels: %s") % ", ".join(said)


## `face` with the badge on its lower-right corner, the badge `side` pixels wide;
## a face that already wears one (a reused slot) has it re-read. Returns `face`,
## so a caller wraps the line that builds it.
static func wear(face: Control, feel: Dictionary, side := 18.0) -> Control:
	var badge = face.get_node_or_null("MoodBadge")
	if badge == null:
		badge = new()
		badge.name = "MoodBadge"  # i18n: ok a node name, found by tests
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		face.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -side
		badge.offset_top = -side
	badge.custom_minimum_size = Vector2(side, side)
	badge.emotion = emotion_of(feel)
	badge.tooltip_text = words_of(feel)
	return face


## The person's face for `feel`: their mood portrait where the art exists, the
## neutral one otherwise (never the silhouette for a mood the art lacks).
static func mood_portrait(person_id: String, feel: Dictionary) -> int:
	var emotion := emotion_of(feel)
	if emotion != Portrait.Emotion.NEUTRAL and Portrait.texture_for(person_id, emotion) != null:
		return emotion
	return Portrait.Emotion.NEUTRAL


func _ready() -> void:
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	# A disc of the panel ground under the glyph, so it reads on any photograph.
	draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, UiTheme.HULL)
	super._draw()
