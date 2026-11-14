extends RefCounted

## The inbox's decision and request rows as FILES -- V5.3 screen 3 (the author picked the
## month's folder and the docked card). A file is whatever row of those two lanes asks
## something of the player: an event, an audience request, a treaty, a council vote, a bill,
## a region's fund. There is no register of files: the lanes ARE it, so a new kind of row is
## a file the moment it is pushed with answers (or protected) and no one lists it twice.
##
## Static over an Inbox, so inbox.gd (at its size ceiling) only keeps `_asked`, the answers
## each row was pushed with.


## The rows in the order the lanes show them (decisions, then requests; newest first):
## each {id, lane, title, body, actions}.
static func list(inbox) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lane in [inbox.DECISIONS, inbox.REQUESTS]:
		for card in inbox._rows[lane].get_children():
			var id: String = inbox._id_of(card)
			if inbox._asked.has(id):
				out.append({"id": id, "lane": lane, "title": inbox._asked[id]["title"], "body": inbox._asked[id]["body"],
					"actions": inbox._asked[id]["actions"]})
	return out


## One file by its card id, {} when it is gone (answered, lapsed, a load).
static func of(inbox, id: String) -> Dictionary:
	for file in list(inbox):
		if file["id"] == id:
			return file
	return {}


## One door for an answer given anywhere but the card itself: a gone row or a disabled answer
## is refused (a request's refused answer keeps its reason on its tooltip), anything else is
## the card's own button -- `card_action`, which main.gd and the request lane already answer.
static func press(inbox, id: String, index: int) -> bool:
	if not inbox._asked.has(id):
		return false
	var actions: Array = inbox._asked[id]["actions"]
	if index < 0 or index >= actions.size() or bool(actions[index].get("disabled", false)):
		return false
	inbox.card_action.emit(id, index)
	return true
