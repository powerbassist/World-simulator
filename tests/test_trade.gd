extends SceneTree

## V1.3b. The directed trade weight, the per-partner external impulse, the
## openness index, and the agreement register. Model: docs/trade-model.md.
##
## The invariants here are mostly ZEROS -- the impulse under re-weighting, the
## openness index with nothing signed, the harness's ten regimes. That is not a
## thin test: the whole reason the balance re-run this session owed could be
## sharpened from "has anything moved materially?" to "has anything moved at
## all?" is that these quantities are exactly zero by construction rather than
## approximately zero by tuning. If one of them stops being exactly zero, the
## claim that every economy constant measured before V1.3b is still valid stops
## being true with it.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Relations = preload("res://src/core/relations.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const FK = preload("res://src/sim/foreign_policy_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Trade = preload("res://src/sim/trade.gd")
const Economy = preload("res://src/sim/economy.gd")
const TK = preload("res://src/sim/trade_constants.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader
var _state


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_state = GameState.new_game(_loader, PLAYER)
	if not _state.errors.is_empty():
		_failures.append("new_game reported %s" % [_state.errors])
		_finish()
		return

	_check_weights_normalise()
	_check_weights_are_directed()
	_check_weight_reads_every_input()
	_check_impulse_zero_at_baseline()
	_check_impulse_zero_under_reweighting()
	_check_impulse_responds_to_a_partner()
	_check_impulse_is_order_independent()
	_check_openness_is_one_without_an_agreement()
	_check_openness_ignores_a_uniform_rescale()
	_check_openness_ignores_relations()
	_check_agreement_round_trip()
	_check_sector_shift_preserves_gdp()
	_check_counterparty_reads_the_partner()
	_check_counterparty_gate_is_reachable()
	_check_third_parties_untouched()
	_check_bad_fixtures_refused()
	_finish()


# --- the weight ------------------------------------------------------------------

func _check_weights_normalise() -> void:
	for id in _state.nations.keys():
		var w := Trade.weights(_state, id)
		if w.size() != _state.nations.size() - 1:
			_failures.append("%s's weight vector has %d entries, expected %d" % [
				id, w.size(), _state.nations.size() - 1,
			])
		var total := 0.0
		for partner_id in w.keys():
			total += float(w[partner_id])
			if float(w[partner_id]) < 0.0:
				_failures.append("%s -> %s weight is negative" % [id, partner_id])
		if not is_equal_approx(total, 1.0):
			_failures.append("%s's weight vector sums to %f, not 1.0" % [id, total])


## The whole point of the session, and the input V1.3a had nowhere to put: a
## symmetric pair key has one number, a directed weight has two, and the size
## disparity is the ratio between them.
func _check_weights_are_directed() -> void:
	var lux_on_fra: float = float(Trade.weights(_state, "LUX").get("FRA", 0.0))
	var fra_on_lux: float = float(Trade.weights(_state, "FRA").get("LUX", 0.0))
	if lux_on_fra <= fra_on_lux:
		_failures.append(
			"LUX->FRA (%f) is not greater than FRA->LUX (%f) -- the weight is not directed" % [
				lux_on_fra, fra_on_lux,
			]
		)


## Each of the three inputs must actually move the answer. A weight that ignores
## one of them is a weight with a constant hiding in it.
func _check_weight_reads_every_input() -> void:
	var base := Trade.weights(_state, "FRA")

	# Size: DEU is larger than BEL, and FRA borders both and shares the EU with
	# both, so size is the only thing separating them.
	if float(base["DEU"]) <= float(base["BEL"]):
		_failures.append("weight ignores partner size: DEU %f <= BEL %f" % [base["DEU"], base["BEL"]])

	# Relations: raise one pair and its share must rise.
	var moved = GameState.new_game(_loader, PLAYER)
	moved.relations[Relations.key("FRA", "ITA")] = DK.RELATIONS_MAX
	if float(Trade.weights(moved, "FRA")["ITA"]) <= float(base["ITA"]):
		_failures.append("weight ignores relations: ITA's share did not rise when the pair did")

	# Border: NLD and ESP are both EU, neither is a French neighbour in the data
	# except ESP -- so ESP's share must exceed what its size alone would buy.
	var esp_per_gdp: float = float(base["ESP"]) / _state.nations["ESP"].gdp_eur_bn
	var nld_per_gdp: float = float(base["NLD"]) / _state.nations["NLD"].gdp_eur_bn
	if esp_per_gdp <= nld_per_gdp:
		_failures.append("weight ignores the border: bordering ESP is not weighted above non-bordering NLD per unit of GDP")


# --- the impulse -----------------------------------------------------------------

func _check_impulse_zero_at_baseline() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	Economy.tick_month(state)
	if not is_zero_approx(state.player().external_impulse_pct):
		_failures.append("external impulse is %f at new-game, not zero" % state.player().external_impulse_pct)


## THE load-bearing invariant of the per-partner baseline, and the reason
## NationState.trade_baseline_by_partner is a dictionary rather than the single
## scalar it replaced. Under one aggregate baseline, shifting weight toward
## whichever partner happens to have the highest trend produces an impulse with
## nothing having changed abroad -- a free growth boost bought by clicking a
## diplomacy button. Per partner, the sum is zero whatever the weights say.
func _check_impulse_zero_under_reweighting() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for id in state.nations.keys():
		if id == PLAYER:
			continue
		# Deliberately absurd and deliberately uneven: if any weighting at all can
		# manufacture an impulse from partners sitting at their own baselines, this
		# should find it.
		state.relations[Relations.key(PLAYER, id)] = (
			DK.RELATIONS_MAX if id < "F" else DK.RELATIONS_MIN
		)
	Economy.tick_month(state)
	if not is_zero_approx(state.player().external_impulse_pct):
		_failures.append(
			"re-weighting alone produced an impulse of %f -- the baseline is not per-partner" % (
				state.player().external_impulse_pct
			)
		)


## V1.6a MEASURED THIS AGAINST A CONTROL, where it used to compare against zero, and
## the change is forced rather than cosmetic. Until the business cycle existed, every
## partner sat at its own baseline forever, so any non-zero impulse WAS the injected
## recession and its sign could be read directly. Now all nine are moving all the time,
## and eight partners in a mild upswing outweigh one in a 3-point slump: the raw figure
## came back +0.039 and the property under test was never about the raw figure.
##
## The control idiom is already in this file, four functions down -- V1.3b wrote it for
## the order-independence check because the quiet-state residual was "the channel's
## honest magnitude rather than an error to assert away". The cycle turns that residual
## into a real signal and the same answer applies, one session and one order of
## magnitude later.
func _check_impulse_responds_to_a_partner() -> void:
	var control = GameState.new_game(_loader, PLAYER)
	var state = GameState.new_game(_loader, PLAYER)
	Economy.tick_month(control)
	Economy.tick_month(state)
	state.nations["DEU"].growth_annual_pct -= 3.0
	Economy.tick_month(control)
	Economy.tick_month(state)

	var delta: float = state.player().external_impulse_pct - control.player().external_impulse_pct
	if delta >= 0.0:
		_failures.append(
			"a partner recession did not move the impulse down against a control (delta %f)" % delta
		)
	if absf(state.player().external_impulse_pct) >= EK.IMPULSE_MAX_PCT:
		_failures.append("one partner's recession alone reached IMPULSE_MAX")


## Economy.tick_month() resolves every nation's impulse before any nation ticks.
## Computed inside the loop instead, the player would read this month's growth for
## partners sorted before it and last month's for those after -- and the answer
## would depend on Dictionary iteration order. Invisible while every partner sits
## at baseline, which is why it is asserted rather than left to be noticed at
## V1.3c.
func _check_impulse_is_order_independent() -> void:
	var control = GameState.new_game(_loader, PLAYER)
	var forward = GameState.new_game(_loader, PLAYER)
	var backward = GameState.new_game(_loader, PLAYER)
	for state in [control, forward, backward]:
		Economy.tick_month(state)

	# BEL sorts before FRA, ITA after it. If the impulse read live growth mid-loop,
	# one of these would be measured against this month's figure and the other
	# against last month's, and only one of the two checks below would hold.
	#
	# Measured as a DELTA against a control rather than against a closed form: by
	# the second tick every partner has drifted a hundredth of a point off its own
	# baseline, and that residual is the channel's honest quiet-state magnitude
	# rather than an error to assert away.
	forward.nations["BEL"].growth_annual_pct -= 2.0
	backward.nations["ITA"].growth_annual_pct -= 2.0

	# V1.6a: the weights are read BEFORE the tick, not after it, and that is a
	# correctness fix rather than a tidy-up. Economy.tick_month() snapshots the weight
	# table at the top and computes the impulse from it, so the weight this arithmetic
	# needs is the one that existed going IN. Reading it afterwards was off by one
	# month of partner-GDP drift -- about 4 parts in ten thousand while every partner
	# sat at its own baseline, which is inside is_equal_approx(), and about ten times
	# that once the business cycle moves all nine every month. The check was right and
	# it was reading the wrong table.
	var w_bel: float = float(Trade.weights(forward, PLAYER).get("BEL", 0.0))
	var w_ita: float = float(Trade.weights(backward, PLAYER).get("ITA", 0.0))

	for state in [control, forward, backward]:
		Economy.tick_month(state)

	var base: float = control.player().external_impulse_pct

	if not is_equal_approx(forward.player().external_impulse_pct - base, TK.TRADE_BETA * w_bel * -2.0):
		_failures.append("impulse for a partner sorted BEFORE the player is %f over control, expected %f" % [
			forward.player().external_impulse_pct - base, TK.TRADE_BETA * w_bel * -2.0,
		])
	if not is_equal_approx(backward.player().external_impulse_pct - base, TK.TRADE_BETA * w_ita * -2.0):
		_failures.append("impulse for a partner sorted AFTER the player is %f over control, expected %f" % [
			backward.player().external_impulse_pct - base, TK.TRADE_BETA * w_ita * -2.0,
		])


# --- openness --------------------------------------------------------------------

func _check_openness_is_one_without_an_agreement() -> void:
	for id in _state.nations.keys():
		var index := Trade.openness_index(_state, id)
		if not is_equal_approx(index, 1.0):
			_failures.append("%s's openness index is %f with nothing signed, not 1.0" % [id, index])


## The anti-ratchet property. The obvious form of an openness figure -- raw trade
## mass over own GDP -- grows with every nation's GDP forever, so it would drift
## potential_shift upward from time passing alone. As a ratio against a
## no-agreement counterfactual, scaling every economy leaves it untouched.
func _check_openness_ignores_a_uniform_rescale() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var before := Trade.openness_index(state, PLAYER)
	for ns in state.nations.values():
		ns.gdp_eur_bn *= 3.0
		for key in ns.sector_output.keys():
			ns.sector_output[key] = float(ns.sector_output[key]) * 3.0
	if not is_equal_approx(Trade.openness_index(state, PLAYER), before):
		_failures.append("openness moved when every nation's GDP tripled -- it is not scale-free")


## The exploit gate. state_visit is +5 relations with no preconditions and no
## domestic price at all, on a per-target cooldown, so nine of them a year would
## buy a permanent trend gain for nothing if relations moved the openness LEVEL.
## They move the MIX instead, and this is what holds that line.
func _check_openness_ignores_relations() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	for id in state.nations.keys():
		if id != PLAYER:
			state.relations[Relations.key(PLAYER, id)] = DK.RELATIONS_MAX
	var index := Trade.openness_index(state, PLAYER)
	if not is_equal_approx(index, 1.0):
		_failures.append(
			"maxing relations with all nine moved openness to %f -- relations must move the mix, not the level" % index
		)


# --- the register ----------------------------------------------------------------

func _check_agreement_round_trip() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var enter = _agreement_action("enter")
	var exit_action = _agreement_action("exit")
	if enter == null or exit_action == null:
		_failures.append("no enter/exit agreement pair is authored")
		return

	var pair_key := Relations.key(PLAYER, "DEU")
	var signed := Diplomacy.execute(state, _loader.diplomatic_actions, enter, PLAYER, "DEU")
	if not signed["applied"]:
		_failures.append("'%s' was refused against DEU at its resting relations" % enter.id)
		return
	if not state.agreements.has(pair_key):
		_failures.append("signing did not write the register")
		return
	if Trade.openness_index(state, PLAYER) <= 1.0:
		_failures.append("a signed agreement did not raise the openness index")
	if not Trade.has_agreement(state, "DEU", PLAYER):
		_failures.append("has_agreement() is not symmetric in its arguments")

	# The enter verb must now be closed against this pair, or the player can stack
	# agreements on one partner and the "one per pair" rule is a comment.
	if Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, "DEU").has(enter):
		_failures.append("'%s' is still available against a pair that already has an agreement" % enter.id)

	state.player().diplo_cooldown_months.clear()
	var left := Diplomacy.execute(state, _loader.diplomatic_actions, exit_action, PLAYER, "DEU")
	if not left["applied"]:
		_failures.append("'%s' was refused against a pair holding an agreement" % exit_action.id)
	if state.agreements.has(pair_key):
		_failures.append("withdrawing did not clear the register")
	if not is_equal_approx(Trade.openness_index(state, PLAYER), 1.0):
		_failures.append("openness did not return to 1.0 after withdrawal")


