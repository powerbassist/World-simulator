extends SceneTree

## V5.3-0 (e): the 78 clips of #226 (36 chief lines, 42 mood lines) are spoken, and
## no clip in the voice manifest is one nothing can ask for.
##   - the chief's briefing: every chief archetype's line for every situation and
##     variant resolves to its clip through the hash of the line the card shows; the
##     driver plays it under main, never over a desk speaker's line there, and the
##     card coming down silences it;
##   - the queue under main (the parent's four rules on #229): a line waiting behind
##     another is cancelled when its card closes, dropped by its card's hush, and
##     emptied by a stop (a load); a desk line that arrives while the chief talks
##     waits behind him and is never dropped;
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
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const AudienceVoice = preload("res://src/ui/audience_voice.gd")
const DeskCards = preload("res://src/ui/desk_cards.gd")
const Voice = preload("res://src/ui/voice.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")

const MANIFEST := "res://assets/audio/voice/manifest.json"
## Past two of Voice.QUEUE_POLL_S, so a waiting chief has looked again.
const WAIT_MS := 700
const CHIEFS := ["chief_fra", "chief_deu", "chief_gbr", "chief_pol"]
## Warm (PLEASED), wary (WORRIED), cold rapport (STERN): MoodBadge.emotion_of's cuts.
const WARM := {"rapport": 0.2}
const WARY := {"rapport": -0.2}
const COLD := {"rapport": -0.5}
const NEUTRAL := {"rapport": 0.0}
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
var _desk
var _card
var _said := {}
var _phase := "start"
var _since := 0
var _scene
var _phone


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_desk = Control.new()  # main's stand-in: the desk speakers' parent
	root.add_child(_desk)
	_card = Control.new()  # the briefing card's stand-in: its meta and visibility
	root.add_child(_card)
	_scene = AudienceScene.new()
	_scene.size = Vector2(1120, 630)
	root.add_child(_scene)
	_phone = PhoneDialog.new()
	root.add_child(_phone)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	match _phase:
		"start":
			_check_chief()
			_queue_behind_messenger()
			return false
		"waiting", "after", "cancel", "freed", "behind", "hushed", "stopped", "orphan":
			if Time.get_ticks_msec() - _since < WAIT_MS:
				return false
			_queue_step()
			return false
	_check_audience()
	_check_phone()
	_check_no_orphan()
	_check_situations()
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
	BriefingDriver.speak(_desk, {"line": said["text"], "clip": said["clip"]}, _card)
	var player := _desk.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player == null or player.stream == null or String(player.get_meta("card", "")) != BriefingDriver.LINE_CARD:
		_fail("the briefing shows the chief's line and does not speak it")
		return
	Voice.hush(_desk, BriefingDriver.LINE_CARD)
	if player.stream != null:
		_fail("the card coming down (Voice.hush on its id) left the chief's line playing")
	# A card with no clip (a French line, no chief) says nothing.
	BriefingDriver.speak(_desk, {"line": "Autre chose.", "clip": ""}, _card)
	if player.stream != null:
		_fail("a card with no clip still plays a line")
	# Once a card: the same month's key says nothing the second time (TAKE 3).
	_said = {"line": said["text"], "clip": said["clip"]}
	BriefingDriver.speak_once(_desk, _said, _card, "1:100")
	Voice.stop(_desk)
	BriefingDriver.speak_once(_desk, _said, _card, "1:100")
	if player.stream != null:
		_fail("the card opened again on the same month said its line twice")
	BriefingDriver.speak_once(_desk, _said, _card, "1:101")
	if player.stream == null:
		_fail("the next month's card said nothing")
	Voice.stop(_desk)


## An arrival month (TAKE 1): the messenger's line waits behind its sting on main's
## player; the chief neither cuts it nor is dropped, and speaks once it has ended.
func _queue_behind_messenger() -> void:
	var player := _desk.get_node(Voice.NODE) as AudioStreamPlayer
	player.set_meta("pending", true)
	player.set_meta("card", "desk_event")
	BriefingDriver.speak(_desk, _said, _card)
	if String(player.get_meta("card", "")) != "desk_event":
		_fail("the chief's line cut the messenger's waiting line")
	_phase = "waiting"
	_since = Time.get_ticks_msec()


