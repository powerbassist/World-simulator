extends RefCounted

## The monthly briefing's three priorities -- V5.3-0, docs/design/v5.3-0-readability.md
## 2.3. A pure, read-only presentation query: it reads GameState and writes nothing,
## so a headless probe calls it on a state with no scene tree.
##
## **Fog first.** A priority reads only what the player can already see: never an
## armed event, never exposure evidence, bloc approval only as the polls show it
## (PollNoise), a person only once Feelings gives their grudge the word "hostile". A
## briefing that named a hidden threat would leak the fog.
##
## **Exactly three, of three kinds.** Held surfaces take their slots first (an
## interrupt, a major card, a minor card in its last month, the term-start offer):
## without that a minor card in its last month (6 x 1.0 x 0.75 = 4.5) loses to an
## election three months away (9 x 0.7 = 6.3) and the briefing names three things
## while the clock waits on a fourth (GLM's finding 2). The score fills the rest.
## Five standing reads (the election or term end, the majority, the weakest polled
## bloc, the budget, unrest) exist in every state at weight 1, so the three always
## fill; the spec names three of them, and the two more are what lets a quiet month
## rotate under the novelty rule instead of printing the same three lines (OPINION).
##
## **Memory is the caller's.** rank() returns the memory to hand back next month
## (last month's lines, each trend's onset, the unrest readings): presentation memory,
## never GameState, so the first briefing after a load reads novelty 1 everywhere.

