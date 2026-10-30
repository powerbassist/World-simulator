extends SceneTree

## Headless test: godot --headless --script res://tests/test_voice_playback.gd
## Non-zero exit on any failure.
##
## V5.2d playback (docs/design/v5.2-d-spec.md section 6), over a FIXTURE clip
## (tests/fixtures/voice/line.ogg, a 0.4 s tone made with ffmpeg) and a fixture
## manifest in tools/voice_pipeline.py's shape:
##   - Godot's sha256_text() is the pipeline's hashlib hash of the UTF-8 bytes (two
##     pins computed in Python, one of them non-ASCII);
##   - the clip is found in the delivered speaker's own archetype, else the speaker
##     form's default (src/core/voices.gd, QA's RECORD on #199), and plays only when
##     the manifest's hash is the shown line's; a stale hash, no manifest row and no
##     manifest at all are silence, and print nothing;
##   - Voices Off and Sound Off are silence; a level sets the player's volume;
##   - an ARRIVAL with a face speaks; a load's restored desk does not; a line is
##     not cut off by the next one, and ends when its card is answered or dismissed.

## suite-exclusive: backs up and restores user://settings.cfg -- the checks write the Sound and Voices settings

const Voice = preload("res://src/ui/voice.gd")
const Voices = preload("res://src/core/voices.gd")
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
			_check_own_voice_first()
			_check_promoted_woman()
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


## The fixture manifest: the speaker form's default archetype's clip of the event's
## line is the fixture, hashed as `text` says.
func _tables(text: String) -> void:
	Voice.set_tables(_rows({_default_arch(): text}))


## Manifest rows for the event's line, one per archetype -> the text it was hashed from.
func _rows(texts: Dictionary) -> Dictionary:
	var out := {}
	for arch in texts:
		out["%s/event.%s" % [arch, _ev.id]] = {"archetype": arch, "line_id": "event.%s" % _ev.id,
			"file": FIXTURE, "text_sha256": String(texts[arch]).sha256_text()}
	return out


func _default_arch() -> String:
	return Voices.speaker_archetype(_main._loader, _ev.speaker, "")


func _clip(person_id := "") -> String:
	return Voice.clip_for(_ev, _main._loader, person_id)


func _shown() -> String:
	return Strings.row("events", String(_ev.id), "speaker_line", String(_ev.speaker_line))


func _check_lookup() -> void:
	if _default_arch() == "":
		_failures.append("fixture: the event's speaker form has no default archetype")
	_tables(_shown())
	if _clip() != "res://" + FIXTURE:
		_failures.append("a clip whose hash is the shown line's was not found: '%s'" % _clip())
	_tables(_shown() + " Changed.")
	if _clip() != "":
		_failures.append("a stale clip (the line changed since it was voiced) was found")
	Voice.set_tables({})
	if _clip() != "":
		_failures.append("a line with no manifest row found a clip")


## QA's RECORD on #199: a person whose own archetype is not the form's default (a
## woman prime minister) speaks in her own voice when it has a clip of the line, and
## in the default when it has none. Each half makes the OTHER archetype's row stale,
## so only the archetype the rule picks can be the one found.
func _check_own_voice_first() -> void:
	var default_arch := _default_arch()
	var pid := ""
	var own := ""
	for id in _main._loader.person_by_id:
		var arch := Voices.speaker_archetype(_main._loader, _ev.speaker, String(id))
		if arch != "" and arch != default_arch:
			pid = String(id)
			own = arch
			break
	if pid == "":
		_failures.append("fixture: no person speaks in an archetype other than the form's default")
		return
	Voice.set_tables(_rows({own: _shown(), default_arch: _shown() + " Stale."}))
	if _clip(pid) != "res://" + FIXTURE:
		_failures.append("a speaker's own archetype clip did not win over the form's default")
	Voice.set_tables(_rows({own: _shown() + " Stale.", default_arch: _shown()}))
	if _clip(pid) != "res://" + FIXTURE:
		_failures.append("a speaker whose own archetype has no clip did not fall back to the default")
	Voice.set_tables(_rows({own: _shown(), default_arch: _shown()}))
	if _clip("no_such_person") != "res://" + FIXTURE:
		_failures.append("an unknown speaker id did not fall back to the form's default clip")


## The parent's call on QA's #206: a woman of another kind made party leader, then
## prime minister, by a challenge has no office-line clip in her own archetype; she
## speaks it in the same-sex archetype of the office's default kind
## (politician_f_50), never the office's male default. The default's row is stale,
## so only the same-sex step can find the clip.
func _check_promoted_woman() -> void:
	var loader = _main._loader
	var ev = null
	for candidate in loader.events:
		if String(candidate.speaker_line).strip_edges() != "" and candidate.speaker.has("office"):
			ev = candidate
			break
	if ev == null:
		_failures.append("fixture: no event carries an office speaker and a line")
		return
	var fallback := Voices.speaker_archetype(loader, ev.speaker, "")
	var rows: Dictionary = loader.voice_archetypes
	var pid := ""
	var own := ""
	for id in loader.person_by_id:
		var arch := Voices.speaker_archetype(loader, ev.speaker, String(id))
		if rows.has(arch) and rows.has(fallback) and String(rows[arch].get("sex", "")) == "f" 				and String(rows[arch].get("kind", "")) != String(rows[fallback].get("kind", "")):
			pid = String(id)
			own = arch
			break
	var twin := Voice.same_sex(loader, own, fallback)
	if pid == "" or twin == "" or twin == fallback:
		_failures.append("fixture: no woman of another kind, or no same-sex office archetype (%s, %s)" % [own, twin])
		return
	var shown := Strings.row("events", String(ev.id), "speaker_line", String(ev.speaker_line))
	var manifest := {}
	for pair in [[twin, shown], [fallback, shown + " Stale."]]:
		manifest["%s/event.%s" % [pair[0], ev.id]] = {"archetype": pair[0], "line_id": "event.%s" % ev.id,
			"file": FIXTURE, "text_sha256": String(pair[1]).sha256_text()}
	Voice.set_tables(manifest)
	if Voice.clip_for(ev, loader, pid) != "res://" + FIXTURE:
		_failures.append("a promoted woman (%s) with no clip of her own did not speak in %s" % [own, twin])


## Neither data/voices/ nor assets/audio/voice/ need exist: the lazy read is silence.
func _check_absent_tables() -> void:
	Voice.reset()
	var path := _clip(_person_id)
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
