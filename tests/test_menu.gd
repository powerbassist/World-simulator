extends SceneTree

## Headless test: godot --headless --script res://tests/test_menu.gd
## Non-zero exit on any failure.
##
## The other wiring test. tests/test_game_loop.gd proves the clock reaches the
## simulation once a game is running; this one proves you can get a game
## running at all -- the menu builds, its overlays start hidden, and its two
## ways into the game (New Game, and Continue/Load with a slot) both land on a
## Main with a live GameState.
##
## Driven a frame at a time, per the Control-outside-the-tree gotcha in
## docs/engine-decision.md: a node only gets its _ready() when it is actually
## in the tree, so nothing here can be asserted during _init().

## suite-exclusive: backs up and restores user://settings.cfg

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const Clock = preload("res://src/core/clock.gd")
const LoadingScreen = preload("res://src/ui/loading_screen.gd")

const SLOT := "__test_menu_continue__"
const SAVED_YEAR := 2031
const SAVED_MONTH := 7
const SAVED_DAY := 23

var _failures: Array[String] = []
var _menu
var _frame := 0
## The two Main instances _start_game() creates this run -- one from the
## Continue/Load path (SLOT), one from New Game's nation select (DEU). Neither
## is read off current_scene, since the second _start_game() call overwrites
## it: each is captured as the child root.add_child() just appended.
var _continued_game
var _new_game_deu
## The Main that the nation-select panel's own buttons produced, driven end to
## end -- V1.2e. The other two are started by calling _start_game() directly,
## which is exactly the path that would keep passing if the panel stopped
## emitting a scenario at all.
var _new_game_fra_scenario
## The start list rows _check_scenario_select() leaves on the panel, and which
## of them is Inheritance -- _check_start_row_geometry() reads them a frame
## later, because the wrapped height only exists once the containers have
## sorted and the autowrap labels re-measured at the real width (the fold
## finding in docs/panel-system.md: a read in the build frame answers for the
## previous width).
var _start_rows: Array = []
var _start_inheritance_index := -1


func _init() -> void:
	_menu = load("res://src/ui/menu.tscn").instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			return false  # let the menu's _ready() run
		2:
			_check_structure()
			_check_settings()
			_check_sound_setting()
			_check_plate()
			_check_scenario_select()
			_write_save()
			return false
		3:
			# One frame of nothing, deliberately: the start list's containers sort
			# and its autowrap labels re-measure at the real width on the frame
			# after the build -- the frame _check_start_row_geometry() reads them
			# on (docs/panel-system.md's fold finding).
			return false
		4:
			_check_start_row_geometry()
			_watch_loading("scenario")
			return false
		_:
			return _drive_starts()


## V4.9a. A start is no longer one synchronous call: the loading screen boots
## the game a stage per frame and the menu frees itself once the game is in.
## So the three starts run one after another, each on a FRESH menu (the old
## one is gone), and each game is captured off the loading screen's `entered`
## signal rather than off the root's last child -- the loading screen moves
## itself there to fade off the game.
const START_TIMEOUT_FRAMES := 3000
var _start_queue: Array = ["slot", "deu"]
var _captured := ""
var _waiting_frames := 0
var _progress_seen: Array[float] = []
var _menu_ready_frame := -1


func _watch_loading(which: String) -> void:
	var loading = _menu._loading
	if loading == null:
		_fail("starting a game (%s) put up no loading screen" % which)
		_finish_all()
		return
	_check_loading_screen(loading, which)
	_captured = ""
	_waiting_frames = 0
	_progress_seen.clear()
	loading.entered.connect(func(game: Node):
		match which:
			"scenario":
				_new_game_fra_scenario = game
			"slot":
				_continued_game = game
			"deu":
				_new_game_deu = game
		_captured = which
	)
	_watching = loading
	_waiting_start = true


## The loading screen frees itself once its game is in, so whether a start is
## still running is its own flag rather than a test on a reference that goes
## stale mid-wait.
var _watching
var _waiting_start := false