const K = preload("res://src/ui/priorities_constants.gd")
const Events = preload("res://src/sim/events.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const President = preload("res://src/sim/president.gd")
const Statute = preload("res://src/sim/statute.gd")
const Government = preload("res://src/sim/government.gd")
const AudienceK = preload("res://src/sim/audience_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const Trends = preload("res://src/ui/trends.gd")


## {lines: exactly three {kind, subject, deadline_month (-1: none), score, u, m,
## held, standing, more, go: {tab, subject}}, memory: what to pass back next month,
## qualified: the kinds that had a candidate, also_due: the crowded-out items in
## their last month, same shape as a line}.
## opts: `memory` (the last call's), `held_events` (the event ids that hold the
## clock now; absent, read from the desk by the spec's rule), `programme_held`.
static func rank(state, loader, opts := {}) -> Dictionary:
	var ns = state.player() if state != null else null
	if ns == null:
		return {"lines": [], "memory": {}}
	var now := int(state.year) * 12 + int(state.month)
	var memory: Dictionary = (opts.get("memory", {}) as Dictionary).duplicate(true)
	_remember_unrest(memory, now, float(ns.unrest_pct))
	var onsets: Dictionary = memory.get("onsets", {})
	var cands: Array = []
	var held: Array = []
	_desk(ns, loader, now, opts, cands, held)
	if bool(opts.get("programme_held", not Programme.available(state, ns, loader).is_empty())):
		held.append(_cand("programme", "offer", now, K.WEIGHT["programme"], 1.0, now))
	_election(state, ns, now, cands)
	_bills(ns, now, cands)
	_majority(ns, now, onsets, cands)
	_commitments(ns, now, cands)
	_requests(ns, now, cands)
	_programme(state, ns, loader, now, cands)
	_blocs(state, ns, now, onsets, cands)
	_budget(state, now, onsets, cands)
	_unrest(memory, now, onsets, cands)
	_people(ns, now, cands)
	var next_onsets := {}
	for c in cands:
		if bool(c["trend"]):
			next_onsets[_key(c)] = int(onsets.get(_key(c), now))
	memory["onsets"] = next_onsets
	var lines := _pick(held, cands, memory.get("last", []), now)
	var also_due := _also_due(lines, held + cands, now)
	memory["last"] = lines.map(func(l): return {"kind": l["kind"], "subject": l["subject"], "u": l["u"], "m": l["m"]})
	# `qualified`: every kind that had a candidate this month, held included, in row
	# order -- RF2's "every kind that qualifies appears at least once" (Systems' probe).
	var seen := {}
	for c in held + cands:
		seen[String(c["kind"])] = true
	return {"lines": lines, "memory": memory, "qualified": K.KINDS.filter(func(k): return seen.has(k)),
		"also_due": also_due}


## The parent's rule on Systems' RF2 finding (#217): an item in its last month is
## never unshown. Three lines stay three; whatever dated item they crowded out in its
## last month (a request that lapses next month, a card's last month, a promise
## judged now) goes to the card's footer, "Also due this month", in rank order.
static func _also_due(lines: Array, all: Array, now: int) -> Array:
	var shown := {}
	for l in lines:
		shown[_key(l)] = true
	var out: Array = []
	for c in all:
		var left := int(c["deadline_month"]) - now
		if bool(c["standing"]) or int(c["deadline_month"]) < 0 or left < 0 or left > 1 or shown.has(_key(c)):
			continue
		shown[_key(c)] = true
		out.append(c)
	return out


## Whether every line is a standing read: the card's "A quiet month".
static func quiet(lines: Array) -> bool:
	return lines.all(func(l): return bool(l["standing"]))


## The surfaces that hold the clock at this boundary by the spec's rule (2.3), for a
## caller with no UI to ask (Systems' probe): an interrupt, a major desk entry on its
## arrival month, a minor one in its last month (main.gd re-holds only a quiet
## arrival through its lapse guard: a major's hold ended when its card was seen --
## Systems on #217), the term-start offer. The game hands
## rank() main's own unseen set instead. An election result is not here: it owns the
## pause before the briefing opens, and is no line of it.
static func held_by_rule(state, loader) -> Dictionary:
	var ns = state.player()
	var events: Array = []
	for entry in ns.event_queue:
		if _holds_by_rule(entry, loader):
			events.append(String(entry.get("event_id", "")))
	return {"events": events, "programme": not Programme.available(state, ns, loader).is_empty()}


## The chief's line and the music read the month by its three (2.6): crisis when one
## is a crisis; tense when one is held, or weighs 6 or more with its deadline 3
## months away or less; calm otherwise. An election is not a crisis: weight alone
## would play the crisis line for six months before every vote.
static func situation(lines: Array) -> String:
	if lines.any(func(l): return String(l["kind"]) == "crisis"):
		return "crisis"
	for l in lines:
		var near := int(l["deadline_month"]) >= 0 and not bool(l["standing"]) and float(l["u"]) >= K.TREND_ONSET
		if bool(l["held"]) or (near and float(l["w"]) >= K.WEIGHT["decision_minor"]):
			return "tense"
	return "calm"


# --- choosing three -------------------------------------------------------------------

static func _pick(held: Array, cands: Array, last: Array, now: int) -> Array:
	var lines: Array = []
	var used := {}
	# Held surfaces first, folded by kind in their own order; past three kinds the
	# third line carries the count of the rest.
	for h in held:
		var kind := String(h["kind"])
		if used.has(kind):
			_fold_into(used[kind], h)
		elif lines.size() < 3:
			h["held"] = true
			lines.append(h)
			used[kind] = h
		else:
			_fold_into(lines[2], h)
	for c in cands:
		c["score"] = float(c["w"]) * float(c["u"]) * float(c["m"]) * _novelty(c, last, now)
	cands.sort_custom(_before)
	for c in cands:
		var kind := String(c["kind"])
		if used.has(kind):
			# A second of a held or chosen kind is "+1 more" on its line; a standing
			# read never counts as one more of a real one.
			if not bool(c["standing"]) and not bool(used[kind]["standing"]) and _key(c) != _key(used[kind]):
				_fold_into(used[kind], c)
			continue
		if lines.size() < 3:
			lines.append(c)
			used[kind] = c
	return lines


## One more of `c` on `line`'s "+N more", and which one: the briefing has told the
## player it exists, so its close counts a folded request as seen (the parent's call
## on QA's #218 RECORD), the same as a request on a line.
static func _fold_into(line: Dictionary, c: Dictionary) -> void:
	line["more"] = int(line["more"]) + 1
	if not line.has("folded"):
		line["folded"] = []
	(line["folded"] as Array).append({"kind": String(c["kind"]), "subject": String(c["subject"])})


static func _novelty(c: Dictionary, last: Array, now: int) -> float:
	var dated := int(c["deadline_month"]) >= 0
	if dated and int(c["deadline_month"]) - now <= K.NO_DAMPING_MONTHS:
		return 1.0
	for l in last:
		if String(l["kind"]) == String(c["kind"]) and String(l["subject"]) == String(c["subject"]):
			var rose := float(c["u"]) > float(l.get("u", 0.0)) + 1e-6 or float(c["m"]) > float(l.get("m", 0.0)) + 1e-6
			return 1.0 if rose else K.NOVELTY
	return 1.0


## Higher score, then higher weight, the sooner deadline, the kind's row order and
## the subject id: a stable key, never a rule that names an id.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["score"]), float(b["score"])):
		return float(a["score"]) > float(b["score"])
	if not is_equal_approx(float(a["w"]), float(b["w"])):
		return float(a["w"]) > float(b["w"])
	var da := int(a["deadline_month"]) if int(a["deadline_month"]) >= 0 else 1 << 30
	var db := int(b["deadline_month"]) if int(b["deadline_month"]) >= 0 else 1 << 30
	if da != db:
		return da < db
	var ra := K.KINDS.find(String(a["kind"]))
	var rb := K.KINDS.find(String(b["kind"]))
	if ra != rb:
		return ra < rb
	return String(a["subject"]) < String(b["subject"])


# --- the candidates, each from a register the player sees -------------------------------

static func _desk(ns, loader, now: int, opts: Dictionary, cands: Array, held: Array) -> void:
	var holding: Array = opts.get("held_events", [])
	var by_rule := not opts.has("held_events")
	for entry in ns.event_queue:
		var sev := clampi(int(entry.get("severity", 1)), 1, 3)
		var left := int(entry.get("months_left", 0))
		var crisis := bool(entry.get("interrupt", false)) or sev >= K.CRISIS_SEVERITY
		var kind := "crisis" if crisis else "decision"
		var w: float = K.WEIGHT["crisis"] if crisis else (K.WEIGHT["decision_major"] if sev >= K.MAJOR_SEVERITY else K.WEIGHT["decision_minor"])
		var c := _cand(kind, String(entry.get("event_id", "")), now + left, w, K.SEVERITY_MAGNITUDE[sev - 1], now)
		var holds := holding.has(c["subject"]) if not by_rule else _holds_by_rule(entry, loader)
		(held if holds else cands).append(c)
	# The spec's hold order: an interrupt, then major cards, then the rest.
	held.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))


