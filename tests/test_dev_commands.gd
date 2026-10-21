extends SceneTree

## Headless test: godot --headless --script res://tests/test_dev_commands.gd
## Non-zero exit on any failure.
##
## V5.1-0b. The dev console's ONLY door into the simulation (src/sim/dev_commands.gd):
## AGENTS.md rule 2 says the UI never writes GameState, so a cheat is a command that
## validates its field against src/core/nation_fields.gd's table and writes through
## here, the way Budget.commit() is the model for player intent. What must hold, each
## a silent failure if it does not:
##
##   - `get` reads any table field and `set` writes only a plain scalar one: a
##     container, a display record or the nation's id is refused WITH A REASON, and a
##     refused command leaves the state byte for byte as it was;
##   - a malformed value (text for a number, a fraction for an integer) is refused
##     rather than coerced to zero;
##   - the table is the validator: every scalar field in it takes `set` with its own
##     current value, so a new field is settable the day it is added to the table;
##   - `event` stages an event through the events system's own staging primitive and
##     refuses an unknown id, one already on the desk and a full desk.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationFields = preload("res://src/core/nation_fields.gd")
const Events = preload("res://src/sim/events.gd")
const EventsK = preload("res://src/sim/events_constants.gd")
const DevCommands = preload("res://src/sim/dev_commands.gd")

var _failures: Array[String] = []
var _loader
var _state


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_state = GameState.new_game(_loader, "FRA")

	_test_get()
	_test_set_types()
	_test_set_refusals_leave_the_state_alone()
	_test_the_table_is_the_validator()
	_test_stage_event()
	_test_person_report()
	_finish()


func _dump() -> String:
	return JSON.stringify(_state.to_dict(), "", true)


func _test_get() -> void:
	var ns = _state.player()
	var got: Dictionary = DevCommands.get_field(_state, "FRA", "gdp_eur_bn")
	if not bool(got["ok"]) or not str(got["text"]).contains("%s" % ns.gdp_eur_bn):
		_fail("get FRA.gdp_eur_bn did not read the live figure: %s" % [got])
	var me: Dictionary = DevCommands.get_field(_state, "me", "gdp_eur_bn")
	if not bool(me["ok"]) or me["text"] != got["text"]:
		_fail("the nation 'me' is not the player's: %s vs %s" % [me, got])
	var deu: Dictionary = DevCommands.get_field(_state, "DEU", "population")
	if not bool(deu["ok"]) or not str(deu["text"]).contains("%s" % _state.nations["DEU"].population):
		_fail("get reads the wrong nation: %s" % [deu])
	var container: Dictionary = DevCommands.get_field(_state, "FRA", "tax_rates_pct")
	if not bool(container["ok"]) or not str(container["text"]).contains("= {"):
		_fail("a container field should print as JSON: %s" % [container])
	for bad in [["XXX", "gdp_eur_bn"], ["FRA", "gdp"], ["FRA", ""]]:
		var refused: Dictionary = DevCommands.get_field(_state, bad[0], bad[1])
		if bool(refused["ok"]) or String(refused["text"]).is_empty():
			_fail("get %s.%s should be refused with a reason: %s" % [bad[0], bad[1], refused])


func _test_set_types() -> void:
	var ns = _state.player()
	var r: Dictionary = DevCommands.set_field(_state, "FRA", "gdp_eur_bn", "1234.5")
	if not bool(r["ok"]) or not is_equal_approx(ns.gdp_eur_bn, 1234.5):
		_fail("set a float field: %s gdp=%s" % [r, ns.gdp_eur_bn])
	r = DevCommands.set_field(_state, "me", "gdp_eur_bn", "77")
	if not bool(r["ok"]) or not is_equal_approx(ns.gdp_eur_bn, 77.0):
		_fail("set a float field from an integer, through 'me': %s" % [r])
	r = DevCommands.set_field(_state, "FRA", "assembly_seats", "551")
	if not bool(r["ok"]) or ns.assembly_seats != 551:
		_fail("set an integer field: %s" % [r])
	r = DevCommands.set_field(_state, "FRA", "has_budget", "false")
	if not bool(r["ok"]) or ns.has_budget:
		_fail("set a bool field: %s" % [r])
	r = DevCommands.set_field(_state, "FRA", "has_budget", "on")
	if not bool(r["ok"]) or not ns.has_budget:
		_fail("a bool takes 'on': %s" % [r])
	r = DevCommands.set_field(_state, "FRA", "incumbent_party_id", "some_party")
	if not bool(r["ok"]) or ns.incumbent_party_id != "some_party":
		_fail("set a string field: %s" % [r])
	if not str(r["text"]).contains("some_party"):
		_fail("the answer should name the new value: %s" % [r])


