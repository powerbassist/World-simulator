class_name Outlet
extends RefCounted

## Typed, validated in-memory representation of one entry in a data/outlets/*.json
## file. See docs/media-model.md and docs/fictionalization.md.
##
## THE SECOND CONTENT CLASS THAT FRONTS NOTHING, after src/core/company.gd -- and
## unlike a firm, an outlet does not get an effect channel of its own. V1.5a opened
## effects.society and V1.5d is its FOURTH register, after corruption, migration and
## settlement. A channel carrying four is schema rather than one session's private
## field, which is what society-model.md section 3 bet on it becoming.
##
## Five fields, and the count is the design:
##
##   audience  -- one of opinion_constants.BLOC_KEYS. THE DIFFERENTIATOR, and the
##                reason a press layer is more than a second SALIENCE_GAIN: different
##                papers reach different people, so the same government failure is
##                amplified for one bloc and not another. Without it every outlet in a
##                nation answers alike and framing IS the global gain with a second
##                writer -- one quantity, two writers, the failure this project has
##                named five times.
##   reach     -- of its OWN audience bloc, not of the nation. Live-read content; the
##                weight the outlet's hostility carries.
##   position  -- the same two-axis ideology space government.gd, legislature.gd and
##                foreign_policy.gd all already work in.
##
## THERE IS NO alignment, hostility, bias OR stance FIELD, AND THE REFUSAL IS THE
## DESIGN. Alignment is DERIVED from `position` against the nation's own live
## `coalition_position`, so an authored one would be a second writer of it -- and the
## whole point of deriving it is that the press turns on you when your government
## changes. That is company.gd's absent-owner refusal and law.gd's refusal of a firm id,
## in a third register. The unrecognised-field loop at the bottom says so out loud,
## because a reader adding a "leaning" field would otherwise think it was an oversight.
##
## Deliberately absent beyond that: an editor or proprietor. A person is the face of an
## outlet, and docs/people-model.md's whole argument is that a person has no field that
## could carry a mechanism -- so an `editor_person_id` would be a label, not a lever.

const K = preload("res://src/sim/opinion_constants.gd")
const MK = preload("res://src/sim/media_constants.gd")


var id: String = ""
var outlet_name: String = ""

## One of opinion_constants.BLOC_KEYS. Checked here rather than at the loader, so a
## bloc typo fails in the file that wrote it -- company.gd's stated reason for checking
## its sector in the same place.
var audience: String = ""

## Share of its AUDIENCE bloc, in (0, 1]. The outlets naming one nation's one bloc sum
## to AT MOST 1.0; the remainder is the unaffiliated part of that bloc, which reads
## nothing and is therefore un-amplified. That residual is what makes the register
## additive -- a later session naming another title takes reach from it and moves no
## existing number, company.gd's property exactly.
var reach: float = 0.0

## Where the outlet sits, on the two axes every position in this project uses. Its
## distance from the government's `coalition_position` is the whole of its alignment.
var position: Dictionary = {"economic": 0.0, "social": 0.0}


static func from_dict(d: Dictionary, index: int, filename: String, errors: Array[String]):
	var o := new()
	var path := "outlets[%d]" % index

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: %s missing or invalid string field 'id'" % [filename, path])
	else:
		o.id = d["id"]

	# `outlet_name`, not `name` -- company.gd, person.gd, party.gd and nation.gd all
	# make the same dodge, because `name` is a Node property.
	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, path])
	else:
		o.outlet_name = d["name"]

	var audience = d.get("audience", "")
	if typeof(audience) != TYPE_STRING or not K.BLOC_KEYS.has(audience):
		errors.append("%s: %s audience '%s' is not one of %s" % [
			filename, path, str(audience), str(K.BLOC_KEYS)
		])
	else:
		o.audience = audience

	if not d.has("reach") or not (typeof(d["reach"]) == TYPE_INT or typeof(d["reach"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or non-numeric field 'reach'" % [filename, path])
	else:
		o.reach = float(d["reach"])
		if o.reach <= 0.0 or o.reach > 1.0:
			errors.append("%s: %s reach = %s must be in (0, 1]" % [filename, path, str(o.reach)])
		elif o.reach < MK.MIN_AUTHORED_REACH:
			errors.append("%s: %s reach = %s is below MIN_AUTHORED_REACH (%s) -- an outlet nobody reads is a masthead, not an outlet" % [
				filename, path, str(o.reach), str(MK.MIN_AUTHORED_REACH)
			])

	# Copied from law.gd's _extract_position() rather than preloading it: law.gd is what
	# data_loader.gd hangs the whole content tree off, and an outlet is loaded from the
	# same pass.
	var pos = d.get("position", null)
	if typeof(pos) != TYPE_DICTIONARY:
		errors.append("%s: %s missing or invalid object field 'position'" % [filename, path])
	else:
		for axis in ["economic", "social"]:
			var v = pos.get(axis, null)
			if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
				errors.append("%s: %s position.%s missing or non-numeric" % [filename, path, axis])
			elif float(v) < -1.0 or float(v) > 1.0:
				errors.append("%s: %s position.%s = %s must be in [-1, 1]" % [
					filename, path, axis, str(v)
				])
			else:
				o.position[axis] = float(v)

	for key in d.keys():
		if key != "id" and key != "name" and key != "audience" and key != "reach" and key != "position":
			errors.append("%s: %s has unrecognised field '%s' -- an outlet carries NO authored alignment, hostility, bias or stance: alignment is derived from `position` against the nation's live coalition_position, and authoring one would be a second writer of it. It carries no editor or proprietor either, because a person has no field that could hold a mechanism" % [
				filename, path, key
			])

	return o
