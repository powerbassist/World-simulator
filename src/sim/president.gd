extends RefCounted

## The president's registers -- V5.2a. What has passed between this nation's
## leader and a person: how well they know each other, how they get on, the
## bond between them, the money, the promises in flight and the evidence left
## behind. The model is docs/people-model.md section 14.9; the design and the
## bands are docs/design/v5.2-spec.md and docs/design/bands-v5.2.md.
##
## THE ONLY WRITER of the nine NationState registers, and the only reader that
## combines them with content (tests/test_president.gd scans src/ for a second).
## A leaf: it preloads its constants and nothing else, and it rolls nothing --
## the seeded odds a lever reads are V5.2b's, the hazard evidence feeds V5.2c's.
##
## EVERY EDGE STARTS AT THE PRESIDENT (spec C1): there is no person-to-person
## register, and gossip about a third person writes the president's knowledge
## of that person. WHOM THE EDGES REACH is the author's call (2026-10-21,
## answer 1): the played nation's people plus the foreign heads of state and
## government -- covers() refuses everyone else, so a writer handed a stray id
## leaves every register untouched rather than growing an edge to 2 147 people.
##
## The registers are V5.2a's; the audiences (b) and the shadows (c) write them.
## On the tick path since V5.2b b2: the audience held (Audiences.hold) and the
## commitments judged at their date (Levers.tick_month).

const K = preload("res://src/sim/president_constants.gd")
const SC = preload("res://src/sim/shadow_constants.gd")


## Whether an edge from this nation's president to the person may exist: an
## authored person of this nation (the loader's id-prefix rule), or another
## nation's current head of state or of government -- the president meets
## heads, not their benches. Never the president themself: an edge needs two
## ends. Read at write time; an edge to a head who has since left office stays,
## because what passed between them still did.
static func covers(state, ns, loader, person_id: String) -> bool:
	if person_id == leader_id(ns):
		return false
	if _own(ns, loader, person_id):
		return true
	if not loader.person_by_id.has(person_id):
		return false
	for nation_id in state.nations:
		if nation_id == ns.id:
			continue
		var other = state.nations[nation_id]
		if person_id == String(other.head_of_state_person_id) or person_id == String(other.pm_person_id):
			return true
	return false


## Who "the president" is on this nation's register: the separately elected
## executive where there is one (France's head of state), else the head of
## government -- the office Elections' verdict decides.
static func leader_id(ns) -> String:
	return String(ns.head_of_state_person_id if ns.has_executive else ns.pm_person_id)


# --- Reads --------------------------------------------------------------------------

static func knowledge(ns, person_id: String) -> float:
	return float(ns.person_knowledge.get(person_id, 0.0))


## stranger | acquaintance | known, on B4's edges.
static func knowledge_band(ns, person_id: String) -> String:
	var k := knowledge(ns, person_id)
	if k >= K.KNOWLEDGE_KNOWN:
		return "known"
	if k >= K.KNOWLEDGE_ACQUAINTANCE:
		return "acquaintance"
	return "stranger"


static func rapport(ns, person_id: String) -> float:
	return float(ns.person_rapport.get(person_id, 0.0))


## The spec's relationship ladder, one answer: the stored bond where there is
## one, else stranger or acquaintance read off knowledge. A well-known person
## with no bond is an acquaintance -- knowing someone is not friendship.
static func relationship(ns, person_id: String) -> String:
	var bond := String(ns.person_bond.get(person_id, ""))
	if bond != "":
		return bond
	return "stranger" if knowledge(ns, person_id) < K.KNOWLEDGE_ACQUAINTANCE else "acquaintance"


## The authored start plus what the register moved. Unbounded below on purpose:
## whether the president can spend money they do not have is the spending
## verb's gate, not the register's.
static func wealth_eur_m(ns, loader, person_id: String) -> float:
	var person = loader.person_by_id.get(person_id)
	var start: float = person.wealth_eur_m if person != null else 0.0
	return start + float(ns.person_wealth_delta_eur_m.get(person_id, 0.0))


