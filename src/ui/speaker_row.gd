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

const FACE := Vector2(36, 50)


## The row for `entry` of `ev`, or null for the narrator.
static func build(loader, ev, entry: Dictionary):
	var person_id := String(entry.get("speaker", ""))
	var line := Strings.row("events", String(ev.id), "speaker_line", String(ev.speaker_line)).strip_edges()
	if person_id == "" or line == "":
		return null
	var row := HBoxContainer.new()
	row.name = "Speaker"  # i18n: ok a node name, found by tests
	row.add_theme_constant_override("separation", 8)
	row.add_child(Portrait.control_for(person_id, FACE))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)
	var who := Label.new()
	who.text = loader.person_name(person_id).to_upper()
	who.theme_type_variation = UiTheme.MICRO
	words.add_child(who)
	PanelKit.plain_line(words, line, PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return row
