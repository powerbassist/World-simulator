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
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")

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
	_state.year = 2026
	_state.month = 1

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
		4:
			_check_eroded_discipline_is_visible()
		5:
			_check_cabinet_entitled_reading()
		6:
			_check_cabinet_shorted_reading()
		7:
			_check_cabinet_vacant_reading()
		8:
			_check_dissolve_button()
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

	var pm_name: String = _loader.person_name(ns.pm_person_id)
	if not text.contains(pm_name):
		_fail("panel does not name the head of government ('%s'): %s" % [pm_name, text])
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
	if not text.contains("bring this government down on its own"):
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
	ns.pm_person_id = "FRA_vasseur"

	var text := _refresh_text()
	if not text.contains("COHABITATION"):
		_fail("a government excluding the President's party is not flagged as cohabitation: %s" % text)
	if not text.contains("Hélène Vasseur"):
		_fail("cohabitation panel does not name the imposed head of government: %s" % text)


## V1.1b: a partner that has slipped below its authored discipline must say so on
## the panel, and the seats it would lose on a bill must be shown before the
## player proposes one rather than after the vote. A silent erosion is a
## mechanic the player cannot play around.
func _check_eroded_discipline_is_visible() -> void:
	var ns = _state.player()
	# Back to the starting government, then eroded by hand -- whether a played
	# regime reaches this discipline is tools/balance_probe.gd's question.
	ns.coalition_party_ids = ["renouveau_civique", "alliance_verte", "parti_social_uni"]
	ns.coalition_seats = 0
	for pid in ns.coalition_party_ids:
		ns.coalition_seats += int(ns.seats_by_party.get(pid, 0))
	ns.is_minority = false
	ns.is_cohabitation = false

	var at_ceiling := _breakable_seats(_refresh_text())
	if at_ceiling < 0:
		_fail("panel does not warn how many coalition seats would break ranks")
		return
	if _refresh_text().contains(" of 0.85"):
		_fail("a coalition sitting at its authored figure prints a drift it does not have")

	for pid in ns.coalition_party_ids:
		ns.party_discipline[pid] = 0.45

	var text := _refresh_text()
	if not text.contains("discipline"):
		_fail("panel has no discipline column: %s" % text)
	if not text.contains("0.45 of 0.85"):
		_fail("panel does not show live discipline against the authored figure: %s" % text)

	var eroded := _breakable_seats(text)
	if eroded <= at_ceiling:
		_fail("eroding the coalition to 0.45 did not raise the seats at risk: %d against %d" % [
			eroded, at_ceiling
		])


## V1.1d: a fully entitled cabinet -- five portfolios, five distinct holders,
## none vacant, none flagged short of entitlement. Reformed fresh because the
## prior frame eroded discipline and reassigned the coalition by hand.
func _check_cabinet_entitled_reading() -> void:
	var ns = _state.player()
	var party_list: Array = _loader.parties.get("FRA", [])
	Government.form(ns, party_list)
	Cabinet.seat(ns, party_list)

	var text := _refresh_text()
	if not text.contains("Cabinet"):
		_fail("panel has no Cabinet section: %s" % text)
	for f in CK.PORTFOLIO_KEYS:
		var label: String = _panel.PORTFOLIO_LABEL.get(f, f)
		if not text.contains(label):
			_fail("cabinet table omits portfolio '%s': %s" % [label, text])
	if text.contains("VACANT"):
		_fail("a freshly seated cabinet reads a vacancy: %s" % text)
	for f in CK.PORTFOLIO_KEYS:
		if String(ns.cabinet.get(f, "")) == "":
			_fail("portfolio '%s' is unseated after a fresh seat() call" % f)


