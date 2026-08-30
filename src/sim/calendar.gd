extends RefCounted

## The president's diary, U6a.
##
## Two jobs, and the first is the one the session is judged on. The game has
## carried dated state since the MVP -- an election date, the council's next
## proposal and its pending vote, a dissolution lockout, and every diplomatic and
## legislative cooldown -- and has never had a surface that puts any of it on a
## timeline. fixed_dates() gathers it. Nothing here computes it; it is all read
## off fields other systems already maintain, so the diary cannot disagree with
## the game about when something happens.
##
## The second job is booking. A booking is a scheduling skin over a command that
## already exists: no new effect channel, no new content type, no new verb. It is
## OPTIONAL rather than a replacement -- every verb keeps its act-now button --
## because a deferral that buys nothing is strictly worse than acting, which is
## the dominance failure V1.3c and V1.3d each shipped and had to be taught by a
## probe. The currency that would have bought something (a monthly budget of the
## player's days) was measured and CUT; see calendar_constants.gd.
##
## V2.4a makes the day REAL for the agenda and for nothing else: a booking with
## travel occupies a block of days -- departure, the meeting, the return -- and
## overlapping blocks are refused, which is scarcity by OCCUPANCY rather than by
## a ceiling. U6a's deleted currency stays deleted on the author's call; what
## replaced it is physical rather than legal, the very distinction U6a named when
## it cut the constant. This file still computes no price: the entry arrives
## carrying `travel_days` (Diplomacy.travel_days() at booking time), and the
## leaf rule survives -- the scheduler spans blocks and refuses overlaps without
## knowing where Rome is or why it is four days away.
##
## THIS FILE PRELOADS NO OTHER SYSTEM, and tests/test_calendar.gd asserts it
## rather than leaving it to this comment. due() hands the orchestrator a list of
## entries and the orchestrator fires the verb. There is no preload CYCLE here --
## nothing would ever need to reach back into Calendar, so six preloads would
## compile -- so the bar is docs/cabinet-model.md's rather than the compiler's:
## composing two systems' effects is the orchestrator's job, not one system
## reaching into another. diplomacy.gd preloads downward because it OWNS those
## effects; a scheduler owns none of them, and would otherwise become the widest
## dependency in src/sim/ while having the narrowest job.

const K = preload("res://src/sim/calendar_constants.gd")


