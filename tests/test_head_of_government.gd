extends SceneTree

## Headless test: godot --headless --script res://tests/test_head_of_government.gd
## Non-zero exit on any failure.
##
## V5.3 block 0: every surface that names a nation's leader names the SIM's person,
## President.leader_id(ns) -- the head of state where the President runs the
## executive (France), the head of government otherwise (Poland) -- under the title
## picked by the same `has_executive` test, never the AUTHORED nation file's
## `leader.person` / `leader.title`. The two agree at New Game, so the test stages a
## different person (and a different title) in the sim and a decoy title in the
## nation file: a surface that still reads the file names the wrong person.

const CountryBox = preload("res://src/ui/country_box.gd")
const President = preload("res://src/sim/president.gd")
const VisitBooking = preload("res://src/ui/visit_booking.gd")
const AudienceTalks = preload("res://src/ui/audience_talks.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Audiences = preload("res://src/sim/audiences.gd")

const DECOY_TITLE := "Authored Decoy Title"
const STAGED_TITLE := "Staged Office Title"

## The audience scene, caught: AudienceTalks.open() hands it the view and nothing else.
class SceneCatcher:
	var view := {}
	func open(v: Dictionary) -> void:
		view = v


var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main._clock.set_process(false)
		_check_every_nation_has_a_leader()
		_check_poland_names_the_sim_pm()
		_check_france_names_the_sim_president()
		_check_audience_names_the_sim_president()
		_check_executive_visit_meets_the_president()
		_finish()
		return true
	return false


## The premise: at New Game every nation's sim leader is a known person under a
## title, so reading the sim never blanks a name the authored read used to show.
func _check_every_nation_has_a_leader() -> void:
	var state = _main._state
	var loader = _main._loader
	for id in state.nations.keys():
		var ns = state.nations[id]
		var who := President.leader_id(ns)
		if who == "" or not loader.person_by_id.has(who):
			_fail("%s's sim leader '%s' is not a known person" % [id, who])
		if President.leader_title(ns) == "":
			_fail("%s's sim leader has no title" % id)


## Poland (no separate executive): the PM. Staged to another Polish person.
func _check_poland_names_the_sim_pm() -> void:
	var state = _main._state
	var loader = _main._loader
	var ns = state.nations["POL"]
	var nation = loader.nations["POL"]
	if ns.has_executive:
		_fail("premise: Poland has no separate executive")
		return
	var authored := String(nation.leader_person_id)
	var staged := _another_person("POL_", authored)
	if staged == "":
		_fail("premise: a second Polish person to stage")
		return
	ns.pm_person_id = staged
	ns.head_of_government_title = STAGED_TITLE
	nation.leader_title = DECOY_TITLE
	var staged_name: String = loader.person_name(staged)
	var authored_name: String = loader.person_name(authored)

	_expect_names("Poland's country box", _box_text("POL"), staged_name, authored_name)
	_expect_names("Poland's Diplomacy file", _file_text("POL"), staged_name, authored_name)

	var people = _main._people_panel
	people._open["abroad"] = true
	people._refresh()
	_expect_names("the People tab's Abroad list", _text_of(people), staged_name, authored_name)

	var meeting = null
	for action in loader.diplomatic_actions:
		if action.opens_meeting:
			meeting = action
			break
	var entry: Dictionary = VisitBooking.earliest_entry(state, loader, meeting, "POL") if meeting != null else {}
	if entry.is_empty():
		_fail("premise: a meeting with Poland the Diary can book")
	elif String(entry.get("person_id", "")) != staged:
		_fail("a visit to Poland books '%s', not the sim's PM '%s'" % [entry.get("person_id", ""), staged])
	var booked: String = _main._calendar_panel._leader_person_id("POL")
	if booked != staged:
		_fail("the Diary's visit to Poland meets '%s', not the sim's PM '%s'" % [booked, staged])


## France (a separate executive): the President, never the PM. The head of state is
## staged to another French person; the player's own card names them too.
func _check_france_names_the_sim_president() -> void:
	var state = _main._state
	var loader = _main._loader
	var ns = state.nations["FRA"]
	var nation = loader.nations["FRA"]
	if not ns.has_executive:
		_fail("premise: France has a separate executive")
		return
	var authored := String(nation.leader_person_id)
	var staged := _another_person("FRA_", authored, String(ns.pm_person_id))
	if staged == "":
		_fail("premise: a second French person to stage")
		return
	ns.head_of_state_person_id = staged
	ns.head_of_state_title = STAGED_TITLE
	nation.leader_title = DECOY_TITLE
	var staged_name: String = loader.person_name(staged)
	var authored_name: String = loader.person_name(authored)

	var box := _box_text("FRA")
	_expect_names("France's country box", box, staged_name, authored_name)
	var pm_name: String = loader.person_name(ns.pm_person_id)
	if pm_name != "" and box.contains(pm_name):
		_fail("France's country box names the PM '%s' as its leader: %s" % [pm_name, box])

	var card = _main._hud.portrait_card
	card.setup(state, loader)
	_expect_names("the player's portrait card", _text_of(card), staged_name, authored_name)
	if card._leader_id != staged:
		_fail("the portrait card's bust is '%s', not the sim's President '%s'" % [card._leader_id, staged])


## The audience's view names the president as the sim has them: France's head of
## state, staged above to someone other than the nation file's leader.
func _check_audience_names_the_sim_president() -> void:
	var state = _main._state
	var loader = _main._loader
	var ns = state.player()
	var authored_name: String = loader.person_name(String(loader.nations[ns.id].leader_person_id))
	var sim_name: String = loader.person_name(President.leader_id(ns))
	if sim_name == authored_name:
		_fail("premise: France's sim president is still the authored one")
		return
	var person = null
	for p in loader.people.get(String(ns.id), []):
		if not p.wants.is_empty() and String(p.id) != President.leader_id(ns):
			person = p
			break
	if person == null:
		_fail("premise: a French person with a want to ask for an audience")
		return
	var now: int = int(state.year) * 12 + int(state.month)
	Audiences._arrive(ns, person, person.wants[0], now, [])
	var request: Dictionary = ns.audience_requests[-1]
	var day := {}
	for date in Audiences.offered_dates(state, ns, String(request["id"])):
		if bool(date["free"]):
			day = date
			break
	if day.is_empty() or not bool(Audiences.book(state, ns, loader, String(request["id"]), day).get("ok", false)):
		_fail("premise: could not book the audience")
		return
	# The booked day, without running the days between (Levers.open reads the date).
	state.year = int(day["year"])
	state.month = int(day["month"])
	state.day = int(day["day"])
	var scene := SceneCatcher.new()
	if not AudienceTalks.open(_main, {"scene": scene}, AudienceDriver.row_of(_main, request)):
		_fail("premise: the audience did not open")
		return
	if String(scene.view.get("president", "")) != sim_name:
		_fail("the audience names the president '%s', not the sim's '%s'" % [scene.view.get("president", ""), sim_name])


## A nation whose President runs the executive (Romania where it does, else the
## first such nation other than the player's): a visit meets the head of state,
## never the PM -- both staged to people other than the nation file's leader.
func _check_executive_visit_meets_the_president() -> void:
	var state = _main._state
	var loader = _main._loader
	var target := ""
	var ids: Array = state.nations.keys()
	ids.sort()
	ids.erase("ROU")
	ids.push_front("ROU")
	for id in ids:
		if String(id) != state.player_nation_id and state.nations.has(id) and state.nations[id].has_executive:
			target = String(id)
			break
	if target == "":
		_fail("premise: a nation other than the player's with a separate executive")
		return
	var ns = state.nations[target]
	var authored := String(loader.nations[target].leader_person_id)
	var pm := String(ns.pm_person_id)
	var staged := _another_person(target + "_", authored, pm)
	if staged == "" or pm == "" or pm == staged:
		_fail("premise: %s has a PM and a second person to stage as head of state" % target)
		return
	ns.head_of_state_person_id = staged
	var meeting = null
	for action in loader.diplomatic_actions:
		if action.opens_meeting:
			meeting = action
			break
	var entry: Dictionary = VisitBooking.earliest_entry(state, loader, meeting, target) if meeting != null else {}
	if entry.is_empty():
		_fail("premise: a meeting with %s the Diary can book" % target)
	elif String(entry.get("person_id", "")) != staged:
		_fail("a visit to %s books '%s', not its President '%s' (PM '%s')" % [target, entry.get("person_id", ""), staged, pm])
	var booked: String = _main._calendar_panel._leader_person_id(target)
	if booked != staged:
		_fail("the Diary's visit to %s meets '%s', not its President '%s' (PM '%s')" % [target, booked, staged, pm])


## Present: the staged name and title. Absent: the authored name and the decoy title.
func _expect_names(where: String, text: String, staged_name: String, authored_name: String) -> void:
	if not text.contains(staged_name):
		_fail("%s does not name the sim's leader '%s': %s" % [where, staged_name, text])
	if not text.contains(STAGED_TITLE):
		_fail("%s does not use the sim's title: %s" % [where, text])
	if text.contains(authored_name):
		_fail("%s still names the authored leader '%s': %s" % [where, authored_name, text])
	if text.contains(DECOY_TITLE):
		_fail("%s still reads the nation file's title: %s" % [where, text])


## The first politician (sorted id) of a nation, by id prefix, other than `skip`.
func _another_person(prefix: String, skip: String, skip_too := "") -> String:
	var loader = _main._loader
	var ids: Array = loader.person_by_id.keys()
	ids.sort()
	for id in ids:
		var pid := String(id)
		if pid.begins_with(prefix) and pid != skip and pid != skip_too \
				and loader.person_name(pid) != "" and loader.person_name(pid) != loader.person_name(skip):
			return pid
	return ""


func _box_text(id: String) -> String:
	for child in _main._stack.get_children():
		if child.get_script() == CountryBox:
			child.show_box(id)
			var text := _text_of(child)
			child.hide()
			return text
	_fail("main built no country box")
	return ""


func _file_text(id: String) -> String:
	_main._on_nation_clicked(id)
	_main._nation_panel.show_nation(id)
	_main._nation_panel.mark_dirty()
	_main._nation_panel._process(0.0)
	var text := _text_of(_main._nation_panel)
	_main._windows.close_all()
	return text


func _text_of(node: Node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		if not child.is_queued_for_deletion():
			out += _text_of(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_head_of_government: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
