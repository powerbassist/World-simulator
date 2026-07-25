class_name EU
extends RefCounted

## Loads and validates data/eu_parliament.json: which nations are members, how
## many European Parliament seats each holds, and when the next EP election is.
## Same treatment as every other static file — read once at startup, validated
## loudly, never mutated. See docs/data-architecture.md and
## docs/electoral-systems.md.
##
## A non-member (GBR, CHE) is simply absent from `members` — there is no
## `eu_member` boolean to gate on here, because the whole point is that the code
## never needs to ask "is this nation special", only "does this id appear in the
## table".

var next_election_year: int = 0
var next_election_month: int = 0
var members: Dictionary = {}  # String id -> ep_seats (int)
var errors: Array[String] = []


func load(path := "res://data/eu_parliament.json") -> void:
	members.clear()
	errors = []

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: could not read file" % path)
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s: invalid JSON" % path)
		return

	var fname := path.get_file()

	var next: Dictionary = parsed.get("next_election", {})
	if typeof(next) != TYPE_DICTIONARY:
		errors.append("%s: missing or invalid object field 'next_election'" % fname)
	else:
		next_election_year = int(next.get("year", 0))
		next_election_month = int(next.get("month", 0))
		if next_election_year < 2026 or next_election_year > 2100:
			errors.append("%s: next_election.year %d out of range" % [fname, next_election_year])
		if next_election_month < 1 or next_election_month > 12:
			errors.append("%s: next_election.month %d out of range" % [fname, next_election_month])

	var raw_members = parsed.get("members", {})
	if typeof(raw_members) != TYPE_DICTIONARY:
		errors.append("%s: missing or invalid object field 'members'" % fname)
		return

	for id in raw_members.keys():
		var entry = raw_members[id]
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("ep_seats"):
			errors.append("%s: members.%s missing 'ep_seats'" % [fname, id])
			continue
		var seats := int(entry["ep_seats"])
		if seats < 1 or seats > 200:
			errors.append("%s: members.%s.ep_seats %d out of range" % [fname, id, seats])
			continue
		members[id] = seats


func is_member(nation_id: String) -> bool:
	return members.has(nation_id)


func ep_seats(nation_id: String) -> int:
	return int(members.get(nation_id, 0))
