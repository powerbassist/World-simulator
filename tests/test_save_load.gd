extends SceneTree

## Headless test: godot --headless --script res://tests/test_save_load.gd
## Non-zero exit on any failure.
##
## Two things S9's done-when list requires, checked directly:
##   1. Saving mid-term, quitting, and reloading produces byte-identical
##      simulation state -- built the same way test_state_copy.gd stresses
##      duplicate_state(): move every nation off its defaults, tick a few
##      months, then compare the reloaded object field-by-field, enumerated
##      off the object rather than listed, so it needs no edit when a session
##      adds a field.
##   2. Loading a save with an unknown save_version fails with a clear message
##      rather than corrupting anything -- checked against a hand-written
##      bogus save file, not a real one.
##
## Uses real filesystem I/O against user://saves/, per docs/data-architecture.md
## (user:// is the live-state location, res:// is read-only static content).
## The slot names here are test-only and removed again at the end.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Relations = preload("res://src/core/relations.gd")
const Trade = preload("res://src/sim/trade.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Defence = preload("res://src/sim/defence.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const Society = preload("res://src/sim/society.gd")
const SK = preload("res://src/sim/society_constants.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const UK = preload("res://src/sim/unrest_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const Clock = preload("res://src/core/clock.gd")

const ROUNDTRIP_SLOT := "__test_save_load_roundtrip__"
const SECOND_NATION_SLOT := "__test_save_load_roundtrip_deu__"
const TRANSITION_SLOT := "__test_save_load_roundtrip_gbr_transition__"
const SCENARIO_SLOT := "__test_save_load_roundtrip_scenario__"
const DIPLOMACY_SLOT := "__test_save_load_roundtrip_diplomacy__"
const TRADE_SLOT := "__test_save_load_roundtrip_trade__"
const COERCION_SLOT := "__test_save_load_roundtrip_coercion__"
const BLOC_SLOT := "__test_save_load_roundtrip_bloc__"
const BOGUS_SLOT := "__test_save_load_bogus_version__"
const FLOAT_EPS := 1e-6

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return

	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
		_finish()
		return

	Budget.commit(state, {
		"tax_rates_pct": {"income": 27.0, "corporate": 31.0, "vat": 23.0},
		"spending_pct_gdp": {"health": 12.5, "education": 6.5, "defence": 3.0, "pensions": 13.0, "infrastructure": 5.0},
	})
	for _i in range(6):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 17

	_run_roundtrip(state, clock)
	_run_atomic_write(state, clock)
	_run_second_nation_roundtrip(loader)
	_run_transition_roundtrip(loader)
	_run_scenario_roundtrip(loader)
	_run_diplomacy_roundtrip(loader)
	_run_trade_roundtrip(loader)
	_run_coercion_roundtrip(loader)
	_run_bloc_roundtrip(loader)
	_run_agenda_roundtrip(loader)
	_run_defence_roundtrip(loader)
	_run_diary_roundtrip(loader)
	_run_companies_roundtrip(loader)
	_run_regulation_roundtrip(loader)
	_run_ownership_roundtrip(loader)
	_check_society_fields(loader)
	_check_demography_fields(loader)
	_check_unrest_fields(loader)
	_run_unknown_version()
	_cleanup()
	clock.free()  # a Node created off-tree isn't owned by anything; free it explicitly
	_finish()


## V1.2a: SAVE_VERSION did not move (see the plan step's own cold count), but
## a save still has to round-trip for whichever nation is playing -- checked
## against Germany specifically, since a v4-era save format built against one
## nation could still quietly assume something about it that a second nation
## breaks. Lighter than _run_roundtrip(): the reflective field check is the
## point, not another pass over atomic writes or version rejection.
func _run_second_nation_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "DEU")
	if not state.errors.is_empty():
		_fail("new_game(DEU) reported %s" % [state.errors])
		return

	for _i in range(3):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 9

	var save_error := SaveManager.save_game(state, clock, SECOND_NATION_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game(DEU) failed: %s" % save_error)
		return

	var result := SaveManager.load_game(SECOND_NATION_SLOT)
	if not result["ok"]:
		_fail("load_game(DEU) failed on a save this test just wrote: %s" % result["error"])
		return

	var loaded = result["state"]
	if loaded.save_version != GameState.SAVE_VERSION:
		_fail("DEU save round-tripped at save_version %d, expected %d" % [loaded.save_version, GameState.SAVE_VERSION])
	if loaded.player_nation_id != "DEU":
		_fail("loaded DEU save has player_nation_id '%s'" % loaded.player_nation_id)
	_check_pair("GameState[DEU]", state, loaded)
	for id in state.nations.keys():
		if not loaded.nations.has(id):
			_fail("DEU save dropped nation %s" % id)
			continue
		_check_pair("NationState[DEU][%s]" % id, state.nations[id], loaded.nations[id])


## V1.2e: a game begun under a start scenario, through the real SaveManager
## rather than to_dict()/from_dict() alone -- tests/test_scenario.gd covers the
## dictionary pair, this covers the disk path SAVE_VERSION guards. Deliberately
## the case the no-bump argument rests on: the scenario's EFFECTS have to ride
## in the ordinary fields, so that a save carries them whether or not anything
## ever reads scenario_id back.
func _run_scenario_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "DEU", "deu_grand_coalition")
	if not state.errors.is_empty():
		_fail("new_game(DEU, deu_grand_coalition) reported %s" % [state.errors])
		return

	for _i in range(3):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 9

	var save_error := SaveManager.save_game(state, clock, SCENARIO_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game(DEU scenario) failed: %s" % save_error)
		return

	var result := SaveManager.load_game(SCENARIO_SLOT)
	if not result["ok"]:
		_fail("load_game(DEU scenario) failed on a save this test just wrote: %s" % result["error"])
		return

	var loaded = result["state"]
	_check_pair("GameState[DEU scenario]", state, loaded)
	_check_pair("NationState[DEU scenario]", state.player(), loaded.player())

	if loaded.scenario_id != "deu_grand_coalition":
		_fail("a scenario save reloaded as scenario_id '%s'" % loaded.scenario_id)

	# Compared per key rather than as whole Dictionaries: JSON has no integer
	# type, so every seat count comes back as a float and the key order is not
	# preserved. True of every Dictionary in a save since S9, not something a
	# scenario introduced -- but a `!=` here would report it as one.
	var before: Dictionary = state.player().seats_by_party
	var after: Dictionary = loaded.player().seats_by_party
	for party_id in before.keys():
		if int(after.get(party_id, -1)) != int(before[party_id]):
			_fail("a scenario's authored assembly did not survive the disk round trip: '%s' %s -> %s" % [
				party_id, before[party_id], after.get(party_id, "absent"),
			])


## V1.2d: system_id, lose_condition and the head-of-state fields become
## MUTABLE at runtime for the first time -- a version-7 save format never had
## to round-trip a value written after new-game for any of them. Pass a
## transition through Legislature.apply() first, then round-trip, so this
## catches a serializer that only ever saw the new-game value.
func _run_transition_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "GBR")
	if not state.errors.is_empty():
		_fail("new_game(GBR) reported %s" % [state.errors])
		return

	var law = null
	for l in loader.laws:
		if l.id == "abolish_the_monarchy":
			law = l
	if law == null:
		_fail("abolish_the_monarchy not found in data/laws/amendments.json")
		return

	Legislature.apply(state, state.player(), law, loader)

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 3

	var save_error := SaveManager.save_game(state, clock, TRANSITION_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game(GBR post-transition) failed: %s" % save_error)
		return

	var result := SaveManager.load_game(TRANSITION_SLOT)
	if not result["ok"]:
		_fail("load_game(GBR post-transition) failed on a save this test just wrote: %s" % result["error"])
		return

	var loaded = result["state"]
	_check_pair("GameState[GBR post-transition]", state, loaded)
	_check_pair("NationState[GBR post-transition]", state.player(), loaded.player())

	if loaded.player().system_id != "parliamentary_republic":
		_fail("post-transition save round-tripped system_id as '%s', expected parliamentary_republic" % loaded.player().system_id)
	if loaded.player().head_of_state_kind != "elected_president":
		_fail("post-transition save round-tripped head_of_state_kind as '%s', expected elected_president" % loaded.player().head_of_state_kind)


## V1.3a. The reflective check above already walks `relations` and
## `diplo_cooldown_months`, but only proves anything if they are OFF their
## defaults -- an empty cooldown map round-trips as an empty cooldown map
## whether or not it is saved at all. So: act first, then save.
##
## Also checks the claim SAVE_VERSION 9 rests on, directly rather than by
## argument: a save with no `relations` key reads every pair as 0.0, which is
## the WORST relations rather than a neutral default. That is the "would a
## missing field read as something wrong" test game_state.gd's own comment sets,
## and it is why this bump exists where `scenario_id`'s did not.
func _run_diplomacy_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
		return

	var action = null
	for candidate in loader.diplomatic_actions:
		if candidate.cooldown_months > 0 and candidate.preconditions.is_empty():
			action = candidate
			break
	if action == null:
		_fail("no unconditional diplomatic action with a cooldown to act with")
		return

	var result := Diplomacy.execute(state, loader.diplomatic_actions, action, "FRA", "DEU")
	if not result["applied"]:
		_fail("could not take a diplomatic action to save: %s" % [result])
		return

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 3

	var save_error := SaveManager.save_game(state, clock, DIPLOMACY_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game failed on a state with diplomacy: %s" % save_error)
		return

	var loaded_result := SaveManager.load_game(DIPLOMACY_SLOT)
	if not loaded_result["ok"]:
		_fail("load_game failed on a save with diplomacy: %s" % loaded_result["error"])
		return

	var loaded = loaded_result["state"]
	_check_pair("GameState[diplomacy]", state, loaded)
	_check_pair("NationState[FRA diplomacy]", state.player(), loaded.player())

	var key := Relations.key("FRA", "DEU")
	if not loaded.relations.has(key):
		_fail("a save round trip dropped the %s pair entirely" % key)
	elif not _deep_equal(loaded.relations[key], state.relations[key]):
		_fail("%s round-tripped as %s, expected %s" % [key, loaded.relations[key], state.relations[key]])
	if loaded.relations.size() != 45:
		_fail("a save round trip left %d pairs, expected 45" % loaded.relations.size())

	var cooldown := Diplomacy.cooldown_key(action.id, "DEU")
	if not loaded.player().diplo_cooldown_months.has(cooldown):
		_fail("a save round trip dropped the '%s' cooldown" % cooldown)

	# The bump's own justification, checked rather than asserted in a comment.
	var older: Dictionary = state.to_dict()
	older.erase("relations")
	var revived = GameState.from_dict(older)
	if not revived.relations.is_empty():
		_fail("a save with no relations key invented some")
	if not is_zero_approx(Relations.score(revived, "FRA", "DEU")):
		_fail("a save with no relations key did not read as 0.0 -- the bump's premise is wrong")


## V1.3b. The agreement register and the per-partner trade baselines, and the two
## halves of SAVE_VERSION 10's own argument -- which are NOT the same field.
##
## An absent `agreements` reads as {} and that is CORRECT for every version-9
## save, so it would not have earned a bump on its own; that is `scenario_id`'s
## case exactly. An absent `trade_baseline_by_partner` is the opposite: every
## partner's baseline resolves to 0.0, so the impulse reads each partner's whole
## growth rather than its deviation and roughly a third of a point per year
## appears from nowhere. Both are asserted here, because the DIFFERENCE between
## them is the rule game_state.gd's comment states.
func _run_trade_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
		return

	var action = null
	for candidate in loader.diplomatic_actions:
		if String(candidate.effects.get("agreement", {}).get("op", "")) == "enter":
			action = candidate
			break
	if action == null:
		_fail("no 'enter' agreement action to act with")
		return

	if not Diplomacy.execute(state, loader.diplomatic_actions, action, "FRA", "DEU")["applied"]:
		_fail("could not sign an agreement to save")
		return

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 4
	var save_error := SaveManager.save_game(state, clock, TRADE_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game failed on a state with an agreement: %s" % save_error)
		return

	var loaded_result := SaveManager.load_game(TRADE_SLOT)
	if not loaded_result["ok"]:
		_fail("load_game failed on a save with an agreement: %s" % loaded_result["error"])
		return

	var loaded = loaded_result["state"]
	var key := Relations.key("FRA", "DEU")
	if not loaded.agreements.has(key):
		_fail("a save round trip dropped the %s agreement" % key)
		return

	# The terms are the contract, so they have to survive intact -- an agreement
	# whose multiplier round-trips as 1.0 is an agreement that does nothing.
	var before: Dictionary = state.agreements[key]
	var after: Dictionary = loaded.agreements[key]
	if not is_equal_approx(float(after["weight_multiplier"]), float(before["weight_multiplier"])):
		_fail("weight_multiplier round-tripped as %s, expected %s" % [
			after["weight_multiplier"], before["weight_multiplier"],
		])
	for sector in (before["sector_shift"] as Dictionary).keys():
		if not is_equal_approx(float(after["sector_shift"][sector]), float(before["sector_shift"][sector])):
			_fail("sector_shift.%s round-tripped as %s, expected %s" % [
				sector, after["sector_shift"][sector], before["sector_shift"][sector],
			])
	if not is_equal_approx(Trade.openness_index(loaded, "FRA"), Trade.openness_index(state, "FRA")):
		_fail("the openness index does not survive a save round trip")

	# Half one of the bump's argument: agreements alone would NOT have earned it.
	var no_agreements: Dictionary = state.to_dict()
	no_agreements.erase("agreements")
	var without = GameState.from_dict(no_agreements)
	if not without.agreements.is_empty():
		_fail("a save with no agreements key invented some")
	if not is_equal_approx(Trade.openness_index(without, "FRA"), 1.0):
		_fail("a save with no agreements key did not read as 'nothing signed' -- that half of the bump's argument is wrong")

	# Half two, which is the half that DID earn it: the static nation facts the
	# trade weight reads. Absent, every nation loads landlocked and outside the EU,
	# both gravity bonuses vanish, and the weight silently collapses back to the
	# GDP-only vector V1.3b replaced -- a reloaded game running a DIFFERENT trade
	# model from the one that saved it, with nothing to say so.
	var no_facts: Dictionary = state.to_dict()
	for id in (no_facts["nations"] as Dictionary).keys():
		(no_facts["nations"][id] as Dictionary).erase("neighbours")
		(no_facts["nations"][id] as Dictionary).erase("eu_member")
	var stripped = GameState.from_dict(no_facts)
	var before_weights := Trade.weights(state, "FRA")
	var after_weights := Trade.weights(stripped, "FRA")
	var moved := false
	for id in before_weights.keys():
		if not is_equal_approx(float(before_weights[id]), float(after_weights.get(id, 0.0))):
			moved = true
	if not moved:
		_fail("a save with no neighbours/eu_member produced the same trade weights -- the bump's premise is wrong")

	# And the baselines, whose failure is quieter but still real: the fallback in
	# Trade.external_impulse() re-bases a missing partner to its CURRENT growth, so
	# an absent dictionary does not explode -- it silently erases an in-flight
	# external shock, re-zeroing the channel at the moment of loading.
	var shocked = GameState.new_game(loader, "FRA")
	Economy.tick_month(shocked)
	shocked.nations["DEU"].growth_annual_pct -= 4.0
	Economy.tick_month(shocked)
	if is_zero_approx(shocked.player().external_impulse_pct):
		_fail("could not set up an in-flight external impulse to save")
		return
	var no_baselines: Dictionary = shocked.to_dict()
	for id in (no_baselines["nations"] as Dictionary).keys():
		(no_baselines["nations"][id] as Dictionary).erase("trade_baseline_by_partner")
	var rebased = GameState.from_dict(no_baselines)
	Economy.tick_month(rebased)
	if not is_zero_approx(rebased.player().external_impulse_pct):
		_fail("a save with no trade_baseline_by_partner did not re-zero the impulse -- the field's own justification is wrong")


## V1.3c. The directed measure register, and the argument for why this session
## earns NO SAVE_VERSION bump -- asserted rather than claimed in a comment.
##
## Every field V1.3c adds passes the rule game_state.gd states: an absent one reads
## as something CORRECT, not as something silently wrong. `measures` reads as {},
## which is right for every version-10 save because those games could not impose
## one -- `agreements`' case exactly. `coercion_impulse_pct` reads as 0.0, which is
## right because nothing was in force. Contrast the two fields that DID earn 9->10
## above, both of which read as an actively wrong model.
func _run_coercion_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
		return

	var action = null
	for candidate in loader.diplomatic_actions:
		if String(candidate.effects.get("measure", {}).get("op", "")) == "impose":
			action = candidate
			break
	if action == null:
		_fail("no 'impose' measure action to act with")
		return

	if not Diplomacy.execute(state, loader.diplomatic_actions, action, "FRA", "DEU")["applied"]:
		_fail("could not impose a measure to save")
		return
	Economy.tick_month(state)

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 9
	var save_error := SaveManager.save_game(state, clock, COERCION_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game failed on a state with a measure: %s" % save_error)
		return

	var loaded_result := SaveManager.load_game(COERCION_SLOT)
	if not loaded_result["ok"]:
		_fail("load_game failed on a save with a measure: %s" % loaded_result["error"])
		return

	var loaded = loaded_result["state"]
	var directed := Relations.directed_key("FRA", "DEU")
	if not loaded.measures.has(directed):
		_fail("a save round trip dropped the %s measure" % directed)
		return

	# The terms are what was imposed, so they have to survive intact -- a severity
	# that round-trips as 0.0 is a measure that does nothing.
	var before: Dictionary = state.measures[directed]
	var after: Dictionary = loaded.measures[directed]
	for field in ["kind", "severity", "retaliated"]:
		if str(after[field]) != str(before[field]):
			_fail("measure.%s round-tripped as %s, expected %s" % [field, after[field], before[field]])

	# The directed key must survive as a DIRECTED key. JSON keys are strings, so a
	# separator collision would show up here as a measure readable from both sides.
	if loaded.measures.has(Relations.directed_key("DEU", "FRA")):
		_fail("a round trip made the measure readable in both directions")

	# And the effects have to survive with it, or a reloaded game is running a
	# different model from the one that saved it.
	if not is_equal_approx(
		Coercion.trade_multiplier(loaded, "FRA", "DEU"),
		Coercion.trade_multiplier(state, "FRA", "DEU")
	):
		_fail("the coercion trade multiplier does not survive a save round trip")
	if not is_equal_approx(Trade.openness_index(loaded, "FRA"), Trade.openness_index(state, "FRA")):
		_fail("the openness index does not survive a save round trip with a measure")

	# The no-bump argument, both halves, checked the way the bump's own halves are.
	var no_measures: Dictionary = state.to_dict()
	no_measures.erase("measures")
	var without = GameState.from_dict(no_measures)
	if not without.measures.is_empty():
		_fail("a save with no measures key invented some")
	if not is_equal_approx(Trade.openness_index(without, "FRA"), 1.0):
		_fail("a save with no measures key did not read as 'nothing imposed' -- the no-bump argument is wrong")

	var no_impulse: Dictionary = state.to_dict()
	for id in (no_impulse["nations"] as Dictionary).keys():
		(no_impulse["nations"][id] as Dictionary).erase("coercion_impulse_pct")
	var zeroed = GameState.from_dict(no_impulse)
	if zeroed.nations["DEU"].coercion_impulse_pct != 0.0:
		_fail("an absent coercion_impulse_pct did not read as exactly 0.0")

	# V1.3c left an assertion here that SAVE_VERSION was STILL 10, so that a later
	# session raising it had to come and say why. V1.3d is that session, and
	# _run_bloc_roundtrip() below is where it says why. Nothing V1.3c added earns a
	# bump on its own and that is still true -- the three checks above are the
	# argument, and they are what this line has been replaced by rather than
	# deleted. See docs/coercion-model.md and docs/bloc-model.md.


## V1.3d, and the session that answers the assertion V1.3c left above.
##
## SAVE_VERSION 10 -> 11. The rule game_state.gd states is "would a missing field
## read as something WRONG", not "is a field new" -- V1.3b's `agreements` and
## V1.3c's `measures` both read correctly as "nothing yet" and neither earned a
## bump. Three fields here fail that test, and the loud one is not the register:
##
##   - an absent `bloc_base_transfer_pct_gdp` is a France that has never paid into
##     a budget it has always paid into, silently moving the starting deficit every
##     economy constant is measured against;
##   - an absent `start_bloc_burden` reads as 0.0 against a LIVE burden, so a game
##     reloaded while in breach scores that breach as brand new and the europe
##     issue is mis-signed for the rest of the run;
##   - an absent `bloc` register reads as no council and no rules, which for a bloc
##     whose premise is that its rules are always in force is wrong rather than empty.
##
## All three are eu_member/neighbours' case: a reloaded game running a different
## model from the one that saved it. Asserted here rather than argued in a comment.
func _run_bloc_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
		return

	# Get something actually into the register rather than saving the empty shape:
	# an empty rules map round-trips as an empty rules map whether or not it is
	# saved at all, which is the trap docs/diplomacy-model.md's own round-trip
	# check names. Adopt directly, the way the probe does -- Bloc has no public
	# "adopt this now" and should not grow one for a test.
	# By id, not by index: the agenda order is a filename sort and a later session
	# adding data/bloc-proposals/aaa.json would silently move this test onto a
	# proposal with no constraint at all, which would then assert nothing.
	var proposal = null
	for candidate in loader.bloc_proposals:
		if candidate.id == "stability_pact":
			proposal = candidate
			break
	if proposal == null:
		_fail("no stability_pact proposal to adopt")
		return

	state.bloc["rules"][proposal.id] = {
		"name": proposal.proposal_name,
		"field": String(proposal.constraint["field"]),
		"op": String(proposal.constraint["op"]),
		"value": float(proposal.constraint["value"]),
		"tolerance": float(proposal.constraint["tolerance"]),
		"severity": float(proposal.constraint["severity"]),
		"transfer_pct_gdp": 0.0,
		"since_year": state.year,
		"since_month": state.month,
	}
	Bloc.tick_month(state, loader)
	Budget.tick_month(state)
	# After the tick, which counts months_to_next down -- set before it, these
	# would be asserting the tick's arithmetic rather than the round trip's.
	state.bloc["next_index"] = 2
	state.bloc["months_to_next"] = 7

	if is_zero_approx(state.player().bloc_burden):
		_fail("could not set up a live bloc burden to save -- France should be in breach of a 3%% deficit rule")
		return

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 21
	var save_error := SaveManager.save_game(state, clock, BLOC_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game failed on a state with a bloc rule: %s" % save_error)
		return

	var loaded_result := SaveManager.load_game(BLOC_SLOT)
	if not loaded_result["ok"]:
		_fail("load_game failed on a save with a bloc rule: %s" % loaded_result["error"])
		return

	var loaded = loaded_result["state"]
	if not (loaded.bloc.get("rules", {}) as Dictionary).has(proposal.id):
		_fail("a save round trip dropped the %s rule" % proposal.id)
		return
	# The scheduler is the half most likely to round-trip subtly wrong: JSON gives
	# every number back as a float, and a countdown comparing a float against an int
	# would run forever without anything looking broken.
	if typeof(loaded.bloc["next_index"]) != TYPE_INT or int(loaded.bloc["next_index"]) != 2:
		_fail("bloc.next_index round-tripped as %s (%d), expected the int 2" % [
			loaded.bloc["next_index"], typeof(loaded.bloc["next_index"])
		])
	if typeof(loaded.bloc["months_to_next"]) != TYPE_INT or int(loaded.bloc["months_to_next"]) != 7:
		_fail("bloc.months_to_next round-tripped as %s, expected the int 7" % [loaded.bloc["months_to_next"]])

	# And the rule has to still BITE, not merely still exist.
	if not is_equal_approx(Bloc.burden(loaded, loaded.player()), Bloc.burden(state, state.player())):
		_fail("the bloc burden does not survive a save round trip: %.6f vs %.6f" % [
			Bloc.burden(loaded, loaded.player()), Bloc.burden(state, state.player())
		])

	# The bump's argument, all three halves, checked the way 9 -> 10's halves are.
	var no_bloc: Dictionary = state.to_dict()
	no_bloc.erase("bloc")
	var without = GameState.from_dict(no_bloc)
	if not is_zero_approx(Bloc.burden(without, without.player())):
		_fail("a save with no bloc key still produced a burden")
	if is_equal_approx(Bloc.burden(without, without.player()), Bloc.burden(state, state.player())):
		_fail("dropping the bloc register changed nothing -- that half of the bump's premise is wrong")

	var no_transfer: Dictionary = state.to_dict()
	for id in (no_transfer["nations"] as Dictionary).keys():
		(no_transfer["nations"][id] as Dictionary).erase("bloc_base_transfer_pct_gdp")
		(no_transfer["nations"][id] as Dictionary).erase("bloc_transfer_pct_gdp")
	var stripped = GameState.from_dict(no_transfer)
	Budget.recompute(stripped, stripped.player())
	if is_equal_approx(stripped.player().deficit_pct_gdp, state.player().deficit_pct_gdp):
		_fail("a save with no bloc transfer produced the same deficit -- the bump's premise is wrong")

	var no_start: Dictionary = state.to_dict()
	for id in (no_start["nations"] as Dictionary).keys():
		(no_start["nations"][id] as Dictionary).erase("start_bloc_burden")
	var mis_signed = GameState.from_dict(no_start)
	if not is_equal_approx(mis_signed.player().start_bloc_burden, 0.0):
		_fail("an absent start_bloc_burden did not read as 0.0")
	# France's own start_bloc_burden is genuinely 0.0 (nothing was in force at
	# new-game), so the mis-signing this field guards against needs a state where
	# it is NOT -- set one, and check the issue moves when it goes missing.
	state.player().start_bloc_burden = state.player().bloc_burden
	var with_reference: Dictionary = state.to_dict()
	var kept = GameState.from_dict(with_reference)
	(with_reference["nations"]["FRA"] as Dictionary).erase("start_bloc_burden")
	var lost = GameState.from_dict(with_reference)
	if is_equal_approx(
		float(Opinion.issue_satisfaction(kept.player())["europe"]),
		float(Opinion.issue_satisfaction(lost.player())["europe"])
	):
		_fail("dropping start_bloc_burden left the europe issue unchanged -- that half of the bump's premise is wrong")

	if GameState.SAVE_VERSION != 18:
		_fail("SAVE_VERSION is %d -- V1.5b raised it to 17 and V1.5c to 18, so a further bump needs its own recorded reason" % GameState.SAVE_VERSION)


## V1.3f adds two things a save carries and only ONE of them earns the bump. The
## distinction is the whole rule -- "would a missing field read as something
## wrong?" -- so it is asserted rather than argued in a comment.
##
## The loud one: an absent diplo_months_to_act reads as 0, and 0 means ACT NOW.
## Every one of the nine fires in the first month after a reload, a nine-act burst
## a played game cannot produce because the staggered counters are the entire
## mechanism that spreads them. eu_member/neighbours' case: the reloaded game
## behaves differently from the one that saved it, with nothing to say so.
##
## The quiet one: an absent foreign_acts reads as [], which is CORRECT for every
## version-11 save because those games had no agenda to record. `measures`' case at
## V1.3c exactly, and it would not have earned a bump on its own.
func _run_agenda_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")

	# The bump's premise, stated as an inequality rather than a value: whatever the
	# seeded stagger is, it must not be the act-now sentinel for any of the nine, or
	# there is nothing for the missing field to read as wrong.
	var acting_now := 0
	for id in state.nations.keys():
		var ns = state.nations[id]
		if not ns.has_budget and ns.diplo_months_to_act <= 0:
			acting_now += 1
	if acting_now != 0:
		_fail("%d of the nine start at diplo_months_to_act <= 0 -- the seeded stagger is not staggering" % acting_now)

	var stripped_dict: Dictionary = state.to_dict()
	for id in (stripped_dict["nations"] as Dictionary).keys():
		(stripped_dict["nations"][id] as Dictionary).erase("diplo_months_to_act")
	var stripped = GameState.from_dict(stripped_dict)

	var burst := 0
	for id in stripped.nations.keys():
		var ns = stripped.nations[id]
		if not ns.has_budget and ns.diplo_months_to_act <= 0:
			burst += 1
	if burst != 9:
		_fail("a save with no diplo_months_to_act left %d of the nine ready to act, not 9 -- the bump's premise is wrong" % burst)

	# And the other half: foreign_acts absent reads as empty, which is correct, so
	# it is NOT what earned the bump.
	var no_acts: Dictionary = state.to_dict()
	no_acts.erase("foreign_acts")
	var revived = GameState.from_dict(no_acts)
	if not revived.foreign_acts.is_empty():
		_fail("a save with no foreign_acts key invented some")


## V1.3g adds three serialised things and they fall on the rule FOUR different
## ways, which is why this asserts four things rather than one. The rule is
## unchanged: would a missing field read as something WRONG?
##
##   military_capability  LOUD  -- the bump. 0.0 against a France that has spent
##                                2 % of GDP on defence for decades: the cost
##                                divides by it and every reader inverts.
##   pacts                QUIET -- {} is correct for every version-12 save,
##                                because those games could not sign one.
##   deployments/obliged  QUIET -- re-derived next tick from pacts x measures.
##   deployments/chosen   LOUD  -- derivable from nothing.
##
## The obliged/chosen SPLIT is the assertion worth having, because it pins the
## property rather than describing it: a later session that makes obligations
## stateful turns this red and has to come and say why.
func _run_defence_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")

	# One pact, one chosen deployment under it, and one measure on a second ally so
	# the reconciler has an obligation to re-derive.
	Defence.sign_pact(state, "FRA", "DEU", _StubPact.new())
	Defence.sign_pact(state, "FRA", "ITA", _StubPact.new())
	Defence.open_deployment(state, "FRA", "DEU", DefenceK.DEPLOYMENT_CHOSEN, null)
	state.measures[Relations.directed_key("GBR", "ITA")] = {
		"action_id": "probe", "action_name": "Probe", "kind": "tariff",
		"severity": 0.60, "since_year": state.year, "since_month": state.month,
		"retaliated": false,
	}
	Defence.tick_month(state)

	if Defence.deployment_kind(state, "FRA", "ITA") != DefenceK.DEPLOYMENT_OBLIGED:
		_fail("the measure on ITA did not open an obliged deployment -- the fixture is wrong, not the save")
		return
	if is_zero_approx(state.player().deployment_bill_pct_gdp):
		_fail("two deployments produced a zero bill -- the fixture is wrong, not the save")
		return

	var saved: Dictionary = state.to_dict()

	# 1. The bump. An absent capability reads 0.0 and the cost inverts.
	var cost_before := Defence.deployment_cost_pct_gdp(state.player())
	var no_capability: Dictionary = state.to_dict()
	for id in (no_capability["nations"] as Dictionary).keys():
		(no_capability["nations"][id] as Dictionary).erase("military_capability")
	var weakened = GameState.from_dict(no_capability)
	if not is_zero_approx(weakened.player().military_capability):
		_fail("an absent military_capability did not read as 0.0 -- the bump's premise is wrong")
	if is_equal_approx(Defence.deployment_cost_pct_gdp(weakened.player()), cost_before):
		_fail("dropping military_capability left the deployment cost unchanged -- the bump's premise is wrong")

	# 2. Quiet: pacts absent read as nothing signed, which is correct for a
	#    version-12 save. `measures`' case at V1.3c exactly.
	var no_pacts: Dictionary = state.to_dict()
	no_pacts.erase("pacts")
	var unallied = GameState.from_dict(no_pacts)
	if not unallied.pacts.is_empty():
		_fail("a save with no pacts key invented some")

	# 3 and 4. The split. Drop the whole register, tick once, and the obliged entry
	#    must come back while the chosen one must not.
	var no_deployments: Dictionary = saved.duplicate(true)
	no_deployments.erase("deployments")
	var stripped = GameState.from_dict(no_deployments)
	if not stripped.deployments.is_empty():
		_fail("a save with no deployments key invented some")
	Defence.tick_month(stripped)

	if Defence.deployment_kind(stripped, "FRA", "ITA") != DefenceK.DEPLOYMENT_OBLIGED:
		_fail("the OBLIGED deployment did not come back after one tick -- it is supposed to be derived from pacts x measures, and if it is not then this half earns the bump too")
	if Defence.deployment_kind(stripped, "FRA", "DEU") != "":
		_fail("a CHOSEN deployment reappeared out of nothing -- it is derivable from nothing, which is half of what SAVE_VERSION 13 is for")

	if not (stripped.player().deployment_bill_pct_gdp < state.player().deployment_bill_pct_gdp):
		_fail("dropping deployments left the bill at or above its saved value -- the chosen half's loudness is unasserted")


## A pact is signed by a verb in the real game. The test brings its own rather than
## reaching into data/diplomatic-actions/, so the assertions above are about the
## save format and do not fail when the content is retuned.
class _StubPact:
	var id: String = "test_pact"
	var action_name: String = "Test Pact"


func _run_roundtrip(state, clock) -> void:
	var save_error := SaveManager.save_game(state, clock, ROUNDTRIP_SLOT)
	if not save_error.is_empty():
		_fail("save_game failed: %s" % save_error)
		return

	var result := SaveManager.load_game(ROUNDTRIP_SLOT)
	if not result["ok"]:
		_fail("load_game failed on a save this test just wrote: %s" % result["error"])
		return

	if int(result["day"]) != 17:
		_fail("day round-tripped as %s, expected 17" % [result["day"]])

	var loaded = result["state"]
	_check_pair("GameState", state, loaded)

	if loaded.nations.size() != state.nations.size():
		_fail("nation count: original %d, loaded %d" % [state.nations.size(), loaded.nations.size()])
	for id in state.nations.keys():
		if not loaded.nations.has(id):
			_fail("loaded save dropped nation %s" % id)
			continue
		_check_pair("NationState[%s]" % id, state.nations[id], loaded.nations[id])

	if loaded.history.size() != state.history.size():
		_fail("history: original has %d entries, loaded has %d" % [state.history.size(), loaded.history.size()])


## The save is written to a sibling .tmp and renamed into place, so that an
## interrupted write loses the new save rather than the old one. Two observable
## consequences, both checked here, because the failure this guards against —
## a truncated save where a working game used to be — cannot be provoked
## directly without killing the process mid-write.
func _run_atomic_write(state, clock) -> void:
	var temp_path: String = SaveManager._path_for(ROUNDTRIP_SLOT) + SaveManager.TEMP_SUFFIX

	# 1. A completed save leaves no temp behind.
	if FileAccess.file_exists(temp_path):
		_fail("save_game left '%s' behind after a successful write" % temp_path)

	# 2. A temp stranded by an interrupted save is invisible to the slot list and
	#    harmless to the good save sitting next to it -- the point of putting the
	#    suffix after ".json" rather than before it.
	var stranded := FileAccess.open(temp_path, FileAccess.WRITE)
	stranded.store_string("{ truncated")
	stranded.close()

	if SaveManager.list_slots().has(ROUNDTRIP_SLOT + ".json" + SaveManager.TEMP_SUFFIX):
		_fail("list_slots() offered a stranded temp file as a loadable slot")
	if not SaveManager.load_game(ROUNDTRIP_SLOT)["ok"]:
		_fail("a stranded temp file broke loading the good save beside it")

	# 3. Saving again over the stranded temp succeeds rather than failing on it.
	var save_error := SaveManager.save_game(state, clock, ROUNDTRIP_SLOT)
	if not save_error.is_empty():
		_fail("save_game failed when a stranded temp file was present: %s" % save_error)
	if FileAccess.file_exists(temp_path):
		_fail("save_game left '%s' behind on the retry" % temp_path)


func _run_unknown_version() -> void:
	SaveManager._ensure_dir()
	var path: String = SaveManager._path_for(BOGUS_SLOT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"save_version": 999, "day": 1, "game_state": {}}))
	file.close()

	var result := SaveManager.load_game(BOGUS_SLOT)
	if result["ok"]:
		_fail("load_game accepted an unknown save_version instead of failing loudly")
	elif result["error"].is_empty():
		_fail("load_game rejected an unknown save_version but gave no error message")

	# Version 1 specifically. V1.1a split the executive's term from the
	# assembly's and added the coalition fields, so a version-1 save has no
	# coherent reading — it must be refused outright rather than restored with
	# the government silently empty. Named as a case of its own because a
	# superseded version is the one an actual player will have on disk, unlike
	# 999 above.
	var v1 := FileAccess.open(path, FileAccess.WRITE)
	v1.store_string(JSON.stringify({"save_version": 1, "day": 1, "game_state": {}}))
	v1.close()

	var old := SaveManager.load_game(BOGUS_SLOT)
	if old["ok"]:
		_fail("load_game accepted a version-1 save; the government fields would be missing")
	elif old["error"].is_empty():
		_fail("load_game rejected a version-1 save but gave no error message")

	# Version 2 for the same reason one version on: V1.1b made party discipline
	# live state, so a version-2 save carries no party_discipline table and every
	# coalition bonus and censure vote read out of it would be scored against the
	# authored figure rather than the eroded one.
	var v2 := FileAccess.open(path, FileAccess.WRITE)
	v2.store_string(JSON.stringify({"save_version": 2, "day": 1, "game_state": {}}))
	v2.close()

	var pre_discipline := SaveManager.load_game(BOGUS_SLOT)
	if pre_discipline["ok"]:
		_fail("load_game accepted a version-2 save; the discipline table would be missing")
	elif pre_discipline["error"].is_empty():
		_fail("load_game rejected a version-2 save but gave no error message")

	# Version 3 for the same reason one version further on: V1.1c added
	# dissolution's six fields, so a version-3 save carries no dissolution_rule
	# and the player could never dissolve, or read a stale lockout, after a load.
	var v3 := FileAccess.open(path, FileAccess.WRITE)
	v3.store_string(JSON.stringify({"save_version": 3, "day": 1, "game_state": {}}))
	v3.close()

	var pre_dissolution := SaveManager.load_game(BOGUS_SLOT)
	if pre_dissolution["ok"]:
		_fail("load_game accepted a version-3 save; the dissolution fields would be missing")
	elif pre_dissolution["error"].is_empty():
		_fail("load_game rejected a version-3 save but gave no error message")

	# Version 4 for the same reason one version further on: V1.1d added
	# cabinet's six fields, so a version-4 save carries no cabinet table and
	# every portfolio would read vacant, silently, after a load.
	var v4 := FileAccess.open(path, FileAccess.WRITE)
	v4.store_string(JSON.stringify({"save_version": 4, "day": 1, "game_state": {}}))
	v4.close()

	var pre_cabinet := SaveManager.load_game(BOGUS_SLOT)
	if pre_cabinet["ok"]:
		_fail("load_game accepted a version-4 save; the cabinet fields would be missing")
	elif pre_cabinet["error"].is_empty():
		_fail("load_game rejected a version-4 save but gave no error message")

	# Version 5 for the same reason one version further on: V1.2b added
	# political-system fields (system_id, head-of-state, lose_condition,
	# term_limit), so a version-5 save carries no lose_condition and the run
	# could never end.
	var v5 := FileAccess.open(path, FileAccess.WRITE)
	v5.store_string(JSON.stringify({"save_version": 5, "day": 1, "game_state": {}}))
	v5.close()

	var pre_political_systems := SaveManager.load_game(BOGUS_SLOT)
	if pre_political_systems["ok"]:
		_fail("load_game accepted a version-5 save; the political-system fields would be missing")
	elif pre_political_systems["error"].is_empty():
		_fail("load_game rejected a version-5 save but gave no error message")

	# Version 6 for the same reason one version further on: V1.2c added
	# amendment_rule, mutable at runtime (an amendment may entrench its own
	# threshold), so a version-6 save carries no amendment_rule and no
	# amendment would ever be proposable after a load.
	var v6 := FileAccess.open(path, FileAccess.WRITE)
	v6.store_string(JSON.stringify({"save_version": 6, "day": 1, "game_state": {}}))
	v6.close()

	var pre_amendment := SaveManager.load_game(BOGUS_SLOT)
	if pre_amendment["ok"]:
		_fail("load_game accepted a version-6 save; amendment_rule would be missing")
	elif pre_amendment["error"].is_empty():
		_fail("load_game rejected a version-6 save but gave no error message")

	# Version 7 for the same reason one version further on: V1.2d added
	# permits_system_change, and made system_id/lose_condition/head-of-state
	# mutable at runtime for the first time -- a version-7 save carries no
	# permits_system_change and would silently refuse every transition the
	# nation's own data permits.
	var v7 := FileAccess.open(path, FileAccess.WRITE)
	v7.store_string(JSON.stringify({"save_version": 7, "day": 1, "game_state": {}}))
	v7.close()

	var pre_transition := SaveManager.load_game(BOGUS_SLOT)
	if pre_transition["ok"]:
		_fail("load_game accepted a version-7 save; permits_system_change would be missing")
	elif pre_transition["error"].is_empty():
		_fail("load_game rejected a version-7 save but gave no error message")


func _cleanup() -> void:
	var dir := DirAccess.open(SaveManager.SAVE_DIR)
	if dir == null:
		return
	for slot in [ROUNDTRIP_SLOT, SECOND_NATION_SLOT, TRANSITION_SLOT, SCENARIO_SLOT, DIPLOMACY_SLOT, TRADE_SLOT, COERCION_SLOT, BLOC_SLOT, BOGUS_SLOT]:
		for p in [SaveManager._path_for(slot), SaveManager._path_for(slot) + SaveManager.TEMP_SUFFIX]:
			if FileAccess.file_exists(p):
				dir.remove(p)


## Same reflective, enumerate-off-the-object approach as test_state_copy.gd --
## walks whatever fields the class actually has instead of a hand-kept list,
## so it stays correct when a later session adds one.
func _check_pair(where: String, original, loaded) -> void:
	var names := _script_variables(original)
	if names.is_empty():
		_fail("%s: could not enumerate script variables — the reflective check is not running" % where)
		return

	for name in names:
		if name == "errors":
			continue  # new-game diagnostics, deliberately not saved
		if name == "nations":
			continue  # Dictionary of objects, not data -- compared nation-by-nation below
		var a = original.get(name)
		var b = loaded.get(name)
		if not _deep_equal(a, b):
			_fail("%s.%s: original %s, loaded %s" % [where, name, a, b])


func _deep_equal(a, b) -> bool:
	if typeof(a) != typeof(b):
		# int vs float is fine -- JSON has one numeric type and from_dict() casts
		# back to int where the field is declared int; a stray float/int pair
		# elsewhere still compares equal by value.
		if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
			return absf(float(a) - float(b)) < FLOAT_EPS
		return false

	match typeof(a):
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for key in a.keys():
				if not b.has(key) or not _deep_equal(a[key], b[key]):
					return false
			return true
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i in range(a.size()):
				if not _deep_equal(a[i], b[i]):
					return false
			return true
		TYPE_FLOAT:
			return absf(a - b) < FLOAT_EPS
		_:
			return a == b


func _script_variables(obj) -> Array:
	var names: Array = []
	for p in obj.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name: String = p["name"]
		if name == "script" or name.begins_with("_"):
			continue
		names.append(name)
	return names


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_save_load: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)


## U6a adds ONE serialised field and earns NO bump, and the interesting half is
## what it did not add. Three claims, each asserted rather than argued:
##
##   1. `appointments` round-trips. A booking is a command the player issued; a
##      save that lost it would eat that command silently.
##   2. An ABSENT `appointments` reads as "nothing booked", which is CORRECT for
##      every version-13 save because those games had no diary to book into.
##      `measures`' case at V1.3c, down to being player-created state derivable
##      from nothing -- and like `measures` it earns no bump.
##   3. `day` is NOT in the game_state dict at all, and round-trips anyway
##      because save_manager.gd carries clock.day at the payload's top level.
##      This is the assertion worth having rather than the bump: it PINS the
##      property that there is exactly one record of the date, so a later session
##      that folds the day into GameState.to_dict() turns this red and has to
##      come and say why it wants two records of one fact.
##
## The field that WOULD have earned a bump was a spent-days counter -- absent it
## reads 0, and a player eight days into a month reloads with all of them back.
## U6a's probe cut the currency it counted before any of it was written, so the
## question never reached game_state.gd's list at all. docs/calendar-model.md §2.
func _run_diary_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	state.day = 17

	var entry := Calendar.make_entry(
		CalendarK.KIND_DIPLOMATIC, state.year, state.month + 2, 9, "state_visit", "DEU",
		"", "", "", loader.nations["DEU"].leader_person_id
	)
	var booked: Dictionary = Calendar.book(state, entry)
	if not bool(booked["ok"]):
		_fail("diary round trip could not book: %s" % String(booked["error"]))
		return
	# One resolved entry too, so the round trip covers a status the pruner reads
	# rather than only the one it never touches.
	var done := Calendar.make_entry(
		CalendarK.KIND_LAW, state.year, state.month, 3, "", "", "high_earner_surtax"
	)
	state.appointments.append(done)
	Calendar.resolve(state, Calendar.verb_key(done), true)

	var dict: Dictionary = state.to_dict()

	# (3) The day is deliberately absent from the state's own dictionary.
	if dict.has("day"):
		_fail("GameState.to_dict() carries `day` -- that is a second record of a fact save_manager.gd already saves, and the two can disagree")

	var loaded = GameState.from_dict(dict)
	if loaded.appointments.size() != 2:
		_fail("diary round-tripped %d entries, expected 2" % loaded.appointments.size())
		return

	# (1) Both halves, by content rather than by count.
	var still_booked := Calendar.booked(loaded)
	if still_booked.size() != 1:
		_fail("%d bookings survived the round trip, expected 1" % still_booked.size())
	elif String(still_booked[0]["action_id"]) != "state_visit" or String(still_booked[0]["target_id"]) != "DEU":
		_fail("the booking came back as %s -- a save that garbles a command is worse than one that drops it" % [still_booked[0]])
	# U6a carried `person_id` unread against the possibility that U6b would key
	# appointments on people. It did not: a person is the FACE of a target that
	# already exists, so a state visit to Germany IS its leader -- one act, one
	# key. The field is a derived LABEL, written here and read only for display.
	if String(still_booked[0].get("person_id", "MISSING")) == "MISSING":
		_fail("the entry's person_id did not survive the round trip")
	elif String(still_booked[0]["person_id"]) != "DEU_vogler":
		_fail("a booked state visit to DEU carries person_id '%s', expected the leader the diary showed at booking time" % still_booked[0]["person_id"])

	# (2) Absent, and correct rather than silently wrong.
	var without: Dictionary = state.to_dict()
	without.erase("appointments")
	var no_diary = GameState.from_dict(without)
	if not no_diary.appointments.is_empty():
		_fail("an absent appointments register did not read as an empty diary")
	if not Calendar.due(no_diary, no_diary.year + 5, 12, 28).is_empty():
		_fail("an absent diary produced appointments out of nothing -- 'nothing booked' is the only correct reading of a version-13 save")

	_run_person_rekey(loader)


## U6b bumps on a RE-KEY, not on a new field, and this is the assertion that pins
## why. Three NationState fields stopped holding names and started holding person
## ids; nothing was added. The naive reading is that nothing is at risk -- but a
## version-13 save carries the OLD keys, so without the bump all three would load
## as "" while the file itself looked intact, and the game would render a
## government nobody governs. That is `military_capability`'s case at V1.3g and
## `eu_member`/`neighbours` at V1.3b, in their strongest form yet.
##
## The other half is what U6b did NOT add: there is no per-person serialised
## state at all, because a person is pure content -- an id and a name, with every
## relationship expressed by the reference that owns it. The field that would have
## earned this bump on its own, a stored `ns.cabinet_person`, was never written,
## because the probe cut the minister bench that needed it.
func _run_person_rekey(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()
	if ns.pm_person_id == "" or ns.head_of_state_person_id == "":
		_fail("a new game did not seat a head of state and a head of government as person ids")
		return
	if loader.person_name(ns.head_of_state_person_id) == "":
		_fail("the head of state's person id does not resolve to a name")

	var dict: Dictionary = state.to_dict()
	var loaded = GameState.from_dict(dict)
	for field in ["pm_person_id", "head_of_state_person_id", "start_head_of_government_person_id"]:
		if String(loaded.player().get(field)) != String(ns.get(field)):
			_fail("%s did not survive the round trip" % field)

	# The bump's own premise, checked rather than asserted: drop the key a
	# version-13 save would not have and the government stops existing.
	var without: Dictionary = state.to_dict()
	(without["nations"]["FRA"] as Dictionary).erase("pm_person_id")
	var lost = GameState.from_dict(without)
	if lost.player().pm_person_id != "":
		_fail("an absent pm_person_id did not read as empty -- the premise of the bump is wrong")
	if loader.person_name(lost.player().pm_person_id) != "":
		_fail("an absent pm_person_id still resolved to somebody")

	# No per-person register was added, and this pins it: a later session storing
	# a minister turns it red and has to come and say why.
	if dict.has("people") or (dict["nations"]["FRA"] as Dictionary).has("cabinet_person"):
		_fail("a save carries per-person state -- U6b's people are pure content, and a stored minister is the escalation its probe declared in advance")

	if GameState.SAVE_VERSION != 18:
		_fail("SAVE_VERSION is %d -- V1.5b raised it to 17 and V1.5c to 18, so a further bump needs its own recorded reason" % GameState.SAVE_VERSION)


## V1.4a adds five serialised fields and ONE of them earns the bump. The other
## four fail the rule cleanly, and asserting the split is worth more than asserting
## the bump: it pins the property that every firm figure except the register is
## DERIVED, so a later session storing one turns this red and has to say why.
##
## The loud one: an absent `companies` register reads every firm as share 0.0, so
## the partition simply is not there. `military_capability` at V1.3g and
## `eu_member`/`neighbours` at V1.3b -- a reloaded game running a different model
## from the one that saved it, not a game missing a label.
##
## The quiet ones: the bill and both deviation channels are recomputed from the
## register on the first tick after a load and read 0.0 when absent, which is
## exactly right for every version-14 save because those games could not subsidise
## anybody. `measures`' case at V1.3c and `appointments`' at U6a.
func _run_companies_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()
	var target := "FRA_aurignac"

	var subsidy = null
	for a in loader.company_actions:
		if a.id == "strategic_rescue":
			subsidy = a
	if subsidy == null:
		_fail("the strategic_rescue verb is missing, so this roundtrip asserts nothing")
		return

	Companies.execute(state, ns, loader.company_actions, subsidy, target, loader)
	for _m in range(24):
		Companies.tick_month(state, loader)
	Budget.recompute(state, ns)

	var moved_share: float = Companies.share_of(ns, target)
	if is_equal_approx(moved_share, 0.14):
		_fail("the share never moved, so the roundtrip below cannot tell a restored register from a fresh one")

	var dict: Dictionary = state.to_dict()
	var loaded = GameState.from_dict(dict)
	if not is_equal_approx(Companies.share_of(loaded.player(), target), moved_share):
		_fail("a moved share did not survive the round trip")
	if not is_equal_approx(Companies.subsidy_of(loaded.player(), target), 1.0)	:
		_fail("a standing subsidy did not survive the round trip")

	# The bump's premise, checked rather than asserted: drop the key a version-14
	# save would not have and the partition is gone -- every firm produces nothing,
	# while the player is still being billed by a serialised budget line.
	var without: Dictionary = state.to_dict()
	(without["nations"]["FRA"] as Dictionary).erase("companies")
	var lost = GameState.from_dict(without)
	if not lost.player().companies.is_empty():
		_fail("an absent companies register did not read as empty -- the premise of the bump is wrong")
	for company in loader.companies["FRA"]:
		if Companies.output_eur_bn(lost.player(), company) != 0.0:
			_fail("%s still produced something with no register -- the bump's premise is wrong" % company.id)
	if not is_equal_approx(lost.player().subsidy_bill_pct_gdp, state.player().subsidy_bill_pct_gdp):
		_fail("the serialised bill did not survive, so the mismatch this bump is about cannot be shown")

	# The four that earn nothing: recomputed from the register, so a save stripped
	# of all of them comes back to the same numbers on one tick.
	# Compared against a save that kept them and was ticked the same once, not
	# against the pre-load state: the tick also advances the share, so the reference
	# has to take the same step or this would be measuring a month rather than a
	# missing field.
	# Through JSON, not through to_dict() alone. to_dict() hands out the LIVE
	# dictionaries -- from_dict()'s own header says it expects freshly parsed ones --
	# so two states built from two to_dict() calls share one register, and ticking
	# both would advance the same shares twice. The real save path parses, so this
	# does too.
	var no_derived: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	for field in ["subsidy_bill_pct_gdp", "firm_impulse_pct", "firm_jobs_offset_pct", "last_company_result"]:
		(no_derived["nations"]["FRA"] as Dictionary).erase(field)
	var derived = GameState.from_dict(no_derived)
	var reference = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	Companies.tick_month(derived, loader)
	Companies.tick_month(reference, loader)
	if not is_equal_approx(derived.player().subsidy_bill_pct_gdp, reference.player().subsidy_bill_pct_gdp):
		_fail("the bill did not come back on one tick, so it is not derived and would have earned the bump itself")
	if not is_equal_approx(derived.player().firm_impulse_pct, reference.player().firm_impulse_pct):
		_fail("the growth impulse did not come back on one tick")
	if not is_equal_approx(derived.player().firm_jobs_offset_pct, reference.player().firm_jobs_offset_pct):
		_fail("the jobs offset did not come back on one tick")

	# And no baseline is carried. A firm's authored share and headcount are content;
	# a copy in the save would be the same fact in two places, and the copy in the
	# save is the one that would drift when the content was edited.
	if dict.has("companies"):
		_fail("a save carries the company CONTENT -- the baseline is data/companies/, and a stored copy is what a content edit would silently disagree with")
	# V1.4c TURNED THIS RED ON PURPOSE and widened it by exactly one key, which is
	# the change worth recording rather than the widening. `share`, `subsidy` and
	# `state_share` are the three things about a firm that MOVE, and each has exactly
	# one writer -- a subsidy, a subsidy, an ownership op. `name`, `sector`,
	# `headcount` and the AUTHORED share are content and must never appear here, for
	# the reason above: the copy in the save is the one a content edit would silently
	# disagree with. A fourth key still fails, so a later session storing a baseline
	# or a per-firm burden has to come and say why.
	const LIVE_KEYS := ["share", "subsidy", "state_share"]
	for entry in (dict["nations"]["FRA"] as Dictionary)["companies"].values():
		for key in (entry as Dictionary).keys():
			if not LIVE_KEYS.has(key):
				_fail("a serialised register entry carries '%s' beyond the live half" % key)


## V1.4b adds `regulation_burden` and earns NO bump, asserted rather than claimed.
##
## The rule applied literally: a version-15 save comes from a game with no
## `business` laws in it at all, so an absent register reads as every burden 0.0 --
## which is not a soft failure but the TRUTH about that save. `measures` at V1.3c,
## `pacts` at V1.3g and `appointments` at U6a, and the third time the answer has
## been "the games that predate the verb could not use it".
##
## It is still serialised, and that half is not free: a law writes the burden once
## and no tick recomputes it, unlike the three prices above, so a save that dropped
## it would silently repeal every rule the assembly ever passed.
##
## The V1.3c-style assertion at the end is the one worth having: V1.4c's ownership
## register almost certainly bumps, and leaving the number pinned here forces that
## session to come and say why rather than moving it in passing.
func _run_regulation_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	var law = null
	for l in loader.laws:
		if l.id == "emissions_standards":
			law = l
	if law == null:
		_fail("emissions_standards is missing, so this roundtrip asserts nothing")
		return

	Legislature.apply(state, ns, law, loader)
	var burden: float = float(ns.regulation_burden.get("industry", 0.0))
	if burden <= 0.0:
		_fail("no burden stands, so a round trip cannot tell a restored register from a fresh one")
		return
	Companies.tick_month(state, loader)

	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if not is_equal_approx(float(kept.player().regulation_burden.get("industry", 0.0)), burden):
		_fail("a standing burden did not survive the round trip")

	# The half that WOULD have earned a bump if it were true: dropping the field
	# must be visibly wrong, not merely re-derived on the next tick. It is not
	# re-derived from anything -- nothing but a law writes it -- so a stripped save
	# runs an unregulated economy while the passed_law_ids list still says the rule
	# is on the books.
	var without: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(without["nations"]["FRA"] as Dictionary).erase("regulation_burden")
	var lost = GameState.from_dict(without)
	if not lost.player().regulation_burden.is_empty():
		_fail("an absent regulation_burden did not read as empty")
	Companies.tick_month(lost, loader)
	if lost.player().firm_impulse_pct == state.player().firm_impulse_pct:
		_fail("dropping the burden changed nothing -- either it is derived, or it reaches no channel")

	# ...and yet no bump, because a version-15 save never had one to drop. The
	# register is per SECTOR, so V1.4a's assertion about what a company entry may
	# carry is untouched -- a later session moving the burden onto a firm turns that
	# one red and has to come and say why.
	for key in (state.to_dict()["nations"]["FRA"] as Dictionary)["regulation_burden"].keys():
		if not EK.SECTOR_TREND.has(key):
			_fail("regulation_burden is keyed by '%s', which is not a sector" % key)

	if GameState.SAVE_VERSION != 18:
		_fail("SAVE_VERSION is %d -- V1.4b argued it should STAY 15, V1.5a raised it to 16, V1.5b to 17 and V1.5c to 18, so a further bump needs its own recorded reason" % GameState.SAVE_VERSION)


## V1.4c adds `state_share` to every register entry and a fourth cached price, and
## earns NO bump either -- which is not what the row expected, so it is asserted
## rather than assumed.
##
## The rule applied literally a fourth time: an absent `state_share` reads 0.0, "the
## state owns nothing", which is the TRUTH about every version-15 save because those
## games had no ownership verb to use. `measures` at V1.3c, `pacts` at V1.3g,
## `appointments` at U6a and `regulation_burden` at V1.4b.
##
## The two halves that could have earned one, and why neither does:
##
##   `dividend_revenue_pct_gdp` is recomputed from the register on the first tick and
##     reads 0.0 when absent -- the four-prices case V1.4a already argued.
##   The PURCHASE and the WINDFALL are already carried, because they were never a
##     field: Companies.execute() writes `debt_eur_bn`, serialised since the MVP. A
##     capital transaction that needed its own save field would have been the sign it
##     should not have been a balance-sheet write, and this checks the premise.
func _run_ownership_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()
	var target := "FRA_halbert"

	var buy = null
	for a in loader.company_actions:
		if a.id == "full_nationalisation":
			buy = a
	if buy == null:
		_fail("full_nationalisation is missing, so this roundtrip asserts nothing")
		return

	var debt_before: float = ns.debt_eur_bn
	var deficit_before: float = ns.deficit_pct_gdp
	Companies.execute(state, ns, loader.company_actions, buy, target, loader)

	# The price is derived and lands on the debt stock in the same instant, while the
	# deficit does not move at all. Checked here rather than only in
	# tests/test_companies.gd because it is the whole reason this session added no
	# save field: a one-off on the revenue side would have needed one.
	if not (ns.debt_eur_bn > debt_before):
		_fail("nationalising moved no debt, so the purchase reached nothing")
	if ns.deficit_pct_gdp != deficit_before:
		_fail("nationalising moved the deficit in the month it happened -- that closes the loop through a company action's own precondition field")

	for _m in range(3):
		Companies.tick_month(state, loader)
	Budget.recompute(state, ns)
	if ns.dividend_revenue_pct_gdp <= 0.0:
		_fail("a fully state-owned firm pays no dividend, so the round trip below asserts nothing")
		return

	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if not is_equal_approx(Companies.state_share_of(kept.player(), target), 1.0):
		_fail("a standing state holding did not survive the round trip")
	if not is_equal_approx(kept.player().debt_eur_bn, ns.debt_eur_bn):
		_fail("the debt the purchase was paid with did not survive the round trip")

	# The premise of NOT bumping: dropping the key reads as "the state owns nothing",
	# which is a correct save rather than a broken one -- the dividend line goes with
	# it on the next tick, and no figure is left claiming a holding that is not there.
	var without: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	for entry in (without["nations"]["FRA"] as Dictionary)["companies"].values():
		(entry as Dictionary).erase("state_share")
	var lost = GameState.from_dict(without)
	if Companies.state_share_of(lost.player(), target) != 0.0:
		_fail("an absent state_share did not read as 0.0 -- the reason for NOT bumping is wrong")
	Companies.tick_month(lost, loader)
	if lost.player().dividend_revenue_pct_gdp != 0.0:
		_fail("a save with no holdings still paid a dividend")

	# And the fourth price is derived, so a save stripped of it comes back on one
	# tick. Same reference-and-tick shape as the three above it.
	var no_derived: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_derived["nations"]["FRA"] as Dictionary).erase("dividend_revenue_pct_gdp")
	var derived = GameState.from_dict(no_derived)
	var reference = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	Companies.tick_month(derived, loader)
	Companies.tick_month(reference, loader)
	if not is_equal_approx(derived.player().dividend_revenue_pct_gdp, reference.player().dividend_revenue_pct_gdp):
		_fail("the dividend line did not come back on one tick, so it is not derived and would have earned the bump itself")

	if GameState.SAVE_VERSION != 18:
		_fail("SAVE_VERSION is %d -- V1.4c argued it should STAY 15, V1.5a raised it to 16, V1.5b to 17 and V1.5c to 18, so a further bump needs its own recorded reason" % GameState.SAVE_VERSION)


## V1.5a. Three added fields and ONE bump, and as at V1.4a and V1.3g the split is
## the assertion worth having rather than the bump itself.
func _check_society_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")

	# (1) service_quality EARNS the bump. Absent it reads 0.0 against a France that
	# has spent 11.0 % of GDP on health for decades, so the satisfaction term reads a
	# collapse the player did not cause. military_capability's case at V1.3g -- and in
	# its strongest form, because equilibrium-init does NOT rescue it: the check below
	# is that the field does not come back on a tick, which is exactly what separates
	# it from the four derived prices V1.4a and V1.4c argued about.
	if state.player().service_quality.is_empty():
		_fail("service_quality is empty at new game -- the stock has no entry to lose")

	var without: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(without["nations"]["FRA"] as Dictionary).erase("service_quality")
	var lost = GameState.from_dict(without)
	Society.tick_month(lost)
	for key in SK.QUALITY_KEYS:
		if is_equal_approx(
			float(lost.player().service_quality.get(key, 0.0)),
			float(state.player().service_quality.get(key, 0.0))
		):
			_fail("service_quality['%s'] came back on one tick, so it is derived and would NOT have earned the bump" % key)

	# ...and the consequence is the one the bump exists to prevent: a reloaded save
	# scoring a health collapse the player never caused.
	if not (
		float(Opinion.issue_satisfaction(lost.player())["health"])
		< float(Opinion.issue_satisfaction(state.player())["health"])
	):
		_fail("dropping service_quality left the health issue no worse -- the premise of the bump is wrong")

	# (2) corruption earns NOTHING. Absent it reads 0.0, which is the truth about
	# every version-15 save because those games had no `society` law to pass --
	# `measures` at V1.3c, `regulation_burden` at V1.4b. Serialised anyway, and that
	# half is not free: a law writes it once and no tick recomputes it, so the check is
	# that dropping it moves the stock's target rather than that it is merely present.
	state.player().corruption = 0.4
	var carried: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	if not is_equal_approx(float(GameState.from_dict(carried).player().corruption), 0.4):
		_fail("corruption did not round-trip -- a law writes it once and no tick recomputes it")
	(carried["nations"]["FRA"] as Dictionary).erase("corruption")
	var no_corruption = GameState.from_dict(carried)
	if not is_zero_approx(no_corruption.player().corruption):
		_fail("an absent corruption did not read as 0.0 -- the premise of NOT bumping for it is wrong")
	if is_equal_approx(
		Society.quality_target(no_corruption.player(), "health"),
		Society.quality_target(state.player(), "health")
	):
		_fail("dropping corruption changed no target -- either it is derived, or it reaches no channel")

	# (3) start_service_quality earns NOTHING either, and for the OTHER reason on this
	# list: it is recomputed at init from the spending_pct_gdp every nation file already
	# authors, so like a firm's authored share it round-trips through data/nations/.
	# Pinned by re-deriving it rather than by asserting the value.
	var fresh = GameState.new_game(loader, "FRA")
	for key in SK.QUALITY_KEYS:
		if not is_equal_approx(
			float(fresh.player().start_service_quality[key]),
			Society.quality_target(fresh.player(), key)
		):
			_fail("start_service_quality['%s'] is not the equilibrium, so it is authored state rather than a re-derivable reference" % key)

	# The register carries the stock and the reference and NOTHING ELSE per line --
	# V1.4a's own assertion about a company entry, made about this one so a later
	# session storing a per-line rate or an authored target turns it red and has to
	# come and say why.
	for key in (state.to_dict()["nations"]["FRA"] as Dictionary)["service_quality"].keys():
		if not SK.QUALITY_KEYS.has(key):
			_fail("service_quality is keyed by '%s', which is not in QUALITY_KEYS" % key)


## V1.5b. Nine added fields, TWO halves of a bump, and the second half is new on this
## list: it is earned by a KEY ADDED TO A DICTIONARY THAT WAS ALREADY SERIALISED,
## which adds no field at all. Asserting the halves separately is the whole point --
## it pins that growing a registry can bump the version, which V1.5c and V1.5d will
## each be tempted to do.
func _check_demography_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")

	# (1a) The two live shares EARN the bump. Absent they read 0.0, which is not a
	# neutral default but a DIFFERENT MODEL -- eu_member/neighbours' case at V1.3b and
	# military_capability's at V1.3g. The check is on the consequences rather than on
	# the fields: working share 1.0, dependency ratio 0.0, labour force the whole
	# population.
	var without: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(without["nations"]["FRA"] as Dictionary).erase("young_share")
	(without["nations"]["FRA"] as Dictionary).erase("old_share")
	var lost = GameState.from_dict(without)
	if not is_zero_approx(Demography.dependency_ratio(lost.player())):
		_fail("an absent old_share did not read as a dependency ratio of 0.0 -- the premise of the bump is wrong")
	if is_equal_approx(Demography.labour_force(lost.player()), Demography.labour_force(state.player())):
		_fail("dropping the shares left the labour force unchanged -- they reach no channel")

	# ...and they do NOT come back on a tick, which is what separates them from every
	# derived price V1.4a and V1.4c argued about. Equilibrium-init does not rescue
	# them: re-deriving on load would erase a drift the player spent a term living
	# through, which is service_quality's own argument one session earlier.
	Demography.tick_month(lost)
	if is_equal_approx(float(lost.player().old_share), float(state.player().old_share)):
		_fail("old_share came back on one tick, so it is derived and would NOT have earned the bump")

	# (1b) THE SHARPER HALF, and it adds no field. A version-16 save carries
	# service_quality = {"health": ...} and no `pensions` key, because QUALITY_KEYS had
	# one entry when it was written. Society._tick_nation() reads .get(key, 0.0), so
	# the pensions stock starts at ZERO and climbs, while quality_deviation() measures
	# it against a start_service_quality that is also absent and therefore 0.0 -- so
	# the deviation reads as a large and growing POSITIVE. A France whose pension
	# system has just been invented and is improving fast: a windfall the player did
	# not earn, mis-signed for the rest of the run.
	if not SK.QUALITY_KEYS.has("pensions"):
		_fail("pensions is not in QUALITY_KEYS -- V1.5b's second bump half has nothing to be about")
	var version_16: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var fra_16: Dictionary = version_16["nations"]["FRA"]
	(fra_16["service_quality"] as Dictionary).erase("pensions")
	(fra_16["start_service_quality"] as Dictionary).erase("pensions")
	var old_save = GameState.from_dict(version_16)
	Society.tick_month(old_save)
	if Society.quality_deviation(old_save.player(), "pensions") <= 0.0:
		_fail("a version-16 save's absent pensions key did not read as an unearned improvement -- the second half of the bump's premise is wrong")
	if not (
		float(Opinion.issue_satisfaction(old_save.player())["pensions"])
		> float(Opinion.issue_satisfaction(state.player())["pensions"])
	):
		_fail("the missing pensions key did not reach the pensions issue, so the mis-signing is not observable")

	# (2) migration_stance earns NOTHING. Absent it reads 0.0 -- no standing migration
	# policy -- which is the truth about every version-16 save, because those games had
	# no migration law to pass. corruption's case at V1.5a, `measures`' at V1.3c.
	# Serialised anyway for V1.4b's reason, so the check is that dropping it MOVES
	# something rather than that it is merely present.
	state.player().migration_stance = 0.5
	var carried: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	if not is_equal_approx(float(GameState.from_dict(carried).player().migration_stance), 0.5):
		_fail("migration_stance did not round-trip -- a law writes it once and no tick recomputes it")
	(carried["nations"]["FRA"] as Dictionary).erase("migration_stance")
	var no_stance = GameState.from_dict(carried)
	if not is_zero_approx(no_stance.player().migration_stance):
		_fail("an absent migration_stance did not read as 0.0 -- the premise of NOT bumping for it is wrong")
	if not is_zero_approx(Demography.migration_drift(no_stance.player())):
		_fail("a save with no stance still drifted")

	# (3) The four content fields and the two references earn NOTHING, and for the
	# OTHER reason on this list: they are recomputed at init from the imported.cohorts
	# every nation file now carries, so they round-trip through data/nations/ the way a
	# firm's authored share does. Pinned by re-deriving rather than by asserting values.
	var fresh = GameState.new_game(loader, "FRA")
	var fra = loader.nations["FRA"]
	if not is_equal_approx(fresh.player().start_old_share, float(fra.cohorts["old_pct"]) / 100.0):
		_fail("start_old_share is not the imported figure, so it is authored state rather than a re-derivable reference")
	if not is_equal_approx(fresh.player().pop_growth_pct, float(fra.cohorts["pop_growth_pct"])):
		_fail("pop_growth_pct is not the imported figure")

	# The dependency factor is EXACTLY 1.0 at new game for all ten -- not approximately
	# -- which is what makes the whole layer inert until the clock runs, and it is the
	# claim the balance re-run's prediction rests on. Exact equality, test_companies.gd's
	# discipline, because is_zero_approx would hide a seeded transient.
	for id in fresh.nations:
		if Demography.dependency_factor(fresh.nations[id]) != 1.0:
			_fail("%s starts at a dependency factor of %s rather than exactly 1.0" % [
				id, str(Demography.dependency_factor(fresh.nations[id]))
			])


## V1.5c adds seven serialised fields and the bump rests on TWO of them, which is new on
## this list: every previous session's bump rested on one. They are asserted separately
## because they fail the rule by DIFFERENT failures -- one erases accumulated state, the
## other resets a schedule to "now" -- and a single combined check would let either half
## be quietly wrong.
func _check_unrest_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	state.year = 2026
	state.month = 1

	# (1) unrest_pct EARNS IT, and this is service_quality's case at V1.5a. Drive the
	# stock up the way a bad government would, then drop the field and show the crisis
	# ends. Re-deriving on load cannot rescue it: the accumulation IS the state.
	state.player().unrest_pct = 55.0
	state.player().unrest_cooldown_months = 7
	var dict: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	if not is_equal_approx(float(GameState.from_dict(dict).player().unrest_pct), 55.0):
		_fail("unrest_pct did not round-trip")

	var no_unrest: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_unrest["nations"]["FRA"] as Dictionary).erase("unrest_pct")
	var calm = GameState.from_dict(no_unrest)
	if not is_zero_approx(calm.player().unrest_pct):
		_fail("an absent unrest_pct did not read as 0.0 -- the premise of the bump is wrong")
	# The stock does NOT come back on one tick, which is exactly what separates it from
	# the derived prices V1.4a and V1.4c added and is the assertion worth having.
	Unrest.tick_month(calm)
	if calm.player().unrest_pct >= 55.0:
		_fail("unrest_pct recovered on one tick, so it is derivable and the bump is unearned")

	# (2) unrest_cooldown_months EARNS IT SEPARATELY, and it is U6a's diplo_months_to_act
	# case: absent it reads 0, 0 means ACT NOW, so a save reloaded mid-cooldown fires a
	# strike in its first month. Set the stock above the threshold so would_act() is
	# gated on the counter alone -- otherwise this check passes for the wrong reason.
	var mid_dispute: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	if Unrest.would_act(GameState.from_dict(mid_dispute).player()):
		_fail("a save carrying its cooldown still wanted to act -- the counter is not gating")
	(mid_dispute["nations"]["FRA"] as Dictionary).erase("unrest_cooldown_months")
	if not Unrest.would_act(GameState.from_dict(mid_dispute).player()):
		_fail("an absent unrest_cooldown_months did not read as ACT NOW -- the second half of the bump's premise is wrong")

	# (3) gini_index would have earned it a third time, on young_share's reasoning:
	# absent, the live index reads 0.0 against a France sitting at 31.8, so the
	# deviation the inequality term is built on is measured from a country with no
	# inequality at all. Folded into the same bump rather than argued as a third.
	var no_gini: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_gini["nations"]["FRA"] as Dictionary).erase("gini_index")
	if is_equal_approx(
		Unrest.inequality_deviation(GameState.from_dict(no_gini).player()),
		Unrest.inequality_deviation(state.player())
	):
		_fail("dropping gini_index left the inequality deviation unchanged -- that half of the premise is wrong")

	# (4) settlement_stance earns NOTHING -- absent it reads 0.0, no standing settlement,
	# the truth about every version-17 save because those games had no settlement law.
	# migration_stance's case one session earlier, and serialised for its reason, so the
	# check is that dropping it MOVES something rather than that it is merely present.
	#
	# Measured from a DISPLACED state, and the first version of this check was not: on a
	# calm country the target sits at the UNREST_MIN floor with or without a settlement,
	# so both sides read 0.0 and the check passed for a reason that had nothing to do
	# with serialisation. That is society_probe.gd table (c)'s error -- a measurement
	# taken on a path that cannot observe the thing being measured -- and the floor is
	# working as designed: a settlement on a quiet country raises the bar rather than
	# lowering a number that is already at the bottom.
	state.player().unemployment_pct = state.player().start_unemployment_pct + 4.0
	state.player().settlement_stance = 0.5
	var carried: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	if not is_equal_approx(float(GameState.from_dict(carried).player().settlement_stance), 0.5):
		_fail("settlement_stance did not round-trip -- a law writes it once and no tick recomputes it")
	var quiet: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(quiet["nations"]["FRA"] as Dictionary).erase("settlement_stance")
	var no_settlement = GameState.from_dict(quiet)
	if not is_zero_approx(no_settlement.player().settlement_stance):
		_fail("an absent settlement_stance did not read as 0.0 -- the premise of NOT bumping for it is wrong")
	if is_equal_approx(Unrest.unrest_target(no_settlement.player()), Unrest.unrest_target(state.player())):
		_fail("dropping the settlement moved nothing, so serialising it buys nothing either")
	state.player().settlement_stance = 0.0

	# (5) unrest_acts earns NOTHING and is a DISPLAY RECORD. The assertion worth having
	# is not that it round-trips but that src/sim/ never reads it back -- that lives in
	# tests/test_unrest.gd. Here: absent, it reads as an empty list, which is correct for
	# every version-17 save because those games' unions could not act.
	var no_acts: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	no_acts.erase("unrest_acts")
	if not GameState.from_dict(no_acts).unrest_acts.is_empty():
		_fail("an absent unrest_acts did not read as an empty list")

	# (6) The inequality read has NO serialised field of its own, and pinning the absence
	# is the point: it is a pure function of imported.inequality and Demography's drift,
	# so a later session storing an index turns this red and has to come and say why.
	var fra_dict: Dictionary = (JSON.parse_string(JSON.stringify(state.to_dict()))["nations"]["FRA"] as Dictionary)
	for key in fra_dict.keys():
		var name := String(key)
		if name.begins_with("inequality") or name == "gini_deviation":
			_fail("a save carries %s -- the inequality read is a stopgap with no state, and storing one is the escalation the plan declared in advance" % name)

	# The stock is EXACTLY 0.0 at new game for all ten nations -- not approximately --
	# which is what lets a channel that writes a growth impulse ship without moving a
	# figure anywhere. Exact equality, test_companies.gd's discipline.
	var fresh = GameState.new_game(loader, "FRA")
	for id in fresh.nations:
		if fresh.nations[id].unrest_pct != 0.0:
			_fail("%s starts at unrest %s rather than exactly 0.0" % [id, str(fresh.nations[id].unrest_pct)])

	if GameState.SAVE_VERSION != 18:
		_fail("SAVE_VERSION is %d -- V1.5c raised it to 18, so a further bump needs its own recorded reason" % GameState.SAVE_VERSION)
