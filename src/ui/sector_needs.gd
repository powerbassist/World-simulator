extends RefCounted

## What waits on the player in each sector -- V5.3 screen 5, slice 1. ONE reader for the
## four places that show it: the sector tab's Needs you rows, the tab's hourglass and
## count, the Sectors row's total in the sidebar (through pending.gd) and the overview
## card's "Decision due" mark. Four readers of four lists would disagree the first time
## one of them learnt a new kind.
##
## An item is a firm with something to answer: a foreign bid, a failing major's rescue
## window, a process stage's ask, a plant closure announced or a buyer come back. A firm
## the loader no longer names is skipped (a register entry a content edit orphaned must
## not light a mark forever: pending.gd's own rule).

const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")
const Processes = preload("res://src/sim/processes.gd")
const Closures = preload("res://src/sim/closures.gd")

## The sector tabs' window ids, by the sector the sim models. The overview keeps the id
## "companies" (domains.gd, tools/screenshot.gd --open and the tests address it).
const TABS := {"agriculture": "sector_agriculture", "industry": "sector_industry", "services": "sector_services"}


static func tab_of(sector: String) -> String:
	return String(TABS.get(sector, ""))


## One row per firm and kind: {sector, company_id, kind, months_left}, months_left -1
## where the sim keeps no window. Kinds are bid, failing, ask, closure.
static func items(state, loader, ns) -> Array:
	var out: Array = []
	if state == null or loader == null or ns == null:
		return out
	var sector_of := {}
	for company in Companies.majors_of(loader, ns.id) + Companies.body_of(loader, ns.id):
		sector_of[String(company.id)] = String(company.sector)
	var bid: Dictionary = Industry.pending_bid(state, ns, loader)
	if not bid.is_empty():
		_add(out, sector_of, String(bid["company_id"]), "bid", int(bid.get("months_left", -1)))
	for failure in Industry.failing(state, ns, loader):
		_add(out, sector_of, String(failure["company_id"]), "failing", int(failure.get("months_left", -1)))
	for row in Processes.asks(ns):
		_add(out, sector_of, String(row["company_id"]), "ask", -1)
	for row in Closures.open(ns):
		if closure_waits(row):
			var now: int = state.year * 12 + state.month
			_add(out, sector_of, String(row["company_id"]), "closure", int(row.get("due", now)) - now)
	return out


## {tab id: items} for the tabs with something waiting.
static func counts(state, loader, ns) -> Dictionary:
	var out := {}
	for item in items(state, loader, ns):
		var tab := tab_of(String(item["sector"]))
		out[tab] = int(out.get(tab, 0)) + 1
	return out


## An announced closure, or a buyer that came back (#285) until it is answered once.
static func closure_waits(row: Dictionary) -> bool:
	return String(row["status"]) == Closures.ANNOUNCED or (String(row["status"]) == Closures.OFFERED and not row.has("answer"))


static func _add(out: Array, sector_of: Dictionary, company_id: String, kind: String, months_left: int) -> void:
	if not sector_of.has(company_id):
		return
	out.append({"sector": String(sector_of[company_id]), "company_id": company_id, "kind": kind, "months_left": months_left})
