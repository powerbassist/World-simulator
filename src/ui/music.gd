extends Node

## V5.3-0 (d), RF9: the music player -- a bed by tension, a sting on a moment, the
## bed ducked under a voice line. It ships with NO tracks: every bed and every
## recorded sting is a row of the manifest below, and a row with no file, or no
## manifest at all, is silence with no error. The author's CC0 files drop into
## assets/audio/music/ with their rows; nothing here changes when they do.
##
## The manifest (res://assets/audio/music/manifest.json, the voice manifest's
## shape; provenance per file as docs/design/v5.3-0-music-sourcing.md lists it):
##   {"beds": {"calm": {"file": "calm.ogg", "author": "...", "url": "...",
##             "licence": "CC0-1.0", "read": "2026-..", "sha256": "..."}, ...},
##    "stings": {"vote_passed": {...}, "election_won": {...}, ...}}
## Beds: MusicBand's four (calm, tense, crisis, campaign). Moments: MOMENTS.
##
## The band moves once a month, from the briefing's own ranking (BriefingDriver
## calls follow()), with the inputs tools/decision_surfaces_probe.gd measures,
## so the bed changes the player hears are the ones the probe counted.

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const SoundBed = preload("res://src/ui/sound_bed.gd")
const Sound = preload("res://src/ui/sound.gd")
const SoundK = preload("res://src/ui/sound_constants.gd")
const Sting = preload("res://src/ui/sting.gd")
const MusicBand = preload("res://src/ui/music_band.gd")
const MusicFlow = preload("res://src/ui/music_flow.gd")

const NODE := "Music"  # i18n: ok a node name
const MANIFEST := "res://assets/audio/music/manifest.json"  # i18n: ok a path
## Voice.speak puts every voice player in this group; the music ducks while any
## of them plays. Polled, never hung on `finished`: Voice.stop emits none.
const VOICE_GROUP := "voice"  # i18n: ok a group name
## The moments a sting answers, and the synthesized stand-in each plays while the
## manifest names no file ("" is silence): the two losing stings are synthesized
## for good (no clean licence exists), election night keeps its toll.
const MOMENTS := {
	"front_page": "", "vote_passed": "", "vote_failed": "vote_failed",  # i18n: ok moment ids
	"election_won": "election", "election_lost": "election_lost",  # i18n: ok moment ids
}

## A test's manifest in place of the file's; null reads the file.
static var override_manifest = null
static var _manifest = null

## MusicBand.step's memory, and the band it gave.
var band_state := {}
## True while a voice line plays (read by the tests; the volume follows it).
var ducked := false
## MusicFlow's state: the crossfade and the rest (read by the tests).
var flow := {}
var _player: AudioStreamPlayer
## The bed fading out after a change.
var _out: AudioStreamPlayer
## The step and the duck, ramped; each bed adds its own fade gain to it.
var _duck_db := SoundK.SILENT_DB
var _track := ""
var _level := -1
var _seen_revision := -1
var _state_id := 0


## The game's sound: the synthesized desk bed (SoundBed) and this node beside it.
static func start(parent: Node) -> Node:
	SoundBed.start(parent, "game")  # i18n: ok a bed id
	var music := new()
	music.name = NODE
	parent.add_child(music)
	return music


static func manifest() -> Dictionary:
	if override_manifest != null:
		return override_manifest
	if _manifest == null:
		_manifest = {}
		if FileAccess.file_exists(MANIFEST):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
			if parsed is Dictionary:
				_manifest = parsed
	return _manifest


## The file a manifest row names under `section` ("beds" or "stings"), or "".
static func track(section: String, id: String) -> String:
	var row = (manifest().get(section, {}) as Dictionary).get(id, null)
	var file := String(row.get("file", "")) if row is Dictionary else ""
	# simplify_path: on Linux a ".." through a folder that does not exist (music/ has no
	# tracked file yet, so a clone has no such folder) does not resolve -- CI read the row
	# as missing while Windows passed.
	var path := MANIFEST.get_base_dir().path_join(file).simplify_path()
	# A row whose file has not landed yet is silence, not an engine ERROR (#223 pass 1).
	return path if not file.is_empty() and FileAccess.file_exists(path) else ""


## The volume the bed wants: the Music step, less DUCK_DB while someone speaks.
static func target_db(level: int, speaking: bool) -> float:
	return float(SoundK.MUSIC_DB[clampi(level, 0, 3)]) - (SoundK.DUCK_DB if speaking else 0.0)


