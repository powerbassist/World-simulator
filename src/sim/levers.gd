extends RefCounted

## The audience -- V5.2b, second half. WORK IN PROGRESS: SIGNATURES ONLY.
##
## This file fixes the command surface the scene UI builds against
## (.superpowers/sdd/v5.2b-plan.md, "THE COMMAND SURFACE"); every body returns
## the shape its caller reads with nothing in it, and every command refuses with
## "not built yet". b2 replaces the bodies, test-first; the names, the
## parameters and the returned keys stay as they are here.
##
## The session is a Dictionary the scene holds and hands back on every call
## (summits-model section 2: a scene is ephemeral, never saved); what it changes
## lands in the registers (President, Characters, Audiences).

const NOT_BUILT := "not built yet"

## The six levers, in the order the scene lists them.
const LEVERS := ["argue", "bargain", "promise_date", "pressure", "flatter", "friendship"]

## The other topics.
const TOPICS := ["family", "opinion", "gossip", "dinner", "flirt"]


## The booked day has come: the session for the scene, or {} when the request is
## not booked. The session carries at least {request_id, person_id,
## attempts_left (3), used_topics: Array}.
static func open(state, ns, loader, request_id: String) -> Dictionary:
	return {}


## [{lever, offered: bool, why_not: String, odds_lo: float, odds_hi: float,
##   fog: "stranger" | "acquaintance" | "known", spends: Dictionary}]
static func offered(state, ns, loader, session: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	return out


## [{topic, offered: bool, why_not: String, spends: Dictionary}]
static func topics(state, ns, loader, session: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	return out


## {ok, error, success: bool, spent: Dictionary, effects: Dictionary}
static func attempt(state, ns, loader, session: Dictionary, lever: String, args := {}) -> Dictionary:
	return {"ok": false, "error": NOT_BUILT, "success": false, "spent": {}, "effects": {}}


## {ok, error, effects: Dictionary}
static func talk(state, ns, loader, session: Dictionary, topic: String, args := {}) -> Dictionary:
	return {"ok": false, "error": NOT_BUILT, "effects": {}}


## {ok, error, outcome: "settled" | "promised" | "declined", price: Dictionary}
static func close(state, ns, loader, session: Dictionary) -> Dictionary:
	return {"ok": false, "error": NOT_BUILT, "outcome": "", "price": {}}


## The phone (b3): one lever attempt or one topic, no diary day. Named `phone`,
## not `call`: a static `call` overrides Object.call() and does not parse.
static func phone(state, ns, loader, person_id: String, lever_or_topic: String, args := {}) -> Dictionary:
	return {"ok": false, "error": NOT_BUILT}


## The traits the president knows; a hidden trait is absent, never wrong.
static func known_traits(ns, person) -> Array[String]:
	var out: Array[String] = []
	return out
