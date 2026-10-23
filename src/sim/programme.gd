extends RefCounted

## The government's programme -- V4.1, the register machine. An agenda the player
## chooses at term start: the first time this game asks WHAT ARE YOU FOR rather
## than what will you do this month. The model and every number's rationale is
## docs/programme-model.md; src/sim/programme_constants.gd is the bounds and
## data/programme/ is the content.
##
## The shape is Victoria 3's journal entry, named for this game. An entry is a
## live goal with a trigger, a clock and a progress reading; it concludes ONCE, on
## one of three outcomes, and its price lands through the one applier the law and
## the event already share.
##
## ============================================================================
## THE STATE MACHINE IS FOUR STATUSES AND NO FLAGS
## ============================================================================
## `active` -> `complete` | `fail` | `invalid`, once, and never back. There is no
## "is live" boolean, no scheduler and no hook in elections.gd: the term-start
## gate is a LEVEL READ of ns.months_in_term (0 at new game and again in the month
## a won election resets it), which is docs/defence-model.md's V1.3g rule -- an
## obligation that opens itself closes itself, so nothing in this project ever
## lifts a flag it has set.
##
## Precedence when two conclusions are true in the same month: complete > fail >
## invalid > timeout. The player DELIVERED, and a goal achieved is not unmet
## because a world that also changed would have ended it; `invalid` last of the
## triggers for the same reason read from the other side -- it exists so a
## world-changed entry stops ticking rather than failing a player who never got to
## play it, not to erase a delivery that already landed. Timeout is not a trigger
## but the clock: the deadline month is the entry's LAST month to land the goal,
## and the same tick concludes `fail` if it did not. A no-deadline entry's clock is
## the term (V5.2a): it is judged in the month the executive verdict falls due.
##
## ============================================================================
## THE PRICE IS A PULSE INTO A STOCK THIS FILE DOES NOT OWN
## ============================================================================
## programme_pulse() is a pure read of the register: +PULSE_COMPLETE for each
## entry that completed this month, -PULSE_FAIL for each that failed, 0 for an
## `invalid`, and 0 for a month with no conclusion at all. The stock it feeds
## (ns.programme_stock, bounded [-1, 1], decaying at PROGRAMME_DECAY_RATE) is
## advanced inside Opinion._tick_nation beside the honeymoon's site -- model
## section 3's agreement clause -- and THIS FILE NEVER WRITES IT. A second writer
## would be the two-machines-one-job failure the single-applier argument exists
## to prevent, one level up.
##
## A choice pays NOTHING. Making a programme is not the pledge's reward-now shape
## grafted onto the wrong register; the price is delivery's, on conclusion. Model
## section 8.
##
## ============================================================================
## A LEAF, WITH THE LOADER HOLDING THE LADDER
## ============================================================================
## This file preloads its constants and Legislature -- apply_effects, the ONE
## applier, and read_field, the one precondition reader -- and nothing else. No UI,
## no opinion.gd, no law.gd (the loader extracts `immediate` and every `on_*`
## through Law.extract_shared_effects at load; by the time a conclusion fires, its
## effects are an ordinary effect dictionary). Content lives in data/programme/ and
## is read through the loader on every tick, so the register -- like the pledge
## register beside it -- round-trips the DECISION and never the ladder.
##
## THE NINE ARE INERT. Programme.init_nation() seeds every nation (the Campaign
## and Projects precedent) but only the player's register is ever populated:
## nothing in src/sim/ calls choose(), which tests/test_programme.gd pins, and
## the pulse on an empty register is exactly zero -- which is what makes the
## balance re-run's "idle baseline is bit-identical" prediction checkable rather
## than assumed.

const K = preload("res://src/sim/programme_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")


## Seeds the live register: nothing chosen, nothing priced. Every nation gets the
## fields rather than only the player -- what keeps the nine inert is that nothing
## ever executes a choice for them.
static func init_nation(ns) -> void:
	ns.programme = []
	ns.programme_chosen_term = -1
	ns.programme_stock = 0.0


## The term-start read, and the only gate the offer and the choice both run
## through. months_in_term is 0 at new game (Elections.init_nation seeds it) and
## 0 again in the month a won election starts the next term; every ordinary month
## it counts up from there. A level read of a counter Elections already owns --
## this file is not its second writer.
static func is_term_start(ns) -> bool:
	return ns.months_in_term == 0


