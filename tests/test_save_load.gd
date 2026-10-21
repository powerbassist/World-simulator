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

## suite-exclusive: real filesystem I/O against user://saves/

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Media = preload("res://src/sim/media.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Credit = preload("res://src/sim/credit.gd")
const CreditK = preload("res://src/sim/credit_constants.gd")
const Tax = preload("res://src/sim/tax.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const CampaignK = preload("res://src/sim/campaign_constants.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const Events = preload("res://src/sim/events.gd")
const ElectoralSystems = preload("res://src/sim/electoral_systems.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Programme = preload("res://src/sim/programme.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const EconomyC = preload("res://src/sim/economy_constants.gd")
const NationState = preload("res://src/core/nation_state.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const JudiciaryK = preload("res://src/sim/judiciary_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Relations = preload("res://src/core/relations.gd")
const Trade = preload("res://src/sim/trade.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const Orgs = preload("res://src/sim/orgs.gd")
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
const NETWORK_SLOT := "__test_save_load_roundtrip_network__"
const TRADE_SLOT := "__test_save_load_roundtrip_trade__"
const COERCION_SLOT := "__test_save_load_roundtrip_coercion__"
const BLOC_SLOT := "__test_save_load_roundtrip_bloc__"
const ORG_FIGHT_SLOT := "__test_save_load_roundtrip_org_fight__"
const BOGUS_SLOT := "__test_save_load_bogus_version__"
const COMMODITY_SLOT := "__test_save_load_roundtrip_commodity__"
const FLOAT_EPS := 1e-6
## And a RELATIVE partner, because the absolute bound above is unsatisfiable at
## the commodity register's own scale -- measured, not assumed. `capacity` holds
## figures up to ~2e11 (transport_services), where one double ULP is 3.05e-5, so
## JSON's ~15-significant-digit form came back up to 3.7e-4 different: 370x the
## absolute bound. The save now writes full_precision (shortest exact digits),
## which shrinks that to a few ULP, still over the absolute bound -- and what is
## left is Godot's parser, not the text: JSON.parse_string reads numbers through
## built_in_strtod, which is not correctly rounded, so no `JSON.stringify`
## setting removes it. test_save_continuity.gd check 5 pins the writer's half
## (no float moves past this relative bound, small ones included). This clause
## is not a loosening of the absolute one: it only accepts what the magnitude's
## own representation error can explain, and the margin is measured -- worst
## realised relative error is 7.3e-14 (a gdp residual), so 1e-12 carries ~14x
## slack while a genuinely lost or re-derived figure moves by orders more. The floor stays 1e-6 so every
## small-magnitude field is checked exactly as tightly as it was.
const FLOAT_REL_EPS := 1e-12

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

	_run_roundtrip(state, clock, loader)
	_run_atomic_write(state, clock, loader)
	_run_second_nation_roundtrip(loader)
	_run_transition_roundtrip(loader)
	_run_scenario_roundtrip(loader)
	_run_diplomacy_roundtrip(loader)
	_run_trade_roundtrip(loader)
	_run_coercion_roundtrip(loader)
	_run_bloc_roundtrip(loader)
	_run_council_registers_roundtrip(loader)
	_run_org_fight_roundtrip(loader)
	_run_agenda_roundtrip(loader)
	_run_defence_roundtrip(loader)
	_run_diary_roundtrip(loader)
	_run_companies_roundtrip(loader)
	_run_regulation_roundtrip(loader)
	_run_ownership_roundtrip(loader)
	_check_society_fields(loader)
	_check_demography_fields(loader)
	_check_unrest_fields(loader)
	_check_cycle_fields(loader)
	_check_inflation_fields(loader)
	_check_credit_fields(loader)
	_check_tax_fields(loader)
	_check_investment_fields(loader)
	_check_project_fields(loader)
	_check_campaign_fields(loader)
	_check_pledge_fields(loader)
	_check_referendum_fields(loader)
	_check_event_fields(loader)
	_check_upper_house_fields(loader)
	_check_judiciary_fields(loader)
	_check_geography_absences(loader)
	_check_network_absences(loader)
	_check_energy_bump(loader)
	_check_energy_absences(loader)
	_check_programme_fields(loader)
	_run_character_roundtrip(loader)
	_run_commodity_roundtrip(loader)
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

	var result := SaveManager.load_game(SECOND_NATION_SLOT, loader)
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

	var result := SaveManager.load_game(SCENARIO_SLOT, loader)
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

	var result := SaveManager.load_game(TRANSITION_SLOT, loader)
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

	var loaded_result := SaveManager.load_game(DIPLOMACY_SLOT, loader)
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
	# C(n,2) over the roster -- 45 in the ten era, 406 at V3.3, derived since V4.11.
	var n: int = loaded.nations.size()
	if loaded.relations.size() != n * (n - 1) / 2:
		_fail("a save round trip left %d pairs, expected %d" % [loaded.relations.size(), n * (n - 1) / 2])

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

	var loaded_result := SaveManager.load_game(TRADE_SLOT, loader)
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

	var loaded_result := SaveManager.load_game(COERCION_SLOT, loader)
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


## V4.5a. The contested council's registers round-trip with their types, and a
## save written before they existed loads with them empty and ticks. No bump:
## the argument is in game_state.gd's SAVE_VERSION block, this is its pin.
func _run_council_registers_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var reg: Dictionary = state.orgs["eu"]
	reg["agenda_choice"] = "cohesion_fund"
	reg["tabled"] = {"proposal_id": "recovery_facility", "by": "FRA"}
	reg["ratifying"] = {"proposal_id": "stability_pact", "name": "x", "sponsor": "DEU", "months_left": 4, "nations": {"FRA": "pending"}}
	reg["aid"] = [{"payer": "FRA", "recipient": "ITA", "pct_gdp": 0.05, "months_left": 7}]
	reg["debts"] = [{"debtor": "FRA", "creditor": "ITA", "made_on": 24312, "months_left": 33, "awaiting": "stability_pact"}]
	var back = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var b: Dictionary = back.orgs["eu"]
	if String(b.get("agenda_choice", "")) != "cohesion_fund":
		_fail("council agenda_choice did not round-trip")
	if String((b.get("tabled", {}) as Dictionary).get("by", "")) != "FRA":
		_fail("council tabled did not round-trip")
	var rat: Dictionary = b.get("ratifying", {})
	if typeof(rat.get("months_left")) != TYPE_INT or int(rat.get("months_left", 0)) != 4:
		_fail("council ratifying.months_left did not come back an int 4")
	var aid: Array = b.get("aid", [])
	if aid.size() != 1 or typeof(aid[0]["months_left"]) != TYPE_INT or not is_equal_approx(float(aid[0]["pct_gdp"]), 0.05):
		_fail("council aid did not come back typed")
	var debts: Array = b.get("debts", [])
	if debts.size() != 1 or typeof(debts[0]["months_left"]) != TYPE_INT or int(debts[0]["months_left"]) != 33:
		_fail("council debts did not come back typed")
	elif typeof(debts[0]["made_on"]) != TYPE_INT or int(debts[0]["made_on"]) != 24312 or String(debts[0]["awaiting"]) != "stability_pact":
		_fail("council debt made_on/awaiting did not come back typed")

	# A version-39 save: strip every V4.5a key and load it.
	var d: Dictionary = JSON.parse_string(JSON.stringify(GameState.new_game(loader, "FRA").to_dict()))
	for org_id in (d["orgs"] as Dictionary).keys():
		for key in ["agenda_choice", "tabled", "ratifying", "aid", "debts"]:
			(d["orgs"][org_id] as Dictionary).erase(key)
	var old = GameState.from_dict(d)
	var o: Dictionary = old.orgs["eu"]
	if String(o.get("agenda_choice", "x")) != "":
		_fail("a pre-V4.5a save did not load with an empty agenda_choice")
	if not (o.get("tabled", {"x": 1}) as Dictionary).is_empty():
		_fail("a pre-V4.5a save did not load with an empty tabled register")
	if not (o.get("ratifying", {"x": 1}) as Dictionary).is_empty():
		_fail("a pre-V4.5a save did not load with an empty ratifying register")
	if not (o.get("aid", [1]) as Array).is_empty() or not (o.get("debts", [1]) as Array).is_empty():
		_fail("a pre-V4.5a save did not load with empty aid and debts registers")
	Orgs.tick_month(old, loader)  # must not error


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

	state.orgs["eu"]["rules"][proposal.id] = {
		"name": proposal.proposal_name, "field": String(proposal.constraint["field"]),
		"op": String(proposal.constraint["op"]), "value": float(proposal.constraint["value"]),
		"tolerance": float(proposal.constraint["tolerance"]), "severity": float(proposal.constraint["severity"]),
		"transfer_pct_gdp": 0.0, "since_year": 2026, "since_month": 1,
	}
	Orgs.tick_month(state, loader)
	state.orgs["eu"]["next_index"] = 2
	state.orgs["eu"]["months_to_next"] = 7
	var clock := Clock.new()
	clock.day = 9
	var save_error := SaveManager.save_game(state, clock, BLOC_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game(org register) failed: %s" % save_error)
		return
	var loaded_res: Dictionary = SaveManager.load_game(BLOC_SLOT, loader)
	if not bool(loaded_res.get("ok", false)):
		_fail("the org register save did not load: %s" % str(loaded_res.get("error", "")))
		return
	var loaded = loaded_res["state"]

	if not ((loaded.orgs["eu"]["rules"] as Dictionary).has(proposal.id)):
		_fail("a rule in force did not survive the save round trip")
	if typeof(loaded.orgs["eu"]["next_index"]) != TYPE_INT or int(loaded.orgs["eu"]["next_index"]) != 2:
		_fail("org register next_index round-tripped as %s, expected the int 2" % [
			loaded.orgs["eu"]["next_index"], typeof(loaded.orgs["eu"]["next_index"])
		])
	if typeof(loaded.orgs["eu"]["months_to_next"]) != TYPE_INT or int(loaded.orgs["eu"]["months_to_next"]) != 7:
		_fail("org register months_to_next round-tripped as %s, expected the int 7" % [loaded.orgs["eu"]["months_to_next"]])

	# And the rule has to still BITE, not merely still exist.
	if not is_equal_approx(Orgs.burden(loaded, loaded.player(), Orgs.council_ids(loaded)), Orgs.burden(state, state.player(), Orgs.council_ids(state))):
		_fail("the org burden does not survive a save round trip: %.6f vs %.6f" % [
			Orgs.burden(loaded, loaded.player(), Orgs.council_ids(loaded)), Orgs.burden(state, state.player(), Orgs.council_ids(state))
		])

	# The bump's argument, checked the way 9 -> 10's halves were: a save whose
	# orgs key is missing reads as no council and no rules, which is WRONG rather
	# than empty -- and that is why the rename earned version 32.
	var no_orgs: Dictionary = state.to_dict()
	no_orgs.erase("orgs")
	var without = GameState.from_dict(no_orgs)
	if not is_zero_approx(Orgs.burden(without, without.player(), Orgs.council_ids(without))):
		_fail("a save with no orgs key still produced a burden")
	if is_equal_approx(Orgs.burden(without, without.player(), Orgs.council_ids(without)), Orgs.burden(state, state.player(), Orgs.council_ids(state))):
		_fail("dropping the org register changed nothing -- that half of the bump's premise is wrong")

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

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.5b raised it to 17, V1.5c to 18, V1.6a to 19, V1.6b to 20, V1.6c to 21, V1.6d to 22, V1.6f to 23 the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V4.4's reason is recorded and is the events machine's registers -- `event_queue` (the slot became the desk: absent, every crisis the country is facing vanishes, `event_pending`'s case one level up, times QUEUE_MAX), `event_category_quiet` and `event_cooldowns` (sparse until-registers whose absent value means `may draw now`, `event_quiet_months`'s case), `event_armed` (a chain the player paid for must not evaporate, `held_bills`' free-escape case), `repealed_at`/`last_accession` (the two stamps other machines write -- a reload must not forget a repeal or an accession the world remembers); V4.11's reason is recorded and is NO field, V3.3's again -- a version-39 save made against the 29-nation roster would load, unrefused, as a silent 29-nation world against org data whose NATO seats the neighbourhood; V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)


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
## V3.2, the review's critical: a membership fight is a state machine whose
## `phase` is the whole of it, and the machine advances by reading
## `ns.last_referendum_result`. Asserted here rather than argued: a fight saved
## mid-negotiation reloads INTACT and completes. V5.0d: so does a fight saved in
## the one-month resolved-but-unconsumed window -- the result now travels, where
## V3.2 had it as a display record and the load ended the fight, which threw away
## a referendum the country had WON (and whose price was already charged) for a
## save taken in the month the result card shows.
func _run_org_fight_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
		return
	var ns = state.player()

	var begun = Orgs.begin_withdrawal(state, loader, ns, "eu")
	if not bool(begun.get("ok", false)):
		_fail("begin_withdrawal refused: %s" % String(begun.get("reason", "")))
		return
	# Run the referendum out.
	var resolved := {}
	for i in range(13):
		resolved = Referendum.resolve_due(ns)
		if not resolved.is_empty():
			break
	if resolved.is_empty() or not bool(resolved.get("passed", false)):
		_fail("the withdrawal referendum did not pass in the round trip (yes_share %.3f)" % float(resolved.get("yes_share", 0.0)))
		return
	# One Orgs tick consumes the result and opens the negotiation.
	Orgs.tick_month(state, loader)
	if state.accessions.is_empty() or String(state.accessions[0].get("phase", "")) != "negotiation":
		_fail("the fight did not reach its negotiation phase before the save")
		return

	var clock := Clock.new()
	clock.day = 9
	var save_error := SaveManager.save_game(state, clock, ORG_FIGHT_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game(org fight) failed: %s" % save_error)
		return
	var result := SaveManager.load_game(ORG_FIGHT_SLOT, loader)
	if not result["ok"]:
		_fail("load_game(org fight) failed: %s" % result["error"])
		return
	var loaded = result["state"]

	if loaded.accessions.is_empty():
		_fail("the membership fight did not survive the save round trip")
		return
	var fight: Dictionary = loaded.accessions[0]
	if String(fight.get("phase", "")) != "negotiation":
		_fail("the fight's phase round-tripped as '%s' -- without it the machine matches nothing and the fight is stranded" % String(fight.get("phase", "")))
		return

	# The reloaded fight COMPLETES: the countdown runs out and membership flips.
	var flipped := false
	for i in range(26):
		Orgs.tick_month(loaded, loader)
		if not loaded.nations["FRA"].orgs.has("eu"):
			flipped = true
			break
	if not flipped:
		_fail("the reloaded fight never flipped membership -- the countdown is not advancing")

	# The window: resolved-but-unconsumed. The pending register is empty and the
	# answer lives only on the result, which travels, so the reloaded fight
	# consumes it and completes exactly as the unsaved one would.
	var state2 = GameState.new_game(loader, "FRA")
	var ns2 = state2.player()
	if not bool(Orgs.begin_withdrawal(state2, loader, ns2, "eu").get("ok", false)):
		_fail("the stranded-window begin was refused")
		return
	for i in range(13):
		if not Referendum.resolve_due(ns2).is_empty():
			break
	# Deliberately NO Orgs.tick_month here: the result sits unconsumed.
	var clock2 := Clock.new()
	clock2.day = 9
	SaveManager.save_game(state2, clock2, ORG_FIGHT_SLOT)
	clock2.free()
	var result2 := SaveManager.load_game(ORG_FIGHT_SLOT, loader)
	if not result2["ok"]:
		_fail("load_game(stranded fight) failed: %s" % result2["error"])
		return
	var loaded2 = result2["state"]
	if loaded2.accessions.is_empty():
		_fail("a fight saved the month its referendum was WON did not survive the load -- the country's answer was thrown away")
		return
	var flipped2 := false
	for i in range(26):
		Orgs.tick_month(loaded2, loader)
		if not loaded2.nations["FRA"].orgs.has("eu"):
			flipped2 = true
			break
	if not flipped2:
		_fail("the fight saved in the resolved-but-unconsumed window never flipped membership after the load")

	# And a fight whose result was ALREADY consumed is not re-triggered by the
	# record travelling: end it at the referendum phase with the consumed flag set,
	# as a stale save would carry it, and the load still ends it.
	var state3 = GameState.new_game(loader, "FRA")
	var ns3 = state3.player()
	if not bool(Orgs.begin_withdrawal(state3, loader, ns3, "eu").get("ok", false)):
		_fail("the consumed-result begin was refused")
		return
	for i in range(13):
		if not Referendum.resolve_due(ns3).is_empty():
			break
	ns3.last_referendum_result["org_fight_consumed"] = true
	var back3 = GameState.from_dict(JSON.parse_string(JSON.stringify(state3.to_dict())))
	Orgs.reconcile_on_load(back3, loader)
	if not back3.accessions.is_empty():
		_fail("a referendum-phase fight whose result was already consumed survived the load -- it would strand every membership verb")


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
	# Every AI nation reads ready (28 of them at V3.3's roster); the count is the
	# roster minus the player, and the ten-era literal was 9.
	if burst != state.nations.size() - 1:
		_fail("a save with no diplo_months_to_act left %d AI nations ready to act, expected %d -- the bump's premise is wrong" % [burst, state.nations.size() - 1])

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


func _run_roundtrip(state, clock, loader) -> void:
	var save_error := SaveManager.save_game(state, clock, ROUNDTRIP_SLOT)
	if not save_error.is_empty():
		_fail("save_game failed: %s" % save_error)
		return

	var result := SaveManager.load_game(ROUNDTRIP_SLOT, loader)
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
func _run_atomic_write(state, clock, loader) -> void:
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


## V1.6a. Two fields, and the SPLIT is the assertion worth having rather than the bump
## -- V1.3g's `deployments` and V1.4a's register, a third time.
##
## The session's own plan predicted NO bump at all, and the reason it gave was true
## about the wrong thing: src/sim/cycle.gd is genuinely stateless, has no accumulator
## and no tick_month(). But NationState.from_dict() rebuilds from the dictionary alone
## and never sees the loader, so a content-derived static fact that is not serialised
## is simply lost. STATELESSNESS IS A PROPERTY OF THE MODULE, NOT OF THE SAVE.
##
##   `cycle_impulse_pct` earns NOTHING. Absent it reads 0.0 and Economy.tick_month()
##   overwrites it from the clock on the very next tick -- coercion_impulse_pct's case,
##   and checked here the same reference-and-tick way rather than asserted.
##
##   `cycle_amplitude_rel` IS the bump. Absent it reads the default 1.0, so France runs
##   a cycle 45 % louder than its content says and Luxembourg one 32 % quieter: the
##   reloaded game runs a DIFFERENT MODEL from the one that saved it, which is
##   `eu_member` at V1.3b and `military_capability` at V1.3g. The premise is checked --
##   drop it and the impulse moves -- rather than argued.
##
## And the last block pins what was NOT added: there is no stored phase, no month
## counter and no accumulated wave anywhere in the save. The whole design rests on the
## generator being a pure function of the clock, so a later session that stores any of
## them turns this red and has to come and say why -- V1.3c's device, and the one thing
## on this list that would turn the module stateful without anybody noticing.
func _check_cycle_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	state.year = 2026
	state.month = 1
	for _i in range(30):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)

	var ns = state.player()
	if is_zero_approx(ns.cycle_impulse_pct):
		_fail("thirty months in and the cycle impulse is still 0.0 -- this check proves nothing")
	if is_equal_approx(ns.cycle_amplitude_rel, 1.0):
		_fail("FRA's cycle_amplitude_rel is 1.0, the default -- the content is not being read, so the drop test below cannot distinguish anything")

	var dict: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var loaded = GameState.from_dict(dict)
	if not is_equal_approx(loaded.player().cycle_amplitude_rel, ns.cycle_amplitude_rel):
		_fail("cycle_amplitude_rel did not survive the round trip")

	# The bump's premise: drop the content field and the model changes.
	var without: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(without["nations"]["FRA"] as Dictionary).erase("cycle_amplitude_rel")
	var lost = GameState.from_dict(without)
	if not is_equal_approx(lost.player().cycle_amplitude_rel, 1.0):
		_fail("an absent cycle_amplitude_rel did not read as the 1.0 default")
	lost.year = state.year
	lost.month = state.month
	Economy.tick_month(lost)
	var reference = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	reference.year = state.year
	reference.month = state.month
	Economy.tick_month(reference)
	if is_equal_approx(lost.player().cycle_impulse_pct, reference.player().cycle_impulse_pct):
		_fail("dropping cycle_amplitude_rel left the impulse unchanged -- the premise of the bump is wrong")

	# ...and the other half earns nothing, because one tick brings it back exactly.
	var no_impulse: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_impulse["nations"]["FRA"] as Dictionary).erase("cycle_impulse_pct")
	var derived = GameState.from_dict(no_impulse)
	if not is_zero_approx(derived.player().cycle_impulse_pct):
		_fail("an absent cycle_impulse_pct did not read as 0.0")
	derived.year = state.year
	derived.month = state.month
	Economy.tick_month(derived)
	if not is_equal_approx(derived.player().cycle_impulse_pct, reference.player().cycle_impulse_pct):
		_fail("the cycle impulse did not come back on one tick, so it is not derived and would have earned the bump itself")

	# Nothing stateful was added, and this is what pins it.
	var fra: Dictionary = (JSON.parse_string(JSON.stringify(state.to_dict()))["nations"]["FRA"] as Dictionary)
	for key in fra.keys():
		var name := String(key)
		if name.begins_with("cycle_") and name != "cycle_impulse_pct" and name != "cycle_amplitude_rel":
			_fail("a save carries %s -- the cycle is a pure function of the clock and stores no phase, counter or accumulated wave, so a third field is a model change that has to be argued" % name)


## V1.7a. THREE FIELDS AND NONE OF THEM EARNS A BUMP, which is the answer the plan
## predicted and this is where it is checked rather than asserted.
##
## All three read as "no campaign" when absent, and that is the TRUTH about every
## version-23 save because those games had no campaign verb -- `measures` at V1.3c,
## `pacts` at V1.3g, `appointments` at U6a, `sector_investment` at V1.6e. They are
## serialised regardless, and for three DIFFERENT reasons, so the checks below are
## separate rather than folded together:
##
##   campaign_running       a verb writes it and no tick recomputes it
##   campaign_mobilisation  it is SPENT at the ballot box, so a reload in the last month
##                          of a run-up would go to the vote with a campaign already paid
##                          for and no longer held
##   campaign_bill_pct_gdp  recomputed on the first tick, serialised so a save read back
##                          and never ticked reports the budget it was saved with
##
## And it ends with V1.3c's device, pointed at the next session for the sixth time: the
## version is STILL 23, so V1.7b has to come and say why it moves.
func _check_campaign_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	# Into the run-up, then two efforts in the field and two months of accrual.
	var target: int = (ns.next_executive_year * 12 + ns.next_executive_month) - CampaignK.CAMPAIGN_WINDOW_MONTHS
	state.year = int(target / 12)
	state.month = target - state.year * 12
	if state.month <= 0:
		state.month += 12
		state.year -= 1

	var site := ""
	for region in loader.regions.get("FRA", []):
		site = String(region.id)
		break
	var started := 0
	for a in loader.campaign_actions:
		if String(a.effects.get("campaign", {}).get("op", "")) != "start":
			continue
		if Campaign.execute(state, ns, loader.campaign_actions, a, site).get("applied", false):
			started += 1
	if ns.campaign_sites.is_empty():
		_fail("the started efforts wrote no site, so this check measures nothing")
		return
	if started == 0:
		_fail("no campaign effort could be started, so this check measures nothing")
		return
	Campaign.tick_month(state, loader)
	Campaign.tick_month(state, loader)
	if ns.campaign_mobilisation.is_empty() or ns.campaign_bill_pct_gdp == 0.0:
		_fail("the campaign did not accrue or did not bill, so this check measures nothing")
		return
	if ns.campaign_saturation.is_empty():
		_fail("two meeting months wrote no saturation, so this check measures nothing")
		return

	var full: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var kept = GameState.from_dict(full)
	if Campaign.running(kept.player()) != Campaign.running(ns):
		_fail("the efforts in the field did not survive the round trip")
	for bloc in ns.campaign_mobilisation:
		if not is_equal_approx(
			float(kept.player().campaign_mobilisation.get(bloc, 0.0)),
			float(ns.campaign_mobilisation[bloc])
		):
			_fail("the mobilisation on '%s' did not survive the round trip" % bloc)
	if not is_equal_approx(kept.player().campaign_bill_pct_gdp, ns.campaign_bill_pct_gdp):
		_fail("the campaign bill did not survive the round trip")
	# V2.6b2: the two sited registers round-trip exactly -- the site as the region id
	# the effort meets in, the saturation to the last bit, because a rounding here
	# would move a tour decision on reload.
	if Campaign.running(kept.player()) == Campaign.running(ns) and not Campaign.running(ns).is_empty():
		for eid in Campaign.running(ns):
			if Campaign.site_of(kept.player(), String(eid)) != Campaign.site_of(ns, String(eid)):
				_fail("the site on '%s' did not survive the round trip" % eid)
	for rid in ns.campaign_saturation:
		if float(kept.player().campaign_saturation.get(rid, -1.0)) != float(ns.campaign_saturation[rid]):
			_fail("the saturation on '%s' did not survive the round trip exactly" % rid)

	# (1) THE RUNNING REGISTER. Absent it reads as nothing in the field, which is correct
	# for a version-23 save -- so no bump. What it is NOT is free to drop from a
	# version-24 save: the bill goes with it, and the player is handed back money they
	# have committed.
	var no_running: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_running["nations"]["FRA"] as Dictionary).erase("campaign_running")
	var dropped_running = GameState.from_dict(no_running)
	if not dropped_running.player().campaign_running.is_empty():
		_fail("a dropped running register came back non-empty")
	Campaign.tick_month(state, loader)
	if Campaign.bill_pct_gdp(dropped_running.player(), loader) != 0.0:
		_fail("a dropped running register still bills -- then it is not derivable and the version must move")

	# (2) THE MOBILISATION. Absent it reads 0.0 and Campaign.turnout_of() returns the
	# authored constant BIT-FOR-BIT, which is the whole property this session rests on.
	var no_mob: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_mob["nations"]["FRA"] as Dictionary).erase("campaign_mobilisation")
	var dropped_mob = GameState.from_dict(no_mob)
	for bloc in OpinionK.BLOC_KEYS:
		if Campaign.turnout_of(dropped_mob.player(), bloc) != float(ElectionK.BLOC_TURNOUT[bloc]):
			_fail("a dropped mobilisation register does not read as the authored turnout for '%s'" % bloc)
	# ...and it is NOT recomputed by a tick, which is what separates it from the bill and
	# is the reason it is serialised at all.
	Campaign.tick_month(state, loader)

	# (2b) V2.6b2's two, and BOTH earn the bump to 30. The site dropped: a running
	# effort silently reverts to the factor-1.0 national reach while the panel still
	# names a place -- the save disagrees with its own readout. The saturation dropped:
	# every spoken-to region returns at full reach, which is `campaign_started`'s
	# exploit one level up -- the tour un-spoken, re-spoken for free on reload.
	var no_sites: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_sites["nations"]["FRA"] as Dictionary).erase("campaign_sites")
	var dropped_sites = GameState.from_dict(no_sites)
	for eid in Campaign.running(ns):
		if Campaign.site_of(dropped_sites.player(), String(eid)) != "":
			_fail("a dropped site register did not read as place-less")
	var no_sat: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_sat["nations"]["FRA"] as Dictionary).erase("campaign_saturation")
	var dropped_sat = GameState.from_dict(no_sat)
	if Campaign.spoken(dropped_sat.player(), site) != 0.0:
		_fail("a dropped saturation register did not read as nobody spoken to")

	# (3) WHAT WAS NOT ADDED. No window flag, no "campaign opened" date, no per-effort
	# entry -- the window is a LEVEL READ of next_executive_*, which the save has carried
	# since the MVP, and the register holds effort IDS and nothing about them. A later
	# session storing any of these turns this red and has to come and say why.
	for absent in ["campaign_open", "campaign_opened_year", "campaign_started_month", "last_campaign_result"]:
		if (full["nations"]["FRA"] as Dictionary).has(absent):
			_fail("a save carries %s -- the window is a level read on the clock and the last result is a display record" % absent)
	for entry in (full["nations"]["FRA"] as Dictionary)["campaign_running"]:
		if typeof(entry) != TYPE_STRING:
			_fail("a serialised running entry is not a bare effort id -- the cost and the reach round-trip through data/campaign-actions/, not through the save")

	# (4) THE SPENT REGISTER, and it is the one campaign field that DOES earn the bump.
	# Absent it reads as "no effort has run yet" while `campaign_running` beside it says
	# one is in the field -- the two disagree, and the disagreement is the exploit the
	# register exists to close: every spent effort is handed back, so a reload re-opens
	# the start/stop/start loop that re-pays a permanent `bloc_offset`. Save-scumming
	# then farms it without bound. `diplo_months_to_act` at U6a.
	#
	# Checked as a PREMISE rather than asserted: drop it, and require that the effort
	# becomes startable again.
	var spent := Campaign.running(ns)
	if spent.is_empty():
		_fail("nothing was started, so the spent-register check measures nothing")
		return
	var spent_action = null
	for a in loader.campaign_actions:
		var t: Dictionary = a.effects.get("campaign", {})
		if String(t.get("op", "")) == "start" and spent.has(String(t.get("effort_id", ""))):
			spent_action = a
			break
	if spent_action == null:
		_fail("no start action names a running effort, so the spent-register check measures nothing")
		return

	var no_spent: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_spent["nations"]["FRA"] as Dictionary).erase("campaign_started")
	(no_spent["nations"]["FRA"] as Dictionary)["campaign_running"] = []
	var dropped_spent = GameState.from_dict(no_spent)
	if not Campaign.available(
		dropped_spent, dropped_spent.player(), loader.campaign_actions
	).has(spent_action):
		_fail("dropping campaign_started left a spent effort unstartable -- then it is derivable and the version did not need to move")

	# ...and it is NOT recomputed by a tick, which is what separates it from the bill.
	Campaign.tick_month(dropped_spent, loader)
	if not dropped_spent.player().campaign_started.is_empty():
		_fail("a tick rebuilt the spent register -- then it is derivable and the version did not need to move")

	# The version assertion is in _check_bloc_fields() above and now reads 24, raised by
	# the V1.7a restart fix. V1.3c's device stays armed there: the next session moving it
	# has to come and say why.


## V1.7b. ONE FIELD AND IT EARNS NOTHING, and this is where that is CHECKED rather
## than asserted.
##
## `pledges` absent reads as "nothing promised", which is the truth about every
## version-23 save because those games had no pledge verb -- `measures` at V1.3c,
## `pacts` at V1.3g, `appointments` at U6a, `campaign_running` at V1.7a.
##
## IT IS SERIALISED REGARDLESS AND THAT HALF IS NOT FREE, which is `regulation_burden`'s
## case at V1.4b rather than the campaign bill's: a verb writes it, no tick recomputes
## it, and THE REWARD HAS ALREADY BEEN PAID. A save that dropped the register would hand
## the player the upside of every promise they ever made and delete the liability. The
## check below drops it and requires the charge to stop, which is that premise measured.
##
## AND THE HALF WORTH PINNING IS WHAT IS NOT THERE. No breach rate, no display name, no
## "is live" flag and no stored judgement: the ladder round-trips through data/pledges/
## and the two dates are read against the clock. A later session storing any of them
## turns this red and has to come and say why.
func _check_pledge_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	var target: int = (ns.next_executive_year * 12 + ns.next_executive_month) - CampaignK.CAMPAIGN_WINDOW_MONTHS
	state.year = int(target / 12)
	state.month = target - state.year * 12
	if state.month <= 0:
		state.month += 12
		state.year -= 1

	var made := 0
	for a in loader.pledges:
		if Pledges.execute(state, ns, loader.pledges, a).get("applied", false):
			made += 1
	if made == 0:
		_fail("no promise could be made, so this check measures nothing")
		return

	# Into the term the promises bind, and break one of them.
	var entry: Dictionary = ns.pledges[0]
	state.year = int(entry["from_year"])
	state.month = int(entry["from_month"])
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	var pending := {
		"tax_rates_pct": ns.tax_rates_pct.duplicate(),
		"spending_pct_gdp": ns.spending_pct_gdp.duplicate(),
	}
	pending["tax_rates_pct"]["income"] = float(pending["tax_rates_pct"]["income"]) + 8.0
	pending["spending_pct_gdp"]["health"] = float(pending["spending_pct_gdp"]["health"]) - 4.0
	Budget.commit(state, pending)
	Pledges.tick_month(state, loader)

	var broken := 0
	for e in ns.pledges:
		broken += int(e["breach_months"])
	if broken == 0:
		_fail("no promise was broken, so this check measures nothing")
		return

	var full: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var kept = GameState.from_dict(full)
	if kept.player().pledges.size() != ns.pledges.size():
		_fail("the promises did not survive the round trip")
	for i in ns.pledges.size():
		for key in (ns.pledges[i] as Dictionary).keys():
			var a = (ns.pledges[i] as Dictionary)[key]
			var b = (kept.player().pledges[i] as Dictionary).get(key)
			if typeof(a) == TYPE_FLOAT:
				if not is_equal_approx(float(a), float(b)):
					_fail("pledge[%d].%s did not survive the round trip" % [i, key])
			elif str(a) != str(b):
				_fail("pledge[%d].%s did not survive the round trip" % [i, key])

	# (1) ABSENT IT READS AS "NOTHING PROMISED" -- correct for a version-23 save, so no
	# bump. What it is NOT is free to drop from a later save: the charge stops and the
	# reward, which was paid at the moment of the promise, is already inside bloc_offset.
	var dropped: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(dropped["nations"]["FRA"] as Dictionary).erase("pledges")
	var no_pledges = GameState.from_dict(dropped)
	if not no_pledges.player().pledges.is_empty():
		_fail("a dropped pledge register came back non-empty")
	var before: Dictionary = no_pledges.player().bloc_offset.duplicate(true)
	Pledges.tick_month(no_pledges, loader)
	for bloc in before:
		if float(no_pledges.player().bloc_offset.get(bloc, 0.0)) != float(before[bloc]):
			_fail("a dropped pledge register still charged '%s' -- then it is derivable and this reasoning is wrong" % bloc)
	# ...and the premise: the register is NOT recomputed by a tick, unlike the campaign
	# bill and V1.4a's three prices. That is what makes serialising it load-bearing.
	if not no_pledges.player().pledges.is_empty():
		_fail("a tick rebuilt the pledge register -- then it need not be serialised at all")

	# (2) WHAT WAS NOT ADDED.
	for absent in ["last_pledge_result", "pledge_live", "pledge_trust", "trust_pct"]:
		if (full["nations"]["FRA"] as Dictionary).has(absent):
			_fail("a save carries %s -- there is no trust quantity in this model and the last result is a display record" % absent)
	var allowed := [
		"pledge_id", "field", "op", "value",
		"from_year", "from_month", "until_year", "until_month",
		"breach_months", "months_live",
	]
	for e in (full["nations"]["FRA"] as Dictionary)["pledges"]:
		for key in (e as Dictionary).keys():
			if not allowed.has(String(key)):
				_fail("a serialised promise carries '%s' -- the ladder round-trips through data/pledges/, not through the save" % key)

	# V1.3c's device, answered and re-armed. V1.7a left "the version is still 23" so
	# V1.7b would have to come and say why it moves; it does not move, and the reason is
	# in this function's header. V1.7c now has to come and say why.
	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.6f raised it to 23, V1.7a argued it should STAY and V1.7b argued the same for `pledges` the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)


