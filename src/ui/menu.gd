extends Control

## The main menu -- the game's entry point, and until U1 the thing it did not
## have. Before this, project.godot booted straight into src/ui/main.tscn, which
## started a France game in _ready() with no way to choose otherwise and no way
## back out.
##
## main.tscn stays the *game* scene rather than growing a menu state inside it.
## Two reasons: tests/test_game_loop.gd loads main.tscn directly and expects a
## running game two frames later, and a scene that is either a menu or a game
## depending on a flag is the shape that turns into a state machine nobody can
## read. One scene, one job -- docs/engine-decision.md Rule 3.

const SaveManager = preload("res://src/core/save_manager.gd")
const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const MapView = preload("res://src/ui/map_view.gd")
const SaveLoadPanel = preload("res://src/ui/save_load_panel.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const CreditsPanel = preload("res://src/ui/credits_panel.gd")
const NationSelectPanel = preload("res://src/ui/nation_select_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const LoadingScreen = preload("res://src/ui/loading_screen.gd")

## The nation the menu plate builds its throwaway month-0 state around. FRA is
## the premise nation, and the plate reads only content that is identical for
## every viewer at month 0: the unrest ring needs grievance past the threshold,
## the campaign ring a running effort, markers and plants non-empty registers
## -- all four come back empty before the first tick, so the door shows a clean
## opening map whatever nation the player then picks.
const VIEWER_NATION_ID := "FRA"

var _continue_button: Button
var _new_game_button: Button
var _load_panel
var _settings_panel
var _credits_panel
var _nation_select_panel
var _loader: DataLoader
var _plate
var _viewer_state
## The menu entry that opened the current overlay, so closing it puts keyboard
## focus back where the player left it rather than nowhere.
var _focus_return: Control
## The loading screen once a game is starting; a second start is refused while
## it runs (a double-click on Continue would otherwise boot two games).
var _loading


func _ready() -> void:
	# First scene up, so this is where the saved display settings land.
	SettingsPanel.apply_saved(get_window())
	# Each scene root carries its own copy -- a Theme propagates down the tree,
	# not across a change_scene_to_file().
	UiTheme.apply(self)

	# New Game needs to know which nations are playable before it can offer a
	# choice -- the same data main.gd loads to build the actual game, read here
	# a second time rather than threaded through the scene change, which cannot
	# pass an argument (see _start_game()'s note).
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		for e in _loader.errors:
			push_error(e)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Presence (V3.6): the door shows the game it opens. A real MapView over a
	# real month-0 GameState rather than a reduced copy of the map's draw
	# passes -- duplicating the lon/lat->screen projection here is the
	# two-copies trap AGENTS.md warns about, and reusing the whole view means
	# the menu cannot drift from the game's own map. The state is a viewer,
	# built and discarded here; New Game builds its own in main.gd as before.
	_viewer_state = GameState.new_game(_loader, VIEWER_NATION_ID)
	_plate = MapView.new()
	_plate.setup(_loader, _viewer_state)
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_plate)
	# IGNORE, set AFTER add_child: map_view's own _ready() claims STOP, and a
	# filter set before that call is silently clobbered by it. The front door is
	# a window onto the game, not a second game to play before the menu -- no
	# pan, no zoom, no hover, and no code in the map that knows it is in a menu.
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_build_scrim())
	add_child(_build_menu())

	_load_panel = SaveLoadPanel.new()
	_load_panel.load_requested.connect(_start_game)
	_add_overlay(_load_panel)
	# After _add_overlay(), never before: the panel builds its children in
	# _ready(), which does not run until add_child() puts it in the tree, so
	# calling this a line earlier silently does nothing.
	_load_panel.hide_save_row()

	_settings_panel = SettingsPanel.new()
	_add_overlay(_settings_panel)

	_credits_panel = CreditsPanel.new()
	_add_overlay(_credits_panel)

	_nation_select_panel = NationSelectPanel.new()
	_nation_select_panel.nation_selected.connect(func(id, scenario_id): _start_game("", id, scenario_id))
	_add_overlay(_nation_select_panel)
	_nation_select_panel.set_nations(
		_playable_nations(), _loader.scenarios, _person_name_map()
	)

	# Godot focuses nothing by default, and a menu with no focused control
	# cannot be driven from the keyboard at all -- arrow keys and Enter go
	# nowhere until something has focus. grab_focus() only works in the tree,
	# so it happens here rather than in _build_menu().
	var first: Button = _new_game_button if _continue_button.disabled else _continue_button
	first.grab_focus()


## Every nation the loaded data marks playable, sorted by id so the list order
## is stable and matches every other place this project iterates nations.gd.
func _playable_nations() -> Array:
	var ids: Array = _loader.nations.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		var n = _loader.nations[id]
		if n.playable:
			out.append(n)
	return out


