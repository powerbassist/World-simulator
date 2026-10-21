extends PanelContainer

## The settings screen, reachable from the main menu and from the pause menu.
##
## Six controls, because six is how many settings this game currently has
## that do something. There is no autosave, no difficulty and no keybind
## remapping, so there are no rows for them -- a screen of dead toggles
## advertises scope that does not exist. Sound arrived at V3.6 as one binary
## row rather than a volume ladder: one synthesized sting exists, and Off/On
## is every level it needs. Motion arrived at V4.9a the same way: Off is
## reduced motion, every tween landing on its final value at once. Ambience
## arrived at V4.9c when the sting became a sound set: the looping beds are the
## one part a player may want off on its own.
##
## V4.8c added the MESSAGES grid below them: per event category, the severity
## band at which each of four switches fires (message_settings.gd owns the
## register, its defaults and the file section; this screen only draws it).
##
## Persisted to user://settings.cfg with the engine's own ConfigFile. Settings
## that reset on every launch are not settings.
##
## Built in code, like every other panel here -- see budget_panel.gd's
## placement note.

signal closed

const PanelKit = preload("res://src/ui/panel_kit.gd")
const MessageSettings = preload("res://src/ui/message_settings.gd")
const Strings = preload("res://src/ui/strings.gd")
const WindowMode = preload("res://src/ui/window_mode.gd")
const EventsK = preload("res://src/sim/events_constants.gd")
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

## Sound on a first launch. Audible rather than muted by default: a sting that
## ships silent is scope nobody will ever notice shipped (V3.6).
const DEFAULT_SOUND := true

## Motion on a first launch (V4.9a). Off is the reduced-motion choice: every
## tween in src/ui/motion.gd lands on its final value at once, so nothing a
## player reads depends on watching an animation finish.
const DEFAULT_MOTION := true

## Ambience on a first launch (V4.9c, author's call): the beds are the one sound
## a player most wants off while keeping the cues, so they get their own row --
## but they ship audible, for DEFAULT_SOUND's reason. Sound Off silences them too.
const DEFAULT_AMBIENT := true

## Bumped on every save, so a reader that caches a setting (motion.gd) knows to
## read the file again. Static: the menu's screen and the pause menu's are two
## instances writing one file.
static var revision := 0

var _language_button: OptionButton
var _content: MarginContainer  ## the whole screen, so a language change can rebuild it
var _fullscreen_button: OptionButton
var _foreign_news_button: OptionButton
## The resolution row as last applied, so a change to it can be told from a change
## to any other row.
var _applied_resolution := -1
var _resolution_button: OptionButton
var _scale_button: OptionButton
var _ambient_button: OptionButton
var _sound_button: OptionButton
var _motion_button: OptionButton
var _message_buttons := {}  # category -> {switch: OptionButton}

## Narrow enough that a category label and four band pickers fit the panel's
## width; the longest band label ("Critical") still reads whole.
const BAND_BUTTON_WIDTH := 96


# --- persistence -------------------------------------------------------------

## The language the file holds; English when there is none.
static func saved_language() -> String:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	return String(cfg.get_value("display", "language", Strings.DEFAULT))


## Applied by whichever scene comes up first, before anything is drawn. Static
## so it costs no instance: reading three values out of a config file does not
## need the panel that edits them to exist.
static func apply_saved(window: Window) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # absent file leaves it empty, which is the default set
	# Before anything is built: tr() gives a Control the text of the language it
	# was built in, so the language has to be known first. A code the game does
	# not offer is English rather than a blank interface.
	if not Strings.set_language(String(cfg.get_value("display", "language", Strings.DEFAULT))):
		Strings.set_language(Strings.DEFAULT)
	_apply(
		window,
		bool(cfg.get_value("display", "fullscreen", DEFAULT_FULLSCREEN)),
		int(cfg.get_value("display", "resolution_index", DEFAULT_RESOLUTION_INDEX)),
		int(cfg.get_value("display", "ui_scale_index", DEFAULT_SCALE_INDEX))
	)
	# F11, on the root window so it works in the menu and in the game (V5.1-0c).
	WindowMode.install(window, toggle_fullscreen)


## F11: flip fullscreen, persist the result, and apply. The Settings row reads the
## file, so writing it here is what keeps the screen and the row in agreement.
static func toggle_fullscreen(window: Window) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	# Flipped from what the window IS, not from the file: when the two disagree the
	# first press must still change what the player sees.
	var fullscreen := window.mode != Window.MODE_FULLSCREEN
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(CONFIG_PATH)
	_apply(
		window,
		fullscreen,
		int(cfg.get_value("display", "resolution_index", DEFAULT_RESOLUTION_INDEX)),
		int(cfg.get_value("display", "ui_scale_index", DEFAULT_SCALE_INDEX))
	)


