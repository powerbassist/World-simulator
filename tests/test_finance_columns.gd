extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_columns.gd
## Non-zero exit on any failure.
##
## W2, the page in columns (Design's pick, the author's, gate-2k.md): Books lays Spending beside Revenue once both
## read whole, on the page's OWN width. Pinned here, at text 90 and 100: one table below the switch and two sheets
## from it; the switch falls where Design computed it (between the 1080 page and the 2K one); nothing in either
## arrangement is wider than its sheet or cut, an open row's editor included; the two sheets' bars share one length
## (the money scale, T5 on #443); in columns each sheet hugs its rows and the width left over stays empty at the right;
## the page goes back to one table; the page's cap; the long pseudo-locale fits.

const GameState = preload("res://src/core/game_state.gd")
const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceColumns = preload("res://src/ui/finance_columns.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceLever = preload("res://src/ui/finance_lever.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const GapBars = preload("res://src/ui/gap_bars.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

## The books' width as the game gives it: the 1080 page with the inbox showing (the bill's rail folded over it), and
## the 2K page with the inbox showing.
const PAGE_1080 := 1240.0
const PAGE_2K := 1880.0

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
	_panel = FinancesPanel.new()
	_panel.theme = UiTheme.build()
	root.add_child(_panel)
	_panel.setup(_state, _loader)
	await _at(PAGE_1080)
	await _check_scale(1.0)
	await _check_scale(0.9)
	UiTheme.set_text_scale(1.0)
	_panel.theme = UiTheme.build()
	await _check_the_open_editor()
	await _check_the_held_slider()
	await _check_the_dragged_bar()
	await _check_who_folded()
	await _check_pseudo()
	await _check_the_scroll_bar()
	await _check_rate_words()
	for line in _failures:
		printerr("FAIL: " + line)
	print("test_finance_columns: %s" % ("OK" if _failures.is_empty() else "%d failures" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)


## The books laid out `width` wide (a page with no window manager keeps the bill's rail in its frame, so the panel
## is that much wider). Containers sort and the table re-lays itself over a few frames. Sized again each pass, as the
## dock sizes its page every frame: sheets measured at another text size hold it for one pass, one table the next.
func _at(width: float) -> void:
	for _pass in 3:
		var rail: float = _panel.size.x - _panel._table.size.x if _panel._table.size.x > 0.0 else 0.0
		_panel.size = Vector2(width + rail, 1100)
		for _i in 4:
			await process_frame
	if absf(_panel._table.size.x - width) > 0.5:
		_fail("premise: the books are %.0f wide, wanted %.0f" % [_panel._table.size.x, width])


func _check_scale(scale: float) -> void:
	UiTheme.set_text_scale(scale)
	_panel.theme = UiTheme.build()
	await _at(PAGE_1080)
	var table: FinanceColumns = _panel._table
	var need: float = table.need()
	print("test_finance_columns: text %d, the switch at %.0f px" % [roundi(scale * 100), need])
	_check_one_table("at %.0f, text %d" % [PAGE_1080, roundi(scale * 100)])
	if scale == 1.0 and not (need > 1652.0 and need <= PAGE_2K):
		_fail("at text 100 the switch is %.0f: not between the 1080 page and the 2K one" % need)
	# Under the 100 bound's floor, so a switch that stopped following the text size fails here.
	if scale < 1.0 and not (need > PAGE_1080 and need <= 1652.0):
		_fail("at text 90 the switch is %.0f: not between the 1080 page and the text-100 floor" % need)
	# One px under, one table; at it and over, two sheets; back under, one table again.
	await _at(need - 2.0)
	_check_one_table("2 px under the switch")
	if table.cap() != INF:
		_fail("one table with a cap of %.0f" % table.cap())
	# Exactly need(), set by hand: _at() allows half a px, which is the whole of this case.
	table.size.x = need
	table._process(0.0)
	if table.size.x != need or not table.columns():
		_fail("text %d: %.2f wide against a switch of %.0f, columns %s" % [roundi(scale * 100), table.size.x, need, table.columns()])
	await _at(need)
	_check_columns("at the switch, text %d" % roundi(scale * 100))
	_check_need("at the switch, text %d" % roundi(scale * 100))
	for width in [need + 175.0 * scale, 2292.0]:
		await _at(width)
		var at := "at %.0f, text %d" % [width, roundi(scale * 100)]
		_check_columns(at)
		_check_hug(scale, at)
	if not is_equal_approx(table.cap(), maxf(1880.0 * scale, need + 1.0)):
		_fail("the cap is %.0f, wanted %.0f" % [table.cap(), maxf(1880.0 * scale, need + 1.0)])
	await _at(PAGE_1080)
	_check_one_table("back under the switch")


func _check_one_table(state: String) -> void:
	var spending: Control = _panel._spending_box
	var revenue: Control = _panel._revenue_box
	if _panel._table.columns() or absf(spending.global_position.x - revenue.global_position.x) > 0.5 \
			or revenue.global_position.y < spending.get_global_rect().end.y - 0.5:
		_fail("%s: not one table, spending %s revenue %s" % [state, spending.get_global_rect(), revenue.get_global_rect()])
		return
	for cell in _slot(spending, "who"):
		if not cell.visible:
			_fail("%s: a spending caption is hidden in one table" % state)
	if _head_text(revenue, "year") != "" or _head_text(revenue, "rate") != "":
		_fail("%s: revenue repeats the column names under spending's" % state)
	if _head_text(spending, "rate") != Strings.t("Rate").to_upper():
		_fail("%s: the rate column is headed '%s'" % [state, _head_text(spending, "rate")])
	_check_fits(state)
	_check_one_bar(state)
	_check_axis(spending, state)
	for head in _slot(revenue, "drag"):
		if head.get_children().any(func(mark) -> bool: return mark.visible):
			_fail("%s: revenue repeats the money scale under spending's" % state)


func _check_columns(state: String) -> void:
	var spending: Control = _panel._spending_box
	var revenue: Control = _panel._revenue_box
	var a := spending.get_global_rect()
	var b := revenue.get_global_rect()
	if not _panel._table.columns() or b.position.x < a.end.x + UiTheme.GAP_PANE - 0.5 or absf(a.position.y - b.position.y) > 0.5:
		_fail("%s: not two sheets side by side, spending %s revenue %s" % [state, a, b])
		return
	var page: Rect2 = _panel._table.get_global_rect()
	if b.end.x > page.end.x + 0.5:
		_fail("%s: revenue ends at %.0f, past the page's %.0f" % [state, b.end.x, page.end.x])
	# The sheets hug: each ends at its own foot (build note 6).
	if (spending.get_parent() as Control).size.y > (spending as Control).get_combined_minimum_size().y + 60.0:
		_fail("%s: spending's sheet is %.0f tall for %.0f of rows" % [state, spending.get_parent().size.y, spending.get_combined_minimum_size().y])
	for cell in _slot(spending, "who"):
		if cell.visible:
			_fail("%s: spending keeps the who-pays cell in columns: '%s'" % [state, cell.text])
			break
	var noted := _slot(spending, "pct").filter(func(c) -> bool: return c.text == Strings.t("not set here"))
	if noted.size() != 2:
		_fail("%s: 'not set here' said on %d of spending's two unset rows" % [state, noted.size()])
	for pair in [["rate", "Rate"], ["drag", "Drag"], ["year", "A year"], ["balance", "Balance"]]:
		if _head_text(revenue, pair[0]) != Strings.t(pair[1]).to_upper():
			_fail("%s: revenue's head reads '%s' for %s" % [state, _head_text(revenue, pair[0]), pair[1]])
	_check_fits(state)
	_check_one_bar(state)
	_check_axis(spending, state)
	_check_axis(revenue, state)
	# Read whole: not one who-pays caption cut, the longest included.
	for cell in _slot(revenue, "who"):
		var wants: float = cell.get_theme_font("font").get_string_size(cell.text, HORIZONTAL_ALIGNMENT_LEFT, -1, cell.get_theme_font_size("font_size")).x
		if wants > cell.size.x + 0.5:
			_fail("%s: '%s' is cut (%.0f of %.0f px)" % [state, cell.text, wants, cell.size.x])


## Nothing is wider than the sheet it sits on.
func _check_fits(state: String) -> void:
	for box in [_panel._spending_box, _panel._revenue_box]:
		var sheet: Rect2 = (box as Control).get_global_rect()
		for node in box.find_children("*", "HBoxContainer", true, false):  # i18n: ok a class name
			var row := node as Control
			if row.is_visible_in_tree() and row.get_global_rect().end.x > sheet.end.x + 0.5:
				_fail("%s: a row ends at %.0f, its sheet at %.0f" % [state, row.get_global_rect().end.x, sheet.end.x])
				return
	var sheet_end: float = (_panel._revenue_box.get_parent() as Control).get_global_rect().end.x
	if _panel._table.columns() and sheet_end > _panel._table.get_global_rect().end.x + 0.5:
		_fail("%s: revenue ends at %.0f, past the page's %.0f" % [state, sheet_end, _panel._table.get_global_rect().end.x])
	if _panel.size.x > 0.0 and _panel._table.get_global_rect().end.x > _panel.get_global_rect().end.x + 0.5:
		_fail("%s: the books end past the page" % state)


## need() is the two sheets as they stand there, the gap between them and the scroll bar's room: nothing short,
## nothing spare.
func _check_need(state: String) -> void:
	var table: FinanceColumns = _panel._table
	var spending: Control = table._wraps[0]
	var revenue: Control = table._wraps[1]
	var gap := revenue.global_position.x - spending.get_global_rect().end.x
	var sum: float = spending.size.x + UiTheme.GAP_PANE + revenue.get_combined_minimum_size().x + table._bar_room()
	if absf(gap - UiTheme.GAP_PANE) > 0.5 or absf(table.need() - sum) > 1.0:
		_fail("%s: the switch is %.1f for sheets, gap and bar room of %.1f (laid gap %.1f)" % [state, table.need(), sum, gap])


## Each sheet is as wide as its rows ask, the bars at their least, whatever the page gives: the leftover stands at the
## right of Revenue, never inside a sheet (the author on 2K).
func _check_hug(scale: float, state: String) -> void:
	var table: FinanceColumns = _panel._table
	var bar: float = (table._row_bars(_panel._revenue_box)[0] as Control).size.x
	var spending: float = (table._wraps[0] as Control).size.x
	var revenue: Control = table._wraps[1]
	var wanted := [FinanceRows.BAR_MIN * scale, table._spend + table._margins(), table._rev + table._margins()]
	if absf(bar - wanted[0]) > 0.5 or absf(spending - wanted[1]) > 0.5 or absf(revenue.size.x - wanted[2]) > 0.5:
		_fail("%s: bars %.1f, sheets %.1f and %.1f, wanted %s" % [state, bar, spending, revenue.size.x, wanted])
	if absf(table.scroll.get_global_rect().end.x - revenue.get_global_rect().end.x) > 0.5:
		_fail("%s: the scroll ends at %.0f, revenue at %.0f: its bar would stand away from the sheets" % [state, table.scroll.get_global_rect().end.x, revenue.get_global_rect().end.x])


## Every bar, in both sheets, one length: the same billions draw the same pixels.
func _check_one_bar(state: String) -> void:
	var widths := {}
	for box in [_panel._spending_box, _panel._revenue_box]:
		for bar in _panel._table._row_bars(box):  # the sheet's rows, not the open editor's tile
			widths[roundi((bar as Control).size.x)] = true
	if widths.size() != 1:
		_fail("%s: the bars are %s px long" % [state, widths.keys()])


## The DRAG head carries the table's one money scale: 0, half and the whole of it, each where every bar under it draws
## that sum, under the word and not on one another.
func _check_axis(box: Control, state: String) -> void:
	var scale: float = _panel._money_scale()
	var head: Label = _slot(box, "drag")[0]
	var marks: Array = head.get_children().filter(func(mark) -> bool: return mark.visible)
	var want := ["0", Num.f(scale * 0.5, 0), FinanceRows.bn_text(scale)]
	var said := marks.map(func(mark) -> String: return mark.text)
	if said != want:
		_fail("%s: the scale reads %s, wanted %s" % [state, said, want])
		return
	var inks := marks.map(func(m) -> float: return m.get_theme_font("font").get_string_size(m.text, HORIZONTAL_ALIGNMENT_LEFT, -1, m.get_theme_font_size("font_size")).x)
	var from: float = marks[0].global_position.x
	var middle: float = marks[1].get_global_rect().get_center().x
	var to: float = marks[2].get_global_rect().end.x
	var bars: Array = _panel._table._row_bars(box).filter(func(bar) -> bool: return bar._per_unit > 0.0)
	if bars.is_empty():
		_fail("premise: %s: no bar with money to read the scale against" % state)
	for bar in bars:
		var drawn := [0.0, 0.5, 1.0].map(func(part) -> float: return bar.global_position.x + bar.x_of(scale * part / bar._per_unit))
		if absf(from - drawn[0]) > 1.0 or absf(middle - drawn[1]) > 1.0 or absf(to - drawn[2]) > 1.0:
			_fail("%s: the scale stands at %.1f %.1f %.1f, a bar draws it at %s" % [state, from, middle, to, drawn])
			break
	if from + inks[0] + 4.0 > middle - inks[1] * 0.5 or middle + inks[1] * 0.5 + 4.0 > to - inks[2]:
		_fail("%s: the scale's figures meet (%s px wide on %.0f)" % [state, inks, to - from])
	for mark in marks:
		if mark.global_position.y < head.global_position.y + head.get_line_height(0) - 0.5 or mark.get_global_rect().end.y > head.get_global_rect().end.y + 0.5:
			_fail("%s: '%s' is on the column's name or out of its head: %s in %s" % [state, mark.text, mark.get_global_rect(), head.get_global_rect()])


## An open row's editor lives in its sheet: it must not widen the column it opens in.
func _check_the_open_editor() -> void:
	await _at(PAGE_2K)
	if not _panel._table.columns():
		_fail("premise: no columns at %.0f" % PAGE_2K)
		return
	for row in [[FinanceDraft.SPENDING, "health"], [FinanceDraft.TAX, "income"]]:
		await _open(row[0], row[1])
		_check_columns("%s open" % row[1])
		# Nothing the editor says is cut in the narrower sheet (a sector's figure was, in the first frames).
		for node in _panel._editor.find_children("*", "Label", true, false) if _panel._editor != null else []:  # i18n: ok a class name
			var label := node as Label
			if label.is_visible_in_tree() and label.clip_text and label.text != "" \
					and label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x > label.size.x + 0.5:
				_fail("%s open: '%s' is cut at %.0f px" % [row[1], label.text, label.size.x])
		if row[0] == FinanceDraft.SPENDING:
			await _check_every_line_figures(2)
	_panel.open_row(FinanceDraft.TAX, "income")
	for _i in 4:
		await process_frame


## A sector's figure wraps beside its name, so it needs a width of its own: starved, it stacks a word a line.
## Read in both arrangements at both text sizes, the spending row's editor left open.
func _check_sector_figures(most := 2) -> void:
	for scale in [0.9, 1.0]:
		UiTheme.set_text_scale(scale)
		_panel.theme = UiTheme.build()
		root.gui_release_focus()  # held by the editor, the rows would stay at the old size and so would the switch
		await _at(PAGE_1080)
		for width in [PAGE_1080, _panel._table.need() + 1.0, PAGE_2K, 2292.0]:
			await _at(width)
			var names: Array = _panel._editor.find_children("*", "Label", true, false).filter(func(l) -> bool: return l.has_meta("sector"))  # i18n: ok a class name
			if names.is_empty():
				_fail("premise: no sector rows at %.0f, text %d" % [width, roundi(scale * 100)])
			var lines: int = most if width == PAGE_1080 else most + 1  # a hugging sheet in columns: one more
			for name in names:
				var figure := name.get_parent().get_child(1) as Label
				if figure.size.x < FinanceRows.CAPTION_MIN * scale - 0.5 or figure.get_line_count() > lines:
					_fail("%s at %.0f, text %d: '%s' is %.0f wide on %d lines" % [_panel._open_id, width, roundi(scale * 100), figure.text, figure.size.x, figure.get_line_count()])
			_check_fits("sector rows at %.0f, text %d" % [width, roundi(scale * 100)])
	UiTheme.set_text_scale(1.0)
	_panel.theme = UiTheme.build()
	await _at(PAGE_2K)


## Every line's sectors, not health's alone: the longest names are elsewhere, and a longer language lengthens them.
func _check_every_line_figures(most: int) -> void:
	var lines := 0
	for key in _state.player().spending_pct_gdp:
		await _open(FinanceDraft.SPENDING, String(key))
		if _panel._editor == null or _panel._editor.find_children("*", "Label", true, false).filter(func(l) -> bool: return l.has_meta("sector")).is_empty():  # i18n: ok a class name
			continue
		lines += 1
		await _check_sector_figures(most)
	if lines < 2:
		_fail("premise: %d lines with sectors" % lines)


## Open a row with the keyboard let go first: an editor holding it keeps its row (the page never rebuilds under a hand),
## and the row asked for would not be the one measured.
func _open(channel: String, key: String) -> void:
	root.gui_release_focus()
	_panel.open_row(channel, key)
	for _i in 6:
		await process_frame
	if _panel._editor == null or _panel._editor.channel != channel or _panel._editor.key != key:
		_fail("premise: no editor on %s (%s)" % [key, "none" if _panel._editor == null else _panel._editor.key])


func _check_pseudo() -> void:
	Strings.set_language("en")
	# 0.5 first: past the shipped 0.35 a header's name outgrows the line rows, which no bar may follow (pass 2 T1).
	for ratio in [0.5, 0.35]:
		ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", ratio)
		TranslationServer.pseudolocalization_enabled = true
		TranslationServer.reload_pseudolocalization()
		root.gui_release_focus()  # an editor holding the keyboard would keep the old rows up
		_panel._open_id = ""
		_panel.mark_dirty()
		await _at(1300.0)
		var need: float = _panel._table.need()
		print("test_finance_columns: pseudo %s, the switch at %.0f px" % [ratio, need])
		if _head_text(_panel._spending_box, "who") == "WHO PAYS" or not _slot(_panel._revenue_box, "who").any(func(c) -> bool: return c.text.begins_with("[")):
			_fail("premise: the rows are still English under the pseudo-locale")
		_check_fits("pseudo %s, one table" % ratio)
		await _at(need + 1.0)
		if not _panel._table.columns():
			_fail("pseudo %s: no columns at its own switch" % ratio)
		_check_fits("pseudo %s, columns" % ratio)
		_check_one_bar("pseudo %s, columns" % ratio)
		if ratio == 0.35:  # the shipped ratio: past it "[558 bn]" is wider than half a bar
			_check_axis(_panel._revenue_box, "pseudo %s, columns" % ratio)
	await _check_every_line_figures(99)  # the pseudo unit runs to five lines: wrapped, never starved of width
	TranslationServer.pseudolocalization_enabled = false


## A slider under the pointer keeps its arrangement, the editor's as a row's bar: a track that changed length
## mid-drag would jump the rate (pass 2 T4). The keyboard alone holds nothing.
func _check_the_held_slider() -> void:
	await _at(PAGE_2K)
	await _open(FinanceDraft.TAX, "income")
	var sliders: Array = _panel._editor.find_children("*", "HSlider", true, false)  # i18n: ok a class name
	var held: Control = sliders[0] if not sliders.is_empty() else _panel._table._row_bars(_panel._revenue_box).filter(func(b) -> bool: return b.focus_mode != Control.FOCUS_NONE)[0]
	held.grab_focus()
	_press(true)
	_panel._table.size.x = PAGE_1080
	_panel._table._process(0.0)
	if not _panel._table.columns():
		_fail("the table re-laid itself under a held slider")
	_press(false)
	_panel._table._process(0.0)
	if _panel._table.columns():
		_fail("a slider only focused holds the arrangement")
	root.gui_release_focus()


## A row's bar mid-drag holds the arrangement too. Pushed to the viewport, not through Input: the table's other
## hold (a focused slider with the button down) reads Input, so only the drag can hold it here.
func _check_the_dragged_bar() -> void:
	await _at(PAGE_2K)
	var bars: Array = _panel._table._row_bars(_panel._spending_box).filter(func(b) -> bool: return b.can_drag())
	if bars.is_empty():
		_fail("premise: no spending bar to drag")
		return
	var bar: FinanceLever = bars[0]
	_drag(bar, true)
	if not bar.is_dragging():
		_fail("premise: the press did not start a drag")
	_panel._table.size.x = PAGE_1080
	_panel._table._process(0.0)
	if not _panel._table.columns():
		_fail("the table re-laid itself under a dragged bar")
	_drag(bar, false)
	_panel._table._process(0.0)
	if _panel._table.columns():
		_fail("a bar let go still holds the arrangement")
	root.gui_release_focus()


## On the handle where it stands, so the draft does not move.
func _drag(bar: FinanceLever, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = bar.get_global_rect().position + Vector2(bar.x_of(bar.value), bar.size.y * 0.5)
	event.global_position = event.position
	root.push_input(event, true)


func _press(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Who pays counts the folded kinds even when every visible row says "At vote" (pass 2 T3).
func _check_who_folded() -> void:
	await _at(PAGE_2K)
	var table: FinanceColumns = _panel._table
	var groups := [{"kinds": [], "folded": [{"who": ["workers", "retirees", "business", "farmers", "students", "workers", "retirees", "business"]}]}]
	for cell in _slot(_panel._revenue_box, "who"):
		cell.remove_meta("who_pays")
	var before: float = table._who
	table.measure(groups)
	if table._who <= before + 100.0:
		_fail("a folded kind's who-pays is not measured: %.0f, was %.0f" % [table._who, before])
	_panel._open_id = ""
	_panel.mark_dirty()
	await _at(PAGE_2K)


## In the dock, a window too short for the books: in columns the bar stands in the gap at Revenue's right (T16 on #441);
## as one table the scroll is inside a sheet again and keeps its own.
func _check_the_scroll_bar() -> void:
	_panel.hide()
	var host := Control.new()
	host.theme = UiTheme.build()
	root.add_child(host)
	var manager := WindowManager.new()
	host.add_child(manager)
	var panel := FinancesPanel.new()
	manager.register("finances", "Finances", panel)
	panel.setup(_state, _loader)
	manager.set_aside("finances", panel.rail())
	for width in [2560, 1920, 2560]:
		root.size = Vector2i(width, 900)
		host.size = Vector2(width, 900)
		manager.open("finances")
		for _i in 12:
			await process_frame
		var table: FinanceColumns = panel._table
		var own: VScrollBar = table.scroll.get_v_scroll_bar()
		var gap: VScrollBar = GapBars.bar_for(manager, table.scroll)
		if table.columns() != (width == 2560) or not GapBars.scrolls(table.scroll):
			_fail("premise: at %d, columns %s, scrolls %s" % [width, table.columns(), GapBars.scrolls(table.scroll)])
		elif table.columns():
			var end: float = (panel._revenue_box.get_parent() as Control).get_global_rect().end.x
			if own.visible or gap == null or not gap.visible or gap.global_position.x < end - 0.5 or gap.get_global_rect().end.x > end + UiTheme.GAP_PANE + 0.5:
				_fail("columns at %d: own bar %s, gap bar at %s, revenue ends at %.0f" % [width, own.visible, "none" if gap == null else str(gap.get_global_rect()), end])
		elif not own.visible or (gap != null and gap.visible):
			_fail("one table at %d: own bar %s, gap bar %s" % [width, own.visible, gap != null and gap.visible])
	host.queue_free()
	_panel.show()


## An index reads before its number, in the row, in its change and in the change's figures, and fits the column.
func _check_rate_words() -> void:
	var ns = _state.player()
	_panel._open_id = ""
	_panel._open_groups["consumption"] = true
	_panel.mark_dirty()
	for width in [PAGE_1080, PAGE_2K]:
		await _at(width)
		for pair in [[100.0, "index\u00a0100"], [105.0, "from index\u00a0100 to 105"]]:
			_panel._draft.set_value(FinanceDraft.TAX, "alcohol_duty", pair[0])
			_panel.mark_dirty()
			for _i in 6:
				await process_frame
			var cell: Label = _panel._ctx["cells"][FinanceRows.row_id(FinanceDraft.TAX, "alcohol_duty")][0]
			var wants: float = cell.get_theme_font("font").get_string_size(cell.text, HORIZONTAL_ALIGNMENT_LEFT, -1, cell.get_theme_font_size("font_size")).x
			if cell.text != pair[1] or wants > cell.size.x + 0.5:
				_fail("at %.0f the index reads '%s' (%.0f of %.0f px), wanted '%s'" % [width, cell.text, wants, cell.size.x, pair[1]])
	var row := {"channel": FinanceDraft.TAX, "key": "alcohol_duty", "live": 100.0, "draft": 105.0}
	if FinanceRows.change_figures(ns, row) != "index\u00a0100 → 105":
		_fail("the change reads '%s'" % FinanceRows.change_figures(ns, row))
	row = {"channel": FinanceDraft.TAX, "key": "vat", "live": 20.0, "draft": 21.0}
	if not FinanceRows.change_figures(ns, row).ends_with("\u00a0%") or FinanceRows.change_figures(ns, row).count("%") != 1:
		_fail("a percentage's change reads '%s'" % FinanceRows.change_figures(ns, row))
	_panel._draft.drop(FinanceDraft.TAX, "alcohol_duty")


func _slot(box: Node, slot: String) -> Array:
	return box.find_children("*", "Label", true, false).filter(func(l) -> bool: return l.get_meta("slot", "") == slot)  # i18n: ok a class name


## The text of a sheet's head cell (the first row of the sheet).
func _head_text(box: Node, slot: String) -> String:
	var cells := _slot(box, slot)
	return "?" if cells.is_empty() else String(cells[0].text).strip_edges()


func _fail(message: String) -> void:
	_failures.append(message)
