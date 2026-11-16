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
##     AS ONE LINE. A person's cells sit side by side under fixed columns, never a
##     label at one edge and its value 900px away.
##   - Rework 1 (the roster, direction A): the verbs sit on the focused row
##     (tests/test_people_roster.gd); the read-only rule this file used to pin went
##     with the cards and groups it guarded.

const CK = preload("res://src/sim/cabinet_constants.gd")
const RosterRows = preload("res://src/ui/roster_rows.gd")
const President = preload("res://src/sim/president.gd")

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

	_check_chips(panel)
	_check_no_label_is_blank(panel)
	_check_names_are_resolved(panel, state)
	_check_agrees_with_politics(panel, state)
	_check_vacancy_reads_as_vacant(panel, state)
	_check_side_words(panel, state)
	_check_chief_shown(panel, state)
	# The layout check reads the busiest group the roster draws.
	panel._pick_chip("politicians")


## QA's #143 RECORDs: a party leader the data gives no party_id (Moucron, Ferrand,
## Aubertin) sits in the party they lead, not under "politician"; a person with no
## party reads their kind as a word (PersonCard.KIND_LABEL), never the raw id.
func _check_side_words(panel, state) -> void:
	var ns = state.player()
	var leaders := {}
	for p in _main._loader.parties.get(String(ns.id), []):
		leaders[String(p.leader_person_id)] = String(p.party_name)
	var checked := 0
	for person in _main._loader.people.get(String(ns.id), []):
		if String(ns.person_party_override.get(person.id, person.party_id)) != "":
			continue
		var side: String = RosterRows._side(state, _main._loader, ns, person)
		if leaders.has(String(person.id)):
			checked += 1
			if side != leaders[String(person.id)]:
				_fail("%s leads %s but sits under '%s'" % [person.person_name, leaders[String(person.id)], side])
		elif side.contains("_") or side == String(person.kind):
			_fail("%s's side is the raw kind '%s'" % [person.person_name, side])
	if checked == 0:
		_fail("premise: no party leader without a party_id")


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


## Rework 1: the groups are chips over one roster, every one of them on the page.
func _check_chips(panel) -> void:
	var text := _text_of(panel)
	for chip in RosterRows.CHIPS:
		if not text.contains(String(chip[1])):
			_fail("the roster has no '%s' chip: %s" % [chip[1], text])


## The characteristic failure of a panel whose job is resolution. An id that does
## not resolve prints "" and the row still exists, so a row-count assertion would
## pass against a screen of empty cells.
func _check_no_label_is_blank(panel) -> void:
	for node in _walk(panel._body):
		if node is Label and String(node.text).strip_edges() == "":
			_fail("the panel renders an EMPTY label -- an unresolved person id prints nothing and leaves the row looking fine")
			return


func _check_names_are_resolved(panel, state) -> void:
	var ns = state.player()
	# The head of government sits in the government's group; the head of state is the
	# president here, who is never on their own roster.
	panel._pick_chip("government")
	panel._refresh()
	var pm: String = _main._loader.person_name(ns.pm_person_id)
	if ns.pm_person_id != President.leader_id(ns) and pm != "" and not _text_of(panel).contains(pm):
		_fail("the government's group does not name the head of government '%s'" % pm)
	# And a FOREIGN leader, the group that would silently go missing if Abroad were cut.
	panel._pick_chip("abroad")
	panel._refresh()
	var abroad := ""
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		if String(id) != ns.id:
			abroad = _main._loader.person_name(President.leader_id(state.nations[id]))
			break
	if abroad != "" and not _text_of(panel).contains(abroad):
		_fail("Abroad does not name a foreign leader ('%s')" % abroad)
	panel._pick_chip("needs")
	panel._refresh()


## The one column both surfaces print. Both read ns.cabinet, so they cannot
## disagree unless one of them has started deriving the holder independently --
## which is the divergence this project's registers exist to prevent.
func _check_agrees_with_politics(panel, state) -> void:
	var ns = state.player()
	var by_id := {}
	for p in _main._loader.parties.get(ns.id, []):
		by_id[p.id] = p

	var text := _text_of(panel)

	for f in CK.PORTFOLIO_KEYS:
		var pid: String = String(ns.cabinet.get(f, ""))
		if pid == "" or not by_id.has(pid):
			continue
		var holder: String = String(by_id[pid].party_name)
		if not text.contains(holder):
			_fail("People does not name '%s', which holds %s" % [holder, f])


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

	if not text.contains("Vacant"):
		_fail("a vacated portfolio does not read as Vacant on the people panel")


## Every row with a face is one line: no gap wider than ROW_GAP_PX between two of
## its cells -- a column's own slack (the roster's widest fixed column, its wants,
## with a dash in it), never the 900px of a label at one edge and its value at the
## other -- and no line of its own per want.
const ROW_GAP_PX := 330.0


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
		if node is Label or node is Button:
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


## V5.3-0 (the parent's call on #216): the chief of staff is shown in the executive,
## right under the played office's holder, their kind as a word.
func _check_chief_shown(panel, state) -> void:
	var chief = preload("res://src/sim/staff.gd").chief_of(_main._loader, String(state.player().id))
	if chief == null:
		_fail("premise: the played nation has no chief of staff")
		return
	for row in RosterRows.rows(state, _main._loader, "government", ""):
		if String(row["id"]) == String(chief.id):
			if String(row["holds"]) != "Chief of staff":
				_fail("the chief of staff holds '%s', not 'Chief of staff'" % row["holds"])
			return
	_fail("the chief of staff is not in the government's group")
