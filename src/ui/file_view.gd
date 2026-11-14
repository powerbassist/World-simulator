extends RefCounted

## A file's page -- V5.3 screen 3 (the author picked decision C: the month's folder, with B's
## docked card for a file met mid-month). ONE builder for both hosts, from file_read.gd's
## dictionary, so the folder's right half and the docked panel cannot drift apart.
##
## The shape is the audience's (accepted C4): the person's face with its mood, their line
## under it; the micro line and the DATE the answer is due; the title; the situation; then the
## choices as cards, each with the tags it carries (effect_tags.gd), one sentence, and one
## 180 px button on a shared bottom edge. A choice with a `short` label heads its card with
## the full label and puts the short one on the button; without one the button carries the
## label and the card has no separate head -- never a stand-in word. The default is marked
## "if you say nothing", with no sentence explaining the rest of the interface.
##
## Pressing a button calls `press(index)` and nothing else: the host sends it through
## Inbox.press, the card's own door.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")
const Strings = preload("res://src/ui/strings.gd")

const FACE := Vector2(150, 190)
const BUTTON_WIDTH := 180


## Builds `page` under `parent` and returns its root. `press` is called with a choice's index.
static func build(parent: Control, page: Dictionary, press: Callable, face := FACE) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(root)
	if page.is_empty():
		PanelKit.line(root, Strings.t("Answered."), PanelKit.Tone.DIM)
		return root
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	root.add_child(top)
	var who: Dictionary = page["who"]
	if not who.is_empty():
		top.add_child(_person(who, face))
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override("separation", 6)
	top.add_child(head)
	var micro := HBoxContainer.new()
	micro.add_theme_constant_override("separation", 10)
	head.add_child(micro)
	if String(page["micro"]) != "":
		PanelKit.heading(micro, String(page["micro"]))
	if String(page["by_text"]) != "":
		var by := Label.new()
		by.text = Strings.t("by %s") % String(page["by_text"])
		by.theme_type_variation = UiTheme.WARN_TEXT
		micro.add_child(by)
	var title := Label.new()
	title.text = String(page["title"])
	title.theme_type_variation = UiTheme.FIGURE
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	if String(page["situation"]) != "":
		PanelKit.line(head, String(page["situation"]), PanelKit.Tone.DIM)
	if not who.is_empty() and String(who["quote"]) != "":
		var quote := PanelKit.plain_line(head, Strings.t("“%s”") % String(who["quote"]), PanelKit.Tone.PLAIN)
		quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var choices: Array = page["choices"]
	if not choices.is_empty():
		# One row of equal cards, so every button sits on the same bottom edge (the audience's rule:
		# C4 put all three tops at one line). Four cards at 216 px fit the folder's page.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		root.add_child(row)
		for i in choices.size():
			row.add_child(_card(choices[i], i, press))
	return root


static func _person(who: Dictionary, face: Vector2) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.custom_minimum_size.x = face.x
	var portrait := Portrait.control_for(String(who["id"]), face)
	column.add_child(MoodBadge.wear(portrait, who["feel"]) if not (who["feel"] as Dictionary).is_empty() else portrait)
	var name := PanelKit.rich(column, PanelKit.person(String(who["id"]), String(who["called"])), PanelKit.Tone.PLAIN)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if String(who["role"]) != "":
		PanelKit.line(column, String(who["role"]), PanelKit.Tone.DIM)
	return column


## One choice: its head (when it has a short label), its default mark, its tags, its sentence,
## and its button at the bottom edge.
static func _card(choice: Dictionary, index: int, press: Callable) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.PLATE
	card.custom_minimum_size = Vector2(BUTTON_WIDTH + 36, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var short := String(choice["short"])
	if bool(choice["default"]):
		PanelKit.heading(column, Strings.t("If you say nothing"))
	if short != "":
		var head := Label.new()
		head.text = String(choice["words"])
		head.theme_type_variation = UiTheme.LEAD
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(head)
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 8)
	tags.add_theme_constant_override("v_separation", 2)
	column.add_child(tags)
	for tag in (choice["tags"] as Array):
		var label := Label.new()
		label.text = "%s %s" % ["▲" if int(tag["tone"]) > 0 else ("▼" if int(tag["tone"]) < 0 else "•"), String(tag["text"])]  # i18n: ok glyph and a worded tag
		label.theme_type_variation = UiTheme.GOOD_SMALL if int(tag["tone"]) > 0 else (UiTheme.BAD_SMALL if int(tag["tone"]) < 0 else UiTheme.CAPTION)
		tags.add_child(label)
	var note := String(choice["note"])
	if note != "":
		var line := PanelKit.plain_line(column, _first_sentence(note), PanelKit.Tone.DIM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var button := PanelKit.sized(Button.new())
	button.text = short if short != "" else String(choice["words"])
	button.custom_minimum_size.x = BUTTON_WIDTH
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = bool(choice["disabled"])
	button.tooltip_text = String(choice["tip"])
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: press.call(index))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(button)
	return card


## The note's first sentence: the rest of a choice's summary is the long form the desk card
## already prints, and the card's job is to be read at a glance.
static func _first_sentence(text: String) -> String:
	var cut := text.find(". ")
	return text if cut < 0 else text.substr(0, cut + 1)