func _drive_starts() -> bool:
	if _waiting_start:
		if _captured.is_empty():
			if is_instance_valid(_watching) and _watching.boot != null:
				_progress_seen.append(float(_watching.boot.progress()))
			_waiting_frames += 1
			if _waiting_frames > START_TIMEOUT_FRAMES:
				_fail("a start never entered its game in %d frames" % START_TIMEOUT_FRAMES)
				_finish_all()
			return false
		_check_progress_monotonic(_captured)
		_watching = null
		_waiting_start = false
		if _start_queue.is_empty():
			_finish_all()
			return false
		_menu = load("res://src/ui/menu.tscn").instantiate()
		root.add_child(_menu)
		_menu_ready_frame = _frame
		return false
	if _menu_ready_frame >= 0 and _frame > _menu_ready_frame:
		_menu_ready_frame = -1
		var which: String = _start_queue.pop_front()
		if which == "slot":
			_menu._start_game(SLOT)
			# Refused while a boot runs: a double-click on Continue must not
			# start two games.
			_menu._start_game(SLOT)
			if _menu.get_children().filter(func(c): return c is LoadingScreen).size() != 1:
				_fail("a second _start_game() during a boot put up a second loading screen")
		else:
			_menu._start_game("", "DEU")
		_watch_loading(which)
	return false


func _finish_all() -> void:
	_check_loaded_game()
	_check_new_game_nation_select()
	_check_new_game_scenario()
	_cleanup()
	_finish()


## The loading screen is opaque to input and holds the focus, so a menu button
## left focused behind it cannot start a second game on Enter.
func _check_loading_screen(loading: Control, which: String) -> void:
	if loading.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("the loading screen (%s) lets clicks through to the menu" % which)
	if loading.get_viewport().gui_get_focus_owner() != loading:
		_fail("the loading screen (%s) does not hold the keyboard focus" % which)


## The bar is honest only if it never goes back.
func _check_progress_monotonic(which: String) -> void:
	for i in range(1, _progress_seen.size()):
		if _progress_seen[i] < _progress_seen[i - 1]:
			_fail("the loading bar (%s) went backwards: %.3f after %.3f" % [
				which, _progress_seen[i], _progress_seen[i - 1]])
			return


func _check_structure() -> void:
	if _menu._continue_button == null:
		_fail("menu did not build its Continue button")
		return

	# Not a tautology against list_slots(): it catches the condition being
	# inverted, which is the way this particular line goes wrong.
	var expected := SaveManager.list_slots().is_empty()
	if _menu._continue_button.disabled != expected:
		_fail("Continue disabled=%s with %d save(s) on disk" % [
			_menu._continue_button.disabled, SaveManager.list_slots().size()
		])

	# Every overlay's holder starts hidden. A visible full-rect holder swallows
	# the clicks meant for the menu buttons under it, which looks like the menu
	# being dead rather than like a layering bug.
	for named in [["load", _menu._load_panel], ["settings", _menu._settings_panel], ["credits", _menu._credits_panel], ["nation select", _menu._nation_select_panel]]:
		var panel = named[1]
		if panel == null:
			_fail("menu did not build its %s panel" % named[0])
			continue
		if panel.get_parent().visible:
			_fail("%s panel's holder is visible before anything opened it" % named[0])

	_menu._show(_menu._load_panel)
	if not _menu._load_panel.get_parent().visible:
		_fail("opening the load panel did not show its holder")
	_menu._load_panel.get_parent().hide()

	# V1.2a: New Game opens a nation choice rather than starting France
	# outright, and every nation the real data marks playable is offered --
	# at minimum France and Germany.
	var ids := []
	for n in _menu._playable_nations():
		ids.append(n.id)
	if not ids.has("FRA") or not ids.has("DEU"):
		_fail("nation select does not offer both FRA and DEU: %s" % [ids])
	if _menu._new_game_button.disabled:
		_fail("New Game is disabled even though playable nations exist")

	# The menu has no game to save, so the save row must be gone rather than
	# present and inert. Checked because the first attempt at this called
	# hide_save_row() before the panel was in the tree, where it did nothing
	# and said nothing.
	if _menu._load_panel._save_row.visible:
		_fail("the menu's load panel still shows its save row")


