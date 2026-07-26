extends SceneTree

## Headless test: godot --headless --script res://tests/test_law_panel.gd
## Non-zero exit on any failure.
##
## Loads the actual main scene, same shape test_election_panel.gd and
## test_game_loop.gd use. Driven a frame at a time because a Control outside
## the scene tree has not run _ready() and Range.value_changed does not emit
## -- see docs/engine-decision.md.

const Legislature = preload("res://src/sim/legislature.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return
	if _main._law_panel == null:
		_fail("main scene did not build a law panel")
		return

	var loader = _main._loader
	var ns = _main._state.player()

	# On the pristine assembly, before the mangling below destroys it.
	_check_rebellion_is_forecast_and_named(loader, ns)

	# Force a hostile assembly so the proposed law fails and names its
	# opponents -- the exact scenario the roadmap's done-when condition names.
	var law = _find_law(loader, "working_time_reduction")
	if law == null:
		_fail("law template 'working_time_reduction' not found")
		return

	var party_list: Array = loader.parties.get(ns.id, [])
	var furthest_id := ""
	var furthest_dist := -1.0
	for party in party_list:
		var support: float = Legislature.support(ns, party, law)
		if -support > furthest_dist:
			furthest_dist = -support
			furthest_id = party.id
	ns.seats_by_party = {}
	for party in party_list:
		ns.seats_by_party[party.id] = 0
	ns.seats_by_party[furthest_id] = ns.assembly_seats

	_main._law_panel.show()
	_main._law_panel.setup(_main._state, loader)
	_main._law_panel.mark_dirty()
	_main._law_panel._process(0.0)

	var text_before := _collect_text(_main._law_panel)
	if not text_before.contains(law.law_name):
		_fail("law panel does not list '%s' before proposing it" % law.law_name)

	_main._law_panel._on_propose(law)
	_main._law_panel._process(0.0)

	var text_after := _collect_text(_main._law_panel)
	if not text_after.contains("FAILED"):
		_fail("law panel does not report FAILED after a hostile-assembly vote: %s" % text_after)

	var opposing_party_name := ""
	for party in party_list:
		if party.id == furthest_id:
			opposing_party_name = party.party_name
	if opposing_party_name == "" or not text_after.contains(opposing_party_name):
		_fail("law panel does not name the opposing party '%s' after a failed vote: %s" % [opposing_party_name, text_after])

	if ns.last_law_result.is_empty():
		_fail("ns.last_law_result was not populated after proposing through the panel")
	elif ns.last_law_result["passed"]:
		_fail("expected the hostile assembly to reject the law, but ns.last_law_result says it passed")


## V1.1b. With the coalition's discipline eroded, the panel must warn that seats
## will break ranks *before* the vote and name who did afterwards. Silent
## rebellion is the failure mode: the player would see a bill they were told
## would pass fail for no visible reason.
##
## Discipline is written by hand; whether a played regime reaches it is
## tools/balance_probe.gd's question and is recorded in docs/discipline-model.md.
func _check_rebellion_is_forecast_and_named(loader, ns) -> void:
	var law = _find_law(loader, "housing_programme")
	if law == null:
		_fail("law template 'housing_programme' not found")
		return

	for pid in ns.coalition_party_ids:
		ns.party_discipline[pid] = 0.2

	_main._law_panel.show()
	_main._law_panel.setup(_main._state, loader)
	_main._law_panel.mark_dirty()
	_main._law_panel._process(0.0)

	var forecast := _collect_text(_main._law_panel)
	if not forecast.contains("expected to break ranks"):
		_fail("the forecast does not warn that seats will break ranks: %s" % forecast)

	_main._law_panel._on_propose(law)
	_main._law_panel._process(0.0)

	var after := _collect_text(_main._law_panel)
	if not after.contains("seats broke ranks"):
		_fail("the result does not report a rebellion: %s" % after)

	var rebels: Dictionary = ns.last_law_result.get("party_rebels", {})
	if rebels.is_empty():
		_fail("no party rebelled at 0.2 discipline, so the panel had nothing to name")
		return
	for party in loader.parties.get(ns.id, []):
		if int(rebels.get(party.id, 0)) > 0 and not after.contains(party.party_name):
			_fail("'%s' lost %d seats to a rebellion and is not named: %s" % [
				party.party_name, int(rebels[party.id]), after
			])


func _find_law(loader, law_id: String):
	for law in loader.laws:
		if law.id == law_id:
			return law
	return null


func _collect_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_law_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
