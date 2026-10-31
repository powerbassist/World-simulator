extends SceneTree

## V5.3-0 (e): the 78 clips of #226 (36 chief lines, 42 mood lines) are spoken, and
## no clip in the voice manifest is one nothing can ask for.
##   - the chief's briefing: every chief archetype's line for every situation and
##     variant resolves to its clip through the hash of the line the card shows, the
##     card plays it when it shows, and the card coming down silences it;
##   - a face that changes mood band during an audience or a call says its mood
##     line INSTEAD of agree or refuse (one line a result, never two queued); no
##     band change, the tone's line as before;
##   - every manifest row's line is one a caller asks for (AudienceVoice.LINES, the
##     chief's line ids, an event with a speaker line), in an archetype the table
##     has: a clip no code asks for is credit spent on silence.
## No player plays headless, so a line is read off the Voice node's stream and the
## caption, set the moment the line is said.

const DataLoader = preload("res://src/core/data_loader.gd")
const Person = preload("res://src/core/person.gd")
const AudienceScene = preload("res://src/ui/audience_scene.gd")
const PhoneDialog = preload("res://src/ui/phone_dialog.gd")
const ChiefBriefing = preload("res://src/ui/chief_briefing.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const AudienceVoice = preload("res://src/ui/audience_voice.gd")
const Voice = preload("res://src/ui/voice.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")

const MANIFEST := "res://assets/audio/voice/manifest.json"
const CHIEFS := ["chief_fra", "chief_deu", "chief_gbr", "chief_pol"]
## Warm (PLEASED), wary (WORRIED), cold rapport (STERN): MoodBadge.emotion_of's cuts.
const WARM := {"rapport": 0.2}
const WARY := {"rapport": -0.2}
const COLD := {"rapport": -0.5}
const VOICE := {
	"greet": {"text": "Good morning.", "clip": ""},
	"agree": {"text": "Agreed.", "clip": ""},
	"refuse": {"text": "No.", "clip": ""},
	"mood_pleased": {"text": "Pleased.", "clip": ""},
	"mood_cold": {"text": "Noted.", "clip": ""},
	"mood_angry": {"text": "That cost me.", "clip": ""},
}

var _failures: Array[String] = []
var _loader
var _frame := 0
var _chief
var _scene
var _phone


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_chief = ChiefBriefing.new()
	root.add_child(_chief)
	_scene = AudienceScene.new()
	_scene.size = Vector2(1120, 630)
	root.add_child(_scene)
	_phone = PhoneDialog.new()
	root.add_child(_phone)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check_chief()
	_check_audience()
	_check_phone()
	_check_no_orphan()
	for f in _failures:
		push_error("FAIL " + f)
	print("test_voice_lines: %s" % ("PASS" if _failures.is_empty() else "%d failure(s)" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)
	return true


func _check_chief() -> void:
	for arch in CHIEFS:
		var chief := Person.new()
		chief.id = "%s_fixture" % arch
		chief.kind = "chief_of_staff"
		chief.voice = arch
		_loader.person_by_id[chief.id] = chief
		for situation in ["calm", "tense", "crisis"]:
			for month in 3:
				var said: Dictionary = BriefingDriver.chief_said(_loader, chief.id, situation, month)
				if String(said["text"]) == "" or String(said["clip"]) == "":
					_fail("%s %s month %d: line '%s', clip '%s'" % [arch, situation, month, said["text"], said["clip"]])
	var said: Dictionary = BriefingDriver.chief_said(_loader, "chief_fra_fixture", "tense", 1)
	_chief.show()
	_chief.show_view({"header": "March", "line": said["text"], "clip": said["clip"], "rows": [], "close": "Continue"})
	var player := _chief.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player == null or player.stream == null:
		_fail("the briefing card shows the chief's line and does not speak it")
	Voice.stop(_chief)
	# A card with no clip (a French line, no chief) says nothing.
	_chief.show_view({"header": "April", "line": "Autre chose.", "clip": "", "rows": [], "close": "Continue"})
	if player != null and player.stream != null:
		_fail("a card with no clip still plays a line")


func _check_audience() -> void:
	var view := {"person_id": "", "name": "Someone", "stance": "neutral", "fog": "low",
		"traits": [], "offered": [], "topics": [], "attempts_left": 3, "voice": VOICE,
		"choices": {"now": 0, "people": [], "feel": WARY}}
	_scene.open(view)
	# The face is a portrait only for a known person: give it one child so the badge has a face.
	if _scene._face.get_child_count() == 0:
		_scene._face.add_child(Control.new())
		_scene._badge(view)
	var spoken := _scene._spoken as Label
	_quiet(_scene)
	_scene.show_result("They will.", _with_feel(view, WARY), "", {}, ResultTone.GOOD)
	if not spoken.text.contains("Agreed."):
		_fail("no band change: the GOOD result should say agree, said '%s'" % spoken.text)
	_quiet(_scene)
	_scene.show_result("They will.", _with_feel(view, WARM), "", {}, ResultTone.GOOD)
	if not spoken.text.contains("Pleased."):
		_fail("wary to warm: the face should say mood_pleased, said '%s'" % spoken.text)
	var player := _scene.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player != null and String(player.get_meta("next", "")) != "":
		_fail("the mood line queued a second line behind it (stacked)")
	_quiet(_scene)
	_scene.show_result("They will not.", _with_feel(view, COLD), "", {}, ResultTone.BAD)
	if not spoken.text.contains("That cost me."):
		_fail("warm to cold: the face should say mood_angry, said '%s'" % spoken.text)
	_quiet(_scene)
	_scene.show_result("They will not.", _with_feel(view, WARY), "", {}, ResultTone.BAD)
	if not spoken.text.contains("Noted."):
		_fail("cold to wary: the face should say mood_cold, said '%s'" % spoken.text)
	_quiet(_scene)
	_scene.show_result("They will not.", _with_feel(view, WARY), "", {}, ResultTone.BAD)
	if not spoken.text.contains("No."):
		_fail("the same band again: refuse, said '%s'" % spoken.text)
	_scene.close_scene()


func _check_phone() -> void:
	var view := {"name": "Someone", "why_not": "", "levers": [], "topics": [], "stance": "neutral",
		"ask": "", "president": "", "voice": VOICE, "choices": {"now": 0, "feel": WARM}}
	_phone.open(view)
	_quiet(_phone)
	_phone.show_result("They are not moved.", [], {}, ResultTone.BAD, COLD)
	if not (_phone._spoken as Label).text.contains("That cost me."):
		_fail("a call that turns a warm face cold should say mood_angry, said '%s'" % (_phone._spoken as Label).text)
	_phone.open(view)
	_quiet(_phone)
	_phone.show_result("They agree.", [], {}, ResultTone.GOOD, WARM)
	if not (_phone._spoken as Label).text.contains("Agreed."):
		_fail("a call with no band change should say agree, said '%s'" % (_phone._spoken as Label).text)
	_phone.close()


func _check_no_orphan() -> void:
	var asked := {}
	for id in AudienceVoice.LINES:
		asked[String(id)] = true
	for id in BriefingDriver.chief_line_ids():
		asked[String(id)] = true
	for ev in _loader.events:
		if String(ev.speaker_line).strip_edges() != "":
			asked["event." + String(ev.id)] = true
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not (manifest is Dictionary) or (manifest as Dictionary).is_empty():
		_fail("the voice manifest is missing or empty")
		return
	for key in manifest.keys():
		var row: Dictionary = manifest[key]
		var arch := String(row.get("archetype", ""))
		var line_id := String(row.get("line_id", ""))
		if String(key) != "%s/%s" % [arch, line_id]:
			_fail("manifest key '%s' is not its archetype/line_id" % key)
		if not _loader.voice_archetypes.has(arch):
			_fail("%s: archetype '%s' is not in the table, so no person speaks it" % [key, arch])
		if not asked.has(line_id):
			_fail("%s: line '%s' has no caller (an orphan clip)" % [key, line_id])


## The voice player free again, so the next line is said now rather than queued.
func _quiet(parent: Node) -> void:
	AudienceVoice.hush(parent, true)


func _with_feel(view: Dictionary, feel: Dictionary) -> Dictionary:
	var out := view.duplicate(true)
	out["choices"]["feel"] = feel
	return out


func _fail(msg: String) -> void:
	_failures.append(msg)