## The sectors-sum-to-GDP identity is what makes the composition shift safe to add
## inside the trend loop. If an agreement could break it, every figure downstream
## of GDP would be reading a number that no longer equals its own parts.
func _check_sector_shift_preserves_gdp() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var enter = _agreement_action("enter")
	if enter == null:
		return
	Diplomacy.execute(state, _loader.diplomatic_actions, enter, PLAYER, "DEU")

	for i in range(60):
		Economy.tick_month(state)
		var ns = state.player()
		var total := 0.0
		for key in ns.sector_output.keys():
			total += float(ns.sector_output[key])
		if not is_equal_approx(total, ns.gdp_eur_bn):
			_failures.append("month %d: sectors sum to %f but GDP is %f" % [i + 1, total, ns.gdp_eur_bn])
			return

	# And it must have actually moved the composition, or the test above is
	# asserting an identity over a no-op.
	var control = GameState.new_game(_loader, PLAYER)
	for i in range(60):
		Economy.tick_month(control)
	var moved := absf(
		100.0 * float(state.player().sector_output["industry"]) / state.player().gdp_eur_bn
		- 100.0 * float(control.player().sector_output["industry"]) / control.player().gdp_eur_bn
	)
	if moved < 0.5:
		_failures.append(
			"industry's share moved %.2f pp over five years, under the 0.5 pp the economy panel's own %%.0f%%%% rounding can show" % moved
		)