static func _apply(window: Window, fullscreen: bool, resolution_index: int, scale_index: int, force_size := false) -> void:
	if window == null:
		return
	# Everything goes through the Window node, not DisplayServer: the node caches
	# its own mode and size and writes them back whenever another property
	# (min_size, unresizable, content_scale_factor) changes, so a DisplayServer
	# call followed by a node property reverted the mode -- measured, V5.1-0c.
	var plan := WindowMode.plan(fullscreen, window.mode == Window.MODE_FULLSCREEN, force_size)
	# Windowed is always resizable, with a floor (V5.1-0c).
	window.unresizable = not bool(plan["resizable"])
	window.min_size = plan["min_size"]
	# Only on a change: assigning WINDOWED again would un-maximize a window the
	# player maximized, on every menu entry and every Settings row.
	if fullscreen != (window.mode == Window.MODE_FULLSCREEN):
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	# Only meaningful windowed -- resizing a fullscreen window fights the
	# display, and the setting reasserts itself the moment fullscreen is left.
	# Skipped when the window is already windowed: the size is then the player's.
	if bool(plan["set_size"]):
		window.size = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
	WindowMode.note_applied()
	window.content_scale_factor = UI_SCALES[clampi(scale_index, 0, UI_SCALES.size() - 1)]


## The "news of other countries" switch, read once per settings revision rather
## than from disk at every month end (main.gd asks inside the month's UI tail).
## `revision` moves on every Settings change, the one place that writes it.
static var _foreign_news := false
static var _foreign_news_revision := -1


static func foreign_news() -> bool:
	if _foreign_news_revision != revision:
		_foreign_news = MessageSettings.foreign_news(CONFIG_PATH)
		_foreign_news_revision = revision
	return _foreign_news


## Read at play time rather than applied at boot: a settings change made from
## the in-game pause menu governs the very next sting with no second wiring
## path, and nothing in the boot order comes to depend on audio existing.
static func sound_enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	return bool(cfg.get_value("audio", "enabled", DEFAULT_SOUND))


## Read at play time, for sound_enabled()'s reason: the pause menu's change
## governs the very next tween.
static func motion_enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	return bool(cfg.get_value("display", "motion", DEFAULT_MOTION))


## Read when the settings screen has saved (sound_bed.gd watches `revision`),
## for sound_enabled()'s reason.
static func ambient_enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	return bool(cfg.get_value("audio", "ambient", DEFAULT_AMBIENT))


func _save_and_apply() -> void:
	var fullscreen := _fullscreen_button.selected == 1
	var resolution_index := _resolution_button.selected
	var scale_index := _scale_button.selected
	var sound_on := _sound_button.selected == 1
	var motion_on := _motion_button.selected == 1
	var ambient_on := _ambient_button.selected == 1
	var language := String(Strings.languages()[_language_button.selected]["code"])

	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("display", "language", language)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "resolution_index", resolution_index)
	cfg.set_value("display", "ui_scale_index", scale_index)
	cfg.set_value("audio", "enabled", sound_on)
	cfg.set_value("audio", "ambient", ambient_on)
	cfg.set_value("display", "motion", motion_on)
	cfg.set_value(MessageSettings.SECTION, MessageSettings.FOREIGN_NEWS_KEY, _foreign_news_button.selected == 1)
	cfg.save(CONFIG_PATH)
	revision += 1

	# The size is the player's to drag: only a resolution picked HERE asks for the
	# preset, not Sound or Motion changing beside it.
	_apply(get_window(), fullscreen, resolution_index, scale_index, resolution_index != _applied_resolution)
	_applied_resolution = resolution_index
	_resolution_button.disabled = fullscreen
	if language != Strings.language() and Strings.set_language(language):
		_rebuild()


# --- construction ------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(480, 300)
	_build()
	# F11 (and any other writer of the file) can move the settings while this panel
	# sits built and hidden; showing it reads them again, or the next row changed
	# would write the stale ones back.
	visibility_changed.connect(func():
		if visible:
			_load_into_controls()
	)


