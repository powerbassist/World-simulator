class_name GameEvent
extends RefCounted

## One entry in a data/events/*.json file -- V1.8, the last block of the V1 tier.
## Validated loudly at load, never mutated afterwards, exactly as src/core/law.gd and
## the six action types before it.
##
## `class_name GameEvent` rather than `Event`, because `Event` is close enough to
## Godot's own vocabulary to be a trap, and the file is still event.gd. The same dodge
## `outlet_name`, `law_name` and `project_name` make for `name`.
##
## ============================================================================
## AN EVENT IS AN OCCASION, NOT A NEW MECHANIC
## ============================================================================
## Counting docs/brainstorm/mechanics-*.md's tier column one last time turned up
## something forty-three prior instances had missed: section 8's own two bullets are
## tiered NOWHERE, and every event-shaped mechanic in those four tables is Someday --
## Terrorism, Pandemics and global crises, Emergency powers, the housing market. The
## only V1-tiered mechanic this section owns is the Scandals row it inherited from
## section 5 at V1.5d.
##
## So there is no crisis left to author that is not either a machine this project
## already built (a strike is V1.5c, a downgrade is V1.6c, a foreign act is V1.3f) or a
## mechanic tiered out of V1. What IS missing, and what an event supplies, is a MOMENT
## AT WHICH THE PLAYER MUST CHOOSE, where the systemic loop otherwise offers only
## standing rates the player may move whenever they like.
##
##   An event does not add a consequence the game did not have.
##   It adds an occasion on which the player must pick one, a menu, and a deadline.
##
## That is what keeps this from being the generic engine under another name that
## docs/tiers/v1.md section 8's warning box forbids: the consequences are systemic and
## every one of them lands on a register some earlier session already owns.
##
## ============================================================================
## THE CHOICE CHANNEL IS THE LAW CHANNEL MINUS `institutional`
## ============================================================================
## Law.extract_shared_effects() is the whole schema, shared rather than copied, and its
## header carries the argument for why the "union of the channels sections 3-7 create"
## is right about the timing and wrong about the shape.
##
## `institutional` is refused, and the refusal has a CITATION rather than only an
## argument: an event choice that could write censure_rule or dissolution_rule is
## "Emergency powers -- suspend normal process during crisis. Addictive and corrosive",
## tiered Someday in docs/brainstorm/mechanics-governance.md. The two keys V1.7c made
## reachable by an ordinary Act are refused with the six entrenched ones, because an
## electoral system rewritten as an executive response to a crisis is worse than one
## entrenched at the amendment bar, not better.
##
## What is NOT refused is tax and spending, and that is deliberate. "Decree / executive
## order -- bypass the assembly on a narrow set of matters, at a legitimacy cost" is
## tiered V1 in that same file and appears in no row of any tier doc; a choice that
## moves a budget line with no division IS that mechanic, the narrow set of matters is
## what the event's content names, and the legitimacy cost is the choice's own
## `bloc_offset`. See docs/events-model.md section 4.

const Law = preload("res://src/core/law.gd")
const K = preload("res://src/sim/events_constants.gd")

var id: String = ""
var event_name: String = ""
var summary: String = ""

## Optional. One of events_constants.SUBJECT_OFFICES, or "" for an event about nobody.
## The sim never resolves it; src/ui/main.gd turns it into a name at card time through
## the register U6b built. U6b's rule verbatim -- a law names an office, the nation's
## own data names the person -- which is what keeps "no mechanism on a person" true by
## construction rather than by intention.
var subject_office: String = ""

## Monthly hazard once every precondition holds, in [LIKELIHOOD_MIN, LIKELIHOOD_MAX].
## Drawn against a deterministic hash of (nation id, event id, absolute month) -- there
## is no randomness anywhere in this project and docs/economy-model.md forbids it
## outright, because determinism is what makes Budget.project() exactly equal to what
## subsequently happens. Section 8 asks for "semi-random"; V1.6a already answered that
## for the business cycle and this is the same answer. Surprise was never the mechanic.
var likelihood: float = 0.0

## Months the player has to answer before the default choice applies to them.
var respond_months: int = 0

## Whether this event can ever fire twice.
var once: bool = false

