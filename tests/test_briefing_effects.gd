extends SceneTree

## Headless test: godot --headless --script res://tests/test_briefing_effects.gd
## Non-zero exit on any failure.
##
## V5.3-0, band RF5 (docs/design/v5.3-0-readability.md 2.5): "what your choices did"
## is BOOKED only from a register that booked the number as the choice's own (a
## law's passage this month, a commitment judged, a request lapsed), and every other
## line is UNCERTAIN, worded so, and never wears GOOD or BAD.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const BriefingEffects = preload("res://src/ui/briefing_effects.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const NationState = preload("res://src/core/nation_state.gd")

var _failures: Array[String] = []
var _loader


func _initialize() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_check_law_booked()
	_check_quiet()
	_check_mixed()
	_check_decided_unbooked()
	_check_division_known()
	_check_answered_requests()
	if _failures.is_empty():
		print("test_briefing_effects: all checks passed")
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1 if not _failures.is_empty() else 0)


func _state():
	var state = GameState.new_game(_loader, "FRA")
	for i in 8:
		state.history.append({"year": 2025, "month": 4 + i, "overall_approval_pct": 40.0 + i,
			"unemployment_pct": 7.0, "deficit_pct_gdp": 4.0 + 0.1 * i, "growth_annual_pct": 1.0, "debt_to_gdp_pct": 110.0})
	return state


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _check_law_booked() -> void:
	var state = _state()
	var ns = state.player()
	var law = _loader.laws[0]
	ns.law_ledger[String(law.id)] = {"channels": {"bloc_offset": {"workers": -0.3, "business": 0.02}}, "months": [_now(state)]}
	var lines := BriefingEffects.lines(state, _loader, {})
	if lines.is_empty() or bool(lines[0]["uncertain"]) or not String(lines[0]["text"]).contains("clearly against"):
		_fail("a law passed this month is not a booked line in the register's words: %s" % str(lines))
	# A passage of another month is not this month's: it books nothing now.
	ns.law_ledger[String(law.id)]["months"] = [_now(state) - 1]
	if BriefingEffects.lines(state, _loader, {}).any(func(l): return not bool(l["uncertain"]) and String(l["text"]).contains("passed")):
		_fail("a law passed last year is booked as this month's")


func _check_quiet() -> void:
	var state = _state()
	var lines := BriefingEffects.lines(state, _loader, {})
	if lines.is_empty() or String(lines[0]["text"]) != "Nothing you decided last month":
		_fail("a quiet month does not say so first: %s" % str(lines))
	for l in lines:
		if bool(l["uncertain"]) and (String(l["tone"]) == ResultTone.GOOD or String(l["tone"]) == ResultTone.BAD):
			_fail("an uncertain line wears a status tone: %s" % str(l))
	if not lines.any(func(l): return bool(l["uncertain"])):
		_fail("a quiet month shows no movement at all, uncertain or not")


## QA's RF5 TAKE on #218: a month with decisions but nothing booked said "Nothing
## you decided". Every command makes the month's recent_effects entry, so the line
## names those decisions -- uncertain, grey -- and only an empty month says nothing.
## The mutant that brings the old text back (out.append the "Nothing" dict whatever
## the entry) fails both asserts.
func _check_decided_unbooked() -> void:
	var state = _state()
	state.recent_effects.insert(0, {"label": "Tax cut; Summit: hold firm; Strike called off", "year": state.year,
		"month": state.month, "movements": [{"key": "overall_approval_pct", "label": "Approval", "unit": "pp",
		"change": 1.5, "severity": -0.3}]})
	var lines := BriefingEffects.lines(state, _loader, {})
	if lines.any(func(l): return String(l["text"]).begins_with("Nothing you decided")):
		_fail("a month with decisions says 'Nothing you decided': %s" % str(lines))
	if lines.is_empty() or not bool(lines[0]["uncertain"]) or not String(lines[0]["text"]).contains("Tax cut") \
			or not String(lines[0]["text"]).contains("1 more") or String(lines[0]["tone"]) != "":
		_fail("a decided-but-unbooked month does not name its decisions as an uncertain line: %s" % str(lines))
	# An entry of another month is not this month's decision.
	state.recent_effects[0]["month"] = int(state.month) - 1 if int(state.month) > 1 else 12
	if String(BriefingEffects.lines(state, _loader, {})[0]["text"]) != "Nothing you decided last month":
		_fail("last month's entry is read as this month's decisions")


## Pre-gate B4: a bill tabled last month divides at the boundary, so its result is
## known when the card opens -- a defeat is booked, with its count, never
## "Decided last month: X" uncertain. A division that settled nothing (refused,
## held by the second chamber, sent to the country) books no defeat.
func _check_division_known() -> void:
	var state = _state()
	var law = _loader.laws[0]
	state.recent_effects.insert(0, {"label": String(law.id), "year": state.year, "month": state.month,
		"movements": [{"key": "overall_approval_pct", "label": "Approval", "unit": "pp", "change": -1.0, "severity": 0.2}]})
	var lost := {"law_id": String(law.id), "passed": false, "yes_seats": 92, "no_seats": 485, "abstain_seats": 0}
	var lines := BriefingEffects.lines(state, _loader, {"division": lost})
	if lines.is_empty() or bool(lines[0]["uncertain"]) or String(lines[0]["tone"]) != ResultTone.BAD \
			or not String(lines[0]["text"]).contains("92") or not String(lines[0]["text"]).contains("485"):
		_fail("a bill that divided and lost is not a booked line against you with its count: %s" % str(lines))
	if lines.any(func(l): return bool(l["uncertain"]) and String(l["text"]).begins_with("Decided last month")):
		_fail("a bill whose result is known still reads 'Decided last month' uncertain: %s" % str(lines))
	for flag in ["refused", "held_by_upper", "referendum_called"]:
		var open := lost.duplicate()
		open[flag] = true
		if BriefingEffects.lines(state, _loader, {"division": open}).any(func(l): return not bool(l["uncertain"]) and String(l["text"]).contains("485")):
			_fail("a division %s is booked as a defeat" % flag)


