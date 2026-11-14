extends RefCounted

## V5.3 screen 4, PR 1: what a law can do toward the month's one slot and the queue of three
## (docs/design/finance-bill.md section 10). ONE table, read by the sheet's verbs and by the
## right click, so neither ever offers a press the sim refuses.
##
##   slot empty, law not queued   Propose                               (the queue is only behind a held slot)
##   slot empty, law queued       Propose down (queued); Take out of the queue
##   slot held by THIS law        Propose down; nothing else
##   slot held by another bill    Propose down; Queue for <month>
##   ... queue full               Queue shown but down, with its reason
##   law queued                   Propose down; Take out of the queue, naming its month
##
## A queue entry k divides on the last day of month + 1 + k: promotion tables the head at the
## close that ends the month, and a tabled bill divides at the close that ends the month it was
## tabled in (bill_queue.gd). The reads are pure over GameState; the commands are BillQueue's.

const BillQueue = preload("res://src/sim/bill_queue.gd")
const Bills = preload("res://src/sim/bills.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")


## The date queue entry `i` divides: {year, month, day}.
static func division(state, i: int) -> Dictionary:
	var index := int(state.year) * 12 + (int(state.month) - 1) + 1 + i
	var year := floori(index / 12.0)
	var month := index - year * 12 + 1
	return {"year": year, "month": month, "day": Calendar.days_in_month(year, month)}


## Where `law_id` stands in the queue, -1 when it is not there.
static func queued_at(ns, law_id: String) -> int:
	for i in ns.bill_queue.size():
		if String(ns.bill_queue[i].get("law_id", "")) == law_id:
			return i
	return -1


## The table's cell for `law_id`: {slot: "empty"|"held"|"here", queued: int, propose: String (the
## reason Propose is down, "" when it is up), queue: {shown, enabled, text, reason},
## unqueue: {shown, text}}. `find_law` is the host's lookup of a law by id, for a composed one.
static func cells(state, loader, law_id: String, find_law := Callable()) -> Dictionary:
	var ns = state.player()
	var tabled := String(ns.tabled_bill.get("law_id", ""))
	var slot := "empty" if ns.tabled_bill.is_empty() else ("here" if tabled == law_id else "held")
	var at := queued_at(ns, law_id)
	var out := {"slot": slot, "queued": at, "propose": "",
		"queue": {"shown": false, "enabled": false, "text": "", "reason": ""},
		"unqueue": {"shown": false, "text": ""}}
	if slot != "empty":
		out["propose"] = tabled_reason(ns, loader, find_law)
	if at >= 0:
		out["propose"] = Strings.t("It is queued for %s: take it out of the queue to put it before the Assembly now.") % month_name(state, at)
		out["unqueue"] = {"shown": true, "text": Strings.t("Take out of the queue (%s)") % month_name(state, at)}
		return out
	if slot == "held":
		var full: bool = ns.bill_queue.size() >= BillQueue.SIZE
		out["queue"] = {"shown": true, "enabled": not full,
			"text": Strings.t("The queue is full") if full else Strings.t("Queue for %s") % month_name(state, ns.bill_queue.size()),
			"reason": Strings.t("The queue holds three bills. Take one out first.") if full else ""}
	return out


## "February", for queue entry `i`.
static func month_name(state, i: int) -> String:
	return DateText.month_long(int(division(state, i)["month"]))


## Which bill is before the Assembly and the day it divides: the slot's whole sentence, for any
## bill in it, a law or the finance bill.
static func tabled_reason(ns, loader, find_law := Callable()) -> String:
	var id := String(ns.tabled_bill.get("law_id", ""))
	# A composed law lives on the register, not the loader: the host's lookup finds it.
	var law = find_law.call(id) if find_law.is_valid() else Bills.by_id(loader, id)
	return Strings.t("%s is before the Assembly: it divides on %s, and no other bill can be put before then.") % [
		Strings.law_name(law, id),
		DateText.day_month(int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))]