## Settings are only settings if they survive a relaunch, so what is checked
## here is the round trip: change the controls, and a freshly built panel comes
## back showing the same thing, with the interface scale actually applied to the
## window rather than merely recorded.
##
## The real user://settings.cfg is backed up and put back afterwards -- a test
## that silently resets the player's display settings is worse than no test.
func _check_settings() -> void:
	var panel = _menu._settings_panel
	if panel == null:
		_fail("menu did not build its settings panel")
		return

	var backup := ""
	var had_config := FileAccess.file_exists(SettingsPanel.CONFIG_PATH)
	if had_config:
		backup = FileAccess.get_file_as_string(SettingsPanel.CONFIG_PATH)

	const SCALE_INDEX := 3
	const RESOLUTION_INDEX := 2
	panel._fullscreen_button.select(0)
	panel._resolution_button.select(RESOLUTION_INDEX)
	panel._scale_button.select(SCALE_INDEX)
	panel._save_and_apply()

	var expected: float = SettingsPanel.UI_SCALES[SCALE_INDEX]
	if not is_equal_approx(root.content_scale_factor, expected):
		_fail("interface scale saved but not applied: window is at %s, expected %s" % [
			root.content_scale_factor, expected
		])

	# A second panel reads the file, not the first panel's memory -- which is
	# what the next launch will do.
	var reloaded = SettingsPanel.new()
	root.add_child(reloaded)
	if reloaded._scale_button.selected != SCALE_INDEX or reloaded._resolution_button.selected != RESOLUTION_INDEX:
		_fail("settings did not survive a reload: scale %d, resolution %d" % [
			reloaded._scale_button.selected, reloaded._resolution_button.selected
		])
	reloaded.queue_free()

	if had_config:
		var restore := FileAccess.open(SettingsPanel.CONFIG_PATH, FileAccess.WRITE)
		restore.store_string(backup)
		restore.close()
		SettingsPanel.apply_saved(root)
	else:
		DirAccess.remove_absolute(SettingsPanel.CONFIG_PATH)
		root.content_scale_factor = 1.0


## V3.6: the Sound row persists, and sound_enabled() reads the file rather than
## the panel. OptionButton.select() emits nothing, so every mutation here calls
## _save_and_apply() explicitly, like _check_settings() above. Rides this file's
## own backup/restore discipline: the real settings.cfg goes back exactly as it
## was found (or stays absent).
func _check_sound_setting() -> void:
	var panel = _menu._settings_panel
	if panel == null:
		_fail("menu did not build its settings panel")
		return

	var backup := ""
	var had_config := FileAccess.file_exists(SettingsPanel.CONFIG_PATH)
	if had_config:
		backup = FileAccess.get_file_as_string(SettingsPanel.CONFIG_PATH)

	# Off writes the key; the static read sees it on the next launch's terms.
	panel._sound_button.select(0)
	panel._save_and_apply()
	if SettingsPanel.sound_enabled():
		_fail("Sound set to Off but sound_enabled() reads true")

	panel._sound_button.select(1)
	panel._save_and_apply()
	if not SettingsPanel.sound_enabled():
		_fail("Sound set to On but sound_enabled() reads false")

	# The default must be the ABSENT key's answer, not a stored true: store a
	# false, then save a config that carries no audio section at all -- true can
	# now only mean the default fired. (ConfigFile has no per-key erase, so the
	# section is dropped by rebuilding the file without it.)
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value("audio", "enabled", false)
	cfg.save(SettingsPanel.CONFIG_PATH)
	if SettingsPanel.sound_enabled():
		_fail("stored [audio] enabled=false but sound_enabled() reads true")
	var fresh := ConfigFile.new()
	fresh.set_value("display", "ui_scale_index", 1)
	fresh.save(SettingsPanel.CONFIG_PATH)
	if not SettingsPanel.sound_enabled():
		_fail("no [audio]/enabled in settings.cfg but sound_enabled() is not the default true")

	if had_config:
		var restore := FileAccess.open(SettingsPanel.CONFIG_PATH, FileAccess.WRITE)
		restore.store_string(backup)
		restore.close()
	else:
		DirAccess.remove_absolute(SettingsPanel.CONFIG_PATH)


