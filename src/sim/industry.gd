extends RefCounted

## V4.7b B1: the autonomy machine -- majors act. Investment drift, relocation,
## failure with a rescue window, and foreign takeover bids. The tier doc's
## standing rows, finally reachable; the model is the plan's Task B1 and the
## bands live in industry_constants.gd, declared before the probe ran.
##
## THE BODY IS NOT AN ACTOR. Only majors draw, move, fail or draw interest;
## the body tier is acted upon (B2's verbs, later blocks' markets). A body
## firm gains no register entry and no field from this file, which is what
## keeps ~2,400 firms out of both the save and the tick's work.
##
## NO RANDOMNESS. Every draw is Cycle.unit("industry|<id>|<event>", month) --
## the summit draw's idiom -- over the ABSOLUTE month index, so a replay of
## the same months produces the same world and no RNG state is serialised
## anywhere. tests/test_industry.gd pins two identical states bit-identical.
##
## TWO WRITERS, ONE PER ROLE. This file owns the machine's writes -- `city`
## (a relocation's override; the authored city stays content in data/),
## `failed`, `rescue_months_left`, `bid_bidder`/`bid_price_eur_bn`/
## `bid_months_left` (the bid as three scalars: from_dict's rebuild guarantee
## is per-scalar, and a nested dictionary would silently narrow it),
## `subsidy_shadow` and `subsidy_lapsed_month` (the failure hazard's memory of
## a withdrawn subsidy). B2's VERB CHANNEL is the second writer of the keys it
## answers: companies.gd's execute() clears/converts bids (block/allow),
## writes `owner` and `courted`, and commits break-ups and rescues onto
## failed/window. No third file writes any of it; tests/test_industry.gd
## scans.
##
## SAVE_VERSION EARNS NO BUMP, argued per field: absent, every key reads its
## default -- no relocation (authored city), not failed, no window, no bid, no
## shadow -- and that is the truth about every save that predates the machine.
## A bid straddling a save was the plan's worry; but a save from before B1
## cannot HAVE a pending bid, so "absent means none" is exactly right for
## every save the version gate will ever admit across this line.

