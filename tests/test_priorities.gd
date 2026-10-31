extends SceneTree

## Headless test: godot --headless --script res://tests/test_priorities.gd
## Non-zero exit on any failure.
##
## V5.3-0 (docs/design/v5.3-0-readability.md 2.3, bands RF1 and RF2): the monthly
## briefing's ranking, src/ui/priorities.gd.
##   - RF1: every month of 24, for each of the four playable nations, run through the
##     game's own month (WorldMonth.tick_month), shows exactly 3 lines of 3 kinds;
##   - RF2's fixtures: nothing hidden is ever named (an armed event, evidence, a
##     grudge under the "hostile" band); a noise-only poll raises no bloc line while
##     a real move does; a held minor card in its last month keeps its slot over an
##     election three months away, two held cards fold into one line; a request
##     about to lapse is never damped by novelty; a quiet month rotates.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const MusicBand = preload("res://src/ui/music_band.gd")

const PLAYABLE := ["DEU", "FRA", "GBR", "POL"]
const MONTHS := 24

var _failures: Array[String] = []
var _loader


func _initialize() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	for nation in PLAYABLE:
		_check_always_three(nation)
	_check_fog()
	_check_noise_and_move()
	_check_held_first()
	_check_also_due()
	_check_no_damping()
	_check_quiet_rotates()
	_check_situation_and_band()
	if _failures.is_empty():
		print("test_priorities: all checks passed")
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1 if not _failures.is_empty() else 0)


func _new(nation: String):
	var state = GameState.new_game(_loader, nation)
	state.year = 2026
	state.month = 1
	return state


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _check_always_three(nation: String) -> void:
	var state = _new(nation)
	var memory := {}
	var repeats := 0
	var overlap := 0
	var last: Array = []
	for i in MONTHS:
		_advance(state)
		WorldMonth.tick_month(state, _loader)
		var r: Dictionary = Priorities.rank(state, _loader, {"memory": memory})
		memory = r["memory"]
		var lines: Array = r["lines"]
		var kinds := {}
		for l in lines:
			kinds[l["kind"]] = true
		if lines.size() != 3 or kinds.size() != 3:
			_fail("%s month %d: %d lines of %d kinds: %s" % [nation, i + 1, lines.size(), kinds.size(), _names(lines)])
		var shared := 0
		for l in lines:
			for p in last:
				if p == _name(l):
					shared += 1
		if i > 0:
			overlap += shared
			repeats += 1 if shared == 3 else 0
		last = lines.map(_name)
		_check_never_unshown(state, r, "%s month %d" % [nation, i + 1])
	print("priorities %s: %d full repeats of %d, mean overlap %.2f" % [nation, repeats, MONTHS - 1, float(overlap) / float(MONTHS - 1)])


func _check_fog() -> void:
	var state = _new("FRA")
	var ns = state.player()
	var people: Array = _loader.people["FRA"]
	ns.event_armed.append({"event_id": "fog_armed"})
	ns.exposure_evidence.append({"id": "fog_evidence", "person_id": String(people[0].id)})
	ns.person_grudges[String(people[1].id)] = 0.30
	for l in Priorities.rank(state, _loader)["lines"]:
		if ["fog_armed", "fog_evidence", String(people[0].id), String(people[1].id)].has(String(l["subject"])):
			_fail("fog: a hidden register reached the briefing: %s" % _name(l))
	# The positive control: the same person at "hostile, may leak" is named.
	ns.person_grudges[String(people[1].id)] = 0.50
	if not _subjects(Priorities.rank(state, _loader)["lines"]).has(String(people[1].id)):
		_fail("fog control: a hostile person (grudge 0.50) is not named")


func _check_noise_and_move() -> void:
	var state = _new("FRA")
	_fake_history(state, 0.0)
	if _kinds_of(Priorities.rank(state, _loader)["lines"], false).has("bloc"):
		_fail("a noise-only poll raised a bloc priority")
	state = _new("FRA")
	_fake_history(state, -12.0)
	var r: Dictionary = Priorities.rank(state, _loader)
	if not _kinds_of(r["lines"], false).has("bloc"):
		_fail("a 12-point polled fall of one bloc raised no bloc priority: %s" % _names(r["lines"]))


