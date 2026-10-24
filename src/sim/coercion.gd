extends RefCounted

## The coercion model: tariffs and sanctions, what they collect, what they cost,
## and what they do to the nation they are pointed at. Built at V1.3c. The model
## and every constant's rationale is docs/coercion-model.md;
## src/sim/coercion_constants.gd is the values.
##
## Stateless, and takes no loader -- the same discipline src/sim/trade.gd holds to,
## and for the same two reasons. Every function here is a pure read over GameState,
## so Budget.project() runs the real model forward on a copy and gets the real
## answer; and no loader means Economy.tick_month()'s signature is untouched again.
##
## Reads state.measures; does NOT write it. Diplomacy owns that register, because
## it is pair state written by a player command exactly like relations and
## agreements. The split keeps rule 3: the modules talk through GameState and never
## preload each other.
##
## A SEPARATE MODULE FROM src/sim/trade.gd, deliberately. The two are close --
## coercion multiplies the weight trade derives -- but they are three different
## jobs: trade answers "who do I trade with", this answers "what does coercion
## collect and destroy", and the register is written by a third module again.
## Folding it into trade.gd would have put a revenue function and a growth-damage
## function in a file whose own header says it is a weight model.

const K = preload("res://src/sim/coercion_constants.gd")
const RK = preload("res://src/core/relations.gd")
const Org = preload("res://src/core/org.gd")


## R10b. Every tariff between two nations that share a customs union, lifted:
## the verb refuses one since R10 (Org.shared_flag), so one standing is a
## tariff from before -- a save made before the rule, or a pair that has just
## become fellow members -- and nothing else would ever lift it. A sanction is
## not a customs duty and stands (R10's scope).
static func clear_union_tariffs(state) -> void:
	var doomed := []
	for directed in state.measures.keys():
		var parts := RK.directed_parts(String(directed))
		if parts.size() == 2 and _kind_of(state.measures[directed]) == "tariff" \
				and Org.shared_flag(state, parts[0], parts[1], "customs_union") != "":
			doomed.append(directed)
	for directed in doomed:
		state.measures.erase(directed)


## What an accession to `org_id` ends (moved from orgs.gd's membership flip,
## V3.2): the org's own collective measures aimed AT the joiner -- the common
## external tariff cannot keep levying on a fellow member, and there is no repeal
## path that would ever lift it otherwise -- and, R10b (the author, "Oui, tout de
## suite"), every tariff between the joiner and a fellow member of a customs union,
## both ways. Called after membership has flipped.
static func clear_on_accession(state, org_id: String, joiner: String) -> void:
	var doomed := []
	for directed in state.measures.keys():
		var terms: Dictionary = state.measures[directed]
		if String(terms.get("org", "")) == org_id and String(directed).ends_with(">" + joiner):
			doomed.append(directed)
	for directed in doomed:
		state.measures.erase(directed)
	clear_union_tariffs(state)


static func _kind_of(terms) -> String:
	return String(terms.get("kind", ""))


## Every measure in force pointed AT `target_id`, as {imposer_id: terms}. The
## register is directed, so this is a filter over one side of the key rather than
## a lookup.
static func against(state, target_id: String) -> Dictionary:
	var out := {}
	for directed in state.measures.keys():
		var parts := RK.directed_parts(String(directed))
		if parts.size() != 2 or parts[1] != target_id:
			continue
		out[parts[0]] = state.measures[directed]
	return out


## Every measure `actor_id` currently has in force, as {target_id: terms}. The
## other side of the same filter.
static func imposed_by(state, actor_id: String) -> Dictionary:
	var out := {}
	for directed in state.measures.keys():
		var parts := RK.directed_parts(String(directed))
		if parts.size() != 2 or parts[0] != actor_id:
			continue
		out[parts[1]] = state.measures[directed]
	return out


