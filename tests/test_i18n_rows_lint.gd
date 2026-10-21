extends SceneTree

## Headless test: godot --headless --script res://tests/test_i18n_rows_lint.gd
## Non-zero exit on any failure.
##
## V5.1b3. A data row's text reaches the screen through Strings (src/ui/strings.gd:
## row, row_name, row_summary, choice_label, choice_summary, record_event_name,
## record_choice_label, record_action_name, noun, law_name, law_summary), or a translated table is "done"
## and never shown -- QA found the French law summaries and the programme rows in that
## state (#38, #39). This fails, anywhere in src/ui, a read of a row's English that is
## not an argument of one of those accessors:
##
##   .law_name  .event_name  .action_name  .proposal_name  .summary   (the loaded rows)
##   Campaign / Pledges / Projects.name_of(                          (the sim's English noun)
##   .get("name" | "summary" | "label" | "choice_label" | "event_name" | "effort_name" |
##        "pledge_name" | "project_name" | "action_name"  and indexed  (rows and records)
##   .capitalize()                                                   (an id made into a label)
##
## A read that is not a row's text to a player -- a UI dictionary's own label, a
## language's name, a proper noun the data holds, a test of emptiness -- carries
## `# i18n: row-ok <why>`. strings.gd is the accessors themselves; dev_*.gd is English
## by design. One line at a time, comments skipped.

const ROOT := "res://src/ui"
const OK_MARK := "# i18n: row-ok"
const ACCESSORS := "row|row_name|row_summary|choice_label|choice_summary|record_event_name|record_choice_label|record_action_name|noun|law_name|law_summary"
const KEYS := "name|summary|label|choice_label|event_name|effort_name|pledge_name|project_name|action_name"

var _failures: Array[String] = []
var _raw: Array[RegEx] = []
var _accessor_re: RegEx


func _init() -> void:
	for pattern in [
		r"(?<!Strings)\.(?:law_name|event_name|action_name|proposal_name)\b",
		r"\.summary\b(?!\.is_empty\(\))",
		r"\b(?:Campaign|Pledges|Projects)\.name_of\(",
		r"\.get\(\s*\"(?:" + KEYS + r")\"",
		r"\[\s*\"(?:" + KEYS + r")\"\s*\]",
		r"\.capitalize\(\)",
	]:
		_raw.append(RegEx.create_from_string(pattern))
	_accessor_re = RegEx.create_from_string(r"(?<![\w])Strings\.(?:" + ACCESSORS + r")\(")
	_self_check()
	var names := Array(DirAccess.get_files_at(ROOT))
	names.sort()
	for name in names:
		if not String(name).ends_with(".gd") or String(name).begins_with("dev_") or name == "strings.gd":
			continue
		var number := 0
		for line in FileAccess.get_file_as_string("%s/%s" % [ROOT, name]).split("\n"):
			number += 1
			for raw in _check_line(line):
				_fail("%s:%d: a row's English read raw (%s) -- route it through Strings, or mark `%s <why>`" % [
					name, number, raw, OK_MARK])
	_finish()
	quit(1 if not _failures.is_empty() else 0)


## The raw reads on one line that are not inside a Strings accessor's arguments.
func _check_line(line: String) -> Array[String]:
	var out: Array[String] = []
	if line.strip_edges().begins_with("#") or line.contains(OK_MARK):
		return out
	var code := _code(line)
	var inside := _accessor_spans(code)
	for re in _raw:
		for m in re.search_all(code):
			var at := m.get_start()
			var covered := false
			for span in inside:
				if at > span.x and at < span.y:
					covered = true
			if not covered:
				out.append(m.get_string())
	return out


## The line with its trailing comment cut (a `#` outside a string literal).
func _code(line: String) -> String:
	var quoted := false
	for i in line.length():
		if line[i] == "\"" and (i == 0 or line[i - 1] != "\\"):
			quoted = not quoted
		elif line[i] == "#" and not quoted:
			return line.substr(0, i)
	return line


## [open paren, close paren] of every accessor call on the line; an unclosed call
## runs to the end of the line (its arguments continue below).
func _accessor_spans(code: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for m in _accessor_re.search_all(code):
		var open := m.get_end() - 1
		var depth := 0
		var close := code.length()
		for i in range(open, code.length()):
			if code[i] == "(":
				depth += 1
			elif code[i] == ")":
				depth -= 1
				if depth == 0:
					close = i
					break
		out.append(Vector2i(open, close))
	return out


## The test's own shapes, pinned: a pattern that silently stopped matching would read
## as a clean tree.
func _self_check() -> void:
	var flagged := [
		"PanelKit.line(box, law.summary, PanelKit.Tone.PLAIN)",
		"button.text = action.action_name",
		"var title: String = ev.event_name",
		"PanelKit.line(block, Campaign.name_of(_loader, effort_id))",
		"PanelKit.line(block, String(terms.get(\"name\", \"\")))",
		"var heading := String(record[\"event_name\"])",
		"button.text = choice.capitalize()",
		"x = tr(law.summary)",
		"line.text = tr(\"Alliance: %s\") % pact.get(\"action_name\", \"\")",
	]
	var clean := [
		"PanelKit.line(box, Strings.law_summary(law), PanelKit.Tone.PLAIN)",
		"var label: String = Strings.law_name(law) if law != null else result[\"law_id\"]",
		"var n := Strings.row(\"programme\", id, \"name\", String(result.get(\"name\", id)))",
		"button.text = Strings.row_name(\"energy-actions\", action)",
		"if not org.summary.is_empty():",
		"var n := String(entry[\"name\"])  # i18n: row-ok a language's own name",
		"# law.summary in a comment",
		"x = Strings.noun(\"campaign-actions\", _loader.campaign_actions, \"campaign\", \"effort_id\", id, \"effort_name\", Campaign.name_of(_loader, id))",
		"x = Strings.noun(\"pledges\", _loader.pledges, \"pledge\", \"pledge_id\", id,",
	]
	for line in flagged:
		if _check_line(line).is_empty():
			_fail("self-check: `%s` should be flagged" % line)
	for line in clean:
		if not _check_line(line).is_empty():
			_fail("self-check: `%s` should be clean, was flagged %s" % [line, _check_line(line)])


func _fail(message: String) -> void:
	if _failures.size() < 400:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_i18n_rows_lint: all checks passed")
	else:
		print("%d raw row reads" % _failures.size())
		for f in _failures:
			printerr(f)
