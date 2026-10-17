extends Node

## V4.9c. An ambient bed: one screen's looping drone, under everything else.
## A node rather than a Sound.cue() because a bed lives as long as its screen,
## fades in and out instead of starting on a cut, and answers the settings while
## it plays -- turning Ambience or Sound off in the pause menu fades the bed out
## then and there, and turning it back on brings it back.
##
## Built OFF the main thread: a 16 s bed is ~380 ms of GDScript (measured
## 2026-10-17), which on the main thread would be a visible hitch on the menu's
## first frame -- the frame tools/menu_boot_probe.gd guards -- or a stall in the
## loading bar's measured stages. The render is a pure function of its recipe
## (synth.gd), so the worker touches nothing but its own buffer; the stream and
## the player are made here, on the main thread, once the task is done. Kept in a
## static cache, so the second time a screen opens its bed starts at once.

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const SoundK = preload("res://src/ui/sound_constants.gd")
const Synth = preload("res://src/ui/synth.gd")

## -1 follows the setting and is off under --headless: a bed there would spend
## ~380 ms of a worker per scene-building test to play into the Dummy driver,
## and nothing a test reads depends on it. 0 forces off, 1 forces on --
## tests/test_sound.gd sets it.
static var override := -1

static var _streams := {}

var bed_id := ""
var _task := -1
var _rendered := PackedByteArray()
var _player: AudioStreamPlayer
var _tween: Tween
var _want := false
var _seen_revision := -1
var _leaving := false


## A bed for `id` (a sound_constants.BEDS key) under `parent`, started as soon as
## its loop is rendered.
static func start(parent: Node, id: String) -> Node:
	var node: Node = new()
	node.bed_id = id
	node.name = "SoundBed_" + id
	parent.add_child(node)
	return node


static func active() -> bool:
	if override >= 0:
		return override == 1
	return DisplayServer.get_name() != "headless"


func recipe() -> Dictionary:
	return SoundK.BEDS.get(bed_id, {})


## True once the bed is audible or swelling in. A test's read; nothing in the
## game branches on it.
func playing() -> bool:
	return _player != null and _player.playing and _want


## Fades the bed out over its own fade and frees it: the screen is going. The
## menu calls this on its way into the game, so the menu's chord does not cut off
## mid-swell when the scene changes.
func fade_out() -> void:
	_leaving = true
	_want = false
	if _player == null:
		queue_free()
		return
	_kill_fade()
	_fade_player(_player, SoundK.SILENT_DB, func(): queue_free())


func _ready() -> void:
	if not active() or recipe().is_empty():
		set_process(false)


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_streams[bed_id] = Synth.wav(_rendered, int(recipe()["rate"]), true)
		_rendered = PackedByteArray()

	if _leaving:
		return
	# The settings file is re-read only when the settings screen has saved:
	# a dozen beds' worth of per-frame file reads is waste, and the counter is
	# the screen's own (motion.gd's pattern), so the dependency stays one-way.
	if _seen_revision != SettingsPanel.revision:
		_seen_revision = SettingsPanel.revision
		_want = SettingsPanel.sound_enabled() and SettingsPanel.ambient_enabled()
		if not _want and _player != null:
			var gone := _player
			_player = null
			_kill_fade()
			_fade_player(gone, SoundK.SILENT_DB, func(): gone.queue_free())

	if not _want or _player != null:
		return
	if not _streams.has(bed_id):
		if _task < 0:
			_task = WorkerThreadPool.add_task(_render, false, "sound bed " + bed_id)
		return
	_player = AudioStreamPlayer.new()
	_player.stream = _streams[bed_id]
	_player.volume_db = SoundK.SILENT_DB
	add_child(_player)
	_player.play()
	_tween = _fade_player(_player, float(recipe()["level_db"]), Callable())


## Runs on a worker thread: reads only the constant recipe, writes only its own
## buffer, which the main thread reads after is_task_completed().
func _render() -> void:
	_rendered = Synth.bed(SoundK.BEDS[bed_id])


## A fade in progress is killed before the same player fades the other way:
## two tweens on one volume_db would fight, and whichever ran last would win.
## A fade OUT is never killed -- it is the old player's own way to silence.
func _kill_fade() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _fade_player(player: AudioStreamPlayer, db: float, done: Callable) -> Tween:
	var tween := create_tween()
	tween.tween_property(player, "volume_db", db, float(recipe()["fade_s"]))
	if done.is_valid():
		tween.tween_callback(done)
	return tween


## A task the pool was given must be waited on before its node goes, or the
## worker would write into a freed buffer. At worst this blocks a screen change
## for what is left of one render.
func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
