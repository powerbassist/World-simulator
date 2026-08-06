extends RefCounted

## The defence model: military capability derived from sustained spending,
## deployments as reversible commitments, defensive pacts, and the obligation that
## opens a deployment without asking. Built at V1.3g, the last session of the V1.3
## block. The model and every constant's rationale is docs/defence-model.md;
## src/sim/defence_constants.gd is the values.
##
## Takes no loader, the discipline src/sim/trade.gd and src/sim/coercion.gd both
## hold to: capability reads the live spending line, and an obligation reads the
## live pacts and measures registers. Nothing here needs content, so
## Budget.project() runs the real model forward on a copy and gets the real answer.
##
## WRITES state.deployments and state.pacts -- and is the only thing that writes
## the first. That is a departure from coercion.gd, which reads a register a third
## module owns, and the reason is that an obliged deployment is not a command:
## nobody issues it, so there is no execute() to own it. Diplomacy still owns the
## PACT writes in the sense that its execute() calls sign_pact()/abandon_pact()
## here; it is the reconciliation that has no caller but the monthly tick.
##
## A SEPARATE MODULE FROM src/sim/diplomacy.gd, deliberately, and the preload
## graph is why: diplomacy.gd preloads foreign_policy.gd preloads trade.gd preloads
## coercion.gd, and this file must be reachable from budget.gd and game_state.gd
## without dragging that chain behind it. It preloads coercion.gd and nothing else
## from src/sim/, which is a leaf.

const K = preload("res://src/sim/defence_constants.gd")
const RK = preload("res://src/core/relations.gd")
const Coercion = preload("res://src/sim/coercion.gd")


## A nation's starting capability is its EQUILIBRIUM, not zero. A France that has
## spent 2.0 % of GDP on defence for decades has an army on the day the game
## starts, and seeding at zero would mean every nation in the roster spends the
## first decade of every game acquiring one -- a transient nobody authored,
## visible in every number that reads capability, and wrong.
static func init_nation(ns) -> void:
	ns.military_capability = capability_target(ns)
	ns.deployment_bill_pct_gdp = 0.0
	ns.deployment_opinion_load = 0.0


