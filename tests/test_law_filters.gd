extends SceneTree

## Headless test: godot --headless --script res://tests/test_law_filters.gd
## Non-zero exit on any failure.
##
## The Bills second pass, the author's pick "A : les rayons": the laws sit on SHELVES (the
## categories Content gave them) down the left, each with its count; the open shelf lists its laws
## one per row -- name, the law's verb, its summary, a small vote bar with the counts -- and a law
## the Assembly cannot take now stays on its shelf with the SIM's reason on its row (law_gate.gd).
## The sheet carries the vote in full and what the law does to each bloc as a diverging chart,
## with one verb. The order paper is always on screen with the rule printed. What can fail
## silently, pinned here:
##   - the shelves: one button per shelf with its count, budget lines and tax rates pointed to
##     Finances, a shelf narrows the list to its laws (open AND shut), a search reads every shelf;
##   - a shut law's row says why in the warning tone, never in a tooltip, and its Propose is down;
##   - the verb word comes from the data field only: absent, no word;
##   - the row's vote counts are the forecast's own;
##   - the sheet's bloc chart prints every bloc with the landed price, zero included;
##   - the verb reads "Propose for <month>"; the paper shows with nothing tabled, rule printed;
##   - the goal tiles and "What moves it" are gone from the tab;
##   - the filter survives a refresh, and the bloc filter a briefing's Go sets reads every shelf;
##   - the hemicycle is a hover on the sheet's vote bar.

