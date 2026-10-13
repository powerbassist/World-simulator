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

## V3.5, and the environment block's first claim on this schema: a crisis that
## happens to a PLACE -- a flood, a heatwave -- rather than only to the government.
## The site itself is drawn at announcement, uniform over the nation's live regions
## and pure in (nation, event, absolute month) exactly like the hazard above; see
## src/sim/events.gd. Content opts in with `"sited": true`; absent reads false,
## which is the truth about every event file and every save made before the key
## existed -- the interrupt flag's argument one boolean later.
var sited := false

## Array of {"field", "op", "value"} on legislature_constants.PRECONDITION_FIELDS,
## minus events_constants.EVENT_PRECONDITION_REFUSED. Often EMPTY, and that is the
## honest split between section 8's two bullets rather than a shortcut: a scandal is
## the pure-hazard case (bullet 2, arriving whether or not deserved) and a fiscal
## ultimatum is the preconditioned one (bullet 1, data-defined with preconditions).
var preconditions: Array = []

## V4.4. REQUIRED. One of events_constants.CATEGORIES. The draw's unit: hazards fire
## per event as they always did, the winner inside a category is weighted, and the
## quiet after a resolution quiets the category. See events_constants.CATEGORIES for
## why a flat global draw could let one loud category crowd the rest out on hazard
## order alone.
var category: String = ""

## V4.4. Draw weight inside the category, in [WEIGHT_MIN, WEIGHT_MAX]. Content, not
## a machine number: it decides only RELATIVE to the other events drawing this month,
## which is why its bounds are wide and its default is neutral.
var weight: float = K.WEIGHT_DEFAULT

## V4.4. 1..3 -- minor / major / critical. Orders the pending queue; V4.8's message
## settings and auto-pause will key on it. Authored because it is a fact about the
## event's weight in the world, not derivable from its effects.
var severity: int = K.SEVERITY_DEFAULT

## V4.4. One of events_constants.ON_ACTIONS, or "" for the standing monthly hazard.
## A hook event fires BECAUSE something happened -- its emitter is read inside
## Events.tick_month off registers the machines already write (or the two V4.4 stamps,
## `repealed_at` and `last_accession`, documented in nation_state.gd) -- and its `likelihood` is the
## chance the hooked happening spawns the occasion. The preconditions still gate it.
var on_action: String = ""

## V4.4. Months after DELIVERY before this event may draw again -- the machine
## writes `month_index + cooldown_months` in Events._deliver(), the one door every
## nation passes, which is the `once` mark's own anchor. The V1.8 cut of this field
## rested on the one-slot argument, which the queue retired; 0 is the default (the
## category quiet already bounds cross-firing) and still binds ONE month -- the machine
## floors the stamp at 1 so an event is never delivered twice in one tick.
var cooldown_months: int = 0

