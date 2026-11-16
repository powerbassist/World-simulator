extends RefCounted

## What a sector makes, good by good -- V5.3 screen 5, slice 1 (the author's C, "les
## produits"). A read over GoodsRead.table() (src/sim/goods_read.gd: the price now, the
## world price ring, this month's trade) and the firm register's `products`. The
## Commodities tab retired into this: its shortage line moved here with it (the strip's
## Supplies figure and the outliner read it), its balance table became these rows, and
## its recipe tree has no home in C and was cut.
##
## WHICH SECTOR A GOOD IS: its category, by content. `agri` is agriculture, `services`
## is services, every other category (raw, energy, intermediate, capital, consumer) is
## industry: a mine, a refinery and a car plant are all industry in the three sectors
## the sim models (nations/*.json `sectors`).
##
## WHICH GOODS A TAB SHOWS, by rule rather than a hand list (industry alone holds 43
## goods): those the nation made or traded this month, one of its majors makes, or one
## short of demand. In
## order: a good under the shortage line first (the strip's Go lands on its row), then
## the majors' products in the register's order, then the rest by the value made this
## month. At most MAX_ROWS, the rest counted.

const GoodsRead = preload("res://src/sim/goods_read.gd")
const Companies = preload("res://src/sim/companies.gd")
const Strings = preload("res://src/ui/strings.gd")

## Categories that are not industry's, by the sector they belong to.
const SECTOR_OF_CATEGORY := {"agri": "agriculture", "services": "services"}

## Rows a tab shows before it counts the rest ("and N more").
const MAX_ROWS := 8

## When a good reads as short: the value of what the country made plus what it bought,
## against the value of what it wanted, below this fraction. 0.25 IS MEASURED (V4.6,
## the 29-nation roster): France steadies at two alerts by month 12 (cotton, uranium
## ore); at 0.75 the same readout flags twenty-four goods, a wall rather than an alert.
## A presentation threshold the simulation never sees, so it lives beside its readers.
const SHORTAGE_COVERAGE := 0.25


## The sector a good belongs to, "" for a good the loader does not know.
static func sector_of_good(loader, good_id: String) -> String:
	var good = loader.commodity_goods.get(good_id)
	if good == null:
		return ""
	return String(SECTOR_OF_CATEGORY.get(String(good.category), "industry"))


## The price change over the months the ring holds, in percent; NAN under two months.
static func price_change(series: Array) -> float:
	if series.size() < 2 or float(series[0]) <= 0.0:
		return NAN
	return 100.0 * (float(series[-1]) / float(series[0]) - 1.0)


## The rows a sector's tab shows, in the order above: {good_id, name, change, months,
## trade_eur_bn_year, makers (major companies), short}. `rows_all()` is the uncut list.
static func rows(state, loader, ns, sector: String) -> Array:
	return rows_all(state, loader, ns, sector).slice(0, MAX_ROWS)


static func rows_all(state, loader, ns, sector: String) -> Array:
	var makers := {}
	var major_order: Array = []
	for company in Companies.firms_in_sector(loader, ns.id, sector):
		if not Companies.is_major(company):
			continue
		for good_id in company.products:
			if not makers.has(good_id):
				makers[good_id] = []
				major_order.append(good_id)
			makers[good_id].append(company)
	var out: Array = []
	var cs: Dictionary = ns.commodity_state
	for row in GoodsRead.table(state, ns):
		var good_id := String(row["good_id"])
		if sector_of_good(loader, good_id) != sector:
			continue
		var made := float((cs.get("output", {}) as Dictionary).get(good_id, 0.0))
		var short := coverage(ns, good_id) < SHORTAGE_COVERAGE
		if not short and not makers.has(good_id) and made <= 0.0 and is_zero_approx(float(row["trade_units"])):
			continue
		var good = loader.commodity_goods.get(good_id)
		out.append({
			"good_id": good_id, "name": Strings.row_name("goods", good), "change": price_change(row["series"]),
			"months": int(row["months"]), "trade_eur_bn_year": float(row["trade_eur_bn_year"]),
			"makers": makers.get(good_id, []), "short": short,
			"rank": major_order.find(good_id), "value": made * float(row["price"]),
		})
	out.sort_custom(func(a, b) -> bool:
		if bool(a["short"]) != bool(b["short"]):
			return bool(a["short"])
		var ra := int(a["rank"])
		var rb := int(b["rank"])
		if (ra >= 0) != (rb >= 0):
			return ra >= 0
		if ra >= 0:
			return ra < rb
		if not is_equal_approx(float(a["value"]), float(b["value"])):
			return float(a["value"]) > float(b["value"])
		return String(a["good_id"]) < String(b["good_id"]))
	return out


## How much of the month's want this nation covered, from its own production plus
## what it bought. Clamped at 0 so an overshoot reads as 0 short rather than
## negative, and 1.0 where nothing was wanted -- a good nobody wants is not short.
static func coverage(ns, good_id: String) -> float:
	var cs: Dictionary = ns.commodity_state
	if cs.is_empty():
		return 1.0
	var want := float((cs.get("demand", {}) as Dictionary).get(good_id, 0.0))
	if want <= 0.0:
		return 1.0
	var made := float((cs.get("output", {}) as Dictionary).get(good_id, 0.0))
	var bought := maxf(0.0, float((cs.get("trade", {}) as Dictionary).get(good_id, 0.0)))
	return clampf((made + bought) / want, 0.0, 1.0)


## The goods under the shortage line, worst first and then by id so two equal figures
## have a total order. ONE implementation: the sector tabs, the strip's Supplies figure
## and its breakdown, and the outliner all read it, so they cannot disagree about
## which good is worst (V4.8b review).
static func shortages(ns, good_ids: Array) -> Array:
	var short: Array = []
	for good_id in good_ids:
		var covered := coverage(ns, String(good_id))
		if covered < SHORTAGE_COVERAGE:
			short.append({"id": String(good_id), "coverage": covered})
	short.sort_custom(func(a, b) -> bool:
		if not is_equal_approx(float(a["coverage"]), float(b["coverage"])):
			return float(a["coverage"]) < float(b["coverage"])
		return String(a["id"]) < String(b["id"]))
	return short


## The tab a good's shortage Go opens: its sector's (SectorNeeds.TABS).
static func tab_of_good(loader, good_id: String) -> String:
	var sector := sector_of_good(loader, good_id)
	return "sector_" + sector if sector != "" else ""
