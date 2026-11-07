extends SceneTree

## V5.3 b, band B5 (docs/design/v5.3-ab.md 4.3 and 4.4's opinion term): the address to the
## nation and the seats it moves. Headless.
##
##   - THE VERB takes the day, writes the register, prices the blocs against, and refuses
##     with no effect when the bill is not open or the diary is taken.
##   - THE SHIFT per bloc: toward, neutral, against, by standing and outlets; repetition
##     discounts what persuades and not what hardens.
##   - THE REGISTER fades over three months, on one bill, and survives a save.
##   - THE TERM moves seats, never the line, by the voters' shift and by discipline; a
##     pledge is spent first, and a negative sway goes with the peel.
##
## The band's numbers are written here as literals, never read from the constants.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const DivisionTerms = preload("res://src/sim/division_terms.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")
const Address = preload("res://src/sim/address.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const EK = preload("res://src/sim/election_constants.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const DiaryDriver = preload("res://src/ui/diary_driver.gd")

const PLAYER := "FRA"
## A hand-written copy of OPINION_WEIGHT, never read from the constant.
const WEIGHT := 6.5

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_a_nation_with_no_address_reads_no_term()
	_check_the_shift_per_bloc()
	_check_standing_and_outlets_scale_it()
	_check_repetition_discounts_what_persuades_only()
	_check_the_verb_writes_the_register_and_the_diary()
	_check_the_verb_refuses_with_no_effect()
	_check_the_verb_prices_the_blocs_against()
	_check_the_register_fades_over_three_months()
	_check_the_game_month_fades_it()
	_check_the_window_forgets_after_six_months()
	_check_a_second_address_adds_to_the_first()
	_check_the_register_survives_a_save()
	_check_the_term_reads_voters_and_discipline()
	_check_the_term_moves_seats_through_a_division()
	_check_seats_with_a_sway()
	_check_the_estimate_is_a_pure_read()

	if _failures.is_empty():
		print("test_address: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 3
	state.day = 10
	return state


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _parties() -> Array:
	return _loader.parties[PLAYER]


## An open ordinary bill.
func _open_bill(state):
	for law in Legislature.available(state.player(), _loader.laws):
		if not law.constitutional:
			return law
	_fail("no open ordinary bill")
	return null


## A throwaway law standing at a position, to place a bloc by hand.
func _law_at(economic: float, social: float):
	var law = LawMagnitude.copy(_loader.laws[0])
	law.id = "probe_law"
	law.position = {"economic": economic, "social": social}
	return law


func _shift_of(ns, law_id: String) -> Dictionary:
	return ((ns.measure_opinion.get("measures", {}) as Dictionary).get(law_id, {}) as Dictionary).get("shifts", {})


func _check_a_nation_with_no_address_reads_no_term() -> void:
	var ns = _new_state().player()
	if not ns.measure_opinion.is_empty():
		_fail("a new game has an opinion register: %s" % [ns.measure_opinion])
	if DivisionTerms.swayed_share(ns, _parties()[0], _law_at(0.0, 0.0), true) != 0.0 or DivisionTerms.swayed_share(ns, _parties()[0], _law_at(0.0, 0.0), false) != 0.0:
		_fail("no address, and a sway")


## At neutral approval, with no outlets: 6 toward, 3 neutral, 1.8 the other way against. The
## bloc's own yes reads where it stands, the same read a referendum takes.
func _check_the_shift_per_bloc() -> void:
	var ns = _new_state().player()
	ns.overall_approval_pct = 50.0
	var seen := {"toward": 0, "neutral": 0, "against": 0}
	for position in [[-0.6, 0.1], [0.7, 0.1], [-0.5, -0.8], [0.1, 0.6], [0.0, 0.0], [0.9, 0.9], [-0.9, 0.9], [0.9, -0.9]]:
		var law = _law_at(position[0], position[1])
		var shifts: Dictionary = Address.shifts(ns, [], law, 1.0)
		for bloc in OpinionK.BLOC_KEYS:
			var yes: float = Referendum.bloc_yes(ns, bloc, law.position)
			var want := 3.0
			var kind := "neutral"
			if yes > 0.6:
				want = 6.0
				kind = "toward"
			elif yes < 0.4:
				want = -1.8
				kind = "against"
			seen[kind] += 1
			if not is_equal_approx(float(shifts[bloc]), want):
				_fail("%s reads yes %.2f on %s and shifts %.3f, want %.1f" % [bloc, yes, position, shifts[bloc], want])
	for kind in seen:
		if int(seen[kind]) == 0:
			_fail("no bloc read %s: the check proved nothing: %s" % [kind, seen])


## A popular president persuades more and a press that stands with the government carries
## it further; a bloc's outlets are its own, and the bounds hold.
func _check_standing_and_outlets_scale_it() -> void:
	var ns = _new_state().player()
	var law = _law_at(-0.5, -0.8)
	ns.overall_approval_pct = 50.0
	var neutral: float = Address.shifts(ns, [], law, 1.0)["students"]
	for row in [[60.0, 1.2, "standing 60 over 50"], [15.0, 0.5, "standing's floor"], [95.0, 1.5, "standing's ceiling"]]:
		ns.overall_approval_pct = float(row[0])
		if Referendum.bloc_yes(ns, "students", law.position) <= 0.6:
			_fail("premise: students do not lean toward the bill at approval %.0f" % row[0])
		if not is_equal_approx(float(Address.shifts(ns, [], law, 1.0)["students"]), neutral * float(row[1])):
			_fail("%s reads %.3f, want %.3f" % [row[2], Address.shifts(ns, [], law, 1.0)["students"], neutral * float(row[1])])
	ns.overall_approval_pct = 50.0
	var friend = _outlet("students", 0.4, ns.coalition_position)
	var plain: Dictionary = Address.shifts(ns, [], law, 1.0)
	var heard: Dictionary = Address.shifts(ns, [friend], law, 1.0)
	if not float(heard["students"]) > float(plain["students"]):
		_fail("a friendly paper did not carry it: %.3f against %.3f" % [heard["students"], plain["students"]])
	if heard["workers"] != plain["workers"]:
		_fail("a paper read by students moved workers")
	var huge: Dictionary = Address.shifts(ns, [_outlet("students", 50.0, ns.coalition_position)], law, 1.0)
	if not is_equal_approx(float(huge["students"]), float(plain["students"]) * 1.5):
		_fail("the outlets' ceiling: %.3f" % huge["students"])
	var hostile: Dictionary = Address.shifts(ns, [_outlet("students", 50.0, _opposite(ns.coalition_position))], law, 1.0)
	if not is_equal_approx(float(hostile["students"]), float(plain["students"]) * 0.5):
		_fail("the outlets' floor: %.3f" % hostile["students"])


func _opposite(position: Dictionary) -> Dictionary:
	return {"economic": -signf(float(position["economic"]) + 0.01), "social": -signf(float(position["social"]) + 0.01)}


func _outlet(audience: String, reach: float, position: Dictionary):
	var outlet = _loader.outlets[PLAYER][0].get_script().new()
	outlet.audience = audience
	outlet.reach = reach
	outlet.position = position.duplicate()
	return outlet


func _check_repetition_discounts_what_persuades_only() -> void:
	var ns = _new_state().player()
	ns.overall_approval_pct = 50.0
	var law = _law_at(-0.5, -0.8)
	var first: Dictionary = Address.shifts(ns, [], law, 1.0)
	var third: Dictionary = Address.shifts(ns, [], law, 0.36)
	var against := 0
	for bloc in OpinionK.BLOC_KEYS:
		if float(first[bloc]) > 0.0:
			if not is_equal_approx(float(third[bloc]), float(first[bloc]) * 0.36):
				_fail("%s persuaded %.3f at a third address, want %.3f" % [bloc, third[bloc], float(first[bloc]) * 0.36])
		else:
			against += 1
			if float(third[bloc]) != float(first[bloc]):
				_fail("%s hardened %.3f at a third address, %.3f at the first" % [bloc, third[bloc], first[bloc]])
	if against == 0:
		_fail("no bloc against: the check proved nothing")


func _check_the_verb_writes_the_register_and_the_diary() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	if not is_equal_approx(Address.worth(ns, _now(state)), 1.0):
		_fail("a first address is worth %.2f" % Address.worth(ns, _now(state)))
	var result: Dictionary = Address.give(state, _loader, law.id)
	if not bool(result.get("ok", false)):
		_fail("the address was refused: %s" % [result])
		return
	if str(_shift_of(ns, law.id)) != str(result["shifts"]) or _shift_of(ns, law.id).is_empty():
		_fail("the register holds %s, the verb said %s" % [_shift_of(ns, law.id), result["shifts"]])
	var booked: Array = state.appointments.filter(func(e) -> bool: return String(e["kind"]) == CalendarK.KIND_ADDRESS)
	if booked.size() != 1 or int(booked[0]["day"]) != 10 or String(booked[0]["law_id"]) != law.id or String(booked[0]["status"]) != CalendarK.STATUS_BOOKED:
		_fail("the diary holds %s" % [booked])
	if Calendar.can_book(state, Calendar.make_entry(CalendarK.KIND_LAW, 2026, 3, 10, "", "", "another")):
		_fail("the address did not take the day")
	if not is_equal_approx(Address.worth(ns, _now(state)), 0.6):
		_fail("a second address in the window is worth %.2f" % Address.worth(ns, _now(state)))


func _check_the_verb_refuses_with_no_effect() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	var offsets: String = str(ns.bloc_offset)
	var no_such: Dictionary = Address.give(state, _loader, "no_such_bill")
	if bool(no_such.get("ok", true)) or String(no_such.get("error", "")) == "":
		_fail("an address on no bill: %s" % [no_such])
	Calendar.book(state, Calendar.make_entry(CalendarK.KIND_LAW, 2026, 3, 10, "", "", "another"))
	var taken: Dictionary = Address.give(state, _loader, law.id)
	if bool(taken.get("ok", true)) or String(taken.get("error", "")) == "":
		_fail("an address on a taken day: %s" % [taken])
	if not ns.measure_opinion.is_empty() or str(ns.bloc_offset) != offsets or state.appointments.size() != 1:
		_fail("a refusal left a mark: %s, %d appointments" % [ns.measure_opinion, state.appointments.size()])


## The blocs against pay, the rest do not, through the applier that clamps.
func _check_the_verb_prices_the_blocs_against() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	var before: Dictionary = ns.bloc_offset.duplicate()
	var result: Dictionary = Address.give(state, _loader, law.id)
	var against := 0
	for bloc in OpinionK.BLOC_KEYS:
		var moved: float = float(ns.bloc_offset.get(bloc, 0.0)) - float(before.get(bloc, 0.0))
		if float(result["shifts"][bloc]) < 0.0:
			against += 1
			if not is_equal_approx(moved, -0.004):
				_fail("%s is against and paid %.5f" % [bloc, moved])
		elif moved != 0.0:
			_fail("%s is not against and paid %.5f" % [bloc, moved])
	if against == 0:
		_fail("%s has no bloc against: the check proved nothing" % law.id)


func _check_the_register_fades_over_three_months() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	var first: Dictionary = Address.give(state, _loader, law.id)["shifts"].duplicate()
	var bloc: String = OpinionK.BLOC_KEYS[0]
	Address.tick_month(state)
	if not is_equal_approx(float(_shift_of(ns, law.id)[bloc]), float(first[bloc]) * 2.0 / 3.0):
		_fail("after a month %.3f, want two thirds of %.3f" % [_shift_of(ns, law.id)[bloc], first[bloc]])
	Address.tick_month(state)
	if not is_equal_approx(float(_shift_of(ns, law.id)[bloc]), float(first[bloc]) / 3.0):
		_fail("after two months %.3f, want a third of %.3f" % [_shift_of(ns, law.id)[bloc], first[bloc]])
	Address.tick_month(state)
	if not _shift_of(ns, law.id).is_empty():
		_fail("after three months the shift stands: %s" % [_shift_of(ns, law.id)])
	# The month's close marks the row, for a game with no day's driver.
	for e in state.appointments:
		if String(e["kind"]) == CalendarK.KIND_ADDRESS and String(e["status"]) != CalendarK.STATUS_DONE:
			_fail("a past address is still %s" % e["status"])


## Through the game's own month, not the function: the step is wired.
func _check_the_game_month_fades_it() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	var first: Dictionary = Address.give(state, _loader, law.id)["shifts"].duplicate()
	var bloc: String = OpinionK.BLOC_KEYS[0]
	if not WorldMonth.STEPS.has("Addresses"):
		_fail("no Addresses step in the month")
		return
	WorldMonth.tick_month(state, _loader)
	if not is_equal_approx(float(_shift_of(ns, law.id)[bloc]), float(first[bloc]) * 2.0 / 3.0):
		_fail("the month did not fade it: %.3f against %.3f" % [_shift_of(ns, law.id).get(bloc, 0.0), first[bloc]])
	if WorldMonth.STEPS.find("Addresses") <= WorldMonth.STEPS.find("Division"):
		_fail("the fade runs before the close's division reads it")


func _check_the_window_forgets_after_six_months() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	Address.give(state, _loader, law.id)
	var now := _now(state)
	if not is_equal_approx(Address.worth(ns, now + 5), 0.6):
		_fail("five months on the first still counts: %.2f" % Address.worth(ns, now + 5))
	if not is_equal_approx(Address.worth(ns, now + 6), 1.0):
		_fail("six months on the first is forgotten: %.2f" % Address.worth(ns, now + 6))
	for i in 7:
		state.month = 3 + i
		Address.tick_month(state)
	if not ns.measure_opinion.is_empty():
		_fail("a register with nothing live left is not empty: %s" % [ns.measure_opinion])


## A second address on one bill adds what it is worth, and restarts the fade.
func _check_a_second_address_adds_to_the_first() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	var first: Dictionary = Address.give(state, _loader, law.id)["shifts"].duplicate()
	# The day's driver marks yesterday's row, with no card: it no longer holds a verb of the same key.
	if not DiaryDriver.resolve(state, _loader, 2026, 3, 10, func(_outcome: Dictionary) -> void: _fail("an address brought the day's card")):
		_fail("the driver had no address to mark")
	Address.tick_month(state)
	var faded: Dictionary = _shift_of(ns, law.id).duplicate()
	state.day = 11
	var second: Dictionary = Address.give(state, _loader, law.id)
	if not bool(second.get("ok", false)):
		_fail("a second address next day: %s" % [second])
		return
	if not is_equal_approx(float(second["worth"]), 0.6):
		_fail("the second is worth %.2f" % second["worth"])
	for bloc in first:
		if not is_equal_approx(float(_shift_of(ns, law.id)[bloc]), float(faded[bloc]) + float(second["shifts"][bloc])):
			_fail("%s holds %.3f, want %.3f" % [bloc, _shift_of(ns, law.id)[bloc], float(faded[bloc]) + float(second["shifts"][bloc])])
	Address.tick_month(state)
	if not is_equal_approx(float(_shift_of(ns, law.id)[first.keys()[0]]), (float(faded[first.keys()[0]]) + float(second["shifts"][first.keys()[0]])) * 2.0 / 3.0):
		_fail("the second address did not restart the fade")


func _check_the_register_survives_a_save() -> void:
	var state = _new_state()
	var law = _open_bill(state)
	Address.give(state, _loader, law.id)
	var want: Dictionary = _shift_of(state.player(), law.id)
	var back = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var read: Dictionary = _shift_of(back.player(), law.id)
	for bloc in want:
		if not is_equal_approx(float(read.get(bloc, 0.0)), float(want[bloc])):
			_fail("the register did not survive a save: %s against %s" % [read, want])
	if not is_equal_approx(Address.worth(back.player(), _now(state)), 0.6):
		_fail("the window did not survive a save")
	Address.tick_month(back)
	if _shift_of(back.player(), law.id).is_empty():
		_fail("a loaded register does not fade")
	var plain: Dictionary = _new_state().to_dict()
	var stripped = GameState.from_dict(JSON.parse_string(JSON.stringify(plain)))
	if not stripped.player().measure_opinion.is_empty():
		_fail("an old save reads an opinion")


## Voters by affinity: all the shift on the bloc nearest a party, and a share of its seats
## that grows as its discipline falls. Written by hand so the number is the formula's.
func _check_the_term_reads_voters_and_discipline() -> void:
	var ns = _new_state().player()
	var law = _law_at(0.0, 0.0)
	var party = _parties()[0]
	var shifts := {}
	for bloc in OpinionK.BLOC_KEYS:
		shifts[bloc] = 10.0
	ns.measure_opinion = {"measures": {law.id: {"months_left": 3, "shifts": shifts}}, "given": []}
	ns.party_discipline[party.id] = 0.5
	if not is_equal_approx(DivisionTerms.swayed_share(ns, party, law, true), WEIGHT * 10.0 / 50.0 * 0.5):
		_fail("a uniform 10 points at discipline 0.5 sways %.4f, want %.4f" % [DivisionTerms.swayed_share(ns, party, law, true), WEIGHT * 10.0 / 50.0 * 0.5])
	if DivisionTerms.swayed_share(ns, party, law, false) != 0.0:
		_fail("no voter hardened, and seats leave the yes line")
	ns.party_discipline[party.id] = 1.0
	if DivisionTerms.swayed_share(ns, party, law, true) != 0.0:
		_fail("a perfectly disciplined party swayed")
	ns.party_discipline[party.id] = 0.5
	var other = _law_at(0.0, 0.0)
	other.id = "another"
	if DivisionTerms.swayed_share(ns, party, other, true) != 0.0:
		_fail("an address on one bill swayed another")
	# Two parties, one bloc shifted: the party whose voters those are moves more.
	var near_bloc := {}
	for bloc in OpinionK.BLOC_KEYS:
		near_bloc[bloc] = 0.0
	near_bloc["business"] = 10.0
	ns.measure_opinion["measures"][law.id]["shifts"] = near_bloc
	var by_slot := {}
	for p in _parties():
		ns.party_discipline[p.id] = 0.5
		by_slot[p.ideology_slot] = DivisionTerms.swayed_share(ns, p, law, true)
	if not float(by_slot["centre_right"]) > float(by_slot["left_populist"]):
		_fail("business moved the left as the right: %s" % [by_slot])
	if not float(by_slot["left_populist"]) > 0.0:
		_fail("a bloc's shift reached no voters of a far party: %s" % [by_slot])
	# Each way on its own, never the mean: half the voters each way moves seats both ways,
	# and the two shares add up to the whole shift's.
	var half := {}
	for bloc in OpinionK.BLOC_KEYS:
		half[bloc] = -10.0
	half["business"] = 10.0
	ns.measure_opinion["measures"][law.id]["shifts"] = half
	var won := DivisionTerms.swayed_share(ns, party, law, true)
	var lost := DivisionTerms.swayed_share(ns, party, law, false)
	if won <= 0.0 or lost <= 0.0 or not is_equal_approx(won + lost, WEIGHT * 10.0 / 50.0 * 0.5):
		_fail("a split country sways %.4f and %.4f, want them to add to %.4f" % [won, lost, WEIGHT * 10.0 / 50.0 * 0.5])
	# Clamped: a share is never more than the seats.
	for bloc in OpinionK.BLOC_KEYS:
		shifts[bloc] = -5000.0
	ns.measure_opinion["measures"][law.id]["shifts"] = shifts
	if DivisionTerms.swayed_share(ns, party, law, false) != 1.0:
		_fail("a sway past the whole line: %.3f" % DivisionTerms.swayed_share(ns, party, law, false))


## An address on a real game: more yes, fewer no, every party's line where it was, and no
## rebellion charged; the seats add up.
func _check_the_term_moves_seats_through_a_division() -> void:
	var state = _new_state()
	var ns = state.player()
	for law in Legislature.available(ns, _loader.laws):
		if law.constitutional:
			continue
		var before: Dictionary = Legislature.resolve_vote(ns, _parties(), law)
		if int(before["no_seats"]) < 100:
			continue
		var given: Dictionary = Address.give(state, _loader, law.id)
		if not bool(given.get("ok", false)):
			_fail("premise: %s" % [given])
			return
		var after: Dictionary = Legislature.resolve_vote(ns, _parties(), law)
		if not int(after["yes_seats"]) > int(before["yes_seats"]):
			_fail("%s: an address moved yes %d to %d" % [law.id, before["yes_seats"], after["yes_seats"]])
		if not int(after["no_seats"]) < int(before["no_seats"]):
			_fail("%s: an address moved no %d to %d" % [law.id, before["no_seats"], after["no_seats"]])
		if str(after["party_votes"]) != str(before["party_votes"]):
			_fail("an address moved a line: %s against %s" % [after["party_votes"], before["party_votes"]])
		if str(after["party_rebels"]) != str(before["party_rebels"]):
			_fail("an address is not a rebellion: %s" % [after["party_rebels"]])
		if int(after["yes_seats"]) + int(after["no_seats"]) + int(after["abstain_seats"]) != int(ns.assembly_seats):
			_fail("the seats do not add up: %s" % [after])
		return
	_fail("no open bill with 100 seats against")


## [yes, no, abstain]. The pledge first, then what is won from what is left of no and
## abstain; what leaves the yes line reads the base the pledge holds.
func _check_seats_with_a_sway() -> void:
	var table := [
		[["no", "no", 100, 0, 0, 0.0, 0.2], [20, 80, 0], "a no line gives a fifth"],
		[["abstain", "abstain", 100, 0, 0, 0.0, 0.2], [20, 0, 80], "an abstaining line gives a fifth"],
		[["yes", "yes", 100, 0, 0, 0.0, 0.2], [100, 0, 0], "a yes line has nothing to give"],
		[["no", "no", 100, 0, 30, 0.0, 0.2], [44, 56, 0], "the sway reads what the pledge left"],
		[["yes", "no", 100, 10, 0, 0.0, 0.5], [95, 5, 0], "rebels against a yes line can be won"],
		[["no", "abstain", 100, 10, 0, 0.0, 0.5], [50, 45, 5], "no and abstain each give their share"],
		[["no", "no", 100, 0, 100, 0.0, 0.2], [100, 0, 0], "nothing left to sway"],
		[["yes", "yes", 100, 0, 30, 0.2, 0.0], [86, 0, 14], "a pledged seat holds"],
		[["yes", "yes", 100, 0, 0, 1.6, 0.0], [0, 0, 100], "the whole line at most"],
		[["no", "no", 100, 0, 0, 0.3, 0.0], [0, 100, 0], "a no line has no yes to lose"],
		[["abstain", "abstain", 100, 0, 0, 0.3, 0.0], [0, 0, 100], "nor an abstaining one"],
		[["yes", "no", 100, 10, 0, 0.1, 0.5], [86, 5, 9], "a sway and a peel on one line"],
	]
	for row in table:
		var a: Array = row[0]
		var got: Array = DivisionTerms.seats_of(a[0], a[1], a[2], a[3], a[4], a[5], a[6])
		if got != row[1]:
			_fail("%s: %s, want %s" % [row[2], got, row[1]])
		elif int(got[0]) + int(got[1]) + int(got[2]) != int(a[2]):
			_fail("%s does not add up" % row[2])


## What the strip reads, on a copy: nothing written, and the after is what the verb then does.
func _check_the_estimate_is_a_pure_read() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _open_bill(state)
	var before_save: String = JSON.stringify(ns.measure_opinion) + str(ns.bloc_offset) + str(state.appointments.size())
	var read: Dictionary = Address.estimate(state, ns, _loader, law)
	if JSON.stringify(ns.measure_opinion) + str(ns.bloc_offset) + str(state.appointments.size()) != before_save:
		_fail("the estimate wrote")
	if str(read["before"]) != str(Legislature.resolve_vote(ns, _parties(), law)):
		_fail("the before is not today's forecast")
	if not is_equal_approx(float(read["worth"]), 1.0):
		_fail("the estimate's worth: %s" % [read["worth"]])
	var given: Dictionary = Address.give(state, _loader, law.id)
	if str(read["shifts"]) != str(given["shifts"]):
		_fail("the estimate promised %s, the verb gave %s" % [read["shifts"], given["shifts"]])
	if str(read["after"]) != str(Legislature.resolve_vote(ns, _parties(), law)):
		_fail("the after is not what the verb did: %s against %s" % [read["after"], Legislature.resolve_vote(ns, _parties(), law)])