## V1.7c. FOUR added fields, THREE of which earn the bump to 25 and one of which is
## not serialised at all -- and they fail the rule by three DIFFERENT failures, so they
## are asserted separately. A single combined check would let any of them be quietly
## wrong, which is the split V1.5c, V1.4a and V1.3g each found worth having.
##
##   election_system / election_threshold_pct  LIFTED from Nation, and the sharpest
##     case on this list since `military_capability`. Absent they read "" and 0.0;
##     ElectoralSystems.allocate() falls through its match on an unknown method and
##     EVERY SEAT ALLOCATION COLLAPSES TO ZERO. NationState.from_dict() never sees the
##     loader -- V1.6a's finding that statelessness is a property of the MODULE and not
##     of the save file -- so a content-derived static fact cannot be re-derived here.
##
##   referendum_mode  static content, and it earns the bump for `eu_member`'s reason
##     rather than for its own: absent it reads "", which is a LEGAL state for six of
##     the ten and a silently different model for France, whose Art. 89 route
##     disappears. A reloaded game runs a different constitution.
##
##   referendum_pending  absent, a referendum the country has already been called to
##     VANISHES -- a free withdrawal of the one act this session deliberately made
##     un-free. `campaign_started` one commit earlier, and `diplo_months_to_act` at U6a.
##
##   last_referendum_result  serialised since V5.0d, absent-ok. V1.7c left it out as
##     `last_project_result`'s display record, but V3.2's membership fight advances
##     by reading it, so a save in the month a vote resolved lost a WON referendum.
##     Its absence reads as "no vote yet", correct for every older save: no bump.
func _check_referendum_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	var law = null
	for candidate in loader.laws:
		if candidate.id == "single_term_reform":
			law = candidate
	if law == null:
		_fail("single_term_reform is not in the law list, so the referendum round trip measures nothing")
		return
	var called := Legislature.propose(state, loader, law, false, true)
	if not bool(called.get("referendum_called", false)):
		_fail("no referendum was called, so the referendum round trip measures nothing")
		return

	var dict: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var back = GameState.from_dict(dict)
	var bns = back.player()

	# (1) the round trip itself.
	if bns.election_system != ns.election_system:
		_fail("election_system did not survive the round trip")
	if not is_equal_approx(bns.election_threshold_pct, ns.election_threshold_pct):
		_fail("election_threshold_pct did not survive the round trip")
	if bns.referendum_mode != ns.referendum_mode:
		_fail("referendum_mode did not survive the round trip")
	if int(bns.referendum_pending.get("months_left", 0)) != int(ns.referendum_pending.get("months_left", -1)):
		_fail("the pending referendum did not survive the round trip")

	# (2) the electoral pair, checked as a PREMISE rather than asserted: drop it, and
	# require that the allocation collapses.
	var no_system: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_system["nations"]["FRA"] as Dictionary).erase("election_system")
	var dropped_system = GameState.from_dict(no_system)
	## expects-error: electoral_systems: unknown system ''
	var seats := ElectoralSystems.allocate(
		dropped_system.player().election_system,
		{"a": 0.6, "b": 0.4}, 100, 0.0
	)
	var total := 0
	for party_id in seats:
		total += int(seats[party_id])
	if total != 0:
		_fail("dropping election_system still allocated %d seats -- then it did not need the bump" % total)

	# (3) the mode, and it is a DIFFERENT failure: not a collapse but a silently
	# different constitution.
	var no_mode: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_mode["nations"]["FRA"] as Dictionary).erase("referendum_mode")
	var dropped_mode = GameState.from_dict(no_mode)
	if Legislature.can_put_to_referendum(dropped_mode.player(), law):
		_fail("dropping referendum_mode left the route open -- then it did not need the bump")

	# (4) the register, and it is a THIRD failure: a free withdrawal.
	var no_pending: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_pending["nations"]["FRA"] as Dictionary).erase("referendum_pending")
	var dropped_pending = GameState.from_dict(no_pending)
	if Referendum.is_pending(dropped_pending.player()):
		_fail("dropping referendum_pending left a referendum in flight")
	var before_offset: float = float(dropped_pending.player().bloc_offset.get("workers", 0.0))
	Legislature.tick_month(dropped_pending, loader)
	if not is_equal_approx(float(dropped_pending.player().bloc_offset.get("workers", 0.0)), before_offset):
		_fail("a tick charged for a referendum the save had already deleted")
	if Referendum.is_pending(dropped_pending.player()):
		_fail("a tick rebuilt the register -- then it is derivable and the version did not need to move")

	# (5) the result TRAVELS (V5.0d). The org fight machine advances by reading
	# it, so a save in the month a vote resolved must carry it -- and an absent
	# key reads as {} ("no vote yet"), correct for every older save: no bump.
	if not (dict["nations"]["FRA"] as Dictionary).has("last_referendum_result"):
		_fail("a save does not carry last_referendum_result -- a membership fight saved the month its vote resolved loses the answer")

	# (6) and the register carries no CONTENT: a law id, a countdown and the question's
	# own position, and nothing else. V1.4a's discipline, and the reason the position is
	# there is that the country must answer the question it was asked.
	var allowed := ["law_id", "months_left", "position"]
	for key in (dict["nations"]["FRA"]["referendum_pending"] as Dictionary).keys():
		if not allowed.has(String(key)):
			_fail("a serialised referendum carries '%s' -- the law round-trips through data/laws/, not through the save" % key)


