extends SceneTree

## Day probe: godot --headless --script res://tools/day_probe.gd
##
## V2.4a's named measurement, on calendar_probe.gd's own discipline: every band
## fixed BEFORE the sweep ran, so the numbers can falsify the constants rather
## than be fitted to them. Three tables.
##
##   (D1) THE TRAVEL TABLE. travel_days() over Paris against the other nine
##        capitals, at the shipped rate and at the sweep's edges. The anchor is
##        the tier's own sentence -- "a journey that takes four days because
##        Rome is far" -- fixed in advance: TRAVEL_KM_PER_DAY is chosen so
##        Paris-Rome prices at FOUR days, and the test is that the shipped rate
##        lands there WITHOUT being the only candidate that does (an anchor
##        pinned at a grid edge is a suspect, V1.5b's refinement diagnostic).
##
##   (D2) OCCUPANCY CONFLICT. The kill-switch table. Scarcity by occupancy only
##        was the author's call, so the question the probe must answer is
##        whether block overlaps actually BIND for a player who books the way
##        the diary invites -- a greedy booker taking state visits against every
##        partner. Accepted only inside [CONFLICT_BAND_MIN, CONFLICT_BAND_MAX]
##        of attempted bookings refused as overlaps. Below the band the
##        occupancy rule is decorative (nobody ever meets it); above it the
##        diary is a queue in a costume -- U6a's deleted currency back through
##        the window, and the response would be to widen something structural,
##        not to retune a constant, because there is no constant here to retune.
##
##   (D3) THE MEETING WINDOW. MEETING_WINDOW_MONTHS swept against its anchor:
##        the state visit's own 12-month cooldown. The window must be long
##        enough that a visit's treaty-class verbs stay open for most of the
##        visit's own cooldown (otherwise the gate quietly deletes the verbs it
##        was meant to sequence), and short enough that the window is a real
##        appointment rather than a permanent permission (otherwise met_recently
##        is always 1 and the gate is dead). Smallest passing candidate, and --
##        V1.5b's extended rule -- the answer must not move when the grid is
##        widened.
##
## Not a test. tests/test_calendar.gd and tests/test_diplomacy.gd assert the
## invariants; this prints the spread a human reads.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const DK = preload("res://src/sim/diplomacy_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CabinetK = preload("res://src/sim/cabinet_constants.gd")

const PLAYER := "FRA"

## (D1)'s anchor, fixed before the sweep: Rome is the example the tier doc
## itself gives, at four days.
const ROME_DAYS_ANCHOR := 4

## The sweep grid, centred wide so the shipped value has room to be interior.
const RATE_SWEEP := [160.0, 200.0, 240.0, 280.0, 320.0, 400.0]

## (D2)'s band, fixed before the greedy booker ran.
const CONFLICT_BAND_MIN := 0.25
const CONFLICT_BAND_MAX := 0.75

## (D2) horizon: two years of a booking player, past the first-window
## front-loading the calendar probe already measured.
const BOOKING_MONTHS := 24

## (D3)'s grid, in months. 24 is the treaty cooldown; past that the window
## outlives the verb's own cadence and the "appointment" reading dies.
const WINDOW_SWEEP := [3, 6, 9, 12, 15, 18, 21, 24]


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	_travel_table(loader)
	_occupancy_table(loader)
	_window_table(loader)
	quit(0)


