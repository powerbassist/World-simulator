extends SceneTree

## V5.3 B7, the quiet-month call (docs/design/v5.3-b7-density.md sections 4 and 8;
## the author's calls 2 to 4, 2026-11-10). When a month ends with nothing arrived,
## the game calls up one thing that is already waiting: a person with a want first
## (Audiences, at the end of its month), up to nine asks in twelve months, then a
## minor event whose answers differ on an arrow or on money (the QuietEvent step).
## A called event never holds the clock: it waits and lapses to its default. The
## council's arrival is a division the player's vote decides, which Orgs stamps at
## the session's opening. Every read here goes through GameState's registers.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudK = preload("res://src/sim/audience_constants.gd")
const Events = preload("res://src/sim/events.gd")
const EventsK = preload("res://src/sim/events_constants.gd")
const EventDraw = preload("res://src/sim/event_draw.gd")
const QuietMonth = preload("res://src/sim/quiet_month.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const DensityCount = preload("res://tools/density_count.gd")
const BriefingEffects = preload("res://src/ui/briefing_effects.gd")

const PLAYER := "FRA"
const EU := "eu"
const METERS := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}
## A month well after the lane's month-3 guarantee, so only the hazard and the
## call can bring anyone.
const YEAR := 2027
const MONTH := 5

var _failures: Array[String] = []
var _loader
var _base


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_base = GameState.new_game(_loader, PLAYER)
	_check_each_arrival_ends_the_quiet()
	_check_asks_count_the_last_twelve_months()
	_check_the_filter_is_the_probes_rule()
	var month := _a_month_the_call_brings_a_person()
	if month < 0:
		_failures.append("no month in 2027-2029 where the call brings a person: the fixture cannot bite")
	else:
		_check_the_person_comes_first(month)
		_check_an_arrival_stops_the_person(month)
		_check_the_cap_sends_the_month_to_an_event(month)
	_check_a_drawn_event_carries_no_never_holds()
	_check_the_swing_stamp_agrees_with_the_division()
	_finish()


func _fresh(now: int = YEAR * 12 + MONTH):
	var state = _base.duplicate_state()
	state.year = int(now / 12.0)
	state.month = now % 12
	if state.month == 0:
		state.year -= 1
		state.month = 12
	var ns = state.player()
	ns.event_queue.clear()
	ns.audience_requests.clear()
	# The lane opened a year ago and someone already asked: the month-3
	# guarantee is spent.
	ns.audience_lane_start = now - 12
	ns.audience_asked_month = {"%s_fixture" % PLAYER: now - 24}
	return state


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