# --- the counterparty, no longer a stopgap ----------------------------------------

## V1.3b's DECLARED STOPGAP, DISCHARGED at V1.3e -- and this is the rewrite.
##
## Until V1.3e this test asserted the opposite: that gutting Germany's economy left
## `would_accept_agreement()` at exactly the verdict it had before, because the
## rule was `score(a, b) >= AGREEMENT_ACCEPT_MIN` and nothing else. That constant
## no longer exists, so the old test died at parse time rather than at assert time
## -- which is the loudest way it could have gone.
##
## What is asserted now is that the target reads the two things the stopgap could
## not: how much of its own trade runs through the proposer, and what is actually
## on the table.
func _check_counterparty_reads_the_partner() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var thin := {"weight_multiplier": 1.05}
	var generous := {"weight_multiplier": 2.00}

	# The terms on the table must matter. Under the stopgap these were identical,
	# because the verdict never looked at them.
	var thin_score := ForeignPolicy.accept_score(state, PLAYER, "DEU", thin)
	var generous_score := ForeignPolicy.accept_score(state, PLAYER, "DEU", generous)
	if not (generous_score > thin_score):
		_failures.append("a 2.00-multiplier deal is not more attractive than a 1.05 one (%.3f vs %.3f) -- the counterparty is not reading the terms" % [generous_score, thin_score])

	# And the partner's own trade dependence must matter. LUX sends a quarter of
	# its trade to France; France sends a fiftieth of its trade to LUX. The small
	# partner should be the eager one, and that asymmetry is unavailable to any
	# symmetric relations score.
	var lux_wants_fra := ForeignPolicy.accept_score(state, PLAYER, "LUX", generous)
	var state_lux = GameState.new_game(_loader, "LUX")
	var fra_wants_lux := ForeignPolicy.accept_score(state_lux, "LUX", PLAYER, generous)
	if not (lux_wants_fra > fra_wants_lux):
		_failures.append("Luxembourg is not keener to sign with France (%.3f) than France with Luxembourg (%.3f) -- the directed weight is not reaching the verdict" % [lux_wants_fra, fra_wants_lux])


