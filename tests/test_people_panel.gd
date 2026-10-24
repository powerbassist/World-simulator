extends SceneTree

## Headless test: godot --headless --script res://tests/test_people_panel.gd
## Non-zero exit on any failure.
##
## U6b's surface. Loads the actual main scene and drives it a frame at a time --
## a Control outside the scene tree has not run _ready(), so everything it builds
## is null. See docs/engine-decision.md.
##
## Every assertion is a MUTATION check scoped to this panel's own containers. A
## "some label exists" walk from the scene root passes against the action bar and
## proves nothing, which is the failure tests/test_nation_panel.gd records.
##
## The ones that matter most are those a green suite could otherwise hide:
##
##   - NO LABEL IS EMPTY. This panel's whole job is resolving ids to names, so its
##     characteristic failure is a row that renders with a blank right-hand side.
##     That is invisible to any assertion that only checks a row exists.
##   - IT AGREES WITH THE POLITICS PANEL about who holds a portfolio. The two
##     surfaces overlap on exactly one column and both read ns.cabinet, so a
##     disagreement means one of them has started deriving it separately.
##   - V5.2 b+ (R5, gate b: "people panel is messy and unreadable"): A ROW READS
##     AS ONE LINE. A person's cells sit side by side, never a label at one edge
##     and its value 900px away, and the wants are a count on the row (their text
##     is on the hover card), not a red line per want under every name.
##   - IT HAS NO BUTTON except Close. nation_panel.gd has paid for the fold twice
##     (V1.3e, V1.3g) because a second button narrows an autowrapping label and
##     grows the row; a read-only panel cannot make that mistake, and this pins it
##     so a later session adding a verb here has to come and say why.

const CK = preload("res://src/sim/cabinet_constants.gd")

## U5a's usable band, the same bound test_calendar_panel.gd checks.
const USABLE_BAND_PX := 886.0

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		# The reference screen: headless starts on a 64px window, too small for the
		# dock to lay a row out at the width a player reads it.
		root.size = Vector2i(1920, 1080)
	if _frame < 2:
		return false  # let the scene's _ready() run
	if _frame == 2:
		_run()
		# The checks above opened Politics beside it; the layout check reads People.
		_main._windows.open("people")
		return false
	if _frame < 5:
		return false  # laid out
	_check_rows_read_as_lines(_main._people_panel)
	_finish()
	return true


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return
	if _main._people_panel == null:
		_fail("main scene did not build a people panel")
		return

	var panel = _main._people_panel
	var state = _main._state

	_check_registered_and_reachable()
	_check_fits_the_band(panel)

	_main._windows.open("people")
	panel.mark_dirty()
	panel._refresh()

	_check_all_four_groups(panel)
	_check_no_label_is_blank(panel)
	_check_names_are_resolved(panel, state)
	_check_agrees_with_politics(panel, state)
	_check_vacancy_reads_as_vacant(panel, state)
	_check_read_only(panel)


func _check_registered_and_reachable() -> void:
	if not _main._windows.is_open("people"):
		_main._windows.open("people")
	if _main._windows.frame("people") == null:
		_fail("no window frame registered under the id 'people'")

	# V5.1-c2.3: the sidebar's route, the only one -- the domain that holds the
	# tab is listed, and the tab is one of its tabs.
	var Domains = load("res://src/ui/domains.gd")
	var domain: String = Domains.domain_of("people")
	if not _main._hud.sidebar.entry_ids().has(domain) or not Domains.tabs(domain, _main._windows.panel_ids()).has("people"):
		_fail("the sidebar does not reach 'people' (domain '%s') -- the panel is unreachable without it" % domain)


func _check_fits_the_band(panel) -> void:
	if panel.custom_minimum_size.y > USABLE_BAND_PX:
		_fail("the people panel opens at %.0fpx, past U5a's %.0fpx usable band" % [
			panel.custom_minimum_size.y, USABLE_BAND_PX,
		])


func _check_all_four_groups(panel) -> void:
	var text := _text_of(panel)
	for header in ["THE EXECUTIVE", "THE CABINET", "THE PARTIES", "ABROAD"]:
		if not text.contains(header):
			_fail("the panel has no '%s' group: %s" % [header, text])


## The characteristic failure of a panel whose job is resolution. An id that does
## not resolve prints "" and the row still exists, so a row-count assertion would
## pass against a screen of empty cells.
func _check_no_label_is_blank(panel) -> void:
	for node in _walk(panel._body):
		if node is Label and String(node.text).strip_edges() == "":
			_fail("the panel renders an EMPTY label -- an unresolved person id prints nothing and leaves the row looking fine")
			return


