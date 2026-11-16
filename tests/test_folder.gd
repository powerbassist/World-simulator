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
## The real-clock lapse (#403 pass 2 T3): "" until the synchronous checks are done.
var _phase := ""
var _lapse_card := ""
var _lapse_event := ""
var _since := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _phase == "lapse":
		return _lapse_step()
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
	_check_go_on_a_crisis_with_no_card()
	_check_nothing_to_answer_shows_the_news()
	_check_a_queued_rerank_runs_once()
	_check_the_decided_order()
	_check_a_note_with_a_deadline_stays_a_card()
	_check_the_keyboard_answers()
	_check_the_whole_consequence()
	_check_a_note_says_its_tone()
	_check_the_news_count_is_the_unread()
	_check_the_inbox_stays_only_for_answers()
	_check_the_programme_file_goes_to_the_agenda()
	_check_the_subject_line()
	_start_the_lapse()
	return false


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


## #403 pass 2 T3: the page never silently becomes another file (a click there would answer it). A card taken
## away while its matter is still on the desk follows the matter to its desk entry.
func _check_a_file_gone_while_shown() -> void:
	_clear_desk()
	var first := _event(0)
	var second := _event(1)
	_open_tab()
	_panel().select("file:" + first)
	_main._hud.inbox.dismiss(first)
	_panel()._refresh()
	if _panel().selected() == "file:" + second:
		_fail("a file that went while shown was swapped for the next file")
	if _panel().selected() != "desk:" + String(_main._loader.events[0].id):
		_fail("a card gone while its matter is on the desk did not follow it (selected '%s')" % _panel().selected())
	_clear_desk()


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
	inbox.news_seen()
	inbox.push("A strike", "The dockers stop.")  # its twin, after it was read: grouped, unread again
	if inbox.news_count() != 1:
		_fail("a note read, then grouped with its twin, is not unread again (%d)" % inbox.news_count())
	for i in Inbox.NOTES_MAX + 2:
		inbox.push("Note %d" % i, "Body %d." % i)
	if inbox.news_count() != Inbox.NOTES_MAX:
		_fail("past the lane's cap the News count is not the unread notes there (%d of %d)" % [inbox.news_count(), Inbox.NOTES_MAX])
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
	# A note that came twice says so on its page, once.
	var twice: String = inbox.push("Twice", "Said again.")
	inbox.push("Twice", "Said again.")
	_panel().select("note:" + twice)
	if not _texts(_panel()._page).contains("Came 2 times."):
		_fail("a note grouped with its twin does not say it came twice")
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


## GLM gap 2: a crisis line whose card is gone (its X) or never came (its popup kept quiet): the Go opens
## the Folder on its desk entry, never nothing.
func _check_go_on_a_crisis_with_no_card() -> void:
	_clear_desk()
	var bare := _event(1, false)
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	game["lines"] = [{"kind": "crisis", "subject": bare, "go": {"tab": "events"}, "held": false, "standing": false,
		"deadline_month": -1}]
	game["also"] = []
	BriefingDriver.go(_main, 0)
	_panel()._refresh()
	if not _main._windows.is_open("events") or _panel().selected() != "desk:" + bare:
		_fail("a Go on a crisis with no card did not open its desk entry (selected '%s')" % _panel().selected())
	_clear_desk()


