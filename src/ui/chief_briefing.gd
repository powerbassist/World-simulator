extends PanelContainer

## The monthly briefing -- V5.3-0, docs/design/v5.3-0-readability.md 2.2. A card on
## the SCENE layer at each month's start: the chief of staff's face and line, three
## priorities each with a Go, what the player's choices did, and one closing button.
## Not `briefing.gd`: that name is V4.2's bill briefing.
##
## The card is dumb on purpose: briefing_driver.gd hands it a view already worded
## (show_view) and performs what its signals ask, so the card never reads GameState.
##
## Keys: 1 / 2 / 3 is that line's Go, Enter and Escape the closing button (Escape
## through the stack's cancel), and SPACE IS SWALLOWED: Space is the pause toggle,
## and a focused closing button would take it as ui_accept and release the hold --
## V5.1-0c's bug, where Space forfeited the Agenda.

signal go_pressed(index: int)
signal closed
## Emitted when the card goes away: the front page waits for it (front_page.gd).
signal dismissed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Icon = preload("res://src/ui/icon.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Grade = preload("res://src/ui/grade.gd")

const SIZE := Vector2(720, 0)
const FACE_PX := 72
const ICON_PX := 20
const SPARK_SIZE := Vector2(96, 24)

var _face: TextureRect
var _header: Label
var _line: Label
var _name: Label
var _rows: VBoxContainer
var _effects: VBoxContainer
var _also: HFlowContainer
var also_buttons: Array[Button] = []
var _close: Button
var go_buttons: Array[Button] = []


func _ready() -> void:
	custom_minimum_size = SIZE
	var root := PanelKit.padded(self, 18, 12)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	root.add_child(top)
	_face = TextureRect.new()
	_face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face.visible = false
	Grade.apply(_face)
	top.add_child(_face)
	var said := VBoxContainer.new()
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(said)
	_name = Label.new()
	_name.theme_type_variation = UiTheme.HEADING
	_name.visible = false
	said.add_child(_name)
	_header = Label.new()
	_header.theme_type_variation = UiTheme.LEAD
	said.add_child(_header)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_line.visible = false
	said.add_child(_line)

	_rows = PanelKit.section(root, tr("Three priorities"))
	# The parent's rule on #217: an item in its last month the three lines crowded out
	# is never unshown -- it is here, folded by kind, each with its Go.
	_also = PanelKit.buttons(root)
	_effects = PanelKit.section(root, tr("What your choices did"))
	var foot := PanelKit.buttons(root)
	_close = PanelKit.sized(Button.new())
	_close.pressed.connect(func() -> void: closed.emit())
	foot.add_child(_close)


## view: {header, who and line ("" hides each), face (Texture2D or null), rows: [{icon, title,
## chip, held}], effects: [{text, tone, uncertain, spark, tooltip}], close}.
func show_view(view: Dictionary) -> void:
	_header.text = String(view.get("header", ""))
	_name.text = String(view.get("who", ""))
	_name.visible = not _name.text.is_empty()
	_line.text = String(view.get("line", ""))
	_line.visible = not _line.text.is_empty()
	_face.texture = view.get("face")
	_face.visible = _face.texture != null
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	go_buttons.clear()
	var rows: Array = view.get("rows", [])
	for i in rows.size():
		_rows.add_child(_row(rows[i], i))
	for child in _effects.get_children():
		_effects.remove_child(child)
		child.queue_free()
	_fill_also(view.get("also", []))
	for effect in view.get("effects", []):
		_effects.add_child(_effect(effect))
	_close.text = String(view.get("close", ""))
	show()
	_close.grab_focus()


func _row(row: Dictionary, index: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.texture = Icon.load_icon(String(row.get("icon", "")), UiTheme.TEXT_DIM, ICON_PX)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	box.add_child(words)
	var title := Label.new()
	title.text = String(row.get("title", ""))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	words.add_child(title)
	var chip := String(row.get("chip", ""))
	if bool(row.get("held", false)):
		# A held line says so in words, never by its colour alone.
		chip = tr("Waiting on you") if chip.is_empty() else tr("Waiting on you · %s") % chip
	if not chip.is_empty():
		var chip_label := Label.new()
		chip_label.text = chip
		chip_label.theme_type_variation = UiTheme.WARN_TEXT if bool(row.get("held", false)) else UiTheme.CAPTION
		words.add_child(chip_label)
	var go := PanelKit.sized(Button.new())
	go.text = tr("Go")
	go.tooltip_text = tr("Open it (key %d)") % (index + 1)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func() -> void: go_pressed.emit(index))
	box.add_child(go)
	go_buttons.append(go)
	return box


func _fill_also(groups: Array) -> void:
	for child in _also.get_children():
		_also.remove_child(child)
		child.queue_free()
	also_buttons.clear()
	_also.visible = not groups.is_empty()
	if groups.is_empty():
		return
	var label := Label.new()
	label.text = tr("Also due this month:")
	label.theme_type_variation = UiTheme.WARN_TEXT
	_also.add_child(label)
	for g in groups:
		var go := PanelKit.sized(Button.new())
		go.text = String(g["text"])
		var index := int(g["index"])
		go.pressed.connect(func() -> void: go_pressed.emit(index))
		_also.add_child(go)
		also_buttons.append(go)


func _effect(effect: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var tag := Label.new()
	tag.uppercase = true
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if bool(effect.get("uncertain", false)):
		# Uncertain is never green or red (the author's "en gris", call 7).
		tag.text = tr("Uncertain")
		tag.theme_type_variation = UiTheme.CAPTION
	else:
		ResultTone.apply(tag, String(effect.get("tone", "")))
	box.add_child(tag)
	var text := Label.new()
	text.text = String(effect.get("text", ""))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.tooltip_text = String(effect.get("tooltip", ""))
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(text)
	var spark: PackedFloat64Array = effect.get("spark", PackedFloat64Array())
	if spark.size() >= 2:
		var chart := ChartKit.spark(box, spark, [])
		chart.custom_minimum_size = SPARK_SIZE
	return box


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_SPACE:
		get_viewport().set_input_as_handled()
	elif key >= KEY_1 and key <= KEY_3 and key - KEY_1 < go_buttons.size():
		get_viewport().set_input_as_handled()
		go_pressed.emit(key - KEY_1)
