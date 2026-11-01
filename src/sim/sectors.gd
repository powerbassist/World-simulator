extends RefCounted

## V5.3 a (docs/design/v5.3-ab.md 3.1, band A2): each spending line split into
## sectors (data/domains/, loader.domains), each moving a named quantity the player
## can read. This file is the reads and the one verb:
##
##   shares(ns, loader, line)       sector id -> share of the line: the player's
##                                  moved shares, else the nation's start shares
##                                  (else the `default` row);
##   quantity(ns, loader, line, id) the sector's quantity: its start figure moved by
##                                  (its spending now / at the start) ^ elasticity,
##                                  with the sign of the row's `better` (more
##                                  spending always improves it);
##   move_share(...)                the quantified verb: move part of one sector's
##                                  share to another, a pure reallocation (the line's
##                                  money is unchanged).
##
## NOTHING FEEDS A CHANNEL YET: society's quality, trend growth and capability
## still read the line's total, so band A1 (with every share at its start, the
## balance table is cmp-identical) holds by construction until the channels read
## the sectors (the next PR, once Content's data has landed).
##
## quantity() calls pow(): a MAIN-THREAD read (src/core/parallel.gd's rule: no
## pow()/exp() on a worker). No tick step calls it; a panel or a probe does.
##
## THE REGISTER IS THE PLAYER'S MOVES ONLY: `ns.sector_shares` holds a line only
## once the player has moved one of its shares, never a copy of the start (a copy
## would be a content-derived static that from_dict() cannot re-derive, and would
## need a SAVE bump). Absent reads the start, the truth for every older save.

const DK = preload("res://src/sim/domains_constants.gd")


static func sectors_of(loader, line: String) -> Array:
	return (loader.domains.get(line, {}) as Dictionary).get("sectors", [])


static func shares(ns, loader, line: String) -> Dictionary:
	var out := {}
	for s in sectors_of(loader, line):
		out[String(s["id"])] = _start(ns, s)["share"]
	var moved: Dictionary = ns.sector_shares.get(line, {})
	# A content edit that renamed or added a sector since the save makes the moved
	# vector a different partition: it is dropped for the start, never half-read.
	if not moved.is_empty() and _same_ids(moved, out):
		for id in out:
			out[id] = float(moved[id])
	return out


static func quantity(ns, loader, line: String, sector_id: String) -> float:
	for s in sectors_of(loader, line):
		if String(s["id"]) != sector_id:
			continue
		var start: Dictionary = _start(ns, s)
		var line_now := float(ns.spending_pct_gdp.get(line, 0.0))
		var line_then := float(ns.start_spending_pct_gdp.get(line, 0.0))
		var share_now := float(shares(ns, loader, line)[sector_id])
		if line_then <= 0.0 or float(start["share"]) <= 0.0:
			return float(start["quantity"])
		var ratio := (line_now / line_then) * (share_now / float(start["share"]))
		var e := float(DK.ELASTICITY[sector_id])
		if String(s["quantity"]["better"]) == "lower":
			e = -e
		return float(start["quantity"]) * pow(maxf(ratio, 0.0), e)
	return 0.0


## Move `amount` of the line's share from one sector to another. {ok, shares} or
## {ok: false, reason}; a refusal writes nothing.
static func move_share(ns, loader, line: String, from_id: String, to_id: String, amount: float) -> Dictionary:
	var now := shares(ns, loader, line)
	if now.is_empty():
		return {"ok": false, "reason": "This spending line has no sectors."}
	if not now.has(from_id) or not now.has(to_id) or from_id == to_id:
		return {"ok": false, "reason": "Pick two different sectors of this line."}
	if amount <= 0.0:
		return {"ok": false, "reason": "Move a share above zero."}
	if float(now[from_id]) - amount < DK.MIN_SHARE:
		return {"ok": false, "reason": "A sector cannot fall under its floor."}
	now[from_id] = float(now[from_id]) - amount
	now[to_id] = float(now[to_id]) + amount
	ns.sector_shares[line] = now
	return {"ok": true, "shares": now.duplicate()}


## The nation's own start row, else the line's default.
static func _start(ns, sector: Dictionary) -> Dictionary:
	return (sector["start"] as Dictionary).get(String(ns.id), sector["start"]["default"])


static func _same_ids(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in b:
		if not a.has(k):
			return false
	return true
