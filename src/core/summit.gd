class_name Summit
extends RefCounted

## Typed, validated in-memory representation of one summit scene: a pair of
## files in data/summits/ -- <ID>.dialogue (the scene, dialogue_manager syntax)
## and <ID>.json (the sidecar naming it and pricing its outcomes). See
## docs/tiers/v2.md section 4 and docs/calendar-model.md.
##
## The sidecar carries the EFFECTS and the .dialogue carries the SCENE, and the
## join is the response LABEL: every response in the dialogue must have an
## effects entry with exactly that text, and every effects entry must name a
## response the dialogue actually offers. Validated at load, loudly -- a scene
## that offers a choice nothing prices, or prices a choice nothing offers, is
## the unread `refused_by_partner` waiting to ship.

const Law = preload("res://src/core/law.gd")

var id: String = ""
var nation_id: String = ""
var summit_name: String = ""
var summary: String = ""
var dialogue_text: String = ""

## {response label -> effects dict in Legislature.apply_effects() channels}.
var effects: Dictionary = {}


## No `-> Summit` on the signature: a new script cannot reference its own
## class_name before the global class cache exists -- CLAUDE.md's first gotcha,
## and U5b paid for it. The loader's calls are untyped anyway.
static func from_dict(
	dialogue_text: String, nation_id: String, file_id: String,
	d: Dictionary, filename: String, errors: Array[String],
	tax_keys: Array, spending_keys: Array, bloc_keys: Array, sector_keys: Array
):
	var s := new()
	s.id = file_id
	s.nation_id = nation_id
	s.dialogue_text = dialogue_text

	s.summit_name = d.get("name", "")
	if typeof(s.summit_name) != TYPE_STRING or s.summit_name == "":
		errors.append("%s: missing or invalid string field 'name'" % filename)

	s.summary = d.get("summary", "")
	if typeof(s.summary) != TYPE_STRING or s.summary == "":
		errors.append("%s: missing or invalid string field 'summary' -- a scene that cannot say what it is about is a window that opens for nothing" % filename)

	if s.dialogue_text.strip_edges() == "":
		errors.append("%s: empty dialogue text" % filename)

	var raw = d.get("effects", {})
	if typeof(raw) != TYPE_DICTIONARY or raw.is_empty():
		errors.append("%s: effects must be a non-empty object -- every response the scene offers has to land somewhere" % filename)
		return s

	# The labels the dialogue offers, parsed minimally: dialogue_manager's
	# response syntax is `- text => target` at the start of a line. The load
	# check does not compile -- the game compiles at draw time -- it only needs
	# the SET of labels, and a line-level scan is exact for the subset of the
	# syntax this content uses. If summit content ever grows conditions or
	# nested jumps, this check grows with it and says so here.
	var labels: Array[String] = []
	for line in s.dialogue_text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("- "):
			continue
		var label := trimmed.substr(2)
		var arrow := label.rfind("=>")
		if arrow != -1:
			label = label.substr(0, arrow)
		labels.append(label.strip_edges())

	if labels.is_empty():
		errors.append("%s: the dialogue offers no responses -- a scene with no choice is a letter, not a summit" % filename)

	# The TOP-LEVEL keys are response LABELS; the effect CHANNELS sit inside
	# each label's object, exactly as an event choice's effects do. Extracted
	# per label through the shared extractor so the validation cannot drift
	# from what apply_effects() will actually do with it.
	var extracted: Dictionary = {}
	for label in raw.keys():
		var inner = raw[label]
		if typeof(inner) != TYPE_DICTIONARY:
			errors.append("%s: effects['%s'] must be an object" % [filename, str(label)])
			continue
		for channel in inner.keys():
			if not Law.SHARED_EFFECT_CHANNELS.has(channel):
				errors.append("%s: effects['%s'].%s is not a recognised effect channel -- a summit lands where a law and an event choice can (%s), and nothing else" % [
					filename, str(label), str(channel), str(Law.SHARED_EFFECT_CHANNELS)
				])
				continue
		# THE RETURN VALUE IS WHAT GETS STORED, which is what Law._extract_effects()
		# and GameEvent._extract_effects() both do. Called for validation alone until
		# the V2.8 review, with the raw JSON kept instead -- so a whole-number value in
		# a sidecar stayed an int where every other content type in this project
		# guarantees a float, and the canonicalization the extractor exists to perform
		# never reached the object at all.
		extracted[label] = Law.extract_shared_effects(
			inner, s.id, "%s.effects['%s']" % [filename, str(label)],
			errors, tax_keys, spending_keys, bloc_keys, sector_keys
		)

	for label in labels:
		if not raw.has(label):
			errors.append("%s: the response '%s' has no effects entry -- a choice that lands nowhere must not be offerable" % [filename, label])
	for key in raw.keys():
		if not labels.has(String(key)):
			errors.append("%s: effects name '%s' but no response offers it -- a price with no choice behind it is content that can never run" % [filename, str(key)])

	s.effects = extracted
	return s
