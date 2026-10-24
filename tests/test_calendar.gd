extends SceneTree

## U6a. The diary: what it refuses, what it fires, what it forgets, and what it
## reads off state the game already carries. Model: docs/calendar-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen:
##
##   - src/sim/calendar.gd PRELOADS NO OTHER SYSTEM. Asserted by reading the file
##     rather than argued in a comment, because the whole reason due() returns data
##     instead of firing a verb is that a scheduler reaching into three systems is
##     what docs/engine-decision.md Rule 3 exists to stop. A later session adding
##     one preload turns this red and has to come and say why.
##   - a booking is NEVER STRANDED. due() reads "<=" rather than "==", so a save
##     reloaded past a date, or a clock stepped more than a day, still fires it. An
##     appointment that can be silently eaten is a command the player issued and
##     the game lost.
##   - the register is BOUNDED. tick_month() prunes resolved entries and the cap
##     refuses rather than dropping, so a save file cannot grow without limit
##     however the player behaves.
##   - a booking commits NOTHING when it is made. The state a booking would change
##     is bit-identical before and after book(), which is what makes booking
##     optional rather than a deferral that costs something.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Orgs = preload("res://src/sim/orgs.gd")

const PLAYER := "FRA"
const PARTNER := "DEU"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_no_system_preloads()
	_check_book_and_refuse()
	_check_booking_commits_nothing()
	_check_due_is_never_stranded()
	_check_resolve_and_prune()
	_check_cap_refuses()
	_check_cancel()
	_check_fixed_dates()
	_check_upcoming_window()
	_check_person_is_a_label_not_an_identity()
	_check_travel_block_spans()
	_check_overlap_refused()
	_check_a_stale_day_reads_as_the_months_last()
	_check_past_departure_refused()
	_check_absent_travel_days_round_trips()
	_check_december_rollover()
	_finish()


## U6a declared `person_id` unread so U6b could key appointments on people
## without a second SAVE_VERSION bump. **U6b did not need it**, and this is where
## that decision is pinned rather than left to a comment.
##
## A person is the FACE of a target that already exists -- booking a state visit
## to Germany IS booking its leader -- so a person cannot change what an
## appointment is. verb_key() therefore stays out of it, and two entries that
## differ ONLY in person_id are the same verb: the second is refused while the
## first is in flight, exactly as two identical ones are.
##
## If a later session makes a person part of an appointment's identity, this
## turns red and it has to come and say why -- and it will owe a bump, because
## every booking in an existing save would silently re-key.
func _check_person_is_a_label_not_an_identity() -> void:
	var state = _fresh()
	var when := _months_ahead(state, 3)

	var plain := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 14, "state_visit", PARTNER
	)
	var with_person := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 14, "state_visit", PARTNER,
		"", "", "", "DEU_vogler"
	)
	if Calendar.verb_key(plain) != Calendar.verb_key(with_person):
		_fail("person_id changed an appointment's identity: '%s' vs '%s'" % [
			Calendar.verb_key(plain), Calendar.verb_key(with_person),
		])

	if not bool(Calendar.book(state, with_person)["ok"]):
		_fail("a booking carrying a person was refused")
	if Calendar.can_book(state, plain):
		_fail("the same verb was bookable again with the person stripped -- a label must not open a second slot")

	# And cancelling by the key derived from the OTHER one still finds it, which
	# is the practical consequence: a panel need not know the person to cancel.
	Calendar.cancel(state, Calendar.verb_key(plain))
	if not Calendar.booked(state).is_empty():
		_fail("cancelling by a key derived without the person left the booking in place")


