extends RefCounted

## The phone -- V5.2b b3. One lever attempt or one topic, no diary day, at most
## one call per person per month (the spec's phone table). The model is
## docs/audiences-model.md "The phone"; the band, docs/design/bands-v5.2.md B5's
## channel row (tools/lever_probe.gd).
##
## THE SAME MATRIX AT LOWER ODDS (the spec's dominance matrix): a lever by phone is
## the audience's lever on the same cell, CALL_ODDS_PENALTY lower, and is not
## offered where that would fall under ODDS_MIN -- so the channel row holds by
## construction, never by a clamp. The printed range uses the audience's seed: the
## call's range is the audience's shifted, and reading both narrows nothing.
##
## A LEVER NEEDS AN ASK: the person's open request, pending or booked. A call that
## works answers it (Audiences.answer: settled or promised, no price, and nothing
## learned -- a call is not a hold); one that fails leaves it open, so the card's
## three answers stand. A topic needs no request and teaches only itself.
##
## The rules are Levers' -- the spend (pay), the win's relief and the flatter
## backfire (outcome), a topic's lesson (teach), a word given once (word_given) --
## so the two channels cannot drift. The month's stamp, ns.phone_calls, is this file's alone. A refusal
## writes nothing and spends no month. Named `dial`, not `call`: a static `call`
## overrides Object.call() and does not parse.

const K = preload("res://src/sim/lever_constants.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const Levers = preload("res://src/sim/levers.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const President = preload("res://src/sim/president.gd")
const Cycle = preload("res://src/sim/cycle.gd")


## A lever's true odds by phone in `cell`, or -1.0 when the phone does not offer it
## (not offered at all, or too long a shot for a call). One function for the call
## and the probe's channel row.
static func odds(person, lever: String, cell: Dictionary) -> float:
	var p := LeverOdds.odds(person, lever, cell)
	if p < 0.0 or p - K.CALL_ODDS_PENALTY < K.ODDS_MIN:
		return -1.0
	return p - K.CALL_ODDS_PENALTY


## The call card: {why_not, request_id, levers, topics}. why_not says why no call
## can be made now; each lever row is Levers.lever_row() at the phone's odds, each
## topic row {topic, offered, why_not, spends}.
static func options(state, ns, loader, person_id: String) -> Dictionary:
	var why := _line_reason(state, ns, loader, person_id)
	var request := _open_request(ns, person_id)
	var out := {"why_not": why, "request_id": String(request.get("id", "")), "levers": [], "topics": []}
	var person = loader.person_by_id.get(person_id)
	if person == null:
		return out
	var c := Levers.cell(state, ns, loader, {"person_id": person_id, "object": String(request.get("object", ""))})
	for lever in K.LEVERS:
		var p := odds(person, lever, c)
		var why_not := why
		if why_not == "" and request.is_empty():
			why_not = "nothing to ask about: they have no request open"
		elif why_not == "" and p < 0.0:
			why_not = "you are not friends" if LeverOdds.odds(person, lever, c) < 0.0 else "too long a shot for a call"
		elif why_not == "":
			why_not = Levers.word_given(ns, person_id, lever, String(request["object"]))
		(out["levers"] as Array).append(Levers.lever_row(ns, person, lever, p, why_not, float(c["knowledge"]), _now(state)))
	for topic in K.TOPICS:
		var why_not := why
		if why_not == "" and topic == "dinner":
			why_not = "not by phone: a dinner needs an evening"
		elif why_not == "" and topic == "flirt":
			why_not = "not yet: the shadows come later"
		(out["topics"] as Array).append({"topic": topic, "offered": why_not == "", "why_not": why_not, "spends": {}})
	return out


## One call: a lever on the person's open request, or a topic. {ok, error, success,
## spent, effects} -- a topic's success is true, the topic was talked through.
static func dial(state, ns, loader, person_id: String, lever_or_topic: String, args := {}) -> Dictionary:
	var refused := {"ok": false, "error": "", "success": false, "spent": {}, "effects": {}}
	var shown := options(state, ns, loader, person_id)
	var row := {}
	for r in (shown["levers"] as Array) + (shown["topics"] as Array):
		if String(r.get("lever", r.get("topic", ""))) == lever_or_topic:
			row = r
	if row.is_empty() or not bool(row["offered"]):
		var why := String(row.get("why_not", shown["why_not"]))
		refused["error"] = why if why != "" else "not something to say on the phone"
		return refused
	var now := _now(state)
	if row.has("topic"):
		var taught := Levers.teach(state, ns, loader, person_id, lever_or_topic, args)
		if taught.has("error"):
			refused["error"] = String(taught["error"])
			return refused
		ns.phone_calls[person_id] = now
		return {"ok": true, "error": "", "success": true, "spent": {}, "effects": taught}
	refused["error"] = Levers.arg_error(lever_or_topic, args, now)
	if refused["error"] != "":
		return refused
	var person = loader.person_by_id.get(person_id)
	var request := Audiences.request(ns, String(shown["request_id"]))
	var object := String(request["object"])
	# The odds before the spend, as in the audience: friendship's bond step and
	# pressure's rapport are paid for this roll, not read by it.
	var p := odds(person, lever_or_topic, Levers.cell(state, ns, loader, {"person_id": person_id, "object": object}))
	var spent := Levers.pay(state, ns, loader, person, object, lever_or_topic, args, now)
	if spent.has("refused"):
		refused["error"] = "the promise could not be made"
		return refused
	ns.phone_calls[person_id] = now
	var success := Cycle.unit_pair(person_id, Cycle.salted("%s:%s" % [K.SALT_PHONE, lever_or_topic], ns.draw_seed), now) < p
	if success:
		Audiences.answer(state, ns, String(request["id"]), AK.STATUS_PROMISED if lever_or_topic == "promise_date" else AK.STATUS_SETTLED)
	return {"ok": true, "error": "", "success": success, "spent": spent,
		"effects": Levers.outcome(state, ns, loader, person, lever_or_topic, success)}


# --- Helpers ------------------------------------------------------------------------

## Why the line is closed: it reaches whom the registers cover (never the
## president), once a month each.
static func _line_reason(state, ns, loader, person_id: String) -> String:
	if not President.covers(state, ns, loader, person_id):
		return "the line does not reach them"
	if int(ns.phone_calls.get(person_id, -1)) == _now(state):
		return "you have spoken this month already"
	return ""


## The person's open request (pending or booked), as Audiences reads it, or {}.
static func _open_request(ns, person_id: String) -> Dictionary:
	for row in ns.audience_requests:
		if String(row.get("person_id", "")) == person_id and AK.OPEN.has(String(row.get("status", ""))):
			return Audiences.request(ns, String(row["id"]))
	return {}


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
