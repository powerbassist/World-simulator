extends RefCounted

## Campaign promises -- V1.7b, the second session of the V1.7 block. A promise made in
## the run-up, binding across the term it wins, and charged for every month it stands
## broken. The model and every number's rationale is docs/pledge-model.md;
## src/sim/pledges_constants.gd is the bounds and data/pledges/ is the ladder.
##
## ============================================================================
## THE PRICE IS ns.bloc_offset, AND NO TRUST QUANTITY WAS INVENTED
## ============================================================================
## ROADMAP.md's V1.7 decomposition records this row as the one most likely to SPLIT,
## on exactly that: "the price is a quantity that does not exist, which is V1.5d's
## legitimacy problem again", and "if the price cannot land on an existing register
## the way V1.5d landed legitimacy on the grievance, then the ledger and the price are
## two sessions."
##
## It lands, and V1.5d's OWN CRITERION is what puts it here -- applied in the other
## direction. docs/media-model.md section 6 sent legitimacy to the grievance because
## legitimacy is willingness to accept your rule OUTSIDE the ballot box. Trust in a
## promise is the opposite: it is squarely AT the ballot box, so it belongs on the
## register that reaches the ballot box. That is ns.bloc_offset, the permanent
## per-bloc approval-target accumulator docs/campaign-model.md section 6 already made
## a campaign's own lasting mark -- "the money and the mobilisation are both spent at
## the ballot box; the resentment is not."
##
## A separate trust stock would also have been the thing docs/tiers/v1.md section 5
## warns against in so many words: a second approval number with a different label.
## tools/pledge_probe.gd table (b0) measured the landing site before a line of content
## existed, which is what makes this a measurement and not a preference.
##
## ============================================================================
## JUDGED EVERY MONTH, NOT AT THE END OF THE TERM -- INSTANCE FORTY-TWO
## ============================================================================
## The row says the triple is "read at the END of the term instead of at proposal".
## The contrast is right and the timing is wrong, and it fails twice on facts that can
## be counted rather than argued:
##
##   1. A SINGLE TERM-END READ IS STRICTLY DOMINATED BY LAST-MINUTE COMPLIANCE.
##      Promise unemployment at or below seven, run it at nine for four years, squeeze
##      it to 6.9 for the final month, pay nothing. That is the shape this project has
##      killed eight times (V1.3c's severities, V1.3d's fourth rule, U6a's booking,
##      V1.4c's dividend, V1.5d's censorship, V1.6e's flat bill, V1.7a's one-off
##      purchase, and pledges_constants.gd's refused `renounce` op).
##
##   2. IT IS STRUCTURALLY INVISIBLE AT THE VOTE IT IS ABOUT. src/ui/main.gd runs
##      Opinion.tick_month() and then, much later in the same month, Elections
##      .tick_month(). Anything writing bloc_offset after the first reaches
##      bloc_approval on the NEXT month's tick -- and even moved ahead of Opinion,
##      opinion_constants.INERTIA_RATE delivers a quarter of the price before the
##      vote. A term-end judgement charges a president for a broken promise at an
##      election that has already been decided without it.
##
## So a promise is judged on a LEVEL every month it is live, and the accrual is the
## price. "The end of the term" is where the TOTAL is read, and the total is the
## integral. That is docs/campaign-model.md's "an effort is a standing rate with a
## deadline" applied to the PRICE rather than to the spend.
##
## GRADED-BY-THE-MISS WAS DESIGNED AND CUT. Scaling the charge by how badly the field
## missed needs a per-field normaliser -- a table with no measurement behind it, which
## is docs/unrest-model.md's own warning. Breach is BINARY per month, and the count of
## breached months is the whole memory: V1.3e's "no grievance ledger" property in a
## new place, where the number IS the record.
##
## ============================================================================
## THE WINDOW IS A LEVEL READ AND SO IS THE EXPIRY
## ============================================================================
## A promise may be made only inside Campaign.is_open(), and it binds the term that
## run-up is for. Both dates are frozen at the moment it is made, out of
## ns.next_executive_* and ns.term_months, and everything afterwards is a comparison
## against the clock -- docs/defence-model.md's V1.3g rule, that nothing in this
## project ever lifts a flag it has set. There is no "the pledge is live" flag and
## nothing in elections.gd knows this file exists.
##
## FROZEN RATHER THAN DERIVED, and that is the one place it matters: Elections
## .tick_month() pushes next_executive_* a full term forward the moment the incumbent
## wins, so a pledge deriving its own deadline from that field would move its own
## goalposts on the night it was won.
##
## Preloads campaign.gd for is_open(), its own constants and opinion_constants. That
## is (b) reading (a), which is what the decomposition says it does; campaign.gd
## preloads three constants files and nothing else, so there is no cycle and no
## ordering question. tests/test_pledges.gd asserts this exact list.

