extends RefCounted

## The audience as a deal -- V5.3 b, step 6 (docs/design/v5.3-ab.md section 5, option 1, the
## author's "Un marchandage concret"; the model is docs/audiences-model.md section 14). Why:
## the scene was three picks among ten buttons for a prize nobody could see ("déroutant").
##
## ONE ASK, ONE OFFER, THREE ANSWERS.
##   ask_of()    what they want, in the game's own objects: a bill, a portfolio, else a dated
##               word on the want. Read when the audience opens, never stamped on the request,
##               so a card is never stale and no save carries it.
##   offer_of()  what they give: their faction's seats on the next bill, else their silence.
##   grant()     pay the ask, take the offer, no roll.
##   bargain()   one of three priced approaches (Levers.attempt, so the rolls, the spends, the
##               fog and the lies are the scene's as they were); a win is the smaller grant for
##               the same offer. The three attempts stay the scene's one tension: small talk
##               spends them too, and a Grant stays open when they run out.
##   Refuse      is Levers.close() with nothing agreed: a decline, priced once.
##
## THE DEAL IS TWO ROWS OF ns.commitments (no third register): the president's dated word and
## what the person owes (`pledge`, `silence`), each carrying `deal`, the request's id.
## CommitmentJudge judges them at their dates and lets each release the other.
##
## WHAT IS NOT HERE (each named in the PR): firm and region asks, since no want names one yet;
## flatter and friendship as modifiers, with the lever bands re-measured on three approaches;
## a phone win still settles with no ask and no offer, B5's channel row unchanged.
##
## `answers()`, `ask_of()` and `offer_of()` write nothing, so the UI may read them on any redraw.

