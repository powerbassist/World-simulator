extends RefCounted

## One supranational organisation: the content type for data/orgs/*.json, and
## the static helper the sim prices co-membership through. Generalises what
## data/eu_parliament.json and the nation files' government.eu blocks were --
## V1.3d's one hardcoded object -- into a register a fifth org joins as a data
## edit. Model: docs/orgs-model.md.
##
## The membership question has TWO answers and keeping them apart is the whole
## design. `members` here is the authored START, read only while building a new
## game and validating content. NationState.orgs is the LIVE truth -- what an
## accession or a withdrawal rewrites months into a run. Any helper that read
## this table at tick time would freeze membership against a fight the player
## already won, so src/sim/ never asks it; shared_bonus() below reads the live
## arrays.

const OrgK := preload("res://src/core/org_constants.gd")
const CouncilK := preload("res://src/sim/council_constants.gd")

var id: String = ""
var name: String = ""
var summary: String = ""

## nation_id -> {} or {"ep_seats": int}. Seats are carried only where the org
## has a parliament; the loader refuses a parliament whose members lack them.
var members: Dictionary = {}

## {next_election: {year, month}, term_years: int}, or {} for an org with no
## parliament. The European Parliament's clocks and seats were
## data/eu_parliament.json's whole content.
var parliament: Dictionary = {}

## True when the org holds an agenda and divides on proposals -- the V1.3d
## council machinery, one register per council org on GameState.orgs.
var council: bool = false

## True when the org runs the net-position transfer machinery (the standing
## contribution, the rules' transfers, the fines).
var net_transfers: bool = false

## Resting-relations points co-members gain. eu carries 15.0, the value
## diplomacy_constants.EU_CO_MEMBER_BONUS held before this register existed;
## everything else ships 0.0 until a session prices it.
var relations_bonus: float = 0.0

## Gravity-weight multiplier for co-members. eu carries 0.50, the value
## trade_constants.EU_TRADE_BONUS held before this register existed.
var trade_bonus: float = 0.0

## Negotiation countdowns, in months, after the referendum has passed. Authored
## per org: joining or leaving the EU is a two-year process, the others are
## shorter. 0 would mean "flips immediately", which no authored org carries.
var accession_months: int = 0
var withdrawal_months: int = 0

## The voting weight a NEW member enters with, on the day the accession flips.
## Authored per council org because the seats table is authored (the EP's real
## allocation, NATO's population-shaped weights) and a joiner needs a number
## from the same table's world -- code deriving one would be a second seat
## arithmetic living outside the content that owns seats. 0 on a non-council
## org, where no weight is ever read.
var accession_seats: int = 0

## Where the ACCESSION or WITHDRAWAL question is put on the two-axis ideology
## space. Referendum.bloc_yes() scores YES here against the size-weighted
## status quo, so these two positions are what make a fight hard or easy --
## authored content, measured in play, not tuned here.
var accession_position: Dictionary = {}
var withdrawal_position: Dictionary = {}

## V4.5a. How this council decides when a proposal does not say: `qmr` (V1.3d's
## cast-seat tally) or `unanimity` (the treaty class). Default qmr, which is what
## every pre-V4.5 council did -- the inertness clause in docs/orgs-model.md.
var decision_rule: String = "qmr"

## V4.5a. The rotating chair, or {} for a council the rotation still drives.
## {"order": [member ids], "months": int, "anchor_index": year * 12 + month - 1}
## -- anchor_index is when order[0]'s term BEGAN, so the chair is a pure
## function of the calendar and nothing about it is ever saved.
var presidency: Dictionary = {}

var errors: Array[String] = []


