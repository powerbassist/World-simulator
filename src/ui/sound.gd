extends RefCounted

## V4.9c. The one door every one-shot sound goes through: UI cues, the event
## sting by severity, the election sting. The player frees itself when its
## stream ends, so there is no pool and no state beyond a stream cache -- V3.6's
## sting.gd shape, grown to a vocabulary. Beds loop and fade, so they are a node
## of their own (sound_bed.gd).
##
## The Sound setting is read at PLAY time, not applied at boot (V3.6): a change
## made from the pause menu governs the very next sound with no second wiring
## path. Safe under --headless -- the Dummy driver opens no device -- which is
## what the whole suite runs on, so a wired cue is countable there.

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const SoundK = preload("res://src/ui/sound_constants.gd")
const Synth = preload("res://src/ui/synth.gd")

## Rendered once per recipe and kept: the set is eleven sounds, ~1-160 KB each.
static var _cache := {}

## The whole one-shot set is ~190 ms of GDScript (measured 2026-10-17; the
## critical sting alone ~80 ms), so a sound rendered on first use would stall
## the frame it is needed in -- the first crisis's arrival. warm() renders the
## set on a worker as the game opens; the worker writes only _warmed, which the
## main thread reads after is_task_completed(). A cue asked for before the
## worker is done renders itself on the spot, as every cue does under
## --headless, where warm() does nothing (the suite builds main.tscn thirty
## times and would spend a worker each time on sounds the Dummy driver drops).
static var _warm_task := -1
static var _warmed := {}


static func ids() -> Array:
	var out: Array = ["election"]
	out.append_array(SoundK.CUES.keys())
	for i in SoundK.EVENTS.size():
		out.append("event_%d" % (i + 1))
	return out


## `force` runs it under --headless too -- tests/test_sound.gd's door to the
## worker path.
static func warm(force: bool = false) -> void:
	if _warm_task >= 0 or (DisplayServer.get_name() == "headless" and not force):
		return
	var todo: Array = []
	for id in ids():
		if not _cache.has(id):
			todo.append(id)
	if todo.is_empty():
		return
	_warm_task = WorkerThreadPool.add_task(func():
		for id in todo:
			_warmed[id] = Synth.one_shot(recipe(id))
	, false, "sound set")


## Waits for a warm still running: a task the pool was given must be waited on.
## main.gd calls it on its way out; at worst it blocks for what is left of one
## render.
static func settle() -> void:
	if _warm_task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_warm_task)
	_warm_task = -1
	_collect()


static func _collect() -> void:
	for id in _warmed:
		if not _cache.has(id):
			_cache[id] = Synth.wav(_warmed[id], int(recipe(id)["rate"]))
	_warmed.clear()


## The recipe a cue id names: "election", a CUES key, or "event_1".."event_3".
static func recipe(id: String) -> Dictionary:
	if id == "election":
		return SoundK.ELECTION
	if id.begins_with("event_"):
		var severity := clampi(int(id.trim_prefix("event_")), 1, SoundK.EVENTS.size())
		return SoundK.EVENTS[severity - 1]
	return SoundK.CUES.get(id, {})


static func stream(id: String) -> AudioStreamWAV:
	if _warm_task >= 0 and WorkerThreadPool.is_task_completed(_warm_task):
		settle()
	if not _cache.has(id):
		var r := recipe(id)
		if r.is_empty():
			return null
		_cache[id] = Synth.wav(Synth.one_shot(r), int(r["rate"]))
	return _cache[id]


## Plays a cue once under `parent`. Returns nothing a caller could come to rely
## on: a silent run (Sound off, or an id with no recipe) is indistinguishable
## from a played one everywhere but the speakers.
static func cue(parent: Node, id: String) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if not SettingsPanel.sound_enabled():
		return
	var s := stream(id)
	if s == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = s
	player.volume_db = float(recipe(id)["level_db"])
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## The event sting for an arrival of `severity` (1..3, V4.4's scale).
static func event_sting(parent: Node, severity: int) -> void:
	cue(parent, "event_%d" % severity)