## Each arrival the rule names ends the quiet; an older stamp, an absent stamp, a
## council the player cannot swing and a council opened last month do not. Nor does
## an arrival that is no decision by the call's own filter (an event or a process ask
## whose answers differ on no arrow and no money): the band would not count it, so the
## month is still quiet. An event this build does not know ends it (the safe side).
func _check_each_arrival_ends_the_quiet() -> void:
	var state = _fresh()
	var now := _now(state)
	var live := _event_id(true)
	var dull := _event_id(false)
	_ok(live != "" and dull != "", "fixture: the book has no minor event on one side of the filter")
	_ok(bool(state.player().in_government), "fixture: France starts out of government")
	_ok(QuietMonth.quiet(state, state.player(), _loader, now), "a month with nothing arrived is not quiet")

	var cases := {
		"an event that differs arrived this month": func(_s, ns) -> void: ns.event_queue.append({"event_id": live, "arrived": now}),
		"an event this build does not know arrived this month": func(_s, ns) -> void: ns.event_queue.append({"event_id": "x", "arrived": now}),
		"a request arrived this month": func(_s, ns) -> void: ns.audience_requests.append({"id": "r", "arrived_month": now}),
		"a closure announced this month": func(_s, ns) -> void: _set_company(ns, "closure", {"status": "announced", "announced": now}),
		"a bid this month": func(_s, ns) -> void: _set_company(ns, "bid_month", now),
		"a failure this month": func(_s, ns) -> void: _set_company(ns, "failed_month", now),
		"a process ask that differs posted this month": func(_s, ns) -> void: ns.processes.append(_ask_fixture(now, 0.2, 0.0)),
		"a process ask whose price differs posted this month": func(_s, ns) -> void: ns.processes.append(_ask_fixture(now, 0.0, 1.0)),
		"a sector warning this month": func(_s, ns) -> void: ns.sector_drift["warnings"] = {"x": {"entered": now}},
		"a council the player swings, opened this month": func(s, _ns) -> void: s.orgs[EU]["pending"] = _pending(s, true, 0),
		"a government out of office": func(_s, ns) -> void: ns.in_government = false,
	}
	for label in cases:
		var s = _fresh()
		(cases[label] as Callable).call(s, s.player())
		_ok(not QuietMonth.quiet(s, s.player(), _loader, now), "%s left the month quiet" % label)

	var still := {
		"a desk entry from last month": func(_s, ns) -> void: ns.event_queue.append({"event_id": live, "arrived": now - 1}),
		"an event whose answers do not differ, this month": func(_s, ns) -> void: ns.event_queue.append({"event_id": dull, "arrived": now}),
		"a process ask whose answers do not differ, this month": func(_s, ns) -> void: ns.processes.append(_ask_fixture(now, 0.0, 0.0)),
		"a desk entry with no stamp (an older save)": func(_s, ns) -> void: ns.event_queue.append({"event_id": "x"}),
		"a request from last month": func(_s, ns) -> void: ns.audience_requests.append({"id": "r", "arrived_month": now - 1}),
		"a council the player cannot swing": func(s, _ns) -> void: s.orgs[EU]["pending"] = _pending(s, false, 0),
		"a council with no stamp (an older save)": func(s, _ns) -> void: s.orgs[EU]["pending"] = _pending(s, true, 0, false),
		"a council the player swings, opened last month": func(s, _ns) -> void: s.orgs[EU]["pending"] = _pending(s, true, 1),
	}
	for label in still:
		var s = _fresh()
		(still[label] as Callable).call(s, s.player())
		_ok(QuietMonth.quiet(s, s.player(), _loader, now), "%s ended the quiet" % label)


## A minor hazard event the call's filter accepts (`differs`) or refuses; "" if none.
func _event_id(differs: bool) -> String:
	for ev in _loader.events:
		if int(ev.severity) == 1 and ev.on_action == "" and EventDraw.meaningful(_base.player(), ev) == differs:
			return String(ev.id)
	return ""


## A process ask posted at `now` with two answers: the second moves workers by
## `offset` and the debt by `debt` bn more than the first.
func _ask_fixture(now: int, offset: float, debt: float) -> Dictionary:
	return {"status": "open", "ask": {"posted": now, "answers": [
		{"bloc_offset": {"workers": 0.0}, "debt_eur_bn": 0.0},
		{"bloc_offset": {"workers": offset}, "debt_eur_bn": debt}]}}


func _set_company(ns, key: String, value) -> void:
	var ids: Array = ns.companies.keys()
	ids.sort()
	(ns.companies[ids[0]] as Dictionary)[key] = value


func _pending(state, swings: bool, months_ago: int, stamped := true) -> Dictionary:
	var out := {"proposal_id": "p", "months_left": 3, "player_vote": Orgs.VOTE_ABSTAIN,
		"opened_year": state.year, "opened_month": int(state.month) - months_ago}
	if stamped:
		out["player_swings"] = swings
	return out


func _check_asks_count_the_last_twelve_months() -> void:
	var state = _fresh()
	var ns = state.player()
	var now := _now(state)
	ns.audience_asked_month = {"FRA_a": now - 1, "FRA_b": now - 11, "FRA_c": now - 12, "GBR_d": now - 3}
	_ok(QuietMonth.asks_in_year(ns, now) == 3, "asks in the last twelve months read %d, want 3 (a visitor counts, a year ago does not)" % QuietMonth.asks_in_year(ns, now))
	_ok(AudK.QUIET_ASKS_MAX == 9 and AudK.QUIET_ASKS_MONTHS == 12, "the cap is not the author's nine asks in twelve months")


