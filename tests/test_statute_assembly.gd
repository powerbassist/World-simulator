extends SceneTree

## V4.2 T6: the assembly's own life -- private members' bills and the chiefs'
## lobbying. The load-bearing pins:
##
##   - TICK ORDER: Statute ticks AFTER the legislature in main.gd's month (a
##     failed bill's authored cooldown must be written after the countdown
##     pass has run, or it arrives one month short -- the V2.8 ordering, one
##     machine down), and BOTH balance harnesses mirror the call -- a harness
##     that never called the tick would run the pre-PMB model and its
##     agreement with main.gd would be about nothing (the V1.5d bug class);
##   - THE HAZARD BAND: 120 idle months table more than none and far fewer
##     than the draws' ceiling (the pool closes as bills resolve -- a failed
##     bill sits out its authored cooldown);
##   - THE ASSEMBLY DECIDES: a bill tabled at PMB_MONTHS_TO_VOTE divides on
##     the next tick with no player action -- full window, the V2.8 lesson
##     -- and the result lands on ns.last_law_result under its assembly
##     marker, passed applying through the ONE applier, failed writing the
##     authored cooldown;
##   - THE ENDORSEMENT: the bonus reaches the division through resolve_vote()'s
##     DEFAULTED support_bonus (the ~25 call sites untouched -- the coordinator
##     interface's sanctioned reading, since a wrapper would have re-mirrored
##     the loop and the majority match verbatim) and the endorsement price
##     lands ONCE through the ONE applier, with a second stand refused;
##   - THE PIPELINE (the version-close review's correction): a CARRIED bill
##     walks propose()'s own stages -- the second chamber between the division
##     and everything after it, then the court; a Senat-refused bill is HELD
##     like propose()'s own, and the release applies through the court on its
##     own. A FAILED division faces neither stage and carries none of the
##     pipeline's keys;
##   - THE LOBBY: a burdened sector with a major draws a chief-backed bill
##     naming that sector's burden-easing law, the backer a REAL chief; a
##     sector with no deregulation law to name falls through to a plain bill;
##   - DETERMINISM, THE has_budget GATE, ROUND-TRIP + ABSENCE, and the
##     available() in-flight guard (the player proposing a tabled law inside
##     the endorsement window would divide it twice).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Statute = preload("res://src/sim/statute.gd")
const SK = preload("res://src/sim/statute_constants.gd")
const CK = preload("res://src/sim/chambers_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")

const PLAYER := "FRA"
## The bill legs (b)/(c) table by hand: an authored, non-constitutional,
## non-institutional law -- the pool's own classes -- whose division the
## endorse bonus measurably moves (control 115/307, endorsed 268/309 at a
## fresh FRA; measured, not assumed).
const ENDORSE_LAW := "retirement_age_reform"
## The sector whose majors lobby, and the deregulation law they name --
## data/laws/business.json's own rows: industrial_deregulation carries
## industry -0.4, and FRA's biggest industry major is FRA_aurignac (share
## 0.14 against FRA_sevrenne's 0.10).
const LOBBY_SECTOR := "industry"
const LOBBY_LAW := "industrial_deregulation"
const LOBBY_FIRM := "FRA_aurignac"
const LOBBY_CHIEF := "FRA_chief_aurignac"
## The idle band, from statute_constants' comment: the draws fire ~0.96 a
## year and the measured 120-month idle run tabled 9 bills; the pin holds a
## ceiling well inside the draws' own 12-per-decade.
const BAND_MAX := 20

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_test_tick_order_pin()
		_test_hazard_band_and_gate()
		_test_resolves_without_player()
		_test_endorse()
		_test_upper_house_and_court_pipeline()
		_test_in_flight_guard()
		_test_lobby()
		_test_determinism()
		_test_roundtrip_absence_and_duplicate()
	_finish()


func _fresh():
	var gs = GameState.new_game(_loader, PLAYER)
	return [gs, gs.player()]


func _tick(state) -> void:
	# The CLOCK owns the month in the running game (test_industry's pattern):
	# tick_month() functions never advance it, and every Cycle draw keys on
	# the absolute month -- without this line the hazards cannot fire.
	state.month = int(state.month) + 1
	if int(state.month) > 12:
		state.month = 1
		state.year = int(state.year) + 1
	Statute.tick_month(state, _loader)


