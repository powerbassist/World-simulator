extends PanelContainer

## The in-game pause menu, on Escape. Until U1 there was no way out of a
## running game at all -- no route back to the main menu, and no quit that was
## not the window's close button.
##
## Emits intent and owns nothing, the same shape as every other panel here:
## main.gd holds the Clock and the GameState, so main.gd is what pauses, saves,
## and swaps the scene. Quit is the one exception, because there is no state to
## coordinate on the way out.
##
## Quit and Main Menu ask first once the game has moved since it was last on disk
## (G19, blind play 11-28: Quit closed at once, and there is no autosave by
## design). "Moved" is a digest of what a save holds, the state and the day.
##
## Built in code, like every other panel here; placement is the owner's
## (window_manager.gd's register()).

const UiTheme = preload("res://src/ui/ui_theme.gd")

## A press this soon after the question is the second half of a double click, not an answer.
const ANSWER_AFTER_MSEC := 500

signal resumed
signal save_load_requested
signal settings_requested
signal main_menu_requested
signal quit_requested

var _main  # read only, for the digest
var _saved := 0
var _warning: Label
var _save: Button
var _asked_at := 0
var _asking: Button  # the way out whose question is up, null when none
var _ways_out := {}  # button -> its own words, while the question may replace them


func _ready() -> void:
	custom_minimum_size = Vector2(300, 260)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = tr("PAUSED")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_warning = Label.new()
	_warning.text = tr("This game has unsaved changes.")
	_warning.theme_type_variation = UiTheme.WARN_TEXT
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size.x = 240
	_warning.hide()
	column.add_child(_warning)

	_add_entry(column, tr("Resume"), func(): resumed.emit())
	_save = _add_entry(column, tr("Save / Load"), func(): save_load_requested.emit())
	_add_entry(column, tr("Settings"), func(): settings_requested.emit())
	_add_way_out(column, tr("Main Menu"), tr("Leave without saving"), main_menu_requested)
	_add_way_out(column, tr("Quit"), tr("Quit without saving"), quit_requested)
	quit_requested.connect(func(): get_tree().quit())
	visibility_changed.connect(_withdraw_the_question)


## main's one call, as it builds: the game is stamped once main has finished
## establishing it (a new one, or a load's).
func watch(main) -> void:
	_main = main
	stamp.call_deferred()


## The game as it stands is on disk.
func stamp() -> void:
	_saved = _digest()


func changed() -> bool:
	return _digest() != _saved


## Whether the question is up.
func warns() -> bool:
	return _warning.visible


func _digest() -> int:
	return hash([_main._state.to_dict(), _main._clock.day])


func _add_entry(column: VBoxContainer, text: String, action := Callable()) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 32)
	if action.is_valid():
		button.pressed.connect(action)
	column.add_child(button)
	return button


## A way out of the game: on a changed one the first press asks, on the button and
## above it, and hands the keyboard to Save / Load; the second leaves.
func _add_way_out(column: VBoxContainer, text: String, anyway: String, leave: Signal) -> void:
	var button := _add_entry(column, text)
	_ways_out[button] = text
	button.pressed.connect(func() -> void:
		if _asking == button and Time.get_ticks_msec() - _asked_at < ANSWER_AFTER_MSEC:
			return
		if _asking != button and changed():
			_withdraw_the_question()
			_asking = button
			button.text = anyway
			_warning.show()
			_asked_at = Time.get_ticks_msec()
			_save.grab_focus()
			return
		leave.emit())


func _withdraw_the_question() -> void:
	_asking = null
	for button in _ways_out:
		(button as Button).text = _ways_out[button]
	_warning.hide()
