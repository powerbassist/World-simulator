extends RefCounted

## V5.3-0. The staff rule (docs/design/v5.3-0-readability.md 2.1): the
## president's own team -- today the chief of staff -- are person records of
## the played nation that MOVE NO NUMBER. The rule is by kind
## (CharacterK.KIND_STAFF), never by id, and this file is its one reader for the
## walkers: every walker of the people register that reads every kind and can
## write a number takes its list from cast(), so a staff person is never
## seeded, settled, invited or drawn; and the player's verbs refuse one through
## is_staff() (President.covers, Audiences.invite). A LEAF: it preloads the
## schema and nothing else, so characters.gd, audiences.gd, audience_triggers.gd
## and president.gd can all read it. tests/test_staff_kind.gd pins the rule and
## the walker inventory.

const CharacterK = preload("res://src/sim/character_constants.gd")


## The nation's people who can act: the register minus the staff kinds, in
## register order (so a register with no staff reads exactly as before).
static func cast(loader, nation_id: String) -> Array:
	return (loader.people.get(nation_id, []) as Array).filter(
		func(person) -> bool: return not CharacterK.KIND_STAFF.has(String(person.kind)))


## Whether the person is staff. In block 0 a chief of staff takes no edge from
## the president (no rapport, no commitment, no call) and asks for nothing, so
## no player verb can move a number through them either; the skills block
## (docs/design/v5.3-skills.md) decides whether that changes.
static func is_staff(loader, person_id: String) -> bool:
	var person = loader.person_by_id.get(person_id)
	return person != null and CharacterK.KIND_STAFF.has(String(person.kind))


## The nation's chief of staff -- "the person of kind chief_of_staff in the
## played nation's file" (2.1: no saved field, no appointment) -- or null for a
## nation that has none.
static func chief_of(loader, nation_id: String):
	for person in loader.people.get(nation_id, []):
		if String(person.kind) == "chief_of_staff":
			return person
	return null
