extends SceneTree

## Headless test: godot --headless --script res://tests/test_glossary_panel.gd
## Non-zero exit on any failure.
##
## V5.1-d3, the A-Z Glossary tab. Every term of data/glossary/terms.json is in it,
## once, in alphabetical order under its letter; each is a marked term (so it is
## hoverable) at its own entry, and the tab is a window in a domain of its own that
## the sidebar lists. Driven a frame at a time: a panel builds only while it is
## visible, and a Control outside the tree has not run _ready().

const Glossary = preload("res://src/ui/glossary.gd")
const GlossaryPanel = preload("res://src/ui/glossary_panel.gd")
const TermText = preload("res://src/ui/term_text.gd")
const Domains = preload("res://src/ui/domains.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _panel


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main._clock.set_process(false)
		_check_the_order()
		_check_it_is_a_tab_in_a_domain()
		_main._windows.open("glossary")
		_panel = _main._windows.frame("glossary")._content
	elif _frame == 6:
		_check_every_term_is_an_entry()
		_check_a_letter_jumps()
	elif _frame == 9:
		_check_the_jump_scrolled()
		_check_a_month_sweep_keeps_the_reader_place()
	elif _frame == 12:
		_check_the_place_was_kept()
		_finish()
		return true
	return false


## Every id once, ordered by its shown word without regard to case; the letters are
## the distinct first characters in that order.
func _check_the_order() -> void:
	var ids: Array = GlossaryPanel.entry_ids()
	if ids.size() != Glossary.ids().size():
		_fail("the tab lists %d of %d terms" % [ids.size(), Glossary.ids().size()])
	var seen := {}
	for id in ids:
		if seen.has(id):
			_fail("the tab lists '%s' twice" % id)
		seen[id] = true
	for i in range(1, ids.size()):
		if Glossary.term(ids[i - 1]).naturalnocasecmp_to(Glossary.term(ids[i])) > 0:
			_fail("'%s' is listed before '%s'" % [Glossary.term(ids[i - 1]), Glossary.term(ids[i])])
	if GlossaryPanel.entry_ids() != ids:
		_fail("two calls to entry_ids() disagree")
	var letters: Array = GlossaryPanel.letters()
	for i in range(1, letters.size()):
		if String(letters[i - 1]).naturalnocasecmp_to(String(letters[i])) >= 0:
			_fail("the letters are not ascending: %s" % [letters])
	if GlossaryPanel.letter_of("approval") != "A" or GlossaryPanel.letter_of("") != "#" or GlossaryPanel.letter_of("49.3") != "#":
		_fail("letter_of misgroups a word")


func _check_it_is_a_tab_in_a_domain() -> void:
	if not _main._windows.panel_ids().has("glossary"):
		_fail("the glossary window is not registered")
	if Domains.domain_of("glossary") != "glossary" or Domains.title("glossary") != "Glossary":
		_fail("the glossary has no domain of its own")
	if not _main._hud.sidebar.entry_ids().has("glossary"):
		_fail("the sidebar does not list the Glossary domain")


## Rendered: each term's own entry marks it, and so every term is hoverable; the
## entry is a section of its own (N1 per entry), so a term is not marked twice there.
func _check_every_term_is_an_entry() -> void:
	var body: VBoxContainer = _panel._body
	var expected: Array = GlossaryPanel.entry_ids()
	var next := 0
	for child in body.get_children():
		if child.is_queued_for_deletion() or not child is VBoxContainer:
			continue
		var first: Node = child.get_child(0)
		if not first is TermText:
			_fail("an entry does not open on a marked term")
			continue
		var marked: PackedStringArray = TermText.term_ids(first)
		if next >= expected.size() or marked.size() != 1 or marked[0] != String(expected[next]):
			_fail("entry %d marks %s, not '%s'" % [next, str(marked), expected[next] if next < expected.size() else "-"])
		next += 1
	if next != expected.size():
		_fail("the tab drew %d entries for %d terms" % [next, expected.size()])


## The bar's last letter scrolls the list down to its heading.
func _check_a_letter_jumps() -> void:
	var last: String = String(GlossaryPanel.letters().back())
	for button in _panel._bar.get_children():
		if not button.is_queued_for_deletion() and (button as Button).text == last:
			(button as Button).pressed.emit()
			return
	_fail("the letter bar has no button for '%s'" % last)


func _check_the_jump_scrolled() -> void:
	if int(_panel._scroll.scroll_vertical) <= 0:
		_fail("the last letter's button did not scroll the list")


## Review pass 1: the month's sweep marks every panel dirty, and a rebuild put the
## reader back at the top of a tab they were reading at speed 3. Nothing in the
## glossary moved, so only a change of language rebuilds it.
var _place := 0


var _first_entry: Node


func _check_a_month_sweep_keeps_the_reader_place() -> void:
	_place = int(_panel._scroll.scroll_vertical)
	_first_entry = _panel._body.get_child(1)
	_main._windows.mark_all_dirty()


func _check_the_place_was_kept() -> void:
	if int(_panel._scroll.scroll_vertical) != _place or _place <= 0:
		_fail("a month's sweep moved the reader from %d to %d" % [_place, int(_panel._scroll.scroll_vertical)])
	# Nothing in the glossary moved: the sweep must not free and rebuild its entries
	# (a plate anchored on a term would lose its anchor with them).
	if not is_instance_valid(_first_entry) or _first_entry.is_queued_for_deletion() or _first_entry.get_parent() != _panel._body:
		_fail("a month's sweep rebuilt the glossary list")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_glossary_panel: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