const K = preload("res://src/sim/pledges_constants.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")


## Seeds the live register: nothing promised.
##
## Every nation gets the fields rather than only the player, Campaign.init_nation()'s
## and Projects.init_nation()'s call: what keeps the nine inert is that nothing ever
## executes a pledge for them, and tests/test_pledges.gd pins that there is no AI
## agenda term for this verb -- docs/defence-model.md's honest limitation, recorded a
## fifth time.
static func init_nation(ns) -> void:
	ns.pledges = []
	ns.last_pledge_result = {}


## One month of every live promise: charge the broken ones, retire the expired ones.
##
## Runs in src/ui/main.gd's order immediately after Campaign.tick_month() and before
## Elections.tick_month(), which is what makes the last month of a term count -- the
## promise is judged, and then the vote is held.
##
## NOT ADDED TO Budget.project(). Every other register in that list is there because
## it moves a spending line; a bloc_offset write is not fiscal, and a projection that
## charged a broken promise would be a budget preview quietly moving approval.
static func tick_month(state, loader) -> void:
	var terms := _terms_by_pledge(loader)
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		_tick_nation(state, state.nations[id], terms)


static func _tick_nation(state, ns, terms: Dictionary) -> void:
	if ns.pledges.is_empty():
		return

	var now: int = _absolute_month(state.year, state.month)
	var kept: Array = []

	for entry in ns.pledges:
		var until: int = _absolute_month(int(entry["until_year"]), int(entry["until_month"]))
		if now > until:
			# Retired on a level read of the clock. What it charged stays charged --
			# bloc_offset is an accumulator, so a term of broken promises outlives the
			# term, which is docs/campaign-model.md section 6's asymmetry exactly.
			continue
		kept.append(entry)

		var from: int = _absolute_month(int(entry["from_year"]), int(entry["from_month"]))
		if now <= from:
			# Made, but the term it binds has not begun. A promise is not broken
			# before it is owed.
			continue

		entry["months_live"] = int(entry["months_live"]) + 1
		if not in_breach(state, ns, entry):
			continue

		entry["breach_months"] = int(entry["breach_months"]) + 1
		var offsets: Dictionary = terms.get(String(entry["pledge_id"]), {}).get("breach_offset", {})
		var blocs: Array = offsets.keys()
		# Sorted, because a Dictionary's key order is insertion order and two runs that
		# reached the same state by different routes must tick alike.
		blocs.sort()
		for bloc in blocs:
			ns.bloc_offset[bloc] = clampf(
				float(ns.bloc_offset.get(bloc, 0.0)) - float(offsets[bloc]),
				LegislatureK.BLOC_OFFSET_MIN, LegislatureK.BLOC_OFFSET_MAX
			)

	ns.pledges = kept


# --- Reading the register -----------------------------------------------------------

## Whether this promise is currently being kept. A pure comparison, so the panel, the
## probe and the tick all read one answer.
static func in_breach(state, ns, entry: Dictionary) -> bool:
	var actual: float = _read_field(state, ns, String(entry["field"]))
	var value: float = float(entry["value"])
	match String(entry["op"]):
		"<=": return actual > value
		">=": return actual < value
		_: return false


## True once the term this promise binds has begun and before it has ended.
static func is_live(state, entry: Dictionary) -> bool:
	var now: int = _absolute_month(state.year, state.month)
	return (
		now > _absolute_month(int(entry["from_year"]), int(entry["from_month"]))
		and now <= _absolute_month(int(entry["until_year"]), int(entry["until_month"]))
	)


