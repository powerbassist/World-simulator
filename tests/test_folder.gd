extends SceneTree

## Headless test: godot --headless --script res://tests/test_folder.gd
## Non-zero exit on any failure.
##
## V5.3 screen 3, the month's folder (the briefing card with the desk's files). What can fail
## silently, pinned by the advisor's list before the build:
##   - THE CLOCK. An answer given in the folder runs main.gd's handler, whose
##     `_resume_if_decision_settled` lets the clock go once nothing holds it: with the folder
##     still up that runs the world under it. The driver re-pauses; the close button's "Next: ..."
##     is read again; closing still gives the speed back.
##   - A file that is not an event (a request's day to pick) is answered where it lives: the
##     folder closes first, the clock staying paused; Delegate and Decline stay in the folder.
##   - The month page is the default and the only page the 1 / 2 / 3 keys mean anything on.
##   - A file gone while shown (answered, lapsed) never leaves a stale page; no files means the
##     card is as it was (no list, its old width).
##   - A Go on a file-kind priority selects the page and keeps the folder up.
##   - A file answered in the folder takes its priority line and Go off the month page (QA #333 T3).

const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const FolderDriver = preload("res://src/ui/folder_driver.gd")
const DeskCards = preload("res://src/ui/desk_cards.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const ChiefBriefing = preload("res://src/ui/chief_briefing.gd")

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
	_check_no_files()
	_check_the_clock_under_an_answer()
	_check_a_request_in_the_folder()
	_check_a_file_gone_while_shown()
	_check_go_selects_a_file()
	_check_an_answer_takes_its_priority()
	_finish()
	return true


func _open_folder() -> ChiefBriefing:
	BriefingDriver._games[_main.get_instance_id()]["pending"] = {}
	BriefingDriver.open(_main, {})
	return BriefingDriver.card_of(_main)


func _clear_desk() -> void:
	var ns = _main._state.player()
	ns.event_queue.clear()
	ns.audience_requests.clear()
	for file in preload("res://src/ui/inbox_files.gd").list(_main._hud.inbox):
		_main._hud.inbox.dismiss(String(file["id"]))
	_main._event_cards.clear()
	_main._unseen_events.clear()
	BriefingDriver.close(_main)


func _event(severity := 1, months := 3, interrupt := false) -> String:
	var ns = _main._state.player()
	var ev = _main._loader.events[0]
	var entry := {"event_id": String(ev.id), "event_name": ev.event_name, "months_left": months, "severity": severity,
		"category": ev.category, "interrupt": interrupt}
	ns.event_queue.append(entry)
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


func _check_no_files() -> void:
	# A desk with no files: the card is as it was, with no list and its old width.
	var card := _open_folder()
	card.show_files([])
	if card._files.visible or card.custom_minimum_size.x != ChiefBriefing.SIZE.x:
		_fail("a desk with no files gives a folder with a list or a widened card; the card should be as it was")
	if card.selected_file() != "" or not card._month.visible:
		_fail("with no files the month's page is not the one shown")
	BriefingDriver.close(_main)


func _check_the_clock_under_an_answer() -> void:
	_clear_desk()
	var holding := _event(3, 2, true)
	_event(1, 3)
	_main._clock.paused = true
	_main._paused_for_decision = true
	# Nothing else holds the clock (the term's programme would keep it paused on its own and hide the
	# very thing under test: main.gd's handler letting the clock go once the answer settles the hold).
	_main._paused_for_programme = false
	var card := _open_folder()
	if not card._files.visible or card.custom_minimum_size.x != ChiefBriefing.FOLDER_WIDTH or card._file_buttons.size() < 2:
		_fail("a desk with files gives no list")
	if card.selected_file() != "" or not card._month.visible or card._file_slot.visible:
		_fail("the month's page is not the default page")
	var closes_with: String = card._close.text
	# The 1/2/3 keys mean something only on the month page: on a file's page they are inert.
	card.select(holding)
	if card._month.visible or not card._file_slot.visible or card._file_slot.get_child_count() == 0:
		_fail("choosing a file did not show its page")
	var went: Array = []
	card.go_pressed.connect(func(i: int) -> void: went.append(i))
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	card._input(key)
	if not went.is_empty():
		_fail("the 1 key pressed a Go on a file's page")
	# Answer the holding event inside the folder.
	var ns = _main._state.player()
	var before: int = ns.event_queue.size()
	card.file_pressed.emit(holding, 0)
	if ns.event_queue.size() != before - 1:
		_fail("an answer given in the folder did not reach main.gd's handler (desk %d -> %d)" % [before, ns.event_queue.size()])
	if not _main._clock.paused:
		_fail("the clock runs under the open folder after an answer")
	if not card.visible:
		_fail("answering an event closed the folder")
	if card._close.text == closes_with and closes_with.begins_with("Next:") and holding != "":
		_fail("the close button still names the answered event: '%s'" % card._close.text)
	if card._file_buttons.has(holding):
		_fail("the answered file is still in the list")
	# Closing gives the speed back: nothing holds the clock now except the second (minor) event's card, which
	# does not hold on arrival; the clock was running before the briefing.
	BriefingDriver._games[_main.get_instance_id()]["was_running"] = true
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	BriefingDriver.close(_main)
	if _main._clock.paused:
		_fail("closing the folder did not give the clock back")
	_clear_desk()


func _check_a_request_in_the_folder() -> void:
	_clear_desk()
	var asked := _request()
	if asked == "":
		_fail("the staging made no request card")
		return
	_main._clock.paused = true
	var card := _open_folder()
	if not card._file_buttons.has(asked):
		_fail("a request is not a file in the folder")
		return
	card.select(asked)
	# Decline stays in the folder.
	card.file_pressed.emit(asked, 2)
	if not card.visible:
		_fail("declining a request closed the folder")
	if not _main._clock.paused:
		_fail("the clock runs after a request was declined in the folder")
	# A second request: its Go (pick a day) closes the folder by Go's rule, the clock staying paused.
	_clear_desk()
	var again := _request()
	_main._clock.paused = true
	card = _open_folder()
	BriefingDriver._games[_main.get_instance_id()]["was_running"] = true
	card.select(again)
	card.file_pressed.emit(again, 0)
	if card.visible:
		_fail("choosing a day left the folder up over the Diary")
	if not _main._clock.paused:
		_fail("choosing a day gave the speed back (Go keeps the clock paused)")
	_clear_desk()


func _check_a_file_gone_while_shown() -> void:
	_clear_desk()
	var id := _event(1, 3)
	_main._clock.paused = true
	var card := _open_folder()
	card.select(id)
	_main._hud.inbox.dismiss(id)
	FolderDriver.refresh(_main, id)
	if card.selected_file() != "" or not card._month.visible:
		_fail("a file that is gone left its page on screen (selected '%s')" % card.selected_file())
	BriefingDriver.close(_main)
	_clear_desk()


func _check_go_selects_a_file() -> void:
	_clear_desk()
	var id := _event(3, 2, true)
	_main._clock.paused = true
	var card := _open_folder()
	var ev = _main._loader.events[0]
	if not FolderDriver.go(_main, {"kind": "crisis", "subject": String(ev.id)}):
		_fail("a Go on a crisis priority did not select its file")
	if not card.visible or card.selected_file() != id:
		_fail("a Go on a file's priority closed the folder or chose another page (selected '%s')" % card.selected_file())
	if FolderDriver.go(_main, {"kind": "bloc", "subject": "workers"}):
		_fail("a Go on a priority that is not a file claimed the folder")
	BriefingDriver.close(_main)
	_clear_desk()


## QA #333 T3 (found in play): a request answered in the folder kept its priority line and Go on
## "This month"; that stale Go closed the folder and opened the Diary for a request already gone.
func _check_an_answer_takes_its_priority() -> void:
	_clear_desk()
	var asked := _request()
	if asked == "":
		_fail("the staging made no request card")
		return
	var request: Dictionary = _main._state.player().audience_requests[0]
	var rid := String(request["id"])
	var who: String = _main._loader.person_name(String(request["person_id"]))
	_main._clock.paused = true
	var card := _open_folder()
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	var named := func() -> bool:
		return ((game["lines"] as Array) + (game["also"] as Array)).any(
			func(l): return String(l["kind"]) == "request" and String(l["subject"]) == rid)
	if not named.call() or not _texts(card._month).contains(who):
		_fail("staging: the request is not among the month's priorities on the month page")
		return
	card.select(asked)
	card.file_pressed.emit(asked, 2)  # Decline: stays in the folder
	if named.call():
		_fail("an answered request's priority line is still among the month's lines")
	if _texts(card._month).contains(who):
		_fail("the month page still names the answered request ('%s')" % who)
	if card.go_buttons.size() + card.also_buttons.size() != (game["lines"] as Array).size() + _groups(game["also"]):
		_fail("the month page's Go buttons do not match its lines after an answer")
	if not card.visible or card.selected_file() != "":
		_fail("after the answer the folder is not up on the month's page")
	BriefingDriver.close(_main)
	_clear_desk()


func _texts(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label or child is Button:
			out += String(child.text) + "\n"
		out += _texts(child)
	return out


func _groups(also: Array) -> int:
	var kinds := {}
	for entry in also:
		kinds[String(entry["kind"])] = true
	return kinds.size()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_folder: all checks passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	quit(1)
