extends SceneTree

## Headless test: godot --headless --script res://tests/test_law_gate.gd
## Non-zero exit on any failure.
##
## V5.3 Bills second pass (the author's "A : les rayons"): a law that cannot be put to the
## Assembly stays on its shelf and says why on its row, and the reason is the SIM's -- one gate
## (src/sim/law_gate.gd) that Legislature.available() itself reads, so the row never says
## "open" about a law the press would refuse, nor a reason the sim does not hold. Pinned:
##   - available() is exactly the laws whose gate reads "";
##   - each closing rule names its own flag (a lost vote's cooldown, a once-only law passed,
##     a held bill, a referendum in flight, a law of another constitution);
##   - the gate writes nothing.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LawGate = preload("res://src/sim/law_gate.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_available_is_the_open_gate()
	_check_each_rule_names_its_flag()
	_check_the_gate_writes_nothing()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_law_gate.gd")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL " + f)
	quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _law(id: String):
	for law in _loader.laws:
		if String(law.id) == id:
			return law
	return null


func _first(pred: Callable):
	for law in _loader.laws:
		if pred.call(law):
			return law
	return null


func _check_available_is_the_open_gate() -> void:
	var ns = GameState.new_game(_loader, "FRA").player()
	var open: Array = Legislature.available(ns, _loader.laws).map(func(law): return String(law.id))
	var gated: Array = _loader.laws.filter(func(law): return LawGate.shut(ns, law) == "").map(func(law): return String(law.id))
	if open != gated:
		_fail("available() and the gate disagree: %d open, %d by the gate" % [open.size(), gated.size()])
	if open.size() < 20 or open.size() >= _loader.laws.size():
		_fail("premise: %d of %d laws open at the start" % [open.size(), _loader.laws.size()])


func _check_each_rule_names_its_flag() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var ordinary = _first(func(law): return not law.constitutional and not law.once and law.preconditions.is_empty())
	ns.law_cooldown_months[ordinary.id] = 7
	_expect(ns, ordinary, LawGate.COOLDOWN)
	ns.law_cooldown_months.erase(ordinary.id)
	_expect(ns, ordinary, "")
	ns.held_bills[ordinary.id] = {"months": 3, "origin": "player"}
	_expect(ns, ordinary, LawGate.HELD)
	ns.held_bills.erase(ordinary.id)
	var once = _first(func(law): return law.once)
	if once == null:
		_fail("premise: no once-only law")
	else:
		ns.passed_law_ids[once.id] = true
		_expect(ns, once, LawGate.PASSED)
	var foreign = _first(func(law): return law.constitutional and not law.systems.has(ns.system_id))
	if foreign == null:
		_fail("premise: no law of another constitution")
	else:
		_expect(ns, foreign, LawGate.CONSTITUTION)
	var gated = _first(func(law): return not law.preconditions.is_empty() and not Legislature.preconditions_met(ns, law.preconditions))
	if gated != null:
		_expect(ns, gated, LawGate.CONDITIONS)


func _expect(ns, law, flag: String) -> void:
	var got: String = LawGate.shut(ns, law)
	if got != flag:
		_fail("%s: the gate reads '%s', want '%s'" % [law.id, got, flag])
	var listed := Legislature.available(ns, [law]).size() == 1
	if listed != (flag == ""):
		_fail("%s: available() %s it while the gate reads '%s'" % [law.id, "lists" if listed else "drops", got])


func _check_the_gate_writes_nothing() -> void:
	var ns = GameState.new_game(_loader, "FRA").player()
	var before: String = JSON.stringify(ns.to_dict())
	for law in _loader.laws:
		LawGate.shut(ns, law)
	if JSON.stringify(ns.to_dict()) != before:
		_fail("the gate wrote to the nation")