## The call's filter is the probe's own rule on the two axes the ruling names: two
## answers whose bloc arrows differ (DensityCount.arrow, the briefing's word bands)
## or whose money differs by MONEY_BN.
func _check_the_filter_is_the_probes_rule() -> void:
	_ok(is_equal_approx(EventsK.QUIET_MONEY_BN, DensityCount.MONEY_BN), "the call's money bar is not the probe's")
	_ok(is_equal_approx(OpinionK.OFFSET_SLIGHT, BriefingEffects.OFFSET_SLIGHT) and is_equal_approx(OpinionK.OFFSET_CLEAR, BriefingEffects.OFFSET_CLEAR),
		"the arrow bands are not the briefing's")
	for offset in [0.0, 0.049, 0.05, -0.05, 0.149, 0.15, -0.3]:
		_ok(EventDraw.arrow(offset) == DensityCount.arrow(offset), "EventDraw.arrow(%s) is not the probe's" % offset)
	var ns = _base.player()
	_ok(is_equal_approx(EventDraw.money_bn(ns, {"spending_pct_gdp": {"health": 0.1}}), -0.001 * float(ns.gdp_eur_bn)),
		"a spending of 0.1 point of GDP does not cost 0.1 % of GDP")
	var seen := {true: 0, false: 0}
	for ev in _loader.events:
		if int(ev.severity) != 1 or ev.on_action != "":
			continue
		var strips: Array = []
		for c in ev.choices:
			var fx: Dictionary = c.get("effects", {})
			var arrows := {}
			for bloc in fx.get("bloc_offset", {}):
				arrows[bloc] = DensityCount.arrow(float(fx["bloc_offset"][bloc]))
			strips.append({"arrows": arrows, "money_bn": EventDraw.money_bn(ns, fx)})
		var want := false
		for i in strips.size():
			for j in range(i + 1, strips.size()):
				var axes: Array = DensityCount.differs(strips[i], strips[j])
				want = want or axes.has("arrow") or axes.has("money")
		var got: bool = EventDraw.meaningful(ns, ev)
		seen[got] = int(seen[got]) + 1
		_ok(got == want, "%s: the filter says %s, the probe's rule %s" % [ev.id, got, want])
	_ok(int(seen[true]) > 0 and int(seen[false]) > 0, "the shipped book has no minor event on one side of the filter: %s" % [seen])


## The first month of 2027-2029 where the fixture's quiet month calls a person.
func _a_month_the_call_brings_a_person() -> int:
	for now in range(YEAR * 12 + MONTH, (YEAR + 3) * 12):
		var state = _fresh(now)
		var out: Dictionary = Audiences.tick_month(state, _loader, METERS)
		var called := _called(state)
		if (out["arrived"] as Array).size() == 1 and called.size() == 1:
			return now
		# Fires only in a month with no arrival: a month the hazard filled calls nobody.
		if (out["arrived"] as Array).size() > called.size() and not called.is_empty():
			_failures.append("month %d: the hazard brought someone and the call brought %s too" % [now, called])
	return -1


func _called(state) -> Array:
	var out: Array = []
	for row in state.player().audience_requests:
		if bool(row.get("called", false)):
			out.append(String(row["person_id"]))
	return out


## Person first: the month the call brings a person brings no event, and the
## person is the waiting candidate the guarantee would pick (the highest standing).
func _check_the_person_comes_first(now: int) -> void:
	var state = _fresh(now)
	Audiences.tick_month(state, _loader, METERS)
	Events.quiet_call(state, _loader)
	_ok(state.player().event_queue.is_empty(), "the call brought a person and an event in one month")
	var row: Dictionary = state.player().audience_requests.back()
	_ok(int(row["arrived_month"]) == now and bool(row["called"]), "the called request is not stamped as called this month")


## Fires only in a month with no arrival: the same month with a desk arrival calls
## no one, and the event step adds nothing either.
func _check_an_arrival_stops_the_person(now: int) -> void:
	var state = _fresh(now)
	state.player().event_queue.append({"event_id": "fixture", "arrived": now, "severity": 1, "months_left": 3})
	Audiences.tick_month(state, _loader, METERS)
	_ok(_called(state).is_empty(), "the call brought a person in a month an event arrived")
	Events.quiet_call(state, _loader)
	_ok(state.player().event_queue.size() == 1, "the call brought an event in a month an event arrived")


