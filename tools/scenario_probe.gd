extends SceneTree

## Scenario envelope probe: godot --headless --script res://tools/scenario_probe.gd
##
## V1.2e's named measurement, run before the authored scenarios were finalised.
##
## docs/tiers/declined.md declined a difficulty slider and accepted start
## scenarios in its place, with an explicit falsifier attached: **the difficulty
## range start scenarios can reach is too narrow**. That is an empirical claim,
## so this probe measures it rather than asserting it -- the same discipline
## docs/dissolution-model.md and docs/cabinet-model.md used to measure a
## mechanic before building content against it.
##
## For each playable nation it runs the real monthly tick under `hands_off` --
## the do-nothing player, the crudest baseline -- five times: once at the
## standard start, once at each axis's extreme, and once with all three
## together. What separates the rows IS the envelope.
##
## Not a test. tests/test_scenario.gd asserts the invariants; this prints the
## spread a human reads. Kept in tools/ and excluded from run_tests.sh, same as
## balance_probe.gd.
##
## Pass a nation id to run one: --headless --script ... -- DEU

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Scenario = preload("res://src/core/scenario.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Government = preload("res://src/sim/government.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")

## One full inherited term plus a little, so the run covers at least one
## election and the months either side of it. Shorter than balance_probe's
## fourteen years on purpose: a scenario is a STARTING state, and what it is
## claimed to change is the opening term. If a difference has not appeared by
## the first election it is not a difficulty lever.
const MONTHS := 60
const START_YEAR := 2026

## The extremes. Deliberately past anything shipped as content -- the point is
## to find the edge of the authorable envelope, not to propose a scenario.
const DEBT_MULTIPLE := 2.0
const SEATS_LEADER_SHARE := 0.14
const APPROVAL_FLOOR := 25.0


func _init() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.length() == 3 and arg == arg.to_upper():
			only = arg

	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		if not loader.nations[id].playable:
			continue
		if only != "" and id != only:
			continue
		_sweep_nation(loader, id)

	_authored(loader, only)
	quit(0)


## The same two measurements, run against what data/scenarios/ actually ships
## rather than against the constructed extremes above. The extremes bound the
## envelope; this says where the authored content sits inside it -- and it is
## the check on docs/amendment-model.md's claim that a grand-coalition-shaped
## start could raise Germany's two-thirds ceiling.
func _authored(loader, only: String) -> void:
	print("\n\n########## authored scenarios ##########")
	var ids: Array = loader.scenarios.keys()
	ids.sort()

	print("\n-- legislature at month 0 --")
	print("%-14s %8s %8s %10s %10s  %s" % [
		"start", "coal", "coal%", "best yes%", "amend need", "amendment reachable",
	])
	print("-".repeat(96))
	for id in ids:
		var s = loader.scenarios[id]
		if only != "" and s.nation_id != only:
			continue
		_legislature(loader, s.nation_id, "%s base" % s.nation_id, null)
		_legislature(loader, s.nation_id, id, s)

	print("\n-- %d months under hands_off --" % MONTHS)
	print("%-14s %8s %8s %8s %8s %8s  %s" % [
		"start", "appr@0", "appr@12", "appr@end", "defic", "debt%", "outcome",
	])
	print("-".repeat(96))
	for id in ids:
		var s = loader.scenarios[id]
		if only != "" and s.nation_id != only:
			continue
		_run(loader, s.nation_id, "%s base" % s.nation_id, null)
		_run(loader, s.nation_id, id, s)


func _sweep_nation(loader, nation_id: String) -> void:
	var nation = loader.nations[nation_id]
	var party_list: Array = loader.parties.get(nation_id, [])

	print("\n\n########## %s (%s) ##########" % [nation.nation_name, nation_id])
	print("standard start: debt %.1f%% of GDP, leader party '%s'" % [nation.debt_to_gdp_pct, nation.leader_party_id])

	var debt_only = _scenario(nation_id, "debt", nation, party_list, true, false, false)
	var seats_only = _scenario(nation_id, "seats", nation, party_list, false, true, false)
	var mood_only = _scenario(nation_id, "mood", nation, party_list, false, false, true)
	var everything = _scenario(nation_id, "all", nation, party_list, true, true, true)

	# Two tables, because the axes act on two different things and one table
	# hid that. The economic/opinion table below answers "how does the run go";
	# the legislative table answers "what can the player pass", which is the
	# only channel the seats axis has and which a do-nothing player never
	# exercises. Splitting them is what turned "seats does nothing" from a
	# conclusion into a measurement -- see docs/scenario-model.md.
	print("\n-- legislature at month 0 --")
	print("%-14s %8s %8s %10s %10s  %s" % [
		"start", "coal", "coal%", "best yes%", "amend need", "amendment reachable",
	])
	print("-".repeat(96))
	_legislature(loader, nation_id, "standard", null)
	_legislature(loader, nation_id, "debt x%.1f" % DEBT_MULTIPLE, debt_only)
	_legislature(loader, nation_id, "seats %.2f" % SEATS_LEADER_SHARE, seats_only)
	_legislature(loader, nation_id, "mood %.0f" % APPROVAL_FLOOR, mood_only)
	_legislature(loader, nation_id, "all three", everything)

	print("\n-- %d months under hands_off --" % MONTHS)
	print("%-14s %8s %8s %8s %8s %8s  %s" % [
		"start", "appr@0", "appr@12", "appr@end", "defic", "debt%", "outcome",
	])
	print("-".repeat(96))

	_run(loader, nation_id, "standard", null)
	_run(loader, nation_id, "debt x%.1f" % DEBT_MULTIPLE, debt_only)
	_run(loader, nation_id, "seats %.2f" % SEATS_LEADER_SHARE, seats_only)
	_run(loader, nation_id, "mood %.0f" % APPROVAL_FLOOR, mood_only)
	_run(loader, nation_id, "all three", everything)


## Builds one extreme Scenario in memory. Deliberately not read from
## data/scenarios/ -- these are past what any shipped scenario should be, and
## authoring them as files would put content in the game whose only purpose is
## to be measured.
func _scenario(nation_id: String, _label: String, nation, party_list: Array, debt: bool, seats: bool, mood: bool):
	var s = Scenario.new()
	s.id = "probe"
	s.nation_id = nation_id

	if debt:
		s.has_debt_to_gdp_pct = true
		s.debt_to_gdp_pct = nation.debt_to_gdp_pct * DEBT_MULTIPLE

	if seats:
		# Cut the incumbent to a rump and spread what it loses over everyone
		# else in proportion to what they already hold -- so the override tests
		# the governing party's collapse rather than a hand-picked assembly
		# that happens to suit one nation's formation rule.
		var leader_share := 0.0
		var others := 0.0
		for party in party_list:
			if party.id == nation.leader_party_id:
				leader_share = party.seat_share
			else:
				others += party.seat_share
		var freed: float = leader_share - SEATS_LEADER_SHARE
		for party in party_list:
			if party.id == nation.leader_party_id:
				s.seat_share[party.id] = SEATS_LEADER_SHARE
			else:
				s.seat_share[party.id] = party.seat_share + freed * (party.seat_share / others)

	if mood:
		for bloc in K.BLOC_KEYS:
			s.bloc_approval[bloc] = APPROVAL_FLOOR

	return s


## The legislative arithmetic a scenario's seat override actually changes,
## measured at month 0 before any tick has run. `best yes%` is the highest
## yes-share any single loaded law can raise from this assembly -- the ceiling
## docs/amendment-model.md and docs/transition-model.md both swept for, computed
## the same way, through the real resolve_vote() rather than a seat count.
func _legislature(loader, nation_id: String, label: String, scenario) -> void:
	var state
	if scenario == null:
		state = GameState.new_game(loader, nation_id)
	else:
		state = _new_game_with(loader, nation_id, scenario)
	if not state.errors.is_empty():
		printerr("  %s: %s" % [label, state.errors])
		return

	var ns = state.player()
	var party_list: Array = loader.parties.get(nation_id, [])

	var best := 0.0
	for law in loader.laws:
		var result := Legislature.resolve_vote(ns, party_list, law)
		var share: float = float(result["yes_seats"]) / float(ns.assembly_seats)
		best = maxf(best, share)

	var needed: float = LK.AMENDMENT_RULE_FRACTIONS.get(ns.amendment_rule, -1.0)
	var verdict := "n/a (%s)" % ns.amendment_rule
	if needed > 0.0:
		verdict = "%s (%.3f vs %.3f)" % ["YES" if best >= needed else "no", best, needed]

	print("%-14s %8d %8.3f %10.3f %10s  %s" % [
		label,
		ns.coalition_seats,
		float(ns.coalition_seats) / float(ns.assembly_seats),
		best,
		"%.3f" % needed if needed > 0.0 else "-",
		verdict,
	])


func _run(loader, nation_id: String, label: String, scenario) -> void:
	var state
	if scenario == null:
		state = GameState.new_game(loader, nation_id)
	else:
		# Injected directly rather than through a scenario_id, so the probe can
		# sweep extremes that exist in no file. new_game() resolves the id; this
		# is the same code path one step later.
		state = _new_game_with(loader, nation_id, scenario)

	if not state.errors.is_empty():
		printerr("  %s: %s" % [label, state.errors])
		return

	state.year = START_YEAR
	state.month = 1

	var ns = state.player()
	var approval_start: float = ns.overall_approval_pct
	var approval_12 := approval_start
	var elections: Array[String] = []
	var fell := 0

	var year := START_YEAR
	var month := 1
	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		Economy.tick_month(state)
		Budget.tick_month(state)
		Orgs.tick_month(state, loader)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)
		Discipline.tick_month(state, loader)
		Legislature.tick_month(state, loader)
		Dissolution.tick_month(state)
		Cabinet.tick_month(state, loader)

		var governments_fallen_before: int = ns.governments_fallen
		var result := Elections.tick_month(state, loader)
		if ns.governments_fallen > governments_fallen_before:
			fell += 1
		if not result.is_empty():
			elections.append("%d-%02d" % [year, month])

		if i + 1 == 12:
			approval_12 = ns.overall_approval_pct

	var outcome := "survived"
	if not elections.is_empty():
		outcome = "%d election(s) %s" % [elections.size(), str(elections)]
	if fell > 0:
		outcome += ", %d government(s) fell" % fell

	print("%-14s %8.1f %8.1f %8.1f %8.2f %8.1f  %s" % [
		label,
		approval_start,
		approval_12,
		ns.overall_approval_pct,
		ns.deficit_pct_gdp,
		ns.debt_eur_bn / ns.gdp_eur_bn * 100.0,
		outcome,
	])


## GameState.new_game() takes a scenario ID and looks it up in the loader. The
## probe has a Scenario object and no file, so it borrows the loader for one
## call by registering the object under a reserved id.
func _new_game_with(loader, nation_id: String, scenario):
	loader.scenarios["__probe__"] = scenario
	scenario.id = "__probe__"
	var state = GameState.new_game(loader, nation_id, "__probe__")
	loader.scenarios.erase("__probe__")
	return state
