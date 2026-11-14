extends RefCounted

## V5.3 e: what moves a goal (docs/design/finance-bill.md section 11; the author's laws
## direction B, the parent's rulings of 2026-11-14). A READ over the forecasts the game
## already makes, never a new rule: nothing here writes the game.
##
## TIER 1, THE LIST. Every measure the player could put before Parliament now (each open
## law at its own size, each spending line and each tax rate in force by a standard step,
## goal_read_constants.gd) is applied ONCE on a copy of the state through the game's own
## appliers (Legislature.apply_effects, Budget.commit) and read for every goal at once:
## the balance a year at today's economy (law_grade's money arithmetic), where each bloc's
## approval is heading (Opinion.target_of), where structural unemployment is heading
## (Economy.structural_target), the demand impulse's sign, and the division as it would
## fall now. A goal only RANKS those reads, so one list serves every goal of the month.
## A copy costs about 30 ms and cannot be sliced, so the list is a cursor, one measure a
## step, and is kept for the month (list_for).
##
## TIER 2, ONE MEASURE'S TWO YEARS. Budget's own projection from a copy with the measure
## applied, against the month's baseline projection, which is run once and shared
## (years_for). The projection runs no Opinion, so tier 2 answers the economic goals only.
##
## WHAT IS HONEST TO TWO YEARS (section 11): a bloc's target, since approval closes 25 %
## of the gap a month; the balance only as "a year at today's economy"; unemployment's
## structural target only as "heading", the cycle (spending and taxes through demand)
## sized by tier 2 alone; growth, debt and emissions not at all in tier 1.

