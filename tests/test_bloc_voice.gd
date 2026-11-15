extends SceneTree

## Headless test: godot --headless --script res://tests/test_bloc_voice.gd
## Non-zero exit on any failure.
##
## V5.3 e, the author's "Construire le discours" (Gameplay's regions brief, section 5b):
## when a development fund opens in the region a figure wants, that figure SPEAKS FOR the
## government, once -- the mirror of a briefing against it: the same two blocs, through the
## same door, at CK.SPEAK_SHARE of the briefing's size, booked in the acts' share so it fades
## on the same half-life and the acts band counts it. A hostile figure does not speak; it
## fires on the fund, not on an ask; an office served is left out.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")

const METERS := {"press_freedom": 50.0, "judicial_independence": 50.0, "grievance": 30.0}

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_a_fund_opened_makes_its_figure_speak_once()
	_check_a_hostile_figure_does_not_speak()
	_check_an_office_served_does_not_speak()
	_check_the_voice_fades_with_the_acts()
	_finish()


func _state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 3
	return state


## The first FRA figure with a region: want, and that region.
func _figure() -> Array:
	for person in _loader.people["FRA"]:
		for want in person.wants:
			if String(want["object"]).begins_with("region:"):
				return [person, String(want["object"]).substr(7)]
	return []


func _open(state, region_id: String) -> void:
	var rule: Dictionary = RegionFunds.limits(_loader)
	var opened := RegionFunds.start(state, state.player(), _loader, region_id, float(rule["share_pct"][0]), int(rule["years"][1]))
	if not bool(opened.get("ok", false)):
		_fail("premise: the fund did not open: %s" % [opened])


func _spoke(acts: Array, pid: String) -> bool:
	for act in acts:
		if String(act["act"]) == "speak_for" and String(act["person_id"]) == pid:
			return true
	return false


func _check_a_fund_opened_makes_its_figure_speak_once() -> void:
	var f := _figure()
	if f.is_empty():
		_fail("premise: no FRA figure wants a region's fund")
		return
	var state = _state()
	var ns = state.player()
	var person = f[0]
	Characters.tick_month(state, _loader, METERS)  # the want settles unserved first
	_open(state, f[1])
	# A standing of its own, so the size is read off the figure's standing and not a default.
	ns.person_standing[person.id] = 0.7
	var before: Dictionary = ns.bloc_offset.duplicate()
	var acts_before: Dictionary = ns.act_bloc_offset.duplicate()
	var acts: Array = Characters.tick_month(state, _loader, METERS)
	if not _spoke(acts, String(person.id)):
		_fail("speak: the figure did not speak the month its fund opened: %s" % [acts])
		return
	var want := -CK.SPEAK_SHARE * Characters.brief_magnitude(person, float(ns.person_standing.get(person.id, 0.0)))
	if want <= 0.0:
		_fail("speak: the voice's size is not a gain (%s)" % want)
	for bloc in CK.BRIEF_BLOCS:
		# The month's other moves on the bloc (the acts' fade, any other act) are read off the
		# acts' share, so the speech is the share's growth beyond its fade.
		var faded := float(acts_before.get(bloc, 0.0)) * CK.ACT_OFFSET_MONTHLY_KEEP
		var grew := float(ns.act_bloc_offset.get(bloc, 0.0)) - faded
		if absf(grew - want) > 1e-9:
			_fail("speak: %s's acts' share grew %s, the voice is %s" % [bloc, grew, want])
		if float(ns.bloc_offset[bloc]) <= float(before.get(bloc, 0.0)):
			_fail("speak: %s's offset did not rise" % bloc)
	# Only the briefing's two blocs: any other bloc's share only fades.
	for bloc in ns.act_bloc_offset:
		if not CK.BRIEF_BLOCS.has(bloc):
			var other := float(ns.act_bloc_offset[bloc]) - float(acts_before.get(bloc, 0.0)) * CK.ACT_OFFSET_MONTHLY_KEEP
			if absf(other) > 1e-9:
				_fail("speak: the voice moved %s's share by %s" % [bloc, other])
	# Once: the next month, the fund still open, nothing more.
	if _spoke(Characters.tick_month(state, _loader, METERS), String(person.id)):
		_fail("speak: the figure spoke again the month after")


func _check_a_hostile_figure_does_not_speak() -> void:
	var f := _figure()
	var state = _state()
	var ns = state.player()
	var person = f[0]
	Characters.tick_month(state, _loader, METERS)
	ns.person_grudges[person.id] = CK.GRUDGE_BRIEF_THRESHOLD + 0.01
	# A word of silence keeps them from briefing, so their one act is free and only the
	# hostility stands between them and the voice.
	ns.commitments.append({"kind": "silence", "person_id": String(person.id), "due_month": 9999})
	_open(state, f[1])
	var acts: Array = Characters.tick_month(state, _loader, METERS)
	for act in acts:
		if String(act["person_id"]) == String(person.id):
			_fail("hostile: premise, the silenced figure still acted (%s)" % act["act"])
	if _spoke(acts, String(person.id)):
		_fail("hostile: a figure past the briefing's grudge spoke for the government")


## A post given serves an office want; the voice is a fund's only (offices left out).
func _check_an_office_served_does_not_speak() -> void:
	var state = _state()
	var ns = state.player()
	var person = null
	var portfolio := ""
	for p in _loader.people["FRA"]:
		for want in p.wants:
			if String(want["object"]).begins_with("office:portfolio:") and String(want["stance"]) == "want":
				person = p
				portfolio = String(want["object"]).substr("office:portfolio:".length())
				break
		if person != null:
			break
	if person == null or not ns.cabinet.has(portfolio):
		_fail("premise: no FRA figure wants a portfolio in the cabinet")
		return
	Characters.tick_month(state, _loader, METERS)
	ns.cabinet[portfolio] = String(person.party_id)
	var acts: Array = Characters.tick_month(state, _loader, METERS)
	if _spoke(acts, String(person.id)):
		_fail("office: a figure handed a post spoke for the government")


func _check_the_voice_fades_with_the_acts() -> void:
	var f := _figure()
	var state = _state()
	var ns = state.player()
	Characters.tick_month(state, _loader, METERS)
	_open(state, f[1])
	Characters.tick_month(state, _loader, METERS)
	var share := float(ns.act_bloc_offset.get("workers", 0.0))
	Characters.tick_month(state, _loader, METERS)
	var next := float(ns.act_bloc_offset.get("workers", 0.0))
	if share <= 0.0 or next >= share:
		_fail("fade: the workers' share went %s then %s; the voice should fade" % [share, next])


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_bloc_voice.gd")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL " + f)
	quit(1)