## Six months of history, every bloc flat at 50; the last three of `fall_bloc` moved.
func _fake_history(state, move: float) -> void:
	state.history.clear()
	for i in 6:
		var blocs := {}
		for bloc in OpinionK.BLOC_KEYS:
			blocs[bloc] = 50.0 + (move if bloc == OpinionK.BLOC_KEYS[0] and i >= 3 else 0.0)
		state.history.append({"year": 2025, "month": 7 + i, "bloc_approval": blocs, "deficit_pct_gdp": 3.0})


func _check_held_first() -> void:
	var state = _new("FRA")
	var ns = state.player()
	_vote_in(state, 3)
	ns.event_queue.clear()
	ns.event_queue.append({"event_id": "minor_last", "months_left": 1, "severity": 1, "interrupt": false})
	# Three that outscore it (the tabled bill's vote next month 8, a commitment due next
	# month 7, the election 6.3): by score alone the minor card (4.5) would be fourth.
	var now := int(state.year) * 12 + int(state.month)
	ns.tabled_bill = {"law_id": "contest_bill", "referendum": false, "vote_year": now / 12, "vote_month": now % 12 + 1, "vote_day": 1}
	ns.commitments.append({"kind": "promise", "person_id": "FRA_x", "object": "contest", "made_month": now, "due_month": now + 1})
	var lines: Array = Priorities.rank(state, _loader, {"held_events": ["minor_last"]})["lines"]
	if not _subjects(lines).has("minor_last"):
		_fail("a held minor card in its last month lost its slot: %s" % _names(lines))
	ns.event_queue.append({"event_id": "major_held", "months_left": 4, "severity": 2, "interrupt": false})
	lines = Priorities.rank(state, _loader, {"held_events": ["minor_last", "major_held"]})["lines"]
	var decisions := lines.filter(func(l): return l["kind"] == "decision")
	if decisions.size() != 1 or String(decisions[0]["subject"]) != "major_held" or int(decisions[0]["more"]) != 1:
		_fail("two held decisions are not one line, the major first, '+1 more': %s" % _names(lines))


## The parent's rule on #217: an item in its last month is a line or in the footer.
func _check_never_unshown(state, r: Dictionary, where: String) -> void:
	var ns = state.player()
	var now := int(state.year) * 12 + int(state.month)
	var shown := _subjects(r["lines"]) + _subjects(r["also_due"])
	for row in ns.audience_requests:
		if String(row.get("status", "")) == "pending" and String(row.get("person_id", "")).begins_with(String(ns.id) + "_") \
				and int(row.get("deadline_month", 0)) - now == 1 and not shown.has(String(row["id"])):
			_fail("%s: request %s lapses next month, unshown: %s" % [where, row["id"], _names(r["lines"])])
	for entry in ns.event_queue:
		if int(entry.get("months_left", 0)) <= 1 and not shown.has(String(entry.get("event_id", ""))):
			_fail("%s: card %s in its last month, unshown" % [where, entry.get("event_id", "")])


## Systems' RF2 case (#217, FRA idle May 2029): two held cards and a vote next month
## fill the three lines; the request lapsing next month goes to the footer.
func _check_also_due() -> void:
	var state = _new("FRA")
	var ns = state.player()
	_vote_in(state, 1)
	var now := int(state.year) * 12 + int(state.month)
	ns.event_queue.clear()
	ns.event_queue.append({"event_id": "crisis_held", "months_left": 2, "severity": 3, "interrupt": true})
	ns.event_queue.append({"event_id": "major_held", "months_left": 3, "severity": 2, "interrupt": false})
	var pid := ""
	for person in _loader.people["FRA"]:
		if String(person.kind) == "politician":
			pid = String(person.id)
			break
	ns.audience_requests.append({"id": "%s|%d" % [pid, now], "person_id": pid, "object": "x", "status": "pending",
		"arrived_month": now - 1, "deadline_month": now + 1})
	var r: Dictionary = Priorities.rank(state, _loader, {"held_events": ["crisis_held", "major_held"], "programme_held": false})
	var id := "%s|%d" % [pid, now]
	if _subjects(r["lines"]).has(id):
		_fail("premise: the request took a line (%s) -- the fixture no longer crowds it" % _names(r["lines"]))
	elif not _subjects(r["also_due"]).has(id):
		_fail("a request lapsing next month, crowded out, is not in the footer: %s" % str(_subjects(r["also_due"])))
	if r["also_due"].any(func(c): return bool(c["standing"])):
		_fail("a standing read is in the footer")
	# A line's "+N more" names what it folded, so the briefing's close can count a
	# folded request as seen: every fold is in `folded`, one per count.
	for line in r["lines"]:
		if (line.get("folded", []) as Array).size() != int(line["more"]):
			_fail("a line counts %d more but names %d folded" % [int(line["more"]), (line.get("folded", []) as Array).size()])


