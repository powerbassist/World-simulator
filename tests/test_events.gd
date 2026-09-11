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
##   - THE NINE NEVER GET AN EVENT. There is no AI chooser -- docs/defence-model.md's
##     honest limitation, recorded a sixth time and pinned rather than described;
##   - src/sim/calendar.gd IS STILL A LEAF after gaining an event row.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const GameEvent = preload("res://src/core/event.gd")
const Events = preload("res://src/sim/events.gd")
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

## The two climate events' ids. V3.5f: data/events/climate.json carries BOTH now, so
## the sweep below runs the LOADER's events -- a lost `"sited": true`, a renamed id or
## a missing file fails there as missing content instead of passing on fixtures. The
## schema tests above still build their own through _make_event(), because a schema
## test needs an event no content edit can move.
const SITED_A := "river_flood"
const SITED_B := "heat_wave"

const NEWLINE := "\n"

var _failures: Array[String] = []
var _loader


## The one piece of the real loader `choose()` reads: the event list. A fixture is
## not content, so the record test hands this in rather than shipping test events
## in data/events/.
class _StubLoader:
	var events: Array = []


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
	_test_once_is_marked_at_announcement()
	_test_the_quiet_period_holds()
	_test_the_diary_shows_the_deadline()
	_test_calendar_is_still_a_leaf()
	_test_the_nine_never_get_an_event()
	_test_history_is_never_read_back()
	_test_the_dependency_runs_one_way()
	_test_every_harness_ticks_it()
	_test_the_hash_is_not_copied()
	_test_the_interrupt_flag()
	_test_sited_schema_loads()
	_test_the_site_draw_is_pure()
	_test_sited_register_carries_place()
	_test_a_non_sited_register_gains_no_keys()
	_test_the_climate_content()
	_test_every_nation_can_be_sited()
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
	var raw := {"id": "x", "name": "X", "summary": "s", "likelihood": 0.05,
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
	if ns.event_pending.get("interrupt", "MISSING") != true:
		_fail("announce did not copy the interrupt flag into the pending register")
	# and a non-flag event's register reads false, not missing.
	var ev3 = GameEvent.from_dict(raw.duplicate(true), "x.json", errs2,
		EconomyK.TAX_KEYS, EconomyK.SPENDING_KEYS, OpinionK.BLOC_KEYS, EconomyK.SECTOR_TREND.keys())
	_announce(state, ev3)
	if bool(ns.event_pending.get("interrupt", false)):
		_fail("a non-interrupt event's pending register claims the flag")

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
		elif in_fn and line.contains("interrupt") and line.contains("get("):
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

	var drawn := String(ns.event_pending.get("region_id", ""))
	var named := String(ns.event_pending.get("region_name", ""))
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
	# And the keys gained are exactly the two: the old register's shape is untouched.
	for key in ns.event_pending.keys():
		if key != "event_id" and key != "event_name" and key != "months_left" \
				and key != "interrupt" and key != "region_id" and key != "region_name":
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
		if ns.event_pending.has(key):
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
				var drawn := String(ns.event_pending.get("region_id", ""))
				var named := String(ns.event_pending.get("region_name", ""))
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


## A fixture built through the real from_dict, so a schema refusal fails here rather
## than in the content that will one day carry the key.
func _make_event(id: String, sited: bool):
	var raw := {"id": id, "name": id.capitalize(), "summary": "s", "likelihood": 0.05,
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
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "respond_months": 2,
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
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "respond_months": 2,
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
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "respond_months": 2,
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
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "respond_months": 2,
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
		"id": "x", "name": "X", "summary": "s", "likelihood": 0.05, "respond_months": 2,
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
		if not ns.event_pending.is_empty():
			_fail("%s starts with an event pending" % id)
		if not ns.event_fired.is_empty():
			_fail("%s starts with a fired event" % id)
		if int(ns.event_quiet_months) != 0:
			_fail("%s starts inside a quiet period" % id)
		if not ns.event_history.is_empty():
			_fail("%s starts with a history" % id)


## One at a time. The register IS the rule -- there is no constant bounding concurrency,
## because one is not a bound, it is what "the matter on your desk" means.
func _test_one_pending_slot() -> void:
	var state = _new_state()
	var ns = state.player()
	_announce(state, _event(HAZARD_ONLY))
	_announce(state, _event(GATED))
	if Events.pending_event_id(ns) != GATED:
		_fail("announcing twice did not replace the slot")
	if typeof(ns.event_pending) != TYPE_DICTIONARY:
		_fail("the pending register is not a single entry")


## The deadline's whole point. Counted down, applied once at zero, register cleared, and
## the quiet period opened -- so nothing else lands the same month.
func _test_the_default_applies_exactly_once() -> void:
	var state = _new_state()
	var ns = state.player()
	var ev = _event(HAZARD_ONLY)
	var default_choice: Dictionary = ev.default_choice()
	var bloc := String((default_choice["effects"]["bloc_offset"] as Dictionary).keys()[0])
	var delta: float = float(default_choice["effects"]["bloc_offset"][bloc])

	_announce(state, ev)
	var before: float = float(ns.bloc_offset.get(bloc, 0.0))
	for _i in range(ev.respond_months):
		Events.tick_month(state, _loader)

	if Events.is_pending(ns):
		_fail("the register still holds an event %d months after it arrived" % ev.respond_months)
	var after: float = float(ns.bloc_offset.get(bloc, 0.0))
	if not is_equal_approx(after, before + delta):
		_fail("the default moved %s by %.4f, expected %.4f" % [bloc, after - before, delta])
	if ns.event_history.is_empty() or not bool(ns.event_history[0]["defaulted"]):
		_fail("the ledger does not record that nobody answered")
	if int(ns.event_quiet_months) != K.EVENT_COOLDOWN_MONTHS:
		_fail("the quiet period did not open after a default")

	# And exactly once: another tick must not charge it again.
	var third := float(ns.bloc_offset.get(bloc, 0.0))
	Events.tick_month(state, _loader)
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


## An event HAS HAPPENED the moment it is announced; the choice is the response to it.
## Marking at resolution instead would let a save reloaded mid-crisis see the same
## revelation announced twice.
func _test_once_is_marked_at_announcement() -> void:
	var state = _new_state()
	var ns = state.player()
	var ev = _event(ONCE_ONLY)
	if not ev.once:
		_fail("'%s' is not a `once` event, so this check measures nothing" % ONCE_ONLY)
		return
	_announce(state, ev)
	if not ns.event_fired.has(ev.id):
		_fail("a `once` event was not marked at announcement")


func _test_the_quiet_period_holds() -> void:
	var state = _new_state()
	var ns = state.player()
	ns.event_quiet_months = K.EVENT_COOLDOWN_MONTHS
	for _i in range(K.EVENT_COOLDOWN_MONTHS - 1):
		Events.tick_month(state, _loader)
		if Events.is_pending(ns):
			_fail("an event fired inside the quiet period")
			return


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


func _test_the_nine_never_get_an_event() -> void:
	var state = _new_state()
	for i in range(168):
		_tick(state, i)
	for id in state.nations.keys():
		if id == PLAYER:
			continue
		var ns = state.nations[id]
		if not ns.event_pending.is_empty() or not ns.event_history.is_empty():
			_fail("%s received an event, and nothing in this game can answer for it" % id)


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
