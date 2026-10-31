extends PanelContainer

## The phone -- V5.2b b3. One call to one person: a single lever or topic, no
## diary day (v5.2b3-plan.md section 1). The verbs are the audience's own grid
## (audience_verbs.gd) over Phone.options()'s rows -- shaped like Levers.offered()'s,
## the odds already lowered by the call's penalty -- so a lever reads the same on
## the phone as across the desk: its range, its cost before the click, its refusal
## with the sim's reason ("too long a shot for a call", "not by phone").
##
## A call is ONE try: after it, the verbs come down and the result stays until
## Close. A call the sim refuses outright (already called this month) opens on
## its reason with nothing to press but Close.
##
## It writes nothing: a verb emits `dialed`, and the wiring calls Phone.dial().

signal dialed(lever_or_topic: String, args: Dictionary)
signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Words = preload("res://src/ui/lever_words.gd")
const AudienceVerbs = preload("res://src/ui/audience_verbs.gd")
const DialogueLines = preload("res://src/ui/dialogue_lines.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const AudienceVoice = preload("res://src/ui/audience_voice.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")

const SIZE := Vector2(760, 0)

var verbs := AudienceVerbs.new()
var _title: Label
var _line: Label
## V5.3-0 (c) 4.2: their voice on the line (AudienceVoice): greet, then agree or
## refuse. No farewell: the dialog is gone when the call ends, and a line not on
## screen is never played.
var _spoken: Label
var _why: Label
var _resource = null
var _view := {}
var _result: Label
## V5.2 close R5: the result's STATUS-toned word, inline before it (the scene's).
var _tone: Label
var _said: HBoxContainer
var _close: Button


func _ready() -> void:
	custom_minimum_size = SIZE
	var root := PanelKit.padded(self, 16, 10)
	_title = PanelKit.heading(root, "")
	# The person's own words (Content's phone_* titles, #126), above the verbs.
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_line)
	_spoken = Label.new()
	_spoken.name = "Spoken"  # i18n: ok a node name, found by tests
	_spoken.theme_type_variation = UiTheme.CAPTION
	_spoken.autowrap_mode = TextServer.AUTOWRAP_WORD
	_spoken.visible = false
	root.add_child(_spoken)
	_why = Label.new()
	_why.theme_type_variation = UiTheme.CAPTION
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_why)
	root.add_child(verbs)
	verbs.attempted.connect(func(lever: String, args: Dictionary) -> void: dialed.emit(lever, args))
	verbs.talked.connect(func(topic: String, args: Dictionary) -> void: dialed.emit(topic, args))
	_said = HBoxContainer.new()
	_said.add_theme_constant_override("separation", 10)
	root.add_child(_said)
	_tone = Label.new()
	_tone.name = "ResultTone"  # i18n: ok a node name, found by tests
	_tone.uppercase = true
	_tone.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_said.add_child(_tone)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_said.add_child(_result)
	_close = PanelKit.sized(Button.new())
	_close.text = tr("Close")
	# Through close(), as Escape is: the hush lives there (#222 QA T4: emitting
	# `closed` straight from the button left the greet playing after the hang-up).
	_close.pressed.connect(close)
	root.add_child(_close)


## `view`: {name, why_not (the call's own refusal, "" when it can be made), levers,
## topics (Phone.options()'s rows), choices (audience_verbs'), and for the lines:
## stance, ask (the open request's, "" for none), president}.
func open(view: Dictionary) -> void:
	_view = view
	_resource = DialogueLines.resource_for(String(view.get("stance", "")))
	# Hidden until a line is said: an empty Label still takes its row, a blank
	# line under the title on a call with nothing to ask (QA's RECORD 9).
	_line.text = ""
	_line.hide()
	_spoken.hide()
	AudienceVoice.say(self, _spoken, view.get("voice", {}), "greet")
	if String(view.get("ask", "")) != "" and String(view.get("why_not", "")) == "":
		speak(["phone_opening"], {})
	_title.text = tr("Call %s") % String(view.get("name", ""))  # i18n: row-ok the person's shown name, resolved by the wiring
	var why := String(view.get("why_not", ""))
	_why.show()
	_result.text = ""
	_result.hide()
	_said.hide()
	verbs.visible = why == ""
	# Without an open request the call has nothing to ask: the sim offers topics
	# only, and the line says why the levers are absent rather than leaving a gap.
	if why != "":
		_why.text = Words.reason(why)
	elif (view.get("levers", []) as Array).is_empty():
		_why.text = tr("They have asked you for nothing: talk, or hang up.")
	else:
		_why.text = tr("One try: a lever or a topic. The odds are lower than across a desk.")
	var choices: Dictionary = view.get("choices", {}).duplicate()
	choices["quiet"] = true  # one try, said above; no "attempts left" line
	verbs.show_verbs(view.get("levers", []), view.get("topics", []), 1, choices)
	show()


## The call is made: what it did, and the verbs down. `titles`: the lines it
## ends on, in the person's mouth (a lever's, then the call's close). `feel`: how
## they feel after it (Feelings.of), so a band the call crossed is said.
func show_result(text: String, titles: Array = [], extra := {}, tone := "", feel := {}) -> void:
	_result.text = text
	_result.visible = not text.is_empty()
	_said.visible = _result.visible
	ResultTone.apply(_tone, tone)
	var before: Dictionary = _view.get("choices", {}).get("feel", {})
	AudienceVoice.say(self, _spoken, _view.get("voice", {}), AudienceVoice.answer(_view.get("voice", {}), tone,
		MoodBadge.emotion_of(before) if not before.is_empty() else -1, feel))
	verbs.visible = false
	_why.text = ""
	_why.hide()
	if not titles.is_empty():
		speak(titles, extra)


## The person's lines for `titles`, one after the other; a title no file has is
## skipped.
func speak(titles: Array, extra: Dictionary) -> void:
	var state := {"name": String(_view.get("name", "")), "ask": String(_view.get("ask", "")),  # i18n: row-ok the person's shown name, resolved by the wiring
		"president": String(_view.get("president", "")), "lever": "", "topic": ""}
	state.merge(extra, true)
	var said := PackedStringArray()
	for title in titles:
		var one: String = await DialogueLines.line(_resource, String(title), state)
		if one != "":
			said.append(one)
	_line.text = " ".join(said)
	_line.visible = not said.is_empty()


## Escape's door, the stack's cancel: the same as Close.
func close() -> void:
	AudienceVoice.hush(self, true)  # the call is over: no line outlives it
	closed.emit()
