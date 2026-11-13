extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_money.gd
## Non-zero exit on any failure.
##
## V5.3, the two rare proposals of an audience, drawn into the accepted C4 grammar (the author:
## "Oui, on l'ajoute", and "Prendre = promettre + argent"). Through the real game and the sim's
## own commands (the UI writes no register):
##
##   THE MONEY. A request that came with money (Systems' Deal.answers()["money"]) is answered
##   BEFORE the cards: the flow is MONEY, the cards are held, her offer and what it risks BY THE
##   VOTE (the term, not a year) are on the screen, and two lines answer it. Take is Deal.take,
##   Grant plus the money, so the deal is struck and the talk opens; Leave is Shadows.refuse_offer
##   and costs her regard, and the three cards follow.
##
##   THE AFFAIR. It is the president's ask, never hers: after a Flirt said this audience a line
##   under it asks (Shadows.begin_affair, once per audience), her answer is affair_begin or her
##   reason, the line reads Asked afterwards and nothing is asked twice; a lover has a line that
##   ends it (Shadows.end_affair).

const Audiences = preload("res://src/sim/audiences.gd")
const Deal = preload("res://src/sim/deal.gd")
const Offers = preload("res://src/sim/offers.gd")
const President = preload("res://src/sim/president.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const SC = preload("res://src/sim/shadow_constants.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const AudienceFlow = preload("res://src/ui/audience_flow.gd")
const AudienceLines = preload("res://src/ui/audience_lines.gd")
const AudienceTalks = preload("res://src/ui/audience_talks.gd")
const AudienceWords = preload("res://src/ui/audience_words.gd")
const Words = preload("res://src/ui/lever_words.gd")

const S = AudienceFlow.S

var _failures: Array[String] = []
var _main
var _frame := 0
var _person := ""
var _before := {}


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_check_the_words()
			_check_where_the_affair_rows_go()
			if not _open_with_offer("executive"):
				return _end()
		5:
			_check_the_money_holds_the_cards()
			_before = _money()
			_rapport_before = President.rapport(_main._state.player(), _person)
			_press("money_leave")
		7:
			_check_leaving_the_money()
			_leave()
		9:
			if not _open_with_offer("press_owner"):
				return _end()
		11:
			_before = _money()
			_press("money_take")
		13:
			_check_taking_the_money()
			_stage_a_flirt()
		15:
			_check_the_affair_ask()
			_press("affair_ask")
		17:
			_check_the_affair_answer()
			_check_the_end_of_an_affair()
			return _end()
	return false


var _rapport_before := 0.0
## What the sim said of the proposal before it was put: "" (it may begin) or the person's reason.
var _why := ""


func _scene():
	return AudienceDriver.scene_of(_main)


func _game() -> Dictionary:
	return AudienceDriver._games[_main.get_instance_id()]


func _session() -> Dictionary:
	return _game()["session"]


## The words that need no scene: the offer's risk is read over the TERM (months to the vote), and falls
## back to the year the sim also gives when no vote is on the clock.
func _check_the_words() -> void:
	var money := {"currency": "party_money", "amount_eur_m": 1.0, "evidence": 1.0, "found_in_a_year": 0.02, "found_in_a_year_without": 0.0,
		"months_to_vote": 16, "found_by_the_vote": 0.0637, "found_by_the_vote_without": 0.0, "take": {"ok": true, "why_not": ""}}
	var term: String = AudienceWords.money_risk(money)
	if not term.contains("16") or not term.contains("6 %") or term.contains("year"):
		_fail("the money's risk is not read over the term: '%s'" % term)
	var year: String = AudienceWords.money_risk(money.merged({"months_to_vote": -1, "found_by_the_vote": -1.0, "found_by_the_vote_without": -1.0}, true))
	if not year.contains("year") or not year.contains("2 %"):
		_fail("with no vote on the clock the risk falls back to the year: '%s'" % year)
	var now: String = AudienceWords.money_risk(money.merged({"months_to_vote": 0, "found_by_the_vote": 0.0}, true))
	if not now.contains("this month"):
		_fail("a vote this month reads as a risk over months: '%s'" % now)
	if not AudienceWords.money_terms(money).contains("party"):
		_fail("the money's terms do not name where it lands: '%s'" % AudienceWords.money_terms(money))
	var lines: Array = AudienceWords.money_lines(money)
	if lines.size() != 2 or String(lines[0]["tone"]) != AudienceWords.BAD or not String(lines[0]["text"]).contains("%"):
		_fail("the money's band is not a risk and the word it gives: %s" % [lines])
	if not lines.any(func(l: Dictionary) -> bool: return String(l["text"]).to_lower().contains("word")):
		_fail("the money's band does not say that taking it gives her your word: %s" % [lines])
	var taken: Array = AudienceWords.taken_lines(money)
	if taken.size() != 2 or String(taken[0]["tone"]) != AudienceWords.GOOD or String(taken[1]["tone"]) != AudienceWords.BAD:
		_fail("the struck band after the money is not one gain and one risk: %s" % [taken])


## The ask follows the Flirt it answers; the end of an affair closes the talk.
func _check_where_the_affair_rows_go() -> void:
	var rows: Array = [{"id": "gossip"}, {"id": "flirt"}, {"id": "dinner"}]
	var ask := {"id": "affair_ask", "sub": true}
	var end := {"id": "affair_end", "sub": false}
	if AudienceLines.affair_index(rows, ask) != 2:
		_fail("the ask is not directly under the Flirt: %d" % AudienceLines.affair_index(rows, ask))
	if AudienceLines.affair_index(rows, end) != 3 or AudienceLines.affair_index([{"id": "gossip"}], ask) != 1:
		_fail("the end of an affair, or an ask with no Flirt line, is not at the foot")


func _check_the_money_holds_the_cards() -> void:
	var scene = _scene()
	if scene.flow.state != S.MONEY:
		_fail("a request with money opened on %s, not the money" % scene.flow.name_of(scene.flow.state))
	if scene.cards.visible or scene.talk.visible:
		_fail("the cards or the talk are up while the money is open")
	if not scene.money_rows.visible or _row_button(scene.money_rows, "money_take") == null or _row_button(scene.money_rows, "money_leave") == null:
		_fail("the money's two answers are not on the screen")
	if not String(scene._result.text).contains("m "):
		_fail("the money's terms are not in the band: '%s'" % scene._result.text)
	var grant: Dictionary = Deal.answers(_main._state, _main._state.player(), _main._loader, _session())["grant"]
	if bool(grant["ok"]):
		_fail("the sim lets Grant through with the money open: %s" % [grant])


func _check_leaving_the_money() -> void:
	var scene = _scene()
	var ns = _main._state.player()
	if scene.flow.state != S.QUESTION or not scene.cards.visible or scene.money_rows.visible:
		_fail("Leave did not return to the three cards: %s" % scene.flow.name_of(scene.flow.state))
	var rapport := President.rapport(ns, _person)
	if absf(rapport - (_rapport_before - SC.OFFER_REFUSED_RAPPORT)) > 1e-6 and rapport > -1.0 + 1e-6:
		_fail("leaving the money did not cost its regard through the sim: %s -> %s" % [_rapport_before, rapport])
	if _money() != _before:
		_fail("leaving the money moved money")
	var grant: Button = scene.cards.find_child("GrantButton", true, false) as Button
	if grant == null or grant.disabled:
		_fail("Grant is down after the money was left")


func _check_taking_the_money() -> void:
	var scene = _scene()
	if scene.flow.state != S.GRANTED and scene.flow.state != S.ANSWERED:
		_fail("Take did not strike the deal: %s" % scene.flow.name_of(scene.flow.state))
	if String(_session().get("won", "")) != "grant":
		_fail("Take is Grant plus the money, so the session is won as a grant: '%s'" % _session().get("won", ""))
	var after := _money()
	var paid: float = (after["wealth"] - _before["wealth"]) + (after["party"] - _before["party"])
	if absf(paid - SC.OFFER_EUR_M) > 1e-6:
		_fail("Take did not pay the money through the sim (moved %s)" % paid)
	if not scene.talk.visible:
		_fail("the talk did not open after Take")
	var said: Array = []
	for cell in scene._band_lines.get_children():
		for child in cell.get_children():
			if child is Label:
				said.append(child.text)
	if not said.any(func(t: String) -> bool: return t.contains("m to ")):
		_fail("the struck band does not name the money taken: %s" % [said])


## After a Flirt said this audience, the line under it asks the affair (it is staged by marking the
## Flirt used on the session, since its gates are the talk menu's own); until then there is none.
func _stage_a_flirt() -> void:
	_person = String(_session()["person_id"])
	if _scene().talk.find_child("Line_affair_ask", true, false) != null:
		_fail("an affair is asked before any Flirt")
	(_session()["used_topics"] as Array).append("flirt")
	AudienceDriver.refresh(_main)
	_scene().show_result("", AudienceTalks.view_of(_main, _game()), "", {}, "")


func _check_the_affair_ask() -> void:
	_why = Shadows.may_begin_affair(_main._state, _main._state.player(), _main._loader, _person, _session())
	if _row_button(_scene().talk, "affair_ask") == null:
		_fail("after a Flirt there is no line that asks the affair")
	if _row_button(_scene().talk, "affair_end") != null:
		_fail("a line ends an affair that was never begun")


func _check_the_affair_answer() -> void:
	var ns = _main._state.player()
	var why := _why
	if not bool(_session().get("affair_asked", false)):
		_fail("pressing the line did not ask the affair through the sim")
	var lovers := President.relationship(ns, _person) == "affair"
	var row: Node = _scene().talk.find_child("Line_affair_ask", true, false)
	if row == null or not row.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "Asked"):
		_fail("the affair line does not read Asked once it was asked")
	if not lovers and _scene()._result.text != Words.reason(why) and why != "":
		_fail("her no is not said: '%s'" % _scene()._result.text)
	var again: Dictionary = Shadows.begin_affair(_main._state, ns, _main._loader, _person, _session())
	if bool(again["ok"]):
		_fail("a second proposal in one audience was taken")