## GLM gap 4: nothing to answer and nothing decided yet, but news: the page shows the newest note, not a blank.
func _check_nothing_to_answer_shows_the_news() -> void:
	_clear_desk()
	var ns = _main._state.player()
	var history: Array = ns.event_history.duplicate(true)
	ns.event_history.clear()
	_main._hud.inbox.push("A strike", "The dockers stop.")
	_panel().select("")
	_open_tab()
	if not _panel().selected().begins_with("note:"):
		_fail("with nothing to answer or decided the Folder shows no page (selected '%s')" % _panel().selected())
	# Pass 1 finding: shown by the fallback, or rebuilt under a shown note, it is not the player reading
	# the news: the count waits for the News line or a note picked in the list.
	if _main._hud.inbox.news_count() != 1:
		_fail("the Folder's fallback to a note reset the News count (%d)" % _main._hud.inbox.news_count())
	_main._hud.inbox.push("A leak", "A memo reaches the press.")
	_panel()._refresh()
	if _main._hud.inbox.news_count() != 2:
		_fail("a rebuild under a shown note reset the News count (%d)" % _main._hud.inbox.news_count())
	_panel().select("note:" + String(_main._hud.inbox.notes()[0]["id"]))
	if _main._hud.inbox.news_count() != 0:
		_fail("a note picked in the list did not count the news read (%d)" % _main._hud.inbox.news_count())
	ns.event_history = history
	_clear_desk()


## GLM gap 10: a re-rank run early for its queue (a caller that needs the read now) leaves the deferred
## call nothing to do: it would rank over the lines set since.
func _check_a_queued_rerank_runs_once() -> void:
	var ChiefMarkView = preload("res://src/ui/chief_mark_view.gd")
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	ChiefMarkView.queue_rerank(_main)
	ChiefMarkView._rerank_queued(_main)  # run early
	var staged := [{"kind": "staged", "subject": "x", "standing": true, "held": false, "deadline_month": -1}]
	game["lines"] = staged
	ChiefMarkView._rerank_queued(_main)  # the deferred call, at the frame's end
	if game["lines"] != staged:
		_fail("the deferred re-rank ran a second time for one queue and ranked over the lines set since")
	game["lines"] = []


## #403 pass 2 T1: newest first, in the order the sim keeps (Events.answer pushes to the front).
func _check_the_decided_order() -> void:
	_clear_desk()
	var ns = _main._state.player()
	var first = _main._loader.events[0]
	var second = _main._loader.events[1]
	_event(0, false)
	_event(1, false)
	Events.answer(_main._state, _main._loader, String(first.id), String(first.choices[0]["id"]))
	Events.answer(_main._state, _main._loader, String(second.id), String(second.choices[0]["id"]))
	_open_tab()
	var decided: Array = _panel().groups().get("decided", [])
	if decided.is_empty() or not String(decided[0]).contains(String(second.id)):
		_fail("'Decided' does not open on the newest answer (%s first)" % [decided.slice(0, 2)])
	# A record keeps its page when a newer one lands (keyed by the record, not its place).
	_panel().select(String(decided[0]))
	var shown: String = _panel().selected()
	ns.event_history.push_front({"event_id": "zz_newer", "event_name": "Newer", "choice_id": "", "choice_label": "x",
		"year": int(_main._state.year), "month": int(_main._state.month), "defaulted": false})
	_panel()._refresh()
	if _panel().selected() != shown or not _texts(_panel()._page).contains(preload("res://src/ui/strings.gd").row_name("events", second)):
		_fail("a record shown became another when a newer one landed (now '%s')" % _panel().selected())
	ns.event_history.remove_at(0)
	_clear_desk()


## #403 pass 2 T2: a note that carries a deadline or a route (the term's countdown, a takeover bid, a firm in
## difficulty) stays a card; only plain news folds into the News line.
func _check_a_note_with_a_deadline_stays_a_card() -> void:
	_clear_desk()
	_main._windows.close_all()  # the inbox on the map
	var inbox = _main._hud.inbox
	var kept: String = inbox.keep_card(inbox.push("Your term", "Sixteen months to the vote."))
	inbox.push("A strike", "The dockers stop.")
	if not inbox._cards[kept].is_visible_in_tree():
		_fail("a note with a deadline is not a card in the inbox")
	if inbox.news_count() != 1:
		_fail("a kept card counts in the News line (%d)" % inbox.news_count())
	for path in ["res://src/ui/industry_news.gd", "res://src/ui/main.gd"]:
		if not FileAccess.get_file_as_string(path).contains("keep_card("):
			_fail("%s no longer keeps its deadline cards up" % path)
	_clear_desk()


