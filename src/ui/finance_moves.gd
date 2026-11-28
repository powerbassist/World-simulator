extends RefCounted

## The page's drafted share moves, in two places the draft cannot reach on its own -- V5.3 Finances slice 5. A move is
## not a row of the finance bill (it costs no money and needs no vote), so it is booked on the live nation the moment
## the footer's verb is pressed, whatever the tabling answers, and it rides the forecast the way the Budget's did.

const Sectors = preload("res://src/sim/sectors.gd")
const Forecast = preload("res://src/ui/budget_forecast.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const BillQueue = preload("res://src/sim/bill_queue.gd")
const FinanceQueue = preload("res://src/ui/finance_queue.gd")


## The footer's verb: the draft's rows tabled as the month's bill (none drafted, none tabled), or queued when another
## bill holds the slot (G2), then the moves booked whatever the tabling answered. FinanceBill.table's answer, with "rows"
## (a bill was put) and "moves" (how many booked); a queued bill adds "queued" and the "month" and "day" it divides.
static func table(state, loader, draft, force: bool) -> Dictionary:
	var rows: bool = not draft.is_empty()
	var tabling: Dictionary = FinanceBill.table(state, loader, draft.bill(), force) if rows else {"tabled": false}
	var lands: Dictionary = FinanceQueue.verb(state, "already_tabled", draft.bill()) if bool(tabling.get("already_tabled", false)) else {}
	if bool(lands.get("enabled", false)) and bool(BillQueue.add(state, {"finance": draft.bill(), "force": force}).get("queued", false)):
		tabling = {"tabled": false, "queued": true, "month": lands["month"], "day": lands["day"]}
	tabling["rows"] = rows
	tabling["moves"] = apply(state, loader, draft)
	return tabling


## The drafted moves booked on the live nation, in the order drafted, then dropped from the draft (a kept draft must not
## move the shares twice). Returns how many were booked.
static func apply(state, loader, draft) -> int:
	var booked := 0
	for m in draft.moves():
		if bool(Sectors.move_share(state.player(), loader, String(m["line"]), String(m["from"]), String(m["to"]), float(m["amount"])).get("ok", false)):
			booked += 1
	draft.clear_moves()
	return booked


## What the forecast projects: the priced pending, with the drafted moves riding on it (budget_forecast.gd takes them
## off and applies them to a copy, after the levers as the booking does).
static func wanted(pending: Dictionary, draft) -> Dictionary:
	if not draft.has_moves():
		return pending
	var out := pending.duplicate()
	out[Forecast.MOVES_KEY] = draft.moves()
	return out
