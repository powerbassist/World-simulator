extends RefCounted

## V5.3 c' (docs/design/v5.3-c-register.md section 5): a programme's overrun, one ask.
##
## DRAWN ONCE, AT THE VOTE (draw()): it falls when the programme's draw is under the
## odds its quote showed at tabling; then it lands in a seeded month of the build's
## middle third. A closure never overruns, a programme never has a second.
##
## THE CARD (tick()): posted in its month as p["ask"] = {kind, posted, due, default,
## eur_m, answers}, the process asks' shape (process_asks.gd), sized as the type's
## overrun_share of the capital still to pay. At most UNIT_OVERRUN_CARDS_A_YEAR cards in
## a calendar year; a further one waits for January. Posted only while more than its
## window of months is left to build, so every answer lands on a building programme.
## Unanswered at `due`, it is paid, and a note says why the bill rose.
##
## THE ANSWERS (outcome(), the card's figures and the register's write alike):
##   pay      the overrun spread over the months left: the bill rises;
##   shrink   each region's units cut in proportion, whole units, until the contract
##            and the overrun scaled to the units kept fit the contract; offered only
##            when a unit is left; the regions get less, the Union holds less;
##   delay    the overrun paid at the first rate over more months (the rate falls a
##            hair so the money is exact): the bill does not rise, the opening moves
##            back, and past the period's last payment year the Union's share is lost.

