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
##
## V5.3-0 (b), docs/design/v5.3-0-readability.md 3.5 and band RF6: the author still
## said "Trop de texte" once the sentences were cut, because what remained was words
## on labels, buttons and cells and authored text shown whole. So a second column
## counts EVERY visible word on a tab (system, content and buttons alike, the same
## walk), with 3.2's targets as ceilings for a rebuilt tab, and the sum over the tabs
## under a ratchet that only comes down, towards RF6's 3 600.

const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
## The inbox at month 12 (spec 3.5's target 170), held at its measure until the
## notes are grouped.
const INBOX_CEILING := 347

## The ceilings, sys 8+ words per tab (the note's "Budget sys 8+" column). Orgs is
## the note's 60 per organisation, for France's five.
const BUDGET := {
	"legislature": 80, "orgs": 300, "agenda": 40, "campaign": 40, "energy": 20,
	"politics": 30, "region": 20, "commodities": 10, "projects": 20, "economy": 40,
	"overview": 30, "diplomacy": 20, "city": 0, "budget": 0, "society": 10,
	"events": 20, "people": 10, "companies": 10, "calendar": 10, "tax": 10,
	"outliner": 10,
}
## The tabs 0b has not reached yet, held at what they measured before it started
## (dc515826 + #93) so they cannot grow while they wait; each PR that trims one
## deletes its line, and the tab then answers to BUDGET.
const PENDING := {}
## All visible words per tab: a rebuilt tab answers to its 3.2 target; a tab (b)
## has not reached yet is held at what it measured before (b) started, so it cannot
## grow while it waits -- each PR that rebuilds one deletes its line here.
## Re-measured once the months ran through main's month hook (Dispatches 14 -> 187,
## Campaign 223 -> 274, the outliner 2 -> 23): the same tabs, now in their played state.
const TOTAL_BUDGET := {"agenda": 400, "people": 250, "legislature": 520}
const TOTAL_PENDING := {
	"budget": 107, "calendar": 42, "campaign": 274, "city": 366, "commodities": 418,
	"companies": 287, "diplomacy": 22, "economy": 115, "energy": 118, "events": 187,
	"orgs": 610, "outliner": 23, "overview": 127,
	"politics": 123, "projects": 75, "region": 136, "society": 106, "tax": 25,
}
## The sum of every tab's total, a ratchet: each rebuilding PR lowers it to what it
## measured. RF6's target is 3 600.
const TOTAL_SUM_CEILING := 4296
const TOTAL_SUM_TARGET := 3600

## Exempt: the glossary is where explanation lives; the summit is a scene.
const EXEMPT := ["glossary", "summit", "audience"]
## No single authored text runs longer than this on a list (the blurbs are shown
## whole, but one at a time).
const CONTENT_NODE_MAX := 120
const SHINGLE := 5