func _month_index(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _hand_bill(law_id: String, backer := "", chief := "") -> Dictionary:
	return {
		"law_id": law_id,
		"months_left": SK.PMB_MONTHS_TO_VOTE,
		"backer_firm": backer,
		"backer_chief": chief,
		"endorse_bonus": 0.0,
	}


## test_industry's pattern: the order is read off the source, because a test
## that only ticked in one order would pass a file wired in the wrong one.
func _test_tick_order_pin() -> void:
	var text := FileAccess.get_file_as_string("res://src/ui/main.gd")
	var legislature := text.find("Legislature.tick_month")
	var statute := text.find("Statute.tick_month")
	if legislature < 0 or statute < 0:
		_fail("main.gd is missing a tick (Legislature %d, Statute %d)" % [legislature, statute])
		return
	if not (legislature < statute):
		_fail("tick order broken: Legislature (%d) < Statute (%d) must hold -- a failed bill's cooldown must be written after the countdown pass" % [
			legislature, statute])
	for harness_path in ["res://tools/balance_probe.gd", "res://tests/test_balance.gd"]:
		var harness := FileAccess.get_file_as_string(harness_path)
		if harness.find("Statute.tick_month") < 0:
			_fail("%s does not mirror the Statute tick -- the harness would run a different model" % harness_path)


## Leg (a): the seeded 120-month idle loop. Leg (f): only the player nation
## ever legislates.
func _test_hazard_band_and_gate() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var seen := {}
	var other_dirty := {}
	for i in range(120):
		_tick(gs)
		# Count DISTINCT bill ids, not size deltas: the in-tray erases at the
		# division, so a month that tables one bill while resolving another
		# shows a zero delta and a size counter undercounts.
		for bill_id in ns.assembly_bills:
			seen[bill_id] = true
		for other_id in gs.nations.keys():
			if other_id == PLAYER:
				continue
			if not (gs.nations[other_id].assembly_bills as Dictionary).is_empty():
				other_dirty[other_id] = true
	var tabled := seen.size()
	if tabled < 1:
		_fail("120 idle months tabled %d bills -- the backbench never acts" % tabled)
	if tabled > BAND_MAX:
		_fail("120 idle months tabled %d bills, over the declared band of %d" % [tabled, BAND_MAX])
	if not other_dirty.is_empty():
		_fail("non-player nations legislated: %s -- has_budget is the standing refusal" % [other_dirty.keys()])
	# The entries' shape, on whatever the loop left in flight or the last
	# resolution's neighbourhood -- walk the in-tray if any bill survived.
	for bill_id in ns.assembly_bills:
		var entry: Dictionary = ns.assembly_bills[bill_id]
		for key in ["law_id", "months_left", "backer_firm", "backer_chief", "endorse_bonus"]:
			if not entry.has(key):
				_fail("in-tray entry %s is missing '%s' -- the shape the save and the cards read" % [bill_id, key])


## Leg (b): the assembly proposes and the assembly decides -- a hand-tabled
## bill divides on the next tick with no player action, full window.
func _test_resolves_without_player() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	ns.assembly_bills["pmb_test_b"] = _hand_bill(ENDORSE_LAW)
	if int(ns.assembly_bills["pmb_test_b"]["months_left"]) != SK.PMB_MONTHS_TO_VOTE:
		_fail("the tabled bill must carry the full window")
	_tick(gs)
	if ns.assembly_bills.has("pmb_test_b"):
		_fail("the bill did not divide on its due month")
	var result: Dictionary = ns.last_law_result
	if String(result.get("law_id", "")) != ENDORSE_LAW:
		_fail("the division's result names '%s', expected %s" % [result.get("law_id", ""), ENDORSE_LAW])
	if not bool(result.get("assembly_bill", false)):
		_fail("the result does not carry the assembly marker -- the cards cannot say where it came from")
	if int(result.get("yes_seats", -1)) < 0:
		_fail("the result carries no seat tally -- resolve_vote() did not run")
	# THE DIVISION'S OWN MONTH, stamped into the result: main.gd's card memory
	# keys on this, not on the current month, so a quiet month cannot re-announce
	# a division that happened once.
	if int(result.get("assembly_division_month", -1)) != _month_index(gs):
		_fail("the result carries no division month stamp (got %s, state at %d) -- the card memory has nothing to key on"
			% [result.get("assembly_division_month", -1), _month_index(gs)])
	var law = _law_by_id(ENDORSE_LAW)
	if bool(result.get("passed", true)):
		if ns.law_cooldown_months.has(ENDORSE_LAW):
			_fail("a passed bill wrote a cooldown")
	else:
		if law.cooldown_months > 0 and not ns.law_cooldown_months.has(ENDORSE_LAW):
			_fail("a failed bill did not write its authored cooldown -- propose()'s failure path, mirrored")


## Leg (c): the endorsement moves the vote -- two states, one endorsed, the
## tallies bit-compared -- and charges the price once.
func _test_endorse() -> void:
	var control = _fresh()
	var treated = _fresh()
	control[1].assembly_bills["pmb_test_c"] = _hand_bill(ENDORSE_LAW)
	treated[1].assembly_bills["pmb_test_c"] = _hand_bill(ENDORSE_LAW)
	var bloc_before: Dictionary = treated[1].bloc_offset.duplicate(true)

	var r: Dictionary = Statute.endorse(treated[0], treated[1], _loader, "pmb_test_c")
	if not bool(r.get("ok", false)):
		_fail("endorse refused: %s" % r.get("refusal", ""))
		return
	if not is_equal_approx(float(treated[1].assembly_bills["pmb_test_c"]["endorse_bonus"]), SK.PMB_ENDORSE_SUPPORT):
		_fail("the in-tray entry does not carry the endorse bonus")
	var bloc: Dictionary = treated[1].bloc_offset
	for bloc_key in SK.PMB_ENDORSE_PRICE:
		var delta: float = float(bloc.get(bloc_key, 0.0)) - float(bloc_before.get(bloc_key, 0.0))
		if not is_equal_approx(delta, float(SK.PMB_ENDORSE_PRICE[bloc_key])):
			_fail("the endorsement price moved %s by %s, expected %s -- the ONE applier must land it once" % [
				bloc_key, delta, SK.PMB_ENDORSE_PRICE[bloc_key]])
	var second: Dictionary = Statute.endorse(treated[0], treated[1], _loader, "pmb_test_c")
	if bool(second.get("ok", true)):
		_fail("a second endorsement was not refused -- the price is per stand")
	var ghost: Dictionary = Statute.endorse(control[0], control[1], _loader, "pmb_nothing")
	if bool(ghost.get("ok", true)):
		_fail("a ghost bill was endorsable")

	_tick(control[0])
	_tick(treated[0])
	var a: Dictionary = control[1].last_law_result
	var b: Dictionary = treated[1].last_law_result
	if int(a["yes_seats"]) == int(b["yes_seats"]) and int(a["no_seats"]) == int(b["no_seats"]) \
			and int(a["abstain_seats"]) == int(b["abstain_seats"]):
		_fail("the endorse bonus did not move the division -- tallies are bit-identical")
	if a["party_support"] == b["party_support"]:
		_fail("the party support lines did not move")
	if int(b["yes_seats"]) <= int(a["yes_seats"]):
		_fail("the endorsed division won no more seats than the control (%d vs %d) -- measured control 115, endorsed 268" % [
			int(b["yes_seats"]), int(a["yes_seats"])])
	# The retired court_skipped marker must be GONE, and a FAILED division must
	# carry none of the passage pipeline's keys: the second chamber and the
	# court review a bill that CARRIED (test_upper_house_and_court_pipeline
	# pins that read), and there is nothing yet for either to review here.
	if b.has("court_skipped"):
		_fail("a failed division still carries the retired court_skipped marker")
	for key in ["upper_chamber", "upper_passed", "reviewable", "held_by_upper", "blocked_by_upper"]:
		if b.has(key):
			_fail("a failed division walked the passage pipeline ('%s' present)" % key)


## THE PIPELINE, the version-close review's correction: a CARRIED assembly bill
## walks propose()'s own stages -- the second chamber between the division and
## everything after it, then the court. FRA's Senat is suspensive for an
## ordinary bill, so the two laws the finder picks give both readings: carried
## AND passed by the chamber reaches the court (the reviewable key is the flip
## of the retired court_skipped pin); carried and REFUSED is HELD like
## propose()'s own, and the release applies through the court with no command
## from anyone -- test_upper_house's idiom, one stage earlier in the pipeline.
func _test_upper_house_and_court_pipeline() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var passing = _pool_law(ns, true)
	var refused = _pool_law(ns, false)
	if passing == null or refused == null:
		_fail("the content offers no Senat-passing or Senat-refusing pool law -- rewrite the finder, do not drop the pin")
		return

	# Carried AND carried by the upper chamber: the court is the next stage.
	ns.assembly_bills["pmb_pipeline_pass"] = _hand_bill(String(passing.id))
	_tick(gs)
	var result: Dictionary = ns.last_law_result
	if String(result.get("law_id", "")) != String(passing.id):
		_fail("the pipeline leg divided the wrong bill: '%s'" % result.get("law_id", ""))
		return
	if String(result.get("upper_chamber", "")) != ns.upper_chamber_name:
		_fail("a carried division skipped the second chamber -- no upper_chamber key")
	if not bool(result.get("upper_passed", false)):
		_fail("the pipeline leg's law did not pass the Senat -- pick another (upper result: %s)" % result)
	if not result.has("reviewable"):
		_fail("a carried, chamber-passed division never reached the court -- no reviewable key")

	# Carried and REFUSED by the suspensive Senat: held, not defeated.
	ns.assembly_bills["pmb_pipeline_hold"] = _hand_bill(String(refused.id))
	_tick(gs)
	var hold_result: Dictionary = ns.last_law_result
	if String(hold_result.get("law_id", "")) != String(refused.id):
		_fail("the hold leg divided the wrong bill: '%s'" % hold_result.get("law_id", ""))
		return
	if not bool(hold_result.get("held_by_upper", false)):
		_fail("a Senat-refused division was not held: %s" % hold_result)
		return
	if int(hold_result.get("held_months", 0)) != CK.UPPER_HOLD_MONTHS:
		_fail("the hold is %s months, expected %d" % [hold_result.get("held_months", 0), CK.UPPER_HOLD_MONTHS])
	if int(ns.held_bills.get(String(refused.id), 0)) != CK.UPPER_HOLD_MONTHS:
		_fail("the held bill is not parked in ns.held_bills -- the release would never fire")
	if ns.law_cooldown_months.has(String(refused.id)):
		_fail("a held bill was cooled down -- it has not been beaten")

	# The release: no second division and no player verb, and the bill arrives
	# THROUGH THE COURT -- the released result is a reviewed one.
	for i in range(CK.UPPER_HOLD_MONTHS):
		Legislature.tick_month(gs, _loader)
	if not ns.held_bills.is_empty():
		_fail("the hold did not expire after %d legislature ticks" % CK.UPPER_HOLD_MONTHS)
	var released: Dictionary = ns.last_law_result
	if not bool(released.get("released", false)) or not released.has("reviewable"):
		_fail("the release did not apply through the court: %s" % released)


## The first pool-class law the assembly carries and the Senat does (or does
## not) also carry -- found in the content rather than named, so a content edit
## cannot leave these legs quietly measuring nothing (test_upper_house's
## _held_law, widened by the upper outcome).
func _pool_law(ns, upper_passes: bool):
	var party_list: Array = _loader.parties.get(PLAYER, [])
	for law in _loader.laws:
		if law.constitutional or law.effects.has("institutional"):
			continue
		if not bool(Legislature.resolve_vote(ns, party_list, law, false)["passed"]):
			continue
		if bool(Legislature.resolve_upper(ns, party_list, law)["passed"]) != upper_passes:
			continue
		return law
	return null


## The in-flight guard: a law the backbench has tabled cannot be proposed by
## the player inside the endorsement window -- the double-application guard
## available() exists to keep. carbon_levy is the control law here because the
## leg needs one the player could otherwise propose AND pass (measured 318/259
## at a fresh FRA); retirement_age_reform fails its own division.
func _test_in_flight_guard() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var law = _law_by_id("carbon_levy")
	var before: Dictionary = Legislature.resolve_vote(ns, _loader.parties.get(PLAYER, []), law, false)
	if not bool(before["passed"]):
		_fail("test setup: the control division must pass for the double-apply leg to mean anything")
		return
	ns.assembly_bills["pmb_test_guard"] = _hand_bill("carbon_levy")
	var result: Dictionary = Legislature.propose(gs, _loader, law)
	if not bool(result.get("unavailable", false)):
		_fail("propose() accepted a law the assembly has tabled -- the effects would apply twice")


## Leg (d): the chiefs' verb. The month is computed off the deterministic
## draw, not looped blind -- Cycle.unit("statute|lobby|FRA", 27) is 0.0009,
## the first firing month, measured before this test was written. The fixture
## sets the month BEFORE the tick's own advance, so the tick lands the state
## on absolute month 27.
func _test_lobby() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	gs.year = 2
	gs.month = 2
	# The draw the TICK will land on: _tick advances the month before it
	# generates, so the hazard index is the state's next absolute month.
	if Cycle.unit("statute|lobby|%s" % PLAYER, _month_index(gs) + 1) >= SK.LOBBY_HAZARD_MONTHLY:
		_fail("test setup: the drawn lobby month no longer fires -- recompute the fixture month")
		return
	ns.regulation_burden[LOBBY_SECTOR] = 0.5
	_tick(gs)
	var found := {}
	for bill_id in ns.assembly_bills:
		var entry: Dictionary = ns.assembly_bills[bill_id]
		if String(entry.get("backer_firm", "")) == "":
			continue
		found[bill_id] = entry
	if found.is_empty():
		_fail("a burdened sector with a major drew no chief-backed bill")
		return
	if found.size() > 1:
		_fail("one lobby month tabled %d backed bills" % found.size())
	var entry: Dictionary = found.values()[0]
	if String(entry["law_id"]) != LOBBY_LAW:
		_fail("the backed bill names '%s', expected %s -- the sector's burden-easing law" % [entry["law_id"], LOBBY_LAW])
	if String(entry["backer_firm"]) != LOBBY_FIRM:
		_fail("the backer is '%s', expected %s -- the sector's biggest major" % [entry["backer_firm"], LOBBY_FIRM])
	if String(entry["backer_chief"]) != LOBBY_CHIEF:
		_fail("the backer chief is '%s', expected %s" % [entry["backer_chief"], LOBBY_CHIEF])
	if _loader.person_name(LOBBY_CHIEF) == "":
		_fail("the backer chief is not a real person in the loader's register")

	# The fall-through: agriculture carries no burden-easing law in the
	# authored book, so the fired draw spends the month on a PLAIN bill.
	var pair2 = _fresh()
	var gs2 = pair2[0]
	var ns2 = pair2[1]
	gs2.year = 2
	gs2.month = 2
	ns2.regulation_burden["agriculture"] = 0.6
	_tick(gs2)
	var plain := {}
	for bill_id in ns2.assembly_bills:
		if String(ns2.assembly_bills[bill_id].get("backer_firm", "")) == "":
			plain[bill_id] = ns2.assembly_bills[bill_id]
	if plain.is_empty():
		_fail("a fired lobby with no deregulation law to name tabled nothing -- it must fall through to the plain backbench bill")


## Leg (e): identical states, identical bills -- Cycle over the absolute
## month, no RNG state anywhere.
func _test_determinism() -> void:
	var a = _fresh()
	var b = _fresh()
	for i in range(24):
		_tick(a[0])
		_tick(b[0])
	if var_to_bytes(a[1].assembly_bills) != var_to_bytes(b[1].assembly_bills):
		_fail("identical states produced different assembly bills")


## Leg (g): round-trip, no aliasing, absence, the init reset.
func _test_roundtrip_absence_and_duplicate() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	ns.assembly_bills["pmb_test_g"] = _hand_bill(ENDORSE_LAW, LOBBY_FIRM, LOBBY_CHIEF)
	ns.assembly_bills["pmb_test_g"]["endorse_bonus"] = SK.PMB_ENDORSE_SUPPORT

	var d: Dictionary = ns.to_dict()
	var ns2 = NationState.from_dict(d)
	if ns2.assembly_bills != ns.assembly_bills:
		_fail("assembly_bills did not survive to_dict/from_dict")
	if int(ns2.assembly_bills["pmb_test_g"]["months_left"]) != SK.PMB_MONTHS_TO_VOTE:
		_fail("the round-tripped months_left came back a float -- the countdown would drift")
	# No aliasing: the loaded register must not share a dictionary with the
	# live one.
	ns2.assembly_bills["pmb_test_g"]["endorse_bonus"] = -1.0
	if is_equal_approx(float(ns.assembly_bills["pmb_test_g"]["endorse_bonus"]), -1.0):
		_fail("from_dict shared the assembly_bills payload -- the save would mutate with the run")

	var s = ns.duplicate_state()
	s.assembly_bills["pmb_test_g"]["months_left"] = 99
	if int(ns.assembly_bills["pmb_test_g"]["months_left"]) == 99:
		_fail("duplicate_state shared assembly_bills -- a projection would tick the live in-tray")

	var d2: Dictionary = ns.to_dict()
	d2.erase("assembly_bills")
	var ns3 = NationState.from_dict(d2)
	if not ns3.assembly_bills.is_empty():
		_fail("absence must read empty with no error")

	Legislature.init_nation(ns)
	if not ns.assembly_bills.is_empty():
		_fail("init_nation did not reset the in-tray -- whatever WRITES a field resets it")


func _law_by_id(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null


func _fail(message: String) -> void:
	_failures.append(message)
	print("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("OK: all statute assembly checks passed")
		quit(0)
	else:
		print("%d failures" % _failures.size())
		quit(1)
