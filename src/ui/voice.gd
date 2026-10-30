extends RefCounted

## V5.2d playback (docs/design/v5.2-d-spec.md section 6): the event speaker's line,
## spoken when its decision card arrives. The clips are tools/voice_pipeline.py's,
## found through its manifest (assets/audio/voice/manifest.json, keyed
## "<archetype>/event.<event id>") and played only when the manifest's text_sha256
## is the hash of the line the card SHOWS -- a line edited since it was voiced, or
## the same line in another language, is silence rather than a voice saying
## something the card does not. No clip, no manifest, no archetype table: silence,
## and nothing printed, since none of them need exist.
##
## The archetype is the speaker form's default (data/voices/archetypes.json's
## `defaults`: a kind, "office:<office>", "evidence_person", "foreign_head") -- the
## pipeline's default reading, one clip a line. Its `--every` reading voices a line
## once per archetype a speaker may carry, keyed by the PERSON's own `voice`; the
## loader does not read that field yet, so that reading needs it there first.
##
## Read as bytes and decoded with load_from_buffer, never load(): the fresh-clone
## rule the fonts and icons follow (AGENTS.md).

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const SoundK = preload("res://src/ui/sound_constants.gd")
const Strings = preload("res://src/ui/strings.gd")

const MANIFEST := "res://assets/audio/voice/manifest.json"
const ARCHETYPES := "res://data/voices/archetypes.json"
## The one player, a child of whatever node speaks: a new line stops the last.
const NODE := "Voice"  # i18n: ok a node name

## Read once on first use; null means not read yet.
static var _manifest = null
static var _defaults = null


## Test seam: fixture tables in place of the shipped files.
static func set_tables(manifest: Dictionary, defaults: Dictionary) -> void:
	_manifest = manifest
	_defaults = defaults


## Back to the shipped files, read again on next use.
static func reset() -> void:
	_manifest = null
	_defaults = null


## The clip that says `ev`'s speaker line as the card shows it, or "".
static func clip_for(ev) -> String:
	if ev == null:
		return ""
	# Hashed as Strings returns it, before speaker_row's strip: the pipeline hashed
	# the raw speaker_line, and English is that line unchanged.
	var shown := Strings.row("events", String(ev.id), "speaker_line", String(ev.speaker_line))
	var arch := archetype(ev.speaker)
	if shown.strip_edges() == "" or arch == "":
		return ""
	var row = _tables()[0].get("%s/event.%s" % [arch, ev.id], null)
	if not (row is Dictionary) or String(row.get("text_sha256", "")) != shown.sha256_text():
		return ""
	var path := "res://" + String(row.get("file", ""))
	return path if path.ends_with(".ogg") and FileAccess.file_exists(path) else ""


## The default archetype for a speaker form, or "" -- voice_pipeline.voices_for's
## default reading.
static func archetype(speaker: Dictionary) -> String:
	var key := ""
	if speaker.has("kind"):
		key = String(speaker["kind"])
	elif speaker.has("office"):
		key = "office:" + String(speaker["office"])
	elif bool(speaker.get("evidence_person", false)):
		key = "evidence_person"
	elif bool(speaker.get("foreign_head", false)):
		key = "foreign_head"
	return String(_tables()[1].get(key, ""))


## Plays `path` under `parent` after `delay_s` (the arrival's sting rings first).
## Sound Off or Voices Off is silence, read at play time as every cue is.
static func speak(parent: Node, path: String, delay_s := 0.0) -> void:
	if parent == null or not parent.is_inside_tree() or path == "":
		return
	var level := SettingsPanel.voice_level()
	if not SettingsPanel.sound_enabled() or level == 0:
		return
	var stream := AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(path))
	if stream == null:
		return
	var player := parent.get_node_or_null(NODE) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = NODE
		parent.add_child(player)
	player.stop()
	player.stream = stream
	player.volume_db = float(SoundK.VOICE_DB[level])
	# A token, so a delayed start that a newer line has replaced does not fire.
	var token := int(player.get_meta("token", 0)) + 1
	player.set_meta("token", token)
	if delay_s <= 0.0:
		player.play()
		return
	parent.get_tree().create_timer(delay_s).timeout.connect(func():
		if is_instance_valid(player) and int(player.get_meta("token", 0)) == token:
			player.play())


## Silences `parent`'s line, a pending start included.
static func stop(parent: Node) -> void:
	var player := parent.get_node_or_null(NODE) as AudioStreamPlayer if parent != null else null
	if player == null:
		return
	player.stop()
	player.stream = null
	player.set_meta("token", int(player.get_meta("token", 0)) + 1)


static func _tables() -> Array:
	if _manifest == null:
		_manifest = _read(MANIFEST)
	if _defaults == null:
		var defaults = _read(ARCHETYPES).get("defaults", {})
		_defaults = defaults if defaults is Dictionary else {}
	return [_manifest, _defaults]


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
