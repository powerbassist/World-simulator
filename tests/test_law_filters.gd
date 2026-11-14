extends SceneTree

## Headless test: godot --headless --script res://tests/test_law_filters.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4 (H12): the catalogue is browsed by shelf (the thirteen categories Content gave
## the laws, #330) and searched by words, above the list of laws (src/ui/law_filters.gd). What can
## fail silently, pinned here:
##   - THE SHELF NARROWS the list to the laws of that category, and a composed law (no category)
##     is only in "All shelves";
##   - THE SEARCH reads the name AND the summary, in the language shown, ignoring case;
##   - the two TOGETHER narrow to the laws that are in the shelf AND match;
##   - an empty result says so (never a list that silently shows nothing);
##   - THE FILTER SURVIVES A REFRESH (the panel redraws every month) and the selection moves to
##     the first law of the narrowed list when its own law left it;
##   - the bloc filter a briefing's Go sets (Laws Workers like) still stacks with the new ones;
##   - THE HEMICYCLE IS A HOVER, not a third of the tab: nothing on the tab draws the chamber, and the
##     forecast bar of the selected law builds it, party by party, when asked.

const LawCategory = preload("res://src/core/law_category.gd")
const Labels = preload("res://src/ui/labels.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._windows.open("legislature")
		6:
			_check_the_shelf_list()
			_check_a_shelf_narrows()
			_check_the_search_reads_name_and_summary()
			_check_both_together()
			_check_an_empty_result_says_so()
			_check_the_filter_survives_a_refresh()
			_check_the_hemicycle_is_a_hover()
			_finish()
			return true
	return false


func _list():
	return _main._law_panel._laws


func _filters():
	return _list()._filters


func _refresh() -> void:
	_main._law_panel.mark_dirty()
	_main._law_panel._process(0.0)


func _shown_ids() -> Array:
	return _list()._shown.map(func(law): return String(law.id))


func _pick(shelf: String, query: String) -> void:
	_filters().set_filter(shelf, query)
	_main._law_panel._process(0.0)


func _check_the_shelf_list() -> void:
	var box: OptionButton = _filters()._shelf
	if box.item_count != LawCategory.KEYS.size() + 1:
		_fail("the shelf list has %d entries, not All plus the %d shelves" % [box.item_count, LawCategory.KEYS.size()])
	if box.get_item_text(0).begins_with(Labels.law_category("taxes")) or box.get_item_text(0) == "":
		_fail("the first entry is not the unfiltered one: '%s'" % box.get_item_text(0))
	for i in LawCategory.KEYS.size():
		if not box.get_item_text(i + 1).begins_with(Labels.law_category(LawCategory.KEYS[i])):
			_fail("entry %d reads '%s', not the shelf %s" % [i + 1, box.get_item_text(i + 1), LawCategory.KEYS[i]])
	var everything := _shown_ids().size()
	if everything < 20:
		_fail("premise: the unfiltered catalogue shows only %d laws" % everything)


func _check_a_shelf_narrows() -> void:
	_pick("", "")
	var all := _shown_ids()
	var picked := ""
	for key in LawCategory.KEYS:
		_pick(key, "")
		var shown := _shown_ids()
		if shown.is_empty():
			continue  # a shelf the player cannot propose from today is empty, and says so below
		for id in shown:
			if LawCategory.of(_main._loader, id) != key:
				_fail("shelf %s shows %s, which is on shelf '%s'" % [key, id, LawCategory.of(_main._loader, id)])
		if shown.size() >= all.size():
			_fail("shelf %s did not narrow the list (%d of %d)" % [key, shown.size(), all.size()])
		picked = key
	if picked == "":
		_fail("no shelf had a proposable law to show")
	_pick("", "")


func _check_the_search_reads_name_and_summary() -> void:
	var law = _list()._shown[0]
	var name_word := Strings.law_name(law).split(" ")[0].to_upper()  # case ignored
	_pick("", name_word)
	if not _shown_ids().has(String(law.id)):
		_fail("a search for the first word of '%s' (%s) did not find it" % [Strings.law_name(law), name_word])
	# A word that is in a summary and in no name.
	var summary_word := ""
	for candidate in _list()._shown:
		for word in Strings.law_summary(candidate).split(" "):
			var w: String = word.strip_edges().to_lower()
			if w.length() >= 8 and not w.contains("[") and not w.contains("]") and _name_hits(w) == 0:
				summary_word = w
				break
		if summary_word != "":
			break
	_pick("", "")
	if summary_word == "":
		_fail("premise: no summary word that is in no name")
		return
	_pick("", summary_word)
	var found := _shown_ids()
	if found.is_empty():
		_fail("a search for '%s', a word of a summary, found nothing" % summary_word)
	_pick("", "")


func _name_hits(word: String) -> int:
	var n := 0
	for law in _main._loader.laws:
		if Strings.law_name(law).to_lower().contains(word):
			n += 1
	return n


func _check_both_together() -> void:
	_pick("", "")
	var law = _list()._shown[0]
	var shelf := LawCategory.of(_main._loader, String(law.id))
	if shelf == "":
		_fail("premise: the first law has no shelf")
		return
	_pick(shelf, Strings.law_name(law).split(" ")[0])
	var ids := _shown_ids()
	if not ids.has(String(law.id)):
		_fail("shelf and name together lost the law they were both taken from")
	for id in ids:
		if LawCategory.of(_main._loader, id) != shelf:
			_fail("a shelf plus a search shows %s from another shelf" % id)
	_pick("", "")


func _check_an_empty_result_says_so() -> void:
	_pick("", "zzzzzz-no-such-law")
	if not _shown_ids().is_empty():
		_fail("a search for nonsense shows laws")
	var said := false
	for child in _list()._rows.get_children():
		if child is Label or child is RichTextLabel:
			said = said or String(child.text).contains("No law")
	if not said:
		_fail("an empty result is silent: the list says nothing")
	_pick("", "")


func _check_the_filter_survives_a_refresh() -> void:
	var law = _list()._shown[3]
	var shelf := LawCategory.of(_main._loader, String(law.id))
	_pick(shelf, "")
	var before := _shown_ids()
	_refresh()
	if _shown_ids() != before:
		_fail("a refresh dropped the shelf filter (%d laws, then %d)" % [before.size(), _shown_ids().size()])
	if not before.has(_list().selected_id()):
		_fail("the selection is '%s', not a law of the narrowed list" % _list().selected_id())
	# The bloc filter a Go sets stacks with the shelf.
	_list().bloc_filter = "workers"
	_refresh()
	for id in _shown_ids():
		if LawCategory.of(_main._loader, id) != shelf:
			_fail("the bloc filter dropped the shelf: %s" % id)
	_list().bloc_filter = ""
	_pick("", "")


func _check_the_hemicycle_is_a_hover() -> void:
	_pick("", "")
	if _main._law_panel.find_child("Charts", true, false) != null:
		_fail("the tab still draws the chamber on the page (a Charts node)")
	var bar = null
	for child in _list()._detail.find_children("*", "Control", true, false):
		if child.get_script() != null and "hover" in child:
			bar = child
	if bar == null or not bar.hover.is_valid():
		_fail("the sheet's forecast bar carries no hover")
		return
	var tip: Control = bar.hover.call()
	var text := ""
	for label in tip.find_children("*", "Label", true, false):
		text += String(label.text) + "
"
	for party in _main._loader.parties[_main._state.player().id]:
		if not text.contains(String(party.party_name)):
			_fail("the hovered chamber does not name %s" % party.party_name)
	# QA on #346: the hover replaced the bar's own counts, so they ride above the chamber.
	var counts: Dictionary = bar._parts.reduce(func(acc, part): acc[String(part["label"])] = int(part["value"]); return acc, {})
	for n in counts.values():
		if not text.contains(str(n)):
			_fail("the hovered chamber does not carry the forecast count %d: %s" % [n, text.replace("
", " | ")])
	tip.free()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_law_filters.gd")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	quit(1)
