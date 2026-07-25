class_name Party
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/parties/*.json file. See docs/data-architecture.md and
## docs/fictionalization.md.

var id: String = ""
var party_name: String = ""
var ideology_slot: String = ""
var seat_share: float = 0.0


static func from_dict(d: Dictionary, index: int, filename: String, errors: Array[String]):
	var p := new()
	var path := "parties[%d]" % index

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: %s missing or invalid string field 'id'" % [filename, path])
	else:
		p.id = d["id"]

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, path])
	else:
		p.party_name = d["name"]

	if not d.has("ideology_slot") or typeof(d["ideology_slot"]) != TYPE_STRING or d["ideology_slot"] == "":
		errors.append("%s: %s missing or invalid string field 'ideology_slot'" % [filename, path])
	else:
		p.ideology_slot = d["ideology_slot"]

	if not d.has("seat_share") or not (typeof(d["seat_share"]) == TYPE_INT or typeof(d["seat_share"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or invalid numeric field 'seat_share'" % [filename, path])
	else:
		p.seat_share = float(d["seat_share"])
		if p.seat_share < 0.0 or p.seat_share > 1.0:
			errors.append("%s: %s seat_share = %s out of range [0, 1]" % [filename, path, str(p.seat_share)])

	return p