## A booking's identity is its VERB, not its date -- one state visit to Germany
## in flight, not twelve booked on twelve days. Derived rather than stored, the
## same move Defence.allies() makes for an alliance: an id counter would be a
## second serialised field whose absent value (0) collides with every existing
## entry after a reload.
static func verb_key(entry: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [
		String(entry.get("kind", "")),
		String(entry.get("action_id", "")),
		String(entry.get("target_id", "")),
		String(entry.get("law_id", "")),
		String(entry.get("portfolio", "")),
	]


## A comparable stamp. Ordering dates as integers rather than comparing three
## fields in every caller is what keeps due()'s "<=" honest below.
static func ordinal(year: int, month: int, day: int) -> int:
	return year * 10000 + month * 100 + day


static func entry_ordinal(entry: Dictionary) -> int:
	return ordinal(int(entry.get("year", 0)), int(entry.get("month", 0)), int(entry.get("day", 1)))


## Build an entry. `person_id` was carried by U6a written by nobody, against the
## possibility that U6b would key appointments on named individuals and have to
## re-key the register. **It did not**, and the reason is the same argument that
## shrank the session: a person is the FACE of a target that already exists, so
## booking a state visit to Germany IS booking its leader. One act, one key.
##
## So `verb_key()` above is untouched, `person_id` stays out of it, and the field
## is a derived LABEL the diary prints -- passed in by the caller that knows the
## target, since src/sim/calendar.gd preloads nothing and cannot resolve one.
## Two bookings differing only in `person_id` are still the same verb, and
## tests/test_calendar.gd asserts exactly that rather than leaving it to this
## comment.
static func make_entry(
	kind: String, year: int, month: int, day: int,
	action_id := "", target_id := "", law_id := "",
	portfolio := "", party_id := "", person_id := "", travel_days := 0
) -> Dictionary:
	return {
		"kind": kind,
		"year": year,
		"month": month,
		"day": day,
		"action_id": action_id,
		"target_id": target_id,
		"law_id": law_id,
		"portfolio": portfolio,
		"party_id": party_id,
		"person_id": person_id,
		"travel_days": travel_days,
		"status": K.STATUS_BOOKED,
	}


## --- booking ---------------------------------------------------------------

static func can_book(state, entry: Dictionary) -> bool:
	return refusal_reason(state, entry).is_empty()


## The can_book()/refusal_reason() pair dissolution.gd established, so a panel
## never re-derives the rule it is greying a button for.
static func refusal_reason(state, entry: Dictionary) -> String:
	if not K.KINDS.has(String(entry.get("kind", ""))):
		return "not a bookable kind of act"

	var now := ordinal(state.year, state.month, int(state.day))
	var when := entry_ordinal(entry)
	if when < now:
		return "that date has passed"

	var horizon := _add_months(state.year, state.month, K.BOOKING_HORIZON_MONTHS)
	if when > ordinal(int(horizon["year"]), int(horizon["month"]), 31):
		return "further ahead than %d months" % K.BOOKING_HORIZON_MONTHS

	var key := verb_key(entry)
	for e in state.appointments:
		if String(e.get("status", "")) != K.STATUS_BOOKED:
			continue
		if verb_key(e) == key:
			return "already booked for %s" % _date_text(e)

	if state.appointments.size() >= K.MAX_APPOINTMENTS:
		return "the diary is full"

	# V2.4a. The block checks need real day numbers on BOTH sides. A state with
	# no date on it (new_game() leaves year/month at 0 -- the clock owns the
	# date) is a degenerate fixture, not a played game, and the checks are
	# skipped for it exactly because refusing a booking on a date the fixture
	# cannot express would be a confident lie. The old checks above already
	# passed, on the tolerant integer ordinal.
	var state_date_ok: bool = state.year >= 1 and state.month >= 1 and state.month <= 12
	if state_date_ok:
		# Departure is travel_days before the meeting, and a journey cannot be
		# booked to leave before today -- the meeting may be months out while
		# the flight is tonight, which is the one date the PLAYER cannot
		# actually choose. Day numbers rather than raw ordinals, because
		# subtracting from an ordinal is a decimal lie the day it crosses a
		# month boundary.
		var now_dn := _to_day_number(state.year, state.month, int(state.day))
		var meet_dn := _to_day_number(
			int(entry.get("year", 0)), int(entry.get("month", 0)), int(entry.get("day", 1))
		)
		if meet_dn - int(entry.get("travel_days", 0)) < now_dn:
			return "the journey would have to leave in the past"

		# One thing at a time. The refusal IS the scarcity: U6a cut the day
		# budget because a ceiling priced against legality binds in every
		# month, and an overlap is not priced against legality -- two blocks
		# cannot share a day for the same reason two presidents cannot share a
		# train. This, not a constant, is what makes the day a resource.
		var start_dn := meet_dn - int(entry.get("travel_days", 0))
		var end_dn := meet_dn + int(entry.get("travel_days", 0))
		for e in state.appointments:
			if String(e.get("status", "")) != K.STATUS_BOOKED:
				continue
			var other_meet := _to_day_number(
				int(e.get("year", 0)), int(e.get("month", 0)), int(e.get("day", 1))
			)
			var other_travel := int(e.get("travel_days", 0))
			if start_dn <= other_meet + other_travel and other_meet - other_travel <= end_dn:
				return "those days are already taken -- %s" % _date_text(e)

	return ""


## The player command, the Budget.commit() / Legislature.propose() shape.
## Returns {"ok": bool, "error": String} rather than pushing an error, because
## the panel prints the reason and the headless tests assert on it.
static func book(state, entry: Dictionary) -> Dictionary:
	var reason := refusal_reason(state, entry)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	state.appointments.append(entry.duplicate(true))
	return {"ok": true, "error": ""}


## Cancelling is free and leaves no trace. A cancelled booking is REMOVED rather
## than marked, because the diary's past is a record of what happened and an act
## the player thought better of never happened.
static func cancel(state, key: String) -> bool:
	for i in range(state.appointments.size()):
		var e: Dictionary = state.appointments[i]
		if String(e.get("status", "")) == K.STATUS_BOOKED and verb_key(e) == key:
			state.appointments.remove_at(i)
			return true
	return false


## --- resolution ------------------------------------------------------------

## Everything booked on or BEFORE the given date. The "<=" rather than "==" is
## load-bearing: a save reloaded past a booking's date, or a clock advanced more
## than a day in one step, must still fire it. An appointment that can be
## stranded forever is a command the player issued and the game silently ate.
static func due(state, year: int, month: int, day: int) -> Array:
	var now := ordinal(year, month, day)
	var out := []
	for e in state.appointments:
		if String(e.get("status", "")) != K.STATUS_BOOKED:
			continue
		if entry_ordinal(e) <= now:
			out.append(e)
	return out


## The orchestrator reports back what the verb did. Kept separate from due() so
## that firing and recording are two steps -- a system that marked an entry done
## before the command ran would lose the act on any failure inside it.
static func resolve(state, key: String, ok: bool) -> void:
	for e in state.appointments:
		if String(e.get("status", "")) == K.STATUS_BOOKED and verb_key(e) == key:
			e["status"] = K.STATUS_DONE if ok else K.STATUS_REFUSED
			return


## Prunes resolved entries older than the window the strip can reach. The
## register is the diary's whole memory, so this is what keeps a save file
## finite -- there is no other accumulator here.
static func tick_month(state) -> void:
	var cutoff := _add_months(state.year, state.month, -K.RESOLVED_KEPT_MONTHS)
	var floor_ord := ordinal(int(cutoff["year"]), int(cutoff["month"]), 1)
	# Typed, because GameState.appointments is Array[Dictionary] and GDScript
	# refuses an untyped Array on assignment -- silently at parse time, loudly
	# sixty times a second at run time.
	var kept: Array[Dictionary] = []
	for e in state.appointments:
		if String(e.get("status", "")) == K.STATUS_BOOKED:
			kept.append(e)
		elif entry_ordinal(e) >= floor_ord:
			kept.append(e)
	state.appointments = kept


## --- reading ---------------------------------------------------------------

static func booked(state) -> Array:
	var out := []
	for e in state.appointments:
		if String(e.get("status", "")) == K.STATUS_BOOKED:
			out.append(e)
	return out


static func entries_in_month(state, year: int, month: int) -> Array:
	var out := []
	for e in state.appointments:
		if int(e.get("year", 0)) == year and int(e.get("month", 0)) == month:
			out.append(e)
	out.sort_custom(func(a, b): return entry_ordinal(a) < entry_ordinal(b))
	return out


## --- the day, V2.4a ---------------------------------------------------------

## Days in one month, off the same day-number arithmetic the block spans use —
## one public read so the booking form's day picker and the tests clamp against
## the scheduler's own calendar rather than a second copy of a leap-year rule.
## A degenerate month reads 31: there is no true answer to invent, and 31 is
## the form's own long-standing upper bound.
static func days_in_month(year: int, month: int) -> int:
	if month < 1 or month > 12:
		return 31
	return _to_day_number(year, month + 1, 1) - _to_day_number(year, month, 1)


## The block a booking occupies, as a real date either side of the meeting.
## Departure and return cross month boundaries -- Rome is four days out and the
## 3rd of a month is not always four days after the 30th of the one before --
## so the answer is a date Dictionary, not an integer ordinal.
static func departure(entry: Dictionary) -> Dictionary:
	var dn := _to_day_number(
		int(entry.get("year", 0)), int(entry.get("month", 0)), int(entry.get("day", 1))
	) - int(entry.get("travel_days", 0))
	return _from_day_number(dn)


static func arrival_home(entry: Dictionary) -> Dictionary:
	var dn := _to_day_number(
		int(entry.get("year", 0)), int(entry.get("month", 0)), int(entry.get("day", 1))
	) + int(entry.get("travel_days", 0))
	return _from_day_number(dn)


## One row per day of one month, classifying what occupies it: {"day", "travel",
## "meeting", "key"}. The ribbon's whole read, so the surface owns no rule about
## spans at all. A day inside a block's legs but not on its meeting day is
## travel; the meeting day itself is the only solid cell, which is the visual
## argument docs/tiers/v2.md section 4 makes -- travel is time you spend without
## choosing it.
##
## Every entry in the register counts, resolved ones included: a kept meeting
## still occupied its day, and the diary's past is a record rather than a blank.
## With the overlap refusal above at most one block owns any day; an old save
## from before V2.4a can hold same-day entries, and the honest rendering of
## those is the AND of both flags rather than a pick.
static func day_cells(state, year: int, month: int) -> Array:
	if month < 1 or month > 12:
		return []
	var first_dn := _to_day_number(year, month, 1)
	var last_dn := _to_day_number(year, month + 1, 1) - 1

	var cells: Array = []
	for d in range(1, last_dn - first_dn + 2):
		cells.append({"day": d, "travel": false, "meeting": false, "key": ""})

	for e in state.appointments:
		var meet_dn := _to_day_number(
			int(e.get("year", 0)), int(e.get("month", 0)), int(e.get("day", 1))
		)
		var travel := int(e.get("travel_days", 0))
		var lo := maxi(meet_dn - travel, first_dn)
		var hi := mini(meet_dn + travel, last_dn)
		for dn in range(lo, hi + 1):
			var idx: int = dn - first_dn
			if idx < 0 or idx >= cells.size():
				continue
			if dn == meet_dn:
				cells[idx]["meeting"] = true
			else:
				cells[idx]["travel"] = true
			if String(cells[idx]["key"]) == "":
				cells[idx]["key"] = verb_key(e)

	return cells


## Days since 1970-01-01, via Time's own proleptic-Gregorian conversion. A
## first draft hand-rolled the days-from-civil pair and was off by one at the
## month boundary -- the whole reason this file buys no clever arithmetic: the
## engine's conversion is exact, and the scheduler's leaf rule bars SYSTEM
## preloads, not the engine singleton that owns what a date is.
static func _to_day_number(year: int, month: int, day: int) -> int:
	return int(Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day,
		"hour": 0, "minute": 0, "second": 0,
	})) / 86400