static func _holds_by_rule(entry: Dictionary, loader) -> bool:
	var left := int(entry.get("months_left", 0))
	if bool(entry.get("interrupt", false)):
		return true
	if int(entry.get("severity", 1)) >= K.MAJOR_SEVERITY:
		# Its arrival month: the clock has not taken a month off its window yet.
		var ev = Events.event_by_id(loader, String(entry.get("event_id", ""))) if loader != null else null
		return ev != null and left >= int(ev.respond_months)
	return left <= 1


static func _election(state, ns, now: int, cands: Array) -> void:
	var dates := {"national": Trends.vote_date(ns), "ep": Vector2i(int(ns.next_ep_election_year), int(ns.next_ep_election_month))}
	var best := ""
	for subject in dates:
		var when: Vector2i = dates[subject]
		if when.x > 0 and (best == "" or when.x * 12 + when.y < dates[best].x * 12 + dates[best].y):
			best = subject
	if best == "":
		return  # no vote: unrest stands in for it, below
	var month: int = dates[best].x * 12 + dates[best].y
	if month - now <= K.ELECTION_NEAR_MONTHS:
		cands.append(_cand("election", best, month, K.WEIGHT["election"], 1.0, now))
	else:
		cands.append(_standing("election", best, month))


static func _bills(ns, now: int, cands: Array) -> void:
	var tabled: Dictionary = ns.tabled_bill
	if not tabled.is_empty():
		var month := int(tabled.get("vote_year", 0)) * 12 + int(tabled.get("vote_month", 0))
		cands.append(_cand("bill", String(tabled.get("law_id", "")), month, K.WEIGHT["bill"], 1.0, now))
	for draft_id in ns.draft_bills:
		var left := int((ns.draft_bills[draft_id] as Dictionary).get("months_left", 0))
		if left > 0:
			cands.append(_cand("bill", String(draft_id), now + left, K.WEIGHT["bill"], 1.0, now))


