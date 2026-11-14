extends RefCounted

## V5.3 e PR B (docs/design/finance-bill.md section 13, calls 5 and 6 (a)): the goods
## screen's reads over the commodity layer, which keeps only this month per nation
## (`ns.commodity_state`). Written only: nothing in the sim reads the ring back.
##
##   the ring   `state.commodity_price_history`, {good_id: [EUR per unit, ...]}, the
##              ONE world price vector over the last twelve months (src/sim/series.gd).
##              Kept once on GameState because every nation holds a copy of the same
##              vector (call 5); recorded at WorldMonth's Commodities step, so a
##              harness that ticks Commodities alone, and the budget projection's
##              copy, which has no past, write none.
##   the table  per good, the price now, the series held, this month's trade in units
##              (bought positive) and the same trade as EUR bn a year (sold positive).
##              The trade has no series (call 6): the screen labels it "this month".

const Series = preload("res://src/sim/series.gd")


## Append this month's world price to the ring. The vector is read off the first
## nation (sorted) that holds one: Commodities writes the same figures into each.
static func record(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var price: Dictionary = state.nations[id].commodity_state.get("price", {})
		if price.is_empty():
			continue
		var goods: Array = price.keys()
		goods.sort()
		for good_id in goods:
			if not state.commodity_price_history.has(good_id):
				state.commodity_price_history[good_id] = []
			Series.push(state.commodity_price_history[good_id], float(price[good_id]))
		return


## Months the ring holds, 0 to Series.MONTHS. Every good is pushed in the same month,
## so any good's length is the ring's.
static func months_held(state) -> int:
	for good_id in state.commodity_price_history:
		return (state.commodity_price_history[good_id] as Array).size()
	return 0


## One row per good the nation's register holds, sorted by good id:
## {good_id, price, series, months, trade_units, trade_eur_bn_year}. `series` is a
## copy; `months` is its length. Empty for a nation with no commodity register.
static func table(state, ns) -> Array:
	var out: Array = []
	var cs: Dictionary = ns.commodity_state
	if cs.is_empty():
		return out
	var goods: Array = (cs["price"] as Dictionary).keys()
	goods.sort()
	for good_id in goods:
		var series: Array = (state.commodity_price_history.get(good_id, []) as Array).duplicate()
		var price := float(cs["price"][good_id])
		var units := float(cs["trade"].get(good_id, 0.0))
		out.append({
			"good_id": String(good_id), "price": price, "series": series, "months": series.size(),
			"trade_units": units, "trade_eur_bn_year": trade_eur_bn_year(units, price),
		})
	return out


## A month's trade in units, bought positive, as EUR bn a year, sold positive.
static func trade_eur_bn_year(units: float, price: float) -> float:
	return -units * price * 12.0 / 1e9


## The value of what a nation buys from abroad over the value of everything it
## wants, both at the live price. Moved here from src/ui/map_layers.gd (V5.3 e PR B),
## which now calls it: it is a sim read, and the goods screen reads its sides.
## VALUE rather than a unit count, and that is a measurement's call: a tonne of ore
## and a tonne of semiconductors are not comparable quantities, and an unweighted
## count of units would report a nation that imports only cheap ore perfectly as
## dependent as one that imports only aircraft. The live price is what makes the
## two commensurable.
##
## Defined on what the nation BOUGHT (the positive half of `trade`) rather than on
## what it wants and did not make, so the figure answers the question the layer's
## name asks: what actually crossed a border to get here. `maxf(0.0, ...)` because
## `trade` is signed -- a negative entry is a sale and belongs on the export side
## of the panel, not in a dependency reading.
static func import_dependency(state, nation_id: String) -> float:
	var cs: Dictionary = state.nations[nation_id].commodity_state
	if cs.is_empty():
		return 0.0
	var want := 0.0
	var bought := 0.0
	for good_id in (cs["demand"] as Dictionary).keys():
		var price := float(cs["price"].get(String(good_id), 0.0))
		want += float(cs["demand"][good_id]) * price
		bought += maxf(0.0, float(cs["trade"].get(String(good_id), 0.0))) * price
	if want <= 0.0:
		return 0.0
	return clampf(bought / want, 0.0, 1.0)
