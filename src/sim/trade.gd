extends RefCounted

## The trade model: who each nation trades with, how much, and what that does to
## its economy. Built at V1.3b. The model and every constant's rationale is
## docs/trade-model.md; src/sim/trade_constants.gd is the values.
##
## Stateless, and takes no loader. Every function here is a pure read over
## GameState -- there is no Trade.tick_month() and nothing on NationState that this
## module owns, because a derived weight recomputed from live GDP, live relations
## and the agreement register has nothing to store. That is also what lets the
## budget projection run it forward on a copy and get the real answer.
##
## No loader argument, deliberately, and it shapes two things elsewhere.
## Economy.tick_month() is the caller and has twenty-eight call sites; growing it a
## loader parameter to reach static nation facts would have been the largest
## mechanical edit in the session for no model gain. So the two facts the weight
## needs -- org membership and neighbours -- are copied onto NationState at new-game like
## assembly_seats already is, and an agreement's TERMS are stored in the register
## rather than resolved from the action id at read time. The second has an argument
## of its own beyond cost: an agreement is a signed contract, and its terms are what
## was agreed at signing rather than what the content file happens to say later.
##
## Reads state.agreements; does NOT write it. Diplomacy owns that register, because
## it is pair state written by the same player command path relations already use.
## The split keeps rule 3: the two modules talk through GameState and never preload
## each other.

