extends RefCounted

## Which lines of conversation an audience offers -- V5.3, Gameplay's talk menu
## (sections 1-4): a pure read over GameState, tier by tier, from the table in
## data/audiences/talk_lines.json. A line is offered only when its condition holds, so a
## stranger at the start of a term gets a few and a person with a history gets more; nothing
## is added to fill the gap (the author's "peu au début, plus ensuite", 2026-11-13).
##
## It lives in src/ui because it reads the sim and writes nothing, and because the words
## and the glyphs are the view's; the sim gains no code from it. The table is read by this
## one rule and never names a person or a nation (AGENTS.md rule 1). Whether a line was
## already put to this person in an earlier audience is a register the sim does not keep yet:
## the no-repeat rule waits for it (talk menu section 2).

const Capital = preload("res://src/core/capital.gd")
const Closures = preload("res://src/sim/closures.gd")
const Companies = preload("res://src/sim/companies.gd")
const Deal = preload("res://src/sim/deal.gd")
const President = preload("res://src/sim/president.gd")
const Shadows = preload("res://src/sim/shadows.gd")

const TABLE_PATH := "res://data/audiences/talk_lines.json"
const BANDS := ["stranger", "acquaintance", "known"]

static var _table := {}


## The offered lines for `session`'s person, in the order they are shown:
## [{id, topic, tag, tier, args, people}]. `args` is what the topic takes (a gossip's `about`
## is its first person; the view overwrites it with the chip picked), `facts` what the
## words name ({law_id}, {company_id}, {sector_id}), `people` a gossip's [{id, tie}].
static func lines(state, ns, loader, session: Dictionary) -> Array[Dictionary]:
	var table := table()
	var pid := String(session.get("person_id", ""))
	var found: Dictionary = {}
	var index := -1
	for def in table["lines"]:
		index += 1
		var hit := _holds(state, ns, loader, session, pid, def["condition"])
		if hit.is_empty():
			continue
		var tier := String(def["tier"])
		if not found.has(tier):
			found[tier] = []
		found[tier].append({"id": String(def["id"]), "topic": String(def["topic"]), "tag": String(def["tag"]), "tier": tier,
			"args": hit.get("args", {}), "facts": hit.get("facts", {}), "people": hit.get("people", []), "age": int(hit.get("age", 0)), "index": index})
	var out: Array[Dictionary] = []
	for tier in table["tier_order"]:
		var rows: Array = found.get(tier, [])
		# What happened most recently comes first within a tier; the table's order breaks ties
		# (sort_custom is not stable, so the tie is explicit).
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["age"]) < int(b["age"]) or (int(a["age"]) == int(b["age"]) and int(a["index"]) < int(b["index"])))
		out.append_array(rows.slice(0, int(table["tier_limits"].get(tier, 1))))
	return out.slice(0, int(table["max_lines"]))


static func table() -> Dictionary:
	if _table.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
		_table = parsed if parsed is Dictionary else {"lines": [], "tier_order": [], "tier_limits": {}, "max_lines": 0}
	return _table


## {} when the condition does not hold, else what the line carries.
static func _holds(state, ns, loader, session: Dictionary, pid: String, condition: Dictionary) -> Dictionary:
	match String(condition["kind"]):
		"bill_soon":
			return _bill_soon(state, ns, loader, pid, int(condition["months"]))
		"closure_at_chief_firm":
			return _chief_firm(state, ns, loader, pid, "closure", 0)
		"sector_warning_at_chief_firm":
			return _chief_firm(state, ns, loader, pid, "sector", int(condition["months"]))
		"gossip_people":
			var people := gossip_people(state, ns, loader, pid, int(condition["max"]))
			return {"people": people, "args": {"about": String(people[0]["id"])}} if not people.is_empty() else {}
		"knowledge":
			var rank := BANDS.find(President.knowledge_band(ns, pid))
			if condition.has("at_least") and rank < BANDS.find(String(condition["at_least"])):
				return {}
			if condition.has("at_most") and rank > BANDS.find(String(condition["at_most"])):
				return {}
			return {"args": {}}
		"affair_gates":
			var known := BANDS.find(President.knowledge_band(ns, pid)) >= BANDS.find(String(condition["knowledge_at_least"]))
			return {"args": {}} if known and Shadows.may_begin_affair(state, ns, loader, pid, session) == "" else {}
	return {}


## Their party's bill reaching the floor within `months`: Deal's own read of the offer a
## vote on the next bill makes, so the line and the strip can never disagree.
static func _bill_soon(state, ns, loader, pid: String, months: int) -> Dictionary:
	var offer := Deal.offer_of(state, ns, loader, pid)
	var ahead := int(offer.get("due_month", 0)) - (int(state.year) * 12 + int(state.month))
	if String(offer.get("kind", "")) != "vote" or ahead < 0 or ahead > months:
		return {}
	return {"args": {}, "facts": {"law_id": String(offer["law_id"]), "due_month": int(offer["due_month"])}, "age": ahead}


## The firms a person is the chief of (the only link the data draws from a person to a firm,
## a sector or a place): a plant closing there, or the sector's warning entered lately.
static func _chief_firm(state, ns, loader, pid: String, what: String, months: int) -> Dictionary:
	var now := int(state.year) * 12 + int(state.month)
	for company in Companies.majors_of(loader, ns.id):
		if String(company.chief_id) != pid:
			continue
		if what == "closure":
			for row in Closures.open(ns):
				if String(row["company_id"]) == String(company.id):
					return {"args": {}, "facts": {"company_id": String(company.id), "city_id": String(row["city_id"]), "due": int(row["due"])},
						"age": now - int(row["announced"])}
			continue
		var warning: Dictionary = ns.sector_drift.get("warnings", {}).get(String(company.sector), {})
		if not warning.is_empty() and now - int(warning["entered"]) <= months:
			return {"args": {}, "facts": {"sector_id": String(company.sector)}, "age": now - int(warning["entered"])}
	return {}


## Whom a gossip may name, and why: the president's own covered people who share the
## person's party or one of their wants (the tie the tooltip on a face says), the people the
## president knows best first, then by name (case and accent folded), at most `cap`.
static func gossip_people(state, ns, loader, pid: String, cap: int) -> Array[Dictionary]:
	var person = loader.person_by_id.get(pid)
	var out: Array[Dictionary] = []
	if person == null:
		return out
	var party := President.party_id_of(ns, loader, pid)
	for other in loader.people.get(String(ns.id), []):
		var id := String(other.id)
		if id == pid or id == President.leader_id(ns) or String(other.kind) == "chief_of_staff" or not President.covers(state, ns, loader, id):
			continue
		var tie := _tie(ns, loader, person, other, party)
		if not tie.is_empty():
			out.append({"id": id, "tie": tie, "know": President.knowledge(ns, id), "key": Capital.fold(String(loader.person_name(id)))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["know"] > b["know"] or (a["know"] == b["know"] and String(a["key"]) < String(b["key"])))
	return out.slice(0, cap)


## {kind: "party", party_id} | {kind: "want", object, same_side: bool} | {}.
static func _tie(ns, loader, person, other, party: String) -> Dictionary:
	if party != "" and President.party_id_of(ns, loader, String(other.id)) == party:
		return {"kind": "party", "party_id": party}
	for want in person.wants:
		for theirs in other.wants:
			if String(theirs["object"]) == String(want["object"]):
				return {"kind": "want", "object": String(want["object"]), "same_side": String(theirs["stance"]) == String(want["stance"])}
	return {}
