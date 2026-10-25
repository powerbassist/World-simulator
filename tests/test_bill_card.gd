extends SceneTree

## Headless test: godot --headless --script res://tests/test_bill_card.gd
## Non-zero exit on any failure.
##
## V5.2 b+ R2 (docs/design/v5.2-bplus-spec.md, "votes made visible"; the author:
## "i dont see when a vote is proposed, accepted, rejected"). Until the sim tables
## bills (Systems, after c1) a player's bill divides the moment it is proposed, so
## its one card says so at once:
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
	var cards := _titled(inbox, name)
	if cards.size() != before + 1:
		_fail("one proposal gave %d cards titled '%s'" % [cards.size() - before, name])
		return
	var result: Dictionary = _main._state.player().last_law_result
	var card: Control = cards[-1]
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
		_fail("the booked bill did not divide on its day")
		return
	var result: Dictionary = state.player().last_law_result
	var text: String = _main._world_news.appointment_text(entry, String(outcomes[0]["label"]), bool(outcomes[0]["ok"]), String(outcomes[0]["reason"]))
	if not bool(result.get("held_by_upper", false)) and not text.contains("%d for" % int(result["yes_seats"])):
		_fail("the booked bill's card carries no division: '%s'" % text)
	# Its card is titled as a vote, not "Kept:" over a defeat (review pass 1).
	_main._world_news.card_appointment(entry, String(outcomes[0]["label"]), bool(outcomes[0]["ok"]), String(outcomes[0]["reason"]))
	if _titled(_main._hud.inbox, "Vote: %s" % String(outcomes[0]["label"])).is_empty():
		_fail("the booked bill's card is not titled as its vote")


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