## The measure on `directed` that its imposer holds by ITS OWN act, or null: one it
## imposed, or the retaliation the sim wrote in its name -- not an org's collective
## levy, which Orgs._apply_external_measure() writes on the same key for every
## member and tags "org". That levy is the org's to end (an accession, a
## withdrawal), never one member's to lift (pre-gate B, RECORD 11): this is what a
## lift verb may clear and what a visitor may ask the played nation to lift.
static func own_measure(state, directed: String):
	var terms = state.measures.get(directed)
	if terms == null or String(terms.get("org", "")) != "":
		return null
	return terms


## Whether anything is in force on the pair, in either direction. What the trade
## weight cares about: goods stop moving both ways whichever side imposed.
static func severity_on_pair(state, a: String, b: String) -> float:
	var total := 0.0
	var forward = state.measures.get(RK.directed_key(a, b))
	if forward != null:
		total += float(forward.get("severity", 0.0))
	var back = state.measures.get(RK.directed_key(b, a))
	if back != null:
		total += float(back.get("severity", 0.0))
	return total


## The multiplier a pair's raw gravity weight carries because of measures on it.
## 1.0 for a clean pair, which is every pair in every balance-harness regime --
## and that exactness is what keeps the re-run bit-identical rather than merely
## close, the same construction docs/trade-model.md used for openness.
##
## Read by src/sim/trade.gd's _raw(), in the WITH pass only. That asymmetry is the
## model's central call: the openness counterfactual is "no agreements and no
## measures", so imposing a tariff drops the openness index below 1.0 and takes
## trend growth down through the potential_shift channel infrastructure and
## education already share. Revenue now, trend later -- the actual protectionist
## trade-off, obtained from machinery that was already built and already measured.
static func trade_multiplier(state, a: String, b: String) -> float:
	var severity := severity_on_pair(state, a, b)
	if severity <= 0.0:
		return 1.0
	return maxf(K.MEASURE_TRADE_FLOOR, 1.0 - K.MEASURE_TRADE_BITE * severity)


## Growth damage to `ns` from every measure pointed at it, %/yr, negative or zero.
##
## Scaled by the TARGET's own trade weight on each imposer -- w(target -> imposer),
## not the other way round. That is where V1.3b's directed table earns its keep a
## second time: France sanctioning Luxembourg hurts, because w(LUX->FRA) is 0.257;
## Luxembourg sanctioning France does almost nothing, because w(FRA->LUX) is 0.021.
## An unweighted constant would have made the smallest nation in the roster as
## dangerous as the largest.
##
## `row` is the target's own weight vector BEFORE measures --
## Trade.weights_before_measures() -- passed in rather than computed here for the
## reason Economy.tick_month() snapshots the weight table at all: computed per
## nation inside the tick loop it would read some partners' GDP from this month and
## some from last.
##
## Before-measures, and that is a correction the probe forced rather than a detail.
## Read off the post-measure weight, damage is proportional to the trade that
## SURVIVES, so a full embargo does almost nothing -- and severity above the
## revenue peak of 0.625 became strictly dominated, collecting less AND hurting
## less while costing more trend. The trade a measure DESTROYS is what does the
## damage; the trade that still crosses the border is what pays the tariff. The two
## effects read different weights because they are different quantities, and only
## revenue has the interior maximum.
static func impulse(state, ns, row: Dictionary) -> float:
	var measures := against(state, ns.id)
	if measures.is_empty():
		return 0.0

	var damage := 0.0
	for imposer_id in measures.keys():
		var severity := float(measures[imposer_id].get("severity", 0.0))
		var weight := float(row.get(imposer_id, 0.0))
		damage += K.COERCION_DAMAGE * severity * weight

	return clampf(-damage, -K.COERCION_IMPULSE_MAX, K.COERCION_IMPULSE_MAX)


