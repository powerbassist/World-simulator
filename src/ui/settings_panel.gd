extends PanelContainer

## The settings screen, reachable from the main menu and from the pause menu.
##
## Three controls, because three is how many settings this game currently has
## that do something. There is no audio, no autosave, no difficulty and no
## keybind remapping, so there are no rows for them -- a screen of dead toggles
## advertises scope that does not exist.
##
## Persisted to user://settings.cfg with the engine's own ConfigFile. Settings
## that reset on every launch are not settings.
##
## Built in code, like every other panel here -- see budget_panel.gd's
## placement note.

signal closed

const CONFIG_PATH := "user://settings.cfg"

## Windowed sizes offered. Fullscreen ignores these; the size is the display's.
##
## These are window sizes, not layout sizes. Since U5a the project stretches
## `canvas_items` from a 1920x1080 base, so every entry here renders the same
## 1080p HUD scaled to fit -- 1280x720 is the 1080p layout at 0.667, not a
## narrower one. That is the whole reason the small sizes can stay on the list
## now that the interface is designed against a fixed base.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

## 1920x1080, matching the project's base viewport. A first launch that has never
## opened the settings screen should be looking at the size the HUD was drawn
## for, not at the smallest one on the list.
const DEFAULT_RESOLUTION_INDEX := 2

## Fullscreen on a first launch. This is a map that fills the screen with the
## interface laid over it; in a 1280x720 window that reads as a screenshot of a
## game rather than as the game.
const DEFAULT_FULLSCREEN := true

## Interface scale. This game is a wall of small numbers in dense tables, so
## the readability knob is worth having before any other polish.
const UI_SCALES: Array[float] = [0.85, 1.0, 1.15, 1.3]
const DEFAULT_SCALE_INDEX := 1

var _fullscreen_button: OptionButton
var _resolution_button: OptionButton
var _scale_button: OptionButton


# --- persistence -------------------------------------------------------------

## Applied by whichever scene comes up first, before anything is drawn. Static
## so it costs no instance: reading three values out of a config file does not
## need the panel that edits them to exist.
static func apply_saved(window: Window) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # absent file leaves it empty, which is the default set
	_apply(
		window,
		bool(cfg.get_value("display", "fullscreen", DEFAULT_FULLSCREEN)),
		int(cfg.get_value("display", "resolution_index", DEFAULT_RESOLUTION_INDEX)),
		int(cfg.get_value("display", "ui_scale_index", DEFAULT_SCALE_INDEX))
	)


static func _apply(window: Window, fullscreen: bool, resolution_index: int, scale_index: int) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

	# Only meaningful windowed -- resizing a fullscreen window fights the
	# display, and the setting reasserts itself the moment fullscreen is left.
	if not fullscreen:
		var size: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
		DisplayServer.window_set_size(size)

	if window != null:
		window.content_scale_factor = UI_SCALES[clampi(scale_index, 0, UI_SCALES.size() - 1)]


func _save_and_apply() -> void:
	var fullscreen := _fullscreen_button.selected == 1
	var resolution_index := _resolution_button.selected
	var scale_index := _scale_button.selected

	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "resolution_index", resolution_index)
	cfg.set_value("display", "ui_scale_index", scale_index)
	cfg.save(CONFIG_PATH)

	_apply(get_window(), fullscreen, resolution_index, scale_index)
	_resolution_button.disabled = fullscreen


# --- construction ------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(480, 300)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "SETTINGS"
	root.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)

	_fullscreen_button = _add_row(grid, "Window", ["Windowed", "Fullscreen"])
	_resolution_button = _add_row(grid, "Resolution", _resolution_labels())
	_scale_button = _add_row(grid, "Interface scale", _scale_labels())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(footer)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func():
		hide()
		closed.emit()
	)
	footer.add_child(close)

	_load_into_controls()


func _add_row(grid: GridContainer, label_text: String, options: Array) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)

	var button := OptionButton.new()
	button.custom_minimum_size.x = 220
	for option in options:
		button.add_item(str(option))
	# item_selected rather than a Range signal, so this panel is drivable from a
	# headless test without the frame dance budget_panel.gd needs -- see the
	# Control-outside-the-tree gotcha in docs/engine-decision.md.
	button.item_selected.connect(func(_index: int): _save_and_apply())
	grid.add_child(button)
	return button


func _resolution_labels() -> Array:
	var labels: Array = []
	for size in RESOLUTIONS:
		labels.append("%d x %d" % [size.x, size.y])
	return labels


func _scale_labels() -> Array:
	var labels: Array = []
	for scale in UI_SCALES:
		labels.append("%d%%" % roundi(scale * 100.0))
	return labels


## Reads the file rather than the live window, so the controls show what will be
## restored next launch even if something else has moved the window since.
func _load_into_controls() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	var fullscreen := bool(cfg.get_value("display", "fullscreen", DEFAULT_FULLSCREEN))
	_fullscreen_button.select(1 if fullscreen else 0)
	_resolution_button.select(clampi(int(cfg.get_value("display", "resolution_index", DEFAULT_RESOLUTION_INDEX)), 0, RESOLUTIONS.size() - 1))
	_scale_button.select(clampi(int(cfg.get_value("display", "ui_scale_index", DEFAULT_SCALE_INDEX)), 0, UI_SCALES.size() - 1))
	_resolution_button.disabled = fullscreen
