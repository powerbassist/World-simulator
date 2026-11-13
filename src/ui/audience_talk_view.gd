extends VBoxContainer

## The conversation after the deal -- V5.3, mockup C4-talk: each line is one sentence the
## president says, and at its right end is a tag, a glyph WITH its words. Small talk is dim; a
## line that spends something real is toned WARN or BAD; the accent is never used (it says
## "you are here", not "this costs"). A gossip names its people as face chips INSIDE the sentence,
## and a chip's tooltip says how that person is tied. A line asked stays where it was, dimmed,
## tagged "Asked" (H3: nothing moves or resets because a line was pressed). Nothing here
## explains the interface.
##
## The ranking is talk_menu.gd's and the words arrive resolved: this draws rows it is handed.

signal asked(line_id: String, topic: String, args: Dictionary)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Strings = preload("res://src/ui/strings.gd")

const ICONS := "res://assets/icons/material/"
## The tag at a line's right end: key -> [glyph (an icon stem, or a sign), words, tone].
const TAGS := {
	"learn": ["menu_book", "Learn about them", ""],  # i18n: msgid
	"warm": ["handshake", "They warm", ""],  # i18n: msgid
	"warm_more": ["handshake", "They warm more", ""],  # i18n: msgid
	"asked": ["✓", "Asked", ""],  # i18n: msgid
	# The rare proposals (C4-offer, C4-affair): what each risks in two or three words, in a status tone.
	"trail": ["payments", "A money trail", "bad"],  # i18n: msgid
	"cools": ["▼", "They cool", "warn"],  # i18n: msgid
	"scandal": ["!", "Risks a scandal", "bad"],  # i18n: msgid
	"regard": ["▼", "Costs their regard", "bad"],  # i18n: msgid
}
const FACE := Vector2i(22, 28)
static var _faces := {}
const MARK := "¶"  # i18n: ok the placeholder a gossip's sentence splits on


## `rows`: [{id, topic, tag, args, prefix, suffix, people: [{id, name, tip}], asked: bool,
## blocked: String (the sim's reason this line cannot be put now, "" for none), picked: String,
## sub: bool (a follow-up drawn under the line above, indented)}].
func show_lines(rows: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 0)
	for row in rows:
		_add_rule()
		_row(row)
	_add_rule()


func _add_rule() -> void:
	var rule := HSeparator.new()
	add_child(rule)


func _row(row: Dictionary) -> void:
	var line_box := HBoxContainer.new()
	line_box.name = "Line_" + String(row["id"])  # i18n: ok a node name, found by tests
	line_box.add_theme_constant_override("separation", 8)
	add_child(line_box)
	if bool(row.get("sub", false)):
		var indent := Control.new()
		indent.custom_minimum_size.x = 18
		line_box.add_child(indent)
	var chevron := Label.new()
	chevron.text = "›"  # i18n: ok a glyph
	chevron.theme_type_variation = UiTheme.CAPTION
	line_box.add_child(chevron)
	var asked_already := bool(row["asked"])
	var blocked := String(row.get("blocked", ""))
	var spoken := HFlowContainer.new()
	spoken.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_box.add_child(spoken)
	var args: Dictionary = (row["args"] as Dictionary).duplicate()
	var put := func(extra: Dictionary) -> void:
		var sent := args.duplicate()
		sent.merge(extra, true)
		asked.emit(String(row["id"]), String(row["topic"]), sent)
	var live := not asked_already and blocked == ""
	if (row["people"] as Array).is_empty():
		var whole := _said(spoken, "%s%s" % [row["prefix"], row["suffix"]], live)
		whole.pressed.connect(func() -> void: put.call({}))
		whole.tooltip_text = blocked
	else:
		_said(spoken, String(row["prefix"]), false)
		for person in row["people"]:
			var chip := _chip(person, live, String(row.get("picked", "")) == String(person["id"]))
			chip.pressed.connect(func() -> void: put.call({"about": String(person["id"])}))
			spoken.add_child(chip)
		_said(spoken, String(row["suffix"]), false)
	line_box.add_child(_tag(String(row["tag"]) if not asked_already else "asked", asked_already or blocked != ""))


## The sentence, as a flat button when pressing it asks the line, else a dim label's width.
func _said(into: Control, text: String, pressable: bool) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = text  # i18n: row-ok the president's line, resolved from the dialogue by the scene
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not pressable
	button.focus_mode = Control.FOCUS_ALL if pressable else Control.FOCUS_NONE
	into.add_child(button)
	return button


func _chip(person: Dictionary, live: bool, picked: bool) -> Button:
	var chip := Button.new()
	chip.name = "Chip_" + String(person["id"])  # i18n: ok a node name, found by tests
	chip.text = String(person["name"])  # i18n: row-ok a person's shown name, from the loader
	chip.tooltip_text = String(person["tip"])  # i18n: row-ok the tie, worded by the view's builder
	chip.disabled = not live
	chip.toggle_mode = true
	chip.button_pressed = picked
	var face := _face(String(person["id"]))
	if face != null:
		chip.icon = face
	return chip


## A person's portrait cut to a chip's size (the button draws an icon at its own size), once each.
static func _face(person_id: String) -> Texture2D:
	if not _faces.has(person_id):
		var full := Portrait.texture_for(person_id)
		var small: Image = full.get_image() if full != null else null
		if small != null:
			small.resize(FACE.x, FACE.y, Image.INTERPOLATE_LANCZOS)
		_faces[person_id] = ImageTexture.create_from_image(small) if small != null else null
	return _faces[person_id]


## The glyph and its words, right-aligned: toned by the table, dimmed once the line is spent.
func _tag(key: String, spent: bool) -> Control:
	var def: Array = TAGS[key]
	var tone := String(def[2])
	var colour := UiTheme.WARN if tone == "warn" else (UiTheme.BAD if tone == "bad" else UiTheme.TEXT_DIM)
	var box := HBoxContainer.new()
	box.name = "Tag"  # i18n: ok a node name, found by tests
	box.add_theme_constant_override("separation", 6)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var glyph := String(def[0])
	if glyph.length() > 2:
		var picture := TextureRect.new()
		picture.texture = Icon.load_icon(ICONS + glyph + ".svg", colour, 15)
		picture.custom_minimum_size = Vector2(15, 15)
		box.add_child(picture)
	else:
		var sign_label := Label.new()
		sign_label.text = glyph
		sign_label.theme_type_variation = UiTheme.WARN_TEXT if tone == "warn" else (UiTheme.BAD_SMALL if tone == "bad" else UiTheme.CAPTION)
		box.add_child(sign_label)
	var words := Label.new()
	words.text = Strings.t(String(def[1]))  # i18n: row-ok a tag key, its words the msgid
	words.theme_type_variation = UiTheme.WARN_TEXT if tone == "warn" and not spent else (UiTheme.BAD_SMALL if tone == "bad" and not spent else UiTheme.CAPTION)
	box.add_child(words)
	return box