## Whether a voice line is playing anywhere in `tree` (or about to: Voice's
## delayed start sets "pending").
static func speaking(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group(VOICE_GROUP):
		var p := node as AudioStreamPlayer
		if p != null and (p.playing or bool(p.get_meta("pending", false))):
			return true
	return false


## The month's step (BriefingDriver): the band from this month's situation and
## the months to the next vote (-1 for none), and the bed that band names.
## `state_id` is the GameState's instance id: a load or a new game is a new state
## and the band starts over, as the briefing's novelty does (#223 pass 2) -- the
## Music node outlives the state, so a carried band would score the old game.
static func follow(parent: Node, situation: String, months_to_vote: int, state_id: int = 0) -> void:
	var music = parent.get_node_or_null(NODE) if parent != null else null
	if music == null:
		return
	if state_id != music._state_id:
		music._state_id = state_id
		music.band_state = {}
	music.band_state = MusicBand.step(music.band_state, situation, months_to_vote if months_to_vote >= 0 else -1)
	var bed := track("beds", String(music.band_state["band"]))
	# A band whose file has not landed plays the tense bed (pre-gate B3: the campaign,
	# the tensest months of the term, was silent until it has a track of its own).
	music._play_bed(bed if bed != "" else track("beds", "tense"))


## A moment's sting under `parent`: its recorded file when the manifest names one
## and Music is on; else its synthesized stand-in, a Sound like any other.
## Music Off silences every moment, recorded or synthesized, so the setting means
## the same thing before and after the author's files land (#223 pass 1); Quiet and
## Loud move a stand-in by the same step they move a file, from its own recipe's
## level at Normal, so the default plays the sound V4.9c tuned (#223 pass 2).
static func moment(parent: Node, id: String) -> void:
	var level := SettingsPanel.music_level()
	if parent == null or not parent.is_inside_tree() or level <= 0:
		return
	var path := track("stings", id)
	if path != "":
		var stream := AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(path))
		if stream != null and SettingsPanel.sound_enabled():
			var player := AudioStreamPlayer.new()
			player.stream = stream
			player.volume_db = target_db(level, false)
			player.set_meta("track", path)  # which file: a count cannot tell one sting from another
			parent.add_child(player)
			player.finished.connect(player.queue_free)
			player.play()
		return
	var synth := String(MOMENTS.get(id, ""))
	var offset := target_db(level, false) - target_db(SettingsPanel.DEFAULT_MUSIC, false)
	if synth == "election":
		Sting.play(parent, offset)
	elif synth != "":
		Sound.cue(parent, synth, offset)


func _process(delta: float) -> void:
	if _seen_revision != SettingsPanel.revision:
		_seen_revision = SettingsPanel.revision
		var was := _level
		_level = SettingsPanel.music_level() if SettingsPanel.sound_enabled() else 0
		# Only Off and on move the bed: it stops, or starts from its top. Any other
		# Settings save leaves it playing where it is, the flow untouched, and the
		# ramp below carries the new level (the parent's TAKE 3 on #230).
		if (was > 0) != (_level > 0):
			_start(_track)
	ducked = speaking(get_tree())
	_duck_db = move_toward(_duck_db, target_db(_level, ducked), SoundK.DUCK_DB_PER_S * delta)
	var length := _player.stream.get_length() if _player != null and _player.stream != null else 0.0
	flow = MusicFlow.step(flow, delta, length)
	if _player != null:
		if bool(flow["restart"]):
			_player.play(0.0)
		elif float(flow["gain"]) <= 0.0 and float(flow["rest"]) > 0.0 and _player.playing:
			_player.stop()  # resting under the ambient bed alone
		_player.volume_db = _duck_db + MusicFlow.db(float(flow["gain"]))
	if _out != null:
		_out.volume_db = _duck_db + MusicFlow.db(float(flow["out"]))
		if float(flow["out"]) <= 0.0:
			_out.queue_free()
			_out = null


## Plays `path` as the looping bed ("" or Music off: none), crossfading from the
## one before (MusicFlow). Off under --headless, as SoundBed is: the suite has no
## speakers and the band and the flow still move.
func _play_bed(path: String) -> void:
	if path == _track:
		return
	_track = path
	flow = MusicFlow.change(flow)
	_start(path, true)


## `path` from its top on a player of its own; with `crossfade` the playing one
## fades out beside it, else it stops (a second change mid-fade drops the oldest).
func _start(path: String, crossfade := false) -> void:
	if _out != null:
		_out.queue_free()
		_out = null
	if _player != null:
		if crossfade and _player.playing:
			_out = _player
			_player = null
		else:
			_player.stop()
	if path == "" or _level <= 0 or not SoundBed.active():
		return
	var stream := AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(path))
	if stream == null:
		return
	stream.loop = true
	if _player == null:
		_player = AudioStreamPlayer.new()
		add_child(_player)
	_player.stream = stream
	_player.volume_db = SoundK.SILENT_DB
	_player.play()