const UK = preload("res://src/sim/units_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const UnitEnvelope = preload("res://src/sim/unit_envelope.gd")

const NOTHING_WAITING := "Nothing here is waiting for an answer."
const NOT_AN_ANSWER := "That is not one of the answers."


## At the vote (UnitBuild.open): whether the overrun falls, and its month.
static func draw(ns, p: Dictionary) -> void:
	if String(p["op"]) != UK.OP_BUILD:
		return
	var seed := int(ns.draw_seed)
	if Cycle.unit(Cycle.salted("unit|%s|overrun" % String(p["id"]), seed), 0) >= float(p["odds"]):
		return
	var third := float(p["build_months"]) / 3.0
	var at := int(floorf(third + Cycle.unit(Cycle.salted("unit|%s|overrun_month" % String(p["id"]), seed), 0) * third))
	p["overrun"] = {"month": int(p["voted"]) + at}


## A month of the cards, after the month's payments: an unanswered card at its date is
## paid, then each overrun whose month has come is posted, inside the year's cap.
static func tick(state, ns, loader, now: int, notes: Array) -> void:
	for p in ns.unit_programmes:
		var ask: Dictionary = p.get("ask", {})
		if not ask.is_empty() and not p.has("answer") and now >= int(ask["due"]):
			answer(state, ns, loader, String(p["id"]), String(ask["default"]))
			notes.append({"kind": "overrun_defaulted", "id": String(p["id"]), "eur_m": float(ask["eur_m"])})
	for p in ns.unit_programmes:
		if not p.has("overrun") or p.has("ask") or String(p["state"]) != UK.STATE_BUILDING \
				or int(p["months_left"]) <= UK.UNIT_OVERRUN_WINDOW_MONTHS or now < int(p["overrun"]["month"]):
			continue
		# shortcut: a card held for January by the cap is dropped if by then no more than the
		# window is left to build (three short builds overrunning in one year); upgrade if
		# tools/units_probe.gd (U6) measures it.
		if _cards_in_year(ns, now) >= UK.UNIT_OVERRUN_CARDS_A_YEAR:
			continue
		var size := float(loader.unit_types[String(p["type"])]["overrun_share"]) * float(p["capital_month_eur_m"]) * int(p["months_left"])
		var answers: Array = []
		for id in [UK.OVERRUN_PAY, UK.OVERRUN_SHRINK, UK.OVERRUN_DELAY]:
			var o := outcome(state, ns, loader, p, id, size)
			if not o.is_empty():
				answers.append(o)
		p["ask"] = {"kind": "overrun", "posted": now, "due": now + UK.UNIT_OVERRUN_WINDOW_MONTHS,
			"default": UK.OVERRUN_PAY, "eur_m": size, "answers": answers}
		notes.append({"kind": "overrun_landed", "id": String(p["id"]), "eur_m": size})


## The forecast's copy blind to the draw (pass 1 on #421, ProcessAsks.blind's reason):
## Budget.project() runs the programmes on `sim`, and an overrun not yet posted would
## land there, showing in the projected bill whether it fell. On the copy only, a draw
## not yet on a card reads as none: the path of a programme that does not overrun.
static func blind(sim) -> void:
	for id in sim.nations:
		for p in sim.nations[id].unit_programmes:
			if p.has("overrun") and not p.has("ask"):
				p.erase("overrun")


## The cards waiting for an answer, oldest first, as copies.
static func asks(ns) -> Array:
	var out: Array = []
	for p in ns.unit_programmes:
		if p.has("ask") and not p.has("answer"):
			out.append((p as Dictionary).duplicate(true))
	return out


## One answer of the card, by id ({} when it does not offer it).
static func answer_of(p: Dictionary, answer_id: String) -> Dictionary:
	for a in (p.get("ask", {}) as Dictionary).get("answers", []):
		if String(a["id"]) == answer_id:
			return a
	return {}


## The player's answer (and the default's), applied at once: {ok} or {ok: false, reason}.
static func answer(state, ns, loader, programme_id: String, answer_id: String) -> Dictionary:
	var p := {}
	for row in ns.unit_programmes:
		if String(row["id"]) == programme_id:
			p = row
	if p.is_empty() or not p.has("ask") or p.has("answer") or String(p["state"]) != UK.STATE_BUILDING:
		return {"ok": false, "reason": NOTHING_WAITING}
	if answer_of(p, answer_id).is_empty():
		return {"ok": false, "reason": NOT_AN_ANSWER}
	var size := float(p["ask"]["eur_m"])
	var o := outcome(state, ns, loader, p, answer_id, size)
	p["capital_month_eur_m"] = float(o["capital_month_eur_m"])
	p["months_left"] = int(o["months_left"])
	p["rows"] = o["rows"]
	p["answer"] = answer_id
	p["overrun_eur_m"] = size
	if p.has("union"):
		p["union"]["reserved_eur_m"] = float(o["union_eur_m"])
	return {"ok": true}


## What answering `answer_id` now would make of `p`: {id, capital_month_eur_m,
## months_left, opens, units, rows, union_eur_m, union_lost}, or {} when not on offer.
static func outcome(state, ns, loader, p: Dictionary, answer_id: String, size: float) -> Dictionary:
	var rate := float(p["capital_month_eur_m"])
	var left := int(p["months_left"])
	var rows: Array = (p["rows"] as Array).duplicate(true)
	match answer_id:
		UK.OVERRUN_PAY:
			rate += size / left
		UK.OVERRUN_DELAY:
			var extra := int(ceilf(size / rate))
			rate = (rate * left + size) / float(left + extra)
			left += extra
		UK.OVERRUN_SHRINK:
			var contract := float(p["contract_eur_m"])
			var keep := contract / (contract + size)
			var voted := _units(rows)
			var kept: Array = []
			for r in rows:
				var units := int(floorf(float(r["units"]) * keep))
				if units > 0:
					r["units"] = units
					kept.append(r)
			if _units(kept) == 0:
				return {}
			var total := (float(p["paid_eur_m"]) + rate * left + size) * float(_units(kept)) / float(voted)
			rate = maxf(0.0, total - float(p["paid_eur_m"])) / left
			rows = kept
		_:
			return {}
	var opens := UnitPrice.now(state) + left
	var union := UnitEnvelope.after(loader, ns, p, rows, opens)
	return {"id": answer_id, "capital_month_eur_m": rate, "months_left": left, "opens": opens, "units": _units(rows),
		"rows": rows, "union_eur_m": float(union["eur_m"]), "union_lost": bool(union["lost"])}


static func _cards_in_year(ns, now: int) -> int:
	var n := 0
	for p in ns.unit_programmes:
		if p.has("ask") and UnitEnvelope.year_of(int(p["ask"]["posted"])) == UnitEnvelope.year_of(now):
			n += 1
	return n


static func _units(rows: Array) -> int:
	var n := 0
	for r in rows:
		n += int(r["units"])
	return n