## docs/amendment-model.md's Germany failure, checked for rather than discovered:
## a gate no playable nation can reach is a feature that does not ship. GBR is the
## binding case -- every one of its pairs rests at the floor of the four-tier
## table -- and V1.3e's own probe found ACCEPT_MIN constrained from above by it for
## the second time in this block.
##
## Both halves, exactly as V1.3b asserted them: Britain starts below the gate, and
## relations work opens it.
func _check_counterparty_gate_is_reachable() -> void:
	var state = GameState.new_game(_loader, "GBR")
	var terms := {"weight_multiplier": 1.35}

	var signed_at_rest := 0
	for id in state.nations.keys():
		if id == "GBR":
			continue
		if ForeignPolicy.would_accept_agreement(state, "GBR", String(id), terms):
			signed_at_rest += 1
	if signed_at_rest > 0:
		_failures.append("GBR can already sign %d agreements at rest -- the gate is inert for the nation that sets it" % signed_at_rest)

	# The strongest single positive verb in the content, applied to every pair.
	# At least one partner must then sign, or the feature is shut to one playable
	# nation in three however long the player plays.
	var strongest := 0.0
	for action in _loader.diplomatic_actions:
		if action.effects.get("agreement", {}).is_empty():
			strongest = maxf(strongest, float(action.effects.get("relations", 0.0)))
	for id in state.nations.keys():
		if id == "GBR":
			continue
		var k := Relations.key("GBR", String(id))
		state.relations[k] = float(state.relations[k]) + strongest

	var signed_after := 0
	for id in state.nations.keys():
		if id == "GBR":
			continue
		if ForeignPolicy.would_accept_agreement(state, "GBR", String(id), terms):
			signed_after += 1
	if signed_after <= 0:
		_failures.append(
			"GBR cannot reach ACCEPT_MIN (%.2f) against ANY partner after the strongest verb (+%.1f) -- the feature is closed to it" % [
				FK.ACCEPT_MIN, strongest,
			]
		)