## V2.4a. The block is real dates, not arithmetic on the meeting's fields:
## departure and arrival cross month boundaries by construction (a 15th with
## four days of travel either side is fine, a 2nd is not), so the span helpers
## are pinned against a crossing and a non-crossing month. The scheduler still
## computes no price -- travel_days arrives ON the entry -- which is the leaf
## rule, asserted in the negative below.
func _check_travel_block_spans() -> void:
	var state = _fresh()
	var when := _months_ahead(state, 2)

	# A meeting on the 2nd with 3 days of travel departs in the PREVIOUS month
	# (two days out is not enough to cross; three is) and returns on the 5th.
	var entry := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 2, "state_visit", PARTNER,
		"", "", "", "", 3
	)
	var depart: Dictionary = Calendar.departure(entry)
	if int(depart["month"]) != int(when["month"]) - 1 or int(depart["day"]) != Calendar.days_in_month(int(when["year"]), int(when["month"]) - 1) - 1:
		_fail("departure across a month boundary came back %s (expected the last day of the previous month)" % [str(depart)])
	var home: Dictionary = Calendar.arrival_home(entry)
	if int(home["month"]) != int(when["month"]) or int(home["day"]) != 5:
		_fail("arrival_home came back %s (expected the 5th)" % [str(home)])

	# A meeting on the 15th with 4 days of travel: the day cells classify the
	# legs and the meeting differently, which is the whole visual argument --
	# travel is hatched, the meeting is solid.
	var mid := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 15, "state_visit", "ITA",
		"", "", "", "", 4
	)
	state.appointments.append(mid.duplicate(true))
	var cells: Array = Calendar.day_cells(state, int(when["year"]), int(when["month"]))
	if cells.size() != Calendar.days_in_month(int(when["year"]), int(when["month"])):
		_fail("day_cells returned %d cells for the month" % cells.size())
	var day15: Dictionary = cells[14]
	if not bool(day15["meeting"]):
		_fail("the meeting day did not read as a meeting")
	if bool(day15["travel"]):
		_fail("the meeting day also read as travel -- the two marks are exclusive on the day itself")
	var day12: Dictionary = cells[11]
	if not bool(day12["travel"]) or bool(day12["meeting"]):
		_fail("an outbound leg day did not read as travel-only")

	# The leaf rule, read off the source like the preload one: the scheduler
	# must not derive a price, only store one.
	var file := FileAccess.open("res://src/sim/calendar.gd", FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	for line in text.split("
"):
		if line.strip_edges().begins_with("#"):
			continue
		if line.contains("KM_PER_DAY") or line.contains("haversine"):
			_fail("calendar.gd computes a travel price -- the leaf rule says the entry carries it: %s" % line.strip_edges())


## V2.4a. Occupancy IS the scarcity; there is no ceiling to bind instead. So
## the refusal rule is the machine, and it is asserted on both orders of the
## pair: a second block inside the first's legs refuses, and the first refuses
## against a booked second, in a DIFFERENT month if the legs reach that far.
## DECEMBER, where the next month is `month + 1` = 13 and Time refuses it outright.
## Both readers were wrong TOGETHER -- days_in_month() answered -20788 and
## day_cells() answered an empty array -- which is exactly why
## _check_travel_block_spans()'s cells-against-days_in_month assertion stayed green
## through the whole bug: two wrong answers agreeing with each other. So every
## number here is absolute, and the loop covers all twelve months rather than the
## one the run happens to be in, which is the property the suite was missing when a
## five-minute play session found this and fourteen simulated years did not.
func _check_december_rollover() -> void:
	var state = _fresh()
	var lengths := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	for m in range(1, 13):
		var expected: int = lengths[m - 1]
		var days: int = Calendar.days_in_month(2026, m)
		if days != expected:
			_fail("days_in_month(2026, %d) = %d, expected %d" % [m, days, expected])
		var cells: Array = Calendar.day_cells(state, 2026, m)
		if cells.size() != expected:
			_fail("day_cells(2026, %d) gave %d cells, expected %d" % [m, cells.size(), expected])

	# The rollover must not have been bought by hard-coding twelve lengths: a leap
	# February is the other thing Time's own conversion is here to get right.
	if Calendar.days_in_month(2028, 2) != 29:
		_fail("days_in_month(2028, 2) = %d, expected 29 in a leap year"
			% Calendar.days_in_month(2028, 2))


func _check_overlap_refused() -> void:
	var state = _fresh()
	var when := _months_ahead(state, 2)

	var first := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 15, "state_visit", PARTNER,
		"", "", "", "", 4
	)
	var result: Dictionary = Calendar.book(state, first)
	if not bool(result["ok"]):
		_fail("the first block was refused: %s" % String(result["error"]))

	# Inside the legs: the 16th, within four days either side of the 15th.
	var second := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 16, "state_visit", "ITA",
		"", "", "", "", 2
	)
	result = Calendar.book(state, second)
	if bool(result["ok"]):
		_fail("a booking inside another's travel legs was accepted")
	if not String(result["error"]).begins_with("those days are already taken"):
		_fail("an overlap refusal carried the wrong reason: %s" % String(result["error"]))

	# A day-only booking on the meeting day itself also conflicts.
	var third := Calendar.make_entry(
		K.KIND_LAW, int(when["year"]), int(when["month"]), 15, "", "", "income_tax_cut"
	)
	result = Calendar.book(state, third)
	if bool(result["ok"]):
		_fail("a day-only booking on an occupied day was accepted")

	# But the day after the block ends is free, and a law there books.
	var fourth := Calendar.make_entry(
		K.KIND_LAW, int(when["year"]), int(when["month"]), 20, "", "", "income_tax_cut"
	)
	result = Calendar.book(state, fourth)
	if not bool(result["ok"]):
		_fail("a booking on the day after the block was refused: %s" % String(result["error"]))


