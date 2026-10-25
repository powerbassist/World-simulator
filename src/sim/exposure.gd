extends RefCounted

## The exposure machine -- V5.2c. Once a month, per route, a seeded hazard that
## the sitting president's evidence is found out. The design is
## docs/design/v5.2-spec.md ("Corruption, in the author's four currencies", C7);
## the band is bands-v5.2.md B6; every number is in shadow_constants.gd.
##
## hazard = clampf(RATE[route] * reach * modifier, 0, HAZARD_MAX), where reach is
## the summed size x EVIDENCE_WEIGHT of the rows the route can reach (ROUTE_KINDS):
## the SITTING president's rows only -- a predecessor's affair is not this desk's
## (the plan's Call 6) -- and, for a turned person, only rows whose person is now a
## rival or an enemy and still covered (an ex-head out of office cannot turn, but
## the press and the courts can still find what passed between them). The modifier:
## the press rises with the share of hostile press owners; the courts read judicial
## independence on its 0-100 scale, divided by 100 (the plan wrote the raw field,
## which at France's 73.8 would make the courts seventy times every other route --
## and a captured court, at 0, prosecutes nobody, spec C7); the auditors and a
## turned person, 1.
##
## A hit moves the heaviest reachable row (ties: the first) to `exposures` and arms
## its scandal for next month through the CHAIN door, Events.arm, which waits on a
## full desk; the hook door would skip it for good. A (route, kind) pair content
## has no event for is still exposed -- the finding out is the fact -- and its row
## says event_id "", which the shadows probe counts as a content gap.
##
## The played nation only: the AI nations carry no shadows (spec C12). No rand():
## each route rolls Cycle.unit on its own salt and the absolute month, so a month
## with nothing to reach skips its roll and shifts no later draw (I1), and a game
## with no evidence pays nothing for this file.

const Cut = preload("res://src/core/cut.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Events = preload("res://src/sim/events.gd")
const JK = preload("res://src/sim/judiciary_constants.gd")
const President = preload("res://src/sim/president.gd")
const SC = preload("res://src/sim/shadow_constants.gd")

const TURNED_BONDS := ["rival", "enemy"]


## The month's exposures, in route order: each the `exposures` row plus its
## event_id ("" when content has no scandal for the pair). At most one a route.
static func tick_month(state, loader) -> Array[Dictionary]:
	var made: Array[Dictionary] = []
	var ns = state.player()
	if ns == null or ns.exposure_evidence.is_empty():
		return made
	var now := int(state.year) * 12 + int(state.month)
	for route in SC.ROUTES:
		var h := hazard(state, ns, loader, route)
		if h <= 0.0 or roll(ns, route, now) >= h:
			continue
		var row := President.expose_evidence(ns, _heaviest(state, ns, loader, route), route, now)
		var ev = Events.exposure_event(loader, route, String(row["kind"]))
		row["event_id"] = "" if ev == null else String(ev.id)
		if ev != null:
			Events.arm(ns, loader, String(ev.id), now + 1)
		made.append(row)
	return made


## This month's chance that `route` finds something. Public for the probe.
static func hazard(state, ns, loader, route: String) -> float:
	var x := pressure(state, ns, loader, route)
	return 0.0 if x <= 0.0 else clampf(float(SC.RATE[route]) * x, 0.0, SC.HAZARD_MAX)


## reach x modifier: the hazard before its RATE and ceiling -- the shadows probe
## traces it so a RATE can be re-priced without re-running the world.
static func pressure(state, ns, loader, route: String) -> float:
	var reach := 0.0
	for index in _reachable(state, ns, loader, route):
		reach += _weight(ns.exposure_evidence[index])
	return 0.0 if reach <= 0.0 else reach * _modifier(ns, loader, route)


## The route's draw this month, in [0, 1): a hit when below the hazard. Public so
## the shadows probe rolls exactly what the machine rolls.
static func roll(ns, route: String, now: int) -> float:
	return Cycle.unit(Cycle.salted("%s|exposure|%s" % [ns.id, route], ns.draw_seed), now)


## Indices into exposure_evidence that `route` can reach now.
static func _reachable(state, ns, loader, route: String) -> Array[int]:
	var kinds: Array = SC.ROUTE_KINDS.get(route, [])
	var leader := President.leader_id(ns)
	var out: Array[int] = []
	for index in ns.exposure_evidence.size():
		var row: Dictionary = ns.exposure_evidence[index]
		if not kinds.has(String(row.get("kind", ""))) or President.evidence_leader(ns, row) != leader:
			continue
		var pid := String(row.get("person_id", ""))
		if route == "turned" and not (President.covers(state, ns, loader, pid) \
				and TURNED_BONDS.has(President.relationship(ns, pid))):
			continue
		out.append(index)
	return out


static func _heaviest(state, ns, loader, route: String) -> int:
	var best := -1
	var best_weight := -1.0
	for index in _reachable(state, ns, loader, route):
		var w := _weight(ns.exposure_evidence[index])
		if w > best_weight:
			best = index
			best_weight = w
	return best


static func _weight(row: Dictionary) -> float:
	return float(row.get("size", 0.0)) * float(SC.EVIDENCE_WEIGHT.get(String(row.get("kind", "")), 0.0))


static func _modifier(ns, loader, route: String) -> float:
	match route:
		"press":
			return SC.PRESS_BASE + SC.PRESS_HOSTILE * _hostile_press(ns, loader)
		"courts":
			return clampf(ns.judicial_independence / JK.INDEPENDENCE_MAX, 0.0, 1.0)
	return 1.0


## The share of the nation's press owners against the president: below zero
## rapport, or holding the grudge that promises a leak. 0 with no press owner.
static func _hostile_press(ns, loader) -> float:
	var owners := 0
	var hostile := 0
	for person in loader.people.get(ns.id, []):
		if String(person.kind) != "press_owner":
			continue
		owners += 1
		var pid := String(person.id)
		if Cut.below(President.rapport(ns, pid), 0.0) \
				or Cut.at_or_above(float(ns.person_grudges.get(pid, 0.0)), SC.PRESS_GRUDGE_HOSTILE):
			hostile += 1
	return 0.0 if owners == 0 else float(hostile) / float(owners)
