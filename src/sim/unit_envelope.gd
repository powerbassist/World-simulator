extends RefCounted

## V5.3 c' (docs/design/v5.3-c-register.md section 6): the Union's envelope.
##
## WHO AND WHAT. A member of an organisation of data/units/cofinancing.json (the
## nation's own `orgs`, Orgs.is_member's register) building units of a `cofinanced`
## type. The Union pays the rate of each region's cohesion category on that row's share
## of the estimate; a region with no category reads 0 %.
##
## THE ENVELOPE. The period whose first_year..last_year holds the vote's year, at
## UNIT_ENVELOPE_GAME_SHARE of the nation's real allocation, and for the period under
## way when the game starts (Clock.START_YEAR) at its years left over its years. What is
## left = the envelope less every programme's reservation still held and what was paid.
##
## ITS LIFE ON A PROGRAMME, as p["union"] = {org, period, pays_until, reserved_eur_m,
## paid_eur_m, months_left}:
##   the vote     reserve(): the rate share of the estimate, capped by what is left. A
##                build that cannot open by pays_until_year has no Union line at all;
##   an answer    after(): a shrink keeps the share of the units still built (gives the
##                rest back), a delay past pays_until_year loses it;
##   the opening  opening(): due = the rate share of the CONTRACT, never above the
##                reservation (a price above the estimate and an overrun are the
##                nation's alone); an opening after pays_until_year is paid nothing;
##   the year on  receipts(): due over UNIT_RECEIPT_MONTHS from the month after; it
##                runs every month after the openings, so a nation that has left the
##                organisation is released there, at its opening or mid-payment alike.
## The receipt is ns.unit_receipt_pct_gdp, which Budget SUBTRACTS from the spending.
## The spec named the transfer line (bloc_transfer_pct_gdp); that line is Orgs' own,
## rewritten every month from the org's net position, so a second writer there would be
## overwritten -- the receipt is its own field, read in the same sum with the opposite sign.
##
## THE WARNING. warn_months before pays_until_year ends, one note names what is about to
## lapse: what is left unreserved, and the reservations of builds that will open too late.