## V4.4. The V1.8 slot became a severity-ordered desk, and the registers grew with
## it -- and they fail the bump's rule by DIFFERENT failures, so they are asserted
## apart rather than together, the pattern V1.5c set and V1.8 extended.
##
##   `event_queue` is `event_pending`'s case one level up: absent, crises the
##   country is facing VANISH -- a free escape from every act V1.8 made
##   un-escapable, times four (the desk holds QUEUE_MAX entries).
##
##   `event_category_quiet` and `event_cooldowns` are `event_quiet_months`'s
##   case one level down: absent they read empty, and empty means "may draw
##   now" -- U6a's `diplo_months_to_act`, whose absent value fired nine acts in
##   one month. A save reloaded the month after a resolution hands the category
##   its draw back immediately.
##
##   `event_armed` is `held_bills`' free-escape case: a consequence the player
##   already paid for is simply not there after a reload.
##
## `repealed_at` and `last_accession` are month stamps whose absent value -- "no
## happening" -- is correct for every save made before V4.4; they ride the bump so
## a reload does not forget a repeal or an accession the world still remembers.
## (`event_hook_fired` rode this family until pass 18 removed it as dead state; a
## save still carrying the key must load, which (6) below pins.)
##
## `event_fired` and `event_history` carry over from V1.8's check in kind: the
## once-mark still earns the bump (absent, a resolved `once` event happens a
## second time and the player pays twice for something already settled), the
## ledger still earns nothing (a display record nothing reads back).
class _EventlessLoader:
	## The tick with nothing to draw: the drop-test's control, because with the
	## real list a live month can land a REAL crisis and the check would measure
	## that crisis's effects rather than the dropped desk's absence.
	var events: Array = []
	var commodity_goods: Dictionary = {}
	var regions: Dictionary = {}


func _check_event_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()
	var month := Events._absolute_month(int(state.year), int(state.month))

	# The desk holds TWO entries, so "both present, months left intact" means both:
	# broadcast_charter is the `once` event, so pin (3) needs its mark, and
	# procurement_scandal gives the queue a second entry. Both non-sited, so the
	# V3.5 announce arguments stay inert -- filled exactly as tick_month fills
	# them. The announce is the RAW primitive: the tick's QUEUE_MAX gate and
	# dedupe are the tick's, and a staged desk wants exactly what it staged -- and
	# since the marks moved from announce to DELIVERY, the once-mark is STAGED
	# beside the registers below rather than bought as announce's side effect.
	var ev = Events.event_by_id(loader, "broadcast_charter")
	if ev == null:
		_fail("broadcast_charter is not in the event list, so the event round trip measures nothing")
		return
	var second = Events.event_by_id(loader, "procurement_scandal")
	if second == null:
		_fail("procurement_scandal is not in the event list, so the queue round trip is one entry short")
		return
	Events.announce(ns, ev, month, Events.region_names(ns, loader))
	Events.announce(ns, second, month, Events.region_names(ns, loader))
	# The once-mark, the quiet, a cooldown, a chain and the hook stamps,
	# staged so every register the bump covers is non-empty in the ONE save this
	# check serialises.
	ns.event_fired[ev.id] = true
	ns.event_category_quiet["fiscal"] = 7
	ns.event_cooldowns["procurement_scandal"] = month + 12
	ns.event_armed.append({
		"event_id": "emergency_budget_demand", "due_index": month + 2,
		"source_id": "procurement_scandal",
	})
	ns.repealed_at["income_tax"] = month
	ns.last_accession = {"org": "eu", "month_index": month}
	ns.assembly_bill_passed_month = month
	ns.commodity_high_month = month
	# One resolved event in the ledger, so the display record has something to survive.
	ns.event_history.push_front({
		"event_id": ev.id, "event_name": ev.event_name,
		"choice_id": "inquiry", "choice_label": "Order an inquiry",
		"defaulted": true, "year": 2026, "month": 4,
	})

	var dict: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var back = GameState.from_dict(dict)
	var bns = back.player()

	# (1) the round trip itself: BOTH desk entries with their deadlines, plus the
	# once-mark, the ledger, and every staged register.
	var staged_left := {}
	for entry in ns.event_queue:
		staged_left[String(entry.get("event_id", ""))] = int(entry.get("months_left", -1))
	var reloaded_left := {}
	for entry in bns.event_queue:
		reloaded_left[String(entry.get("event_id", ""))] = int(entry.get("months_left", -1))
	if reloaded_left != staged_left or bns.event_queue.size() != 2:
		_fail("the desk did not survive the round trip: %s staged against %s reloaded" % [staged_left, reloaded_left])
	if not bns.event_fired.has(ev.id):
		_fail("event_fired did not survive the round trip")
	if bns.event_history.size() != ns.event_history.size():
		_fail("the event ledger did not survive the round trip")
	if int(bns.event_category_quiet.get("fiscal", -1)) != 7:
		_fail("event_category_quiet did not survive the round trip")
	if int(bns.event_cooldowns.get("procurement_scandal", -1)) != month + 12:
		_fail("event_cooldowns did not survive the round trip")
	if bns.event_armed.size() != 1 \
			or String(bns.event_armed[0].get("event_id", "")) != "emergency_budget_demand" \
			or int(bns.event_armed[0].get("due_index", -1)) != month + 2:
		_fail("event_armed did not survive the round trip: %s" % [bns.event_armed])
	if int(bns.repealed_at.get("income_tax", -1)) != month:
		_fail("repealed_at did not survive the round trip")
	if String(bns.last_accession.get("org", "")) != "eu" \
			or int(bns.last_accession.get("month_index", -1)) != month:
		_fail("last_accession did not survive the round trip")
	if bns.assembly_bill_passed_month != month:
		_fail("assembly_bill_passed_month did not survive the round trip")
	if bns.commodity_high_month != month:
		_fail("commodity_high_month did not survive the round trip")

	# (2) `event_queue` earns the bump, and it is `event_pending`'s case one level
	# up: absent, crises the country is facing VANISH -- a free escape from every
	# act V1.8 made un-escapable, times four. And the escape stays free: a tick
	# charges nothing for what the save no longer holds, through a loader with no
	# events so the check cannot measure some real crisis the month happened to
	# draw (the class _EventlessLoader names).
	var no_queue: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_queue["nations"]["FRA"] as Dictionary).erase("event_queue")
	var dropped_queue = GameState.from_dict(no_queue)
	if Events.is_pending(dropped_queue.player()):
		_fail("dropping event_queue left crises on the desk")
	var before_offset: float = float(dropped_queue.player().bloc_offset.get("urban", 0.0))
	Events.tick_month(dropped_queue, _EventlessLoader.new())
	if not is_equal_approx(float(dropped_queue.player().bloc_offset.get("urban", 0.0)), before_offset):
		_fail("a tick charged for an event the save had already deleted")
	if Events.is_pending(dropped_queue.player()):
		_fail("a tick rebuilt the desk -- then it is derivable and the version did not need to move")

	# (3) `event_fired` earns it by a DIFFERENT failure, unchanged from V1.8:
	# absent, a resolved `once` event happens a second time and the player pays
	# its price twice for something already settled. `passed_law_ids`' case,
	# marked at DELIVERY since the move the staging comment above records --
	# which is why the mark is staged by hand rather than bought as announce's
	# side effect.
	var no_fired: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_fired["nations"]["FRA"] as Dictionary).erase("event_fired")
	var dropped_fired = GameState.from_dict(no_fired)
	if dropped_fired.player().event_fired.has(ev.id):
		_fail("dropping event_fired still remembered a `once` event")

	# (4) the quiet and the cooldown earn it by a THIRD, one level down from
	# `event_quiet_months`: absent they read empty, and empty means *may draw
	# now*. Each staged above, each checked as a PREMISE in (1), each dropped
	# here and required to read ready.
	var no_quiet: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_quiet["nations"]["FRA"] as Dictionary).erase("event_category_quiet")
	if not GameState.from_dict(no_quiet).player().event_category_quiet.is_empty():
		_fail("dropping event_category_quiet did not read as `may draw now`")
	var no_cooldowns: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_cooldowns["nations"]["FRA"] as Dictionary).erase("event_cooldowns")
	if not GameState.from_dict(no_cooldowns).player().event_cooldowns.is_empty():
		_fail("dropping event_cooldowns did not read as `may draw now`")

	# (5) `event_armed` earns it as `held_bills`' free-escape: a chain the player
	# paid for is simply not there after a reload, and the consequence it owes
	# never arrives.
	var no_armed: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_armed["nations"]["FRA"] as Dictionary).erase("event_armed")
	if not GameState.from_dict(no_armed).player().event_armed.is_empty():
		_fail("dropping event_armed left a chain armed")

	# (6) the hook stamps ride the bump for the RELOAD, not for absence: erase
	# each and it reads as "no happening", which is correct for every save made
	# before V4.4. The pin is that the round trip does not invent or keep one.
	var no_stamps: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_stamps["nations"]["FRA"] as Dictionary).erase("repealed_at")
	(no_stamps["nations"]["FRA"] as Dictionary).erase("last_accession")
	(no_stamps["nations"]["FRA"] as Dictionary).erase("assembly_bill_passed_month")
	(no_stamps["nations"]["FRA"] as Dictionary).erase("commodity_high_month")
	var dropped_stamps = GameState.from_dict(no_stamps)
	if not dropped_stamps.player().repealed_at.is_empty() \
			or not dropped_stamps.player().last_accession.is_empty():
		_fail("dropping the hook stamps left a memory behind")
	# The month stamp's empty value is -1, not 0: month 0 is a real month, and a
	# default of 0 would read as "an assembly bill passed in month 0".
	if int(dropped_stamps.player().assembly_bill_passed_month) != -1:
		_fail("dropping assembly_bill_passed_month did not read -1 (got %d)" % dropped_stamps.player().assembly_bill_passed_month)
	if int(dropped_stamps.player().commodity_high_month) != -1:
		_fail("dropping commodity_high_month did not read -1 (got %d) -- a default of 0 would read as a crossing in month 0" % dropped_stamps.player().commodity_high_month)
	# A save written while `event_hook_fired` still existed must load: from_dict reads
	# explicit keys, so the dead key is ignored, and the field is not written back.
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(legacy["nations"]["FRA"] as Dictionary)["event_hook_fired"] = {"law_passed": month}	# from_dict never returns null, so "it loaded" is no assertion: a field staged above
	# (event_cooldowns, month + 12) must come back from THIS payload, which proves the
	# load read the legacy dictionary and not a fresh game.
	var legacy_back = GameState.from_dict(legacy)
	if int(legacy_back.player().event_cooldowns.get("procurement_scandal", -1)) != month + 12:
		_fail("a save carrying the removed event_hook_fired key did not load its other fields")
	if (legacy_back.to_dict()["nations"]["FRA"] as Dictionary).has("event_hook_fired"):
		_fail("a save carrying the removed event_hook_fired key wrote it back out")

	# (7) `event_history` earns NOTHING and is serialised regardless, unchanged
	# from V1.8. A display record nothing in src/sim/ reads back -- `unrest_acts`'
	# case -- kept because the ledger is half of what the Dispatches window exists
	# to be. Stated as an absence-of-consequence rather than as a bump: dropping
	# it must change no figure.
	var no_history: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_history["nations"]["FRA"] as Dictionary).erase("event_history")
	var dropped_history = GameState.from_dict(no_history)
	if not dropped_history.player().event_history.is_empty():
		_fail("dropping event_history left a ledger behind")
	if not is_equal_approx(
		float(dropped_history.player().bloc_offset.get("urban", 0.0)),
		float(back.player().bloc_offset.get("urban", 0.0))
	):
		_fail("dropping event_history moved a figure -- then it is not a display record")

	# (8) WHAT WAS NOT ADDED, and it is the half worth pinning: no stored hazard,
	# no stored draw, no RNG state. Events.hazard_passes() and the weighted pick
	# are pure functions of (nation, event, absolute month), which is what makes
	# a save reloaded on the month a crisis arrived receive the SAME crisis -- and
	# the hooks' month stamps are memories of happenings, not draw state. V1.6c
	# pinned the credit module's statelessness the same way, so the day a session
	# gives an event's arrival an accumulator this turns red and has to come and
	# say why.
	for banned in ["event_seed", "event_rng", "event_draw", "event_hazard"]:
		if (dict["nations"]["FRA"] as Dictionary).has(banned):
			_fail("a save carries '%s' -- the hazard is a pure function and has nothing to store" % banned)

	# (9) and the desk carries no CONTENT: an id, a name for the diary, a
	# countdown, the interrupt flag, and the V4.4 pair that orders the desk --
	# severity, category. V1.4a's discipline, one justified addition at a time:
	# the flag is LIVE STATE (the load path reads it to re-pause the clock on a
	# save made mid-crisis); the pair is the queue's own sort key, so a dropped
	# one would silently reorder every desk a save reloads. Everything else about
	# an event round-trips through data/events/.
	#
	# V3.5's sited pair keeps its place on the same argument: the register
	# carries no announcement month (months_left only counts down), so a save
	# reloaded mid-crisis could not reconstruct which month drew which place. A
	# non-sited event's entry carries neither key, as staged here.
	var allowed := ["event_id", "event_name", "months_left", "interrupt",
		"severity", "category", "region_id", "region_name"]
	for entry in (dict["nations"]["FRA"]["event_queue"] as Array):
		for key in (entry as Dictionary).keys():
			if not allowed.has(String(key)):
				_fail("a serialised event carries '%s' -- the choices round-trip through data/events/, not through the save" % key)