func _queue_step() -> void:
	var player := _desk.get_node(Voice.NODE) as AudioStreamPlayer
	match _phase:
		"waiting":
			if String(player.get_meta("card", "")) != "desk_event":
				_fail("the waiting chief took the player while the messenger still held it")
			player.set_meta("pending", false)  # the messenger's line has ended
			_phase = "after"
		"after":
			if String(player.get_meta("card", "")) != BriefingDriver.LINE_CARD or player.stream == null:
				_fail("the messenger's line ended and the chief never spoke (an arrival month is silent)")
			# Closed while waiting: the queued line is cancelled, nothing replays.
			Voice.stop(_desk)
			player.set_meta("pending", true)
			player.set_meta("card", "desk_event")
			BriefingDriver.speak(_desk, _said, _card)
			_card.hide()
			player.set_meta("pending", false)
			_phase = "cancel"
		"cancel":
			if String(player.get_meta("card", "")) == BriefingDriver.LINE_CARD:
				_fail("the card was closed and its queued chief line still played")
			# Main goes (back to the menu) while the chief waits: the wait goes with it,
			# with no "Lambda capture ... was freed" ERROR (#229 QA TAKE 1; the runner
			# fails an undeclared ERROR line).
			var host := Control.new()
			root.add_child(host)
			var card := Control.new()
			host.add_child(card)
			card.set_meta(BriefingDriver.SPOKEN, "1:100")
			var busy := AudioStreamPlayer.new()
			busy.name = Voice.NODE
			busy.set_meta("pending", true)
			host.add_child(busy)
			BriefingDriver.speak(host, _said, card)
			host.queue_free()
			_phase = "freed"
		"freed":
			# Rule 4: a desk line that arrives while the chief talks waits behind him.
			Voice.stop(_desk)
			_card.show()
			Voice.speak(_desk, String(_said["clip"]), 0.0, BriefingDriver.LINE_CARD)
			player.set_meta("pending", true)  # the chief still talking (no player plays headless)
			DeskCards.say(_desk, "desk_event", String(_said["clip"]))
			if String(player.get_meta("card", "")) != BriefingDriver.LINE_CARD:
				_fail("a desk line cut the chief mid-line")
			player.stop()
			player.set_meta("pending", false)  # the chief has finished
			_phase = "behind"
		"behind":
			if String(player.get_meta("card", "")) != "desk_event" or player.stream == null:
				_fail("a desk line that arrived while the chief talked was dropped")
			# A queued line goes with its card's hush; the next one still plays.
			Voice.stop(_desk)
			player.set_meta("pending", true)
			player.set_meta("card", BriefingDriver.LINE_CARD)
			Voice.speak_queued(_desk, String(_said["clip"]), "desk_a")
			Voice.speak_queued(_desk, String(_said["clip"]), "desk_b")
			Voice.hush(_desk, "desk_a")
			player.set_meta("pending", false)
			_phase = "hushed"
		"hushed":
			if String(player.get_meta("card", "")) != "desk_b" or player.stream == null:
				_fail("a hushed card's queued line played, or the next one in line did not (%s)" % player.get_meta("card", ""))
			# Rule 3: a load stops everything, the queue included.
			player.stop()
			player.set_meta("pending", true)
			player.set_meta("card", BriefingDriver.LINE_CARD)
			Voice.speak_queued(_desk, String(_said["clip"]), "desk_c")
			Voice.stop(_desk)
			_phase = "stopped"
		"stopped":
			if player.stream != null:
				_fail("a stop (a load) left a queued line to play after it (%s)" % player.get_meta("card", ""))
			# The poll empties the queue and the line it starts holds the player; a line
			# queued in that same frame still has a poll to wait on.
			player.set_meta("pending", true)
			Voice.speak_queued(_desk, String(_said["clip"]), "desk_d")
			player.set_meta("pending", false)
			Voice._next(_desk, player, player.get_node(Voice.WAIT))
			player.set_meta("pending", true)  # desk_d talking
			Voice.speak_queued(_desk, String(_said["clip"]), "desk_e")
			player.stop()
			player.set_meta("pending", false)  # desk_d has ended
			_phase = "orphan"
		"orphan":
			if String(player.get_meta("card", "")) != "desk_e":
				_fail("a line queued in the frame the queue emptied never played (%s)" % player.get_meta("card", ""))
			_phase = "done"
	_since = Time.get_ticks_msec()


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
	_quiet(_scene)
	_scene.show_result("They will.", _with_feel(view, NEUTRAL), "", {}, ResultTone.GOOD)
	if not spoken.text.contains("Agreed."):
		_fail("wary to neutral says nothing of its own: agree by the tone, said '%s'" % spoken.text)
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


## Priorities.SITUATIONS is a hand list beside situation()'s literals (the parent's
## TAKE 2): every answer situation() gives is in it, and the list holds nothing
## situation() never answers, so the chief's line ids cannot drift from the ranking.
func _check_situations() -> void:
	var line := {"kind": "deadline", "deadline_month": -1, "standing": false, "u": 0.0, "held": false, "w": 0.0}
	var held := line.duplicate()
	held["held"] = true
	var crisis := line.duplicate()
	crisis["kind"] = "crisis"
	var answers := {}
	for lines in [[], [line], [held], [crisis, held]]:
		var said := Priorities.situation(lines)
		if not Priorities.SITUATIONS.has(said):
			_fail("situation() answered '%s', which Priorities.SITUATIONS lacks" % said)
		answers[said] = true
	for situation in Priorities.SITUATIONS:
		if not answers.has(situation):
			_fail("Priorities.SITUATIONS lists '%s', which situation() never answered" % situation)


## The voice player free again, so the next line is said now rather than queued.
func _quiet(parent: Node) -> void:
	AudienceVoice.hush(parent, true)


func _with_feel(view: Dictionary, feel: Dictionary) -> Dictionary:
	var out := view.duplicate(true)
	out["choices"]["feel"] = feel
	return out


func _fail(msg: String) -> void:
	_failures.append(msg)