static func _majority(ns, now: int, onsets: Dictionary, cands: Array) -> void:
	if int(ns.assembly_seats) <= 0:
		return
	if bool(ns.in_government) and int(ns.coalition_seats) <= Government.majority_seats(ns):
		cands.append(_trend("majority", "seats", K.WEIGHT["majority"], 1.0, onsets, now))
	cands.append(_standing("majority", "seats"))


static func _commitments(ns, now: int, cands: Array) -> void:
	for row in President.commitments(ns):
		var due := int(row["due_month"])
		if due >= now:
			var subject := "%s|%s|%s" % [row["kind"], row["person_id"], row["object"]]
			cands.append(_cand("commitment", subject, due, K.WEIGHT["commitment"], 1.0, now))


static func _requests(ns, now: int, cands: Array) -> void:
	var own := "%s_" % ns.id
	for row in ns.audience_requests:
		var pid := String(row.get("person_id", ""))
		if String(row.get("status", "")) != AudienceK.STATUS_PENDING or not pid.begins_with(own):
			continue
		var m := clampf(0.5 + float(ns.person_standing.get(pid, 0.0)), K.MAGNITUDE_MIN, K.MAGNITUDE_MAX)
		cands.append(_cand("request", String(row.get("id", "")), int(row.get("deadline_month", now)), K.WEIGHT["request"], m, now))


static func _programme(state, ns, loader, now: int, cands: Array) -> void:
	for entry in Programme.this_term(ns):
		if String(entry["status"]) != ProgrammeK.STATUS_ACTIVE:
			continue
		var timeout := int(Programme.terms_of(loader, String(entry["entry_id"])).get("timeout_months", 0))
		if timeout > 0:
			var month := now + maxi(0, timeout - int(entry.get("months_live", 0)))
			cands.append(_cand("programme", String(entry["entry_id"]), month, K.WEIGHT["programme"], 1.0, now))


## Bloc approval only as the polls show it: each month's reading through PollNoise,
## the poll of that month, as the Society panel prints it.
static func _blocs(state, ns, now: int, onsets: Dictionary, cands: Array) -> void:
	var history: Array = state.history
	var weakest := ""
	var weakest_value := INF
	for bloc in OpinionK.BLOC_KEYS:
		var polled := PollNoise.displayed(now, bloc, float(ns.bloc_approval.get(bloc, 0.0)))
		if polled < weakest_value:
			weakest_value = polled
			weakest = bloc
		var n := K.BLOC_WINDOW
		if history.size() < 2 * n:
			continue
		var recent := _poll_mean(history, bloc, history.size() - n, n)
		var before := _poll_mean(history, bloc, history.size() - 2 * n, n)
		var moved := recent - before
		if absf(moved) > 2.0 * K.BLOC_MARGIN_POINTS:
			var m := clampf(absf(moved) / K.BLOC_POINTS_PER_UNIT, K.MAGNITUDE_MIN, K.MAGNITUDE_MAX)
			var c := _trend("bloc", bloc, K.WEIGHT["bloc"], m, onsets, now)
			c["moved"] = moved
			cands.append(c)
	if weakest != "":
		cands.append(_standing("bloc", weakest))


