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
## its `player_swings` (Orgs). It preloads a constants file and no system: budget.gd
## preloads events.gd, so a system preloaded here could close a cycle back to its
## caller.
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


static func quiet(state, ns, now: int) -> bool:
	if not bool(ns.in_government):
		return false
	for entry in ns.event_queue:
		if int(entry.get("arrived", -1)) == now:
			return false
	for row in ns.audience_requests:
		if int(row.get("arrived_month", -1)) == now:
			return false
	for company_id in ns.companies:
		var c: Dictionary = ns.companies[company_id]
		if int(c.get("bid_month", -1)) == now or int(c.get("failed_month", -1)) == now \
				or int((c.get("closure", {}) as Dictionary).get("announced", -1)) == now:
			return false
	for row in ns.processes:
		if int((row.get("ask", {}) as Dictionary).get("posted", -1)) == now:
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


## How many people asked in the QUIET_ASKS_MONTHS before `now` (every lane: a
## visitor and a chief count as the nation's own do), off the one register every ask
## stamps -- the person branch's cap reads it.
static func asks_in_year(ns, now: int) -> int:
	var n := 0
	for pid in ns.audience_asked_month:
		if now - int(ns.audience_asked_month[pid]) < AudK.QUIET_ASKS_MONTHS:
			n += 1
	return n