static func _from_day_number(n: int) -> Dictionary:
	var d := Time.get_datetime_dict_from_unix_time(n * 86400)
	return {"year": int(d["year"]), "month": int(d["month"]), "day": int(d["day"])}


## Every date the game already knows about, as data. Reads plain fields and calls
## no system, which is what stops the diary drifting from the thing it is a diary
## of. The panel does the naming -- an id here, a label there -- so src/sim/ owns
## no presentation.
##
## Each row: {"kind", "year", "month", "day", "ref"}. `ref` is whatever the row
## points at (a law id, an "action_id|TARGET" cooldown key) or "".
static func fixed_dates(state) -> Array:
	var ns = state.player()
	var out := []

	if ns.next_election_year > 0:
		out.append(_fixed(K.FIXED_ELECTION, ns.next_election_year, ns.next_election_month, ""))
	if ns.next_ep_election_year > 0:
		out.append(_fixed(K.FIXED_EP_ELECTION, ns.next_ep_election_year, ns.next_ep_election_month, ""))
	if ns.has_executive and ns.next_executive_year > 0:
		out.append(_fixed(K.FIXED_EXECUTIVE, ns.next_executive_year, ns.next_executive_month, ""))
	if ns.head_of_state_next_year > 0:
		out.append(_fixed(
			K.FIXED_HEAD_OF_STATE, ns.head_of_state_next_year, ns.head_of_state_next_month, ""
		))

	var bloc: Dictionary = state.bloc
	var months_to_next := int(bloc.get("months_to_next", 0))
	if months_to_next > 0:
		out.append(_fixed_in(state, K.FIXED_COUNCIL_PROPOSAL, months_to_next, ""))
	var pending = bloc.get("pending", {})
	if typeof(pending) == TYPE_DICTIONARY and not pending.is_empty():
		out.append(_fixed_in(
			state, K.FIXED_COUNCIL_VOTE, int(pending.get("months_left", 0)),
			String(pending.get("id", ""))
		))

	if ns.dissolution_lockout_remaining > 0:
		out.append(_fixed_in(
			state, K.FIXED_DISSOLUTION, ns.dissolution_lockout_remaining, ""
		))

	# The densest source by far, and the one U6a's probe found reading zero until
	# it was pointed at a player who actually acts: every act the player has taken
	# is a date they can act again, and until now the game only ever said "in 14
	# months" on a panel the player had to be standing on to see.
	for k in ns.diplo_cooldown_months.keys():
		var months := int(ns.diplo_cooldown_months[k])
		if months > 0:
			out.append(_fixed_in(state, K.FIXED_COOLDOWN, months, String(k)))
	for k in ns.law_cooldown_months.keys():
		var months := int(ns.law_cooldown_months[k])
		if months > 0:
			out.append(_fixed_in(state, K.FIXED_COOLDOWN, months, String(k)))

	# V1.6f, and the reason it fits here rather than needing a scheduler of its own is
	# the whole of why V1.6f did not write one. A project's register entry counts
	# MONTHS REMAINING, the idiom every countdown above already uses, so this is one
	# more plain-field read and this file still preloads nothing -- it does not know
	# what a project costs, what it will buy or whether it can be abandoned, only when
	# it lands. GameState.appointments is a register of deferred COMMANDS and a project
	# is a commitment in flight; the diary shows both and owns neither.
	for pid in ns.projects.keys():
		var entry = ns.projects[pid]
		if typeof(entry) != TYPE_DICTIONARY or bool(entry.get("done", false)):
			continue
		var left := int(entry.get("months_left", 0))
		if left > 0:
			out.append(_fixed_in(state, K.FIXED_PROJECT, left, String(pid)))

	# V1.7c, and it needed no preload for V1.6f's reason directly above: a pending
	# referendum counts months_left, which is the idiom every row here already uses.
	# This file does not know what the question is, what it costs or whether it can be
	# called off -- only when the country votes.
	if not ns.referendum_pending.is_empty():
		var ref_left := int(ns.referendum_pending.get("months_left", 0))
		if ref_left > 0:
			out.append(_fixed_in(
				state, K.FIXED_REFERENDUM, ref_left,
				String(ns.referendum_pending.get("law_id", ""))
			))

	# V1.8, and it needed no preload for V1.6f's and V1.7c's reason a third time. What
	# this row carries is not an id but the event's own NAME, copied into the register
	# at announcement -- so unlike the referendum row above, calendar_panel.gd does not
	# have to look anything up to print it.
	if not ns.event_pending.is_empty():
		var event_left := int(ns.event_pending.get("months_left", 0))
		if event_left > 0:
			out.append(_fixed_in(
				state, K.FIXED_EVENT, event_left,
				String(ns.event_pending.get("event_name", ""))
			))

	out.sort_custom(func(a, b): return entry_ordinal(a) < entry_ordinal(b))
	return out