## V1.1e. SAVE_VERSION 26 -> 27, on EIGHT added fields of ten, and they fail the rule
## by THREE DIFFERENT FAILURES -- so the three groups are asserted APART rather than
## together, which is docs/unrest-model.md's V1.5c discipline. A single combined check
## would let any one half be quietly wrong.
##
##   THE SIX STATIC ROWS -- has_upper_house, upper_chamber_name, upper_seats,
##     upper_ordinary, upper_amendment and judicial_review -- are content-derived facts
##     NationState.from_dict() cannot re-derive, because it never sees the loader.
##     `cycle_amplitude_rel` at V1.6a and `election_system` at V1.7c, and the failure is
##     loud: absent, a reloaded France has no Senat and no Conseil constitutionnel, so
##     it runs a DIFFERENT MODEL from the one that saved it.
##
##   `upper_share` and `judicial_independence` are accumulated state nothing recomputes
##     on the next tick. The chamber renews only at a legislative election, which for
##     France is up to five years away; and re-deriving rule of law from content on load
##     would erase the erosion a player spent a term buying, which is
##     `service_quality`'s case at V1.5a in its strongest form.
##
##   `held_bills` is a FREE ESCAPE if it goes missing: a bill the second chamber refused
##     simply is not there any more, and neither is the override price the release
##     charges. `referendum_pending` at V1.7c and `event_pending` at V1.8.
##
## `start_judicial_independence` earns NOTHING and is serialised anyway, for the reason
## its own declaration gives. And what is NOT added is pinned too: no stored upper-house
## SEATS, because Chambers.seats() derives them, and no stored court verdict, because
## src/sim/judiciary.gd is a pure read over a law's own reach.
func _check_upper_house_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()
	var party_list: Array = loader.parties.get("FRA", [])

	var law = null
	for candidate in loader.laws:
		if candidate.constitutional:
			continue
		if not bool(Legislature.resolve_vote(ns, party_list, candidate, false)["passed"]):
			continue
		if bool(Legislature.resolve_upper(ns, party_list, candidate)["passed"]):
			continue
		law = candidate
		break
	if law == null:
		_fail("no law the Senat refuses, so the held-bill round trip measures nothing")
		return
	Legislature.propose(state, loader, law)
	if not ns.held_bills.has(law.id):
		_fail("the bill was not held, so the held-bill round trip measures nothing")
		return

	var dict: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var back = GameState.from_dict(dict)
	var bns = back.player()

	# (1) the round trip itself. The ultra pass-2 shape: the entry carries
	# {"months", "origin"} -- compared field by field, like upper_share below.
	var held_back: Dictionary = bns.held_bills.get(law.id, {})
	var held_live: Dictionary = ns.held_bills[law.id]
	if int(held_back.get("months", -1)) != int(held_live.get("months", -2)) \
			or String(held_back.get("origin", "")) != String(held_live.get("origin", "")):
		_fail("the held bill did not survive the round trip")
	# Key by key: Godot compares Dictionary `==` by REFERENCE, so a round-tripped copy
	# never equals its original and the first version of this check failed on a value that
	# had survived perfectly.
	for party_id in ns.upper_share:
		if not is_equal_approx(float(bns.upper_share.get(party_id, -1.0)), float(ns.upper_share[party_id])):
			_fail("upper_share did not survive the round trip for %s" % party_id)
	if bns.upper_seats != ns.upper_seats or bns.upper_ordinary != ns.upper_ordinary \
			or bns.upper_amendment != ns.upper_amendment or not bns.has_upper_house:
		_fail("the second chamber's static rows did not survive the round trip")

	# (2) the STATIC rows earn the bump, and the failure is that the chamber vanishes.
	var no_chamber: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	for key in ["has_upper_house", "upper_chamber_name", "upper_seats", "upper_ordinary",
			"upper_amendment"]:
		(no_chamber["nations"]["FRA"] as Dictionary).erase(key)
	var dropped = GameState.from_dict(no_chamber)
	if dropped.player().has_upper_house:
		_fail("dropping the static rows still left a second chamber")
	if Chambers.power_over(dropped.player(), law) != ChambersK.VERDICT_NONE:
		_fail("a France with no serialised Senat still claims a power over a bill")
	if not Chambers.seats(dropped.player()).is_empty():
		_fail("a France with no serialised Senat still seats one")

	# (3) `upper_share` earns it by a SECOND failure: it is accumulated state, and only a
	# legislative election rewrites it -- which for France is up to five years away. A tick
	# must NOT rebuild it, or it is derivable and the version did not need to move.
	var no_share: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_share["nations"]["FRA"] as Dictionary).erase("upper_share")
	var shareless = GameState.from_dict(no_share)
	if not shareless.player().upper_share.is_empty():
		_fail("dropping upper_share left a composition behind")
	Legislature.tick_month(shareless, loader)
	if not shareless.player().upper_share.is_empty():
		_fail("a tick rebuilt upper_share -- then it is derived and the bump was unearned")

	# (4) `held_bills` earns it by a THIRD: absent, the bill is gone and so is the
	# override price the release charges. A free escape from the obstacle.
	var no_held: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_held["nations"]["FRA"] as Dictionary).erase("held_bills")
	var escaped = GameState.from_dict(no_held)
	if escaped.player().held_bills.has(law.id):
		_fail("dropping held_bills still remembered the bill")
	var before: float = float(escaped.player().bloc_offset.get("workers", 0.0))
	for i in range(ChambersK.UPPER_HOLD_MONTHS + 1):
		Legislature.tick_month(escaped, loader)
	if not is_equal_approx(float(escaped.player().bloc_offset.get("workers", 0.0)), before):
		_fail("a tick charged an override for a bill the save had already deleted")

	# (5) WHAT IS NOT SERIALISED, pinned so a later session storing it turns this red.
	var payload: Dictionary = (state.to_dict()["nations"]["FRA"] as Dictionary)
	for absent in ["upper_seats_by_party", "upper_electorate"]:
		if payload.has(absent):
			_fail("'%s' is serialised -- the chamber's seats are DERIVED from the share" % absent)


## The court adds ONE serialised stock and one reference, and the interesting half is
## what it does not add: no stored verdict, no stored tolerance, no stored reach. The
## module is a pure read, and the ABSENCE is what pins that.
func _check_judiciary_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	var law = null
	for candidate in loader.laws:
		if candidate.id == "judicial_appointments_reform":
			law = candidate
	if law == null:
		_fail("judicial_appointments_reform is not in the law list, so the round trip measures nothing")
		return
	Legislature.apply(state, ns, law, loader)
	if is_equal_approx(ns.judicial_independence, ns.start_judicial_independence):
		_fail("the ladder did not move rule of law, so the round trip measures nothing")
		return

	var dict: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var back = GameState.from_dict(dict)
	var bns = back.player()

	# (1) the round trip.
	if not is_equal_approx(bns.judicial_independence, ns.judicial_independence):
		_fail("judicial_independence did not survive the round trip")
	if not is_equal_approx(bns.start_judicial_independence, ns.start_judicial_independence):
		_fail("start_judicial_independence did not survive the round trip")
	if bns.judicial_review != ns.judicial_review:
		_fail("judicial_review did not survive the round trip")

	# (2) `judicial_independence` earns the bump, and it is `service_quality`'s case at
	# V1.5a in its strongest form: absent it reads 0.0 against a France the World Bank
	# scores 73.8, so the tolerance goes to 1.0 and the court stops existing -- AND
	# re-deriving it from content on load would erase the erosion the player just bought.
	var no_stock: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_stock["nations"]["FRA"] as Dictionary).erase("judicial_independence")
	var dropped = GameState.from_dict(no_stock)
	if not is_equal_approx(dropped.player().judicial_independence, 0.0):
		_fail("dropping judicial_independence did not read as 0.0")
	var struck_before := 0
	var struck_after := 0
	for candidate in loader.laws:
		if Judiciary.strikes_down(ns, candidate):
			struck_before += 1
		if Judiciary.strikes_down(dropped.player(), candidate):
			struck_after += 1
	if struck_after >= struck_before:
		_fail("a France with no serialised rule of law still has a court -- the bump is unearned")
	Legislature.tick_month(dropped, loader)
	if not is_equal_approx(dropped.player().judicial_independence, 0.0):
		_fail("a tick rebuilt judicial_independence -- then it is derived and the bump was unearned")

	# (3) `judicial_review` earns it for `referendum_mode`'s reason rather than its own:
	# absent it reads "", which is Britain's, the Netherlands' and Switzerland's real
	# position and a silently different constitution for the other seven.
	var no_rule: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_rule["nations"]["FRA"] as Dictionary).erase("judicial_review")
	var ruleless = GameState.from_dict(no_rule)
	for candidate in loader.laws:
		if Judiciary.reviews(ruleless.player(), candidate):
			_fail("a France with no serialised review rule still reviews a bill")
			break

	# (4) WHAT IS NOT SERIALISED. The module is a pure read over a law's own reach and a
	# stock, so a stored verdict would mean it had become stateful.
	var payload: Dictionary = (state.to_dict()["nations"]["FRA"] as Dictionary)
	for absent in ["judicial_tolerance", "judicial_verdict", "last_judicial_result",
			"struck_law_ids"]:
		if payload.has(absent):
			_fail("'%s' is serialised -- src/sim/judiciary.gd is a pure read" % absent)

## V4.3: the six person-state registers. Values first -- an empty dict
## round-tripping as an empty dict proves nothing -- then the int-1 trap
## programme_stock's own comment names (a JSON 1.0 in a float map must come
## back the float the typed register declares), then one ABSENCE PIN per
## register: stripped from an otherwise complete payload it reads {} --
## neutral, loadable, never re-seeded -- which is the truth about every
## version-35 save and the reason the bump ships ahead of the first writer.
func _run_character_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game(FRA) reported %s" % [state.errors])
		return
	var ns = state.player()
	ns.person_loyalty["FRA_aumont"] = 0.75
	ns.person_standing["FRA_vasseur"] = 0.4
	ns.person_grudges["FRA_ferrand"] = 0.9
	ns.party_leader_override["renouveau_civique"] = "FRA_vasseur"
	ns.person_party_override["FRA_lachapelle"] = "gauche_populaire"
	ns.person_want_state["FRA_aumont|office:premiership"] = false
	ns.person_want_state["FRA_okwant|meter:grievance"] = true

	var loaded = GameState.from_dict(state.to_dict())
	var p = loaded.player()
	if abs(float(p.person_loyalty.get("FRA_aumont", 0.0)) - 0.75) > 0.0001:
		_fail("person_loyalty did not survive the round trip")
	if abs(float(p.person_standing.get("FRA_vasseur", 0.0)) - 0.4) > 0.0001:
		_fail("person_standing did not survive the round trip")
	if abs(float(p.person_grudges.get("FRA_ferrand", 0.0)) - 0.9) > 0.0001:
		_fail("person_grudges did not survive the round trip")
	if String(p.party_leader_override.get("renouveau_civique", "")) != "FRA_vasseur":
		_fail("party_leader_override did not survive the round trip")
	if String(p.person_party_override.get("FRA_lachapelle", "")) != "gauche_populaire":
		_fail("person_party_override did not survive the round trip")
	if bool(p.person_want_state.get("FRA_aumont|office:premiership", true)) != false:
		_fail("person_want_state did not survive the round trip (false entry)")
	if bool(p.person_want_state.get("FRA_okwant|meter:grievance", false)) != true:
		_fail("person_want_state did not survive the round trip (true entry)")

	ns.person_loyalty["FRA_charles_xi"] = 1.0
	var reloaded = GameState.from_dict(state.to_dict())
	if typeof(reloaded.player().person_loyalty.get("FRA_charles_xi")) != TYPE_FLOAT:
		_fail("a whole-number loyalty round-tripped as %s, not the float the register declares" % [
			type_string(typeof(reloaded.player().person_loyalty.get("FRA_charles_xi")))])

	for key in ["person_loyalty", "person_standing", "person_grudges",
			"party_leader_override", "person_party_override", "person_want_state"]:
		var stripped_dict: Dictionary = state.to_dict()
		(stripped_dict["nations"]["FRA"] as Dictionary).erase(key)
		var stripped = GameState.from_dict(stripped_dict)
		if not stripped.errors.is_empty():
			_fail("a payload stripped of %s did not load: %s" % [key, stripped.errors])
		elif not (stripped.player().get(key) as Dictionary).is_empty():
			_fail("%s stripped from the payload came back non-empty -- absence must read {}, never re-seed" % key)


