extends RefCounted

## The front pages' words -- V5.2 d (docs/design/v5.2-d-spec.md section 4): one
## headline per event, answer and tone, `{event_id: {answer_id: {friendly, neutral,
## hostile}}}` in data/headlines/events.json (Content's), and the political moments
## the same way in data/headlines/moments.json.
##
## Read here, in src/ui, and not by DataLoader, for glossary.gd's reason: no system
## reads a headline, the press's effect on opinion is media.gd's and the card adds
## none. French joins through Strings.row("headlines", "<id>.<answer>", tone), the
## key Interface and Content agreed (2026-10-25).
##
## **A missing headline is an empty string, never a key.** The caller drops the
## line: a front page with one paper is still a front page, a paper with an id on
## it is a bug on screen. A template that names a variable nobody filled counts as
## missing for the same reason -- "{{president}}" printed is a key by another name.

const Strings = preload("res://src/ui/strings.gd")

const PATHS := {"event": "res://data/headlines/events.json", "moment": "res://data/headlines/moments.json"}

static var _tables := {}   # kind -> {id: {answer: {tone: english}}}


## The headline `kind` (event | moment) prints for `id` answered `answer`, in
## `tone`, its `{{variables}}` filled from `vars`; "" when none is written.
static func text(kind: String, id: String, answer: String, tone: String, vars: Dictionary) -> String:
	var answers = table(kind).get(id, {})
	var tones = answers.get(answer, {}) if answers is Dictionary else {}
	var english := String(tones.get(tone, "")) if tones is Dictionary else ""
	if english.strip_edges().is_empty():
		return ""
	var words := Strings.row("headlines", "%s.%s" % [id, answer], tone, english)
	for key in vars:
		words = words.replace("{{%s}}" % key, String(vars[key]))
	return "" if words.contains("{{") else words


## The table for `kind`, read once; a file not written yet is an empty table, so
## every headline of that kind is missing rather than an error.
static func table(kind: String) -> Dictionary:
	if not _tables.has(kind):
		var path := String(PATHS.get(kind, ""))
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_tables[kind] = parsed if parsed is Dictionary else {}
	return _tables[kind]


## A test's seam: the table `kind` reads from now on, in place of the file.
static func set_table(kind: String, rows: Dictionary) -> void:
	_tables[kind] = rows
