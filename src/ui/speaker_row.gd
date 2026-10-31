extends RefCounted

## The face on an event's decision card -- V5.2d, docs/design/v5.2-d-spec.md section 3:
## who brings the news to the president, their portrait, their name and their line.
## The person is Speakers.resolve()'s, stored on the desk entry at delivery
## (entry["speaker"], a person id) so the face does not change while the card waits;
## no id, or an event with no written line, is the narrator and gets no row. The line
## is a variable-free sentence (the voice pipeline voices it), read through Strings.

const Portrait = preload("res://src/ui/portrait.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")
const Feelings = preload("res://src/ui/feelings.gd")

const FACE := Vector2(36, 50)


## The row for `entry` of `ev`, or null for the narrator.
static func build(loader, ev, entry: Dictionary, ns = null):
	var person_id := String(entry.get("speaker", ""))
	var line := Strings.row("events", String(ev.id), "speaker_line", String(ev.speaker_line)).strip_edges()
	# An id the content no longer names (a load) is the narrator too, never a nameless face.
	if person_id == "" or line == "" or loader.person_name(person_id) == "":
		return null
	var row := HBoxContainer.new()
	row.name = "Speaker"  # i18n: ok a node name, found by tests
	row.add_theme_constant_override("separation", 8)
	# V5.3-0 (c) 4.2: how the messenger feels about you, when the nation is known.
	var face := Portrait.control_for(person_id, FACE)
	row.add_child(MoodBadge.wear(face, Feelings.of(ns, person_id), 14.0) if ns != null else face)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)
	var who := Label.new()
	who.text = loader.person_name(person_id)
	who.theme_type_variation = UiTheme.CAPTION
	words.add_child(who)
	PanelKit.plain_line(words, line, PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return row