## V4.6: `ns.commodity_state`, one register of seven keys. `_run_character_roundtrip`'s
## shape -- values first, then the absence pin -- with two differences the register
## itself forces. It is a Dictionary OF Dictionaries, so an empty round trip proves
## nothing about the INNER maps and every inner figure is written first; and it is
## aliasing-prone in a way the typed person maps are not, so the first thing checked
## here is that a loaded state does not SHARE its register with the state it was
## serialised from, by mutation rather than by comparison. Then the absence pin:
## stripped from an otherwise complete payload the field reads `{}` -- and unlike the
## person registers it is NOT left empty for ever, because Commodities.tick_month()
## lazily seeds it, which is the behaviour tests/test_commodities.gd's own bridge
## check owns. So this check pins what a round trip and a bare from_dict can be held
## to: the keys survive, the inner dictionaries survive, the loaded register is its
## own object, and the absent field does not CRASH the load or re-seed itself at
## from_dict time (the seed is the module's, not the loader's, and the single-writer
## pin depends on that).
func _run_commodity_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game(FRA) reported %s" % [state.errors])
		return
	var ns = state.player()
	# Move a value in EVERY one of the seven keys off its seeded default, so a
	# dropped key shows up as a dropped key rather than as a coincidence of two
	# zeros. `price` is deliberately moved only for France: it is the ONE vector
	# every nation copies, so a per-nation divergence is what a shallow or
	# per-nation-only copy would produce.
	ns.commodity_state["capacity"]["steel"] = 1234.5
	ns.commodity_state["demand"]["steel"] = 900.25
	ns.commodity_state["output"]["steel"] = 750.0
	ns.commodity_state["surplus"]["steel"] = 100.125
	ns.commodity_state["trade"]["steel"] = -50.0625
	ns.commodity_state["price"]["steel"] = 432.109375
	ns.commodity_state["value_added_eur_bn"] = 12.5

	var loaded = GameState.from_dict(state.to_dict())
	var p = loaded.player()
	# THE ALIASING PIN, and it is here because a MUTATION CHECK found the hole this
	# file had without it: with from_dict() assigning the payload dictionary
	# straight through (the naive form, `s.commodity_state = d.get(...)`), the
	# whole-register comparison below STILL PASSED -- the two states were equal,
	# because they were the SAME register. `to_dict()` returns the live field as the
	# value (`{"commodity_state": commodity_state}` copies no dictionary) and
	# commodities.gd mutates IN PLACE, so a shared register is two simulations
	# wearing one name. The probe is a write through the loaded state, read back off
	# the original: identity is only ever provable by mutation, never by `==`, which
	# compares by value and cannot tell the two apart. The probe writes a value the
	# assertions below do not read, so a failing probe can never explain a later
	# failure as its own side effect.
	p.commodity_state["capacity"]["steel"] = -1.0
	if float(ns.commodity_state["capacity"]["steel"]) == -1.0:
		_fail("from_dict() shares its commodity register with the state it was serialised from -- a write through the loaded state is visible on the original")
	p.commodity_state["capacity"]["steel"] = float(ns.commodity_state["capacity"]["steel"])
	# The nested half: `capacity` being its own dictionary is not enough if its
	# INNER dictionary is still shared, which is the shape the aliasing takes one
	# level down (a shallow duplicate passes a top-level probe).
	p.commodity_state["price"]["steel"] = -2.0
	if float(ns.commodity_state["price"]["steel"]) == -2.0:
		_fail("from_dict() shares the INNER price dictionary with the original -- a shallow rebuild is not enough")
	p.commodity_state["price"]["steel"] = float(ns.commodity_state["price"]["steel"])
	for key in ["capacity", "demand", "output", "surplus", "trade", "price"]:
		var inner: Dictionary = p.commodity_state.get(key, {})
		if abs(float(inner.get("steel", 0.0)) - float(ns.commodity_state[key]["steel"])) > FLOAT_EPS:
			_fail("commodity_state['%s']['steel'] did not survive the round trip (%s)" % [key, inner.get("steel", "missing")])
	if abs(float(p.commodity_state.get("value_added_eur_bn", 0.0)) - 12.5) > FLOAT_EPS:
		_fail("commodity_state['value_added_eur_bn'] did not survive the round trip")
	# The scale trap a small-figure fixture would hide: the capacity figures run to
	# 1e11 (transport_services), where one double ULP is 3.05e-5 -- 30x the
	# absolute walker bound. Asserted through the DISK path, because that is where
	# JSON's ~15-significant-digit form bites and the in-memory dictionary pair is
	# bit-exact and would pass either way. The tolerance is _floats_equal's, so a
	# figure that actually moved is still caught: the realised error here is one
	# ULP, and the relative bound carries ~30x slack over it.
	var sentinel := 211609027777.77774
	ns.commodity_state["capacity"]["transport_services"] = sentinel
	# The DISK path, and note the save is taken from `state` rather than from
	# `loaded`: `loaded` is a from_dict() product and its register is a REBUILD, so
	# writing through it would have proved the rebuild is writable rather than that
	# the live state's figure survives JSON. (`state` and `loaded` still share
	# nothing -- that is what nation_field_readers.commodity_state()'s rebuild exists for.)
	var commodity_clock := Clock.new()
	var disk_error := SaveManager.save_game(state, commodity_clock, COMMODITY_SLOT)
	commodity_clock.free()  # a Node created off-tree isn't owned by anything; free it explicitly
	if not disk_error.is_empty():
		_fail("save_game failed on the commodity fixture: %s" % disk_error)
	else:
		var reread := SaveManager.load_game(COMMODITY_SLOT, loader)
		if not reread["ok"]:
			_fail("load_game failed on the commodity fixture: %s" % reread["error"])
		elif not _floats_equal(float(reread["state"].player().commodity_state["capacity"]["transport_services"]), sentinel):
			_fail("a 1e11 capacity figure did not survive a real save/load (%s vs %s) -- the register is losing precision at its own scale" % [
				reread["state"].player().commodity_state["capacity"]["transport_services"], sentinel])

	var stripped_dict: Dictionary = state.to_dict()
	(stripped_dict["nations"]["FRA"] as Dictionary).erase("commodity_state")
	var stripped = GameState.from_dict(stripped_dict)
	if not stripped.errors.is_empty():
		_fail("a payload stripped of commodity_state did not load: %s" % [stripped.errors])
	elif not (stripped.player().commodity_state as Dictionary).is_empty():
		_fail("commodity_state stripped from the payload came back non-empty -- from_dict must not re-seed, the seed is Commodities' own")


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
	for slot in [ROUNDTRIP_SLOT, SECOND_NATION_SLOT, TRANSITION_SLOT, SCENARIO_SLOT, DIPLOMACY_SLOT, NETWORK_SLOT, TRADE_SLOT, COERCION_SLOT, BLOC_SLOT, ORG_FIGHT_SLOT, COMMODITY_SLOT, BOGUS_SLOT]:
		for p in [SaveManager._path_for(slot), SaveManager._path_for(slot) + SaveManager.TEMP_SUFFIX]:
			if FileAccess.file_exists(p):
				dir.remove(p)

	# The list above IS the contract, asserted rather than trusted: ORG_FIGHT
	# and NETWORK were each missing from it and their slots outlived every run
	# that wrote them (playtest B16a -- a test polluting the live slot list).
	# Any new save_game call in this file must join both lists or this goes red.
	for slot in [ROUNDTRIP_SLOT, SECOND_NATION_SLOT, TRANSITION_SLOT, SCENARIO_SLOT, DIPLOMACY_SLOT, NETWORK_SLOT, TRADE_SLOT, COERCION_SLOT, BLOC_SLOT, ORG_FIGHT_SLOT, COMMODITY_SLOT, BOGUS_SLOT]:
		if FileAccess.file_exists(SaveManager._path_for(slot)):
			_fail("cleanup left '%s' behind in %s" % [slot, SaveManager.SAVE_DIR])


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
			return _floats_equal(float(a), float(b))
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
			return _floats_equal(a, b)
		_:
			return a == b


## The float clause, one place because it is used from two. Absolute first --
## every field whose own magnitude is at or below 1e6 is held to exactly the
## bound it always was -- and the relative partner only where the magnitude can
## outrun it. `is_equal_approx` is deliberately NOT used: its tolerance is the
## engine's own and would loosen the small figures this walk exists to pin.
func _floats_equal(a: float, b: float) -> bool:
	if absf(a - b) < FLOAT_EPS:
		return true
	return absf(a - b) <= maxf(absf(a), absf(b)) * FLOAT_REL_EPS


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

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.5b raised it to 17, V1.5c to 18, V1.6a to 19, V1.6b to 20, V1.6c to 21 V1.6d to 22 and V1.6f to 23 the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)


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

	# The bump's premise, checked rather than asserted -- and rewritten at the
	# rule when V4.7a made the register SPARSE: the partition now lives in
	# content (an absent entry reads the authored share, by design), so "no
	# register" no longer means "no output". What the register alone carries is
	# the VERB STATE -- a moved share and a standing subsidy. Drop the key and
	# the share reverts to authored and the subsidy to zero, while the
	# serialised bill (its own field) keeps billing: the mismatch the bump
	# exists to prevent is still shown, and a save from before the register
	# loads as the world its era modelled -- firms at their authored partition,
	# nothing subsidised.
	var without: Dictionary = state.to_dict()
	(without["nations"]["FRA"] as Dictionary).erase("companies")
	var lost = GameState.from_dict(without)
	if not lost.player().companies.is_empty():
		_fail("an absent companies register did not read as empty -- the premise of the bump is wrong")
	for company in loader.companies["FRA"]:
		if not Companies.is_major(company):
			continue
		if not is_equal_approx(Companies.share_of_company(lost.player(), company), company.share):
			_fail("%s did not revert to its authored share with no register" % company.id)
		if Companies.subsidy_of(lost.player(), company.id) != 0.0:
			_fail("%s kept a subsidy with no register -- the verb state did not revert" % company.id)
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
	# `state_share` are the three things about a firm that MOVE; `state_share`
	# keeps exactly one writer, and `share` and `subsidy` widened at V4.7b to the
	# ledger companies.gd's header keeps (the machine's failure commit stops the
	# support). `name`, `sector`,
	# `headcount` and the AUTHORED share are content and must never appear here, for
	# the reason above: the copy in the save is the one a content edit would silently
	# disagree with. A key beyond the list still fails, so a later session storing a
	# baseline or a per-firm burden has to come and say why.
	# V4.7b widens it for the AUTONOMY fields -- all scalars, one writer each,
	# all carrying only what MOVED. The writers are the two-file ledger
	# industry.gd's header keeps: industry.gd writes the machine's fields (the
	# relocation's city override, the failure and its window, the open bid, the
	# subsidy shadow the failure hazard reads), and execute() writes the verb
	# answers (owner, courted, board_chair) and commits rescues and break-ups
	# onto failed/window. Absent, every one reads its default, which is the
	# truth about every save that predates the machine.
	const LIVE_KEYS := ["share", "subsidy", "state_share", "city", "failed",
		"rescue_months_left", "bid_bidder", "bid_price_eur_bn", "bid_months_left",
		"subsidy_shadow", "subsidy_lapsed_month", "owner", "courted", "board_chair"]
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

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.4b argued it should STAY 15, V1.5a raised it to 16, V1.5b to 17, V1.5c to 18, V1.6a to 19, V1.6b to 20, V1.6c to 21 V1.6d to 22 and V1.6f to 23 the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)


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

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.4c argued it should STAY 15, V1.5a raised it to 16, V1.5b to 17, V1.5c to 18, V1.6a to 19, V1.6b to 20, V1.6c to 21 V1.6d to 22 and V1.6f to 23 the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)


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

	# (7) V1.5d. press_freedom earns NOTHING -- absent it reads 0.0, no standing press law,
	# which is the truth about every version-18 save because those games had none to pass.
	# settlement_stance's case one session earlier, and serialised for its reason: a law
	# writes it once and no tick recomputes it, so a save that dropped it would silently
	# repeal the act.
	state.player().press_freedom = -0.4
	var with_press: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	if not is_equal_approx(float(GameState.from_dict(with_press).player().press_freedom), -0.4):
		_fail("press_freedom did not round-trip -- a law writes it once and no tick recomputes it")

	var no_press: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_press["nations"]["FRA"] as Dictionary).erase("press_freedom")
	if not is_zero_approx(GameState.from_dict(no_press).player().press_freedom):
		_fail("an absent press_freedom did not read as 0.0 -- the premise of NOT bumping for it is wrong")
	state.player().press_freedom = 0.0

	# (8) THE ASSERTION WORTH HAVING, and it is an ABSENCE. V1.5d's framing deviation is
	# measured against the size-weighted national MEAN rather than against a captured
	# baseline, so unlike service_quality, start_young_share and start_gini_index there is
	# no reference field at all -- which is exactly why SAVE_VERSION does not move.
	#
	# The design pass predicted a bump to 19 on a `start_press_stance`, and it was RIGHT
	# ABOUT THE DESIGN IT WAS GIVEN: no start_coalition_position is serialised, so an
	# absent baseline would be recomputed against the CURRENT government and a save
	# reloaded after the press turned would score the hostility as new -- start_bloc_burden
	# at V1.3d, word for word. The mean anchor deleted the field and the bump with it.
	#
	# Pinned here so a later session that stores a baseline turns this red and has to come
	# and say why, which is the device V1.3c introduced and the fifth session to use it.
	var fra_press: Dictionary = (JSON.parse_string(JSON.stringify(state.to_dict()))["nations"]["FRA"] as Dictionary)
	for key in fra_press.keys():
		var pname := String(key)
		if pname.begins_with("start_press") or pname == "start_framing_gain":
			_fail("a save carries %s -- the framing deviation is anchored on the live national mean and needs no baseline, so storing one is a model change that has to be argued" % pname)

	# framing_gain is serialised and earns nothing: Media.tick_month() rewrites it in full
	# on the next tick, so it fails soft for exactly one month -- unrest_opinion_load's case.
	var no_gain: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(no_gain["nations"]["FRA"] as Dictionary).erase("framing_gain")
	var regained = GameState.from_dict(no_gain)
	Media.tick_month(regained, loader)
	if regained.player().framing_gain.is_empty():
		_fail("framing_gain did not come back on one tick -- then it would earn a bump")

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.5c raised it to 18, V1.5d deliberately left it there, V1.6a raised it to 19, V1.6b to 20, V1.6c to 21 V1.6d to 22 and V1.6f to 23 the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)