## Runs after Diplomacy in src/ui/main.gd's order, and Budget.project() runs it in
## the same slot. See docs/defence-model.md §3 for why the obligation is a level
## read rather than an edge trigger, and main.gd's own comment for why the two
## prices lag a month together rather than one of them lagging alone.
static func tick_month(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		_tick_capability(state.nations[id])

	# Orphans first. A pact abandoned this month must not survive as a live bill
	# for one more month because the reconciler happened to re-open it, and the
	# order is what makes that structural rather than a case _reconcile_obliged()
	# has to remember.
	_close_orphans(state)
	_reconcile_obliged(state)
	_recompute_prices(state)


# --- Capability ---------------------------------------------------------------

## What this nation's capability is converging on: its own defence spending line.
## Derived and never authored, the treatment src/sim/cabinet.gd's competence gets
## -- an authored per-nation military strength is a second number somebody has to
## keep in step with the first, and it disagrees with it the moment a player moves
## the lever.
static func capability_target(ns) -> float:
	return clampf(
		float(ns.spending_pct_gdp.get("defence", 0.0)), K.CAPABILITY_MIN, K.CAPABILITY_MAX
	)


## One month of convergence. Pure, so tools/defence_probe.gd can sweep the
## constant over a fourteen-year horizon without building a GameState.
static func capability_step(current: float, target: float) -> float:
	return clampf(
		current + K.CAPABILITY_CONVERGENCE * (target - current),
		K.CAPABILITY_MIN,
		K.CAPABILITY_MAX,
	)


## Capability as a multiple of an ordinary military, clamped. Everything that
## reads capability reads it through here, so the reference-relative anchoring
## docs/defence-model.md argues for cannot be bypassed by a caller dividing by
## something else.
static func capability_ratio(ns) -> float:
	return clampf(
		float(ns.military_capability) / K.CAPABILITY_REFERENCE,
		K.DEPLOYMENT_COST_MIN_RATIO,
		K.DEPLOYMENT_COST_MAX_RATIO,
	)


static func _tick_capability(ns) -> void:
	ns.military_capability = capability_step(
		float(ns.military_capability), capability_target(ns)
	)


# --- Pacts: the symmetric register --------------------------------------------

static func pact_active(state, a: String, b: String) -> bool:
	return state.pacts.has(RK.key(a, b))


static func pact_count(state, actor_id: String) -> int:
	return allies(state, actor_id).size()


## The "set of allies" the tier bullet asks for, DERIVED rather than stored. This
## is what makes a fifth kind of live state unnecessary: an alliance is a set only
## when you look at it from one nation, and every pair in it is a pair.
static func allies(state, actor_id: String) -> Array:
	var out: Array = []
	for pair_key in state.pacts.keys():
		var counterparty := RK.other(String(pair_key), actor_id)
		if counterparty != "":
			out.append(counterparty)
	out.sort()
	return out


## The terms are copied into the register at signing and read from there
## afterwards -- the fourth time this project has made that call, after an
## agreement's terms, a measure's severity and a bloc rule's constraint, and for
## the same reason: what binds you is what was signed, not what the content file
## says later.
static func sign_pact(state, a: String, b: String, action) -> void:
	state.pacts[RK.key(a, b)] = {
		"action_id": action.id,
		"action_name": action.action_name,
		"since_year": state.year,
		"since_month": state.month,
	}


## Abandoning closes every deployment on the pair, in BOTH directions and of both
## kinds. One rule rather than four cases, which is what requiring a pact for a
## chosen deployment buys: the pact is the domain of both registers, so there is
## exactly one way for a deployment to become an orphan and exactly one place that
## handles it.
static func abandon_pact(state, a: String, b: String) -> void:
	state.pacts.erase(RK.key(a, b))
	close_deployment(state, a, b)
	close_deployment(state, b, a)


# --- Deployments: the directed register ---------------------------------------

## Every deployment `actor_id` currently has open, as {ally_id: terms}. The
## register is directed, so this is a filter over one side of the key rather than
## a lookup -- Coercion.imposed_by()'s shape, on the other register with the same
## separator.
static func deployments_of(state, actor_id: String) -> Dictionary:
	var out := {}
	for directed in state.deployments.keys():
		var parts := RK.directed_parts(String(directed))
		if parts.size() != 2 or parts[0] != actor_id:
			continue
		out[parts[1]] = state.deployments[directed]
	return out


## "chosen", "obliged", or "" for no deployment. The register's own read, kept in
## one place so the precondition fields cannot drift apart -- the argument
## diplomacy_constants.gd gives for having three measure fields rather than one.
static func deployment_kind(state, actor_id: String, ally_id: String) -> String:
	var terms = state.deployments.get(RK.directed_key(actor_id, ally_id))
	if terms == null:
		return ""
	return String(terms.get("kind", ""))


static func deployment_count(state, actor_id: String) -> int:
	return deployments_of(state, actor_id).size()


## `action` may be null: an obliged deployment has no verb behind it, which is the
## whole point of it. The panel reads the action name when there is one and says
## so when there is not.
static func open_deployment(state, actor_id: String, ally_id: String, kind: String, action) -> void:
	var entry := {
		"kind": kind,
		"since_year": state.year,
		"since_month": state.month,
	}
	if action != null:
		entry["action_id"] = action.id
		entry["action_name"] = action.action_name
	# The cost is NOT stored. It is derived from live capability every month, and
	# storing it would be one intensity written twice -- the redundancy
	# tools/coercion_probe.gd cut when it deleted the authored tariff_rate_pct.
	state.deployments[RK.directed_key(actor_id, ally_id)] = entry


static func close_deployment(state, actor_id: String, ally_id: String) -> void:
	state.deployments.erase(RK.directed_key(actor_id, ally_id))


# --- The obligation -----------------------------------------------------------

## Whether `actor_id`'s pact with `ally_id` obliges it right now: somebody other
## than the actor itself has a measure in force on the ally, at or above the floor.
##
## The self-exclusion is not defensive coding. Without it, a nation that tariffs
## its own ally is obliged to deploy in that ally's support AGAINST ITSELF, and
## the register would carry a commitment nobody could read a meaning into.
static func obligation_due(state, actor_id: String, ally_id: String) -> bool:
	var measures := Coercion.against(state, ally_id)
	for imposer_id in measures.keys():
		if String(imposer_id) == actor_id:
			continue
		if float(measures[imposer_id].get("severity", 0.0)) >= K.OBLIGATION_MIN_SEVERITY:
			return true
	return false


## A LEVEL READ, reconciled every month, and docs/defence-model.md §3 records why
## at length: nothing in this project ever lifts a measure except a lift verb, and
## no AI carries one on its agenda, so an edge-triggered obligation turns every
## retaliation that lands on a pact partner into a permanent line on the player's
## budget. The player still cannot close an obligation -- only the aggressor
## lifting the measure, or abandoning the pact, can.
static func _reconcile_obliged(state) -> void:
	var pair_keys: Array = state.pacts.keys()
	pair_keys.sort()

	for pair_key in pair_keys:
		var parts := RK.pair_parts(String(pair_key))
		if parts.size() != 2:
			continue
		_reconcile_one(state, String(parts[0]), String(parts[1]))
		_reconcile_one(state, String(parts[1]), String(parts[0]))


static func _reconcile_one(state, actor_id: String, ally_id: String) -> void:
	var due := obligation_due(state, actor_id, ally_id)
	var kind := deployment_kind(state, actor_id, ally_id)

	if due:
		# A CHOSEN deployment already in place is left chosen rather than promoted.
		# The player volunteered before the obligation arrived, and re-labelling it
		# would raise the domestic price of a commitment they made freely -- charging
		# somebody the obliged multiplier for a decision they took themselves.
		if kind == "":
			open_deployment(state, actor_id, ally_id, K.DEPLOYMENT_OBLIGED, null)
		return

	if kind == K.DEPLOYMENT_OBLIGED:
		close_deployment(state, actor_id, ally_id)


## A deployment whose pact is gone. Reachable through exactly one route -- the
## pact was abandoned by the counterparty rather than by this nation -- because
## abandon_pact() closes its own side's pair directly.
static func _close_orphans(state) -> void:
	var directed_keys: Array = state.deployments.keys()
	directed_keys.sort()

	for directed in directed_keys:
		var parts := RK.directed_parts(String(directed))
		if parts.size() != 2:
			continue
		if not pact_active(state, String(parts[0]), String(parts[1])):
			state.deployments.erase(directed)


# --- The two prices -----------------------------------------------------------

## What ONE deployment costs this nation, points of GDP per year. Inverse in
## capability, which is the whole reason capability exists: a nation that has
## funded its military commits cheaply, and a nation that has not pays through the
## nose for the same commitment. That is what makes sustained spending PAY, which
## a spending line on its own never does.
static func deployment_cost_pct_gdp(ns) -> float:
	return K.DEPLOYMENT_COST_PCT_GDP / capability_ratio(ns)


## The whole bill, clamped. If the reachable obliged stack measured by
## tools/defence_probe.gd table (d) sits ON the clamp, the clamp and not the model
## is setting the number and the session's first escalation trigger has fired.
static func deployment_bill_pct_gdp(state, ns) -> float:
	var count := deployment_count(state, ns.id)
	if count == 0:
		return 0.0
	return minf(
		deployment_cost_pct_gdp(ns) * float(count), K.DEPLOYMENT_BILL_MAX_PCT_GDP
	)


## What the deployments take off the `defence` issue's satisfaction, on the
## [-1, +1] scale opinion_constants.gd's terms use. Positive here and SUBTRACTED
## by the caller, so the sign is decided in one place.
##
## Not scaled by capability. A commitment a well-funded army makes cheaply in
## money is not one the public minds less -- the cost that reaches an electorate is
## the fact of the commitment, and pricing it twice off the same stock would make
## a defence build-up politically free, which is the opposite of what the issue is
## in the model to say.
static func deployment_opinion_load(state, ns) -> float:
	var load := 0.0
	for ally_id in deployments_of(state, ns.id).keys():
		var kind := deployment_kind(state, ns.id, String(ally_id))
		load += K.DEPLOYMENT_OPINION_CHOSEN * (
			K.DEPLOYMENT_OBLIGED_MULT if kind == K.DEPLOYMENT_OBLIGED else 1.0
		)
	return load


## Both prices cached onto NationState once a month, and read from there by
## Budget.recompute() and Opinion.issue_satisfaction().
##
## Cached rather than called, and the reason is the preload graph rather than
## speed: budget.gd and opinion.gd reading Defence directly is an edge each, and
## opinion.gd's issue_satisfaction(ns) would stop being pure-on-ns -- which
## elections.gd's attribution and overview_panel.gd both depend on.
##
## Gated on has_budget, bloc.gd:114's shape. The REGISTERS are not gated: an
## AI-to-AI pact is world state like a measure, and the map and the nation panel
## read it.
static func _recompute_prices(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		if not ns.has_budget:
			continue
		ns.deployment_bill_pct_gdp = deployment_bill_pct_gdp(state, ns)
		ns.deployment_opinion_load = deployment_opinion_load(state, ns)