const IK = preload("res://src/sim/industry_constants.gd")
const CK = preload("res://src/sim/companies_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Companies = preload("res://src/sim/companies.gd")
const Net = preload("res://src/sim/network.gd")
const EK = preload("res://src/sim/economy_constants.gd")

## The relocation distance tables are a pure function of loader content: the
## graph is built once by _load_region_graph, never mutated after (only
## clear()ed by the next load_all), and duplicate_state()'s deep copy
## duplicates content. One memo therefore serves every graph the process
## holds, keyed on the graph's structural hash -- any content difference
## clears it, so a stale table is not reachable. BEFORE the memo the machine
## paid ~8 Dijkstras per nation-month unconditionally: 1,124 ms of the month
## tick measured over the 29-nation roster, 7.6x the whole 300 ms band, the
## B1 review's cannot-verify item found by the re-baseline's own wall clock.
## The memo changes no distance and consumes no Cycle draw, so no result this
## file produces moves. (It lives here and not in network.gd because tests
## call distances_from on synthetic same-size graphs, where a memo could
## answer stale.)
static var _dist_memo: Dictionary = {}
static var _dist_memo_graph := 0


static func tick_month(state, loader) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		_tick_nation(state, ns, loader)


static func _tick_nation(state, ns, loader) -> void:
	var month: int = int(state.year) * 12 + int(state.month)
	var majors := Companies.majors_of(loader, ns.id)
	if majors.is_empty():
		return
	# The plan's own order, and not for taste: FAILURES FIRST, so a firm that
	# fails this month does so at its pre-tick share. Invest-then-fail would
	# zero a post-invest share while every reader of the failure (the rescue
	# credit, the tests' partition audit) prices the pre-tick one -- a
	# same-month leak of up to one INVEST_STEP per failure, found by the
	# zero-sum pin to exactly that magnitude.
	_failures(ns, majors, month)
	_bids(state, ns, loader, majors, month)
	_invest(ns, loader, majors, month)
	_relocate(ns, loader, majors, month)


# --- Investment drift -----------------------------------------------------------

## One month's autonomous drift: in a growing sector, firms that draw intent
## take INVEST_STEP from their rivals' spare (each rival's live share above
## half its authored position -- the subsidy pool's own floor idiom); in a
## declining one, drawing firms shed INVEST_STEP onto the others pro-rata by
## live share. Zero-sum across the sector's majors by construction, and the
## idle world's partition is bit-stable except where a failure commits.
static func _invest(ns, loader, majors: Array, month: int) -> void:
	var by_sector := {}
	for company in majors:
		if _failed(ns, company.id):
			continue
		if not by_sector.has(company.sector):
			by_sector[company.sector] = []
		by_sector[company.sector].append(company)
	for sector in by_sector.keys():
		var firms: Array = by_sector[sector]
		if firms.size() < 2:
			continue
		var declining: bool = float(EK.SECTOR_TREND.get(sector, 0.0)) < 0.0
		var before := {}
		for company in firms:
			before[company.id] = Companies.share_of_company(ns, company)
		var deltas := {}
		for company in firms:
			deltas[company.id] = 0.0
		for company in firms:
			var acts: bool = Cycle.unit("industry|%s|invest" % company.id, month) < 0.5
			if not acts:
				continue
			var step: float = IK.INVEST_STEP
			if declining:
				# Shedding is bounded by what the firm still holds above zero.
				step = minf(step, float(before[company.id]))
				if step <= 0.0:
					continue
				# The others absorb pro-rata by live share, capped by SHARE_MAX.
				var receivers := 0.0
				for other in firms:
					if other.id != company.id:
						receivers += float(before[other.id])
				if receivers <= 0.0:
					continue
				deltas[company.id] = float(deltas[company.id]) - step
				for other in firms:
					if other.id == company.id:
						continue
					var give: float = step * float(before[other.id]) / receivers
					give = minf(give, maxf(CK.SHARE_MAX - float(before[other.id]) - float(deltas[other.id]), 0.0))
					deltas[other.id] = float(deltas[other.id]) + give
			else:
				# Taking: from the others' spare above the rival floor, the
				# subsidy pool's arithmetic one row down.
				var spare := 0.0
				for other in firms:
					if other.id != company.id:
						spare += maxf(float(before[other.id]) - CK.RIVAL_FLOOR_FRACTION * other.share, 0.0)
				if spare <= 0.0:
					continue
				var want: float = minf(step, spare)
				deltas[company.id] = float(deltas[company.id]) + want
				for other in firms:
					if other.id == company.id:
						continue
					var supply: float = maxf(float(before[other.id]) - CK.RIVAL_FLOOR_FRACTION * other.share, 0.0)
					deltas[other.id] = float(deltas[other.id]) - want * supply / spare
		for company in firms:
			# EXACT zero, deliberately not is_equal_approx: Godot's approximate
			# equality has a 1e-5 ABSOLUTE floor, and a drain of 9.8e-6 -- a
			# real rival's real loss, the books' other half -- reads as
			# "approximately zero" and is silently skipped. That exact bug
			# leaked ~1e-5 per sector-month into the partition audit until the
			# zero-sum pin caught it (V3.6's settled-is-a-tolerance lesson,
			# third appearance). deltas start at exact 0.0; only a firm the
			# pass genuinely touched carries a non-zero value.
			if float(deltas[company.id]) == 0.0:
				continue
			# Safe read like every other pass: the entry normally exists
			# (Companies seeds majors first in main.gd's order), but a tick
			# reorder should degrade to a skipped firm, not a crash.
			var entry: Dictionary = ns.companies.get(company.id, {})
			if entry.is_empty():
				continue
			entry["share"] = float(before[company.id]) + float(deltas[company.id])


# --- Relocation -----------------------------------------------------------------

## The tier doc: a relocation must MEAN something -- V2.2's regions and V2.7's
## network price it. A firm that draws the yearly hazard considers the move;
## the price is the graph km to the nearest OTHER region of its nation (the
## one transform -- no second distance invented), and the move lands on that
## nearest region: a firm relocates next door when it relocates at all. The
## register's `city` is the override; the authored city stays content.
static func _relocate(ns, loader, majors: Array, month: int) -> void:
	var city_region := {}
	var region_cities := {}
	for region in loader.regions.get(ns.id, []):
		region_cities[region.id] = true
		for city in region.cities:
			city_region[city.id] = region.id
	var graph: Dictionary = loader.region_graph
	var graph_key: int = graph.hash()
	if _dist_memo_graph != graph_key:
		_dist_memo.clear()
		_dist_memo_graph = graph_key
	for company in majors:
		if _failed(ns, company.id):
			continue
		var entry: Dictionary = ns.companies.get(company.id, {})
		if entry.is_empty():
			continue
		var current_region: String = String(city_region.get(live_city_of(ns, company), ""))
		if current_region == "" or not region_cities.has(current_region):
			continue
		if not _dist_memo.has(current_region):
			_dist_memo[current_region] = Net.distances_from(graph, current_region)
		var rows: Dictionary = _dist_memo[current_region]
		var best_km := INF
		var best_region := ""
		for region_id in region_cities.keys():
			if region_id == current_region:
				continue
			var km: float = float(rows.get(region_id, INF))
			if km < best_km:
				best_km = km
				best_region = region_id
		if best_region == "":
			continue
		# ONE draw, with the distance inside it: the monthly hazard discounted
		# by the move's price. A first draft drew twice -- hazard, then a
		# "price" gate at the same base -- which multiplied the probabilities
		# (p x p x discount) and left the machine dead by construction; the
		# mechanics test caught it as zero relocations in 240 months across
		# nine majors.
		var discount: float = maxf(1.0 - best_km / IK.RELOCATE_KM_SCALE, IK.RELOCATE_DISCOUNT_FLOOR)
		var p_monthly: float = IK.RELOCATE_HAZARD_YEARLY / 12.0 * discount
		if Cycle.unit("industry|%s|relocate" % company.id, month) >= p_monthly:
			continue
		var target := ""
		for region in loader.regions.get(ns.id, []):
			if region.id == best_region and not region.cities.is_empty():
				# The new city: the region's largest place, deterministic.
				var top = region.cities[0]
				for city in region.cities:
					if city.share > top.share:
						top = city
				target = top.id
				break
		if target == "":
			continue
		entry["city"] = target


# --- Failure --------------------------------------------------------------------

## base x (1 + 2 x burden + withdrawn + declining). A failed major's share is
## 0.0 -- to the unnamed residual, the first legal writer outside the subsidy
## pool -- its headcount reads 0 through Companies.headcount, and the register
## carries `failed` plus the rescue window. The window lapsing commits the
## failure; B2's strategic_rescue on a failing major clears the flag and
## restores the authored share.
static func _failures(ns, majors: Array, month: int) -> void:
	for company in majors:
		var entry: Dictionary = ns.companies.get(company.id, {})
		if entry.is_empty():
			continue
		var subsidy: float = Companies.subsidy_of(ns, company.id)
		var shadow: float = float(entry.get("subsidy_shadow", subsidy))
		var lapsed: int = int(entry.get("subsidy_lapsed_month", -1))
		if shadow > 0.0 and subsidy <= 0.0:
			lapsed = month
		entry["subsidy_shadow"] = subsidy
		entry["subsidy_lapsed_month"] = lapsed
		if _failed(ns, company.id):
			var left: int = int(entry.get("rescue_months_left", 0))
			if left > 0:
				entry["rescue_months_left"] = left - 1
			continue
		if float(entry.get("share", company.share)) <= 0.0:
			continue
		var withdrawn: float = IK.FAIL_WITHDRAWN_TERM if (lapsed >= 0 and month - lapsed <= IK.FAIL_WITHDRAWN_WINDOW_MONTHS) else 0.0
		var declining: float = IK.FAIL_DECLINE_TERM if float(EK.SECTOR_TREND.get(company.sector, 0.0)) < 0.0 else 0.0
		var burden: float = Companies.regulation_burden_of(ns, company.sector)
		var hazard: float = IK.FAIL_BASE_MONTHLY * (1.0 + IK.FAIL_BURDEN_WEIGHT * burden + withdrawn + declining)
		if Cycle.unit("industry|%s|fail" % company.id, month) >= hazard:
			continue
		entry["failed"] = true
		entry["share"] = 0.0
		entry["rescue_months_left"] = IK.RESCUE_WINDOW_MONTHS


## The majors in their rescue windows, for the surfaces and the verbs.
static func failing(state, ns) -> Array:
	var out: Array = []
	for company_id in ns.companies.keys():
		var entry: Dictionary = ns.companies[company_id]
		if bool(entry.get("failed", false)) and int(entry.get("rescue_months_left", 0)) > 0:
			out.append({
				"company_id": String(company_id),
				"months_left": int(entry.get("rescue_months_left", 0)),
			})
	return out


# --- Foreign bids ---------------------------------------------------------------

## A major draws interest; an eligible foreign rival (same sector, larger live
## share, not the firm's own nation and not the player's) makes the offer at
## the firm's derived value. Three scalars, one window, and an unanswered bid
## simply lapses. B1 opens and lapses only -- the answering verbs are B2's.
static func _bids(state, ns, loader, majors: Array, month: int) -> void:
	for company in majors:
		var entry: Dictionary = ns.companies.get(company.id, {})
		if entry.is_empty():
			continue
		var pending_bidder: String = String(entry.get("bid_bidder", ""))
		if pending_bidder != "":
			var left: int = int(entry.get("bid_months_left", 0))
			if left <= 1:
				entry["bid_bidder"] = ""
				entry["bid_price_eur_bn"] = 0.0
				entry["bid_months_left"] = 0
			else:
				entry["bid_months_left"] = left - 1
			continue
		if _failed(ns, company.id):
			continue
		# A courted firm draws interest at the multiplier the verb bought:
		# court_investor's flag is the player asking for exposure, and the
		# exposure is exactly that the takeover verbs become live.
		var p_monthly: float = IK.BID_HAZARD_YEARLY / 12.0
		if float(ns.companies.get(company.id, {}).get("courted", 0.0)) > 0.0:
			p_monthly *= IK.COURTED_BID_MULTIPLIER
		if Cycle.unit("industry|%s|bid" % company.id, month) >= p_monthly:
			continue
		var live: float = Companies.share_of_company(ns, company)
		var eligible: Array = []
		for other_id in state.nations.keys():
			if String(other_id) == ns.id or String(other_id) == state.player_nation_id:
				continue
			for other in Companies.majors_of(loader, String(other_id)):
				if other.sector != company.sector:
					continue
				var other_entry: Dictionary = state.nations[other_id].companies.get(other.id, {})
				if bool(other_entry.get("failed", false)):
					continue
				if Companies.share_of_company(state.nations[other_id], other) > live:
					eligible.append(String(other_id) + "|" + other.id)
		if eligible.is_empty():
			continue
		eligible.sort()
		var pick: String = eligible[int(Cycle.unit("industry|%s|bidder" % company.id, month) * float(eligible.size())) % eligible.size()]
		entry["bid_bidder"] = pick
		entry["bid_price_eur_bn"] = Companies.value_eur_bn(ns, company)
		entry["bid_months_left"] = IK.BID_WINDOW_MONTHS


## The open bid on this nation's register, if any: {company_id, bidder_id,
## price_eur_bn, months_left}. The verbs read this; the surfaces render it.
static func pending_bid(state, ns) -> Dictionary:
	for company_id in ns.companies.keys():
		var entry: Dictionary = ns.companies[company_id]
		var bidder: String = String(entry.get("bid_bidder", ""))
		if bidder == "":
			continue
		var parts := bidder.split("|")
		return {
			"company_id": String(company_id),
			"bidder_id": parts[parts.size() - 1],
			"bidder_nation": parts[0] if parts.size() > 1 else "",
			"price_eur_bn": float(entry.get("bid_price_eur_bn", 0.0)),
			"months_left": int(entry.get("bid_months_left", 0)),
		}
	return {}


# --- Reads the rest of the game borrows ----------------------------------------

## A failed firm employs nobody: the one branch the V1.4 headcount never
## needed, read through the same register every other read uses.
static func is_failed(ns, company_id: String) -> bool:
	return bool(ns.companies.get(company_id, {}).get("failed", false))


## The firm's LIVE city -- the relocation override when one stands, the
## authored content otherwise. headcount_in_city reads through this, so a
## move takes the payroll with it and Migration's pull follows for free.
static func live_city_of(ns, company) -> String:
	var entry: Dictionary = ns.companies.get(company.id, {})
	var city: String = String(entry.get("city", ""))
	return city if city != "" else String(company.city)


static func _failed(ns, company_id: String) -> bool:
	return bool(ns.companies.get(company_id, {}).get("failed", false))
