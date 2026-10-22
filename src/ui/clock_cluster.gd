extends HBoxContainer

## Date, pause and speed -- U5a's bottom-right cluster, in the title bar since
## V5.1-c2.3 (the BUREAU board's place for it, beside save and the menu). The
## minimap it held went with the move: the map is the whole screen behind the
## workspace now, and a second, smaller map of it in a corner was the floating
## shell's answer to windows covering it.
##
## Proposes, never commands: pause and speed go back to main.gd as signals, the
## same shape Budget.commit() uses. main.gd is the one holding the Clock.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Motion = preload("res://src/ui/motion.gd")
const DateText = preload("res://src/ui/date_text.gd")

signal pause_toggled
signal speed_selected(speed: int)

## The English names, for tests and callers that want the table; the interface prints
## months through DateText, which translates them.
const MONTH_NAMES := DateText.SHORT

var _date_label: Label
var _pause_button: Button
var _speed_buttons := {}
## The clock last drawn, and whether it was held -- see _process().
var _clock: Node = null
var _shown_held := false


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	alignment = BoxContainer.ALIGNMENT_CENTER

	_date_label = Label.new()
	_date_label.theme_type_variation = UiTheme.FIGURE
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_date_label)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gap)

	_pause_button = _button(tr("Pause (Space)"))
	_pause_button.pressed.connect(func(): pause_toggled.emit())

	# One triangle, two, three -- the speed is legible without reading a number,
	# and the labels stay in the built-in glyph range rather than needing an
	# icon each.
	var glyphs := {1: ">", 2: ">>", 3: ">>>"}
	for s in [1, 2, 3]:
		var button := _button(tr("Speed %d (%d)") % [s, s])
		button.text = glyphs[s]
		button.toggle_mode = true
		button.pressed.connect(func(): speed_selected.emit(s))
		_speed_buttons[s] = button


## No focus, as on every piece of chrome: a clicked button that kept the focus
## would take Space, the pause key, for itself (V5.1-0c's forfeited Agenda).
func _button(tip: String) -> Button:
	var button := Button.new()
	button.theme_type_variation = UiTheme.SUBROW_BUTTON
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	return button


## V5.1-0a. A month closing across frames holds the clock (month_runner.gd),
## and nothing refreshes this while it does -- the held day_advanced is the
## refresh -- so the cluster watches for the hold itself.
func _process(_delta: float) -> void:
	if _clock != null and bool(_clock.held) != _shown_held:
		refresh(_clock)


func refresh(clock: Node) -> void:
	if clock == null:
		return
	_clock = clock
	_shown_held = bool(clock.held)
	# The month closing: the date dims as a paused one does and keeps last
	# month's text -- the 1st arrives with its day_advanced, when the hold lets
	# go and this is refreshed again -- and the pause button reads as busy.
	if _shown_held:
		_date_label.modulate.a = Motion.PAUSED_ALPHA
		_pause_button.text = "..."
		return
	var date := DateText.day_month_year(clock.day, clock.month, clock.year)
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