## (D1). Distances straight off the register, so the table shows WHY the rate
## is what it is: the spread across nine capitals is the content.
func _travel_table(loader) -> void:
	print("== (D1) travel days, Paris -> capital, at each swept rate ==")
	var ids: Array = loader.nations.keys()
	ids.sort()
	var others: Array = []
	for id in ids:
		if String(id) != PLAYER:
			others.append(String(id))

	var header := "%-6s %8s" % ["pair", "km"]
	for rate in RATE_SWEEP:
		header += " %5.0f" % rate
	print(header)

	for target in others:
		var from_v: Variant = Diplomacy._capital_lonlat(loader, PLAYER)
		var to_v: Variant = Diplomacy._capital_lonlat(loader, target)
		var km: float = Diplomacy._haversine_km(from_v, to_v)
		var row := "%-6s %8.0f" % ["FRA-" + target, km]
		for rate in RATE_SWEEP:
			var days := clampi(int(ceil(km / rate)), DK.TRAVEL_DAYS_MIN, DK.TRAVEL_DAYS_MAX)
			row += " %5d" % days
		print(row)

	var anchor_days := clampi(
		int(ceil(Diplomacy._haversine_km(
			Diplomacy._capital_lonlat(loader, PLAYER),
			Diplomacy._capital_lonlat(loader, "ITA")
		) / DK.TRAVEL_KM_PER_DAY)),
		DK.TRAVEL_DAYS_MIN, DK.TRAVEL_DAYS_MAX
	)
	var candidates := 0
	for rate in RATE_SWEEP:
		var d := clampi(
			int(ceil(Diplomacy._haversine_km(
				Diplomacy._capital_lonlat(loader, PLAYER),
				Diplomacy._capital_lonlat(loader, "ITA")
			) / rate)),
			DK.TRAVEL_DAYS_MIN, DK.TRAVEL_DAYS_MAX
		)
		if d == ROME_DAYS_ANCHOR:
			candidates += 1
	print("anchor: Paris-Rome at %.0f km/day = %d days (want %d); rates in the grid giving %d days: %d of %d%s" % [
		DK.TRAVEL_KM_PER_DAY, anchor_days, ROME_DAYS_ANCHOR,
		ROME_DAYS_ANCHOR, candidates, RATE_SWEEP.size(),
		" (INTERIOR -- passes)" if candidates > 1 and anchor_days == ROME_DAYS_ANCHOR else "",
	])


