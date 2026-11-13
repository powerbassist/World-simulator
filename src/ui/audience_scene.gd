extends PanelContainer

## The audience -- V5.3, the author's C4 and C4-talk. A person of the played nation sits across the
## desk and asks for what they want: her face and her line, the ask in one sentence, then THREE
## cards (Grant / Counter / Refuse, audience_cards.gd). A deal struck, the cards give way to what it
## did and the conversation (audience_talk_view.gd): a few lines, only the ones that have a reason
## to be there. A refusal ends it: her parting line, what it cost, the way out. The scene owns the
## screen and holds the clock (the screen stack's SCENE rank, summit_panel's shape).
##
## Its states are audience_flow.gd's, in one table; this file draws the state the flow is in and
## moves it only by that table's events. It never touches the sim: each verb is a signal, the
## wiring (audience_talks.gd, audience_ask.gd) calls the sim and hands the result back through
## show_result() / show_close(), with a `view` carrying what the sim now reads. The lines come
## from DialogueManager over data/audiences/*.dialogue; a title the files lack falls back to a
## plain line, so the scene plays while the lines are being written.

signal granted
signal countered(date: Dictionary)
signal asked(line_id: String, topic: String, args: Dictionary)
signal ended
signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const AudienceFlow = preload("res://src/ui/audience_flow.gd")
const AudienceCards = preload("res://src/ui/audience_cards.gd")
const AudienceTalkView = preload("res://src/ui/audience_talk_view.gd")
const Words = preload("res://src/ui/audience_words.gd")
const DialogueLines = preload("res://src/ui/dialogue_lines.gd")
const PartyChip = preload("res://src/ui/party_chip.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")
const AudienceVoice = preload("res://src/ui/audience_voice.gd")
const Icon = preload("res://src/ui/icon.gd")

## The mockup's dialog: 1160 wide, as tall as its content.
const SIZE := Vector2(1160, 0)
const FACE := Vector2(190, 240)
const ICONS := "res://assets/icons/material/"

## The person in the chair while a scene runs, "" otherwise: the clock's hold line names them.
var visiting := ""
var flow := AudienceFlow.new()
var cards := AudienceCards.new()
var talk := AudienceTalkView.new()

var _view: Dictionary = {}
var _resource = null
var _face: Control
var _spoken: Label
var _voice: Dictionary = {}
var _speaker: Label
var _party: HBoxContainer
var _line: Label
var _lead: Label
var _band: PanelContainer
var _tone: Label
var _result: Label
var _band_lines: VBoxContainer
var _end: Button
var _pending := ""
## The talk's rows being built: a newer build discards an older one still awaiting its lines.
var _build := 0


func _ready() -> void:
	custom_minimum_size = SIZE
	var root := PanelKit.padded(self, 24, 14)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	root.add_child(top)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	top.add_child(side)
	_face = Control.new()
	_face.custom_minimum_size = FACE
	side.add_child(_face)
	_spoken = Label.new()
	_spoken.name = "Spoken"  # i18n: ok a node name, found by tests
	_spoken.theme_type_variation = UiTheme.CAPTION
	_spoken.autowrap_mode = TextServer.AUTOWRAP_WORD
	_spoken.custom_minimum_size.x = FACE.x
	_spoken.visible = false
	side.add_child(_spoken)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 10)
	top.add_child(words)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	words.add_child(head)
	_speaker = Label.new()
	_speaker.theme_type_variation = UiTheme.MICRO
	_speaker.uppercase = true
	head.add_child(_speaker)
	_party = HBoxContainer.new()
	head.add_child(_party)
	_line = Label.new()
	_line.theme_type_variation = UiTheme.FIGURE
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	words.add_child(_line)
	_lead = Label.new()
	_lead.name = "Lead"  # i18n: ok a node name, found by tests
	_lead.theme_type_variation = UiTheme.CAPTION
	_lead.autowrap_mode = TextServer.AUTOWRAP_WORD
	words.add_child(_lead)
	_band = PanelContainer.new()
	_band.theme_type_variation = UiTheme.PLATE
	words.add_child(_band)
	var band_box := PanelKit.padded(_band, 12, 6)
	var band_head := HBoxContainer.new()
	band_head.add_theme_constant_override("separation", 12)
	band_box.add_child(band_head)
	_tone = Label.new()
	_tone.name = "ResultTone"  # i18n: ok a node name, found by tests
	_tone.uppercase = true
	_tone.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	band_head.add_child(_tone)
	_result = Label.new()
	_result.theme_type_variation = UiTheme.LEAD
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	band_head.add_child(_result)
	_band_lines = VBoxContainer.new()
	_band_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_band_lines.add_theme_constant_override("separation", 3)
	band_box.add_child(_band_lines)
	root.add_child(cards)
	cards.granted.connect(func() -> void: granted.emit())
	cards.countered.connect(func(date: Dictionary) -> void: countered.emit(date))
	cards.refused.connect(func() -> void: ended.emit())
	cards.date_picked.connect(func(date: Dictionary) -> void: flow.date = date)
	cards.date_opened.connect(func() -> void: flow.fire("open_date"))
	cards.date_closed.connect(func() -> void: flow.fire("close_date"))
	root.add_child(talk)
	talk.asked.connect(func(line_id: String, topic: String, args: Dictionary) -> void:
		_pending = line_id
		if args.has("about"):
			flow.pick(line_id, String(args["about"]))
		asked.emit(line_id, topic, args))
	_end = PanelKit.sized(Button.new())
	_end.custom_minimum_size.x = AudienceCards.BUTTON_WIDTH
	# The way out sits where the cards' buttons sit: the dialog's own left padding.
	_end.pressed.connect(func() -> void:
		if flow.state == AudienceFlow.S.REFUSED:
			flow.fire("end")
			_over()
		else:
			ended.emit())
	root.add_child(_end)


