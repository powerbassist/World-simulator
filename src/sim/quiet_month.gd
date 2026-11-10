extends RefCounted

## V5.3 B7, the quiet-month call's one question: did anything arrive for the player
## this month? (docs/design/v5.3-b7-density.md section 4; the author's call 2 and the
## parent's ruling on the shape, 2026-11-10.) Asked twice a month, by two owners:
## Audiences at the end of its month (the person branch) and the QuietEvent step after
## it (Events, the event branch) -- so the second sees the first's call, a request
## stamped this month, and neither system calls the other.
##
## A LEAF OVER STAMPS. Every read is a register another machine already writes, with
## the month it wrote it: a desk entry's `arrived` (Events), a request's
## `arrived_month` (Audiences), a closure's `announced` (Closures), a firm's
## `bid_month` and `failed_month` (Companies), a process ask's `posted` (Processes), a
## sector warning's `entered` (SectorWarnings) and a council division's opening with
## its `player_swings` (Orgs). It preloads constants and Events' draw leaf (whose own
## preloads are the cycle and constants) and no system: budget.gd preloads events.gd,
## so a system preloaded here could close a cycle back to its caller.
##
## AN ARRIVAL THAT IS NO DECISION DOES NOT END THE QUIET. A desk event or a process ask
## whose answers differ on no bloc arrow and no money (event_draw.gd's filter, the same
## one the call's own event passes) is not something the band counts, so the month is
## still empty for the player -- the scandal whose answers move only press freedom and
## corruption, the minority stake whose asks all cost alike. Measured on the build: five
## of the seven months left empty in the first density run held exactly such an event
## or ask. A request counts the same way since the author's ruling of 2026-11-10: one
## whose answers all leave the person in the same feeling words (Audiences stamps
## `differs` on each request the month brings, with the cuts the card draws its words
## with, src/sim/feeling_constants.gd) is no arrival. An event this build does not
## know, and a request with no stamp, end the quiet: the safe side.
##
## What does NOT end the quiet, as the spec measured it: a backbench bill awaiting the
## president's stand, a treaty awaiting the assembly and the Regions arrival -- each
## is a card of its own, the prototype read none of them, and the figures the author
## accepted assume that. A government out of office is never called on (the
## prototype's gate, which the figures also assume): the asks and the desk are a
## government's.
##
## An absent stamp reads as no arrival (an older save's desk entry, a division opened
## before the stamp existed), which is the truth for every month but the one a save
## was taken in -- and that month already ran its call.

const AudK = preload("res://src/sim/audience_constants.gd")
const EventDraw = preload("res://src/sim/event_draw.gd")


static func quiet(state, ns, loader, now: int) -> bool:
	if not bool(ns.in_government):
		return false
	for entry in ns.event_queue:
		if int(entry.get("arrived", -1)) == now and _decides(ns, loader, String(entry.get("event_id", ""))):
			return false
	for row in ns.audience_requests:
		if int(row.get("arrived_month", -1)) == now and bool(row.get("differs", true)):
			return false
	for company_id in ns.companies:
		var c: Dictionary = ns.companies[company_id]
		if int(c.get("bid_month", -1)) == now or int(c.get("failed_month", -1)) == now \
				or int((c.get("closure", {}) as Dictionary).get("announced", -1)) == now:
			return false
	for row in ns.processes:
		var ask: Dictionary = row.get("ask", {})
		if int(ask.get("posted", -1)) == now and EventDraw.answers_differ(ns, ask.get("answers", [])):
			return false
	for row in (ns.sector_drift.get("warnings", {}) as Dictionary).values():
		if int(row.get("entered", -1)) == now:
			return false
	for org_id in ns.orgs:
		var pending: Dictionary = (state.orgs.get(org_id, {}) as Dictionary).get("pending", {})
		if bool(pending.get("player_swings", false)) \
				and int(pending.get("opened_year", 0)) * 12 + int(pending.get("opened_month", 0)) == now:
			return false
	return true


## Whether a desk event's answers differ (event_draw.gd's filter); an id this build's
## book does not hold reads as a decision.
static func _decides(ns, loader, event_id: String) -> bool:
	for ev in loader.events:
		if String(ev.id) == event_id:
			return EventDraw.meaningful(ns, ev)
	return true


## How many people asked in the QUIET_ASKS_MONTHS before `now` (every lane: a
## visitor and a chief count as the nation's own do), off the one register every ask
## stamps -- the person branch's cap reads it.
static func asks_in_year(ns, now: int) -> int:
	var n := 0
	for pid in ns.audience_asked_month:
		if now - int(ns.audience_asked_month[pid]) < AudK.QUIET_ASKS_MONTHS:
			n += 1
	return n
