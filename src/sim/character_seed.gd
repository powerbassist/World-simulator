extends RefCounted

## What the people register holds before anything has happened: standing off
## authored ambition, and (V5.3 a + b, docs/design/v5.3-ab.md section 6) the regard
## a person starts with. Beside characters.gd rather than in it: that file is at the
## size ratchet's ceiling, and a new game's arithmetic is not the month's.
##
## The regard is two parts, both read from data, the author's answer: "plus ils sont
## opposés à tes idées plus ils ne t'apprécient pas", then a real relation on top.
## A formula with no draw, so it neither reads nor moves any seeded roll: a new game
## starts at the same regard every time. Rejected: a floor just above "rival", the
## earlier draft's: the author's answer says the distance decides.

const CK = preload("res://src/sim/character_act_constants.gd")
const EK = preload("res://src/sim/election_constants.gd")
const Government = preload("res://src/sim/government.gd")
const President = preload("res://src/sim/president.gd")
const Staff = preload("res://src/sim/staff.gd")


## Ambition plus the trait's floor (the scalar is the dial, the trait is the floor --
## 14.2's own distinction), so an ambitious person starts with weight to use and a
## contented one starts anonymous.
static func standing(person) -> float:
	var value := CK.STANDING_SEED_BASE + CK.STANDING_SEED_AMBITION * float(person.ambition)
	if person.traits.has("ambitious"):
		value += CK.STANDING_SEED_AMBITIOUS_BONUS
	return clampf(value, 0.0, 1.0)


## Seeds the president's regard for the cast of the played nation, after its start
## government has formed (GameState._build_nation runs before Characters.init_nation),
## so the coalition this reads is the one that sits. A zero writes no row: absent is
## neutral, the register's own reading. Never the president (an edge needs two ends)
## and never the staff (Staff.cast).
##
## The offset is read only against the nation's authored start leader: it records a
## relation with that one politician, and says nothing about whoever a scenario's
## seats put there instead.
static func regard(ns, loader) -> void:
	var by_id := {}
	var led := {}
	for party in loader.parties.get(ns.id, []):
		by_id[party.id] = party
		if party.leader_person_id != "":
			led[party.leader_person_id] = party.id
	var leader := President.leader_id(ns)
	var own = by_id.get(_party_id(loader, leader, led))
	var authored_leader_sits: bool = leader == String(loader.nations[ns.id].leader_person_id)
	for person in Staff.cast(loader, ns.id):
		if person.id == leader:
			continue
		var value := _ideas(by_id.get(_party_id(loader, person.id, led)), own, ns.coalition_party_ids)
		if authored_leader_sits:
			value += float(person.start_regard_offset)
		if value != 0.0:
			President.seed_rapport(ns, person.id, value)


## A person's party at a new game: the authored edge, else the party they lead. A
## leader carries no party_id, the party names them, and they are the opponents the
## player meets first. No override to read: Characters.init_nation has just cleared them.
static func _party_id(loader, person_id: String, led: Dictionary) -> String:
	var person = loader.person_by_id.get(person_id)
	var authored := "" if person == null else String(person.party_id)
	return authored if authored != "" else String(led.get(person_id, ""))


## The first part: no party on either side has no slot to measure from; the
## president's own party is warm; a partner in the start government is neutral, since
## a partner is not an opponent; every other party is colder the farther its slot,
## and colder again across a cordon, the data's own statement of opposed ideas.
static func _ideas(party, own, coalition) -> float:
	if party == null or own == null:
		return 0.0
	if party.id == own.id:
		return CK.REGARD_OWN_PARTY
	if coalition.has(party.id):
		return 0.0
	var distance := Government.distance(EK.SLOT_POSITION[party.ideology_slot], EK.SLOT_POSITION[own.ideology_slot])
	return CK.REGARD_PER_DISTANCE * distance + (CK.REGARD_CORDON if Government.refuses(party, own) else 0.0)