## Array of {"id", "label", "summary", "effects", "is_default"} plus the V4.4
## optional "arms" ({event_id, delay_months}). Two to four, exactly one of them the
## default.
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
	elif not _is_integral(d["respond_months"]):
		errors.append("%s: %s respond_months = %s is not a whole number of months" % [filename, ev.id, str(d["respond_months"])])
	else:
		ev.respond_months = int(d["respond_months"])
		if ev.respond_months < K.RESPOND_MONTHS_MIN or ev.respond_months > K.RESPOND_MONTHS_MAX:
			errors.append("%s: %s respond_months = %d out of range [%d, %d]" % [
				filename, ev.id, ev.respond_months, K.RESPOND_MONTHS_MIN, K.RESPOND_MONTHS_MAX
			])

	if not d.has("category") or typeof(d["category"]) != TYPE_STRING or not K.CATEGORIES.has(d["category"]):
		errors.append("%s: %s category is missing or not one of %s -- V4.4 requires it; the category is the draw's unit" % [
			filename, ev.id, K.CATEGORIES
		])
	else:
		ev.category = d["category"]

	if d.has("weight"):
		if not (typeof(d["weight"]) == TYPE_INT or typeof(d["weight"]) == TYPE_FLOAT):
			errors.append("%s: %s weight is not numeric" % [filename, ev.id])
		else:
			ev.weight = float(d["weight"])
			if ev.weight < K.WEIGHT_MIN or ev.weight > K.WEIGHT_MAX:
				errors.append("%s: %s weight = %s out of range [%s, %s]" % [
					filename, ev.id, str(ev.weight), str(K.WEIGHT_MIN), str(K.WEIGHT_MAX)
				])

	if d.has("severity"):
		if not (typeof(d["severity"]) == TYPE_INT or typeof(d["severity"]) == TYPE_FLOAT):
			errors.append("%s: %s severity is not numeric" % [filename, ev.id])
		elif not _is_integral(d["severity"]):
			errors.append("%s: %s severity = %s is not a whole number (1 minor, 2 major, 3 critical)" % [filename, ev.id, str(d["severity"])])
		else:
			ev.severity = int(d["severity"])
			if ev.severity < K.SEVERITY_MIN or ev.severity > K.SEVERITY_MAX:
				errors.append("%s: %s severity = %d out of range [%d, %d] (1 minor, 2 major, 3 critical)" % [
					filename, ev.id, ev.severity, K.SEVERITY_MIN, K.SEVERITY_MAX
				])

	if d.has("on_action"):
		var hook = d["on_action"]
		if typeof(hook) != TYPE_STRING or not K.ON_ACTIONS.has(hook):
			# Names the refused hook in the error rather than lumping it with typos:
			# src/core/law.gd's own V1.7c discipline, and election_lost is the one an
			# author will reach for.
			errors.append("%s: %s on_action '%s' is not one of %s -- and 'election_lost' is refused outright: a lost election ends the game, so nothing could answer the event" % [
				filename, ev.id, str(hook), K.ON_ACTIONS
			])
		else:
			ev.on_action = hook

	if d.has("cooldown_months"):
		if not (typeof(d["cooldown_months"]) == TYPE_INT or typeof(d["cooldown_months"]) == TYPE_FLOAT):
			errors.append("%s: %s cooldown_months is not numeric" % [filename, ev.id])
		elif not _is_integral(d["cooldown_months"]):
			errors.append("%s: %s cooldown_months = %s is not a whole number of months" % [filename, ev.id, str(d["cooldown_months"])])
		else:
			ev.cooldown_months = int(d["cooldown_months"])
			if ev.cooldown_months < 0 or ev.cooldown_months > K.EVENT_COOLDOWN_MAX_MONTHS:
				errors.append("%s: %s cooldown_months = %d out of range [0, %d]" % [
					filename, ev.id, ev.cooldown_months, K.EVENT_COOLDOWN_MAX_MONTHS
				])

	ev.once = bool(d.get("once", false))
	ev.interrupt = bool(d.get("interrupt", false))
	ev.sited = bool(d.get("sited", false))
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


## JSON numbers arrive as float, so "an integer field" means a float with no
## fractional part. `int()` would load 2.9 as 2 silently (and 0.5 as 0, then
## refuse it for a range it was never given); the schema refuses the value
## itself, naming it. The caller has already checked the type is numeric.
static func _is_integral(v) -> bool:
	return float(v) == floorf(float(v))


const KNOWN_KEYS := [
	"id", "name", "summary", "subject_office", "likelihood", "respond_months",
	"once", "preconditions", "choices", "interrupt", "sited",
	"category", "weight", "severity", "on_action", "cooldown_months",
]

const CHOICE_KEYS := ["id", "label", "summary", "effects", "default", "arms"]


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

		# V4.4: a choice may arm a follow-up event at a delay -- the chain machine
		# V4.1 deliberately refused, built once here. The target is validated as a
		# loaded event id by the loader's cross-check (it needs the whole set in
		# hand, _validate_people's pattern); here only the shape and the delay bound.
		var arms := {}
		if entry.has("arms"):
			var raw_arms = entry["arms"]
			if typeof(raw_arms) != TYPE_DICTIONARY:
				errors.append("%s: %s arms must be an object {event_id, delay_months}" % [filename, path])
			else:
				var target = raw_arms.get("event_id", "")
				var delay = raw_arms.get("delay_months", 0)
				if typeof(target) != TYPE_STRING or target == "":
					errors.append("%s: %s arms.event_id is missing or not a string" % [filename, path])
				elif not (typeof(delay) == TYPE_INT or typeof(delay) == TYPE_FLOAT) \
						or not _is_integral(delay) \
						or int(delay) < K.ARMS_DELAY_MIN_MONTHS \
						or int(delay) > K.ARMS_DELAY_MAX_MONTHS:
					errors.append("%s: %s arms.delay_months = %s is not a whole number in [%d, %d]" % [
						filename, path, str(delay), K.ARMS_DELAY_MIN_MONTHS, K.ARMS_DELAY_MAX_MONTHS
					])
				else:
					arms = {"event_id": target, "delay_months": int(delay)}

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
			"arms": arms,
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
