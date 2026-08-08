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
const SaveLoadPanel = preload("res://src/ui/save_load_panel.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const CreditsPanel = preload("res://src/ui/credits_panel.gd")
const NationSelectPanel = preload("res://src/ui/nation_select_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const GAME_SCENE := "res://src/ui/main.tscn"

var _continue_button: Button
var _new_game_button: Button
var _load_panel
var _settings_panel
var _credits_panel
var _nation_select_panel
var _loader: DataLoader
## The menu entry that opened the current overlay, so closing it puts keyboard
## focus back where the player left it rather than nowhere.
var _focus_return: Control


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
	add_child(_build_background())
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


func _build_background() -> Control:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.07, 0.08, 0.09)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return background


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
	if _focus_return != null:
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
func _start_game(load_slot: String, nation_id: String = "", scenario_id: String = "") -> void:
	# Untyped, like main.gd's panel references: pending_load_slot is a script
	# property, and a Node-typed variable cannot see it without a cast that buys
	# nothing here.
	var game = load(GAME_SCENE).instantiate()
	game.pending_load_slot = load_slot
	if not nation_id.is_empty():
		game.pending_player_id = nation_id
	game.pending_scenario_id = scenario_id
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	queue_free()
