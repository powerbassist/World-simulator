extends SceneTree

## Smoke test for the EXPORTED game's PCK (tools/export_windows.py --smoke runs it):
##
##   godot --headless --main-pack build/NationSimulator.pck --script tools/exe_smoke.gd
##
## An export template ignores --script (measured, 4.7.2: it just boots the game), so the
## stock engine runs this file against the PCK as its main pack: res:// is the PCK, the
## project settings and the autoloads are the exported ones. The script file lives outside
## the PCK (tools/ never ships). Headless: no window, no cursor, nothing for
## tools/os_cursor.gd to guard. Exit 1 on any failed check;
## the caller also fails the run on any ERROR line the exe logged.
##
## What a green run proves: the exe reaches the menu, the real New Game boot builds the
## game scene, a month ticks, a save loads back, and one of each kind of byte-read asset
## (voice clip, music bed, portrait, SVG icon, summit .dialogue, data rows) is in the PCK.
## What it does not: any frame is drawn, and the dev console is absent only by the audit
## in export_windows.py (here: its file does not resolve).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Clock = preload("res://src/core/clock.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const BootStages = preload("res://src/ui/boot_stages.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Music = preload("res://src/ui/music.gd")
const Icon = preload("res://src/ui/icon.gd")

const SLOT := "__exe_smoke__"
## Wall clock, not frames: a stage gets 50 ms a frame, so how many frames the boot needs
## depends on the machine (292-600+ measured, with other runs loading the CPU).
const BOOT_DEADLINE_MS := 120_000

var _failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(not ResourceLoader.exists("res://src/ui/dev_console.gd"), "dev console is not in the PCK")
	_check(not FileAccess.file_exists("res://tools/os_cursor.gd"), "tools/ is not in the PCK")

	# 1. The menu scene, as the exe boots it.
	var menu: Node = (load("res://src/ui/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	for _i in 3:
		await process_frame
	_check(menu.is_inside_tree(), "menu scene reaches the tree")
	menu.queue_free()
	await process_frame

	# 2. Data from the PCK.
	var loader := DataLoader.new()
	loader.load_all()
	_check(loader.errors.is_empty(), "data loads with no errors %s" % [loader.errors.slice(0, 3)])
	_check(loader.nations.has("FRA") and loader.laws.size() > 100, "nations and laws read (%d laws)" % loader.laws.size())
	_check(loader.summits.size() > 0, "summit .dialogue scenes read (%d)" % loader.summits.size())

	# 3. New game, a month, save, load.
	var state = GameState.new_game(loader, "FRA")
	_check(state.errors.is_empty(), "new_game FRA has no errors")
	var months_before: int = state.month + 12 * state.year
	WorldMonth.tick_month(state, loader)
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	_check(state.month + 12 * state.year == months_before + 1, "a month ticked")
	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 1
	_check(SaveManager.save_game(state, clock, SLOT) == "", "save writes")
	var got: Dictionary = SaveManager.load_game(SLOT, loader)
	_check(bool(got.get("ok", false)) and got["state"].month == state.month, "save loads back")
	SaveManager.delete_slot(SLOT)

	# 4. The byte-read assets.
	var voice: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/voice/manifest.json"))
	var vkey: String = voice.keys()[0]
	var vfile := "res://" + String(voice[vkey]["file"])
	var clip: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(vfile))
	_check(clip != null and clip.get_length() > 0.1, "voice clip decodes (%s, %.1fs)" % [vkey, clip.get_length() if clip else 0.0])
	var bed_path := Music.track("beds", "calm")
	var bed: AudioStreamOggVorbis = null
	if bed_path != "":
		bed = AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(bed_path))
	_check(bed != null and bed.get_length() > 1.0, "music bed decodes (%s)" % bed_path)
	var pid := ""
	var da: DirAccess = DirAccess.open("res://assets/portraits/neutral")
	if da != null:
		for f in da.get_files():
			if f.ends_with(".webp"):
				pid = f.get_basename()
				break
	var tex: ImageTexture = Portrait.texture_for(pid) if pid != "" else null
	_check(tex != null and tex.get_width() > 16, "portrait decodes (%s)" % pid)
	var icon := Icon.load_icon("res://assets/icons/material/menu_book.svg", Color.WHITE, 24)
	_check(icon != null and icon.get_width() > 0, "SVG icon rasterises")
	_check(ResourceLoader.exists("res://assets/fonts/Archivo-Variable.ttf") and load("res://assets/fonts/Archivo-Variable.ttf") is FontFile,
		"Archivo font loads as a FontFile")

	# 5. The real New Game boot, a stage per frame as the loading screen runs it.
	var boot := BootStages.new("FRA", "", "")
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while not boot.ready_to_enter() and Time.get_ticks_msec() - t0 < BOOT_DEADLINE_MS:
		boot.step(50_000)
		frames += 1
		await process_frame
	_check(boot.ready_to_enter(), "boot reaches enter in %d frames, %.1fs" % [frames, (Time.get_ticks_msec() - t0) / 1000.0])
	if boot.ready_to_enter():
		root.add_child(boot.game)
		for _i in 10:
			await process_frame
		_check(is_instance_valid(boot.game) and boot.game.is_inside_tree(), "game scene lives ten frames")
		boot.game.queue_free()
		await process_frame

	print("exe_smoke: %d failed" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
