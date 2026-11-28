extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_talk_only.gd
## Non-zero exit on any failure.
##
## The author's call 2 B on screen (#463 pass 2, T1-T3): an audience on a want no act of the
## president's answers (a programme's place) is talk. Through the real game and the sim's own
## commands, with a request that came WITH money, so the money's absence is the rule's, not the
## draw's:
##   - it opens on the topics: no Grant / Counter / Refuse, no offer of money, the talk shown,
##     and the band says there is no word to give;
##   - End closes it at once, settled, unpriced: her regard untouched by an offer she was never
##     shown;
##   - the next talk audience opens on its topics too (the flow left behind is the last one's);
##   - a summons is talk the same way: the topics, its own band, End closes it settled.

const Audiences = preload("res://src/sim/audiences.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Deal = preload("res://src/sim/deal.gd")
const Offers = preload("res://src/sim/offers.gd")
const President = preload("res://src/sim/president.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")

const TALK_WANT := {"object": "programme:prog_jobs_first", "stance": "oppose"}

var _failures: Array[String] = []
var _main
var _frame := 0
var _person := ""
var _request := ""
var _used: Array[String] = []
var _rapport := 0.0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			if not _open_talk():
				return _end()
		5:
			_check_it_opens_on_the_topics("the first", "only talk")
			_rapport = President.rapport(_main._state.player(), _person)
			_scene()._end.pressed.emit()
		7:
			_check_the_close()
			if not _open_talk():
				return _end()
		9:
			_check_it_opens_on_the_topics("a second", "only talk")
			_scene()._end.pressed.emit()
		11:
			if not _open_summons():
				return _end()
		13:
			_check_it_opens_on_the_topics("a summons'", "nothing to settle")
			_scene()._end.pressed.emit()
		15:
			_check_the_close()
			return _end()
	return false


func _scene():
	return AudienceDriver.scene_of(_main)


func _check_it_opens_on_the_topics(which: String, band: String) -> void:
	var scene = _scene()
	var session: Dictionary = AudienceDriver._games[_main.get_instance_id()]["session"]
	if not _main._windows.is_open("audience") or not AK.is_talk(session):
		_fail("premise: %s talk audience is not open as talk: %s" % [which, session.get("ask", {})])
		return
	if scene.cards.visible or scene.money_rows.visible or not scene.flow.in_talk() or not scene.talk.visible:
		_fail("%s talk audience did not open on the topics: %s, cards %s, money %s, talk %s" % [which,
			scene.flow.name_of(scene.flow.state), scene.cards.visible, scene.money_rows.visible, scene.talk.visible])
	if scene.flow.lines.is_empty() or scene.talk.find_children("Line_*", "", true, false).is_empty():
		_fail("%s talk audience shows no topic rows: %d ranked" % [which, scene.flow.lines.size()])
	if not (scene._view.get("money", {}) as Dictionary).is_empty() or not Shadows.offer(_main._state.player(), session).is_empty() \
			or not (Deal.answers(_main._state, _main._state.player(), _main._loader, session)["money"] as Dictionary).is_empty():
		_fail("%s talk audience still offers the request's money" % which)
	var said := ""
	for label in scene._band_lines.find_children("*", "Label", true, false):
		said += (label as Label).text + " "
	if not said.contains(band):
		_fail("%s talk audience's band does not say '%s': '%s'" % [which, band, said])


func _check_the_close() -> void:
	var ns = _main._state.player()
	if _main._windows.is_open("audience"):
		_fail("End did not close a talk audience at once")
	if String(Audiences.request(ns, _request).get("status", "")) != AK.STATUS_SETTLED:
		_fail("a talk audience did not end settled: %s" % [Audiences.request(ns, _request)])
	# A summons warms them as it closes (RECEIVED_RAPPORT); a request with money must not move at all.
	if not AK.is_summons(Audiences.request(ns, _request)) and not is_equal_approx(President.rapport(ns, _person), _rapport):
		_fail("ending a talk audience moved her regard (an unshown offer refused?): %f -> %f" % [_rapport, President.rapport(ns, _person)])


## A programme want arrives for an executive whose draw this month brings money, is booked on a
## free day and opens on it: the real game's door to the scene.
func _open_talk() -> bool:
	var state = _main._state
	var ns = state.player()
	var now: int = int(state.year) * 12 + int(state.month)
	_request = ""
	for m in range(now, now + 60):
		for person in _main._loader.people.get(String(ns.id), []):
			if String(person.kind) != "executive" or _used.has(String(person.id)) or not President.covers(state, ns, _main._loader, String(person.id)) \
					or Offers.offer_for(ns, person, m).is_empty():
				continue
			state.year = (m - 1) / 12
			state.month = (m - 1) % 12 + 1
			Audiences._arrive(ns, person, TALK_WANT, m, [])
			if not (ns.audience_requests[-1].get("offer", {}) as Dictionary).is_empty():
				_request = String(ns.audience_requests[-1]["id"])
				_person = String(person.id)
				_used.append(_person)
			break
		if _request != "":
			break
	if _request == "":
		_fail("premise: no executive's programme request came with an offer")
		return false
	var day := {}
	for date in Audiences.offered_dates(state, ns, _request):
		if bool(date["free"]):
			day = date
			break
	if day.is_empty() or not bool(Audiences.book(state, ns, _main._loader, _request, day).get("ok", false)):
		_fail("premise: could not book the talk request")
		return false
	state.year = int(day["year"])
	state.month = int(day["month"])
	_main._on_day_advanced(int(day["year"]), int(day["month"]), int(day["day"]))
	return true


## The president summons a quiet person of the nation on a free day and the day comes.
func _open_summons() -> bool:
	var state = _main._state
	var ns = state.player()
	for person in _main._loader.people.get(String(ns.id), []):
		var pid := String(person.id)
		if _used.has(pid) or not Audiences.summon_refusal(state, ns, _main._loader, pid).is_empty():
			continue
		for d in Audiences.summon_days(state, pid):
			if bool(d["free"]) and bool(Audiences.summon(state, ns, _main._loader, pid, d).get("ok", false)):
				_person = pid
				_used.append(pid)
				_request = String(ns.audience_requests[-1]["id"])
				_rapport = President.rapport(ns, pid)
				state.year = int(d["year"])
				state.month = int(d["month"])
				_main._on_day_advanced(int(d["year"]), int(d["month"]), int(d["day"]))
				return true
	_fail("premise: nobody could be summoned on a free day")
	return false


func _fail(message: String) -> void:
	_failures.append(message)


func _end() -> bool:
	if _failures.is_empty():
		print("test_audience_talk_only: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
