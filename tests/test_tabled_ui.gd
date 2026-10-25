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
const Government = preload("res://src/sim/government.gd")
const Statute = preload("res://src/sim/statute.gd")
const President = preload("res://src/sim/president.gd")
const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const Strings = preload("res://src/ui/strings.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _law
var _card := ""
var _phase := 0
var _booked
var _day_card := ""


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
		_ when _frame > 10 and _phase == 0 and not _main._month_runner.running():
			_check_one_card()
			_book_a_bill()
			if _booked == null:
				return _end()
			_phase = 1
			_frame = 100
		103:
			_check_stale_result_hidden()
			_check_empty_list()
			var state = _main._state
			var next: int = int(state.year) * 12 + int(state.month) + 1
			var year := floori((next - 1) / 12.0)
			_main._on_month_elapsed(year, next - year * 12)
		_ when _frame > 104 and _phase == 1 and not _main._month_runner.running():
			_check_booked_one_card()
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
	# Article 49.3 adopts without a vote, so it is never tabled and stays open on
	# another bill (the parent's call on #173); it answers only to its cooldown.
	var ns = _main._state.player()
	var live := 0
	for b in detail.find_children("*", "Button", true, false):
		var verb := b as Button
		if verb.name == "Force":
			if verb.disabled != not Government.can_force(ns):
				_fail("49.3 is %s while a bill is tabled" % ("down" if verb.disabled else "live past its cooldown"))
			continue
		if not verb.disabled:
			live += 1
		elif not verb.tooltip_text.contains("before the Assembly"):
			_fail("a verb is down without saying a bill is before the Assembly: %s" % verb.text)
	if live > 0:
		_fail("%d Legislature verbs stay live while a bill is tabled" % live)
	if detail.find_child("Propose", true, false) == null:
		_fail("the detail has no Propose to hold")


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


## A second bill, booked in the Diary for today and reached through main's own
## appointment door: tabled, with the day's card.
func _book_a_bill() -> void:
	var state = _main._state
	var ns = state.player()
	for law in Legislature.available(ns, _main._loader.laws):
		if String(law.id) != String(_law.id):
			_booked = law
			break
	if _booked == null:
		_fail("premise: no second proposable law")
		return
	var total: int = int(state.year) * 12 + int(state.month)
	var day := 20
	var entry := Calendar.make_entry(CalendarK.KIND_LAW, total / 12, total % 12 + 1, day, "", "", String(_booked.id))
	state.appointments.append(entry)
	var before: Array = _main._hud.inbox._cards.keys()
	_main._resolve_appointments(int(entry["year"]), int(entry["month"]), day)
	if ns.tabled_bill.is_empty() or String(ns.tabled_bill.get("law_id", "")) != String(_booked.id):
		_fail("premise: the Diary did not table %s" % _booked.id)
		_booked = null
		return
	for id in _main._hud.inbox._cards:
		if not before.has(id):
			_day_card = String(id)
	_main._windows.open("legislature")
	_main._law_panel.mark_dirty()


## The previous bill's result is history while another waits: the page opens on the
## bill before the Assembly, not on last month's verdict.
func _check_stale_result_hidden() -> void:
	if _main._state.player().last_law_result.is_empty():
		_fail("premise: the first bill left no result")
	if _main._law_panel._result_box.get_child_count() > 0:
		_fail("the Legislature still shows the previous result while a bill is tabled")


## With nothing proposable the list still says which bill is before the Assembly.
func _check_empty_list() -> void:
	var laws = _main._law_panel.find_child("Laws", true, false)
	laws.fill(_main._state.player(), [], [])
	if not _texts(laws).contains("before the Assembly"):
		_fail("an empty list does not say a bill is before the Assembly: %s" % _texts(laws))
	_main._law_panel.mark_dirty()


## The Diary's day card carries the booked bill's verdict, and no second card does.
func _check_booked_one_card() -> void:
	var inbox = _main._hud.inbox
	if _day_card == "" or inbox.lane_of(_day_card) == "":
		_fail("the Diary's day card for %s is gone" % _booked.id)
		return
	var body := String(inbox._notes.get(_day_card, {}).get("body", ""))
	if not (body.begins_with("Carried") or body.begins_with("Defeated") or body.contains("held") or body.contains("struck")):
		_fail("the Diary's day card does not carry the verdict: '%s'" % body)
	if not _notes_titled(Strings.law_name(_booked)).is_empty():
		_fail("the booked bill's division pushed a second card")


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