## `view`: {request_id, person_id, name, ask, stance, president, party, voice, opening_title,
## choices.feel, question (AudienceWords.question), counter_default, struck, struck_lines, talk (the
## ranked rows, resolved), refused_lines}.
func open(view: Dictionary) -> void:
	_view = view
	flow = AudienceFlow.new()
	visiting = String(view.get("name", ""))  # i18n: row-ok the person's shown name, resolved by the wiring
	_resource = DialogueLines.resource_for(String(view.get("stance", "")))
	for child in _face.get_children():
		_face.remove_child(child)
		child.queue_free()
	var person_id := String(view.get("person_id", ""))
	if person_id != "":
		var feel: Dictionary = view.get("choices", {}).get("feel", {})
		_face.add_child(Portrait.framed_for(person_id, _face.custom_minimum_size, MoodBadge.mood_portrait(person_id, feel),
			Portrait.scene_from_name("office")))
		_badge(view)
	_voice = view.get("voice", {})
	_spoken.visible = false
	AudienceVoice.hush(self)
	AudienceVoice.say(self, _spoken, _voice, "greet")
	for child in _party.get_children():
		child.queue_free()
	if view.has("party"):
		_party.add_child(PartyChip.make(view["party"]))
	_render(_view)
	say(String(view.get("opening_title", "opening")), {})


## After a verb: the sim's result in words (the band's head), what the sim now reads (`view`),
## the title of her answer, and how it landed. A line asked and answered is marked asked.
func show_result(text: String, view: Dictionary, title: String, extra := {}, tone := "") -> void:
	_view.merge(view, true)  # the face, the name and the party stay: a result's view carries only what changed
	flow.sync(bool(view.get("struck", false)))
	flow.fire("close_date")  # a Counter she did not take is back on the question, with the date kept
	if _pending != "":
		if tone != ResultTone.BLOCKED:
			flow.ask(_pending)
		_pending = ""
	_result.text = text
	ResultTone.apply(_tone, tone)
	var badge = _face.get_node_or_null("MoodBadge")
	AudienceVoice.say(self, _spoken, _voice, AudienceVoice.answer(_voice, tone, badge.emotion if badge != null else -1,
		view.get("choices", {}).get("feel", {})))
	_render(_view)
	_badge(_view)
	if title != "":
		say(title, extra)


## The sim has closed the audience. From the question, that is a refusal: her parting line, what it
## cost and the way out. From the talk, it is the end: the scene comes down at once.
func show_close(outcome: String, text: String, tone := "") -> void:
	_result.text = text
	ResultTone.apply(_tone, tone)
	AudienceVoice.say(self, _spoken, _voice, "farewell")
	say(DialogueLines.close_title(_view, outcome), {})
	if flow.fire("refuse"):
		_render(_view)
	elif flow.fire("end"):
		_over()


func close_scene() -> void:
	AudienceVoice.hush(self)
	visiting = ""
	_view = {}


## The flow is at ENDED: the scene's own farewell goes with it.
func _over() -> void:
	AudienceVoice.hush(self)
	closed.emit()