## V3.6: the front door shows the game it opens. A real MapView over a real
## month-0 viewer state, and mouse-dead -- a window onto the game, not a second
## game to play before the menu. Built in the menu's _ready(), so frame 2 is
## the first frame anything can be read off it.
func _check_plate() -> void:
	if _menu._viewer_state == null:
		_fail("the menu built no viewer GameState for the plate")
	if _menu._plate == null or not _menu._plate.is_inside_tree():
		_fail("the menu has no map plate")
	elif _menu._plate.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("the menu plate is interactive (mouse_filter is not IGNORE)")
	elif not _menu._plate.visible:
		_fail("the menu plate is built but hidden")


## A save the menu can be asked to continue from. Written straight through
## SaveManager rather than by playing a game, because what is under test here
## is the menu -> Main handoff, not the simulation.
func _write_save() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
		return

	var state = GameState.new_game(loader, "FRA")
	state.year = SAVED_YEAR
	state.month = SAVED_MONTH

	var clock := Clock.new()
	clock.day = SAVED_DAY
	var error := SaveManager.save_game(state, clock, SLOT)
	clock.free()  # a Node created off-tree isn't owned by anything; free it explicitly
	if not error.is_empty():
		_fail("could not write the test save: %s" % error)


func _check_loaded_game() -> void:
	var game = _continued_game
	if game == null:
		_fail("_start_game() did not produce a Main instance for the Continue/Load path")
		return
	if game._state == null:
		_fail("the game scene the menu started has no GameState")
		return

	# pending_load_slot has to reach main.gd's existing load path, not merely be
	# stored on it -- the date is the cheapest proof the save actually replaced
	# the new game that _ready() builds first.
	if game._state.year != SAVED_YEAR or game._state.month != SAVED_MONTH:
		_fail("continued into %d-%d, expected the saved %d-%d" % [
			game._state.year, game._state.month, SAVED_YEAR, SAVED_MONTH
		])

	var clock: Node = game.get_node("Clock")
	if clock.year != SAVED_YEAR or clock.month != SAVED_MONTH or clock.day != SAVED_DAY:
		_fail("clock resumed at %d-%d-%d, expected %d-%d-%d" % [
			clock.year, clock.month, clock.day, SAVED_YEAR, SAVED_MONTH, SAVED_DAY
		])

	_check_pause_menu(game, clock)


## The Play button on a row, wherever the row puts it -- a nation row is
## [Label, Button] and a start row is [VBox, Button], and a test that indexed
## either would break on the other.
func _play_button(row: Control) -> Button:
	for child in row.get_children():
		if child is Button:
			return child
	return null