## No self-typed return and no `Org.new()` inside this file: a script cannot
## resolve its own class_name on first run, before the global class cache
## exists -- AGENTS.md's first gotcha, which V2.4b paid for at exactly this
## signature. BlocProposal.from_dict() is the shape to copy.
static func from_dict(raw: Dictionary, fname: String, errors: Array[String]):
	var org := new()

	org.id = String(raw.get("id", ""))
	if org.id.is_empty():
		errors.append("%s: missing 'id'" % fname)
		return org
	org.name = String(raw.get("name", ""))
	if org.name.is_empty():
		errors.append("%s: %s missing 'name'" % [fname, org.id])
	org.summary = String(raw.get("summary", ""))

	var raw_members = raw.get("members", {})
	if typeof(raw_members) != TYPE_DICTIONARY or (raw_members as Dictionary).is_empty():
		errors.append("%s: %s missing or empty 'members'" % [fname, org.id])
		return org

	# Seats are required where a PARLIAMENT exists (the EP allocation) and where
	# a COUNCIL exists -- a council whose members all weigh zero can never pass
	# anything, which is the silent-failure class, so the loader refuses it
	# instead. V3.2: the same key carries the EP's real seats and a council
	# org's authored weights (NATO decides by consensus in reality; the game's
	# council needs numbers, and the register is where content lives).
	var raw_parl = raw.get("parliament", {})
	var has_parliament: bool = typeof(raw_parl) == TYPE_DICTIONARY and not (raw_parl as Dictionary).is_empty()
	var wants_seats: bool = has_parliament or bool(raw.get("council", false))
	for member_id in raw_members.keys():
		var entry = raw_members[member_id]
		if wants_seats:
			var seats_value = entry.get("seats", entry.get("ep_seats", 0)) if typeof(entry) == TYPE_DICTIONARY else 0
			var seats := int(seats_value)
			if seats < 1 or seats > 200:
				errors.append("%s: %s members.%s seats %d out of range" % [fname, org.id, member_id, seats])
				continue
			org.members[member_id] = {"seats": seats}
		else:
			org.members[member_id] = {}

	if has_parliament:
		var next_e: Dictionary = raw_parl.get("next_election", {})
		var year := int(next_e.get("year", 0))
		var month := int(next_e.get("month", 0))
		if year < 2026 or year > 2100 or month < 1 or month > 12:
			errors.append("%s: %s parliament.next_election out of range" % [fname, org.id])
		var term := int(raw_parl.get("term_years", 0))
		if term < 1 or term > 10:
			errors.append("%s: %s parliament.term_years %d out of range" % [fname, org.id, term])
		org.parliament = {
			"next_election": {"year": year, "month": month},
			"term_years": term,
		}

	org.council = bool(raw.get("council", false))
	org.net_transfers = bool(raw.get("net_transfers", false))

	for key in OrgK.ORG_EFFECT_KEYS:
		var v = raw.get(key, 0.0)
		if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
			errors.append("%s: %s %s must be numeric" % [fname, org.id, key])
			continue
		org.set(key, float(v))
	if org.relations_bonus < 0.0 or org.relations_bonus > OrgK.MAX_RELATIONS_BONUS:
		errors.append("%s: %s relations_bonus %.2f outside [0, %.1f]" % [fname, org.id, org.relations_bonus, OrgK.MAX_RELATIONS_BONUS])
	if org.trade_bonus < 0.0 or org.trade_bonus > OrgK.MAX_TRADE_BONUS:
		errors.append("%s: %s trade_bonus %.2f outside [0, %.1f]" % [fname, org.id, org.trade_bonus, OrgK.MAX_TRADE_BONUS])

	org.accession_months = int(raw.get("accession_months", 0))
	org.withdrawal_months = int(raw.get("withdrawal_months", 0))
	org.accession_seats = int(raw.get("accession_seats", 0))
	for key in ["accession_months", "withdrawal_months"]:
		var m := int(org.get(key))
		if m != 0 and (m < OrgK.MIN_ACCESSION_MONTHS or m > OrgK.MAX_ACCESSION_MONTHS):
			errors.append("%s: %s %s %d outside [%d, %d]" % [
				fname, org.id, key, m, OrgK.MIN_ACCESSION_MONTHS, OrgK.MAX_ACCESSION_MONTHS,
			])

	org.accession_position = _extract_position(raw.get("accession_position", {}), "accession_position", org.id, fname, errors)
	org.withdrawal_position = _extract_position(raw.get("withdrawal_position", {}), "withdrawal_position", org.id, fname, errors)

	var raw_rule = raw.get("decision_rule", CouncilK.DECISION_QMR)
	if typeof(raw_rule) != TYPE_STRING:
		errors.append("%s: %s decision_rule must be a string" % [fname, org.id])
		raw_rule = CouncilK.DECISION_QMR
	org.decision_rule = String(raw_rule)
	if not CouncilK.DECISION_RULES.has(org.decision_rule):
		errors.append("%s: %s decision_rule '%s' is not one of %s" % [fname, org.id, org.decision_rule, CouncilK.DECISION_RULES])
		org.decision_rule = CouncilK.DECISION_QMR

	var raw_pres = raw.get("presidency", {})
	if raw.has("presidency") and typeof(raw_pres) != TYPE_DICTIONARY:
		errors.append("%s: %s presidency must be an object" % [fname, org.id])
	if typeof(raw_pres) == TYPE_DICTIONARY and not (raw_pres as Dictionary).is_empty():
		org.presidency = _extract_presidency(raw_pres, org, fname, errors)
	return org