func _test_set_refusals_leave_the_state_alone() -> void:
	var before := _dump()
	var cases := [
		["XXX", "gdp_eur_bn", "1"],         # no such nation
		["FRA", "gdp", "1"],                # no such field
		["FRA", "id", "XXX"],               # the key every register is addressed by
		["FRA", "tax_rates_pct", "5"],      # a container: not a scalar
		["FRA", "last_investment_result", "5"],  # a display record, not saved
		["FRA", "gdp_eur_bn", "lots"],      # text for a float
		["FRA", "assembly_seats", "3.5"],   # a fraction for an integer
		["FRA", "has_budget", "maybe"],     # not a bool word
		["FRA", "gdp_eur_bn", ""],          # nothing
		["FRA", "gdp_eur_bn", "1e400"],     # overflows to INF, which a save turns into null
		["FRA", "gdp_eur_bn", "-1e400"],
		["FRA", "gdp_eur_bn", "nan"],
		["FRA", "gdp_eur_bn", "inf"],
	]
	for c in cases:
		var r: Dictionary = DevCommands.set_field(_state, c[0], c[1], c[2])
		if bool(r["ok"]) or String(r["text"]).is_empty():
			_fail("set %s.%s %s should be refused with a reason: %s" % [c[0], c[1], c[2], r])
	if _dump() != before:
		_fail("a refused set changed the state")


func _test_the_table_is_the_validator() -> void:
	var ns = _state.player()
	var settable := 0
	for row in NationFields.FIELDS:
		if row[NationFields.COL_COPY] != NationFields.SCALAR or row[NationFields.COL_READ] != NationFields.VALUE:
			continue
		var name: String = row[NationFields.COL_NAME]
		if name == "id":
			continue
		var current = ns.get(name)
		var r: Dictionary = DevCommands.set_field(_state, "FRA", name, str(current))
		if not bool(r["ok"]):
			_fail("the table lists %s as a scalar but set refused it: %s" % [name, r])
		elif not _same(ns.get(name), current):
			_fail("set %s with its own value moved it: %s -> %s" % [name, current, ns.get(name)])
		settable += 1
	if settable < 50:
		_fail("only %d scalar fields were swept -- the table walk is not walking" % settable)


## A float prints with fewer digits than it holds, so its round trip is approximate.
func _same(a, b) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(a, b)
	return a == b


func _test_stage_event() -> void:
	var ns = _state.player()
	ns.event_queue.clear()
	var ev = _loader.events[0]
	var r: Dictionary = DevCommands.stage_event(_state, _loader, "no_such_event")
	if bool(r["ok"]):
		_fail("an unknown event id was staged: %s" % [r])
	r = DevCommands.stage_event(_state, _loader, String(ev.id))
	if not bool(r["ok"]) or not Events.is_pending(ns) or Events.pending_event_id(ns) != String(ev.id):
		_fail("a known event did not reach the desk: %s queue=%s" % [r, ns.event_queue])
	r = DevCommands.stage_event(_state, _loader, String(ev.id))
	if bool(r["ok"]) or ns.event_queue.size() != 1:
		_fail("the same event was staged twice: %s queue=%d" % [r, ns.event_queue.size()])
	var staged := 1
	for other in _loader.events:
		if staged >= EventsK.QUEUE_MAX:
			break
		if String(other.id) != String(ev.id) and bool(DevCommands.stage_event(_state, _loader, String(other.id))["ok"]):
			staged += 1
	if ns.event_queue.size() != EventsK.QUEUE_MAX:
		_fail("could not fill the desk to its bound (%d)" % ns.event_queue.size())
	var extra = null
	for other in _loader.events:
		if not DevCommands.on_desk(ns, String(other.id)):
			extra = other
			break
	r = DevCommands.stage_event(_state, _loader, String(extra.id))
	if bool(r["ok"]) or ns.event_queue.size() != EventsK.QUEUE_MAX:
		_fail("a full desk took another event: %s queue=%d" % [r, ns.event_queue.size()])
	ns.event_queue.clear()


func _test_person_report() -> void:
	var id := ""
	for key in _loader.person_by_id.keys():
		id = String(key)
		break
	var r: Dictionary = DevCommands.person_report(_state, _loader, id)
	var person = _loader.person_by_id[id]
	if not bool(r["ok"]) or not str(r["text"]).contains(String(person.person_name)):
		_fail("person %s: %s" % [id, r])
	r = DevCommands.person_report(_state, _loader, "nobody_at_all")
	if bool(r["ok"]) or String(r["text"]).is_empty():
		_fail("an unknown person should be refused with a reason: %s" % [r])


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_dev_commands: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		printerr("test_dev_commands: %d check(s) failed" % _failures.size())
		quit(1)
