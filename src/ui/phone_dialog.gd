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

const SIZE := Vector2(760, 0)

var verbs := AudienceVerbs.new()
var _title: Label
var _why: Label
var _result: Label
var _close: Button


func _ready() -> void:
	custom_minimum_size = SIZE
	var root := PanelKit.padded(self, 16, 10)
	_title = PanelKit.heading(root, "")
	_why = Label.new()
	_why.theme_type_variation = UiTheme.CAPTION
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_why)
	root.add_child(verbs)
	verbs.attempted.connect(func(lever: String, args: Dictionary) -> void: dialed.emit(lever, args))
	verbs.talked.connect(func(topic: String, args: Dictionary) -> void: dialed.emit(topic, args))
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_result)
	_close = PanelKit.sized(Button.new())
	_close.text = tr("Close")
	_close.pressed.connect(func() -> void: closed.emit())
	root.add_child(_close)


## `view`: {name, why_not (the call's own refusal, "" when it can be made), levers,
## topics (Phone.options()'s rows), choices (audience_verbs')}.
func open(view: Dictionary) -> void:
	_title.text = tr("Call %s") % String(view.get("name", ""))  # i18n: row-ok the person's shown name, resolved by the wiring
	var why := String(view.get("why_not", ""))
	_result.text = ""
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


## The call is made: what it did, and the verbs down.
func show_result(text: String) -> void:
	_result.text = text
	verbs.visible = false
	_why.text = ""


## Escape's door, the stack's cancel: the same as Close.
func close() -> void:
	closed.emit()
