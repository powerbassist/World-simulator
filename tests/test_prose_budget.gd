extends SceneTree

## Headless test: godot --headless --script res://tests/test_prose_budget.gd
## Non-zero exit on any failure.
##
## V5.2-0b, the text diet (the author at the V5.1 gate: "still a lot of useless
## text everywhere", "legislature tab is clunky and heavy", "some panels are really
## monolithic"). Each workspace tab has a ceiling on its SYSTEM SENTENCE words --
## Gameplay's measure in docs/design/v5.2-legibility.md, "How the text was counted",
## walked the same way so the numbers compare:
##
##   - every VISIBLE Label, RichTextLabel (its parsed text) and Button under the
##     tab's content, a hidden subtree (a folded plate, an unselected detail) skipped;
##   - a word is a whitespace token holding a letter ("318" and "51%" are not);
##   - a node is CONTENT when it holds a run of five words found in a string of
##     data/ (a law's summary, a programme blurb): that is the game's written voice,
##     budgeted per node and never cut; every other node is SYSTEM;
##   - "sys 8+" counts the words of system nodes of eight words or more -- a
##     heading, a cell or a figure label is not a sentence.
##
## Staged at day 1 and after twelve real months, because the councils and the
## dispatches grow with time. The glossary is exempt: it is where prose goes.

const WorldMonth = preload("res://src/sim/world_month.gd")

## The ceilings, sys 8+ words per tab (the note's "Budget sys 8+" column).
const BUDGET := {
	"legislature": 80, "orgs": 120, "agenda": 40, "campaign": 40, "energy": 20,
	"politics": 30, "region": 20, "commodities": 10, "projects": 20, "economy": 40,
	"overview": 30, "diplomacy": 20, "city": 0, "budget": 0, "society": 10,
	"events": 20, "people": 10, "companies": 10, "calendar": 10, "tax": 10,
	"outliner": 10,
}
## The tabs 0b has not reached yet, held at what they measured before it started
## (dc515826 + #93) so they cannot grow while they wait; each PR that trims one
## deletes its line, and the tab then answers to BUDGET.
const PENDING := {
	"agenda": 123, "budget": 14, "politics": 106, "orgs": 491, "projects": 45,
	"region": 104, "commodities": 82, "city": 17, "energy": 154, "campaign": 217,
}
## Exempt: the glossary is where explanation lives; the summit is a scene.
const EXEMPT := ["glossary", "summit"]
## No single authored text runs longer than this on a list (the blurbs are shown
## whole, but one at a time).
const CONTENT_NODE_MAX := 120
const SHINGLE := 5

var _failures: Array[String] = []
var _shingles := {}
var _measured := {}  # id -> max sys8 over the stages


func _initialize() -> void:
	_load_data_shingles("res://data")
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var windows = main._windows
	windows.size = Vector2(1920.0, 1080.0)
	await _sweep(main, "day 1")
	for i in 12:
		WorldMonth.tick_month(main._state, main._loader)
	windows.mark_all_dirty()
	await _sweep(main, "month 12")
	_report()
	quit(1 if not _failures.is_empty() else 0)


func _sweep(main, stage: String) -> void:
	var windows = main._windows
	for id in windows.panel_ids():
		if EXEMPT.has(id):
			continue
		windows.open(id, true)
		await process_frame
		await process_frame
		var frame = windows.frame(id)
		var sys8 := 0
		for node in _visible_text_nodes(frame._content):
			var text := _text_of(node)
			var words := _words(text)
			if words.is_empty():
				continue
			if _is_content(words):
				if words.size() > CONTENT_NODE_MAX:
					_fail("%s (%s): one authored text runs %d words on screen: %s" % [id, stage, words.size(), text.left(80)])
				continue
			if words.size() >= 8:
				sys8 += words.size()
		_measured[id] = maxi(int(_measured.get(id, 0)), sys8)
		var ceiling := int(PENDING.get(id, BUDGET.get(id, -1)))
		if ceiling >= 0 and sys8 > ceiling:
			_fail("%s (%s): %d system sentence words, the ceiling is %d" % [id, stage, sys8, ceiling])
	windows.close_all()


func _visible_text_nodes(node: Node) -> Array:
	var out: Array = []
	if node is CanvasItem and not (node as CanvasItem).visible:
		return out
	if node is Label or node is RichTextLabel or node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_visible_text_nodes(child))
	return out


func _text_of(node: Node) -> String:
	if node is RichTextLabel:
		return (node as RichTextLabel).get_parsed_text()
	return String(node.get("text"))


func _words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for token in text.split(" ", false):
		for part in token.split("\n", false):
			var t := part.strip_edges()
			if t != "" and _has_letter(t):
				out.append(t)
	return out


func _has_letter(t: String) -> bool:
	for c in t:
		if c.to_lower() != c.to_upper():
			return true
	return false


func _norm(word: String) -> String:
	return word.to_lower().strip_edges(true, true).trim_suffix(".").trim_suffix(",").trim_suffix(";").trim_suffix(":")


func _is_content(words: PackedStringArray) -> bool:
	for i in words.size() - SHINGLE + 1:
		if _shingles.has(_key(words, i)):
			return true
	return false


func _key(words: PackedStringArray, at: int) -> String:
	var parts := PackedStringArray()
	for j in SHINGLE:
		parts.append(_norm(words[at + j]))
	return " ".join(parts)


## Every five-word run of every English string under data/ (the i18n tree, the
## French, skipped).
func _load_data_shingles(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub != "i18n":
			_load_data_shingles(path.path_join(sub))
	for file in dir.get_files():
		if file.ends_with(".json"):
			_strings_of(JSON.parse_string(FileAccess.get_file_as_string(path.path_join(file))))


func _strings_of(value) -> void:
	if value is String:
		var words := _words(value)
		for i in words.size() - SHINGLE + 1:
			_shingles[_key(words, i)] = true
	elif value is Array:
		for v in value:
			_strings_of(v)
	elif value is Dictionary:
		for v in value.values():
			_strings_of(v)


func _report() -> void:
	var ids := _measured.keys()
	ids.sort()
	for id in ids:
		print("prose budget  %-12s sys8+ %4d  ceiling %s%s" % [id, _measured[id], str(PENDING.get(id, BUDGET.get(id, "-"))), "  (pending)" if PENDING.has(id) else ""])
	if _failures.is_empty():
		print("test_prose_budget: all checks passed")
		return
	for f in _failures:
		printerr("FAIL: %s" % f)


func _fail(message: String) -> void:
	_failures.append(message)
