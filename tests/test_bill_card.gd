extends SceneTree

## Headless test: godot --headless --script res://tests/test_bill_card.gd
## Non-zero exit on any failure.
##
## V5.2 b+ R2 (docs/design/v5.2-bplus-spec.md, "votes made visible"; the author:
## "i dont see when a vote is proposed, accepted, rejected"). The sim tables a bill
## at the press and divides it at the month's close (Systems, #173); its ONE card
## says "Tabled" at once and carries the division in place:
##   - the verdict as a word (Carried / Defeated), the division's yes, no and
##     abstain seats exactly as resolve_vote() counted them, and who broke ranks,
##     by party name;
##   - a bill adopted under Article 49.3 says it was adopted without a vote and
##     how the censure that follows went -- never "Yes 0, No 0";
##   - a real proposal gives exactly one card, a note (never a hold), whose
##     counts are the division's.

const ProposalNote = preload("res://src/ui/proposal_note.gd")
const Strings = preload("res://src/ui/strings.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const DiaryDriver = preload("res://src/ui/diary_driver.gd")
const Division = preload("res://src/sim/division.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_check_bodies()
		_check_one_card()
		_check_booked_bill()
		_check_struck()
		_check_division_sting()
		_check_referendum_sting()
		_finish()
		return true
	return false


func _check_bodies() -> void:
	var parties: Array = _main._loader.parties[String(_main._state.player().id)]
	var a := String(parties[0].id)
	var carried := ProposalNote.body({"passed": true, "yes_seats": 312, "no_seats": 259, "abstain_seats": 6,
		"party_rebels": {a: 7}}, parties)
	if not carried.begins_with("Carried") or not carried.contains("312 for") or not carried.contains("259 against") \
			or not carried.contains("6 abstaining") or not carried.contains(String(parties[0].party_name)) or not carried.contains("7"):
		_fail("a carried bill reads '%s'" % carried)
	var defeated := ProposalNote.body({"passed": false, "yes_seats": 100, "no_seats": 400, "abstain_seats": 77, "party_rebels": {}}, parties)
	if not defeated.begins_with("Defeated") or not defeated.contains("77 abstaining") or defeated.contains("broke ranks"):
		_fail("a defeated bill reads '%s'" % defeated)
	var forced := ProposalNote.body({"passed": true, "forced": true, "yes_seats": 0, "no_seats": 0,
		"censure": {"carried": false, "for_seats": 250, "threshold": 289}}, parties)
	if not forced.contains("without a vote") or forced.contains("Yes 0") or not forced.contains("250"):
		_fail("a bill adopted under 49.3 reads '%s'" % forced)


## A real proposal: one card, a note, the division's own counts.
func _check_one_card() -> void:
	var inbox = _main._hud.inbox
	var law = null
	for l in _main._loader.laws:
		if String(l.majority) == "simple":
			law = l
			break
	if law == null:
		_fail("premise: no simple-majority law")
		return
	var name: String = Strings.law_name(law)
	var before := _titled(inbox, name).size()
	_main._law_panel.run_proposal(law)
	var tabled := _titled(inbox, name)
	if tabled.size() != before + 1:
		_fail("one tabling gave %d cards titled '%s'" % [tabled.size() - before, name])
		return
	_divide()
	# The division sets its verdict on the tabling's card, in place: still one card.
	var cards := _titled(inbox, name)
	if cards.size() != before + 1:
		_fail("the division gave %d cards titled '%s', not the tabling's one" % [cards.size() - before, name])
		return
	var card: Control = null
	for c in cards:
		if tabled.has(c):
			card = c
	if card == null:
		_fail("the tabling's card titled '%s' is gone after the division" % name)
		return
	var result: Dictionary = _main._state.player().last_law_result
	# #222 QA TAKE C (M19): the verdict set in place carries its tone's tag.
	if not inbox.has_tag(inbox._id_of(card)):
		_fail("the tabling's card took the division's verdict with no tone tag")
	if inbox.lane_of(inbox._id_of(card)) != inbox.NOTES:
		_fail("the bill's card is not a note: lane %s" % inbox.lane_of(inbox._id_of(card)))
	var text := ""
	for label in card.find_children("*", "Label", true, false):
		text += (label as Label).text + "\n"
	for rt in card.find_children("*", "RichTextLabel", true, false):
		text += (rt as RichTextLabel).get_parsed_text() + "\n"
	if not bool(result.get("referendum_route", false)) and not bool(result.get("refused", false)):
		for key in ["yes_seats", "no_seats"]:
			if not text.contains(str(int(result[key]))):
				_fail("the card does not carry the division's %s (%d): %s" % [key, int(result[key]), text])


## A bill booked in the Diary divides on its day: the day's card carries the
## verdict and the counts too, not "as booked" alone.
func _check_booked_bill() -> void:
	var state = _main._state
	var law = null
	for l in _main._loader.laws:
		if String(l.majority) == "simple" and String(l.id) != String(state.player().last_law_result.get("law_id", "")):
			law = l
			break
	var total: int = int(state.year) * 12 + int(state.month)
	var entry := Calendar.make_entry(CalendarK.KIND_LAW, total / 12, total % 12 + 1, 20, "", "", String(law.id))
	state.appointments.append(entry)
	var outcomes: Array = []
	DiaryDriver.resolve(state, _main._loader, int(entry["year"]), int(entry["month"]), 20, func(o: Dictionary) -> void: outcomes.append(o))
	if outcomes.size() != 1:
		_fail("the booked bill was not tabled on its day")
		return
	var text: String = _main._world_news.appointment_text(entry, String(outcomes[0]["label"]), bool(outcomes[0]["ok"]), String(outcomes[0]["reason"]))
	if not text.contains("Tabled"):
		_fail("the booked bill's day card does not say it was tabled: '%s'" % text)
	_divide()
	var result: Dictionary = state.player().last_law_result
	var division := ProposalNote.body(result, _main._loader.parties[String(state.player().id)])
	if not bool(result.get("held_by_upper", false)) and not division.contains("%d for" % int(result["yes_seats"])):
		_fail("the booked bill's division carries no counts: '%s'" % division)
	# Its card is titled as a vote, not "Kept:" over a defeat (review pass 1).
	_main._world_news.card_appointment(entry, String(outcomes[0]["label"]), bool(outcomes[0]["ok"]), String(outcomes[0]["reason"]))
	if _titled(_main._hud.inbox, "Vote: %s" % String(outcomes[0]["label"])).is_empty():
		_fail("the booked bill's card is not titled as its vote")


## QA's TAKE on #158: a bill the assembly carries and the court strikes down
## (legislature.gd: passed false, struck_down true) is not "Defeated", and under
## 49.3 it does not "stand". farm_standards_act strikes on a new France game.
func _check_struck() -> void:
	var forced := ProposalNote.body({"passed": false, "forced": true, "struck_down": true,
		"censure": {"carried": false, "for_seats": 259, "threshold": 289}}, [])
	if forced.contains("the bill stands") or not forced.contains("court"):
		_fail("a forced bill the court struck reads '%s'" % forced)
	var law = null
	for l in _main._loader.laws:
		if String(l.id) == "farm_standards_act":
			law = l
	if law == null:
		_fail("premise: no farm_standards_act")
		return
	_main._law_panel.run_proposal(law)
	_divide()
	var result: Dictionary = _main._state.player().last_law_result
	if not bool(result.get("struck_down", false)):
		_fail("premise: farm_standards_act was not struck down (%s)" % [result.keys()])
		return
	var text := ProposalNote.body(result, _main._loader.parties[String(_main._state.player().id)])
	if text.begins_with("Defeated") or not text.begins_with("Carried") or not text.contains("court"):
		_fail("a bill the court struck reads '%s'" % text)


## The inbox cards whose title reads `title`.
func _titled(inbox, title: String) -> Array:
	var out: Array = []
	for label in inbox.find_children("*", "Label", true, false):
		if (label as Label).text.to_upper() == title.to_upper():
			var node: Node = label
			while node != null and not node is PanelContainer:
				node = node.get_parent()
			if node != null and not out.has(node):
				out.append(node)
	return out

## V5.2 b+ R2: the tabled bill divides at the month's close -- through main's own
## Division hook, so the division's card is the one the game pushes.
## #223 pass 1: the division is where a vote's sting plays -- a defeat's is
## synthesized (a passed bill's waits for a recorded file, silent until then).
func _check_division_sting() -> void:
	var before: int = _main.find_children("*", "AudioStreamPlayer", false, false).size()
	ProposalNote.card_division(_main, {"division": {"law_id": "x", "passed": false, "yes_seats": 100, "no_seats": 400}})
	var placed: int = _main.find_children("*", "AudioStreamPlayer", false, false).size() - before
	if placed != 1:
		_fail("a defeated division placed %d sting players, expected 1" % placed)



## #223 pass 2: a referendum's own result is where it is won or lost -- a card and
## the vote's sting at the Legislature step, through main's own hook; the division
## that put it to the country plays nothing, nor does a withdrawal or a vote still
## in flight.
func _check_referendum_sting() -> void:
	var ns = _main._state.player()
	var inbox = _main._hud.inbox
	var players := func() -> int: return _main.find_children("*", "AudioStreamPlayer", false, false).size()
	var before: int = players.call()
	ns.referendum_pending = {"law_id": "x"}
	ProposalNote.card_division(_main, {"division": {"law_id": "x", "passed": true, "referendum_called": true}})
	if players.call() != before:
		_fail("the division that put a bill to the country played a sting")
	# A carried vote's sting waits for a recorded file (silent until then); a refused
	# one plays its synthesized stand-in.
	for c in [[true, "Carried by the country", 0], [false, "Refused by the country", 1]]:
		ns.referendum_pending = {"law_id": "x"}
		_main._on_month_step("Legislature", false, {}, _main._state.year, _main._state.month)
		_main._on_month_step("Legislature", true, {}, _main._state.year, _main._state.month)
		if players.call() != before:
			_fail("a referendum still in flight played a sting")
		ns.referendum_pending = {}
		ns.last_referendum_result = {"law_id": "x", "passed": c[0], "yes_share": 0.55 if c[0] else 0.4, "withdrawn": false}
		_main._on_month_step("Legislature", true, {}, _main._state.year, _main._state.month)
		if players.call() != before + c[2]:
			_fail("a referendum %s placed %d sting players, expected %d" % [c[1], players.call() - before, c[2]])
		if not _inbox_says(inbox, c[1]):
			_fail("a referendum's result left no '%s' card" % c[1])
		before = players.call()
	# Withdrawn on the panel before the step: the snapshot is empty, nothing plays.
	ns.referendum_pending = {}
	ns.last_referendum_result = {"law_id": "x", "passed": false, "yes_share": 0.0, "withdrawn": true}
	_main._on_month_step("Legislature", false, {}, _main._state.year, _main._state.month)
	_main._on_month_step("Legislature", true, {}, _main._state.year, _main._state.month)
	if players.call() != before:
		_fail("a withdrawn referendum played a sting")
	ns.last_referendum_result = {}


func _inbox_says(inbox, words: String) -> bool:
	for node in inbox.find_children("*", "", true, false):
		if (node is Label or node is RichTextLabel) and String(node.text).contains(words):
			return true
	return false


func _divide() -> void:
	var report := {"division": Division.divide(_main._state, _main._loader)}
	_main._on_month_step("Division", true, report, _main._state.year, _main._state.month)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_bill_card: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
