extends SceneTree

## V4.1. The government's programme: an agenda register the player chooses at term
## start, ticks once a month against three conclusions (complete / fail / invalid),
## and prices through a unit pulse into a bounded stock. Model:
## docs/programme-model.md. The register machine is a LEAF: it preloads its own
## constants and the ONE applier, and nothing else -- most of the assertions below
## are about what does NOT happen:
##
##   - progress is DERIVED from the live figure, never stored -- the register carries
##     six decision keys and no content, so a save round-trips the choice and never
##     the ladder;
##   - an `invalid` conclusion concludes the entry and moves NOTHING (zero pulse,
##     model section 2: the outcome was outside the player's agency);
##   - the pulse is a unit STEP, not a standing rate: next month it reads zero again;
##   - the nine never choose -- nothing outside this file names Programme.choose;
##   - and no surface hand-writes a list of entry ids, the seventh-hand-written-list
##     rule pointed at the new content.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Programme = preload("res://src/sim/programme.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const LawK = preload("res://src/core/law.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const EconK = preload("res://src/sim/economy_constants.gd")
const OpiK = preload("res://src/sim/opinion_constants.gd")

const PLAYER := "FRA"
## The entry each test drives, by what it exists to prove rather than by theme:
## one that completes on a live read, one that dies by the clock, one the world
## can invalidate, and one whose `possible` gate is shut at new game.
const COMPLETE_ENTRY := "prog_jobs_first"
const TIMEOUT_ENTRY := "prog_maastricht_letter"
const INVALID_ENTRY := "prog_industrial_renewal"
const GATED_ENTRY := "prog_office_honour"
## V5.2a: a no-deadline entry with an authored on_fail, so the term-end verdict's
## price is visible in bloc_offset.
const NO_DEADLINE_ENTRY := "prog_in_the_black"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_content_loads()
	_test_the_register_sweep()
	_test_the_loader_refuses_malformed_entries()
	_test_pulses_are_fixed_authored_constants()
	_test_register_seeds_empty_and_available_at_term_start()
	_test_choose_outside_term_start_refuses()
	_test_choose_twice_refuses()
	_test_an_already_failed_entry_is_not_offered()
	_test_an_already_won_entry_stays_offered()
	_test_progress_is_derived()
	_test_a_met_complete_trigger_concludes_complete()
	_test_timeout_concludes_fail()
	_test_no_deadline_is_judged_at_the_term_end()
	_test_no_deadline_met_at_the_term_end_completes()
	_test_the_term_end_needs_a_clock()
	_test_the_term_end_leaves_a_deadline_entry_alone()
	_test_an_invalid_trigger_concludes_silent()
	_test_the_register_carries_no_content()
	_test_the_register_round_trips_through_json()
	_test_preloads_are_a_short_list()
	_test_trigger_reads_delegate_to_the_laws_reader()
	_test_the_nine_never_choose()
	_test_no_hand_written_entry_list()

	_finish()


# --- Content --------------------------------------------------------------------------

func _test_content_loads() -> void:
	if _loader.programme.is_empty():
		_fail("data/programme/ loaded no entries")
		return
	var seen := {}
	for entry in _loader.programme:
		var id := String(entry["id"])
		if seen.has(id):
			_fail("programme entry '%s' is defined twice" % id)
		seen[id] = true
		if not ProgrammeK.GROUPS.has(String(entry.get("group", ""))):
			_fail("%s carries group '%s', which is not one of the five" % [id, entry.get("group", "")])
		if not ProgrammeK.ACTIVATIONS.has(String(entry.get("activation", ""))):
			_fail("%s carries activation '%s', which is not one of the four" % [id, entry.get("activation", "")])
		if not ProgrammeK.PROGRESS_DIRECTIONS.has(String(entry.get("progressbar", ""))):
			_fail("%s carries progressbar '%s', which is not a direction" % [id, entry.get("progressbar", "")])
		if int(entry.get("timeout_months", -1)) < 0:
			_fail("%s carries a negative timeout" % id)
		# An entry that could never conclude would tick forever.
		var can_conclude: bool = entry.has("complete") or entry.has("fail") \
			or entry.has("invalid") or int(entry.get("timeout_months", 0)) > 0
		if not can_conclude:
			_fail("%s has no trigger and no deadline -- it could never conclude" % id)


