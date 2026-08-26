extends RefCounted

## Events -- V1.8, the last block of the V1 tier and the last section of
## docs/tiers/v1.md. A crisis or a revelation arrives, the player has a fixed number of
## months to answer it, and if they say nothing the authored default answers for them.
##
## The model and every number is docs/events-model.md; src/sim/events_constants.gd is
## the values, and it carries exactly ONE tuned constant.
##
## ============================================================================
## AN EVENT IS AN OCCASION, NOT A NEW MECHANIC
## ============================================================================
## Counting docs/brainstorm/mechanics-*.md one last time found that section 8's own two
## bullets are tiered nowhere and that every event-shaped mechanic in those four tables
## is Someday -- so there is no crisis left to author that is not already a machine here
## (a strike is V1.5c, a downgrade is V1.6c, a foreign act is V1.3f) or tiered out of
## V1. See src/core/event.gd's header for the full argument. What this file adds is the
## MOMENT, the MENU and the DEADLINE; every consequence lands on a register some earlier
## session already owns and writes through the one function that owns it.
##
## ============================================================================
## NO RANDOMNESS, AND THE HAZARD IS A PURE FUNCTION OF (nation, event, month)
## ============================================================================
## docs/tiers/v1.md section 8 asks for "scripted and SEMI-RANDOM events", which collides
## head-on with docs/economy-model.md's rule that there is no randf() anywhere --
## determinism is what makes Budget.project() exactly equal to what subsequently
## happens, and that is an MVP done-when condition. V1.6a hit the identical collision in
## the identical words ("arriving whether or not deserved") and its answer transfers
## whole: the draw is a hash, so an event's arrival month is fixed before the game
## starts and reproducible from state alone.
##
## The hash is Cycle.unit(), PRELOADED rather than copied. cycle.gd duplicates
## poll_noise.gd's on a boundary argument -- one is a render-time device that must never
## touch the model -- and that argument does not transfer to a second file inside
## src/sim/. tests/test_events.gd fails if a splitmix constant appears in this file.
##
## ============================================================================
## PLAYER ONLY, AND NOT A LEAF
## ============================================================================
## Events fire for the player's nation alone, because a choice needs somebody to make
## it and the nine have no decider. Bloc._tick_council() already gates on
## state.player_nation_id for the same reason -- the council's proposal waits for the
## player's vote and nobody else's -- so this is the second place in src/sim/ that reads
## the player id rather than has_budget, and the reason is the same both times.
## tests/test_events.gd pins that there is no AI chooser: docs/defence-model.md's honest
## limitation, recorded a sixth time rather than left as an absence.
##
## This file PRELOADS legislature.gd, and that is deliberate rather than reluctant. The
## leaf alternative -- returning the resolved choice as data for somebody else to apply,
## which is src/sim/calendar.gd's due() and src/sim/referendum.gd's resolve_due() -- fails
## here because there is no single somebody: src/ui/main.gd, tools/balance_probe.gd,
## tests/test_balance.gd, Budget.project() and eight probes would each have to apply,
## which is V1.5d's forgotten-tick failure multiplied by ten rather than avoided. V1.6a's
## rule governs: a system that CANNOT be forgotten is worth more than one that is
## remembered. The dependency runs one way only and tests/test_events.gd fails if
## legislature.gd ever names this file.
##
## WRITES ns.event_pending, ns.event_fired, ns.event_quiet_months and ns.event_history,
## and nothing else. Every effect a choice carries is written by
## Legislature.apply_effects(), which is the single writer of all six of those channels.