## V1.2e: the two-step flow, driven through the panel's own buttons rather than
## by calling _start_game(). Both halves fail silently otherwise -- a panel that
## stopped offering starts would still start games, and a signal that dropped
## its second argument would still start the right nation.
func _check_scenario_select() -> void:
	var panel = _menu._nation_select_panel

	# France has an authored start, so its Play opens the start list rather than
	# starting the game. Germany would do the same; a nation with no scenario
	# must NOT, and that asymmetry is the thing worth asserting.
	var fra_row: Control = null
	for row in panel._list.get_children():
		for child in row.get_children():
			if child is Label and child.text.begins_with("France"):
				fra_row = row
	if fra_row == null:
		_fail("nation select has no France row")
		return

	# Keyboard-drivable, which this panel was not from V1.2a until V1.2e: nothing
	# ever called grab_focus() on it, so Tab landed nowhere and the whole New
	# Game flow was mouse-only. Silent by construction -- every automated check
	# emitted `pressed` directly and never asked what had focus.
	# Focus must land INSIDE the panel, not merely be non-null: the main menu's
	# own New Game button keeps focus otherwise, which is what made the first
	# version of this assertion pass with the fix disabled.
	_menu._show(panel)
	var opened: Control = root.gui_get_focus_owner()
	if opened == null or not panel.is_ancestor_of(opened):
		_fail("opening nation select left focus outside it, so it cannot be driven from the keyboard")

	# Closing must never hand focus to a disabled control: Godot paints the brass
	# focus stylebox over any state, so a disabled Continue wearing it read as
	# enabled until clicked (playtest 2026-09-05). A click gives a disabled
	# button focus anyway, so Continue is exactly the control an overlay can be
	# asked to return to -- and disabled is forced here rather than assumed,
	# because a machine with saves on disk would leave Continue enabled and the
	# case would silently not reproduce.
	_menu._continue_button.disabled = true
	_menu._continue_button.grab_focus()
	_menu._show(panel)
	_menu._close(panel)
	var returned: Control = root.gui_get_focus_owner()
	var returned_button: Button = returned as Button
	if returned_button != null and returned_button.disabled:
		_fail("closing an overlay handed focus back to the disabled Continue")
	_menu._show(panel)

	var before: int = root.get_child_count()
	_play_button(fra_row).pressed.emit()
	if root.get_child_count() != before:
		_fail("choosing a nation with authored starts began a game instead of offering them")
		return
	if not panel._title.text.begins_with("CHOOSE A START"):
		_fail("choosing France did not open the start list: title is '%s'" % panel._title.text)
		return

	# Standard first, then the authored ones -- the baseline must not be buried
	# under the variants, since it is the game every measured figure describes.
	var rows: Array = panel._list.get_children()
	if rows.size() < 2:
		_fail("France's start list offers %d row(s), expected Standard plus at least one authored start" % rows.size())
		return

	# Focus has to survive the list swap too -- the control that had it was just
	# queue_free()d, and a panel focused on a dead node is as keyboard-dead as
	# one focused on nothing.
	var focused: Control = root.gui_get_focus_owner()
	if focused == null or not is_instance_valid(focused) or not panel.is_ancestor_of(focused):
		_fail("swapping to the start list left focus on nothing, on a freed control, or outside the panel")

	var found_inheritance := -1
	for i in rows.size():
		for child in rows[i].get_children():
			if child is VBoxContainer and child.get_child(0).text == "Inheritance":
				found_inheritance = i
	if found_inheritance <= 0:
		_fail("Inheritance is not offered after Standard in France's start list (index %d)" % found_inheritance)
		return

	# The Inheritance press moves to _check_start_row_geometry(): the wrapped
	# height it asserts on only exists a frame after this build, and starting
	# the game here would free the menu before that frame could run.
	_start_rows = rows
	_start_inheritance_index = found_inheritance


## The Inheritance row's description wraps at the real width; the row must
## reserve that height or the Play button rides up onto the text (playtest
## 2026-09-05). Standard's short description cannot expose the bug, so the
## comparison is against it. Runs a frame after _check_scenario_select() built
## the list -- container sorting and the autowrap label's re-measure settle on
## the frame after the build (docs/panel-system.md's fold finding).
func _check_start_row_geometry() -> void:
	if _start_rows.size() < 2 or _start_inheritance_index < 1:
		_fail("start rows were not captured for the wrapped-height check")
		return

	var one_line: Control = _start_rows[0]
	var wrapped: Control = _start_rows[_start_inheritance_index]
	if not is_instance_valid(one_line) or not is_instance_valid(wrapped):
		_fail("the start rows were freed before the geometry check could read them")
		return
	if wrapped.size.y <= one_line.size.y:
		_fail("the wrapped start row reserves no more height than the one-line row (%.0f vs %.0f): the Play button rides its own text" % [
			wrapped.size.y, one_line.size.y
		])

	_play_button(wrapped).pressed.emit()