## Flattened for nation_select_panel.gd, which is the one surface that resolves a
## person without holding a loader -- see that file's `_person_names`.
func _person_name_map() -> Dictionary:
	var out := {}
	for pid in _loader.person_by_id.keys():
		out[pid] = _loader.person_by_id[pid].person_name
	return out


## A scrim, not a backdrop: the map is behind it, the menu column on top of it.
## The pre-V3.6 background colour at 45% alpha -- enough dimming that the brass
## column keeps its contrast whatever the map is showing under it.
func _build_scrim() -> Control:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.07, 0.08, 0.09, 0.45)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return scrim


func _build_menu() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var title := Label.new()
	title.text = "NATION SIMULATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 16
	column.add_child(spacer)

	# Continue first and disabled when there is nothing to continue, because it
	# is the entry most launches want and a menu that makes you find the newest
	# slot yourself is a menu that wastes a click every session.
	var slots := SaveManager.list_slots()
	_continue_button = _add_entry(column, "Continue", func(): _start_game(slots[0]))
	_continue_button.disabled = slots.is_empty()

	_new_game_button = _add_entry(column, "New Game", func(): _show(_nation_select_panel))
	_new_game_button.disabled = _playable_nations().is_empty()
	_add_entry(column, "Load Game", func(): _show(_load_panel))
	_add_entry(column, "Settings", func(): _show(_settings_panel))
	_add_entry(column, "Credits", func(): _show(_credits_panel))
	_add_entry(column, "Quit", func(): get_tree().quit())

	return center


func _add_entry(column: VBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 34)
	button.pressed.connect(action)
	column.add_child(button)
	return button


## Each panel gets its own full-rect CenterContainer, and it is the *holder*
## that is shown and hidden rather than the panel -- a hidden holder cannot eat
## clicks meant for the menu buttons underneath it.
##
## main.gd's _add_centered() does nearly the same thing and is deliberately not
## shared. U2 docked five of main.gd's nine overlays as dashboard tabs, but the
## other four -- election results, pause, settings, save/load -- are genuinely
## modal and still use _add_centered(), so both this copy and that one keep a
## caller. Extracting ten lines of node plumbing into a module shared by two
## call sites is not worth the indirection.
func _add_overlay(panel: Control) -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(panel)
	holder.hide()
	add_child(holder)

	panel.closed.connect(func(): _close(panel))


func _show(panel: Control) -> void:
	_focus_return = get_viewport().gui_get_focus_owner()
	panel.get_parent().show()
	panel.show()
	if panel.has_method("mark_dirty"):
		panel.mark_dirty()
	# Same reason _ready() focuses the first menu entry: a panel with no focused
	# control cannot be driven from the keyboard at all. The nation select panel
	# never had this and so was mouse-only from V1.2a until V1.2e noticed.
	if panel.has_method("focus_first"):
		panel.focus_first()


func _close(panel: Control) -> void:
	panel.get_parent().hide()
	# A disabled button must not take focus back: Godot paints the brass focus
	# stylebox over any state, so a disabled Continue wearing it read as enabled
	# until clicked (playtest 2026-09-05).
	if _focus_return != null and not _focus_return.disabled:
		_focus_return.grab_focus()


## Escape closes whatever is open, and focus goes back to the entry that opened
## it. Without this an overlay can only be dismissed with the mouse, which is
## the one input a main menu should never require.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.keycode != KEY_ESCAPE:
		return
	for panel in [_load_panel, _settings_panel, _credits_panel, _nation_select_panel]:
		if panel.get_parent().visible:
			_close(panel)
			return


## Instantiated and handed a property rather than routed through
## change_scene_to_file(), which cannot pass an argument. The alternative is a
## one-field autoload, and docs/tooling.md already records that a headless
## editor run strips autoloads out of project.godot -- a global that vanishes
## under a tool the project uses is not the cheap option it looks like.
##
## An empty slot means a new game, in which case `nation_id` is the player's
## choice from the nation select panel and `scenario_id` their choice of start
## ("" for the standard one). Both are ignored when loading -- a save carries
## its own player_nation_id and scenario_id, and main.gd's load path replaces
## the whole GameState wholesale after building a throwaway one.
##
## V4.9a: the scene is built by the loading screen (boot_stages.gd), a stage per
## frame, rather than here in one call that froze the window for seconds. The
## pending_* properties are set there, the same three this used to set.
func _start_game(load_slot: String, nation_id: String = "", scenario_id: String = "") -> void:
	if _loading != null:
		return
	# The plate is under an opaque screen from here on: hidden, it costs the
	# boot no frame time.
	_plate.hide()
	_loading = LoadingScreen.new()
	add_child(_loading)
	_loading.entered.connect(func(_game: Node): queue_free())
	_loading.start(nation_id, scenario_id, load_slot)
