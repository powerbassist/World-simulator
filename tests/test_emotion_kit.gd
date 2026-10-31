extends SceneTree

## V5.3-0 (c), 4.2 (docs/design/v5.3-0-readability.md): faces react and audiences
## speak.
##
##   - the mood badge reads Feelings' own bands (a cold, a wary, a warm, a hostile
##     person each wear their mood), its tooltip is the card's words, and a reused
##     face slot keeps ONE badge;
##   - a person's four lines resolve with text AND clip (the 56 shipped clips, so a
##     line on screen is a line heard), a lever's tone picks agree or refuse, and a
##     said line is shown as a quoted caption.

const DataLoader = preload("res://src/core/data_loader.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")
const AudienceVoice = preload("res://src/ui/audience_voice.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Voices = preload("res://src/core/voices.gd")
const Motion = preload("res://src/ui/motion.gd")
const TopBar = preload("res://src/ui/top_bar.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Voice = preload("res://src/ui/voice.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_moods()
	_check_badge()
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
	else:
		_check_lines(loader)
	_check_reactions()
	_check_figure_flash()
	if _failures.is_empty():
		print("test_emotion_kit: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _check_moods() -> void:
	var cases := [
		["a stranger", {}, Portrait.Emotion.NEUTRAL],
		["a warm person", {"rapport": 0.2}, Portrait.Emotion.PLEASED],
		["a wary person", {"rapport": -0.1}, Portrait.Emotion.WORRIED],
		["a cold person", {"rapport": -0.5}, Portrait.Emotion.STERN],
		["an annoyed friend", {"rapport": 0.4, "grudge": 0.1}, Portrait.Emotion.WORRIED],
		["a resentful friend", {"rapport": 0.4, "grudge": 0.3}, Portrait.Emotion.STERN],
	]
	for c in cases:
		var got := MoodBadge.emotion_of(c[1])
		if got != int(c[2]):
			_fail("%s wears mood %d, expected %d" % [c[0], got, c[2]])
	# The badge says the card's word, so the two cannot disagree.
	var cold := {"rapport": -0.5, "grudge": 0.3}
	var said := MoodBadge.words_of(cold)
	for register in ["rapport", "grudge"]:
		var word := Feelings.word(register, float(cold[register]))
		if not said.contains(word):
			_fail("the badge's words '%s' lack the card's %s word '%s'" % [said, register, word])
	# No mood art for a stranger id: their face stays the neutral one.
	if MoodBadge.mood_portrait("NOPE_nobody", cold) != Portrait.Emotion.NEUTRAL:
		_fail("a person with no mood art was asked for a mood portrait")


func _check_badge() -> void:
	var face := Control.new()
	MoodBadge.wear(face, {"rapport": 0.4})
	MoodBadge.wear(face, {"rapport": -0.5})
	var badges := face.get_children().filter(func(c): return String(c.name) == "MoodBadge")
	if badges.size() != 1:
		_fail("a re-read face wears %d badges, expected 1" % badges.size())
	elif int(badges[0].emotion) != Portrait.Emotion.STERN:
		_fail("a re-read badge kept its old mood")
	elif String(badges[0].tooltip_text) == "":
		_fail("the badge has no words")
	face.free()


func _check_lines(loader) -> void:
	var pid := ""
	for id in loader.person_by_id:
		if Voices.archetype_of(loader, String(id)) != "":
			pid = String(id)
			break
	if pid == "":
		_fail("no person has a voice archetype")
		return
	var voice := AudienceVoice.lines(loader, pid)
	for id in AudienceVoice.LINES:
		if not voice.has(id) or String(voice[id]["text"]) == "":
			_fail("%s has no %s line" % [pid, id])
		elif String(voice[id]["clip"]) == "":
			_fail("%s's %s line '%s' has no clip that says it" % [pid, id, voice[id]["text"]])
	if not AudienceVoice.lines(loader, "NOPE_nobody").is_empty():
		_fail("a person with no archetype has lines")
	# Said: a quoted caption, shown (no tree, so no sound -- Voice.speak's own guard).
	var holder := Node.new()
	var caption := Label.new()
	caption.visible = false
	AudienceVoice.say(holder, caption, voice, "greet")
	if not caption.visible or not caption.text.contains(String(voice["greet"]["text"])):
		_fail("the greet line was not shown: '%s'" % caption.text)
	AudienceVoice.say(holder, caption, voice, "")
	if not caption.text.contains(String(voice["greet"]["text"])):
		_fail("a neutral result replaced the line")
	# Queued behind a line still playing: the newest caller's voice speaks, not the
	# voice of the call that first queued (#222 pass 1). A pending player stands in
	# for one that is playing; finished is emitted by hand.
	var player := AudioStreamPlayer.new()
	player.name = Voice.NODE
	player.set_meta("pending", true)
	holder.add_child(player)
	var other := {"greet": {"text": "Someone else entirely.", "clip": ""}}  # i18n: ok test data
	AudienceVoice.say(holder, caption, voice, "farewell")
	AudienceVoice.say(holder, caption, other, "greet")
	player.set_meta("pending", false)
	player.finished.emit()
	if not caption.text.contains("Someone else entirely."):
		_fail("a queued line was read from the first caller's voice: '%s'" % caption.text)
	# The queue is cleared when an audience opens on someone new, and cut with the
	# line when a call closes: Voice.stop emits no `finished` (#222 pass 2).
	player.set_meta("pending", true)
	AudienceVoice.say(holder, caption, voice, "farewell")
	AudienceVoice.hush(holder)
	if String(player.get_meta("next", "")) != "":
		_fail("hush() left a queued line")
	AudienceVoice.say(holder, caption, voice, "farewell")
	AudienceVoice.hush(holder, true)
	for c in player.finished.get_connections():
		if (c["callable"] as Callable).get_method() == "_said_next":
			_fail("hush(stop) left the queue's one-shot on `finished`")
	if String(player.get_meta("next", "")) != "":
		_fail("hush(stop) left a queued line")
	# Above every cut (NaN): no word and no band, as word() always had it.
	if Feelings.band("grudge", NAN) != -1 or Feelings.word("grudge", NAN) != "":
		_fail("a value past every cut found a band")
	caption.free()
	holder.free()


func _check_reactions() -> void:
	var want := {ResultTone.GOOD: "agree", ResultTone.RISKY: "agree", ResultTone.BAD: "refuse", ResultTone.BLOCKED: "refuse", "": ""}
	for tone in want:
		if AudienceVoice.reaction(tone) != want[tone]:
			_fail("tone '%s' draws '%s', expected '%s'" % [tone, AudienceVoice.reaction(tone), want[tone]])


## 4.5: a figure flashes its status tone by its good direction; a reading that
## changed shape, or a figure with no verdict, does not flash.
func _check_figure_flash() -> void:
	var cases := [
		["approval up", "approval", "41%", "43%", UiTheme.GOOD],
		["approval down", "approval", "43%", "41%", UiTheme.BAD],
		# The strip's own text: the signed balance, Num.fs(-deficit) ("%+.2f").
		["deficit up", "deficit", "-4.10%", "-4.60%", UiTheme.BAD],
		["deficit down", "deficit", "-4.60%", "-4.10%", UiTheme.GOOD],
		["a negative growth deeper", "gdp", "-0.4%", "-1.2%", UiTheme.BAD],
		["unemployment down", "unemployment", "7.4%", "7.1%", UiTheme.GOOD],
		["no move", "approval", "41%", "41%", Color(0, 0, 0, 0)],
		["a reading that changed shape", "approval", "41%", "no poll", Color(0, 0, 0, 0)],
		["a figure with no verdict", "assembly", "289", "301", Color(0, 0, 0, 0)],
	]
	for c in cases:
		var got := TopBar.flash_tone(c[1], c[2], c[3])
		if got != c[4]:
			_fail("%s flashes %s, expected %s" % [c[0], got, c[4]])


func _fail(message: String) -> void:
	_failures.append(message)
