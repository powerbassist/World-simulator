extends SceneTree

## V1.3c. The directed measure register, tariff revenue, coercion damage, the
## agreement break, and the retaliation stopgap. Model: docs/coercion-model.md.
##
## Like tests/test_trade.gd, a good half of the invariants here are ZEROS: the
## trade multiplier on a clean pair, the coercion impulse with nothing imposed,
## the tariff line before the verb is ever used. That is what lets V1.3c's balance
## re-run ask "has anything moved at all?" rather than "has anything moved
## materially?" -- exactly 1.0 and exactly 0.0 by construction, not approximately
## so by tuning. If one of them stops being exact, the claim that every economy
## constant measured before this session is still valid stops being true with it.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Relations = preload("res://src/core/relations.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const Trade = preload("res://src/sim/trade.gd")
const Budget = preload("res://src/sim/budget.gd")
const Economy = preload("res://src/sim/economy.gd")
const CK = preload("res://src/sim/coercion_constants.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")

const PLAYER := "FRA"
const TARGET := "DEU"

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

	_check_directed_key_is_not_the_pair_key()
	_check_nothing_in_force_at_new_game()
	_check_impose_writes_the_directed_entry()
	_check_lift_clears_only_its_own_kind()
	_check_measure_cuts_trade_both_ways()
	_check_measure_lowers_openness()
	_check_damage_reads_the_directed_weight()
	_check_damage_is_monotone_in_severity()
	_check_damage_is_clamped()
	_check_tariff_collects_and_sanction_does_not()
	_check_revenue_peaks_below_max_severity()
	_check_measure_breaks_an_agreement()
	_check_retaliation_is_decided()
	_check_retaliation_still_fires()
	_check_retaliation_converges()
	_check_third_parties_untouched()
	_check_bad_fixtures_refused()
	_finish()


# --- the key -----------------------------------------------------------------------

## The directed key must be a different shape from the symmetric one, or a
## register entry could be read as a relations pair and vice versa.
func _check_directed_key_is_not_the_pair_key() -> void:
	if Relations.directed_key("FRA", "DEU") == Relations.directed_key("DEU", "FRA"):
		_failures.append("directed_key() is symmetric -- FRA>DEU and DEU>FRA collide")
	if Relations.directed_key("FRA", "DEU") == Relations.key("FRA", "DEU"):
		_failures.append("directed_key() and key() produce the same string")
	# other() must refuse a directed key rather than silently splitting one.
	if Relations.other(Relations.directed_key("FRA", "DEU"), "FRA") != "":
		_failures.append("Relations.other() parsed a DIRECTED key -- the separators are not distinct")
	var parts := Relations.directed_parts(Relations.directed_key("FRA", "DEU"))
	if parts != ["FRA", "DEU"]:
		_failures.append("directed_parts() did not round-trip: %s" % [parts])
	if not Relations.directed_parts(Relations.key("FRA", "DEU")).is_empty():
		_failures.append("directed_parts() parsed a SYMMETRIC key")


# --- the exact zeros ----------------------------------------------------------------

func _check_nothing_in_force_at_new_game() -> void:
	if not _state.measures.is_empty():
		_failures.append("a new game starts with measures in force: %s" % [_state.measures])

	for a in _state.nations.keys():
		for b in _state.nations.keys():
			if a == b:
				continue
			var m := Coercion.trade_multiplier(_state, a, b)
			if m != 1.0:
				_failures.append("clean pair %s/%s has trade multiplier %.17f, not exactly 1.0" % [a, b, m])
				return

	for ns in _state.nations.values():
		var impulse := Coercion.impulse(_state, ns, Trade.weights_before_measures(_state, ns.id))
		if impulse != 0.0:
			_failures.append("%s has coercion impulse %.17f with nothing imposed" % [ns.id, impulse])

	var player = _state.player()
	Budget.recompute(_state, player)
	if float(player.revenue_pct_gdp.get("tariffs", 0.0)) != 0.0:
		_failures.append("the tariff revenue line is non-zero with nothing imposed")


# --- the register --------------------------------------------------------------------

