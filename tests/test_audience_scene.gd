extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_scene.gd
## Non-zero exit on any failure.
##
## V5.3, the audience scene (C4 and C4-talk) on views the sim would hand it, no sim behind:
##   - the three cards' buttons are 180 px wide and their tops sit on one line; the Counter's
##     field is ABOVE its button;
##   - H3: a date picked survives a Counter she did not take, and the face picked in a gossip
##     survives the redraw after the line is asked; an asked line stays, tagged Asked;
##   - the deal struck gives way to the talk; Refuse gives way to the refusal and NO talk, and the
##     way out ends the scene; the talk's way out ends it in one press;
##   - the person's opening and the talk's lines come through DialogueManager from
##     data/audiences/default.dialogue; a stance's file replaces the default title by title.

const AudienceFlow = preload("res://src/ui/audience_flow.gd")
const AudienceScene = preload("res://src/ui/audience_scene.gd")
const DialogueLines = preload("res://src/ui/dialogue_lines.gd")
const Words = preload("res://src/ui/lever_words.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const TalkMenu = preload("res://src/ui/talk_menu.gd")

const S = AudienceFlow.S
const APRIL_2027 := 2027 * 12 + 4

var _failures: Array[String] = []
var _scene
var _other
var _frame := 0
var _emitted := []
var _other_emitted := []


func _init() -> void:
	_scene = _make(_emitted)
	_other = _make(_other_emitted)


func _make(log: Array):
	var scene = AudienceScene.new()
	scene.size = Vector2(1160, 630)
	root.add_child(scene)
	scene.countered.connect(func(date: Dictionary) -> void: log.append(["countered", date]))
	scene.asked.connect(func(id: String, topic: String, args: Dictionary) -> void: log.append(["asked", id, topic, args]))
	scene.ended.connect(func() -> void: log.append(["ended"]))
	scene.closed.connect(func() -> void: log.append(["closed"]))
	scene.granted.connect(func() -> void: log.append(["granted"]))
	return scene


func _card(micro: String, title: String, ok: bool, lines := []) -> Dictionary:
	return {"micro": micro, "title": title, "lines": lines, "ok": ok, "why": "" if ok else "No."}


func _view(struck: bool) -> Dictionary:
	var counter := _card("Counter", "The same word, later", true, [{"glyph": "%", "tone": "", "text": "0–36 % they agree"}, {"glyph": "=", "tone": "", "text": "The same terms, judged on 01 APR 2027", "live": true}])
	counter["earliest"] = 2027 * 12 + 1
	counter["latest"] = 2027 * 12 + 12
	return {"request_id": "req_1", "person_id": "", "name": "Cécile Aumont", "ask": "the pension age held",
		"stance": "defend", "president": "Daniel Moucron", "choices": {"feel": {}}, "struck": struck,
		"question": {"lead": "Your word on it.", "grant": _card("Grant", "Give your word", true, [{"glyph": "▲", "tone": "good", "text": "A silence."}]),
			"counter": counter, "refuse": _card("Refuse", "Say no", true, [{"glyph": "▼", "tone": "bad", "text": "She will be annoyed."}])},
		"counter_default": {"year": 2027, "month": 4, "day": 5}, "talk_blocked": {},
		"struck_lines": [{"glyph": "▲", "tone": "good", "text": "A silence of twelve months."}],
		"refused_lines": [{"glyph": "▼", "tone": "bad", "text": "They are annoyed."}],
		"talk": [
			{"id": "gossip", "topic": "gossip", "tag": "learn", "args": {"about": "p_a"}, "vars": {}, "plain": "Gossip",
				"people": [{"id": "p_a", "name": "Paul Ixe", "tip": "Of the same party."}, {"id": "p_b", "name": "Léa Oux", "tip": "Wants the same."}]},
			{"id": "family", "topic": "family", "tag": "warm", "args": {}, "people": [], "vars": {}, "plain": "Family"}]}


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_scene.open(_view(false))
			_other.open(_view(false))
		5:
			_check_cards()
			_check_the_grid()
			_check_the_judged_line_follows_the_picked_month()
			_check_the_date_survives_a_counter_she_did_not_take()
		8:
			_check_the_deal_gives_way_to_the_talk()
		14:
			_check_the_talk_and_the_face_picked()
		18:
			_check_the_picked_face_survives()
			_check_refuse_leaves_no_talk()
		22:
			_check_the_talks_way_out()
			_check_titles()
			_check_blocks()
			_check_files_compile()
			_check_stance_files()
			_finish()
			return true
	return false


func _button(scene, name: String) -> Button:
	return scene.find_child(name, true, false) as Button


func _check_cards() -> void:
	var tops := []
	for name in ["GrantButton", "CounterButton", "RefuseButton"]:
		var b := _button(_scene, name)
		if b == null:
			_fail("the question has no %s" % name)
			return
		if int(b.size.x) != 180:
			_fail("%s is %d px wide, not 180" % [name, int(b.size.x)])
		tops.append(int(b.global_position.y))
	if tops[0] != tops[1] or tops[1] != tops[2]:
		_fail("the three buttons' tops are not on one line: %s" % [tops])
	var field = _scene.cards.date_pick
	if field == null or field.global_position.y >= _button(_scene, "CounterButton").global_position.y:
		_fail("the Counter's date field is not above its button")
	if field != null and field.text != "Mon 05/04/2027":
		_fail("the field opens on '%s', not the row's default day" % field.text)


## The grid's Monday-first lead (1 April 2027 is a Thursday: three blanks), and paging that stops at the window.
func _check_the_grid() -> void:
	var field = _scene.cards.date_pick
	field._show(APRIL_2027)
	var cells: Array = field._grid.get_children()
	if cells.size() < 11 or cells[10].name != "Day1":
		_fail("1 April 2027 is not under Thursday: cell 10 is %s" % [cells[10].name if cells.size() > 10 else "missing"])
	field._show(field._first - 5)
	if field._shown != field._first or not field._back.disabled:
		_fail("paging back passed the window's first month")
	field._show(field._last + 5)
	if field._shown != field._last or not field._forward.disabled:
		_fail("paging forward passed the window's last month")
	field._show(APRIL_2027)


## The Counter's "judged on" line follows the date field's MONTH (a word is judged on day 1 of its
## month; the day picked is for the diary only), live, without the cards being rebuilt.
func _check_the_judged_line_follows_the_picked_month() -> void:
	var label: Label = _scene.cards.find_child("JudgedLine", true, false) as Label
	if label == null:
		_fail("the Counter has no live 'judged on' line")
		return
	_scene.cards.date_pick.choose(16, 2027 * 12 + 10)
	if not label.text.contains("01 OCT 2027") or label.text.contains("16"):
		_fail("the Counter's line does not follow the picked month's first day: '%s'" % label.text)
	_scene.cards.date_pick.choose(3, 2027 * 12 + 10)
	if not label.text.contains("01 OCT 2027"):
		_fail("the Counter's line moved with the day: '%s'" % label.text)
	_scene.cards.date_pick.choose(16, APRIL_2027)


func _check_the_date_survives_a_counter_she_did_not_take() -> void:
	_scene.cards.date_pick.choose(16, APRIL_2027)
	if _scene.flow.date.get("day", 0) != 16 or _scene.cards.date_pick.text != "Fri 16/04/2027":
		_fail("a day picked is not what the field says: %s" % [_scene.cards.date_pick.text])
	_button(_scene, "CounterButton").pressed.emit()
	if _emitted.back() != ["countered", {"year": 2027, "month": 4, "day": 16}]:
		_fail("Counter did not send the date picked: %s" % [_emitted.back()])
	_scene.show_result("They are not moved.", _view(false), "lever_promise_date_failure", {}, ResultTone.BAD)
	if _scene.flow.state != S.QUESTION or _scene.cards.date_pick.text != "Fri 16/04/2027":
		_fail("a Counter she did not take reset the question: %s, '%s'" % [_scene.flow.name_of(_scene.flow.state), _scene.cards.date_pick.text])
	if _button(_scene, "GrantButton") == null or _button(_scene, "RefuseButton") == null:
		_fail("Grant and Refuse did not stay open after a refused Counter")


func _check_the_deal_gives_way_to_the_talk() -> void:
	_scene.show_result("The deal is struck.", _view(true), "deal_grant", {}, ResultTone.GOOD)
	if _scene.flow.state != S.GRANTED or _scene.cards.visible or not _scene.talk.visible:
		_fail("a struck deal did not open the talk: %s" % _scene.flow.name_of(_scene.flow.state))
	if _scene._end.text != "That will be all":
		_fail("the talk's way out reads '%s'" % _scene._end.text)


func _check_the_talk_and_the_face_picked() -> void:
	for id in ["gossip", "family"]:
		if _scene.talk.find_child("Line_" + id, true, false) == null:
			_fail("the talk has no line %s" % id)
	var chip := _button(_scene, "Chip_p_b")
	if chip == null:
		_fail("no face chip for the second person")
		return
	chip.pressed.emit()
	if _emitted.back() != ["asked", "gossip", "gossip", {"about": "p_b"}]:
		_fail("a face chip did not ask the line about that person: %s" % [_emitted.back()])
	_scene.show_result("What changed: you learn.", _view(true), "talk_gossip_yes", {"third": "Léa Oux"}, ResultTone.GOOD)
	if _scene.flow.state != S.ANSWERED or not _scene.flow.asked.has("gossip"):
		_fail("an answered line did not move the flow to ANSWERED")


func _check_the_picked_face_survives() -> void:
	var chip := _button(_scene, "Chip_p_b")
	if chip == null or not chip.button_pressed or not chip.disabled:
		_fail("the face picked did not survive the redraw (pressed and spent)")
	var other := _button(_scene, "Chip_p_a")
	if other == null or other.button_pressed:
		_fail("the face NOT picked reads as picked")
	var family: Node = _scene.talk.find_child("Line_family", true, false)
	if family == null or _first_button(family).disabled:
		_fail("a line not asked was closed by another's answer")
	var tags := PackedStringArray()
	for label in _scene.talk.find_children("*", "Label", true, false):
		tags.append((label as Label).text)
	if not " ".join(tags).contains("Asked"):
		_fail("the asked line is not tagged Asked: %s" % [tags])


func _first_button(node: Node) -> Button:
	return node.find_children("*", "Button", true, false)[0] as Button


## Refuse is an end: her parting line, what it cost, the way out, and no talk.
func _check_refuse_leaves_no_talk() -> void:
	_button(_other, "RefuseButton").pressed.emit()
	if _other_emitted.back() != ["ended"]:
		_fail("Refuse did not ask the sim to close: %s" % [_other_emitted.back()])
	_other.show_close("declined", "They leave.", ResultTone.BAD)
	if _other.flow.state != S.REFUSED or _other.talk.visible or _other.cards.visible:
		_fail("a refusal did not show only its own band: %s" % _other.flow.name_of(_other.flow.state))
	if _other.flow.fire("ask"):
		_fail("the flow let a line be asked after Refuse")
	if _other._end.text != "End the audience":
		_fail("the refusal's way out reads '%s'" % _other._end.text)
	_other._end.pressed.emit()
	if _other_emitted.back() != ["closed"] or _other.flow.state != S.ENDED:
		_fail("the refusal's way out did not end the scene")


func _check_the_talks_way_out() -> void:
	_scene._end.pressed.emit()
	if _emitted.back() != ["ended"]:
		_fail("That will be all did not close the audience in the sim: %s" % [_emitted.back()])
	_scene.show_close("promised", "It is settled.", ResultTone.GOOD)
	if _emitted.back() != ["closed"] or _scene.flow.state != S.ENDED:
		_fail("the talk's way out needed a second press")


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
	for line in TalkMenu.table()["lines"]:
		for suffix in ["", "_yes", "_no"]:
			titles.append("talk_%s%s" % [line["id"], suffix])
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