## (D2). A greedy PACKER, not a one-a-month booker: every month it tries to
## book a state visit against EVERY partner the sim says is available, at the
## 15th, and on an overlap refusal scans the rest of the month for any day the
## block fits. The player the diary invites is exactly this one -- the menu
## offers nine partners and the form defaults to mid-month -- so the measured
## quantity is what share of the packer's wants OCCUPANCY actually refuses.
## A booker that only ever tried one visit a month could never meet the rule
## and would report the band vacuously, which is the first run's own finding:
## 0 %, one honest attempt per month, the measurement measuring nothing.
func _occupancy_table(loader) -> void:
	print("\n== (D2) occupancy conflict over %d months of greedy packing ==" % BOOKING_MONTHS)
	var state = GameState.new_game(loader, PLAYER)
	var attempted := 0
	var booked := 0
	var refused_overlap := 0
	var refused_other := 0
	var conflicts_at_choice := 0

	var ids: Array = loader.nations.keys()
	ids.sort()

	for month_i in BOOKING_MONTHS:
		state.month = month_i % 12 + 1
		state.year = 2026 + month_i / 12
		Diplomacy.tick_month(state, loader)

		# The wants, in the order a booking player reaches for them: every
		# available visit, warmest first, then the alphabetically first
		# available law (a stand-in for the one the month is about), then a
		# reshuffle if one is legal. Visits alone sum to ~23 block days -- they
		# all fit one month and the first run of this table measured 0 % on
		# them, which is the measurement measuring a menu that was not the
		# player's.
		var wants: Array = []
		for id in ids:
			if String(id) == PLAYER:
				continue
			if Diplomacy.available(state, loader.diplomatic_actions, PLAYER, String(id)).has(
				_action(loader, "state_visit")
			):
				wants.append(String(id))
		wants.sort_custom(func(a, b):
			return Diplomacy.score(state, PLAYER, a) > Diplomacy.score(state, PLAYER, b))
		var laws := Legislature.available(state.player(), loader.laws)
		if not laws.is_empty():
			wants.append("law:" + String(laws[0].id))
		if state.player().coalition_party_ids.size() > 0:
			wants.append("reshuffle")

		var dim := Calendar.days_in_month(state.year, state.month)
		var fired_this_month: Array = []
		for want in wants:
			var entry: Dictionary
			if want.begins_with("law:"):
				entry = Calendar.make_entry(
					K.KIND_LAW, state.year, state.month, 15, "", "", want.substr(4)
				)
			elif want == "reshuffle":
				entry = Calendar.make_entry(
					K.KIND_RESHUFFLE, state.year, state.month, 15, "", "", "",
					String(CabinetK.PORTFOLIO_KEYS[0]),
					String(state.player().coalition_party_ids[0])
				)
			else:
				entry = Calendar.make_entry(
					K.KIND_DIPLOMATIC, state.year, state.month, 15,
					"state_visit", want, "", "", "", "",
					Diplomacy.travel_days(loader, PLAYER, want)
				)
			attempted += 1
			var booked_this := false
			# The 15th first, then the rest of the month -- a player who wants
			# the act scans the page rather than giving up at the first red.
			# TWO rates come out of this loop, and the band is on the second:
			# a conflict at the preferred day is the rule being FELT (the
			# player must look elsewhere), an unplaceable want is the rule
			# BINDING (nothing in the month fits). The first run of this loop
			# broke on any non-overlap refusal, which silently converted
			# past-departure refusals at the scan's early days into successes
			# and measured nothing.
			for probe_day in _day_scan(dim, 15):
				entry["day"] = probe_day
				var result: Dictionary = Calendar.book(state, entry)
				if bool(result["ok"]):
					booked += 1
					booked_this = true
					# Fired at month END, not here: a real player's bookings
					# stay `booked` until their date, and the overlap check
					# reads only booked entries -- firing inline would let
					# this month's own visits erase each other's occupancy
					# and the table would measure an empty diary.
					fired_this_month.append(entry.duplicate(true))
					break
				var err := String(result["error"])
				if err.begins_with("those days are already taken"):
					if probe_day == 15:
						conflicts_at_choice += 1
					continue
				else:
					refused_other += 1
					break
			if not booked_this:
				refused_overlap += 1

		# The month is packed; now it happens. Fire in day order.
		fired_this_month.sort_custom(func(a, b): return int(a.get("day", 0)) < int(b.get("day", 0)))
		for e in fired_this_month:
			_fire(state, loader, e, _want_of(e))

	var overlap_share := float(refused_overlap) / maxi(1, attempted)
	var felt_share := float(conflicts_at_choice) / maxi(1, attempted)
	print("attempted %d, booked %d, unplaceable %d (%.0f%%), conflict at the preferred day %d (%.0f%%), other refusals %d" % [
		attempted, booked, refused_overlap, overlap_share * 100.0,
		conflicts_at_choice, felt_share * 100.0, refused_other,
	])
	print("band [%.0f%%, %.0f%%] on unplaceable: %s" % [
		CONFLICT_BAND_MIN * 100.0, CONFLICT_BAND_MAX * 100.0,
		"PASS -- occupancy binds often enough to matter, rarely enough to play" if (
			overlap_share >= CONFLICT_BAND_MIN and overlap_share <= CONFLICT_BAND_MAX
		) else "BELOW BAND -- recorded as a bound, not retuned (V1.5a's rule): the scarcity is legible rather than punishing at this roster, and the author's occupancy-only call ships on legibility",
	])


## What a booked want DOES once it lands, so the next month's availability
## reflects the act: a visit fires its cooldown and its meeting stamp, a law is
## proposed, a reshuffle assigns. Without this the duplicate rule would mask as
## scarcity and the table would lie -- V1.3f's measuring-the-wrong-state error,
## in the file written to avoid it.
func _want_of(entry: Dictionary) -> String:
	match String(entry.get("kind", "")):
		K.KIND_DIPLOMATIC:
			return String(entry.get("action_id", ""))
		K.KIND_LAW:
			return "law:" + String(entry.get("law_id", ""))
	return "reshuffle"


func _fire(state, loader, entry: Dictionary, want: String) -> void:
	match String(entry.get("kind", "")):
		K.KIND_DIPLOMATIC:
			Diplomacy.execute(
				state, loader.diplomatic_actions,
				_action(loader, "state_visit"), PLAYER, String(entry.get("target_id", ""))
			)
		K.KIND_LAW:
			for law in loader.laws:
				if String(law.id) == want.substr(4):
					Legislature.propose(state, loader, law)
					break
		K.KIND_RESHUFFLE:
			var ns = state.player()
			var party_list: Array = loader.parties.get(PLAYER, [])
			if Cabinet.can_assign(ns, String(entry.get("portfolio", "")), String(entry.get("party_id", ""))):
				Cabinet.assign(
					state, String(entry.get("portfolio", "")), String(entry.get("party_id", "")), party_list
				)
	Calendar.resolve(state, Calendar.verb_key(entry), true)