## What the flow's state shows: the cards, the deal's band with the talk, or the refusal's.
func _render(view: Dictionary) -> void:
	flow.sync(bool(view.get("struck", false)))
	var state := flow.state
	var asking := state == AudienceFlow.S.QUESTION or state == AudienceFlow.S.COUNTER_OPEN
	cards.visible = asking
	talk.visible = flow.in_talk()
	_lead.visible = asking
	_band.visible = not asking
	_end.visible = not asking
	_end.text = tr("That will be all") if flow.in_talk() else tr("End the audience")
	if asking:
		_lead.text = String(view.get("question", {}).get("lead", ""))
		if not view.is_empty() and view.has("question"):
			cards.show_question(view["question"], flow.date, view.get("counter_default", {}))
		return
	if state == AudienceFlow.S.REFUSED:
		_lines(view.get("refused_lines", []))
	else:
		_lines(view.get("struck_lines", []))
		if not flow.ranked and view.has("talk"):
			flow.lines = view["talk"]
			flow.ranked = true
		_fill_talk(view)


func _lines(rows: Array) -> void:
	for child in _band_lines.get_children():
		_band_lines.remove_child(child)
		child.queue_free()
	for row in rows:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		_band_lines.add_child(cell)
		var glyph := String(row["glyph"])
		var tone := String(row["tone"])
		var colour := UiTheme.GOOD if tone == Words.GOOD else (UiTheme.BAD if tone == Words.BAD else UiTheme.TEXT_DIM)
		if glyph.length() > 2:
			var picture := TextureRect.new()
			picture.texture = Icon.load_icon(ICONS + glyph + ".svg", colour, 16)
			picture.custom_minimum_size = Vector2(16, 16)
			cell.add_child(picture)
		else:
			var sign_label := Label.new()
			sign_label.text = glyph
			sign_label.theme_type_variation = UiTheme.GOOD_SMALL if tone == Words.GOOD else (UiTheme.BAD_SMALL if tone == Words.BAD else UiTheme.CAPTION)
			cell.add_child(sign_label)
		var text := Label.new()
		text.text = String(row["text"])  # i18n: row-ok words built by audience_words.gd
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(text)


## The talk's rows, their sentences from the dialogue (a title the files lack: a plain line), each
## with what the flow remembers: asked, and the face picked. Built once the lines are in.
func _fill_talk(view: Dictionary) -> void:
	_build += 1
	var mine := _build
	var rows: Array = []
	for line in flow.lines:
		var vars := {"name": String(view.get("name", "")), "ask": String(view.get("ask", "")),  # i18n: row-ok the person's shown name, resolved by the wiring
			"president": String(view.get("president", "")), "lever": "", "topic": "", "first": String(view.get("name", "")).get_slice(" ", 0)}  # i18n: row-ok a shown name
		vars.merge(line.get("vars", {}), true)
		vars["third"] = AudienceTalkView.MARK
		var said: String = await DialogueLines.line(_resource, "talk_" + String(line["id"]), vars)
		if mine != _build:
			return
		var parts := (said if said != "" else _plain(line)).split(AudienceTalkView.MARK)
		var open_quote := "“"  # i18n: ok a quotation mark
		var shut_quote := "”"  # i18n: ok a quotation mark
		var before: String = open_quote + parts[0]
		var after: String = (parts[1] if parts.size() > 1 else "") + shut_quote
		if parts.size() == 1:
			before += shut_quote
			after = ""
		rows.append({"id": line["id"], "topic": line["topic"], "tag": line["tag"], "args": line.get("args", {}),
			"people": line.get("people", []), "prefix": before, "suffix": after,
			"asked": flow.asked.has(line["id"]), "picked": String(flow.picked.get(line["id"], "")),
			"blocked": String(view.get("talk_blocked", {}).get(String(line["topic"]), ""))})
	talk.show_lines(rows)


## The line the files do not have: the topic's own word, and a gossip's sentence around its faces.
func _plain(line: Dictionary) -> String:
	if not (line.get("people", []) as Array).is_empty():
		return tr("What do you make of") + " " + AudienceTalkView.MARK + "?"
	return String(line.get("plain", line["topic"]))  # i18n: row-ok the wiring's own word for the line


func _badge(view: Dictionary) -> void:
	var feel: Dictionary = view.get("choices", {}).get("feel", {})
	if not feel.is_empty() and _face.get_child_count() > 0:
		MoodBadge.wear(_face, feel, 28.0)


## One title of her lines, through the addon; a title the files lack is a plain line in her mouth.
func say(title: String, extra: Dictionary) -> void:
	var state := {"name": String(_view.get("name", "")), "ask": String(_view.get("ask", "")),  # i18n: row-ok the person's shown name, resolved by the wiring
		"president": String(_view.get("president", "")), "lever": "", "topic": "", "first": String(_view.get("name", "")).get_slice(" ", 0)}  # i18n: row-ok a shown name
	state.merge(extra, true)
	_speaker.text = String(state["name"])  # i18n: row-ok the person's shown name, resolved by the wiring
	var said: String = await DialogueLines.line(_resource, title, state)
	_line.text = said if said != "" or not title.ends_with("opening") else String(state["ask"])