## This nation's parties only. Another id is an error and a zero, never a
## silent zero (V1.6d's confident-zero rule).
static func party_money_eur_m(ns, loader, party_id: String) -> float:
	var party = _party(ns, loader, party_id)
	if party == null:
		push_error("president: '%s' is not a party of %s" % [party_id, ns.id])
		return 0.0
	return party.funds_eur_m + float(ns.party_money_delta_eur_m.get(party_id, 0.0))


## Every commitment in flight to a person, months cast to int: the rows come
## back from a JSON save with every number a float (the pledges precedent --
## cast on every read), and the ROWS reader whitelists no key, so a key a
## hand-edited save dropped reads its empty value rather than erroring.
static func commitments_with(ns, person_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in ns.commitments:
		if String(row.get("person_id", "")) == person_id:
			out.append(_commitment(row))
	return out


## V5.2b b2. Every commitment in flight, cast as above, earliest due first (ties
## in the order they were made) -- the Diary's read: the author's "Oui, parole
## donnée" (2026-10-24) keeps a failed promise binding, and the player sees it.
static func commitments(ns) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in ns.commitments:
		out.append(_commitment(row))
	var order := range(out.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return out[a]["due_month"] < out[b]["due_month"] or (out[a]["due_month"] == out[b]["due_month"] and a < b))
	var sorted: Array[Dictionary] = []
	for i in order:
		sorted.append(out[i])
	return sorted


## V5.2b b2.1. The commitments judged at their date and still remembered, in
## judging order (oldest first): the Diary's record of a promise kept or a lie
## revealed after the month's report is gone. Cast like commitments(), plus
## {verdict, judged_month}. A "void" row may name a person content no longer
## carries -- the reason it was void -- so a reader resolves the id with care.
static func judged_commitments(ns) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in ns.commitments_judged:
		var view := _commitment(row)
		view["verdict"] = String(row.get("verdict", ""))
		view["judged_month"] = int(row.get("judged_month", 0))
		out.append(view)
	return out


## The evidence held against the president, summed -- what V5.2c's exposure
## hazard rises with.
static func evidence_size(ns) -> float:
	var total := 0.0
	for row in ns.exposure_evidence:
		total += float(row.get("size", 0.0))
	return total


## V5.2c. Who left an evidence row: the president it names, or -- a row from
## before c, which named nobody -- the sitting one.
static func evidence_leader(ns, row: Dictionary) -> String:
	var who := String(row.get("leader_id", ""))
	return who if who != "" else leader_id(ns)


## V5.2c. Every exposure, cast the way commitments() casts.
static func exposures(ns) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in ns.exposures:
		out.append({
			"kind": String(row.get("kind", "")),
			"route": String(row.get("route", "")),
			"person_id": String(row.get("person_id", "")),
			"size": float(row.get("size", 0.0)),
			"made_month": int(row.get("made_month", 0)),
			"exposed_month": int(row.get("exposed_month", 0)),
			"leader_id": String(row.get("leader_id", "")),
		})
	return out


# --- Writers (the only ones) ----------------------------------------------------------

## Knowledge moves both ways: a lie caught collapses it (spec, the lies table).
static func learn(state, ns, loader, person_id: String, amount: float) -> bool:
	if not covers(state, ns, loader, person_id):
		return false
	ns.person_knowledge[person_id] = clampf(knowledge(ns, person_id) + amount, 0.0, 1.0)
	return true


## V5.2b b2. What the audience teaches: `amount` times what is left to learn, so
## a well-known person teaches less (B4: acquaintance in 2-5 audiences, known in
## at least 8). The one door for the curve -- the audience held and each topic --
## so the two cannot drift. What it wrote.
static func learn_from(state, ns, loader, person_id: String, amount: float) -> float:
	var before := knowledge(ns, person_id)
	learn(state, ns, loader, person_id, amount * (1.0 - before))
	return knowledge(ns, person_id) - before


static func adjust_rapport(state, ns, loader, person_id: String, amount: float) -> bool:
	if not covers(state, ns, loader, person_id):
		return false
	ns.person_rapport[person_id] = clampf(rapport(ns, person_id) + amount, -1.0, 1.0)
	return true


## One of K.BONDS, or "" to clear back to the knowledge-read relationship.
static func set_bond(state, ns, loader, person_id: String, bond: String) -> bool:
	if not covers(state, ns, loader, person_id):
		return false
	if bond == "":
		ns.person_bond.erase(person_id)
		return true
	if not K.BONDS.has(bond):
		return false
	ns.person_bond[person_id] = bond
	return true


## The president's own money is keyed by person rather than held as one scalar,
## so a successor never inherits a deposed leader's gains. This nation's people
## only: a foreign head's fortune is not on this register.
static func adjust_wealth_eur_m(ns, loader, person_id: String, amount: float) -> bool:
	if not _own(ns, loader, person_id):
		return false
	ns.person_wealth_delta_eur_m[person_id] = float(ns.person_wealth_delta_eur_m.get(person_id, 0.0)) + amount
	return true


static func adjust_party_money_eur_m(ns, loader, party_id: String, amount: float) -> bool:
	if _party(ns, loader, party_id) == null:
		return false
	ns.party_money_delta_eur_m[party_id] = float(ns.party_money_delta_eur_m.get(party_id, 0.0)) + amount
	return true


## A promise or an IOU to a covered person, due in a LATER month: a date already
## reached could not be kept, so it is refused rather than broken on arrival.
## `object` is what was promised, in the want grammar's own words
## ("programme:<id>", "office:<...>") so a keeper can judge it against the want.
## Pre-gate B, CALL 2: the command that seeds the played nation's people's draws
## (NationState.draw_seed, its one writer). The UI calls it once at a new game with
## a fresh seed; a loaded game keeps the one it was saved with.
static func seed_draws(state, draw_seed: int) -> void:
	state.player().draw_seed = draw_seed


## V5.2c: `lie` marks a promise the president never meant (src/sim/lies.gd); the
## key is written only when true, so an honest row is the row b2 wrote.
static func commit(state, ns, loader, kind: String, person_id: String, object: String, due_month: int, lie := false) -> bool:
	if not K.COMMITMENT_KINDS.has(kind) or object == "" or due_month <= _now(state):
		return false
	if not covers(state, ns, loader, person_id):
		return false
	var row := {
		"kind": kind,
		"person_id": person_id,
		"object": object,
		"made_month": _now(state),
		"due_month": due_month,
	}
	if lie:
		row["lie"] = true
	ns.commitments.append(row)
	return true


## V5.2c. A commitment in flight taken back unjudged -- a promise caught as a lie
## is no promise (Lies.settle). The first row of that kind, person and object.
static func withdraw_commitment(ns, kind: String, person_id: String, object: String) -> bool:
	for index in ns.commitments.size():
		var row: Dictionary = ns.commitments[index]
		if String(row.get("kind", "")) == kind and String(row.get("person_id", "")) == person_id and String(row.get("object", "")) == object:
			ns.commitments.remove_at(index)
			return true
	return false


## V5.2b b2. Every commitment due by `now`, taken off the register in its order
## and cast the way commitments_with() casts: the judge (Levers.tick_month)
## prices each once, so no row outlives its date and none is judged twice.
static func take_commitments_due(ns, now: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	var later: Array[Dictionary] = []
	for row in ns.commitments:
		if int(row.get("due_month", 0)) > now:
			later.append(row)
		else:
			due.append(_commitment(row))
	ns.commitments = later
	return due


## V5.2b b2.1. A commitment taken off by take_commitments_due(), remembered with
## its verdict -- one of K.VERDICTS -- for the Diary.
static func record_judged(ns, row: Dictionary, verdict: String, now: int) -> bool:
	if not K.VERDICTS.has(verdict):
		return false
	var judged := _commitment(row)
	judged["verdict"] = verdict
	judged["judged_month"] = now
	ns.commitments_judged.append(judged)
	return true


## The judged commitments older than JUDGED_KEPT_MONTHS are forgotten.
static func prune_judged(ns, now: int) -> void:
	if ns.commitments_judged.is_empty() or now - int(ns.commitments_judged[0].get("judged_month", 0)) <= K.JUDGED_KEPT_MONTHS:
		return
	var kept: Array[Dictionary] = []
	for row in ns.commitments_judged:
		if now - int(row.get("judged_month", 0)) <= K.JUDGED_KEPT_MONTHS:
			kept.append(row)
	ns.commitments_judged = kept


static func leave_evidence(state, ns, loader, kind: String, person_id: String, size: float) -> bool:
	if not K.EVIDENCE_KINDS.has(kind) or size <= 0.0:
		return false
	if not covers(state, ns, loader, person_id):
		return false
	ns.exposure_evidence.append({
		"kind": kind,
		"person_id": person_id,
		"size": size,
		"month": _now(state),
		"leader_id": leader_id(ns),
	})
	return true


## V5.2c. Evidence that accrues -- the affair's monthly share: `amount` onto the
## sitting president's open row of that kind and person, else a new row. A
## predecessor's row is theirs and is never grown (the plan's Call 6).
static func grow_evidence(state, ns, loader, kind: String, person_id: String, amount: float) -> bool:
	if not K.EVIDENCE_KINDS.has(kind) or amount <= 0.0:
		return false
	if not covers(state, ns, loader, person_id):
		return false
	for row in ns.exposure_evidence:
		if String(row.get("kind", "")) == kind and String(row.get("person_id", "")) == person_id 				and evidence_leader(ns, row) == leader_id(ns):
			row["size"] = float(row.get("size", 0.0)) + amount
			return true
	return leave_evidence(state, ns, loader, kind, person_id, amount)


## V5.2c. Evidence found out: exposure_evidence[index] moves to `exposures`,
## stamped with its route and month. {} -- nothing written -- for a bad index, a
## route outside SC.ROUTES, or one that cannot reach the row's kind.
static func expose_evidence(ns, index: int, route: String, now: int) -> Dictionary:
	if index < 0 or index >= ns.exposure_evidence.size():
		return {}
	var row: Dictionary = ns.exposure_evidence[index]
	if not SC.ROUTE_KINDS.get(route, []).has(String(row.get("kind", ""))):
		return {}
	var exposed := {
		"kind": String(row.get("kind", "")),
		"route": route,
		"person_id": String(row.get("person_id", "")),
		"size": float(row.get("size", 0.0)),
		"made_month": int(row.get("month", 0)),
		"exposed_month": now,
		"leader_id": evidence_leader(ns, row),
	}
	ns.exposure_evidence.remove_at(index)
	ns.exposures.append(exposed)
	return exposed.duplicate()


# --- Helpers ----------------------------------------------------------------------------

## A commitment row as every reader gets it: the months cast to int, a dropped
## key read as its empty value.
static func _commitment(row: Dictionary) -> Dictionary:
	var view := {
		"kind": String(row.get("kind", "")),
		"person_id": String(row.get("person_id", "")),
		"object": String(row.get("object", "")),
		"made_month": int(row.get("made_month", 0)),
		"due_month": int(row.get("due_month", 0)),
	}
	if bool(row.get("lie", false)):
		view["lie"] = true
	return view


## An authored person of this nation: the loader's id-prefix rule.
static func _own(ns, loader, person_id: String) -> bool:
	return loader.person_by_id.has(person_id) and person_id.begins_with("%s_" % ns.id)


static func _party(ns, loader, party_id: String):
	for party in loader.parties.get(ns.id, []):
		if party.id == party_id:
			return party
	return null


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
