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
##   - THE STRUCK-DOWN CARD and THE COLLISION (ultra pass 4): a court strike
##     outranks every other wording on both paths that reach the card body;
##     a PMB dividing the same month a hold releases pushes BOTH cards, on
##     the capture main.gd takes between its two ticks;
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
		_test_division_charges_rebellion_discipline()
		_test_upper_house_and_court_pipeline()
		_test_in_flight_guard()
		_test_lobby()
		_test_lobby_skips_dead_firms()
		_test_held_composed_law_applies_at_release()
		_test_release_and_division_same_month()
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


## Every Label's text in a builder's output, depth-first -- the same live read
## the surfaces test makes on the real panel, minus the scene tree (the
## summary builders make Labels and boxes only, nothing that needs _ready).
func _labels_text(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label:
			out += String(child.text) + "\n"
		else:
			out += _labels_text(child)
	return out


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
	# The ultra pass-2 shape: {"months", "origin"} -- and the origin is
	# "assembly", what makes the release charge no override (see below).
	var held_entry: Dictionary = ns.held_bills.get(String(refused.id), {})
	if int(held_entry.get("months", 0)) != CK.UPPER_HOLD_MONTHS:
		_fail("the held bill is not parked in ns.held_bills -- the release would never fire")
	if String(held_entry.get("origin", "")) != "assembly":
		_fail("the assembly's hold must carry origin \"assembly\" -- nobody insisted on a PMB")
	if ns.law_cooldown_months.has(String(refused.id)):
		_fail("a held bill was cooled down -- it has not been beaten")

	# The release: no second division and no player verb, and the bill arrives
	# THROUGH THE COURT -- the released result is a reviewed one. AND IT CHARGES
	# NO OVERRIDE: the bloc movement across the release must be exactly the
	# law's own authored effects, to the bit -- the override price is the
	# GOVERNMENT's insistence priced, and the assembly's hold is nobody's.
	var bloc_before: Dictionary = {}
	for bloc in ns.bloc_offset:
		bloc_before[bloc] = float(ns.bloc_offset[bloc])
	for i in range(CK.UPPER_HOLD_MONTHS):
		Legislature.tick_month(gs, _loader)
	if not ns.held_bills.is_empty():
		_fail("the hold did not expire after %d legislature ticks" % CK.UPPER_HOLD_MONTHS)
	var released: Dictionary = ns.last_law_result
	if not bool(released.get("released", false)) or not released.has("reviewable"):
		_fail("the release did not apply through the court: %s" % released)
	if not bool(released.get("passed", false)):
		_fail("the released PMB was struck down -- the no-override leg has no effects to measure against")
		return
	if released.has("override_offset"):
		_fail("a released PMB carried the override price nobody incurred")
	var authored: Dictionary = refused.effects.get("bloc_offset", {})
	for bloc in bloc_before:
		var moved: float = float(ns.bloc_offset.get(bloc, 0.0)) - float(bloc_before[bloc])
		var charged: float = moved - float(authored.get(bloc, 0.0))
		if absf(charged) > 1e-9:
			_fail("a released PMB charged %f on %s -- the override price is the government's, not the assembly's" % [
				charged, bloc])

	# The ultra pass-3 card fix: the release IS the coming-into-force event,
	# and main.gd's card gate reads the assembly marker and the event's own
	# month stamp off the result -- without them the bill's enactment pushed
	# no card anywhere (only the Legislature panel, on open, said so).
	if not bool(released.get("assembly_bill", false)):
		_fail("the released PMB carries no assembly marker -- the coming-into-force card cannot fire")
	if int(released.get("assembly_division_month", -1)) != _month_index(gs):
		_fail("the released PMB carries no release-month stamp (got %s, state at %d) -- the card memory has nothing to key on"
			% [released.get("assembly_division_month", -1), _month_index(gs)])

	# The card's WORDS, driven on main.gd's body-builder with the results the
	# machine writes (a bare main instance: the builder reads only the loader
	# and its argument, nothing of the scene). A held division says carried
	# and suspended, never defeated; a blocked one says blocked; a release
	# words the coming-into-force and carries no tally to contradict.
	var main_ui = load("res://src/ui/main.gd").new()
	main_ui._loader = _loader
	var held_body: String = main_ui._assembly_result_body(hold_result)
	if held_body.find("defeated") != -1:
		_fail("a held division's card reads 'defeated': %s" % held_body)
	if held_body.find("carried") == -1 or held_body.find("suspended") == -1:
		_fail("a held division's card does not say carried-and-suspended: %s" % held_body)
	var blocked_result: Dictionary = hold_result.duplicate(true)
	blocked_result.erase("held_by_upper")
	blocked_result["blocked_by_upper"] = true
	var blocked_body: String = main_ui._assembly_result_body(blocked_result)
	if blocked_body.find("blocked") == -1 or blocked_body.find("defeated") != -1:
		_fail("a blocked division's card does not say blocked: %s" % blocked_body)
	var release_body: String = main_ui._assembly_result_body(released)
	if release_body.find("comes into force") == -1 or release_body.find("ayes") != -1:
		_fail("a release's card does not word the coming-into-force: %s" % release_body)
	# The ultra pass-5 finding: the release card names the chamber by the
	# nation's own name (the hold card did, twelve months earlier) -- the
	# generic "second chamber" fallback must never fire on a machine result.
	if release_body.find(String(released["upper_chamber"])) == -1:
		_fail("a release's card does not name the chamber '%s': %s" % [released.get("upper_chamber"), release_body])
	# The ultra pass-5 finding, second half: the TABLING card must stop
	# offering a stand once the president has made one -- the endorsed entry
	# re-renders as the on-the-record line, never the endorsement ask.
	var tabling: Dictionary = {"law_id": "high_earner_surtax", "months_left": 1,
		"backer_firm": "", "backer_chief": "", "endorse_bonus": 0.0}
	var ask_body: String = main_ui._assembly_bill_body(tabling)
	if ask_body.find("Endorse it") == -1:
		_fail("an unendorsed tabling card does not offer the stand: %s" % ask_body)
	tabling["endorse_bonus"] = 0.10
	var endorsed_body: String = main_ui._assembly_bill_body(tabling)
	if endorsed_body.find("Endorse it") != -1 or endorsed_body.find("on the record") == -1:
		_fail("an endorsed tabling card still offers the stand: %s" % endorsed_body)
	# The ultra pass-4 finding: a COURT STRIKE outranks every other wording,
	# on BOTH paths that reach this builder -- a release the court stopped
	# still carries released/assembly_bill, and a struck division still
	# carries its tally. "Comes into force" and "defeated, N ayes" against a
	# bill the court stopped are both the card contradicting the state it
	# announces; the court sentence prints alone.
	var struck_release: Dictionary = released.duplicate(true)
	struck_release["struck_down"] = true
	struck_release["passed"] = false
	struck_release["yes_seats"] = 300
	struck_release["no_seats"] = 250
	var struck_body: String = main_ui._assembly_result_body(struck_release)
	if struck_body.find("struck") == -1:
		_fail("a struck-down release's card does not name the court: %s" % struck_body)
	if struck_body.find("comes into force") != -1 or struck_body.find("ayes") != -1:
		_fail("a struck-down card words the coming-into-force or the tally: %s" % struck_body)
	var struck_division: Dictionary = {
		"assembly_bill": true, "law_id": String(released["law_id"]), "passed": false,
		"struck_down": true, "majority": "simple",
		"yes_seats": 300, "no_seats": 250, "abstain_seats": 0, "seats_total": 577,
		"party_votes": {}, "party_support": {}, "party_rebels": {},
	}
	var struck_div_body: String = main_ui._assembly_result_body(struck_division)
	if struck_div_body.find("struck") == -1 or struck_div_body.find("defeated") != -1:
		_fail("a struck-down division's card reads its own tally: %s" % struck_div_body)
	main_ui.free()

	# THE PANEL's record of the same release (the ultra pass-7 finding): the
	# result summary gave a release the IN FORCE verdict and then printed the
	# division tally underneath it -- "Yes 0 · No 0 · Abstain 0, of 577 seats",
	# a chamber that never sat, reported as one that voted. The card above
	# already refuses the tally on a release; the panel's own builder is
	# driven here on the machine's own dict, the bare-instance way the card
	# body is (it reads only the loader and its argument).
	var panel_ui = load("res://src/ui/law_panel.gd").new()
	panel_ui._loader = _loader
	var release_summary = panel_ui._build_result_summary(released)
	var summary_text := _labels_text(release_summary)
	panel_ui.free()
	if summary_text.find("Yes 0") != -1:
		_fail("a release's result summary prints a seat tally -- a hold's release has no division, the chamber never sat: %s" % summary_text)
	if summary_text.find("IN FORCE") == -1:
		_fail("a release's result summary lost its verdict line: %s" % summary_text)


## THE COLLISION, the ultra pass-4 finding: a PMB dividing the same month an
## assembly-origin hold releases. Both results carry the assembly marker and
## the SAME month stamp, and the division -- the later writer -- overwrites
## ns.last_law_result before the announcer reads it, so the release card was
## permanently unreachable. main.gd now captures the release between its two
## ticks and hands it to the announcer beside the division, whose memory holds
## one slot per card. Ticks run in main's order, the capture mirrors main's,
## and the announcer runs on a bare main with a recording stack.
class _StubStack:
	var pushed: Array = []
	func push(title: String, body: String, _actions: Array = []) -> String:
		pushed.append({"title": title, "body": body})
		return "card_%d" % pushed.size()
	func set_body(_id: String, _body: String) -> void:
		pass
	func dismiss(_id: String) -> void:
		pass


class _StubHUD:
	var message_stack
	func _init() -> void:
		message_stack = _StubStack.new()


func _test_release_and_division_same_month() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var refused = _pool_law(ns, false)
	if refused == null:
		_fail("the collision leg needs a Senat-refusing pool law")
		return
	ns.held_bills[String(refused.id)] = {"months": 1, "origin": "assembly"}
	ns.assembly_bills["pmb_collision"] = _hand_bill(ENDORSE_LAW)
	# Main's order: Legislature, capture, Statute, announce.
	Legislature.tick_month(gs, _loader)
	var assembly_release: Dictionary = {}
	var release_result: Dictionary = ns.last_law_result
	if bool(release_result.get("assembly_bill", false)) \
			and bool(release_result.get("released", false)):
		assembly_release = release_result.duplicate(true)
	if assembly_release.is_empty():
		_fail("setup: the hold did not release with its assembly keys -- the capture has nothing to hand over: %s" % [release_result])
		return
	Statute.tick_month(gs, _loader)
	var division_result: Dictionary = ns.last_law_result
	if String(division_result.get("law_id", "")) != ENDORSE_LAW:
		_fail("setup: the in-tray bill did not divide this month: '%s'" % division_result.get("law_id", ""))
		return
	if int(division_result.get("assembly_division_month", -2)) \
			!= int(assembly_release.get("assembly_division_month", -3)):
		_fail("setup: the two results must share the month stamp -- that is the collision")
		return
	var main_ui = load("res://src/ui/main.gd").new()
	main_ui._loader = _loader
	main_ui._state = gs
	main_ui._hud = _StubHUD.new()
	main_ui._announce_assembly_events(assembly_release)
	var pushed: Array = main_ui._hud.message_stack.pushed
	if pushed.size() != 2:
		_fail("a collision month pushed %d cards -- the release and the division must BOTH land" % pushed.size())
	else:
		# Pin that neither result is lost: each pushed card carries its own
		# result's body, built the only way a body is built.
		var release_body: String = main_ui._assembly_result_body(assembly_release)
		var division_body: String = main_ui._assembly_result_body(division_result)
		if String(pushed[0]["body"]) != release_body:
			_fail("the release card's body is not the release's own: %s" % [pushed[0]])
		if String(pushed[1]["body"]) != division_body:
			_fail("the division card's body is not the division's own: %s" % [pushed[1]])
	# A quiet month re-announces neither (the tray is cleared: a generated bill
	# would legitimately push its own tabling card and spoil the count).
	ns.assembly_bills.clear()
	main_ui._announce_assembly_events({})
	if main_ui._hud.message_stack.pushed.size() != 2:
		_fail("a quiet month re-announced a collision card")
	# And the SOURCE: the capture must sit between the two ticks it guards.
	var text := FileAccess.get_file_as_string("res://src/ui/main.gd")
	var legislature_idx := text.find("Legislature.tick_month")
	var capture_idx := text.find("var assembly_release")
	var statute_idx := text.find("Statute.tick_month")
	if not (legislature_idx < capture_idx and capture_idx < statute_idx):
		_fail("main.gd does not capture the release between its two ticks -- a same-month division swallows the release card")
	main_ui.free()


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


## THE REBELLION CHARGE on the assembly's own division -- the ultra pass-2
## finding: every other division path applied Discipline.penalise_rebellions()
## and this one skipped it, so the identical division cost two different
## disciplines by route. The endorsement is what makes rebels ordinary here:
## the bonus drags coalition lines across the abstain band while the members'
## own spatial view stays put, and the strain that split measures is exactly
## this charge's subject.
func _test_division_charges_rebellion_discipline() -> void:
	var treated = _fresh()
	treated[1].assembly_bills["pmb_rebel"] = _hand_bill(ENDORSE_LAW)
	var discipline_before: Dictionary = treated[1].party_discipline.duplicate()
	Statute.endorse(treated[0], treated[1], _loader, "pmb_rebel")
	_tick(treated[0])
	var rebels: Dictionary = treated[1].last_law_result.get("party_rebels", {})
	if rebels.is_empty():
		_fail("the endorsed division shed no rebels -- the discipline leg is vacuous; pick a law whose bonus crosses the abstain band")
		return
	for pid in rebels:
		var before: float = float(discipline_before[pid])
		var after: float = float(treated[1].party_discipline[pid])
		if after >= before:
			_fail("the division did not charge %s's rebellion (%s vs %s) -- resolve_vote() computed rebels the machine never priced" % [
				pid, before, after])


## The ultra pass-2 lobby finding: the pick read the AUTHORED share and gated
## on nothing, so the sector's biggest major was named as backer while FAILED.
## The failure is committed exactly as industry.gd writes it (the sparse
## register: the flag, the zeroed share, the cleared seat), the fixture month
## is the same measured draw the healthy leg above runs, and the OTHER major
## must sign the ask.
func _test_lobby_skips_dead_firms() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	gs.year = 2
	gs.month = 2
	if Cycle.unit("statute|lobby|%s" % PLAYER, _month_index(gs) + 1) >= SK.LOBBY_HAZARD_MONTHLY:
		_fail("test setup: the drawn lobby month no longer fires -- recompute the fixture month")
		return
	ns.companies[LOBBY_FIRM] = {
		"failed": true, "share": 0.0, "board_chair": "", "rescue_months_left": 6,
	}
	ns.regulation_burden[LOBBY_SECTOR] = 0.5
	_tick(gs)
	var backed := ""
	var chief := ""
	for bill_id in ns.assembly_bills:
		var entry: Dictionary = ns.assembly_bills[bill_id]
		if String(entry.get("backer_firm", "")) != "":
			backed = String(entry["backer_firm"])
			chief = String(entry.get("backer_chief", ""))
	if backed != "FRA_sevrenne":
		_fail("the lobby picked '%s' with the sector's biggest major dead -- expected FRA_sevrenne" % backed)
	if chief != "FRA_chief_sevrenne":
		_fail("the dead firm's chief signed the ask: '%s'" % chief)


## F12's pin, recorded so the refuted class can never land silently: a composed
## law held by the chamber is APPLIED at release, not silently destroyed. The
## release's lookup is the loader's, and a composed law is not in loader.laws
## -- without the register fallback in legislature._tick_held_bills the entry
## was erased and the act vanished: no effects, no result, no error. The law
## composes through the machine (the tax test's birth idiom), the hold is
## hand-written THE MACHINE'S WAY, and one legislature tick releases it.
func _test_held_composed_law_applies_at_release() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var spec := {
		"name": "The Border Adjustment",
		"position": {"economic": 0.0, "social": 0.0},
		"channels": {"other_revenue_pct_gdp": 0.3},
	}
	var r: Dictionary = Statute.draft(gs, ns, _loader, spec)
	if not bool(r.get("ok", false)):
		_fail("the composed hold leg's spec refused: %s" % r.get("refusal", ""))
		return
	var law_id := String(r["draft_id"])
	for i in range(int(ns.draft_bills[law_id]["months_left"])):
		Statute.tick_month(gs, _loader)
	if not ns.custom_laws.has(law_id):
		_fail("the composition never completed -- the hold leg has no law to hold")
		return
	ns.held_bills[law_id] = {"months": 1, "origin": "assembly"}
	var before: float = float(ns.law_other_revenue_pct_gdp)
	Legislature.tick_month(gs, _loader)
	if ns.held_bills.has(law_id):
		_fail("the hold did not release after its month")
		return
	if not is_equal_approx(float(ns.law_other_revenue_pct_gdp), before + 0.3):
		_fail("the held composed law was silently destroyed at release: %s vs %s -- the release must resolve the composed register" % [
			ns.law_other_revenue_pct_gdp, before + 0.3])
	var released: Dictionary = ns.last_law_result
	if String(released.get("law_id", "")) != law_id or not bool(released.get("released", false)):
		_fail("the composed law's release recorded no result: %s" % [released])


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