## V1.3a's third-pair rule, extended to the register: signing with one partner
## must not create, clear or alter an agreement anywhere else.
##
## What it must NOT assert is that the partner is untouched. An agreement is
## bilateral -- the register is keyed by the unordered pair, so DEU reads the same
## contract FRA does, and both economies open up. That is the model being right
## rather than a leak: the declared stopgap is that the partner does not DECIDE,
## not that the contract has one side. It is also what makes the transmission
## channel live this session rather than dormant until V1.3c -- the partner's
## trend genuinely moves, so the bracket in the impulse sum is genuinely non-zero.
## One hop and no loop: the player's own trend never feeds back to the partner.
func _check_third_parties_untouched() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var enter = _agreement_action("enter")
	if enter == null:
		return

	var before_gdp: float = state.nations["DEU"].gdp_eur_bn
	var before_sectors: Dictionary = state.nations["DEU"].sector_output.duplicate(true)

	Diplomacy.execute(state, _loader.diplomatic_actions, enter, PLAYER, "DEU")

	if state.agreements.size() != 1:
		_failures.append("signing one agreement produced %d register entries" % state.agreements.size())

	# Signing is not itself an economic event: the terms take effect through the
	# monthly tick, so nothing may move before one has run.
	if not is_equal_approx(state.nations["DEU"].gdp_eur_bn, before_gdp):
		_failures.append("signing with DEU moved DEU's GDP before a month had ticked")
	for key in before_sectors.keys():
		if not is_equal_approx(float(state.nations["DEU"].sector_output[key]), float(before_sectors[key])):
			_failures.append("signing with DEU moved DEU's %s output before a month had ticked" % key)

	# Both sides of the pair, and only those two.
	if Trade.openness_index(state, "DEU") <= 1.0:
		_failures.append("the agreement did not open the partner's economy -- it is keyed by the pair and must read from both sides")
	for id in state.nations.keys():
		if id == PLAYER or id == "DEU":
			continue
		if not is_equal_approx(Trade.openness_index(state, id), 1.0):
			_failures.append("signing FRA-DEU moved %s's openness -- a third nation read a contract it is not party to" % id)


# --- content validation ------------------------------------------------------------

func _check_bad_fixtures_refused() -> void:
	_expect_fixture_error(
		"res://tests/fixtures/actions_bad_sector_sum", "sums to",
		"a sector_shift that does not sum to zero loaded without error"
	)
	_expect_fixture_error(
		"res://tests/fixtures/actions_exit_with_terms", "exit",
		"an exit carrying economic terms loaded without error"
	)


func _expect_fixture_error(actions_dir: String, needle: String, message: String) -> void:
	var fixture_loader := DataLoader.new()
	fixture_loader.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://data/laws",
		"res://data/political-systems", "res://data/scenarios", actions_dir,
	)
	for e in fixture_loader.errors:
		if e.find(needle) != -1:
			return
	_failures.append("%s, or did not name '%s'" % [message, needle])


# --- helpers -----------------------------------------------------------------------

func _agreement_action(op: String):
	for action in _loader.diplomatic_actions:
		if String(action.effects.get("agreement", {}).get("op", "")) == op:
			return action
	return null


func _finish() -> void:
	if _failures.is_empty():
		print("test_trade: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
