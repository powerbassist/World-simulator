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
const UiTheme = preload("res://src/ui/ui_theme.gd")

## surface -> [the file that shows it, the call that tones it]. A surface that
## reaches the player through another one is named with it: a summit's outcome is
## queued as an effect, so the consequence card (effects_ledger) is its result. A
## verdict module's own helper (LawVerdict.tint, ElectionVerdict.show_title) is
## ResultTone underneath, pinned by the reads below.
const REGISTER := {
	"law verdict and referendum": ["res://src/ui/law_panel.gd", "LawVerdict.tint("],
	"vote result card": "res://src/ui/proposal_note.gd",
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
	"company action refused": "res://src/ui/companies_panel.gd",
	"organisation act refused": "res://src/ui/orgs_panel.gd",
	"campaign programme outcome": "res://src/ui/campaign_programme.gd",
	"campaign stopped for money": "res://src/ui/campaign_chest.gd",
	"booked day kept or not": "res://src/ui/world_news.gd",
	"diplomatic act": ["res://src/ui/main.gd", "NationPanel.say_result("],
	"diplomatic act, the card": "res://src/ui/nation_panel.gd",
	"energy act refused (the panel's and the map's order)": "res://src/ui/energy_panel.gd",
	"public works refused": "res://src/ui/projects_panel.gd",
	"campaign effort or promise refused": ["res://src/ui/campaign_panel.gd", "CampaignChest."],
	"booked day's act": ["res://src/ui/diary_driver.gd", "on_outcome.call("],
}

## A sim command a UI file runs (`Energy.execute(`): the file must be registered
## above, so a new verb cannot reach the player with no tone at all.
const EXECUTE := r"\b[A-Z][A-Za-z]*\.execute\("
## A refusal dropped on the floor: the command's `applied` read false, and the
## very next line returns (#222, the parent's call: energy, projects and the
## sector programmes all did this).
const SILENT := r'^\s*if not (bool\()?result\.get\("applied", false\)\)?:\s*$'

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

	_check_every_command_registered()

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
	if not status.has_theme_color_override("font_color"):
		_fail("a BLOCKED status took no colour")
	ResultTone.say(status, "Booked.")
	if status.has_theme_color_override("font_color"):
		_fail("a neutral status after a refusal kept the refusal's colour")
	status.free()
	_check_tint_keeps_size()

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


## Every src/ui file that runs a sim command is a registered result surface, and
## none of them drops a refusal with a bare `return`.
func _check_every_command_registered() -> void:
	var registered := {}
	for surface in REGISTER:
		registered[REGISTER[surface][0] if REGISTER[surface] is Array else REGISTER[surface]] = true
	var execute := RegEx.create_from_string(EXECUTE)
	var silent := RegEx.create_from_string(SILENT)
	for file in DirAccess.get_files_at("res://src/ui"):
		if not file.ends_with(".gd"):
			continue
		var path := "res://src/ui/" + file
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#") or line.begins_with("##"):
				continue
			if execute.search(line) != null and not registered.has(path):
				_fail("%s:%d runs a sim command but is no registered result surface" % [file, i + 1])
			if silent.search(lines[i]) != null and i + 1 < lines.size() and lines[i + 1].strip_edges() == "return":
				_fail("%s:%d drops a refused command with a bare return" % [file, i + 1])


## #222 QA T1: tint() colours a verdict and leaves its size alone -- a heading
## that says DEFEATED stays a heading, a body line stays body size.
func _check_tint_keeps_size() -> void:
	var host := Control.new()
	host.theme = UiTheme.build()
	root.add_child(host)
	for variation in ["", UiTheme.HEADING, UiTheme.LEAD]:
		var label := Label.new()
		label.theme_type_variation = variation
		host.add_child(label)
		var size_before := label.get_theme_font_size("font_size")
		for tone in [ResultTone.GOOD, ResultTone.BAD, ResultTone.BLOCKED, ResultTone.RISKY]:
			ResultTone.tint(label, tone)
			if label.get_theme_font_size("font_size") != size_before:
				_fail("tint(%s) resized a '%s' line: %d -> %d" % [tone, variation, size_before, label.get_theme_font_size("font_size")])
			if label.get_theme_color("font_color") != ResultTone.TINT[tone]:
				_fail("tint(%s) did not colour a '%s' line" % [tone, variation])
	host.free()


func _expect(what: String, got: String, want: String) -> void:
	if got != want:
		_fail("%s reads '%s', expected '%s'" % [what, got, want])


func _fail(message: String) -> void:
	_failures.append(message)