## Task 5's register sweep, over EVERY entry in data/programme/: each one lands
## in one of the five groups, carries an authored weight, can conclude through a
## trigger or the clock, re-validates every effect slot through the ONE extractor
## the loader uses, and derives its progress read from a live state. The
## triviality half is asserted against TWO states -- new game and one ticked
## month -- and only for entries whose `possible` gate is open there: an entry
## behind a shut gate is not yet a promise, which is the whole point of the gate.
## A goal already won (or already lost) at the offer is not a programme -- and
## not only for the nation in the chair: for banded entries the offer arm below
## walks EVERY roster nation's start state, because the co2e entries shipped a
## `possible` band that contained their own `fail` line and five nations the
## band admitted (BGR, CYP, GRC, HRV, ITA) were offered a conclusion on tick
## one while the sweep sat in France's chair. The ungated half of the same
## class -- an entry offered to a playable nation whose start already meets the
## complete line (Germany at 3.4 unemployment under a below-seven jobs goal)
## or has already crossed the fail one (Poland at 8.8 against an eight-per-cent
## deficit fail) -- is the PLAYABLE arm: the invariant is a suite gate for the
## four chairs a player can sit in, at both states, and the bands it demanded
## were authored into the book in the same commit as this arm.
func _test_the_register_sweep() -> void:
	if _loader.programme.size() < 30 or _loader.programme.size() > 40:
		_fail("the register holds %d entries; the tier asked for 30-40" % _loader.programme.size())
	var by_group := {}
	for g in ProgrammeK.GROUPS:
		by_group[g] = 0
	var fresh = _new_state()
	var ticked = _new_state()
	# new_game leaves the clock at month 0 and the CYCLE is month-indexed, so an
	# untimed tick reads a world that never exists (growth 1.98 against the real
	# month's 1.34). The ticked arm is month 1 of the standard start.
	ticked.month = 1
	ticked.year = 2026
	Economy.tick_month(ticked)
	Budget.tick_month(ticked)
	Opinion.tick_month(ticked)
	for entry in _loader.programme:
		var id := String(entry["id"])
		by_group[String(entry["group"])] += 1
		if not (entry.has("complete") or entry.has("fail") or entry.has("invalid")
				or int(entry.get("timeout_months", 0)) > 0):
			_fail("%s could never conclude" % id)
		# Ordering is authored, not defaulted: the panel sorts by this.
		if not entry.has("weight") or not (typeof(entry["weight"]) == TYPE_FLOAT or typeof(entry["weight"]) == TYPE_INT):
			_fail("%s carries no numeric weight" % id)
		# Every effect slot re-validates through the same extraction the loader ran.
		for key in ["immediate", "on_complete", "on_fail", "on_invalid", "on_timeout"]:
			if not entry.has(key):
				continue
			var errs: Array[String] = []
			LawK.extract_shared_effects(entry[key], id, "sweep", errs,
				EconK.TAX_KEYS, EconK.SPENDING_KEYS, OpiK.BLOC_KEYS, EconK.SECTOR_TREND.keys())
			if not errs.is_empty():
				_fail("%s.%s does not pass extract_shared_effects: %s" % [id, key, errs])
		if not Programme.progress_of(fresh.player(), entry).has("current_value"):
			_fail("%s has no derivable progress read" % id)
		# If the complete trigger reads the progress field itself, the bar's
		# direction must agree with the op -- a bar that fills the wrong way lies.
		if entry.has("complete") and String(entry["complete"]["field"]) == String(entry["current_value"]):
			var op := String(entry["complete"]["op"])
			if String(entry["progressbar"]) == "up" and op != ">" and op != ">=":
				_fail("%s: direction up under a '%s' complete trigger" % [id, op])
			if String(entry["progressbar"]) == "down" and op != "<" and op != "<=":
				_fail("%s: direction down under a '%s' complete trigger" % [id, op])
		for label in ["new game", "month 1"]:
			# The NATION, not the state: the triggers read figures ON the nation,
			# and a GameState passed where a NationState is expected is a script
			# error per read and a null that every comparison scores as zero.
			var ns = (fresh if label == "new game" else ticked).player()
			if not Programme._preconditions_met(ns, entry.get("possible", [])):
				continue
			for key in ["complete", "fail", "invalid"]:
				if entry.has(key) and Programme._trigger_met(ns, entry[key]):
					_fail("%s: %s already true at %s" % [id, key, label])
			var cur := float(Programme.progress_of(ns, entry)["current_value"])
			var goal := float(entry["goal_value"])
			if String(entry["progressbar"]) == "up" and goal <= cur:
				_fail("%s: bar fills up but the goal is at or under the live figure at %s" % [id, label])
			if String(entry["progressbar"]) == "down" and goal >= cur:
				_fail("%s: bar fills down but the goal is at or over the live figure at %s" % [id, label])
		# The offer arm across the ROSTER, at new game -- the one fresh state
		# carries all twenty-nine seeded starts. The band is the admission test
		# because the band IS the offer: any nation it admits must find the
		# goal neither won nor lost already, or the entry concludes on tick one
		# at zero agency. The rule this enforces is "no fail inside its own
		# possible band, for any roster nation"; entries with no band are
		# judged from the player's chair only (see the docblock above).
		if entry.has("possible"):
			for nid in fresh.nations:
				var rns = fresh.nations[nid]
				if not Programme._preconditions_met(rns, entry["possible"]):
					continue
				for key in ["complete", "fail", "invalid"]:
					if entry.has(key) and Programme._trigger_met(rns, entry[key]):
						_fail("%s: %s already true at the offer for %s" % [id, key, nid])
		# The PLAYABLE arm: the same invariant, ungated entries included, for the
		# four chairs a player can sit in. The nine never choose, so an ungated
		# entry that is already won or lost at a playable start (Germany at 3.4
		# under a below-seven jobs goal) is a free pulse at choice and no
		# programme at all -- the band is the book's repair, and this arm is what
		# makes an unauthored band red rather than a content note. The playable
		# flag is read off the LOADER, not off a list in this file. Month 1 rides
		# along because the first tick is when a choice made at the offer first
		# concludes; `invalid` is exempt -- the world-changed guard, not a
		# verdict on the record.
		for nid in fresh.nations:
			if not bool(_loader.nations[nid].playable):
				continue
			for label in ["new game", "month 1"]:
				var pns = (fresh if label == "new game" else ticked).nations[nid]
				if not Programme._preconditions_met(pns, entry.get("possible", [])):
					continue
				for key in ["complete", "fail"]:
					if entry.has(key) and Programme._trigger_met(pns, entry[key]):
						_fail("%s: %s already true at the offer for %s at %s" % [id, key, nid, label])
	for g in by_group:
		if int(by_group[g]) == 0:
			_fail("no entries in group '%s' -- the five groups are the panel's filing" % str(g))


