extends SceneTree

## Headless test: godot --headless --script res://tests/test_sector_columns.gd
## Non-zero exit on any failure.
##
## W2, the page in columns (Design's pick, the author's, gate-2k.md note 5): a sector's tab lays three columns -- the
## lead over the majors, what it makes, the firm's sheet -- from the page's OWN width, and keeps its two under it.
## Every column hugs its content: the leftover width stays empty at the right of the page, never inside a column.
## Pinned here: the switch at text 100 and 90; the same column widths on every wide page; a long goods table widening
## its own column only, and past the page two columns; nothing wider than its column in either arrangement; a chip and
## a held programme slider moving nothing; the page's cap, in the dock too; the pseudo-locale.

const GameState = preload("res://src/core/game_state.gd")
const SectorPanel = preload("res://src/ui/sector_panel.gd")
const Companies = preload("res://src/sim/companies.gd")
const Closures = preload("res://src/sim/closures.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const GapBars = preload("res://src/ui/gap_bars.gd")

## The page as the game gives it: 1080 with the inbox showing and away, 2K showing and away.
const PAGE_1080 := 1240.0
const PAGE_1080_AWAY := 1652.0
const PAGE_2K := 1880.0
const PAGE_2K_AWAY := 2292.0

var _failures: Array[String] = []
var _loader
var _state
var _panel


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_state = GameState.new_game(_loader, "FRA")
	_run.call_deferred()


func _run() -> void:
	_panel = SectorPanel.new("industry")
	_panel.theme = UiTheme.build()
	_panel.theme_type_variation = UiTheme.BARE  # what its page gives it (tab_page.gd)
	root.add_child(_panel)
	_panel.setup(_state, _loader)
	await _at(PAGE_1080)
	await _check_scale(1.0)
	await _check_scale(0.9)
	await _scale_to(1.0)
	await _check_the_long_table()
	await _check_the_chip()
	await _check_the_focus()
	await _check_the_held_slider()
	await _check_pseudo()
	await _check_needs_you()
	await _check_the_dock()
	for line in _failures:
		printerr("FAIL: " + line)
	print("test_sector_columns: %s" % ("OK" if _failures.is_empty() else "%d failures" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


func _frames() -> void:
	for _i in 5:
		await process_frame


## The page laid out `width` wide.
func _at(width: float) -> void:
	for _pass in 2:
		_panel.size = Vector2(width, 1100)
		await _frames()
	if absf(_panel.size.x - width) > 0.5:
		_fail("premise: the page is %.0f wide, wanted %.0f" % [_panel.size.x, width])


func _scale_to(scale: float) -> void:
	UiTheme.set_text_scale(scale)
	_panel.theme = UiTheme.build()
	_panel.setup(_state, _loader)
	await _frames()


func _check_scale(scale: float) -> void:
	await _scale_to(scale)
	var at := "text %d" % roundi(scale * 100)
	await _at(PAGE_1080)
	var need: float = _panel._need
	print("test_sector_columns: %s, the switch at %.0f px" % [at, need])
	# The picture's three columns, in px at text 100: 788, a goods column no narrower than the firm's sheet, the sheet.
	var picture := ceilf((788.0 + 440.0) * scale + 440.0 + 2.0 * UiTheme.GAP_PANE)
	if absf(need - picture) > 0.5:
		_fail("%s: the switch is %.0f, wanted %.0f" % [at, need, picture])
	if scale == 1.0:
		if not (need > PAGE_1080_AWAY and need <= PAGE_2K):
			_fail("%s: the switch is %.0f: not between the 1080 page and the 2K one" % [at, need])
		await _at(PAGE_1080_AWAY)
		_check_two("1080, the inbox away, " + at)
		await _at(PAGE_1080)
	_check_two("1080, " + at)
	await _at(need - 1.0)
	_check_two("1 px under the switch, " + at)
	await _at(need)
	_check_three("at the switch, " + at)
	await _at(PAGE_2K)
	_check_three("2K, " + at)
	var widths := _widths()
	# France's industry in January: four majors a little over 648 in a row, a short goods table, the firm's sheet at its
	# two-column width.
	if scale == 1.0 and not (widths[0] >= 647.5 and widths[0] < 700.0 and _near(widths.slice(1), [440.0, 440.0])):
		_fail("at 2K the columns are %s, wanted about 650, then 440 and 440" % [widths])
	_check_one_row("2K, " + at)
	await _at(PAGE_2K_AWAY)
	_check_three("the wider 2K page, " + at)
	if not _near(_widths(), widths):
		_fail("%s: the columns follow the page's width: %s at 1880, %s at 2292" % [at, widths, _widths()])
	await _at(PAGE_2K)
	var cap := maxf(1880.0 * scale, need + 1.0)
	if not is_equal_approx(_panel.page_cap(), cap):
		_fail("%s: the cap is %.0f, wanted %.0f" % [at, _panel.page_cap(), cap])
	# Back under, straight from the capped page: the columns' widths must not hold the page wide.
	await _at(PAGE_1080)
	_check_two("back at 1080, " + at)


func _check_two(state: String) -> void:
	var body: Control = _scroll(_panel._body)
	var sheet: Control = _scroll(_panel._sheet)
	if _panel._goods.get_parent() != _panel._body or _scroll(_panel._middle).visible:
		_fail("%s: not two columns" % state)
		return
	# Head, then the goods, then the majors, as built.
	var count: int = _panel._body.get_child_count()
	if _panel._goods.get_index() != count - 2:
		_fail("%s: the goods stand at %d of %d, not above the majors" % [state, _panel._goods.get_index(), count])
	if absf(sheet.size.x - 440.0) > 0.5 or absf(body.size.x + UiTheme.GAP_PANE + 440.0 - _panel.size.x) > 0.5:
		_fail("%s: the columns are %.0f and %.0f in %.0f" % [state, body.size.x, sheet.size.x, _panel.size.x])
	if _panel.page_cap() != INF:
		_fail("%s: two columns with a cap of %.0f" % [state, _panel.page_cap()])
	_check_fits(state)


func _check_three(state: String) -> void:
	if _panel._goods.get_parent() != _panel._middle or not _scroll(_panel._middle).visible:
		_fail("%s: not three columns" % state)
		return
	var a := _scroll(_panel._body).get_global_rect()
	var b := _scroll(_panel._middle).get_global_rect()
	var c := _scroll(_panel._sheet).get_global_rect()
	var page: Rect2 = _panel.get_global_rect()
	if absf(a.position.x - page.position.x) > 0.5 or absf(b.position.x - a.end.x - UiTheme.GAP_PANE) > 0.5 \
			or absf(c.position.x - b.end.x - UiTheme.GAP_PANE) > 0.5 or absf(a.position.y - b.position.y) > 0.5 or c.end.x > page.end.x + 0.5:
		_fail("%s: the columns stand %s %s %s in %s" % [state, a, b, c, page])
	_check_fits(state)


func _check_one_row(state: String) -> void:
	var majors := _major_cells()
	if majors.size() < 4 or absf(majors[0].global_position.y - majors[3].global_position.y) > 0.5:
		_fail("%s: premise or defect: the four majors do not stand in one row at %.0f" % [state, _widths()[0]])


## The three columns' widths, left to right.
func _widths() -> Array:
	return [_scroll(_panel._body).size.x, _scroll(_panel._middle).size.x, _scroll(_panel._sheet).size.x]


func _near(a: Array, b: Array) -> bool:
	for i in a.size():
		if absf(a[i] - b[i]) > 0.5:
			return false
	return true


## Nothing is wider than the column it stands in.
func _check_fits(state: String) -> void:
	for box in [_panel._body, _panel._middle, _panel._sheet]:
		var scroll := _scroll(box)
		if scroll.visible and (box as Control).get_combined_minimum_size().x > scroll.size.x + 0.5:
			_fail("%s: a column holds %.0f of content in %.0f" % [state, box.get_combined_minimum_size().x, scroll.size.x])


## A goods table longer than the sheet widens its own column and no other; one too long for the 2K page keeps two
## columns there, and a wider page takes three.
func _check_the_long_table() -> void:
	await _at(PAGE_2K)
	var hug: float = _widths()[0]
	_panel._goods.custom_minimum_size.x = 700.0
	await _frames()
	_check_three("a 700 px goods table at 2K")
	if not _near(_widths(), [hug, 700.0, 440.0]):
		_fail("a 700 px goods table leaves the columns %s, wanted %.0f, 700 and 440" % [_widths(), hug])
	# Majors too wide for one row: the lead stops at the picture's 788, and under it where the page has less to give.
	var cell: Control = _major_cells()[0]
	var tile := cell.custom_minimum_size.x
	cell.custom_minimum_size.x = 400.0
	await _frames()
	if not _near(_widths(), [648.0, 700.0, 440.0]):
		_fail("wide majors beside a 700 px table: the columns are %s, they wrap in 648" % [_widths()])
	await _at(PAGE_2K_AWAY)
	if not _near(_widths(), [788.0, 700.0, 440.0]):
		_fail("wide majors and a 700 px table on the wider page: the columns are %s, the lead stops at 788" % [_widths()])
	# The room shrinks under columns that fill it past the switch: the page follows, its own minimums never hold it.
	await _at(PAGE_2K)
	_check_three("back from the wider page")
	await _at(PAGE_1080)
	_check_two("from three columns with a 700 px table")
	cell.custom_minimum_size.x = tile
	await _at(PAGE_2K)
	_panel._goods.custom_minimum_size.x = 800.0
	await _frames()
	_check_two("an 800 px goods table at 2K")
	await _at(PAGE_2K_AWAY)
	_check_three("an 800 px goods table on the wider page")
	if _panel.page_cap() < _panel._need + 0.5:
		_fail("the cap %.0f is under the switch %.0f" % [_panel.page_cap(), _panel._need])
	_panel._goods.custom_minimum_size.x = 0.0
	_panel.mark_dirty()
	await _frames()


## One good's chip narrows the table; the switch stands where the whole table put it.
func _check_the_chip() -> void:
	await _at(PAGE_2K)
	_panel._goods.custom_minimum_size.x = 700.0
	await _frames()
	var need: float = _panel._need
	var chips: Array = _panel._goods.find_children("*", "Button", true, false).filter(func(b) -> bool: return b.has_meta("good") and String(b.get_meta("good")) != "")  # i18n: ok a class name
	if chips.is_empty():
		_fail("premise: no good's chip")
		return
	chips[0].pressed.emit()
	await _frames()
	if _panel._good_filter == "" or not is_equal_approx(_panel._need, need):
		_fail("a chip moved the switch from %.0f to %.0f (filter '%s')" % [need, _panel._need, _panel._good_filter])
	_check_three("one good filtered")
	_panel.setup(_state, _loader)
	await _frames()
	if _panel._need >= need:
		_fail("a load keeps the last game's goods width: %.0f" % _panel._need)


## The goods block changes parent at a switch; the keyboard stays on the chip it held.
func _check_the_focus() -> void:
	await _at(PAGE_2K)
	var chip := _panel._goods.find_children("*", "Button", true, false).filter(func(b) -> bool: return b.has_meta("good"))[0] as Button  # i18n: ok a class name
	chip.grab_focus()
	for width in [PAGE_1080, PAGE_2K]:
		await _at(width)
		var owner := root.gui_get_focus_owner()
		if owner != chip:
			_fail("the focus left the chip at the switch to %.0f: it is on %s" % [width, owner])
	chip.release_focus()


func _check_the_held_slider() -> void:
	await _at(PAGE_2K)
	_panel._dragging = true
	_panel.size = Vector2(PAGE_1080, 1100)  # held, the three columns may keep the page a little wider: no premise
	await _frames()
	if _panel._goods.get_parent() != _panel._middle:
		_fail("the columns moved under a held programme slider")
	_panel._dragging = false
	await _at(PAGE_1080)
	_check_two("the slider let go")


## What waits on the player stands in the lead's column, between the lead and the majors.
func _check_needs_you() -> void:
	var ns = _state.player()
	var major = null
	for company in Companies.majors_of(_loader, ns.id):
		if String(company.sector) == "industry":
			major = company
			break
	Closures._announce(ns, major, ns.companies[major.id], 0.2, _loader.closure_rule, _state.year * 12 + _state.month)
	_panel.mark_dirty()
	await _at(PAGE_2K)
	_check_three("a closure waiting")
	var answers: Array = _panel._body.find_children("*", "Button", true, false).filter(func(b) -> bool: return b.has_meta("go_firm"))  # i18n: ok a class name
	if answers.is_empty() or _panel._body.get_child_count() != 3:
		_fail("a closure waiting: %d answers in the lead's column, %d blocks" % [answers.size(), _panel._body.get_child_count()])
	await _at(PAGE_1080)
	_check_two("a closure waiting")


func _check_pseudo() -> void:
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 0.35)
	TranslationServer.pseudolocalization_enabled = true
	TranslationServer.reload_pseudolocalization()
	_panel.setup(_state, _loader)
	await _at(PAGE_1080)
	_check_two("pseudo-locale")
	var need: float = _panel._need
	print("test_sector_columns: pseudo, the switch at %.0f px" % need)
	await _at(need)
	_check_three("pseudo-locale, at its own switch")
	TranslationServer.pseudolocalization_enabled = false


## In the dock: the 2K page stops at its cap and the 1080 one keeps two columns.
func _check_the_dock() -> void:
	_panel.hide()
	var host := Control.new()
	host.theme = UiTheme.build()
	root.add_child(host)
	var manager := WindowManager.new()
	host.add_child(manager)
	var panel := SectorPanel.new("industry")
	manager.register("sector_industry", "Industry", panel)
	panel.setup(_state, _loader)
	for width in [2560, 1920, 2560]:
		root.size = Vector2i(width, 500)
		host.size = Vector2(width, 500)
		manager.open("sector_industry")
		panel.mark_dirty()
		for _i in 12:
			await process_frame
		var wide: bool = width == 2560
		if (panel._goods.get_parent() == panel._middle) != wide:
			_fail("in the dock at %d: three columns %s" % [width, not wide])
		elif wide:
			if absf(panel.size.x - 1880.0) > 0.5:
				_fail("in the dock at %d the page is %.0f wide, wanted 1880" % [width, panel.size.x])
			# A window too short for them: each column's bar stands in the gap at its right (T16 on #441).
			var scroll := panel._middle.get_parent() as ScrollContainer
			var gap: VScrollBar = GapBars.bar_for(manager, scroll)
			if not GapBars.scrolls(scroll) or gap == null or not gap.visible or scroll.get_v_scroll_bar().visible:
				_fail("the middle column scrolls %s, its gap bar %s" % [GapBars.scrolls(scroll), gap != null and gap.visible])
	host.queue_free()
	_panel.show()


func _major_cells() -> Array:
	var out: Array = []
	for button in _panel._body.find_children("*", "Button", true, false):  # i18n: ok a class name
		if button.has_meta("firm"):
			out.append(button.get_parent().get_parent())
	return out


func _scroll(box: Control) -> Control:
	return box.get_parent() as Control


func _fail(message: String) -> void:
	_failures.append(message)