## Pre-gate B4: a request answered last month -- delegated, declined, booked -- is a
## decision, so "Nothing you decided" does not follow it. A lapse is not one (the
## sim's, booked on its own line), nor an audience held last month that was booked
## months before (the parent's TAKE 1 on #230: the player's command was the
## booking). Through the sim's own commands, then the month turns.
func _check_answered_requests() -> void:
	for verb in ["delegate", "decline", "book", "lapse", "held"]:
		var state = _state()
		var ns = state.player()
		var pid := String(_loader.people["FRA"][3].id)
		var id := "%s|t" % pid
		var now := _now(state)
		ns.audience_requests.append({"id": id, "person_id": pid, "object": "programme:none", "stance": "sponsor",
			"arrived_month": now, "deadline_month": now + 2, "status": "pending", "date": {}, "resolved_month": -1})
		match verb:
			"delegate": Audiences.delegate(state, ns, _loader, id)
			"decline": Audiences.decline(state, ns, _loader, id)
			"book":
				var days: Array = Audiences.offered_dates(state, ns, id).filter(func(d): return bool(d.get("free", true)))
				if days.is_empty() or not bool(Audiences.book(state, ns, _loader, id, days[0]).get("ok", false)):
					_fail("book: premise, no free offered day to book")
					continue
			"lapse":
				ns.audience_requests[-1]["status"] = "lapsed"
				ns.audience_requests[-1]["resolved_month"] = now
			"held":
				# Booked now, held and settled three months on.
				var days: Array = Audiences.offered_dates(state, ns, id).filter(func(d): return bool(d.get("free", true)))
				if days.is_empty() or not bool(Audiences.book(state, ns, _loader, id, days[0]).get("ok", false)):
					_fail("held: premise, no free offered day to book")
					continue
				now += 3
				_set_month(state, now)
				Audiences.hold(state, ns, _loader, id)
				if not bool(Audiences.settle(state, ns, _loader, id, "settled").get("ok", false)):
					_fail("held: premise, the audience did not settle")
		# The briefing opens on the next month.
		_set_month(state, now + 1)
		var first := String(BriefingEffects.lines(state, _loader, {})[0]["text"])
		if verb == "book":
			# A save between the booking and the card keeps the stamp (TAKE 2; rows
			# come back with every number a float, cast on every read).
			var loaded = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
			var row: Dictionary = loaded.audience_requests.filter(func(r): return String(r["id"]) == id)[0]
			if not row.has("acted_month") or BriefingEffects._answered(loaded, now + 1) != 1:
				_fail("a booking's month did not survive a save: %s" % str(row))
		if verb == "lapse" or verb == "held":
			if first != "Nothing you decided last month":
				_fail("a %s request is read as last month's decision: %s" % [verb, first])
		elif first.begins_with("Nothing you decided") or not first.contains("1 request answered"):
			_fail("a request answered last month (%s) is not a decision on the card: %s" % [verb, first])


## The state on absolute month `abs_month` (year x 12 + month).
func _set_month(state, abs_month: int) -> void:
	state.year = floori((abs_month - 1) / 12.0)
	state.month = abs_month - state.year * 12


func _check_mixed() -> void:
	var state = _state()
	var ns = state.player()
	var now := _now(state)
	ns.commitments_judged.append({"kind": "promise", "person_id": String(_loader.people["FRA"][0].id), "object": "x",
		"made_month": now - 2, "due_month": now, "verdict": "kept", "judged_month": now})
	state.recent_effects.insert(0, {"label": "x", "year": state.year, "month": state.month,
		"movements": [{"key": "overall_approval_pct", "label": "Approval", "unit": "pp", "change": 2.0, "severity": -0.4}]})
	var lines := BriefingEffects.lines(state, _loader, {"audience_requests": {"lapsed": [{}, {}]}})
	if lines.size() != 3:
		_fail("a mixed month does not show three lines: %s" % str(lines))
		return
	if String(lines[0]["tone"]) != ResultTone.GOOD or bool(lines[0]["uncertain"]):
		_fail("a kept word is not a booked line in your favour: %s" % str(lines[0]))
	if String(lines[1]["tone"]) != ResultTone.BAD or not String(lines[1]["text"]).begins_with("2 requests"):
		_fail("two lapsed requests are not one booked line against you: %s" % str(lines[1]))
	if not bool(lines[2]["uncertain"]) or String(lines[2]["tone"]) != "":
		_fail("the measured approval rise is not uncertain and neutral: %s" % str(lines[2]))


func _fail(message: String) -> void:
	_failures.append(message)
