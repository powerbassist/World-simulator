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
## sim (Levers.attempt / talk / close) and hands the result back to `show_result`.

signal attempted(lever: String)
signal talked(topic: String)
signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

const DIALOGUE_DIR := "res://data/audiences/"
## 16:9, the board's scene window over the map.
const SIZE := Vector2(1120, 630)

const LEVER_LABEL := {
	"argue": "Argue", "bargain": "Bargain", "promise_date": "Promise a date",  # i18n: msgid
	"pressure": "Pressure", "flatter": "Flatter", "friendship": "Appeal to friendship",  # i18n: msgid
}
const TOPIC_LABEL := {
	"family": "Family", "opinion": "Their opinion", "gossip": "Gossip",  # i18n: msgid
	"dinner": "Dinner", "flirt": "Flirt",  # i18n: msgid
}
## The fog the scene assumes when the sim names none: the widest.
const FOG_DEFAULT := "stranger"
const FOG_LABEL := {
	"stranger": "a stranger -- the odds are a wide guess",  # i18n: msgid
	"acquaintance": "an acquaintance -- the odds are a rough guess",  # i18n: msgid
	"known": "known to you -- the odds are close",  # i18n: msgid
}

## The person in the chair while a scene runs, "" otherwise: the clock's hold line
## names them (hold_reason.gd, the summit's `visiting` seam).
var visiting := ""

var _view: Dictionary = {}
var _resource = null
var _face: Control
var _speaker: Label
var _line: Label
var _fog: Label
var _levers: GridContainer
var _topics: HFlowContainer
var _attempts: Label
var _result: Label
var _talk_heading: Label


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
	_levers = GridContainer.new()
	_levers.columns = 3
	_levers.add_theme_constant_override("h_separation", 16)
	talk.add_child(_levers)
	_attempts = Label.new()
	_attempts.theme_type_variation = UiTheme.CAPTION
	talk.add_child(_attempts)
	_talk_heading = PanelKit.heading(talk, tr("Or talk"))
	_topics = PanelKit.buttons(talk)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD
	talk.add_child(_result)
	var close := PanelKit.sized(Button.new())
	close.text = tr("End the audience")
	close.pressed.connect(func() -> void: closed.emit())
	root.add_child(close)


## `view`: {request_id, person_id, name, ask, stance, president, fog ("stranger" |
## "acquaintance" | "known"), offered (Levers.offered()'s rows), topics
## (Levers.topics()'s rows, each {topic, offered, why_not}), attempts_left}.
func open(view: Dictionary) -> void:
	_view = view
	visiting = String(view.get("name", ""))  # i18n: row-ok the person's shown name, resolved by the wiring
	_resource = _load_dialogue(String(view.get("stance", "")))
	for child in _face.get_children():
		child.queue_free()
	var person_id := String(view.get("person_id", ""))
	if person_id != "":
		_face.add_child(Portrait.framed_for(person_id, _face.custom_minimum_size, Portrait.Emotion.NEUTRAL,
			Portrait.scene_from_name("office")))
	_fog.text = tr("They are %s.") % tr(String(FOG_LABEL.get(String(view.get("fog", FOG_DEFAULT)), "")))
	_result.text = ""
	_fill_verbs(view.get("offered", []), view.get("topics", []), int(view.get("attempts_left", 3)))
	say("opening", {})


## After a verb: the sim's result in words, the levers' new odds, what is left.
func show_result(text: String, offered: Array, attempts_left: int, title: String, extra := {}) -> void:
	_result.text = text
	_fill_verbs(offered, _view.get("topics", []), attempts_left)
	say(title, extra)


func close_scene() -> void:
	visiting = ""
	_view = {}


func _fill_verbs(offered: Array, topics: Array, attempts_left: int) -> void:
	for box in [_levers, _topics]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	for row in offered:
		var button := PanelKit.sized(Button.new())
		button.text = tr(String(LEVER_LABEL.get(String(row["lever"]), String(row["lever"]))))
		button.disabled = attempts_left <= 0 or not bool(row.get("offered", false))
		button.tooltip_text = String(row.get("why_not", "")) if not bool(row.get("offered", false)) else ""
		var lever := String(row["lever"])
		button.pressed.connect(func() -> void: attempted.emit(lever))
		_levers.add_child(button)
		var odds := Label.new()
		odds.text = odds_text(float(row.get("odds_lo", 0.0)), float(row.get("odds_hi", 0.0)))
		_levers.add_child(odds)
		_levers.add_child(_spends_label(row.get("spends", {})))
	# No levers offered at all (before the sim's levers exist, or none fit): the
	# audience is heard, not argued -- saying "no attempts left" would be a lie.
	if offered.is_empty():
		_attempts.text = tr("Hear them out, then end the audience.")
	elif attempts_left > 0:
		_attempts.text = tr_n("%d attempt left", "%d attempts left", attempts_left) % attempts_left
	else:
		_attempts.text = tr("No attempts left: end the audience.")
	_talk_heading.visible = not topics.is_empty()
	for row in topics:
		var button := Button.new()
		button.text = tr(String(TOPIC_LABEL.get(String(row["topic"]), String(row["topic"]))))
		button.disabled = not bool(row.get("offered", true))
		button.tooltip_text = String(row.get("why_not", ""))
		var topic := String(row["topic"])
		button.pressed.connect(func() -> void: talked.emit(topic))
		_topics.add_child(button)


## A range, never a point: what the president cannot know about the person is the
## width (B4). Text tokens only -- odds are no good or bad news.
static func odds_text(lo: float, hi: float) -> String:
	return Strings.t("%s–%s %%") % [Num.f(lo * 100.0, 0), Num.f(hi * 100.0, 0)]


func _spends_label(spends: Dictionary) -> Label:
	var label := Label.new()
	label.theme_type_variation = UiTheme.CAPTION
	var parts := PackedStringArray()
	for key in spends.keys():
		parts.append("%s %s" % [String(key).replace("_", " "), Num.fs(float(spends[key]), 2)])  # i18n: row-ok a register key, shown as is until its label lands
	label.text = ", ".join(parts)
	return label


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