func _check_names_are_resolved(panel, state) -> void:
	var text := _text_of(panel)
	var ns = state.player()
	var nation = _main._loader.nations.get(ns.id)

	# The player's own head of state, by name, from the register rather than from
	# anything this panel computed.
	var hos: String = _main._loader.person_name(ns.head_of_state_person_id)
	if hos == "":
		_fail("the player's head of state does not resolve to a name at all")
	elif not text.contains(hos):
		_fail("the panel does not name the head of state '%s': %s" % [hos, text])

	var pm: String = _main._loader.person_name(ns.pm_person_id)
	if pm != "" and not text.contains(pm):
		_fail("the panel does not name the head of government '%s'" % pm)

	# And a FOREIGN leader, which is the group that would silently go missing if
	# `Abroad` were ever cut for space -- the declared fallback if it folds.
	var abroad := ""
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		if String(id) != ns.id:
			abroad = _main._loader.person_name(_main._loader.nations[id].leader_person_id)
			break
	if abroad != "" and not text.contains(abroad):
		_fail("the panel does not name a foreign leader ('%s')" % abroad)

	if nation != null and not text.contains(nation.nation_name):
		_fail("the panel does not name the player's own nation")


## The one column both surfaces print. Both read ns.cabinet, so they cannot
## disagree unless one of them has started deriving the holder independently --
## which is the divergence this project's registers exist to prevent.
func _check_agrees_with_politics(panel, state) -> void:
	var ns = state.player()
	var by_id := {}
	for p in _main._loader.parties.get(ns.id, []):
		by_id[p.id] = p

	var text := _text_of(panel)
	var gov_text := ""
	_main._windows.open("politics")
	_main._government_panel.mark_dirty()
	_main._government_panel._refresh()
	for node in _walk(_main._government_panel):
		if node is Label:
			gov_text += node.text + "\n"

	for f in CK.PORTFOLIO_KEYS:
		var pid: String = String(ns.cabinet.get(f, ""))
		if pid == "" or not by_id.has(pid):
			continue
		var holder: String = String(by_id[pid].party_name)
		if not text.contains(holder):
			_fail("People does not name '%s', which holds %s" % [holder, f])
		if not gov_text.contains(holder):
			_fail("Politics does not name '%s', which holds %s -- the two surfaces disagree" % [holder, f])


## A vacancy has to read as one. U6b cut the minister bench, so this column names
## a PARTY -- and the failure mode it replaces is a blank cell that looks like a
## rendering bug rather than a department with nobody steering it.
func _check_vacancy_reads_as_vacant(panel, state) -> void:
	var ns = state.player()
	var held := ""
	for f in CK.PORTFOLIO_KEYS:
		if String(ns.cabinet.get(f, "")) != "":
			held = String(f)
			break
	if held == "":
		return  # nothing seated; the vacancy path is the only path and is covered above

	var before: String = String(ns.cabinet[held])
	ns.cabinet[held] = ""
	panel.mark_dirty()
	panel._refresh()
	var text := _text_of(panel)
	ns.cabinet[held] = before
	panel.mark_dirty()
	panel._refresh()

	if not text.contains("VACANT"):
		_fail("a vacated portfolio does not read as VACANT on the people panel")


## Read-only, and pinned. See this file's header.
func _check_read_only(panel) -> void:
	var buttons: Array[String] = []
	for node in _walk(panel):
		if node is Button:
			buttons.append(String(node.text))
	for label in buttons:
		if label != "Close":
			_fail("the people panel carries a '%s' button -- it is read-only by design, and a second button in a row with an autowrapping label is the fold nation_panel.gd has paid for twice" % label)


## Every row with a face is one line: no gap wider than ROW_GAP_PX between two of
## its cells -- a column's own slack, never the 900px of a label at one edge and
## its value at the other -- and no line of its own per want.
const ROW_GAP_PX := 240.0


func _check_rows_read_as_lines(panel) -> void:
	var rows := 0
	for node in _walk(panel._body):
		if node is Label and (String(node.text).ends_with("— denied") or String(node.text).ends_with("— served")):
			_fail("a want prints as its own line: '%s'" % node.text)
			break
	for node in _walk(panel._body):
		if not node is HBoxContainer or node.get_child_count() < 3:
			continue
		var cells: Array = []
		for child in node.get_children():
			if child is Label and child.visible:
				cells.append(child)
		if cells.size() < 2:
			continue
		rows += 1
		for i in range(1, cells.size()):
			var gap: float = _span(cells[i]).x - _span(cells[i - 1]).y
			if gap > ROW_GAP_PX:
				_fail("'%s' and '%s' sit %.0fpx apart on one row" % [cells[i - 1].text, cells[i].text, gap])
				return
	if rows < 10:
		_fail("premise: only %d person rows found" % rows)


## Where a label's TEXT runs on screen, (start, end) in x: a label stretched to fill
## its row puts its words at one edge and the box's width says nothing about them.
func _span(label: Label) -> Vector2:
	var font := label.get_theme_font("font")
	var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	var x0: float = label.global_position.x
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x0 += label.size.x - width
	elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x0 += (label.size.x - width) / 2.0
	return Vector2(x0, x0 + minf(width, label.size.x))


## Walks the whole panel rather than its scrolling body, because the title sits
## outside the scroll -- still scoped to this panel, which is the property that
## matters, since a walk from the scene root would pass against the action bar.
func _text_of(panel) -> String:
	var text := ""
	for node in _walk(panel):
		if node is Label:
			text += node.text + "\n"
	return text


func _walk(node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_people_panel: all checks passed")
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
	_main.queue_free()
	quit(0 if _failures.is_empty() else 1)