## V2.4b, and the one boolean that reverses a V1.8 call -- for THIS CLASS ONLY.
## docs/events-model.md's non-modal argument survives for every event without the
## flag: a crisis you can ignore and pay for is the whole of "time pressure". What
## the flag buys is the case that argument does not cover -- an event nobody could
## reasonably choose to ignore -- and for it the clock PAUSES on announcement and
## stays paused until the player answers. Default false: absent in a version-27
## save reads as non-interrupt, which is the truth about that save.
var interrupt := false

## Array of {"field", "op", "value"} on legislature_constants.PRECONDITION_FIELDS,
## minus events_constants.EVENT_PRECONDITION_REFUSED. Often EMPTY, and that is the
## honest split between section 8's two bullets rather than a shortcut: a scandal is
## the pure-hazard case (bullet 2, arriving whether or not deserved) and a fiscal
## ultimatum is the preconditioned one (bullet 1, data-defined with preconditions).
var preconditions: Array = []

## Array of {"id", "label", "summary", "effects", "is_default"}. Two to four, exactly
## one of them the default.
var choices: Array = []

const MIN_CHOICES := 2
const MAX_CHOICES := 4


static func from_dict(d: Dictionary, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array, sector_keys: Array) -> GameEvent:
	var ev := new()

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: missing or invalid string field 'id'" % filename)
	else:
		ev.id = d["id"]

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, ev.id])
	else:
		ev.event_name = d["name"]

	if not d.has("summary") or typeof(d["summary"]) != TYPE_STRING or d["summary"] == "":
		errors.append("%s: %s missing or invalid string field 'summary' -- an event with no body is a card that says nothing" % [filename, ev.id])
	else:
		ev.summary = d["summary"]

	if d.has("subject_office"):
		var office = d["subject_office"]
		if typeof(office) != TYPE_STRING or not K.SUBJECT_OFFICES.has(office):
			errors.append("%s: %s subject_office '%s' must be one of %s" % [
				filename, ev.id, str(office), K.SUBJECT_OFFICES
			])
		else:
			ev.subject_office = office

	if not d.has("likelihood") or not (typeof(d["likelihood"]) == TYPE_INT or typeof(d["likelihood"]) == TYPE_FLOAT):
		errors.append("%s: %s likelihood is missing or not numeric" % [filename, ev.id])
	else:
		ev.likelihood = float(d["likelihood"])
		if ev.likelihood < K.LIKELIHOOD_MIN or ev.likelihood > K.LIKELIHOOD_MAX:
			errors.append("%s: %s likelihood = %s out of range [%s, %s]" % [
				filename, ev.id, str(ev.likelihood), str(K.LIKELIHOOD_MIN), str(K.LIKELIHOOD_MAX)
			])

	if not d.has("respond_months") or not (typeof(d["respond_months"]) == TYPE_INT or typeof(d["respond_months"]) == TYPE_FLOAT):
		errors.append("%s: %s respond_months is missing or not numeric" % [filename, ev.id])
	else:
		ev.respond_months = int(d["respond_months"])
		if ev.respond_months < K.RESPOND_MONTHS_MIN or ev.respond_months > K.RESPOND_MONTHS_MAX:
			errors.append("%s: %s respond_months = %d out of range [%d, %d]" % [
				filename, ev.id, ev.respond_months, K.RESPOND_MONTHS_MIN, K.RESPOND_MONTHS_MAX
			])

	ev.once = bool(d.get("once", false))
	ev.interrupt = bool(d.get("interrupt", false))
	ev.preconditions = Law.extract_preconditions(
		d, ev.id, filename, errors, K.EVENT_PRECONDITION_REFUSED
	)
	ev.choices = _extract_choices(
		d, ev.id, filename, errors, tax_keys, spending_keys, bloc_keys, sector_keys
	)

	for key in d.keys():
		if not KNOWN_KEYS.has(key):
			errors.append("%s: %s '%s' is not a recognised event field -- an event is %s and nothing else" % [
				filename, ev.id, key, KNOWN_KEYS
			])

	return ev


const KNOWN_KEYS := [
	"id", "name", "summary", "subject_office", "likelihood", "respond_months",
	"once", "preconditions", "choices", "interrupt",
]

const CHOICE_KEYS := ["id", "label", "summary", "effects", "default"]