## The loader's loud refusals, at unit scale, on scratch error lists so the
## assertion is about the refusal and not about this test's own failures: an
## unknown field, the institutional slot a programme may not carry, an effect
## channel no law or event could use, an unrecognised trigger field, the entry
## with no trigger and no deadline that would tick forever -- and the
## REQUIRED_FIELDS half of the whitelist, which the loader enforces: an entry
## missing a required key, and a summary present but blank (the offer prints
## it under the name, so a blank summary is a field the entry does not carry).
func _test_the_loader_refuses_malformed_entries() -> void:
	var base := {
		"id": "prog_fixture", "name": "The Fixture", "summary": "s",
		"group": "economy", "activation": "player", "timeout_months": 0,
		"current_value": "growth_annual_pct", "goal_value": 2.0, "progressbar": "up",
	}
	_refused(base, "could never conclude", "an entry with no trigger and no deadline")
	_refused(_with(base, "possibles", []), "not a recognised field", "a typo'd field name")
	_refused(_with(base, "institutional", {"amendment_rule": "ordinary_law"}),
		"not a recognised field", "the institutional slot -- a programme is not an amendment")
	_refused(_with(base, "on_complete", {"relations": 0.05}),
		"not a recognised effect channel", "an effect channel no law or event could use")
	var complete := base.duplicate()
	complete["complete"] = {"field": "inflation_pct", "op": ">=", "value": 2.0}
	_refused(complete, "not a recognised field", "an unrecognised trigger field")
	var no_summary := base.duplicate()
	no_summary.erase("summary")
	_refused(no_summary, "missing required field 'summary'", "an entry without a summary")
	_refused(_with(base, "summary", "   "), "non-empty string", "an entry with a blank summary")


func _with(d: Dictionary, key: String, value) -> Dictionary:
	var out: Dictionary = d.duplicate()
	out[key] = value
	return out


func _refused(d: Dictionary, needle: String, what: String) -> void:
	var errs: Array[String] = []
	_loader._extract_programme_entry(d, "fixture.json", errs)
	for e in errs:
		if String(e).contains(needle):
			return
	_fail("the loader accepted %s: %s" % [what, errs])


## The two pulses are FIXED AUTHORED constants (model section 3): the swept dial is
## PROGRAMME_SPAN, so sweeping the pulses too would re-parametrise the same one dial
## twice. PROGRAMME_SPAN itself is deliberately NOT pinned here -- it ships 0.0 for
## TDD and the Task 4 sweep owns it.
func _test_pulses_are_fixed_authored_constants() -> void:
	if not is_equal_approx(ProgrammeK.PROGRAMME_PULSE_COMPLETE, 1.0):
		_fail("PROGRAMME_PULSE_COMPLETE moved off the fixed 1.0 -- it is not a sweep dimension")
	if not is_equal_approx(ProgrammeK.PROGRAMME_PULSE_FAIL, 1.0):
		_fail("PROGRAMME_PULSE_FAIL moved off the fixed 1.0 -- symmetry is what makes P2 testable")
	if ProgrammeK.PROGRAMME_DECAY_RATE <= 0.0 or ProgrammeK.PROGRAMME_DECAY_RATE >= 1.0:
		_fail("PROGRAMME_DECAY_RATE is not a monthly fraction in (0, 1)")