func _check_impose_writes_the_directed_entry() -> void:
	var state = _fresh()
	var action = _measure_action("impose", "tariff")
	if action == null:
		_failures.append("no impose/tariff action is authored")
		return

	Diplomacy.execute(state, _loader.diplomatic_actions, action, PLAYER, TARGET)

	if not state.measures.has(Relations.directed_key(PLAYER, TARGET)):
		_failures.append("impose did not write %s>%s" % [PLAYER, TARGET])
		return
	if state.measures.has(Relations.directed_key(TARGET, PLAYER)):
		_failures.append("impose wrote the REVERSE direction too -- the register is not directed")

	var terms: Dictionary = state.measures[Relations.directed_key(PLAYER, TARGET)]
	if String(terms.get("kind", "")) != "tariff":
		_failures.append("the register did not carry the action's kind")
	if bool(terms.get("retaliated", true)):
		_failures.append("a freshly imposed measure is already flagged retaliated")


## The content bug this test exists to prevent: with a single "measure_active"
## field, lift_sanctions would clear a tariff, because the precondition could ask
## whether the pair was coerced but not HOW.
func _check_lift_clears_only_its_own_kind() -> void:
	var state = _fresh()
	var impose = _measure_action("impose", "tariff")
	var lift_other = _lift_action_for("sanction")
	if impose == null or lift_other == null:
		_failures.append("missing impose/tariff or lift-for-sanction content")
		return

	Diplomacy.execute(state, _loader.diplomatic_actions, impose, PLAYER, TARGET)
	var available: Array = Diplomacy.available(
		state, _loader.diplomatic_actions, PLAYER, TARGET
	)
	if available.has(lift_other):
		_failures.append("the sanction lift is offered against a TARIFF -- one lift can clear the other kind")

	var lift_own = _lift_action_for("tariff")
	if lift_own == null or not available.has(lift_own):
		_failures.append("the tariff lift is not offered against a tariff in force")
		return
	Diplomacy.execute(state, _loader.diplomatic_actions, lift_own, PLAYER, TARGET)
	if state.measures.has(Relations.directed_key(PLAYER, TARGET)):
		_failures.append("lift did not clear the directed entry")


# --- trade --------------------------------------------------------------------------

## The register is directed; the trade effect is not. Goods stop moving both ways
## whichever side imposed, so the multiplier must be identical read from either.
func _check_measure_cuts_trade_both_ways() -> void:
	var state = _fresh()
	_impose(state, PLAYER, TARGET, "sanction", 1.0)

	var forward := Coercion.trade_multiplier(state, PLAYER, TARGET)
	var backward := Coercion.trade_multiplier(state, TARGET, PLAYER)
	if not is_equal_approx(forward, backward):
		_failures.append("the trade multiplier is directional: %.4f one way, %.4f the other" % [forward, backward])
	if forward >= 1.0:
		_failures.append("a measure at full severity did not cut the pair's trade")

	var floored = _fresh()
	_impose(floored, PLAYER, TARGET, "sanction", 1.0)
	_impose(floored, TARGET, PLAYER, "sanction", 1.0)
	if Coercion.trade_multiplier(floored, PLAYER, TARGET) < CK.MEASURE_TRADE_FLOOR:
		_failures.append("stacked measures drove the multiplier under MEASURE_TRADE_FLOOR")


## The model's central call: the openness counterfactual is "no agreements AND no
## measures", so imposing a tariff costs trend growth. If this stops holding, the
## protectionist trade-off is gone and a tariff is free money.
func _check_measure_lowers_openness() -> void:
	var state = _fresh()
	if not is_equal_approx(Trade.openness_index(state, PLAYER), 1.0):
		_failures.append("openness is not exactly 1.0 with nothing in force")

	_impose(state, PLAYER, TARGET, "tariff", 0.625)
	if Trade.openness_index(state, PLAYER) >= 1.0:
		_failures.append("imposing a tariff did not lower the imposer's openness index")


# --- damage ---------------------------------------------------------------------------