const K = preload("res://src/sim/events_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Cycle = preload("res://src/sim/cycle.gd")


## Runs for all ten nations even though only the player's register is ever written, so
## the state shape is uniform and duplicate_state() has nothing conditional to copy --
## Unrest.init_nation()'s and Referendum.init_nation()'s call, and their reason.
static func init_nation(ns) -> void:
	ns.event_pending = {}
	ns.event_fired = {}
	ns.event_quiet_months = 0
	ns.event_history.clear()


# --- Reads -------------------------------------------------------------------------

static func is_pending(ns) -> bool:
	return not ns.event_pending.is_empty()


static func pending_event_id(ns) -> String:
	return String(ns.event_pending.get("event_id", ""))


static func pending_event_name(ns) -> String:
	return String(ns.event_pending.get("event_name", ""))


## Months left before the default answers for the player. Copied into the register at
## announcement, counted down here, and read by src/sim/calendar.gd -- which needs no
## preload to do it, because "months remaining" is the idiom every countdown in that
## file already uses. V1.6f's project register and V1.7c's referendum, a third time.
static func months_left(ns) -> int:
	return int(ns.event_pending.get("months_left", 0))


static func event_by_id(loader, event_id: String):
	for ev in loader.events:
		if String(ev.id) == event_id:
			return ev
	return null


## The event currently in front of the player, or null.
static func pending_event(ns, loader):
	if not is_pending(ns):
		return null
	return event_by_id(loader, pending_event_id(ns))


# --- The tick ----------------------------------------------------------------------

## One month. Runs in src/ui/main.gd AFTER Unrest.tick_month(), so `unrest_pct` has
## settled before it is read as a precondition, and before Cabinet and Elections, which
## run last on settled state.
static func tick_month(state, loader) -> void:
	var ns = state.player()
	if ns == null or not ns.has_budget:
		return

	if int(ns.event_quiet_months) > 0:
		ns.event_quiet_months = int(ns.event_quiet_months) - 1

	if is_pending(ns):
		var left := months_left(ns) - 1
		if left > 0:
			ns.event_pending["months_left"] = left
			return
		var ev = pending_event(ns, loader)
		if ev == null:
			# Content the save was carrying and this build no longer defines. Cleared
			# rather than left standing: an entry pointing at nothing is a deadline the
			# player can never answer, and Calendar.fixed_dates() would print it forever.
			ns.event_pending = {}
			return
		_resolve(state, ns, loader, ev, ev.default_choice(), true)
		return

	if int(ns.event_quiet_months) > 0:
		return

	var next = _next_event(state, ns, loader)
	if next != null:
		announce(ns, next)


## The first event, in content order, whose gate is open this month.
##
## Content order rather than a score, and the difference matters: a scored pick would be
## a second decision the content cannot see, and with one pending slot the ordering only
## ever decides which of two simultaneously-drawn events goes first -- the other draws
## again next month, because the hazard is a function of the month.
static func _next_event(state, ns, loader):
	for ev in loader.events:
		if ev.once and ns.event_fired.has(ev.id):
			continue
		if not Legislature.preconditions_met(ns, ev.preconditions):
			continue
		if not hazard_passes(ns.id, ev.id, int(state.year), int(state.month), float(ev.likelihood)):
			continue
		return ev
	return null


## Whether this event's deterministic draw comes up this month.
##
## Pure: the same (nation, event, month) always gives the same answer, so a save
## reloaded on the month an event arrived gets the same event, and Budget.project()'s
## twelve-month forecast sees exactly what the following twelve months deliver.
static func hazard_passes(nation_id: String, event_id: String, year: int, month: int, likelihood: float) -> bool:
	if likelihood <= 0.0:
		return false
	var index: int = (
		_absolute_month(year, month)
		- _absolute_month(K.EVENT_EPOCH_YEAR, K.EVENT_EPOCH_MONTH)
	)
	return Cycle.unit("%s|%s" % [nation_id, event_id], index) < likelihood


static func _absolute_month(year: int, month: int) -> int:
	return year * 12 + month


## Put the event in front of the player.
##
## `event_name` is COPIED IN, not looked up at read time, for Referendum.announce()'s
## reason: src/sim/calendar.gd draws a diary row off this register and preloads nothing,
## so the register has to carry its own label. It is also what lets tick_month() above
## clear an entry whose content has gone without needing to name it.
##
## THE `once` MARK IS MADE HERE AND NOT AT RESOLUTION, which is the one place this
## differs from Legislature.apply()'s `passed_law_ids`. An event HAS HAPPENED the moment
## it is announced; the choice is the response to it, not the event. Marking at
## resolution would also mean a save reloaded mid-crisis could see the same revelation
## announced twice.
static func announce(ns, ev) -> void:
	ns.event_pending = {
		"event_id": ev.id,
		"event_name": ev.event_name,
		"months_left": int(ev.respond_months),
	}
	if ev.once:
		ns.event_fired[ev.id] = true


# --- The verb ----------------------------------------------------------------------

## The player answers. Returns the record that was written, or {} if there was nothing
## pending or the id names no choice on it.
##
## There is no cost to answering EARLY and none to answering late beyond the default
## itself, and that is not an oversight: the deadline is the pressure, and a second
## price on the timing would need a number solved against the default's, which is what
## src/core/investment_action.gd refuses as one strength written twice. What waiting
## actually buys is information -- another month of the figures the choice is about --
## and what it risks is the default arriving first.
static func choose(state, loader, choice_id: String) -> Dictionary:
	var ns = state.player()
	if ns == null or not is_pending(ns):
		return {}
	var ev = pending_event(ns, loader)
	if ev == null:
		ns.event_pending = {}
		return {}
	var choice: Dictionary = ev.choice_by_id(choice_id)
	if choice.is_empty():
		return {}
	return _resolve(state, ns, loader, ev, choice, false)


static func _resolve(state, ns, loader, ev, choice: Dictionary, defaulted: bool) -> Dictionary:
	Legislature.apply_effects(state, ns, choice.get("effects", {}), loader)

	ns.event_pending = {}
	ns.event_quiet_months = K.EVENT_COOLDOWN_MONTHS

	var record := {
		"event_id": ev.id,
		"event_name": ev.event_name,
		"choice_id": String(choice.get("id", "")),
		"choice_label": String(choice.get("label", "")),
		"defaulted": defaulted,
		"year": int(state.year),
		"month": int(state.month),
	}
	# A DISPLAY RECORD AND NOT A MEMORY. Nothing in src/sim/ reads this back, and
	# tests/test_events.gd asserts it by reading every file in the directory -- V1.3e's
	# *no grievance ledger* property and V1.3f's own `foreign_acts` check, in the one
	# session most likely to be tempted to build the ledger literally. What an event
	# remembers about a previous event is exactly what `event_fired` says and nothing
	# more.
	ns.event_history.push_front(record)
	while ns.event_history.size() > K.EVENTS_KEPT:
		ns.event_history.remove_at(ns.event_history.size() - 1)
	return record
