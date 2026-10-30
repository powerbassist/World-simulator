extends SceneTree

## V5.2d. The press marks what matters (docs/design/v5.2-d-spec.md section 4):
## the month report's `front_page` entry, the sim side of the card
## src/ui/front_page.gd prints. D8 (at most one a month, the most severe, ties
## to the earlier arrival) and D9 (two tones whenever the outlets offer two) are
## pinned here; the card's own never-holds-the-clock is tests/test_front_page.gd's.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Events = preload("res://src/sim/events.gd")
const FrontPage = preload("res://src/sim/front_page.gd")
const FK = preload("res://src/sim/front_page_constants.gd")
const Media = preload("res://src/sim/media.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_quiet_month_has_no_front_page()
	_check_an_answer_earns_one()
	_check_a_minor_event_earns_none()
	_check_a_default_earns_one()
	_check_most_severe_wins_ties_to_arrival()
	_check_moments_from_the_report()
	_check_command_moments()
	_check_a_resignation_is_noted()
	_check_ai_nations_write_nothing()
	_check_two_tones_whenever_two_exist()
	_check_same_tone_takes_reach()
	_check_world_month_carries_the_entry()
	_finish()


func _state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	return state


func _event_of_severity(severity: int):
	for ev in _loader.events:
		if int(ev.severity) == severity and ev.on_action == "":
			return ev
	return null


func _check_quiet_month_has_no_front_page() -> void:
	var state = _state()
	if not FrontPage.close(state, _loader, {}).is_empty():
		_failures.append("a month with nothing in it printed a front page")


func _check_an_answer_earns_one() -> void:
	var state = _state()
	var ns = state.player()
	var ev = _event_of_severity(2)
	Events.announce(ns, ev, 0, {})
	var choice: Dictionary = ev.choices[0]
	Events.answer(state, _loader, ev.id, String(choice["id"]))
	var entry := FrontPage.close(state, _loader, {})
	if String(entry.get("kind", "")) != "event" or String(entry.get("id", "")) != ev.id \
			or String(entry.get("answer", "")) != String(choice["id"]) or int(entry.get("severity", 0)) != 2:
		_failures.append("an answered major event did not earn its front page: %s" % [entry])
	if int(entry.get("month", -1)) != int(state.year) * 12 + int(state.month):
		_failures.append("the entry's month is not y*12+m: %s" % [entry.get("month")])
	var papers: Array = entry.get("papers", [])
	if papers.is_empty() or papers.size() > 2:
		_failures.append("France's front page carries %d papers" % papers.size())
	for paper in papers:
		if not FK.TONES.has(String(paper.get("tone", ""))) or String(paper.get("outlet", "")) == "":
			_failures.append("a paper is not {outlet, tone}: %s" % [paper])
	if not FrontPage.close(state, _loader, {}).is_empty():
		_failures.append("the same resolution printed a second front page the next month")


func _check_a_minor_event_earns_none() -> void:
	var state = _state()
	var ev = _event_of_severity(1)
	Events.announce(state.player(), ev, 0, {})
	Events.answer(state, _loader, ev.id, String(ev.choices[0]["id"]))
	if not FrontPage.close(state, _loader, {}).is_empty():
		_failures.append("a minor event earned a front page")


func _check_a_default_earns_one() -> void:
	var state = _state()
	var ns = state.player()
	var ev = _event_of_severity(3)
	Events.announce(ns, ev, 0, {})
	ns.event_queue[0]["months_left"] = 1
	Events.tick_month(state, _loader)
	var found := false
	for note in ns.front_page_pending:
		if String(note.get("id", "")) == ev.id and String(note.get("answer", "")) == String(ev.default_choice()["id"]):
			found = true
	if not found:
		_failures.append("a critical event's default at its deadline was not noted for the press: %s" % [ns.front_page_pending])


## D8: one entry, the most severe; equal severity goes to the earlier arrival; the
## next two ride along as "also", in the same order.
func _check_most_severe_wins_ties_to_arrival() -> void:
	var state = _state()
	var ns = state.player()
	FrontPage.note(state, ns, "event", "first_major", "a", 2)
	FrontPage.note(state, ns, "event", "first_critical", "b", 3)
	FrontPage.note(state, ns, "event", "second_critical", "c", 3)
	FrontPage.note(state, ns, "event", "second_major", "d", 2)
	var entry := FrontPage.close(state, _loader, {})
	if String(entry.get("id", "")) != "first_critical":
		_failures.append("the front page is %s, not the earlier of the two critical stories" % entry.get("id"))
	var also: Array = entry.get("also", [])
	var ids: Array = []
	for story in also:
		ids.append(String(story.get("id", "")))
		if not story.has("outlet") or not FK.TONES.has(String(story.get("tone", ""))):
			_failures.append("an also line is not {kind, id, answer, outlet, tone}: %s" % [story])
	if ids != ["second_critical", "first_major"]:
		_failures.append("also is %s, not the next two by severity then arrival" % [ids])
	if not ns.front_page_pending.is_empty():
		_failures.append("the close left %d stories pending" % ns.front_page_pending.size())


func _check_moments_from_the_report() -> void:
	var cases := [
		[{"election_results": [{"kind": "executive", "incumbent_largest": true}]}, "election", "executive_won"],
		[{"election_results": [{"kind": "executive", "incumbent_largest": false}]}, "election", "executive_lost"],
		[{"election_results": [{"kind": "national", "formation": {"cohabitation": false, "minority": false}}]}, "election", "legislative_majority"],
		[{"election_results": [{"kind": "national", "formation": {"cohabitation": false, "minority": true}}]}, "election", "legislative_minority"],
		[{"election_results": [{"kind": "national", "formation": {"cohabitation": true, "minority": false}}]}, "election", "legislative_opposition"],
		[{"character_acts": [{"act": "defect", "person_id": "x", "detail": {}}]}, "character", "defected"],
		[{"character_acts": [{"act": "resign", "person_id": "x", "detail": {"office": "premiership"}}]}, "character", "prime_minister_resigned"],
	]
	for case in cases:
		var entry := FrontPage.close(_state(), _loader, case[0])
		if String(entry.get("kind", "")) != "moment" or String(entry.get("id", "")) != case[1] \
				or String(entry.get("answer", "")) != case[2]:
			_failures.append("%s did not print %s.%s: %s" % [case[0], case[1], case[2], entry])
	for quiet in [
		{"election_results": [{"kind": "eu_parliament"}, {"kind": "termed_out"}]},
		{"character_acts": [{"act": "brief_against", "person_id": "x", "detail": {}}]},
	]:
		if not FrontPage.close(_state(), _loader, quiet).is_empty():
			_failures.append("%s printed a front page" % [quiet])


## The moments a player's command makes outside the month: they wait in the
## register for the next close.
func _check_command_moments() -> void:
	var state = _state()
	var ns = state.player()
	if Dissolution.can_dissolve(state, ns):
		Dissolution.dissolve(state, ns)
		var entry := FrontPage.close(state, _loader, {})
		if String(entry.get("id", "")) != "dissolution" or String(entry.get("answer", "")) != "called":
			_failures.append("a dissolution did not print dissolution.called: %s" % [entry])
	else:
		_failures.append("France cannot dissolve at the start -- the dissolution check needs another month")
	# Article 49.3: the first law France can force.
	state = _state()
	ns = state.player()
	for law in _loader.laws:
		var result := Legislature.propose(state, _loader, law, true)
		if not bool(result.get("forced", false)) or bool(result.get("refused", false)):
			continue
		var ids: Array = []
		for note in ns.front_page_pending:
			ids.append("%s.%s" % [note["id"], note["answer"]])
		if bool(result.get("passed", false)) != ids.has("article_49_3.carried"):
			_failures.append("49.3 passed=%s but the press noted %s" % [result.get("passed"), ids])
		var fell := bool((result.get("censure", {}) as Dictionary).get("carried", false))
		if fell != ids.has("censure.government_fell"):
			_failures.append("censure carried=%s but the press noted %s" % [fell, ids])
		return
	_failures.append("no law could be forced -- the 49.3 check found nothing to force")


## A minister walking out of the cabinet: one note per resignation, inside the month.
func _check_a_resignation_is_noted() -> void:
	var state = _state()
	var ns = state.player()
	# The cabinet test's lever: strip a coalition party of its portfolios at the
	# worst approval, so its loyalty and the unpopularity both push it out.
	ns.overall_approval_pct = 0.0
	for pid in ns.coalition_party_ids:
		for f in CK.PORTFOLIO_KEYS:
			if String(ns.cabinet.get(f, "")) == pid:
				ns.cabinet[f] = ""
		break
	var before: int = ns.resignations_count
	Cabinet.tick_month(state, _loader)
	var resigned: int = ns.resignations_count - before
	var noted := 0
	for note in ns.front_page_pending:
		if String(note["id"]) == "character" and String(note["answer"]) == "minister_resigned":
			noted += 1
	if resigned == 0:
		_failures.append("no minister resigned at zero approval -- the resignation check tested nothing")
	elif noted != resigned:
		_failures.append("%d ministers resigned but %d were noted for the press" % [resigned, noted])


func _check_ai_nations_write_nothing() -> void:
	var state = _state()
	var ai = state.nations["DEU"]
	FrontPage.note(state, ai, "event", "x", "a", 3)
	if not ai.front_page_pending.is_empty():
		_failures.append("an AI nation's resolution was noted for a front page nobody prints")


func _outlets() -> Array:
	return _loader.outlets.get(PLAYER, [])


## D9: over a grid of government positions, whenever France's outlets fall in two
## tones or more, the two papers carry two different tones.
func _check_two_tones_whenever_two_exist() -> void:
	var state = _state()
	var ns = state.player()
	var both := 0
	for e in range(-10, 11):
		for s in range(-10, 11):
			ns.coalition_position = {"economic": e / 10.0, "social": s / 10.0}
			var tones := {}
			for outlet in _outlets():
				tones[FrontPage.tone(Media.outlet_alignment(outlet, ns))] = true
			var papers := FrontPage.papers(ns, _loader)
			if tones.size() >= 2:
				both += 1
				if papers.size() != 2 or String(papers[0]["tone"]) == String(papers[1]["tone"]):
					_failures.append("at %s the outlets offer %s but the papers are %s" % [ns.coalition_position, tones.keys(), papers])
					return
	if both == 0:
		_failures.append("no position on the grid gives France's outlets two tones -- D9 checked nothing")


func _check_same_tone_takes_reach() -> void:
	var state = _state()
	var ns = state.player()
	for e in range(-10, 11):
		for s in range(-10, 11):
			ns.coalition_position = {"economic": e / 10.0, "social": s / 10.0}
			var tones := {}
			for outlet in _outlets():
				tones[FrontPage.tone(Media.outlet_alignment(outlet, ns))] = true
			if tones.size() != 1 or _outlets().size() < 2:
				continue
			var by_reach := _outlets().duplicate()
			by_reach.sort_custom(func(a, b): return a.reach > b.reach if a.reach != b.reach else a.id < b.id)
			var papers := FrontPage.papers(ns, _loader)
			if papers.size() != 2 or String(papers[0]["outlet"]) != by_reach[0].id or String(papers[1]["outlet"]) != by_reach[1].id:
				_failures.append("one tone at %s, but the papers are not the two with the greatest reach: %s" % [ns.coalition_position, papers])
			return


## The entry rides the month report, and WorldMonth's own tick drains the register.
func _check_world_month_carries_the_entry() -> void:
	var state = _state()
	var ns = state.player()
	FrontPage.note(state, ns, "event", "probe", "a", 3)
	state.month += 1
	var report := WorldMonth.tick_month(state, _loader)
	if not report.has("front_page"):
		_failures.append("the month report carries no front_page key")
	elif String((report["front_page"] as Dictionary).get("id", "")) == "":
		_failures.append("a noted story did not reach the month's front page: %s" % [report["front_page"]])
	if not ns.front_page_pending.is_empty():
		_failures.append("the month left the press register full")


func _finish() -> void:
	if _failures.is_empty():
		print("test_front_page_entry: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