static func _poll_mean(history: Array, bloc: String, from: int, n: int) -> float:
	var total := 0.0
	for i in range(from, from + n):
		var e: Dictionary = history[i]
		var id := PollNoise.poll_id(int(e.get("year", 0)), int(e.get("month", 0)))
		total += PollNoise.displayed(id, bloc, float((e.get("bloc_approval", {}) as Dictionary).get(bloc, 0.0)))
	return total / float(n)


static func _budget(state, now: int, onsets: Dictionary, cands: Array) -> void:
	var history: Array = state.history
	if history.size() > K.DEFICIT_WINDOW_MONTHS:
		var rise := float(history[-1].get("deficit_pct_gdp", 0.0)) - float(history[-1 - K.DEFICIT_WINDOW_MONTHS].get("deficit_pct_gdp", 0.0))
		if rise >= K.DEFICIT_RISE_POINTS:
			var m := clampf(rise / K.DEFICIT_POINTS_PER_UNIT, K.MAGNITUDE_MIN, K.MAGNITUDE_MAX)
			cands.append(_trend("budget", "deficit", K.WEIGHT["budget"], m, onsets, now))
	cands.append(_standing("budget", "balance"))


static func _remember_unrest(memory: Dictionary, now: int, value: float) -> void:
	var readings: Array = memory.get("unrest", [])
	if readings.is_empty() or int(readings[-1][0]) != now:
		readings.append([now, value])
	while readings.size() > K.UNREST_RISING_MONTHS + 1:
		readings.pop_front()
	memory["unrest"] = readings


static func _unrest(memory: Dictionary, now: int, onsets: Dictionary, cands: Array) -> void:
	var readings: Array = memory["unrest"]
	var rising := readings.size() > K.UNREST_RISING_MONTHS
	for i in range(1, readings.size()):
		rising = rising and float(readings[i][1]) > float(readings[i - 1][1]) + 1e-6
	if rising:
		cands.append(_trend("unrest", "unrest", K.WEIGHT["unrest"], 1.0, onsets, now))
	cands.append(_standing("unrest", "unrest"))


static func _people(ns, now: int, cands: Array) -> void:
	for pid in ns.person_grudges:
		if float(ns.person_grudges[pid]) >= K.HOSTILE_GRUDGE:
			cands.append(_cand("person", String(pid), -1, K.WEIGHT["person"], 1.0, now, false))


# --- shapes -------------------------------------------------------------------------------

static func _cand(kind: String, subject: String, deadline: int, w: float, m: float, now: int, dated := true) -> Dictionary:
	var u := _urgency(deadline - now) if dated else K.TREND_AFTER
	return {"kind": kind, "subject": subject, "deadline_month": deadline if dated else -1, "w": w, "u": u,
		"m": clampf(m, K.MAGNITUDE_MIN, K.MAGNITUDE_MAX), "score": 0.0, "held": false, "standing": false,
		"trend": false, "more": 0, "go": {"tab": K.GO_TAB[kind], "subject": subject}}


static func _trend(kind: String, subject: String, w: float, m: float, onsets: Dictionary, now: int) -> Dictionary:
	var c := _cand(kind, subject, -1, w, m, now, false)
	c["trend"] = true
	c["u"] = K.TREND_ONSET if int(onsets.get(_key(c), now)) == now else K.TREND_AFTER
	return c


static func _standing(kind: String, subject: String, deadline := -1) -> Dictionary:
	var c := _cand(kind, subject, -1, K.STANDING_WEIGHT, 1.0, 0, false)
	c["u"] = K.STANDING_URGENCY
	c["standing"] = true
	c["deadline_month"] = deadline
	return c


static func _urgency(months: int) -> float:
	for step in K.URGENCY_STEPS:
		if months <= int(step[0]):
			return float(step[1])
	return K.URGENCY_FAR


static func _key(c: Dictionary) -> String:
	return "%s|%s" % [c["kind"], c["subject"]]
