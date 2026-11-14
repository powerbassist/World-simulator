extends RefCounted

## The month's folder's wiring -- V5.3 screen 3 (the author picked decision C: the briefing
## becomes the place the month's files are answered). Static over main, beside
## briefing_driver.gd (which is at its size ceiling): it fills the card's list with the desk's
## files (inbox_files.gd), builds a file's page when one is chosen (file_read.gd), and sends a
## page's button through Inbox.press -- the card's own door -- so every rule main.gd and the
## request lane keep is the same.
##
## **The clock.** The briefing holds the clock and gives the speed back on its close. An answer
## given in the folder runs main.gd's own handler, whose `_resume_if_decision_settled` lets the
## clock go once nothing holds it; with the folder still up that would run the world under it,
## so the driver re-pauses straight after, and the close button's "Next: ..." is read again.
## A file that is not an event (a request's day to pick, a treaty or a vote to open) is
## answered where it lives: the folder closes first by Go's own rule, the clock staying paused.

const FileRead = preload("res://src/ui/file_read.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const RequestLane = preload("res://src/ui/request_lane.gd")


static func attach(main, card) -> void:
	card.file_selected.connect(func(id: String) -> void: _show(main, card, id))
	card.file_pressed.connect(func(id: String, index: int) -> void: _press(main, card, id, index))


## The list, rebuilt from the desk now; `selected` keeps a page the player is on.
static func refresh(main, selected := "") -> void:
	var card = BriefingDriver.card_of(main)
	if card == null:
		return
	var inbox = main._hud.inbox
	var files: Array = []
	for file in InboxFiles.list(inbox):
		files.append({"id": file["id"], "title": FileRead.list_title(main, file), "by": FileRead.by_text(main, file, true)})
	card.show_files(files, selected)
	if card.selected_file() != "":
		_show(main, card, card.selected_file())


## A Go on a priority whose subject is a file selects its page and keeps the folder up.
## False for any other line.
static func go(main, line: Dictionary) -> bool:
	var id := file_of(main, line)
	if id == "" or InboxFiles.of(main._hud.inbox, id).is_empty():
		return false
	refresh(main, id)
	return BriefingDriver.card_of(main).selected_file() == id


## The desk file a priority line is about, or "" for a line that is not a file.
static func file_of(main, line: Dictionary) -> String:
	match String(line["kind"]):
		"crisis", "decision":
			for card_id in main._event_cards:
				if String(main._event_cards[card_id]) == String(line["subject"]):
					return String(card_id)
		"request":
			return AudienceDriver.lane_of(main).card_of(String(line["subject"]))
	return ""


## An answered file's lines leave the month page with it (QA #333 T3): a Go left there would
## close the folder and open the surface of a file that is gone. `answered` are the lines that
## named it, read before the answer (a declined request has no card to look up after). The
## lines are not ranked again: the chief spoke over these three, and the rest keep their places.
static func _drop_lines(main, card, id: String, answered: Array) -> void:
	if answered.is_empty() or not InboxFiles.of(main._hud.inbox, id).is_empty():
		return
	var game: Dictionary = BriefingDriver._games[main.get_instance_id()]
	for key in ["lines", "also"]:
		game[key] = (game[key] as Array).filter(func(l): return not answered.has(l))
	card.show_lines(BriefingDriver.view(main, game["lines"], game.get("report", {}), game["also"]))


static func _show(main, card, id: String) -> void:
	card.show_file_page(id, FileRead.describe(main, InboxFiles.of(main._hud.inbox, id)))


static func _press(main, card, id: String, index: int) -> void:
	# Stays in the folder: an event's answer, a request's Delegate or Decline. Everything else (a
	# request's day to pick or its call, a treaty, a vote, a bill) is answered where it lives.
	var request: bool = AudienceDriver.lane_of(main)._request_of.has(id)
	var stays: bool = main._event_cards.has(id) or (request and [RequestLane.DELEGATE, RequestLane.DECLINE].has(index))
	if not stays:
		BriefingDriver._games[main.get_instance_id()]["was_running"] = false
		BriefingDriver.close(main)
		InboxFiles.press(main._hud.inbox, id, index)
		return
	var game: Dictionary = BriefingDriver._games[main.get_instance_id()]
	var answered: Array = ((game["lines"] as Array) + (game["also"] as Array)).filter(func(l): return file_of(main, l) == id)
	if not InboxFiles.press(main._hud.inbox, id, index):
		return
	main._clock.paused = true
	main._hud.clock_cluster.refresh(main._clock, preload("res://src/ui/hold_reason.gd").show(main))
	refresh(main)
	_drop_lines(main, card, id, answered)
	card.set_close_text(BriefingDriver._close_text(main))