## Every promise on the books, sorted, for the panel. Sorted rather than in the order
## they were made so two saves of the same state draw the same list.
static func on_the_books(ns) -> Array:
	var out: Array = ns.pledges.duplicate()
	out.sort_custom(func(a, b): return String(a["pledge_id"]) < String(b["pledge_id"]))
	return out


static func pledge_count(ns) -> int:
	return ns.pledges.size()


static func has_pledged(ns, pledge_id: String) -> bool:
	for entry in ns.pledges:
		if String(entry["pledge_id"]) == pledge_id:
			return true
	return false


## The NOUN, not the action name. Campaign.name_of()'s and Projects.name_of()'s
## reason: an action name is an imperative, which is right on the button that makes
## the promise and wrong everywhere the promise itself is named.
static func name_of(loader, pledge_id: String) -> String:
	return String(terms_of(loader, pledge_id).get("pledge_name", pledge_id))


static func terms_of(loader, pledge_id: String) -> Dictionary:
	return _terms_by_pledge(loader).get(pledge_id, {})


## pledge id -> the authored {field, op, value, breach_offset, pledge_name}. Built from
## the loader on every call rather than cached on NationState, because caching it would
## put content in the save -- the property tests/test_pledges.gd pins, and V1.4a's,
## V1.6e's, V1.6f's and V1.7a's tests before it.
static func _terms_by_pledge(loader) -> Dictionary:
	var out := {}
	if loader == null:
		return out
	for action in loader.pledges:
		var terms: Dictionary = action.effects.get("pledge", {})
		var pid := String(terms.get("pledge_id", ""))
		if pid != "":
			out[pid] = terms
	return out


# --- The verb --------------------------------------------------------------------------

## Which promises may be made right now. Campaign.available()'s shape.
##
## REFUSES EVERYTHING OUTSIDE THE RUN-UP, structurally, before any content is
## consulted -- which is why pledges_constants.PRECONDITION_FIELDS has no
## `campaign_open` entry.
##
## AND REFUSES A TERMED-OUT INCUMBENT, which the probe found rather than the design.
## Table (a0) prints three run-ups over fourteen years and the third opens in
## September 2036 against a `termed_out` notice in May 2037: Campaign.is_open() is a
## pure clock read with no term-limit branch, so the window opens for a president who
## cannot stand. Spending money on a successor's campaign is at least arguable and
## V1.7a is left as it is; a PROMISE about a term you are barred from serving binds
## nobody, so this file refuses it and says so.
static func available(state, ns, all_actions: Array) -> Array:
	var out: Array = []
	if not Campaign.is_open(state, ns):
		return out
	if ns.term_limit > 0 and ns.terms_served >= ns.term_limit:
		return out
	for action in all_actions:
		if action.id == "":
			continue
		var pid := String(action.effects.get("pledge", {}).get("pledge_id", ""))
		if pid == "" or has_pledged(ns, pid):
			continue
		if _preconditions_met(state, ns, action):
			out.append(action)
	return out


static func _preconditions_met(state, ns, action) -> bool:
	for cond in action.preconditions:
		var actual: float = _read_field(state, ns, cond["field"])
		var value: float = cond["value"]
		var ok: bool
		match cond["op"]:
			"<": ok = actual < value
			"<=": ok = actual <= value
			">": ok = actual > value
			">=": ok = actual >= value
			"==": ok = is_equal_approx(actual, value)
			_: ok = false
		if not ok:
			return false
	return true