const Legislature = preload("res://src/sim/legislature.gd")
const Bills = preload("res://src/sim/bills.gd")
const Budget = preload("res://src/sim/budget.gd")
const Economy = preload("res://src/sim/economy.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const K = preload("res://src/sim/goal_read_constants.gd")

## A pledge's field and the goal that reads it; any other field has no tier-1 read.
const FIELD_GOALS := {
	"deficit_pct_gdp": "deficit", "unemployment_pct": "unemployment", "overall_approval_pct": "approval",
}


## Every measure open now, in a fixed order: the laws as the law list scans them, then
## each spending line and each tax kind in force, a step down and a step up, a step that
## would leave the line below nothing or the kind outside its band left out.
static func measures(state, loader) -> Array:
	var ns = state.player()
	var out := []
	for law in Legislature.available(ns, Bills.open(state, ns, loader)):
		out.append({"kind": "law", "id": String(law.id)})
	for key in EK.SPENDING_KEYS:
		for step in [-K.SPENDING_STEP, K.SPENDING_STEP]:
			if float(ns.spending_pct_gdp.get(key, 0.0)) + step >= 0.0:
				out.append({"kind": "line", "key": key, "step": step})
	for kind in ns.tax_rates_pct:
		var band: Array = ns.tax_library[kind]["rate_range_pct"]
		for step in [-K.RATE_STEP, K.RATE_STEP]:
			var landed: float = float(ns.tax_rates_pct[kind]) + step
			if landed >= float(band[0]) and landed <= float(band[1]):
				out.append({"kind": "rate", "key": kind, "step": step})
	return out


## One measure on a copy: every goal's figure, and the division as it would fall now.
## A law tabled, passed or put on cooldown since the month's list was built is no longer
## open: read as gone ({measure, unavailable}), which rank() leaves out.
static func read(state, loader, measure: Dictionary) -> Dictionary:
	var ns = state.player()
	var law = null
	if String(measure["kind"]) == "law":
		law = Legislature.open_law(state, ns, loader, String(measure["id"]))
		if law == null:
			return {"measure": measure, "unavailable": true}
	var parties: Array = loader.parties.get(ns.id, [])
	var sim = state.duplicate_state()
	var sns = sim.player()
	Budget.recompute(sim, sns)
	var deficit_before := float(sns.deficit_pct_gdp) * float(sns.gdp_eur_bn)
	var impulse_before := float(sns.demand_impulse_pct)
	var vote: Dictionary
	if law != null:
		Legislature.apply_effects(sim, sns, law.effects, loader)
		vote = Legislature.resolve_vote(ns, parties, law, Legislature.takes_route(ns, law, false))
	else:
		var bill := {_channel(measure): {String(measure["key"]): float(measure["step"])}}
		Budget.commit(sim, _pending(sns, measure))
		vote = FinanceBill.resolve(ns, parties, FinanceBillLaw.law(ns, {"law_id": "finance:read", "finance": bill}))
	Budget.recompute(sim, sns)
	var sat_now := Opinion.issue_satisfaction(ns)
	var sat_then := Opinion.issue_satisfaction(sns)
	var blocs := {}
	for bloc in OpinionK.BLOC_KEYS:
		blocs[bloc] = Opinion.target_of(sns, bloc, sat_then, Opinion.bloc_weights(sns, bloc, sat_then)) \
			- Opinion.target_of(ns, bloc, sat_now, Opinion.bloc_weights(ns, bloc, sat_now))
	return {
		"measure": measure,
		"cost_bn": (deficit_before - float(sns.deficit_pct_gdp) * float(sns.gdp_eur_bn)) / 100.0,
		"bloc_target": blocs,
		"unemployment_target": Economy.structural_target(sns) - Economy.structural_target(ns),
		"impulse": float(sns.demand_impulse_pct) - impulse_before,
		"passes": bool(vote["passed"]), "yes": int(vote["yes_seats"]), "no": int(vote["no_seats"]),
	}


static func _channel(measure: Dictionary) -> String:
	return "spending_pct_gdp" if String(measure["kind"]) == "line" else "tax_rates_pct"


## A step as Budget.commit's absolute pending: the live value plus the step.
static func _pending(ns, measure: Dictionary) -> Dictionary:
	var register: Dictionary = ns.spending_pct_gdp if String(measure["kind"]) == "line" else ns.tax_rates_pct
	var key := String(measure["key"])
	return {_channel(measure): {key: float(register[key]) + float(measure["step"])}}


## The list's next measure read: one copy, the unit the caller fits into a frame.
static func step(list: List) -> void:
	if not list.done():
		list.reads.append(read(list.state, list.loader, list.measures[list.reads.size()]))


## The rows for `goal` ("deficit", "unemployment", "approval", "bloc:<id>", or
## "field:<a pledge's field>"), best first, ties by the chance to pass. A row is
## {measure, effect, read, sign, passes, cost_bn}; `effect` is signed so that more is
## better for the goal. A measure tier 1 cannot size for the goal is listed unread with
## its sign; one with no channel to it at all is left out. A field with no tier-1 read
## gives one row, {no_read: true}: run the forecast.
static func rank(reads: Array, goal: String, _state, _loader) -> Array:
	if goal.begins_with("field:"):
		var field := goal.trim_prefix("field:")
		if not FIELD_GOALS.has(field):
			return [{"no_read": true, "field": field}]
		goal = String(FIELD_GOALS[field])
	var read_rows := []
	var unread := []
	for r in reads:
		if bool(r.get("unavailable", false)):
			continue
		var row := {"measure": r["measure"], "passes": r["passes"], "cost_bn": r["cost_bn"], "read": true, "sign": 0}
		var effect := _effect(r, goal)
		if effect != 0.0:
			row["effect"] = effect
			row["sign"] = 1 if effect > 0.0 else -1
			read_rows.append(row)
		elif goal == "unemployment" and float(r["impulse"]) != 0.0:
			row["read"] = false
			row["effect"] = 0.0
			row["sign"] = 1 if float(r["impulse"]) > 0.0 else -1
			unread.append(row)
	read_rows.sort_custom(_better)
	unread.sort_custom(_better)
	return read_rows + unread


static func _effect(r: Dictionary, goal: String) -> float:
	match goal:
		"deficit":
			return float(r["cost_bn"])
		"unemployment":
			return -float(r["unemployment_target"])
		"approval":
			var total := 0.0
			for bloc in OpinionK.BLOC_KEYS:
				total += float(OpinionK.BLOC_SIZE[bloc]) * float(r["bloc_target"][bloc])
			return total
	return float(r["bloc_target"].get(goal.trim_prefix("bloc:"), 0.0))


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if float(a["effect"]) != float(b["effect"]):
		return float(a["effect"]) > float(b["effect"])
	if int(a["sign"]) != int(b["sign"]):
		return int(a["sign"]) > int(b["sign"])
	return bool(a["passes"]) and not bool(b["passes"])


## The month's list: `prev` again when it was built for this game and this month (done
## or still filling), else a new one. Reopening a goal the same month costs nothing.
static func list_for(prev, state, loader) -> List:
	var month := int(state.year) * 12 + int(state.month)
	if prev != null and prev.state == state and prev.month == month:
		return prev
	var list := List.new()
	list.state = state
	list.loader = loader
	list.month = month
	list.measures = measures(state, loader)
	return list


## One measure's projection against the month's baseline, `prev`'s baseline kept when
## it is this game's, this month's and this horizon's. null for a law no longer open.
static func years_for(prev, state, loader, measure: Dictionary, months: int = K.YEARS_MONTHS) -> Years:
	var law = null
	if String(measure["kind"]) == "law":
		law = Legislature.open_law(state, state.player(), loader, String(measure["id"]))
		if law == null:
			return null
	var month := int(state.year) * 12 + int(state.month)
	var years := Years.new()
	if prev != null and prev.baseline.state == state and prev.baseline.month == month and prev.baseline.months == months:
		years.baseline = prev.baseline
	else:
		years.baseline = Baseline.new()
		years.baseline.state = state
		years.baseline.month = month
		years.baseline.months = months
		years.baseline.job = Budget.projection(state, {}, months, loader)
	years.job = Budget.projection(state, {}, months, loader)
	years.job.sim = Budget.projection_copy(state, {})
	var sns = years.job.sim.player()
	if law != null:
		Legislature.apply_effects(years.job.sim, sns, law.effects, loader)
	else:
		Budget.commit(years.job.sim, _pending(sns, measure))
	return years


class List extends RefCounted:
	var state
	var loader
	var month := -1
	var measures: Array = []
	var reads: Array = []

	func done() -> bool:
		return reads.size() == measures.size()


class Baseline extends RefCounted:
	var state
	var month := -1
	var months := 0
	var job


class Years extends RefCounted:
	var baseline: Baseline
	var job

	## One projection unit: the baseline's first while it runs, then the measure's.
	func step() -> void:
		if not Budget.projection_done(baseline.job):
			Budget.projection_step(baseline.job)
		elif not Budget.projection_done(job):
			Budget.projection_step(job)

	func done() -> bool:
		return Budget.projection_done(baseline.job) and Budget.projection_done(job)

	## The last projected month, the measure's run less the baseline's, per figure.
	func result() -> Dictionary:
		var out := {}
		var with: Dictionary = job.path[job.path.size() - 1]
		var base: Dictionary = baseline.job.path[baseline.job.path.size() - 1]
		for key in ["deficit_pct_gdp", "debt_to_gdp_pct", "growth_annual_pct", "unemployment_pct"]:
			out[key] = float(with[key]) - float(base[key])
		return out
