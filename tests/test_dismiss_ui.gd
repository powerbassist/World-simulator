extends SceneTree

## Headless test: godot --headless --script res://tests/test_dismiss_ui.gd
## Non-zero exit on any failure.
##
## V5.2 b+ R4's interface half (docs/design/v5.2-bplus-spec.md "R4"; Systems'
## #142 built the command): Government > Politics carries Dismiss beside Reassign.
##   - a real click on Dismiss asks first, naming the party and its leader's
##     feeling after the pulse in R11's words, and changes nothing;
##   - Dismiss on the card vacates the office and reaches main's effect queue;
##   - a second removal of that office within the year is refused with the sim's
##     reason, and no card opens;
##   - the Diary refuses a Reassign booking the limit will refuse on its day
##     (Removal.why_not at booking, not only on the day).

const Removal = preload("res://src/sim/removal.gd")
const President = preload("res://src/sim/president.gd")
const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const CabinetVerbs = preload("res://src/ui/cabinet_verbs.gd")
const DiaryDriver = preload("res://src/ui/diary_driver.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _verbs
var _portfolio := ""
var _party := ""
var _leader := ""
var _target: Control


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._windows.open("politics")
		6:
			_verbs = _main._government_panel.find_child("CabinetVerbs", true, false)
			if _verbs == null or not _verbs.is_visible_in_tree():
				_fail("Politics has no cabinet verbs on screen")
				return _end()
			_pick_portfolio()
			if _portfolio == "":
				return _end()
			_target = _verbs.find_child("Dismiss", true, false) as Control
			_press(true)
		9:
			_press(false)
		12:
			var card := _card()
			var ns = _main._state.player()
			if card == null or not card.is_visible_in_tree():
				_fail("a click on Dismiss does not ask first")
				return _end()
			var text := _text(card)
			var party_name := ""
			for p in _main._loader.parties[String(ns.id)]:
				if String(p.id) == _party:
					party_name = String(p.party_name)
			if not text.contains(party_name) or not text.contains(_main._loader.person_name(_leader)) or not text.contains("they will be"):
				_fail("the card does not name the party, its leader and their feeling after: %s" % text)
			# QA's TAKE on #155: Cabinet.loyalty feeds the ministers' resignation check,
			# not a division's rebels (ns.party_discipline does) -- the card says so.
			# Said only when the party's loyalty falls AND a minister stays who could
			# resign (`others`, QA on #162).
			var price := Removal.price(_main._state, ns, _main._loader, _portfolio)
			var resigns := float(price["loyalty_after"]) < float(price["loyalty_before"]) - 1e-9 and int(price["others"]) > 0
			if text.contains("break ranks") or text.contains("likelier to resign") != resigns:
				_fail("the card promises an effect the sim does not have (%s): %s" % [price, text])
			_check_last_minister(ns)
			if String(ns.cabinet[_portfolio]) != _party:
				_fail("the click dismissed before the card was answered")
			# The clock runs behind the card: the leader's feeling changes under it
			# (here a grudge that crosses into the next band), so its price is stale
			# and Dismiss asks again rather than pay what it did not show.
			ns.person_grudges[_leader] = 0.5
			card.confirmed.emit()
			if not card.is_visible_in_tree() or String(ns.cabinet[_portfolio]) != _party or not _text(card).contains("bitter"):
				_fail("a stale price was paid, not asked again: %s" % _text(card))
			_target = card.find_child("Confirm", true, false) as Control
			_press(true)
		15:
			_press(false)
		18:
			var ns = _main._state.player()
			if String(ns.cabinet.get(_portfolio, "")) != "":
				_fail("Dismiss on the card did not vacate %s" % _portfolio)
			# Titled as what happened (the parent's call 3): nothing was reassigned.
			if not str(_main._pending_effects).contains("Minister dismissed") or str(_main._pending_effects).contains("Cabinet reassigned"):
				_fail("the dismissal did not reach main's effect queue as a dismissal: %s" % [_main._pending_effects])
			_verbs.select_portfolio(_portfolio)
			_target = _verbs.find_child("Dismiss", true, false) as Control
			_press(true)
		21:
			_press(false)
		24:
			if _card().is_visible_in_tree():
				_fail("a refused dismissal opened the card")
			var why := Removal.why_not(_main._state, _main._state.player(), _portfolio, "")
			if why == "" or not String(_verbs.status_text()).contains(why):
				_fail("a refused dismissal does not say why: '%s' (the sim: '%s')" % [_verbs.status_text(), why])
			_check_diary_booking()
			return _end()
	return false


## A portfolio held by a party whose leader is not the president: its removal
## writes a pulse, so the card has a feeling to name.
## QA's RECORD on #162: a party whose last minister is the one dismissed has no
## minister left to resign (Removal.price's `others` is 0), so the card does not
## say its ministers are likelier to.
func _check_last_minister(ns) -> void:
	var cabinet: Dictionary = ns.cabinet.duplicate()
	for portfolio in ns.cabinet.keys():
		if portfolio != _portfolio and String(ns.cabinet[portfolio]) == _party:
			ns.cabinet[portfolio] = ""
	var text: String = _verbs._price(_portfolio)
	# And the line's own case: entitled to two posts and holding two, the party
	# loses loyalty with this one (Cabinet.shortfall) and keeps a minister.
	var entitled: Dictionary = ns.cabinet_entitlement.duplicate()
	ns.cabinet_entitlement[_party] = 2
	for portfolio in ns.cabinet.keys():
		if portfolio != _portfolio:
			ns.cabinet[portfolio] = _party
			break
	var kept: String = _verbs._price(_portfolio)
	ns.cabinet_entitlement = entitled
	ns.cabinet = cabinet
	if not kept.contains("likelier to resign"):
		_fail("a party that keeps a minister and loses loyalty is not told so: %s" % kept)
	if text.contains("likelier to resign"):
		_fail("the card says the ministers of a party with none left are likelier to resign: %s" % text)


func _pick_portfolio() -> void:
	var ns = _main._state.player()
	var president := President.leader_id(ns)
	for portfolio in CK.PORTFOLIO_KEYS:
		var pid := String(ns.cabinet.get(portfolio, ""))
		for p in _main._loader.parties[String(ns.id)]:
			var leader := Characters.party_leader(ns, pid, {pid: p.leader_person_id}) if String(p.id) == pid else ""
			if leader != "" and leader != president:
				_portfolio = portfolio
				_party = pid
				_leader = leader
				_verbs.select_portfolio(portfolio)
				return
	_fail("premise: every portfolio is held by the president's own party")


## Booked for next month, a Reassign of the office just dismissed: the limit will
## refuse it on its day, so the Diary refuses it now, with the sim's reason.
func _check_diary_booking() -> void:
	var state = _main._state
	var ns = state.player()
	var other := ""
	for pid in ns.coalition_party_ids:
		if String(pid) != _party:
			other = String(pid)
	# Fill the vacancy first: a refill is no removal, so the limit is what refuses.
	ns.cabinet[_portfolio] = other
	var total: int = int(state.year) * 12 + int(state.month)
	var entry := Calendar.make_entry(K.KIND_RESHUFFLE, total / 12, total % 12 + 1, 10, "", "", "", _portfolio, _party)
	var result: Dictionary = CabinetVerbs.book(state, entry)
	if bool(result.get("ok", false)) or String(result.get("error", "")) != Removal.why_not(state, ns, _portfolio, _party):
		_fail("the Diary booked a Reassign the limit refuses: %s" % [result])
	# Booked before the limit applied, refused on its day: the outcome and the day's
	# card carry the sim's reason (QA's R4 RECORD: "It did not carry." alone).
	state.appointments.append(entry)
	var outcomes: Array = []
	DiaryDriver.resolve(state, _main._loader, int(entry["year"]), int(entry["month"]), int(entry["day"]), func(o: Dictionary) -> void: outcomes.append(o))
	var why := Removal.why_not(state, ns, _portfolio, _party)
	if outcomes.size() != 1 or bool(outcomes[0]["ok"]) or String(outcomes[0].get("reason", "")) != why:
		_fail("a Reassign refused on its day carries no reason: %s" % [outcomes])
	elif not _main._world_news.appointment_text(entry, "Defence", false, why).contains(why):
		_fail("the day's card does not say why the Reassign did not carry")


func _card() -> Control:
	return _main.find_child("ConfirmCard", true, false) as Control


func _text(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + "\n"
	return out


func _press(down: bool) -> void:
	if _target == null:
		return
	var at: Vector2 = _target.get_global_rect().get_center()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = down
	click.position = at
	click.global_position = at
	_main.get_viewport().push_input(click, true)


func _fail(message: String) -> void:
	_failures.append(message)


func _end() -> bool:
	if _failures.is_empty():
		print("test_dismiss_ui: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
