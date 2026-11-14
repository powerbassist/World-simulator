extends RefCounted

## The lane's counts, and the requests events have overtaken. Split out of audiences.gd when
## a chief's request (V5.3 b, step 6) met that file's 300-line cap.
##
## A CHIEF'S REQUEST IS NOT THE DOMESTIC LANE'S. It arrives because a plant is closing,
## not because a person drew a monthly ask, so it takes no place under MAX_PENDING and
## pushes nobody out. The object says which it is: a chief also carries the nation's id
## prefix, so the person cannot.

const K = preload("res://src/sim/audience_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Closures = preload("res://src/sim/closures.gd")
const Dates = preload("res://src/sim/audience_dates.gd")
const Characters = preload("res://src/sim/characters.gd")


## The open requests of this nation's people (`own`), or of the visiting heads.
static func open_count(ns, own: bool) -> int:
	var n := 0
	for row in ns.audience_requests:
		if K.OPEN.has(String(row.get("status", ""))) and not String(row.get("object", "")).begins_with(K.FIRM_PREFIX) \
				and String(row.get("person_id", "")).begins_with("%s_" % ns.id) == own:
			n += 1
	return n


## Whether any of the played nation's own people has ever asked (a visiting head
## is not the draw's).
static func asked_ever(ns) -> bool:
	for pid in ns.audience_asked_month:
		if String(pid).begins_with("%s_" % ns.id):
			return true
	return false


## A request events overtook closes with no price, its day given back, and nobody was
## refused. A chief's, at once, when its closure is no longer waiting for an answer: the
## plant landed, or the player answered it on the Industry tab (Closures runs first in the
## month, so a closure left unanswered has landed by the time its request would lapse).
## Any other, when it would lapse with its want served now (Gameplay's read of #351, the
## parent's card): the fund opened on the Regions screen, the card left unanswered. Run
## before the lapses; a request the player already agreed keeps its own close.
static func close_overtaken(state, ns, now: int, loader = null, meters: Dictionary = {}) -> void:
	for row in ns.audience_requests:
		var object := String(row.get("object", ""))
		if not K.OPEN.has(String(row.get("status", ""))):
			continue
		if object.begins_with(K.FIRM_PREFIX):
			if not Closures.announced(ns, object.substr(K.FIRM_PREFIX.length())).is_empty():
				continue
		elif loader == null or not overdue(row, now) or String(row.get("agreed", "")) != "" or not _served(state, ns, loader, meters, row):
			continue
		if String(row["status"]) == K.STATUS_BOOKED:
			Calendar.cancel(state, Calendar.verb_key(Dates.entry(row, row["date"])))
		row["status"] = K.STATUS_OVERTAKEN
		row["resolved_month"] = now


## Pending past its window lapses; an audience booked or held in an earlier month and never
## closed is a no-show (Audiences' lapse loop and close_overtaken() read this one rule).
static func overdue(row: Dictionary, now: int) -> bool:
	match String(row.get("status", "")):
		K.STATUS_PENDING:
			return now >= int(row["deadline_month"])
		K.STATUS_BOOKED, K.STATUS_HELD:
			var date: Dictionary = row.get("date", {})
			return int(date.get("year", 0)) * 12 + int(date.get("month", 0)) < now
	return false


## Whether the request's want, as the person holds it, is served now (Characters' judge, with
## the authored leaders Audiences' arrivals read). A request with no such want (a visiting head's)
## is not served.
static func _served(state, ns, loader, meters: Dictionary, row: Dictionary) -> bool:
	var person = loader.person_by_id.get(String(row.get("person_id", "")))
	if person == null:
		return false
	var leaders := {}
	for party in loader.parties.get(state.player_nation_id, []):
		leaders[party.id] = party.leader_person_id
	for want in person.wants:
		if String(want["object"]) == String(row["object"]) and String(want["stance"]) == String(row["stance"]):
			return Characters.want_served(ns, person, want, meters, leaders)
	return false