const LawCategory = preload("res://src/core/law_category.gd")
const LawGate = preload("res://src/sim/law_gate.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Labels = preload("res://src/ui/labels.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const LawFilters = preload("res://src/ui/law_filters.gd")

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
			_check_the_shelves()
			_check_a_shelf_narrows()
			_check_the_search_reads_every_shelf()
			_check_an_empty_result_says_so()
			_check_a_shut_law_says_why()
			_check_the_verb_comes_from_data()
			_check_the_row_counts_are_the_forecast()
			_check_the_bloc_chart()
			_check_the_verb_and_the_paper()
			_check_the_goal_tiles_are_gone()
			_check_the_filter_survives_a_refresh()
			_check_the_hemicycle_is_a_hover()
			_check_a_shelf_press_ends_the_search()
			_check_a_law_elsewhere_opens_its_shelf()
			_check_the_verdict_word()
			_finish()
			return true
	return false


func _list():
	return _main._law_panel._laws


func _filters():
	return _list()._filters


func _ns():
	return _main._state.player()


func _refresh() -> void:
	_main._law_panel.mark_dirty()
	_main._law_panel._process(0.0)


func _shown_ids() -> Array:
	return _list()._shown.map(func(law): return String(law.id))


func _pick(shelf: String, query: String) -> void:
	_filters().set_filter(shelf, query)
	_main._law_panel._process(0.0)


## Every shelf's laws the catalogue lists: open or shut, but never another constitution's.
func _on_shelf(key: String) -> Array:
	return _main._loader.laws.filter(func(law) -> bool:
		return LawCategory.of(_main._loader, String(law.id)) == key and LawGate.shut(_ns(), law) != LawGate.CONSTITUTION
	).map(func(law): return String(law.id))


func _texts(node: Node) -> String:
	var out := ""
	for child in node.find_children("*", "Control", true, false):
		if child is Label or child is RichTextLabel or child is Button:
			out += String(child.text) + "\n"
	return out


func _row_of(law_id: String) -> Control:
	for row in _list()._rows.get_children():
		if row.has_meta("law_id") and String(row.get_meta("law_id")) == law_id:
			return row
	return null


func _check_the_shelves() -> void:
	var buttons: Array = _filters().shelf_buttons()
	if buttons.size() != LawFilters.SHELVES.size():
		_fail("%d shelf buttons for %d shelves" % [buttons.size(), LawFilters.SHELVES.size()])
	for i in mini(buttons.size(), LawFilters.SHELVES.size()):
		var key: String = LawFilters.SHELVES[i]
		var b: Button = buttons[i]
		if not String(b.text).begins_with(Labels.law_category(key)):
			_fail("shelf %d reads '%s', not %s" % [i, b.text, key])
		if not String(b.text).ends_with(str(_on_shelf(key).size())):
			_fail("shelf %s says '%s', its count is %d" % [key, b.text, _on_shelf(key).size()])
	if not _texts(_filters()).contains("Finances"):
		_fail("the shelves do not point budget lines and tax rates to Finances")
	if LawFilters.SHELVES.size() < 12:
		_fail("only %d shelves" % LawFilters.SHELVES.size())


func _check_a_shelf_narrows() -> void:
	for key in LawFilters.SHELVES:
		_pick(key, "")
		var want := _on_shelf(key)
		want.sort()
		var shown := _shown_ids()
		shown.sort()
		if shown != want:
			_fail("shelf %s lists %d laws, its shelf holds %d" % [key, shown.size(), want.size()])
		if not _filters().shelf_buttons()[LawFilters.SHELVES.find(key)].button_pressed:
			_fail("shelf %s is shown but its button is not pressed" % key)
	_pick(String(LawFilters.SHELVES[0]), "")


func _check_the_search_reads_every_shelf() -> void:
	_pick("work", "")
	var other = null
	for law in _main._loader.laws:
		var shelf := LawCategory.of(_main._loader, String(law.id))
		if shelf != "work" and LawFilters.SHELVES.has(shelf) and LawGate.shut(_ns(), law) == "":
			other = law
			break
	var word := Strings.law_name(other).split(" ")[0].to_upper()  # case ignored
	_pick("work", word)
	if not _shown_ids().has(String(other.id)):
		_fail("a search for '%s' on the Work shelf did not find %s on another shelf" % [word, other.id])
	# A word that is in a summary and in no name.
	var summary_word := ""
	for law in _main._loader.laws:
		for w in Strings.law_summary(law).split(" "):
			var lw: String = w.strip_edges().to_lower()
			if lw.length() >= 8 and lw.is_valid_identifier() and _name_hits(lw) == 0:
				summary_word = lw
				break
		if summary_word != "":
			break
	_pick("work", summary_word)
	if _shown_ids().is_empty():
		_fail("a search for '%s', a word of a summary, found nothing" % summary_word)
	_pick("work", "")


func _name_hits(word: String) -> int:
	var n := 0
	for law in _main._loader.laws:
		if Strings.law_name(law).to_lower().contains(word):
			n += 1
	return n


func _check_an_empty_result_says_so() -> void:
	_pick("work", "zzzzzz-no-such-law")
	if not _shown_ids().is_empty():
		_fail("a search for nonsense shows laws")
	if not _texts(_list()._rows).contains("No law"):
		_fail("an empty result is silent: the list says nothing")
	_pick("work", "")


func _check_a_shut_law_says_why() -> void:
	var law = null
	for l in _main._loader.laws:
		if LawCategory.of(_main._loader, String(l.id)) == "work" and LawGate.shut(_ns(), l) == "":
			law = l
			break
	_ns().law_cooldown_months[law.id] = 9
	_pick("work", "")
	if not _shown_ids().has(String(law.id)):
		_fail("a law in its cooldown left its shelf")
	var row := _row_of(String(law.id))
	var why: Label = null
	for label in row.find_children("*", "Label", true, false) if row != null else []:
		if String(label.theme_type_variation) == UiTheme.WARN_TEXT:
			why = label
	if why == null or not why.text.contains("9"):
		_fail("the shut row does not say why in the warning tone (%s)" % (why.text if why != null else "no line"))
	_list().select(String(law.id))
	var propose: Button = _list()._detail.find_child("Propose", true, false)
	if propose == null or not propose.disabled or propose.tooltip_text == "":
		_fail("a shut law's Propose is not down with its reason")
	_ns().law_cooldown_months.erase(law.id)
	_pick("work", "")


func _check_the_verb_comes_from_data() -> void:
	_pick("work", "")
	var law = _list()._shown[0]
	var name_and_verb := func() -> String: return _texts(_row_of(String(law.id))).to_lower()
	var before: String = name_and_verb.call()
	_main._loader.law_verb[String(law.id)] = "raises"
	_refresh()
	if not name_and_verb.call().contains("raises"):
		_fail("a law with a verb does not show it on its row")
	_main._loader.law_verb.erase(String(law.id))
	_refresh()
	if name_and_verb.call() != before or before.contains("raises"):
		_fail("a law without a verb shows a word all the same")
	# The authored field's shape: one lowercase word, or an error at load.
	var LawVerb = preload("res://src/core/law_verb.gd")
	for case in [["raises", true], ["Raises", false], ["two words", false], [3, false], ["", false]]:
		var errors: Array[String] = []
		var got: String = LawVerb.parse({"verb": case[0]}, "x", "f.json", errors)
		if (got != "" and errors.is_empty()) != bool(case[1]):
			_fail("verb %s parsed to '%s' with %d errors" % [case[0], got, errors.size()])
	var none: Array[String] = []
	if LawVerb.parse({}, "x", "f.json", none) != "" or not none.is_empty():
		_fail("a law without a verb is an error")


func _check_the_row_counts_are_the_forecast() -> void:
	_pick("work", "")
	var panel = _main._law_panel
	for law in _list()._shown:
		if LawGate.shut(_ns(), law) != "":
			continue
		var c: Dictionary = panel.forecast_counts(_ns(), _main._loader.parties[_ns().id], law, panel.forecast_band(_ns(), law.id))
		var want := "%d for · %d against" % [c["yes"], c["no"]]
		if not _texts(_row_of(String(law.id))).contains(want):
			_fail("%s: the row does not read '%s'" % [law.id, want])
		return


func _check_the_bloc_chart() -> void:
	_pick("work", "")
	var law = null
	for l in _list()._shown:
		if not (l.effects.get("bloc_offset", {}) as Dictionary).is_empty() and LawGate.shut(_ns(), l) == "":
			law = l
	_list().select(String(law.id))
	var chart: Control = _list()._detail.find_child("BlocChart", true, false)
	if chart == null:
		_fail("the sheet has no bloc chart")
		return
	var text := _texts(chart)
	var price: Dictionary = law.effects["bloc_offset"]
	for bloc in OpinionK.BLOC_KEYS:
		if not text.contains(Labels.bloc(bloc)):
			_fail("the bloc chart leaves out %s" % bloc)
		var landed := clampf(float(price.get(bloc, 0.0)), LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX)
		var shown := "0" if landed == 0.0 else preload("res://src/ui/num.gd").fs(landed, 2)
		if not text.contains(shown):
			_fail("the bloc chart does not print %s for %s" % [shown, bloc])


func _check_the_verb_and_the_paper() -> void:
	_pick("work", "")
	var open = null
	for l in _list()._shown:
		if LawGate.shut(_ns(), l) == "":
			open = l
			break
	_list().select(String(open.id))
	var propose: Button = _list()._detail.find_child("Propose", true, false)
	var month := DateText.month_long(int(_main._state.month))
	if propose == null or propose.text != "Propose for %s" % month:
		_fail("the verb reads '%s', not 'Propose for %s'" % [propose.text if propose != null else "", month])
	var paper = _main._law_panel._paper
	if not paper.is_visible_in_tree():
		_fail("the order paper is hidden with nothing tabled")
	if not _texts(paper).contains("One law goes to the Assembly each month."):
		_fail("the order paper does not print its rule")


func _check_the_goal_tiles_are_gone() -> void:
	for node in _main._law_panel.find_children("*", "Control", true, false):
		var script = node.get_script()
		if script != null and String(script.resource_path).contains("goal_"):
			_fail("the Bills tab still builds %s" % script.resource_path)
			return
	if _texts(_main._law_panel).contains("What moves it"):
		_fail("the Bills tab still says 'What moves it'")


func _check_the_filter_survives_a_refresh() -> void:
	_pick("work", "")
	var before := _shown_ids()
	_refresh()
	if _shown_ids() != before:
		_fail("a refresh dropped the shelf (%d laws, then %d)" % [before.size(), _shown_ids().size()])
	if not before.has(_list().selected_id()):
		_fail("the selection is '%s', not a law of the shelf" % _list().selected_id())
	# The bloc filter a Go sets reads every shelf: the laws a bloc likes stand on many.
	_list().bloc_filter = "workers"
	_refresh()
	var liked: Array = _shown_ids()
	if liked.is_empty() or liked.all(func(id): return LawCategory.of(_main._loader, id) == "work"):
		_fail("the bloc filter kept to the open shelf: %s" % [liked])
	_list().bloc_filter = ""
	_pick("work", "")


func _check_the_hemicycle_is_a_hover() -> void:
	_pick("work", "")
	var bar = null
	for child in _list()._detail.find_children("*", "Control", true, false):
		if child.get_script() != null and "hover" in child:
			bar = child
	if bar == null or not bar.hover.is_valid():
		_fail("the sheet's vote bar carries no hover")
		return
	var tip: Control = bar.hover.call()
	var text := _texts(tip)
	for party in _main._loader.parties[_ns().id]:
		if not text.contains(String(party.party_name)):
			_fail("the hovered chamber does not name %s" % party.party_name)
	tip.free()


## Pressing a shelf ends a search: the list is that shelf's, not the search's.
func _check_a_shelf_press_ends_the_search() -> void:
	_pick("work", "act")
	_filters().shelf_buttons()[LawFilters.SHELVES.find("housing")].pressed.emit()
	_main._law_panel._process(0.0)
	var want := _on_shelf("housing")
	want.sort()
	var shown := _shown_ids()
	shown.sort()
	if _filters().query != "" or shown != want:
		_fail("a shelf pressed during a search did not show the shelf (query '%s', %d laws of %d)" % [_filters().query, shown.size(), want.size()])
	_pick("work", "")


## A law selected from elsewhere (a Go, the order paper) opens its own shelf, selected.
func _check_a_law_elsewhere_opens_its_shelf() -> void:
	_pick("work", "")
	var law = null
	for l in _main._loader.laws:
		if LawCategory.of(_main._loader, String(l.id)) == "housing" and LawGate.shut(_ns(), l) == "":
			law = l
			break
	_list().select(String(law.id))
	if _filters().category != "housing" or _list().selected_id() != String(law.id):
		_fail("selecting %s from the Work shelf left the shelf at '%s', selection '%s'" % [law.id, _filters().category, _list().selected_id()])
	if not _texts(_list()._detail).contains(Strings.law_name(law)):
		_fail("the sheet does not show the law selected from another shelf")
	_pick("work", "")


## The sheet's verdict word reads the counts at their edges: carried only when the undecided cannot
## turn it, lost only when they cannot save it.
func _check_the_verdict_word() -> void:
	var LawSheet = preload("res://src/ui/law_sheet.gd")
	for case in [
		[{"yes": 300, "no": 200, "undecided": 77}, 289, true, "passes"],
		[{"yes": 250, "no": 200, "undecided": 127}, 289, true, "too close to call"],
		[{"yes": 200, "no": 300, "undecided": 77}, 289, true, "fails"],
		[{"yes": 385, "no": 100, "undecided": 92}, 385, false, "passes"],
		[{"yes": 384, "no": 100, "undecided": 93}, 385, false, "too close to call"],
		[{"yes": 300, "no": 200, "undecided": 77}, 385, false, "fails"],
	]:
		var got: String = LawSheet.verdict_of(case[0], int(case[1]), bool(case[2]))[0]
		if got != String(case[3]):
			_fail("the verdict of %s at %d reads '%s', not '%s'" % [case[0], case[1], got, case[3]])


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