const K = preload("res://src/sim/trade_constants.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const RK = preload("res://src/core/relations.gd")
const Org = preload("res://src/core/org.gd")
const Coercion = preload("res://src/sim/coercion.gd")


## Every nation's directed weight vector, in one snapshot: {actor_id: {partner_id:
## share}}, each vector summing to 1.
##
## Computed once per tick and passed down, rather than looked up per nation inside
## the loop, for the reason Economy.tick_month() already computes the aggregate it
## replaces once: reading it mid-loop would see some partners' GDP from this month
## and some from last, and the answer would depend on Dictionary iteration order.
static func weight_table(state) -> Dictionary:
	var out := {}
	for actor_id in state.nations.keys():
		out[actor_id] = weights(state, actor_id)
	return out


## One nation's view of the other nine, normalised. Directed and asymmetric by
## construction: w(LUX -> FRA) is 12x w(FRA -> LUX), because Luxembourg's trade is
## mostly with France and France's is barely with Luxembourg.
##
## That asymmetry is the third input V1.3a dropped. A symmetric pair key has one
## number and no side to attach a size disparity to; a normalised directed weight
## has two, and the disparity is the ratio between them. See
## docs/diplomacy-model.md section 2.
static func weights(state, actor_id: String) -> Dictionary:
	return _normalise(_raw(state, actor_id, true, true))


## The same vector as if no coercive measure existed, agreements still in force.
##
## V1.3c's, and it exists because the two things a measure does read DIFFERENT
## weights. Revenue is collected on the trade that still crosses the border, which
## is weights() above. Damage is done by the trade DESTROYED, which is this one --
## a nation that has fully decoupled has nothing left to disrupt, so reading damage
## off the post-measure weight made the harshest measure the least harmful and put
## a trap in the content: severity above the revenue peak was strictly dominated,
## collecting less AND hurting less while costing more trend. Measured, then fixed
## here rather than tuned around.
static func weights_before_measures(state, actor_id: String) -> Dictionary:
	return _normalise(_raw(state, actor_id, true, false))


## The openness index: this nation's raw trade mass against what the same mass
## would be with no agreement in force. Exactly 1.0 when the player has signed
## nothing, which is every nation at new-game and every regime in the balance
## harness.
##
## Deliberately a RATIO against a counterfactual rather than a trade-to-GDP figure.
## The obvious form, raw mass over own GDP, has two defects the ratio does not:
## partner GDP levels would sit in the numerator alone and grow at trend forever,
## ratcheting the index up ~20% over the balance harness's fourteen years from time
## passing alone and driving potential_shift toward a clamp that then sets the
## growth rate -- the IMPULSE_MAX failure docs/economy-model.md already writes up,
## committed a second time; and own GDP in the denominator is an unmotivated
## negative feedback on the player's own success. Here partner GDP and the tie
## bonuses appear identically above and below and cancel exactly.
##
## The consequence is deliberate and is the model's central call: RELATIONS MOVE
## THE MIX, ONLY AN AGREEMENT MOVES THE LEVEL. Relations enter both passes, so they
## cancel too. Without that, state_visit -- +5 relations, no preconditions, no
## domestic price at all, cooldown per target -- would buy a permanent trend gain
## against all nine neighbours for nothing, the same exploit shape
## docs/diplomacy-model.md records the V1.3a probe catching before content shipped.
static func openness_index(state, actor_id: String) -> float:
	var neutral := _sum(_raw(state, actor_id, false, false))
	if neutral <= 0.0:
		return 1.0
	return _sum(_raw(state, actor_id, true, true)) / neutral


## External demand, as a trade-weighted sum of partners' deviations from their own
## new-game growth. `table` is one row of weight_table().
##
## Each bracket is measured against THAT PARTNER's baseline, not against one
## aggregate. So the sum is identically zero whenever every partner sits at its own
## baseline, whatever the weights say -- which is what stops re-weighting alone
## from manufacturing an impulse. See NationState.trade_baseline_by_partner.
static func external_impulse(state, ns, row: Dictionary) -> float:
	var out := 0.0
	for partner_id in row.keys():
		var partner = state.nations.get(partner_id)
		if partner == null:
			continue
		var baseline: float = float(ns.trade_baseline_by_partner.get(partner_id, partner.growth_annual_pct))
		out += float(row[partner_id]) * (partner.growth_annual_pct - baseline)
	return K.TRADE_BETA * out


## The per-sector trend shift from every agreement this nation has in force, in
## points per year, keyed by sector. Empty when nothing is signed.
##
## Compositional by construction: each agreement's three shifts sum to zero, so the
## nation's total trend is untouched and only the split between sectors moves. This
## is where "winners and losers at home" lands in the economy; the political half
## lands in the same action's bloc_offset.
static func sector_shift(state, actor_id: String) -> Dictionary:
	var out := {}
	for pair_key in state.agreements.keys():
		if RK.other(String(pair_key), actor_id) == "":
			continue
		var shifts: Dictionary = state.agreements[pair_key].get("sector_shift", {})
		for sector in shifts.keys():
			out[sector] = float(out.get(sector, 0.0)) + float(shifts[sector])
	return out


## Whether a pair has an agreement in force. One per pair: a second would need a
## rule for how two sets of terms compose, and no content this session wants one.
static func has_agreement(state, a: String, b: String) -> bool:
	return state.agreements.has(RK.key(a, b))


## The unnormalised gravity mass toward each partner. `with_effects` is what makes
## openness_index() a ratio rather than a level -- the same table twice, the second
## time with every agreement multiplier AND every coercive measure removed.
##
## V1.3c widened this flag from agreements alone, and that widening is the
## coercion model's central call rather than a tidy-up. Because a measure is
## present in the with-pass and absent from the counterfactual, imposing a tariff
## drops the openness index BELOW 1.0 and takes trend growth down through the same
## potential_shift channel infrastructure and education write. Revenue now, trend
## later: the protectionist trade-off, obtained from machinery already measured
## rather than from a new channel. See docs/coercion-model.md.
static func _raw(state, actor_id: String, with_agreements: bool, with_measures: bool) -> Dictionary:
	var a = state.nations.get(actor_id)
	if a == null:
		return {}

	var out := {}
	# V5.0c, the month's hottest loop (Diplomacy builds ~400 of these vectors a
	# month): the pair key is built once rather than twice, and the agreement and
	# measure registers are not probed while they are empty -- a pair with no
	# entry multiplies by exactly 1.0 there, so skipping the lookup is the same
	# float, not an approximation (the 51-regime table is cmp-identical).
	var any_agreement: bool = with_agreements and not state.agreements.is_empty()
	var any_measure: bool = with_measures and not state.measures.is_empty()
	for partner_id in state.nations.keys():
		if partner_id == actor_id:
			continue
		var b = state.nations[partner_id]

		var value: float = pow(maxf(0.0, b.gdp_eur_bn), K.GRAVITY_EXPONENT)
		# V3.2: co-membership's trade price is content -- the sum over the orgs
		# both nations belong to, read from live membership. eu carries 0.50, the
		# value EU_TRADE_BONUS held; every other org ships 0.0, and multiplying by
		# 1.0 is what the old non-member branch did.
		value *= 1.0 + Org.shared_bonus(state, a.id, b.id, "trade_bonus")
		if a.neighbours.has(partner_id):
			value *= 1.0 + K.BORDER_TRADE_BONUS

		# Floored at zero rather than clamped to a minimum: a pair at relations 0
		# should be able to read as no trade at all, and INTENSITY_SPAN is set so
		# the floor is not reached at any relations value in the readable range.
		var pair_key := RK.key(actor_id, partner_id)
		var relations: float = float(state.relations.get(pair_key, DK.REST_BASE))
		value *= maxf(0.0, 1.0 + K.INTENSITY_SPAN * (relations - DK.REST_BASE) / 100.0)

		if any_agreement:
			if state.agreements.has(pair_key):
				value *= float(state.agreements[pair_key].get("weight_multiplier", 1.0))

		if any_measure:
			# Measures in EITHER direction on the pair, because goods stop moving
			# both ways whichever side imposed. The register is directed so that a
			# tariff and its retaliation stay distinguishable; the trade effect is
			# not, because it is not a fact about who is angry.
			#
			# Exactly 1.0 for a clean pair -- by construction, not by tuning --
			# which is what keeps the balance harness bit-identical: no regime
			# imposes a measure, so this multiplies by one everywhere and both
			# passes stay identical.
			value *= Coercion.trade_multiplier(state, actor_id, partner_id)

		out[partner_id] = value
	return out


static func _sum(raw: Dictionary) -> float:
	var total := 0.0
	for id in raw.keys():
		total += float(raw[id])
	return total


static func _normalise(raw: Dictionary) -> Dictionary:
	var total := _sum(raw)
	if total <= 0.0:
		return raw
	var out := {}
	for id in raw.keys():
		out[id] = float(raw[id]) / total
	return out