## V1.6b. THREE of four fields earn the bump to 20 and they are asserted SEPARATELY,
## because each fails the rule by a DIFFERENT failure and a single combined check would
## let any one of the three be quietly wrong. That split is the assertion worth having
## rather than the bump, which is V1.5c's device and V1.3g's before it.
func _check_inflation_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	# The register goes live moving nothing: at new game the unemployment gap is
	# exactly 0.0, so inflation sits at its own anchor, the deviation is exactly 0.0
	# and the growth addend is exactly 0.0. Exact equality rather than
	# is_zero_approx(), which is V1.4a's precedent for a channel that must be inert.
	if ns.inflation_pct != ns.start_inflation_pct:
		_fail("inflation does not start at its own baseline -- the thirteenth issue is non-zero before anything has happened")
	if ns.inflation_pct != ns.inflation_anchor_pct:
		_fail("inflation does not start at its anchor -- init seeds a transient nobody authored")
	if ns.inflation_impulse_pct != 0.0:
		_fail("the inflation growth addend is %s at new game, not exactly 0.0" % ns.inflation_impulse_pct)

	# Displace it, so the round-trip is testing a live figure rather than a default --
	# and by LESS than INFLATION_SCALE_PP, or check (3) below compares two saturated
	# clamps and reports them equal. The first version of this used +4.0 and did
	# exactly that: both sides pinned at -1.0 and the check failed for a reason that
	# had nothing to do with the field it was about.
	ns.inflation_pct = ns.inflation_anchor_pct + 0.2
	var full: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))

	# (1) inflation_pct EARNS IT, and re-deriving on load cannot rescue it because the
	# accumulation IS the state -- service_quality's case at V1.5a and unrest_pct's at
	# V1.5c. The assertion that separates it from a derived price is that it does NOT
	# come back on one tick.
	var dropped: Dictionary = JSON.parse_string(JSON.stringify(full))
	(dropped["nations"]["FRA"] as Dictionary).erase("inflation_pct")
	var calm = GameState.from_dict(dropped)
	if not is_zero_approx(calm.player().inflation_pct):
		_fail("an absent inflation_pct did not read as 0.0 -- the premise of the bump is wrong")
	Inflation.tick_month(calm)
	if calm.player().inflation_pct >= ns.inflation_anchor_pct:
		_fail("inflation_pct recovered to its anchor on one tick, so it is derivable and the bump is unearned")

	# (2) inflation_anchor_pct EARNS IT for a DIFFERENT failure: it is content-derived
	# and from_dict() rebuilds from the dictionary ALONE, never seeing the loader --
	# cycle_amplitude_rel's case at V1.6a verbatim. Absent, the nation runs a different
	# MODEL, so the check is that the model moved and not merely that a field is 0.0.
	var no_anchor: Dictionary = JSON.parse_string(JSON.stringify(full))
	(no_anchor["nations"]["FRA"] as Dictionary).erase("inflation_anchor_pct")
	var adrift = GameState.from_dict(no_anchor)
	if not is_zero_approx(adrift.player().inflation_anchor_pct):
		_fail("an absent inflation_anchor_pct did not read as 0.0 -- the premise of the bump is wrong")
	if is_equal_approx(
		Inflation.inflation_target(adrift.player()), Inflation.inflation_target(state.player())
	):
		_fail("dropping inflation_anchor_pct left the target unchanged -- that half of the bump's premise is wrong")

	# (3) start_inflation_pct EARNS IT for a THIRD failure, and it is the sharpest:
	# absent it reads 0.0 against a live figure, so the issue is not missing but
	# MIS-SIGNED for the rest of the run. start_bloc_burden's case at V1.3d.
	var no_start: Dictionary = JSON.parse_string(JSON.stringify(full))
	(no_start["nations"]["FRA"] as Dictionary).erase("start_inflation_pct")
	var mis_signed = GameState.from_dict(no_start)
	var kept_sat: float = float(Opinion.issue_satisfaction(GameState.from_dict(full).player())["inflation"])
	var lost_sat: float = float(Opinion.issue_satisfaction(mis_signed.player())["inflation"])
	if is_equal_approx(kept_sat, lost_sat):
		_fail("dropping start_inflation_pct left the inflation issue unchanged -- that half of the bump's premise is wrong")
	# The strongest form of the claim: absent, the issue is not merely wrong but pinned
	# at the FLOOR from the first month, because the deviation it reads is the whole
	# anchor rather than the player's own movement.
	if lost_sat > -1.0 or kept_sat <= -1.0:
		_fail("an absent start_inflation_pct read %s against a kept %s -- the failure this bump names is that the issue saturates negative, and that is not what happened" % [lost_sat, kept_sat])

	# (4) inflation_impulse_pct EARNS NOTHING and is serialised anyway --
	# coercion_impulse_pct's and cycle_impulse_pct's case. It comes back in full on one
	# tick, which is exactly what separates it from (1) above.
	var no_impulse: Dictionary = JSON.parse_string(JSON.stringify(full))
	(no_impulse["nations"]["FRA"] as Dictionary).erase("inflation_impulse_pct")
	var restored = GameState.from_dict(no_impulse)
	Inflation.tick_month(restored)
	if is_zero_approx(restored.player().inflation_impulse_pct):
		_fail("inflation_impulse_pct did not come back on one tick from a displaced state -- then it would earn a bump")

	# And what was NOT added. There is no stored expectation series, no month counter
	# and no accumulated wave: the model is an anchor, a slope and a one-line lag, so a
	# later session making it stateful turns this red and has to come and say why.
	for pname in ["inflation_expectation_pct", "inflation_months", "inflation_history"]:
		if (full["nations"]["FRA"] as Dictionary).has(pname):
			_fail("a save carries %s -- the inflation model is a first-order lag on a measured anchor and needs no memory of its own, so storing one is a model change that has to be argued" % pname)

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.6b raised it to 20 on three fields of four, V1.6c to 21 on one, V1.6d to 22 on three and V1.6f to 23 on half of one the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)


## V1.6c. ONE field earns the bump to 21, and it is the smallest addition on this list
## ever to earn one -- a single float with no register behind it. The half worth pinning
## is the other one: THREE ABSENCES, because src/sim/credit.gd is stateless and staying
## stateless is the V1.6 decomposition's own split trigger.
func _check_credit_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	# The register goes live moving nothing, exactly: the spread reads 0.0 and the yield
	# reads the anchor, so every balance figure this project has quoted against a flat
	# DEBT_REAL_RATE_PCT keeps its meaning. Exact equality rather than is_zero_approx(),
	# V1.4a's precedent for a channel that must be inert.
	if Credit.spread_pct(ns) != 0.0:
		_fail("the bond spread is %s at new game, not exactly 0.0" % Credit.spread_pct(ns))
	if ns.start_debt_to_gdp_pct != ns.debt_to_gdp_pct():
		_fail("start_debt_to_gdp_pct is %s against a live %s at new game" % [
			ns.start_debt_to_gdp_pct, ns.debt_to_gdp_pct()
		])

	# Displace the stock, so the round trip tests a live figure rather than a default.
	ns.debt_eur_bn += 0.25 * ns.gdp_eur_bn
	Budget.recompute(state, ns)
	var full: Dictionary = state.to_dict()

	var kept = GameState.from_dict(full)
	if absf(Credit.yield_pct(kept.player()) - Credit.yield_pct(ns)) > 1e-9:
		_fail("the yield does not survive a round trip: %s against %s" % [
			Credit.yield_pct(kept.player()), Credit.yield_pct(ns)
		])

	# THE BUMP. Absent, start_debt_to_gdp_pct reads 0.0 against a live ~135, so the debt
	# gap reads the whole stock as newly borrowed and the yield goes to the clamp -- a
	# reloaded game running a different MODEL from the one that saved it, which is
	# `cycle_amplitude_rel` at V1.6a and `military_capability` at V1.3g.
	var dropped: Dictionary = state.to_dict()
	(dropped["nations"]["FRA"] as Dictionary).erase("start_debt_to_gdp_pct")
	var adrift = GameState.from_dict(dropped)
	if not is_zero_approx(adrift.player().start_debt_to_gdp_pct):
		_fail("an absent start_debt_to_gdp_pct did not read as 0.0 -- the premise of the bump is wrong")
	# NOT the clamp, and the first version of this check said the clamp. Measured: the
	# yield comes back at 4.1 against a kept 2.4, which is a France paying seventy per
	# cent more interest for the rest of the run because it saved. Large, permanent and
	# silent is the failure the rule is about; "on the clamp" was a guess and the check
	# is written against the number instead.
	var adrift_yield: float = Credit.yield_pct(adrift.player())
	var kept_yield: float = Credit.yield_pct(kept.player())
	if adrift_yield <= kept_yield * 1.5:
		_fail("dropping start_debt_to_gdp_pct moved the yield from %s to %s -- less than the standing overcharge this bump names" % [kept_yield, adrift_yield])

	# And re-deriving on load does not rescue it, which is what separates this field from
	# every derived price on this list: one tick does not bring it back, and re-anchoring
	# on the live ratio would silently forgive every point of debt the player has added.
	Economy.tick_month(adrift)
	Budget.tick_month(adrift)
	if not is_zero_approx(adrift.player().start_debt_to_gdp_pct):
		_fail("start_debt_to_gdp_pct came back on one tick, so it is derivable and the bump is unearned")

	# WHAT WAS NOT ADDED, and this is the assertion worth having. The yield, the spread
	# and the rating are pure reads over a debt stock serialised since the MVP and a
	# grievance serialised at V1.5c. A later session storing any of them has made
	# src/sim/credit.gd stateful, which is the V1.6 decomposition's stated split trigger
	# for this session -- so it turns this red and has to come and say why.
	for pname in ["bond_yield_pct", "credit_spread_pct", "credit_rating",
			"start_bond_yield_pct", "credit_rating_months"]:
		if (full["nations"]["FRA"] as Dictionary).has(pname):
			_fail("a save carries %s -- src/sim/credit.gd is a pure read over the debt stock and the grievance, so storing one is the second machine the V1.6 decomposition says would have split this session" % pname)


## V1.6d. THREE fields earn the bump to 22, and two of them add no key to the save at
## all -- they GROW `tax_rates_pct`, a dictionary serialised since S4, which is V1.5b's
## `service_quality["pensions"]` case and the second time on this list. The three are
## asserted in TWO groups rather than three, and the grouping is the claim: the two rates
## fail by one failure each, and the bracket pair fails by ONE failure BETWEEN THEM.
func _check_tax_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var full: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))

	# (1) THE TWO NEW RATES. A version-21 save carries three keys in `tax_rates_pct`, and
	# revenue_lines() reads `.get(key, 0.0)` -- so both new taxes come back at a rate of
	# zero and the save has silently ABOLISHED them. France collects 0.6 points of GDP of
	# capital-gains tax at its own authored rate; that is what a reloaded game loses, and
	# the deficit widens by it with nothing anywhere to say so.
	var no_rates: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var rates: Dictionary = (no_rates["nations"]["FRA"] as Dictionary)["tax_rates_pct"]
	rates.erase("capital_gains")
	rates.erase("wealth")
	var stripped = GameState.from_dict(no_rates)
	Budget.recompute(stripped, stripped.player())
	if not is_zero_approx(float(stripped.player().revenue_pct_gdp.get("capital_gains", 0.0))):
		_fail("dropping the capital_gains rate left the line collecting something -- that half of the premise is wrong")
	if is_equal_approx(stripped.player().deficit_pct_gdp, state.player().deficit_pct_gdp):
		_fail("a save with both new tax rates dropped runs the same deficit as one with them, so the two keys would not earn the bump")

	# The matching start keys go too, which is the sharper half: `_erosion()` divides by
	# the nation's own start, so an absent one falls to the ZERO-REFERENCE branch and
	# every later rate rise is priced as a tax invented from nothing rather than as a
	# rise in one the country already levies. A reloaded game running a DIFFERENT MODEL,
	# which is `eu_member` at V1.3b.
	var no_start: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	((no_start["nations"]["FRA"] as Dictionary)["start_tax_rates_pct"] as Dictionary).erase("capital_gains")
	var restarted = GameState.from_dict(no_start)
	restarted.player().tax_rates_pct["capital_gains"] = 40.0
	Budget.recompute(restarted, restarted.player())
	var kept = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	kept.player().tax_rates_pct["capital_gains"] = 40.0
	Budget.recompute(kept, kept.player())
	if is_equal_approx(
		float(restarted.player().revenue_pct_gdp["capital_gains"]),
		float(kept.player().revenue_pct_gdp["capital_gains"])
	):
		_fail("dropping start_tax_rates_pct.capital_gains priced a later rise identically -- then the start keys would not earn the bump")

	# (2) THE BRACKET PAIR, asserted TOGETHER and deliberately not separately. Absent,
	# both read 0.0 -- which is PROGRESSIVITY_MIN, the flattest schedule the model has,
	# and NOT a neutral default. But because the START reads 0.0 as well, the DEVIATION is
	# still exactly zero, so the reloaded game does not merely forget the player's bracket
	# structure: it agrees a flat tax was always normal, and every price keyed to the
	# deviation reads as though nothing had ever been done. Neither field alone fails in a
	# way the other does not cover, so splitting the check would be checking one failure
	# twice -- which is the opposite of V1.6b's three, and the reason is written here
	# rather than left for a reader to infer.
	var committed = GameState.new_game(loader, "FRA")
	Budget.commit(committed, {"tax_progressivity": TaxK.PROGRESSIVITY_BASE + 0.6})
	var moved := Tax.gini_policy_offset(committed.player())
	if is_zero_approx(moved):
		_fail("a committed bracket change moved nothing, so this check is not measuring what it says")

	var no_brackets: Dictionary = JSON.parse_string(JSON.stringify(committed.to_dict()))
	(no_brackets["nations"]["FRA"] as Dictionary).erase("tax_progressivity")
	(no_brackets["nations"]["FRA"] as Dictionary).erase("start_tax_progressivity")
	var flattened = GameState.from_dict(no_brackets)
	if not is_zero_approx(Tax.gini_policy_offset(flattened.player())):
		_fail("a save with both bracket fields dropped still carried the player's schedule -- then neither would earn the bump")
	if not is_zero_approx(Tax.progressivity_deviation(flattened.player())):
		_fail("with both fields absent the DEVIATION is not zero, so the pair does not fail the way this check claims and they should be asserted separately")

	# (3) WHAT WAS NOT ADDED, and it is the half worth pinning -- V1.6c's shape one
	# session on. src/sim/tax.gd is stateless, so there is no stored offset, no stored
	# effective index and no stored base factor: each is a pure read over one float and
	# two rates this save already carries. A later session giving the distribution an
	# accumulator turns this red and has to come and say why.
	for pname in ["gini_policy_offset", "gini_effective", "start_tax_rates_progressivity",
			"progressivity_base_factor", "tax_progressivity_months"]:
		if (full["nations"]["FRA"] as Dictionary).has(pname):
			_fail("a save carries %s -- the distribution is a derived read over fields the save already has, so storing one is a model change that has to be argued" % pname)

	# And `gini_index` keeps its single writer. The effective index is a SUM of that
	# drift and a derived offset, which is what the V1.6 decomposition's "a second field,
	# not a second writer" asked for -- one step further, because there is no second
	# field either.
	var demog_src := FileAccess.get_file_as_string("res://src/sim/tax.gd")
	if demog_src.contains("gini_index ="):
		_fail("src/sim/tax.gd assigns gini_index -- Demography.tick_month() is its single writer")

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.6c raised it to 21, V1.6d to 22 on three fields and V1.6f to 23 on half of one the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)


## V1.6e. THE REGISTER EARNS NOTHING AND IS SERIALISED ANYWAY, and the two halves are
## checked separately because they are two different claims.
##
## The rule game_state.gd states is "would a missing field read as something WRONG",
## and for a version-22 save the answer is no: those games had no investment verb, so
## "no programme running and nothing built" is the truth about them rather than a soft
## failure. `measures` at V1.3c, `pacts` at V1.3g and `regulation_burden` at V1.4b.
##
## What is not free is the other half. The capital stock is written by a tick and NO
## TICK RE-DERIVES IT FROM CONTENT -- unlike V1.4a's four prices, which come back on
## the next tick, and unlike `start_service_quality`, which round-trips through
## data/nations/. A save that dropped it would silently demolish everything the player
## spent a term building, so the premise is CHECKED rather than asserted: dropping the
## register must move the trend shift.
func _check_investment_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	# (1) A NEW GAME CARRIES THE REGISTER AND IT IS INERT. Exact equality, because that
	# is the property the balance re-run's bit-identity rests on.
	var fresh: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var fresh_entry = (fresh["nations"]["FRA"] as Dictionary).get("sector_investment")
	if fresh_entry == null:
		_fail("a save does not carry sector_investment at all")
	elif not (fresh_entry as Dictionary).has("industry"):
		_fail("the serialised register has no industry entry")
	if Investment.national_trend_shift_pct(GameState.from_dict(fresh).player()) != 0.0:
		_fail("a reloaded new game has a non-zero trend shift")

	# (2) THE PREMISE, CHECKED. A programme run for five years, then the register
	# dropped: the trend shift must fall to zero, or serialising it buys nothing.
	for a in loader.investment_actions:
		if a.id == "reindustrialisation":
			Investment.execute(state, ns, loader.investment_actions, a)
	for _m in range(60):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Investment.tick_month(state)

	var built: float = Investment.national_trend_shift_pct(ns)
	if is_zero_approx(built):
		_fail("five years of investment moved nothing, so this check is not measuring what it says")

	var full: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var dropped: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(dropped["nations"]["FRA"] as Dictionary).erase("sector_investment")
	var demolished = GameState.from_dict(dropped)
	if not is_zero_approx(Investment.national_trend_shift_pct(demolished.player())):
		_fail("a save with sector_investment dropped still carried the capital -- then serialising it buys nothing")
	if Investment.intensity_of(demolished.player(), "industry") != 0.0:
		_fail("a dropped register still reports a standing programme")

	# And the round trip keeps both halves of every entry.
	var kept = GameState.from_dict(full)
	if not is_equal_approx(Investment.capital_of(kept.player(), "industry"), Investment.capital_of(ns, "industry")):
		_fail("the capital stock did not survive the round trip")
	if not is_equal_approx(Investment.intensity_of(kept.player(), "industry"), Investment.intensity_of(ns, "industry")):
		_fail("the standing intensity did not survive the round trip")

	# (3) THE ENTRY CARRIES EXACTLY TWO KEYS, which is V1.4a's own device pointed at a
	# new register: a later session storing a per-sector baseline, a cached shift or a
	# months counter turns this red and has to come and say why. The shift is a DERIVED
	# read over the capital and the sector shares, both of which the save already has.
	var entry: Dictionary = (full["nations"]["FRA"] as Dictionary)["sector_investment"]["industry"]
	for key in entry.keys():
		if key != "intensity" and key != "capital":
			_fail("a serialised investment entry carries '%s' -- two keys is the whole register" % key)
	if entry.size() != 2:
		_fail("a serialised investment entry has %d keys, expected exactly 2" % entry.size())

	# (4) WHAT WAS NOT ADDED. src/sim/investment.gd caches only the bill, so there is no
	# stored shift and no stored national figure.
	for pname in ["sector_trend_shift", "investment_trend_shift_pct", "investment_capital"]:
		if (full["nations"]["FRA"] as Dictionary).has(pname):
			_fail("a save carries %s -- the trend shift is a derived read, so storing one is a model change that has to be argued" % pname)

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.6d raised it to 22, V1.6e argued it should STAY there and V1.6f is what moved it to 23 -- on its OWN register, not on this one the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)


