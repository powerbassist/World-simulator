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
## V5.2c: the money on the table answered, an affair proposed or ended.
signal offer_answered(accepted: bool)
signal affair(action: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Strings = preload("res://src/ui/strings.gd")
const Words = preload("res://src/ui/lever_words.gd")
const AudienceVerbs = preload("res://src/ui/audience_verbs.gd")
const AudienceShadow = preload("res://src/ui/audience_shadow.gd")
const DialogueLines = preload("res://src/ui/dialogue_lines.gd")
const PartyChip = preload("res://src/ui/party_chip.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")

## 16:9, the board's scene window over the map.
const SIZE := Vector2(1120, 630)

## The person in the chair while a scene runs, "" otherwise: the clock's hold line
## names them (hold_reason.gd, the summit's `visiting` seam).
var visiting := ""
var verbs := AudienceVerbs.new()
var shadow := AudienceShadow.new()

var _view: Dictionary = {}
var _resource = null
var _face: Control
var _speaker: Label
## V5.2 close R3: the person's party beside their name, said and swatched.
var _party: HBoxContainer
var _line: Label
var _fog: Label
var _traits: Label
var _result: Label
## V5.2 close R5: how the last result landed, a STATUS-toned word before it.
var _tone: Label
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
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	talk.add_child(head)
	_speaker = Label.new()
	_speaker.theme_type_variation = UiTheme.MICRO
	head.add_child(_speaker)
	_party = HBoxContainer.new()
	head.add_child(_party)
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
	talk.add_child(shadow)
	shadow.offer_answered.connect(func(accepted: bool) -> void: offer_answered.emit(accepted))
	shadow.affair.connect(func(action: String) -> void: affair.emit(action))
	var said := HBoxContainer.new()
	said.add_theme_constant_override("separation", 10)
	talk.add_child(said)
	_tone = Label.new()
	_tone.name = "ResultTone"  # i18n: ok a node name, found by tests
	_tone.uppercase = true
	_tone.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	said.add_child(_tone)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	said.add_child(_result)
	ResultTone.apply(_tone, "")
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
	_resource = DialogueLines.resource_for(String(view.get("stance", "")))
	for child in _face.get_children():
		child.queue_free()
	var person_id := String(view.get("person_id", ""))
	if person_id != "":
		_face.add_child(Portrait.framed_for(person_id, _face.custom_minimum_size, Portrait.Emotion.NEUTRAL,
			Portrait.scene_from_name("office")))
	_result.text = ""
	ResultTone.apply(_tone, "")
	for child in _party.get_children():
		child.queue_free()
	# A view without the key (a test's, the phone's) shows no party line at all;
	# the lane's row always carries it, {} for a person with none.
	if view.has("party"):
		_party.add_child(PartyChip.make(view["party"]))
	_show_state(view)
	say(String(view.get("opening_title", "opening")), {})
	_say_offer(view)


## After a verb: the sim's result in words, the levers' new ranges, what is left.
## `view` carries the fresh fog, traits, offered, topics and attempts_left; `tone`
## is a ResultTone key, "" for a result that is neither good nor bad news.
func show_result(text: String, view: Dictionary, title: String, extra := {}, tone := "") -> void:
	_result.text = text
	ResultTone.apply(_tone, tone)
	_show_state(view)
	if title != "":
		say(title, extra)


## The sim has closed the audience: its outcome, said; every verb down; one way out.
func show_close(outcome: String, text: String, tone := "") -> void:
	_over = true
	_result.text = text
	ResultTone.apply(_tone, tone)
	verbs.show_verbs([], [], 0, {})
	verbs.visible = false
	shadow.visible = false
	_end.text = tr("Leave")
	say(DialogueLines.close_title(_view, outcome), {})


func close_scene() -> void:
	visiting = ""
	_view = {}
	verbs.visible = true
	shadow.visible = true


func _show_state(view: Dictionary) -> void:
	_fog.text = Words.fog(String(view.get("fog", Words.FOG_DEFAULT)))
	var traits: Array = view.get("traits", [])
	_traits.text = tr("What you know of them: %s.") % ", ".join(PackedStringArray(traits)) if not traits.is_empty() else tr("You know nothing of their character yet.")
	verbs.show_verbs(view.get("offered", []), view.get("topics", []), int(view.get("attempts_left", 0)), view.get("choices", {}))
	shadow.show_for(view)


## The money a request came with, in the person's own words (Content's
## offer_<kind>_<currency> title) beside the opening, which keeps the ask.
func _say_offer(view: Dictionary) -> void:
	var offer: Dictionary = view.get("shadow", {}).get("offer", {})
	shadow.set_offer_line("")
	if offer.is_empty():
		return
	var state := {"name": String(view.get("name", "")), "ask": String(view.get("ask", "")),  # i18n: row-ok the person's shown name, resolved by the wiring
		"president": String(view.get("president", "")), "lever": "", "topic": ""}
	var asked := String(view.get("request_id", ""))
	var said: String = await DialogueLines.line(_resource, "offer_%s_%s" % [String(view["shadow"].get("kind", "")), String(offer.get("currency", ""))], state)
	# The line is awaited: the audience it was asked for may be gone by now.
	if String(_view.get("request_id", "")) == asked:
		shadow.set_offer_line(said)


## One title of the person's lines, through the addon; a title the files lack is
## a plain line in the person's mouth, so a missing line never stops the scene.
func say(title: String, extra: Dictionary) -> void:
	var state := {"name": String(_view.get("name", "")), "ask": String(_view.get("ask", "")),  # i18n: row-ok the person's shown name, resolved by the wiring
		"president": String(_view.get("president", "")), "lever": "", "topic": ""}
	state.merge(extra, true)
	_speaker.text = String(state["name"])  # i18n: row-ok the person's shown name, resolved by the wiring
	var said: String = await DialogueLines.line(_resource, title, state)
	# No line for the title: the opening says the ask bare, anything else nothing.
	_line.text = said if said != "" or not title.ends_with("opening") else String(state["ask"])