static func _extract_choices(d: Dictionary, event_id: String, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array, sector_keys: Array) -> Array:
	var raw = d.get("choices", [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s: %s choices must be an array" % [filename, event_id])
		return []
	if raw.size() < MIN_CHOICES or raw.size() > MAX_CHOICES:
		errors.append("%s: %s has %d choices, and an event carries between %d and %d -- one choice is not a decision" % [
			filename, event_id, raw.size(), MIN_CHOICES, MAX_CHOICES
		])

	var out: Array = []
	var seen := {}
	var defaults := 0
	for i in raw.size():
		var entry = raw[i]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s: %s choices[%d] is not an object" % [filename, event_id, i])
			continue

		var cid = entry.get("id", "")
		if typeof(cid) != TYPE_STRING or cid == "":
			errors.append("%s: %s choices[%d] missing or invalid string field 'id'" % [filename, event_id, i])
			continue
		if seen.has(cid):
			errors.append("%s: %s has two choices called '%s'" % [filename, event_id, cid])
		seen[cid] = true

		var path := "%s.%s" % [event_id, cid]

		var label = entry.get("label", "")
		if typeof(label) != TYPE_STRING or label == "":
			errors.append("%s: %s missing or invalid string field 'label' -- it is the button" % [filename, path])
			label = ""

		var choice_summary = entry.get("summary", "")
		if typeof(choice_summary) != TYPE_STRING or choice_summary == "":
			errors.append("%s: %s missing or invalid string field 'summary' -- a button with no consequence written beside it is a coin toss" % [filename, path])
			choice_summary = ""

		var is_default := bool(entry.get("default", false))
		if is_default:
			defaults += 1

		var effects := _extract_effects(
			entry, path, filename, errors, tax_keys, spending_keys, bloc_keys, sector_keys
		)

		for key in entry.keys():
			if not CHOICE_KEYS.has(key):
				errors.append("%s: %s '%s' is not a recognised choice field" % [filename, path, key])

		out.append({
			"id": cid,
			"label": label,
			"summary": choice_summary,
			"effects": effects,
			"is_default": is_default,
		})

	# EXACTLY ONE DEFAULT, and it is required rather than inferred from the ordering.
	# What happens when the player says nothing is the whole of "forces a response
	# under time pressure", so it is the one thing an author must state out loud --
	# and an inferred default (the first, the last, the cheapest) is a rule a reader
	# has to know rather than read.
	if not out.is_empty() and defaults != 1:
		errors.append("%s: %s has %d choices marked `default` and needs exactly one -- what happens when the player says nothing is the whole of the deadline" % [
			filename, event_id, defaults
		])

	return out


## A choice's effects. Law.extract_shared_effects() plus one refusal, and the refusal
## names Emergency powers rather than saying "unrecognised" -- src/core/law.gd's own
## V1.7c error string, which names WHICH rule was broken rather than lumping the key in
## with a typo.
static func _extract_effects(entry: Dictionary, path: String, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array, sector_keys: Array) -> Dictionary:
	var raw = entry.get("effects", {})
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects must be an object" % [filename, path])
		return {}

	if raw.has("institutional"):
		errors.append("%s: %s effects.institutional is refused on an event choice -- an institution rewritten as an executive response to a crisis is \"Emergency powers\", tiered Someday in docs/brainstorm/mechanics-governance.md. An institution changes by amendment, or for the two electoral keys by ordinary Act; see src/core/law.gd" % [filename, path])

	var out := Law.extract_shared_effects(
		raw, path, filename, errors, tax_keys, spending_keys, bloc_keys, sector_keys
	)

	for key in raw.keys():
		if not Law.SHARED_EFFECT_CHANNELS.has(key) and not Law.SCALAR_EFFECT_KEYS.has(key) and key != "institutional":
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, path, key])

	# V1.3f's property that nothing on the law list does nothing, restated where it
	# bites hardest: a choice with no effects is a button that resolves the deadline for
	# free, which makes every other choice on that event strictly dominated. The shape
	# this project has killed eleven times, refused at LOAD rather than measured by the
	# probe -- because unlike a mis-sized effect, a missing one cannot be tuned.
	if out.is_empty():
		errors.append("%s: %s names no effect at all -- a choice that costs nothing resolves the deadline for free and strictly dominates every other choice on this event" % [filename, path])

	return out


## Whether this event names an office at all.
func has_subject() -> bool:
	return subject_office != ""


## The choice that applies when the player says nothing. Never empty for a loaded event:
## _extract_choices() refuses a file without exactly one.
func default_choice() -> Dictionary:
	for c in choices:
		if bool(c["is_default"]):
			return c
	return {}


func choice_by_id(choice_id: String) -> Dictionary:
	for c in choices:
		if String(c["id"]) == choice_id:
			return c
	return {}
