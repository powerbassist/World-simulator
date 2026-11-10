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
const Landings = preload("res://src/sim/request_landings.gd")
const President = preload("res://src/sim/president.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const DensityCount = preload("res://tools/density_count.gd")
const Budget = preload("res://src/sim/budget.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const BriefingEffects = preload("res://src/ui/briefing_effects.gd")

const PLAYER := "FRA"
const PLAYABLE := ["DEU", "FRA", "GBR", "POL"]
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
		_check_a_full_lane_sends_the_month_to_an_event(month)
		_check_a_grudge_holder_is_never_called(month)
	_check_a_called_lapse_costs_a_share()
	_check_a_called_accomplice_pays_the_whole_broken_word()
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
		"a request that differs arrived this month": func(_s, ns) -> void: ns.audience_requests.append({"id": "r", "arrived_month": now, "differs": true}),
		"a request with no stamp arrived this month": func(_s, ns) -> void: ns.audience_requests.append({"id": "r", "arrived_month": now}),
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
		"a request whose answers leave the same words, this month": func(_s, ns) -> void: ns.audience_requests.append({"id": "r", "arrived_month": now, "differs": false}),
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
	# FRA_a asked twice in the window, REQUEST_COOLDOWN_MONTHS apart: four requests, three
	# people. The cap counts people, the rule the spec measured (QA's TAKE on #317).
	for ask in [["FRA_a", now - 1 - AudK.REQUEST_COOLDOWN_MONTHS], ["FRA_a", now - 1], ["FRA_b", now - 11], ["FRA_c", now - 12], ["GBR_d", now - 3]]:
		ns.audience_requests.append({"id": "%s|%d" % ask, "person_id": ask[0], "arrived_month": ask[1], "status": AudK.STATUS_LAPSED})
	_ok(QuietMonth.asks_in_year(ns, now) == 3, "asks in the last twelve months read %d, want 3 people (a visitor counts, a year ago does not, a person asking twice counts once)" % QuietMonth.asks_in_year(ns, now))
	_ok(AudK.QUIET_ASKS_MAX == 9 and AudK.QUIET_ASKS_MONTHS == 12, "the cap is not the author's nine asks in twelve months")


## The call's filter is the probe's own rule on the two axes the ruling names: two
## answers whose bloc arrows differ (DensityCount.arrow, the briefing's word bands)
## or whose money differs by MONEY_BN. The money side is the PROBE's: each answer
## booked on a copy of the world (_booked_money), not the filter's own estimate, for
## every shipped minor event in each playable nation at the game's start (QA's TAKE on
## #317). A tax at 0 that a law raises later in a run is where the estimate (which
## reads it as yielding nothing) and the booking could part; this checks the start.
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
	for nation in PLAYABLE:
		var world = _base if nation == PLAYER else GameState.new_game(_loader, nation)
		for ev in _loader.events:
			if int(ev.severity) != 1 or ev.on_action != "":
				continue
			var strips: Array = []
			var estimates: Array = []
			for c in ev.choices:
				var fx: Dictionary = c.get("effects", {})
				var arrows := {}
				for bloc in fx.get("bloc_offset", {}):
					arrows[bloc] = DensityCount.arrow(float(fx["bloc_offset"][bloc]))
				strips.append({"arrows": arrows, "money_bn": _booked_money(world, fx)})
				estimates.append({"money_bn": EventDraw.money_bn(world.player(), fx)})
			var want := false
			var money_booked := false
			var money_estimated := false
			for i in strips.size():
				for j in range(i + 1, strips.size()):
					var axes: Array = DensityCount.differs(strips[i], strips[j])
					want = want or axes.has("arrow") or axes.has("money")
					money_booked = money_booked or axes.has("money")
					money_estimated = money_estimated or DensityCount.differs(estimates[i], estimates[j]).has("money")
			var got: bool = EventDraw.meaningful(world.player(), ev)
			seen[got] = int(seen[got]) + 1
			_ok(got == want, "%s %s: the filter says %s, the probe's rule %s" % [nation, ev.id, got, want])
			# The money axis alone: most events that differ in money differ in arrows too,
			# which would hide a wrong estimate from the line above.
			_ok(money_estimated == money_booked, "%s %s: the estimate's money says %s, the booking's %s" % [nation, ev.id, money_estimated, money_booked])
	_ok(int(seen[true]) > 0 and int(seen[false]) > 0, "the shipped book has no minor event on one side of the filter: %s" % [seen])


## The probe's money for one answer (decision_surfaces_probe.gd's _balance_move): its
## fiscal channels booked on a copy through Legislature.apply_effects, read off the
## deficit, EUR bn a year, positive a better balance.
func _booked_money(world, fx: Dictionary) -> float:
	var fiscal := {}
	for key in ["spending_pct_gdp", "tax_rates_pct", "other_revenue_pct_gdp"]:
		if fx.has(key):
			fiscal[key] = fx[key]
	if fiscal.is_empty():
		return 0.0
	var copy = world.duplicate_state()
	var cns = copy.player()
	Budget.recompute(copy, cns)
	var before := float(cns.deficit_pct_gdp)
	Legislature.apply_effects(copy, cns, fiscal, _loader)
	Budget.recompute(copy, cns)
	return -(float(cns.deficit_pct_gdp) - before) * float(cns.gdp_eur_bn) / 100.0


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
	_ok(row.has("differs") and bool(row["differs"]) == Landings.differs(state, state.player(), _loader, row),
		"the called request's differs stamp is not request_landings.gd's answer")
	# quiet_month.gd's header: from no grudge, a called request always differs.
	_ok(bool(row["differs"]), "the called request leaves the person in the same words whatever the answer")
	_check_a_called_person_spends_the_month(now)
	_check_a_dull_request_does_not_stop_the_call(now)


## QA's TAKE on #317: a called request ends the quiet whatever its words, so the event
## branch never answers the same month again -- one call a month, by construction.
func _check_a_called_person_spends_the_month(now: int) -> void:
	var state = _fresh(now)
	Audiences.tick_month(state, _loader, METERS)
	var row: Dictionary = state.player().audience_requests.back()
	_ok(bool(row.get("called", false)), "the fixture month called no one")
	row["differs"] = false
	Events.quiet_call(state, _loader)
	_ok(state.player().event_queue.is_empty(), "a called request whose answers read the same let the event branch call too")


## The author's ruling (2026-11-10): a request whose answers all leave the person in
## the same feeling words is no arrival. A row that arrived this month with no open
## answer (already declined) lands nowhere, so request_landings.gd calls it dull:
## Audiences stamps it so, and the month still calls someone.
func _check_a_dull_request_does_not_stop_the_call(now: int) -> void:
	var state = _fresh(now)
	var ns = state.player()
	var row := {"id": "fixture|%d" % now, "person_id": "%s_fixture" % PLAYER, "object": "x", "stance": "",
		"arrived_month": now, "deadline_month": now + 3, "status": "declined", "date": {}, "resolved_month": now}
	ns.audience_requests.append(row)
	Audiences.tick_month(state, _loader, METERS)
	_ok(row.has("differs") and not bool(row["differs"]) and not Landings.differs(state, ns, _loader, row),
		"a request with no open answer was not stamped as leaving the same words")
	_ok(_called(state).size() == 1, "a month whose only request leaves the same words called no one")
	_check_where_the_answers_land(now)


## request_landings.gd on an open request: from a neutral rapport, booking leaves the
## person warm and declining leaves them wary, so the answers differ; from the
## coldest rapport and the worst grudge every answer reads the same.
func _check_where_the_answers_land(now: int) -> void:
	var state = _fresh(now)
	var ns = state.player()
	var person = _loader.people[PLAYER][0]
	var row := {"id": "%s|%d" % [person.id, now], "person_id": String(person.id), "object": "x", "stance": "",
		"arrived_month": now, "deadline_month": now + 3, "status": AudK.STATUS_PENDING, "date": {}, "resolved_month": -1}
	ns.audience_requests.append(row)
	ns.person_rapport[person.id] = 0.0
	ns.person_grudges[person.id] = 0.0
	_ok(Landings.differs(state, ns, _loader, row), "from a neutral rapport, booking and declining read the same")
	ns.person_rapport[person.id] = -1.0
	ns.person_grudges[person.id] = 1.0
	_ok(Landings.landings(state, ns, _loader, row).size() >= 2 and not Landings.differs(state, ns, _loader, row),
		"from the coldest rapport and the worst grudge, the answers read as different words")


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


## A full lane takes no one: the month the call would bring a person brings an
## event instead (the open rows are old, so they are no arrival this month).
func _check_a_full_lane_sends_the_month_to_an_event(now: int) -> void:
	var state = _fresh(now)
	var ns = state.player()
	for i in AudK.MAX_PENDING:
		ns.audience_requests.append({"id": "lane|%d" % i, "person_id": "%s_lane%d" % [PLAYER, i], "object": "x",
			"stance": "", "arrived_month": now - 2, "deadline_month": now + 2, "status": AudK.STATUS_PENDING,
			"date": {}, "resolved_month": -1})
	Audiences.tick_month(state, _loader, METERS)
	Events.quiet_call(state, _loader)
	_ok(_called(state).is_empty(), "the call brought a person into a full lane")
	_ok(ns.event_queue.size() == 1, "a full lane's quiet month brought no event")


## The author's ruling on #317 (B3): the call passes over anyone holding a grudge.
## The person the month calls, given the slightest grudge, is not called; whoever
## comes instead holds none.
func _check_a_grudge_holder_is_never_called(now: int) -> void:
	var first = _fresh(now)
	Audiences.tick_month(first, _loader, METERS)
	var picked: Array = _called(first)
	if picked.size() != 1:
		_failures.append("fixture: month %d no longer calls one person" % now)
		return
	var state = _fresh(now)
	var ns = state.player()
	ns.person_grudges[String(picked[0])] = AudK.QUIET_CALL_GRUDGE_MAX + 0.01
	var before: Dictionary = ns.person_grudges.duplicate()
	Audiences.tick_month(state, _loader, METERS)
	for pid in _called(state):
		_ok(pid != String(picked[0]), "the call brought %s, who holds a grudge" % pid)
		_ok(float(before.get(pid, 0.0)) <= AudK.QUIET_CALL_GRUDGE_MAX, "the call brought %s, who held a grudge of %s" % [pid, before.get(pid, 0.0)])


## The author's ruling on #317 (B3): a called request that lapses costs
## CALLED_LAPSE_SHARE (0.25) of a decline -- grudge and rapport -- and a request the
## person asked for keeps the full decline (1.0). Same person, same month, the only
## difference the `called` stamp.
func _check_a_called_lapse_costs_a_share() -> void:
	_ok(is_equal_approx(AudK.CALLED_LAPSE_SHARE, 0.25) and is_equal_approx(AudK.QUIET_CALL_GRUDGE_MAX, 0.0),
		"the ruling's numbers moved: a share of %s, a grudge bar of %s" % [AudK.CALLED_LAPSE_SHARE, AudK.QUIET_CALL_GRUDGE_MAX])
	var cost := {}
	for called in [false, true]:
		var state = _fresh()
		var ns = state.player()
		var now := _now(state)
		var person = _loader.people[PLAYER][1]
		var pid := String(person.id)
		ns.person_grudges[pid] = 0.0
		ns.person_rapport[pid] = 0.0
		var row := {"id": "%s|%d" % [pid, now - 3], "person_id": pid, "object": "x", "stance": "",
			"arrived_month": now - 3, "deadline_month": now, "status": AudK.STATUS_PENDING, "date": {}, "resolved_month": -1}
		if called:
			row["called"] = true
		ns.audience_requests.append(row)
		# The card's read of the lapse (Interface's ask on #317) is what the lapse writes.
		var told: Dictionary = Landings.lapse_price(ns, _loader, row)
		if not called:
			_ok(told == Landings.decline_price(ns, _loader, row), "an uncalled lapse is not priced as a decline: %s" % [told])
		var loyalty_before := float(ns.person_loyalty.get(pid, 0.0))
		Audiences.tick_month(state, _loader, METERS)
		_ok(String(row["status"]) == AudK.STATUS_LAPSED, "the fixture request did not lapse")
		cost[called] = [float(ns.person_grudges.get(pid, 0.0)), float(ns.person_rapport.get(pid, 0.0))]
		var paid := {"grudge": cost[called][0], "rapport": cost[called][1],
			"loyalty": float(ns.person_loyalty.get(pid, 0.0)) - loyalty_before}
		for register in paid:
			_ok(is_equal_approx(float(told[register]), float(paid[register])),
				"lapse_price told %s %s, the lapse wrote %s (called %s)" % [register, told[register], paid[register], called])
	_ok(float(cost[false][0]) > 0.0 and float(cost[false][1]) < 0.0, "an ordinary lapse cost nothing: %s" % [cost[false]])
	_ok(is_equal_approx(float(cost[true][0]), float(cost[false][0]) * AudK.CALLED_LAPSE_SHARE)
		and is_equal_approx(float(cost[true][1]), float(cost[false][1]) * AudK.CALLED_LAPSE_SHARE),
		"a called lapse cost %s against an ordinary %s, not a quarter" % [cost[true], cost[false]])


## The share is the decline's own part: an accomplice called up and left to lapse still
## breaks their word whole (Lies.cross is unshared), and lapse_price says so.
func _check_a_called_accomplice_pays_the_whole_broken_word() -> void:
	var state = _fresh()
	var ns = state.player()
	var now := _now(state)
	var pid := String(_loader.people[PLAYER][1].id)
	ns.person_grudges[pid] = 0.0
	ns.person_rapport[pid] = 0.0
	ns.exposure_evidence.append({"kind": "favour", "person_id": pid, "size": 1.0, "month": now - 4, "leader_id": President.leader_id(ns)})
	var row := {"id": "%s|%d" % [pid, now - 3], "person_id": pid, "object": "x", "stance": "", "called": true,
		"arrived_month": now - 3, "deadline_month": now, "status": AudK.STATUS_PENDING, "date": {}, "resolved_month": -1}
	ns.audience_requests.append(row)
	var told: Dictionary = Landings.lapse_price(ns, _loader, row)
	_ok(bool(told.get("broken_word", false)), "lapse_price does not flag a called accomplice's broken word")
	Audiences.tick_month(state, _loader, METERS)
	_ok(String(row["status"]) == AudK.STATUS_LAPSED, "the accomplice's request did not lapse")
	var paid := [float(ns.person_grudges.get(pid, 0.0)), float(ns.person_rapport.get(pid, 0.0))]
	_ok(is_equal_approx(float(told["grudge"]), paid[0]) and is_equal_approx(float(told["rapport"]), paid[1]),
		"lapse_price told %s, the accomplice's lapse wrote grudge %s rapport %s" % [told, paid[0], paid[1]])


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