## The player command: put a promise on the books, take what the blocs pay for hearing
## it, and record the result for the panel to read. Campaign.execute()'s shape.
##
## IT DOES NOT GO THROUGH Budget.commit(), which is deliberate rather than convenient
## and for once trivially so: a promise has no bill at all. V1.6e's, V1.6f's and
## V1.7a's escape from docs/tax-model.md section 11's live bug is inherited by having
## nothing to escape.
##
## THE REWARD IS PAID NOW AND THE PRICE IS CHARGED LATER, WHICH IS THE WHOLE DECISION.
## docs/society-model.md's "the delta prices the announcement, the stock prices the
## delivery" -- here literally, on one channel, with opposite signs at different times.
##
## Refuses rather than half-applies when the promise is not currently available, so a
## UI offering a stale button cannot produce the effect the window exists to prevent.
static func execute(state, ns, all_actions: Array, action) -> Dictionary:
	var terms: Dictionary = action.effects.get("pledge", {})
	var pid := String(terms.get("pledge_id", ""))

	if not available(state, ns, all_actions).has(action):
		var refused := {
			"action_id": action.id,
			"pledge_id": pid,
			"applied": false,
			"refused": true,
		}
		ns.last_pledge_result = refused
		return refused

	# Frozen at the moment of the promise. See the header: deriving these later would
	# let a re-elected president's own victory move the deadline they promised against.
	var from: int = _absolute_month(int(ns.next_executive_year), int(ns.next_executive_month))
	var until: int = from + int(ns.term_months)

	ns.pledges.append({
		"pledge_id": pid,
		"field": String(terms.get("field", "")),
		"op": String(terms.get("op", "")),
		"value": float(terms.get("value", 0.0)),
		"from_year": _year_of(from),
		"from_month": _month_of(from),
		"until_year": _year_of(until),
		"until_month": _month_of(until),
		"breach_months": 0,
		"months_live": 0,
	})

	for bloc_id in action.effects.get("bloc_offset", {}).keys():
		ns.bloc_offset[bloc_id] = clampf(
			float(ns.bloc_offset.get(bloc_id, 0.0))
			+ float(action.effects["bloc_offset"][bloc_id]),
			LegislatureK.BLOC_OFFSET_MIN, LegislatureK.BLOC_OFFSET_MAX
		)

	var result := {
		"action_id": action.id,
		"action_name": action.action_name,
		"pledge_id": pid,
		"pledge_name": String(terms.get("pledge_name", pid)),
		"applied": true,
		"refused": false,
		"binds_until": "%04d-%02d" % [_year_of(until), _month_of(until)],
	}
	ns.last_pledge_result = result
	return result


## Every field here is the acting nation's own state. `months_to_election` and
## `pledge_count` are gates and not promises, which is why pledges_constants keeps two
## lists rather than one: promising your own pledge count is not a sentence.
static func _read_field(state, ns, field: String) -> float:
	match field:
		"unemployment_pct": return ns.unemployment_pct
		"deficit_pct_gdp": return ns.deficit_pct_gdp
		"debt_to_gdp_pct": return ns.debt_to_gdp_pct()
		"growth_annual_pct": return ns.growth_annual_pct
		"unrest_pct": return ns.unrest_pct
		"tax_income_pct": return float(ns.tax_rates_pct.get("income", 0.0))
		"tax_corporate_pct": return float(ns.tax_rates_pct.get("corporate", 0.0))
		"tax_vat_pct": return float(ns.tax_rates_pct.get("vat", 0.0))
		"tax_capital_gains_pct": return float(ns.tax_rates_pct.get("capital_gains", 0.0))
		"tax_wealth_pct": return float(ns.tax_rates_pct.get("wealth", 0.0))
		"spending_health_pct_gdp": return float(ns.spending_pct_gdp.get("health", 0.0))
		"spending_education_pct_gdp": return float(ns.spending_pct_gdp.get("education", 0.0))
		"spending_defence_pct_gdp": return float(ns.spending_pct_gdp.get("defence", 0.0))
		"spending_pensions_pct_gdp": return float(ns.spending_pct_gdp.get("pensions", 0.0))
		"spending_infrastructure_pct_gdp": return float(ns.spending_pct_gdp.get("infrastructure", 0.0))
		"pledge_count": return float(pledge_count(ns))
		"months_to_election": return float(Campaign.months_to_election(state, ns))
		_:
			push_error("pledges: unknown field '%s'" % field)
			return 0.0


# --- Dates --------------------------------------------------------------------------

## Months since year zero. The register stores year/month pairs because that is what
## the save and the panel both read, and every comparison in this file runs through
## here so no two of them can disagree about what "before" means.
static func _absolute_month(year: int, month: int) -> int:
	return year * 12 + (month - 1)


static func _year_of(absolute: int) -> int:
	return absolute / 12


static func _month_of(absolute: int) -> int:
	return (absolute % 12) + 1
