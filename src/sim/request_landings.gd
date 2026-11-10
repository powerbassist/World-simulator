extends RefCounted

## A request's answers and where each would leave the person -- Audiences' leaf.
## `answers` and `decline_price` moved here from audiences.gd at V5.3 B7 (the size
## ratchet: audiences.gd had no room), unchanged; audiences.gd keeps them public by
## their old names, over a request id.
##
## `landings` and `differs` are the V5.3 B7 question the author ruled on (2026-11-10):
## does a request offer a real choice, i.e. do two of its open answers leave the person
## in different feeling words? The cuts are src/sim/feeling_constants.gd's, the ones
## the card draws its words with, so the quiet-month call (Audiences stamps `differs`
## on each request the month brings) and the density probe (which counts with
## `landings`) share one definition. A request whose three answers all read the same
## is not an arrival for the quiet rule: the call still fires.
##
## Every answer is priced as the commands price it: booking the rapport an audience
## gives, delegation the snub and a share of a decline's grudge and loyalty, a decline
## (or a lapse) decline_price below.

const K = preload("res://src/sim/audience_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const President = preload("res://src/sim/president.gd")
const Dates = preload("res://src/sim/audience_dates.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const Delegation = preload("res://src/sim/delegation.gd")
const FK = preload("res://src/sim/feeling_constants.gd")


## The card's three answers. Booking needs a waiting request and an offered day
## the diary can place; delegation and decline are open on every open request,
## booked included -- the commands accept both, and a booked day is given back
## (B2's 100 %). Delegate also carries the cabinet's odds of keeping the word and
## why none can (V5.3-0 gate: Delegation.odds' {chance, why, effectiveness,
## loyalty}), so the player sees the risk before handing it over; it stays open
## even at chance 0, B2's row.
static func answers(state, ns, loader, row: Dictionary) -> Dictionary:
	if row.is_empty() or not K.OPEN.has(String(row["status"])):
		var closed := {"ok": false, "reason": "this request is no longer waiting"}
		return {"book": closed, "delegate": closed, "decline": closed}
	var open := {"ok": true, "reason": ""}
	var delegate := open.merged(Delegation.odds(ns, loader, String(row["object"]), String(row.get("stance", ""))))
	if String(row["status"]) == K.STATUS_BOOKED:
		return {"book": {"ok": false, "reason": "already booked"}, "delegate": delegate, "decline": open}
	var book := {"ok": false, "reason": "none of the days offered is free"}
	for date in Dates.offered(state, ns, row):
		if bool(date["free"]):
			book = {"ok": true, "reason": ""}
			break
	return {"book": book, "delegate": delegate, "decline": open}


## What a decline writes on the person's card now, through the same ceiling the
## price pays: the card names it (B3). An accomplice's broken word is in it (c1c,
## rule 1), flagged `broken_word` so the card can say why; one summed pulse under the
## room clamp is the two pulses exactly. `share` scales the decline's own part and
## never the broken word, as Audiences' lapse does: lapse_price below is the caller.
static func decline_price(ns, loader, row: Dictionary, share := 1.0) -> Dictionary:
	var person = loader.person_by_id.get(String(row.get("person_id", "")))
	var crossed: bool = person != null and President.holds_evidence(ns, String(person.id), int(row.get("arrived_month", 0)))
	var pulse: float = K.DECLINE_GRUDGE * share + (LK.LIE_GRUDGE if crossed else 0.0)
	var grudge: float = Characters.refusal_grudge(ns, person, pulse) if person != null else K.DECLINE_GRUDGE * share
	var price := {"grudge": grudge, "loyalty": K.DECLINE_LOYALTY * share, "rapport": K.DECLINE_RAPPORT * share - (LK.LIE_RAPPORT if crossed else 0.0)}
	if crossed:
		price["broken_word"] = true
	return price


## The share of a decline a lapse or a no-show costs: CALLED_LAPSE_SHARE for a request
## the quiet-month call brought, the whole decline for one the person asked for. One
## definition for the lapse (audiences.gd) and the card (lapse_price), so they agree.
static func lapse_share(row: Dictionary) -> float:
	return K.CALLED_LAPSE_SHARE if bool(row.get("called", false)) else 1.0


## What letting the request lapse (or missing the booked day) writes on the card now:
## decline_price at lapse_share. An uncalled request's is its decline_price exactly.
static func lapse_price(ns, loader, row: Dictionary) -> Dictionary:
	return decline_price(ns, loader, row, lapse_share(row))


## Each open answer as the feeling bands it leaves the person in, every register
## filled (an unmoved one at its current band), keyed "person|register", so two
## answers compare register by register: [{"feel": {key: band}}], book, delegate,
## decline in that order, the closed ones left out.
static func landings(state, ns, loader, row: Dictionary) -> Array:
	var pid := String(row.get("person_id", ""))
	var person = loader.person_by_id.get(pid)
	var open: Dictionary = answers(state, ns, loader, row)
	var deltas: Array = []
	if bool(open["book"]["ok"]):
		deltas.append({"rapport": K.RECEIVED_RAPPORT})
	if bool(open["delegate"]["ok"]):
		deltas.append({
			"rapport": Delegation.snub(person, String(row["object"])),
			"grudge": Characters.refusal_grudge(ns, person, K.DECLINE_GRUDGE * K.DELEGATE_GRUDGE_SHARE) if person != null else 0.0,
			"loyalty": K.DECLINE_LOYALTY * K.DELEGATE_GRUDGE_SHARE,
		})
	if bool(open["decline"]["ok"]):
		deltas.append(decline_price(ns, loader, row))
	var feel := {
		"grudge": float(ns.person_grudges.get(pid, 0.0)),
		"rapport": President.rapport(ns, pid),
		"loyalty": float(ns.person_loyalty.get(pid, 0.0)),
	}
	var out: Array = []
	for delta in deltas:
		var bands := {}
		for register in FK.CUTS:
			var span: Vector2 = FK.RANGE[register]
			var value := clampf(float(feel[register]) + float(delta.get(register, 0.0)), span.x, span.y)
			bands["%s|%s" % [pid, register]] = FK.band(register, value)
		out.append({"feel": bands})
	return out


## Whether two of the request's open answers leave the person in different words.
static func differs(state, ns, loader, row: Dictionary) -> bool:
	var lands := landings(state, ns, loader, row)
	for i in lands.size():
		for j in range(i + 1, lands.size()):
			if lands[i]["feel"] != lands[j]["feel"]:
				return true
	return false