## A party held below its d'Hondt entitlement must read as short on the panel,
## with the entitlement cell naming held-against-entitled -- the condition
## docs/cabinet-model.md ties to a reachable resignation.
func _check_cabinet_shorted_reading() -> void:
	var ns = _state.player()
	var target := ""
	for pid in ns.coalition_party_ids:
		if int(ns.cabinet_entitlement.get(pid, 0)) > 0:
			target = pid
			break
	if target == "":
		_fail("no coalition party is entitled to a portfolio -- cannot test the shorted reading")
		return

	var held_portfolio := ""
	for f in CK.PORTFOLIO_KEYS:
		if String(ns.cabinet.get(f, "")) == target:
			held_portfolio = f
			ns.cabinet[f] = ""
			break
	if held_portfolio == "":
		_fail("'%s' is entitled but holds no portfolio -- seat() did not distribute entitlement" % target)
		return

	var text := _refresh_text()
	var entitled: int = int(ns.cabinet_entitlement.get(target, 0))
	var expected := "%d of %d" % [entitled - 1, entitled]
	if not text.contains(expected):
		_fail("shorted party's entitlement cell does not read '%s': %s" % [expected, text])

	# Restore for later frames.
	ns.cabinet[held_portfolio] = target


## A vacant portfolio reads VACANT rather than an empty cell -- silent
## vacancies are exactly the kind of failure docs/opinion-model.md's own
## standard for a game model rejects.
func _check_cabinet_vacant_reading() -> void:
	var ns = _state.player()
	var f: String = CK.PORTFOLIO_KEYS[0]
	var previous_holder: String = String(ns.cabinet.get(f, ""))
	ns.cabinet[f] = ""

	var text := _refresh_text()
	if not text.contains("VACANT"):
		_fail("an empty portfolio does not read VACANT: %s" % text)

	ns.cabinet[f] = previous_holder


## V1.1c: the dissolve button reads three ways, the same precedent Article
## 49.3's Force button set at law_panel.gd -- absent where the rule forbids it
## outright, disabled with a stated reason where it does not apply right now,
## and enabled otherwise.
func _check_dissolve_button() -> void:
	# France, month 1 of a fresh game: executive_discretion, no lockout, and the
	# next scheduled election (June 2029) is nowhere near the blackout window.
	_refresh_text()
	if not _panel._dissolve_button.visible:
		_fail("dissolve button is hidden for FRA, which can dissolve at will")
	if _panel._dissolve_button.disabled:
		_fail("dissolve button is disabled for FRA with no lockout and no blackout: %s" % _panel._dissolve_button.tooltip_text)

	var ns = _state.player()
	ns.dissolution_lockout_remaining = 6
	_refresh_text()
	if not _panel._dissolve_button.disabled:
		_fail("dissolve button is enabled during an active lockout")
	if not _panel._dissolve_button.tooltip_text.contains("6"):
		_fail("disabled dissolve button does not name the months remaining: %s" % _panel._dissolve_button.tooltip_text)
	ns.dissolution_lockout_remaining = 0

	# A nation whose rule refuses the command outright gets no button at all --
	# Germany, confidence_failure, no confidence-vote mechanic exists yet.
	var deu_state = GameState.new_game(_loader, "DEU")
	if not deu_state.errors.is_empty():
		_fail("new_game(DEU) reported %s" % [deu_state.errors])
		return
	deu_state.year = 2026
	deu_state.month = 1
	_panel.setup(deu_state, _loader)
	_panel.mark_dirty()
	_panel._refresh()
	if _panel._dissolve_button.visible:
		_fail("dissolve button is shown for DEU, whose rule is confidence_failure")

	_panel.setup(_state, _loader)


## The number out of "Up to N of those break ranks", or -1 if the line is absent.
##
## The LAST such line, not the first: _refresh() frees the old labels with
## queue_free(), which does not take effect until the end of the frame, so within
## one frame the collected text still carries every earlier refresh's output.
func _breakable_seats(text: String) -> int:
	var found := -1
	for line in text.split("\n"):
		if line.begins_with("Up to "):
			found = int(line.trim_prefix("Up to ").split(" ")[0])
	return found


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
