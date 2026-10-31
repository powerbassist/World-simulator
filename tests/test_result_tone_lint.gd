extends SceneTree

## V5.3-0 (c), band RF7 (docs/design/v5.3-0-readability.md 4.1): every surface
## that shows the player a result says how it landed through ResultTone -- a word
## in a status tone, never colour alone and never parsed out of the sentence.
##
##   - the REGISTER below names each result surface and the file that draws it;
##     the lint fails a registered file that no longer calls ResultTone;
##   - the tones themselves are read off the sim's result keys: a passed bill is
##     GOOD, a failed one BAD, a bill a chamber holds RISKY, a moot release
##     neutral; a neutral tag is hidden and an inbox card gets no tag for it.

const ResultTone = preload("res://src/ui/result_tone.gd")
const LawVerdict = preload("res://src/ui/law_verdict.gd")

## surface -> [the file that shows it, the call that tones it]. A surface that
## reaches the player through another one is named with it: a summit's outcome is
## queued as an effect, so the consequence card (effects_ledger) is its result. A
## verdict module's own helper (LawVerdict.tint, ElectionVerdict.show_title) is
## ResultTone underneath, pinned by the reads below.
const REGISTER := {
	"law verdict and referendum": ["res://src/ui/law_panel.gd", "LawVerdict.tint("],
	"election verdict": ["res://src/ui/election_panel.gd", "ElectionVerdict.show_title("],
	"consequence card, summit outcome": "res://src/ui/effects_ledger.gd",
	"decided for you": "res://src/ui/desk_cards.gd",
	"held month cards": "res://src/ui/briefing_driver.gd",
	"commitment judged": "res://src/ui/promise_list.gd",
	"request lapsed": "res://src/ui/audience_driver.gd",
	"programme conclusions": "res://src/ui/agenda_panel.gd",
	"diary booking refused": "res://src/ui/calendar_panel.gd",
	"briefing lines": "res://src/ui/chief_briefing.gd",
	"audience": "res://src/ui/audience_talks.gd",
	"phone": "res://src/ui/phone_driver.gd",
}

var _failures: Array[String] = []


func _init() -> void:
	for surface in REGISTER:
		var entry = REGISTER[surface]
		var path: String = entry[0] if entry is Array else entry
		var needle: String = entry[1] if entry is Array else "ResultTone."
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			_fail("%s: %s does not exist" % [surface, path])
		elif not text.contains(needle):
			_fail("%s: %s shows a result with no ResultTone call" % [surface, path])

	var passed := {"law_id": "x", "passed": true}
	var failed := {"law_id": "x", "passed": false}
	_expect("a passed bill", LawVerdict.tone(passed, null), ResultTone.GOOD)
	_expect("a failed bill", LawVerdict.tone(failed, null), ResultTone.BAD)
	_expect("a bill the upper chamber holds", LawVerdict.tone({"law_id": "x", "passed": true, "held_by_upper": true}, null), ResultTone.RISKY)
	_expect("a bill a court struck", LawVerdict.tone({"law_id": "x", "passed": true, "struck_down": true}, null), ResultTone.BAD)
	_expect("a moot release", LawVerdict.tone({"law_id": "x", "passed": true, "target_already_gone": true}, null), "")
	_expect("a lapsed release", LawVerdict.tone({"law_id": "x", "passed": true, "released": true, "lapsed": true}, null), ResultTone.BAD)
	_expect("a referendum still in flight", LawVerdict.tone({"law_id": "x", "passed": true, "referendum_called": true}, null), ResultTone.RISKY)

	# A reused status line: refused, then booked, is never left in the refusal's tone.
	var status := Label.new()
	status.theme_type_variation = "Caption"
	ResultTone.say(status, "Refused.", ResultTone.BLOCKED)
	if status.theme_type_variation == "Caption":
		_fail("a BLOCKED status kept its plain variation")
	ResultTone.say(status, "Booked.")
	if status.theme_type_variation != "Caption":
		_fail("a neutral status after a refusal kept '%s'" % status.theme_type_variation)
	status.free()

	var neutral := ResultTone.tag("")
	if neutral.visible or neutral.text != "":
		_fail("a neutral tag is shown ('%s')" % neutral.text)
	var good := ResultTone.tag(ResultTone.GOOD)
	if not good.visible or good.text == "":
		_fail("a GOOD tag is hidden or wordless")
	neutral.free()
	good.free()

	if _failures.is_empty():
		print("test_result_tone_lint: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _expect(what: String, got: String, want: String) -> void:
	if got != want:
		_fail("%s reads '%s', expected '%s'" % [what, got, want])


func _fail(message: String) -> void:
	_failures.append(message)