## A language change rebuilds the screen: tr() text is the language it was built in,
## and this is the one screen the player is looking at while the language changes.
## The old tree leaves at once (it is mid-signal, so it is freed, not deleted).
func _rebuild() -> void:
	remove_child(_content)
	_content.queue_free()
	_message_buttons = {}
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	_content = margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	PanelKit.line(root, tr("SETTINGS"), PanelKit.Tone.PLAIN)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)

	var language_names: Array = []
	for entry in Strings.languages():
		language_names.append(String(entry["name"]))
	_language_button = _add_row(grid, tr("Language"), language_names)
	_fullscreen_button = _add_row(grid, tr("Window (F11)"), [tr("Windowed"), tr("Fullscreen")])
	_resolution_button = _add_row(grid, tr("Resolution"), _resolution_labels())
	_scale_button = _add_row(grid, tr("Interface scale"), _scale_labels())
	_sound_button = _add_row(grid, tr("Sound"), [tr("Off"), tr("On")])
	_ambient_button = _add_row(grid, tr("Ambience"), [tr("Off"), tr("On")])
	_motion_button = _add_row(grid, tr("Motion"), [tr("Off"), tr("On")])
	_foreign_news_button = _add_row(grid, tr("News of other countries"), [tr("Off"), tr("On")])

	PanelKit.line(root, tr(tr("The language applies in full to windows opened after the change; load a game again to apply it to every window.")))

	_build_messages(root)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(footer)

	var close := Button.new()
	close.text = tr("Close")
	close.pressed.connect(func():
		hide()
		closed.emit()
	)
	footer.add_child(close)

	_load_into_controls()


func _add_row(grid: GridContainer, label_text: String, options: Array) -> OptionButton:
	# A grid CELL rather than a row, so it is built here rather than by PanelKit:
	# every kit primitive that draws prose autowraps, and an autowrapping label in a
	# fixed two-column grid reports a minimum width of one word and lets the column
	# collapse. The kit owns whole rows and whole tables; a cell inside somebody
	# else's grid is the panel's own.
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


## V4.8c. One row per event category, one band picker per switch. Its own grid
## (five columns) rather than rows in the display grid above, because these are
## a table read across -- a category's four switches side by side -- and the
## two-column grid would stack them into thirty-six rows.
func _build_messages(root: VBoxContainer) -> void:
	PanelKit.line(root, tr("MESSAGES"), PanelKit.Tone.PLAIN)
	PanelKit.line(root, tr("For each kind of event, the least severe one each switch fires for. Pause off still stops the clock in a decision's last month."))

	var grid := GridContainer.new()
	grid.columns = 1 + MessageSettings.SWITCHES.size()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)

	grid.add_child(Label.new())
	for heading in MessageSettings.SWITCH_LABELS:
		var label := Label.new()
		label.text = String(heading)
		grid.add_child(label)

	for category in EventsK.CATEGORIES:
		var name_label := Label.new()
		name_label.text = String(category).capitalize()
		grid.add_child(name_label)
		var row := {}
		for switch in MessageSettings.SWITCHES:
			var button := OptionButton.new()
			button.custom_minimum_size.x = BAND_BUTTON_WIDTH
			for band in MessageSettings.BAND_LABELS:
				button.add_item(String(band))
			button.item_selected.connect(func(_index: int): _save_messages())
			grid.add_child(button)
			row[switch] = button
		_message_buttons[category] = row


## The register as the pickers show it. Index + 1 is the threshold: BAND_LABELS
## is ordered so the two are one addition apart.
func messages_from_controls() -> Dictionary:
	var out := {}
	for category in _message_buttons.keys():
		var row := {}
		for switch in _message_buttons[category].keys():
			row[switch] = int(_message_buttons[category][switch].selected) + 1
		out[category] = row
	return out


func _save_messages() -> void:
	MessageSettings.save_to(messages_from_controls(), CONFIG_PATH)


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
	var codes: Array[String] = []
	for entry in Strings.languages():
		codes.append(String(entry["code"]))
	_language_button.select(maxi(codes.find(Strings.language()), 0))
	_fullscreen_button.select(1 if fullscreen else 0)
	_resolution_button.select(clampi(int(cfg.get_value("display", "resolution_index", DEFAULT_RESOLUTION_INDEX)), 0, RESOLUTIONS.size() - 1))
	_applied_resolution = _resolution_button.selected
	_scale_button.select(clampi(int(cfg.get_value("display", "ui_scale_index", DEFAULT_SCALE_INDEX)), 0, UI_SCALES.size() - 1))
	_sound_button.select(1 if bool(cfg.get_value("audio", "enabled", DEFAULT_SOUND)) else 0)
	_ambient_button.select(1 if bool(cfg.get_value("audio", "ambient", DEFAULT_AMBIENT)) else 0)
	_motion_button.select(1 if bool(cfg.get_value("display", "motion", DEFAULT_MOTION)) else 0)
	_foreign_news_button.select(1 if bool(cfg.get_value(
		MessageSettings.SECTION, MessageSettings.FOREIGN_NEWS_KEY, MessageSettings.DEFAULT_FOREIGN_NEWS)) else 0)
	_resolution_button.disabled = fullscreen
	var messages := MessageSettings.load_from(CONFIG_PATH)
	for category in _message_buttons.keys():
		for switch in _message_buttons[category].keys():
			_message_buttons[category][switch].select(
				MessageSettings.threshold(messages, category, switch) - 1)
