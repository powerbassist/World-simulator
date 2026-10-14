extends SceneTree

## V1.8. Events: the content schema, the deterministic hazard, the one pending slot, the
## deadline and its default, and the verb. Model: docs/events-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen, and each is
## a property this session's shape rests on:
##
##   - THERE IS NO RANDOMNESS. The hazard is a pure function of (nation, event, absolute
##     month), so the same state always produces the same crisis in the same month --
##     which is what keeps Budget.project() exactly equal to what subsequently happens,
##     an MVP done-when condition. Asserted by reading the source AND by running it;
##   - A CHOICE MAY NOT WRITE effects.institutional, because that is Emergency powers and
##     it is tiered Someday. Refused at LOAD, so the schema carries the rule rather than
##     the docs;
##   - A CHOICE MAY NOT BE EMPTY. A button that costs nothing resolves the deadline for
##     free and strictly dominates every alternative -- the shape this project has killed
##     eleven times, and the one version of it that cannot be tuned away by a probe;
##   - EXACTLY ONE DEFAULT, refused at load, because what happens when the player says
##     nothing is the whole of "forces a response under time pressure";
##   - `event_history` IS NEVER READ BACK by src/sim/. V1.3e's *no grievance ledger*
##     property and V1.3f's own `foreign_acts` check, in the session most likely to be
##     tempted to build the ledger literally;
##   - src/sim/legislature.gd NEVER NAMES src/sim/events.gd. The dependency runs one way,
##     and if it ever runs the other the effect application has two owners;
##   - EVERY HARNESS TICKS IT. V1.5d shipped with neither balance harness calling
##     Media.tick_month(), so both ran the pre-session model and their agreement about a
##     bit-identical re-run was about nothing. tests/test_referendum.gd made that check
##     structural for two files; this extends it to FOUR, adding src/sim/budget.gd's
##     project() and src/ui/main.gd;
##   - THE OTHER TWENTY-EIGHT GET EVENTS AND ANSWER THEM THEMSELVES (V4.4). The AI
##     chooser closed defence-model's "no AI chooser" limitation, recorded a sixth
##     time at V1.8 and closed here at the rule: an AI nation delivers and resolves
##     in the same tick, deterministically, against its own position -- and it never
##     holds a desk, so its queue is structurally always empty;
##   - src/sim/calendar.gd IS STILL A LEAF after gaining an event row.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const GameEvent = preload("res://src/core/event.gd")
const Events = preload("res://src/sim/events.gd")
const EventHooks = preload("res://src/sim/event_hooks.gd")
const EventChooser = preload("res://src/sim/event_chooser.gd")
const K = preload("res://src/sim/events_constants.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

const PLAYER := "FRA"
const START_YEAR := 2026

## Named rather than derived, for tests/test_projects.gd's reason: a test that picks its
## own subject silently changes what it measures when the content moves.
const HAZARD_ONLY := "procurement_scandal"
const GATED := "emergency_budget_demand"
const ONCE_ONLY := "broadcast_charter"

## The two climate events' ids. V3.5f: the disaster file carries BOTH (V4.4 moved
## them there from the retired climate.json), so
## the sweep below runs the LOADER's events -- a lost `"sited": true`, a renamed id or
## a missing file fails there as missing content instead of passing on fixtures. The
## schema tests above still build their own through _make_event(), because a schema
## test needs an event no content edit can move.
const SITED_A := "river_flood"
const SITED_B := "heat_wave"

const NEWLINE := "\n"

var _failures: Array[String] = []
var _loader


## The pieces of the real loader the tick reads: the event list, the goods table
## the commodity_price_high hook prices against, and the region map a delivery
## names a sited event from. A fixture is not content, so the record tests hand
## this in rather than shipping test events in data/events/ -- and the goods and
## regions stay EMPTY, so the hook is inert and no sited name resolves here by
## construction rather than by a default in the machine.
class _StubLoader:
	var events: Array = []
	var commodity_goods: Dictionary = {}
	var regions: Dictionary = {}


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_content_loads()
	_test_every_event_has_exactly_one_default()
	_test_no_choice_is_empty()
	_test_institutional_is_refused_by_name()
	_test_approval_precondition_is_refused()
	_test_emissions_precondition_resolves()
	_test_a_second_default_is_refused()
	_test_a_choice_with_no_effects_is_refused()
	_test_no_randomness_in_the_source()
	_test_the_hazard_is_a_pure_function()
	_test_the_hazard_actually_fires()
	_test_register_seeds_empty()
	_test_one_pending_slot()
	_test_the_default_applies_exactly_once()
	_test_answering_applies_the_choice()
	_test_answering_early_and_late_cost_the_same()
	_test_once_is_marked_at_delivery()
	_test_the_quiet_period_holds()
	_test_the_quiet_cadence_is_delivery_month_plus_three()
	_test_an_ai_fiscal_answer_never_touches_the_players_budget()
	_test_the_diary_shows_the_deadline()
	_test_calendar_is_still_a_leaf()
	_test_the_nine_never_get_an_event()
	_test_history_is_never_read_back()
	_test_the_dependency_runs_one_way()
	_test_every_harness_ticks_it()
	_test_the_hash_is_not_copied()
	_test_the_desk_is_bounded()
	_test_the_desk_does_not_double_hold()
	_test_a_desk_resident_does_not_crowd_out_a_sibling()
	_test_the_cooldown_floor_is_one_month()
	_test_a_chain_may_arm_a_hook_event()
	_test_a_chain_ignores_the_targets_preconditions()
	_test_a_desk_resident_does_not_crowd_out_a_hook_sibling()
	_test_the_weighted_pick_is_pure_and_weighted()
	_test_hooks_fire_on_staged_registers()
	_test_chains_arm_and_land()
	_test_the_per_event_cooldown_binds()
	_test_the_chooser_situates()
	_test_the_hook_vocabulary_is_swept()
	_test_the_interrupt_flag()
	_test_tick_order_pin()
	_test_sited_schema_loads()
	_test_the_site_draw_is_pure()
	_test_sited_register_carries_place()
	_test_a_non_sited_register_gains_no_keys()
	_test_the_climate_content()
	_test_every_nation_can_be_sited()
	_test_the_union_book_needs_membership()
	_finish()


## V2.4b, and the reversal of a V1.8 call for one flagged class. Four halves,
## each pinned where it lives:
##
##   the SCHEMA opens by exactly one boolean -- absent in a version-27 save it
##   reads false, which is the truth about that save, so no bump and the
##   unknown-key refusal still guards every OTHER field;
##   announce COPIES the flag into the pending register, because the thing
##   that pauses the clock reads the register and has no access to content;
##   the shipped content exercises it -- blackout_night carries the flag, and
##   the pause path reads it at the tick AND at load (the reload re-raise);
##   and the non-modal argument survives: a non-flag event pauses NOTHING,
##   which is asserted at source because the pause is a line in another file's
##   handler.
func _test_the_interrupt_flag() -> void:
	# Schema: the key is known, absent reads false, and the default is
	# non-interrupt.
	var raw := {"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "category": "scandal",
		"respond_months": 2, "choices": [
			{"id": "a", "label": "A", "summary": "do a", "effects": {"bloc_offset": {"business": 0.01}}, "default": true},
			{"id": "b", "label": "B", "summary": "do b", "effects": {"bloc_offset": {"workers": 0.01}}},
		]}
	var errs: Array[String] = []
	var ev = GameEvent.from_dict(raw.duplicate(true), "x.json", errs,
		EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS, EconomyK.SECTOR_TREND.keys())
	if not errs.is_empty() or ev.interrupt:
		_fail("an event without the flag did not default to non-interrupt (errs=%s)" % [errs])

	# from_dict READS the key off the content; the load path is the proof.
	var errs2: Array[String] = []
	var with_key: Dictionary = raw.duplicate(true)
	with_key["interrupt"] = true
	var ev2 = GameEvent.from_dict(with_key, "x.json", errs2,
		EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS, EconomyK.SECTOR_TREND.keys())
	if not ev2.interrupt:
		_fail("from_dict did not read interrupt: true off the content")

	# The register: announce copies the flag.
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	_announce(state, ev2)
	if _entry(ns, "x").get("interrupt", "MISSING") != true:
		_fail("announce did not copy the interrupt flag into the queue entry")
	# and a non-flag event's entry reads false, not missing. A DIFFERENT id: the
	# queue keeps both entries, so the same id would read the interrupt one back.
	var raw3: Dictionary = raw.duplicate(true)
	raw3["id"] = "y"
	var ev3 = GameEvent.from_dict(raw3, "y.json", errs2,
		EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS, EconomyK.SECTOR_TREND.keys())
	_announce(state, ev3)
	if bool(_entry(ns, "y").get("interrupt", false)):
		_fail("a non-interrupt event's queue entry claims the flag")

	# The shipped content: the one crisis that stops the clock.
	var crisis = null
	for e in _loader.events:
		if String(e.id) == "blackout_night":
			crisis = e
	if crisis == null:
		_fail("blackout_night did not load -- the interrupt class ships with no member")
	elif not crisis.interrupt:
		_fail("blackout_night does not carry interrupt: true")

	# The pause path, at source: it exists, it is reached from BOTH the month
	# tick and the load path, and it gates on the flag rather than pausing for
	# every event -- V1.8's non-modal argument survives everywhere else.
	var file := FileAccess.open("res://src/ui/main.gd", FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	if not text.contains("func _enforce_interrupt()"):
		_fail("main.gd has no _enforce_interrupt -- the reversal is not wired")
	var in_load := false
	var load_raises := false
	for line in text.split("
"):
		if line.begins_with("func _on_load_requested"):
			in_load = true
		elif in_load and line.begins_with("func "):
			break
		elif in_load and line.contains("_enforce_interrupt()"):
			load_raises = true
	if not load_raises:
		_fail("the load path does not re-raise an interrupt -- a save mid-crisis reloads past the question")
	if not text.contains("_enforce_interrupt()"):
		_fail("_enforce_interrupt is defined but never called")
	# the gate: the pause happens only behind the flag read
	var in_fn := false
	var gated := false
	for line in text.split("
"):
		if line.begins_with("func _enforce_interrupt"):
			in_fn = true
		elif in_fn and line.begins_with("func "):
			break
		elif in_fn and line.contains("interrupt_pending("):
			gated = true
	if not gated:
		_fail("_enforce_interrupt does not gate on the flag -- it would pause for every event, and V1.8's argument would die")


# --- V3.5: the schema grows `sited` ----------------------------------------------

## The interrupt precedent, one boolean later: absent reads false, which is the truth
## about every event file and every save made before the key existed, so no bump and
## the unknown-key refusal still guards every OTHER field.
func _test_sited_schema_loads() -> void:
	var plain = _make_event("plain_event", false)
	if plain.sited:
		_fail("an event without 'sited' did not default to false")
	var sited = _make_event(SITED_A, true)
	if not sited.sited:
		_fail("from_dict did not read sited: true off the content")


## The site is a pure function of (nation, event, absolute month) -- the SAME hash
## family as the hazard, salted. A save reloaded on the arrival month therefore gets
## the same crisis in the same place. Two different months CAN draw two different
## places, but the assertion here is purity, not movement: movement is witnessed over
## the sweep below, not asserted month to month.
func _test_the_site_draw_is_pure() -> void:
	for combo in [["FRA", SITED_A, 13], ["DEU", SITED_B, 38], ["GBR", SITED_A, 12], ["FRA", SITED_B, 13]]:
		var n: int = combo[2]
		for m in range(Events._absolute_month(2027, 1), Events._absolute_month(2031, 1)):
			var a: int = Events._site_index(combo[0], combo[1], m, n)
			var b: int = Events._site_index(combo[0], combo[1], m, n)
			if a != b:
				_fail("the site draw gave two answers for %s/%s month %d" % [combo[0], combo[1], m])
			if a < 0 or a >= n:
				_fail("the site draw returned %d against %d regions -- announce would index past the register" % [a, n])
	# One region takes index 0 -- the CYP/EST/LTU/LVA/MLT bound named in the handoff:
	# a nation of one region cannot differ from itself, and a hash would be a second
	# answer to a question with one response.
	if Events._site_index("MLT", SITED_A, Events._absolute_month(2029, 7), 1) != 0:
		_fail("a one-region nation did not draw its only region")
	# The salt is what keeps a site draw from being the hazard draw's echo, and its
	# absence is behaviourally invisible over any short sweep -- both draws stay
	# pure -- so it is pinned at source, _enforce_interrupt()'s way.
	if not _code("res://src/sim/events.gd").contains("|site"):
		_fail("the site draw lost its salt -- it is the hazard stream again")


## A past act's site cannot be re-derived once the shares have moved -- V2.6b1's
## record argument -- and the calendar is a leaf, so the register stores id AND name.
func _test_sited_register_carries_place() -> void:
	var state = _new_state()
	var ns = state.player()
	var ev = _make_event(SITED_A, true)
	_announce(state, ev)

	var drawn := String(Events.head_entry(ns).get("region_id", ""))
	var named := String(Events.head_entry(ns).get("region_name", ""))
	if drawn == "" or named == "":
		_fail("a sited event's register carries id '%s' name '%s'" % [drawn, named])
		return
	if not ns.region_pop_share.has(drawn):
		_fail("the register's region '%s' is not one of the nation's live regions" % drawn)
	# The name must be the LOADER's name for the drawn id -- consistent with the same
	# array every UI helper scans -- not merely with whatever this test handed in.
	for region in _loader.regions.get(ns.id, []):
		if String(region.id) == drawn and String(region.region_name) != named:
			_fail("the register names %s '%s', the loader says '%s'" % [drawn, named, region.region_name])
	# And the keys gained are exactly the queue entry's own: the V1.8 register's
	# shape grown by severity and category (V4.4) and by the sited pair (V3.5).
	for key in Events.head_entry(ns).keys():
		if key != "event_id" and key != "event_name" and key != "months_left" \
				and key != "interrupt" and key != "severity" and key != "category" \
				and key != "region_id" and key != "region_name":
			_fail("a sited register gained '%s'" % key)

	# The diary row carries the place, because the register does -- the one UI
	# surface this file can reach headless.
	var found := false
	for row in Calendar.fixed_dates(state):
		if String(row.get("kind", "")) == CalendarK.FIXED_EVENT:
			found = true
			if String(row.get("ref", "")) != "%s — %s" % [ev.event_name, named]:
				_fail("the diary row carries '%s', without the place" % row.get("ref", ""))
	if not found:
		_fail("a sited event does not appear in the diary")

	# And the record keeps it after the register is gone. choose() resolves the
	# event off the loader, so the fixture rides a stub carrying exactly it -- the
	# stub's bloc_offset effects reach apply_effects without a real loader.
	var stub := _StubLoader.new()
	stub.events = [ev]
	var record := Events.choose(state, stub, "b")
	if record.is_empty():
		_fail("answering the sited fixture recorded nothing")
	elif String(record.get("region_name", "")) != named:
		_fail("the history record lost the place: '%s'" % String(record.get("region_name", "")))


## THE OLD-SAVE-SHAPE PIN. A non-sited event's register is what version-31 through 34
## saves carry, byte for byte: no empty-string keys, nothing to read differently.
func _test_a_non_sited_register_gains_no_keys() -> void:
	var state = _new_state()
	var ns = state.player()
	_announce(state, _event(HAZARD_ONLY))
	for key in ["region_id", "region_name"]:
		if Events.head_entry(ns).has(key):
			_fail("a non-sited event's register gained '%s' -- old saves and old events must read identically" % key)


## The loud gate: both climate events, over two years, for every one of the
## twenty-nine nations. V3.5f runs the LOADER's events -- the fixtures above built
## their own, and a green sweep over them would say nothing about the file the player
## actually loads. A draw outside a nation's own live register, or a region with no
## name, means announce and the loader have come apart. The sweep also witnesses
## MOVEMENT: a nation of several regions whose 48 draws are all one region is the
## constant-return defect (V2.6b1's static site) and not a coincidence -- at France's
## 13 regions the odds are (1/13)^47.
func _test_every_nation_can_be_sited() -> void:
	var state = _new_state()
	if state.nations.size() != 29:
		_fail("the sweep ran over %d nations, expected 29" % state.nations.size())
	var events: Array = []
	for ev_id in [SITED_A, SITED_B]:
		var ev = _event(ev_id)
		if ev == null:
			_fail("the sited content '%s' did not load, so the sweep would pass on nothing" % ev_id)
		elif not ev.sited:
			_fail("'%s' loaded without \"sited\": true -- the sweep would sweep a non-sited event" % ev_id)
		else:
			events.append(ev)
	if events.size() != 2:
		return
	var varied := false
	for nation_id in state.nations.keys():
		var ns = state.nations[nation_id]
		var by_id: Dictionary = Events.region_names(ns, _loader)
		var distinct := {}
		for ev in events:
			for i in range(24):
				Events.announce(ns, ev, Events._absolute_month(2027, 1) + i, by_id)
				# The sweep drives the RAW primitive month by month, so the
				# draw under test is the LAST entry -- the queue keeps them
				# all, which is exactly what makes the sweep legible.
				var last: Dictionary = ns.event_queue[ns.event_queue.size() - 1]
				var drawn := String(last.get("region_id", ""))
				var named := String(last.get("region_name", ""))
				if drawn == "" or not ns.region_pop_share.has(drawn):
					_fail("%s drew '%s', which is not one of its own regions" % [nation_id, drawn])
					continue
				if named == "":
					_fail("%s drew %s with no name" % [nation_id, drawn])
				elif named != String(by_id.get(drawn, "")):
					_fail("%s names %s '%s', the loader says '%s'" % [nation_id, drawn, named, by_id.get(drawn, "")])
				distinct[drawn] = true
		if ns.region_pop_share.size() > 1:
			if distinct.size() == 1:
				_fail("%s drew %s in all 48 draws -- the site cannot move" % [nation_id, distinct.keys()[0]])
			else:
				varied = true
	if not varied:
		_fail("no nation's site draw ever varied over the whole sweep")


## The content pins, for the reason blackout_night's interrupt pin exists: the machine
## tests run fixtures, so nothing else would notice the day the file loses its key or
## its split. river_flood is the pure-hazard member -- a revelation of rain, arriving
## whether or not it is deserved -- and heat_wave the preconditioned one, gated on the
## live emissions field at the measured 6.5 t. A session that changes either half of
## the split comes here and says why.
func _test_the_climate_content() -> void:
	var flood = _event(SITED_A)
	var heat = _event(SITED_B)
	if flood == null or heat == null:
		return
	if not flood.preconditions.is_empty():
		_fail("river_flood carries a gate -- the pure-hazard member of the split is the point")
	if heat.preconditions.size() != 1:
		_fail("heat_wave carries %d precondition rows, expected the one emissions gate" % heat.preconditions.size())
	else:
		var row: Dictionary = heat.preconditions[0]
		if String(row["field"]) != "co2e_per_capita_t" or String(row["op"]) != ">=" or float(row["value"]) != 6.5:
			_fail("heat_wave's gate is not the measured co2e_per_capita_t >= 6.5: %s" % [row])
	for ev in [flood, heat]:
		if ev.once:
			_fail("'%s' is a once event -- a hazard that cannot recur is a script, not climate" % ev.id)
		# The split's France answer at the 2026 baseline: the flood's gate is open by
		# construction (there is nothing to meet), the heat wave's closed at 4.0 t --
		# until the grid that feeds the live field is rebuilt dirtier.
		var ns = _new_state().player()
		var expected_open: bool = ev.id == SITED_A
		if Legislature.preconditions_met(ns, ev.preconditions) != expected_open:
			_fail("France's gate for '%s' reads %s at the 2026 baseline -- wrong half of the split" % [ev.id, not expected_open])


## Five hooks read registers written earlier in the SAME tick: five compare
## emitter stamps against `== month_index` (member_bill_passed, takeover_bid,
## firm_failed, accession_won, and commodity_price_high, whose stamp is
## `ns.commodity_high_month` -- an edge, not a level read). They fire only because Events.tick_month runs AFTER
## Commodities, Orgs, Legislature, Statute and Industry in `_on_month_elapsed`;
## the pin in test_commodities.gd holds only Economy < Commodities < Opinion, so
## this is the pin for the Events end. The balance probe mirrors the order and is
## held to it too, as is tests/test_balance.gd's loop, as are Budget.project()
## and test_budget's mirror of it -- those two never tick Commodities (the
## projection prices no goods) and never tick Legislature (budget.gd says so
## beside its Statute call), so they are held to the three predecessors they do
## run.
const _EVENTS_READS_AFTER := {
	"Commodities": "the commodity_price_high hook reads the commodity_high_month crossing stamp Commodities writes",
	"Orgs": "the accession_won hook reads ns.last_accession",
	"Legislature": "the member_bill_passed hook reads assembly_bill_passed_month, which Legislature._tick_held_bills writes for an assembly-origin release",
	"Statute": "the member_bill_passed hook reads the assembly_bill_passed_month stamp",
	"Industry": "the takeover_bid and firm_failed hooks read industry registers",
}

func _test_tick_order_pin() -> void:
	var all_five := ["Commodities", "Orgs", "Legislature", "Statute", "Industry"]
	_check_events_order_in("res://src/ui/main.gd", all_five)
	_check_events_order_in("res://tools/balance_probe.gd", all_five)
	# test_balance's month loop is the other balance harness: it ticks all five
	# (Commodities since pass 17), so it is held to the same order as main.gd.
	_check_events_order_in("res://tests/test_balance.gd", all_five)
	# The two measurement probes whose loops tick Events: held to the same order as
	# main.gd so the hooks that read these registers can fire in what they measure.
	_check_events_order_in("res://tools/agency_probe.gd", all_five)
	_check_events_order_in("res://tools/programme_probe.gd", all_five)
	_check_events_order_in("res://src/sim/budget.gd", ["Orgs", "Statute", "Industry"])
	_check_events_order_in("res://tests/test_budget.gd", ["Orgs", "Statute", "Industry"])


## Line of the first CALL `<module>.tick_month(` -- comment lines skipped, since
## budget.gd's own comments name Orgs.tick_month() above the loop.
func _first_call_line(lines: PackedStringArray, module: String) -> int:
	var needle := module + ".tick_month("
	for i in lines.size():
		var code := lines[i].strip_edges()
		if code.begins_with("#"):
			continue
		if code.begins_with(needle):
			return i
	return -1


func _check_events_order_in(path: String, predecessors: Array) -> void:
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		_fail("could not read %s" % path)
		return
	var lines := src.split("\n")
	var events_at := _first_call_line(lines, "Events")
	if events_at == -1:
		_fail("%s is missing Events.tick_month(" % path)
		return
	for module: String in predecessors:
		var at := _first_call_line(lines, module)
		if at == -1:
			_fail("%s is missing %s.tick_month( -- Events reads after it" % [path, module])
		elif at > events_at:
			_fail("%s: Events.tick_month (line %d) must be after %s.tick_month (line %d) -- %s" % [
				path, events_at + 1, module, at + 1, _EVENTS_READS_AFTER[module]])

func _finish() -> void:
	if _failures.is_empty():
		print("test_events: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


## The Union's letters are addressed to members. GBR and CHE are playable and sit
## outside the Union, and an ungated Commission letter dealt a non-member player
## "the vote is this month" over a treaty they never signed (the pass-14 find).
## `eu_member` is a live 0/1 read off ns.orgs, so this pins both directions: the
## gate closes for a nation with no `eu` org and opens again on accession.
func _test_the_union_book_needs_membership() -> void:
	var gated := ["eu_infringement_notice", "eu_quota_fight", "eu_summit_ambush",
		"eu_eastern_partner_row", "eu_rule_of_law_clause", "eu_farm_rules_fight",
		"eu_border_checks_row", "eu_eurozone_plea", "eu_backbench_bill",
		"for_neighbour_checks", "state_aid_complaint", "dumping_allegation"]
	var state = _new_state()
	var ns = state.player()
	var month := Events._absolute_month(int(state.year), int(state.month))
	var saved_orgs: Array = ns.orgs.duplicate()
	for id in gated:
		var ev = _event(id)
		if ev == null:
			_fail("the membership-gated fixture '%s' is not in the book" % id)
			continue
		ns.orgs = []
		if Events._gates_pass(ns, ev, month):
			_fail("%s passed its gates for a nation outside the Union" % id)
		ns.orgs = ["eu"]
		var passes := Events._gates_pass(ns, ev, month)
		# A gate that also names a figure (growth, deficit) may fail on the
		# figure; the membership leg must be the ONLY thing between a member and
		# an ungated event, so the ungated ones are asserted open.
		if ev.preconditions.size() == 1 and not passes:
			_fail("%s is closed to an EU member -- the membership gate is the only gate it names" % id)
	ns.orgs = saved_orgs


func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = START_YEAR
	state.month = 1
	return state


func _event(id: String):
	return Events.event_by_id(_loader, id)


## The two arguments announce() grew at V3.5, filled exactly as tick_month fills them,
## so a test that stages an event stages it the way the month tick would.
func _announce(state, ev) -> void:
	var ns = state.player()
	Events.announce(
		ns, ev,
		Events._absolute_month(int(state.year), int(state.month)),
		Events.region_names(ns, _loader)
	)


## The queue entry for one event id, or {}. The tests read their OWN entry now that
## the desk holds several -- a test that read the head would measure whichever
## crisis happened to sort first, which is the queue's business, not the test's.
func _entry(ns, event_id: String) -> Dictionary:
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) == event_id:
			return entry
	return {}


## A fixture built through the real from_dict, so a schema refusal fails here rather
## than in the content that will one day carry the key.
func _make_event(id: String, sited: bool):
	var raw := {"id": id, "name": id.capitalize(), "summary": "s", "likelihood": 0.05, "category": "scandal",
		"respond_months": 2, "choices": [
			{"id": "a", "label": "A", "summary": "do a", "effects": {"bloc_offset": {"business": 0.01}}, "default": true},
			{"id": "b", "label": "B", "summary": "do b", "effects": {"bloc_offset": {"workers": 0.01}}},
		]}
	if sited:
		raw["sited"] = true
	var errs: Array[String] = []
	var ev = GameEvent.from_dict(raw, "x.json", errs,
		EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS, EconomyK.SECTOR_TREND.keys())
	if not errs.is_empty():
		_fail("the fixture '%s' did not load: %s" % [id, errs])
	return ev


## src/ui/main.gd's order, trimmed to what an event reads and what reads an event.
func _tick(state, months_in: int) -> void:
	state.year = START_YEAR + int(months_in / 12)
	state.month = (months_in % 12) + 1
	Economy.tick_month(state)
	Budget.tick_month(state)
	Inflation.tick_month(state)
	Opinion.tick_month(state)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Events.tick_month(state, _loader)


func _source(path: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		_fail("could not read %s" % path)
	return src


## The same file with every comment line removed.
##
## THE FIRST RUN OF THIS TEST FAILED ON ITS OWN PROSE, twice: src/sim/events.gd's header
## quotes docs/economy-model.md's ban on `randf()`, and src/sim/legislature.gd's new
## apply_effects() names src/sim/events.gd while explaining why the edge runs the other
## way. docs/projects-model.md records the same failure -- "a fourth was the probe
## reading its own prose" -- and the fix is the same: a check about what the CODE does
## must not be able to be tripped by a sentence about what it does not.
func _code(path: String) -> String:
	var out := ""
	for line in _source(path).split(NEWLINE):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		out += line + NEWLINE
	return out


# --- The content ------------------------------------------------------------------

func _test_content_loads() -> void:
	if _loader.events.is_empty():
		_fail("data/events/ produced no events")
		return
	for id in [HAZARD_ONLY, GATED, ONCE_ONLY]:
		if _event(id) == null:
			_fail("the event '%s' this test is written against is not in the content" % id)


## Nothing on the event list does nothing, and nothing on it is ambiguous about what
## silence means -- V1.3f's property, restated for the one field that decides what the
## deadline is for.
func _test_every_event_has_exactly_one_default() -> void:
	for ev in _loader.events:
		var defaults := 0
		for c in ev.choices:
			if bool(c["is_default"]):
				defaults += 1
		if defaults != 1:
			_fail("'%s' has %d default choices" % [ev.id, defaults])
		if ev.choices.size() < GameEvent.MIN_CHOICES:
			_fail("'%s' offers %d choices" % [ev.id, ev.choices.size()])


func _test_no_choice_is_empty() -> void:
	for ev in _loader.events:
		for c in ev.choices:
			if (c["effects"] as Dictionary).is_empty():
				_fail("'%s.%s' names no effect, so it resolves the deadline for free" % [
					ev.id, c["id"],
				])


# --- The schema's three refusals --------------------------------------------------

## The refusal that has a CITATION rather than only an argument: an event choice writing
## an institution is "Emergency powers", tiered Someday. The error string has to NAME it,
## because a key refused as "unrecognised" reads as a typo and gets re-added.
func _test_institutional_is_refused_by_name() -> void:
	var errors := _validate({
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "category": "scandal", "respond_months": 2,
		"choices": [
			{"id": "a", "label": "A", "summary": "s", "default": true,
			 "effects": {"institutional": {"censure_rule": "constructive"}}},
			{"id": "b", "label": "B", "summary": "s", "effects": {"bloc_offset": {"urban": 0.1}}},
		],
	})
	if not _any_contains(errors, "Emergency powers"):
		_fail("an event choice writing effects.institutional loaded, or was refused without naming Emergency powers: %s" % [errors])


## docs/pledge-model.md refused this field because a promise about your own approval is
## circular; this refuses it because the choice's own price IS approval, so an event
## gated on it is positive feedback with nothing damping it. Two refusals, two reasons,
## one field.
func _test_approval_precondition_is_refused() -> void:
	var errors := _validate({
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "category": "scandal", "respond_months": 2,
		"preconditions": [{"field": "overall_approval_pct", "op": "<=", "value": 40.0}],
		"choices": [
			{"id": "a", "label": "A", "summary": "s", "default": true,
			 "effects": {"bloc_offset": {"urban": -0.1}}},
			{"id": "b", "label": "B", "summary": "s", "effects": {"bloc_offset": {"urban": 0.1}}},
		],
	})
	if errors.is_empty():
		_fail("an event preconditioned on overall_approval_pct loaded")
	# And the field is still legal for a LAW, because the refusal is a subtraction from
	# one list rather than a second list. If this stops being true the two have drifted.
	if not LegislatureK.PRECONDITION_FIELDS.has("overall_approval_pct"):
		_fail("overall_approval_pct was removed from PRECONDITION_FIELDS rather than refused on this channel")


## V3.5: an event may precondition on the nation's emissions. The schema accepts the
## row because the field sits on the ONE precondition list (not the refused
## subtraction), and the row resolves through the same preconditions_met() a law's
## does -- so it must track the LIVE field, or a crisis could not answer a warming
## world.
func _test_emissions_precondition_resolves() -> void:
	var errors := _validate({
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "category": "scandal", "respond_months": 2,
		"preconditions": [{"field": "co2e_per_capita_t", "op": "<=", "value": 8.0}],
		"choices": [
			{"id": "a", "label": "A", "summary": "s", "default": true,
			 "effects": {"bloc_offset": {"urban": -0.1}}},
			{"id": "b", "label": "B", "summary": "s", "effects": {"bloc_offset": {"urban": 0.1}}},
		],
	})
	if not errors.is_empty():
		_fail("an event preconditioned on co2e_per_capita_t was refused: %s" % [errors])

	var state = _new_state()
	var ns = state.player()
	var row := [{"field": "co2e_per_capita_t", "op": "<=", "value": 8.0}]
	if not Legislature.preconditions_met(ns, row):
		_fail("France at %.2f t failed an at-most-8.0 t precondition" % ns.co2e_per_capita_t)
	var measured: float = ns.co2e_per_capita_t
	ns.co2e_per_capita_t = 9.0
	if Legislature.preconditions_met(ns, row):
		_fail("a nation at 9.0 t passed an at-most-8.0 t precondition -- the row is not reading the live field")
	ns.co2e_per_capita_t = measured


func _test_a_second_default_is_refused() -> void:
	var errors := _validate({
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "category": "scandal", "respond_months": 2,
		"choices": [
			{"id": "a", "label": "A", "summary": "s", "default": true,
			 "effects": {"bloc_offset": {"urban": -0.1}}},
			{"id": "b", "label": "B", "summary": "s", "default": true,
			 "effects": {"bloc_offset": {"urban": 0.1}}},
		],
	})
	if errors.is_empty():
		_fail("an event with two defaults loaded")


func _test_a_choice_with_no_effects_is_refused() -> void:
	var errors := _validate({
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "category": "scandal", "respond_months": 2,
		"choices": [
			{"id": "a", "label": "A", "summary": "s", "default": true,
			 "effects": {"bloc_offset": {"urban": -0.1}}},
			{"id": "b", "label": "B", "summary": "s", "effects": {}},
		],
	})
	if errors.is_empty():
		_fail("a choice with no effects loaded, so it resolves the deadline for free")


func _validate(d: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	GameEvent.from_dict(
		d, "test", errors,
		EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS,
		EconomyK.SECTOR_TREND.keys()
	)
	return errors


func _any_contains(errors: Array[String], needle: String) -> bool:
	for e in errors:
		if e.contains(needle):
			return true
	return false


# --- Determinism -------------------------------------------------------------------

## docs/economy-model.md forbids randf() outright. Asserted by reading the file, because
## a run that happens not to call it proves nothing about the next one.
func _test_no_randomness_in_the_source() -> void:
	var src := _code("res://src/sim/events.gd")
	for banned in ["randf", "randi", "RandomNumberGenerator", "randomize"]:
		if src.contains(banned):
			_fail("src/sim/events.gd names '%s'" % banned)


func _test_the_hazard_is_a_pure_function() -> void:
	var ev = _event(HAZARD_ONLY)
	if ev == null:
		return
	for month in range(1, 13):
		var a := Events.hazard_passes(PLAYER, ev.id, 2029, month, ev.likelihood)
		var b := Events.hazard_passes(PLAYER, ev.id, 2029, month, ev.likelihood)
		if a != b:
			_fail("the hazard gave two answers for 2029-%02d" % month)
	# Two nations at the same month must not agree by construction, or "semi-random"
	# collapses into "every country has the same crisis on the same day".
	var same := 0
	for month in range(1, 61):
		if Events.hazard_passes("FRA", ev.id, 2029, month, 0.5) == Events.hazard_passes("DEU", ev.id, 2029, month, 0.5):
			same += 1
	if same == 60:
		_fail("FRA and DEU drew identically in all 60 months, so the nation id is not in the hash")


## A hazard nothing ever clears is content that never loads its own consequence. Checked
## over the horizon a game actually runs rather than over a million draws, because the
## claim worth making is about the game and not about the hash.
func _test_the_hazard_actually_fires() -> void:
	var ev = _event(HAZARD_ONLY)
	if ev == null:
		return
	var hits := 0
	for i in range(168):
		if Events.hazard_passes(PLAYER, ev.id, START_YEAR + int(i / 12), (i % 12) + 1, ev.likelihood):
			hits += 1
	if hits == 0:
		_fail("'%s' never drew in fourteen years at likelihood %s" % [ev.id, str(ev.likelihood)])
	if hits == 168:
		_fail("'%s' drew in every month, so the gate is not a gate" % ev.id)


# --- The register ------------------------------------------------------------------

func _test_register_seeds_empty() -> void:
	var state = _new_state()
	for id in state.nations.keys():
		var ns = state.nations[id]
		if not ns.event_queue.is_empty():
			_fail("%s starts with an event pending" % id)
		if not ns.event_fired.is_empty():
			_fail("%s starts with a fired event" % id)
		if not ns.event_category_quiet.is_empty():
			_fail("%s starts inside a quiet period" % id)
		if not ns.event_cooldowns.is_empty():
			_fail("%s starts inside a cooldown" % id)
		if not ns.event_armed.is_empty():
			_fail("%s starts with a chain armed" % id)
		if not ns.event_history.is_empty():
			_fail("%s starts with a history" % id)


## THE DESK IS A QUEUE, AND SEVERITY ORDERS IT. The V1.8 one-slot argument ("the
## register IS the rule") died with the slot at V4.4's scale -- a draw the world
## considered and withdrew for want of a slot is an occasion with no reason behind
## it. What replaced it is bounded (QUEUE_MAX), ordered worst-first, and deduplicated:
## the same event twice is one occasion, not two, because two entries with one id
## would answer twice through two cards -- the deadline charging double.
func _test_one_pending_slot() -> void:
	var state = _new_state()
	var ns = state.player()
	_announce(state, _event(HAZARD_ONLY))
	_announce(state, _event(GATED))
	if ns.event_queue.size() != 2:
		_fail("announcing twice left %d entries, expected both -- the queue holds what the slot refused" % ns.event_queue.size())
	# Severity descending: the fixture events are both severity 1 and 2
	# (procurement 1, emergency_budget 2), so the fiscal crisis is on top.
	if Events.pending_event_id(ns) != GATED:
		_fail("the head of the desk is %s, not the more severe %s" % [Events.pending_event_id(ns), GATED])
	# Only the ordering premise is checked here; the bound is driven in
	# _test_the_desk_is_bounded and the same-id dedupe in _test_the_desk_does_not_double_hold.
	if K.QUEUE_MAX < 2:
		_fail("QUEUE_MAX is %d -- the ordering check above cannot mean anything" % K.QUEUE_MAX)


## The deadline's whole point. Counted down, applied once at zero, register cleared, and
## the CATEGORY quiet opened. Isolated on a stub loader carrying exactly the fixture --
## with the queue, the real content can land a second crisis in the same window and the
## measured delta would be two events' truth, so the isolation is measurement, not
## convenience (the sited-record test's stub, one job over).
func _test_the_default_applies_exactly_once() -> void:
	var state = _new_state()
	var ns = state.player()
	var ev = _event(HAZARD_ONLY)
	var stub := _StubLoader.new()
	stub.events = [ev]
	var default_choice: Dictionary = ev.default_choice()
	var bloc := String((default_choice["effects"]["bloc_offset"] as Dictionary).keys()[0])
	var delta: float = float(default_choice["effects"]["bloc_offset"][bloc])

	_announce(state, ev)
	var before: float = float(ns.bloc_offset.get(bloc, 0.0))
	for _i in range(ev.respond_months):
		Events.tick_month(state, stub)

	if Events.is_pending(ns):
		_fail("the register still holds an event %d months after it arrived" % ev.respond_months)
	var after: float = float(ns.bloc_offset.get(bloc, 0.0))
	if not is_equal_approx(after, before + delta):
		_fail("the default moved %s by %.4f, expected %.4f" % [bloc, after - before, delta])
	if ns.event_history.is_empty() or not bool(ns.event_history[0]["defaulted"]):
		_fail("the ledger does not record that nobody answered")
	if int(ns.event_category_quiet.get(ev.category, 0)) != K.CATEGORY_QUIET_MONTHS:
		_fail("the category quiet did not open after a default")

	# And exactly once: another tick must not charge it again.
	var third := float(ns.bloc_offset.get(bloc, 0.0))
	Events.tick_month(state, stub)
	if not is_equal_approx(float(ns.bloc_offset.get(bloc, 0.0)), third):
		_fail("the default charged a second time")


func _test_answering_applies_the_choice() -> void:
	var state = _new_state()
	var ns = state.player()
	var ev = _event(HAZARD_ONLY)
	_announce(state, ev)

	var chosen: Dictionary = {}
	for c in ev.choices:
		if not bool(c["is_default"]):
			chosen = c
			break
	var terms: Dictionary = chosen["effects"]["bloc_offset"]
	var bloc := String(terms.keys()[0])
	var before: float = float(ns.bloc_offset.get(bloc, 0.0))

	var record := Events.choose(state, _loader, String(chosen["id"]))
	if record.is_empty():
		_fail("choosing '%s' returned nothing" % chosen["id"])
		return
	if bool(record["defaulted"]):
		_fail("an answered event was recorded as a default")
	if not is_equal_approx(float(ns.bloc_offset.get(bloc, 0.0)), before + float(terms[bloc])):
		_fail("the chosen effect did not reach bloc_offset")
	if Events.is_pending(ns):
		_fail("answering did not clear the register")
	# Nothing more to answer, so a second call is inert rather than a second charge.
	if not Events.choose(state, _loader, String(chosen["id"])).is_empty():
		_fail("an event could be answered twice")


## THE DEADLINE IS THE PRESSURE AND THERE IS NO SECOND PRICE ON THE TIMING. A cost for
## answering late would need a number solved against the default's, which
## src/core/investment_action.gd refuses as one strength written twice; a cost for
## answering early would make waiting free and delete the decision.
func _test_answering_early_and_late_cost_the_same() -> void:
	var ev = _event(GATED)
	var chosen: Dictionary = {}
	for c in ev.choices:
		if not bool(c["is_default"]):
			chosen = c
			break
	var terms: Dictionary = chosen["effects"]["bloc_offset"]
	var bloc := String(terms.keys()[0])

	var early = _new_state()
	_announce(early, ev)
	Events.choose(early, _loader, String(chosen["id"]))

	var late = _new_state()
	_announce(late, ev)
	for _i in range(ev.respond_months - 1):
		Events.tick_month(late, _loader)
	Events.choose(late, _loader, String(chosen["id"]))

	if not is_equal_approx(
		float(early.player().bloc_offset.get(bloc, 0.0)),
		float(late.player().bloc_offset.get(bloc, 0.0))
	):
		_fail("answering on the last month cost a different amount from answering on the first")


## An event HAS HAPPENED the moment it is DELIVERED; the choice is the response to
## it. Marking at resolution instead would let a save reloaded mid-crisis see the
## same revelation announced twice. The mark lives in _deliver, not in announce():
## announce is the raw staging primitive the sweeps drive repeatedly, and -- the
## defect this shape fixed -- only the player branch ever called announce(), so a
## mark there never bound for the other twenty-eight nations, whose once event
## recurred and whose cooldowns never fired.
func _test_once_is_marked_at_delivery() -> void:
	var state = _new_state()
	var ns = state.player()
	var ev = _event(ONCE_ONLY)
	if not ev.once:
		_fail("'%s' is not a `once` event, so this check measures nothing" % ONCE_ONLY)
		return
	var stub := _StubLoader.new()
	stub.events = [ev]
	var month := Events._absolute_month(int(state.year), int(state.month))
	# The player leg: the mark exists once the event is in front of the player,
	# driven through the tick's own delivery door because the mark is delivery's
	# write now.
	Events._deliver(state, ns, stub, ev, month, true)
	if not ns.event_fired.has(ev.id):
		_fail("a `once` event was not marked at delivery")
	if not Events.is_pending(ns):
		_fail("the `once` event never reached the desk, so the mark is not the one in front of the player")
	# The AI leg, the finding's other half: the AI branch never touches announce(),
	# so the marks must live where every delivery passes. The desk stays empty --
	# the AI has no queue. The REAL loader, because _resolve applies the chosen
	# effects through it and a stub carries nothing for apply_effects to read.
	var ai_state = _new_state()
	var ai_ns = null
	for id in ai_state.nations.keys():
		if String(id) != PLAYER:
			ai_ns = ai_state.nations[id]
			break
	Events._deliver(ai_state, ai_ns, _loader, ev, month, false)
	if not ai_ns.event_fired.has(ev.id):
		_fail("an AI nation's delivery did not mark the `once` event -- it would recur for ever")
	if not ai_ns.event_queue.is_empty():
		_fail("an AI delivery queued an entry, and the AI has no desk")
	# And delivery writes the per-event cooldown -- the other half of the same
	# move. A fixture rather than content: the anchor must hold for ANY event,
	# content or fixture alike, and this pin is what keeps the write where every
	# delivery passes.
	var cd = _make_event("cooldown_fixture", false)
	cd.cooldown_months = 4
	var cd_state = _new_state()
	var cd_ns = cd_state.player()
	var cd_month := Events._absolute_month(int(cd_state.year), int(cd_state.month))
	Events._deliver(cd_state, cd_ns, _loader, cd, cd_month, true)
	if int(cd_ns.event_cooldowns.get(cd.id, -1)) != cd_month + 4:
		_fail("delivery did not write the per-event cooldown register")


## THE QUIET HOLDS FOR ITS OWN CATEGORY AND NOTHING ELSE. The V1.8 global quiet
## silenced the world after any resolution; V4.4 followed the slot down a level, so
## a scandal on the desk is the scandal category's whole say this month -- the other
## eight go on talking. Both halves are the pin: quieted holds, un-quieted may.
func _test_the_quiet_period_holds() -> void:
	# A likelihood-1.0 fixture on a stub loader, because the shipped book draws
	# nothing at the epoch month: a loop over the real loader asserted "nothing
	# landed" whether or not the gate existed. The control leg below is what
	# makes the quieted leg mean something -- same fixture, same month, no quiet.
	var fixture = _make_event("quiet_fixture", false)
	fixture.likelihood = 1.0
	var other = _make_event("quiet_other_category", false)
	other.likelihood = 1.0
	other.category = "fiscal"
	var stub := _StubLoader.new()
	stub.events = [fixture, other]

	var control = _new_state()
	Events.tick_month(control, stub)
	if _count_in_category(control.player(), fixture.category) == 0:
		_fail("the likelihood-1.0 fixture did not land with no quiet -- the quiet leg below proves nothing")
		return

	var state = _new_state()
	var ns = state.player()
	ns.event_category_quiet[fixture.category] = K.CATEGORY_QUIET_MONTHS
	Events.tick_month(state, stub)
	if _count_in_category(ns, fixture.category) != 0:
		_fail("an event fired inside its category's quiet period")
	if _count_in_category(ns, other.category) == 0:
		_fail("a quiet scandal category silenced a different category -- the quiet is per-category")


func _count_in_category(ns, category: String) -> int:
	var n := 0
	for entry in ns.event_queue:
		if String(entry.get("category", "")) == category:
			n += 1
	return n


## WHAT CATEGORY_QUIET_MONTHS 3 REALLY MEANS, pinned at the machine. `_tick_quiet`
## decrements BEFORE the hazard loop reads the register, so a delivery at month M
## stamps 3 and the category is blocked at M+1 (reads 2) and M+2 (reads 1) -- TWO
## blocked months after the delivery month -- then M+3 decrements to 0, erases the
## entry and the category draws again. The value reads "draws again K months
## later", not "K months of silence". NO behaviour change: E4's cadence bands were
## swept on exactly this arithmetic. Two legs: the register's own countdown, and the
## end-to-end cadence of an AI nation resolving a likelihood-1.0 fixture in place
## (an AI delivery and resolution are one tick, so the delivery months ARE the
## cadence, with no desk countdown mixed in).
func _test_the_quiet_cadence_is_delivery_month_plus_three() -> void:
	# Leg 1: the countdown on its own. 3 -> 2 -> 1 -> erased, so the third tick
	# after the stamp is the first that no longer blocks.
	var probe_state = _new_state()
	var pns = probe_state.player()
	pns.event_category_quiet["scandal"] = 3
	Events._tick_quiet(pns, 0)
	if int(pns.event_category_quiet.get("scandal", 0)) != 2:
		_fail("a delivery's quiet stamp of 3 did not read 2 after one tick -- the first month after delivery must still block")
	Events._tick_quiet(pns, 1)
	if int(pns.event_category_quiet.get("scandal", 0)) != 1:
		_fail("the quiet stamp did not read 1 after two ticks -- the second month after delivery must still block")
	Events._tick_quiet(pns, 2)
	if pns.event_category_quiet.has("scandal"):
		_fail("the quiet stamp survived three ticks -- the category must draw again three months after the delivery month")

	# Leg 2: end to end. An AI nation, a fixture that passes every draw, and the
	# months its history records the occasion: M, M+3, M+6 -- never M+1 or M+2.
	var fixture = _make_event("cadence_fixture", false)
	fixture.likelihood = 1.0
	var stub := _StubLoader.new()
	stub.events = [fixture]
	var state = _new_state()
	var ai = state.nations["DEU"]
	var delivered_at: Array[int] = []
	for offset in range(0, 7):
		var before: int = ai.event_history.size()
		state.year = START_YEAR + int(offset / 12)
		state.month = (offset % 12) + 1
		Events.tick_month(state, stub)
		if ai.event_history.size() > before:
			delivered_at.append(offset)
	var expected: Array[int] = [0, 3, 6]
	if delivered_at != expected:
		_fail("an AI nation's likelihood-1.0 fixture was delivered at month offsets %s, expected %s -- blocked M+1 and M+2, open M+3" % [delivered_at, expected])


## THE BLOCK'S HEADLINE DEFECT, PINNED. V4.4's first chooser routed an AI nation's
## event fiscal effects through Budget.commit(), which is the PLAYER's command verb
## (it reads state.player()): the other twenty-eight governments' crisis answers
## rewrote the President's tax rates and spending. The fix is the nation-scoped
## Budget.apply_pending(), called from Legislature.apply_effects(). Pinned two
## ways: the player's whole serialised nation is byte-identical -- rates, spending,
## schedule, the demand impulse and the books (there is no pending-budget register
## on the nation: the budget panel holds its edits in the UI, so the saved nation IS
## the surface) -- and, since pass 23, the AI nation's OWN budget and firm burdens
## are unmoved too. Nothing ticks the other twenty-eight governments' rates,
## spending, firm burdens or other-revenue line back toward anything, so an event
## answer written there only ratchets (measured: AI infrastructure +1.45 points of
## GDP on average, an industry burden at its clamp); an AI resolution skips the four
## fiscal/company channels and every other channel (bloc_offset here) still lands.
func _test_an_ai_fiscal_answer_never_touches_the_players_budget() -> void:
	var raw := {"id": "ai_fiscal_fixture", "name": "Ai Fiscal Fixture", "summary": "s", "likelihood": 0.05,
		"category": "fiscal", "respond_months": 2, "choices": [
			{"id": "tax", "label": "Tax", "summary": "raise income tax", "effects": {"tax_rates_pct": {"income": 1.5}, "bloc_offset": {"workers": 0.02}}, "default": true},
			{"id": "spend", "label": "Spend", "summary": "raise health", "effects": {"spending_pct_gdp": {"health": 0.4}, "bloc_offset": {"workers": 0.02}}},
			{"id": "firm", "label": "Firm", "summary": "burden industry", "effects": {"company": {"sector": "industry", "burden": 0.05}, "other_revenue_pct_gdp": -0.1, "bloc_offset": {"workers": 0.02}}},
		]}
	var errs: Array[String] = []
	var ev = GameEvent.from_dict(raw, "x.json", errs,
		EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS, EconomyK.SECTOR_TREND.keys())
	if not errs.is_empty():
		_fail("the fiscal fixture did not load: %s" % [errs])
		return
	var stub := _StubLoader.new()
	stub.events = [ev]

	for choice in ev.choices:
		var state = _new_state()
		var player = state.player()
		var ai = state.nations["DEU"]
		var player_before: String = JSON.stringify(player.to_dict(), "", true)
		var ai_tax_before: float = float(ai.tax_rates_pct["income"])
		var ai_health_before: float = float(ai.spending_pct_gdp["health"])
		var ai_burden_before: float = float(ai.regulation_burden.get("industry", 0.0))
		var ai_other_before: float = float(ai.law_other_revenue_pct_gdp)
		var ai_offset_before: float = float(ai.bloc_offset.get("workers", 0.0))
		var player_tax_before: float = float(player.tax_rates_pct["income"])
		var player_health_before: float = float(player.spending_pct_gdp["health"])
		var effects_before: String = JSON.stringify(choice["effects"], "", true)
		Events._resolve(state, ai, stub, ev, choice, false, {})
		var cid := String(choice["id"])
		# THE FILTER: none of the four skipped channels moved on the AI nation.
		if float(ai.tax_rates_pct["income"]) != ai_tax_before:
			_fail("an AI '%s' answer moved the AI nation's income rate (%.4f -> %.4f) -- AI fiscal channels only ratchet" % [cid, ai_tax_before, float(ai.tax_rates_pct["income"])])
		if float(ai.spending_pct_gdp["health"]) != ai_health_before:
			_fail("an AI '%s' answer moved the AI nation's health spending (%.4f -> %.4f)" % [cid, ai_health_before, float(ai.spending_pct_gdp["health"])])
		if float(ai.regulation_burden.get("industry", 0.0)) != ai_burden_before:
			_fail("an AI '%s' answer moved the AI nation's industry burden" % cid)
		if float(ai.law_other_revenue_pct_gdp) != ai_other_before:
			_fail("an AI '%s' answer moved the AI nation's other-revenue line" % cid)
		# And every other channel still lands: the choice is not a no-op.
		if not is_equal_approx(float(ai.bloc_offset.get("workers", 0.0)), ai_offset_before + 0.02):
			_fail("an AI '%s' answer did not land its bloc_offset (%.4f -> %.4f) -- the filter swallowed more than the fiscal channels" % [cid, ai_offset_before, float(ai.bloc_offset.get("workers", 0.0))])
		# The content is shared by all twenty-nine nations and the player's desk: the
		# filter works on a copy.
		if JSON.stringify(choice["effects"], "", true) != effects_before:
			_fail("an AI '%s' answer mutated the shared choice content -- the filter must work on a copy" % cid)
		if JSON.stringify(player.to_dict(), "", true) != player_before:
			_fail("an AI nation's '%s' answer changed the PLAYER's nation -- the fiscal effect leaked through the player-scoped commit" % cid)
		# Explicit reads beside the whole-nation comparison, so a failure names the
		# register rather than only "something differs".
		if float(player.tax_rates_pct["income"]) != player_tax_before:
			_fail("the player's income rate moved under an AI '%s' answer" % cid)
		if float(player.spending_pct_gdp["health"]) != player_health_before:
			_fail("the player's health spending moved under an AI '%s' answer" % cid)

	# THE PLAYER PATH IS UNCHANGED: the filter is for AI nations only. The same
	# fiscal choice and the firm choice resolved on the PLAYER's nation land their
	# authored amounts -- without this leg a filter widened to every nation would
	# pass every assertion above (the AI legs only ever see "did not move").
	for choice in ev.choices:
		var cid_p := String(choice["id"])
		if cid_p == "spend":
			continue
		var pstate = _new_state()
		var pns = pstate.player()
		var p_tax_before: float = float(pns.tax_rates_pct["income"])
		var p_burden_before: float = float(pns.regulation_burden.get("industry", 0.0))
		var p_other_before: float = float(pns.law_other_revenue_pct_gdp)
		Events._resolve(pstate, pns, stub, ev, choice, false, {})
		if cid_p == "tax":
			if not is_equal_approx(float(pns.tax_rates_pct["income"]), p_tax_before + 1.5):
				_fail("the PLAYER's '%s' answer did not move the income rate by the authored +1.5 (%.4f -> %.4f) -- the AI filter reached the player path" % [cid_p, p_tax_before, float(pns.tax_rates_pct["income"])])
		else:
			if not is_equal_approx(float(pns.regulation_burden.get("industry", 0.0)), p_burden_before + 0.05):
				_fail("the PLAYER's '%s' answer did not move the industry burden by the authored +0.05 -- the AI filter reached the player path" % cid_p)
			if not is_equal_approx(float(pns.law_other_revenue_pct_gdp), p_other_before - 0.1):
				_fail("the PLAYER's '%s' answer did not move the other-revenue line by the authored -0.1" % cid_p)

	# The whole path, not just _resolve: the AI's own delivery picks a choice through
	# the chooser and resolves in place. Whichever it picks, the player is untouched
	# and the AI nation's history carries the row.
	var state2 = _new_state()
	var player2 = state2.player()
	var ai2 = state2.nations["DEU"]
	var player2_before: String = JSON.stringify(player2.to_dict(), "", true)
	var rows_before: int = ai2.event_history.size()
	var ai2_tax_before: float = float(ai2.tax_rates_pct["income"])
	var ai2_health_before: float = float(ai2.spending_pct_gdp["health"])
	var ai2_offset_before: float = float(ai2.bloc_offset.get("workers", 0.0))
	Events._deliver(state2, ai2, stub, ev, Events._absolute_month(int(state2.year), int(state2.month)), false)
	if ai2.event_history.size() != rows_before + 1:
		_fail("the AI delivery did not resolve in place")
	else:
		# The AI nation's own budget did NOT move (pass 23: the fiscal and company
		# channels are skipped for AI resolutions), while the channel the filter
		# leaves alone DID land -- a delivery that logged a row but skipped
		# apply_effects altogether would otherwise pass this leg.
		var picked: String = String(ai2.event_history[ai2.event_history.size() - 1].get("choice_id", ""))
		if picked != "tax" and picked != "spend" and picked != "firm":
			_fail("the AI delivery recorded choice '%s', not one of the fixture's" % picked)
		if float(ai2.tax_rates_pct["income"]) != ai2_tax_before:
			_fail("after the AI's delivered '%s' answer its income rate moved (%.4f -> %.4f)" % [picked, ai2_tax_before, float(ai2.tax_rates_pct["income"])])
		if float(ai2.spending_pct_gdp["health"]) != ai2_health_before:
			_fail("after the AI's delivered '%s' answer its health spending moved (%.4f -> %.4f)" % [picked, ai2_health_before, float(ai2.spending_pct_gdp["health"])])
		if not is_equal_approx(float(ai2.bloc_offset.get("workers", 0.0)), ai2_offset_before + 0.02):
			_fail("after the AI's delivered '%s' answer its bloc_offset did not land" % picked)
	if JSON.stringify(player2.to_dict(), "", true) != player2_before:
		_fail("an AI nation's delivered fiscal event changed the PLAYER's nation")


# --- The surfaces ------------------------------------------------------------------

func _test_the_diary_shows_the_deadline() -> void:
	var state = _new_state()
	var ns = state.player()
	_announce(state, _event(GATED))
	var found := false
	for row in Calendar.fixed_dates(state):
		if String(row.get("kind", "")) == CalendarK.FIXED_EVENT:
			found = true
			if String(row.get("ref", "")) != _event(GATED).event_name:
				_fail("the diary row carries '%s' rather than the event's name" % row.get("ref", ""))
	if not found:
		_fail("a pending event does not appear in the diary")


## V1.6f's and V1.7c's property, held through a third addition. If a later session gives
## the calendar a preload to resolve an event's name or its choices, this turns red --
## naming a thing is cheap and knowing what it costs is not.
func _test_calendar_is_still_a_leaf() -> void:
	var src := _source("res://src/sim/calendar.gd")
	for line in src.split("\n"):
		if not line.begins_with("const ") or not line.contains("preload("):
			continue
		var target := line.get_slice("\"", 1)
		if target != "res://src/sim/calendar_constants.gd":
			_fail("src/sim/calendar.gd preloads '%s', which would stop it being a leaf" % target)


## THE OTHER TWENTY-EIGHT GET EVENTS, AND ANSWER THEM THEMSELVES. This is the pin
## V1.8 wrote as "the nine never get an event" -- docs/defence-model.md's honest
## limitation, recorded a sixth time -- and V4.4 closes it at the rule: an AI nation
## delivers and resolves in the same tick, so its QUEUE is structurally always
## empty (no desk, nothing pending), while its HISTORY is the visible trace of
## politics that happened to it. Deterministic like everything here: two identical
## states answer identically, which is the reload-safety the pure-function pins
## have always been about, one register over.
func _test_the_nine_never_get_an_event() -> void:
	var state = _new_state()
	for i in range(168):
		_tick(state, i)
	var any_answered := false
	for id in state.nations.keys():
		if id == PLAYER:
			continue
		var ns = state.nations[id]
		if not ns.event_queue.is_empty():
			_fail("%s holds a pending event -- the AI has no desk, and a queue on it is a decision nobody can make" % id)
		if not ns.event_history.is_empty():
			any_answered = true
			for record in ns.event_history:
				if bool(record.get("defaulted", false)):
					_fail("%s took a DEFAULT -- the AI always answers, so a defaulted record is a chooser that did not run" % id)
	if not any_answered:
		_fail("no AI nation answered anything in fourteen years -- the chooser ships unreachable")

	# Determinism: the same state twice answers the same way.
	var again = _new_state()
	for i in range(168):
		_tick(again, i)
	for id in state.nations.keys():
		if id == PLAYER:
			continue
		var a: Array = state.nations[id].event_history
		var b: Array = again.nations[id].event_history
		if a.size() != b.size():
			_fail("%s answered %d events on one run and %d on another -- the chooser is not deterministic" % [id, a.size(), b.size()])
			continue
		for i in range(a.size()):
			if String(a[i].get("event_id", "")) != String(b[i].get("event_id", "")) \
					or String(a[i].get("choice_id", "")) != String(b[i].get("choice_id", "")):
				_fail("%s answered '%s' with '%s' on one run and '%s' with '%s' on another" % [
					id, a[i].get("event_id", ""), a[i].get("choice_id", ""),
					b[i].get("event_id", ""), b[i].get("choice_id", ""),
				])
				break


# --- The properties ----------------------------------------------------------------

## V1.3e's *no grievance ledger* and V1.3f's `foreign_acts` check, in the session most
## likely to be tempted to build the ledger literally. The sim writes the record, the UI
## decides what it means, and no decision anywhere consults it.
func _test_history_is_never_read_back() -> void:
	var dir := DirAccess.open("res://src/sim")
	if dir == null:
		_fail("could not open src/sim")
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			var src := FileAccess.get_file_as_string("res://src/sim/%s" % f)
			for line in src.split("\n"):
				var stripped := line.strip_edges()
				if stripped.begins_with("#"):
					continue
				if not stripped.contains("event_history"):
					continue
				# events.gd writes it; nobody may read it.
				if f != "events.gd":
					_fail("src/sim/%s names event_history" % f)
				elif not (
					stripped.contains("ns.event_history.push_front")
					or stripped.contains("ns.event_history.size")
					or stripped.contains("ns.event_history.remove_at")
					or stripped.contains("ns.event_history.clear")
				):
					_fail("src/sim/events.gd reads event_history back: %s" % stripped)
		f = dir.get_next()
	dir.list_dir_end()


## src/sim/events.gd preloads src/sim/legislature.gd on purpose -- see its header -- and
## the edge must never run the other way, or the effect application has two owners.
func _test_the_dependency_runs_one_way() -> void:
	var src := _code("res://src/sim/legislature.gd")
	if src.contains("events.gd"):
		_fail("src/sim/legislature.gd names events.gd, so the dependency is a cycle")


## V1.5d cost a session to two harnesses that never called Media.tick_month(), so both
## ran the pre-session model and their agreement about a bit-identical re-run was about
## nothing. tests/test_referendum.gd made that structural for two files; four here,
## because Budget.project() and src/ui/main.gd are the two that would fail SILENTLY --
## a forecast that never counts a deadline down tells the player doing nothing is free.
func _test_every_harness_ticks_it() -> void:
	for path in [
		"res://tools/balance_probe.gd", "res://tests/test_balance.gd",
		"res://src/sim/budget.gd", "res://src/ui/main.gd",
	]:
		var src := _code(path)
		if not src.contains("Events.tick_month("):
			_fail("%s does not call Events.tick_month -- an event would never arrive or resolve there" % path)


## src/sim/cycle.gd's header justifies duplicating src/ui/poll_noise.gd's hash on a
## BOUNDARY: one of the two is a render-time device that must never touch the model.
## That argument does not transfer to a second file inside src/sim/, so this file draws
## from Cycle.unit() rather than carrying a third copy.
func _test_the_hash_is_not_copied() -> void:
	var src := _code("res://src/sim/events.gd")
	for marker in ["0x9E3779B1", "0x21F0AAAD", "2166136261", "16777619"]:
		if src.contains(marker):
			_fail("src/sim/events.gd carries its own copy of the splitmix hash (%s)" % marker)
	if not src.contains("Cycle.unit("):
		_fail("src/sim/events.gd does not draw from Cycle.unit()")


# --- V4.4: the queue, the weighted draw, the hooks, the chains ---------------------

## The desk is BOUNDED, at EVERY delivery door. A draw that does not fit is
## skipped, not banked -- next month is a fresh draw because the hazard is a
## function of the month -- and the bound is what keeps the message column's six
## cards able to hold one arrival card per entry.
func _test_the_desk_is_bounded() -> void:
	if K.QUEUE_MAX < 2:
		_fail("QUEUE_MAX is %d -- the bound check below cannot mean anything" % K.QUEUE_MAX)
	# The bound is enforced in _deliver, where ALL THREE doors pass (the
	# review's find: the chain and hook doors delivered unconditionally and
	# reached six) -- pinned at source, the leaf-property way.
	if not _code("res://src/sim/events.gd").contains(">= K.QUEUE_MAX"):
		_fail("delivery no longer gates on QUEUE_MAX -- the desk is unbounded")

	# The REAL doors, driven against a FULL desk staged with raw announces (the
	# site sweep's own way -- announce is the unbounded staging primitive by
	# design, which is exactly why the gate cannot live in it).
	var state = _new_state()
	var ns = state.player()
	var month := Events._absolute_month(int(state.year), int(state.month))
	var filler = _make_event("desk_filler", false)
	for _i in range(K.QUEUE_MAX):
		Events.announce(ns, filler, month, Events.region_names(ns, _loader))
	if ns.event_queue.size() != K.QUEUE_MAX:
		_fail("staging a full desk left %d entries, expected %d -- the staging itself is broken" % [ns.event_queue.size(), K.QUEUE_MAX])
		return

	# The chain door, through the REAL tick (the survive-and-retry lives in the
	# tick's armed loop, not in _deliver, so that is the door under test): an
	# armed entry due NOW finds the desk full and WAITS -- a consequence the
	# player paid for must not evaporate on a busy month. The stub carries only
	# the fixture, so nothing else can land and the count stays legible.
	var chain = _make_event("desk_chain_fixture", false)
	var stub := _StubLoader.new()
	stub.events = [chain]
	ns.event_armed.append({"event_id": chain.id, "due_index": month, "source_id": filler.id})
	Events._tick_nation(state, ns, stub, month, true)
	if ns.event_queue.size() > K.QUEUE_MAX:
		_fail("a chain delivery on a full desk grew the desk to %d" % ns.event_queue.size())
	if ns.event_armed.size() != 1:
		_fail("the armed chain did not survive a full-desk month -- a paid-for consequence died at the bound")
		ns.event_armed.clear()
		return

	# The hook door, fired as the hook loop fires it while the desk is STILL
	# full: a delivery returns false and lands nothing -- the skip is final
	# (the next happening re-fires the hook), the hazard door's own semantics.
	var hook = _make_event("desk_hook_fixture", false)
	hook.on_action = "law_passed"
	ns.law_ledger["probe_law"] = {"months": [month - 1]}
	# Drive the delivery door directly after staging the hook register; this is
	# not the hook loop in _tick_nation().
	if not EventHooks.fired(state, ns, stub, hook.on_action, month):
		_fail("the full-desk hook-door fixture did not fire its staged law_passed hook")
	var landed: bool = Events._deliver(state, ns, stub, hook, month, true)
	if landed:
		_fail("a hook delivery on a full desk claimed to land")
	if ns.event_queue.size() > K.QUEUE_MAX:
		_fail("a hook delivery on a full desk grew the desk past QUEUE_MAX")
	ns.law_ledger.erase("probe_law")

	# And the wait is a WAIT, not a death: a month later, with room on the desk,
	# the same chain lands and its entry is spent.
	ns.event_queue.clear()
	state.month += 1
	if int(state.month) > 12:
		state.month = 1
		state.year += 1
	Events.tick_month(state, stub)
	if not Events.is_pending(ns) or Events.pending_event_id(ns) != chain.id:
		_fail("the chain that waited out a full desk never landed once the desk had room")
	if not ns.event_armed.is_empty():
		_fail("a delivered chain left its armed entry behind")


## The same occasion twice is one occasion: a draw landing while the desk still holds
## its event adds nothing, because two entries with one id would answer twice through
## two cards -- the deadline charging double.
func _test_the_desk_does_not_double_hold() -> void:
	# Driven, not grepped: a comment-sentence pin stays green when the skip is
	# deleted and the comment survives. The fixture is delivered twice on a desk
	# with room; the second delivery must add nothing.
	var state = _new_state()
	var ns = state.player()
	var month := Events._absolute_month(int(state.year), int(state.month))
	var ev = _make_event("double_hold_fixture", false)
	var stub := _StubLoader.new()
	stub.events = [ev]
	ns.event_queue.clear()
	if not Events._deliver(state, ns, stub, ev, month, true):
		_fail("the first delivery onto an empty desk did not land")
	if not Events._deliver(state, ns, stub, ev, month, true):
		_fail("the repeat delivery of an event already on the desk returned false -- the skip reports success")
	var held := 0
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) == ev.id:
			held += 1
	if held != 1:
		_fail("the desk holds %d entries for one event -- the deadline can charge double" % held)


## An event already on the player's desk must not enter its category's draw pool: it
## could win the category's single weighted slot, be dropped at _deliver's dedupe, and
## leave a sibling that would have landed undelivered. Two same-category likelihood-1.0
## fixtures, one held on the desk; the other must land. Run in BOTH assignments because
## the weighted pick is a pure function of the pool, so whichever fixture it favours
## is the one the mutated (unskipped) pool would hand the slot to -- one of the two legs
## is the crowded-out case whatever the hash says.
func _test_a_desk_resident_does_not_crowd_out_a_sibling() -> void:
	var first = _make_event("crowd_first", false)
	first.likelihood = 1.0
	var second = _make_event("crowd_second", false)
	second.likelihood = 1.0
	var stub := _StubLoader.new()
	stub.events = [first, second]
	for pair in [[first, second], [second, first]]:
		var resident = pair[0]
		var sibling = pair[1]
		var state = _new_state()
		var ns = state.player()
		var month := Events._absolute_month(int(state.year), int(state.month))
		ns.event_queue.clear()
		Events.announce(ns, resident, month, {})
		Events.tick_month(state, stub)
		var held := {}
		for entry in ns.event_queue:
			held[String(entry.get("event_id", ""))] = true
		if not held.has(sibling.id):
			_fail("'%s' sat on the desk and crowded out its same-category sibling '%s' from the draw" % [resident.id, sibling.id])
		if not held.has(resident.id):
			_fail("the resident '%s' left the desk inside its own deadline" % resident.id)


## THE ONE-MONTH COOLDOWN FLOOR, three legs. An authored cooldown of 0 on a
## non-`once` event used to bind nothing, so the same occasion could land twice in one
## tick. Likelihood 0 on every fixture keeps the hazard door out: each leg drives the
## chain / hook door it is about and reads an observable the second delivery changes.
func _test_the_cooldown_floor_is_one_month() -> void:
	# (a) An AI nation with two armed entries for one target due the same month. The AI
	# resolves on the spot, so a second delivery would apply the choice a second time --
	# the history row count is the observable (one resolution, one row).
	var state = _new_state()
	var ai_ns = state.nations["DEU"]
	var month := Events._absolute_month(int(state.year), int(state.month))
	var target = _make_event("floor_ai_target", false)
	target.likelihood = 0.0
	if target.cooldown_months != 0 or target.once:
		_fail("the floor fixture is not a cooldown-0, non-once event -- the legs below measure nothing")
		return
	var stub := _StubLoader.new()
	stub.events = [target]
	ai_ns.event_armed.append({"event_id": target.id, "due_index": month, "source_id": "x"})
	ai_ns.event_armed.append({"event_id": target.id, "due_index": month, "source_id": "y"})
	Events.tick_month(state, stub)
	var resolutions := 0
	for row in ai_ns.event_history:
		if String(row.get("event_id", "")) == target.id:
			resolutions += 1
	if resolutions != 1:
		_fail("two armed entries for one cooldown-0 target resolved it %d times in one tick -- expected once" % resolutions)

	# (b) A player entry that DEFAULTS this tick must not come back the same tick by an
	# armed entry for its own id: the id-diff in main.gd would see it present before and
	# after and show neither the departure card nor a ledger line.
	var pstate = _new_state()
	var pns = pstate.player()
	var pmonth := Events._absolute_month(int(pstate.year), int(pstate.month))
	var ev = _make_event("floor_player_event", false)
	ev.likelihood = 0.0
	var pstub := _StubLoader.new()
	pstub.events = [ev]
	pns.event_queue.clear()
	Events.announce(pns, ev, pmonth, {})
	_entry(pns, ev.id)["months_left"] = 1
	pns.event_armed.append({"event_id": ev.id, "due_index": pmonth, "source_id": "x"})
	Events.tick_month(pstate, pstub)
	var defaulted := 0
	for row in pns.event_history:
		if String(row.get("event_id", "")) == ev.id and bool(row.get("defaulted", false)):
			defaulted += 1
	if defaulted != 1:
		_fail("the expiring entry left %d defaulted ledger rows -- the leg did not stage an expiry" % defaulted)
	if not _entry(pns, ev.id).is_empty():
		_fail("an entry that defaulted this tick was re-delivered by its own armed entry in the same tick")

	# (c) The delivery stamp itself: a cooldown-0 delivery writes month + 1, not nothing.
	var dstate = _new_state()
	var dns = dstate.player()
	var dmonth := Events._absolute_month(int(dstate.year), int(dstate.month))
	dns.event_queue.clear()
	dns.event_cooldowns.clear()
	if not Events._deliver(dstate, dns, pstub, ev, dmonth, true):
		_fail("the floor fixture did not deliver onto an empty desk")
	elif int(dns.event_cooldowns.get(ev.id, -1)) != dmonth + 1:
		_fail("a cooldown-0 delivery stamped %s, expected %d (the one-month floor)" % [dns.event_cooldowns.get(ev.id, "nothing"), dmonth + 1])


## A CHAIN MAY ARM A HOOK EVENT (the loader's refusal of the shape went at pass 18).
## An AI nation with an armed entry for a hook-event target, due the very month that
## target's hook fires, resolves it ONCE: the chain door delivers first and the
## one-month cooldown floor keeps the hook door off it. On this AI path the floor is
## written TWICE -- _deliver stamps it, then the in-tick _resolve raises it again to
## the same month + 1 -- so this test goes red only when BOTH are removed, not when
## either alone is. The AI resolves on the spot, so a second delivery would
## apply the choice twice -- the history row count is the observable. The control run
## (no armed entry) proves the hook really does deliver this fixture, so "once" is
## not "never".
func _test_a_chain_may_arm_a_hook_event() -> void:
	var target = _make_event("chain_hook_target", false)
	target.on_action = "law_passed"
	target.likelihood = 1.0
	if target.cooldown_months != 0 or target.once:
		_fail("the chain/hook fixture is not a cooldown-0, non-once event -- the legs below measure nothing")
		return
	var stub := _StubLoader.new()
	stub.events = [target]

	var control = _new_state()
	var control_ns = control.nations["DEU"]
	var cmonth := Events._absolute_month(int(control.year), int(control.month))
	control_ns.law_ledger["probe_law"] = {"months": [cmonth - 1]}
	Events.tick_month(control, stub)
	if _history_rows(control_ns, target.id) != 1:
		_fail("the hook alone delivered the fixture %d times -- the control premise failed" % _history_rows(control_ns, target.id))

	var state = _new_state()
	var ai_ns = state.nations["DEU"]
	var month := Events._absolute_month(int(state.year), int(state.month))
	ai_ns.law_ledger["probe_law"] = {"months": [month - 1]}
	ai_ns.event_armed.append({"event_id": target.id, "due_index": month, "source_id": "x"})
	Events.tick_month(state, stub)
	var rows := _history_rows(ai_ns, target.id)
	if rows != 1:
		_fail("a chain-armed hook event resolved %d times in the tick its hook fired -- expected once" % rows)
	if not ai_ns.event_armed.is_empty():
		_fail("the armed entry survived its own delivery")


## A CHAIN DELIVERS REGARDLESS OF THE TARGET'S PRECONDITIONS (the author's decision:
## the arming is the occasion, preconditions gate the hazard and hook doors). The armed
## door keeps the target's existence, its `once` mark and its cooldown. The fixture's
## gate is provably closed (deficit >= 1000 % of GDP), asserted first so a fixture that
## quietly opened could not make the legs below vacuous. Player leg: the entry lands on
## the desk at its due month and the armed entry is spent. AI leg: it resolves once.
## `once` leg: a once-fired target still kills the chain, nothing delivered.
func _test_a_chain_ignores_the_targets_preconditions() -> void:
	var target = _make_event("chain_gated_target", false)
	target.likelihood = 0.0
	target.preconditions = [{"field": "deficit_pct_gdp", "op": ">=", "value": 1000.0}]
	var stub := _StubLoader.new()
	stub.events = [target]

	var state = _new_state()
	var ns = state.player()
	if Legislature.preconditions_met(ns, target.preconditions):
		_fail("the gated-chain fixture's precondition is open -- the legs below measure nothing")
		return
	var month := Events._absolute_month(int(state.year), int(state.month))
	ns.event_queue.clear()
	ns.event_armed.append({"event_id": target.id, "due_index": month, "source_id": "x"})
	Events.tick_month(state, stub)
	if Events.pending_event_id(ns) != target.id:
		_fail("a chain whose target's precondition fails was not delivered at its due month (desk holds '%s')" % Events.pending_event_id(ns))
	if not ns.event_armed.is_empty():
		_fail("the delivered gated chain left its armed entry behind")

	var astate = _new_state()
	var ai_ns = astate.nations["DEU"]
	var amonth := Events._absolute_month(int(astate.year), int(astate.month))
	if Legislature.preconditions_met(ai_ns, target.preconditions):
		_fail("the AI nation's gate is open -- the AI leg measures nothing")
		return
	ai_ns.event_armed.append({"event_id": target.id, "due_index": amonth, "source_id": "x"})
	Events.tick_month(astate, stub)
	if _history_rows(ai_ns, target.id) != 1:
		_fail("an AI nation resolved a gated chain %d times, expected once" % _history_rows(ai_ns, target.id))

	var ostate = _new_state()
	var ons = ostate.player()
	var once_target = _make_event("chain_once_target", false)
	once_target.likelihood = 0.0
	once_target.once = true
	var ostub := _StubLoader.new()
	ostub.events = [once_target]
	var omonth := Events._absolute_month(int(ostate.year), int(ostate.month))
	ons.event_queue.clear()
	ons.event_fired[once_target.id] = true
	ons.event_armed.append({"event_id": once_target.id, "due_index": omonth, "source_id": "x"})
	Events.tick_month(ostate, ostub)
	if Events.is_pending(ons):
		_fail("a once-fired target was delivered by its chain -- the once mark must still kill it")
	if not ons.event_armed.is_empty():
		_fail("the chain onto a once-fired target survived -- it should die at the door")


func _history_rows(ns, event_id: String) -> int:
	var rows := 0
	for row in ns.event_history:
		if String(row.get("event_id", "")) == event_id:
			rows += 1
	return rows


## A hook event already on the player's desk must not take the hook loop's one slot per
## happening: it would pass its draw, hit _deliver's dedupe (true) and break, and a
## sibling on the same happening would never draw. Resident first in book order, which
## is the order that crowds.
func _test_a_desk_resident_does_not_crowd_out_a_hook_sibling() -> void:
	var resident = _make_event("hook_resident", false)
	resident.on_action = "law_passed"
	resident.likelihood = 1.0
	var sibling = _make_event("hook_sibling", false)
	sibling.on_action = "law_passed"
	sibling.likelihood = 1.0
	var stub := _StubLoader.new()
	stub.events = [resident, sibling]
	var state = _new_state()
	var ns = state.player()
	var month := Events._absolute_month(int(state.year), int(state.month))
	ns.law_ledger["probe_law"] = {"months": [month - 1]}
	ns.event_queue.clear()
	Events.announce(ns, resident, month, {})
	Events.tick_month(state, stub)
	if _entry(ns, sibling.id).is_empty():
		_fail("a hook event on the desk took the happening's one slot and crowded out its sibling")
	if _entry(ns, resident.id).is_empty():
		_fail("the resident hook event left the desk inside its own deadline")


## The weighted pick inside a pulsing category is a pure function of (nation,
## category, month) against the cumulative authored weights -- the hazard's own
## discipline, one draw over. Same inputs, same winner; and the weights actually
## weight: a 25:1 pair splits its winners, not 50:50.
func _test_the_weighted_pick_is_pure_and_weighted() -> void:
	var high = _make_event("weight_high", false)
	var low = _make_event("weight_low", false)
	high.weight = K.WEIGHT_MAX
	low.weight = K.WEIGHT_MIN
	var fired: Array = [high, low]
	var month := Events._absolute_month(2029, 3)
	var a = Events._weighted_pick(_new_state().player(), fired, month)
	var b = Events._weighted_pick(_new_state().player(), fired, month)
	if a != b:
		_fail("the weighted pick gave two answers for one (nation, category, month)")
	var wins := {"high": 0, "low": 0}
	var ns = _new_state().player()
	for m in range(month, month + 240):
		var winner = Events._weighted_pick(ns, fired, m)
		if winner == high:
			wins["high"] += 1
		else:
			wins["low"] += 1
	if wins["high"] < 200 or wins["low"] < 1:
		_fail("a 25:1 weight split gave %d:%d over 240 draws -- the weights do not weight" % [wins["high"], wins["low"]])


## THE HOOKS FIRE BECAUSE SOMETHING HAPPENED. Each emitter is proven by staging the
## register its machine writes and asserting the hook sees it -- which is also the
## proof the vocabulary has no name without a branch (a hook that never fires is a
## content promise the machine does not keep).
func _test_hooks_fire_on_staged_registers() -> void:
	var state = _new_state()
	var ns = state.player()
	var month := Events._absolute_month(int(state.year), int(state.month))

	# law_passed is a PURE ONE-MONTH LAG, pinned BOTH directions in one wave:
	# the ledger stamps at APPLY time and the player's routes apply at command
	# time (month M), which this machine first reads at M+1 -- so last month's
	# passage is the readable window and THIS month's is not (yet).
	ns.law_ledger["probe_law"] = {"months": [month - 1]}
	if not EventHooks.fired(state, ns, _loader, "law_passed", month):
		_fail("law_passed did not read last month's passage -- the lag is the emitter's whole window")
	ns.law_ledger["probe_law"] = {"months": [month]}
	if EventHooks.fired(state, ns, _loader, "law_passed", month):
		_fail("law_passed fired on the command month itself -- with the lag leg that would double-fire an in-tick passage")
	ns.law_ledger.erase("probe_law")

	# law_repealed carries law_passed's lag, pinned BOTH directions the same way:
	# the stamp lands at APPLY time and the player's Propose/Force repeals at
	# command time, so last month's stamp is the readable window and THIS month's
	# is not.
	ns.repealed_at["some_law"] = month - 1
	if not EventHooks.fired(state, ns, _loader, "law_repealed", month):
		_fail("law_repealed did not read last month's repeal stamp -- the lag is the emitter's whole window")
	ns.repealed_at["some_law"] = month
	if EventHooks.fired(state, ns, _loader, "law_repealed", month):
		_fail("law_repealed fired on the command month itself -- with the lag leg that would double-fire an in-tick repeal")
	ns.repealed_at.clear()

	ns.last_resignation = {"portfolio": "health", "party_id": "x", "year": int(state.year), "month": int(state.month) - 1}
	if not EventHooks.fired(state, ns, _loader, "minister_resigned", month):
		_fail("minister_resigned did not read last month's resignation stamp")
	ns.last_resignation = {}

	ns.last_accession = {"org": "eu", "month_index": month}
	if not EventHooks.fired(state, ns, _loader, "accession_won", month):
		_fail("accession_won did not read the accession stamp")
	# The stamp is written for every org; the hook is the UNION's. NATO joining the
	# same month must not fire it (and burn eu_accession_bills' `once` mark).
	ns.last_accession = {"org": "nato", "month_index": month}
	if EventHooks.fired(state, ns, _loader, "accession_won", month):
		_fail("accession_won fired for a NATO accession -- the hook is the Union's")
	ns.last_accession = {}

	# member_bill_passed reads its own stamp, pinned BOTH directions: M fires,
	# M-1 (last month's passage) does not, and the default -1 does not.
	if EventHooks.fired(state, ns, _loader, "member_bill_passed", month):
		_fail("member_bill_passed fired with no assembly bill ever passed (default -1)")
	ns.assembly_bill_passed_month = month
	if not EventHooks.fired(state, ns, _loader, "member_bill_passed", month):
		_fail("member_bill_passed did not read the assembly_bill_passed_month stamp")
	ns.assembly_bill_passed_month = month - 1
	if EventHooks.fired(state, ns, _loader, "member_bill_passed", month):
		_fail("member_bill_passed fired on a stamp from last month -- the hook is a month read")
	# The pass-17 finding: a later division the same month (a private member's
	# bill that FAILS) overwrites last_law_result, and used to erase a held bill's
	# release with it. The stamp is independent of that register.
	ns.assembly_bill_passed_month = month
	ns.last_law_result = {"assembly_bill": true, "assembly_division_month": month, "passed": false}
	if not EventHooks.fired(state, ns, _loader, "member_bill_passed", month):
		_fail("a failed same-month division in last_law_result cancelled the passed-bill stamp")
	# And the inverse: a passed-looking last_law_result with no stamp fires nothing.
	ns.assembly_bill_passed_month = -1
	ns.last_law_result = {"assembly_bill": true, "assembly_division_month": month, "passed": true}
	if EventHooks.fired(state, ns, _loader, "member_bill_passed", month):
		_fail("member_bill_passed read last_law_result instead of its own stamp")
	ns.last_law_result = {}

	# And a stale stamp fires nothing: the emitters are month reads, not edges.
	ns.repealed_at["some_law"] = month - 3
	if EventHooks.fired(state, ns, _loader, "law_repealed", month):
		_fail("law_repealed fired on a three-month-old stamp -- the emitters are month reads, not memories")

	# The three register-backed hooks that need external machinery were omitted
	# from the first sweep. A real commodity good makes the price resolver live.
	var good: Dictionary = _loader.commodity_goods.get("iron_ore", {})
	if good.is_empty() or float(good.get("base_price", 0.0)) <= 0.0:
		_fail("hook staging needs loader commodity iron_ore with positive base_price")
		return
	var fake_company: Dictionary = {}
	ns.companies["fake_firm"] = fake_company
	fake_company["bid_month"] = month
	if not EventHooks.fired(state, ns, _loader, "takeover_bid", month):
		_fail("takeover_bid did not read a bid_month == month")
	fake_company["bid_month"] = month - 1
	if EventHooks.fired(state, ns, _loader, "takeover_bid", month):
		_fail("takeover_bid fired on a stale month's bid")
	fake_company.erase("bid_month")
	fake_company["failed_month"] = month
	if not EventHooks.fired(state, ns, _loader, "firm_failed", month):
		_fail("firm_failed did not read a failed_month == month")
	fake_company["failed_month"] = month - 1
	if EventHooks.fired(state, ns, _loader, "firm_failed", month):
		_fail("firm_failed fired on a stale month's failure")
	ns.companies.erase("fake_firm")

	# commodity_price_high is an EDGE: it reads the crossing stamp Commodities writes
	# (ns.commodity_high_month), pinned both directions like member_bill_passed --
	# M fires, M-1 does not, the default -1 does not. A price vector sitting high
	# with no crossing this month fires nothing (the level read this replaced fired
	# on exactly that, almost every month).
	if EventHooks.fired(state, ns, _loader, "commodity_price_high", month):
		_fail("commodity_price_high fired with no crossing ever stamped (default -1)")
	ns.commodity_high_month = month
	if not EventHooks.fired(state, ns, _loader, "commodity_price_high", month):
		_fail("commodity_price_high did not read the commodity_high_month stamp")
	ns.commodity_high_month = month - 1
	if EventHooks.fired(state, ns, _loader, "commodity_price_high", month):
		_fail("commodity_price_high fired on last month's crossing -- the hook is an edge, a month read")
	var base_price: float = float(good.get("base_price", 0.0))
	ns.commodity_high_month = -1
	ns.commodity_state = {"price": {"iron_ore": base_price * 1.75}}
	if EventHooks.fired(state, ns, _loader, "commodity_price_high", month):
		_fail("commodity_price_high fired on a price vector at its clamp with no crossing stamp -- a level read")
	ns.commodity_state = {}


## A choice that ARMS a follow-up schedules it: due at its delay, ahead of the
## calendar's draws, past the armed door's three checks (target exists, `once`,
## cooldown; not its preconditions). The chain is the machine V4.1 refused, built
## once, here.
func _test_chains_arm_and_land() -> void:
	var state = _new_state()
	var ns = state.player()
	var source = _event("procurement_scandal")
	var target = _event("emergency_budget_demand")
	# The chain door ignores the target's preconditions (see
	# _test_a_chain_ignores_the_targets_preconditions); the gate is staged open
	# anyway (the chooser test's staging) so this test still reads the shipped
	# target in its own authored situation.
	ns.deficit_pct_gdp = 6.0
	var chosen: Dictionary = {}
	# The choice lives in the SHARED loader's book: the mutation is undone on EVERY
	# exit path below, or each later test in this file runs on content the shipped
	# book does not have (an `arms` key the real procurement_scandal never carried).
	var had_arms := false
	var old_arms: Variant = null
	for c in source.choices:
		if not bool(c["is_default"]):
			had_arms = c.has("arms")
			old_arms = c.get("arms")
			c["arms"] = {"event_id": target.id, "delay_months": 2}
			chosen = c
			break
	_announce(state, source)
	Events.answer(state, _loader, source.id, String(chosen.get("id", "")))
	if had_arms:
		chosen["arms"] = old_arms
	else:
		chosen.erase("arms")
	if ns.event_armed.size() != 1:
		_fail("answering an arming choice left %d armed chains, expected 1" % ns.event_armed.size())
		return
	if String(ns.event_armed[0].get("event_id", "")) != target.id:
		_fail("the armed chain points at '%s', not the authored target" % ns.event_armed[0].get("event_id", ""))
	var stub := _StubLoader.new()
	stub.events = [target]
	# The armed entry is due at an ABSOLUTE month, and tick_month reads the calendar
	# without advancing it -- V1.8's countdown idiom (two ticks, same month) would
	# never reach the due month, so the clock moves here, _tick()'s way.
	for _i in range(2):
		state.month += 1
		if int(state.month) > 12:
			state.month = 1
			state.year += 1
		Events.tick_month(state, stub)
	if not Events.is_pending(ns):
		_fail("the armed follow-up never landed at its delay")
	elif Events.pending_event_id(ns) != target.id:
		_fail("the desk holds '%s' -- the armed follow-up landed something else" % Events.pending_event_id(ns))


## An event's own cooldown binds: the register holds an UNTIL month, sparse, and
## nothing draws the event before it.
func _test_the_per_event_cooldown_binds() -> void:
	var state = _new_state()
	var ns = state.player()
	var ev = _event("procurement_scandal")
	var month := Events._absolute_month(int(state.year), int(state.month))
	ns.event_cooldowns[ev.id] = month + 5
	if Events._cooldown_ok(ns, ev, month + 4):
		_fail("a cooling event passed its own cooldown gate")
	if not Events._cooldown_ok(ns, ev, month + 5):
		_fail("the cooldown gated the month it releases -- an until-month is inclusive")


## THE AI CHOOSER SITUATES. Two positions answer the same event differently -- that
## is the whole claim the E7 probe will sweep, pinned here at the unit: a
## deficit-running government weighs the balance, a balanced one does not. Not
## optimality: difference.
func _test_the_chooser_situates() -> void:
	var ev = _event("emergency_budget_demand")
	var state = _new_state()
	var ns = state.player()
	ns.deficit_pct_gdp = 0.5
	var balanced = EventChooser.choose(ns, ev)
	ns.deficit_pct_gdp = 6.0
	var indebted = EventChooser.choose(ns, ev)
	if balanced.is_empty() or indebted.is_empty():
		_fail("the chooser returned no choice at all")
		return
	var ids := []
	for c in ev.choices:
		ids.append(String(c["id"]))
	if not ids.has(String(balanced.get("id", ""))) or not ids.has(String(indebted.get("id", ""))):
		_fail("the chooser invented a choice not on the event")
	if String(balanced.get("id", "")) == String(indebted.get("id", "")):
		_fail("a balanced and a deficit-running government answered '%s' identically -- the chooser does not situate" % String(balanced.get("id", "")))


## THE VOCABULARY SWEEP THE COMMENTS PROMISE. `ON_ACTIONS` is a closed vocabulary
## and `EventHooks.fired`'s match is its machine, and the two must name exactly the
## same set -- in BOTH directions, the house rule: a vocabulary name without a
## match arm is a content promise the machine silently never keeps (an event
## could load on it and fire nothing, forever), and a match arm outside the
## vocabulary is a live emitter no event can legally name (the loader would
## refuse the content, so the branch is dead code wearing a contract's clothes).
## Read at source, `_test_the_hash_is_not_copied`'s way: running the hooks can
## only witness the arms that fire THIS month, never the one that went missing.
func _test_the_hook_vocabulary_is_swept() -> void:
	var arms := {}
	var in_fn := false
	for line in _source("res://src/sim/event_hooks.gd").split(NEWLINE):
		if line.begins_with("static func fired"):
			in_fn = true
			continue
		if not in_fn:
			continue
		if line.begins_with("func ") or (line.begins_with("static func ") and not line.begins_with("static func fired")):
			break
		var stripped := line.strip_edges()
		if stripped.begins_with("\"") and stripped.ends_with("\":"):
			arms[stripped.substr(1, stripped.length() - 3)] = true
	if arms.is_empty():
		_fail("could not extract any match arm from EventHooks.fired -- the extraction is broken, not the machine")
		return
	for hook in K.ON_ACTIONS:
		if not arms.has(hook):
			_fail("ON_ACTIONS names '%s' and EventHooks.fired has no branch for it -- a hook that can load and never fire" % hook)
	for hook in arms.keys():
		if not K.ON_ACTIONS.has(hook):
			_fail("EventHooks.fired matches '%s', which is not in ON_ACTIONS -- a live emitter no event may name" % hook)