## #403 pass 2 T4: the keyboard answers -- the answer buttons take focus, and a pick in the list keeps it.
func _check_the_keyboard_answers() -> void:
	_clear_desk()
	var bare := _event(1, false)
	_open_tab()
	var item: Button = _panel()._buttons.get("desk:" + bare)
	if item == null:
		_fail("premise: the desk entry has no list button")
		return
	item.grab_focus()
	item.pressed.emit()
	var owner: Control = _main.get_viewport().gui_get_focus_owner()
	if owner == null or not _panel().is_ancestor_of(owner):
		_fail("a pick in the Folder's list lost the keyboard focus")
	var answers: Array = _panel()._page.find_children("*", "Button", true, false)
	if answers.is_empty() or answers.any(func(b): return (b as Button).focus_mode == Control.FOCUS_NONE):
		_fail("an answer button on the Folder takes no keyboard focus")
	_main.get_viewport().gui_release_focus()
	_clear_desk()


## #403 pass 2 T5: a choice's whole consequence before the answer, not its first sentence.
func _check_the_whole_consequence() -> void:
	_clear_desk()
	var Strings = preload("res://src/ui/strings.gd")
	var n := -1
	for i in _main._loader.events.size():
		var ev = _main._loader.events[i]
		if Strings.choice_summary(ev.id, ev.choices[0]).count(". ") >= 1:
			n = i
			break
	if n < 0:
		_fail("premise: no event has a choice summary of two sentences")
		return
	var bare := _event(n, false)
	_open_tab()
	_panel().select("desk:" + bare)
	var ev = _main._loader.events[n]
	var whole: String = preload("res://src/ui/panel_kit.gd").TermText.plain(Strings.choice_summary(ev.id, ev.choices[0]))
	if not _texts(_panel()._page).contains(whole):
		_fail("the page shows less than the choice's whole consequence: '%s'" % whole.left(60))
	_clear_desk()


## #403 pass 2 T6: a note's good / bad word is on its page, words and not colour alone.
func _check_a_note_says_its_tone() -> void:
	_clear_desk()
	var ResultTone = preload("res://src/ui/result_tone.gd")
	var id: String = ResultTone.push(_main._hud.inbox, "Carried", "The bill passed.", ResultTone.GOOD)
	_open_tab()
	_panel().select("note:" + id)
	var word := preload("res://src/ui/strings.gd").t(String(ResultTone.TAG[ResultTone.GOOD][1]))
	if not _texts(_panel()._page).contains(word):
		_fail("a note's '%s' word is not on its page" % word)
	_clear_desk()


## #403 pass 2 T7: the count is the unread notes there -- a note taken away by code, Clear all, a News press
## with nothing to read.
func _check_the_news_count_is_the_unread() -> void:
	_clear_desk()
	var inbox = _main._hud.inbox
	var a: String = inbox.push("A strike", "The dockers stop.")
	inbox.push("A leak", "A memo reaches the press.")
	inbox.dismiss(a)
	if inbox.news_count() != 1:
		_fail("a note taken away by code still counts (%d)" % inbox.news_count())
	inbox.clear_notes()
	if inbox.news_count() != 0:
		_fail("Clear all left a News count (%d)" % inbox.news_count())
	inbox.news_line().pressed.emit()
	_panel()._refresh()
	if inbox.news_count() != 0 or not _main._windows.is_open("events"):
		_fail("a News press with nothing to read left a count or opened nothing")
	_clear_desk()


