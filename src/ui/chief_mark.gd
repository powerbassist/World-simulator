extends Button

## The chief of staff's mark in the title bar, beside "requests waiting" -- G1,
## chief-briefing-brief.md 2: his face small, the month's first priority and its
## deadline chip, always on and read at zero clicks while the clock runs. A click
## opens his full read (BriefingDriver.read). He never stops the clock on his own
## (the author, 2026-11-15: "Jamais"), so this mark is how a month reaches the player.
##
## A Button holding its own row: the children ignore the mouse, so the whole plate is
## the one target, and its width follows the row (a long title is cut, the tooltip
## carries it whole: a request's name and "+2 more" ran past 600 px in French at 130 %).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Grade = preload("res://src/ui/grade.gd")

const FACE_PX := 32
## The title's widest, at 100 %; the text size scales it with the type.
const TITLE_MAX_PX := 340
const PAD_X := 8

var _face: TextureRect
var _title: Label
var _chip: Label
var _row: HBoxContainer
var _full_title := ""


func _ready() -> void:
	theme_type_variation = UiTheme.CHIEF_MARK
	focus_mode = Control.FOCUS_NONE  # chrome never takes Space (V5.1-0c)
	clip_contents = true
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = PAD_X
	_row.offset_right = -PAD_X
	add_child(_row)
	_face = TextureRect.new()
	_face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Grade.apply(_face)
	_row.add_child(_face)
	_title = _label("")
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_chip = _label(UiTheme.CAPTION)
	hide()


## face may be null (the silhouette is the portrait card's, not this mark's); `due_now`
## gives the chip the WARN tone, paired with its words ("This month"), never alone.
func show_line(face: Texture2D, title: String, chip: String, due_now: bool, tip: String) -> void:
	_face.texture = face
	_face.visible = face != null
	_full_title = title
	_title.text = title
	_chip.text = chip
	_chip.visible = not chip.is_empty()
	_chip.theme_type_variation = UiTheme.WARN_TEXT if due_now else UiTheme.CAPTION
	tooltip_text = tip if title.is_empty() else "%s\n%s" % [tip, title]
	_fit()
	show()


func clear() -> void:
	_full_title = ""
	hide()


func title_text() -> String:
	return _full_title if visible else ""


func chip_text() -> String:
	return _chip.text if visible and _chip.visible else ""


## The plate's width from its row: the title at its own width up to its cap.
func _fit() -> void:
	var font := _title.get_theme_font("font")
	var px := _title.get_theme_font_size("font_size")
	var want := font.get_string_size(_full_title, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if font != null else 0.0
	_title.custom_minimum_size.x = minf(ceilf(want), TITLE_MAX_PX * UiTheme.text_scale())
	custom_minimum_size.x = _row.get_combined_minimum_size().x + 2 * PAD_X
	text = ""


func _label(variation: String) -> Label:
	var label := Label.new()
	if variation != "":
		label.theme_type_variation = variation
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(label)
	return label
