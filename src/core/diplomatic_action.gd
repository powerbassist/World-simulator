class_name DiplomaticAction
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/diplomatic-actions/*.json file. See docs/diplomacy-model.md and
## docs/data-architecture.md.
##
## Mirrors src/core/law.gd's from_dict shape: a plain data object built once at
## load time, validated loudly, never mutated afterward.
##
## Borrowed from the law template: preconditions, cooldown, effects. Deliberately
## NOT borrowed: `position`, `majority`, `once`. A diplomatic action is an
## executive act with no assembly division, so there is no vote to resolve and
## nothing for an ideology position to score -- giving it either would be a
## parallel vocabulary for a mechanism that does not exist here. `once` is
## absent because the cooldown is keyed per (action, target): a state visit to
## Germany and a state visit to Italy are separate uses of the same verb, and
## "once, ever, against anybody" is not a shape any action in this block wants.

const DK = preload("res://src/sim/diplomacy_constants.gd")
const TK = preload("res://src/sim/trade_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const CK = preload("res://src/sim/coercion_constants.gd")
const DFK = preload("res://src/sim/defence_constants.gd")


var id: String = ""
var action_name: String = ""
var summary: String = ""

## Months this action must wait before it can be used against THE SAME target
## again. Zero is legal and means no cooldown.
var cooldown_months: int = 0

## Array of {"field": String, "op": String, "value": float}, each field checked
## against diplomacy_constants.PRECONDITION_FIELDS at load time. "relations" is
## evaluated against the target of the proposed action; every other field is the
## acting nation's own state.
var preconditions: Array = []

## Five channels: `relations` (required and non-zero), `bloc_offset` (optional),
## `agreement` (V1.3b), `measure` (V1.3c) and `pact` (V1.3g), the last three
## optional and MUTUALLY EXCLUSIVE -- each is a separate counterparty decision, and
## one verb has one answer.
var effects: Dictionary = {}

## The list the unknown-channel check reads, so adding a sixth channel is one entry
## here rather than a fifth clause in a boolean nobody re-reads. V1.3g found that
## chain at four terms and turned it into a list before adding to it.
const EFFECT_CHANNELS := ["relations", "bloc_offset", "agreement", "measure", "pact"]


static func from_dict(d: Dictionary, filename: String, errors: Array[String], bloc_keys: Array):
	var a := new()

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: missing or invalid string field 'id'" % filename)
	else:
		a.id = d["id"]

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, a.id])
	else:
		a.action_name = d["name"]

	a.summary = d.get("summary", "")
	if typeof(a.summary) != TYPE_STRING:
		errors.append("%s: %s summary must be a string" % [filename, a.id])
		a.summary = ""

	a.cooldown_months = int(d.get("cooldown_months", 0))
	if a.cooldown_months < 0:
		errors.append("%s: %s cooldown_months must be >= 0" % [filename, a.id])

	a.preconditions = _extract_preconditions(d, a.id, filename, errors)
	a.effects = _extract_effects(d, a.id, filename, errors, bloc_keys)

	return a


static func _extract_preconditions(d: Dictionary, action_id: String, filename: String, errors: Array[String]) -> Array:
	var raw = d.get("preconditions", [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s: %s preconditions must be an array" % [filename, action_id])
		return []

	var out: Array = []
	for i in raw.size():
		var entry = raw[i]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s: %s preconditions[%d] is not an object" % [filename, action_id, i])
			continue

		var field = entry.get("field", "")
		if typeof(field) != TYPE_STRING or not DK.PRECONDITION_FIELDS.has(field):
			errors.append("%s: %s preconditions[%d].field '%s' is not a recognised field" % [filename, action_id, i, str(field)])
			continue

		var op = entry.get("op", "")
		if typeof(op) != TYPE_STRING or not DK.PRECONDITION_OPS.has(op):
			errors.append("%s: %s preconditions[%d].op '%s' is not a recognised operator" % [filename, action_id, i, str(op)])
			continue

		if not entry.has("value") or not (typeof(entry["value"]) == TYPE_INT or typeof(entry["value"]) == TYPE_FLOAT):
			errors.append("%s: %s preconditions[%d].value is missing or not numeric" % [filename, action_id, i])
			continue

		out.append({"field": field, "op": op, "value": float(entry["value"])})

	return out


## `relations` is REQUIRED and must be non-zero. An action that moves no pair is
## a domestic gesture wearing a diplomacy label -- the same class of quiet lie
## src/core/scenario.gd refuses for an overrides block that overrides nothing.
## `bloc_offset` is optional: an action with no domestic price is legitimate,
## and the measurement in docs/diplomacy-model.md is about whether a price that
## IS authored is legible, not about whether one must exist.
static func _extract_effects(d: Dictionary, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	var raw = d.get("effects", {})
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects must be an object" % [filename, action_id])
		return {}

	var out := {}

	if not raw.has("relations"):
		errors.append("%s: %s effects.relations is required -- an action that moves no pair is not a diplomatic action" % [filename, action_id])
	elif not (typeof(raw["relations"]) == TYPE_INT or typeof(raw["relations"]) == TYPE_FLOAT):
		errors.append("%s: %s effects.relations must be numeric" % [filename, action_id])
	else:
		var delta := float(raw["relations"])
		if is_zero_approx(delta):
			errors.append("%s: %s effects.relations is zero -- an action that moves no pair is not a diplomatic action" % [filename, action_id])
		if absf(delta) > DK.MAX_ACTION_RELATIONS_DELTA:
			errors.append("%s: %s effects.relations = %s exceeds MAX_ACTION_RELATIONS_DELTA (%s)" % [
				filename, action_id, str(delta), str(DK.MAX_ACTION_RELATIONS_DELTA)
			])
		out["relations"] = delta

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_bloc_offset(raw["bloc_offset"], action_id, filename, errors, bloc_keys)

	if raw.has("agreement"):
		out["agreement"] = _extract_agreement(raw["agreement"], action_id, filename, errors)

	if raw.has("measure"):
		out["measure"] = _extract_measure(raw["measure"], action_id, filename, errors)

	if raw.has("pact"):
		out["pact"] = _extract_pact(raw["pact"], action_id, filename, errors)

	# V1.3g: at most ONE of the three counterparty channels, where V1.3c wrote a
	# single pairwise test. Widened rather than extended, because a second pairwise
	# test beside the first is the shape that silently misses the third pair.
	#
	# agreement+pact is the one combination that is technically harmless -- separate
	# registers, no erase ordering -- and it is refused anyway: it would give one
	# action TWO counterparty gates, and execute()'s single `blocked_by_partner`
	# would have to become an OR that a later session has to unpick.
	var counterparty_channels: Array = []
	for channel in ["agreement", "measure", "pact"]:
		if raw.has(channel):
			counterparty_channels.append(channel)
	if counterparty_channels.size() > 1:
		errors.append("%s: %s carries %s -- an action may write at most one of the agreement, measure and pact registers, because each is a separate counterparty decision and one verb has one answer" % [
			filename, action_id, str(counterparty_channels)
		])

	# V1.3c's own message, kept for the pair it was written about: a measure breaks
	# an agreement on the same pair, so an action carrying both would describe an
	# order-dependent outcome rather than merely an ambiguous one.
	if raw.has("agreement") and raw.has("measure"):
		errors.append("%s: %s carries both effects.agreement and effects.measure -- a measure breaks an agreement on the same pair, so one action cannot do both" % [
			filename, action_id
		])

	for key in raw.keys():
		if not EFFECT_CHANNELS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, action_id, key])

	return out


## The fourth effect channel, added at V1.3c: an action that imposes or lifts a
## coercive measure. Same shape as effects.agreement above and for the same reason
## -- docs/trade-model.md's argument against a content type of its own applies
## unchanged, and V1.3c ships no data/measures/ either.
##
## The two kinds are one verb with a different price, which is what
## docs/tiers/v1.md section 3 committed to. A "tariff" collects revenue and bites
## moderately; a "sanction" collects nothing and bites hard.
##
## A "lift" carries no terms. It names nothing and sets nothing; it clears the
## directed entry. Terms on a lift would be an author believing they had written
## something read by nobody, so they are a load error rather than ignored -- the
## same rule an agreement "exit" gets.
static func _extract_measure(raw, action_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.measure must be an object" % [filename, action_id])
		return {}

	var op = raw.get("op", "")
	if typeof(op) != TYPE_STRING or not (op == "impose" or op == "lift"):
		errors.append("%s: %s effects.measure.op '%s' must be \"impose\" or \"lift\"" % [
			filename, action_id, str(op)
		])
		return {}

	var out := {"op": op}

	if op == "lift":
		for key in raw.keys():
			if key != "op":
				errors.append("%s: %s effects.measure.%s is set on a \"lift\" -- a lift clears the pair and reads no terms" % [
					filename, action_id, key
				])
		return out

	var kind = raw.get("kind", "")
	if typeof(kind) != TYPE_STRING or not CK.MEASURE_KINDS.has(kind):
		errors.append("%s: %s effects.measure.kind '%s' is not a recognised kind (%s)" % [
			filename, action_id, str(kind), str(CK.MEASURE_KINDS)
		])
		return out
	out["kind"] = kind

	var severity := float(raw.get("severity", 0.0))
	if severity <= 0.0:
		errors.append("%s: %s effects.measure.severity must be > 0 -- a measure that bites nothing is not a measure" % [
			filename, action_id
		])
	elif severity > CK.MAX_MEASURE_SEVERITY:
		errors.append("%s: %s effects.measure.severity = %s exceeds MAX_MEASURE_SEVERITY (%s)" % [
			filename, action_id, str(severity), str(CK.MAX_MEASURE_SEVERITY)
		])
	out["severity"] = severity

	# Severity is the ONLY intensity dial. An authored tariff rate was cut at
	# measurement time -- tools/coercion_probe.gd's first revenue table showed yield
	# exactly linear in it, because the trade bite read severity and the rate merely
	# scaled the answer, so the two were one intensity written twice. Named here
	# because an author reaching for a rate should find out why there isn't one.
	for key in raw.keys():
		if key != "op" and key != "kind" and key != "severity":
			errors.append("%s: %s effects.measure.%s is not a recognised term -- severity is the only intensity, and a tariff rate is the same number written twice" % [
				filename, action_id, key
			])

	return out


## The FIFTH effect channel, added at V1.3g: an action that signs or abandons a
## defensive pact, or opens or closes a deployment under one. Same shape as
## effects.measure above and for the same reason -- V1.3g ships no data/pacts/
## either, and that is the sixth session running.
##
## FOUR ops on one channel rather than a fifth channel for the deployment verbs. A
## chosen deployment needs a verb, and giving it a channel of its own would be a
## parallel vocabulary for a mechanism that already exists -- the objection
## src/core/diplomatic_action.gd's own header raises against borrowing `position`
## from the law template.
##
## No op carries terms at all, which is why this is the shortest of the three: a
## pact has no severity and no multiplier, and a deployment's cost is DERIVED from
## the actor's capability rather than authored. Terms here would be an author
## believing they had written something read by nobody -- the same rule a measure's
## "lift" and an agreement's "exit" already get, applied to every op.
static func _extract_pact(raw, action_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.pact must be an object" % [filename, action_id])
		return {}

	var op = raw.get("op", "")
	if typeof(op) != TYPE_STRING or not DFK.PACT_OPS.has(op):
		errors.append("%s: %s effects.pact.op '%s' is not a recognised op (%s)" % [
			filename, action_id, str(op), str(DFK.PACT_OPS)
		])
		return {}

	for key in raw.keys():
		if key != "op":
			errors.append("%s: %s effects.pact.%s is set, but no pact op reads terms -- a deployment's cost is derived from capability, not authored" % [
				filename, action_id, key
			])

	return {"op": op}


## The third effect channel, added at V1.3b: an action that enters or leaves a
## bilateral trade agreement. The terms live here rather than in a content type of
## their own -- see docs/trade-model.md for why V1.3b ships no data/trade-agreements/.
##
## An `exit` carries no terms. It names nothing and sets nothing; it clears the
## pair. Terms on an exit would be an author believing they had written something
## that is read by nobody, so they are a load error rather than ignored.
static func _extract_agreement(raw, action_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.agreement must be an object" % [filename, action_id])
		return {}

	var op = raw.get("op", "")
	if typeof(op) != TYPE_STRING or not (op == "enter" or op == "exit"):
		errors.append("%s: %s effects.agreement.op '%s' must be \"enter\" or \"exit\"" % [
			filename, action_id, str(op)
		])
		return {}

	var out := {"op": op}

	if op == "exit":
		for key in raw.keys():
			if key != "op":
				errors.append("%s: %s effects.agreement.%s is set on an \"exit\" -- an exit clears the pair and reads no terms" % [
					filename, action_id, key
				])
		return out

	var multiplier := float(raw.get("weight_multiplier", 1.0))
	if multiplier <= 0.0:
		errors.append("%s: %s effects.agreement.weight_multiplier must be > 0" % [filename, action_id])
	elif multiplier > TK.MAX_AGREEMENT_WEIGHT_MULTIPLIER:
		errors.append("%s: %s effects.agreement.weight_multiplier = %s exceeds MAX_AGREEMENT_WEIGHT_MULTIPLIER (%s)" % [
			filename, action_id, str(multiplier), str(TK.MAX_AGREEMENT_WEIGHT_MULTIPLIER)
		])
	out["weight_multiplier"] = multiplier

	out["sector_shift"] = _extract_sector_shift(raw.get("sector_shift", {}), action_id, filename, errors)
	return out


## The agreement's winners and losers at home, in points of trend per sector.
##
## THE THREE MUST SUM TO ZERO. Not because a surplus would be ignored -- because
## it would be silently converted into a DIFFERENT composition change than the one
## the author wrote. Economy._apply_growth_to_sectors() reconciles sectors against
## the month's GDP target by redistributing the residual by
## SECTOR_CYCLE_BETA (0.4 / 1.8 / 0.8), so a shift summing to +0.3 is clawed back
## disproportionately from industry, and nothing tells the author. The same class
## of quiet lie a zero effects.relations is refused for above.
static func _extract_sector_shift(raw, action_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.agreement.sector_shift must be an object" % [filename, action_id])
		return {}
	if raw.is_empty():
		return {}

	var out := {}
	var total := 0.0
	for key in raw.keys():
		if not EK.SECTOR_TREND.has(key):
			errors.append("%s: %s effects.agreement.sector_shift.%s is not a recognised sector" % [
				filename, action_id, key
			])
			continue
		if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
			errors.append("%s: %s effects.agreement.sector_shift.%s must be numeric" % [
				filename, action_id, key
			])
			continue
		var value := float(raw[key])
		if absf(value) > TK.MAX_AGREEMENT_SECTOR_SHIFT:
			errors.append("%s: %s effects.agreement.sector_shift.%s = %s exceeds MAX_AGREEMENT_SECTOR_SHIFT (%s)" % [
				filename, action_id, key, str(value), str(TK.MAX_AGREEMENT_SECTOR_SHIFT)
			])
		out[key] = value
		total += value

	if not is_zero_approx(total):
		errors.append("%s: %s effects.agreement.sector_shift sums to %s, not zero -- the cyclical residual would redistribute the difference by SECTOR_CYCLE_BETA and produce a different composition change than the one authored" % [
			filename, action_id, str(total)
		])

	return out


static func _extract_bloc_offset(raw, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.bloc_offset must be an object" % [filename, action_id])
		return {}
	if raw.is_empty():
		errors.append("%s: %s effects.bloc_offset is present but empty" % [filename, action_id])

	var out := {}
	for key in raw.keys():
		if not bloc_keys.has(key):
			errors.append("%s: %s effects.bloc_offset.%s is not a recognised bloc" % [filename, action_id, key])
			continue
		if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
			errors.append("%s: %s effects.bloc_offset.%s must be numeric" % [filename, action_id, key])
			continue
		var value := float(raw[key])
		if absf(value) > DK.MAX_ACTION_BLOC_OFFSET:
			errors.append("%s: %s effects.bloc_offset.%s = %s exceeds MAX_ACTION_BLOC_OFFSET (%s)" % [
				filename, action_id, key, str(value), str(DK.MAX_ACTION_BLOC_OFFSET)
			])
		out[key] = value
	return out