# --- The register and the offer -------------------------------------------------------

func _test_register_seeds_empty_and_available_at_term_start() -> void:
	var state = _new_state()
	for ns in state.nations.values():
		if not ns.programme.is_empty():
			_fail("%s starts with programme entries on the register" % ns.id)
		if int(ns.programme_chosen_term) != -1:
			_fail("%s starts with a programme already chosen" % ns.id)
		if not is_equal_approx(float(ns.programme_stock), 0.0):
			_fail("%s starts with a non-zero programme stock" % ns.id)

	var ns = state.player()
	# A fresh game IS a term start: Elections.init_nation() seeds months_in_term = 0.
	var offered: Array = Programme.available(state, ns, _loader)
	if offered.is_empty():
		_fail("no programme is offered at term start")
	for entry in offered:
		if String(entry["id"]) == GATED_ENTRY:
			_fail("%s is offered before its possible gate is met" % GATED_ENTRY)

	ns.months_in_term = 3
	if not Programme.available(state, ns, _loader).is_empty():
		_fail("programmes are offered outside term start")
	ns.months_in_term = 0


func _test_choose_outside_term_start_refuses() -> void:
	var state = _new_state()
	var ns = state.player()
	ns.months_in_term = 5
	var result: Dictionary = Programme.choose(state, ns, COMPLETE_ENTRY, _loader)
	if bool(result.get("applied", true)) or not bool(result.get("refused", false)):
		_fail("choose() outside term start was not refused")
	if not ns.programme.is_empty():
		_fail("a refused choice still reached the register")
	if int(ns.programme_chosen_term) != -1:
		_fail("a refused choice still marked the term as chosen")


func _test_choose_twice_refuses() -> void:
	var state = _new_state()
	var ns = state.player()
	var first: Dictionary = Programme.choose(state, ns, COMPLETE_ENTRY, _loader)
	if not bool(first.get("applied", false)):
		_fail("the first choice at term start was refused: %s" % [first.get("reason", "")])
	if Programme.choose(state, ns, TIMEOUT_ENTRY, _loader).get("applied", true):
		_fail("a second choice in the same term was allowed")
	if Programme.choose(state, ns, COMPLETE_ENTRY, _loader).get("applied", true):
		_fail("choosing the SAME entry twice was allowed")
	if ns.programme.size() != 1:
		_fail("expected one register entry after two choices, found %d" % ns.programme.size())
	# An unknown id is not an offer, and must refuse rather than half-apply.
	if Programme.choose(state, ns, "prog_does_not_exist", _loader).get("applied", true):
		_fail("an unknown entry id was accepted")


## The already-lost gate at a MID-GAME term start -- the half of Task 5's
## already-won/lost class no authored band can close, because the offer re-fires
## every term against drifted figures. The fixture is read off the loader by
## PROPERTY (an entry whose `possible` and `fail` can hold at once -- an
## overlap the sweep cannot see at start figures), never by id. Control arm
## first: inside the band the entry IS offered, so the assertion below cannot
## pass on a shut gate.
func _test_an_already_failed_entry_is_not_offered() -> void:
	var fixture := {}
	for entry in _loader.programme:
		if String(entry.get("activation", "")) != "player" or not entry.has("fail"):
			continue
		# The staged state carries one field, so every trigger the fixture reads
		# must read that field -- anything else would be a missing-key error,
		# not a comparison.
		if String(entry["fail"]["field"]) != "unrest_pct":
			continue
		var gated := true
		for cond in entry.get("possible", []):
			if String(cond["field"]) != "unrest_pct":
				gated = false
		if not gated:
			continue
		var staged := {"unrest_pct": 25.0}
		if Programme._trigger_met(staged, entry["fail"]) \
				and Programme._preconditions_met(staged, entry.get("possible", [])):
			fixture = entry
			break
	if fixture.is_empty():
		_fail("no entry's possible and fail can hold at once -- the fixture needs an overlap")
		return

	var state = _new_state()
	var ns = state.player()
	# The month a won election starts the next term: mid-game, and a term start.
	ns.terms_served = 2
	ns.months_in_term = 0

	ns.unrest_pct = 10.0
	if not Programme.available(state, ns, _loader).has(fixture):
		_fail("%s was not offered inside its own band -- the control arm failed" % str(fixture["id"]))

	ns.unrest_pct = 25.0
	for entry in Programme.available(state, ns, _loader):
		if String(entry["id"]) == String(fixture["id"]):
			_fail("%s is already past its fail line at the offer and must not be offered" % str(fixture["id"]))
	if Programme.choose(state, ns, String(fixture["id"]), _loader).get("applied", true):
		_fail("choose() accepted an entry whose fail trigger was already true")