## The term's last month: the month the executive verdict falls due, read exactly
## as Elections reads it (`>=` in absolute months, Calendar.due()'s rule, so a
## stepped-over date still counts). A level read of Elections' clock, which this
## file never writes; Programme runs before Elections, so the month it reads true
## is the month of the vote, and a won election moves the clock past it. A clock
## never set (year 0, a bare fixture) has no term to end.
static func is_term_end(state, ns) -> bool:
	if int(ns.next_executive_year) <= 0:
		return false
	return int(state.year) * 12 + int(state.month) 		>= int(ns.next_executive_year) * 12 + int(ns.next_executive_month)


## One month of every live register: advance the clocks, judge the triggers,
## conclude what concluded. Runs for all ten nations the way Pledges.tick_month()
## does -- an empty register returns before any work, so the nine cost nothing.
static func tick_month(state, loader) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		_tick_nation(state, state.nations[id], loader)


static func _tick_nation(state, ns, loader) -> void:
	if ns.programme.is_empty():
		return

	var content := _content_by_id(loader)
	for entry in ns.programme:
		if String(entry["status"]) != K.STATUS_ACTIVE:
			continue

		entry["months_live"] = int(entry["months_live"]) + 1
		var terms: Dictionary = content.get(String(entry["entry_id"]), {})
		if terms.is_empty():
			# A save carried an entry forward into content that no longer defines
			# it. Conclude INVALID -- the goal was overtaken by the world, which
			# includes the world the loader now describes -- and never FAIL: the
			# player did not miss a goal nobody can read.
			push_error("programme: register entry '%s' has no content -- concluding invalid" % str(entry["entry_id"]))
			_conclude(state, ns, loader, entry, {}, K.STATUS_INVALID)
			continue

		# Precedence: complete > fail > invalid > timeout. See the header.
		if _trigger_met(ns, terms.get("complete", {})):
			_conclude(state, ns, loader, entry, terms.get("on_complete", {}), K.STATUS_COMPLETE)
			continue
		if _trigger_met(ns, terms.get("fail", {})):
			_conclude(state, ns, loader, entry, terms.get("on_fail", {}), K.STATUS_FAIL)
			continue
		if _trigger_met(ns, terms.get("invalid", {})):
			_conclude(state, ns, loader, entry, terms.get("on_invalid", {}), K.STATUS_INVALID)
			continue

		# A no-deadline entry is judged at the end of the term, then ends (the
		# author, 2026-10-23: "il se juge à la fin du mandat"). Before V5.2a it
		# ran on into the next term with nothing to conclude it but a trigger.
		var timeout := int(terms.get("timeout_months", 0))
		if (timeout > 0 and int(entry["months_live"]) >= timeout) 				or (timeout == 0 and is_term_end(state, ns)):
			# Timeout IS a fail (the brief's own wording and the pulse's sign),
			# but the table's `on_timeout` slot is its effects: an entry the clock
			# killed may price differently from one a trigger did. Unauthored, a
			# timeout falls to on_fail -- a missed goal is a missed goal. The
			# term's end is the same verdict for an entry whose clock is the term.
			var effects: Dictionary = terms.get("on_timeout", {})
			if effects.is_empty():
				effects = terms.get("on_fail", {})
			_conclude(state, ns, loader, entry, effects, K.STATUS_FAIL)


## Record the conclusion and land its effects through the ONE applier. The month
## of the conclusion is stored as (terms_served, months_in_term) rather than an
## absolute month because concluded_this_month() reads the same pair back and a
## register that compared clocks across terms would re-announce old conclusions
## in a later term's same-named month.
static func _conclude(state, ns, loader, entry: Dictionary, effects: Dictionary, status: String) -> void:
	entry["status"] = status
	entry["concluded_term"] = int(ns.terms_served)
	entry["concluded_term_month"] = int(ns.months_in_term)
	if not effects.is_empty():
		Legislature.apply_effects(state, ns, effects, loader)


# --- The offer and the verb -----------------------------------------------------------

