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

var _failures: Array[String] = []
var _loader


func _initialize() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_check_law_booked()
	_check_quiet()
	_check_mixed()
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