## V1.6f. THE BUMP TO 23, AND IT IS EARNED BY HALF OF ONE FIELD -- which is V1.3g's
## `deployments` split in a new place and, as there, the SPLIT is the assertion worth
## having rather than the bump.
##
## `NationState.projects` is one dictionary carrying two things:
##
##   the BUILDING half fails soft. An absent register reads as "nothing under
##   construction", which is the truth about every version-22 save because those games
##   had no project verb -- `measures` at V1.3c, `sector_investment` at V1.6e.
##
##   the DONE half does not. A France that finished the rail spine has bought a
##   permanent claim on its own trend, and an absent register erases the record of it.
##   Nothing re-derives it: the accumulator is the only other trace and it is not
##   content, so there is nothing to re-derive FROM.
##
## The two are checked separately, because a single combined assertion would let either
## half be quietly wrong.
## V2.2a. SAVE_VERSION stays at 27, and WHAT WAS NOT ADDED is the whole of it --
## which is V1.6c's shape and V1.8's, and the third time this list has had a session
## whose serialised contribution is nothing at all.
##
## The register is CONTENT. A region's share of its nation and a city's share of its
## region round-trip through data/regions/ the way a firm's authored share and
## headcount round-trip through data/companies/ (V1.4a), and a firm's `city` is one
## more authored field in a file the save has never carried. Nothing ticks, nothing
## accumulates, and there is no reference value to anchor a deviation against --
## because there is no deviation: docs/tiers/v2.md section 5 is the session that gives
## a region a quantity that moves, and section 6 the one that moves people between
## cities.
##
## So this pinned three ABSENCES rather than three fields, and each one turned red for
## a different reason. A stored region share means the partition can drift from the
## content that defines it. A stored city population means a head count exists that
## `share x population` does not already give. And a `regions` key on NationState at
## all means the register has become live state, which is precisely the change V2.5
## has to come here and argue for.
##
## V2.5 FLIPPED ONE OF THESE THREE AND LEFT THE OTHER TWO, which is the assertion
## worth having. `region_gdp_eur_bn` is now live state and MUST be present -- a save
## without it loads a nation whose GDP is the sum of nothing. The SHARES are still
## content and still round-trip through data/regions/, and there is still no head
## count on a city, so those two stay red the day somebody stores them.
##
## V2.6a FLIPPED THE OTHER TWO, and the one that is left is the one worth having.
## The two SHARES are live state now: a region's share of its nation's population and
## a city's share of its region both move every month, and a save without them loads a
## country whose cities all have a population of zero -- no glyph on the map at any
## zoom, an empty league table in both panels. Re-seeding from the authored shares
## does NOT rescue them, which is what separates this from every derived price on this
## list: re-seeding would erase the movement the save exists to remember.
##
## WHAT STAYS RED is a stored city POPULATION. A head count is `population x share x
## share` and the two shares are now both here, so storing one would be a second
## answer to a question these already answer -- and the day somebody does, this fails
## and has to come and say why.
func _check_geography_absences(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var fresh: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var fresh_nation: Dictionary = fresh["nations"]["FRA"]

	for key in ["region_population", "city_population"]:
		if fresh_nation.has(key):
			_fail("a save carries `%s` -- a head count is population x share x share, and storing one is a second answer to a question two live shares already answer" % key)
	if fresh_nation.has("regions") or fresh_nation.has("cities"):
		_fail("a save carries a top-level region register -- the register itself is still content and round-trips through data/regions/")
	for key in ["region_gdp_eur_bn", "region_pop_share", "city_pop_share"]:
		if not fresh_nation.has(key):
			_fail("a save does not carry `%s`" % key)

	# The bump, and the failure it prevents, checked rather than asserted: drop either
	# share register from a round trip and every city in the country has a population
	# of zero.
	for key in ["region_pop_share", "city_pop_share"]:
		var stripped_shares: Dictionary = fresh.duplicate(true)
		(stripped_shares["nations"]["FRA"] as Dictionary).erase(key)
		var reloaded_shares = GameState.from_dict(stripped_shares)
		var back: Dictionary = reloaded_shares.nations["FRA"].get(key)
		if not back.is_empty():
			_fail("a save stripped of `%s` came back with one -- this check is measuring nothing" % key)

	# region_gdp_eur_bn's own strip check, from V2.5, unchanged by this session: it
	# earned the bump on a different failure (the country has no economy at all) and
	# keeps its own proof rather than folding into the loop above.
	var stripped: Dictionary = fresh.duplicate(true)
	(stripped["nations"]["FRA"] as Dictionary).erase("region_gdp_eur_bn")
	var reloaded = GameState.from_dict(stripped)
	if not reloaded.nations["FRA"].region_gdp_eur_bn.is_empty():
		_fail("a stripped save came back with a region register -- this check is measuring nothing")

	# The domicile is authored too, and it is the one V2.2a field a reader might
	# expect to find here: it is read every time a panel asks what a city employs.
	# It is not saved, because Company.city comes back off the loader with the rest of
	# data/companies/ -- the same reason a firm's authored share is not saved either.
	var companies_entry = fresh_nation.get("companies", {})
	if typeof(companies_entry) == TYPE_DICTIONARY:
		for firm_id in (companies_entry as Dictionary).keys():
			var entry = companies_entry[firm_id]
			if typeof(entry) == TYPE_DICTIONARY and (entry as Dictionary).has("city"):
				_fail("the save carries a firm's city -- a domicile is content, not state")

	# V2.6b1. THE SITE IS DERIVED AND NOTHING STORES IT, which is why this session
	# moves no version at all. A place is arg-max over two live share registers that
	# are already here, so a stored site would be a second answer to a question those
	# shares answer -- `region_population`'s case above, one quantity over -- and a
	# stored concentration or output index would be a third and a fourth.
	#
	# The day a session stores one, this fails and has to come and say why: a site
	# that is state rather than a read has to survive Budget.project(), which runs the
	# real model on a DUPLICATE, and V2.6b1's whole no-bump claim rests on the
	# projection and the tick deriving the same place from the same shares.
	for key in ["unrest_site", "unrest_site_id", "unrest_site_region", "site_concentration", "unrest_site_impulse"]:
		if fresh_nation.has(key):
			_fail("a save carries `%s` -- V2.6b1 derives the site from two live share registers every read, and storing one is a second answer to a question those already answer" % key)

	# The act RECORD carries the place, and that is a different thing from state: it is
	# written once at the moment of the act because a past act's site cannot be
	# re-derived after the shares have moved, and it is read by src/ui/main.gd's card
	# and by nothing in src/sim/. Absent -- every act on a version-29 save -- it reads
	# as "no place" and the card falls back to the national wording it has always had,
	# so it earns no bump and the loop above is what pins the distinction.
	if typeof(fresh.get("unrest_acts", [])) != TYPE_ARRAY:
		_fail("a save's unrest_acts is not an array")

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.1e raised it to 27 and V2.5 to 28, on `region_gdp_eur_bn`: national GDP is the sum of the regions now, so a save without the register has no economy at all rather than a quietly different one; V2.6a raised it to 29, on two live population shares -- national GDP already has no economy without a register, and now every city has no population without one either; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)



## V2.7. SAVE_VERSION STAYS 30, AND WHAT WAS NOT ADDED IS THE WHOLE OF IT -- V1.6c's
## shape and V2.2a's, and the fifth session on this list whose serialised
## contribution is nothing at all.
##
## THREE ABSENCES, PINNED APART because they fail the rule for three different
## reasons and a combined check would let any one of them be quietly wrong:
##   (1) the GRAPH is content on disk. A save carrying it would be a second copy of
##       data/geo/region_graph.json, and the copy is the one that drifts.
##   (2) the ACCESSIBILITY INDEX is a pure read over a static graph and the output
##       shares V2.5 already serialises -- src/sim/credit.gd's stateless shape. A
##       stored index would be a second answer to a question the register answers.
##   (3) a project's SITE REGION is derived from an authored lon/lat on every read.
##       Storing it would let a save disagree with data/nations/ about where the rail
##       spine is.
##
## The day a session gives the graph an accumulator -- a road that gets built, an
## edge whose cost the player moves -- this turns red and has to come and say why.
## That is the point of pinning an absence rather than writing a paragraph.
func _check_network_absences(loader) -> void:
	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V2.6b2 raised it to 30 on two campaign-sited registers and V2.7 argues it should STAY there: the graph is content on disk, the accessibility index is a pure read over shares V2.5 already serialises, and a project's site is derived from an authored coordinate. V2.8's reason is recorded and is three content-derived statics, none of them a graph accumulator. A further bump needs its own recorded reason; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org (an absent register is no council and no rules, wrong rather than empty), `NationState.orgs`, live membership (absent it a reloaded France belongs to nothing and pays nothing), and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero), and the fight `phase` (absent it a membership fight matches nothing and is stranded); V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)
	var state = GameState.new_game(loader, "FRA")
	var payload: Dictionary = state.to_dict()
	for absent in ["region_graph", "region_accessibility", "project_site_region", "project_sited_pct"]:
		if payload.has(absent):
			_fail("GameState.to_dict() carries '%s' -- V2.7 pins its absence" % absent)
	var nation: Dictionary = payload["nations"]["FRA"]
	for absent in ["accessibility", "network_deviation_pct", "site_region"]:
		if nation.has(absent):
			_fail("NationState.to_dict() carries '%s' -- V2.7 pins its absence" % absent)

	# And "content, not saved" must not become "content, not loaded either": through
	# the real SaveManager, a loaded state carries the graph and runs a month on it.
	var edges_on_disk := 0
	var text := FileAccess.get_file_as_string("res://data/geo/region_graph.json")
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("edges"):
		edges_on_disk = (parsed as Dictionary)["edges"].size()
	if edges_on_disk == 0:
		_fail("data/geo/region_graph.json did not parse -- the load check below would be measuring nothing")
	var network_clock := Clock.new()
	var save_error := SaveManager.save_game(state, network_clock, NETWORK_SLOT)
	network_clock.free()  # same off-tree rule; this one predates V4.6 but is the same class
	if not save_error.is_empty():
		_fail("save_game(FRA) failed: %s" % save_error)
		return
	var result := SaveManager.load_game(NETWORK_SLOT, loader)
	if not result["ok"]:
		_fail("load_game(FRA) failed on a save this test just wrote: %s" % result["error"])
		return
	var loaded = result["state"]
	if loaded.region_graph.is_empty():
		_fail("a loaded state carries no region graph -- content re-attachment was lost on the load path")
		return
	var loaded_edges: int = (loaded.region_graph.get("edges", []) as Array).size()
	if loaded_edges != edges_on_disk:
		_fail("a loaded state carries %d graph edges against %d on disk" % [loaded_edges, edges_on_disk])
	# One real month with the network term live: the loaded state runs the same
	# expression the pre-save state ran, and both move without error.
	Economy.tick_month(loaded)
	Economy.tick_month(state)


## V2.8 BUMPS TO 31 ON THREE FIELDS OF EIGHT, AND THEY FAIL THE RULE BY THE SAME
## FAILURE -- which is why they are asserted TOGETHER here and the ones that earn
## nothing are asserted apart below. V1.6a's finding is the whole reason: a module
## being stateless is a property of the module, not of the save file, because
## NationState.from_dict() rebuilds from the dictionary ALONE and never sees the
## loader. So every content-derived static that lives on this class is already in
## the save, and dropping one runs a DIFFERENT MODEL from the one that saved it.
##
##   start_energy_mix            absent -> {} -> mix() returns zeros, the partition
##                               is not there, and every dependency reading is the
##                               full measured level appearing at once.
##   start_import_dependency_pct absent -> 0.0 -> the deviation becomes the whole
##                               dependency, so a France that has imported half its
##                               energy for fifty years reads as having just started.
##   energy_kwh_per_capita       absent -> 0.0 -> national_twh() is 0.0, and one
##                               plant is then the country's whole electricity.
##   start_co2e_per_capita_t     absent -> 0.0 -> emissions_tonnes() is the fleet's
##                               deviation alone, so a reloaded France reads a
##                               decarbonised country against a live 4.0 t/capita.
##
## start_debt_to_gdp_pct at V1.6c and cycle_amplitude_rel at V1.6a, in their
## strongest form yet: all of them are re-derivable in principle and NONE of them
## is re-derived, because from_dict() has nothing to re-derive them from. V3.5
## adds the fourth in the same shape, one field.
func _check_energy_bump(loader) -> void:
	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d, expected 39 -- V2.8's three content-derived statics began the reason chain this pin carries; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the six person-state registers; V4.6's reason is recorded and is `ns.commodity_state` -- the seven-key goods register, a country that can make nothing and holds no price vector when it is absent, and the ONE world price the case a re-derivation cannot rescue; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable), `ns.draft_bills`, `ns.custom_laws`, `ns.custom_taxes`, `ns.poll_purchases` and `ns.assembly_bills` (composition in flight, passed composed laws, a proposed key's base and erosion, paid polls, and private members' bills -- the held_bills free-escape class); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital"
			% GameState.SAVE_VERSION)
	var payload: Dictionary = GameState.new_game(loader, "FRA").to_dict()
	for field in ["start_energy_mix", "start_import_dependency_pct", "energy_kwh_per_capita", "start_co2e_per_capita_t"]:
		if not payload["nations"]["FRA"].has(field):
			_fail("a version-35 save must carry %s" % field)


## `plants` EARNS NOTHING and is serialised anyway. Absent it reads as {}, which is
## "nothing built" -- true of every version-30 save, because those games had no
## energy verb at all. `measures`' case at V1.3c, `pacts`' at V1.3g, `appointments`'
## at U6a. It is carried regardless because a verb writes it and no tick recomputes
## it, so a save that dropped it would silently demolish every station the player
## built while continuing to bill for none of them.
##
## `plant_seq` earns nothing for the same reason and is carried for a different
## one: it is monotone, so dropping it lets a later plant re-use a decommissioned
## id and make two stations one row.
##
## `energy_bill_pct_gdp` and `import_dependency_pct` earn nothing -- both are
## recomputed from the register on the first tick, project_bill_pct_gdp's case.
##
## And `last_energy_result` is NOT serialised at all, last_project_result's case.
func _check_energy_absences(loader) -> void:
	var payload: Dictionary = GameState.new_game(loader, "FRA").to_dict()
	if payload["nations"]["FRA"].has("last_energy_result"):
		_fail("last_energy_result must not be serialised -- it is a display record")

	# V3.5. There is no cumulative-emissions register and no temperature term: the
	# accord's rule reads the per-capita FLOW the tick rewrites, and a stock would
	# need its own bump argument (V1.6a's trap, named in the handoff). Pinned at
	# both levels a field could land at, so a later session cannot add one by
	# accident without coming and saying why.
	for absent in ["cumulative_emissions_tonnes", "temperature_anomaly_c"]:
		if payload.has(absent) or payload["nations"]["FRA"].has(absent):
			_fail("a save carries %s -- the emissions read is a flow re-derived from the mix every tick, and a stock is a model change that has to be argued" % absent)