const UK = preload("res://src/sim/units_constants.gd")
const GameClock = preload("res://src/core/clock.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const Units = preload("res://src/sim/units.gd")


## The absolute month's year (UnitPrice.now's months: year x 12 + month).
static func year_of(month: int) -> int:
	return floori(float(month - 1) / 12.0)


## The first organisation of the rule the nation belongs to, "" for none.
static func org_of(loader, ns) -> String:
	var ids: Array = loader.unit_cofinancing.keys()
	ids.sort()
	for org_id in ids:
		if ns.orgs.has(String(org_id)):
			return String(org_id)
	return ""


static func period_of(loader, org_id: String, year: int) -> Dictionary:
	for p in loader.unit_cofinancing.get(org_id, {}).get("periods", []):
		if int(p["first_year"]) <= year and year <= int(p["last_year"]):
			return p
	return {}


## The period's envelope in the game, M EUR: the declared share of the real one, and
## for the period under way at the start, the years left over its years.
static func envelope_eur_m(period: Dictionary, nation_id: String) -> float:
	var years := int(period["last_year"]) - int(period["first_year"]) + 1
	# The years from the start to the period's end, never more than its own: a later
	# period is whole, one ended before the start is nothing.
	var left := clampi(int(period["last_year"]) - GameClock.START_YEAR + 1, 0, years)
	return float(period["envelope_eur_bn"].get(nation_id, 0.0)) * 1000.0 * UK.UNIT_ENVELOPE_GAME_SHARE * float(left) / float(years)


## What is left of the envelope of the period holding `year`, M EUR (0 for a
## non-member or a year with no period).
static func left_eur_m(loader, ns, year: int) -> float:
	var org_id := org_of(loader, ns)
	var period := period_of(loader, org_id, year)
	if period.is_empty():
		return 0.0
	return maxf(0.0, envelope_eur_m(period, ns.id) - _held(ns, org_id, String(period["id"])))


## At the vote, before `p` joins the register: its reservation, when it has a Union line
## (none when nothing is left: a reservation of 0 is no Union money, and no line).
static func reserve(loader, ns, p: Dictionary) -> void:
	var t: Dictionary = loader.unit_types[String(p["type"])]
	if String(p["op"]) != UK.OP_BUILD or not bool(t.get("cofinanced", false)):
		return
	var org_id := org_of(loader, ns)
	var period := period_of(loader, org_id, year_of(int(p["voted"])))
	if period.is_empty() or year_of(UnitPrice.opens_at(p)) > int(period["pays_until_year"]):
		return
	var reserved := minf(_want(loader, org_id, ns, p, p["rows"]), left_eur_m(loader, ns, year_of(int(p["voted"]))))
	if reserved <= 0.0:
		return
	p["union"] = {"org": org_id, "period": String(period["id"]), "pays_until": int(period["pays_until_year"]),
		"reserved_eur_m": reserved, "paid_eur_m": 0.0, "months_left": 0}


## What the Union would still hold for `p` built as `rows`, opening in month `opens`:
## {eur_m, lost}. Never more than the reservation.
static func after(loader, ns, p: Dictionary, rows: Array, opens: int) -> Dictionary:
	var u: Dictionary = p.get("union", {})
	if u.is_empty():
		return {"eur_m": 0.0, "lost": false}
	var reserved := float(u["reserved_eur_m"])
	if year_of(opens) > int(u["pays_until"]):
		return {"eur_m": 0.0, "lost": reserved > 0.0}
	return {"eur_m": minf(reserved, _want(loader, String(u["org"]), ns, p, rows)), "lost": false}


## The month `p` opened (`now`): what the Union owes it, or the lapse.
static func opening(loader, ns, p: Dictionary, now: int, notes: Array) -> void:
	var u: Dictionary = p.get("union", {})
	if u.is_empty():
		return
	if year_of(now) > int(u["pays_until"]):
		if float(u["reserved_eur_m"]) > 0.0:
			notes.append({"kind": "union_lapsed", "id": String(p["id"]), "eur_m": float(u["reserved_eur_m"])})
		u["reserved_eur_m"] = 0.0
		return
	var share := float(p["contract_eur_m"]) / float(p["estimate_eur_m"]) if float(p["estimate_eur_m"]) > 0.0 else 0.0
	u["reserved_eur_m"] = minf(float(u["reserved_eur_m"]), _want(loader, String(u["org"]), ns, p, p["rows"]) * share)
	u["months_left"] = UK.UNIT_RECEIPT_MONTHS


## The month's receipts, M EUR: each opened programme's due in equal parts, from the
## month after its opening. A nation no longer in the organisation (TAKE 2 on #421) holds
## nothing and receives nothing more: what was paid stays paid.
static func receipts(ns, now: int) -> float:
	var total := 0.0
	for p in ns.unit_programmes:
		var u: Dictionary = p.get("union", {})
		if not u.is_empty() and not ns.orgs.has(String(u["org"])):
			u["reserved_eur_m"] = 0.0
			u["months_left"] = 0
		if u.is_empty() or int(u.get("months_left", 0)) <= 0 or int(p.get("opened", now)) >= now:
			continue
		var pay := float(u["reserved_eur_m"]) / int(u["months_left"])
		u["reserved_eur_m"] = float(u["reserved_eur_m"]) - pay
		u["paid_eur_m"] = float(u["paid_eur_m"]) + pay
		u["months_left"] = int(u["months_left"]) - 1
		total += pay
	return total


## The note warn_months before the end of a period's LAST VOTE YEAR (TAKE 5 on #421, the
## parent's ruling): what can still be reserved then -- only when a type the nation
## builds, voted now, would still open by the last payment year -- and the reservations
## of builds that will open after it. Never money nobody can reserve.
static func warn(loader, ns, now: int, notes: Array) -> void:
	var org_id := org_of(loader, ns)
	if org_id == "":
		return
	var rule: Dictionary = loader.unit_cofinancing[org_id]
	for period in rule["periods"]:
		var last := int(period["last_year"])
		if now != last * 12 + 12 - int(rule["warn_months"]) + 1:
			continue
		var until := int(period["pays_until_year"])
		var lapsing := 0.0
		if _usable(loader, ns, now, until):
			lapsing = maxf(0.0, envelope_eur_m(period, ns.id) - _held(ns, org_id, String(period["id"])))
		for p in ns.unit_programmes:
			var u: Dictionary = p.get("union", {})
			if String(u.get("period", "")) == String(period["id"]) and String(p["state"]) == UK.STATE_BUILDING \
					and year_of(UnitPrice.opens_at(p)) > until:
				lapsing += float(u["reserved_eur_m"])
		if lapsing > 0.0:
			notes.append({"kind": "lapse_warning", "org": org_id, "period": String(period["id"]), "eur_m": lapsing,
				"year": last, "pays_until": until})


## Whether a cofinanced type the nation builds, voted in month `now`, opens by `until`.
static func _usable(loader, ns, now: int, until: int) -> bool:
	for type_id in loader.unit_types:
		var t: Dictionary = loader.unit_types[type_id]
		if bool(t.get("cofinanced", false)) and Units.offered(loader, ns.id, String(type_id)) \
				and year_of(now - 1 + int(t["build_months"])) <= until:
			return true
	return false


static func _held(ns, org_id: String, period_id: String) -> float:
	var held := 0.0
	for p in ns.unit_programmes:
		var u: Dictionary = p.get("union", {})
		if String(u.get("org", "")) == org_id and String(u.get("period", "")) == period_id:
			held += float(u["reserved_eur_m"]) + float(u["paid_eur_m"])
	return held


## The rate share of `rows`' estimate: each row's units at the price its region was
## quoted (the surcharge the vote fixed), times its category's rate.
static func _want(loader, org_id: String, ns, p: Dictionary, rows: Array) -> float:
	var cost := float(loader.unit_types[String(p["type"])]["cost_eur_m"][ns.id])
	var rates: Dictionary = loader.unit_cofinancing[org_id]["rates"]
	var category := {}
	for r in loader.regions.get(ns.id, []):
		category[r.id] = r.cohesion_category
	var want := 0.0
	for r in rows:
		var region := String(r["region"])
		want += float(rates.get(String(category.get(region, "")), 0.0)) * float(r["units"]) * cost \
			* (1.0 + float(p.get("surcharge", {}).get(region, 0.0)))
	return want
