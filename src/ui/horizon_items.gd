extends RefCounted

## What the horizon (ribbon.gd) draws, read off registers that already exist -- the
## author picked bar C of the V5.3 bar pictures ("what pulls you into next month, in
## sight"). This file holds no state and writes none, and `src/sim` is not touched:
## it gathers DATED things the sim already carries, three calendar months from today,
## and says where each lands.
##
##   bookings  the diary's appointments (Calendar), by meeting day and travel days;
##   dues      the last month a request can be answered (Audiences' `deadline_month`
##             minus one, the convention audience_driver and the diary share) and the
##             last month a desk decision can be (its `months_left` counts DOWN at each
##             month tick, so the entry lapses on the first of now + months_left);
##   vote      the vote that ends the player's term (Trends.vote_date, the one clock
##             every surface counts to).
##
## **Deadlines are month-granular in the sim**, so a due is drawn at its month's END and
## never at a day the sim does not hold (the parent's ruling: no sim change). A booking
## is day-exact, as the diary is.

const Calendar = preload("res://src/sim/calendar.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Events = preload("res://src/sim/events.gd")
const Trends = preload("res://src/ui/trends.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

## This month and the two after it.
const MONTHS := 3


## {bookings: [{ordinal, day, month, year, travel_days, kind, name, person_id}],
##  dues: [{abs_month, kind ("request" | "decision"), count, who, person_id}],
##  vote: {year, month, months}}. Bookings sorted by day, dues by month.
static func read(state, loader) -> Dictionary:
	var ns = state.player() if state != null else null
	var out := {"bookings": [], "dues": [], "vote": {}}
	if ns == null:
		return out
	var now := int(state.year) * 12 + int(state.month)
	var first := Calendar.ordinal(int(state.year), int(state.month), int(state.day))
	var last_month := now + MONTHS - 1  # the window's last month, as year * 12 + month
	var last := Calendar.ordinal(floori((last_month - 1) / 12.0), (last_month - 1) % 12 + 1, 31)
	for entry in state.appointments:
		var ord := Calendar.entry_ordinal(entry)
		if ord < first or ord > last:
			continue
		out["bookings"].append({"ordinal": ord, "year": int(entry.get("year", 0)), "month": int(entry.get("month", 0)),
			"day": int(entry.get("day", 1)), "travel_days": int(entry.get("travel_days", 0)), "kind": String(entry.get("kind", "")),
			"act": booking_name(entry, loader), "person_id": String(entry.get("person_id", ""))
				if String(entry.get("kind", "")) == "audience" else ""})
	(out["bookings"] as Array).sort_custom(func(a, b): return int(a["ordinal"]) < int(b["ordinal"]))
	var dues := {}
	for row in Audiences.pending(ns):
		_due(dues, "request", int(row["deadline_month"]) - 1, now, loader.person_name(String(row["person_id"])), String(row["person_id"]))
	for entry in ns.event_queue:
		var ev = Events.event_by_id(loader, String(entry.get("event_id", "")))
		_due(dues, "decision", now + int(entry.get("months_left", 0)) - 1, now, Strings.row_name("events", ev) if ev != null else "", "")
	for key in dues:
		out["dues"].append(dues[key])
	(out["dues"] as Array).sort_custom(func(a, b): return int(a["abs_month"]) < int(b["abs_month"]))
	var when := Trends.vote_date(ns)
	out["vote"] = {"year": when.x, "month": when.y, "months": Trends.months_until(state, when.x, when.y)}
	return out


## A due inside the window joins the (kind, month) group; a second one drops the name
## (a count is what the chip says then).
static func _due(dues: Dictionary, kind: String, abs_month: int, now: int, label: String, person_id: String) -> void:
	if abs_month < now or abs_month > now + MONTHS - 1:
		return
	var key := "%s:%d" % [kind, abs_month]
	if not dues.has(key):
		dues[key] = {"abs_month": abs_month, "kind": kind, "count": 1, "who": label, "person_id": person_id}
		return
	dues[key]["count"] = int(dues[key]["count"]) + 1
	dues[key]["who"] = ""
	dues[key]["person_id"] = ""


## The chip's words for a due, marked up for TermText: a name that links to its card
## when one person is the whole group, a count otherwise.
static func due_text(due: Dictionary) -> String:
	var count := int(due["count"])
	if due["kind"] == "request":
		if count == 1 and String(due["person_id"]) != "":
			return Strings.t("%s's request lapses") % PanelKit.person(String(due["person_id"]), String(due["who"]))
		return Strings.tn("%d request lapses", "%d requests lapse", count) % count
	if count == 1 and String(due["who"]) != "":
		return Strings.t("%s decides itself") % String(due["who"])
	return Strings.tn("%d decision decides itself", "%d decisions decide themselves", count) % count


## An appointment's chip words: the person's name linked, or the act.
static func booking_text(item: Dictionary) -> String:
	if String(item["person_id"]) != "":
		return Strings.t("Audience · %s") % PanelKit.person(String(item["person_id"]), String(item["act"]))
	return String(item["act"])


## The act, in words: never the raw kind. (Moved from the ribbon, which the
## horizon replaced; the ribbon's tooltip path calls it through `_booking_name`.)
static func booking_name(entry: Dictionary, loader) -> String:
	match String(entry.get("kind", "")):
		"diplomatic":
			var action_name := String(entry.get("action_id", ""))
			var nation = loader.nations.get(String(entry.get("target_id", "")))
			if nation != null:
				for action in loader.diplomatic_actions:
					if String(action.id) == String(entry.get("action_id", "")):
						action_name = Strings.row_name("diplomatic-actions", action)
						break
				return "%s — %s" % [action_name, String(nation.nation_name)]
			return action_name
		"law":
			return Strings.t("A law is proposed")
		"reshuffle":
			return Strings.t("A portfolio changes hands")
		"address":
			return Strings.t("An address to the nation")
		"audience":
			var name: String = loader.person_name(String(entry.get("person_id", "")))
			return Strings.t("An audience") if name == "" else name
	return String(entry.get("kind", ""))


## The vote's figure: "05/2027", and its count of months.
static func vote_text(vote: Dictionary) -> String:
	return "%02d/%d" % [int(vote["month"]), int(vote["year"])]