## V2.4a. The one date the player cannot choose is the departure. A meeting
## booked too soon for its own travel is refused -- and the meeting WITHOUT
## travel (a law, a reshuffle) is never refused on today, because there is no
## journey to have left late.
func _check_past_departure_refused() -> void:
	var state = _fresh()

	# Booked on the 1st, a meeting on the 2nd of the SAME month with 3 days of
	# travel would have to have left on the 30th of the month before.
	var entry := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(state.year), int(state.month), 2, "state_visit", PARTNER,
		"", "", "", "", 3
	)
	var result: Dictionary = Calendar.book(state, entry)
	if bool(result["ok"]):
		_fail("a journey departing before today was accepted (booked on day 1, meeting on the 2nd, 3 days out)")
	if not String(result["error"]).begins_with("the journey would have to leave in the past"):
		_fail("a past-departure refusal carried the wrong reason: %s" % String(result["error"]))

	var same_day := Calendar.make_entry(
		K.KIND_LAW, int(state.year), int(state.month), 1, "", "", "income_tax_cut"
	)
	if not Calendar.can_book(state, same_day):
		_fail("a same-day booking without travel was refused -- there is no journey to leave late")


## V5.2b, Interface's find. The month can advance before the day does: main.gd
## moves state.month at the close and sets state.day on the next day tick, so a
## read made during the close sees April with day 31. The day number of an
## impossible date is an engine ERROR (the runner fails on it) and a wrong
## answer; the stale day reads as the month's last day instead.
func _check_a_stale_day_reads_as_the_months_last() -> void:
	var state = _fresh()
	state.year = 2026
	state.month = 4
	state.day = 31
	var last_day := Calendar.make_entry(K.KIND_LAW, 2026, 4, 30, "", "", "income_tax_cut")
	if not Calendar.can_book(state, last_day):
		_fail("with a stale day 31 in April, the 30th read as %s rather than today" % Calendar.refusal_reason(state, last_day))
	var next_month := Calendar.make_entry(K.KIND_DIPLOMATIC, 2026, 5, 3, "state_visit", PARTNER, "", "", "", "", 3)
	if not Calendar.can_book(state, next_month):
		_fail("with a stale day 31 in April, a visit leaving on 30 April read as %s" % Calendar.refusal_reason(state, next_month))


## V2.4a. The back-compat half of the no-bump argument, pinned the way
## test_save_load.gd pins its absences: an entry from a version-27 save carries
## no travel_days at all, and it must read as a DAY-ONLY block -- bookable,
## spanning one day, refusing an overlap on its day and no others.
func _check_absent_travel_days_round_trips() -> void:
	var state = _fresh()
	var when := _months_ahead(state, 2)

	# Written the way from_dict rehydrates a version-27 entry: no travel_days
	# key in the dictionary at all.
	var old_entry := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 15, "state_visit", PARTNER
	)
	old_entry.erase("travel_days")
	state.appointments.append(old_entry)

	var cells: Array = Calendar.day_cells(state, int(when["year"]), int(when["month"]))
	if not bool(cells[14]["meeting"]):
		_fail("a version-27 entry's meeting day did not read as a meeting")
	if bool(cells[13]["travel"]) or bool(cells[15]["travel"]):
		_fail("a version-27 entry grew travel legs it never had")
	if bool(cells[14]["travel"]):
		_fail("a version-27 entry's meeting day read as travel")

	# And the overlap rule still protects its day against a new day-only block.
	var law := Calendar.make_entry(
		K.KIND_LAW, int(when["year"]), int(when["month"]), 15, "", "", "income_tax_cut"
	)
	if Calendar.can_book(state, law):
		_fail("a new booking landed on a version-27 entry's day")