## Where V1.3b's directed weight table earns its keep a second time. France
## sanctioning Luxembourg must hurt far more than Luxembourg sanctioning France,
## because w(LUX->FRA) is an order of magnitude above w(FRA->LUX).
func _check_damage_reads_the_directed_weight() -> void:
	var big = _fresh()
	_impose(big, "FRA", "LUX", "sanction", 1.0)
	var to_lux := Coercion.impulse(big, big.nations["LUX"], Trade.weights_before_measures(big, "LUX"))

	var small = _fresh()
	_impose(small, "LUX", "FRA", "sanction", 1.0)
	var to_fra := Coercion.impulse(small, small.nations["FRA"], Trade.weights_before_measures(small, "FRA"))

	if absf(to_lux) <= absf(to_fra):
		_failures.append("FRA>LUX (%.3f) does not out-damage LUX>FRA (%.3f) -- the directed weight is not being read" % [to_lux, to_fra])
	if absf(to_lux) < 4.0 * absf(to_fra):
		_failures.append("the FRA>LUX / LUX>FRA damage ratio is only %.1fx -- far below the weights' own 12x" % [absf(to_lux) / maxf(absf(to_fra), 1e-9)])


## Damage must rise with severity all the way to the ceiling. Read off the
## POST-measure weight it did not: a full embargo destroyed the trade it was
## damaging through, so every severity past the revenue peak was strictly
## dominated and the content had a trap in it. Measured before content existed.
func _check_damage_is_monotone_in_severity() -> void:
	var previous := 0.0
	for severity in [0.2, 0.4, 0.625, 0.8, 1.0]:
		var state = _fresh()
		_impose(state, PLAYER, TARGET, "sanction", severity)
		var damage: float = absf(Coercion.impulse(
			state, state.nations[TARGET], Trade.weights_before_measures(state, TARGET)
		))
		if damage <= previous:
			_failures.append("damage did not rise from severity %.3f: %.4f after %.4f" % [severity, damage, previous])
			return
		previous = damage


func _check_damage_is_clamped() -> void:
	var state = _fresh()
	for id in state.nations.keys():
		if id != TARGET:
			_impose(state, id, TARGET, "sanction", 1.0)
	var damage := Coercion.impulse(
		state, state.nations[TARGET], Trade.weights_before_measures(state, TARGET)
	)
	if absf(damage) > CK.COERCION_IMPULSE_MAX:
		_failures.append("nine simultaneous embargoes produced %.3f, past COERCION_IMPULSE_MAX %.3f" % [damage, CK.COERCION_IMPULSE_MAX])


# --- revenue -----------------------------------------------------------------------------

## An embargo is a refusal to trade, not a levy on trade. The kind decides, not a
## severity of zero.
func _check_tariff_collects_and_sanction_does_not() -> void:
	var levy = _fresh()
	_impose(levy, PLAYER, TARGET, "tariff", 0.625)
	var collected := Coercion.tariff_revenue_pct_gdp(levy, PLAYER, Trade.weights(levy, PLAYER))
	if collected <= 0.0:
		_failures.append("a tariff collected nothing")

	var embargo = _fresh()
	_impose(embargo, PLAYER, TARGET, "sanction", 1.0)
	if Coercion.tariff_revenue_pct_gdp(embargo, PLAYER, Trade.weights(embargo, PLAYER)) != 0.0:
		_failures.append("a sanction collected revenue")

	# And it must reach the budget, not just the model.
	Budget.recompute(levy, levy.player())
	if not is_equal_approx(float(levy.player().revenue_pct_gdp.get("tariffs", 0.0)), collected):
		_failures.append("the tariff line on the budget does not match Coercion's own figure")
	if float(levy.player().revenue_pct_gdp.get("tariffs", 0.0)) <= 0.0:
		_failures.append("tariff revenue never reached ns.revenue_pct_gdp")


## The Laffer curve, and it is authored nowhere -- it falls out of TARIFF_YIELD
## and MEASURE_TRADE_BITE, because revenue is collected on the trade that survives
## the tariff. If this stops holding, the two constants have drifted apart and the
## content's "0.625 is the revenue-maximising severity" note is a lie.
func _check_revenue_peaks_below_max_severity() -> void:
	var peak = _fresh()
	_impose(peak, PLAYER, TARGET, "tariff", 1.0 / (2.0 * CK.MEASURE_TRADE_BITE))
	var at_peak := Coercion.tariff_revenue_pct_gdp(peak, PLAYER, Trade.weights(peak, PLAYER))

	var maxed = _fresh()
	_impose(maxed, PLAYER, TARGET, "tariff", CK.MAX_MEASURE_SEVERITY)
	var at_max := Coercion.tariff_revenue_pct_gdp(maxed, PLAYER, Trade.weights(maxed, PLAYER))

	if at_peak <= at_max:
		_failures.append("revenue does not peak below max severity (%.4f at the peak, %.4f at the ceiling) -- there is no Laffer curve" % [at_peak, at_max])


