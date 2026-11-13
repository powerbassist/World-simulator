extends RefCounted

## The people in the matter of a request -- the V5.3 audience reads (the parent's card of
## 2026-11-13, mockup C's "Ask her about"). Deal's leaf: Deal.people_in_matter() is the
## door the scene reads. A pure read, writes nothing.
##
## ONLY WHAT THE DATA LINKS, in this order, at most MAX, never the asker, the sitting
## president, a chief of staff, or anyone twice:
##   1. the anchor: a firm's chief (companies' `chief_id`);
##   2. the others whose wants name the same object, the other stance first (the ones who
##      would argue against the asker), then the same stance, each by standing, then id;
##   3. on a programme goal that names laws: the leaders of the parties with
##      seats, ordered by their party's support for the goal's laws (Legislature.support,
##      the division's own read), the other side of the asker's stance first;
##   4. on a meter: the people whose kind reads that meter (CharacterK.KIND_METERS), by
##      standing, then id.
## What the data does not link is left out rather than guessed: no person carries a
## region, and no person is tied to a bloc, so a region's figures and a goal's bloc leaders
## are not here (a `region:` want reads its fellow wanters only). Empty is a real answer.

const AK = preload("res://src/sim/audience_constants.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const Companies = preload("res://src/sim/companies.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const President = preload("res://src/sim/president.gd")

## The parent's card: three to five faces, never the roster.
const MAX := 5


## `row` a request as Audiences keeps it. Person ids, at most MAX, ordered.
static func of(_state, ns, loader, row: Dictionary) -> Array[String]:
	var asker := String(row.get("person_id", ""))
	var object := String(row.get("object", ""))
	var stance := String(row.get("stance", ""))
	var out: Array[String] = []
	var skip := {asker: true, President.leader_id(ns): true}
	if object.begins_with(AK.FIRM_PREFIX):
		for company in Companies.majors_of(loader, ns.id):
			if AK.FIRM_PREFIX + String(company.id) == object:
				_add(out, skip, loader, String(company.chief_id))
	var people: Array = loader.people.get(ns.id, [])
	var others: Array = []
	var same: Array = []
	for person in people:
		for want in person.wants:
			if String(want["object"]) == object:
				(same if String(want["stance"]) == stance else others).append(person)
				break
	for group in [others, same]:
		for person in _by_standing(ns, group):
			_add(out, skip, loader, String(person.id))
	for pid in _party_leaders(ns, loader, object, stance):
		_add(out, skip, loader, pid)
	if object.begins_with("meter:"):
		var meter := object.substr("meter:".length())
		var readers: Array = people.filter(func(p): return String(CharacterK.KIND_METERS.get(String(p.kind), "")) == meter)
		for person in _by_standing(ns, readers):
			_add(out, skip, loader, String(person.id))
	return out


static func _add(out: Array[String], skip: Dictionary, loader, pid: String) -> void:
	var person = loader.person_by_id.get(pid)
	if out.size() >= MAX or pid == "" or skip.has(pid) or person == null or String(person.kind) == "chief_of_staff":
		return
	skip[pid] = true
	out.append(pid)


static func _by_standing(ns, people: Array) -> Array:
	var sorted := people.duplicate()
	sorted.sort_custom(func(a, b):
		var sa := float(ns.person_standing.get(a.id, 0.0))
		var sb := float(ns.person_standing.get(b.id, 0.0))
		return sa > sb or (sa == sb and String(a.id) < String(b.id)))
	return sorted


## The leaders of the parties with seats on a goal's laws, by their mean support,
## the asker's other side first: an opponent of the goal meets its supporters first.
static func _party_leaders(ns, loader, object: String, stance: String) -> Array[String]:
	var law_ids: Array = []
	if object.begins_with("programme:"):
		for entry in loader.programme:
			if "programme:%s" % String(entry["id"]) == object:
				law_ids = entry.get("laws", [])
	var laws: Array = loader.laws.filter(func(l): return law_ids.has(String(l.id)))
	var out: Array[String] = []
	if laws.is_empty():
		return out
	var sign := 1.0 if stance == "oppose" else -1.0
	var rows: Array = []
	var leaders := {}
	for party in loader.parties.get(ns.id, []):
		leaders[party.id] = party.leader_person_id
	for party in loader.parties.get(ns.id, []):
		if int(ns.seats_by_party.get(party.id, 0)) <= 0:
			continue
		var support := 0.0
		for law in laws:
			support += Legislature.support(ns, party, law)
		rows.append({"pid": Characters.party_leader(ns, String(party.id), leaders), "key": sign * support / laws.size(), "id": String(party.id)})
	rows.sort_custom(func(a, b): return float(a["key"]) > float(b["key"]) or (float(a["key"]) == float(b["key"]) and String(a["id"]) < String(b["id"])))
	for r in rows:
		out.append(String(r["pid"]))
	return out
