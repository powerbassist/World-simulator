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
##                                  money is unchanged);
##   factor(ns, line)               what the moved shares did to the channel the line
##                                  feeds: exactly 1.0 with nothing moved.
##
## THE CHANNELS READ THE FACTOR (3.1: "a moved share moves its sector's quantity
## and, through it, the existing channel"). Society.quality_target() (health,
## pensions), Economy._update_potential_shift() (education, infrastructure) and
## Defence.capability_target() (defence) multiply the line's spending by it. The
## factor is the start-share-weighted mean of what the move did to each sector's
## quantity, as an improvement and with the line's spending held:
##   sum(s0 * (s / s0) ^ elasticity) / sum(s0)
## so money moved toward a more elastic sector buys more of the channel and the
## reverse buys less, and since every elasticity is under 1 each quantity's returns
## diminish: between two equally elastic sectors (pensions) any move costs the
## channel. The line's spending stays out of it, because every channel already
## reads that. With nothing moved the factor is absent and reads exactly 1.0, and
## x * 1.0 == x in IEEE arithmetic, so band A1 (every share at its start, the
## balance table cmp-identical) holds by construction.
##
## THE FACTOR IS DERIVED, NOT SAVED (project_sited_pct's case): the three channels
## take no loader, so move_share() stores it on the nation (`ns.sector_factor`) and
## the load path re-derives it from the saved moves and the shipped rows
## (rebuild(), from save_manager.load_game()). The re-derivation is also what drops
## the factor of a moved vector shares() no longer reads (a sector renamed since the
## save), so the channel and the tile never disagree.
##
## quantity() and the factor call pow(): MAIN-THREAD only (src/core/parallel.gd's
## rule: no pow()/exp() on a worker). No tick step computes either; a channel reads
## the stored float, a panel or a probe reads quantity().
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
		return float(start["quantity"]) * pow(maxf(ratio, DK.RATIO_FLOOR), e)
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
	_store_factor(ns, loader, line)
	return {"ok": true, "shares": now.duplicate()}


## The channel factor of `line` (see the header): 1.0 with nothing moved.
static func factor(ns, line: String) -> float:
	return float(ns.sector_factor.get(line, 1.0))


## Every nation's factors, re-derived from its saved moves and the loaded rows.
static func rebuild(state, loader) -> void:
	for ns in state.nations.values():
		ns.sector_factor = {}
		for line in ns.sector_shares:
			_store_factor(ns, loader, String(line))


static func _store_factor(ns, loader, line: String) -> void:
	var moved: Dictionary = ns.sector_shares.get(line, {})
	var now := shares(ns, loader, line)
	if moved.is_empty() or not _same_ids(moved, now):
		ns.sector_factor.erase(line)
		return
	var total := 0.0
	var weight := 0.0
	for s in sectors_of(loader, line):
		var id := String(s["id"])
		var s0 := float(_start(ns, s)["share"])
		total += s0 * pow(maxf(float(now[id]) / s0, DK.RATIO_FLOOR), float(DK.ELASTICITY[id]))
		weight += s0
	ns.sector_factor[line] = total / weight


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
