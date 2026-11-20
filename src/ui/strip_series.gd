extends RefCounted

## The curves under the top bar's tiles (V5.3, gate 3: the author's pick of top bar A,
## "tuiles avec courbes"): each standing figure history carries, over its last 18 months.
## Read off state.history (Budget.snapshot), never computed anew: the money is the sim's
## own deficit share of GDP as euros a month, the arithmetic budget.gd adds to the debt.
##
## The money curve is the SIGNED balance, surplus up (the parent's rule at #418 pass 2): a
## growing deficit draws down, the zero line is drawn, and nothing flips at a crossing. The
## caption word and the unsigned figure beside it follow the live sign.

## A term and a half: long enough that a trend is a trend, short enough to stay this term's.
const MONTHS := 18

## The figures with a curve, in the strip's order.
const IDS: Array[String] = ["deficit", "gdp", "unemployment", "inflation"]

## The history field each curve reads (the money reads two, below).
const KEYS := {"gdp": "growth_annual_pct", "unemployment": "unemployment_pct", "inflation": "inflation_pct"}


## The month's balance in bn of euros, surplus positive: the deficit's share of GDP
## (spending less revenue, budget.gd) over twelve months of GDP.
static func balance_bn(deficit_pct_gdp: float, gdp_eur_bn: float) -> float:
	return -deficit_pct_gdp / 100.0 * gdp_eur_bn / 12.0


## The balance a history entry records, NAN when it lacks either field (an older save's
## entry): a missing month is skipped, never drawn as a zero.
static func entry_balance(entry: Dictionary) -> float:
	if not entry.has("deficit_pct_gdp") or not entry.has("gdp_eur_bn"):
		return NAN
	return balance_bn(float(entry["deficit_pct_gdp"]), float(entry["gdp_eur_bn"]))


## `id`'s curve, oldest first, at most MONTHS long, months lacking the field left out;
## empty under two points.
static func values(id: String, state) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if state == null or not IDS.has(id):
		return out
	var history: Array = state.history
	for i in range(maxi(history.size() - MONTHS, 0), history.size()):
		var e: Dictionary = history[i]
		var v := entry_balance(e) if id == "deficit" else (float(e[KEYS[id]]) if e.has(KEYS[id]) else NAN)
		if not is_nan(v):
			out.append(v)
	if out.size() < 2:
		return PackedFloat64Array()
	return out
