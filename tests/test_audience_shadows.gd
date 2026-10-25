extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_shadows.gd
## Non-zero exit on any failure.
##
## V5.2c c1's interface half (.superpowers plan v5.2c-plan.md "What Interface must
## build"; Systems' Shadows and Lies): the shadows in the audience, through the
## real game and the sim's own commands (the UI writes no register):
##   - the bargain lists the two corrupt currencies by name, and their price --
##     evidence -- is read before the click and said after it;
##   - a request that comes with money shows the person's offer and Accept /
##     Refuse; a real Accept (press and release frames apart) pays the president
##     or the party through Shadows.accept_offer, a Refuse costs regard only;
##   - argue carries a lie toggle: ticked, the odds read the lie's range and the
##     press sends `lie`;
##   - after a flirt, "Propose an affair" reaches Shadows.begin_affair (begun, or
##     the person's reason said as a sentence, never a key), and an affair under
##     way offers "End the affair";
##   - a reason key the shadows return reads as a sentence.

const Audiences = preload("res://src/sim/audiences.gd")
const Levers = preload("res://src/sim/levers.gd")
const President = preload("res://src/sim/president.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const SC = preload("res://src/sim/shadow_constants.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const AudienceTalks = preload("res://src/ui/audience_talks.gd")
const Words = preload("res://src/ui/lever_words.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _person := ""
var _target: Button
var _before := {}
var _sent: Array = []


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_check_reason_words()
			if not _open_with_offer("executive"):
				return _end()
		5:
			_check_currencies()
			_check_offer_shown()
			_before = _money()
			_press(true)
		9:
			_press(false)
		11:
			_check_accepted()
			_check_lie_toggle()
		13:
			_check_lie_sent()
			_leave()
		15:
			if not _open_with_offer("press_owner"):
				return _end()
		17:
			_check_refuse()
			_flirt()
		19:
			_check_affair_proposal()
			return _end()
	return false


func _scene():
	return AudienceDriver.scene_of(_main)


func _session() -> Dictionary:
	return AudienceDriver._games[_main.get_instance_id()]["session"]


## A request from a person of `kind` that came with money, booked on its first
## free day and reached through the game's own day door. The offer is the sim's
## draw: the premise looks for a request that carries one, never assumes it.
func _open_with_offer(kind: String) -> bool:
	var state = _main._state
	var ns = state.player()
	var now: int = int(state.year) * 12 + int(state.month)
	var request := ""
	# Executives carry no wants of their own (a firm's chief asks about its trade):
	# the premise lends them the first want in the roster.
	var want := {}
	for person in _main._loader.people.get(String(ns.id), []):
		if want.is_empty() and not person.wants.is_empty():
			want = person.wants[0]
	for person in _main._loader.people.get(String(ns.id), []):
		if String(person.kind) != kind or not President.covers(state, ns, _main._loader, String(person.id)):
			continue
		Audiences._arrive(ns, person, person.wants[0] if not person.wants.is_empty() else want, now, [])
		if not (ns.audience_requests[-1].get("offer", {}) as Dictionary).is_empty():
			request = String(ns.audience_requests[-1]["id"])
			_person = String(person.id)
			break
	if request == "":
		_fail("premise: no %s request came with an offer" % kind)
		return false
	var day := {}
	for date in Audiences.offered_dates(state, ns, request):
		if bool(date["free"]):
			day = date
			break
	if day.is_empty() or not bool(Audiences.book(state, ns, _main._loader, request, day).get("ok", false)):
		_fail("premise: could not book the %s request" % kind)
		return false
	state.year = int(day["year"])
	state.month = int(day["month"])
	_main._on_day_advanced(int(day["year"]), int(day["month"]), int(day["day"]))
	return true


func _check_reason_words() -> void:
	for key in ["not_covered", "unmarried", "spouse", "already", "too_cold", "no_spark", "not_affair"]:
		var said := Words.reason(key)
		if said == key or said == "" or said.contains("_"):
			_fail("the shadows' reason key '%s' reads '%s', not a sentence" % [key, said])


## The bargain's picker names both corrupt currencies, and each one's price is
## written beside it before the click.
func _check_currencies() -> void:
	var bargain: Button = _scene().verbs.lever_button("bargain")
	var pick: OptionButton = bargain.get_parent().find_child("Currency", false, false)
	var spend: Label = bargain.get_parent().get_parent().get_child(bargain.get_parent().get_index() + 2)
	for currency in SC.CURRENCY_EVIDENCE:
		var at := -1
		for i in pick.item_count:
			if String((pick.get_item_metadata(i) as Dictionary).get("currency", "")) == currency:
				at = i
		if at < 0:
			_fail("the bargain does not list the %s currency" % currency)
			continue
		if pick.get_item_text(at) == currency:
			_fail("the %s currency is shown by its raw id" % currency)
		pick.select(at)
		pick.item_selected.emit(at)
		if spend.text == Words.spends_text({}, {}):
			_fail("the %s currency reads as costing nothing: '%s'" % [currency, spend.text])
	pick.select(0)
	pick.item_selected.emit(0)


func _check_offer_shown() -> void:
	var shadow = _scene().shadow
	_target = shadow.find_child("OfferAccept", true, false)
	var refuse: Button = shadow.find_child("OfferRefuse", true, false)
	if _target == null or refuse == null or not _target.is_visible_in_tree() or not refuse.is_visible_in_tree():
		_fail("a request with money shows no Accept / Refuse")
		_target = null
		return
	var line: Label = shadow.find_child("OfferLine", true, false)
	if line == null or line.text == "":
		_fail("the offer is not put in words")


## The money the offer pays, where it lands: the president's or the party's.
func _money() -> Dictionary:
	var ns = _main._state.player()
	return {"wealth": President.wealth_eur_m(ns, _main._loader, President.leader_id(ns)),
		"party": President.party_money_eur_m(ns, _main._loader, String(ns.incumbent_party_id))}


func _check_accepted() -> void:
	if _target == null:
		return
	var after := _money()
	var paid: float = (after["wealth"] - _before["wealth"]) + (after["party"] - _before["party"])
	if absf(paid - SC.OFFER_EUR_M) > 1e-6:
		_fail("a real click on Accept did not pay the offer through the sim (moved %s)" % paid)
	if _scene().shadow.find_child("OfferAccept", true, false).is_visible_in_tree():
		_fail("the answered offer is still on the table")
	if _scene()._result.text == "":
		_fail("the accepted offer's result is not said")


## Argue's lie toggle: ticked, the odds read the lie's own range.
func _check_lie_toggle() -> void:
	var argue: Button = _scene().verbs.lever_button("argue")
	var lie: CheckBox = argue.get_parent().find_child("Lie", false, false)
	if lie == null:
		_fail("argue has no lie toggle")
		return
	var row := {}
	for r in Levers.offered(_main._state, _main._state.player(), _main._loader, _session()):
		if String(r["lever"]) == "argue":
			row = r
	var odds: Label = argue.get_parent().get_parent().get_child(argue.get_parent().get_index() + 1)
	lie.button_pressed = true
	var want := Words.odds_text(float(row["lie"]["odds_lo"]), float(row["lie"]["odds_hi"]))
	if odds.text != want:
		_fail("a ticked lie shows %s, the sim's lie range is %s" % [odds.text, want])
	_scene().verbs.attempted.connect(func(lever: String, args: Dictionary) -> void: _sent.append([lever, args]))
	argue.pressed.emit()


func _check_lie_sent() -> void:
	if _sent.is_empty() or String(_sent[0][0]) != "argue" or not bool((_sent[0][1] as Dictionary).get("lie", false)):
		_fail("a ticked lie did not send `lie` with argue: %s" % [_sent])


func _leave() -> void:
	if not _scene()._over:
		_scene()._end.pressed.emit()
	_scene()._end.pressed.emit()


## Refuse: the regard falls by the sim's price, the money stays where it was.
func _check_refuse() -> void:
	var refuse: Button = _scene().shadow.find_child("OfferRefuse", true, false)
	if refuse == null or not refuse.is_visible_in_tree():
		_fail("the press owner's offer shows no Refuse")
		return
	var ns = _main._state.player()
	var rapport := President.rapport(ns, _person)
	var money := _money()
	refuse.pressed.emit()
	if absf(President.rapport(ns, _person) - (rapport - SC.OFFER_REFUSED_RAPPORT)) > 1e-6 and President.rapport(ns, _person) > -1.0 + 1e-6:
		_fail("a refused offer did not cost its regard through the sim")
	if _money() != money:
		_fail("a refused offer moved money")


func _flirt() -> void:
	var flirt: Button = _scene().verbs.topic_button("flirt")
	if flirt == null or flirt.disabled:
		_fail("premise: flirt is not offered (%s)" % (flirt.tooltip_text if flirt != null else "no button"))
		return
	flirt.pressed.emit()


## After the flirt the proposal is there; pressed, it begins the affair or the
## person says why not -- the reason a sentence. An affair under way offers its end.
func _check_affair_proposal() -> void:
	var ns = _main._state.player()
	var propose: Button = _scene().shadow.find_child("ProposeAffair", true, false)
	if propose == null or not propose.is_visible_in_tree():
		_fail("after a flirt there is no 'Propose an affair'")
		return
	var why := Shadows.may_begin_affair(_main._state, ns, _main._loader, _person)
	propose.pressed.emit()
	if why == "":
		if President.relationship(ns, _person) != "affair":
			_fail("a proposal the sim allows did not begin the affair")
	elif _scene()._result.text != Words.reason(why):
		_fail("a refused proposal says '%s', not the reason '%s'" % [_scene()._result.text, Words.reason(why)])
	if President.relationship(ns, _person) != "affair":
		President.set_bond(_main._state, ns, _main._loader, _person, "affair")
		_scene().shadow.show_for(AudienceTalks.view_of(_main, AudienceDriver._games[_main.get_instance_id()]))
	var stop: Button = _scene().shadow.find_child("EndAffair", true, false)
	if stop == null or not stop.is_visible_in_tree():
		_fail("an affair under way offers no 'End the affair'")
		return
	stop.pressed.emit()
	if President.relationship(ns, _person) == "affair":
		_fail("'End the affair' did not end it through the sim")


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
		print("test_audience_shadows: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
