extends SceneTree

## Headless test: godot --headless --script res://tests/test_government_panel.gd
## Non-zero exit on any failure.
##
## A smoke test for the government screen. It does not check pixels; it checks
## that the control tree builds, that every figure on it comes from live state,
## and that it says the right thing about a majority, a minority and a
## cohabitation rather than only rendering the happy case.
##
## Driven a frame at a time through MainLoop's _process, because a Control
## outside the tree has not run _ready() — see docs/engine-decision.md and
## test_budget_panel.gd's note.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Government = preload("res://src/sim/government.gd")
const GovernmentPanel = preload("res://src/ui/government_panel.gd")

var _failures: Array[String] = []
var _loader: DataLoader
var _state
var _panel
var _frame := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_state = GameState.new_game(_loader, "FRA")
	if not _state.errors.is_empty():
		_failures.append("new_game reported %s" % [_state.errors])
		_finish()
		return

	_panel = GovernmentPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_check_majority()
		2:
			_check_minority()
		3:
			_check_cohabitation()
			_finish()
	return false


func _refresh_text() -> String:
	_panel.setup(_state, _loader)
	_panel.show()
	_panel.mark_dirty()
	_panel._refresh()
	return _collect_text(_panel)


## The starting French government: a three-party majority of 318, censure at 289.
func _check_majority() -> void:
	var ns = _state.player()
	var text := _refresh_text()

	if not text.contains(ns.pm_name):
		_fail("panel does not name the head of government ('%s'): %s" % [ns.pm_name, text])
	if not text.contains(ns.head_of_government_title):
		_fail("panel does not give the head of government's title ('%s')" % ns.head_of_government_title)
	if not text.contains("%d" % ns.coalition_seats):
		_fail("panel does not show the coalition's seat count (%d)" % ns.coalition_seats)
	if not text.contains("%d" % Government.censure_seats(ns)):
		_fail("panel does not show the censure threshold (%d)" % Government.censure_seats(ns))
	if not text.contains("Majority government"):
		_fail("a 318-of-577 government is not described as a majority: %s" % text)

	# Every partner named, and every party outside it named as opposition.
	for party in _loader.parties["FRA"]:
		if not text.contains(party.party_name):
			_fail("panel omits '%s' entirely" % party.party_name)
	if not text.contains("In opposition"):
		_fail("panel does not list the opposition")


## A government below the majority line must say so. Forced by hand rather than
## played into, because France's authored roster starts with a majority.
func _check_minority() -> void:
	var ns = _state.player()
	ns.coalition_party_ids = ["renouveau_civique"]
	ns.coalition_seats = int(ns.seats_by_party.get("renouveau_civique", 0))
	ns.is_minority = true
	ns.is_cohabitation = false

	var text := _refresh_text()
	if not text.contains("MINORITY GOVERNMENT"):
		_fail("a one-party government of %d of %d seats is not flagged as a minority: %s" % [
			ns.coalition_seats, ns.assembly_seats, text
		])
	# 577 - 162 = 415 opposition seats against a 289 threshold, so the panel must
	# say a united opposition could remove this government.
	if not text.contains("could bring this government down"):
		_fail("a minority facing 415 opposition seats is not warned about censure: %s" % text)


## Cohabitation is the one outcome that is neither a win nor a loss, so the panel
## has to name it specifically rather than falling back to 'minority'.
func _check_cohabitation() -> void:
	var ns = _state.player()
	ns.coalition_party_ids = ["union_conservatrice", "parti_social_uni", "front_souverainiste"]
	ns.coalition_seats = 0
	for pid in ns.coalition_party_ids:
		ns.coalition_seats += int(ns.seats_by_party.get(pid, 0))
	ns.is_minority = false
	ns.is_cohabitation = true
	ns.pm_party_id = "union_conservatrice"
	ns.pm_name = "Hélène Vasseur"

	var text := _refresh_text()
	if not text.contains("COHABITATION"):
		_fail("a government excluding the President's party is not flagged as cohabitation: %s" % text)
	if not text.contains("Hélène Vasseur"):
		_fail("cohabitation panel does not name the imposed head of government: %s" % text)


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
		print("test_government_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
