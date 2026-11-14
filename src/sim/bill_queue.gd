extends RefCounted

## V5.3 e, PR 2: the queue of three (docs/design/finance-bill.md section 10; the author's
## call 2, "one vote a month, plus a queue of three bills in an order the player picks").
##
## The slot is unchanged: ns.tabled_bill holds the one bill that divides at the close
## ending its month. Behind it, ns.bill_queue holds up to SIZE entries, each what a
## tabling would carry: a law {law_id, scale, referendum, force} or the finance bill
## {finance: deltas, force}. The player's verbs here write ONLY the queue; nothing is
## checked against the Assembly until the bill reaches the slot.
##
## PROMOTION IS A TABLING. At the close, right after the division (WorldMonth's Division
## step), the head goes through the one tabling function that already exists,
## Legislature.propose or FinanceBill.table, so every check a tabling makes runs in the
## month the bill reaches the slot: a law no longer open, a referendum in flight, a
## constitutional bill forced, the autumn rule, the rate ranges. The caller has already
## moved the month, so a tabled head divides at the close that ends the new one.
##
## The parent's rulings (2026-11-14): a refused head is DROPPED, its refusal written to
## last_law_result as any refusal is, and the next tried, so the month's slot is not
## wasted (call 1); `force` rides in the entry and is engaged at promotion, refused then
## if the formation rule or the cooldown forbids it (call 2); the queue survives a fallen
## government, the new one's checks running at each promotion (call 3), which is why
## nothing outside this file clears it.
##
## Article 49.3 on a law adopts it at once and never takes the slot (propose's rule), so
## promotion goes on while the slot is empty: a forced law at the head is adopted and
## the next entry tabled in the same close. A forced finance bill IS tabled (it waits for
## the close), so it takes the slot like any other.

const Legislature = preload("res://src/sim/legislature.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")

## The author's number: three bills behind the month's one.
const SIZE := 3


## Queue `entry` at the back. Refused (writing nothing) when the queue holds SIZE, when the
## law is already queued or in the slot, or when a finance bill is already queued or
## tabled: one budget text at a time, the tabled one amended through FinanceBill.table.
static func add(state, entry: Dictionary) -> Dictionary:
	var ns = state.player()
	if ns.bill_queue.size() >= SIZE:
		return {"queued": false, "refused": true, "full": true}
	var held: Array = [ns.tabled_bill] + ns.bill_queue
	for other in held:
		if entry.has("finance") and (other.has("finance") or FinanceBillLaw.is_finance(String(other.get("law_id", "")))):
			return {"queued": false, "refused": true, "finance_queued": true}
		if not entry.has("finance") and String(other.get("law_id", "")) == String(entry.get("law_id", "")):
			return {"queued": false, "refused": true, "already_queued": true}
	ns.bill_queue.append(entry.duplicate(true))
	return {"queued": true, "position": ns.bill_queue.size() - 1}


## Take entry `i` out of the queue. False, and nothing changed, for an index outside it.
static func remove(state, i: int) -> bool:
	var ns = state.player()
	if i < 0 or i >= ns.bill_queue.size():
		return false
	ns.bill_queue.remove_at(i)
	return true


## Move entry `i` to position `j`, the others keeping their order. False, and nothing
## changed, when either index is outside the queue.
static func move(state, i: int, j: int) -> bool:
	var ns = state.player()
	var n: int = ns.bill_queue.size()
	if i < 0 or i >= n or j < 0 or j >= n:
		return false
	var entry = ns.bill_queue.pop_at(i)
	ns.bill_queue.insert(j, entry)
	return true


## The close's promotion: while the slot is empty, the head is tabled; a refused one is
## dropped and the next tried. Returns each tabling's result in order (the report's
## `queue`, from which the player is told), [] when nothing was queued.
static func promote(state, loader) -> Array:
	var ns = state.player()
	var out := []
	if ns == null:
		return out
	while ns.tabled_bill.is_empty() and not ns.bill_queue.is_empty():
		out.append(_table(state, loader, ns, ns.bill_queue.pop_front()))
	return out


static func _table(state, loader, ns, entry: Dictionary) -> Dictionary:
	var force := bool(entry.get("force", false))
	if entry.has("finance"):
		var bill: Dictionary = entry["finance"]
		var tabling := FinanceBill.table(state, loader, bill, force)
		if not bool(tabling.get("refused", false)):
			return tabling
		# FinanceBill.table's refusals write nothing and carry no id (the panel's own
		# press reads them at once). Dropped from the queue, the refusal is the player's
		# only record of the bill, so it goes on last_law_result under the id it would
		# have carried, with the deltas a panel can offer to table again.
		var result := Legislature.refused(ns, FinanceBillLaw.id_for(state), "", "finance")
		result.merge(tabling)
		result["finance_bill"] = bill.duplicate(true)
		return result
	var law_id := String(entry.get("law_id", ""))
	var law = Legislature.open_law(state, ns, loader, law_id)
	if law == null:
		return Legislature.refused(ns, law_id, "", "unavailable")
	return Legislature.propose(state, loader, law, force, bool(entry.get("referendum", false)), float(entry.get("scale", 1.0)))