## Tariff revenue for `actor_id`, as a percent of GDP. Zero unless this nation has
## imposed at least one measure of kind "tariff".
##
## Collected on the tariffed share of external demand, at the measure's severity.
## The weight row is the POST-measure one -- the same table the rest of the model
## reads -- so the base has already been shrunk by the tariff's own bite, and
## revenue therefore has an interior maximum in severity rather than rising
## forever. That Laffer shape falls out of TARIFF_YIELD and MEASURE_TRADE_BITE and
## is authored nowhere; tools/coercion_probe.gd's revenue table is where it is read.
##
## Severity is the only dial. An authored tariff RATE was cut at measurement time:
## the probe showed yield exactly linear in it, because the bite read severity and
## the rate merely scaled the answer, so the two were one intensity written twice.
##
## A "sanction" collects nothing, by construction rather than by a severity of
## zero: an embargo is a refusal to trade, not a levy on trade.
static func tariff_revenue_pct_gdp(state, actor_id: String, row: Dictionary) -> float:
	var measures := imposed_by(state, actor_id)
	if measures.is_empty():
		return 0.0

	var revenue := 0.0
	for target_id in measures.keys():
		var terms: Dictionary = measures[target_id]
		if String(terms.get("kind", "")) != "tariff":
			continue
		revenue += (
			K.TARIFF_YIELD
			* float(terms.get("severity", 0.0))
			* float(row.get(target_id, 0.0))
		)
	return revenue


## The mirror rule: what `target_id` imposes back on `imposer_id`, or an empty
## Dictionary if it does not answer this month.
##
## > [!warning] THE ENTIRE COUNTERPARTY MODEL, and a DECLARED STOPGAP.
## > A fixed fraction of what was imposed, after a fixed delay, once. The target
## > does not weigh its own economy, does not compare this imposer against its
## > other partners, does not escalate beyond the single step, never lifts what it
## > imposed, and never acts first. Nothing about its GDP, sectors, unemployment,
## > growth, government or other pairs is consulted -- tests/test_coercion.gd
## > asserts exactly that, by mutating every one of them and checking the answer
## > does not move.
## >
## > Named rather than approximated, the same shape V1.3a's and V1.3b's stopgaps
## > use, so V1.3e replacing it is a visible test change rather than a silent one.
## > V1.3e opens with the checklist of all three. See ROADMAP.md (retired 2026-10-05 -- the tier docs carry the build order now).
##
## Called by Diplomacy.tick_month(), which already runs for all ten nations and
## whose own comment anticipated exactly this ("V1.3e will have the other nine
## acting through this same path").
##
## `fraction` is DECIDED by the caller at V1.3e, where V1.3c read
## K.RETALIATION_FRACTION here directly. This module builds the terms of a measure
## and says what one does; it does not decide to impose one, which is
## Diplomacy.execute()'s job for the player and _tick_retaliation()'s for the
## nine. Keeping the decision out of here is also what keeps this file free of the
## interest model, which cannot be preloaded from inside trade.gd's own
## dependencies.
static func retaliation_terms(terms: Dictionary, fraction: float, year: int, month: int) -> Dictionary:
	var severity := float(terms.get("severity", 0.0)) * fraction
	# Below the floor, no entry is opened at all. A register entry at severity 0.01
	# is a diplomatic incident on the nation panel and on the map's relations layer
	# that costs the target nothing and the player nothing; refusing to open one is
	# what lets the model say NO rather than only HOW MUCH. V1.3c could not say no.
	if severity < K.RETALIATION_MIN_SEVERITY:
		return {}
	return {
		"action_id": "retaliation",
		"action_name": "Retaliation",
		"kind": terms.get("kind", "tariff"),
		"severity": severity,
		"since_year": year,
		"since_month": month,
		# A retaliation is itself a measure in the register, and without this it
		# would be answered by a counter-retaliation, and that by another. The flag
		# is what bounds the exchange at one exchange rather than relying on
		# RETALIATION_FRACTION < 1 to make an infinite series converge.
		"retaliated": true,
	}


## How many months a measure has been in force. Used by the nation panel, and by
## tick_month() to decide whether the delay has elapsed.
static func months_in_force(terms: Dictionary, year: int, month: int) -> int:
	var since := int(terms.get("since_year", year)) * 12 + int(terms.get("since_month", month))
	return maxi(0, year * 12 + month - since)