func _check_the_end_of_an_affair() -> void:
	var ns = _main._state.player()
	if President.relationship(ns, _person) != "affair":
		President.set_bond(_main._state, ns, _main._loader, _person, "affair")
	_scene().show_result("", AudienceTalks.view_of(_main, _game()), "", {}, "")
	var end := _row_button(_scene().talk, "affair_end")
	if end == null:
		_fail("a lover has no line that ends it")
		return
	end.pressed.emit()
	if President.relationship(ns, _person) == "affair":
		_fail("the line did not end the affair through the sim")
	if _row_button(_scene().talk, "affair_end") != null:
		_fail("the line that ends an affair stayed after it ended")


## The first Button of a talk row, by its line id: what a press on the sentence is.
func _row_button(view: Control, id: String) -> Button:
	var row: Node = view.find_child("Line_" + id, true, false)
	if row == null or not row.is_visible_in_tree():
		return null
	for child in row.find_children("*", "Button", true, false):
		return child
	return null


func _press(id: String) -> void:
	var view = _scene().money_rows if id.begins_with("money") else _scene().talk
	var button := _row_button(view, id)
	if button == null:
		_fail("no line '%s' to press" % id)
		return
	button.pressed.emit()


func _leave() -> void:
	_scene()._end.pressed.emit()
	if _main._windows.is_open("audience"):
		_scene()._end.pressed.emit()