## The gate is ONE-SIDED on purpose, pinned so it cannot be completed in the
## other direction: an entry whose COMPLETE trigger is already true at the
## offer stays offerable -- a goal already met is a different and far less
## harmful shape than a verdict already written, and the model doc records the
## call.
func _test_an_already_won_entry_stays_offered() -> void:
	var fixture := {}
	for entry in _loader.programme:
		if String(entry.get("activation", "")) != "player" or not entry.has("complete"):
			continue
		if not entry.has("possible") and not entry.has("fail"):
			fixture = entry
			break
	if fixture.is_empty():
		_fail("no ungated player entry with a complete trigger -- the fixture needs one")
		return

	var state = _new_state()
	var ns = state.player()
	var trigger: Dictionary = fixture["complete"]
	var staged: float = float(trigger["value"]) + (1.0 if String(trigger["op"]) in [">", ">="] else -1.0)
	ns.set(String(trigger["field"]), staged)

	var offered := false
	for entry in Programme.available(state, ns, _loader):
		if String(entry["id"]) == String(fixture["id"]):
			offered = true
	if not offered:
		_fail("%s with its complete trigger already true must stay offered" % str(fixture["id"]))


# --- Progress is a read, not a register -----------------------------------------------

func _test_progress_is_derived() -> void:
	var state = _new_state()
	var ns = state.player()
	var entry: Dictionary = _entry(COMPLETE_ENTRY)
	ns.unemployment_pct = 8.2
	var read: Dictionary = Programme.progress_of(ns, entry)
	if not is_equal_approx(float(read["current_value"]), 8.2):
		_fail("progress did not read the live figure (8.2 -> %s)" % str(read.get("current_value")))
	if not is_equal_approx(float(read["goal_value"]), float(entry["goal_value"])):
		_fail("progress did not read the authored goal")
	if String(read["progressbar"]) != String(entry["progressbar"]):
		_fail("progress did not read the authored direction")
	# The same call a moment later is a different answer -- nothing was cached.
	ns.unemployment_pct = 7.4
	if not is_equal_approx(float(Programme.progress_of(ns, entry)["current_value"]), 7.4):
		_fail("progress moved with the live figure, so it was stored somewhere")


# --- The three conclusions ------------------------------------------------------------

## (e) + (h): the complete trigger fires on a live read, the entry lands in
## concluded_this_month for exactly one month, and the conclusion's effects reach
## the state through the ONE applier -- as does the choice's own `immediate`.
func _test_a_met_complete_trigger_concludes_complete() -> void:
	var state = _new_state()
	var ns = state.player()
	var before: float = float(ns.bloc_offset.get("workers", 0.0))
	Programme.choose(state, ns, COMPLETE_ENTRY, _loader)
	var after_immediate: float = float(ns.bloc_offset.get("workers", 0.0))
	if not is_equal_approx(after_immediate - before, 0.05):
		_fail("the choice's immediate effects did not reach bloc_offset through the one applier")

	ns.unemployment_pct = 6.5
	Programme.tick_month(state, _loader)

	var register: Dictionary = ns.programme[0]
	if String(register["status"]) != "complete":
		_fail("a met complete trigger concluded as '%s'" % str(register["status"]))
	var concluded: Array = Programme.concluded_this_month(ns)
	if concluded.size() != 1 or String(concluded[0]["entry_id"]) != COMPLETE_ENTRY:
		_fail("the completed entry is not in concluded_this_month")
	if not is_equal_approx(Programme.programme_pulse(ns), ProgrammeK.PROGRAMME_PULSE_COMPLETE):
		_fail("a completion did not pay the unit pulse")

	var after_conclusion: float = float(ns.bloc_offset.get("workers", 0.0))
	if not is_equal_approx(after_conclusion - after_immediate, 0.10):
		_fail("on_complete did not reach bloc_offset through the one applier")

	# The pulse is a step input, not a standing rate: next month it reads zero.
	ns.months_in_term = 1
	_advance(state)
	if not Programme.concluded_this_month(ns).is_empty():
		_fail("an entry stayed in concluded_this_month after its month")
	if not is_equal_approx(Programme.programme_pulse(ns), 0.0):
		_fail("the pulse is still paying a month after the conclusion")


