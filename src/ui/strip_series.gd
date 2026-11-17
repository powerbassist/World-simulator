extends RefCounted

## The curves under the top bar's tiles (V5.3, gate 3: the author's pick of top bar A,
## "tuiles avec courbes"): each standing figure history carries, over its last 18 months,
## in the units its tile prints. Read off state.history (Budget.snapshot), never computed
## anew: the money is the sim's own deficit share of GDP as euros a month, the same
## arithmetic budget.gd adds to the debt each month.

## A term and a half: long enough that a trend is a trend, short enough to stay this term's.
const MONTHS := 18

## The figures with a curve, in the strip's order.
const IDS: Array[String] = ["deficit", "gdp", "unemployment"]

## The narrowest range each curve is drawn over, in its tile's units (bn a month, points):
## without it a calm series fills the box like a cliff.
const MIN_SPAN := {"deficit": 2.0, "gdp": 0.6, "unemployment": 0.6}


## The month's balance in bn of euros, surplus positive: the deficit's share of GDP
## (spending less revenue, budget.gd) over twelve months of GDP.
static func balance_bn(deficit_pct_gdp: float, gdp_eur_bn: float) -> float:
	return -deficit_pct_gdp / 100.0 * gdp_eur_bn / 12.0


## `id`'s curve, oldest first, at most MONTHS long; empty under two months of history.
## The money curve follows the tile's figure: the deficit's size while the month is in
## deficit (rising is worse, as the figure reads), the surplus otherwise.
static func values(id: String, state) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if state == null or not IDS.has(id):
		return out
	var history: Array = state.history
	var from := maxi(history.size() - MONTHS, 0)
	var flip := 1.0
	if id == "deficit" and not history.is_empty():
		var last: Dictionary = history[-1]
		flip = -1.0 if balance_bn(float(last.get("deficit_pct_gdp", 0.0)), float(last.get("gdp_eur_bn", 0.0))) < 0.0 else 1.0
	for i in range(from, history.size()):
		var e: Dictionary = history[i]
		match id:
			"deficit":
				out.append(flip * balance_bn(float(e.get("deficit_pct_gdp", 0.0)), float(e.get("gdp_eur_bn", 0.0))))
			"gdp":
				out.append(float(e.get("growth_annual_pct", 0.0)))
			"unemployment":
				out.append(float(e.get("unemployment_pct", 0.0)))
	if out.size() < 2:
		return PackedFloat64Array()
	return out
