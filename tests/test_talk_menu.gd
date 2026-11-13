extends SceneTree
## V5.3 the audience's conversation (Gameplay's talk menu, sections 1-4; the author's rule
## "few at the start, more as a history builds"): TalkMenu.lines() is a pure read of GameState
## through data/audiences/talk_lines.json. Headless, no scene tree.
##
##   - A stranger gets the opener and no Dinner; an acquaintance or better gets Dinner, not Family.
##   - At most five lines, tiers in the table's order, at most a tier's limit of each.
##   - Flirt appears exactly when the affair's gates open and the person is known at all.
##   - A line appears only when its own condition holds: a closure at the chief's firm, a
##     sector warning entered lately, a bill within three months, people tied to the person.
##   - No filler: a person with nothing going on gets only what holds, never a padded five.
const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Closures = preload("res://src/sim/closures.gd")
const Companies = preload("res://src/sim/companies.gd")
const Deal = preload("res://src/sim/deal.gd")
const President = preload("res://src/sim/president.gd")
const PresidentK = preload("res://src/sim/president_constants.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const TalkMenu = preload("res://src/ui/talk_menu.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader
var _state


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_state = GameState.new_game(_loader, PLAYER)
	_check_a_stranger_gets_the_opener_and_no_dinner()
	_check_an_acquaintance_gets_dinner_not_family()
	_check_the_order_and_the_caps()
	_check_flirt_follows_its_gates()
	_check_a_plant_at_the_chiefs_firm()
	_check_a_sector_warning_at_the_chiefs_firm()
	_check_a_bill_within_three_months()
	_check_gossip_people_are_tied_and_few()
	_check_nothing_fills_the_gap()
	_finish()


func _session(pid: String) -> Dictionary:
	return {"person_id": pid, "used_topics": [], "request_id": ""}


func _ids(pid: String) -> Array:
	var out: Array = []
	for line in TalkMenu.lines(_state, _state.player(), _loader, _session(pid)):
		out.append(String(line["id"]))
	return out


## Someone who is not a chief of a firm and not the president or a chief of staff.
func _plain_person() -> String:
	var chiefs := {}
	for company in Companies.majors_of(_loader, PLAYER):
		chiefs[String(company.chief_id)] = true
	for person in _loader.people[PLAYER]:
		if String(person.kind) == "politician" and not chiefs.has(String(person.id)) and String(person.id) != President.leader_id(_state.player()):
			return String(person.id)
	return ""


func _know(pid: String, value: float) -> void:
	_state.player().person_knowledge[pid] = value


func _check_a_stranger_gets_the_opener_and_no_dinner() -> void:
	var pid := _plain_person()
	_know(pid, 0.0)
	var ids := _ids(pid)
	_ok(ids.has("family"), "a stranger was not offered Family: %s" % [ids])
	_ok(not ids.has("dinner") and not ids.has("flirt"), "a stranger was offered Dinner or Flirt: %s" % [ids])


func _check_an_acquaintance_gets_dinner_not_family() -> void:
	var pid := _plain_person()
	for value in [PresidentK.KNOWLEDGE_ACQUAINTANCE, PresidentK.KNOWLEDGE_KNOWN, 1.0]:
		_know(pid, value)
		var ids := _ids(pid)
		_ok(ids.has("dinner") and not ids.has("family"), "knowledge %s: Dinner without Family expected, got %s" % [value, ids])


## An injected table of seven lines that all hold: the tiers come in order, each is cut to
## its limit, and the whole is cut to max_lines.
func _check_the_order_and_the_caps() -> void:
	var real := TalkMenu._table
	var line := func(id: String, tier: String) -> Dictionary:
		return {"id": id, "tier": tier, "topic": "family", "tag": "warm", "condition": {"kind": "knowledge", "at_least": "stranger"}}
	TalkMenu._table = {"max_lines": 5, "tier_order": ["a", "b", "c"], "tier_limits": {"a": 2, "b": 1, "c": 3},
		"lines": [line.call("c1", "c"), line.call("b1", "b"), line.call("a1", "a"), line.call("a2", "a"), line.call("a3", "a"),
			line.call("b2", "b"), line.call("c2", "c"), line.call("c3", "c")]}
	var ids := _ids(_plain_person())
	TalkMenu._table = real
	_ok(ids == ["a1", "a2", "b1", "c1", "c2"], "tier order or caps wrong: %s" % [ids])


## Flirt is offered exactly when the affair's own gates open and the person is no stranger.
func _check_flirt_follows_its_gates() -> void:
	var ns = _state.player()
	var offered := 0
	var withheld := 0
	for person in _loader.people[PLAYER]:
		var pid := String(person.id)
		for value in [0.0, PresidentK.KNOWLEDGE_KNOWN]:
			_know(pid, value)
			var gates := Shadows.may_begin_affair(_state, ns, _loader, pid, _session(pid)) == ""
			var want: bool = gates and float(value) >= PresidentK.KNOWLEDGE_ACQUAINTANCE
			_ok(_ids(pid).has("flirt") == want, "%s at knowledge %s: Flirt %s but the gates say %s" % [pid, value, _ids(pid).has("flirt"), want])
			offered += 1 if want else 0
			withheld += 0 if want else 1
	_ok(withheld > 0, "no one was ever withheld Flirt")


func _chief_of_a_major():
	for company in Companies.majors_of(_loader, PLAYER):
		if String(company.chief_id) != "" and _loader.person_by_id.has(String(company.chief_id)):
			return company
	return null


func _check_a_plant_at_the_chiefs_firm() -> void:
	var company = _chief_of_a_major()
	if company == null:
		_failures.append("the fixture needs a major with a chief")
		return
	var chief := String(company.chief_id)
	var other := _plain_person()
	_ok(not _ids(chief).has("plant"), "a plant line with no closure open")
	var now := int(_state.year) * 12 + int(_state.month)
	# A closure at ANOTHER firm is nothing to this chief.
	for rival in Companies.majors_of(_loader, PLAYER):
		if String(rival.id) != String(company.id) and _state.player().companies.has(String(rival.id)):
			_state.player().companies[String(rival.id)]["closure"] = {"id": "y|%d" % now, "company_id": String(rival.id), "city_id": "c",
				"status": Closures.ANNOUNCED, "announced": now - 1, "due": now + 2, "ended": -1, "jobs": 100.0}
			_ok(not _ids(chief).has("plant"), "a closure at another firm gave this chief the plant line")
			_state.player().companies[String(rival.id)].erase("closure")
			break
	_state.player().companies[String(company.id)]["closure"] = {"id": "x|%d" % now, "company_id": String(company.id), "city_id": "c", "status": Closures.ANNOUNCED,
		"announced": now - 1, "due": now + 2, "ended": -1, "jobs": 100.0}
	_ok(_ids(chief).has("plant"), "the chief of a firm with a closure open was not offered the plant line")
	_ok(not _ids(other).has("plant"), "a person who chairs no such firm was offered the plant line")
	_state.player().companies[String(company.id)].erase("closure")
	_ok(not _ids(chief).has("plant"), "the plant line outlived the closure")


func _check_a_sector_warning_at_the_chiefs_firm() -> void:
	var company = _chief_of_a_major()
	var chief := String(company.chief_id)
	var now := int(_state.year) * 12 + int(_state.month)
	var ns = _state.player()
	_ok(not _ids(chief).has("sector"), "a sector line with no warning")
	ns.sector_drift["warnings"] = {String(company.sector): {"entered": now - 2}}
	_ok(_ids(chief).has("sector"), "a warning entered two months ago was not offered")
	ns.sector_drift["warnings"] = {String(company.sector): {"entered": now - 6}}
	_ok(not _ids(chief).has("sector"), "a warning entered six months ago was offered")
	ns.sector_drift["warnings"] = {}


## Over every person: the bill line is there when Deal's own offer is a vote whose division
## falls within three months, and nowhere else.
func _check_a_bill_within_three_months() -> void:
	var now := int(_state.year) * 12 + int(_state.month)
	var checked := 0
	for person in _loader.people[PLAYER]:
		var pid := String(person.id)
		var offer := Deal.offer_of(_state, _state.player(), _loader, pid)
		var ahead := int(offer.get("due_month", 0)) - now
		var want := String(offer.get("kind", "")) == "vote" and ahead >= 0 and ahead <= 3
		_ok(_ids(pid).has("bill") == want, "%s: bill line %s, Deal's offer says %s" % [pid, _ids(pid).has("bill"), want])
		checked += 1
	_ok(checked > 20, "only %d people were read" % checked)


func _check_gossip_people_are_tied_and_few() -> void:
	var seen := 0
	for person in _loader.people[PLAYER]:
		var pid := String(person.id)
		var people := TalkMenu.gossip_people(_state, _state.player(), _loader, pid, 4)
		_ok(people.size() <= 4, "%s reads %d people to gossip about" % [pid, people.size()])
		for p in people:
			seen += 1
			_ok(String(p["id"]) != pid and String(p["id"]) != President.leader_id(_state.player()), "%s may gossip about themselves or the president" % pid)
			_ok(["party", "want"].has(String(p["tie"]["kind"])), "a gossip name without a tie: %s" % [p])
	_ok(seen > 0, "nobody was ever tied to anybody")


## No filler: every line returned holds by its own condition, and across the roster the count
## is not always five (a stranger with no history gets a few).
func _check_nothing_fills_the_gap() -> void:
	var counts := {}
	for person in _loader.people[PLAYER]:
		var pid := String(person.id)
		_know(pid, 0.0)
		var n := TalkMenu.lines(_state, _state.player(), _loader, _session(pid)).size()
		counts[n] = int(counts.get(n, 0)) + 1
		_ok(n <= 5, "%s got %d lines" % [pid, n])
	_ok(not counts.has(5), "a stranger was given five lines: %s" % [counts])
	_ok(counts.has(1) or counts.has(2), "strangers never got a short list: %s" % [counts])


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_talk_menu: OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		print("test_talk_menu: FAIL (%d)" % _failures.size())
		quit(1)
