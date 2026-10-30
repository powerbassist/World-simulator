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
## The archetype is the ONE resolver's, src/core/voices.gd (QA's RECORD on #199):
## the delivered speaker's own (`Voices.speaker_archetype` over the desk entry's
## person -- a woman prime minister speaks in her own voice), and when that
## archetype has no clip of the line, the speaker form's default (the pipeline's
## default reading, one clip a line, made before its `--every` reading is). Between
## the two, the archetype of the default's kind in the speaker's own sex (the
## parent's call on QA's #206, no paid batch): a woman regional figure made party
## leader, then prime minister, by a challenge has no clip of an office line in her
## own archetype, and speaks it as politician_f_50 -- whose office lines all exist --
## rather than the office's male default. Evidence lines take the same net.
##
## Read as bytes and decoded with load_from_buffer, never load(): the fresh-clone
## rule the fonts and icons follow (AGENTS.md).

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const SoundK = preload("res://src/ui/sound_constants.gd")
const Strings = preload("res://src/ui/strings.gd")

const Voices = preload("res://src/core/voices.gd")

const MANIFEST := "res://assets/audio/voice/manifest.json"
## The one player, a child of whatever node speaks: a new line stops the last.
const NODE := "Voice"  # i18n: ok a node name

## Read once on first use; null means not read yet.
static var _manifest = null


## Test seam: a fixture manifest in place of the shipped one.
static func set_tables(manifest: Dictionary) -> void:
	_manifest = manifest


## Back to the shipped manifest, read again on next use.
static func reset() -> void:
	_manifest = null


## The clip that says `ev`'s speaker line as the card shows it, or "": in the voice
## of `person_id` (the desk entry's "speaker") when that archetype has a clip of the
## line, else in the speaker form's default.
static func clip_for(ev, loader, person_id: String) -> String:
	if ev == null or loader == null:
		return ""
	# Hashed as Strings returns it, before speaker_row's strip: the pipeline hashed
	# the raw speaker_line, and English is that line unchanged.
	var shown := Strings.row("events", String(ev.id), "speaker_line", String(ev.speaker_line))
	if shown.strip_edges() == "":
		return ""
	var own := Voices.speaker_archetype(loader, ev.speaker, person_id)
	var fallback := Voices.speaker_archetype(loader, ev.speaker, "")
	for arch in [own, same_sex(loader, own, fallback), fallback]:
		var path := _clip(String(arch), String(ev.id), shown)
		if path != "":
			return path
	return ""


## The archetype of `fallback`'s kind in `own`'s sex (the table's `kind` and `sex`),
## or "" when either is unknown. Ties to id, so the pick never depends on file order.
static func same_sex(loader, own: String, fallback: String) -> String:
	var rows: Dictionary = loader.voice_archetypes
	if not rows.has(own) or not rows.has(fallback):
		return ""
	var kind := String(rows[fallback].get("kind", ""))
	var sex := String(rows[own].get("sex", ""))
	var ids: Array = rows.keys()
	ids.sort()
	for id in ids:
		if String(rows[id].get("kind", "")) == kind and String(rows[id].get("sex", "")) == sex:
			return String(id)
	return ""


static func _clip(arch: String, event_id: String, shown: String) -> String:
	if arch == "":
		return ""
	var row = _tables().get("%s/event.%s" % [arch, event_id], null)
	if not (row is Dictionary) or String(row.get("text_sha256", "")) != shown.sha256_text():
		return ""
	var path := "res://" + String(row.get("file", ""))
	return path if path.ends_with(".ogg") and FileAccess.file_exists(path) else ""


## Plays `path` under `parent` after `delay_s` (the arrival's sting rings first).
## Sound Off or Voices Off is silence, read at play time as every cue is. A line
## already playing or waiting to start is never cut off: the newer one is dropped
## (review pass 1 -- the lapse guard, run after the arrivals, used to replace the
## month's arrival line). `card_id` names the card the line belongs to, so
## hush() can end it with that card.
static func speak(parent: Node, path: String, delay_s := 0.0, card_id := "") -> void:
	if parent == null or not parent.is_inside_tree() or path == "":
		return
	var level := SettingsPanel.voice_level()
	if not SettingsPanel.sound_enabled() or level == 0:
		return
	var player := parent.get_node_or_null(NODE) as AudioStreamPlayer
	if player != null and (player.playing or bool(player.get_meta("pending", false))):
		return
	var stream := AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(path))
	if stream == null:
		return
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = NODE
		parent.add_child(player)
	player.stream = stream
	player.volume_db = float(SoundK.VOICE_DB[level])
	player.set_meta("card", card_id)
	if delay_s <= 0.0:
		player.play()
		return
	# A token, so a delayed start that stop() has cancelled does not fire.
	var token := int(player.get_meta("token", 0)) + 1
	player.set_meta("token", token)
	player.set_meta("pending", true)
	parent.get_tree().create_timer(delay_s).timeout.connect(func():
		if is_instance_valid(player) and int(player.get_meta("token", 0)) == token:
			player.set_meta("pending", false)
			player.play())


## Silences `parent`'s line, a pending start included.
static func stop(parent: Node) -> void:
	var player := parent.get_node_or_null(NODE) as AudioStreamPlayer if parent != null else null
	if player == null:
		return
	player.stop()
	player.stream = null
	player.set_meta("pending", false)
	player.set_meta("token", int(player.get_meta("token", 0)) + 1)


## Silences the line only if it belongs to `card_id` -- the card was answered or
## dismissed, so its speaker has nothing left to say.
static func hush(parent: Node, card_id: String) -> void:
	var player := parent.get_node_or_null(NODE) as AudioStreamPlayer if parent != null else null
	if player != null and card_id != "" and String(player.get_meta("card", "")) == card_id:
		stop(parent)


static func _tables() -> Dictionary:
	if _manifest == null:
		_manifest = _read(MANIFEST)
	return _manifest


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
