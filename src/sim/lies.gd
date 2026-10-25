extends RefCounted

## Lies -- V5.2c. A lie on argue or on a promised date raises that attempt's odds by
## LIE_ODDS; the listener's reading skill against the president's decides whether it
## is caught there and then, on a roll of its own (no other roll moves). A promise
## the scene did not catch carries `lie` on its commitment row, and Levers' judge
## reveals it at its date with no roll, served or not (B8's third row). Caught or
## revealed, the price is reveal(): b2's broken-promise price, unchanged, in one
## function, so a caught lie and a broken date are never priced two ways. An
## uncaught lie leaves no evidence (the plan's Call 4): its risk is the catch and
## the date. The audience only; the phone takes none (Call 8).
##
## A caught lie also fails the attempt (#170's call 5, Gameplay #171): being seen
## through and persuaded at once is the one outcome a player cannot read. B5 prices a
## lie at (1 - P(caught)) x (p + LIE_ODDS) - P(caught) x the reveal.

const K = preload("res://src/sim/lever_constants.gd")
const SC = preload("res://src/sim/shadow_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const President = preload("res://src/sim/president.gd")


static func catch_chance(listener_skill: float, president_skill: float) -> float:
	return clampf(SC.LIE_CATCH_BASE + SC.LIE_CATCH_SLOPE * (listener_skill - president_skill), SC.LIE_CATCH_MIN, SC.LIE_CATCH_MAX)


## Whether `args` tells a lie on a lever that takes one.
static func told(lever: String, args: Dictionary) -> bool:
	return bool(args.get("lie", false)) and SC.LIE_LEVERS.has(lever)


static func odds_bonus(lever: String, args: Dictionary) -> float:
	return SC.LIE_ODDS if told(lever, args) else 0.0


## The card's lie variant of a lever row: the range at the raised odds, B4's fog.
static func lie_row(ns, person, lever: String, p: float, knowledge: float) -> Dictionary:
	var r := Vector2.ZERO if p < 0.0 else LeverOdds.shown_range(person.id, lever, clampf(p + SC.LIE_ODDS, K.ODDS_MIN, K.ODDS_MAX), knowledge, ns.draw_seed)
	return {"odds_lo": r.x, "odds_hi": r.y}


## The catch roll for attempt `index`: the request, the lever and the index under
## SALT_LIE, and the month -- the lever roll's own shape on a salt of its own.
static func caught(state, ns, loader, session: Dictionary, lever: String, index: int) -> bool:
	var person = loader.person_by_id.get(String(session.get("person_id", "")))
	var leader = loader.person_by_id.get(President.leader_id(ns))
	if person == null or leader == null:
		return false
	var p := catch_chance(float(person.social_skill), float(leader.social_skill))
	var key := Cycle.salted("%s:%s:%d" % [SC.SALT_LIE, lever, index], ns.draw_seed)
	return Cycle.unit_pair(String(session.get("request_id", "")), key, int(state.year) * 12 + int(state.month)) < p


## After an attempt's roll: a lie told and caught is revealed now, and a promise
## caught as a lie is no promise (withdrawn, so its date prices nothing again).
## Whether it was caught; the reveal's price lands in `effects["revealed"]`.
static func settle(state, ns, loader, session: Dictionary, person, lever: String, args: Dictionary, index: int, effects: Dictionary) -> bool:
	if not told(lever, args) or not caught(state, ns, loader, session, lever, index):
		return false
	if lever == "promise_date":
		President.withdraw_commitment(ns, "promise", String(person.id), String(session.get("object", "")))
	effects["revealed"] = reveal(state, ns, loader, person)
	return true


## A lie found out: rapport falls LIE_RAPPORT, knowledge keeps LIE_KNOWLEDGE_KEEP of
## itself, a LIE_GRUDGE pulse -- in b2's order. What it wrote.
static func reveal(state, ns, loader, person) -> Dictionary:
	var pid := String(person.id)
	var rapport := President.rapport(ns, pid)
	var knowledge := President.knowledge(ns, pid)
	President.adjust_rapport(state, ns, loader, pid, -K.LIE_RAPPORT)
	President.learn(state, ns, loader, pid, -knowledge * (1.0 - K.LIE_KNOWLEDGE_KEEP))
	var applied: Dictionary = Characters.price_refusal(ns, person, K.LIE_GRUDGE, 0.0)
	applied["rapport"] = President.rapport(ns, pid) - rapport
	applied["knowledge"] = President.knowledge(ns, pid) - knowledge
	return applied