# --- the agreement break -----------------------------------------------------------------

## docs/trade-model.md booked agreement expiry to this session: "no agreement
## duration or expiry -- V1.3c owns it, via a sanction breaking one".
func _check_measure_breaks_an_agreement() -> void:
	var state = _fresh()
	var enter = _agreement_action("enter")
	var impose = _measure_action("impose", "sanction")
	if enter == null or impose == null:
		_failures.append("missing agreement-enter or measure-impose content")
		return

	Diplomacy.execute(state, _loader.diplomatic_actions, enter, PLAYER, TARGET)
	if not state.agreements.has(Relations.key(PLAYER, TARGET)):
		_failures.append("the agreement fixture did not sign -- cannot test the break")
		return

	Diplomacy.execute(state, _loader.diplomatic_actions, impose, PLAYER, TARGET)
	if state.agreements.has(Relations.key(PLAYER, TARGET)):
		_failures.append("imposing a measure did not break the agreement on the same pair")


# --- the counterparty, no longer a stopgap -------------------------------------------------

## V1.3c's DECLARED STOPGAP, DISCHARGED at V1.3e -- and this is the rewrite.
##
## Until V1.3e this asserted that gutting the target's economy and moving a third
## pair left the answered severity at exactly RETALIATION_FRACTION of what was
## imposed. It went red on the first run after the interest model landed, with its
## own message saying so.
##
## Replaced by the property the decision actually has, which is stronger than
## "something moved": THE ANSWER IS SCALED BY DEPENDENCE, BOTH WAYS ROUND. A small
## nation that depends heavily on a large one answers barely at all, because
## answering costs it more than it collects.
func _check_retaliation_is_decided() -> void:
	var state = _fresh()

	# France against Luxembourg, and Luxembourg against France. LUX sends a quarter
	# of its trade to FRA; FRA sends a fiftieth of its trade to LUX -- the 12.1x
	# asymmetry docs/coercion-model.md measured for damage, now reaching the answer.
	var lux_answers := ForeignPolicy.retaliation_fraction(state, PLAYER, "LUX", CK.RETALIATION_FRACTION)
	var fra_answers := ForeignPolicy.retaliation_fraction(state, "LUX", PLAYER, CK.RETALIATION_FRACTION)

	if not (fra_answers > lux_answers):
		_failures.append(
			"France answers Luxembourg at %.4f and Luxembourg answers France at %.4f -- the answer is not scaled by dependence" % [
				fra_answers, lux_answers,
			]
		)
	if fra_answers > CK.RETALIATION_FRACTION + 1.0e-9:
		_failures.append("an answer of %.4f exceeded the ceiling of %.2f" % [fra_answers, CK.RETALIATION_FRACTION])

	# And the decision must be able to say NO, which V1.3c could not: below the
	# floor no entry is opened, so a token measure is not recorded as a diplomatic
	# incident that costs nobody anything.
	var trivial := Coercion.retaliation_terms({"severity": 1.0, "kind": "tariff"}, 0.001, 2026, 1)
	if not trivial.is_empty():
		_failures.append("an answer below RETALIATION_MIN_SEVERITY still opened a register entry")


## The other half of the discharge: an answer must still actually fire between
## partners who matter to each other, or "decided" would be a way of shipping
## nothing. Germany answers France.
func _check_retaliation_still_fires() -> void:
	var fired := _retaliation_severity(func(_s): pass)
	if is_zero_approx(fired):
		_failures.append("no retaliation fired at all between FRA and %s" % TARGET)


## The mirror fires ONCE per measure, flagged in the register. Convergence is
## structural rather than a consequence of RETALIATION_FRACTION < 1, and this is
## what proves the flag holds: a register that grew every month would be
## docs/economy-model.md's IMPULSE_MAX failure with a new name.
func _check_retaliation_converges() -> void:
	var state = _fresh()
	state.year = 2026
	state.month = 1
	_impose(state, PLAYER, TARGET, "tariff", 0.625, false)

	for i in range(36):
		state.month = (i + 1) % 12 + 1
		state.year = 2026 + (i + 1) / 12
		Diplomacy.tick_month(state, _loader)

	if state.measures.size() != 2:
		_failures.append("after 36 months the register holds %d entries, not 2 -- the exchange ratchets" % state.measures.size())
	if not state.measures.has(Relations.directed_key(TARGET, PLAYER)):
		_failures.append("the target never retaliated")


