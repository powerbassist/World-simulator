extends PanelContainer

## Date, pause and speed, bottom-right -- U5a. Moved out of top_bar.gd, where
## U2 put them because there was nowhere else, and down to the corner the
## reference puts them in.
##
## The move is not only cosmetic. The clock is the one control the player touches
## constantly, and it now sits next to the mouse's resting position on the map
## rather than diagonally opposite the thing being watched.
##
## Proposes, never commands: pause and speed go back to main.gd as signals, the
## same shape Budget.commit() uses. main.gd is the one holding the Clock.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Motion = preload("res://src/ui/motion.gd")

signal pause_toggled
signal speed_selected(speed: int)

const MONTH_NAMES: Array[String] = [
	"JAN", "FEB", "MAR", "APR", "MAY", "JUN",
	"JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
]

## Reserved for U5b's minimap. Held open as a sized, empty box rather than left
## out, because a corner cluster that changes height the session the minimap
## arrives moves every control above it.
const MINIMAP_SIZE := Vector2(176, 104)

var _date_label: Label
var _pause_button: Button
var _speed_buttons := {}
var _minimap_slot: Control


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	add_child(column)

	_date_label = Label.new()
	_date_label.theme_type_variation = UiTheme.FIGURE
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_date_label)

	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 3)
	column.add_child(controls)

	_pause_button = Button.new()
	_pause_button.theme_type_variation = UiTheme.SUBROW_BUTTON
	_pause_button.tooltip_text = "Pause (Space)"
	_pause_button.pressed.connect(func(): pause_toggled.emit())
	controls.add_child(_pause_button)

	# One triangle, two, three -- the speed is legible without reading a number,
	# and the labels stay in the built-in glyph range rather than needing an
	# icon each.
	var glyphs := {1: ">", 2: ">>", 3: ">>>"}
	for s in [1, 2, 3]:
		var button := Button.new()
		button.theme_type_variation = UiTheme.SUBROW_BUTTON
		button.text = glyphs[s]
		button.toggle_mode = true
		button.tooltip_text = "Speed %d (%d)" % [s, s]
		button.pressed.connect(func(): speed_selected.emit(s))
		controls.add_child(button)
		_speed_buttons[s] = button

	_minimap_slot = PanelContainer.new()
	_minimap_slot.custom_minimum_size = MINIMAP_SIZE
	column.add_child(_minimap_slot)

	var placeholder := Label.new()
	placeholder.text = "MAP OVERVIEW"
	placeholder.theme_type_variation = UiTheme.MICRO
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_minimap_slot.add_child(placeholder)


## U5b fills the reserved box. Public rather than reaching into the node from
## outside, so the slot's construction stays this file's business.
func set_minimap(minimap: Control) -> void:
	for child in _minimap_slot.get_children():
		_minimap_slot.remove_child(child)
		child.queue_free()
	minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_minimap_slot.add_child(minimap)


func refresh(clock: Node) -> void:
	if clock == null:
		return
	var date := "%02d %s %d" % [clock.day, MONTH_NAMES[clock.month - 1], clock.year]
	# V4.9a. The clock shows its speed rather than stating it: one brass beat per
	# day, so the beats' own rhythm is the speed, and a paused date is dimmed --
	# still the date, visibly not moving. The dim is state, not motion, so it
	# holds with motion off too.
	# Alpha only: the beat tweens the colour channels, so a second refresh the
	# same day (a month boundary, any command) leaves it running.
	_date_label.modulate.a = Motion.PAUSED_ALPHA if clock.paused else 1.0
	if date != _date_label.text:
		var first := _date_label.text.is_empty()
		_date_label.text = date
		if not first and not clock.paused:
			Motion.pulse(_date_label)
	_pause_button.text = "|>" if clock.paused else "||"
	for s in _speed_buttons.keys():
		_speed_buttons[s].button_pressed = (not clock.paused) and clock.speed == s