## Fixed dates and bookings together, from the current month forward, over the
## window the strip draws. The one call a surface needs.
static func upcoming(state, months: int) -> Array:
	var limit := _add_months(state.year, state.month, months)
	var limit_ord := ordinal(int(limit["year"]), int(limit["month"]), 31)
	var now_ord := ordinal(state.year, state.month, 1)

	var out := []
	for row in fixed_dates(state):
		var o := entry_ordinal(row)
		if o >= now_ord and o <= limit_ord:
			out.append(row)
	# EVERY appointment in the window, not only the unfired ones. booked() here was
	# a bug the first frame caught: the strip draws a resolved entry differently
	# from a booked one and offers it no cancel button, and none of that could ever
	# run because nothing resolved ever reached the panel. A diary whose past goes
	# blank the moment an act is kept is a to-do list.
	for e in state.appointments:
		var o := entry_ordinal(e)
		if o >= now_ord and o <= limit_ord:
			out.append(e)

	out.sort_custom(func(a, b): return entry_ordinal(a) < entry_ordinal(b))
	return out


## What the game knows about BEYOND the strip, nearest first.
##
## This exists because of a measurement, not because a year felt short. U6a's
## probe reported 31 % of months carrying a dated event over fourteen years, and
## then the panel test found the sharper version of the same fact: a NEW GAME's
## next twelve months are completely empty. France's presidential election is 16
## months out, the council's first proposal 18, the legislative election 41 --
## and cooldowns, much the densest source, do not exist until the player has
## acted. So the sparseness is front-loaded exactly where a first impression is
## formed, and a strip alone would open blank on the one day every player sees.
##
## The plan pre-committed the response to a thin diary as CONTENT OR SHAPE rather
## than a constant, and widening BOOKING_HORIZON_MONTHS would have been the
## constant: it also bounds booking, so a horizon long enough to catch a
## four-year-out election would let the player book a state visit into the next
## term. This is the shape instead.
static func later(state, months: int, cap: int) -> Array:
	var limit := _add_months(state.year, state.month, months)
	var limit_ord := ordinal(int(limit["year"]), int(limit["month"]), 31)

	var out := []
	for row in fixed_dates(state):
		if entry_ordinal(row) > limit_ord:
			out.append(row)
		if out.size() >= cap:
			break
	return out


## --- helpers ---------------------------------------------------------------

static func _fixed(kind: String, year: int, month: int, ref: String) -> Dictionary:
	return {"kind": kind, "year": year, "month": month, "day": 1, "ref": ref}


## A countdown of N months lands on day 1 of the month N ahead, because that is
## when Clock emits month_elapsed and the whole monthly pipeline runs.
static func _fixed_in(state, kind: String, months: int, ref: String) -> Dictionary:
	var d := _add_months(state.year, state.month, months)
	return _fixed(kind, int(d["year"]), int(d["month"]), ref)


static func _add_months(year: int, month: int, delta: int) -> Dictionary:
	var total := year * 12 + (month - 1) + delta
	return {"year": total / 12, "month": total % 12 + 1}


static func _date_text(entry: Dictionary) -> String:
	return "%02d/%02d/%d" % [
		int(entry.get("day", 1)), int(entry.get("month", 1)), int(entry.get("year", 0)),
	]
