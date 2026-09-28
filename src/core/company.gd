class_name Company
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/companies/*.json file. See docs/companies-model.md and
## docs/fictionalization.md.
##
## THE FIRST CONTENT CLASS IN THE PROJECT THAT FRONTS NOTHING. U6b's "no new
## effect channel" held because a leader is the face of a nation
## data/nations/ already ships and a party leader is the face of a party; a firm
## is the face of nothing, so V1.4 owns a channel of its own -- effects.company,
## on src/core/diplomatic_action.gd's shape. src/core/person.gd's header names
## this class as the place the argument would be had, and this is it: a person
## has no field that could carry a mechanism, and a firm has two.
##
## Four fields, and the count is the design:
##
##   share      -- of its SECTOR's output, not of GDP. Live state after
##                 new-game; what a lever moves.
##   headcount  -- jobs at the authored share. The DIFFERENTIATOR, and the
##                 reason picking a firm is a decision rather than picking a
##                 sector: two firms of equal share employ different numbers of
##                 people, so moving share between them creates or destroys
##                 jobs. Nothing else in the model does that.
##
## Without the second, every firm in a sector answers alike and V1.4's subsidy
## IS docs/tiers/v1.md section 6's "sectoral investment -- a lever pointed at a
## sector". That is the clustered-`coalition_position` finding
## docs/foreign-policy-model.md records, caught at design time rather than by a
## probe.
##
## Deliberately absent: revenue (it is share x sector output, and authoring it
## would be one quantity written twice -- the redundancy tools/coercion_probe.gd
## cut when it deleted `tariff_rate_pct`), a CEO (a person is the face of a
## firm, and the mechanism that gives one something to do is section 5), and any
## authored margin, productivity or ownership term. Ownership arrives with the
## verb that changes it, at V1.4c.

const EK = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/companies_constants.gd")


var id: String = ""
var company_name: String = ""

## One of economy_constants.SECTOR_TREND's three keys. Checked here rather than
## at the loader, so a sector typo fails in the file that wrote it.
var sector: String = ""

## Share of its sector's output, in [0, 1]. The shares of one nation's firms in
## one sector sum to AT MOST 1.0 -- the remainder is the unnamed rest of the
## sector, and it is what makes the register additive: a later session naming a
## seventh firm takes share from the residual and moves no existing number.
var share: float = 0.0

## Jobs at the authored share. Scales with share and NOT with the sector's
## output -- see src/sim/companies.gd, where that call is load-bearing enough to
## have its own paragraph.
var headcount: float = 0.0

## V2.2a. The id of a city in data/regions/<this nation>.json. A FIFTH FIELD, and
## the one the header above says a firm does not have: it fronts a place.
##
## docs/tiers/v2.md section 2 puts it here rather than in the region register --
## *"a city's employment is already written in `data/companies/` and needs no
## second authoring"* -- and the direction is the point. A city holding a list of
## its firms would be the same relationship written twice, and the two would
## disagree the first time a session added a firm and forgot the other file.
##
## Checked against the register at the loader rather than here, because this file
## sees one entry and the cities live in a different one. Required: a firm with
## no city is a firm this tier cannot draw, and an optional field would be one
## eighteen entries silently never filled in.
var city: String = ""

## V4.7a tier: legacy entries without the field remain majors until A3 regenerates them.
var tier: String = "major"

## V4.7a: the major's named chief -- a person in the same nation's
## data/people/<ID>.json, kind "executive". Required on majors (the loader
## refuses a major without one: a champion with no face is the count-is-the-
## design rule half-built), refused on body firms (the body is acted upon,
## nobody fronts it). The id itself is validated cross-register in
## _validate_companies, the way party ids resolve for people.
var chief_id: String = ""


static func from_dict(d: Dictionary, index: int, filename: String, errors: Array[String]):
	var c := new()
	var path := "companies[%d]" % index

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: %s missing or invalid string field 'id'" % [filename, path])
	else:
		c.id = d["id"]

	# `company_name`, not `name` -- person.gd, party.gd and nation.gd all make the
	# same dodge, because `name` is a Node property.
	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, path])
	else:
		c.company_name = d["name"]

	var sector = d.get("sector", "")
	if typeof(sector) != TYPE_STRING or not EK.SECTOR_TREND.has(sector):
		errors.append("%s: %s sector '%s' is not one of %s" % [
			filename, path, str(sector), str(EK.SECTOR_TREND.keys())
		])
	else:
		c.sector = sector

	# The floor is scoped by tier BEFORE the share check reads it: majors keep
	# the 0.02 standard (a verb target too small to move its sector is a label),
	# while a body firm's whole band lives BELOW it (~0.005 typical, 0.03 the
	# ceiling BODY_SHARE_MAX clamps at the loader). One floor for both tiers
	# would refuse every body file A3 generates -- the A1 review's finding,
	# fixed at the shared check rather than per call site.
	var tier := "major"
	if d.has("tier"):
		tier = String(d["tier"])
	var share_floor: float = K.MIN_BODY_SHARE if tier == "body" else K.MIN_AUTHORED_SHARE
	if not d.has("share") or not (typeof(d["share"]) == TYPE_INT or typeof(d["share"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or non-numeric field 'share'" % [filename, path])
	else:
		c.share = float(d["share"])
		if c.share <= 0.0 or c.share > 1.0:
			errors.append("%s: %s share = %s must be in (0, 1]" % [filename, path, str(c.share)])
		elif c.share < share_floor:
			# A MAJOR too small to move its sector is a name on a panel. The floor is
			# the same standard _validate_people() applies to an unreferenced person:
			# content with no reachable effect fails the load rather than sitting in a
			# file looking like a feature. A body firm sits under MIN_BODY_SHARE's
			# smaller floor for the same reason at its own scale -- its CEILING is
			# BODY_SHARE_MAX, the loader's tier rule, not this floor's job.
			errors.append("%s: %s share = %s is below the %s-tier floor (%s) -- a firm that cannot move its sector is a label, not a firm" % [
				filename, path, str(c.share), tier, str(share_floor)
			])

	if not d.has("headcount") or not (typeof(d["headcount"]) == TYPE_INT or typeof(d["headcount"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or non-numeric field 'headcount'" % [filename, path])
	else:
		c.headcount = float(d["headcount"])
		if c.headcount <= 0.0:
			errors.append("%s: %s headcount = %s must be > 0" % [filename, path, str(c.headcount)])

	if not d.has("city") or typeof(d["city"]) != TYPE_STRING or d["city"] == "":
		errors.append("%s: %s missing or invalid string field 'city'" % [filename, path])
	else:
		c.city = d["city"]

	if d.has("tier"):
		c.tier = String(d["tier"])

	if d.has("chief_id"):
		if typeof(d["chief_id"]) != TYPE_STRING:
			errors.append("%s: %s field 'chief_id' must be a string" % [filename, path])
		else:
			c.chief_id = d["chief_id"]

	for key in d.keys():
		if key != "id" and key != "name" and key != "sector" and key != "share" 				and key != "headcount" and key != "city" and key != "tier" and key != "chief_id":
			errors.append("%s: %s has unrecognised field '%s' -- revenue is share x sector output and is never authored, and a firm carries no owner, margin or productivity term" % [
				filename, path, key
			])

	return c
