extends HBoxContainer

## The audience's question -- V5.3, mockup C4: three cards, Grant / Counter / Refuse, built by one
## rule. A header (a micro word and a one-line title), consequence lines that all start from
## the same top, and a footer pinned to the card's bottom: the action button 180 px wide at the
## card's own left padding, so the three buttons' tops sit on one line whatever the card above
## them says; the Counter's date field is ABOVE its button, in the same footer. The words are
## audience_words.gd's and the figures the sim's; this draws them and writes nothing.

signal granted
signal countered(date: Dictionary)
signal refused
signal date_picked(date: Dictionary)
signal date_opened
signal date_closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Icon = preload("res://src/ui/icon.gd")
const DatePick = preload("res://src/ui/date_pick.gd")
const Words = preload("res://src/ui/audience_words.gd")

const BUTTON_WIDTH := 180
## 16 of padding and the plate's 1 px hairline: the 17 px the mockup measures from the card's edge.
const PADDING := 16
const ICONS := "res://assets/icons/material/"
const NODE := {"grant": ["GrantCard", "GrantButton"], "counter": ["CounterCard", "CounterButton"], "refuse": ["RefuseCard", "RefuseButton"]}  # i18n: ok node names, found by tests

var date_pick: DatePick


func _ready() -> void:
	add_theme_constant_override("separation", 14)


## `q` is AudienceWords.question(); `date` the Counter's current date ({} for the default the
## row gives). Every call rebuilds the cards from `q` and `date`, so what the player chose is
## whatever the caller holds, never the widgets' own memory.
func show_question(q: Dictionary, date: Dictionary, default_date: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	date_pick = null
	_card("grant", q["grant"], func() -> void: granted.emit())
	if not (q["counter"] as Dictionary).is_empty():
		var counter: Dictionary = q["counter"]
		var footer := _card("counter", counter, func() -> void: countered.emit(date_pick.date))
		date_pick = DatePick.new()
		date_pick.name = "DateField"  # i18n: ok a node name, found by tests
		date_pick.custom_minimum_size.x = BUTTON_WIDTH
		date_pick.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		footer.add_child(date_pick)
		footer.move_child(date_pick, 0)
		date_pick.setup(int(counter["earliest"]), int(counter["latest"]), date if not date.is_empty() else default_date)
		date_pick.picked.connect(func(chosen: Dictionary) -> void: date_picked.emit(chosen))
		date_pick.opened.connect(func() -> void: date_opened.emit())
		date_pick.closed.connect(func() -> void: date_closed.emit())
		date_pick.disabled = not bool(counter["ok"])
	_card("refuse", q["refuse"], func() -> void: refused.emit())


## One card; the footer (the box the button is in) is returned for the Counter's field.
func _card(key: String, def: Dictionary, on_press: Callable) -> VBoxContainer:
	var plate := PanelContainer.new()
	plate.name = NODE[key][0]
	plate.theme_type_variation = UiTheme.PLATE
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(plate)
	var box := PanelKit.padded(plate, PADDING, 8)
	var micro := Label.new()
	micro.theme_type_variation = UiTheme.MICRO
	micro.uppercase = true
	micro.text = String(def["micro"])
	box.add_child(micro)
	var title := Label.new()
	title.theme_type_variation = UiTheme.LEAD
	title.text = String(def["title"])
	box.add_child(title)
	for row in def["lines"]:
		_line(box, row)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	box.add_child(footer)
	var button := PanelKit.sized(Button.new())
	button.name = NODE[key][1]
	button.text = String(def["micro"])  # i18n: row-ok the card's own word, from audience_words.gd
	button.custom_minimum_size.x = BUTTON_WIDTH
	button.disabled = not bool(def["ok"])
	button.tooltip_text = String(def["why"])
	button.pressed.connect(on_press)
	footer.add_child(button)
	return footer


## A consequence line: its glyph (a sign or an icon, in the status tone) and its sentence.
func _line(into: Control, row: Dictionary) -> void:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 8)
	into.add_child(cell)
	var tone := String(row["tone"])
	var glyph_colour := UiTheme.GOOD if tone == Words.GOOD else (UiTheme.BAD if tone == Words.BAD else (UiTheme.WARN if tone == Words.WARN else UiTheme.TEXT_DIM))
	var glyph := String(row["glyph"])
	if glyph.length() > 2:
		var picture := TextureRect.new()
		picture.texture = Icon.load_icon(ICONS + glyph + ".svg", glyph_colour, 16)
		picture.custom_minimum_size = Vector2(16, 16)
		picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		cell.add_child(picture)
	else:
		var sign_label := Label.new()
		sign_label.text = glyph
		sign_label.custom_minimum_size.x = 16
		sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sign_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		sign_label.theme_type_variation = UiTheme.GOOD_SMALL if tone == Words.GOOD else (UiTheme.BAD_SMALL if tone == Words.BAD else (UiTheme.WARN_TEXT if tone == Words.WARN else UiTheme.CAPTION))
		cell.add_child(sign_label)
	var text := Label.new()
	text.text = String(row["text"])  # i18n: row-ok words built by audience_words.gd
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(text)
