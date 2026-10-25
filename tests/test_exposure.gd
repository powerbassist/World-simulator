extends SceneTree

## V5.2c Task 3. The exposure machine: a monthly seeded hazard per route over the
## sitting president's evidence, a hit moving the heaviest reachable row into
## `exposures` and arming its scandal through the chain door. The plan:
## .superpowers/sdd/v5.2c-plan.md, Task 3; the band: bands-v5.2.md B6.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const GameEvent = preload("res://src/core/event.gd")
const Cut = preload("res://src/core/cut.gd")
const Exposure = preload("res://src/sim/exposure.gd")
const Events = preload("res://src/sim/events.gd")
const President = preload("res://src/sim/president.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const JK = preload("res://src/sim/judiciary_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const SC = preload("res://src/sim/shadow_constants.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_cut_counts_a_sum_on_the_cut_as_on_it()
	_check_no_evidence_no_hazard()
	_check_determinism()
	_check_captured_court_never_exposes()
	_check_turned_needs_a_turned_person()
	_check_currency_order()
	_check_former_leader_rows_not_rolled()
	_check_arms_the_event()
	_check_on_arrival_applies_once()
	_finish()


func _state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	return state


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


## The first of the played nation's people who is not the president.
func _person() -> String:
	var nation = _loader.nations[PLAYER]
	for person in _loader.people[PLAYER]:
		if person.id != nation.head_of_state_person_id and person.id != nation.head_of_government_person_id \
				and String(person.kind) != "press_owner":
			return String(person.id)
	return ""


func _summed(state, ns) -> float:
	var total := 0.0
	for route in SC.ROUTES:
		total += Exposure.hazard(state, ns, _loader, route)
	return total


## The B6 amendment's own case: three declines of 0.10 from 0 read -0.30000000000000004
## in doubles, and must read ON the cut (-0.30 is still wary, not cold).
func _check_cut_counts_a_sum_on_the_cut_as_on_it() -> void:
	var three := 0.0
	for _i in range(3):
		three -= 0.1
	if three == -0.3:
		_failures.append("fixture: the three declines summed exactly; the tolerance check would be vacuous")
	if Cut.below(three, -0.30) or not Cut.at_or_above(three, -0.30):
		_failures.append("a sum within 1e-9 of -0.30 read as below the cut")
	if not Cut.below(-0.3001, -0.30) or Cut.above(0.30 + 1e-12, 0.30) or not Cut.at_or_below(0.30 + 1e-12, 0.30):
		_failures.append("Cut's four comparisons disagree with the declared brackets")


func _check_no_evidence_no_hazard() -> void:
	var state = _state()
	var ns = state.player()
	for route in SC.ROUTES:
		if Exposure.hazard(state, ns, _loader, route) != 0.0:
			_failures.append("route %s has a hazard with no evidence" % route)
	var before := JSON.stringify(ns.to_dict())
	if not Exposure.tick_month(state, _loader).is_empty() or JSON.stringify(ns.to_dict()) != before:
		_failures.append("a month with no evidence exposed or wrote something")


## I1: two identical states, 60 months, identical exposures and armings -- and a
## pile big enough that the run is not vacuous.
func _check_determinism() -> void:
	var runs: Array[String] = []
	for _run in range(2):
		var state = _state()
		var ns = state.player()
		var pid := _person()
		for kind in ["diverted_budget", "personal_wealth", "party_money"]:
			President.leave_evidence(state, ns, _loader, kind, pid, 40.0)
		var made: Array = []
		for _m in range(60):
			_advance(state)
			made.append_array(Exposure.tick_month(state, _loader))
		if made.is_empty():
			_failures.append("fixture: 60 months at the hazard ceiling exposed nothing")
			return
		runs.append(JSON.stringify([made, ns.exposures, ns.exposure_evidence, ns.event_armed]))
	if runs[0] != runs[1]:
		_failures.append("two identical states exposed differently over 60 months")


## Spec C7: a captured court prosecutes nobody; the press still digs.
func _check_captured_court_never_exposes() -> void:
	var state = _state()
	var ns = state.player()
	President.leave_evidence(state, ns, _loader, "personal_wealth", _person(), 1.0)
	ns.judicial_independence = 0.0
	if Exposure.hazard(state, ns, _loader, "courts") != 0.0:
		_failures.append("a captured court has a hazard")
	if Exposure.hazard(state, ns, _loader, "press") <= 0.0:
		_failures.append("the press lost its hazard with the courts")
	ns.judicial_independence = JK.INDEPENDENCE_MAX
	var full := Exposure.hazard(state, ns, _loader, "courts")
	if not is_equal_approx(full, SC.RATE["courts"] * SC.EVIDENCE_WEIGHT["personal_wealth"]):
		_failures.append("the courts read independence off its 0-100 scale: %f" % full)


## Only a rival or an enemy talks, and only one the register still covers.
func _check_turned_needs_a_turned_person() -> void:
	var state = _state()
	var ns = state.player()
	var pid := _person()
	President.leave_evidence(state, ns, _loader, "favour", pid, 1.0)
	President.learn(state, ns, _loader, pid, 0.5)
	if President.relationship(ns, pid) != "acquaintance":
		_failures.append("fixture: the person is not an acquaintance")
	if Exposure.hazard(state, ns, _loader, "turned") != 0.0:
		_failures.append("an acquaintance can turn")
	President.set_bond(state, ns, _loader, pid, "enemy")
	if Exposure.hazard(state, ns, _loader, "turned") <= 0.0:
		_failures.append("an enemy cannot turn")
	for route in ["courts", "auditors"]:
		if Exposure.hazard(state, ns, _loader, route) != 0.0:
			_failures.append("route %s reaches a favour" % route)
	# #170's call 1 (Gameplay #171): journalists dig up backroom deals.
	if Exposure.hazard(state, ns, _loader, "press") <= 0.0:
		_failures.append("the press does not reach a favour")


## B6's order, structurally: equal size, the person an enemy so every route is open,
## the courts fully independent -- the summed hazard rises with the currency.
func _check_currency_order() -> void:
	var summed: Array[float] = []
	for kind in ["favour", "party_money", "personal_wealth", "diverted_budget"]:
		var state = _state()
		var ns = state.player()
		var pid := _person()
		President.set_bond(state, ns, _loader, pid, "enemy")
		ns.judicial_independence = JK.INDEPENDENCE_MAX
		President.leave_evidence(state, ns, _loader, kind, pid, 1.0)
		summed.append(_summed(state, ns))
	for i in range(1, summed.size()):
		if summed[i] <= summed[i - 1]:
			_failures.append("the currency order broke: %s" % [summed])
			return


## The plan's Review focus 3: a predecessor's rows are not this desk's.
func _check_former_leader_rows_not_rolled() -> void:
	var state = _state()
	var ns = state.player()
	President.leave_evidence(state, ns, _loader, "diverted_budget", _person(), 40.0)
	ns.exposure_evidence[0]["leader_id"] = "FRA_somebody_else"
	if _summed(state, ns) != 0.0:
		_failures.append("a predecessor's evidence has a hazard")
	for _m in range(24):
		_advance(state)
		if not Exposure.tick_month(state, _loader).is_empty():
			_failures.append("a predecessor's evidence was exposed")
			return


## A hit arms its scandal for next month, and the game's own month delivers it. A
## fixture event for the pair (party money: only the auditors reach it while the
## person is not turned), after content's own -- exposure_event takes the first.
func _check_arms_the_event() -> void:
	var errors: Array[String] = []
	var ev = GameEvent.from_dict({
		"id": "probe_auditors_exposure", "name": "Probe", "summary": "A probe.", "likelihood": 0.002,
		"respond_months": 2, "category": "scandal", "severity": 2, "on_action": "exposure",
		"exposure": {"route": "auditors", "kinds": ["party_money"]},
		"choices": [
			{"id": "a", "label": "A", "summary": "A.", "default": true, "effects": {"bloc_offset": {"business": -0.02}}},
			{"id": "b", "label": "B", "summary": "B.", "effects": {"bloc_offset": {"workers": -0.02}}},
		],
	}, "probe.json", errors, [], [], OpinionK.BLOC_KEYS, [])
	if not errors.is_empty():
		_failures.append("fixture event did not load: %s" % [errors])
		return
	_loader.events.append(ev)
	var armed_id := String(Events.exposure_event(_loader, "auditors", "party_money").id)
	var state = _state()
	var ns = state.player()
	President.leave_evidence(state, ns, _loader, "party_money", _person(), 400.0)
	var hit := {}
	for _m in range(60):
		_advance(state)
		for row in Exposure.tick_month(state, _loader):
			if String(row["route"]) == "auditors":
				hit = row
		if not hit.is_empty():
			break
	if hit.is_empty():
		_failures.append("60 months at the auditors' ceiling exposed nothing")
	elif String(hit.get("event_id", "")) != armed_id or ns.exposures.is_empty():
		_failures.append("the auditors' hit did not name its scandal or reach the register: %s" % [hit])
	else:
		var due := false
		for entry in ns.event_armed:
			due = due or (String(entry["event_id"]) == armed_id and int(entry["due_index"]) == _now(state) + 1)
		if not due:
			_failures.append("the scandal was not armed for next month: %s" % [ns.event_armed])
		_advance(state)
		WorldMonth.tick_month(state, _loader)
		var on_desk := false
		for entry in ns.event_queue:
			on_desk = on_desk or String(entry.get("event_id", entry.get("id", ""))) == armed_id
		if not on_desk:
			_failures.append("the game's month did not deliver the armed scandal")
	_loader.events.erase(ev)



## Gameplay's scandal floor (B5, #161): an exposure's price belongs to its arrival,
## not to an answer -- the block's `on_arrival` effects land once, through the
## applier, the month the evidence is found, whatever the player later answers.
func _check_on_arrival_applies_once() -> void:
	var errors: Array[String] = []
	var ev = GameEvent.from_dict({
		"id": "probe_arrival_exposure", "name": "Probe", "summary": "A probe.", "likelihood": 0.002,
		"respond_months": 2, "category": "scandal", "severity": 2, "on_action": "exposure",
		"exposure": {"route": "auditors", "kinds": ["party_money"], "on_arrival": {"bloc_offset": {"workers": -0.05}}},
		"choices": [
			{"id": "a", "label": "A", "summary": "A.", "default": true, "effects": {"bloc_offset": {"business": -0.02}}},
			{"id": "b", "label": "B", "summary": "B.", "effects": {"bloc_offset": {"workers": -0.02}}},
		],
	}, "probe.json", errors, [], [], OpinionK.BLOC_KEYS, [])
	if not errors.is_empty() or (ev.exposure_on_arrival as Dictionary).is_empty():
		_failures.append("an on_arrival block did not load: %s" % [errors])
		return
	_loader.events.push_front(ev)
	var state = _state()
	var ns = state.player()
	President.leave_evidence(state, ns, _loader, "party_money", _person(), 400.0)
	var before := float(ns.bloc_offset.get("workers", 0.0))
	var hit_month := -1
	for m in range(60):
		_advance(state)
		for row in Exposure.tick_month(state, _loader):
			if String(row["event_id"]) == "probe_arrival_exposure":
				hit_month = m
		if hit_month >= 0:
			break
	if hit_month < 0:
		_failures.append("fixture: 60 months at the auditors' ceiling exposed nothing")
	elif not is_equal_approx(float(ns.bloc_offset.get("workers", 0.0)) - before, -0.05):
		_failures.append("on_arrival moved workers by %.3f, not -0.05" % (float(ns.bloc_offset.get("workers", 0.0)) - before))
	else:
		_advance(state)
		Exposure.tick_month(state, _loader)
		if not is_equal_approx(float(ns.bloc_offset.get("workers", 0.0)) - before, -0.05):
			_failures.append("on_arrival landed again the month after")
	_loader.events.erase(ev)


func _finish() -> void:
	if _failures.is_empty():
		print("test_exposure: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
