extends SceneTree

## V5.2c Task 2. The chain door as a command (Events.arm) and the chain-only
## exposure events: an exposure is armed by the exposure machine, waits on a full
## desk rather than being lost, and is never drawn by the standing hazard or fired by
## a hook. The plan: .superpowers/sdd/v5.2c-plan.md, Task 2.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const GameEvent = preload("res://src/core/event.gd")
const Events = preload("res://src/sim/events.gd")
const K = preload("res://src/sim/events_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

const PLAYER := "FRA"
const ARMED := "procurement_scandal"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_arm_delivers_next_month()
	_check_arm_waits_on_a_full_desk()
	_check_arm_refuses_an_unknown_event()
	_check_exposure_block_validated()
	_check_exposure_events_are_chain_only()
	_finish()


func _state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	return state


func _index(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _on_desk(ns, event_id: String) -> bool:
	for entry in ns.event_queue:
		if String(entry.get("event_id", entry.get("id", ""))) == event_id:
			return true
	return false


func _next_month(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	Events.tick_month(state, _loader)


func _check_arm_delivers_next_month() -> void:
	var state = _state()
	var ns = state.player()
	if not Events.arm(ns, _loader, ARMED, _index(state) + 1):
		_failures.append("arm() refused a known event")
		return
	_next_month(state)
	if not _on_desk(ns, ARMED):
		_failures.append("an event armed for next month did not reach the desk")


## A full desk is pre-mortem #2's failure: an exposure skipped for good. The chain
## door waits a month instead.
func _check_arm_waits_on_a_full_desk() -> void:
	var state = _state()
	var ns = state.player()
	var fillers: Array = []
	for ev in _loader.events:
		if fillers.size() >= K.QUEUE_MAX:
			break
		if String(ev.id) != ARMED and ev.on_action == "":
			fillers.append(ev)
	for ev in fillers:
		Events.announce(ns, ev, _index(state), {})
	Events.arm(ns, _loader, ARMED, _index(state) + 1)
	_next_month(state)
	if _on_desk(ns, ARMED):
		_failures.append("an armed event landed on a full desk")
	var waiting := false
	for armed in ns.event_armed:
		if String(armed.get("event_id", "")) == ARMED:
			waiting = true
	if not waiting:
		_failures.append("an armed event was dropped by a full desk instead of waiting")


func _check_arm_refuses_an_unknown_event() -> void:
	var state = _state()
	var ns = state.player()
	if Events.arm(ns, _loader, "no_such_event", _index(state) + 1) or not ns.event_armed.is_empty():
		_failures.append("arm() accepted an event content does not define")


func _exposure(route, kinds, on_action := "exposure") -> Dictionary:
	return {
		"id": "probe_exposure", "name": "Probe", "summary": "A probe.", "likelihood": 0.002,
		"respond_months": 2, "category": "scandal", "severity": 2, "on_action": on_action,
		"exposure": {"route": route, "kinds": kinds},
		"choices": [
			{"id": "a", "label": "A", "summary": "A.", "default": true, "effects": {"bloc_offset": {"business": -0.02}}},
			{"id": "b", "label": "B", "summary": "B.", "effects": {"bloc_offset": {"workers": -0.02}}},
		],
	}


func _errors_of(d: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	GameEvent.from_dict(d, "probe.json", errors, [], [], OpinionK.BLOC_KEYS, [])
	return errors


func _check_exposure_block_validated() -> void:
	if not _errors_of(_exposure("press", ["personal_wealth"])).is_empty():
		_failures.append("a valid exposure block was refused: %s" % [_errors_of(_exposure("press", ["personal_wealth"]))])
	for bad in [_exposure("tabloids", ["affair"]), _exposure("press", ["party_money"]),
			_exposure("auditors", []), _exposure("courts", ["diverted_budget"], "law_passed")]:
		if _errors_of(bad).is_empty():
			_failures.append("a malformed exposure block loaded: %s" % [bad["exposure"]])
	var arrival := _exposure("press", ["affair"])
	arrival["exposure"]["on_arrival"] = {"bloc_offset": {"workers": -0.03}}
	if not _errors_of(arrival).is_empty():
		_failures.append("a valid on_arrival block was refused: %s" % [_errors_of(arrival)])
	arrival["exposure"]["on_arrival"] = {"no_such_channel": 1.0}
	if _errors_of(arrival).is_empty():
		_failures.append("an on_arrival naming no effect channel loaded")
	var no_block := _exposure("press", ["affair"])
	no_block.erase("exposure")
	if _errors_of(no_block).is_empty():
		_failures.append("an on_action 'exposure' event with no exposure block loaded")


## Chain-only: neither the hazard nor a hook ever delivers an exposure event; the
## lookup finds the first event naming the route and the kind.
func _check_exposure_events_are_chain_only() -> void:
	var errors: Array[String] = []
	var d := _exposure("press", ["personal_wealth", "affair"])
	d["likelihood"] = K.LIKELIHOOD_MAX
	var ev = GameEvent.from_dict(d, "probe.json", errors, [], [], OpinionK.BLOC_KEYS, [])
	# The shipped exposure scandals (data/events/shadows.json) come first in content
	# order and would win the lookup, so the probe stands alone while it runs.
	var shipped: Array = []
	for existing in _loader.events.duplicate():
		if String(existing.on_action) == "exposure":
			shipped.append(existing)
			_loader.events.erase(existing)
	_loader.events.append(ev)
	if Events.exposure_event(_loader, "press", "affair") != ev or Events.exposure_event(_loader, "courts", "affair") != null:
		_failures.append("exposure_event() did not find the event by route and kind")
	var state = _state()
	for _m in range(36):
		_next_month(state)
		if _on_desk(state.player(), "probe_exposure"):
			_failures.append("an exposure event reached the desk without being armed")
			break
	_loader.events.erase(ev)
	_loader.events.append_array(shipped)


func _finish() -> void:
	if _failures.is_empty():
		print("test_event_arm: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