## Which entries are offerable RIGHT NOW. Empty everywhere but term start,
## structurally, before any content is consulted -- Pledges.available()'s refusal
## of everything outside the run-up: a window that had to be remembered by the
## content would be a window a file could forget.
##
## An entry is offered when its activation is the player's (the other three are
## later blocks' writers), its `possible` gate passes, it is not already
## running, and it is not ALREADY LOST -- an entry whose authored `fail`
## trigger is true at the offer is skipped, because choosing one would
## insta-fail on the next tick for a -1 pulse on a programme the player never
## got to play. Task 5 closed the new-game half of that class by authoring
## bands into the content; this gate is the mid-game half, which no band can
## close -- the offer re-fires every term against drifted figures. An
## already-WON entry stays offerable on purpose: a goal already met is a
## different and far less harmful shape, recorded in the model doc. A
## CONCLUDED entry may be offered again in a later term -- a new term is a new
## attempt at the same goal, and the register separates the attempts by
## status. Concluded-this-term entries cannot be re-offered while
## programme_chosen_term still names this term: one choice per term, the scalar
## below the sweep.
static func available(state, ns, loader) -> Array:
	var out: Array = []
	if not is_term_start(ns):
		return out
	if int(ns.programme_chosen_term) == int(ns.terms_served):
		return out
	for entry in loader.programme:
		if String(entry.get("activation", "")) != "player":
			continue
		if not _active_entry(ns, String(entry["id"])).is_empty():
			continue
		if not _preconditions_met(ns, entry.get("possible", [])):
			continue
		if entry.has("fail") and _trigger_met(ns, entry["fail"]):
			continue
		out.append(entry)
	return out


## The player command: put an entry on the register for this term, apply its
## `immediate` effects through the ONE applier, and mark the term as chosen.
## Refuses rather than half-applies when the choice is not legal, so a stale
## button cannot produce an effect the gate exists to prevent -- and it needs the
## loader for both halves of that, which is why it takes one where the brief's
## interface line sketched three arguments.
static func choose(state, ns, entry_id: String, loader) -> Dictionary:
	var refused := {
		"entry_id": entry_id,
		"applied": false,
		"refused": true,
		"reason": "",
	}
	if not is_term_start(ns):
		refused["reason"] = "not_term_start"
		return refused
	if int(ns.programme_chosen_term) == int(ns.terms_served):
		refused["reason"] = "already_chosen"
		return refused

	var chosen: Dictionary = {}
	for entry in available(state, ns, loader):
		if String(entry["id"]) == entry_id:
			chosen = entry
			break
	if chosen.is_empty():
		# Not offerable: unknown id, a `possible` gate shut, or an activation
		# nothing can fire yet. One reason for all three -- the panel offered
		# what available() said, and this is the backstop.
		refused["reason"] = "not_offerable"
		return refused

	ns.programme.append({
		"entry_id": entry_id,
		"chosen_term": int(ns.terms_served),
		"months_live": 0,
		"status": K.STATUS_ACTIVE,
		"concluded_term": -1,
		"concluded_term_month": -1,
	})
	ns.programme_chosen_term = int(ns.terms_served)

	var immediate: Dictionary = chosen.get("immediate", {})
	if not immediate.is_empty():
		Legislature.apply_effects(state, ns, immediate, loader)

	return {
		"entry_id": entry_id,
		"name": String(chosen.get("name", entry_id)),
		"applied": true,
		"refused": false,
	}


# --- Reading the register -------------------------------------------------------------

## The progress read, DERIVED from the live figure every time it is called --
## the region-share discipline. A cached `current_value` could disagree with the
## live figure it reads, and then the panel lies. Returns the authored goal and
## direction untouched; the bar's fraction is the panel's arithmetic on the pair.
static func progress_of(ns, entry: Dictionary) -> Dictionary:
	return {
		"current_value": _read_field(ns, String(entry["current_value"])),
		"goal_value": float(entry["goal_value"]),
		"progressbar": String(entry["progressbar"]),
	}


