extends PanelContainer

## The audience -- V5.2b. A person of the played nation sits across the desk and
## asks for what they want; the president has three attempts to move them, each a
## lever with its odds shown as a RANGE as wide as the president's ignorance of the
## person (B4: the true odds are always inside it), and the topics that buy
## knowledge and rapport. A scene: it owns the screen and holds the clock (the
## screen stack's SCENE rank, summit_panel's shape); the request card that led here
## never did.
##
## The frame is the summit's: the face, the speaker's line, the verbs. The LINES
## come from DialogueManager (the project's stated autoload exception, V2.4b) over
## data/audiences/*.dialogue -- Content's, one file a request stance overriding
## default.dialogue title by title, with {{name}}, {{ask}}, {{president}}, {{lever}}
## and {{topic}} in scope. A title neither file has falls back to a plain line, so
## the scene plays while the lines are being written.
##
## The panel never touches state: each verb is a signal, and the wiring calls the
## sim (Levers.attempt / talk / close) and hands the result back. Ending is two
## clicks apart on purpose: End closes the audience in the sim and shows its
## outcome in the person's mouth; Leave takes the scene down.

signal attempted(lever: String, args: Dictionary)
signal talked(topic: String, args: Dictionary)
signal ended
signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Strings = preload("res://src/ui/strings.gd")
const Words = preload("res://src/ui/lever_words.gd")
const AudienceVerbs = preload("res://src/ui/audience_verbs.gd")

const DIALOGUE_DIR := "res://data/audiences/"
## 16:9, the board's scene window over the map.
const SIZE := Vector2(1120, 630)

## The person in the chair while a scene runs, "" otherwise: the clock's hold line
## names them (hold_reason.gd, the summit's `visiting` seam).
var visiting := ""
var verbs := AudienceVerbs.new()

var _view: Dictionary = {}
var _resource = null
var _face: Control
var _speaker: Label
var _line: Label
var _fog: Label
var _traits: Label
var _result: Label
var _end: Button
var _over := false


func _ready() -> void:
	custom_minimum_size = SIZE
	var root := PanelKit.padded(self, 16, 10)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_face = Control.new()
	_face.custom_minimum_size = Vector2(220, 302)
	body.add_child(_face)
	var talk := VBoxContainer.new()
	talk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talk.add_theme_constant_override("separation", 8)
	body.add_child(talk)
	_speaker = Label.new()
	_speaker.theme_type_variation = UiTheme.MICRO
	talk.add_child(_speaker)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	talk.add_child(_line)
	_fog = Label.new()
	_fog.theme_type_variation = UiTheme.CAPTION
	talk.add_child(_fog)
	_traits = Label.new()
	_traits.theme_type_variation = UiTheme.CAPTION
	talk.add_child(_traits)
	talk.add_child(verbs)
	verbs.attempted.connect(func(lever: String, args: Dictionary) -> void: attempted.emit(lever, args))
	verbs.talked.connect(func(topic: String, args: Dictionary) -> void: talked.emit(topic, args))
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD
	talk.add_child(_result)
	_end = PanelKit.sized(Button.new())
	_end.pressed.connect(func() -> void:
		if _over:
			closed.emit()
		else:
			ended.emit())
	root.add_child(_end)


## `view`: {request_id, person_id, name, ask, stance, president, fog ("stranger" |
## "acquaintance" | "known"), traits (shown words), offered (Levers.offered()'s
## rows), topics (Levers.topics()'s), attempts_left, choices (audience_verbs')}.
func open(view: Dictionary) -> void:
	_view = view
	_over = false
	_end.text = tr("End the audience")
	visiting = String(view.get("name", ""))  # i18n: row-ok the person's shown name, resolved by the wiring
	_resource = _load_dialogue(String(view.get("stance", "")))
	for child in _face.get_children():
		child.queue_free()
	var person_id := String(view.get("person_id", ""))
	if person_id != "":
		_face.add_child(Portrait.framed_for(person_id, _face.custom_minimum_size, Portrait.Emotion.NEUTRAL,
			Portrait.scene_from_name("office")))
	_result.text = ""
	_show_state(view)
	say("opening", {})


## After a verb: the sim's result in words, the levers' new ranges, what is left.
## `view` carries the fresh fog, traits, offered, topics and attempts_left.
func show_result(text: String, view: Dictionary, title: String, extra := {}) -> void:
	_result.text = text
	_show_state(view)
	if title != "":
		say(title, extra)


## The sim has closed the audience: its outcome, said; every verb down; one way out.
func show_close(outcome: String, text: String) -> void:
	_over = true
	_result.text = text
	verbs.show_verbs([], [], 0, {})
	verbs.visible = false
	_end.text = tr("Leave")
	say("close_" + outcome, {})


func close_scene() -> void:
	visiting = ""
	_view = {}
	verbs.visible = true


func _show_state(view: Dictionary) -> void:
	_fog.text = Words.fog(String(view.get("fog", Words.FOG_DEFAULT)))
	var traits: Array = view.get("traits", [])
	_traits.text = tr("What you know of them: %s.") % ", ".join(PackedStringArray(traits)) if not traits.is_empty() else tr("You know nothing of their character yet.")
	verbs.show_verbs(view.get("offered", []), view.get("topics", []), int(view.get("attempts_left", 0)), view.get("choices", {}))


## One title of the person's lines, through the addon; a title the files lack is
## a plain line in the person's mouth, so a missing line never stops the scene.
func say(title: String, extra: Dictionary) -> void:
	var state := {"name": String(_view.get("name", "")), "ask": String(_view.get("ask", "")),  # i18n: row-ok the person's shown name, resolved by the wiring
		"president": String(_view.get("president", "")), "lever": "", "topic": ""}
	state.merge(extra, true)
	_speaker.text = String(state["name"])  # i18n: row-ok the person's shown name, resolved by the wiring
	var manager = _manager()
	if _resource != null and manager != null and _resource.titles.has(title):
		var line = await manager.get_next_dialogue_line(_resource, title, [state])
		if line != null:
			_line.text = String(line.text)
			return
	_line.text = String(state["ask"]) if title == "opening" else ""


## The stance's file over the default, merged title by title (a title twice is a
## compile error, so the stance's block replaces the default's).
func _load_dialogue(stance: String):
	var manager = _manager()
	if manager == null:
		return null
	var blocks := titled_blocks(FileAccess.get_file_as_string(DIALOGUE_DIR + "default.dialogue"))
	var own := DIALOGUE_DIR + stance + ".dialogue"
	if stance != "" and FileAccess.file_exists(own):
		blocks.merge(titled_blocks(FileAccess.get_file_as_string(own)), true)
	if blocks.is_empty():
		return null
	return manager.create_resource_from_text("\n".join(PackedStringArray(blocks.values())))


## A .dialogue file cut at its "~ title" lines: title -> its block, title line included.
static func titled_blocks(text: String) -> Dictionary:
	var blocks := {}
	var title := ""
	for line in text.split("\n"):
		if line.begins_with("~ "):
			title = line.substr(2).strip_edges()
			blocks[title] = ""
		if title != "":
			blocks[title] += line + "\n"
	return blocks


func _manager():
	if Engine.has_singleton("DialogueManager"):
		return Engine.get_singleton("DialogueManager")
	return get_node_or_null("/root/DialogueManager")
