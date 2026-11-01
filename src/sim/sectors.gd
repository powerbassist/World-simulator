extends RefCounted

## V5.3 a (docs/design/v5.3-ab.md 3.1, band A2): each spending line split into
## sectors (data/domains/, loader.domains), each moving a named quantity the player
## can read. This file is the reads and the two verbs:
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
##                                  feeds: exactly 1.0 with nothing moved;
##   set_priority(...)              the regional priority (3.3 (a) 1): one region put
##                                  first for a sector, the others paying the same
##                                  money, so no national figure moves;
##                                  regional_quantity() and priority_estimate() read it.
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
const RK = preload("res://src/sim/region_constants.gd")


static func sectors_of(loader, line: String) -> Array:
	return (loader.domains.get(line, {}) as Dictionary).get("sectors", [])


static func shares(ns, loader, line: String) -> Dictionary:
	var out := {}
	for s in sectors_of(loader, line):
		out[String(s["id"])] = _start(ns, s)["share"]
	var moved := _moved(ns, loader, line)
	for id in moved:
		out[id] = float(moved[id])
	return out


## The player's moved vector for `line` as shares() reads it, else {}. A content
## edit that renamed or added a sector since the save makes the moved vector a
## different partition: it is dropped for the start, never half-read. One rule, so
## the factor (_store_factor) and the tile cannot disagree about it.
static func _moved(ns, loader, line: String) -> Dictionary:
	var moved: Dictionary = ns.sector_shares.get(line, {})
	if moved.is_empty():
		return {}
	var ids := {}
	for s in sectors_of(loader, line):
		ids[String(s["id"])] = true
	return moved if _same_ids(moved, ids) else {}


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
	if _moved(ns, loader, line).is_empty():
		ns.sector_factor.erase(line)
		return
	var now := shares(ns, loader, line)
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


# --- The regional priority (V5.3 a, docs/design/v5.3-ab.md 3.3 (a) 1) ---------------
# "Put hospitals first in Hauts-de-France": the region's spending per head on the
# sector rises by DK.PRIORITY_UPLIFT and every other region's falls so the money is
# the same, so the population-weighted mean multiplier is exactly 1 and no national
# figure moves (the line's total, quantity(), factor() and every channel). One
# priority per sector at a time: a second replaces the first, which is the choice.
# It reads the live population shares, so the same money holds as people move.

## The region put first for this sector, "" for none.
static func priority_of(ns, sector_id: String) -> String:
	return String(ns.sector_priorities.get(sector_id, ""))


## Put `region_id` first for a sector of `line`. {ok} or {ok: false, reason}; a
## refusal writes nothing.
static func set_priority(state, ns, loader, line: String, sector_id: String, region_id: String) -> Dictionary:
	var why := _priority_refusal(state, ns, loader, line, sector_id, region_id)
	if why != "":
		return {"ok": false, "reason": why}
	ns.sector_priorities[sector_id] = region_id
	return {"ok": true}


static func clear_priority(ns, sector_id: String) -> Dictionary:
	if not ns.sector_priorities.has(sector_id):
		return {"ok": false, "reason": "This sector has no regional priority."}
	ns.sector_priorities.erase(sector_id)
	return {"ok": true}


## The region's spending per head on the sector against the nation's: 1.0 with no
## priority, 1 + uplift in the region put first, and the same money's loss elsewhere.
static func spend_multiplier(ns, sector_id: String, region_id: String) -> float:
	var first := priority_of(ns, sector_id)
	if first == "":
		return 1.0
	if first == region_id:
		return 1.0 + DK.PRIORITY_UPLIFT
	return _others_multiplier(ns, first)


## The sector's quantity in one region: the nation's, moved by the region's spending
## multiplier ^ elasticity (the sign from `better`), as quantity() moves by spending.
## Exactly the nation's figure with no priority. pow(): a main-thread read.
static func regional_quantity(ns, loader, line: String, sector_id: String, region_id: String) -> float:
	var q := quantity(ns, loader, line, sector_id)
	var m := spend_multiplier(ns, sector_id, region_id)
	if m == 1.0:
		return q
	return q * pow(maxf(m, DK.RATIO_FLOOR), _signed_elasticity(loader, line, sector_id))


## The strip's figures for putting `region_id` first: {ok, region_before,
## region_after, others_after, national} or {ok: false, reason}. "Others" is any
## region other than the one put first (they all lose the same share).
static func priority_estimate(state, ns, loader, line: String, sector_id: String, region_id: String) -> Dictionary:
	var why := _priority_refusal(state, ns, loader, line, sector_id, region_id)
	if why != "":
		return {"ok": false, "reason": why}
	var q := quantity(ns, loader, line, sector_id)
	var e := _signed_elasticity(loader, line, sector_id)
	return {"ok": true, "region_before": regional_quantity(ns, loader, line, sector_id, region_id),
		"region_after": q * pow(1.0 + DK.PRIORITY_UPLIFT, e),
		"others_after": q * pow(maxf(_others_multiplier(ns, region_id), DK.RATIO_FLOOR), e), "national": q}


## Every other region's spending multiplier when `first` is put first: the uplift's
## money spread over the rest of the population. Over the map's own total, not 1.0:
## the live shares need not sum to exactly 1 (migration moves them, the authored ones
## are rounded), and the same money is what this must keep exactly.
static func _others_multiplier(ns, first: String) -> float:
	var p := float(ns.region_pop_share.get(first, 0.0))
	return 1.0 - DK.PRIORITY_UPLIFT * p / (_pop_total(ns) - p)


static func _pop_total(ns) -> float:
	var total := 0.0
	for region in ns.region_pop_share:
		total += float(ns.region_pop_share[region])
	return total


static func _signed_elasticity(loader, line: String, sector_id: String) -> float:
	for s in sectors_of(loader, line):
		if String(s["id"]) == sector_id:
			var e := float(DK.ELASTICITY[sector_id])
			return -e if String(s["quantity"]["better"]) == "lower" else e
	return 0.0


static func _priority_refusal(state, ns, loader, line: String, sector_id: String, region_id: String) -> String:
	var known := false
	for s in sectors_of(loader, line):
		if String(s["id"]) == sector_id:
			known = true
	if not known:
		return "That is not a sector of this spending line."
	for region in state.regions.get(ns.id, []):
		if region.id == region_id and region_id != RK.RESIDUAL_KEY:
			var p := float(ns.region_pop_share.get(region_id, 0.0))
			if p <= 0.0:
				return "This region has no population share to weigh a priority by."
			if _pop_total(ns) - p <= 0.0:
				return "This nation has no other region to pay for a priority."
			# regional_quantity() floors a multiplier at RATIO_FLOOR, and a floored one
			# no longer pays its part: a region that holds most of the people cannot be
			# paid for by the rest, so the same money would not hold.
			if _others_multiplier(ns, region_id) < DK.RATIO_FLOOR:
				return "This region holds too much of the population for the others to pay for a priority."
			return ""
	return "That is not one of this nation's regions."