## The property the whole file's shape exists to keep. Read the source, not the
## behaviour: a preload that is present but unused still makes this the widest
## dependency in src/sim/ while having the narrowest job.
func _check_no_system_preloads() -> void:
	var file := FileAccess.open("res://src/sim/calendar.gd", FileAccess.READ)
	if file == null:
		_fail("could not read src/sim/calendar.gd to check its preloads")
		return
	var text := file.get_as_text()
	file.close()

	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("const ") or not trimmed.contains("preload("):
			continue
		# Its own constants file is the one allowed dependency -- every other
		# *_constants.gd pairing in src/sim/ has exactly this shape.
		if trimmed.contains("calendar_constants.gd"):
			continue
		_fail("calendar.gd preloads something: `%s` -- the scheduler must not know what it schedules" % trimmed)


func _check_book_and_refuse() -> void:
	var state = _fresh()
	var when := _months_ahead(state, 2)

	var good := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 14, "state_visit", PARTNER
	)
	var result: Dictionary = Calendar.book(state, good)
	if not bool(result["ok"]):
		_fail("a plain booking two months out was refused: %s" % String(result["error"]))
	if state.appointments.size() != 1:
		_fail("book() left %d entries, expected 1" % state.appointments.size())

	# The same VERB again, on a different day. Refused: one state visit to Germany
	# in flight, not twelve booked across twelve days. This is what makes the
	# derived verb_key a usable identity and lets cancel() work without an id
	# counter -- which would have been a second serialised field whose absent
	# value collides with every existing entry after a reload.
	var twin := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 21, "state_visit", PARTNER
	)
	if Calendar.can_book(state, twin):
		_fail("the same verb was bookable twice while one was still in flight")

	var past := Calendar.make_entry(
		K.KIND_DIPLOMATIC, state.year - 1, 6, 1, "state_visit", "ITA"
	)
	if Calendar.refusal_reason(state, past) != "that date has passed":
		_fail("a date in the past was not refused with the reason a panel prints")

	var far := _months_ahead(state, K.BOOKING_HORIZON_MONTHS + 2)
	var distant := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(far["year"]), int(far["month"]), 1, "state_visit", "ITA"
	)
	if Calendar.can_book(state, distant):
		_fail("a booking past the %d-month horizon was allowed" % K.BOOKING_HORIZON_MONTHS)

	var nonsense := Calendar.make_entry("summit", state.year, state.month, 28)
	if Calendar.can_book(state, nonsense):
		_fail("a kind that is not in KINDS was bookable")


## Booking is OPTIONAL, and this is the assertion that keeps it so. If making a
## booking moved anything, a deferred act would cost something the act-now button
## does not, and U6a would have shipped the strictly-worse button V1.3c and V1.3d
## each had to be taught by a probe.
func _check_booking_commits_nothing() -> void:
	var state = _fresh()
	var before := Budget.snapshot(state)
	before.merge(Opinion.snapshot(state))
	var relations_before: Dictionary = state.relations.duplicate(true)

	var when := _months_ahead(state, 1)
	Calendar.book(state, Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 9, "state_visit", PARTNER
	))

	var after := Budget.snapshot(state)
	after.merge(Opinion.snapshot(state))
	for key in before.keys():
		if before[key] != after.get(key):
			_fail("booking moved %s: %s -> %s" % [key, before[key], after.get(key)])
	if state.relations != relations_before:
		_fail("booking moved relations before the act was ever carried out")


## The "<=" in due(), which is the difference between a diary and a trap.
func _check_due_is_never_stranded() -> void:
	var state = _fresh()
	var when := _months_ahead(state, 1)
	Calendar.book(state, Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 10, "state_visit", PARTNER
	))

	if not Calendar.due(state, state.year, state.month, 28).is_empty():
		_fail("an appointment fired before its date")

	# The day itself.
	if Calendar.due(state, int(when["year"]), int(when["month"]), 10).size() != 1:
		_fail("an appointment did not fire on its own date")

	# A whole year late -- a save reloaded long past the date, or a clock stepped
	# in something other than single days. It must still fire.
	if Calendar.due(state, int(when["year"]) + 1, int(when["month"]), 10).size() != 1:
		_fail("an appointment overshot by a year was stranded rather than fired")