## The money the offer pays, where it lands: the president's or the party's.
func _money() -> Dictionary:
	var ns = _main._state.player()
	return {"wealth": President.wealth_eur_m(ns, _main._loader, President.leader_id(ns)),
		"party": President.party_money_eur_m(ns, _main._loader, String(ns.incumbent_party_id))}


## A request from a person of `kind` that came with money, booked on its first free day and reached
## through the game's own day door. The offer is the sim's draw: the premise looks for a request
## that carries one, never assumes it.
func _open_with_offer(kind: String) -> bool:
	var state = _main._state
	var ns = state.player()
	var now: int = int(state.year) * 12 + int(state.month)
	var request := ""
	var want := {}
	for person in _main._loader.people.get(String(ns.id), []):
		if want.is_empty() and not person.wants.is_empty():
			want = person.wants[0]
	for m in range(now, now + 60):
		for person in _main._loader.people.get(String(ns.id), []):
			if String(person.kind) != kind or not President.covers(state, ns, _main._loader, String(person.id)) \
					or Offers.offer_for(ns, person, m).is_empty():
				continue
			state.year = (m - 1) / 12
			state.month = (m - 1) % 12 + 1
			Audiences._arrive(ns, person, person.wants[0] if not person.wants.is_empty() else want, m, [])
			if not (ns.audience_requests[-1].get("offer", {}) as Dictionary).is_empty():
				request = String(ns.audience_requests[-1]["id"])
				_person = String(person.id)
			break
		if request != "":
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


func _fail(message: String) -> void:
	_failures.append(message)


func _end() -> bool:
	if _failures.is_empty():
		print("test_audience_money: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
