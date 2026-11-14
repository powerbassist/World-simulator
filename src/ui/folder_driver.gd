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
	var id := ""
	match String(line["kind"]):
		"crisis", "decision":
			for card_id in main._event_cards:
				if String(main._event_cards[card_id]) == String(line["subject"]):
					id = String(card_id)
		"request":
			id = AudienceDriver.lane_of(main).card_of(String(line["subject"]))
	if id == "" or InboxFiles.of(main._hud.inbox, id).is_empty():
		return false
	refresh(main, id)
	return BriefingDriver.card_of(main).selected_file() == id


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
	if not InboxFiles.press(main._hud.inbox, id, index):
		return
	main._clock.paused = true
	main._hud.clock_cluster.refresh(main._clock, preload("res://src/ui/hold_reason.gd").show(main))
	refresh(main)
	card.set_close_text(BriefingDriver._close_text(main))
