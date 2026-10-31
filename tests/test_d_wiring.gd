extends SceneTree

## Headless test: godot --headless --script res://tests/test_d_wiring.gd
## Non-zero exit on any failure.
##
## V5.2d's wiring, over Systems' month report and desk entries:
##   - the Elections step hands report["front_page"] to the card: a real entry shows
##     it, the empty month leaves the card up, neither touches the clock;
##   - a load's rebind puts the previous game's front page away, with no note;
##   - an event desk entry carrying a speaker puts that person's face, name and line
##     on its decision card; one with no speaker (the narrator) adds nothing;
##   - an event with no written line is the narrator even when the entry names a
##     speaker; and the Dispatches desk entry carries the same face as the card.

const DeskCards = preload("res://src/ui/desk_cards.gd")
const Headlines = preload("res://src/ui/headlines.gd")
const Inbox = preload("res://src/ui/inbox.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	# V5.3-0: this test drives months for another surface, not the monthly briefing.
	preload("res://src/ui/briefing_driver.gd").suppressed = true
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check_front_page()
	_check_speaker()
	_check_no_line()
	_check_dispatches_speaker()
	if _failures.is_empty():
		print("PASS tests/test_d_wiring.gd")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: " + f)
		quit(1)
	return true


func _check_front_page() -> void:
	var card = _main._hud.front_page
	var outlets: Array = _main._loader.outlets.get(String(_main._state.player_nation_id), [])
	Headlines.set_table("event", {"e": {"a": {"friendly": "Good news for all", "hostile": "Bad news for all"}}})
	var entry := {"kind": "event", "id": "e", "answer": "a", "severity": 3, "month": 1,
		"papers": [{"outlet": String(outlets[0].id), "tone": "friendly"}, {"outlet": String(outlets[1].id), "tone": "hostile"}],
		"also": []}
	var state = _main._state
	var paused: bool = _main._clock.paused
	_main._on_month_step("Elections", true, {"front_page": entry}, state.year, state.month)
	if not card.visible:
		_failures.append("the Elections step did not show the month's front page")
	_main._on_month_step("Elections", true, {"front_page": {}}, state.year, state.month)
	_main._on_month_step("Elections", true, {}, state.year, state.month)
	if not card.visible:
		_failures.append("a month with no front page put away the card still up")
	if _main._clock.paused != paused:
		_failures.append("a front page moved the clock")
	_main._hud.inbox.clear()
	_main._hud.rebind(state, _main._loader)
	if card.visible or _main._hud.inbox.lane_count(Inbox.NOTES) != 0:
		_failures.append("a load left the previous game's front page up, or noted it")


func _check_speaker() -> void:
	var ev = null
	for candidate in _main._loader.events:
		if String(candidate.speaker_line).strip_edges() != "":
			ev = candidate
			break
	if ev == null:
		_failures.append("fixture: no event carries a speaker_line")
		return
	var ns = _main._state.player()
	var person = _main._loader.people.get(String(ns.id), [])[0]
	var inbox = _main._hud.inbox
	inbox.clear()
	var spoken := {"event_id": String(ev.id), "months_left": 3, "severity": 2, "speaker": String(person.id)}
	DeskCards.push(_main, ev, spoken)
	var face = inbox.find_child("Speaker", true, false)
	if face == null:
		_failures.append("an entry with a speaker has no face on its card")
	else:
		var text := _texts(face)
		if not text.contains(String(person.person_name)) or not text.contains(String(ev.speaker_line).strip_edges()):
			_failures.append("the face does not carry the speaker's name and line: '%s'" % text)
	# The summary under the face is body size, not caption: it carries the deadline.
	for body in inbox.find_children("*", "RichTextLabel", true, false):
		if body.theme_type_variation == UiTheme.RICH_CAPTION and body.get_parsed_text().contains("to answer"):
			_failures.append("the summary under a speaker's face is still caption size")
	inbox.clear()
	DeskCards.push(_main, ev, {"event_id": String(ev.id), "months_left": 3, "severity": 2, "speaker": "nobody_by_this_id"})
	if inbox.find_child("Speaker", true, false) != null:
		_failures.append("a speaker the content does not name got a nameless face")
	inbox.clear()
	DeskCards.push(_main, ev, {"event_id": String(ev.id), "months_left": 3, "severity": 2})
	if inbox.find_child("Speaker", true, false) != null:
		_failures.append("the narrator got a face")
	inbox.clear()


## A face with nothing to say is the narrator: an entry naming a person on an event
## that has no speaker_line gets no face.
## Every shipped event has a line since Content's #191, so one is blanked for the check.
func _check_no_line() -> void:
	var ev = _main._loader.events[0]
	var line := String(ev.speaker_line)
	ev.speaker_line = ""
	var ns = _main._state.player()
	var person = _main._loader.people.get(String(ns.id), [])[0]
	var inbox = _main._hud.inbox
	inbox.clear()
	DeskCards.push(_main, ev, {"event_id": String(ev.id), "months_left": 3, "severity": 2, "speaker": String(person.id)})
	if inbox.find_child("Speaker", true, false) != null:
		_failures.append("an event with no written line got a face from its entry's speaker")
	inbox.clear()
	ev.speaker_line = line


## The Dispatches desk entry shows who brings the news, as the card does.
func _check_dispatches_speaker() -> void:
	var ev = null
	for candidate in _main._loader.events:
		if String(candidate.speaker_line).strip_edges() != "":
			ev = candidate
			break
	if ev == null:
		return  # _check_speaker already failed on the fixture
	var ns = _main._state.player()
	var person = _main._loader.people.get(String(ns.id), [])[0]
	var queue: Array = ns.event_queue.duplicate(true)
	ns.event_queue.clear()
	ns.event_queue.append({"event_id": String(ev.id), "months_left": 3, "severity": 2, "speaker": String(person.id)})
	var panel = _main._events_panel
	panel._refresh()
	var face = panel.find_child("Speaker", true, false)
	if face == null:
		_failures.append("the Dispatches desk entry has no speaker's face")
	elif not _texts(face).contains(String(person.person_name)):
		_failures.append("the Dispatches face does not name the speaker: '%s'" % _texts(face))
	ns.event_queue.clear()
	ns.event_queue.append_array(queue)
	panel._refresh()


func _texts(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for child in node.get_children():
		out += _texts(child)
	return out
