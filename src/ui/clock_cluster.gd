extends HBoxContainer

## Date, pause and speed -- the left end of the horizon (ribbon.gd) since V5.3's bar
## rebuild: the title bar had it on the right, far from the days it counts. One
## segmented control (pause | 1 | 2 | 3, glyphs rather than the ASCII `|> >> >>>` the
## gate called "outdated"), then the date with, under it, the line that says why
## the clock holds.
##
## Proposes, never commands: pause and speed go back to main.gd as signals, the
## same shape Budget.commit() uses. main.gd is the one holding the Clock.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Motion = preload("res://src/ui/motion.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Icon = preload("res://src/ui/icon.gd")

signal pause_toggled
signal speed_selected(speed: int)

## The English names, for tests and callers that want the table; the interface prints
## months through DateText, which translates them.
const MONTH_NAMES := DateText.SHORT

const ICON_PX := 20
## The hold line's room: it ellipsises past it and the tooltip carries the whole sentence.
const REASON_WIDTH := 290
## Own-drawn glyphs (assets/icons/ui), one file per speed so the speed reads as a
## pip count without a number: Material has no three-step play.
const GLYPHS := {
	"pause": "res://assets/icons/ui/pause.svg", 1: "res://assets/icons/ui/play1.svg",
	2: "res://assets/icons/ui/play2.svg", 3: "res://assets/icons/ui/play3.svg",
	"busy": "res://assets/icons/ui/hourglass.svg",
}

var _date_label: Label
## V5.1-d1b1: why the clock holds, under the date -- every hold says so, whether
## or not the inbox moved (hold_reason.gd). Gone when the clock runs.
var _reason: Label
var _pause_button: Button
var _speed_buttons := {}
## Glyph key -> {dim, lit} textures: the lit one is drawn while the button is down.
var _textures := {}
## The clock last drawn, and whether it was held -- see _process().
var _clock: Node = null
var _shown_held := false


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	alignment = BoxContainer.ALIGNMENT_BEGIN

	var segments := HBoxContainer.new()
	segments.add_theme_constant_override("separation", 2)
	segments.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(segments)
	_pause_button = _button(segments, tr("Pause (Space)"), "pause")
	_pause_button.pressed.connect(func(): pause_toggled.emit())
	for s in [1, 2, 3]:
		var button := _button(segments, tr("Speed %d (%d)") % [s, s], s)
		button.pressed.connect(func(): speed_selected.emit(s))
		_speed_buttons[s] = button

	_textures["busy"] = {"lit": Icon.load_icon(GLYPHS["busy"], UiTheme.TEXT, ICON_PX)}
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -2)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(text)
	_date_label = Label.new()
	_date_label.theme_type_variation = UiTheme.FIGURE
	_date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_child(_date_label)
	_reason = Label.new()
	_reason.theme_type_variation = UiTheme.WARN_TEXT
	_reason.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_reason.custom_minimum_size.x = REASON_WIDTH
	_reason.mouse_filter = Control.MOUSE_FILTER_PASS
	_reason.hide()
	text.add_child(_reason)


## No focus, as on every piece of chrome: a clicked button that kept the focus
## would take Space, the pause key, for itself (V5.1-0c's forfeited Agenda).
func _button(parent: Control, tip: String, glyph) -> Button:
	var button := Button.new()
	button.theme_type_variation = UiTheme.SUBROW_BUTTON
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(38, 32)
	_textures[glyph] = {"dim": Icon.load_icon(GLYPHS[glyph], UiTheme.TEXT_DIM, ICON_PX),
		"lit": Icon.load_icon(GLYPHS[glyph], UiTheme.TEXT, ICON_PX)}
	button.icon = _textures[glyph]["dim"]
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = false
	parent.add_child(button)
	return button


## V5.1-0a. A month closing across frames holds the clock (month_runner.gd),
## and nothing refreshes this while it does -- the held day_advanced is the
## refresh -- so the cluster watches for the hold itself.
func _process(_delta: float) -> void:
	if _clock != null and bool(_clock.held) != _shown_held:
		refresh(_clock)


func hold_reason() -> String:
	return _reason.text


## `reason`: why the clock holds, from a hold (hold_reason.gd); left as it was when
## not given. A running clock has none.
func refresh(clock: Node, reason = null) -> void:
	if clock == null:
		return
	if reason != null:
		_reason.text = String(reason)
	if not clock.paused:
		_reason.text = ""
	_reason.visible = not _reason.text.is_empty()
	_reason.tooltip_text = _reason.text
	_clock = clock
	_shown_held = bool(clock.held)
	# The month closing: the date dims as a paused one does and keeps last
	# month's text -- the 1st arrives with its day_advanced, when the hold lets
	# go and this is refreshed again -- and the pause button reads as busy.
	if _shown_held:
		_date_label.modulate.a = Motion.PAUSED_ALPHA
		_pause_button.button_pressed = true
		_pause_button.icon = _textures["busy"]["lit"]
		return
	var date := DateText.weekday_full(clock.day, clock.month, clock.year)
	# V4.9a. The clock shows its speed rather than stating it: one beat per
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
	_pause_button.button_pressed = clock.paused
	_set_glyph(_pause_button, "pause", clock.paused)
	for s in _speed_buttons.keys():
		var on: bool = (not clock.paused) and clock.speed == s
		_speed_buttons[s].button_pressed = on
		_set_glyph(_speed_buttons[s], s, on)


## The dim glyph at rest, the lit one while the button is the clock's state.
func _set_glyph(button: Button, glyph, lit: bool) -> void:
	button.icon = _textures[glyph]["lit" if lit else "dim"]
