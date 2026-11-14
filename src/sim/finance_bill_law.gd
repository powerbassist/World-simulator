extends RefCounted

## The tabled finance bill as a Law (docs/design/finance-bill.md sections 2 and 3): its
## id, its position on the two axes, and the Law object every reader of a tabled bill
## already knows how to read (the forecast, Address, Deal, the law surfaces). A LEAF:
## Bills preloads it, and Bills is preloaded by legislature.gd, so this file preloads
## only constants and the core Law factory -- never finance_bill.gd or legislature.gd.

const Law = preload("res://src/core/law.gd")
const FK = preload("res://src/sim/finance_bill_constants.gd")
const SK = preload("res://src/sim/statute_constants.gd")

## One id per tabling, `finance:<year * 12 + month>`, so a pledge, an address or a poll
## on this year's bill never attaches to next year's.
const PREFIX := "finance:"


static func is_finance(law_id: String) -> bool:
	return law_id.begins_with(PREFIX)


static func id_for(state) -> String:
	return PREFIX + str(int(state.year) * 12 + int(state.month))


## A finance bill by id alone, for its name: no register, so no position (Bills.by_id).
static func named(law_id: String):
	return Law.composed_from_dict({"id": law_id, "name": FK.BILL_NAME, "theme": "tax", "majority": "simple", "origin": "player"})


## The register's finance bill as a Law, or null when the register holds none. Not listed
## in Bills.open: the law list's forecast reads the law whip, and this bill's reading is
## FinanceBill.resolve()'s (the review of #331).
static func tabled(ns):
	var entry: Dictionary = ns.tabled_bill
	if not is_finance(String(entry.get("law_id", ""))):
		return null
	return law(ns, entry)


## A finance bill as a Law: simple majority, no cooldown, no effects of its own (the
## division applies the deltas through Budget, never Legislature.apply: a budget is not
## an act on the statute book), so its reach is 0 and no court strikes it.
static func law(ns, entry: Dictionary):
	return Law.composed_from_dict({
		"id": String(entry.get("law_id", "")),
		"name": FK.BILL_NAME,
		"theme": "tax",
		"position": position(ns, entry.get("finance", {})),
		"majority": "simple",
		"origin": "player",
	})


## The coalition's agreed position, moved toward the size-weighted mean of the lines'
## anchors by t = min(1, size / REF_SIZE). A balanced budget averages toward the
## centre: its pain is the opinion model's, which prices each line per bloc.
static func position(ns, bill: Dictionary) -> Dictionary:
	var centroid: Dictionary = ns.coalition_position
	var size := 0.0
	var econ := 0.0
	var social := 0.0
	var rows: Array = []
	for channel in ["tax_rates_pct", "spending_pct_gdp"]:
		for key in bill.get(channel, {}):
			rows.append([channel, String(key), float(bill[channel][key]), float(SK.CHANNEL_COST[channel])])
	# V5.3 e: a birth reads as its kind's rise from nothing, an abolition as a cut to zero.
	for kind in bill.get("create", {}):
		rows.append(["tax_rates_pct", String(kind), float(bill["create"][kind]), float(SK.CHANNEL_COST["tax_rates_pct"])])
	for kind in bill.get("abolish", []):
		rows.append(["tax_rates_pct", String(kind), -float(ns.tax_rates_pct.get(kind, 0.0)), float(SK.CHANNEL_COST["tax_rates_pct"])])
	if bill.has("tax_progressivity"):
		rows.append(["tax_rates_pct", FK.FALLBACK_TAX_KEY, float(bill["tax_progressivity"]) * FK.PROGRESSIVITY_INCOME_POINTS,
			float(SK.CHANNEL_COST["tax_rates_pct"])])
	for row in rows:
		var value: float = row[2]
		if value == 0.0:
			continue
		# A tax kind's anchor is its library row's (V5.3 e); a spending line's is FK's.
		var spend: bool = row[0] == "spending_pct_gdp"
		var table: Dictionary = FK.ANCHOR[row[0]] if spend else ns.tax_library
		var key: String = row[1] if table.has(row[1]) else FK.FALLBACK_TAX_KEY
		var sides: Dictionary = table[key] if spend else table[key]["finance_anchor"]
		var anchor: Dictionary = sides["up" if value > 0.0 else "down"]
		var weight: float = absf(value) * float(row[3])
		econ += weight * float(anchor["economic"])
		social += weight * float(anchor["social"])
		size += weight
	if size == 0.0:
		return {"economic": float(centroid["economic"]), "social": float(centroid["social"])}
	var t := minf(1.0, size / FK.REF_SIZE)
	return {
		"economic": float(centroid["economic"]) + t * (econ / size - float(centroid["economic"])),
		"social": float(centroid["social"]) + t * (social / size - float(centroid["social"])),
	}
