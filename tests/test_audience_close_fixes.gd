extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_close_fixes.gd
## Non-zero exit on any failure.
##
## V5.2's closing play gate, its audience items (.superpowers/sdd/v5.2-gate-close-
## report.md), through the real game and the sim's own commands, on V5.3's screen (the
## affair's and the lie's widgets left it with the author's C4: Argue, Pressure, the lie and
## the shadows' offer are the sim's, not this screen's):
##   - R3: the person's party, by name and in the hemicycle's colour slot, on the
##     request card, the Diary's booking block and the scene's header -- a party's
##     LEADER included, whom the data names from the party, not the person;
##   - R5: the audience's end carries a STATUS-toned word that agrees with what
##     happened, never the colour alone -- a deal struck (the good tag driven) and a
##     second audience refused with nothing won; that second audience opens afresh.

const Audiences = preload("res://src/sim/audiences.gd")
const President = preload("res://src/sim/president.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Words = preload("res://src/ui/lever_words.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PartyChip = preload("res://src/ui/party_chip.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Levers = preload("res://src/sim/levers.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _person = null
var _request := ""
var _target: Button
var _said := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			if not _arrive():
				return _end()
			_check_card_party()
			_check_booking_party()
			_check_member_and_none()
		5:
			if not _reach_audience():
				return _end()
		7:
			_check_scene_party()
			_scene().cards.find_child("GrantButton", true, false).pressed.emit()
		9:
			_check_won_tone()
			_scene()._end.pressed.emit()
		11:
			_check_close_tone(ResultTone.GOOD, "an audience won")
			if not _arrive_other() or not _reach_audience():
				return _end()
		13:
			_scene().cards.find_child("RefuseButton", true, false).pressed.emit()
		15:
			_check_close_tone(ResultTone.BAD, "an audience refused with nothing won")
			_scene()._end.pressed.emit()
			return _end()
	return false


func _game() -> Dictionary:
	return AudienceDriver._games[_main.get_instance_id()]


func _scene():
	return AudienceDriver.scene_of(_main)


## A party's leader -- in the party by its leader_person, with no party_id of their
## own (the gate's "No party" case) -- whom the president covers and may flirt
## with, asks for an audience through the sim's own arrival; the lane is redrawn
## off the register.
func _arrive() -> bool:
	var state = _main._state
	var ns = state.player()
	var want := {}
	for person in _main._loader.people.get(String(ns.id), []):
		if want.is_empty() and not person.wants.is_empty():
			want = person.wants[0]
	# A leader with the spark first (the sim's seeded draw), so the begun-then-ended
	# path runs through the wiring; any covered leader otherwise.
	for need_spark in [true, false]:
		for person in _main._loader.people.get(String(ns.id), []):
			var pid := String(person.id)
			if _person != null or String(person.party_id) != "" or _led_by(pid) == "" or pid == String(ns.head_of_state_person_id) or pid == String(ns.pm_person_id):
				continue
			if not President.covers(state, ns, _main._loader, pid) or Shadows.flirt_why_not(state, ns, _main._loader, pid) != "":
				continue
			if need_spark and not Shadows.spark(ns, pid):
				continue
			_person = person
	if _person == null:
		_fail("premise: no covered party leader to see")
		return false
	var now: int = int(state.year) * 12 + int(state.month)
	Audiences._arrive(ns, _person, _person.wants[0] if not _person.wants.is_empty() else want, now, [])
	_request = String(ns.audience_requests[-1]["id"])
	AudienceDriver.refresh(_main)
	return true


## The party whose authored leader is `pid`, "" for none.
func _led_by(pid: String) -> String:
	for party in _main._loader.parties.get(String(_main._state.player().id), []):
		if String(party.leader_person_id) == pid:
			return String(party.id)
	return ""


## The party the data gives the person -- the one they lead -- its name and its
## slot's colour (its order in the nation's data, the hemicycle's rule).
func _expected() -> Dictionary:
	var parties: Array = _main._loader.parties.get(String(_main._state.player().id), [])
	for i in parties.size():
		if String(parties[i].id) == _led_by(String(_person.id)):
			return {"name": String(parties[i].party_name), "colour": PartyChip.colour_at(i)}
	return {}


## An ordinary member reads their own authored edge; someone with no party at all
## reads {} (the chip then says "No party" in words).
func _check_member_and_none() -> void:
	var ns = _main._state.player()
	var member = null
	var none = null
	for person in _main._loader.people.get(String(ns.id), []):
		if member == null and String(person.party_id) != "" and _led_by(String(person.id)) == "":
			member = person
		if none == null and String(person.party_id) == "" and _led_by(String(person.id)) == "":
			none = person
	if member != null:
		var got := PartyChip.of(_main._loader, ns, String(member.id))
		var party = null
		for p in _main._loader.parties.get(String(ns.id), []):
			if String(p.id) == String(member.party_id):
				party = p
		if party == null or String(got.get("name", "")) != String(party.party_name):
			_fail("a member's chip reads '%s', not their party" % got.get("name", ""))
	if none != null and not PartyChip.of(_main._loader, ns, String(none.id)).is_empty():
		_fail("a person with no party was given one")
	var chip := PartyChip.make({})
	var label: Label = chip.find_child("Party", true, false)
	if chip.find_child("Swatch", true, false) != null or label == null or label.text != label.tr("No party"):
		_fail("no party is not said in words, or is swatched")
	chip.free()


## A chip under `holder` says the person's party by name and swatches it in the
## hemicycle's slot -- the name is the reading, the colour only repeats it.
func _chip_matches(holder: Node, where: String) -> void:
	var chip: Node = holder.find_child("PartyChip", true, false) if holder != null else null
	if chip == null:
		_fail("%s shows no party" % where)
		return
	var want := _expected()
	var label: Label = chip.find_child("Party", true, false)
	var swatch: ColorRect = chip.find_child("Swatch", true, false)
	# A narrow chip (the Diary's request card, #221) may show the party's initials,
	# the full name on its hover -- still words, never colour alone.
	var short_ok: bool = label != null and label.visible and label.text != "" \
			and String((chip as Control).tooltip_text) == String(want.get("name", "?"))
	if label == null or (label.text != String(want.get("name", "?")) and not short_ok):
		_fail("%s names the party '%s', the data says '%s'" % [where, label.text if label != null else "", want.get("name", "?")])
	if swatch == null or swatch.color != want.get("colour", Color.BLACK):
		_fail("%s swatches the party out of its hemicycle slot" % where)


func _check_card_party() -> void:
	var inbox = _main._hud.inbox
	var card_id: String = AudienceDriver.lane_of(_main).card_of(_request)
	_chip_matches(inbox._cards.get(card_id), "the request card")


func _check_booking_party() -> void:
	AudienceDriver._open_booking(_main, _request)
	# The Diary's chip says the party on its hover, the column's card having gone.
	var chip: Button = _main._calendar_panel._grid._days.find_child("Chip_%s" % _request, true, false)
	var ns = _main._state.player()
	var person := String(Audiences.request(ns, _request)["person_id"])
	var party: Dictionary = preload("res://src/ui/party_chip.gd").of(_main._loader, ns, person)
	if chip == null:
		_fail("the Diary has no chip for the request")
	elif not party.is_empty() and not chip.tooltip_text.contains(String(party["name"])):
		_fail("the Diary's chip does not name the party: '%s'" % chip.tooltip_text)


func _reach_audience() -> bool:
	var state = _main._state
	var ns = state.player()
	var day := {}
	for date in Audiences.offered_dates(state, ns, _request):
		if bool(date["free"]):
			day = date
			break
	if day.is_empty() or not bool(Audiences.book(state, ns, _main._loader, _request, day).get("ok", false)):
		_fail("premise: could not book the audience")
		return false
	state.year = int(day["year"])
	state.month = int(day["month"])
	_main._on_day_advanced(int(day["year"]), int(day["month"]), int(day["day"]))
	if _scene() == null or _scene().visiting == "":
		_fail("premise: the booked day opened no audience")
		return false
	return true


func _check_scene_party() -> void:
	_chip_matches(_scene()._party, "the audience's header")


## R4: the lie is an option ON the lever -- the flat option look, its words a
## modifier of the verb, its box a different shape ticked than not.
func _check_won_tone() -> void:
	if not _game()["session"].has("struck"):
		_fail("premise: Grant did not strike the deal")
		return
	_tone_is(_scene()._tone, ResultTone.GOOD, "a struck deal's result")


func _check_close_tone(key: String, where: String) -> void:
	_tone_is(_scene()._tone, key, where)


## A second covered person (not the first), whose audience is ended with nothing
## won: the declined close.
func _arrive_other() -> bool:
	var state = _main._state
	var ns = state.player()
	var first = _person
	_person = null
	for person in _main._loader.people.get(String(ns.id), []):
		var pid := String(person.id)
		if _person != null or person == first or person.wants.is_empty() or pid == String(ns.head_of_state_person_id) or pid == String(ns.pm_person_id):
			continue
		if President.covers(state, ns, _main._loader, pid):
			_person = person
	if _person == null:
		_fail("premise: no second person to see")
		return false
	var now: int = int(state.year) * 12 + int(state.month)
	Audiences._arrive(ns, _person, _person.wants[0], now, [])
	_request = String(ns.audience_requests[-1]["id"])
	AudienceDriver.refresh(_main)
	return true


func _tone_is(tone: Label, key: String, where: String) -> void:
	if not tone.visible or tone.text == "":
		_fail("%s carries no tone word" % where)
		return
	if tone.theme_type_variation != String(ResultTone.TAG[key][0]) or tone.text != tone.tr(String(ResultTone.TAG[key][1])):
		_fail("%s reads '%s' (%s), not the %s tone" % [where, tone.text, tone.theme_type_variation, key])


func _press(down: bool) -> void:
	if _target == null or not _target.is_visible_in_tree():
		return
	Click.half(_main.get_viewport(), _target, down)


func _fail(message: String) -> void:
	_failures.append(message)


func _end() -> bool:
	if _failures.is_empty():
		print("test_audience_close_fixes: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
