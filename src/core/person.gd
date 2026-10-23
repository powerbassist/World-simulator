class_name Person
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/people/*.json file. See docs/people-model.md (sections 2, 4 and 14)
## and docs/fictionalization.md.
##
## Seven fields: WHO a person is (id, name, kind) and WHAT THEY WANT (traits,
## ambition, wants), plus the one optional affiliation edge (party_id) a
## backbencher needs because no slot points at them.
##
## Two of the three fields this class was born refusing are still refused:
## `title` is an office's property (`ns.head_of_state_title`, and an amendment
## can change it under a person who has not moved), and `role` is the slot
## pointing at them (`pm_person_id`, `leader_person_id`) -- a second record of
## the reference graph is the divergence the register exists to remove, and
## Daniel Moucron -- head of state AND a party leader -- shows a role cannot
## even be single-valued. `party_id` re-joined at V4.3 in the narrow
## backbencher form: anyone a slot or a leadership points at leaves it empty,
## and it exists so a bench politician's affiliation is authored once instead
## of dangling with no edge at all.
##
## WHAT A PERSON WANTS IS CONTENT, NEVER STATE. Traits, ambition and the want
## list are authored in data/ and do not move; what the player DID to a person
## -- loyalty, standing, grudges, overrides -- is live state on NationState
## (SAVE_VERSION 36). Keeping the halves apart is the difference between a
## character and a save.
##
## Validation splits in two by necessity, not taste: people load BEFORE
## parties and programme, so this file checks shape and closed vocabularies
## (kind, traits, stance-for-family, threshold coherence) and
## PeopleLoader.validate_people() resolves the cross-register halves (party
## ids, programme entries, portfolios) once the whole loader is in hand.
## `kind` absent reads "politician" -- the truth about every one of the 213
## entries that existed before V4.3 -- and an explicit unknown kind is an
## error, never a silent fallback to the default.

const CharacterK = preload("res://src/sim/character_constants.gd")

## The keys a want object may carry. Closed for the sidecar-contract reason:
## "threhold" must be a load error, not an inert half of a want nobody reads.
const WANT_FIELDS := ["object", "stance", "below", "above"]

var id: String = ""
var person_name: String = ""
var kind: String = "politician"
var traits: Array[String] = []
var ambition: float = 0.5
var party_id: String = ""
var wants: Array[Dictionary] = []
## The portrait tiering flag: `bench: false` is the met cast (V2.3's
## political register), `bench: true` is the V4.3 deep bench. The PORTRAIT
## pipeline reads it (met cast renders five emotions, bench renders the
## single neutral) and nothing in src/sim/ does -- it is not character
## content, it is an art-logistics marker, which is also why it defaults to
## false: every person of the pre-V4.3 register is met cast.
var bench: bool = false
## V5.2a, three more facts about who a person IS, none of which moves -- so the
## character layer's content/state line holds (people-model 14.9). How well
## they read others and hide themselves, in [0, 1]: a lie's catch and a
## flatterer's backfire both read it. 0.5 absent, a middling reader, which is
## the honest default for a person Content has not yet characterised.
var social_skill: float = 0.5
## The person record they are married to, "" for none. A content field on the
## leader, not a marriage system: nothing in src/sim/ makes or ends a marriage
## (spec C2), and the affair reads it.
var spouse_id: String = ""
## Personal wealth at game start, EUR millions. The START only: what the
## president gains or loses is NationState.person_wealth_delta_eur_m.
var wealth_eur_m: float = 0.0


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

	# --- The character layer (V4.3) ------------------------------------------------
	if d.has("kind"):
		if typeof(d["kind"]) != TYPE_STRING or not CharacterK.KIND_KEYS.has(String(d["kind"])):
			errors.append("%s: %s field 'kind' must be one of %s" % [
				filename, path, str(CharacterK.KIND_KEYS)])
		else:
			p.kind = String(d["kind"])

	if d.has("traits"):
		if typeof(d["traits"]) != TYPE_ARRAY:
			errors.append("%s: %s field 'traits' must be an array" % [filename, path])
		else:
			# 2-3 is the authored band; 4+ is a load error because a trait past
			# the third prices nothing -- the generator and hand edits share it.
			if d["traits"].size() > 3:
				errors.append("%s: %s carries %d traits; at most 3" % [
					filename, path, d["traits"].size()])
			for raw in d["traits"]:
				# `trait` is a reserved word in GDScript 4.x (a future language
				# feature), so the local is trait_name -- named here because the
				# natural spelling is the one the parser refuses.
				var trait_name := String(raw)
				if not CharacterK.TRAIT_KEYS.has(trait_name):
					errors.append("%s: %s trait '%s' is not in the trait set %s" % [
						filename, path, trait_name, str(CharacterK.TRAIT_KEYS)])
				elif p.traits.has(trait_name):
					errors.append("%s: %s carries trait '%s' twice" % [filename, path, trait_name])
				else:
					p.traits.append(trait_name)

	if d.has("ambition"):
		if typeof(d["ambition"]) in [TYPE_FLOAT, TYPE_INT]:
			var a := float(d["ambition"])
			if a < 0.0 or a > 1.0:
				errors.append("%s: %s ambition %.2f outside [0, 1]" % [filename, path, a])
			else:
				p.ambition = a
		else:
			errors.append("%s: %s field 'ambition' must be a number in [0, 1]" % [
				filename, path])

	if d.has("party_id"):
		if typeof(d["party_id"]) != TYPE_STRING:
			errors.append("%s: %s field 'party_id' must be a string" % [filename, path])
		else:
			p.party_id = String(d["party_id"])

	if d.has("bench"):
		if typeof(d["bench"]) == TYPE_BOOL:
			p.bench = bool(d["bench"])
		else:
			errors.append("%s: %s field 'bench' must be a boolean" % [filename, path])

	# V5.2a. Shape only; spouse_id resolves in PeopleLoader.validate_people(),
	# where every nation's register is in hand (a spouse may be authored after).
	if d.has("social_skill"):
		var skill = d["social_skill"]
		if typeof(skill) in [TYPE_FLOAT, TYPE_INT] and float(skill) >= 0.0 and float(skill) <= 1.0:
			p.social_skill = float(skill)
		else:
			errors.append("%s: %s field 'social_skill' must be a number in [0, 1]" % [filename, path])

	if d.has("spouse_id"):
		if typeof(d["spouse_id"]) == TYPE_STRING:
			p.spouse_id = String(d["spouse_id"])
		else:
			errors.append("%s: %s field 'spouse_id' must be a string" % [filename, path])

	if d.has("wealth_eur_m"):
		var wealth = d["wealth_eur_m"]
		if typeof(wealth) in [TYPE_FLOAT, TYPE_INT] and float(wealth) >= 0.0:
			p.wealth_eur_m = float(wealth)
		else:
			errors.append("%s: %s field 'wealth_eur_m' must be a number >= 0" % [filename, path])

	if d.has("wants"):
		if typeof(d["wants"]) != TYPE_ARRAY:
			errors.append("%s: %s field 'wants' must be an array" % [filename, path])
		else:
			var seen_objects := {}
			for j in d["wants"].size():
				_validate_want(d["wants"][j], "%s.wants[%d]" % [path, j], filename, errors, p, seen_objects)

	return p


## One want: an object string (family:target), a stance legal for the family,
## and -- for a meter want only -- exactly one numeric threshold. A duplicate
## object on one person is refused too: a person cannot sponsor the same entry
## twice, and a downstream reader must not have to ask which copy governs.
static func _validate_want(w, wpath: String, filename: String, errors: Array[String], p, seen_objects: Dictionary) -> void:
	if typeof(w) != TYPE_DICTIONARY:
		errors.append("%s: %s is not an object" % [filename, wpath])
		return
	for key in (w as Dictionary).keys():
		if not WANT_FIELDS.has(String(key)):
			errors.append("%s: %s carries '%s', which is not a want field (%s)" % [
				filename, wpath, str(key), str(WANT_FIELDS)])

	var object := String(w.get("object", ""))
	var stance := String(w.get("stance", ""))
	var family := object.split(":")[0] if object.contains(":") else ""

	if not CharacterK.WANT_STANCES.has(family):
		errors.append("%s: %s object '%s' has no known want family (programme:/office:/meter:)" % [
			filename, wpath, object])
		return
	if not (CharacterK.WANT_STANCES[family] as Array).has(stance):
		errors.append("%s: %s stance '%s' is not legal for a %s want (%s)" % [
			filename, wpath, stance, family, str(CharacterK.WANT_STANCES[family])])
		return
	# The meter's own key, HERE rather than in PeopleLoader.resolve_want(): it is
	# a closed vocabulary like kind and traits, and the loader's half only
	# resolves cross-register references. A want for "meter:corruption" would
	# otherwise load clean and sit inert forever -- the exact class the closed
	# lists exist to make loud.
	if family == "meter":
		var meter_key := object.substr("meter:".length())
		if not CharacterK.METER_KEYS.has(meter_key):
			errors.append("%s: %s names meter '%s', which is not one of the meters (%s)" % [
				filename, wpath, meter_key, str(CharacterK.METER_KEYS)])
			return
	if seen_objects.has(object):
		errors.append("%s: %s repeats object '%s'; one want per object" % [
			filename, wpath, object])
		return
	seen_objects[object] = true

	# Threshold coherence: a meter want carries EXACTLY ONE of below/above --
	# both is contradictory, neither is a want with no condition -- and no
	# other family reads one, so a threshold on an office want is content
	# asserting a number nothing reads.
	var has_below := (w as Dictionary).has("below")
	var has_above := (w as Dictionary).has("above")
	if family == "meter":
		if has_below == has_above:
			errors.append("%s: %s must carry exactly one of below/above" % [filename, wpath])
		else:
			var key := "below" if has_below else "above"
			# The stance PAIRS with its direction, or the stance is prose
			# nothing reads: "demand" wants the meter DOWN (below) and
			# "defend" wants it HELD UP (above) -- a demand-above want loads
			# as "wants it high", which is defend's meaning in demand's
			# clothing. Refused loudly rather than read either way.
			var stance_expects_below := stance == "demand"
			if (has_below and not stance_expects_below) or (has_above and stance_expects_below):
				errors.append("%s: %s stance '%s' pairs with '%s', not '%s'" % [
					filename, wpath, stance, "below" if stance_expects_below else "above", key])
			elif typeof((w as Dictionary)[key]) not in [TYPE_FLOAT, TYPE_INT]:
				errors.append("%s: %s '%s' must be a number" % [filename, wpath, key])
	elif has_below or has_above:
		errors.append("%s: %s carries a threshold; only a meter want reads one" % [
			filename, wpath])

	p.wants.append(w)
