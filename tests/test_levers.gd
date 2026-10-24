extends SceneTree

## Headless test: godot --headless --script res://tests/test_levers.gd
## Non-zero exit on any failure.
##
## V5.2b b2, the audience (src/sim/levers.gd, src/sim/lever_odds.gd;
## docs/audiences-model.md "The audience"). What this file holds:
##
##   - THE ODDS READ THE PERSON (the spec's lever table and dominance matrix): each
##     trait moves the lever it names, the right way, and nothing leaves [0.05, 0.95].
##   - THE FOG NARROWS AND NEVER LIES (B4): a stranger's range is at least 0.30
##     wide, a known person's at most 0.10, and the true odds are always inside.
##   - A HIDDEN TRAIT READS AS UNKNOWN, NEVER WRONG (the spec's fog call).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Person = preload("res://src/core/person.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const President = preload("res://src/sim/president.gd")

const PLAYER := "FRA"
const BANDS := [0.165, 0.5, 0.835]

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_odds_follow_the_traits()
	_check_the_fog_narrows_and_never_lies()
	_check_known_traits_never_lie()

	_finish()


## Each trait the spec's table names moves its lever the way the table says, from
## one plain person in one plain cell.
func _check_odds_follow_the_traits() -> void:
	var cell := _cell()
	var plain = _person([], 0.5)
	if not LeverOdds.odds(_person(["stubborn"], 0.5), "argue", cell) < LeverOdds.odds(plain, "argue", cell):
		_fail("stubborn does not lower argue")
	if not LeverOdds.odds(plain, "argue", _cell({"aligned": false})) < LeverOdds.odds(plain, "argue", cell):
		_fail("an ask against a want does not lower argue")
	if not LeverOdds.odds(plain, "argue", _cell({"knowledge": 0.9})) > LeverOdds.odds(plain, "argue", _cell({"knowledge": 0.1})):
		_fail("knowledge does not raise argue")
	var bargain := LeverOdds.odds(plain, "bargain", cell)
	if not LeverOdds.odds(_person(["pragmatic"], 0.5), "bargain", cell) > bargain:
		_fail("pragmatic does not raise bargain")
	if not LeverOdds.odds(_person(["principled"], 0.5), "bargain", cell) < bargain:
		_fail("principled does not lower bargain")
	if not LeverOdds.odds(_person(["ambitious"], 0.5), "promise_date", cell) > LeverOdds.odds(plain, "promise_date", cell):
		_fail("ambitious does not raise a promise")
	if not LeverOdds.odds(_person([], 0.9), "promise_date", cell) < LeverOdds.odds(plain, "promise_date", cell):
		_fail("a skilled reader does not lower a promise")
	if not LeverOdds.odds(plain, "pressure", _cell({"standing": 0.2})) > LeverOdds.odds(plain, "pressure", _cell({"standing": 0.8})):
		_fail("pressure does not fall as standing rises")
	if not LeverOdds.odds(plain, "pressure", _cell({"approval": 70.0})) > LeverOdds.odds(plain, "pressure", _cell({"approval": 30.0})):
		_fail("pressure does not rise with the president's approval")
	if not LeverOdds.odds(_person(["networked"], 0.5), "pressure", cell) < LeverOdds.odds(plain, "pressure", cell):
		_fail("networked does not lower pressure")
	if not LeverOdds.odds(_person(["vain"], 0.5), "flatter", cell) > LeverOdds.odds(plain, "flatter", cell):
		_fail("vain does not raise flatter")
	if not LeverOdds.odds(_person([], 0.9), "flatter", cell) < LeverOdds.odds(_person([], 0.2), "flatter", cell):
		_fail("a skilled reader does not lower flatter")
	if LeverOdds.odds(plain, "friendship", cell) != -1.0:
		_fail("friendship is offered to an acquaintance")
	var friend := LeverOdds.odds(plain, "friendship", _cell({"relationship": "friend"}))
	if friend < 0.0 or not LeverOdds.odds(plain, "friendship", _cell({"relationship": "close"})) > friend:
		_fail("friendship is not offered to a friend, or is no stronger at close (%.3f)" % friend)
	if not LeverOdds.odds(plain, "argue", _cell({"rapport": 0.8})) > LeverOdds.odds(plain, "argue", _cell({"rapport": -0.8})):
		_fail("rapport does not raise the odds")
	var extremes := [
		_cell({"knowledge": 1.0, "rapport": 1.0, "relationship": "close", "standing": 0.0, "approval": 100.0}),
		_cell({"knowledge": 0.0, "rapport": -1.0, "aligned": false, "standing": 1.0, "approval": 0.0}),
	]
	for person in [plain, _person(["vain", "pragmatic", "ambitious"], 0.0), _person(["stubborn", "principled", "networked"], 1.0)]:
		for c in extremes:
			for lever in LK.LEVERS:
				var p := LeverOdds.odds(person, lever, c)
				if p != -1.0 and (p < LK.ODDS_MIN or p > LK.ODDS_MAX):
					_fail("%s's odds %.3f left [%.2f, %.2f]" % [lever, p, LK.ODDS_MIN, LK.ODDS_MAX])


