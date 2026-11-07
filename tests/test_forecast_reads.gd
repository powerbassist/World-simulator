extends SceneTree

## Headless test: godot --headless --script res://tests/test_forecast_reads.gd
## Non-zero exit on any failure.
##
## The forecast a player reads is the division's own (QA's gate on the step 5 UI, the
## external review's finding 3 on #298). LawPanel.forecast_counts is the catalogue's bar, the
## briefing's and the council's. It was a copy of the division's walk that had not learned
## a bill's size in the members' view, a pledge, the peel or an address's sway, so after an
## address it moved on none of 96 reads while the division's yes moved up to 37 seats.
##
## The pin: at the division's own band the bar IS resolve_vote, law by law, with each term
## live. At the catalogue's wider blur it still moves after an address. With no term live it
## reads as it always did, against a copy of the old walk kept here for that.
##
## Finding 5 lives here too: a pledge is the deputy's word to the president, so the words
## that read "Your word to" must not say it.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Division = preload("res://src/sim/division.gd")
const Address = preload("res://src/sim/address.gd")
const President = preload("res://src/sim/president.gd")
const LawPanel = preload("res://src/ui/law_panel.gd")
const BriefingEffects = preload("res://src/ui/briefing_effects.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const PeopleNow = preload("res://src/ui/people_now.gd")
const Words = preload("res://src/ui/lever_words.gd")
const Strings = preload("res://src/ui/strings.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const DiaryGrid = preload("res://src/ui/diary_grid.gd")

const NATIONS := ["FRA", "DEU", "GBR", "POL"]

## What AudienceDriver's two lists read off the game.
class FakeMain:
	var _state
	var _loader


var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	for nation in NATIONS:
		_check_no_term_reads_as_before(nation)
		_check_the_address(nation)
		_check_a_pledge(nation)
	_check_a_grade()
	_check_a_tabled_grade()
	_check_a_pledge_is_not_your_word()
	_finish()


func _state(nation: String):
	return GameState.new_game(_loader, nation)


func _laws(ns) -> Array:
	return Legislature.available(ns, _loader.laws).filter(func(law): return not law.constitutional)


## forecast_counts at the division's band against the division itself.
func _same_as_the_division(ns, law, label: String) -> bool:
	var parties: Array = _loader.parties.get(ns.id, [])
	var c: Dictionary = LawPanel.forecast_counts(ns, parties, law, LK.ABSTAIN_BAND)
	var v: Dictionary = Legislature.resolve_vote(ns, parties, law)
	if int(c["yes"]) != int(v["yes_seats"]) or int(c["no"]) != int(v["no_seats"]) or int(c["undecided"]) != int(v["abstain_seats"]):
		_fail("%s on %s: the bar reads %d, %d, %d, the division %d, %d, %d" % [label, law.id, c["yes"], c["no"], c["undecided"],
			v["yes_seats"], v["no_seats"], v["abstain_seats"]])
		return false
	return true


## The walk this bar had before the terms: with none live the bar must not have moved, at
## either band. Kept here as the fixture, since the code no longer holds it.
func _old_walk(ns, law, band: float) -> Dictionary:
	var yes := 0
	var no := 0
	var undecided := 0
	var rebels := 0
	for party in _loader.parties.get(ns.id, []):
		var s: float = Legislature.support(ns, party, law)
		var own: float = Legislature.spatial_support(ns, party, law)
		var seats: int = int(ns.seats_by_party.get(party.id, 0))
		var broke := 0
		if Legislature.vote_of(own) != Legislature.vote_of(s):
			broke = Discipline.rebel_seats(ns, party, s, own)
		rebels += broke
		if s > band:
			yes += seats - broke
		elif s < -band:
			no += seats - broke
		else:
			undecided += seats - broke
		if own > band:
			yes += broke
		elif own < -band:
			no += broke
		else:
			undecided += broke
	return {"yes": yes, "no": no, "undecided": undecided, "rebels": rebels}


func _check_no_term_reads_as_before(nation: String) -> void:
	var state = _state(nation)
	var ns = state.player()
	var parties: Array = _loader.parties.get(nation, [])
	var laws := _laws(ns)
	if laws.is_empty():
		_fail("premise: %s has no open law" % nation)
	for law in laws:
		for band in [LK.ABSTAIN_BAND, LawPanel.FORECAST_UNCERTAIN_BAND]:
			var now: Dictionary = LawPanel.forecast_counts(ns, parties, law, band)
			var then := _old_walk(ns, law, band)
			if now != then:
				_fail("%s %s at %s: with no term live the bar reads %s, it read %s" % [nation, law.id, band, now, then])
		_same_as_the_division(ns, law, nation + " no term")


## An address: the bar is the division on every law, and the blur the catalogue shows moves.
func _check_the_address(nation: String) -> void:
	var state = _state(nation)
	var ns = state.player()
	var parties: Array = _loader.parties.get(nation, [])
	var now: int = int(state.year) * 12 + int(state.month)
	var moved := 0
	for law in _laws(ns):
		var before: Dictionary = LawPanel.forecast_counts(ns, parties, law, LawPanel.FORECAST_UNCERTAIN_BAND)
		Address._write(ns, String(law.id), Address.shifts(ns, _loader.outlets.get(nation, []), law, 0), now)
		_same_as_the_division(ns, law, nation + " address")
		if LawPanel.forecast_counts(ns, parties, law, LawPanel.FORECAST_UNCERTAIN_BAND) != before:
			moved += 1
	if moved == 0:
		_fail("%s: an address moved the catalogue's bar on no law" % nation)
	# The real verb reaches it too: the estimate's "after" is what the bar now says.
	var fresh = _state(nation)
	var fns = fresh.player()
	var law = _laws(fns)[0]
	var est: Dictionary = Address.estimate(fresh, fns, _loader, law)
	if not bool(Address.give(fresh, _loader, String(law.id)).get("ok", false)):
		_fail("%s: premise: the address on %s was refused" % [nation, law.id])
		return
	var c: Dictionary = LawPanel.forecast_counts(fns, parties, law, LK.ABSTAIN_BAND)
	if int(c["yes"]) != int(est["after"]["yes_seats"]) or int(c["no"]) != int(est["after"]["no_seats"]):
		_fail("%s: the bar reads %s after the address, the strip said %s" % [nation, c, est["after"]])


func _check_a_pledge(nation: String) -> void:
	var state = _state(nation)
	var ns = state.player()
	var now: int = int(state.year) * 12 + int(state.month)
	for law in _laws(ns):
		var verdict: Dictionary = Legislature.resolve_vote(ns, _loader.parties.get(nation, []), law)
		for party in _loader.parties.get(nation, []):
			if String(verdict["party_votes"][party.id]) != "no" or int(ns.seats_by_party.get(party.id, 0)) <= 20:
				continue
			for person in _loader.people[nation]:
				if String(person.party_id) == party.id and President.pledge(state, ns, _loader, String(person.id), String(law.id), now + 3):
					var after: Dictionary = Legislature.resolve_vote(ns, _loader.parties.get(nation, []), law)
					if int(after["yes_seats"]) <= int(verdict["yes_seats"]):
						_fail("%s: premise: the pledge moved no seat on %s" % [nation, law.id])
					_same_as_the_division(ns, law, nation + " pledge")
					return
	_fail("%s: premise: no law with a party against it and a person to pledge" % nation)


## A size: the size term in the members' view, and the peel on a yes line.
func _check_a_grade() -> void:
	for nation in NATIONS:
		var state = _state(nation)
		var ns = state.player()
		var graded := 0
		for law in _laws(ns):
			if not law.effects.has("spending_pct_gdp"):
				continue
			var row = LawMagnitude.copy(law)
			row.magnitude = {"value": 40.0, "reference": 40.0, "unit": "units"}
			for scale in [0.1, 10.0]:
				_same_as_the_division(ns, LawMagnitude.scaled(row, scale), "%s grade %s" % [nation, scale])
				graded += 1
		if graded == 0:
			_fail("%s: premise: no law to grade" % nation)


## A bill tabled at a grade: the catalogue's row is the law at its reference, and the bar
## must read what the chamber will vote on, as Division.forecast does.
func _check_a_tabled_grade() -> void:
	var state = _state("FRA")
	var ns = state.player()
	var parties: Array = _loader.parties.get("FRA", [])
	var law = null
	for candidate in _laws(ns):
		if candidate.effects.has("spending_pct_gdp"):
			law = candidate
			break
	if law == null:
		_fail("premise: no law to table")
		return
	var at_rest: Dictionary = {}
	var held: Dictionary = law.magnitude
	law.magnitude = {"value": 40.0, "reference": 40.0, "unit": "units"}
	at_rest = LawPanel.forecast_counts(ns, parties, law, LK.ABSTAIN_BAND)
	ns.tabled_bill = {"law_id": String(law.id), "vote_year": int(state.year), "vote_month": int(state.month), "vote_day": 28, "scale": 10.0}
	var c: Dictionary = LawPanel.forecast_counts(ns, parties, law, LK.ABSTAIN_BAND)
	var v: Dictionary = Division.forecast(state, ns, _loader)
	if int(c["yes"]) != int(v["yes_seats"]) or int(c["no"]) != int(v["no_seats"]):
		_fail("tabled at ten times: the bar reads %s, the division %s for %s against" % [c, v["yes_seats"], v["no_seats"]])
	if c == at_rest:
		_fail("premise: ten times moved nothing on %s" % law.id)
	law.magnitude = held
	ns.tabled_bill = {}


## Finding 5: the deputy gave the word. Nowhere does the player read a pledge as their own,
## and a pledge is not a thing they have to keep, so it does not rank or read as due.
func _check_a_pledge_is_not_your_word() -> void:
	var state = _state("FRA")
	var ns = state.player()
	var now: int = int(state.year) * 12 + int(state.month)
	# Not the president, whom the people's list leaves out.
	var person = _loader.people["FRA"].filter(func(p): return String(p.id) != President.leader_id(ns))[0]
	var who: String = _loader.person_name(String(person.id))
	var row := {"kind": "pledge", "person_id": String(person.id), "object": "law:x", "party_id": String(person.party_id),
		"made_month": now - 1, "due_month": now + 1}
	ns.commitments.append(row)
	var diary := Words.commitment_text("pledge", who, "A bill", now + 1)
	if diary.contains(Strings.t("Your word to %s, due %s (their want: %s).").get_slice("%", 0)):
		_fail("diary: a pledge reads as the president's word: '%s'" % diary)
	if not diary.contains(who) or not diary.contains("A bill"):
		_fail("diary: the pledge does not name who and what: '%s'" % diary)
	for line in Priorities.rank(state, _loader, {"held_events": [], "programme_held": false})["lines"]:
		if String(line["kind"]) == "commitment" and String(line["subject"]).begins_with("pledge|"):
			_fail("briefing: a pledge ranks as the president's commitment (%s)" % line["subject"])
	for entry in PeopleNow.chosen(state, _loader, func(_pid) -> String: return "left"):
		if String(entry["id"]) == String(person.id) and String(entry["reason"]) == Strings.t("A promise falls due"):
			_fail("people: a pledge reads as a promise of the player's falling due")
	var seat := FakeMain.new()
	seat._state = state
	seat._loader = _loader
	if not AudienceDriver.given_lines(seat).is_empty():
		_fail("the Your word list carries a pledge: %s" % [AudienceDriver.given_lines(seat)])
	var grid := DiaryGrid.new()
	grid._state = state
	grid._loader = _loader
	var due: int = now + 1
	var days: Dictionary = grid._entries((due - 1) / 12, (due - 1) % 12 + 1)
	var found := false
	for day in days:
		for entry in days[day]:
			if String(entry.get("subject", "")).begins_with("pledge|"):
				found = true
				if String(entry.get("call", "")) != "":
					_fail("diary: a pledge offers a Call before it is judged, as a word of the president's would")
	if not found:
		_fail("premise: the diary shows no pledge row")
	grid.free()
	ns.commitments.clear()
	for verdict in [["kept", "Their word: %s kept it."], ["broken", "Their word: %s broke it."]]:
		ns.commitments_judged.clear()
		ns.commitments_judged.append({"kind": "pledge", "person_id": String(person.id), "object": "law:x",
			"verdict": verdict[0], "judged_month": now})
		var said := ""
		for line in BriefingEffects.lines(state, _loader, {}):
			said += String(line["text"]) + "|"
		if said.contains(Strings.t("Your word to %s: kept") % who) or said.contains(Strings.t("Your word to %s: broken") % who):
			_fail("briefing: a judged pledge reads as your word: '%s'" % said)
		if not said.contains(Strings.t(verdict[1]) % who):
			_fail("briefing: a judged pledge says nothing of %s's word: '%s'" % [who, said])
		if not AudienceDriver.judged_rows(seat).is_empty():
			_fail("the Your word list carries a judged pledge: %s" % [AudienceDriver.judged_rows(seat)])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_forecast_reads: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