static func _extract_position(raw, key: String, org_id: String, fname: String, errors: Array[String]) -> Dictionary:
	if raw == null or (raw is Dictionary and (raw as Dictionary).is_empty()):
		return {}
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s %s must be an object" % [fname, org_id, key])
		return {}
	var out := {}
	for axis in ["economic", "social"]:
		var v = raw.get(axis, 0.0)
		if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
			errors.append("%s: %s %s.%s must be numeric" % [fname, org_id, key, axis])
			out[axis] = 0.0
			continue
		out[axis] = clampf(float(v), -1.0, 1.0)
	return out


## The chair's rotation. Every id must be an AUTHORED member, once each: a chair
## who is not in the club, or one who presides twice per cycle, is a typo the
## register refuses rather than a rotation the council silently runs.
static func _extract_presidency(raw: Dictionary, org, fname: String, errors: Array[String]) -> Dictionary:
	var order: Array = []
	var raw_order = raw.get("order", [])
	if typeof(raw_order) != TYPE_ARRAY or (raw_order as Array).is_empty():
		errors.append("%s: %s presidency.order missing or empty" % [fname, org.id])
		return {}
	for entry in raw_order:
		if typeof(entry) != TYPE_STRING:
			errors.append("%s: %s presidency.order entries must be strings" % [fname, org.id])
			return {}
		var id := String(entry)
		if not org.members.has(id):
			errors.append("%s: %s presidency.order names '%s', not an authored member" % [fname, org.id, id])
			return {}
		if order.has(id):
			errors.append("%s: %s presidency.order names '%s' twice" % [fname, org.id, id])
			return {}
		order.append(id)
	var raw_months = raw.get("months", 0)
	var whole: bool = typeof(raw_months) == TYPE_INT or (typeof(raw_months) == TYPE_FLOAT and float(raw_months) == roundf(float(raw_months)))
	if not whole:
		errors.append("%s: %s presidency.months must be a whole number" % [fname, org.id])
		return {}
	var months := int(raw_months)
	if months < CouncilK.MIN_PRESIDENCY_MONTHS or months > CouncilK.MAX_PRESIDENCY_MONTHS:
		errors.append("%s: %s presidency.months %d outside [%d, %d]" % [
			fname, org.id, months, CouncilK.MIN_PRESIDENCY_MONTHS, CouncilK.MAX_PRESIDENCY_MONTHS,
		])
		return {}
	var anchor = raw.get("anchor", {})
	# Type-check before int(): int("x") or int([]) is a runtime error, and a
	# malformed data file must be a loader error instead.
	var year := 0
	var month := 0
	if typeof(anchor) == TYPE_DICTIONARY:
		var ry = anchor.get("year", 0)
		var rm = anchor.get("month", 0)
		if (typeof(ry) == TYPE_INT or typeof(ry) == TYPE_FLOAT) and (typeof(rm) == TYPE_INT or typeof(rm) == TYPE_FLOAT):
			year = int(ry)
			month = int(rm)
	if year < CouncilK.MIN_ANCHOR_YEAR or year > CouncilK.MAX_ANCHOR_YEAR or month < 1 or month > 12:
		errors.append("%s: %s presidency.anchor out of range" % [fname, org.id])
		return {}
	return {"order": order, "months": months, "anchor_index": year * 12 + (month - 1)}


## The nation's voting weight in this org's council (and its EP seats where
## this org carries the parliament -- the same number under two names, which is
## why one method serves both).
func seats(nation_id: String) -> int:
	var entry: Dictionary = members.get(nation_id, {})
	return int(entry.get("seats", 0))


func is_member(nation_id: String) -> bool:
	return members.has(nation_id)


## The standing price two nations share, summed over the orgs BOTH belong to.
## One helper because the same three-line loop was about to live in trade.gd
## and foreign_policy.gd -- the co-member term both files hardcode against
## eu_member today, read from live membership and the static snapshot on
## GameState instead. Returns exactly 0.0 when the nations share no org, which
## is the non-member case bit-for-bit.
##
## Reads NationState.orgs (live) and GameState.org_effects (static snapshot of
## content). It deliberately takes neither the loader nor the org table: the
## callers -- Trade.weights() and ForeignPolicy._resting() -- have state and
## nothing else, and the dependency rules forbid handing them one.
static func shared_bonus(state, a_id: String, b_id: String, key: String) -> float:
	var a = state.nations.get(a_id)
	var b = state.nations.get(b_id)
	if a == null or b == null:
		return 0.0
	var total := 0.0
	for org_id in a.orgs:
		if b.orgs.has(org_id):
			var effects: Dictionary = state.org_effects.get(org_id, {})
			total += float(effects.get(key, 0.0))
	return total