const K = preload("res://src/sim/deal_constants.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const CalK = preload("res://src/sim/calendar_constants.gd")
const SC = preload("res://src/sim/shadow_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const DivisionTerms = preload("res://src/sim/division_terms.gd")
const Exposure = preload("res://src/sim/exposure.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Levers = preload("res://src/sim/levers.gd")
const President = preload("res://src/sim/president.gd")
const Programme = preload("res://src/sim/programme.gd")
const Shadows = preload("res://src/sim/shadows.gd")


## The booked day has come: Levers' session, which this scene hands back on every call, with the
## ask fixed for the audience. {} when it cannot open.
static func open(state, ns, loader, request_id: String) -> Dictionary:
	var row := Audiences.request(ns, request_id)
	var session := Levers.open(state, ns, loader, request_id)
	if session.is_empty():
		return {}
	session["ask"] = ask_of(state, ns, loader, row)
	session["ask_object"] = String(session["ask"]["object"])
	return session


# --- Reads --------------------------------------------------------------------------------

## `row` a request as Audiences reads it. {kind, object, due_month, smaller_due_month}, with
## {law_id} on a bill and {portfolio, party_id, why_not} on a post, which has no due_month: it
## is paid now.
static func ask_of(state, ns, loader, row: Dictionary) -> Dictionary:
	var now := _now(state)
	var object := String(row.get("object", ""))
	if object.begins_with("office:portfolio:"):
		var portfolio := object.substr("office:portfolio:".length())
		var party := President.party_id_of(ns, loader, String(row.get("person_id", "")))
		return {"kind": K.ASK_POST, "object": object, "portfolio": portfolio, "party_id": party,
			"why_not": Cabinet.refusal_reason(ns, portfolio, party), "smaller_due_month": now + K.SMALLER_EXTRA_MONTHS}
	if object.begins_with("programme:") and String(row.get("stance", "")) == "sponsor":
		var law_id := _open_law_named(state, ns, loader, object.substr("programme:".length()))
		if law_id != "":
			var by := now + K.LAW_MONTHS
			return {"kind": K.ASK_LAW, "object": "law:%s" % law_id, "law_id": law_id, "due_month": by, "smaller_due_month": by + K.SMALLER_EXTRA_MONTHS}
	var due := _word_due(ns, now, object)
	return {"kind": K.ASK_WORD, "object": object, "due_month": due, "smaller_due_month": due + K.SMALLER_EXTRA_MONTHS}


## {kind: vote, law_id, party_id, seats, due_month, date} or {kind: silence, months, due_month}.
## `date` is the bill's day in the diary, {} for one already tabled. The seats are what the
## division will count, before the cap a second pledge from the party might meet.
static func offer_of(state, ns, loader, person_id: String) -> Dictionary:
	var now := _now(state)
	var party := President.party_id_of(ns, loader, person_id)
	var seats := int(ns.seats_by_party.get(party, 0))
	var bill := _next_bill(state, ns, now)
	if seats > 0 and not bill.is_empty() and not _pledged(ns, person_id, String(bill["law_id"])):
		return bill.merged({"kind": K.OFFER_VOTE, "party_id": party, "seats": DivisionTerms.one_pledge(ns, person_id, seats)})
	return {"kind": K.OFFER_SILENCE, "months": K.SILENCE_MONTHS, "due_month": now + K.SILENCE_MONTHS}


## The scene's card, everything its strips need and nothing written:
##   ask, offer  as above;
##   money       the request's offer of money, with what taking it risks, shown first (the
##               author's ruling): {currency, amount_eur_m, evidence, found_in_a_year}, or {};
##   grant       {ok, why_not};
##   bargain     {due_month, approaches}, each a Levers lever row, a promise's own date beside;
##   refuse      the price Levers.close() would charge with nothing agreed.
static func answers(state, ns, loader, session: Dictionary) -> Dictionary:
	var why := _grant_reason(ns, session)
	var approaches: Array = []
	for row in Levers.offered(state, ns, loader, session):
		if K.APPROACHES.has(String(row["lever"])):
			approaches.append(row)
	return {
		"ask": session.get("ask", {}),
		"offer": offer_of(state, ns, loader, String(session.get("person_id", ""))),
		"money": _money(state, ns, loader, session),
		"grant": {"ok": why == "", "why_not": why},
		"bargain": {"due_month": int(session.get("ask", {}).get("smaller_due_month", 0)), "approaches": approaches},
		"refuse": Audiences.decline_price(ns, loader, String(session.get("request_id", ""))),
	}


# --- Commands -----------------------------------------------------------------------------

## Pay the ask, take the offer: {ok, error, ask, offer, effects}. A refusal writes nothing.
static func grant(state, ns, loader, session: Dictionary) -> Dictionary:
	var why := _grant_reason(ns, session)
	if why != "":
		return {"ok": false, "error": why}
	var ask: Dictionary = session["ask"]
	var pid := String(session["person_id"])
	var outcome := AK.STATUS_SETTLED
	if String(ask["kind"]) == K.ASK_POST:
		Cabinet.seat_party(state, String(ask["portfolio"]), String(ask["party_id"]), loader.parties.get(ns.id, []))
	else:
		if not President.commit(state, ns, loader, "promise", pid, String(ask["object"]), int(ask["due_month"])):
			return {"ok": false, "error": "the promise could not be made"}
		_link(ns, session)
		outcome = AK.STATUS_PROMISED
	session["won"] = "grant"
	var offer := _strike(state, ns, loader, session, outcome)
	var effects := Levers.outcome(state, ns, loader, loader.person_by_id.get(pid), "grant", true)
	return {"ok": true, "error": "", "ask": ask, "offer": offer, "effects": effects}


## One approach: Levers.attempt()'s result, and on a win {ask, offer} with the smaller grant
## written. A promise not believed still binds (the author's "Oui, parole donnée"), on no deal.
static func bargain(state, ns, loader, session: Dictionary, approach: String, args := {}) -> Dictionary:
	if not K.APPROACHES.has(approach):
		return {"ok": false, "error": "not an approach", "success": false, "spent": {}, "effects": {}}
	var result := Levers.attempt(state, ns, loader, session, approach, args)
	if not bool(result.get("success", false)):
		return result
	var ask: Dictionary = session["ask"]
	var pid := String(session["person_id"])
	# A promise's own spend is the word. A word given earlier in this scene and not believed
	# then is taken up now: one word on one ask.
	if Levers.word_given(ns, pid, "promise_date", String(ask["object"])) == "":
		President.commit(state, ns, loader, "promise", pid, String(ask["object"]), int(ask["smaller_due_month"]))
	_link(ns, session)
	result["ask"] = ask
	result["offer"] = _strike(state, ns, loader, session, AK.STATUS_PROMISED)
	return result


# --- Helpers ------------------------------------------------------------------------------

## Why Grant is closed, "" when it is open. Spent attempts do not close it: three failures
## leave the full price on the table.
static func _grant_reason(ns, session: Dictionary) -> String:
	var why := Levers.open_reason(ns, session)
	if why != "":
		return why
	if String(session.get("won", "")) != "":
		return "they have already agreed"
	var ask: Dictionary = session.get("ask", {})
	if String(ask.get("kind", "")) == K.ASK_POST:
		return String(ask.get("why_not", ""))
	return Levers.word_given(ns, String(session["person_id"]), "promise_date", String(ask.get("object", "")))


## What the person owes, written, and the audience's outcome stamped so a scene left open ends
## as this deal. The offer as written: a pledge the register refused falls back to silence.
static func _strike(state, ns, loader, session: Dictionary, outcome: String) -> Dictionary:
	var pid := String(session["person_id"])
	var deal := String(session["request_id"])
	var offer := offer_of(state, ns, loader, pid)
	var wrote := String(offer["kind"]) == K.OFFER_VOTE and President.pledge(state, ns, loader, pid, String(offer["law_id"]), int(offer["due_month"]))
	if not wrote:
		offer = {"kind": K.OFFER_SILENCE, "months": K.SILENCE_MONTHS, "due_month": _now(state) + K.SILENCE_MONTHS}
		wrote = President.commit(state, ns, loader, "silence", pid, "silence", int(offer["due_month"]))
	if wrote:
		ns.commitments[-1]["deal"] = deal
	session["outcome"] = outcome
	Audiences.agree(ns, deal, outcome)
	return offer


## The president's word on this ask joins the deal.
static func _link(ns, session: Dictionary) -> void:
	for row in ns.commitments:
		if String(row.get("kind", "")) == "promise" and String(row.get("person_id", "")) == String(session["person_id"]) \
				and String(row.get("object", "")) == String(session["ask"]["object"]):
			row["deal"] = String(session["request_id"])


## The first law a programme entry names that is open to the president now, or "".
static func _open_law_named(state, ns, loader, entry_id: String) -> String:
	for entry in loader.programme:
		if String(entry["id"]) == entry_id:
			for law_id in entry.get("laws", []):
				if Legislature.open_law(state, ns, loader, String(law_id)) != null:
					return String(law_id)
	return ""


## A programme's word falls due the month after its register opens: the register opens in the
## month of the vote, after that month's judge has run (Programme runs before Elections). A
## clock never set has no term to name, so it reads as any other word.
static func _word_due(ns, now: int, object: String) -> int:
	if not object.begins_with("programme:"):
		return now + K.WORD_MONTHS
	if Programme.is_term_start(ns) and int(ns.programme_chosen_term) != int(ns.terms_served):
		return now + 1
	var vote := int(ns.next_executive_year) * 12 + int(ns.next_executive_month)
	return vote + 1 if vote >= now else now + K.WORD_MONTHS


## The next bill the president brings: one already tabled, else the earliest in the diary, or
## {}. {law_id, due_month, date}: a pledge stands until the division reads it, the tick after
## the bill's day.
static func _next_bill(state, ns, now: int) -> Dictionary:
	var tabled := String(ns.tabled_bill.get("law_id", ""))
	if tabled != "":
		return {"law_id": tabled, "due_month": now + 1, "date": {}}
	var best := {}
	for entry in Calendar.booked(state):
		if String(entry.get("kind", "")) == CalK.KIND_LAW and String(entry.get("law_id", "")) != "" \
				and (best.is_empty() or _day(entry) < _day(best)):
			best = entry
	if best.is_empty():
		return {}
	return {"law_id": String(best["law_id"]), "due_month": int(best["year"]) * 12 + int(best["month"]) + 1,
		"date": {"year": int(best["year"]), "month": int(best["month"]), "day": int(best["day"])}}


static func _pledged(ns, person_id: String, law_id: String) -> bool:
	for row in President.pledges_on(ns, law_id):
		if String(row["person_id"]) == person_id:
			return true
	return false


## The money on the table and what taking it risks. The chance is the months after, read as the
## game reads them, on the evidence as it stands.
static func _money(state, ns, loader, session: Dictionary) -> Dictionary:
	var offer := Shadows.offer(ns, session)
	if offer.is_empty():
		return {}
	var amount := float(offer.get("amount_eur_m", 0.0))
	var evidence := amount * SC.EVIDENCE_PER_EUR_M
	var currency := String(offer.get("currency", ""))
	var month := Exposure.hazard_if(state, ns, loader, currency, String(session["person_id"]), evidence)
	var clear := 1.0
	for i in 12:
		clear *= 1.0 - month
	return {"currency": currency, "amount_eur_m": amount, "evidence": evidence, "found_in_a_year": 1.0 - clear}


static func _day(entry: Dictionary) -> int:
	return (int(entry["year"]) * 12 + int(entry["month"])) * 32 + int(entry["day"])


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
