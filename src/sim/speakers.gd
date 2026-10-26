extends RefCounted

## Who brings an event to the president -- V5.2d, docs/design/v5.2-d-spec.md
## section 3. An event's authored `speaker` form (src/core/event.gd) becomes a
## person id at DELIVERY: Events._deliver calls resolve() and stores the id on the
## desk entry, so the face does not change while the card waits (D6). "" is the
## narrator: no form, or no person qualifies.
##
## PRESENTATION ONLY. Nothing in src/sim/ reads the stored id back and nothing here
## writes a register, so the balance table cannot move (D10). The rule reads kinds,
## offices and registers, never a nation or a person id (rule 1), and it never
## returns the president: an office the president holds falls to the head of
## government, and a person pool drops the president before it ranks anyone.
##
## The kind draw is Cycle.unit on its own salt over the event and the absolute
## month, under the game's draw seed -- a pure read like the hazard's, so it
## consumes no stream and shifts no other draw (I1).

const Cycle = preload("res://src/sim/cycle.gd")
const Government = preload("res://src/sim/government.gd")
const President = preload("res://src/sim/president.gd")
const Relations = preload("res://src/core/relations.gd")
const K = preload("res://src/sim/events_constants.gd")
const OrgsK = preload("res://src/sim/orgs_constants.gd")


static func resolve(state, ns, loader, ev, month_index: int) -> String:
	var form: Dictionary = ev.speaker
	if form.has("kind"):
		return _of_kind(ns, loader, ev, String(form["kind"]), String(form.get("pick", "")), month_index)
	if form.has("office"):
		return _office(ns, loader, String(form["office"]))
	if form.has("evidence_person"):
		return _witness(ns, loader, ev)
	if form.has("foreign_head"):
		return _foreign_head(state, ns, loader, ev)
	return ""


## Of the nation's people of `kind`, the president dropped: with a pick, the
## lowest (hostile) or highest (friendly) rapport, ties to id; without one, one of
## the three with the highest standing, ties to id, by the seeded draw -- a few
## faces recur so the player learns them, without one voicing every strike.
static func _of_kind(ns, loader, ev, kind: String, pick: String, month_index: int) -> String:
	var leader := President.leader_id(ns)
	var ids: Array = []
	for person in loader.people.get(ns.id, []):
		if String(person.kind) == kind and String(person.id) != leader:
			ids.append(String(person.id))
	if ids.is_empty():
		return ""
	if pick != "":
		var sign := -1.0 if pick == "hostile" else 1.0
		ids.sort_custom(func(a, b):
			var ra := sign * President.rapport(ns, a)
			var rb := sign * President.rapport(ns, b)
			return ra > rb if ra != rb else a < b)
		return ids[0]
	ids.sort_custom(func(a, b):
		var sa := float(ns.person_standing.get(a, 0.0))
		var sb := float(ns.person_standing.get(b, 0.0))
		return sa > sb if sa != sb else a < b)
	var pool := mini(ids.size(), K.SPEAKER_POOL)
	var draw := Cycle.unit(Cycle.salted("%s|%s|%s" % [ns.id, ev.id, K.SPEAKER_SALT], ns.draw_seed), month_index)
	return ids[mini(int(draw * float(pool)), pool - 1)]


## The holder of an office. One the president holds is skipped for the head of
## government; if that is the president's too, the narrator speaks -- as for a
## vacant office (a premiership left empty by a resignation act).
static func _office(ns, loader, office: String) -> String:
	var leader := President.leader_id(ns)
	var holder := ""
	match office:
		"head_of_government":
			holder = String(ns.pm_person_id)
		"head_of_state":
			holder = String(ns.head_of_state_person_id)
		"largest_party_leader":
			var parties: Array = loader.parties.get(ns.id, [])
			var largest := Government.largest_party_id(ns, parties)
			for party in parties:
				if party.id == largest:
					# The override first: a challenge deposed the authored leader.
					holder = String(ns.party_leader_override.get(party.id, party.leader_person_id))
	if holder == leader:
		holder = String(ns.pm_person_id)
	return "" if holder == leader or not loader.person_by_id.has(holder) else holder


## The person of the latest exposure the event answers (its route, one of its
## kinds): the witness who tells it. The exposure machine arms the event the month
## after the row is written, so the latest matching row is the one that armed it.
static func _witness(ns, loader, ev) -> String:
	var best := ""
	var best_month := -1
	for row in ns.exposures:
		if String(row.get("route", "")) != ev.exposure_route or not ev.exposure_kinds.has(String(row.get("kind", ""))):
			continue
		if int(row.get("exposed_month", 0)) >= best_month:
			best_month = int(row.get("exposed_month", 0))
			best = String(row.get("person_id", ""))
	return best if best != President.leader_id(ns) and loader.person_by_id.has(best) else ""


## No event names a nation, so the counterpart is derived: the head of
## government of the nation the played one stands worst with (lowest relations,
## ties to id) -- the partner a row or a demand plausibly comes from. A European
## event looks only among the Union's members when the played nation is one.
static func _foreign_head(state, ns, loader, ev) -> String:
	var leader := President.leader_id(ns)
	var in_union: bool = ev.category == "european" and ns.orgs.has(OrgsK.UNION_ORG_ID)
	var best := ""
	var best_score := INF
	var ids: Array = state.nations.keys()
	ids.sort()
	for nation_id in ids:
		if String(nation_id) == String(ns.id):
			continue
		var other = state.nations[nation_id]
		var head := String(other.pm_person_id)
		if head == "" or head == leader or not loader.person_by_id.has(head):
			continue
		if in_union and not other.orgs.has(OrgsK.UNION_ORG_ID):
			continue
		var score := Relations.score(state, String(ns.id), String(nation_id))
		if score < best_score:
			best_score = score
			best = head
	return best
