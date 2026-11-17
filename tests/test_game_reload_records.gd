extends SceneTree

## Headless test: godot --headless --script res://tests/test_game_reload_records.gd
## Non-zero exit on any failure.
##
## The #396 load-rebuild RECORDs (QA's sweeps), pinned:
##
##   (a) a save that carries NO holds loads paused. set_clock() is the only thing that pauses a
##       hold-free load; every other test loads a game with a decision or a programme pending,
##       which holds the clock on its own, so dropping `clock.paused = true` survived as a mutant.
##   (b) every `static var` in src/ui is accounted for: cleared or forgotten by game_reload.gd
##       (CLEARED_STATICS, MAIN_KEYED_STATICS) or on the cache allow-list below with its reason.
##       A new per-game static then cannot leak across a load unnoticed, and a stale allow-list
##       entry (the var is gone) fails too.
##   (c) a load drops the old main's entries from EVERY main-keyed static, proposal_note's
##       _tabled/_told and region_arrival's _told included.
##   (d) the dev console and its Logger do not outlive the main they were built for: the old
##       console's Logger is removed with it, and the rebuilt game's console is its own.

const GameReload = preload("res://src/ui/game_reload.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const SLOT := "__test_game_reload_records__"

## Statics that are NOT one game's: caches of files or rendered assets, process-wide settings,
## parsed regexes, a session's own memory. Each says why a load may leave it alone.
const NOT_PER_GAME := {
	"audience_talk_view.gd:_faces": "portrait face crops, a cache of assets",
	"backdrop.gd:_material": "the shared blur material",
	"event_art.gd:_cache": "decoded art plates, a cache",
	"glossary.gd:_rows": "the glossary table, read once from data/",
	"glossary.gd:_by_id": "the glossary index over those rows",
	"glossary.gd:_loaded": "whether the glossary has been read",
	"glossary_hint.gd:config_path": "where the settings file is (a test points it elsewhere)",
	"glossary_hint.gd:_shown_in": "this SESSION's hint note; compared by identity and checked with is_instance_valid()",
	"glossary_hint.gd:_card": "the id of that note",
	"glossary_hint.gd:term_read": "whether a term plate has opened since the hint (a session fact)",
	"grade.gd:_material": "the shared photograph grade material",
	"headlines.gd:_tables": "headline tables read from data/headlines/, a cache",
	"icon.gd:_width": "a compiled regex",
	"interface_size.gd:dpi_override": "a test's override of the screen dpi",
	"interface_size.gd:_index": "the text size setting (settings, not a game's)",
	"map_ground.gd:_cached": "the decoded ground raster, a cache",
	"map_ground.gd:_sidecar": "that raster's sidecar data, a cache",
	"map_ground.gd:_attempted": "whether that raster was tried",
	"map_raster.gd:_cached": "the decoded map raster, a cache",
	"map_raster.gd:_attempted": "whether that raster was tried",
	"motion.gd:override": "a test's override of motion",
	"motion.gd:_setting": "the motion setting (settings, not a game's)",
	"motion.gd:_seen_revision": "which settings revision motion last read",
	"motion.gd:_number_re": "a compiled regex",
	"motion.gd:_grouped_re": "a compiled regex",
	"music.gd:override_manifest": "a test's manifest",
	"music.gd:_manifest": "the music manifest read from disk, a cache",
	"portrait.gd:_cache": "decoded portraits, a cache",
	"portrait.gd:_scene_cache": "decoded scene backdrops, a cache",
	"settings_panel.gd:revision": "the settings revision counter (settings, not a game's)",
	"settings_panel.gd:_foreign_news": "the news-of-other-countries switch, read per settings revision",
	"settings_panel.gd:_foreign_news_revision": "the revision that switch was read at",
	"sound.gd:_cache": "rendered one-shots, a cache",
	"sound.gd:_warm_task": "the warm-up worker's task id",
	"sound.gd:_warmed": "what that worker rendered",
	"sound_bed.gd:override": "a test's override of the bed",
	"sound_bed.gd:_streams": "rendered looping beds, a cache",
	"strings.gd:dir": "where the translation tables are (a test points it elsewhere)",
	"strings.gd:_language": "the language setting (settings, not a game's)",
	"strings.gd:_decimal": "that language's decimal separator",
	"strings.gd:_installed": "the installed Translation",
	"strings.gd:_rows": "data-row translations read from data/i18n/, a cache",
	"strings.gd:_placeholder_regex": "a compiled regex",
	"synth.gd:primed_thread": "the thread the synth was primed on",
	"talk_menu.gd:_table": "talk lines read from data/audiences/, a cache",
	"term_text.gd:_tag": "a compiled regex",
	"term_text.gd:_plain_tag": "a compiled regex",
	"term_text.gd:_person_tag": "a compiled regex",
	"term_text.gd:_marked_ids": "a compiled regex",
	"ui_theme.gd:_accent": "the played nation's accent, re-applied by main on every boot (UiTheme.apply_for)",
	"ui_theme.gd:_text_scale": "the text size setting (settings, not a game's)",
	"ui_theme.gd:_archivo": "the loaded font, a cache",
	"ui_theme.gd:_map_face": "the loaded map font, a cache",
	"ui_theme.gd:_map_figure_face": "the loaded map figure font, a cache",
	"voice.gd:_manifest": "the voice manifest read from disk, a cache",
	"window_mode.gd:_applied_once": "whether the window mode was applied in this process",
}

var _failures: Array[String] = []
var _frame := 0
var _old_console
var _old_log
var _main


func _init() -> void:
	_check_a_hold_free_save_loads_paused()
	_check_every_static_is_accounted_for()
	_check_forget_main_drops_every_keyed_entry()
	_check_reset_statics_clears_every_cleared_static()
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_old_console = _main.get_node_or_null("DevConsole")
			if _old_console == null:
				_fail("(d) the game has no DevConsole in a debug run: the check cannot run")
				_finish()
				return true
			_old_log = _old_console._log
			if not _old_log._installed:
				_fail("(d) the console's Logger is not installed on a live game")
			var error := SaveManager.save_game(_main._state, _main._clock, SLOT)
			if error != "":
				_fail("could not save: %s" % error)
				_finish()
				return true
			var old = _main
			_main = _main._on_load_requested(SLOT)
			if _main == null or _main == old:
				_fail("(d) a load did not hand back a new main")
				_finish()
				return true
		6:
			_check_the_console_follows_the_rebuilt_game()
			SaveManager.delete_slot(SLOT)
			_finish()
	return false


## (a) set_clock() on a stub main whose save carries nothing that holds: the clock is running
## beforehand (the old game's), so a load that does not pause it opens a running game.
func _check_a_hold_free_save_loads_paused() -> void:
	var clock := preload("res://src/core/clock.gd").new()
	clock.paused = false
	var state := Stub.new()
	state.year = 2027
	state.month = 4
	var main := Stub.new()
	main._clock = clock
	main._state = state
	main.pending_save = {"state": state, "day": 14, "slot": "s"}  # no "speed": a boot
	GameReload.set_clock(main)
	if not clock.paused:
		_fail("(a) a hold-free save opened the game RUNNING: set_clock must pause the clock")
	if clock.year != 2027 or clock.month != 4 or clock.day != 14 or state.day != 14:
		_fail("(a) the loaded date did not reach the clock and the state: %d-%d-%d / %d"
			% [clock.year, clock.month, clock.day, state.day])
	if clock.speed != 1:
		_fail("(a) a boot (speed 0) changed the clock's own speed to %d" % clock.speed)
	clock.paused = false
	main.pending_save["speed"] = 3
	GameReload.set_clock(main)
	if not clock.paused or clock.speed != 3:
		_fail("(a) a load at speed 3 must open paused at speed 3, got paused=%s speed=%d" % [clock.paused, clock.speed])
	clock.free()


## (b) Every `static var` in src/ui, by file and name.
func _check_every_static_is_accounted_for() -> void:
	var accounted := {}
	for entry in GameReload.CLEARED_STATICS:
		accounted["%s.gd:%s" % [entry[0], entry[1]]] = "cleared"
	for entry in GameReload.MAIN_KEYED_STATICS:
		accounted["%s.gd:%s" % [entry[0], entry[1]]] = "keyed"
	var found := {}
	for path in _gd_files("res://src/ui"):
		var text := FileAccess.get_file_as_string(path)
		var rx := RegEx.create_from_string("(?m)^\\s*static var\\s+(\\w+)")
		for m in rx.search_all(text):
			found["%s:%s" % [path.get_file(), m.get_string(1)]] = true
	for key in found:
		if not accounted.has(key) and not NOT_PER_GAME.has(key):
			_fail("(b) `static var` %s is neither cleared/forgotten by game_reload.gd nor on this test's NOT_PER_GAME list: "
				% key + "a per-game static would leak across a load")
	for key in accounted:
		if not found.has(key):
			_fail("(b) game_reload.gd lists %s, which is not a static var in src/ui" % key)
	for key in NOT_PER_GAME:
		if not found.has(key):
			_fail("(b) the NOT_PER_GAME list names %s, which is no longer a static var in src/ui" % key)
		if accounted.has(key):
			_fail("(b) %s is both reset by game_reload.gd and on the NOT_PER_GAME list" % key)


## (c) A plain node stands for the old main; every keyed static holds an entry for it and one for
## another id, and only the first goes.
func _check_forget_main_drops_every_keyed_entry() -> void:
	var names := {}
	for entry in GameReload.MAIN_KEYED_STATICS:
		names["%s.%s" % [entry[0], entry[1]]] = true
	for must in ["proposal_note._tabled", "proposal_note._told", "region_arrival._told"]:
		if not names.has(must):
			_fail("(c) %s is keyed by a main's id and is not forgotten on a load" % must)
	var old := Node.new()
	var other := 1
	for entry in GameReload.MAIN_KEYED_STATICS:
		var d: Dictionary = GameReload._static_dict(entry[0], entry[1])
		d[old.get_instance_id()] = {"stale": true}
		d[other] = {"kept": true}
	GameReload._forget_main(old)
	for entry in GameReload.MAIN_KEYED_STATICS:
		var d: Dictionary = GameReload._static_dict(entry[0], entry[1])
		if d.has(old.get_instance_id()):
			_fail("(c) %s.%s keeps the replaced main's entry after a load" % [entry[0], entry[1]])
		if not d.has(other):
			_fail("(c) %s.%s lost another main's entry" % [entry[0], entry[1]])
		d.erase(other)
	old.free()


func _check_reset_statics_clears_every_cleared_static() -> void:
	for entry in GameReload.CLEARED_STATICS:
		GameReload._static_dict(entry[0], entry[1])["x"] = 1
	GameReload.reset_statics()
	for entry in GameReload.CLEARED_STATICS:
		if not GameReload._static_dict(entry[0], entry[1]).is_empty():
			_fail("(b) reset_statics() left %s.%s filled" % [entry[0], entry[1]])


## (d) After the rebuild: the old console's Logger is gone with it, the new console belongs to the
## new main and has its own Logger installed.
func _check_the_console_follows_the_rebuilt_game() -> void:
	if _old_log._installed:
		_fail("(d) the replaced game's Logger is still installed after the load")
	if is_instance_valid(_old_console):
		_fail("(d) the replaced game's console is still alive after the load")
	var console = _main.get_node_or_null("DevConsole")
	if console == null:
		_fail("(d) the rebuilt game has no DevConsole")
		return
	if console._main != _main:
		_fail("(d) the rebuilt game's console still points at another main")
	if console._log == _old_log or not console._log._installed:
		_fail("(d) the rebuilt game's console has no Logger of its own")


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".gd"):
			out.append("%s/%s" % [dir, name])
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files("%s/%s" % [dir, sub]))
	return out


## A main and a state as set_clock() reads them.
class Stub extends RefCounted:
	var _clock
	var _state
	var pending_save := {}
	var year := 0
	var month := 0
	var day := 0


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_game_reload_records: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
