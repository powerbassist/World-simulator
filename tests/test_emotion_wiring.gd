extends SceneTree

## #222 QA T4 + T5: the emotion kit's WIRING, which every targeted test let go
## silent (QA's mutants M1-M8, M11, M12, M15 stayed green). Each check drives the
## real surface and reads what the player would see:
##   - the audience scene: the greet caption on open, the face's mood badge, the
##     refusal caption after a BAD result, the farewell at the close;
##   - the chief's briefing card wears the badge its view's feelings give;
##   - the election verdict and the diplomatic card read their tones off the sim's
##     keys (RE-ELECTED good, DEFEATED bad; Agreed good, Refused not possible);
##   - a booked day's card says it carried or not by the sim's `ok`;
##   - the vote card's tone (proposal_note) follows the division;
##   - a refused energy, public-works or sector-programme command is said as a
##     BLOCKED line in its panel (the parent's call on #222), never dropped;
##   - the phone's Close button, a REAL click (press and release frames apart),
##     hushes the line: no voice outlives the call.
## No player plays headless, so a caption is set the moment its line is said.

const DataLoader = preload("res://src/core/data_loader.gd")
const AudienceScene = preload("res://src/ui/audience_scene.gd")
const ChiefBriefing = preload("res://src/ui/chief_briefing.gd")
const PhoneDialog = preload("res://src/ui/phone_dialog.gd")
const ElectionVerdict = preload("res://src/ui/election_verdict.gd")
const NationPanel = preload("res://src/ui/nation_panel.gd")
const WorldNews = preload("res://src/ui/world_news.gd")
const ProposalNote = preload("res://src/ui/proposal_note.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")
const Voice = preload("res://src/ui/voice.gd")
const AudienceVoice = preload("res://src/ui/audience_voice.gd")
const Click = preload("res://tests/click.gd")

const VOICE := {
	"greet": {"text": "Good of you to see me", "clip": ""},
	"agree": {"text": "That I can live with", "clip": ""},
	"refuse": {"text": "Then we have nothing more to say", "clip": ""},
	"farewell": {"text": "Until the next time", "clip": ""},
}
const FEEL := {"rapport": 0.4}


## A stand-in inbox: the three calls ResultTone makes, the tag kept per card.
class FakeInbox:
	var tags := {}
	var _next := 0

	func push(_title: String, _body: String) -> String:
		_next += 1
		return "card_%d" % _next

	func has_tag(id: String) -> bool:
		return tags.has(id)

	func add_under_title(id: String, control: Control) -> void:
		tags[id] = (control as Label).text
		control.free()


## The NationState fields ElectionVerdict.read() looks at.
class FakeNation:
	var in_government := true
	var has_executive := true
	var is_cohabitation := false


var _failures: Array[String] = []
var _frame := 0
var _loader
var _main
var _scene
var _chief
var _phone
var _closed := false


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	_scene = AudienceScene.new()
	_scene.size = Vector2(1120, 630)
	root.add_child(_scene)
	_chief = ChiefBriefing.new()
	root.add_child(_chief)
	_phone = PhoneDialog.new()
	root.add_child(_phone)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_check_audience()
			_check_chief()
			_check_verdicts()
			_check_appointments()
			_check_vote_card()
			_check_refusals()
			_arm_phone()
		5:
			Click.half(root, _phone._close, true)
		8:
			Click.half(root, _phone._close, false)
		10:
			_check_phone()
			_phone.hide()
			_arm_leave()
		12:
			Click.half(root, _scene._end, true)
		15:
			Click.half(root, _scene._end, false)
		17:
			_check_leave()
			_finish()
			return true
	return false


func _check_audience() -> void:
	var pid := String(_loader.person_by_id.keys()[0])
	var view := {"request_id": "req_1", "person_id": pid, "name": "Cécile Aumont", "ask": "",
		"stance": "defend", "president": "Daniel Moucron", "fog": "stranger", "traits": [],
		"offered": [], "topics": [], "attempts_left": 3, "voice": VOICE,
		"choices": {"now": 24310, "people": [], "feel": FEEL}}
	_scene.open(view)
	var spoken := _scene.find_child("Spoken", true, false) as Label
	if spoken == null or not spoken.visible or not spoken.text.contains(String(VOICE["greet"]["text"])):
		_fail("the audience opened without its greeting on screen: '%s'" % (spoken.text if spoken != null else "<none>"))
		return
	if _scene._face.find_child("MoodBadge", true, false) == null:
		_fail("the visitor's face wears no mood badge")
	_scene.show_result("They will not move.", view, "", {}, ResultTone.BAD)
	if not spoken.text.contains(String(VOICE["refuse"]["text"])):
		_fail("a BAD result did not give the refusal line: '%s'" % spoken.text)
	_scene.show_result("They will.", view, "", {}, ResultTone.GOOD)
	if not spoken.text.contains(String(VOICE["agree"]["text"])):
		_fail("a GOOD result did not give the agreeing line: '%s'" % spoken.text)
	_scene.show_close("refused", "The audience is over.")
	if not spoken.text.contains(String(VOICE["farewell"]["text"])):
		_fail("the close did not give the farewell: '%s'" % spoken.text)


func _check_chief() -> void:
	_chief.show_view({"header": "March", "who": "The chief", "line": "", "rows": [], "feel": FEEL, "close": "Continue"})
	if not _chief._face.has_node("MoodBadge"):
		_fail("the chief's briefing wears no mood badge for a view with feelings")
	_chief.show_view({"header": "April", "rows": [], "close": "Continue"})
	if _chief._face.has_node("MoodBadge"):
		_fail("a briefing with no chief kept the last one's badge")


