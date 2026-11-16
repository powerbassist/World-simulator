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
const GlossaryHint = preload("res://src/ui/glossary_hint.gd")
const Events = preload("res://src/sim/events.gd")
const DeskCards = preload("res://src/ui/desk_cards.gd")
## The inbox at month 12, spec 3.5's target (170). One stated rise, 170 -> 196 (G1,
## chief-briefing-brief.md "What must hold"; the parent's ruling: cut first, state the
## rest): no briefing opens by itself to say a month, so its cards reach the inbox. Of
## the 46 words that came, the ledger's echo of a lapse (20) is cut
## (EffectsLedger.drop_default_echo); the desk's "Decided for you" (26) is the rest.
## G2 moves the month's cards to the Presidency page's part 5.
const INBOX_CEILING := 196

## The ceilings, sys 8+ words per tab (the note's "Budget sys 8+" column). Orgs is
## the note's 60 per organisation, for France's five.
const BUDGET := {
	"legislature": 80, "orgs": 300, "agenda": 40, "campaign": 40, "energy": 20,
	"majority": 30, "region": 20, "projects": 20, "economy": 40,
	# The Presidency page: 30 -> 36, a stated rise (rework 2 S1, the parent's ruling): the Overview's
	# government reads kept whole (capability, the majority's line, the censure), three 8+ word sentences.
	"overview": 36, "diplomacy": 20, "society": 10,
	"events": 20, "people": 10, "companies": 10, "calendar": 10,
	"sector_agriculture": 10, "sector_industry": 10, "sector_services": 10,
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
const TOTAL_BUDGET := {"agenda": 400, "people": 250, "legislature": 450, "finances": 181, "region": 250, "events": 95,
	"companies": 145, "sector_agriculture": 122, "sector_industry": 148, "sector_services": 135,
	"overview": 170}
const TOTAL_PENDING := {
	"calendar": 34, "campaign": 140,
	"diplomacy": 22, "economy": 128, "energy": 118,
	"orgs": 610,
	"majority": 97, "projects": 75, "society": 106,
}
## The sum of every tab's total and the inbox's, a ratchet: each rebuilding PR
## lowers it to what it measured. RF6's target is 3 600, reached at V5.3-0 (b)
## (6 648 in the spec's count, 4 911 once this test played its months as the game
## does): it can only come down from here. One stated rise, 2934 -> 2943 (V5.3 a +
## b, the parent's call): the Industry cards' "trend against the nation's", a figure
## spec 3.2 asks for, 9 words on a tab still at 22 of its 145. A second, 2943 -> 2947
## (the parent's call): the Budget's "of which regional aid" line, the development
## fund's money on a line of its own (spec 3.3 (a)), "—" at rest like its siblings
## rather than a row that comes and goes; the Budget's held total 105 -> 109. A
## third, 2947 -> 2951, the same shape (#277's "of which plant rescues"; 109 -> 113).
## The parent's standing rule since: a Budget row of that shape (one named line, four
## words, "—" at rest) rises with no call, said in its PR body. A fourth, 2951 -> 2970
## (the parent's call): the Tax Code lists every kind in force, France 5 -> 15 rows
## (#336, the tax library's data); names of the player's own levers, no new prose; the
## screen-4 build (laws B) redraws the Tax Code and brings it back down. One of the
## nineteen words is the File tab's (#333), measured on the same merge. Screen 4's second PR
## takes the hemicycle off the Bills tab (it is the forecast bar's hover now, 520 -> 443 on the tab)
## and adds the shelf and the search: 2970 -> 2946. Its third (2b), a stated rise 2946 -> 2953, the
## parent's call (OK'd on #352): the law sheet carries the briefing's price per bloc (a heading and
## the bloc names, 5 words) and "Poll it" (2), the polls themselves folded behind it, 450 on the tab.
## Finances direction A, slice 1 (the author picked "A, à l'échelle"): the Books tab is new and stands
## BESIDE the Budget (113) and the Tax Code (45) until slice 2 retires both into it: 2953 -> 3134 (+181,
## the parent's OK on #359, with the condition that slice 2 states the net for the whole of A).
## Slice 2 retires the Tax Code (45 words, its tab and its X key) into the Books rows, whose editors are closed
## at rest and add nothing counted here: 3134 -> 3089. The Budget (113) stays for its sector tiles until the
## Sectors screen takes them, so A's net is Books 181 + Budget 113 = 294 against the 339 it began from.
## Finances slice 5: the Budget tab (113) went with its sector tiles, which now answer, opened, to SECTOR_TILE_CEILING under
## the Books row: 3089 -> 2597 (the two "N parts" lines of the Books included).
## One stated rise, 2597 -> 2612 (the parent's ruling on slice 5): the Budget's revenue-against-spending chart and its Gini row
## moved to Economy as they were (113 -> 128 there), so nothing the Budget showed was lost with it.
## One stated rise, 2612 -> 2638 (G1): the inbox's, above -- nothing else moved.
## Screen 5, slice 1 (the author's C): the Commodities tab retires into three sector tabs (76, 98
## and 85 at rest: a head, the goods each sector makes, its majors), cut first (no Needs you
## section when nothing waits, the lead does not repeat the verdict tag): 2638 -> 2700, stated.
## Screen 5, slice 2: each sector tab gains its firm sheet (a firm's head and three figures, the
## State's verbs with their prices and, for aid, its price a job and in tax points), cut first (the
## sheet does not repeat the sector or name the chief): 2700 -> 2846, stated; the three tabs at
## 122 / 148 / 135, their month-12 count.
## Screen 6, slice 2: +2, the Regions rail's chip row ("Map" and its three measures,
## "12 months" being two words), stated: 2846 -> 2848.
## Rework 1 (People + cabinet, direction A): People is one roster (122 at rest, from the
## old groups and cards) and Politics, retired, comes back as Parliament's Majority tab
## without the cabinet table (123 -> 97): 2848 -> 2794.
## Rework 2, slice 1: the Overview (127) and the Outliner (23) became one Presidency page, 130 at its
## played state against a ceiling of 170 (the parent's, card G): 2794 -> 2770; then 2770 -> 2779, a stated rise
## (the parent's ruling: every government read the Overview showed stays on the page, 139 of 170).
## #401 pass 2 (section titles kept in Open now, the vote named, censure and 49.3 split): 2779 -> 2777.
const TOTAL_SUM_CEILING := 2777
const TOTAL_SUM_TARGET := 3600

## V5.3 a + b step 2, band A6 (docs/design/v5.3-ab.md section 9): an opened sector
## card on the Industry tab, its first major's verbs open and one verb focused --
## one full strip and the other verbs' name and money line -- under 90 words.
const INDUSTRY_CARD_CEILING := 90
## The same band for a spending line's tile on the Budget (spec 3.1), opened with
## its share move and strip.
const SECTOR_TILE_CEILING := 90
## An announced closure's row on In progress, its answers and its counters (the
## parent's ruling on #287): a decision this size must read at a glance.
const CLOSURE_CARD_CEILING := 100

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
	# The first-use hint is offered at boot to a profile that has not seen it: a
	# private flag file, reset, so the inbox is counted as a new player meets it
	# whatever ran before this test in the same user dir.
	GlossaryHint.config_path = "user://test_prose_budget_hint.cfg"
	GlossaryHint.reset()
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var windows = main._windows
	windows.size = Vector2(1920.0, 1080.0)
	await _sweep(main, "day 1")
	# V5.3-0 (b), spec 3.5: the months run through the game's own month hook, not a
	# bare tick_month, so the inbox, the Agenda and Dispatches stand in their played
	# state (a bare tick left Dispatches at 14 words against 187 in play). The clock
	# is not running, so the month runs whole, now (month_runner.gd). G2: the chief's
	# plate is retired (his read is the Presidency page, whose ceilings are
	# test_presidency_page.gd's), so nothing opens over the months.
	for i in 12:
		var next: int = main._state.year * 12 + main._state.month + 1
		var year := floori((next - 1) / 12.0)
		main._on_month_elapsed(year, next - year * 12)
		await process_frame
	_stage_desk(main)
	windows.mark_all_dirty()
	await _sweep(main, "month 12")
	await _sweep_inbox(main)
	await _sweep_industry_card(main)
	await _sweep_closure_card(main)
	await _sweep_sector_tile(main)
	await _sweep_warned_tile(main)
	_report()
	quit(1 if not _failures.is_empty() else 0)


## The desk at month 12, STAGED (V5.3 PR 3, the parent's ruling of 2026-11-16). The
## months run through the game's own hook, so which event cards stand open at month 12
## followed the sim's path: PR 3's rarer closures left one more card open ("The harvest
## that failed over there") and the events, inbox and crisis briefing passed their
## ceilings with no word of new text. The budget measures the surfaces, so the desk is
## cleared and this named set opened on purpose: exactly the cards main's path left
## open (student_occupation, two months left, its speaker), so the ceilings stand as
## they were and still measure an event card in the tab and in the inbox.
const STAGED_DESK := [{"event_id": "student_occupation", "months_left": 2, "speaker": "FRA_chauvire"}]


func _stage_desk(main) -> void:
	var ns = main._state.player()
	var month_index: int = main._state.year * 12 + main._state.month
	var desk: Array[Dictionary] = []
	for card in STAGED_DESK:
		var ev = Events.event_by_id(main._loader, String(card["event_id"]))
		desk.append({"event_id": ev.id, "event_name": ev.event_name, "months_left": int(card["months_left"]),
			"interrupt": bool(ev.interrupt), "severity": int(ev.severity), "category": ev.category,
			"arrived": month_index, "speaker": String(card["speaker"])})
	ns.event_queue = desk
	# The inbox and the clock keep their own record of the desk: a card left from the
	# path is dismissed and forgotten, a staged card missing is pushed, both through the
	# game's own DeskCards, so the inbox shows exactly the staged set.
	var staged := {}
	for entry in desk:
		staged[String(entry["event_id"])] = entry
	var shown := {}
	for card_id in main._event_cards.keys().duplicate():
		var event_id := String(main._event_cards[card_id])
		if staged.has(event_id):
			shown[event_id] = true
		else:
			DeskCards.dismiss(main, event_id)
			main._unseen_events.erase(event_id)
	for event_id in staged:
		if not shown.has(event_id):
			DeskCards.push(main, Events.event_by_id(main._loader, String(event_id)), staged[event_id])


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


## A6: the health line's tile on the Budget, opened with its verb and strip.
func _sweep_sector_tile(main) -> void:
	var panel = main._windows.frame("finances")._content
	main._windows.open("finances", true)
	panel._open_id = "spending_pct_gdp:health"
	panel.mark_dirty()
	await process_frame
	await process_frame
	var total := 0
	for node in _visible_text_nodes(panel._editor):
		total += _words(_text_of(node)).size()
	print("prose: opened spending row (health, editor + sectors) %d words" % total)
	if total == 0:
		_fail("opened spending row: the health row drew nothing")
	if total > SECTOR_TILE_CEILING:
		_fail("opened spending row: %d visible words, the ceiling is %d (A6)" % [total, SECTOR_TILE_CEILING])
	panel._open_id = ""
	main._windows.close_all()


## The announced closure, as it arrives: its three answers, its chips, the first chip's
## strip. Taken back off the register after, so no later count sees it.
func _sweep_closure_card(main) -> void:
	var state = main._state
	var ns = state.player()
	var major = preload("res://src/sim/companies.gd").majors_of(main._loader, ns.id)[0]
	preload("res://src/sim/closures.gd")._announce(ns, major, ns.companies[major.id], 0.2, main._loader.closure_rule, state.year * 12 + state.month)
	var panel = main._companies_panel
	main._windows.open("companies", true)
	panel.mark_dirty()
	await process_frame
	await process_frame
	var total := 0
	for node in _visible_text_nodes(panel._progress):
		var words := _words(_text_of(node))
		total += words.size()
		if _dump.has("closure_card"):
			print("dump closure_card %3d %s: %s" % [words.size(), node.get_class(), _text_of(node).left(90)])
	print("prose: closure card (announced, first chip) %d words" % total)
	if total > CLOSURE_CARD_CEILING:
		_fail("closure card: %d visible words, the ceiling is %d" % [total, CLOSURE_CARD_CEILING])
	if total == 0:
		_fail("closure card: nothing on the tab; the count proves nothing")
	(ns.companies[major.id] as Dictionary).erase("closure")
	panel.mark_dirty()
	main._windows.close_all()


## The same band with every sector of the line warned: the marks, the reason, the raise.
func _sweep_warned_tile(main) -> void:
	var ns = main._state.player()
	var had: Dictionary = (ns.sector_drift as Dictionary).duplicate(true)
	ns.sector_drift["base_gdp_per_head"] = float(ns.gdp_eur_bn) / float(ns.population) * 1.5
	var panel = main._windows.frame("finances")._content
	main._windows.open("finances", true)
	panel._open_id = "spending_pct_gdp:health"
	panel.mark_dirty()
	await process_frame
	await process_frame
	var total := 0
	for node in _visible_text_nodes(panel._editor):
		total += _words(_text_of(node)).size()
	print("prose: opened spending row (health, all warned: editor + marks + chip + verb + strip) %d words" % total)
	if total > SECTOR_TILE_CEILING:
		_fail("opened spending row, warned: %d visible words, the ceiling is %d (A6)" % [total, SECTOR_TILE_CEILING])
	ns.sector_drift = had
	panel._open_id = ""
	panel.mark_dirty()
	main._windows.close_all()


## A6: the opened card, as a player leaves it mid-decision.
func _sweep_industry_card(main) -> void:
	var state = main._state
	var ns = state.player()
	var major = preload("res://src/sim/companies.gd").majors_of(main._loader, ns.id)[0]
	var panel = main._companies_panel
	panel._open_sector = String(major.sector)
	panel._open_firm = String(major.id)
	main._windows.open("companies", true)
	panel.mark_dirty()
	await process_frame
	await process_frame
	for button in panel.find_children("*", "Button", true, false):  # i18n: ok a class name
		if button.has_meta("action_id") and not button.disabled:
			button.grab_focus()
			break
	await process_frame
	var card: Node = null
	for button in panel.find_children("*", "Button", true, false):  # i18n: ok a class name
		if String(button.get_meta("sector", "")) == String(major.sector):
			card = button.get_parent().get_parent()
	if card == null:
		_fail("industry card: the opened card is not on the tab")
		return
	var total := 0
	for node in _visible_text_nodes(card):
		var words := _words(_text_of(node))
		total += words.size()
		if _dump.has("industry_card"):
			print("dump industry_card %3d %s: %s" % [words.size(), node.get_class(), _text_of(node).left(90)])
	print("prose: industry card (opened, one verb focused) %d words" % total)
	if total > INDUSTRY_CARD_CEILING:
		_fail("industry card: %d visible words opened, the ceiling is %d (A6)" % [total, INDUSTRY_CARD_CEILING])
	main._windows.close_all()


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