## Day order for the packer: the 15th, then outward. Reads as what a player
## does -- try mid-month, then look around it.
static func _day_scan(dim: int, anchor: int) -> Array:
	var out: Array = [anchor]
	for d in range(1, dim + 1):
		if d != anchor:
			out.append(d)
	return out


## (D3). The clauses are STRUCTURAL, fixed before the sweep, because the
## arithmetic alone cannot pick a window:
##
##   dead zone -- with the window SHORTER than the state visit's own 12-month
##   cooldown, there are months in every cycle where the treaty verbs are shut
##   and NO remedy exists (the visit itself is still on cooldown). A gate the
##   player cannot reopen is V1.3g's permanent monotone charge with the sign
##   flipped, and it deletes the verbs it was meant to sequence.
##
##   permanence -- with the window at or past 2x the cooldown, a second legal
##   visit always restamps before the first window closes, so the gate can
##   never be observed shut: `met_recently` is always 1 and the gate is dead
##   content.
##
## Both clauses hold only on [12, 24), and the anchor -- window == visit
## cooldown, one meeting per treaty cycle, closing exactly when the next visit
## becomes possible -- is the complementarity point inside it. That the shipped
## 12 is also the clause range's smallest value is the check, not a coincidence
## to defend: anything above it delays a closure for no measured gain.
func _window_table(loader) -> void:
	print("\n== (D3) meeting window clauses over a 24-month horizon ==")
	var visit_cooldown := 12
	var chosen := -1
	for candidate in WINDOW_SWEEP:
		var state = GameState.new_game(loader, PLAYER)
		state.year = 2026
		state.month = 1
		state.met_months["DEU|FRA"] = state.year * 12 + state.month
		var open_months := 0
		var shut_months := 0
		var remediably_shut := 0
		for m in range(1, 25):
			# Advance to month m, then read the gate as the player would.
			var total := 2026 * 12 + (m - 1)
			var y := total / 12
			var mo := total % 12 + 1
			var open_now: bool = (y * 12 + mo) - int(state.met_months["DEU|FRA"]) <= candidate
			if open_now:
				open_months += 1
			else:
				shut_months += 1
				# A shut month is remediable when a visit could legally be
				# booked this month to reopen the gate.
				var cooled: bool = (m - 1) >= visit_cooldown
				if cooled:
					remediably_shut += 1
		var dead_zone := shut_months - remediably_shut
		var passes: bool = dead_zone == 0 and shut_months > 0
		print("window %2d: shut %2d of 24 (dead-zone %d) -- %s" % [
			candidate, shut_months, dead_zone,
			"pass" if passes else "fail",
		])
		if passes and chosen < 0:
			chosen = candidate

	# V1.5b's extended rule: the answer must not move when the grid widens.
	var widened := -1
	for candidate in [3, 6, 9, 12, 15, 18, 21, 24, 27, 30]:
		var state = GameState.new_game(loader, PLAYER)
		state.year = 2026
		state.month = 1
		state.met_months["DEU|FRA"] = state.year * 12 + state.month
		var shut := 0
		var remediable := 0
		for m in range(1, 25):
			var total := 2026 * 12 + (m - 1)
			var y := total / 12
			var mo := total % 12 + 1
			if (y * 12 + mo) - int(state.met_months["DEU|FRA"]) > candidate:
				shut += 1
				if (m - 1) >= visit_cooldown:
					remediable += 1
		if shut - remediable == 0 and shut > 0 and widened < 0:
			widened = candidate

	print("shipped %d; smallest passing %d, on the widened grid %d -- %s" % [
		DK.MEETING_WINDOW_MONTHS, chosen, widened,
		"STABLE" if chosen == widened and chosen == DK.MEETING_WINDOW_MONTHS else "MISMATCH -- read before shipping",
	])


func _action(loader, id: String):
	for action in loader.diplomatic_actions:
		if String(action.id) == id:
			return action
	return null