var _failures: Array[String] = []
var _shingles := {}
var _measured := {}  # id -> max sys8 over the stages
var _totals := {}  # id -> max all-words over the stages
## `-- --dump=legislature,orgs` prints every counted node of those tabs: where a
## tab's words are is the question each rebuild starts from.
var _dump := PackedStringArray()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dump="):
			_dump = arg.trim_prefix("--dump=").split(",", false)
	_load_data_shingles("res://data")
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var windows = main._windows
	windows.size = Vector2(1920.0, 1080.0)
	await _sweep(main, "day 1")
	# V5.3-0 (b), spec 3.5: the months run through the game's own month hook, not a
	# bare tick_month, so the inbox, the Agenda and Dispatches stand in their played
	# state (a bare tick left Dispatches at 14 words against 187 in play). The clock
	# is not running, so the month runs whole, now (month_runner.gd). The monthly
	# briefing is staged by its own fixtures, not here.
	BriefingDriver.suppressed = true
	for i in 12:
		var next: int = main._state.year * 12 + main._state.month + 1
		var year := floori((next - 1) / 12.0)
		main._on_month_elapsed(year, next - year * 12)
		await process_frame
	windows.mark_all_dirty()
	await _sweep(main, "month 12")
	await _sweep_inbox(main)
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
		var total := 0
		for node in _visible_text_nodes(frame._content):
			var text := _text_of(node)
			var words := _words(text)
			if words.is_empty():
				continue
			total += words.size()
			if _dump.has(id):
				print("dump %s (%s) %3d %s: %s" % [id, stage, words.size(), node.get_class(), text.left(90).replace("\n", " / ")])
			if _is_content(words):
				if words.size() > CONTENT_NODE_MAX:
					_fail("%s (%s): one authored text runs %d words on screen: %s" % [id, stage, words.size(), text.left(80)])
				continue
			if words.size() >= 8:
				sys8 += words.size()
		_measured[id] = maxi(int(_measured.get(id, 0)), sys8)
		_totals[id] = maxi(int(_totals.get(id, 0)), total)
		var total_ceiling := int(TOTAL_PENDING.get(id, TOTAL_BUDGET.get(id, -1)))
		if total_ceiling >= 0 and total > total_ceiling:
			_fail("%s (%s): %d visible words, the ceiling is %d" % [id, stage, total, total_ceiling])
		var ceiling := int(PENDING.get(id, BUDGET.get(id, -1)))
		if ceiling >= 0 and sys8 > ceiling:
			_fail("%s (%s): %d system sentence words, the ceiling is %d" % [id, stage, sys8, ceiling])
	windows.close_all()


## The inbox at month 12, slid in over the workspace: it is outside every window,
## and its weight was the lapse notes (spec 3.2).
func _sweep_inbox(main) -> void:
	var inbox = main._hud.inbox
	inbox.slide_in()
	await process_frame
	await process_frame
	var total := 0
	for node in _visible_text_nodes(inbox):
		var text := _text_of(node)
		var words := _words(text)
		total += words.size()
		if _dump.has("inbox"):
			print("dump inbox (month 12) %3d %s: %s" % [words.size(), node.get_class(), text.left(90).replace("\n", " / ")])
	_totals["inbox"] = total
	if total > INBOX_CEILING:
		_fail("inbox (month 12): %d visible words, the ceiling is %d" % [total, INBOX_CEILING])
	inbox.slide_out()


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
## French, and the glossary skipped).
func _load_data_shingles(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		# The glossary's definitions are not a panel's voice: a five-word run of a
		# sentence a panel prints ("on the first day of") could match one and count
		# the sentence as content (QA on #99).
		if sub != "i18n" and sub != "glossary":
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
	var sum := 0
	for id in ids:
		sum += int(_totals.get(id, 0))
		print("prose budget  %-12s sys8+ %4d  ceiling %s%s   all words %5d  ceiling %s" % [id, _measured[id],
			str(PENDING.get(id, BUDGET.get(id, "-"))), "  (pending)" if PENDING.has(id) else "",
			int(_totals.get(id, 0)), str(TOTAL_PENDING.get(id, TOTAL_BUDGET.get(id, "-")))])
	# The inbox is in RF6's sum as it is in the spec's table (3.2).
	sum += int(_totals.get("inbox", 0))
	print("prose budget  inbox (month 12)              all words %5d  ceiling %d" % [int(_totals.get("inbox", 0)), INBOX_CEILING])
	print("prose budget  all tabs: %d visible words, ratchet %d, target %d" % [sum, TOTAL_SUM_CEILING, TOTAL_SUM_TARGET])
	if sum > TOTAL_SUM_CEILING:
		_fail("all tabs together show %d words, over the ratchet %d" % [sum, TOTAL_SUM_CEILING])
	if _failures.is_empty():
		print("test_prose_budget: all checks passed")
		return
	for f in _failures:
		printerr("FAIL: %s" % f)


func _fail(message: String) -> void:
	_failures.append(message)
