extends RefCounted

## One line of the People roster -- rework 1. The face, the name over its side, then a
## fixed column per reading (what they hold, how they feel, what they want now, what you
## owe them, how well you know them), every cell a word before any figure.
##
## The line is a press target under its cells: a toggle button that fills the row (its
## pressed look is the focused row, its focus ring the keyboard's place), the cells drawn
## over it and letting the pointer through. It holds no panel state: whoever builds it
## hands the callables, so a later surface (an audience's "talk about someone", H3) can
## list the same line.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")
const Feelings = preload("res://src/ui/feelings.gd")

const FACE := Vector2(28, 38)
## The columns after the face, as shares of the line: person, holds, feels, wants, owe,
## known. Shares rather than pixels, so the heads and every line divide the same dock the
## same way at any text size (the first frames clipped the page at the former 130 %); a long cell
## wraps inside its column, and a value sits under its head (V5.2 b+ R5).
const COLS := [230, 170, 130, 300, 190, 80]


## The column heads, over the lines (Micro, the grammar's section label).
static func heads(parent: Control, texts: Array) -> Control:
	var row := _cells_box()
	row.add_child(_spacer(FACE.x))
	for i in texts.size():
		var head := _cell(row, String(texts[i]), i, UiTheme.MICRO)
		head.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# The lines' own side padding, so a head sits over its column.
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_%s" % side, 8)
	pad.add_child(row)
	parent.add_child(pad)
	return pad


## `meta` is [key, id] ("person" or "office"); `cells` [{text, tone}] in COLS order, the
## first with a "sub" line under the name. `face_id` "" draws no face. `hover` (id, line),
## `unhover` (), `pick` (), `menu` () are the panel's.
static func build(parent: Control, meta: Array, face_id: String, feel: Dictionary, cells: Array, picked: bool,
		hover: Callable, unhover: Callable, pick: Callable, menu: Callable) -> Control:
	var wrap := MarginContainer.new()
	wrap.set_meta(String(meta[0]), String(meta[1]))
	# The button under the cells takes the pointer; the wrapper must not take an event
	# the button leaves (a right click) a second time.
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wrap)
	var press := Button.new()
	press.theme_type_variation = UiTheme.SUBROW_BUTTON
	press.toggle_mode = true
	press.button_pressed = picked
	press.focus_mode = Control.FOCUS_ALL
	press.set_meta("line", String(meta[1]))
	# A line is un-focused only by focusing another (a rebuild): a second click on the
	# focused one must not un-press it (pass 2 on #388).
	press.toggled.connect(func(on: bool) -> void:
		if not on:
			press.set_pressed_no_signal(true))
	wrap.add_child(press)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_%s" % side, 8)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_%s" % side, 3)
	wrap.add_child(pad)
	var row := _cells_box()
	pad.add_child(row)
	var face: Control
	if face_id != "":
		face = Portrait.framed_for(face_id, FACE, MoodBadge.mood_portrait(face_id, feel)) if not feel.is_empty() \
			else Portrait.framed_for(face_id, FACE)
	else:
		face = Control.new()
	face.custom_minimum_size = FACE
	row.add_child(face)
	# The portrait's own parts stop the pointer (pass 2 on #388: a click on the face was
	# dead and the card hid): every cell over the press target lets it through.
	_let_through(face)
	var first: Dictionary = cells[0]
	var name := VBoxContainer.new()
	name.add_theme_constant_override("separation", 0)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_stretch_ratio = COLS[0]
	name.alignment = BoxContainer.ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name)
	_label(name, String(first["text"]), String(first.get("tone", "")), true)
	if String(first.get("sub", "")) != "":
		_label(name, String(first["sub"]), UiTheme.CAPTION, true)
	for i in range(1, cells.size()):
		_cell(row, String(cells[i]["text"]), i, String(cells[i].get("tone", "")))
	press.pressed.connect(func() -> void: pick.call())
	var on_input := func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				pick.call()
				menu.call()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				pick.call()
	press.gui_input.connect(on_input)
	# A test (and nothing else) drives the line by its tagged wrapper.
	wrap.gui_input.connect(on_input)
	var hover_id := face_id if face_id != "" else String(meta[1])
	press.mouse_entered.connect(func() -> void: hover.call(hover_id, press))
	press.mouse_exited.connect(func() -> void: unhover.call())
	return wrap


static func _let_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_let_through(child)


static func _cells_box() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


static func _spacer(width: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.x = width
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


static func _cell(row: Control, text: String, col: int, tone: String) -> Label:
	var label := _label(row, text, tone, false)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = COLS[col]
	return label


static func _label(parent: Control, text: String, tone: String, trim: bool) -> Label:
	var label := Label.new()
	label.text = text  # i18n: row-ok every caller hands a translated or resolved string
	label.theme_type_variation = tone
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if trim:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(label)
	return label
