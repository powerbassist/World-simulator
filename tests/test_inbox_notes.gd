extends SceneTree

## Headless test: godot --headless --script res://tests/test_inbox_notes.gd
## Non-zero exit on any failure.
##
## V5.2 b+ (R13 and R12, gate b: "too much clutter in the notes"; "the game is too
## verbose sometimes, explanation that should be tied into a bubble or something";
## QA's six identical LEAK notes). The NOTES lane:
##   - groups IDENTICAL notes: six of them are one card, its count in the title;
##     a new body under the same title is its own card (a tally, a default, a
##     second person's leak each say something new); a decision is never grouped;
##   - folds a LONG note to the whole sentences that fit, its rest behind More: a
##     real click (press and release frames apart) opens it in place, a second
##     folds it back; a short note (a division, a tally) is never folded;
##   - never hides a glossary mark behind the fold.
## V5.3-0 (b), spec 3.3-3.4: the lapses of the requests are ONE note that counts and
## names them, and the first-use hint leaves once a plate was read and has closed.

const Inbox = preload("res://src/ui/inbox.gd")

const GlossaryHint = preload("res://src/ui/glossary_hint.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _inbox
var _long := ""
var _target: Button

const LONG := "Grievance stands at 40 of 100 after the strike in the north. Output will carry it for months, and the unions say they will be back. The ministry expects the next round before the summer recess."


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_inbox = _main._hud.inbox
			_inbox.clear()
			_check_grouping()
			_long = _inbox.push("Dispatch", LONG)
		4:
			_check_folded()
			_target = _more(_long)
			_press(true)
		7:
			_press(false)
		9:
			if not _body_text(_long).contains("before the summer recess."):
				_fail("More did not open the note: '%s'" % _body_text(_long))
			if _more(_long) == null or _more(_long).text != "Less":
				_fail("an open note does not offer Less")
			_press(true)
		12:
			_press(false)
		14:
			if _body_text(_long).contains("summer recess"):
				_fail("Less did not fold the note back")
			_check_marks_whole()
			_check_hint_whole()
			_check_lapses_grouped()
			_check_hint_retires()
			_finish()
			return true
	return false


func _check_grouping() -> void:
	var first: String = _inbox.push("A leak", "Apolline Delcour briefs against the government.")
	for i in 5:
		var again: String = _inbox.push("A leak", "Apolline Delcour briefs against the government.")
		if again != first:
			_fail("an identical note was pushed as a new card (%s, not %s)" % [again, first])
	if _inbox.lane_count(Inbox.NOTES) != 1:
		_fail("six identical notes are %d cards, not one" % _inbox.lane_count(Inbox.NOTES))
	if not _title_text(first).contains("6"):
		_fail("the grouped note's title does not count six: '%s'" % _title_text(first))
	_inbox.push("A leak", "Gilles Aubertin briefs against the government.")
	if _inbox.lane_count(Inbox.NOTES) != 2:
		_fail("a second person's leak joined the first's card")
	_inbox.push("A resignation", "Someone resigns.")
	if _inbox.lane_count(Inbox.NOTES) != 3:
		_fail("a note under another title joined a group")
	var d1: String = _inbox.push("A question", "Answer it.", [{"label": "Yes"}])
	var d2: String = _inbox.push("A question", "Answer it.", [{"label": "Yes"}])
	if d1 == d2 or _inbox.lane_count(Inbox.DECISIONS) != 2:
		_fail("two decisions under one title were grouped")
	_inbox.clear()


func _check_folded() -> void:
	var shown := _body_text(_long)
	if not shown.begins_with("Grievance stands at 40 of 100") or shown.contains("summer recess") or not shown.contains("…"):
		_fail("a long note shows '%s', not its first sentences and the fold mark" % shown)
	if _more(_long) == null or not _more(_long).visible:
		_fail("a folded note has no More")
	var short: String = _inbox.push("Workplace Safety Act", "Failed. Yes 210 · No 289 · Abstain 78, of 577 seats.")
	if (_more(short) != null and _more(short).visible) or not _body_text(short).contains("Yes 210"):
		_fail("a short note (a division) was folded: '%s'" % _body_text(short))


func _check_marks_whole() -> void:
	var marked: String = _inbox.push("Marked", LONG + " Your [g=approval]approval[/g] moved.")
	if not _body_text(marked).contains("approval moved"):
		_fail("the fold hid a glossary mark: '%s'" % _body_text(marked))


## QA's #141 RECORD: the first-use hint is an instruction, not news -- its second
## sentence ("Click it to keep the note open ...") is the half the player needs,
## and the fold hid it behind More. The hint keeps its whole body.
func _check_hint_whole() -> void:
	GlossaryHint.config_path = "user://test_inbox_notes_hint.cfg"
	GlossaryHint.reset()
	GlossaryHint.offer(_inbox)
	var id := String(GlossaryHint._card)
	if not _body_text(id).contains("Click it to keep") or (_more(id) != null and _more(id).visible):
		_fail("the first-use hint is folded: '%s'" % _body_text(id))
	GlossaryHint.reset()


func _check_lapses_grouped() -> void:
	_inbox.clear()
	var game := {}
	for person in ["Clarisse Turcy", "Loïc Périer", "Diane Ollivier"]:
		AudienceDriver._note_lapse(_main, game, person)
	if _inbox.lane_count(Inbox.NOTES) != 1:
		_fail("three lapses are %d notes, not one" % _inbox.lane_count(Inbox.NOTES))
	var id := String(game.get("lapse_note", ""))
	var body := _body_text(id)
	if not body.begins_with("3 requests lapsed") or not body.contains("Diane Ollivier") or not body.contains("Clarisse Turcy"):
		_fail("the grouped lapse note does not count and name them: '%s'" % body)
	_inbox.dismiss(id)
	AudienceDriver._note_lapse(_main, game, "Gaspard Zuber")
	var next := String(game["lapse_note"])
	if next == id or not _body_text(next).begins_with("Gaspard Zuber's request lapsed"):
		_fail("a lapse after the note was dismissed did not start a new one: '%s'" % _body_text(next))


func _check_hint_retires() -> void:
	GlossaryHint.config_path = "user://test_inbox_notes_hint.cfg"
	GlossaryHint.reset()
	GlossaryHint.offer(_inbox)
	var id := String(GlossaryHint._card)
	GlossaryHint.retire()
	if _inbox.lane_of(id) == "":
		_fail("the hint left before any plate was read")
	GlossaryHint.term_read = true
	GlossaryHint.retire()
	if _inbox.lane_of(id) != "":
		_fail("the hint stayed after a plate was read and closed")
	GlossaryHint.reset()


func _card(id: String) -> Control:
	return _inbox._cards.get(id)


func _more(id: String) -> Button:
	var card := _card(id)
	return card.find_child("More", true, false) as Button if card != null else null


func _title_text(id: String) -> String:
	var card := _card(id)
	for label in card.find_children("*", "Label", true, false):
		if (label as Label).theme_type_variation == "Heading":
			return (label as Label).text
	return ""


func _body_text(id: String) -> String:
	var body = _inbox._bodies.get(id)
	return (body as RichTextLabel).get_parsed_text() if body is RichTextLabel else String(body.text) if body != null else ""


func _press(down: bool) -> void:
	if _target == null or not _target.is_visible_in_tree():
		_fail("no More button on screen to click")
		return
	Click.half(_main.get_viewport(), _target, down)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_inbox_notes: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
