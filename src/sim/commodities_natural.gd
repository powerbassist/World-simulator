extends RefCounted

## The natural goods' market: the world pool's demand and the routing of each
## natural good across the roster and the pool. Moved verbatim out of
## commodities.gd (V5.0c) so that file could take the month-tick lever without
## growing past its size baseline; commodities.gd is still the only caller and
## the only writer of the registers these fill.

const K = preload("res://src/sim/commodity_constants.gd")


## The world pool's requirement for a good at this month's price, with commodities.gd's
## `_rows()` price response -- the outlines buy less of what grew dear.
static func pool_want(endowed: Dictionary, good_id: String, price: Dictionary, loader) -> float:
	var base := float(loader.commodity_goods[good_id].base_price)
	var p := float(price.get(good_id, base))
	return float(endowed["pool_base_want"].get(good_id, 0.0)) * pow(base / maxf(p, 1e-9), K.DEMAND_ELASTICITY)


## One natural good across the roster and the pool. Roster sellers offer their
## spare at TRADE_RATE to roster buyers first, in sorted id order; the pool then
## SELLS its whole net surplus to whoever is still short, or BUYS what roster
## sellers still offer up to its net shortfall. The pool trades its full net
## position because it is the rest of the world clearing against Europe, not one
## nation keeping a month's buffer (K.POOL_OFFER_RATE, argued at the constant).
static func route_natural(good_id: String, nation_ids: Array, capacities: Dictionary, required: Dictionary,
		endowed: Dictionary, price: Dictionary, loader, traded: Dictionary, spare_by_nation: Dictionary) -> void:
	var offered := {}
	for nation_id in nation_ids:
		var spare := float(capacities[nation_id][good_id]) - float(required[nation_id][good_id])
		if spare > 0.0:
			offered[nation_id] = spare * K.TRADE_RATE
			spare_by_nation[nation_id][good_id] = spare
	var pool_net := float(endowed["pool_capacity"].get(good_id, 0.0)) - pool_want(endowed, good_id, price, loader)
	var pool_offer := maxf(pool_net, 0.0) * K.POOL_OFFER_RATE
	var pool_need := maxf(-pool_net, 0.0) * K.POOL_OFFER_RATE
	for buyer in nation_ids:
		var want := float(required[buyer][good_id]) - float(capacities[buyer][good_id])
		if want <= 0.0:
			continue
		for seller in nation_ids:
			if want <= 0.0:
				break
			if not offered.has(seller):
				continue
			var moved: float = minf(want, float(offered[seller]))
			if moved <= 0.0:
				continue
			offered[seller] = float(offered[seller]) - moved
			want -= moved
			traded[seller][good_id] = float(traded[seller][good_id]) - moved
			traded[buyer][good_id] = float(traded[buyer][good_id]) + moved
		if want > 0.0 and pool_offer > 0.0:
			var from_pool: float = minf(want, pool_offer)
			pool_offer -= from_pool
			traded[buyer][good_id] = float(traded[buyer][good_id]) + from_pool
	for seller in nation_ids:
		if pool_need <= 0.0:
			break
		if not offered.has(seller):
			continue
		var sold: float = minf(pool_need, float(offered[seller]))
		if sold <= 0.0:
			continue
		offered[seller] = float(offered[seller]) - sold
		pool_need -= sold
		traded[seller][good_id] = float(traded[seller][good_id]) - sold


# --- V4.11b: real endowments and the world pool -----------------------------------
# docs/commodities-model.md section 8. Everything here is a pure function of the
# loader's content (authored nation figures, the outline register, the endowment
# shares), memoised with the recipe tables, so it adds no state and no save field.
#
# Moved here from commodities.gd with the V5.0c2 lever, verbatim but for the
# names; `category_sector` is commodities.gd's CATEGORY_SECTOR, passed in so this
# file keeps its one preload.

## {} when the loader carries no endowments (a fixture, or the pre-V4.11 model).
## Otherwise: "goods" (the endowed set), "capacity" {nation: {good: units/month}},
## "pool_capacity" and "pool_base_want" {good: units/month}.
##
## The WORLD VOLUME is the world's REQUIREMENT -- every roster nation's from its
## AUTHORED sector output through commodities.gd's `_bucket()` formula (what its industry
## processes), every outline's from its own GDP through the world sector mix --
## so the world opens balanced and the shares only decide who makes it.
static func endowment_tables(loader, structure: Dictionary, category_sector: Dictionary) -> Dictionary:
	var shares = loader.get("commodity_endowments")
	if not (shares is Dictionary) or (shares as Dictionary).is_empty():
		return {}
	var nations: Dictionary = loader.nations
	var nation_ids: Array = nations.keys()
	nation_ids.sort()
	var wss := authored_sector_share(loader, nation_ids)
	var outlines: Dictionary = loader.get("outlines") if loader.get("outlines") is Dictionary else {}
	var outline_value := 0.0
	for outline_id in outlines.keys():
		outline_value += maxf(float(outlines[outline_id]["gdp_eur_bn"]), 0.0) * 1e9 / 12.0

	var capacity := {}
	for nation_id in nation_ids:
		capacity[nation_id] = {}
	var pool_capacity := {}
	var pool_base_want := {}
	var endowed_goods := {}
	for good_id in (shares as Dictionary).keys():
		if not loader.commodity_goods.has(good_id):
			continue
		var good: Dictionary = loader.commodity_goods[good_id]
		var sector := String(category_sector.get(String(good.category), "industry"))
		var weight := float(structure.get(good_id, 0.0)) / float(good.base_price)
		var roster_need := 0.0
		for nation_id in nation_ids:
			var n = nations[nation_id]
			roster_need += float(n.gdp_eur_bn) * 1e9 / 12.0 * float(n.sectors.get(sector, 0.0)) * weight
		var outline_want := outline_value * float(wss.get(sector, 0.0)) * weight
		var world := roster_need + outline_want
		var good_shares: Dictionary = shares[good_id]
		var pool_share := 0.0
		for producer in good_shares.keys():
			var s := float(good_shares[producer])
			if nations.has(producer):
				capacity[producer][good_id] = s * world
			else:
				pool_share += s
		pool_capacity[good_id] = pool_share * world
		pool_base_want[good_id] = outline_want
		endowed_goods[good_id] = true
	return {
		"goods": endowed_goods,
		"capacity": capacity,
		"pool_capacity": pool_capacity,
		"pool_base_want": pool_base_want,
	}


## The world's sector mix as authored: each nation's measured GDP times its
## measured sector shares, summed and normalised. Empty when any nation in play
## has no authored record, so the caller falls back to the live mix.
static func authored_sector_share(loader, nation_ids: Array) -> Dictionary:
	var nations = loader.get("nations")
	if not (nations is Dictionary):
		return {}
	var weight := {}
	var total := 0.0
	for nation_id in nation_ids:
		if not nations.has(nation_id):
			return {}
		var n = nations[nation_id]
		var gdp := float(n.gdp_eur_bn)
		var sectors: Dictionary = n.sectors
		for sector in sectors.keys():
			var w := gdp * float(sectors[sector])
			weight[sector] = float(weight.get(sector, 0.0)) + w
			total += w
	if total <= 0.0:
		return {}
	for sector in weight.keys():
		weight[sector] = float(weight[sector]) / total
	return weight