## The chosen start has to reach main.gd's pending_scenario_id and then the
## GameState, not merely be emitted -- the same property _check_loaded_game()
## proves for Continue and _check_new_game_nation_select() for the nation.
func _check_new_game_scenario() -> void:
	var game = _new_game_fra_scenario
	if game == null:
		_fail("pressing Play on a start did not produce a Main instance")
		return
	if game._state == null:
		_fail("the New-Game-with-scenario scene has no GameState")
		return
	if game._state.scenario_id != "fra_inheritance":
		_fail("started under scenario '%s', expected fra_inheritance" % game._state.scenario_id)
		return
	if game._state.player_nation_id != "FRA":
		_fail("the scenario start began as '%s', expected FRA" % game._state.player_nation_id)

	# The scenario's own effect, not just its id: a scenario_id that arrived
	# without its overrides being applied is the failure this catches.
	var loader = game._loader
	var expected: float = loader.scenarios["fra_inheritance"].debt_to_gdp_pct
	var got: float = game._state.player().debt_eur_bn / game._state.player().gdp_eur_bn * 100.0
	if absf(got - expected) > 0.1:
		_fail("scenario start's debt is %.1f%% of GDP, expected the authored %.1f%%" % [got, expected])


## V1.2a: choosing Germany from the nation select panel has to reach main.gd's
## pending_player_id, not merely be stored on the menu -- the same "reached the
## existing load path" property _check_loaded_game() proves for Continue.
func _check_new_game_nation_select() -> void:
	var game = _new_game_deu
	if game == null:
		_fail("_start_game(\"\", \"DEU\") did not produce a Main instance")
		return
	if game._state == null:
		_fail("the New-Game-as-DEU scene has no GameState")
		return
	if game._state.player_nation_id != "DEU":
		_fail("New Game with nation_id 'DEU' started as '%s'" % game._state.player_nation_id)
		return

	var deu = game._state.player()
	if deu.has_executive:
		_fail("DEU's player nation carries an executive clock; Germany has none")
	if deu.dissolution_rule != "confidence_failure":
		_fail("DEU's dissolution_rule is '%s', expected confidence_failure" % deu.dissolution_rule)


## Two properties, both of which fail silently rather than loudly:
##   1. Opening pauses and closing restores the state from *before*, so pausing
##      to save does not start the clock on a player who had stopped it.
##   2. The blocking holder is hidden when the menu is closed. A visible
##      full-rect blocking CenterContainer eats every map click for the rest of
##      the session and looks like the map having died.
func _check_pause_menu(game, clock) -> void:
	if game._pause_menu == null:
		_fail("the game scene has no pause menu")
		return
	var holder: Control = game._pause_menu.get_parent()

	# A clean slate: this game boots into a term-start programme pause, and the
	# pause menu's close path now honours a live hold (a save loaded through the
	# menu re-raises one after the menu took its snapshot) -- this check pins the
	# SNAPSHOT contract, the hold pins live in test_playability.
	game._paused_for_programme = false
	game._paused_for_decision = false
	game._state.player().event_queue.clear()

	for was_paused in [true, false]:
		clock.paused = was_paused
		game._open_pause_menu()
		if not holder.visible:
			_fail("opening the pause menu did not show its holder")
		if not clock.paused:
			_fail("the pause menu opened without stopping the clock")

		game._close_pause_menu()
		if holder.visible:
			_fail("the closed pause menu's blocking holder is still visible")
		if clock.paused != was_paused:
			_fail("closing the pause menu left paused=%s, expected the prior %s" % [
				clock.paused, was_paused
			])


func _cleanup() -> void:
	var dir := DirAccess.open(SaveManager.SAVE_DIR)
	if dir == null:
		return
	for p in [SaveManager._path_for(SLOT), SaveManager._path_for(SLOT) + SaveManager.TEMP_SUFFIX]:
		if FileAccess.file_exists(p):
			dir.remove(p)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_menu: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