## Every register entry that concluded THIS month -- completed, failed and
## invalidated alike. The agenda panel's "what happened" list and the pulse's
## only input, which is why they share one read: two answers to "what concluded"
## is how a panel and a price drift apart.
static func concluded_this_month(ns) -> Array:
	var out: Array = []
	for entry in ns.programme:
		if String(entry["status"]) == K.STATUS_ACTIVE:
			continue
		if int(entry["concluded_term"]) != int(ns.terms_served):
			continue
		if int(entry["concluded_term_month"]) != int(ns.months_in_term):
			continue
		out.append(entry)
	return out


## Every register entry chosen THIS term, live or already concluded. The three
## surfaces that answer "what is this term's programme" -- the Agenda, the
## Overview section and the Campaign panel's promises line -- read it through
## here rather than each re-filtering `chosen_term`, which is how two panels
## end up carrying two answers to one question. Not the one-choice-per-term
## gate: that is the `programme_chosen_term` scalar beside the register.
static func this_term(ns) -> Array:
	var out: Array = []
	for entry in ns.programme:
		if int(entry["chosen_term"]) == int(ns.terms_served):
			out.append(entry)
	return out


## The unit pulse for Opinion's bounded stock: +1 per completion this month,
## -1 per failure, ZERO for an invalid -- the outcome was outside the player's
## agency, so concluding the entry is all it does (model section 2). A month
## with no conclusion reads exactly 0.0, which is what makes the idle and
## nine-AI baseline bit-identical rather than merely small.
static func programme_pulse(ns) -> float:
	var pulse := 0.0
	for entry in concluded_this_month(ns):
		match String(entry["status"]):
			K.STATUS_COMPLETE:
				pulse += K.PROGRAMME_PULSE_COMPLETE
			K.STATUS_FAIL:
				pulse -= K.PROGRAMME_PULSE_FAIL
			_:
				pass  # invalid: conclude without pricing
	return pulse


## The authored terms for an entry id, or {} -- the surfaces' name, summary,
## deadline and progress-scale read, on Pledges.terms_of()'s pattern. The
## register stores the DECISION and never the ladder, so every display fact
## about an entry is looked up from the loader through here rather than cached
## on the register (a second answer to the content is how a panel drifts).
static func terms_of(loader, entry_id: String) -> Dictionary:
	if loader == null:
		return {}
	for entry in loader.programme:
		if String(entry["id"]) == entry_id:
			return entry
	return {}


## The register entry currently running for this id, or {} -- the panel's "what
## are you working on" read, and available()'s exclusion of a still-running goal.
static func _active_entry(ns, entry_id: String) -> Dictionary:
	for entry in ns.programme:
		if String(entry["entry_id"]) == entry_id and String(entry["status"]) == K.STATUS_ACTIVE:
			return entry
	return {}


# --- Triggers and fields --------------------------------------------------------------

static func _trigger_met(ns, trigger: Dictionary) -> bool:
	if trigger.is_empty():
		return false
	var actual: float = _read_field(ns, String(trigger["field"]))
	var value: float = float(trigger["value"])
	match String(trigger["op"]):
		"<": return actual < value
		"<=": return actual <= value
		">": return actual > value
		">=": return actual >= value
		"==": return is_equal_approx(actual, value)
		_: return false


static func _preconditions_met(ns, conditions: Array) -> bool:
	for cond in conditions:
		if not _trigger_met(ns, cond):
			return false
	return true


## The ladder borrows the law's precondition list (TRIGGER_FIELDS is
## PRECONDITION_FIELDS), so it borrows the law's reader too: the list's meaning lives
## in Legislature.read_field and nowhere else -- a field added there is readable here
## with no edit. Every field in it is a figure ON the nation, which is why this read
## takes no `state`, unlike pledges' list, which reaches the campaign clock. A field
## outside the list is an error and a zero, never a silent pass (V1.6d's
## confident-zero rule); the guard is here so the message stays Programme's.
static func _read_field(ns, field: String) -> float:
	if not K.TRIGGER_FIELDS.has(field):
		push_error("programme: unknown field '%s'" % field)
		return 0.0
	return Legislature.read_field(ns, field)


## entry id -> the authored terms. Built from the loader on every call rather
## than cached on NationState, because caching it would put content in the save
## -- the pledge ladder's rule, a seventh register later.
static func _content_by_id(loader) -> Dictionary:
	var out := {}
	if loader == null:
		return out
	for entry in loader.programme:
		out[String(entry["id"])] = entry
	return out