## V4.1 bumps to 35 on the government's programme, and this check carries the
## absences beside the bump the way V2.7's and V2.8's carry theirs:
##
##   ns.programme            the chosen register -- a verb writes it
##                           (Programme.choose) and no tick recomputes it, so a
##                           dropped register un-prices a term the player lived.
##   programme_chosen_term   the one-choice-per-term scalar -- dropped, a lived
##                           term reads as never chosen and the offer re-opens.
##   programme_stock         the bounded credit the conclusion pulses feed --
##                           dropped, every delivery the player watched wipes to
##                           a clean slate.
##
## And WHAT IS NOT THERE is pinned with them: progress is Programme.progress_of()
## over the live figure, never stored -- a cached copy could disagree with the
## figure it reads and then the panel lies. The injection check below is what
## turns red the day a serialiser starts caching it.
func _check_programme_fields(loader) -> void:
	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d, expected 39 -- V4.1 raised it on the government's programme: the chosen register `ns.programme` and the stock the conclusion pulses feed `programme_stock`, because a save that dropped either un-prices a term the player already lived -- the term reads as never chosen, its conclusions as never delivered, the record wiped to a clean slate. Progress earns NOTHING: it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and the injection check below is what pins that; V4.3's reason is recorded and is the six person-state registers; V4.6's reason is recorded and is `ns.commodity_state`, the seven-key goods register whose absence reads as a country that can make nothing and holds no price vector; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable), `ns.draft_bills`, `ns.custom_laws`, `ns.custom_taxes`, `ns.poll_purchases` and `ns.assembly_bills` (composition in flight, passed composed laws, a proposed key's base and erosion, paid polls, and private members' bills -- the held_bills free-escape class); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital"
			% GameState.SAVE_VERSION)

	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	# A fresh game IS a term start (Elections.init_nation() seeds months_in_term
	# = 0), so the choice needs no clock staging -- test_programme.gd's fixture.
	# It leaves programme_chosen_term at 0, off the -1 default, which is what
	# makes the round trip below able to catch a dropped field at all.
	if not bool(Programme.choose(state, ns, "prog_jobs_first", loader).get("applied", false)):
		_fail("no programme could be chosen at term start, so this check measures nothing")
		return
	# One register tick advances the entry's clock. France's seeded unemployment
	# (7.4) sits between the entry's complete (<= 7) and fail (>= 10) triggers, so
	# the entry stays active and months_live is the only thing that moves.
	ns.months_in_term = 1
	Programme.tick_month(state, loader)
	if String(ns.programme[0]["status"]) != "active" or int(ns.programme[0]["months_live"]) != 1:
		_fail("the fixture entry did not come through one register tick as active with months_live 1 -- the fixture is wrong, not the save")
		return
	# The stock has no writer until the pulse task wires Opinion -- staged by hand
	# the way start_bloc_burden is staged in _run_bloc_roundtrip(). Negative, so a
	# sign flip cannot hide behind the +1 a completion would carry.
	ns.programme_stock = -0.5

	# THE ROUND TRIP, through the JSON path a real save takes. The register is
	# decision state and the stock is accumulated state -- both must survive to
	# the last bit.
	var full: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var kept = GameState.from_dict(full)
	var kept_ns = kept.player()
	if kept_ns.programme.size() != ns.programme.size():
		_fail("the programme register did not survive the round trip")
	var allowed := [
		"entry_id", "chosen_term", "months_live", "status",
		"concluded_term", "concluded_term_month",
	]
	for i in ns.programme.size():
		var a: Dictionary = ns.programme[i]
		var b: Dictionary = kept_ns.programme[i]
		for key in allowed:
			if str(a.get(key)) != str(b.get(key)):
				_fail("programme[%d].%s did not survive the round trip: %s -> %s" % [i, key, a.get(key), b.get(key)])
	if int(kept_ns.programme_chosen_term) != int(ns.programme_chosen_term):
		_fail("programme_chosen_term did not survive the round trip: %d -> %d" % [int(ns.programme_chosen_term), int(kept_ns.programme_chosen_term)])
	if float(kept_ns.programme_stock) != float(ns.programme_stock):
		_fail("programme_stock did not survive the round trip exactly: %f -> %f" % [float(ns.programme_stock), float(kept_ns.programme_stock)])

	# THE SIX KEYS, on the SERIALISED register rather than the live one -- a save
	# that cached content or progress alongside the decision is the defect this
	# catches, and the live register's own pin (tests/test_programme.gd) cannot
	# see it.
	var serialised: Array = full["nations"]["FRA"]["programme"]
	for entry in serialised:
		for key in (entry as Dictionary).keys():
			if not allowed.has(String(key)):
				_fail("a serialised programme entry carries '%s' -- the six decision keys are the whole register" % key)

	# PROGRESS IS NEVER STORED, at both places a field could land: beside the
	# register on the nation, or cached inside an entry. The injection is the
	# V1.6a device pointed at the derived read -- a cached copy must come back on
	# nothing and move nothing, because progress never read it at all.
	for absent in ["programme_progress", "programme_progress_pct", "programme_current_value"]:
		if full.has(absent) or (full["nations"]["FRA"] as Dictionary).has(absent):
			_fail("a save carries %s -- progress is Programme.progress_of() over the live figure, and a stored copy drifts from it" % absent)
	var cached: Dictionary = full.duplicate(true)
	((cached["nations"]["FRA"]["programme"] as Array)[0] as Dictionary)["programme_progress"] = 0.73
	var injected = GameState.from_dict(cached)
	if (injected.player().programme[0] as Dictionary).has("programme_progress"):
		_fail("a cached progress value survived the load -- progress is never stored")
	var content: Dictionary = {}
	for e in loader.programme:
		if String(e["id"]) == "prog_jobs_first":
			content = e
	if content.is_empty():
		_fail("prog_jobs_first is not in data/programme/ -- the fixture is wrong, not the save")
		return
	var before: Dictionary = Programme.progress_of(ns, content)
	var after: Dictionary = Programme.progress_of(injected.player(), content)
	if not is_equal_approx(float(before["current_value"]), float(after["current_value"])):
		_fail("the derived progress read moved on a payload that carried no stored progress -- progress is not derived, and the bump's own argument is wrong")
	if not is_equal_approx(float(before["goal_value"]), float(after["goal_value"])):
		_fail("the authored goal moved on the round trip")
	if String(before["progressbar"]) != String(after["progressbar"]):
		_fail("the authored direction moved on the round trip")

	# THE ABSENCE: a save carrying none of the three keys reads as "no programme
	# chosen" -- empty register, chosen_term -1, stock 0.0 -- which was the truth
	# about every version-34 save, made by code with no programme verb on any tick
	# path. Erased at the nation level, where the keys live.
	var stripped: Dictionary = full.duplicate(true)
	(stripped["nations"]["FRA"] as Dictionary).erase("programme")
	(stripped["nations"]["FRA"] as Dictionary).erase("programme_chosen_term")
	(stripped["nations"]["FRA"] as Dictionary).erase("programme_stock")
	var amnesiac = GameState.from_dict(stripped)
	var a_ns = amnesiac.player()
	if not a_ns.programme.is_empty():
		_fail("a save with no programme register came back with one")
	if int(a_ns.programme_chosen_term) != -1:
		_fail("a save with no programme_chosen_term did not read as 'never chosen'")
	if not is_equal_approx(float(a_ns.programme_stock), 0.0):
		_fail("a save with no programme_stock did not read as a zero stock")


func _check_project_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()

	# (1) A NEW GAME CARRIES AN EMPTY REGISTER AND A ZERO ACCUMULATOR. Exact equality,
	# because that is the property the balance re-run's bit-identity rests on.
	var fresh: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var fresh_nation: Dictionary = fresh["nations"]["FRA"]
	if not fresh_nation.has("projects"):
		_fail("a save does not carry `projects` at all")
	if not (fresh_nation["projects"] as Dictionary).is_empty():
		_fail("a new game's project register is not empty")
	if GameState.from_dict(fresh).player().project_potential_target_pct != 0.0:
		_fail("a reloaded new game has a non-zero project payoff")

	# (2) THE BUILDING HALF FAILS SOFT. A project begun and not finished, register
	# dropped: nothing is lost that a version-22 save could have had, because a
	# version-22 save could not have begun one.
	for a in loader.project_actions:
		if a.id == "start_flood_defence":
			Projects.execute(state, ns, loader.project_actions, a)
	if Projects.building_count(ns) != 1:
		_fail("the project the check needs did not start")
	for _m in range(6):
		Projects.tick_month(state, loader)
	var mid: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var mid_kept = GameState.from_dict(mid)
	if Projects.months_left(mid_kept.player(), "flood_defence") != Projects.months_left(ns, "flood_defence"):
		_fail("months remaining did not survive the round trip")
	(mid["nations"]["FRA"] as Dictionary).erase("projects")
	var mid_dropped = GameState.from_dict(mid)
	if Projects.building_count(mid_dropped.player()) != 0:
		_fail("a dropped register still reports work under way")
	if mid_dropped.player().project_potential_target_pct != 0.0:
		_fail("a half-built project left a payoff behind, which it must not")

	# (3) THE DONE HALF DOES NOT, AND THAT IS THE BUMP. Finish it, drop the register,
	# and the country has silently un-built a motorway it paid for.
	for _m2 in range(30):
		Projects.tick_month(state, loader)
	if not Projects.is_done(ns, "flood_defence"):
		_fail("the project did not complete, so this check is not measuring what it says")
	var built: float = ns.project_potential_target_pct
	if is_zero_approx(built):
		_fail("a completed project bought no trend, so this check is not measuring what it says")

	var full: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var dropped: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(dropped["nations"]["FRA"] as Dictionary).erase("projects")
	var amnesiac = GameState.from_dict(dropped)
	if not (amnesiac.player().projects as Dictionary).is_empty():
		_fail("a dropped register came back non-empty")
	if Projects.completed(amnesiac.player()).size() != 0:
		_fail("a dropped register still remembers what was built -- then the bump buys nothing")

	var kept = GameState.from_dict(full)
	if Projects.completed(kept.player()).size() != 1:
		_fail("the completed project did not survive the round trip")
	if not is_equal_approx(kept.player().project_potential_target_pct, built):
		_fail("the accumulated payoff did not survive the round trip")

	# (4) THE ENTRY CARRIES EXACTLY THE TWO KEYS Projects.ENTRY_KEYS NAMES, which is
	# V1.4a's device pointed at a fourth register and V1.6e's pointed at a fifth. The
	# cost, the duration and the payoff are AUTHORED, so a session caching any of them
	# here is putting content in the save and has to come and say why.
	var entry: Dictionary = (full["nations"]["FRA"] as Dictionary)["projects"]["flood_defence"]
	for key in entry.keys():
		if not Projects.ENTRY_KEYS.has(key):
			_fail("a serialised project entry carries '%s' -- %s is the whole register" % [key, str(Projects.ENTRY_KEYS)])
	if entry.size() != Projects.ENTRY_KEYS.size():
		_fail("a serialised project entry has %d keys, expected exactly %d" % [entry.size(), Projects.ENTRY_KEYS.size()])
	for authored in ["cost_pct_gdp", "build_months", "potential_growth_pct", "name"]:
		if entry.has(authored):
			_fail("a serialised project entry carries the authored '%s' -- content round-trips through data/project-actions/, not through the save" % authored)

	# (5) WHAT WAS NOT ADDED. The bill is recomputed on the first tick
	# (`investment_bill_pct_gdp`'s case) and the last result is a display record, so
	# neither earns anything -- and `last_project_result` is not serialised at all,
	# which is `last_investment_result`'s case and is pinned rather than assumed.
	if (full["nations"]["FRA"] as Dictionary).has("last_project_result"):
		_fail("a save carries last_project_result -- it is a display record of something that has already happened to the register")
	for pname in ["project_completion_year", "project_start_month", "projects_built"]:
		if (full["nations"]["FRA"] as Dictionary).has(pname):
			_fail("a save carries %s -- the register counts MONTHS REMAINING and holds no dates, which is what let the diary read it with no scheduler" % pname)

	if GameState.SAVE_VERSION != 41:
		_fail("SAVE_VERSION is %d -- V1.6d raised it to 22, V1.6e argued it should STAY there, and V1.6f raised it to 23 on the DONE half of `projects` the V1.7a restart fix to 24 V1.7c to 25 V1.8 to 26 and V1.1e to 27 on EIGHT fields of ten, failing the rule three different ways, so a further bump needs its own recorded reason; V2.5's reason is recorded and is `region_gdp_eur_bn` -- national GDP is the sum of the regions now, so an absent register is a country with no economy, not a quietly different one; V2.6a's reason is recorded and is two live population shares -- absent, every city has a population of zero; V2.6b2's reason is recorded and is two campaign-sited registers -- `campaign_sites`, because a running effort whose site was dropped silently reverts to the place-less national reach while the panel still names a place, and `campaign_saturation`, because a dropped spoken-to register hands every saturated region back at full reach: the tour un-spoken, `campaign_started`'s exploit one level up; V2.8's reason is recorded and is three content-derived statics -- `start_energy_mix`, because absent it is {} and the partition is not there, so a reloaded France reads a country with no electricity mix at all; `start_import_dependency_pct`, because absent it reads 0.0 and the deviation becomes the whole dependency, so a France that has imported half its energy for fifty years reads as having just started; `energy_kwh_per_capita`, because absent national_twh() is 0.0 and one reactor is then the country's whole electricity; V3.2's reason is recorded and is the bloc->orgs rename on three fields -- `GameState.orgs`, one register per council org, because an absent register is no council and no rules, wrong rather than empty; `NationState.orgs`, live membership, because absent it a reloaded France belongs to nothing and pays nothing into a budget it has always paid into; and `.org_base_transfer_pct_gdp`, the standing transfer per org -- folded into the same unreleased bump: `.org_seats`, live voting weight (absent it an acceded nation's vote weighs zero -- the second-class-member finding), and the fight `phase` (absent it a membership fight matches nothing and is stranded, the review's critical); `GameState.accessions` rides 33 serialised but its absence is correct, measures' case; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, because a save that dropped it un-prices a term the player already lived: the term reads as never chosen and its conclusions as never delivered; and `programme_stock`, the bounded credit the conclusion pulses feed, because absent it reads 0.0 -- a clean slate over a record the player watched; progress earns NOTHING -- it is re-derived from the same live figure the panel reads (docs/programme-model.md section 8), and test_save_load.gd injects a cached copy into a serialised entry and measures the derived read unchanged; V4.3's reason is recorded and is the SIX person-state registers -- `person_loyalty`, `person_standing`, `person_grudges` (absent, nobody remembers anything you did to them, programme_stock's case), `party_leader_override` (absent, a deposed rival is resurrected mid-term), `person_party_override` (absent, a defector silently walks back to the party they left) and `person_want_state` (absent, a denial straddling the save re-fires its grudge on every load); the bump ships ahead of the first writer (characters.gd), and the absences are pinned in _run_character_roundtrip; V4.6's reason is recorded and is `ns.commodity_state` -- a nation's capacity, demand, output, surplus, trade, its own copy of the ONE world price vector and the month's value added, all seven keys of one register. An absent register is the `region_gdp_eur_bn` class rather than the neutral-empty one: a reloaded France reads a country that can make nothing and holds no price vector, and the ONE world price is the case no re-derivation can rescue, because the vector is a shared world quantity and rebuilding it at base silently invents a second answer. The bump ships WITH the first writer rather than ahead of it (V4.1's and V4.3's timing, inverted): commodities.gd has written this register since V4.6's Task 3, so version 36 is the one version under which a save could hold a commodity register and not carry it. The lazy seed in Commodities.tick_month() STAYS -- the gate refuses version MISMATCHES, so the `{}` it catches now comes from a payload with the key absent, and the absence is pinned in _run_commodity_roundtrip; V4.2's reason is recorded and is the statute book's SIX registers -- `ns.law_ledger` (the realized-delta record repeal subtracts; absent, no pre-38 law is repealable and no re-derivation of a past passage is attempted, the second answer this project refuses), `ns.draft_bills` (composition in flight -- absent, a bill the player was drafting is simply gone), `ns.custom_laws` (passed composed laws -- absent, acts in force vanish from the book), `ns.custom_taxes` (a proposed key's base and erosion -- absent, the tax stops yielding at reload while its rate survives in tax_rates_pct, a silent half-tax), `ns.poll_purchases` (paid polls -- absent, a reload un-buys the fixed-forecast read and charges the player twice for one number) and `ns.assembly_bills` (private members' bills and lobbying in flight -- the held_bills free-escape case, an announced bill vanishing without a division); V5.1-0d's reason is recorded and is `embassies` -- a content-seeded register an absent key would read as no embassy anywhere, the pre-0d model, so the AI reopens them in the player's capital" % GameState.SAVE_VERSION)
