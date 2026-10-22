extends SceneTree

## Headless test: godot --headless --script res://tests/test_glossary.gd
## Non-zero exit on any failure.
##
## V5.1-c, the glossary table the tooltips read (docs/design/glossary-tooltips.md,
## "The data model" and P4). What a tooltip on screen cannot show:
##
##   - the merged table loads with no problem, and the loader refuses each kind of
##     bad row ONCE: an unknown see_also id, an unknown live name, a missing model,
##     a model list with one malformed anchor -- the spec's "unresolvable = load
##     error, loud";
##   - every live name the table uses is in the UI's closed table (rule L1: a live
##     value is a reader the UI already calls, never a NationState field), and the
##     dissolution entry names the months LEFT, not the config field;
##   - P4: every model anchor, a string or a list of them, names a docs/*.md that
##     holds that heading -- so a renamed section turns this red instead of leaving
##     a definition citing nothing;
##   - the shown text goes through Strings, so the English is what the row holds.

const Glossary = preload("res://src/ui/glossary.gd")
const GlossaryLive = preload("res://src/ui/glossary_live.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_the_merged_table_is_clean()
	_check_each_refusal_fires_once()
	_check_live_names_are_closed()
	_check_model_anchors_cite_real_headings()
	_check_text_reads_through_strings()
	_finish()


func _check_the_merged_table_is_clean() -> void:
	var ids: PackedStringArray = Glossary.ids()
	if ids.size() != 48:
		_fail("the glossary holds %d entries; the merged table has 48" % ids.size())
	var problems: PackedStringArray = Glossary.problems(Glossary.rows(), GlossaryLive.NAMES)
	if not problems.is_empty():
		_fail("the merged table has problems: %s" % [problems])


func _check_each_refusal_fires_once() -> void:
	var good := {"id": "a", "term": "a", "definition": "d", "model": "opinion-model#Approval"}
	var cases := {
		"unknown see_also": {"see_also": ["no_such_entry"]},
		"unknown live": {"live": "no_such_reader"},
		"missing model": {"model": null},
		"bad anchor in a list": {"model": ["opinion-model#Approval", "no anchor here"]},
	}
	for label in cases:
		var row: Dictionary = good.duplicate()
		for key in cases[label]:
			if cases[label][key] == null:
				row.erase(key)
			else:
				row[key] = cases[label][key]
		var problems: PackedStringArray = Glossary.problems([row], GlossaryLive.NAMES)
		if problems.size() != 1:
			_fail("%s: expected exactly one problem, got %s" % [label, problems])
	if not Glossary.problems([good], GlossaryLive.NAMES).is_empty():
		_fail("a well-formed row was refused: %s" % [Glossary.problems([good], GlossaryLive.NAMES)])


func _check_live_names_are_closed() -> void:
	for id in Glossary.ids():
		var live: String = Glossary.live_name(id)
		if not live.is_empty() and not GlossaryLive.NAMES.has(live):
			_fail("%s names the live value '%s', which the closed table does not hold" % [id, live])
	if Glossary.live_name("dissolution") != "dissolution_months_left":
		_fail("dissolution's live value is '%s'; the UI shows the months LEFT (dissolution_months_left)" % Glossary.live_name("dissolution"))
	if GlossaryLive.NAMES.has("dissolution_lockout_months"):
		_fail("the closed table still holds dissolution_lockout_months, the NationState config field's name")


func _check_model_anchors_cite_real_headings() -> void:
	for id in Glossary.ids():
		for anchor in Glossary.anchors(Glossary.entry(id).get("model")):
			var parts: PackedStringArray = String(anchor).split("#", true, 1)
			var path := "res://docs/%s.md" % parts[0]
			if not FileAccess.file_exists(path):
				_fail("%s cites %s, and %s does not exist" % [id, anchor, path])
				continue
			if not _headings(path).has(parts[1]):
				_fail("%s cites '%s', and %s has no such heading" % [id, parts[1], path])


func _check_text_reads_through_strings() -> void:
	var row: Dictionary = Glossary.entry("approval")
	if Glossary.term("approval") != String(row["term"]):
		_fail("term() did not return the row's English in English")
	if Glossary.definition("approval") != String(row["definition"]):
		_fail("definition() did not return the row's English in English")
	if Glossary.body("no_such_entry") != "":
		_fail("an unknown id has a body")


func _headings(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("#"):
			out.append(line.lstrip("#").strip_edges())
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_glossary: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