## #403 pass 2 T9: the inbox stays after an answer only while a row asks one (a decision or a request), not for
## the programme's card or an Open row.
func _check_the_inbox_stays_only_for_answers() -> void:
	_clear_desk()
	var inbox = _main._hud.inbox
	_main._windows.open("finances")
	inbox.push("Choose the programme", "The term starts.", [], null, true)
	inbox.push("A fund", "Hauts-de-France asks.", [{"label": "Open"}])
	var carded := _event(0)
	inbox.slide_in()
	inbox.card_action.emit(carded, 0)
	if inbox.is_slid():
		_fail("the inbox stayed over the tab for rows that ask no answer")
	_main._windows.close_all()
	_clear_desk()


## #403 pass 2 T10: the term's programme card, a file with no answer of its own, opens the Agenda (until S3).
func _check_the_programme_file_goes_to_the_agenda() -> void:
	_clear_desk()
	var inbox = _main._hud.inbox
	var saved: String = _main._programme_card_id
	_main._programme_card_id = inbox.push("Choose the programme", "The term starts.", [], null, true)
	_open_tab()
	_panel().select("file:" + _main._programme_card_id)
	var go: Button = null
	for b in _panel()._page.find_children("*", "Button", true, false):
		go = b
	if go == null:
		_fail("the programme's file has no way to the Agenda")
	else:
		go.pressed.emit()
		if not _main._windows.is_open("agenda"):
			_fail("the programme file's button did not open the Agenda")
	_main._programme_card_id = saved
	_main._windows.close_all()
	_clear_desk()


## #403 pass 2 T13: an event about an office names its holder on the page (the old Dispatches subject line).
func _check_the_subject_line() -> void:
	_clear_desk()
	var ns = _main._state.player()
	var n := -1
	for i in _main._loader.events.size():
		if String(_main._loader.events[i].subject_office) == "head_of_government":
			n = i
			break
	if n < 0:
		_fail("premise: no event is about the head of government")
		return
	var bare := _event(n, false)
	_open_tab()
	_panel().select("desk:" + bare)
	var who: String = _main._loader.person_name(String(ns.pm_person_id))
	var want: String = who if who != "" else String(ns.head_of_government_title)
	if want == "" or not _texts(_panel()._page).contains(want):
		_fail("the page of an event about the head of government does not name them ('%s')" % want)
	_clear_desk()


## #403 pass 2 T3, on the real clock: a file shown when its deadline passes shows its own record, says the clock
## answered it, and is never swapped for another file.
func _start_the_lapse() -> void:
	_clear_desk()
	_main._paused_for_programme = false
	_lapse_card = _event(0, true, 1)
	_event(1, true, 3)
	_lapse_event = String(_main._loader.events[0].id)
	_open_tab()
	_panel().select("file:" + _lapse_card)
	var clock: Node = _main.get_node("Clock")
	clock.day = clock._days_in_month(clock.month, clock.year)
	clock.paused = false
	clock.set_speed(4)
	_phase = "lapse"
	_since = 0


func _lapse_step() -> bool:
	_since += 1
	var ns = _main._state.player()
	var gone: bool = not ns.event_queue.any(func(e): return String(e.get("event_id", "")) == _lapse_event)
	if not gone or _main._month_runner.running():
		if _since > 1200:
			_fail("the lapse never came (date %d-%d)" % [_main._clock.year, _main._clock.month])
			_finish()
			return true
		if _main._clock.paused:
			_main._clock.paused = false  # an arrival may hold it; the lapse is the clock's
		return false
	_main._clock.paused = true
	_panel()._refresh()
	var shown: String = _panel().selected()
	if shown.begins_with("file:") and shown != "file:" + _lapse_card:
		_fail("a file that lapsed while shown was swapped for another file ('%s')" % shown)
	if not shown.begins_with("record:") or not shown.contains(_lapse_event):
		_fail("a file that lapsed while shown does not show its own record (selected '%s')" % shown)
	var text := _texts(_panel()._page)
	if not text.contains("No answer given") or not text.contains("lapsed"):
		_fail("the lapsed file's record does not say the clock answered it: '%s'" % text.left(160))
	_finish()
	return true


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
