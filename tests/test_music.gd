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
const MusicFlow = preload("res://src/ui/music_flow.gd")

var _failures: Array = []


func _init() -> void:
	_check_no_manifest()
	_check_manifest_rows()
	_check_flow()
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


## RF9 (spec 4.3, #223's RECORD): a bed change crossfades over MUSIC_CROSSFADE_S,
## and after MUSIC_PLAYS_BEFORE_REST plays through the bed rests MUSIC_REST_S under
## the ambient bed alone, then starts again from its top. MusicFlow is the pure
## half; headless places no player, so the gains are what is pinned.
func _check_flow() -> void:
	var fade: float = SoundK.MUSIC_CROSSFADE_S
	var f := MusicFlow.change({})
	f = MusicFlow.step(f, fade, 120.0)
	if not is_equal_approx(float(f["gain"]), 1.0):
		_fail("a first bed is not at full gain after the fade: %s" % f)
	f = MusicFlow.change(f)
	if not is_equal_approx(float(f["out"]), 1.0) or float(f["gain"]) > 0.0:
		_fail("a bed change cut instead of crossfading: %s" % f)
	f = MusicFlow.step(f, fade / 2.0, 120.0)
	if not is_equal_approx(float(f["gain"]), 0.5) or not is_equal_approx(float(f["out"]), 0.5):
		_fail("halfway through the crossfade the beds are not at half each: %s" % f)
	f = MusicFlow.step(f, fade / 2.0, 120.0)
	if not is_equal_approx(float(f["gain"]), 1.0) or float(f["out"]) > 0.0:
		_fail("the crossfade did not end at the new bed alone: %s" % f)
	# Two plays through, then the rest: silent for MUSIC_REST_S, then the top again.
	var length := 120.0
	f = MusicFlow.change({})
	var t := 0.0
	var plays_end: float = length * SoundK.MUSIC_PLAYS_BEFORE_REST
	while t < plays_end - 1.0:
		f = MusicFlow.step(f, 1.0, length)
		t += 1.0
	if float(f["rest"]) > 0.0 or float(f["gain"]) < 1.0:
		_fail("the bed rested before two plays through: %s at %.0f s" % [f, t])
	f = MusicFlow.step(f, 1.0, length)
	if float(f["rest"]) <= 0.0:
		_fail("two plays through and the bed did not rest: %s" % f)
	f = MusicFlow.step(f, fade, length)
	if float(f["gain"]) > 0.0:
		_fail("the resting bed is not silent after its fade: %s" % f)
	var restarted := false
	var rested := 0.0
	while not restarted and rested < SoundK.MUSIC_REST_S + 10.0:
		f = MusicFlow.step(f, 1.0, length)
		rested += 1.0
		restarted = bool(f["restart"])
	if not restarted or absf(rested + fade - SoundK.MUSIC_REST_S) > 1.5:
		_fail("the rest did not end after %.0f s (rested %.0f s, restarted %s)" % [SoundK.MUSIC_REST_S, rested + fade, restarted])
	if float(f["played"]) > 1.0 or float(f["rest"]) > 0.0:
		_fail("after its rest the bed does not start from its top: %s" % f)
	# A bed of unknown length (no stream, headless) never rests.
	f = MusicFlow.change({})
	for i in 1000:
		f = MusicFlow.step(f, 1.0, 0.0)
	if float(f["rest"]) > 0.0:
		_fail("a bed with no length rested")


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
	# Pre-gate B3: a band with no file plays the tense bed (the campaign was silent
	# for the four months before the election).
	Music.override_manifest = {"beds": {"tense": {"file": "../voice/activist_f_30/agree.ogg"}}}
	Music.follow(desk, "calm", 3, 4343)  # three months to the vote: the campaign band
	if String(music.band_state["band"]) != "campaign" or music._track != Music.track("beds", "tense"):
		_fail("a band with no file did not fall back to the tense bed: %s, '%s'" % [music.band_state, music._track])
	# RF9: the node's own bed change starts MusicFlow's crossfade.
	music._process(SoundK.MUSIC_CROSSFADE_S)
	Music.override_manifest = {"beds": {"crisis": {"file": "../voice/activist_f_30/refuse.ogg"},
		"tense": {"file": "../voice/activist_f_30/agree.ogg"}}}
	Music.follow(desk, "crisis", 20, 4343)
	if not is_equal_approx(float(music.flow.get("out", 0.0)), 1.0) or float(music.flow.get("gain", 1.0)) > 0.0:
		_fail("the node's bed change did not crossfade: %s" % music.flow)
	# The parent's TAKE 3 on #230: a Settings save re-applies the level to the bed
	# playing -- its volume only, never from its top, and the flow goes on.
	var bed := AudioStreamPlayer.new()
	bed.stream = AudioStreamGenerator.new()
	music.add_child(bed)
	music._player = bed
	bed.play()
	music._process(1.0)
	var flowing: Dictionary = music.flow.duplicate()
	_set_music(3)
	SettingsPanel.revision += 1
	music._process(0.0)
	if music._player != bed or not bed.playing:
		_fail("a Settings save restarted the bed (playing %s)" % bed.playing)
	if float(music.flow["played"]) != float(flowing["played"]) or float(music.flow["gain"]) != float(flowing["gain"]):
		_fail("a Settings save reset the flow: %s, was %s" % [music.flow, flowing])
	_set_music(SettingsPanel.DEFAULT_MUSIC)
	SettingsPanel.revision += 1
	music._process(0.0)
	Music.override_manifest = {}
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