func _check_resolve_and_prune() -> void:
	var state = _fresh()
	var when := _months_ahead(state, 1)
	var entry := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 10, "state_visit", PARTNER
	)
	Calendar.book(state, entry)
	var key := Calendar.verb_key(entry)

	Calendar.resolve(state, key, true)
	if String(state.appointments[0]["status"]) != K.STATUS_DONE:
		_fail("resolve(ok) did not mark the entry done")
	if not Calendar.due(state, int(when["year"]), int(when["month"]), 10).is_empty():
		_fail("a resolved entry came back as due -- it would fire every day forever")

	# A resolved entry survives inside the window the strip can reach, and is
	# pruned once it cannot. The register is the diary's only memory, so this is
	# the whole of what keeps a save file finite.
	state.year = int(when["year"])
	state.month = int(when["month"])
	Calendar.tick_month(state)
	if state.appointments.size() != 1:
		_fail("a just-resolved entry was pruned while its own month was still on the strip")

	var later := _months_ahead(state, K.RESOLVED_KEPT_MONTHS + 2)
	state.year = int(later["year"])
	state.month = int(later["month"])
	Calendar.tick_month(state)
	if not state.appointments.is_empty():
		_fail("a resolved entry %d months old was not pruned" % (K.RESOLVED_KEPT_MONTHS + 2))

	# A BOOKED entry is never pruned however old it is, because an unfired
	# appointment is still a command the player issued.
	var stale = _fresh()
	Calendar.book(stale, Calendar.make_entry(
		K.KIND_DIPLOMATIC, stale.year, stale.month, 2, "state_visit", PARTNER
	))
	var far := _months_ahead(stale, K.RESOLVED_KEPT_MONTHS + 6)
	stale.year = int(far["year"])
	stale.month = int(far["month"])
	Calendar.tick_month(stale)
	if stale.appointments.size() != 1:
		_fail("an unfired booking was pruned -- the player's command was silently eaten")


## The cap REFUSES rather than dropping. A guard rail that silently discards the
## newest entry teaches the player their click did nothing.
func _check_cap_refuses() -> void:
	var state = _fresh()
	for i in range(K.MAX_APPOINTMENTS):
		state.appointments.append(Calendar.make_entry(
			K.KIND_LAW, state.year, state.month, 1, "", "", "filler_%d" % i
		))

	var when := _months_ahead(state, 1)
	var one_more := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 5, "state_visit", PARTNER
	)
	if Calendar.can_book(state, one_more):
		_fail("the diary accepted a booking past MAX_APPOINTMENTS")
	if Calendar.refusal_reason(state, one_more) != "the diary is full":
		_fail("the full diary did not give the reason a panel prints")
	if state.appointments.size() != K.MAX_APPOINTMENTS:
		_fail("a refused booking still changed the register")


func _check_cancel() -> void:
	var state = _fresh()
	var when := _months_ahead(state, 3)
	var entry := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 6, "state_visit", PARTNER
	)
	Calendar.book(state, entry)
	var key := Calendar.verb_key(entry)

	if not Calendar.cancel(state, key):
		_fail("cancel() did not find a booking that was there")
	if not state.appointments.is_empty():
		_fail("a cancelled booking left a trace -- an act thought better of never happened")
	if Calendar.cancel(state, key):
		_fail("cancel() reported success on an empty diary")

	# Once resolved, an entry is history and cannot be cancelled.
	Calendar.book(state, entry)
	Calendar.resolve(state, key, true)
	if Calendar.cancel(state, key):
		_fail("a resolved appointment was cancellable -- the past is not editable")


