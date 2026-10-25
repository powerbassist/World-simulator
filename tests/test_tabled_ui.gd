extends SceneTree

## Headless test: godot --headless --script res://tests/test_tabled_ui.gd
## Non-zero exit on any failure.
##
## V5.2 b+ R2's interface half, on Systems' tabling (#173: Legislature.propose()
## TABLES a bill and it divides as the first step of the month's close):
##   - ONE CARD FOLLOWS THE BILL: the card the tabling pushed ("Tabled: the
##     Assembly votes on ...") carries the verdict after the division, in place --
##     no second card for the same bill;
##   - THE LEGISLATURE while a bill is before the Assembly says which and when, and
##     its verbs are down with that reason (propose() would refuse already_tabled);
##   - THE DISMISS CARD while a bill is tabled says what a dismissal does to its
##     division (Removal.price's forecast_before / forecast_after, Gameplay #157).

const Legislature = preload("res://src/sim/legislature.gd")
const Statute = preload("res://src/sim/statute.gd")
const President = preload("res://src/sim/president.gd")
const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _law
var _card := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_table_a_bill()
			if _law == null:
				return _end()
			_main._windows.open("legislature")
		6:
			_check_legislature()
			_main._windows.open("politics")
		9:
			_check_dismiss_card()
			var state = _main._state
			var next: int = int(state.year) * 12 + int(state.month) + 1
			var year := floori((next - 1) / 12.0)
			_main._on_month_elapsed(year, next - year * 12)
		_ when _frame > 10 and not _main._month_runner.running():
			_check_one_card()
			return _end()
	return false


## The first proposable law, through the panel's own propose path (the briefing's
## verb lands in run_proposal).
func _table_a_bill() -> void:
	var ns = _main._state.player()
	var open: Array = Legislature.available(ns, _main._loader.laws + Statute.custom_laws(ns))
	if open.is_empty():
		_fail("premise: no proposable law")
		return
	_law = open[0]
	_main._law_panel.run_proposal(_law)
	if ns.tabled_bill.is_empty():
		_fail("premise: proposing did not table %s" % _law.id)
		_law = null
		return
	for id in _notes_titled(Strings.law_name(_law)):
		_card = id
	if _card == "" or not String(_main._hud.inbox._notes[_card]["body"]).begins_with("Tabled"):
		_fail("the tabling pushed no 'Tabled' card for %s" % _law.id)


func _notes_titled(title: String) -> Array:
	var out: Array = []
	for id in _main._hud.inbox._notes:
		if String(_main._hud.inbox._notes[id]["title"]) == title:
			out.append(id)
	return out


func _texts(node: Node) -> String:
	var out := ""
	for child in node.find_children("*", "Control", true, false):
		if child is Label or child is RichTextLabel:
			out += String(child.text) + "\n"
	return out


## Which bill and when, and the verbs down with that reason.
func _check_legislature() -> void:
	var laws = _main._law_panel.find_child("Laws", true, false)
	var detail: VBoxContainer = laws._detail
	if not _texts(detail).contains(Strings.law_name(_law)) or not _texts(detail).contains("before the Assembly"):
		_fail("the Legislature does not say which bill is before the Assembly: %s" % _texts(detail))
	var live := 0
	for b in detail.find_children("*", "Button", true, false):
		if not (b as Button).disabled:
			live += 1
		elif not (b as Button).tooltip_text.contains("before the Assembly"):
			_fail("a verb is down without saying a bill is before the Assembly: %s" % (b as Button).text)
	if live > 0:
		_fail("%d Legislature verbs stay live while a bill is tabled" % live)


## A minister of a party other than the president's: dismissing them moves the
## tabled bill's division, and the card says so.
func _check_dismiss_card() -> void:
	var ns = _main._state.player()
	var verbs = _main._government_panel.find_child("CabinetVerbs", true, false)
	var president := President.leader_id(ns)
	for portfolio in CK.PORTFOLIO_KEYS:
		var pid := String(ns.cabinet.get(portfolio, ""))
		for p in _main._loader.parties[String(ns.id)]:
			if String(p.id) == pid and Characters.party_leader(ns, pid, {pid: p.leader_person_id}) != president:
				var text: String = verbs._price(portfolio)
				if not text.contains("The bill before the Assembly"):
					_fail("dismissing a %s minister says nothing of the tabled bill: %s" % [pid, text])
				return
	_fail("premise: every portfolio is held by the president's own party")


## After the division: the tabling's card carries the verdict, and it is the only
## card for the bill.
func _check_one_card() -> void:
	var cards := _notes_titled(Strings.law_name(_law))
	var body := String(_main._hud.inbox._notes.get(_card, {}).get("body", ""))
	if not (body.begins_with("Carried") or body.begins_with("Defeated") or body.contains("held") or body.contains("struck")):
		_fail("the tabled card does not carry the verdict: '%s'" % body)
	if cards.size() != 1:
		_fail("%d cards for one bill after its division, not one" % cards.size())


func _fail(message: String) -> void:
	_failures.append(message)


func _end() -> bool:
	if _failures.is_empty():
		print("test_tabled_ui: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
