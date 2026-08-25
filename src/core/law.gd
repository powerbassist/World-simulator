class_name Law
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/laws/*.json file. See docs/data-architecture.md and
## docs/legislature-model.md.
##
## Mirrors src/core/party.gd's from_dict shape: a plain data object built once
## at load time, validated loudly, never mutated afterward.

const LK = preload("res://src/sim/legislature_constants.gd")
const Nation = preload("res://src/core/nation.gd")
## V1.4b. Borrowed rather than re-declared, exactly as src/core/company_action.gd
## borrows it: the bound on how hard one authored rule may lean on a sector is a
## property of the companies model, and a second number for it here would be one
## strength written twice.
const CK = preload("res://src/sim/companies_constants.gd")
const SK = preload("res://src/sim/society_constants.gd")
const DK = preload("res://src/sim/demography_constants.gd")
const UK = preload("res://src/sim/unrest_constants.gd")
const MK = preload("res://src/sim/media_constants.gd")

## `business` is V1.4b's, and it is named for a DOMAIN like the other four rather
## than for a mechanism. A theme called "regulation" is where V1.6's sectoral
## investment would wrongly land -- that is a lever pointed at a sector too, and
## the thing that separates them is the register, not the word.
const THEME_KEYS := ["tax", "labour", "social", "institutional", "business"]

## Effect keys that are a single float delta into one of the non-budget
## channels legislature.gd accumulates onto NationState.
const SCALAR_EFFECT_KEYS := [
	"structural_unemployment_pct", "potential_growth_pct", "other_revenue_pct_gdp",
]

## effects.institutional keys a constitutional amendment may set, each an
## ABSOLUTE value written straight onto NationState -- an institution is set,
## not nudged, unlike every other effect channel above. Whether a given VALUE
## is allowed for a given nation is a template question, checked once at
## load by DataLoader against every system named in this law's own `systems`
## list -- see docs/amendment-model.md. This dict only checks that the value
## is a recognised member of the right enum at all.
const INSTITUTIONAL_EFFECT_KEYS := {
	"censure_rule": Nation.KNOWN_CENSURE_RULES,
	"dissolution_rule": Nation.KNOWN_DISSOLUTION_RULES,
	"formation_method": Nation.KNOWN_FORMATION_METHODS,
	"amendment_rule": Nation.KNOWN_AMENDMENT_RULES,
}
## Integer institutional effect keys, checked by range rather than by enum.
const INSTITUTIONAL_INT_KEYS := {
	"term_limit": [Nation.MIN_TERM_LIMIT, Nation.MAX_TERM_LIMIT],
	"term_months": [12, 120],
}

## ============================================================================
## THE CHANNEL HAS TWO BARS, AND THAT IS V1.7c'S CORRECTION TO ITS OWN ROW
## ============================================================================
## Everything above requires `constitutional: true`, which forces
## `majority: "amendment"`, which routes the vote to the nation's own
## amendment_rule. docs/tiers/v1.md section 7 asked for electoral-system choice as
## "a seventh effects.institutional key" -- right about the CHANNEL and wrong about
## the BAR, because that phrasing entrenches the electoral system at each nation's
## amendment threshold and electoral law is ORDINARY LEGISLATION in essentially all
## ten: France's code electoral (changed by ordinary law in 1985 and again in 1986),
## Germany's Bundeswahlgesetz (2023), Italy's Rosatellum, Britain's ordinary Act.
## It happens to be right for GBR, and only because GBR's amendment_rule already IS
## `ordinary_law`. Wrong for two of the three playable nations. Instance forty-three.
##
## So the keys below may be written by ANY law and the six above may not. That is
## V1.4a/V1.4b's split written into the schema rather than only into the docs -- a
## subsidy reaches effects.company directly and a regulation reaches it through an
## assembly division -- one block later and in the other direction.
##
## No template constrains either key and none could: constitutional_monarchy alone
## covers `fptp`, `pr_dhondt` and `pr_national` across GBR, ESP, BEL, NLD and LUX,
## so an `allowed_election_systems` field would be a constraint with nothing to say.
## `term_months` is the precedent -- bounded by its own range check and by no
## template. See docs/electoral-systems.md and docs/referendum-model.md.
const ORDINARY_INSTITUTIONAL_KEYS := {
	"election_system": Nation.KNOWN_ELECTION_SYSTEMS,
}
const ORDINARY_INSTITUTIONAL_FLOAT_KEYS := {
	"election_threshold_pct": [0.0, 20.0],
}

## Keys a system-transition amendment must ALSO write if it writes
## effects.institutional.system_id -- a bare system_id write would leave every
## OTHER field at its pre-transition value, which is exactly the
## half-understood institutional state docs/political-systems.md refuses.
## head_of_state is a nested object, checked separately by
## _extract_head_of_state(). See docs/transition-model.md.
const SYSTEM_CHANGE_REQUIRED_KEYS := [
	"formation_method", "censure_rule", "dissolution_rule", "amendment_rule", "term_limit",
]

var id: String = ""
var law_name: String = ""
var theme: String = ""
var summary: String = ""

## Position on the same two-axis ideology space election_constants.gd's
## SLOT_POSITION uses -- economic (-1 left ... +1 right), social (-1 open ...
## +1 traditional). No parallel vocabulary; see docs/legislature-model.md.
var position: Dictionary = {}

var majority: String = ""

## Months a law must wait after failing before it can be proposed again.
## Passed laws with `once = true` can never be proposed again at all.
var cooldown_months: int = 0
var once: bool = true

## Array of {"field": String, "op": String, "value": float}, each field checked
## against legislature_constants.PRECONDITION_FIELDS at load time.
var preconditions: Array = []

## {"tax_rates_pct": {...}, "spending_pct_gdp": {...},
##  "structural_unemployment_pct": float, "potential_growth_pct": float,
##  "other_revenue_pct_gdp": float, "bloc_offset": {...},
##  "institutional": {...}, "company": {...}} -- any subset.
##
## `company` is V1.4b's, and it is the SAME CHANNEL NAME company_action.gd uses
## with a deliberately different shape: an action names an op against the one firm
## it is pointed at, a law names a SECTOR and a burden. That is the a/b split
## written into the schema rather than only into the docs -- a subsidy is an
## executive act aimed at a firm, a regulation is a law aimed at a sector.
var effects: Dictionary = {}

## A constitutional amendment: resolve_vote() reads the proposing nation's own
## ns.amendment_rule instead of `majority` above. See docs/amendment-model.md.
var constitutional: bool = false

## Which political-system templates this law may be proposed under -- filters
## Legislature.available(). Required and non-empty when constitutional is
## true; ignored (and must be absent) otherwise, the same
## present-only-if-needed shape Nation's executive block uses.
var systems: Array[String] = []

## True when effects.institutional writes system_id -- a system transition,
## not an ordinary amendment. Derived once at load, the same precedent
## `constitutional` sets, so Legislature.available() does not dig into a
## nested dict every call. Gated separately from `constitutional` by
## ns.permits_system_change -- see docs/transition-model.md.
var changes_system: bool = false


## `sector_keys` is PASSED rather than preloaded, the way tax_keys, spending_keys
## and bloc_keys already are: which sectors exist is the economy model's list, and
## a validator reaching sideways for it is the dependency data_loader.gd exists to
## carry. The bound on a burden's size is a different question and comes from CK.
static func from_dict(d: Dictionary, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array, sector_keys: Array):
	var law := new()

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: missing or invalid string field 'id'" % filename)
	else:
		law.id = d["id"]

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, law.id])
	else:
		law.law_name = d["name"]

	if not d.has("theme") or typeof(d["theme"]) != TYPE_STRING or not THEME_KEYS.has(d["theme"]):
		errors.append("%s: %s theme must be one of %s" % [filename, law.id, THEME_KEYS])
	else:
		law.theme = d["theme"]

	law.summary = d.get("summary", "")
	if typeof(law.summary) != TYPE_STRING:
		errors.append("%s: %s summary must be a string" % [filename, law.id])
		law.summary = ""

	law.position = _extract_position(d, law.id, filename, errors)

	if not d.has("majority") or not LK.MAJORITY_KEYS.has(d.get("majority")):
		errors.append("%s: %s majority must be one of %s" % [filename, law.id, LK.MAJORITY_KEYS])
	else:
		law.majority = d["majority"]

	law.cooldown_months = int(d.get("cooldown_months", 0))
	if law.cooldown_months < 0:
		errors.append("%s: %s cooldown_months must be >= 0" % [filename, law.id])

	law.once = bool(d.get("once", false))

	law.constitutional = bool(d.get("constitutional", false))
	if law.constitutional and law.majority != "amendment":
		errors.append("%s: %s constitutional laws must set majority: 'amendment'" % [filename, law.id])
	if not law.constitutional and law.majority == "amendment":
		errors.append("%s: %s majority 'amendment' requires constitutional: true" % [filename, law.id])

	if law.constitutional:
		law.systems = _extract_string_array(d, "systems", law.id, filename, errors)
		if law.systems.is_empty():
			errors.append("%s: %s constitutional laws must name at least one system in 'systems'" % [filename, law.id])
	elif d.has("systems"):
		errors.append("%s: %s 'systems' is only valid on a constitutional law" % [filename, law.id])

	law.preconditions = extract_preconditions(d, law.id, filename, errors)
	law.effects = _extract_effects(d, law.id, filename, errors, tax_keys, spending_keys, bloc_keys, sector_keys, law.constitutional)
	law.changes_system = law.effects.get("institutional", {}).has("system_id")

	return law


static func _extract_string_array(d: Dictionary, key: String, law_id: String, filename: String, errors: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var raw = d.get(key, [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s: %s %s must be an array" % [filename, law_id, key])
		return out
	for entry in raw:
		if typeof(entry) != TYPE_STRING:
			errors.append("%s: %s %s contains a non-string entry" % [filename, law_id, key])
			continue
		out.append(entry)
	return out


static func _extract_position(d: Dictionary, law_id: String, filename: String, errors: Array[String]) -> Dictionary:
	var pos: Dictionary = d.get("position", {})
	if typeof(pos) != TYPE_DICTIONARY or not pos.has("economic") or not pos.has("social"):
		errors.append("%s: %s missing or invalid object field 'position' {economic, social}" % [filename, law_id])
		return {"economic": 0.0, "social": 0.0}

	var econ := float(pos.get("economic", 0.0))
	var social := float(pos.get("social", 0.0))
	if econ < -1.0 or econ > 1.0:
		errors.append("%s: %s position.economic = %s out of range [-1, 1]" % [filename, law_id, str(econ)])
	if social < -1.0 or social > 1.0:
		errors.append("%s: %s position.social = %s out of range [-1, 1]" % [filename, law_id, str(social)])
	return {"economic": econ, "social": social}


## Public since V1.8, and it takes a REFUSAL LIST rather than a second whitelist.
##
## src/sim/events_constants.gd needs the same triple with one field removed, and the
## alternative -- a parallel EVENT_PRECONDITION_FIELDS array -- is the failure
## src/sim/legislature.gd already records about itself: its whitelist and its
## read_field() match are the same list in two places and V1.5c added half of it. A
## third copy would be that failure again with the same excuse, so this is a
## SUBTRACTION from the one list, which is also the shape ORDINARY_INSTITUTIONAL_KEYS
## took at V1.7c.
static func extract_preconditions(d: Dictionary, law_id: String, filename: String, errors: Array[String], refused: Array = []) -> Array:
	var raw = d.get("preconditions", [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s: %s preconditions must be an array" % [filename, law_id])
		return []

	var out: Array = []
	for i in raw.size():
		var entry = raw[i]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s: %s preconditions[%d] is not an object" % [filename, law_id, i])
			continue

		var field = entry.get("field", "")
		if typeof(field) != TYPE_STRING or not LK.PRECONDITION_FIELDS.has(field):
			errors.append("%s: %s preconditions[%d].field '%s' is not a recognised field" % [filename, law_id, i, str(field)])
			continue
		if refused.has(field):
			errors.append("%s: %s preconditions[%d].field '%s' is refused on this channel -- see src/sim/events_constants.gd EVENT_PRECONDITION_REFUSED" % [filename, law_id, i, str(field)])
			continue

		var op = entry.get("op", "")
		if typeof(op) != TYPE_STRING or not LK.PRECONDITION_OPS.has(op):
			errors.append("%s: %s preconditions[%d].op '%s' is not a recognised operator" % [filename, law_id, i, str(op)])
			continue

		if not entry.has("value") or not (typeof(entry["value"]) == TYPE_INT or typeof(entry["value"]) == TYPE_FLOAT):
			errors.append("%s: %s preconditions[%d].value is missing or not numeric" % [filename, law_id, i])
			continue

		out.append({"field": field, "op": op, "value": float(entry["value"])})

	return out


static func _extract_effects(d: Dictionary, law_id: String, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array, sector_keys: Array, allow_institutional: bool) -> Dictionary:
	var raw: Dictionary = d.get("effects", {})
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects must be an object" % [filename, law_id])
		return {}

	var out := extract_shared_effects(
		raw, law_id, filename, errors, tax_keys, spending_keys, bloc_keys, sector_keys
	)

	if raw.has("institutional"):
		# `allow_institutional` is the law's own `constitutional` flag, and since
		# V1.7c it selects WHICH keys are legal rather than whether the channel is.
		# See ORDINARY_INSTITUTIONAL_KEYS.
		out["institutional"] = _extract_institutional(
			raw["institutional"], law_id, filename, errors, allow_institutional
		)

	for key in raw.keys():
		if not SHARED_EFFECT_CHANNELS.has(key) and key != "institutional" and not SCALAR_EFFECT_KEYS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, law_id, key])

	return out


## THE CHANNELS A LAW AND AN EVENT CHOICE SHARE, extracted at V1.8 so the two cannot
## drift apart. Everything here is reachable by BOTH; `institutional` is reachable by
## neither an event choice nor an ordinary Act and stays in the caller.
##
## The extraction is what makes docs/tiers/v1.md section 8's own argument collectable.
## That section is last because "the event schema's shape is the union of the effect
## channels sections 3-7 create, and written before them it gets written twice" -- and
## the honest form of that claim is this function: `society` grew from one term to four
## across V1.5a-d, `company` and the sector burden arrived at V1.4b, and a schema
## written at V1.5d would have carried a quarter of what this carries. What section 8
## got WRONG is that the union includes pair state and commitments in flight -- relations,
## agreements, measures, pacts, investment, projects, campaigns, pledges -- each of
## which has exactly one writer with an ACTOR or a BILL behind it, and an event is
## neither. Those are not here and cannot be. See docs/events-model.md section 3.
const SHARED_EFFECT_CHANNELS := [
	"tax_rates_pct", "spending_pct_gdp", "bloc_offset", "company", "society",
]


static func extract_shared_effects(raw: Dictionary, owner_id: String, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array, sector_keys: Array) -> Dictionary:
	var law_id := owner_id
	var out := {}

	if raw.has("tax_rates_pct"):
		out["tax_rates_pct"] = _extract_keyed_deltas(raw["tax_rates_pct"], tax_keys, "effects.tax_rates_pct", law_id, filename, errors)

	if raw.has("spending_pct_gdp"):
		out["spending_pct_gdp"] = _extract_keyed_deltas(raw["spending_pct_gdp"], spending_keys, "effects.spending_pct_gdp", law_id, filename, errors)

	for key in SCALAR_EFFECT_KEYS:
		if raw.has(key):
			if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
				errors.append("%s: %s effects.%s must be numeric" % [filename, law_id, key])
			else:
				out[key] = float(raw[key])

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_keyed_deltas(raw["bloc_offset"], bloc_keys, "effects.bloc_offset", law_id, filename, errors)

	if raw.has("company"):
		out["company"] = _extract_company(raw["company"], law_id, filename, errors, sector_keys)

	if raw.has("society"):
		out["society"] = _extract_society(raw["society"], law_id, filename, errors)

	# THE ANTI-DOUBLE-COUNT, MADE MECHANICAL. A regulation's burden reaches
	# structural unemployment through Companies.headcount(), which is the same act
	# (a law passing), the same landing site (Economy._update_unemployment()) and
	# the same units as `structural_unemployment_pct`. A law carrying both would be
	# two answers to one question with no way for a reader to tell which one the
	# number came from.
	#
	# docs/legislature-model.md's existing lever-vs-bloc_offset rule says the same
	# thing about a different pair and says it in PROSE -- "the sixteen templates
	# each pick one story and tell it once". This one is a load error instead,
	# because a convention that only the docs enforce is one an author breaks by
	# not reading them. Same shape as the directed key that refuses a symmetric one.
	if raw.has("company") and raw.has("structural_unemployment_pct"):
		errors.append("%s: %s carries both effects.company and effects.structural_unemployment_pct -- a sector burden already reaches structural unemployment through the firm register, so the two are one story told twice. Pick one." % [filename, law_id])

	# THE SAME ANTI-DOUBLE-COUNT, at the second place it can happen. Corruption
	# reaches the `health` opinion issue through Society.quality_target(), which is
	# the same act, the same landing site and the same units as a law moving
	# `spending_pct_gdp.health` directly. A law carrying both would be two answers to
	# one question -- and the more insidious half is that they can be given OPPOSITE
	# signs, so a law could buy approval on a service while quietly degrading it and
	# the ledger would net them to nothing.
	#
	# V1.5c NARROWED THIS FROM THE CHANNEL TO THE PAIR, and the narrowing is argued
	# rather than slipped in because it turns an existing refusal green. The reason
	# written above is about CORRUPTION reaching the spending issues through the quality
	# stock -- it was never true of the channel, only of that one term, and V1.5a scoped
	# it to the channel because `corruption` was the only term there was. A settlement
	# law is naturally a spending law (public-sector pay, a pension restoration), and
	# under the wide scope every one of those was a load error. That is exactly what
	# V1.5b did to its own refusal below for data/laws/labour.json's sake, one session
	# earlier, and for the same reason: a blanket rule that catches working content to
	# stop one bad case is the wrong shape.
	if raw.has("society") and raw.has("spending_pct_gdp") and typeof(raw["society"]) == TYPE_DICTIONARY and raw["society"].has("corruption"):
		errors.append("%s: %s carries both effects.society.corruption and effects.spending_pct_gdp -- corruption already reaches the spending issues through the quality stock, so the two are one story told twice. Pick one." % [filename, law_id])

	# THE SAME ANTI-DOUBLE-COUNT, at the third place it can happen, and V1.5b's own.
	# A migration stance reaches structural unemployment through the labour force:
	# Demography.labour_force() is firm_jobs_offset_pct()'s denominator and
	# Economy._update_unemployment() reads that beside `law_structural_offset_pct`.
	# Same act, same landing site, same units -- and data/laws/social.json's
	# `immigration_tightening` was the law that had it BOTH ways until this session
	# re-authored it, pricing a migration flow as a structural unemployment offset
	# because there was no flow to price it on.
	#
	# Scoped to the PAIR and not to the channel, deliberately: data/laws/labour.json's
	# four laws keep `structural_unemployment_pct` and are right to, because a labour
	# reform genuinely is a claim about the matching rate rather than about who is in
	# the country. A blanket refusal of the scalar would have cost four working laws
	# to catch one.
	if raw.has("society") and raw.has("structural_unemployment_pct") and typeof(raw["society"]) == TYPE_DICTIONARY and raw["society"].has("migration"):
		errors.append("%s: %s carries both effects.society.migration and effects.structural_unemployment_pct -- a migration stance already reaches structural unemployment through the labour force, so the two are one story told twice. Pick one." % [filename, law_id])

	# THERE IS NO FOURTH, AND REFUSING TO ADD ONE IS V1.5c's CONTRIBUTION TO THIS RULE.
	# `society.settlement` + `structural_unemployment_pct` was written, and then deleted
	# once it was checked against the criterion the three above actually use rather than
	# against the pattern they make. The first refusal states it in full: "the same act,
	# the same landing site AND THE SAME UNITS". A settlement is in units of stance and
	# lands on the unrest target directly; structural unemployment is in points and
	# lands on Economy._update_unemployment(), reaching unrest only afterwards through
	# the `jobs` satisfaction. Two of the three criteria fail.
	#
	# The difference is one MECHANISM priced twice against two mechanisms landing on one
	# number, and the three refusals above are all the first kind: a regulation's burden
	# IS headcount, corruption's degradation IS the spending issue, and
	# `immigration_tightening`'s structural offset was literally a stand-in for the
	# migration flow because there was no flow to price it on. But "a minimum wage rise
	# makes hiring harder" and "a minimum wage rise buys industrial peace" are two true
	# sentences about two mechanisms, and a rule that forbade them would forbid
	# `bloc_offset` beside anything.
	#
	# Recorded here rather than in the model doc because the next session to add a term
	# on this channel will reach for a fourth refusal by symmetry, and symmetry is not
	# the test.
	#
	# V1.5d IS THAT SESSION, IT REACHED FOR ONE, AND THE PARAGRAPH ABOVE STOPPED IT.
	# `press_freedom` was checked against all four things it could plausibly collide with,
	# and every one fails the criterion:
	#
	#   + structural_unemployment_pct  units differ (stance vs points) and sites differ
	#                                  (the unrest target vs _update_unemployment()).
	#                                  V1.5c's deleted refusal, identically.
	#   + bloc_offset                  the site coincides -- both reach a bloc's approval
	#                                  target -- but a stance scaling a SALIENCE
	#                                  amplification and a flat additive on the target are
	#                                  not the same units, and refusing this would forbid
	#                                  bloc_offset beside anything, which is the sentence
	#                                  above. data/laws/institutional.json's own press
	#                                  laws carry one, so the rule would fail the content
	#                                  it was written for.
	#   + society.settlement           both are terms of unrest_target(), so the site
	#                                  coincides -- and they are two mechanisms landing on
	#                                  one number, not one priced twice. "Censorship breeds
	#                                  grievance" and "a pay settlement buys industrial
	#                                  peace" are two true sentences.
	#   + society.corruption           different sites (the quality stock vs the salience
	#                                  gain) and different units. A transparency act naming
	#                                  both is a legitimate law.
	#
	# The refusal that IS warranted has no shape a law schema can express, because it is
	# not two keys on one law: press_freedom must not reach the grievance target through
	# BOTH media_constants.PRESS_UNREST_BETA and Unrest.hardship(), which would be the
	# same act, the same landing site and the same units -- the first kind. It is one
	# register reaching one number twice through CODE, so it is refused in a signature
	# instead: Opinion.salience_weights() takes its gain as a REQUIRED argument and
	# unrest.gd states the unframed one out loud. See both.

	return out


## V1.5a. The SIXTH effect channel, and V1.5 owns it the way V1.4 owns
## `effects.company` -- (c)'s unrest and (d)'s press freedom reach it through here,
## so this is schema two later sessions read rather than one session's private field.
##
## A law names terms from a CLOSED LIST -- `corruption` at V1.5a, `migration` at
## V1.5b -- and at least one of them. Anything else is refused, for
## `_extract_company()`'s reason stated about a different register: `service_quality`
## has exactly one writer and it is Society.tick_month(), and the age shares have one
## and it is Demography.tick_month(). A law that could set a quality level or an age
## share directly would be a second writer of it -- two answers to the question of how
## good the hospitals are, or how old the country is -- and it would bypass the stock
## and the drift, which are the things that make the consequence lag the decision.
##
## V1.5b WIDENED THE LIST BY EXACTLY ONE KEY AND NOTHING ELSE, which is what V1.5a
## meant by declaring this "schema two later sessions read rather than one session's
## private field". The channel needed no new shape to carry a second register.
##
## Both values are SIGNED. Anti-corruption is the negative direction on one
## accumulator and a migration tightening the negative direction on the other, not
## repeal verbs: V1.4b's argument for deregulation transferred whole, plus one V1.4b
## did not need -- a one-directional level would make an anti-corruption law INERT on
## a clean state, and V1.3f's own property is that nothing on the law list does
## nothing. For migration the sign carries a second load: ageing is a charge no verb
## in this game can otherwise close, so an opening direction is what makes the
## dependency ratio admissible at all rather than a permanent monotone ratchet.
##
## V1.5c WIDENED IT BY ONE KEY AGAIN, which is the second piece of evidence for V1.5a's
## claim and a better one than the first: a channel that carries a second register might
## be lucky, and one that carries a third is schema. `settlement` is what makes unrest
## CLOSABLE -- without it the only lever pointed at a strike is a spending increase, and
## society_probe.gd table (c) established that raising a line necessarily widens the
## deficit, so the player could buy industrial peace only by opening `public_finances`.
## V1.5d adds `press_freedom` and takes the claim one step further again: a channel that
## carries a second register might be lucky, a third is schema, and a FOURTH written by
## a fourth session is the thing V1.5a bet on when it opened the channel with one term.
## Nothing below this line changed to accept it -- _extract_society() is generic over
## this dictionary, so all four of its error strings updated themselves.
const SOCIETY_TERMS := {
	"corruption": SK.CORRUPTION_MAX,
	"migration": DK.MIGRATION_STANCE_MAX,
	"settlement": UK.SETTLEMENT_STANCE_MAX,
	"press_freedom": MK.PRESS_FREEDOM_MAX,
}


static func _extract_society(raw, law_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.society must be an object" % [filename, law_id])
		return {}

	var out := {}
	for term in SOCIETY_TERMS:
		if not raw.has(term):
			continue
		if not (typeof(raw[term]) == TYPE_INT or typeof(raw[term]) == TYPE_FLOAT):
			errors.append("%s: %s effects.society.%s is not numeric" % [filename, law_id, term])
			continue
		var value := float(raw[term])
		var limit: float = float(SOCIETY_TERMS[term])
		if value == 0.0:
			errors.append("%s: %s effects.society.%s is 0.0 -- a reform that changes nothing is not a reform" % [filename, law_id, term])
		elif absf(value) > limit:
			errors.append("%s: %s effects.society.%s = %s exceeds its maximum (%s)" % [
				filename, law_id, term, str(value), str(limit)
			])
		out[term] = value

	if out.is_empty():
		errors.append("%s: %s effects.society names none of %s" % [
			filename, law_id, SOCIETY_TERMS.keys()
		])
		return {}

	for key in raw.keys():
		if not SOCIETY_TERMS.has(key):
			errors.append("%s: %s effects.society.%s is not a recognised term -- a law names %s and nothing else, and a quality figure or an age share beside them would make a law the second writer of a register that has one" % [
				filename, law_id, key, SOCIETY_TERMS.keys()
			])

	return out


## V1.4b. A regulation names a SECTOR and a burden on it, and that is the whole
## schema -- `sector` and `burden`, refused if anything else appears.
##
## MUST NOT NAME A FIRM, and the refusal below is where that is enforced rather
## than merely intended. Share movement is the subsidy's persistent channel, and a
## law that could point at one firm would be a second writer of it -- two answers
## to the question of who is winning the sector. A regulation is sector-wide by
## construction, and the register is what it reads rather than what it moves.
##
## The burden is SIGNED. Deregulation is the negative direction on the same
## accumulator, not a repeal verb: there is no repeal in this project and a `once`
## law never returns, so a burden that could only ever rise would be a permanent
## monotone charge -- the failure docs/defence-model.md names, where a clamp stops
## being a guard rail and becomes the number. A signed burden also costs no new
## precondition field, and legislature_constants.PRECONDITION_FIELDS has no sector
## parameter and should not grow one.
static func _extract_company(raw, law_id: String, filename: String, errors: Array[String], sector_keys: Array) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.company must be an object" % [filename, law_id])
		return {}

	var sector = raw.get("sector", "")
	if typeof(sector) != TYPE_STRING or not sector_keys.has(sector):
		errors.append("%s: %s effects.company.sector '%s' is not a recognised sector (%s)" % [
			filename, law_id, str(sector), str(sector_keys)
		])
		return {}

	if not raw.has("burden") or not (typeof(raw["burden"]) == TYPE_INT or typeof(raw["burden"]) == TYPE_FLOAT):
		errors.append("%s: %s effects.company.burden is missing or not numeric" % [filename, law_id])
		return {}

	var burden := float(raw["burden"])
	if burden == 0.0:
		errors.append("%s: %s effects.company.burden is 0.0 -- a rule that binds nobody is not a rule" % [filename, law_id])
	elif absf(burden) > CK.REGULATION_BURDEN_MAX:
		errors.append("%s: %s effects.company.burden = %s exceeds REGULATION_BURDEN_MAX (%s)" % [
			filename, law_id, str(burden), str(CK.REGULATION_BURDEN_MAX)
		])

	for key in raw.keys():
		if key != "sector" and key != "burden":
			errors.append("%s: %s effects.company.%s is not a recognised term -- a regulation names a sector and a burden, and a firm id or a share rate beside them would make a law the second writer of the subsidy's channel" % [
				filename, law_id, key
			])

	return {"sector": sector, "burden": burden}


## Absolute values written straight onto NationState -- see
## INSTITUTIONAL_EFFECT_KEYS' header comment. Only checks that the value is a
## recognised member of the right enum at all; whether it is the RIGHT value
## for a given nation's declared system is DataLoader's cross-check against
## this law's own `systems` list.
static func _extract_institutional(raw, law_id: String, filename: String, errors: Array[String], entrenched: bool) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.institutional must be an object" % [filename, law_id])
		return {}
	if raw.is_empty():
		errors.append("%s: %s effects.institutional must not be empty" % [filename, law_id])

	var out := {}
	for key in raw.keys():
		if ORDINARY_INSTITUTIONAL_KEYS.has(key):
			var permitted: Array = ORDINARY_INSTITUTIONAL_KEYS[key]
			if typeof(raw[key]) != TYPE_STRING or not permitted.has(raw[key]):
				errors.append("%s: %s effects.institutional.%s must be one of %s" % [filename, law_id, key, permitted])
			else:
				out[key] = raw[key]
		elif ORDINARY_INSTITUTIONAL_FLOAT_KEYS.has(key):
			var bounds: Array = ORDINARY_INSTITUTIONAL_FLOAT_KEYS[key]
			if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
				errors.append("%s: %s effects.institutional.%s must be numeric" % [filename, law_id, key])
			else:
				var f := float(raw[key])
				if f < float(bounds[0]) or f > float(bounds[1]):
					errors.append("%s: %s effects.institutional.%s = %s out of range [%s, %s]" % [filename, law_id, key, f, bounds[0], bounds[1]])
				out[key] = f
		elif not entrenched:
			# Every key below this line changes an entrenched institution, and an
			# ordinary Act may not touch one. Named rather than lumped in with an
			# unrecognised field, so the error says which rule was broken.
			errors.append("%s: %s effects.institutional.%s requires constitutional: true" % [filename, law_id, key])
		elif key == "system_id":
			# A system-transition target. Whether it names a real template, and
			# whether the rest of `out` is legal under that template, is
			# DataLoader's target-side cross-check -- this only checks the
			# value is a non-empty string. See docs/transition-model.md.
			if typeof(raw[key]) != TYPE_STRING or raw[key] == "":
				errors.append("%s: %s effects.institutional.system_id must be a non-empty string" % [filename, law_id])
			else:
				out[key] = raw[key]
		elif key == "head_of_state":
			out[key] = _extract_head_of_state(raw[key], law_id, filename, errors)
		elif INSTITUTIONAL_EFFECT_KEYS.has(key):
			var allowed: Array = INSTITUTIONAL_EFFECT_KEYS[key]
			if typeof(raw[key]) != TYPE_STRING or not allowed.has(raw[key]):
				errors.append("%s: %s effects.institutional.%s must be one of %s" % [filename, law_id, key, allowed])
			else:
				out[key] = raw[key]
		elif INSTITUTIONAL_INT_KEYS.has(key):
			var range: Array = INSTITUTIONAL_INT_KEYS[key]
			if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
				errors.append("%s: %s effects.institutional.%s must be numeric" % [filename, law_id, key])
			else:
				var value := int(raw[key])
				if value < int(range[0]) or value > int(range[1]):
					errors.append("%s: %s effects.institutional.%s = %d out of range [%d, %d]" % [filename, law_id, key, value, range[0], range[1]])
				out[key] = value
		else:
			errors.append("%s: %s effects.institutional.%s is not a recognised institutional field" % [filename, law_id, key])

	# Completeness: a system_id write with nothing else is the exact
	# half-understood state the template's own cross-check refuses for a
	# nation file -- see SYSTEM_CHANGE_REQUIRED_KEYS' header comment.
	if out.has("system_id"):
		for key in SYSTEM_CHANGE_REQUIRED_KEYS:
			if not out.has(key):
				errors.append("%s: %s writes system_id but is missing effects.institutional.%s, required for every system transition" % [filename, law_id, key])
		if not out.has("head_of_state"):
			errors.append("%s: %s writes system_id but is missing effects.institutional.head_of_state, required for every system transition" % [filename, law_id])
	elif out.has("head_of_state"):
		errors.append("%s: %s effects.institutional.head_of_state is only valid alongside system_id" % [filename, law_id])

	return out


## The office an amendment installs, not the person -- see
## docs/transition-model.md. `elected_president` derives its holder from the
## largest party's own leader at apply() time, so `name` is forbidden there,
## the mirror of Nation.gd's own head-of-state parsing (which always requires
## a name, because a nation's starting head of state is always authored, never
## derived). `term_years` is required only for `elected_president`, the same
## present-only-if-needed shape Nation.gd's own clock uses.
static func _extract_head_of_state(raw, law_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.institutional.head_of_state must be an object" % [filename, law_id])
		return {}

	var out := {}

	var kind = raw.get("kind", "")
	if typeof(kind) != TYPE_STRING or not Nation.KNOWN_HEAD_OF_STATE_KINDS.has(kind):
		errors.append("%s: %s effects.institutional.head_of_state.kind '%s' is not a recognised kind" % [filename, law_id, str(kind)])
		return {}
	out["kind"] = kind

	var title = raw.get("title", "")
	if typeof(title) != TYPE_STRING or title == "":
		errors.append("%s: %s effects.institutional.head_of_state.title is missing or invalid" % [filename, law_id])
	else:
		out["title"] = title

	# A transition names an OFFICE; the acting nation's own content names who
	# fills it. That is true for every kind now, where before it was true only
	# for elected_president: the Restoration Act used to author "Alexander IV"
	# inline, so every parliamentary republic in Europe restored the SAME king.
	# The nation's `government.pretender_person` answers it per nation instead —
	# and a monarchy points that reference at its own sitting monarch, so a
	# restoration puts the right dynasty back. See docs/transition-model.md.
	if raw.has("name"):
		errors.append("%s: %s effects.institutional.head_of_state.name must not be set for any kind -- the holder is derived at apply() time, from the largest party's leader for 'elected_president' and from the nation's own government.pretender_person otherwise" % [filename, law_id])

	if kind == "elected_president":
		if not raw.has("term_years") or not (typeof(raw["term_years"]) == TYPE_INT or typeof(raw["term_years"]) == TYPE_FLOAT):
			errors.append("%s: %s effects.institutional.head_of_state.term_years is missing or not numeric, required for kind 'elected_president'" % [filename, law_id])
		else:
			var term_years := int(raw["term_years"])
			if term_years < 1 or term_years > 10:
				errors.append("%s: %s effects.institutional.head_of_state.term_years = %d out of range [1, 10]" % [filename, law_id, term_years])
			out["term_years"] = term_years
	elif raw.has("term_years"):
		errors.append("%s: %s effects.institutional.head_of_state.term_years must not be set for kind '%s'" % [filename, law_id, kind])

	return out


static func _extract_keyed_deltas(raw, known_keys: Array, path: String, law_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s %s must be an object" % [filename, law_id, path])
		return {}

	var out := {}
	for key in raw.keys():
		if not known_keys.has(key):
			errors.append("%s: %s %s.%s is not a recognised key" % [filename, law_id, path, key])
			continue
		if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
			errors.append("%s: %s %s.%s must be numeric" % [filename, law_id, path, key])
			continue
		out[key] = float(raw[key])
	return out