## Nine asks in twelve months: the ninth turns the month to an event; at eight the
## person still comes. The called event never holds and lapses to its default.
func _check_the_cap_sends_the_month_to_an_event(now: int) -> void:
	for asks in [8, 9]:
		var state = _fresh(now)
		var ns = state.player()
		for i in asks:
			ns.audience_asked_month["%s_cap%d" % [PLAYER, i]] = now - 1 - i
		Audiences.tick_month(state, _loader, METERS)
		Events.quiet_call(state, _loader)
		if asks == 8:
			_ok(_called(state).size() == 1 and ns.event_queue.is_empty(), "at eight asks in a year the person did not come first")
			continue
		_ok(_called(state).is_empty(), "the call brought a ninth person in twelve months")
		_ok(ns.event_queue.size() == 1, "at the cap the call brought no event (desk: %s)" % [ns.event_queue])
		if ns.event_queue.size() != 1:
			continue
		var entry: Dictionary = ns.event_queue[0]
		var ev = Events.event_by_id(_loader, String(entry["event_id"]))
		_ok(bool(entry.get("never_holds", false)), "the called event does not carry never_holds")
		_ok(int(entry.get("arrived", -1)) == now, "the called event is not stamped as arrived this month")
		_ok(int(ev.severity) == 1 and ev.on_action == "" and EventDraw.meaningful(ns, ev), "the call brought %s, not a minor event whose answers differ" % ev.id)
		_lapses(state, String(entry["event_id"]), int(entry["months_left"]))


## Left alone, the called entry is answered by its default when its countdown runs
## out, like any entry: it never holds, it lapses (the note is Interface's).
func _lapses(state, event_id: String, months: int) -> void:
	var ns = state.player()
	for i in months:
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Events.tick_month(state, _loader)
	var still := false
	for entry in ns.event_queue:
		still = still or String(entry["event_id"]) == event_id
	_ok(not still, "the called event is still on the desk after its window")
	var lapsed := false
	for record in ns.event_history:
		lapsed = lapsed or (String(record["event_id"]) == event_id and bool(record["defaulted"]))
	_ok(lapsed, "the called event did not lapse to its default")


## The hazard's own deliveries are stamped as arrived and never carry the flag.
func _check_a_drawn_event_carries_no_never_holds() -> void:
	var drawn := 0
	for now in range(YEAR * 12 + MONTH, (YEAR + 4) * 12):
		var state = _fresh(now)
		Events.tick_month(state, _loader)
		for entry in state.player().event_queue:
			drawn += 1
			_ok(int(entry.get("arrived", -1)) == now, "a drawn entry is not stamped with its month")
			_ok(not entry.has("never_holds"), "a drawn entry carries never_holds")
	_ok(drawn > 0, "no event drawn in four years: the check did not bite")


## The swing stamp agrees with the division: resolved on the opening's books under
## each of the player's three votes, the outcome differs exactly when the stamp
## says the player swings it. Across EU proposals, both answers must occur.
func _check_the_swing_stamp_agrees_with_the_division() -> void:
	var seen := {true: 0, false: 0}
	for p in _loader.org_proposals.get(EU, []):
		var state = _fresh()
		var register: Dictionary = state.orgs[EU]
		register["pending"] = {}
		register["months_to_next"] = 0
		register["tabled"] = {"proposal_id": p.id, "by": ""}
		Orgs.tick_month(state, _loader)
		var pending: Dictionary = register.get("pending", {})
		if pending.is_empty() or int(pending.get("opened_month", 0)) != int(state.month):
			continue
		_ok(pending.has("player_swings"), "an opening carries no swing stamp")
		var outcomes := {}
		for vote in Orgs.VOTE_CHOICES:
			var copy = state.duplicate_state()
			Orgs.cast_vote(copy, EU, vote)
			Orgs._resolve(copy, _loader, EU)
			outcomes[bool(copy.orgs[EU]["last_vote"]["passed"])] = true
		var swings: bool = bool(pending.get("player_swings", false))
		seen[swings] = int(seen[swings]) + 1
		_ok(swings == (outcomes.size() == 2), "%s: stamped %s, the division says %s" % [pending["proposal_id"], swings, outcomes.size() == 2])
	_ok(int(seen[true]) > 0 and int(seen[false]) > 0, "the EU book never shows both a swing and no swing: %s" % [seen])


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_quiet_month: PASS")
		quit(0)
		return
	for f in _failures:
		push_error("test_quiet_month: " + f)
	print("test_quiet_month: FAIL (%d)" % _failures.size())
	quit(1)