func _test_timeout_concludes_fail() -> void:
	var state = _new_state()
	var ns = state.player()
	Programme.choose(state, ns, TIMEOUT_ENTRY, _loader)
	ns.deficit_pct_gdp = 5.0  # above the 3.0 goal, so only the clock can end it

	for m in range(5):
		Programme.tick_month(state, _loader)
		_advance(state)
		ns.months_in_term = m + 1
	if String(ns.programme[0]["status"]) != "active":
		_fail("the entry concluded before its deadline month")
	Programme.tick_month(state, _loader)
	if String(ns.programme[0]["status"]) != "fail":
		_fail("an entry past timeout_months concluded as '%s'" % str(ns.programme[0]["status"]))
	if not is_equal_approx(Programme.programme_pulse(ns), -ProgrammeK.PROGRAMME_PULSE_FAIL):
		_fail("a timeout did not pay the fail pulse")
	if not is_equal_approx(float(ns.bloc_offset.get("business", 0.0)), -0.05):
		_fail("on_timeout did not reach bloc_offset through the one applier")


## V5.2a, the author's rule (2026-10-23): a no-deadline entry "se juge à la fin
## du mandat" -- judged at the end of the term, then ended. The term's end is the
## month the executive verdict falls due, read as Elections reads it; Programme
## runs before Elections, so the verdict lands in the month of the vote. Not met
## by then, it is a FAIL priced like a timeout (on_timeout, else on_fail).
func _test_no_deadline_is_judged_at_the_term_end() -> void:
	var state = _new_state()
	var ns = state.player()
	if int(_entry(NO_DEADLINE_ENTRY).get("timeout_months", -1)) != 0:
		_fail("%s carries a deadline -- the fixture no longer tests the no-deadline rule" % NO_DEADLINE_ENTRY)
		return
	Programme.choose(state, ns, NO_DEADLINE_ENTRY, _loader)
	ns.deficit_pct_gdp = 4.0  # between the complete (<= 0) and fail (>= 8) lines
	var before: float = float(ns.bloc_offset.get("business", 0.0))
	_set_month(state, _verdict_month(ns) - 1)
	Programme.tick_month(state, _loader)
	if Programme.is_term_end(state, ns) or String(ns.programme[0]["status"]) != "active":
		_fail("a no-deadline entry concluded '%s' before the term's last month" % str(ns.programme[0]["status"]))
	_advance(state)
	if not Programme.is_term_end(state, ns):
		_fail("the verdict month is not read as the term's end")
	Programme.tick_month(state, _loader)
	if String(ns.programme[0]["status"]) != "fail":
		_fail("an unmet no-deadline entry concluded '%s' at the term's end, not fail" % str(ns.programme[0]["status"]))
	if not is_equal_approx(Programme.programme_pulse(ns), -ProgrammeK.PROGRAMME_PULSE_FAIL):
		_fail("the term-end verdict did not pay the fail pulse")
	if not is_equal_approx(float(ns.bloc_offset.get("business", 0.0)) - before, -0.04):
		_fail("the term-end verdict did not land on_fail through the one applier")


func _test_no_deadline_met_at_the_term_end_completes() -> void:
	var state = _new_state()
	var ns = state.player()
	Programme.choose(state, ns, NO_DEADLINE_ENTRY, _loader)
	_set_month(state, _verdict_month(ns))
	ns.deficit_pct_gdp = -0.5
	Programme.tick_month(state, _loader)
	if String(ns.programme[0]["status"]) != "complete":
		_fail("a no-deadline entry met in the verdict month concluded '%s', not complete" % str(ns.programme[0]["status"]))


## A NationState whose executive clock was never set (a bare fixture) has no term
## to end: the rule must not judge every month.
func _test_the_term_end_needs_a_clock() -> void:
	var state = _new_state()
	var ns = state.player()
	Programme.choose(state, ns, NO_DEADLINE_ENTRY, _loader)
	ns.deficit_pct_gdp = 4.0
	ns.next_executive_year = 0
	ns.next_executive_month = 0
	Programme.tick_month(state, _loader)
	if Programme.is_term_end(state, ns) or String(ns.programme[0]["status"]) != "active":
		_fail("a nation with no executive clock judged its programme as '%s'" % str(ns.programme[0]["status"]))


## The rule is for the no-deadline entry only: an entry with its own clock is
## judged on that clock, even when the verdict month falls inside it (a nation
## whose first vote is three months in).
func _test_the_term_end_leaves_a_deadline_entry_alone() -> void:
	var state = _new_state()
	var ns = state.player()
	Programme.choose(state, ns, TIMEOUT_ENTRY, _loader)
	ns.deficit_pct_gdp = 5.0  # above the goal, below any fail line: only a clock can end it
	_set_month(state, _verdict_month(ns))
	Programme.tick_month(state, _loader)
	if String(ns.programme[0]["status"]) != "active":
		_fail("the term end concluded a %d-month entry in its first month as '%s'" % [
			int(_entry(TIMEOUT_ENTRY).get("timeout_months", 0)), str(ns.programme[0]["status"])])


func _verdict_month(ns) -> int:
	return int(ns.next_executive_year) * 12 + int(ns.next_executive_month)


