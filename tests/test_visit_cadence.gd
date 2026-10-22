extends SceneTree

## The AI's state-visit cadence (the V5.1 play gate, the author's call 2026-10-22).
##
## Before this, a hands-off world sent ~26 state visits a year to the player and
## almost none anywhere else: each friendly act credits its ACTOR with every
## observer that has a stake in the target (ForeignPolicy.third_party_from), so
## AI-AI amity saturated within two years and closed the agenda's `deepen` room
## between AIs, while an idle player -- the one nation that never acts, so never
## collects that credit -- stayed the only target with room, visited by every AI
## once per cooldown. The rule that answers it is the host's, read off the
## action: a nation that received a verb carrying `host_interval_months` is not
## offered it again by anyone until the interval has run (the UK's convention is
## two incoming state visits a year).
##
## Through the game's own month (WorldMonth.tick_month), hands-off, on every
## playable nation:
##
##   1. state_visit carries a host interval (the data pin).
##   2. No host -- the player or any AI -- receives a state visit twice within
##      that interval.
##   3. The player receives at most ceil(12 / interval) state visits in any
##      calendar year, and at least one over the run: one partner among many,
##      not the default and not forgotten.
##   4. AIs visit each other: AI-to-AI state visits outnumber visits to the
##      player over the run.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Cooldowns = preload("res://src/sim/diplomacy_cooldowns.gd")

const VERB := "state_visit"
const YEARS := 3
const START_YEAR := 2026

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	var interval := _host_interval()
	if interval <= 0:
		_fail("%s carries no host_interval_months -- nothing limits how often one nation is visited" % VERB)
	else:
		for player in _playables():
			_check_player(player, interval)
		_check_booking(interval)
		_check_reservation(interval)
	_finish()


func _host_interval() -> int:
	for action in _loader.diplomatic_actions:
		if action.id == VERB:
			return int(action.host_interval_months)
	_fail("no %s verb in data/diplomatic-actions/" % VERB)
	return 0


## The playable roster, read off the data rather than listed here.
func _playables() -> Array:
	var out: Array = []
	for id in _loader.nations:
		if bool(_loader.nations[id].playable):
			out.append(String(id))
	out.sort()
	if out.size() < 4:
		_fail("expected the four playables, found %s" % [out])
	return out


func _check_player(player: String, interval: int) -> void:
	var state = GameState.new_game(_loader, player)
	state.year = START_YEAR
	state.month = 1
	var to_player_by_year := {}
	var to_player := 0
	var ai_to_ai := 0
	var last_hosted := {}
	for i in YEARS * 12:
		WorldMonth.tick_month(state, _loader)
		var now: int = state.year * 12 + state.month
		for act in state.foreign_acts:
			if int(act["year"]) != state.year or int(act["month"]) != state.month:
				continue
			if String(act["action_id"]) != VERB:
				continue
			var host := String(act["target_id"])
			if last_hosted.has(host) and now - int(last_hosted[host]) < interval:
				_fail("%s game: %s received a second state visit %d months after the last, inside the %d-month interval" % [
					player, host, now - int(last_hosted[host]), interval])
			last_hosted[host] = now
			if host == player:
				to_player += 1
				to_player_by_year[state.year] = int(to_player_by_year.get(state.year, 0)) + 1
			else:
				ai_to_ai += 1
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
	var cap: int = ceili(12.0 / float(interval))
	for year in to_player_by_year:
		if int(to_player_by_year[year]) > cap:
			_fail("%s game: the player received %d state visits in %d, the cap is %d" % [player, int(to_player_by_year[year]), year, cap])
	if to_player < 1:
		_fail("%s game: no AI visited the player in %d years -- one partner among many, not forgotten" % [player, YEARS])
	if ai_to_ai <= to_player:
		_fail("%s game: %d AI-to-AI state visits against %d to the player -- the player is still the default partner" % [player, ai_to_ai, to_player])
	print("%s: %d state visits to the player in %d years %s, %d AI-to-AI" % [player, to_player, YEARS, to_player_by_year, ai_to_ai])


## The rule holds for the player too (the author, 2026-10-22), so the diary must
## not book what the rule will refuse on the day ("It did not carry.", QA on #74):
## a state visit inside the host's window is refused with the first day it would
## carry, that day books, and -- through the game's own months, AI turns included
## -- it is still on offer when it comes.
func _check_booking(interval: int) -> void:
	var state = GameState.new_game(_loader, "FRA")
	state.year = START_YEAR
	state.month = 3
	state.day = 10
	var host = state.nations["DEU"]
	host.diplo_hosted_months[VERB] = 2
	var travel: int = Diplomacy.travel_days(_loader, "FRA", "DEU")
	var inside: Dictionary = Calendar.make_entry(CalendarK.KIND_DIPLOMATIC, START_YEAR, 4, 20, VERB, "DEU", "", "", "", "", travel)
	var reason: String = Calendar.refusal_reason(state, inside)
	if not reason.contains("01/05/%d" % START_YEAR):
		_fail("a visit inside the host's window was not refused with its first day: '%s'" % reason)
	var first: Dictionary = Calendar.make_entry(CalendarK.KIND_DIPLOMATIC, START_YEAR, 5, 1, VERB, "DEU", "", "", "", "", travel)
	if not bool(Calendar.book(state, first)["ok"]):
		_fail("the first day out of the host's window did not book: '%s'" % Calendar.refusal_reason(state, first))
	var elsewhere: Dictionary = Calendar.make_entry(CalendarK.KIND_DIPLOMATIC, START_YEAR, 4, 20, VERB, "ITA", "", "", "", "", 0)
	if Calendar.refusal_reason(state, elsewhere).contains("too recently"):
		_fail("another host was refused on Germany's window")
	for m in [4, 5]:
		state.month = m
		WorldMonth.tick_month(state, _loader)
	var offered: Array = Diplomacy.available(state, _loader.diplomatic_actions, "FRA", "DEU")
	var carries := false
	for action in offered:
		if action.id == VERB:
			carries = true
	if not carries:
		_fail("the booked visit would not carry on its day: Germany's register reads %s" % [host.diplo_hosted_months])


## The agenda leaves a booked host alone: an AI act now would still stand on the
## booked day. Inside the interval the booked verb is withheld; outside it, kept.
func _check_reservation(interval: int) -> void:
	var state = GameState.new_game(_loader, "FRA")
	state.year = START_YEAR
	state.month = 3
	var visit = null
	for action in _loader.diplomatic_actions:
		if action.id == VERB:
			visit = action
	var offers: Array = [visit]
	if Cooldowns.unreserved(state, "DEU", offers).size() != 1:
		_fail("an empty diary withheld a visit")
	state.appointments.append(Calendar.make_entry(CalendarK.KIND_DIPLOMATIC, START_YEAR, 3 + interval - 1, 1, VERB, "DEU"))
	if not Cooldowns.unreserved(state, "DEU", offers).is_empty():
		_fail("an AI could visit a host the player has booked inside the interval")
	if Cooldowns.unreserved(state, "ITA", offers).size() != 1:
		_fail("a booking with Germany withheld a visit to Italy")
	state.appointments.clear()
	state.appointments.append(Calendar.make_entry(CalendarK.KIND_DIPLOMATIC, START_YEAR, 3 + interval, 1, VERB, "DEU"))
	if Cooldowns.unreserved(state, "DEU", offers).size() != 1:
		_fail("a booking a whole interval away withheld the visit -- it would have expired by then")


func _fail(message: String) -> void:
	_failures.append(message)
	print("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("OK: all visit cadence checks passed")
		quit(0)
	else:
		print("%d failures" % _failures.size())
		quit(1)
