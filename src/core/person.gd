class_name Person
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/people/*.json file. See docs/people-model.md and
## docs/fictionalization.md.
##
## A person is an ID AND A NAME, and deliberately nothing else.
##
## The three fields this class was planned with — `role`, `title` and `party_id`
## — were all cut before it was written, for one reason each time: every one of
## them is already stated by the REFERENCE that owns the relationship. A head of
## state's title is `NationState.head_of_state_title`, which an amendment can
## change; a party leader is whoever that party's `leader_person_id` points at;
## and the office a person holds is the slot pointing at them. Authoring any of
## the three would be a second record of one fact — precisely the failure this
## register exists to remove, since data/nations/*.json wrote its leader's name
## twice in all ten files.
##
## That leaves the class with no field that could carry a mechanism, which makes
## U6b's "no mechanism on a person" true by construction rather than by
## discipline. docs/tiers/v1.md §4 and §5 add the mechanisms that give a
## journalist or a firm something to do; they inherit this register and extend
## it, and the first field with a number in it is the one to argue about.

var id: String = ""
var person_name: String = ""


static func from_dict(d: Dictionary, index: int, filename: String, errors: Array[String]):
	var p := new()
	var path := "people[%d]" % index

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: %s missing or invalid string field 'id'" % [filename, path])
	else:
		p.id = d["id"]

	# `person_name`, not `name` — the same dodge party.gd makes for `party_name`
	# and nation.gd for `nation_name`, because `name` is a Node property and a
	# value type that shadows it reads as a bug the first time someone subclasses.
	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, path])
	else:
		p.person_name = d["name"]

	return p