## B4's widths at the band edges, and the range holds the truth for every France
## person, lever and band -- placed by a seeded offset, so not always centred.
func _check_the_fog_narrows_and_never_lies() -> void:
	if LeverOdds.fog_width(0.0) < 0.30 or LeverOdds.fog_width(0.32) < 0.30:
		_fail("a stranger's range is narrower than 0.30 (%.3f at 0, %.3f at 0.32)" % [LeverOdds.fog_width(0.0), LeverOdds.fog_width(0.32)])
	if LeverOdds.fog_width(0.67) > 0.10 or LeverOdds.fog_width(1.0) > 0.10:
		_fail("a known person's range is wider than 0.10 (%.3f at 0.67)" % LeverOdds.fog_width(0.67))
	var off_centre := 0
	var ranges := 0
	for person in _loader.people[PLAYER]:
		for k in BANDS:
			var c := _cell({"knowledge": k, "relationship": "friend", "standing": 0.5})
			for lever in LK.LEVERS:
				var p := LeverOdds.odds(person, lever, c)
				var r: Vector2 = LeverOdds.shown_range(person.id, lever, p, k)
				ranges += 1
				if p < r.x - 0.000001 or p > r.y + 0.000001:
					_fail("%s %s at %.3f: the true odds %.3f are outside [%.3f, %.3f]" % [person.id, lever, k, p, r.x, r.y])
					return
				if r.x < 0.0 or r.y > 1.0:
					_fail("%s %s: the range [%.3f, %.3f] leaves [0, 1]" % [person.id, lever, r.x, r.y])
					return
				var at := (p - r.x) / maxf(r.y - r.x, 0.000001)
				if at < 0.4 or at > 0.6:
					off_centre += 1
	if off_centre == 0:
		_fail("every one of %d ranges is centred on the truth: the fog says the answer" % ranges)


## A trait shows once the president knows the person well enough, and only a real
## one: nothing at 0, everything at "known", and the set only grows.
func _check_known_traits_never_lie() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	for person in _loader.people[PLAYER]:
		if person.id == President.leader_id(ns):
			continue
		var before: Array[String] = []
		for k in [0.0, 0.2, 0.4, 0.6, 0.67, 1.0]:
			ns.person_knowledge[person.id] = k
			var shown: Array[String] = LeverOdds.known_traits(ns, person)
			for t in shown:
				if not person.traits.has(t):
					_fail("%s shows a trait they do not have: %s" % [person.id, t])
			for t in before:
				if not shown.has(t):
					_fail("%s's trait %s disappeared as knowledge rose to %.2f" % [person.id, t, k])
			if k == 0.0 and not shown.is_empty():
				_fail("%s shows traits to a stranger: %s" % [person.id, shown])
			if k >= 0.67 and shown.size() != person.traits.size():
				_fail("%s at knowledge %.2f still hides traits (%s of %s)" % [person.id, k, shown, person.traits])
			before = shown


func _cell(over := {}) -> Dictionary:
	var c := {"knowledge": 0.5, "rapport": 0.0, "relationship": "acquaintance", "aligned": true, "standing": 0.5, "approval": 50.0}
	c.merge(over, true)
	return c


func _person(traits: Array, skill: float):
	var p = Person.new()
	p.id = "TST_person"
	var t: Array[String] = []
	for x in traits:
		t.append(String(x))
	p.traits = t
	p.social_skill = skill
	return p


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_levers: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
