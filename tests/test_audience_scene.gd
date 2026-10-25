extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_scene.gd
## Non-zero exit on any failure.
##
## V5.2b, the audience scene, on Levers' row shapes (src/sim/levers.gd):
##   - the levers print their odds as a range ("35–60 %"), never a point, and say
##     why the range is wide (the fog word) and which traits are known; a lever the
##     sim does not offer is disabled with its reason;
##   - every spend reads BEFORE the click: bargain's currency (a favour, a vote
##     trade, aid refused with its reason), the promise's date and that it binds;
##   - a real click on a lever (press and release frames apart) emits that lever;
##     the promise emits its picked date, the gossip its third person;
##   - attempts spent leave the levers down and the scene says to end it;
##   - End and Leave are two steps: after the sim closes it, the button leaves;
##   - the person's opening line comes through DialogueManager from
##     data/audiences/default.dialogue ({{ask}} in their mouth); a stance's file
##     replaces the default title by title, and once Content ships any stance
##     file, every stance has one.

const AudienceScene = preload("res://src/ui/audience_scene.gd")
const DialogueLines = preload("res://src/ui/dialogue_lines.gd")
const Words = preload("res://src/ui/lever_words.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _scene
var _frame := 0
var _emitted := []

const NOW := 24310
const OFFERED := [
	{"lever": "argue", "offered": true, "why_not": "", "odds_lo": 0.35, "odds_hi": 0.6, "fog": "stranger", "spends": {}},
	{"lever": "bargain", "offered": true, "why_not": "", "odds_lo": 0.2, "odds_hi": 0.56, "fog": "stranger",
		"spends": {"rapport": -0.1, "iou": 1.0}, "currencies": [
			{"currency": "favour", "offered": true, "why_not": "", "spends": {"rapport": -0.1}},
			{"currency": "vote_trade", "offered": true, "why_not": "", "spends": {"iou": 1.0}},
			{"currency": "aid", "offered": false, "why_not": "aid is not open yet", "spends": {}}]},
	{"lever": "promise_date", "offered": true, "why_not": "", "odds_lo": 0.25, "odds_hi": 0.61, "fog": "stranger", "spends": {"promise": 1.0}},
	{"lever": "friendship", "offered": false, "why_not": "you are not friends", "odds_lo": 0.0, "odds_hi": 0.0, "fog": "stranger", "spends": {"bond": -1.0}},
]
const TOPICS := [{"topic": "family", "offered": true, "why_not": ""}, {"topic": "gossip", "offered": true, "why_not": ""},
	{"topic": "flirt", "offered": false, "why_not": "not yet: the shadows come later"}]


func _init() -> void:
	_scene = AudienceScene.new()
	_scene.size = Vector2(1120, 630)
	root.add_child(_scene)


func _view(offered: Array, attempts: int) -> Dictionary:
	return {"request_id": "req_1", "person_id": "", "name": "Cécile Aumont", "ask": "the pension age held",
		"stance": "defend", "president": "Daniel Moucron", "fog": "stranger", "traits": ["Vain"],
		"offered": offered, "topics": TOPICS, "attempts_left": attempts,
		"choices": {"now": NOW, "people": [{"id": "p_x", "name": "Paul Ixe"}]}}


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_scene.attempted.connect(func(lever: String, args: Dictionary) -> void: _emitted.append([lever, args]))
			_scene.talked.connect(func(topic: String, args: Dictionary) -> void: _emitted.append([topic, args]))
			_scene.ended.connect(func() -> void: _emitted.append(["ended"]))
			_scene.closed.connect(func() -> void: _emitted.append(["closed"]))
			_scene.open(_view(OFFERED, 3))
		5:
			_check_open()
			_check_spends()
			_press(true)
		9:
			_press(false)
		11:
			_check_clicks()
			var spent := []
			for row in OFFERED:
				var r: Dictionary = row.duplicate()
				r["offered"] = false
				r["why_not"] = "no attempts left"
				# The sim refuses every currency too once no attempt is left.
				if r.has("currencies"):
					var refused: Array = []
					for c in r["currencies"]:
						var cr: Dictionary = c.duplicate()
						cr["offered"] = false
						refused.append(cr)
					r["currencies"] = refused
				spent.append(r)
			_scene.show_result("She will not move.", _view(spent, 0), "lever_argue_failure")
		13:
			_check_spent()
			_scene.show_close("declined", Words.outcome("declined"))
		15:
			_check_closed()
			_check_blocks()
			_check_titles()
			_check_stance_files()
			_check_files_compile()
			_finish()
			return true
	return false


func _argue() -> Button:
	return _scene.verbs.lever_button("argue")


func _check_open() -> void:
	var labels: Array = []
	for c in _scene.verbs.find_children("*", "Label", true, false):
		labels.append((c as Label).text)
	if not labels.has("35–60 %"):
		_fail("the argue lever's odds are not the range 35–60 %%: %s" % [labels])
	var friendship: Button = _scene.verbs.lever_button("friendship")
	if friendship == null or not friendship.disabled or friendship.tooltip_text != "you are not friends":
		_fail("a lever the sim does not offer is not disabled with its reason")
	if not _scene._fog.text.contains("stranger"):
		_fail("the scene does not say why the odds are wide: %s" % _scene._fog.text)
	if not _scene._traits.text.contains("Vain"):
		_fail("the known traits are not shown: %s" % _scene._traits.text)
	# Content's lines frame the want in a sentence; the placeholder says it bare.
	if not _scene._line.text.contains("the pension age held"):
		_fail("the opening line does not carry the asker's want through the dialogue: '%s'" % _scene._line.text)
	if _scene.visiting != "Cécile Aumont":
		_fail("the hold line's seam does not name the person")
	var flirt: Button = _scene.verbs.topic_button("flirt")
	if flirt == null or not flirt.disabled or flirt.tooltip_text == "":
		_fail("flirting is not listed, refused, with its reason")


## The spends, read before any click.
func _check_spends() -> void:
	var bargain: Button = _scene.verbs.lever_button("bargain")
	var pick: OptionButton = bargain.get_parent().find_child("Currency", false, false) if bargain != null else null
	if pick == null or pick.item_count != 3:
		_fail("bargain has no currency choice of three")
		return
	if pick.selected != 0 or pick.get_item_text(pick.selected) != Words.currency("favour"):
		_fail("the currency shown is not the favour the cost is read from: '%s'" % pick.get_item_text(pick.selected))
	var spend := _spend_of("bargain")
	# R11: the favour's rapport in the word it lands in (a stranger at 0: -0.10 is wary).
	if not spend.contains("rapport turns wary"):
		_fail("the favour's spend is not shown before the click: '%s'" % spend)
	pick.select(1)
	pick.item_selected.emit(1)
	if not _spend_of("bargain").contains("IOU"):
		_fail("choosing a vote trade does not show the IOU it costs: '%s'" % _spend_of("bargain"))
	if not pick.is_item_disabled(2) or pick.get_item_tooltip(2) != "aid is not open yet":
		_fail("aid is not refused with the sim's reason")
	var promise: Button = _scene.verbs.lever_button("promise_date")
	var due: OptionButton = promise.get_parent().find_child("Due", false, false) if promise != null else null
	if due == null or due.item_count != LK.PROMISE_MAX_MONTHS - LK.PROMISE_MIN_MONTHS + 1:
		_fail("the promise has no date choice over the sim's window")
		return
	if not _spend_of("promise_date").contains(Words.when(NOW + 12)) or not _spend_of("promise_date").contains("binds"):
		_fail("the promise's date and that it binds are not shown: '%s'" % _spend_of("promise_date"))


func _spend_of(lever: String) -> String:
	var button: Button = _scene.verbs.lever_button(lever)
	var cell := button.get_parent()
	var grid := cell.get_parent()
	return (grid.get_child(cell.get_index() + 2) as Label).text


func _check_clicks() -> void:
	if _emitted.size() != 1 or _emitted[0][0] != "argue":
		_fail("a held click on Argue emitted %s" % [_emitted])
	_emitted.clear()
	_scene.verbs.lever_button("promise_date").pressed.emit()
	_scene.verbs.lever_button("bargain").pressed.emit()
	_scene.verbs.topic_button("gossip").pressed.emit()
	if _emitted.size() != 3:
		_fail("the verbs did not emit: %s" % [_emitted])
		return
	if int(_emitted[0][1].get("due_month", -1)) != NOW + 12:
		_fail("the promise did not carry its picked date: %s" % [_emitted[0]])
	if String(_emitted[1][1].get("currency", "")) != "vote_trade":
		_fail("the bargain did not carry its picked currency: %s" % [_emitted[1]])
	if String(_emitted[2][1].get("about", "")) != "p_x":
		_fail("the gossip did not carry its third person: %s" % [_emitted[2]])
	_emitted.clear()


func _check_spent() -> void:
	var argue := _argue()
	if argue == null or not argue.disabled or argue.tooltip_text != "no attempts left":
		_fail("attempts spent left Argue live, or without the sim's reason")
	if not _scene.verbs._attempts.text.contains("end the audience"):
		_fail("no attempts left, and the scene does not say to end it: %s" % _scene.verbs._attempts.text)
	if _scene._result.text != "She will not move.":
		_fail("the result is not shown")
	# Every currency refused: the picker still shows the favour its cost is read
	# from, not whichever item the OptionButton fell back to (it showed "Aid").
	var pick: OptionButton = _scene.verbs.lever_button("bargain").get_parent().find_child("Currency", false, false)
	if pick == null or pick.get_item_text(pick.selected) != Words.currency("favour"):
		_fail("a refused bargain's picker does not show the favour: '%s'" % (pick.get_item_text(pick.selected) if pick != null else "none"))


func _check_closed() -> void:
	if _scene._end.text != "Leave" or _scene.verbs.visible:
		_fail("after the sim closed it, the scene does not offer only Leave")
	_scene._end.pressed.emit()
	if _emitted != [["closed"]]:
		_fail("Leave emitted %s, not closed" % [_emitted])


## Which opening and closing a request speaks (dialogue_lines.gd).
func _check_titles() -> void:
	var ns := {"reshuffle_month": 24300}
	var cases := [
		[{"object": "measure:FRA>ALB", "arrived_month": 24301}, "visitor_opening", "visitor_close_declined"],
		[{"object": "office:portfolio:interior", "arrived_month": 24301}, "reshuffle_opening", "close_declined"],
		[{"object": "office:portfolio:interior", "arrived_month": 24305}, "opening", "close_declined"],
		[{"object": "programme:prog_x", "arrived_month": 24301}, "opening", "close_declined"],
	]
	for c in cases:
		if DialogueLines.opening_title(ns, c[0]) != c[1] or DialogueLines.close_title(c[0], "declined") != c[2]:
			_fail("%s opens %s / closes %s, not %s / %s" % [c[0], DialogueLines.opening_title(ns, c[0]), DialogueLines.close_title(c[0], "declined"), c[1], c[2]])


func _check_blocks() -> void:
	var base := DialogueLines.titled_blocks("~ opening\nA: one\n=> END\n~ close_settled\nA: bye\n=> END\n")
	var own := DialogueLines.titled_blocks("~ opening\nA: mine\n=> END\n")
	base.merge(own, true)
	if base.size() != 2 or not String(base["opening"]).contains("mine") or not String(base["close_settled"]).contains("bye"):
		_fail("a stance's title does not replace the default's alone: %s" % [base])


## Every file under data/audiences compiles through the addon (Content's #103
## suggestion, test_summits' shape), and once the default carries more than the
## placeholder's opening it carries every title the scene asks for.
func _check_files_compile() -> void:
	var manager = root.get_node_or_null("/root/DialogueManager")
	if manager == null:
		_fail("no DialogueManager autoload to compile with")
		return
	var titles := ["opening", "close_settled", "close_promised", "close_declined",
		# b3 (Content's #126): the phone, the visitor and the reshuffle ask.
		"phone_opening", "phone_close_settled", "phone_close_promised", "phone_close_unresolved",
		"visitor_opening", "visitor_close_settled", "visitor_close_promised", "visitor_close_declined",
		"reshuffle_opening"]
	for lever in Words.LEVER_LABEL.keys():
		titles.append("lever_%s_success" % lever)
		titles.append("lever_%s_failure" % lever)
	for topic in Words.TOPIC_LABEL.keys():
		titles.append("topic_%s" % topic)
	var dir := DirAccess.open("res://data/audiences")
	for file in dir.get_files():
		if not file.ends_with(".dialogue"):
			continue
		var text := FileAccess.get_file_as_string("res://data/audiences/" + file)
		if manager.create_resource_from_text(text) == null:
			_fail("data/audiences/%s does not compile" % file)
		if file == "default.dialogue":
			var blocks := DialogueLines.titled_blocks(text)
			if blocks.size() > 1:
				for t in titles:
					if not blocks.has(t):
						_fail("default.dialogue lacks the title %s" % t)


## Content's PR ships the stance files (the parent's call): until then only the
## default exists; once any stance file lands, every stance must have one.
func _check_stance_files() -> void:
	var dir := DirAccess.open("res://data/audiences")
	if dir == null or not dir.file_exists("default.dialogue"):
		_fail("data/audiences/default.dialogue is missing")
		return
	var stances: Array = PersonCard.STANCE_LABEL.keys()
	var shipped := 0
	for stance in stances:
		if dir.file_exists("%s.dialogue" % stance):
			shipped += 1
	if shipped > 0 and shipped < stances.size():
		_fail("Content shipped %d of %d stance dialogues; every request stance needs one" % [shipped, stances.size()])


func _press(down: bool) -> void:
	var target := _argue()
	if target == null:
		_fail("no Argue button")
		return
	Click.half(root, target, down)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_audience_scene: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