## Absolute month (year * 12 + month, month 1..12) onto the state's clock.
func _set_month(state, absolute: int) -> void:
	state.year = (absolute - 1) / 12
	state.month = absolute - state.year * 12


## (g): the world moved on and the entry stops ticking -- priced at ZERO pulse
## (model section 2: the outcome was outside the player's agency), and its effects
## still land through the one applier (none are authored here, so bloc_offset
## must be bit-for-bit unchanged).
func _test_an_invalid_trigger_concludes_silent() -> void:
	var state = _new_state()
	var ns = state.player()
	Programme.choose(state, ns, INVALID_ENTRY, _loader)
	var before: Dictionary = ns.bloc_offset.duplicate(true)
	ns.unrest_pct = 45.0
	Programme.tick_month(state, _loader)

	if String(ns.programme[0]["status"]) != "invalid":
		_fail("a tripped invalid trigger concluded as '%s'" % str(ns.programme[0]["status"]))
	if Programme.concluded_this_month(ns).is_empty():
		_fail("the invalidated entry is not in concluded_this_month")
	if not is_equal_approx(Programme.programme_pulse(ns), 0.0):
		_fail("an invalid conclusion moved the pulse -- it must price at zero")
	for bloc in before:
		if float(ns.bloc_offset.get(bloc, 0.0)) != float(before[bloc]):
			_fail("an invalid conclusion moved bloc_offset['%s'] with no on_invalid authored" % bloc)


# --- The properties -------------------------------------------------------------------

## The register carries the DECISION and never the ladder: no content key, no cached
## progress, no second answer to the live figure. The pledges register's property,
## in the register the agenda panel will read.
func _test_the_register_carries_no_content() -> void:
	var state = _new_state()
	var ns = state.player()
	Programme.choose(state, ns, COMPLETE_ENTRY, _loader)
	var allowed := [
		"entry_id", "chosen_term", "months_live", "status",
		"concluded_term", "concluded_term_month",
	]
	for entry in ns.programme:
		for key in entry.keys():
			if not allowed.has(String(key)):
				_fail("the register carries '%s', which is not one of its six keys" % key)
		for key in allowed:
			if not entry.has(key):
				_fail("the register is missing '%s'" % key)
		if entry.has("goal_value") or entry.has("on_complete") or entry.has("name"):
			_fail("the register cached content -- the ladder must round-trip through data/programme/")


## JSON has one number type: a whole-number float comes back an int, and a stock of
## 1.0 would come back `1` without the from_dict cast -- the pledges precedent,
## exercised on the exact value that trips it.
func _test_the_register_round_trips_through_json() -> void:
	var state = _new_state()
	var ns = state.player()
	Programme.choose(state, ns, COMPLETE_ENTRY, _loader)
	ns.programme[0]["months_live"] = 2
	ns.programme_stock = 1.0

	var parsed = JSON.parse_string(JSON.stringify(ns.to_dict()))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("the nation dict did not survive JSON")
	var ns2 = NationState.from_dict(parsed)
	if ns2.programme.size() != 1:
		_fail("the programme register did not round-trip")
	var original: Dictionary = ns.programme[0]
	var loaded: Dictionary = ns2.programme[0]
	for key in original:
		if original[key] != loaded.get(key, null):
			_fail("register key '%s' changed across the round trip: %s -> %s" % [key, str(original[key]), str(loaded.get(key, ""))])
	if typeof(int(loaded["months_live"])) != TYPE_INT or int(loaded["months_live"]) != 2:
		_fail("months_live did not come back the int it went out as")
	if typeof(ns2.programme_stock) != TYPE_FLOAT or not is_equal_approx(ns2.programme_stock, 1.0):
		_fail("programme_stock did not come back a float -- the JSON int trap")
	if typeof(ns2.programme_chosen_term) != TYPE_INT:
		_fail("programme_chosen_term did not come back an int")


# --- The leaf contract ----------------------------------------------------------------

## Read from the source, the idiom test_pledges.gd uses. This file may reach its own
## constants and the ONE applier, which is (b) reading (a); law.gd does the content
## extraction at load, in the loader, and nothing here may name a UI file or opinion.
func _test_preloads_are_a_short_list() -> void:
	var text := FileAccess.get_file_as_string("res://src/sim/programme.gd")
	var allowed := [
		"res://src/sim/programme_constants.gd",
		"res://src/sim/legislature.gd",
	]
	for line in text.split("\n"):
		var trimmed := String(line).strip_edges()
		if not trimmed.begins_with("const ") or not trimmed.contains("preload("):
			continue
		var path := trimmed.get_slice("preload(\"", 1).get_slice("\"", 0)
		if not allowed.has(path):
			_fail("src/sim/programme.gd preloads '%s', which is not on its short list" % path)
		if path.contains("src/ui/") or path.contains("opinion"):
			_fail("src/sim/programme.gd preloads '%s' -- a leaf does not know the UI or opinion exists" % path)


