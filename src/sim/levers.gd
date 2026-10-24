extends RefCounted

## The audience -- V5.2b b2. The booked day has come: the president and one
## person, three attempts, each a lever (argue, bargain, promise a date, pressure,
## flatter, appeal to friendship) or a topic (family, opinion, gossip, dinner).
## The model is docs/audiences-model.md "The audience"; the design,
## docs/design/v5.2-spec.md "The influence levers" and "The other topics"; the
## bands, docs/design/bands-v5.2.md B4 and B5 (tools/lever_probe.gd).
##
## THE SESSION IS EPHEMERAL (summits-model section 2, spec C11): a Dictionary the
## scene holds and hands back on every call, never saved. What it changes lands
## in the registers -- President's (knowledge, rapport, the bond, commitments),
## Characters' (grudge and loyalty, through price_refusal) and Audiences' (the
## request's outcome). A scene left open past its month is b1's no-show, priced as
## a decline once.
##
## THE ODDS ARE LeverOdds.odds() on a cell built here from the registers, so the
## scene shows the numbers the probe judges. A roll is Cycle.unit_pair over the
## request, the lever and the attempt index, and the month (I1).
##
## A refusal writes nothing: every command checks before it spends.

const K = preload("res://src/sim/lever_constants.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const President = preload("res://src/sim/president.gd")
const Characters = preload("res://src/sim/characters.gd")
const Cycle = preload("res://src/sim/cycle.gd")

## The six levers and the other topics, in the order the scene lists them.
const LEVERS := K.LEVERS
const TOPICS := K.TOPICS


## The booked day has come: the session for the scene, or {} when the request is
## not booked or its day is still ahead. Opening holds the request (Audiences),
## which teaches the president a little whatever is said.
static func open(state, ns, loader, request_id: String) -> Dictionary:
	var row := Audiences.request(ns, request_id)
	if row.is_empty() or String(row["status"]) != AK.STATUS_BOOKED:
		return {}
	var date: Dictionary = row["date"]
	if _ymd(int(state.year), int(state.month), int(state.day)) < _ymd(int(date["year"]), int(date["month"]), int(date["day"])):
		return {}
	if not bool(Audiences.hold(state, ns, loader, request_id).get("ok", false)):
		return {}
	return {
		"request_id": request_id,
		"person_id": String(row["person_id"]),
		"object": String(row["object"]),
		"stance": String(row["stance"]),
		"attempts_left": K.ATTEMPTS,
		"attempts": [],
		"used_topics": [],
		"won": "",
		"closed": false,
	}


## The cell LeverOdds reads, from the registers as they stand. ALIGNED is whether
## the request's want was served at Characters' last settle -- the register that
## judge keeps, so the scene and the want ladder read one answer.
static func cell(state, ns, loader, session: Dictionary) -> Dictionary:
	var pid := String(session.get("person_id", ""))
	return {
		"knowledge": President.knowledge(ns, pid),
		"rapport": President.rapport(ns, pid),
		"relationship": President.relationship(ns, pid),
		"aligned": bool(ns.person_want_state.get("%s|%s" % [pid, String(session.get("object", ""))], false)),
		"standing": float(ns.person_standing.get(pid, K.STANDING_NEUTRAL)),
		"approval": float(ns.overall_approval_pct),
	}


## [{lever, offered: bool, why_not: String, odds_lo: float, odds_hi: float,
##   fog: "stranger" | "acquaintance" | "known", spends: Dictionary}]. The true
## odds are never returned, only the range that holds them (B4).
static func offered(state, ns, loader, session: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var person = loader.person_by_id.get(String(session.get("person_id", "")))
	if person == null:
		return out
	var c := cell(state, ns, loader, session)
	var why := _why_not(ns, session)
	var now := _now(state)
	for lever in K.LEVERS:
		var p := LeverOdds.odds(person, lever, c)
		var r := Vector2.ZERO if p < 0.0 else LeverOdds.shown_range(person.id, lever, p, float(c["knowledge"]))
		var why_not := why if why != "" else ("you are not friends" if p < 0.0 else "")
		var row := {
			"lever": lever,
			"offered": why_not == "",
			"why_not": why_not,
			"odds_lo": r.x,
			"odds_hi": r.y,
			"fog": President.knowledge_band(ns, person.id),
			"spends": _spends(lever),
		}
		# b2.1, for the scene: a bargain names what it can pay in (one, chosen), and
		# a promise its window, so the UI restates no sim rule.
		if lever == "bargain":
			row["currencies"] = [
				{"currency": K.CURRENCY_FAVOUR, "offered": why_not == "", "why_not": why_not, "spends": {"rapport": -K.BARGAIN_FAVOUR_RAPPORT}},
				{"currency": K.CURRENCY_VOTE_TRADE, "offered": why_not == "", "why_not": why_not, "spends": {"iou": 1.0}},
				{"currency": K.CURRENCY_AID, "offered": false, "why_not": "aid is not open yet", "spends": {}},
			]
		elif lever == "promise_date":
			row["dates"] = {"earliest": now + K.PROMISE_MIN_MONTHS, "latest": now + K.PROMISE_MAX_MONTHS}
		out.append(row)
	return out


## [{topic, offered: bool, why_not: String, spends: Dictionary}]
static func topics(state, ns, loader, session: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var why := _attempt_reason(ns, session)
	for topic in K.TOPICS:
		var why_not := why
		if why_not == "" and topic == "flirt":
			why_not = "not yet: the shadows come later"
		elif why_not == "" and topic == "dinner" and (session["used_topics"] as Array).has("dinner"):
			why_not = "you have dined together already"
		out.append({"topic": topic, "offered": why_not == "", "why_not": why_not, "spends": {"attempt": 1}})
	return out


## One lever: its spend paid, then the seeded roll. {ok, error, success, spent,
## effects}. A refusal (no attempts left, already agreed, not offered, a bad
## argument) writes nothing.
static func attempt(state, ns, loader, session: Dictionary, lever: String, args := {}) -> Dictionary:
	var refused := {"ok": false, "error": "", "success": false, "spent": {}, "effects": {}}
	refused["error"] = _why_not(ns, session)
	if refused["error"] != "":
		return refused
	var pid := String(session["person_id"])
	var person = loader.person_by_id.get(pid)
	var c := cell(state, ns, loader, session)
	var p := LeverOdds.odds(person, lever, c) if K.LEVERS.has(lever) else -1.0
	if p < 0.0:
		refused["error"] = "not a lever offered here"
		return refused
	var now := _now(state)
	var currency := String(args.get("currency", K.CURRENCY_FAVOUR))
	var due := int(args.get("due_month", -1))
	if lever == "bargain" and currency != K.CURRENCY_FAVOUR and currency != K.CURRENCY_VOTE_TRADE:
		refused["error"] = "aid is not open yet" if currency == K.CURRENCY_AID else "not a currency"
		return refused
	if lever == "promise_date" and (due < now + K.PROMISE_MIN_MONTHS or due > now + K.PROMISE_MAX_MONTHS):
		refused["error"] = "that date is too near or too far for a promise"
		return refused
	var spent := _pay(state, ns, loader, person, session, lever, currency, due, now)
	if spent.has("refused"):
		refused["error"] = "the promise could not be made"
		return refused
	var index := K.ATTEMPTS - int(session["attempts_left"])
	var success := Cycle.unit_pair(String(session["request_id"]), "%s:%s:%d" % [K.SALT_ROLL, lever, index], now) < p
	session["attempts_left"] = int(session["attempts_left"]) - 1
	(session["attempts"] as Array).append({"lever": lever, "success": success})
	var effects := {}
	if success:
		session["won"] = lever
		Audiences.agree(ns, String(session["request_id"]), AK.STATUS_PROMISED if lever == "promise_date" else AK.STATUS_SETTLED)
		if lever != "flatter":
			effects = Characters.price_refusal(ns, person, -K.GRUDGE_ACCEPT_RELIEF, K.LOYALTY_ACCEPT)
	elif lever == "flatter" and person.traits.has("principled") and float(person.social_skill) > K.FLATTER_BACKFIRE_SKILL:
		effects["rapport"] = _rapport(state, ns, loader, pid, -K.FLATTER_BACKFIRE_RAPPORT)
	return {"ok": true, "error": "", "success": success, "spent": spent, "effects": effects}


## One topic: an attempt spent for knowledge and rapport. {ok, error, effects}.
## Gossip names the third person in args.about and teaches the president about
## them only (spec C1: every edge starts at the president).
static func talk(state, ns, loader, session: Dictionary, topic: String, args := {}) -> Dictionary:
	var refused := {"ok": false, "error": "", "effects": {}}
	var offer := {}
	for t in topics(state, ns, loader, session):
		if String(t["topic"]) == topic:
			offer = t
	if offer.is_empty() or not bool(offer["offered"]):
		refused["error"] = String(offer.get("why_not", "not a topic"))
		return refused
	var pid := String(session["person_id"])
	var effects := {}
	match topic:
		"gossip":
			var about := String(args.get("about", ""))
			if about == "" or about == pid or not President.covers(state, ns, loader, about):
				refused["error"] = "gossip needs someone else to talk about"
				return refused
			effects["knowledge_of"] = {about: _learn(state, ns, loader, about, K.KNOW_GOSSIP)}
			effects["rapport"] = _rapport(state, ns, loader, pid, K.RAPPORT_GOSSIP)
		"dinner":
			effects["knowledge"] = _learn(state, ns, loader, pid, K.KNOW_DINNER)
			effects["rapport"] = _rapport(state, ns, loader, pid, K.RAPPORT_DINNER)
		_:
			effects["knowledge"] = _learn(state, ns, loader, pid, K.KNOW_TOPIC)
			effects["rapport"] = _rapport(state, ns, loader, pid, K.RAPPORT_TOPIC)
	session["attempts_left"] = int(session["attempts_left"]) - 1
	(session["used_topics"] as Array).append(topic)
	return {"ok": true, "error": "", "effects": effects}


## The audience ends. A lever that worked settles the request (a promise as
## "promised"); none, and it is a decline, priced once through Audiences.
## {ok, error, outcome: "settled" | "promised" | "declined", price: Dictionary}
static func close(state, ns, loader, session: Dictionary) -> Dictionary:
	var why := _open_reason(ns, session)
	if why != "":
		return {"ok": false, "error": why, "outcome": "", "price": {}}
	var won := String(session["won"])
	var outcome := AK.STATUS_DECLINED
	if won == "promise_date":
		outcome = AK.STATUS_PROMISED
	elif won != "":
		outcome = AK.STATUS_SETTLED
	var r: Dictionary = Audiences.settle(state, ns, loader, String(session["request_id"]), outcome)
	session["closed"] = true
	return {"ok": bool(r.get("ok", false)), "error": String(r.get("error", "")), "outcome": outcome, "price": r.get("price", {})}


## The month's half of the audience: every promise, IOU and delegation due is
## judged once, with no roll -- kept (or paid) if the person's want is served now,
## else a lie revealed (a promise) or a betrayal (an IOU; a delegation, which also
## lands the share of the grudge it deferred). {kept, broken, void}, the rows
## judged, each also remembered with its verdict for the Diary. The played nation
## only: the AI nations hold no audiences (spec C12). A person who has since
## defected or left office is judged on the same want; one whose content no
## longer carries the want (an older save) is VOID, dropped unpriced -- there is
## nothing left to break.
static func tick_month(state, loader, meters: Dictionary) -> Dictionary:
	var out := {"kept": [], "broken": [], "void": []}
	var ns = state.player()
	if ns == null:
		return out
	var now := _now(state)
	President.prune_judged(ns, now)
	if ns.commitments.is_empty():
		return out
	var leaders := {}
	for party in loader.parties.get(ns.id, []):
		leaders[party.id] = party.leader_person_id
	for row in President.take_commitments_due(ns, now):
		var verdict := _judge(state, ns, loader, row, meters, leaders)
		out[verdict].append(row)
		President.record_judged(ns, row, verdict, now)
	return out


## One commitment at its date: its verdict, its price written.
static func _judge(state, ns, loader, row: Dictionary, meters: Dictionary, leaders: Dictionary) -> String:
	var person = loader.person_by_id.get(String(row["person_id"]))
	var want := {}
	if person != null:
		for w in person.wants:
			if String(w["object"]) == String(row["object"]):
				want = w
	if want.is_empty():
		return "void"
	var pid := String(person.id)
	var kind := String(row["kind"])
	if Characters.want_served(ns, person, want, meters, leaders):
		if kind != "iou":
			_rapport(state, ns, loader, pid, K.PROMISE_KEPT_RAPPORT)
		return "kept"
	if kind == "promise":
		_rapport(state, ns, loader, pid, -K.LIE_RAPPORT)
		President.learn(state, ns, loader, pid, -President.knowledge(ns, pid) * (1.0 - K.LIE_KNOWLEDGE_KEEP))
		Characters.price_refusal(ns, person, K.LIE_GRUDGE, 0.0)
		return "broken"
	if kind == "delegated":
		var deferred := 1.0 - AK.DELEGATE_GRUDGE_SHARE
		Characters.price_refusal(ns, person, AK.DECLINE_GRUDGE * deferred, AK.DECLINE_LOYALTY * deferred)
	_rapport(state, ns, loader, pid, -K.IOU_BETRAYAL_RAPPORT)
	Characters.price_refusal(ns, person, K.IOU_BETRAYAL_GRUDGE, 0.0)
	return "broken"


## The phone (b3): one lever attempt or one topic, no diary day. Named `phone`,
## not `call`: a static `call` overrides Object.call() and does not parse.
static func phone(state, ns, loader, person_id: String, lever_or_topic: String, args := {}) -> Dictionary:
	return {"ok": false, "error": "not built yet"}


## The traits the president knows; a hidden trait is absent, never wrong.
static func known_traits(ns, person) -> Array[String]:
	return LeverOdds.known_traits(ns, person)


# --- Helpers ------------------------------------------------------------------------

## Why a session takes no command at all: it was closed, or its request is no
## longer being held (it lapsed as a no-show, or was never opened).
static func _open_reason(ns, session: Dictionary) -> String:
	if session.is_empty() or bool(session.get("closed", true)):
		return "this audience is over"
	var row := Audiences.request(ns, String(session.get("request_id", "")))
	if row.is_empty() or String(row["status"]) != AK.STATUS_HELD or String(row["person_id"]) != String(session.get("person_id", "")):
		return "this audience is over"
	return ""


## Why no attempt -- lever or topic -- can be made: the session's reason, or the
## three are spent. Closing stays open either way.
static func _attempt_reason(ns, session: Dictionary) -> String:
	var why := _open_reason(ns, session)
	if why == "" and int(session.get("attempts_left", 0)) <= 0:
		why = "no attempts left"
	return why


## Why no lever can be tried: the attempt's reason, or the person has agreed.
static func _why_not(ns, session: Dictionary) -> String:
	var why := _attempt_reason(ns, session)
	if why == "" and String(session.get("won", "")) != "":
		why = "they have already agreed"
	return why


## The lever's own spend, paid win or lose; what it wrote, after the clamps. A
## commitment the register refuses comes back {refused}, with nothing written --
## the commitment is each of those levers' only spend.
static func _pay(state, ns, loader, person, session: Dictionary, lever: String, currency: String, due: int, now: int) -> Dictionary:
	var pid := String(person.id)
	var object := String(session["object"])
	match lever:
		"bargain":
			if currency == K.CURRENCY_VOTE_TRADE:
				if not President.commit(state, ns, loader, "iou", pid, object, now + K.IOU_MONTHS):
					return {"refused": true}
				return {"iou": now + K.IOU_MONTHS}
			return {"rapport": _rapport(state, ns, loader, pid, -K.BARGAIN_FAVOUR_RAPPORT)}
		"promise_date":
			if not President.commit(state, ns, loader, "promise", pid, object, due):
				return {"refused": true}
			return {"promise": due}
		"pressure":
			var spent: Dictionary = Characters.price_refusal(ns, person, K.PRESSURE_GRUDGE, 0.0)
			spent["rapport"] = _rapport(state, ns, loader, pid, -K.PRESSURE_RAPPORT)
			return spent
		"friendship":
			var bond := President.relationship(ns, pid)
			President.set_bond(state, ns, loader, pid, "friend" if bond == "close" else "")
			return {"bond": "%s -> %s" % [bond, President.relationship(ns, pid)]}
	return {}


## What a lever costs, for the card: register -> amount, every value a number --
## rapport and grudge in their own points, a commitment (promise) and a bond step
## as counts. A bargain's is its default currency's, the favour; the row's
## `currencies` lists each one it can pay in instead (QA's R2 on #113: one is
## paid, so the card shows one).
static func _spends(lever: String) -> Dictionary:
	match lever:
		"bargain":
			return {"rapport": -K.BARGAIN_FAVOUR_RAPPORT}
		"promise_date":
			return {"promise": 1.0}
		"pressure":
			return {"rapport": -K.PRESSURE_RAPPORT, "grudge": K.PRESSURE_GRUDGE}
		"friendship":
			return {"bond": -1.0}
	return {}


static func _learn(state, ns, loader, pid: String, amount: float) -> float:
	return President.learn_from(state, ns, loader, pid, amount)


static func _rapport(state, ns, loader, pid: String, amount: float) -> float:
	var before := President.rapport(ns, pid)
	President.adjust_rapport(state, ns, loader, pid, amount)
	return President.rapport(ns, pid) - before


static func _ymd(y: int, m: int, d: int) -> int:
	return (y * 12 + m) * 32 + d


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
