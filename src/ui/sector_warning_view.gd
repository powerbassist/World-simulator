extends RefCounted

## A sector slipping, read and answered -- V5.3 a + b, band B7, #288's reads
## (src/sim/sector_warnings.gd). A figure drifts on its own, so a held line slips into its
## bad band: the tile marks the sector and says why, and offers the answer that exists.
##
## TWO ANSWERS, SIDE BY SIDE (the parent's ruling on #290). Systems measured that a warned
## sector rarely has an un-warned one to pay it, so the tile offers one raise for the line,
## priced by the Budget's own books, beside the move. The move stays whenever the sim
## accepts it, a warned sector paying included: that is the tradeoff, and its strip shows
## it. A raise holds the shares, so it lifts every sector of the line: one verb, the largest
## restore of those warned, not one per sector.
##
## ARRIVALS SPEND NO STOP (decision-surfaces.md, 4 + 6 a year): a crossing is a line on the
## monthly briefing, which holds the clock anyway (Priorities._sectors), or a note on a
## month the briefing does not show. Several in a month, as a sharp fall brings, fold into
## that one line or note (QA's RECORD on #288: France's GDP down 5 % warns 7 at once).

const Sectors = preload("res://src/sim/sectors.gd")
const SectorWarnings = preload("res://src/sim/sector_warnings.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")

## The share a move takes, in points of the line: the tile's smallest, and what "can pay"
## tries.
const STEP := 0.01


## {sector id: reason msgid} for the line's sectors in their bad band.
static func warned(ns, loader, line: String) -> Dictionary:
	var out := {}
	for s in Sectors.sectors_of(loader, line):
		var why := SectorWarnings.warning(ns, loader, line, String(s["id"]))
		if why != "":
			out[String(s["id"])] = why
	return out


## Whether the sim would let any sector of the line pay another: the move's floor, asked
## of the sim, so "cannot pay" is said only where it refuses.
static func can_pay(ns, loader, line: String, sectors: Array) -> bool:
	for s in sectors:
		for other in sectors:
			if String(s["id"]) != String(other["id"]):
				if bool(Sectors.move_share(ns.duplicate_state(), loader, line, String(s["id"]), String(other["id"]), STEP).get("ok", false)):
					return true
				break
	return false


## The first sector that can pay `to_id` a share and is not itself warned, "" for none:
## what a Go aims the move from, not what decides whether the move is offered.
static func donor(ns, loader, line: String, sectors: Array, why_of: Dictionary, to_id: String) -> String:
	for s in sectors:
		var id := String(s["id"])
		if id != to_id and not why_of.has(id) and bool(Sectors.move_share(ns.duplicate_state(), loader, line, id, to_id, STEP).get("ok", false)):
			return id
	return ""


## A month the briefing does not show: the crossings, folded into one note.
static func note_cards(ns, loader, now: int) -> Array:
	var arrivals := SectorWarnings.arrivals(ns, loader, now)
	if arrivals.is_empty():
		return []
	var parts := PackedStringArray()
	for a in arrivals:
		parts.append(name_of(loader, String(a["line"]), String(a["id"])))
	return [{"title": Strings.t("Sectors slipping"), "tone": ResultTone.RISKY,
		"body": Strings.t("%s: the figures have slipped. See the Books.") % ", ".join(parts)}]


## A priority's subject: its line, then its sector.
static func subject_of(line: String, id: String) -> String:
	return "%s|%s" % [line, id]


static func name_of(loader, line: String, id: String) -> String:
	for s in Sectors.sectors_of(loader, line):
		if String(s["id"]) == id:
			return sector_name(s)
	return id


static func sector_name(sector: Dictionary) -> String:
	return Strings.row("domains", String(sector["id"]), "name", String(sector["name"]))
