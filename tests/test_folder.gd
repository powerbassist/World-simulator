extends SceneTree

## Headless test: godot --headless --script res://tests/test_folder.gd
## Non-zero exit on any failure.
##
## Rework 2 S2 (G2): the Folder tab -- Dispatches renamed and rebuilt on file_view.gd -- with
## the chief's SCENE plate retired. What can fail silently, pinned before the build:
##   - THE THREE GROUPS. "To answer" is every file of the inbox AND every desk entry with no card
##     (popup off, or the card's X): Dispatches was the only place those were answered. "Decided"
##     is the ledger whole, the clock's answers included. "News" is the inbox's notes.
##   - THE CLOCK. The tab never pauses: an answer given on it, an event's, a desk entry's with no
##     card, a request's Decline, leaves a running clock running.
##   - A file gone while shown never leaves its page; the selection moves on.
##   - The read (the chief's mark) opens the Presidency page and leaves the clock running; a Go on
##     a file's priority opens the Folder on that file.
##   - The inbox keeps Decisions and Requests; the notes become one line, "News: N", which opens the
##     news group. N moves the day a note lands: a note grouped with its twin and a note past the
##     lane's cap move it too.

const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const DeskCards = preload("res://src/ui/desk_cards.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const RequestLane = preload("res://src/ui/request_lane.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")
const Inbox = preload("res://src/ui/inbox.gd")
const Events = preload("res://src/sim/events.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check_no_scene_plate()
	_check_the_groups()
	_check_an_answer_keeps_the_clock()
	_check_a_desk_entry_with_no_card()
	_check_a_request_on_the_tab()
	_check_a_file_gone_while_shown()
	_check_read_opens_the_page()
	_check_go_opens_the_file()
	_check_the_news_line()
	_check_the_inbox_stays_while_a_request_waits()
	_finish()
	return true


func _panel():
	return _main._events_panel


func _clear_desk() -> void:
	var ns = _main._state.player()
	ns.event_queue.clear()
	ns.audience_requests.clear()
	_main._hud.inbox.clear()
	_main._event_cards.clear()
	_main._unseen_events.clear()
	_main._paused_for_decision = false
	_main._paused_for_programme = false


func _open_tab() -> void:
	_main._windows.open("events")
	_panel()._refresh()


## A desk entry for the content's event `n`, with its inbox card unless `card` is false.
func _event(n := 0, card := true, months := 3) -> String:
	var ns = _main._state.player()
	var ev = _main._loader.events[n]
	var entry := {"event_id": String(ev.id), "event_name": ev.event_name, "months_left": months, "severity": 1,
		"category": ev.category, "interrupt": false}
	ns.event_queue.append(entry)
	if not card:
		return String(ev.id)
	DeskCards.push(_main, ev, entry)
	for id in _main._event_cards:
		if String(_main._event_cards[id]) == String(ev.id):
			return String(id)
	return ""


func _request() -> String:
	var ns = _main._state.player()
	var now := int(_main._state.year) * 12 + int(_main._state.month)
	var person: String = ""
	for p in _main._loader.people[String(ns.id)]:
		if String(p.kind) == "politician" and String(p.id) != preload("res://src/sim/president.gd").leader_id(ns):
			person = String(p.id)
			break
	var id := "%s|%d" % [person, now]
	ns.audience_requests.append({"id": id, "person_id": person, "object": "programme:none", "stance": "sponsor",
		"arrived_month": now - 1, "deadline_month": now + 2, "status": "pending", "date": {}, "resolved_month": -1})
	AudienceDriver.refresh(_main)
	return String(AudienceDriver.lane_of(_main).card_of(id))


## G2: the chief's scene plate is gone, not hidden: nothing of it is left to hold the clock.
func _check_no_scene_plate() -> void:
	if FileAccess.file_exists("res://src/ui/chief_briefing.gd") or FileAccess.file_exists("res://src/ui/folder_driver.gd"):
		_fail("the chief's plate (chief_briefing.gd / folder_driver.gd) still ships")
	var driver := FileAccess.get_file_as_string("res://src/ui/briefing_driver.gd")
	if driver.contains("func card_of(") or driver.contains("func showing("):
		_fail("BriefingDriver still hands out a plate")


func _check_the_groups() -> void:
	_clear_desk()
	var carded := _event(0)
	var bare := _event(1, false)
	var asked := _request()
	var ns = _main._state.player()
	var ev = _main._loader.events[0]
	var history_before: int = ns.event_history.size()
	ns.event_history.append({"event_id": String(ev.id), "event_name": ev.event_name, "choice_id": String(ev.choices[0]["id"]),
		"choice_label": String(ev.choices[0]["label"]), "year": 2027, "month": 3, "defaulted": false})
	ns.event_history.append({"event_id": String(ev.id), "event_name": ev.event_name, "choice_id": String(ev.choices[0]["id"]),
		"choice_label": String(ev.choices[0]["label"]), "year": 2027, "month": 4, "defaulted": true})
	_main._hud.inbox.push("A strike", "The dockers stop.")
	_main._hud.inbox.push("A leak", "A memo reaches the press.")
	_open_tab()
	var groups: Dictionary = _panel().groups()
	var answer: Array = groups.get("answer", [])
	for key in ["file:" + carded, "desk:" + bare, "file:" + asked]:
		if not answer.has(key):
			_fail("'To answer' lacks %s (has %s)" % [key, answer])
	if (groups.get("decided", []) as Array).size() != history_before + 2:
		_fail("'Decided' is not the ledger whole: %d rows for %d records" % [(groups.get("decided", []) as Array).size(), history_before + 2])
	if (groups.get("news", []) as Array).size() != 2:
		_fail("'News' does not hold the two notes: %s" % [groups.get("news", [])])
	# The record the clock answered says so on its page.
	var defaulted := ""
	for key in groups.get("decided", []):
		_panel().select(String(key))
		if _texts(_panel()._page).contains("No answer given"):
			defaulted = String(key)
	if defaulted == "":
		_fail("no record of 'Decided' says the clock answered it")
	ns.event_history.resize(history_before)
	_clear_desk()


func _check_an_answer_keeps_the_clock() -> void:
	_clear_desk()
	var carded := _event(0)
	_event(1)
	_main._clock.paused = false
	_open_tab()
	_panel().select("file:" + carded)
	var ns = _main._state.player()
	var before: int = ns.event_queue.size()
	var history: int = ns.event_history.size()
	_panel().press(0)
	_panel()._refresh()
	if ns.event_queue.size() != before - 1 or ns.event_history.size() != history + 1:
		_fail("an answer on the Folder did not reach main.gd's handler (desk %d -> %d)" % [before, ns.event_queue.size()])
	if _main._clock.paused:
		_fail("an answer on the Folder paused the clock")
	if not _main._windows.is_open("events"):
		_fail("an answer on the Folder closed the tab")
	if _panel().selected() == "file:" + carded or (_panel().groups().get("answer", []) as Array).has("file:" + carded):
		_fail("the answered file is still listed or still shown")
	_clear_desk()


func _check_a_desk_entry_with_no_card() -> void:
	_clear_desk()
	var bare := _event(1, false)
	_main._clock.paused = false
	_open_tab()
	_panel().select("desk:" + bare)
	var title: String = preload("res://src/ui/strings.gd").row_name("events", _main._loader.events[1])
	if not _texts(_panel()._page).contains(title):
		_fail("a desk entry with no card shows no page of its own ('%s' not on it)" % title)
	var ns = _main._state.player()
	var history: int = ns.event_history.size()
	_panel().press(0)
	if ns.event_queue.any(func(e): return String(e.get("event_id", "")) == bare) or ns.event_history.size() != history + 1:
		_fail("a desk entry with no card could not be answered on the Folder")
	if _main._clock.paused:
		_fail("answering a desk entry with no card paused the clock")
	_clear_desk()


func _check_a_request_on_the_tab() -> void:
	_clear_desk()
	var asked := _request()
	if asked == "":
		_fail("the staging made no request card")
		return
	_main._clock.paused = false
	_open_tab()
	_panel().select("file:" + asked)
	_panel().press(RequestLane.DECLINE)
	if not _main._windows.is_open("events"):
		_fail("declining a request left the Folder")
	if _main._clock.paused:
		_fail("declining a request on the Folder paused the clock")
	_clear_desk()


func _check_a_file_gone_while_shown() -> void:
	_clear_desk()
	var first := _event(0)
	var second := _event(1)
	_open_tab()
	_panel().select("file:" + first)
	_main._hud.inbox.dismiss(first)
	_panel()._refresh()
	if _panel().selected() == "file:" + first:
		_fail("a file that is gone left its page on screen")
	if _panel().selected() != "file:" + second:
		_fail("a gone file's selection did not move to the next file (selected '%s')" % _panel().selected())
	_clear_desk()


## The read is the Presidency page now: it opens the page and never pauses.
func _check_read_opens_the_page() -> void:
	_clear_desk()
	_main._windows.close("events")
	_main._clock.paused = false
	BriefingDriver._games[_main.get_instance_id()]["pending"] = {}
	BriefingDriver.month_end(_main, {})
	BriefingDriver.read(_main)
	if not _main._windows.is_open("overview"):
		_fail("the chief's read did not open the Presidency page")
	if _main._clock.paused:
		_fail("the chief's read paused the clock")
	_clear_desk()


## A Go on a priority about a desk file opens the Folder on that file, the clock as it was.
func _check_go_opens_the_file() -> void:
	_clear_desk()
	var carded := _event(0)
	_main._clock.paused = false
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	game["lines"] = [{"kind": "crisis", "subject": String(_main._loader.events[0].id), "go": {"tab": "events"},
		"held": false, "standing": false, "deadline_month": -1}]
	game["also"] = []
	BriefingDriver.go(_main, 0)
	_panel()._refresh()
	if not _main._windows.is_open("events") or _panel().selected() != "file:" + carded:
		_fail("a Go on a file's priority did not open the Folder on it (selected '%s')" % _panel().selected())
	if _main._clock.paused:
		_fail("a Go on a file's priority paused the clock")
	_clear_desk()


func _check_the_news_line() -> void:
	_clear_desk()
	_main._windows.close("events")
	var inbox = _main._hud.inbox
	if inbox._rows[Inbox.NOTES].visible:
		_fail("the inbox still shows its notes as cards")
	if inbox.news_count() != 0:
		_fail("an empty inbox counts %d news" % inbox.news_count())
	inbox.push("A strike", "The dockers stop.")
	if inbox.news_count() != 1 or not inbox.news_line().text.contains("1"):
		_fail("a note landing did not move the News line (%d, '%s')" % [inbox.news_count(), inbox.news_line().text])
	inbox.push("A strike", "The dockers stop.")  # its twin: grouped, one row
	if inbox.news_count() != 2:
		_fail("a note grouped with its twin did not move the News count (%d)" % inbox.news_count())
	for i in Inbox.NOTES_MAX + 2:
		inbox.push("Note %d" % i, "Body %d." % i)
	if inbox.news_count() != Inbox.NOTES_MAX + 4:
		_fail("notes past the lane's cap did not move the News count (%d)" % inbox.news_count())
	# Decisions and requests keep their lanes.
	var asked := _request()
	if asked == "" or inbox.lane_of(asked) != Inbox.REQUESTS or not inbox._rows[Inbox.REQUESTS].visible:
		_fail("a request no longer has its own lane")
	inbox.news_line().pressed.emit()
	_panel()._refresh()
	if not _main._windows.is_open("events") or not _panel().selected().begins_with("note:"):
		_fail("the News line did not open the Folder's news (selected '%s')" % _panel().selected())
	if inbox.news_count() != 0:
		_fail("the news read on the Folder still counts %d" % inbox.news_count())
	_clear_desk()


## The parent's call on S2 (QA, in play): after an answer the inbox stays over the tab while a decision
## or a request is still in it; it slides out only once it holds neither (or the player puts it away).
## Requests never hold the clock, so the old rule ("unless a decision holds the clock") hid waiting ones.
func _check_the_inbox_stays_while_a_request_waits() -> void:
	_clear_desk()
	var inbox = _main._hud.inbox
	_main._windows.open("finances")
	var carded := _event(0)
	_request()
	inbox.slide_in()
	if not inbox.is_slid():
		_fail("premise: the inbox did not slide over the tab")
		return
	inbox.card_action.emit(carded, 0)  # the card's own button
	if not inbox.is_slid():
		_fail("answering a decision slid the inbox away with a request still waiting")
	_clear_desk()
	carded = _event(0)
	inbox.slide_in()
	inbox.card_action.emit(carded, 0)
	if inbox.is_slid():
		_fail("answering the last thing in the inbox left it over the tab")
	_main._windows.close_all()
	_clear_desk()


func _texts(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label or child is Button:
			out += String(child.text) + "\n"
		elif child is RichTextLabel:
			out += String(child.get_parsed_text()) + "\n"
		out += _texts(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_folder")
		quit(0)
	else:
		print("FAIL test_folder: %d" % _failures.size())
		quit(1)
