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


## A chief's request whose closure is no longer waiting for an answer closes with no price:
## the plant landed, or the player answered it on the Industry tab, and nobody was refused.
## Run before the lapses: Closures runs first in the month, so a closure left unanswered
## has landed by the time its request would have lapsed.
static func close_overtaken(state, ns, now: int) -> void:
	for row in ns.audience_requests:
		var object := String(row.get("object", ""))
		if not object.begins_with(K.FIRM_PREFIX) or not K.OPEN.has(String(row.get("status", ""))):
			continue
		if not Closures.announced(ns, object.substr(K.FIRM_PREFIX.length())).is_empty():
			continue
		if String(row["status"]) == K.STATUS_BOOKED:
			Calendar.cancel(state, Calendar.verb_key(Dates.entry(row, row["date"])))
		row["status"] = K.STATUS_OVERTAKEN
		row["resolved_month"] = now