## The headline. Every one of these is state the game has carried for sessions
## with no surface that puts it on a timeline.
func _check_fixed_dates() -> void:
	var state = _fresh()
	var kinds := _fixed_kinds(state)

	if not kinds.has(K.FIXED_ELECTION):
		_fail("fixed_dates() did not report the legislative election")
	if not kinds.has(K.FIXED_EP_ELECTION):
		_fail("fixed_dates() did not report the European election")

	# A cooldown is the densest source by far, and U6a's probe read it as exactly
	# zero until it was pointed at a player who actually acts. Act, then look.
	# V3.3: actions[0] is whatever sorts first, and on the EU-29 roster that is an
	# act that carries no cooldown -- the assertion is about cooldowns, so the
	# helper executes the first action that actually creates one.
	var actions := Diplomacy.available(state, _loader.diplomatic_actions, PLAYER, PARTNER)
	if actions.is_empty():
		_fail("no diplomatic action was available to set a cooldown with")
		return
	var acted := false
	for action in actions:
		Diplomacy.execute(state, _loader.diplomatic_actions, action, PLAYER, PARTNER)
		if not state.player().diplo_cooldown_months.is_empty():
			acted = true
			break
	if not acted:
		_fail("no diplomatic action set a cooldown to put in the diary")
		return
	if not _fixed_kinds(state).has(K.FIXED_COOLDOWN):
		_fail("an act's own cooldown did not appear as a date the player can see")

	# Dated in the FUTURE, and by the number of months the cooldown actually
	# carries -- a diary that disagrees with the panel it is a diary of is worse
	# than no diary.
	var ns = state.player()
	var key: String = ns.diplo_cooldown_months.keys()[0]
	var months := int(ns.diplo_cooldown_months[key])
	var expected := _months_ahead(state, months)
	for row in Calendar.fixed_dates(state):
		if String(row["kind"]) != K.FIXED_COOLDOWN or String(row["ref"]) != key:
			continue
		if int(row["year"]) != int(expected["year"]) or int(row["month"]) != int(expected["month"]):
			_fail("a cooldown expiry was dated %d/%d, the cooldown says %d months" % [
				int(row["month"]), int(row["year"]), months,
			])


func _check_upcoming_window() -> void:
	var state = _fresh()
	var when := _months_ahead(state, 2)
	Calendar.book(state, Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(when["year"]), int(when["month"]), 12, "state_visit", PARTNER
	))

	var rows := Calendar.upcoming(state, K.BOOKING_HORIZON_MONTHS)
	if rows.is_empty():
		_fail("upcoming() returned nothing with an election and a booking both in range")

	var limit := _months_ahead(state, K.BOOKING_HORIZON_MONTHS)
	var limit_ord := Calendar.ordinal(int(limit["year"]), int(limit["month"]), 31)
	var floor_ord := Calendar.ordinal(state.year, state.month, 1)
	var sorted := true
	var previous := -1
	for row in rows:
		var o := Calendar.entry_ordinal(row)
		if o < floor_ord or o > limit_ord:
			_fail("upcoming() returned a row at %d, outside [%d, %d]" % [o, floor_ord, limit_ord])
		if o < previous:
			sorted = false
		previous = o
	if not sorted:
		_fail("upcoming() came back out of date order -- the strip draws it as given")

	var found := false
	for row in rows:
		if row.has("status") and String(row.get("action_id", "")) == "state_visit":
			found = true
	if not found:
		_fail("upcoming() dropped the player's own booking")


## --- helpers ---------------------------------------------------------------

func _fresh():
	var state = GameState.new_game(_loader, PLAYER)
	# One month of real ticking, so the council scheduler and every cooldown are
	# in the state a played game produces rather than the static new-game table.
	# V1.3f's own lesson, and U6a's probe made the same mistake once already.
	# V2.4a sets the YEAR too: new_game() leaves both at 0 (the clock owns the
	# date), and the day-number arithmetic the block spans use is era-based --
	# at year 0 every span comes back nonsense instead of failing loudly.
	state.year = 2026
	state.month = 2
	Economy.tick_month(state)
	Budget.tick_month(state)
	Orgs.tick_month(state, _loader)
	Opinion.tick_month(state)
	state.day = 1
	return state


func _fixed_kinds(state) -> Array:
	var out := []
	for row in Calendar.fixed_dates(state):
		if not out.has(String(row["kind"])):
			out.append(String(row["kind"]))
	return out


func _months_ahead(state, months: int) -> Dictionary:
	var total: int = state.year * 12 + (state.month - 1) + months
	return {"year": total / 12, "month": total % 12 + 1}


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_calendar: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
