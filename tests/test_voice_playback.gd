extends SceneTree

## Headless test: godot --headless --script res://tests/test_voice_playback.gd
## Non-zero exit on any failure.
##
## V5.2d playback (docs/design/v5.2-d-spec.md section 6), over a FIXTURE clip
## (tests/fixtures/voice/line.ogg, a 0.4 s tone made with ffmpeg) and a fixture
## manifest in tools/voice_pipeline.py's shape:
##   - Godot's sha256_text() is the pipeline's hashlib hash of the UTF-8 bytes (two
##     pins computed in Python, one of them non-ASCII);
##   - the clip is found by the speaker form's default archetype and plays only when
##     the manifest's hash is the shown line's; a stale hash, no manifest row and no
##     tables at all are silence, and print nothing;
##   - Voices Off and Sound Off are silence; a level sets the player's volume;
##   - an ARRIVAL with a face speaks; a load's restored desk does not; a line is
##     not cut off by the next one, and ends when its card is answered or dismissed.

## suite-exclusive: backs up and restores user://settings.cfg -- the checks write the Sound and Voices settings

const Voice = preload("res://src/ui/voice.gd")
const DeskCards = preload("res://src/ui/desk_cards.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const SoundK = preload("res://src/ui/sound_constants.gd")
const Strings = preload("res://src/ui/strings.gd")

const FIXTURE := "tests/fixtures/voice/line.ogg"

## hashlib.sha256(s.encode("utf-8")).hexdigest(), computed in Python 2026-10-30.
const PINS := {
	"We close in April.": "0675e821d95a78db1cbcbbb620c7635518b0da559779be6bad734679fe526456",
	"Le gouvernement est tombé.": "184cf3dea2cfe4eea1e45acc6c5b6bc0be3b902233c3a8e72b599aa629b50f55",
}

## How long the arrival check waits for a delayed start (the worst sting is 1.8 s).
const WAIT_MS := 4000

var _failures: Array[String] = []
var _main
var _frame := 0
var _phase := 0
var _ev
var _person_id := ""
var _started := 0
var _had_settings := false
var _settings_backup := ""


func _init() -> void:
	_had_settings = FileAccess.file_exists(SettingsPanel.CONFIG_PATH)
	if _had_settings:
		_settings_backup = FileAccess.get_file_as_string(SettingsPanel.CONFIG_PATH)
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	match _phase:
		0:
			_check_hash_parity()
			if not _pick_event():
				return _finish()
			_check_lookup()
			_check_absent_tables()
			_check_settings_gate()
			_check_restore_silent()
			_start_arrival()
			_phase = 1
		1:
			var player := _player()
			if player != null and player.playing:
				_phase = 2
			elif Time.get_ticks_msec() - _started > WAIT_MS:
				_failures.append("an arrival whose speaker has a clip did not start it within %d ms" % WAIT_MS)
				_phase = 2
		2:
			_check_no_interrupt()
			_check_dismiss_hushes()
			return _finish()
	return false


## A line in progress is not cut off by the next one (review pass 1: the lapse guard
## used to replace the month's arrival line); it ends when its card goes.
func _check_no_interrupt() -> void:
	var player := _player()
	if player == null or player.stream == null:
		return
	var speaking: AudioStream = player.stream
	Voice.speak(_main, "res://" + FIXTURE)
	if player.stream != speaking:
		_failures.append("a second line cut off the one being spoken")


func _check_dismiss_hushes() -> void:
	var card_id := ""
	for id in _main._event_cards:
		if String(_main._event_cards[id]) == String(_ev.id):
			card_id = String(id)
	if card_id == "":
		_failures.append("fixture: the arrival's card is not on the desk")
		return
	_main._hud.inbox.dismiss(card_id)
	var player := _player()
	if player != null and (player.playing or player.stream != null):
		_failures.append("the line went on after its card was dismissed")


func _check_hash_parity() -> void:
	for text in PINS:
		if String(text).sha256_text() != PINS[text]:
			_failures.append("sha256_text() is not the pipeline's hash for '%s'" % text)


func _pick_event() -> bool:
	for candidate in _main._loader.events:
		if String(candidate.speaker_line).strip_edges() != "" and candidate.speaker.has("kind"):
			_ev = candidate
			break
	if _ev == null:
		_failures.append("fixture: no event carries a kind speaker and a line")
		return false
	var ns = _main._state.player()
	_person_id = String(_main._loader.people.get(String(ns.id), [])[0].id)
	return true


## The fixture tables: the event's kind defaults to archetype "arch", whose clip of the
## event's line is the fixture, hashed as `text` says.
func _tables(text: String) -> void:
	var kind := String(_ev.speaker["kind"])
	var key := "arch/event.%s" % _ev.id
	Voice.set_tables({key: {"archetype": "arch", "line_id": "event.%s" % _ev.id, "file": FIXTURE,
		"text_sha256": text.sha256_text()}}, {kind: "arch"})


func _shown() -> String:
	return Strings.row("events", String(_ev.id), "speaker_line", String(_ev.speaker_line))


func _check_lookup() -> void:
	_tables(_shown())
	if Voice.clip_for(_ev) != "res://" + FIXTURE:
		_failures.append("a clip whose hash is the shown line's was not found: '%s'" % Voice.clip_for(_ev))
	_tables(_shown() + " Changed.")
	if Voice.clip_for(_ev) != "":
		_failures.append("a stale clip (the line changed since it was voiced) was found")
	Voice.set_tables({}, {String(_ev.speaker["kind"]): "arch"})
	if Voice.clip_for(_ev) != "":
		_failures.append("a line with no manifest row found a clip")


## Neither data/voices/ nor assets/audio/voice/ need exist: the lazy read is silence.
func _check_absent_tables() -> void:
	Voice.reset()
	var path := Voice.clip_for(_ev)
	if path != "" and not FileAccess.file_exists(path):
		_failures.append("the shipped tables name a clip that does not exist: '%s'" % path)


func _check_settings_gate() -> void:
	_tables(_shown())
	var path := "res://" + FIXTURE
	_set_audio(true, 0)
	Voice.speak(_main, path)
	if _player() != null and _player().stream != null:
		_failures.append("Voices Off still loaded a clip")
	Voice.stop(_main)
	_set_audio(false, 2)
	Voice.speak(_main, path)
	if _player() != null and _player().stream != null:
		_failures.append("Sound Off still loaded a clip")
	for level in [1, 3]:
		_set_audio(true, level)
		Voice.speak(_main, path)
		var player := _player()
		if player == null or not (player.stream is AudioStreamOggVorbis):
			_failures.append("Voices level %d did not load the clip as Ogg Vorbis" % level)
		elif not is_equal_approx(player.volume_db, float(SoundK.VOICE_DB[level])):
			_failures.append("Voices level %d plays at %.1f dB, not %.1f" % [level, player.volume_db, SoundK.VOICE_DB[level]])
		Voice.stop(_main)


func _check_restore_silent() -> void:
	_set_audio(true, 2)
	_tables(_shown())
	var ns = _main._state.player()
	ns.event_queue.append({"event_id": String(_ev.id), "months_left": 3, "severity": 2, "speaker": _person_id})
	Voice.stop(_main)
	DeskCards.restore_after_load(_main)
	if _player() != null and _player().stream != null:
		_failures.append("a load's restored desk spoke a line")
	ns.event_queue.clear()
	_main._hud.inbox.clear()
	_main._event_cards.clear()
	_main._unseen_events.clear()


func _start_arrival() -> void:
	var ns = _main._state.player()
	ns.event_queue.append({"event_id": String(_ev.id), "months_left": 3, "severity": 3, "speaker": _person_id})
	Voice.stop(_main)
	_started = Time.get_ticks_msec()
	DeskCards.card_events(_main, _main._state.year, _main._state.month, {}, {})
	if _player() == null or _player().stream == null:
		_failures.append("an arrival whose speaker has a clip loaded nothing")


func _player() -> AudioStreamPlayer:
	return _main.get_node_or_null(Voice.NODE) as AudioStreamPlayer


func _set_audio(sound_on: bool, voices: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value("audio", "enabled", sound_on)
	cfg.set_value("audio", "voice", voices)
	cfg.save(SettingsPanel.CONFIG_PATH)


func _finish() -> bool:
	Voice.reset()
	if _had_settings:
		var f := FileAccess.open(SettingsPanel.CONFIG_PATH, FileAccess.WRITE)
		f.store_string(_settings_backup)
		f.close()
	elif FileAccess.file_exists(SettingsPanel.CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsPanel.CONFIG_PATH))
	if _failures.is_empty():
		print("PASS tests/test_voice_playback.gd")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: " + f)
		quit(1)
	return true