func _check_verdicts() -> void:
	var ns := FakeNation.new()
	var won := ElectionVerdict.read([{"kind": "executive", "incumbent_largest": true}], ns)
	_expect("RE-ELECTED", String(won["tone"]), ResultTone.GOOD)
	ns.in_government = false
	var lost := ElectionVerdict.read([{"kind": "executive", "incumbent_largest": false}], ns)
	_expect("DEFEATED", String(lost["tone"]), ResultTone.BAD)
	var inbox := FakeInbox.new()
	NationPanel.say_result(inbox, "Trade pact", {"refused": false})
	NationPanel.say_result(inbox, "Trade pact", {"refused": true, "reason": "They are at war"})
	_expect_tag(inbox, "card_1", "an agreed diplomatic act", ResultTone.GOOD)
	_expect_tag(inbox, "card_2", "a refused diplomatic act", ResultTone.BLOCKED)


func _check_appointments() -> void:
	var news := WorldNews.new()
	var inbox := FakeInbox.new()
	news._stack = inbox
	news._loader = _loader
	var kept: String = news.card_appointment({"kind": "visit"}, "A visit", true)
	var failed: String = news.card_appointment({"kind": "visit"}, "A visit", false)
	_expect_tag(inbox, kept, "a booked day that carried", ResultTone.GOOD)
	_expect_tag(inbox, failed, "a booked day that did not carry", ResultTone.BAD)


func _check_vote_card() -> void:
	_expect("a carried division", ProposalNote.tone({"law_id": "x", "passed": true}, null), ResultTone.GOOD)
	_expect("a defeated division", ProposalNote.tone({"law_id": "x", "passed": false}, null), ResultTone.BAD)
	_expect("a tabled bill", ProposalNote.tone({"law_id": "x", "tabled": true, "vote_day": 1, "vote_month": 5}, null), "")
	_expect("a refused bill", ProposalNote.tone({"law_id": "x", "refused": true}, null), ResultTone.BLOCKED)
	_expect("a forced bill that fell to censure",
		ProposalNote.tone({"law_id": "x", "passed": true, "forced": true, "censure": {"carried": true}}, null), ResultTone.BAD)


func _check_refusals() -> void:
	var ns = _main._state.player()
	ns.last_project_result = {"action_id": String(_loader.project_actions[0].id), "applied": false, "refused": true}
	_main._projects_panel._refresh()
	_expect_blocked(_main._projects_panel, "a refused public work")
	ns.last_energy_result = {"action_id": String(_loader.energy_actions[0].id), "applied": false, "refused": true}
	_main._energy_panel._refresh()
	_expect_blocked(_main._energy_panel, "a refused energy order")
	# A programme the sim does not offer: execute() refuses it, as a stale button.
	var stale := {"id": "inv_stale", "name": "A stale programme", "effects": {"investment": {"sector": "none"}}}
	_main._companies_panel._on_invest(ns, stale)
	_main._companies_panel._refresh()
	_expect_blocked(_main._companies_panel, "a refused sector programme")


## A label in `panel` says "refused" in the BLOCKED colour.
func _expect_blocked(panel: Node, what: String) -> void:
	for label in panel.find_children("*", "Label", true, false):
		if (label as Label).text.contains("refused") and label.has_theme_color_override("font_color") \
				and label.get_theme_color("font_color") == ResultTone.TINT[ResultTone.BLOCKED]:
			return
	_fail("%s is not said as a BLOCKED line" % what)


## A line playing and one queued behind it, as on a call that has just been greeted.
func _arm_phone() -> void:
	_phone.closed.connect(func() -> void: _closed = true)
	var player := AudioStreamPlayer.new()
	player.name = Voice.NODE
	_phone.add_child(player)
	player.set_meta("pending", true)
	player.set_meta("next", "refuse")


## The audience over, its farewell said, and a reaction queued behind a line
## still playing: Leave must take the queue with it.
func _arm_leave() -> void:
	var player := AudioStreamPlayer.new()
	player.name = Voice.NODE
	_scene.add_child(player)
	player.set_meta("pending", true)
	AudienceVoice.say(_scene, _scene._spoken, VOICE, "agree")


func _check_leave() -> void:
	var player := _scene.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player == null:
		_fail("premise: the audience lost its voice player")
		return
	player.set_meta("pending", false)
	player.finished.emit()  # the playing line ends after Leave
	if String(player.get_meta("next", "")) != "" or _scene._spoken.text.contains(String(VOICE["agree"]["text"])):
		_fail("a line queued in the audience played after Leave (a real click)")


func _check_phone() -> void:
	if not _closed:
		_fail("a real click on Close did not close the call")
	var player := _phone.get_node_or_null(Voice.NODE) as AudioStreamPlayer
	if player == null:
		_fail("premise: the phone lost its voice player")
	elif bool(player.get_meta("pending", false)) or String(player.get_meta("next", "")) != "":
		_fail("Close (a real click) left the line playing or queued")


func _expect_tag(inbox: FakeInbox, card: String, what: String, tone: String) -> void:
	var want := Strings.t(String(ResultTone.TAG[tone][1]))
	if String(inbox.tags.get(card, "")) != want:
		_fail("%s is tagged '%s', expected '%s'" % [what, inbox.tags.get(card, ""), want])


func _expect(what: String, got: String, want: String) -> void:
	if got != want:
		_fail("%s reads '%s', expected '%s'" % [what, got, want])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_emotion_wiring: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
