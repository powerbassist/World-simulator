extends SceneTree

## Headless test: godot --headless --script res://tests/test_sector_columns.gd
## Non-zero exit on any failure.
##
## W2, the page in columns (Design's pick, the author's, gate-2k.md note 5): a sector's tab lays three columns -- the
## lead over the majors, what it makes, the firm's sheet -- from the page's OWN width, and keeps its two under it.
## Pinned here: the switch at text 100 and 90; the picture's widths at the 2K page; a long goods table taking width from
## the lead's column down to four majors in a row, and past that two columns; nothing wider than its column in either
## arrangement; a chip and a held programme slider moving nothing; the page's cap, in the dock too; the pseudo-locale.

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
	if scale == 1.0:
		# The picture: 788 | 628 | 440.
		var widths := [_scroll(_panel._body).size.x, _scroll(_panel._middle).size.x, _scroll(_panel._sheet).size.x]
		if absf(widths[0] - 788.0) > 0.5 or absf(widths[1] - 628.0) > 0.5 or absf(widths[2] - 440.0) > 0.5:
			_fail("at 2K the columns are %s, the picture's are 788, 628 and 440" % [widths])
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
	if absf(b.position.x - a.end.x - UiTheme.GAP_PANE) > 0.5 or absf(c.position.x - b.end.x - UiTheme.GAP_PANE) > 0.5 \
			or absf(a.position.y - b.position.y) > 0.5 or absf(c.end.x - _panel.get_global_rect().end.x) > 0.5:
		_fail("%s: the columns stand %s %s %s in %s" % [state, a, b, c, _panel.get_global_rect()])
	_check_fits(state)


## Nothing is wider than the column it stands in.
func _check_fits(state: String) -> void:
	for box in [_panel._body, _panel._middle, _panel._sheet]:
		var scroll := _scroll(box)
		if scroll.visible and (box as Control).get_combined_minimum_size().x > scroll.size.x + 0.5:
			_fail("%s: a column holds %.0f of content in %.0f" % [state, box.get_combined_minimum_size().x, scroll.size.x])


## A goods table longer than the sheet takes width from the lead's column, down to four majors in a row; past that
## the 2K page keeps two columns and a wider one takes three.
func _check_the_long_table() -> void:
	await _at(PAGE_2K)
	_panel._goods.custom_minimum_size.x = 700.0
	await _frames()
	_check_three("a 700 px goods table at 2K")
	var left: float = _scroll(_panel._body).size.x
	if absf(left - (PAGE_2K - 700.0 - 440.0 - 2.0 * UiTheme.GAP_PANE)) > 0.5 or _scroll(_panel._middle).size.x < 699.5:
		_fail("a 700 px goods table leaves the lead %.0f and the goods %.0f" % [left, _scroll(_panel._middle).size.x])
	var majors := _major_cells()
	if majors.size() < 4 or absf(majors[0].global_position.y - majors[3].global_position.y) > 0.5:
		_fail("premise or defect: the four majors do not stand in one row at %.0f" % left)
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
