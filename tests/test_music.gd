extends SceneTree

## V5.3-0 (d): the music player with no tracks (src/ui/music.gd). RF9's "music
## that does not tire" waits for the author's files; what is pinned now is that
## the empty player is silent and error-free, that the band moves by MusicBand's
## rule, that the bed ducks under a voice line by polling (Voice.stop emits no
## `finished`), and that each moment plays its stand-in or nothing.

const Music = preload("res://src/ui/music.gd")
const SoundK = preload("res://src/ui/sound_constants.gd")
const Sound = preload("res://src/ui/sound.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")

var _failures: Array = []


func _init() -> void:
	_check_no_manifest()
	_check_manifest_rows()
	# Deferred: a node added in _init is not in the tree's groups yet.
	_check_band_and_moments.call_deferred()


func _finish() -> void:
	Music.override_manifest = null
	if _failures.is_empty():
		print("test_music: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


## No manifest on disk: no rows, no file, and no error (the runner fails on one).
func _check_no_manifest() -> void:
	if FileAccess.file_exists(Music.MANIFEST):
		return  # the author's tracks have landed; _check_manifest_rows still runs
	if not Music.manifest().is_empty() or Music.track("beds", "calm") != "":
		_fail("no manifest, yet a bed was found")


func _check_manifest_rows() -> void:
	# A row resolves next to the manifest; a committed clip stands in for a track.
	var clip := "../voice/activist_f_30/agree.ogg"
	Music.override_manifest = {"beds": {"calm": {"file": clip}, "tense": {"file": ""}, "crisis": {"file": "crisis.ogg"}}}
	if Music.track("beds", "calm") != "res://assets/audio/music/".path_join(clip).simplify_path():
		_fail("a bed row resolved to '%s'" % Music.track("beds", "calm"))
	if Music.track("beds", "tense") != "" or Music.track("stings", "vote_passed") != "":
		_fail("a row with no file played something")
	# #223 pass 1: a row whose file has not landed is silence, never an engine ERROR.
	if Music.track("beds", "crisis") != "":
		_fail("a row naming a missing file resolved to '%s'" % Music.track("beds", "crisis"))
	Music.override_manifest = {}


## The duck: polled from the voice group, released the frame the line ends, with
## or without a `finished` (a pending start stands in for a playing line).
func _check_ducking() -> void:
	var voice := AudioStreamPlayer.new()
	voice.add_to_group(Music.VOICE_GROUP)
	root.add_child(voice)
	if Music.speaking(self):
		_fail("an idle voice player ducks the music")
	voice.set_meta("pending", true)
	if not Music.speaking(self):
		_fail("a voice line about to play does not duck the music")
	var normal := Music.target_db(2, false)
	if not is_equal_approx(Music.target_db(2, true), normal - SoundK.DUCK_DB):
		_fail("ducked target %.1f, expected %.1f" % [Music.target_db(2, true), normal - SoundK.DUCK_DB])
	if Music.target_db(0, false) > -60.0:
		_fail("Music Off is not silent: %.1f dB" % Music.target_db(0, false))
	voice.set_meta("pending", false)
	if Music.speaking(self):
		_fail("the duck outlived the line")
	voice.free()


func _check_band_and_moments() -> void:
	_check_ducking()
	var desk := Node.new()
	root.add_child(desk)
	var music = Music.start(desk)
	# The band: MusicBand's rule, month by month, with no track and no error.
	Music.follow(desk, "calm", 20)
	Music.follow(desk, "crisis", 20)
	if String(music.band_state["band"]) != "crisis":
		_fail("a crisis month did not move the band: %s" % music.band_state)
	Music.follow(desk, "calm", 2)
	if String(music.band_state["band"]) != "crisis":
		_fail("the band fell from crisis in one calm month")
	# #223 pass 2: a load or a new game (another state) starts the band over.
	Music.follow(desk, "crisis", 20)  # a crisis this month, so the band cannot fall on its own
	Music.follow(desk, "calm", 20, 4242)
	if String(music.band_state["band"]) != "calm":
		_fail("another game's calm month did not start calm: %s" % music.band_state)
	if music.get_children().any(func(c): return c is AudioStreamPlayer):
		_fail("a bed with no track placed a player")
	# The duck seen by the node itself, a frame at a time.
	var voice := AudioStreamPlayer.new()
	voice.add_to_group(Music.VOICE_GROUP)
	voice.set_meta("pending", true)
	desk.add_child(voice)
	music._process(0.1)
	if not music.ducked:
		_fail("the music node did not see the voice line")
	voice.set_meta("pending", false)
	music._process(0.1)
	if music.ducked:
		_fail("the music node stayed ducked after the line")
	# Moments: the losing stings and the toll play their stand-ins; a recorded-only
	# moment with no file plays nothing.
	_set_sound(true)
	for c in [["vote_failed", 1], ["election_lost", 1], ["election_won", 1], ["vote_passed", 0], ["front_page", 0]]:
		var before := _players(desk)
		Music.moment(desk, c[0])
		if _players(desk) - before != c[1]:
			_fail("moment %s placed %d players, expected %d" % [c[0], _players(desk) - before, c[1]])
	# #223 pass 1: Music Off silences the synthesized stings too.
	_set_music(0)
	var quiet := _players(desk)
	Music.moment(desk, "vote_failed")
	if _players(desk) != quiet:
		_fail("a sting played with Music off")
	# #223 pass 2: Quiet and Loud move the stand-ins too, and Normal plays them at
	# their own recipe's level.
	var heard := {}
	for level in [1, SettingsPanel.DEFAULT_MUSIC, 3]:
		_set_music(level)
		for id in ["vote_failed", "election_lost", "election_won"]:
			Music.moment(desk, id)
			var last: Node = desk.get_child(desk.get_child_count() - 1)
			heard["%s@%d" % [id, level]] = (last as AudioStreamPlayer).volume_db if last is AudioStreamPlayer else NAN
	for id in ["vote_failed", "election_lost", "election_won"]:
		var q: float = heard["%s@1" % id]
		var n: float = heard["%s@%d" % [id, SettingsPanel.DEFAULT_MUSIC]]
		var l: float = heard["%s@3" % id]
		var recipe: String = "election" if id == "election_won" else String(id)
		if not (q < n and n < l):
			_fail("the Music step does not move %s: quiet %s normal %s loud %s" % [id, q, n, l])
		if not is_equal_approx(n, float(Sound.recipe(recipe)["level_db"])):
			_fail("%s at Normal is %s, not its recipe's level" % [id, n])
	_set_music(SettingsPanel.DEFAULT_MUSIC)
	# #223 QA D9: a line Voice.speak places is one Music.speaking() sees.
	var line_parent := Node.new()
	desk.add_child(line_parent)
	preload("res://src/ui/voice.gd").speak(line_parent, "res://assets/audio/voice/activist_f_30/agree.ogg")
	if line_parent.get_child_count() == 0:
		_fail("premise: Voice.speak placed no player")
	elif not Music.speaking(self):
		_fail("a real voice line is not one the music ducks under")
	desk.free()
	_finish()


func _players(node: Node) -> int:
	return node.get_children().filter(func(c): return c is AudioStreamPlayer).size()


func _set_sound(enabled: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value("audio", "enabled", enabled)
	cfg.save(SettingsPanel.CONFIG_PATH)


func _set_music(level: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value("audio", "music", level)
	cfg.save(SettingsPanel.CONFIG_PATH)


func _fail(message: String) -> void:
	_failures.append(message)
