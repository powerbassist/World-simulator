extends RefCounted

## The natural goods' market: the world pool's demand and the routing of each
## natural good across the roster and the pool. Moved verbatim out of
## commodities.gd (V5.0c) so that file could take the month-tick lever without
## growing past its size baseline; commodities.gd is still the only caller and
## the only writer of the registers these fill.

const K = preload("res://src/sim/commodity_constants.gd")


## The world pool's requirement for a good at this month's price, with `_want`'s
## own price response -- the outlines buy less of what grew dear.
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