func _check_third_parties_untouched() -> void:
	var state = _fresh()
	_impose(state, PLAYER, TARGET, "sanction", 1.0)
	Economy.tick_month(state)

	for id in state.nations.keys():
		if id == PLAYER or id == TARGET:
			continue
		if state.nations[id].coercion_impulse_pct != 0.0:
			_failures.append("%s took coercion damage from a %s>%s measure it is not party to" % [id, PLAYER, TARGET])
			return


# --- content validation ----------------------------------------------------------------

func _check_bad_fixtures_refused() -> void:
	_expect_fixture_error(
		"res://tests/fixtures/actions_lift_with_terms", "lift",
		"a lift carrying terms loaded without error"
	)
	_expect_fixture_error(
		"res://tests/fixtures/actions_measure_rate", "tariff_rate_pct",
		"a measure carrying a tariff_rate_pct loaded without error"
	)
	_expect_fixture_error(
		"res://tests/fixtures/actions_measure_and_agreement", "measure",
		"an action carrying both an agreement and a measure loaded without error"
	)


func _expect_fixture_error(actions_dir: String, needle: String, message: String) -> void:
	var fixture_loader := DataLoader.new()
	fixture_loader.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://data/eu_parliament.json", "res://data/laws",
		"res://data/political-systems", "res://data/scenarios", actions_dir,
	)
	for e in fixture_loader.errors:
		if e.find(needle) != -1:
			return
	_failures.append("%s, or did not name '%s'" % [message, needle])


# --- helpers ------------------------------------------------------------------------------

func _fresh():
	return GameState.new_game(_loader, PLAYER)


## Write the register directly, the way tools/coercion_probe.gd does. Most checks
## here are about the model rather than the content, and going through execute()
## would tie every assertion to whatever severity the shipped verbs happen to use.
func _impose(state, from: String, to: String, kind: String, severity: float, retaliated := true) -> void:
	state.measures[Relations.directed_key(from, to)] = {
		"action_id": "test",
		"action_name": "Test",
		"kind": kind,
		"severity": severity,
		"since_year": state.year,
		"since_month": state.month,
		"retaliated": retaliated,
	}


## Run one measure to its retaliation and report the severity that came back.
## `mutate` is applied after the measure is written and before the clock moves.
func _retaliation_severity(mutate: Callable) -> float:
	var state = _fresh()
	state.year = 2026
	state.month = 1
	_impose(state, PLAYER, TARGET, "tariff", 0.625, false)
	mutate.call(state)

	for i in range(CK.RETALIATION_DELAY_MONTHS + 2):
		state.month = (i + 1) % 12 + 1
		state.year = 2026 + (i + 1) / 12
		Diplomacy.tick_month(state, _loader)

	var back = state.measures.get(Relations.directed_key(TARGET, PLAYER))
	if back == null:
		return 0.0
	return float(back.get("severity", 0.0))


func _measure_action(op: String, kind: String):
	for action in _loader.diplomatic_actions:
		var m: Dictionary = action.effects.get("measure", {})
		if String(m.get("op", "")) == op and String(m.get("kind", "")) == kind:
			return action
	return null


## The lift verb whose precondition names this kind -- "tariff_active" or
## "sanction_active". Found by the precondition rather than by id, so the test
## does not hardcode content names.
func _lift_action_for(kind: String):
	for action in _loader.diplomatic_actions:
		if String(action.effects.get("measure", {}).get("op", "")) != "lift":
			continue
		for cond in action.preconditions:
			if String(cond["field"]) == "%s_active" % kind:
				return action
	return null


func _agreement_action(op: String):
	for action in _loader.diplomatic_actions:
		if String(action.effects.get("agreement", {}).get("op", "")) == op:
			return action
	return null


func _finish() -> void:
	if _failures.is_empty():
		print("test_coercion: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
