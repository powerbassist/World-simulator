class_name Party
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/parties/*.json file. See docs/data-architecture.md and
## docs/fictionalization.md.

var id: String = ""
var party_name: String = ""
var ideology_slot: String = ""
var seat_share: float = 0.0

## A reference into data/people/, per docs/people-model.md. Where this party
## governs its nation, this is the SAME person the nation's own leader slot
## points at — which used to be two authored name strings that happened to
## agree, in all ten files, and is now one record with two references.
var leader_person_id: String = ""

## How reliably the party delivers its seats behind a position it has signed up
## to, in [0, 1]. Scales the coalition bonus in src/sim/legislature.gd — see
## docs/government-model.md.
var discipline: float = 0.0

## How well this party governs a portfolio it holds, in [0, 1], scaled per
## portfolio by ideological affinity — see src/sim/cabinet.gd and
## docs/cabinet-model.md. A separate axis from discipline: a party can be
## disciplined and inexperienced, or fractious and highly competent.
var competence: float = 0.0

## Party ids this party refuses to sit in government with. Read symmetrically by
## src/sim/government.gd, so a cordon is authored once, on the party that draws
## it. Validated against the same nation's roster by data_loader.gd.
var excluded_partners: Array[String] = []

## V5.2a. The party's funds at game start, EUR millions -- the START only: what
## is raised or spent is NationState.party_money_delta_eur_m (the author's call,
## 2026-10-21: party money is its own register, not the president's wealth).
## Optional; absent reads 0, which is every party before Content authors one.
var funds_eur_m: float = 0.0


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

	if not d.has("leader_person") or typeof(d["leader_person"]) != TYPE_STRING or d["leader_person"] == "":
		errors.append("%s: %s missing or invalid string field 'leader_person'" % [filename, path])
	else:
		p.leader_person_id = d["leader_person"]

	if not d.has("discipline") or not (typeof(d["discipline"]) == TYPE_INT or typeof(d["discipline"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or invalid numeric field 'discipline'" % [filename, path])
	else:
		p.discipline = float(d["discipline"])
		if p.discipline < 0.0 or p.discipline > 1.0:
			errors.append("%s: %s discipline = %s out of range [0, 1]" % [filename, path, str(p.discipline)])

	if not d.has("competence") or not (typeof(d["competence"]) == TYPE_INT or typeof(d["competence"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or invalid numeric field 'competence'" % [filename, path])
	else:
		p.competence = float(d["competence"])
		if p.competence < 0.0 or p.competence > 1.0:
			errors.append("%s: %s competence = %s out of range [0, 1]" % [filename, path, str(p.competence)])

	if not d.has("excluded_partners") or typeof(d["excluded_partners"]) != TYPE_ARRAY:
		errors.append("%s: %s missing or invalid array field 'excluded_partners'" % [filename, path])
	else:
		for entry in d["excluded_partners"]:
			if typeof(entry) != TYPE_STRING or entry == "":
				errors.append("%s: %s excluded_partners holds a non-string entry" % [filename, path])
			else:
				p.excluded_partners.append(entry)

	if d.has("funds_eur_m"):
		var funds = d["funds_eur_m"]
		if typeof(funds) in [TYPE_FLOAT, TYPE_INT] and float(funds) >= 0.0:
			p.funds_eur_m = float(funds)
		else:
			errors.append("%s: %s field 'funds_eur_m' must be a number >= 0" % [filename, path])

	return p