func _vote_in(state, months: int) -> void:
	var ns = state.player()
	var at := int(state.year) * 12 + int(state.month) + months
	for prefix in ["next_election", "next_executive"]:
		ns.set(prefix + "_year", (at - 1) / 12)
		ns.set(prefix + "_month", (at - 1) % 12 + 1)


func _check_no_damping() -> void:
	var state = _new("FRA")
	var ns = state.player()
	var now := int(state.year) * 12 + int(state.month)
	var pid := ""
	for person in _loader.people["FRA"]:
		if String(person.id).begins_with("FRA_"):
			pid = String(person.id)
			break
	ns.audience_requests.append({"id": "%s|%d" % [pid, now], "person_id": pid, "object": "x", "status": "pending",
		"arrived_month": now, "deadline_month": now + 1})
	var first: Dictionary = Priorities.rank(state, _loader)
	var second: Dictionary = Priorities.rank(state, _loader, {"memory": first["memory"]})
	var a := _line_of(first["lines"], "request")
	var b := _line_of(second["lines"], "request")
	if a.is_empty() or b.is_empty() or not is_equal_approx(float(a["score"]), float(b["score"])):
		_fail("a request lapsing next month was damped or dropped: %s then %s" % [str(a), str(b)])


## The same quiet state twelve months running: the standing reads give way to one
## another under novelty, so the three are not the same three every month.
func _check_quiet_rotates() -> void:
	var state = _new("FRA")
	var ns = state.player()
	ns.event_queue.clear()
	ns.audience_requests.clear()
	ns.person_grudges.clear()
	var memory := {}
	var last := ""
	var repeats := 0
	for i in 12:
		var r: Dictionary = Priorities.rank(state, _loader, {"memory": memory, "programme_held": false})
		memory = r["memory"]
		var key := ",".join(r["lines"].map(_name))
		repeats += 1 if key == last else 0
		last = key
	if repeats > 2:
		_fail("a quiet month repeats its three lines %d times of 11" % repeats)


## 2.6 and 4.3 (RF9's rule): a crisis line is a crisis, a held one tense, an
## election far off calm; the band goes up at once, down after two calmer months,
## and the campaign takes the last three months before a vote.
func _check_situation_and_band() -> void:
	var calm := [{"kind": "election", "deadline_month": 99, "u": 0.4, "w": 1.0, "held": false, "standing": true}]
	var tense := [{"kind": "request", "deadline_month": 5, "u": 1.0, "w": 6.0, "held": false, "standing": false}]
	var crisis := [{"kind": "crisis", "deadline_month": 5, "u": 1.0, "w": 10.0, "held": true, "standing": false}]
	if Priorities.situation(calm) != "calm" or Priorities.situation(tense) != "tense" or Priorities.situation(crisis) != "crisis":
		_fail("situation: %s / %s / %s" % [Priorities.situation(calm), Priorities.situation(tense), Priorities.situation(crisis)])
	var b := MusicBand.step({}, "calm", 20)
	b = MusicBand.step(b, "crisis", 20)
	if b["band"] != "crisis":
		_fail("the band did not go up to crisis at once")
	b = MusicBand.step(b, "calm", 20)
	if b["band"] != "crisis":
		_fail("the band came down after one calm month")
	b = MusicBand.step(b, "calm", 20)
	if b["band"] != "calm":
		_fail("the band did not come down after two calm months")
	if MusicBand.step(b, "calm", 2)["band"] != "campaign" or MusicBand.step(b, "crisis", 2)["band"] != "crisis":
		_fail("the campaign band does not take the last three months, or beats a crisis")


func _line_of(lines: Array, kind: String) -> Dictionary:
	for l in lines:
		if l["kind"] == kind:
			return l
	return {}


func _kinds_of(lines: Array, standing: bool) -> Array:
	return lines.filter(func(l): return bool(l["standing"]) == standing).map(func(l): return l["kind"])


func _subjects(lines: Array) -> Array:
	return lines.map(func(l): return String(l["subject"]))


func _name(l: Dictionary) -> String:
	return "%s:%s" % [l["kind"], l["subject"]]


func _names(lines: Array) -> String:
	return ", ".join(lines.map(_name))


func _fail(message: String) -> void:
	_failures.append(message)