## The nine never choose. Programme.init_nation() seeds every nation (the Campaign
## precedent) and only the player's register is ever populated, which is what keeps
## the pulse exactly zero on every AI path -- model section 5, asserted not described.
func _test_the_nine_never_choose() -> void:
	var dir := DirAccess.open("res://src/sim")
	if dir == null:
		_fail("could not open src/sim to check for an AI programme agenda")
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".gd") and name != "programme.gd":
			var text := FileAccess.get_file_as_string("res://src/sim/%s" % name)
			if text.contains("Programme.choose"):
				_fail("src/sim/%s chooses a programme -- the nine are supposed to be inert" % name)
		name = dir.get_next()
	dir.list_dir_end()


## Instance fifty-two's rule, pointed at the new content: no file under src/ui/ or
## tools/ may name three or more entry ids in one literal. Two is a pair; three is a
## hand-written list, and the loader already knows them -- test_panel_kit's scanner,
## reading its ids from the LOADER rather than from a list of its own.
func _test_no_hand_written_entry_list() -> void:
	var ids: Array[String] = []
	for entry in _loader.programme:
		ids.append(String(entry["id"]))
	if ids.size() < 3:
		_fail("the scanner needs at least three entry ids to mean anything")
	for path in _gd_files("res://src/ui") + _gd_files("res://tools"):
		var source := FileAccess.get_file_as_string(path)
		var worst := 0
		var worst_line := ""
		# Both bracket shapes -- tools/screenshot.gd's dictionary was the fifth list,
		# and a scanner that only read arrays would have called it clean.
		for opener in [["[", "]"], ["{", "}"]]:
			for chunk in source.split(opener[0]):
				var head: String = chunk.split(opener[1])[0]
				if head.length() > 600:
					continue
				var count := 0
				for id in ids:
					if head.contains(id):
						count += 1
				if count > worst:
					worst = count
					worst_line = head.strip_edges().substr(0, 120)
		if worst >= 3:
			_fail("%s names %d programme entry ids in one literal -- that is a list, and the loader already knows them: %s"
				% [path, worst, worst_line])


# --- Harness --------------------------------------------------------------------------

## The ladder borrows the law's precondition list, so Programme._read_field must BE
## Legislature.read_field for every field on it -- one reader, one meaning. Each field
## is staged to a distinct non-zero value so a reader that fell through to the 0.0
## default, or mixed two fields up, cannot pass; eu_member is checked both ways.
func _test_trigger_reads_delegate_to_the_laws_reader() -> void:
	var ns = _new_state().player()
	ns.unemployment_pct = 7.3
	ns.deficit_pct_gdp = 4.1
	ns.overall_approval_pct = 41.5
	ns.growth_annual_pct = 1.7
	ns.terms_served = 2
	ns.unrest_pct = 3.3
	ns.co2e_per_capita_t = 5.5
	var expected := {
		"unemployment_pct": 7.3,
		"deficit_pct_gdp": 4.1,
		"overall_approval_pct": 41.5,
		"growth_annual_pct": 1.7,
		"terms_served": 2.0,
		"unrest_pct": 3.3,
		"co2e_per_capita_t": 5.5,
		"debt_to_gdp_pct": float(ns.debt_to_gdp_pct()),
	}
	for field in ProgrammeK.TRIGGER_FIELDS:
		if field == "eu_member":
			continue
		var got: float = Programme._read_field(ns, field)
		if not is_equal_approx(got, Legislature.read_field(ns, field)):
			_fail("Programme._read_field('%s') = %s, the law's reader says %s" % [field, got, Legislature.read_field(ns, field)])
		if not expected.has(field):
			_fail("TRIGGER_FIELDS grew '%s' and this test stages no value for it" % field)
		elif not is_equal_approx(got, float(expected[field])):
			_fail("Programme._read_field('%s') = %s, staged %s" % [field, got, expected[field]])
	ns.orgs = ["eu"]
	if not is_equal_approx(Programme._read_field(ns, "eu_member"), 1.0):
		_fail("a Union member reads eu_member != 1.0 through the programme reader")
	ns.orgs = []
	if not is_equal_approx(Programme._read_field(ns, "eu_member"), 0.0):
		_fail("a non-member reads eu_member != 0.0 through the programme reader")


func _new_state():
	return GameState.new_game(_loader, PLAYER)


func _entry(id: String) -> Dictionary:
	for entry in _loader.programme:
		if String(entry["id"]) == id:
			return entry
	_fail("no programme entry named '%s' is loaded" % id)
	return {}


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, name])
	return out


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _finish() -> void:
	if _failures.is_empty():
		print("test_programme: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
