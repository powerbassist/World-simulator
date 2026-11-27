extends PanelContainer

## The Books table: Spending over Revenue as one sheet, or, from the width at which both read whole, two sheets
## side by side (W2, the page in columns: Design's pick, the author's, 2026-11-27). The page asks its OWN width, not
## the screen's, and the switch is read from the rows at run time, so it follows the text size and the language.
## Nothing is rebuilt at a switch: the same rows are dressed for one arrangement or the other (finance_rows.gd tags
## the cells that change with a "slot").

const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceLever = preload("res://src/ui/finance_lever.gd")
const GapBars = preload("res://src/ui/gap_bars.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")

## The width the columned page stops at, times the text size (the parent's ruling, gate-2k.md note 3).
const CEILING := 1880.0
## Of the room over what both columns need, spending's share: Design's 736 of 1880 (about 701 needed, 175 over).
## Under a half, so revenue always has room for bars as long as spending's (one money scale, T5 on #443).
const SPENDING_SHARE := 0.2
const HEADS := {"drag": "Drag", "year": "A year", "balance": "Balance"}  # i18n: msgid

var scroll := ScrollContainer.new()
var spending := VBoxContainer.new()
var revenue := VBoxContainer.new()
var _books := BoxContainer.new()
var _wraps: Array[PanelContainer] = []
var _columns := false
var _stale := false
## Measured on the rows just built: the switch, each sheet's width, who-pays whole.
var _need := INF
var _spend := 0.0
var _rev := 0.0
var _who := 0.0


func _init() -> void:
	theme_type_variation = UiTheme.PLATE
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_meta(GapBars.FOLLOWS, true)
	add_child(scroll)
	_books.vertical = true
	_books.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_books.add_theme_constant_override("separation", 0)
	scroll.add_child(_books)
	# Spending first: the lines are what a budget sets; revenue after them. The reading and focus order in both.
	for box in [spending, revenue]:
		var wrap := PanelContainer.new()
		wrap.theme_type_variation = UiTheme.BARE
		wrap.add_child(box)
		_books.add_child(wrap)
		_wraps.append(wrap)
	_wraps[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(func() -> void: _stale = true)
	scroll.resized.connect(func() -> void: _stale = true)


func columns() -> bool:
	return _columns


## The page's width from which the two columns read whole.
func need() -> float:
	return _need


## The width the page stops at: none as one table (it fills the workspace, decision 9).
func cap() -> float:
	# A px over the switch: a cap equal to it, subtracted back from the band, could land a fraction under.
	return maxf(CEILING * UiTheme.text_scale(), _need + 1.0) if _columns else INF


func _process(_delta: float) -> void:
	# Never under a hand: a track that moved or changed length mid-drag would jump its value.
	if _stale and not _held():
		_lay()


## A row's bar dragged, or the pointer down on the editor's slider (which cannot say it is dragged).
func _held() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is HSlider and is_ancestor_of(focus) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	return find_children("*", "HSlider", true, false).any(func(bar) -> bool: return bar is FinanceLever and bar.is_dragging())  # i18n: ok a class name


## Read the rows just built (call it after every rebuild, before anything dresses them) and lay them out.
## `groups` is the book's revenue: who pays counts at its longest, folded kinds included, so a fold opened
## never moves the switch.
func measure(groups: Array) -> void:
	_who = 0.0
	var cells := _slot(revenue, "who")  # the head and the notes are in that column too
	for cell in cells:
		_who = maxf(_who, _text_width(cell, cell.text))
	var captions := cells.filter(func(c) -> bool: return c.theme_type_variation == UiTheme.CAPTION)
	for group in groups if not captions.is_empty() else []:  # every kind's, shown or folded: the caption's font
		for kind in (group["kinds"] as Array) + (group["folded"] as Array):
			_who = maxf(_who, _text_width(captions[0], ", ".join((kind["who"] as Array).map(func(b) -> String: return Labels.bloc(String(b))))))
	_who = ceilf(_who) + 1.0
	# Whole pixels: a sheet a fraction wide would draw its bars a pixel longer than the other's.
	_spend = ceilf(_widest(spending, 0.0))
	_rev = _widest(revenue, _who)
	_need = ceilf(_spend + _rev + 2.0 * _margins() + UiTheme.GAP_PANE + _bar_room())
	_lay()


## The widest of a sheet's rows, the who-pays cell counted at `who` (0: the column drops it). The open row's
## editor tile is not a row: it takes the width its sheet has.
func _widest(box: Control, who: float) -> float:
	var widest := 0.0
	for child in box.get_children():
		var row := _row_in(child)
		if row != null:
			widest = maxf(widest, _width_of(row, who))
		elif not child is PanelContainer:
			widest = maxf(widest, (child as Control).get_combined_minimum_size().x)
	return widest


## The row a sheet's child is (a header sits in its spacing margin), or null.
func _row_in(child: Node) -> HBoxContainer:
	var inner: Node = child.get_child(0) if child is MarginContainer and child.get_child_count() == 1 else child
	return inner as HBoxContainer


## The sheet's rows' own bars, never the open editor's slider.
func _row_bars(box: Control) -> Array:
	var bars := []
	for child in box.get_children():
		var row := _row_in(child)
		if row != null:
			bars.append_array(row.get_children().filter(func(c) -> bool: return c is FinanceLever))
	return bars


func _width_of(row: Control, who: float) -> float:
	var total := 0.0
	var count := 0
	for cell in row.get_children():
		var wide := ceilf((cell as Control).get_combined_minimum_size().x)  # a box rounds each cell's minimum up
		if cell.get_meta("slot", "") == "who":
			if who <= 0.0:
				continue
			wide = who
		total += wide
		count += 1
	return total + maxi(count - 1, 0) * row.get_theme_constant("separation")


func _text_width(cell: Label, text: String) -> float:
	return cell.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, cell.get_theme_font_size("font_size")).x


func _margins() -> float:
	return get_theme_stylebox("panel", UiTheme.PLATE).get_minimum_size().x


## What the scroll bar takes when it shows; kept always, so that it never decides the arrangement.
func _bar_room() -> float:
	return scroll.get_v_scroll_bar().get_combined_minimum_size().x + scroll.get_theme_constant("scrollbar_h_separation")


func _lay() -> void:
	_stale = false
	_columns = size.x >= _need
	var scale := UiTheme.text_scale()
	_books.vertical = not _columns
	_books.add_theme_constant_override("separation", UiTheme.GAP_PANE if _columns else 0)
	theme_type_variation = UiTheme.BARE if _columns else UiTheme.PLATE
	# Never DISABLED in columns: the content's minimum would hold the page wide, and it could not come back.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if _columns else ScrollContainer.SCROLL_MODE_DISABLED
	# In columns the scroll holds sheets: its bar stands in the gap, or Revenue would end short of the header's edge.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if _columns else ScrollContainer.SCROLL_MODE_AUTO
	for wrap in _wraps:
		wrap.theme_type_variation = UiTheme.PLATE if _columns else UiTheme.BARE
		wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if _columns else Control.SIZE_FILL  # the sheets hug
	# From the scroll's width, never from the rows': their own widths would hold a narrowed page open.
	var over := maxf(0.0, scroll.size.x - _bar_room() - _spend - _rev - 2.0 * _margins() - UiTheme.GAP_PANE) if _columns else 0.0
	var spend_wide := _spend + floorf(over * SPENDING_SHARE)
	_wraps[0].custom_minimum_size.x = spend_wide + _margins() if _columns else 0.0
	# One length for every bar of both sheets, one money scale: the least a bar is plus spending's share. Never what
	# is left beside one row: a header's longer name would lengthen revenue's bars past the page (pass 2 T1).
	var bar_wide := FinanceRows.BAR_MIN * scale + floorf(over * SPENDING_SHARE)
	for cell in _slot(spending, "who"):
		cell.visible = not _columns
	for cell in _slot(spending, "pct"):  # "not set here" moves into the blank figure cell
		var note := _slot(cell.get_parent(), "who")
		cell.text = note[0].text if _columns and not note.is_empty() else ""
		cell.theme_type_variation = UiTheme.CAPTION if _columns else ""
	for cell in _slot(revenue, "who"):
		cell.custom_minimum_size.x = _who if _columns else FinanceRows.CAPTION_MIN * scale
	for slot in HEADS:
		for cell in _slot(revenue, slot):  # spending names the columns for both only while it stands over revenue
			cell.text = Strings.t(HEADS[slot]).to_upper() if _columns else ""
	for bar in _row_bars(spending) + _slot(spending, "drag") + _row_bars(revenue) + _slot(revenue, "drag"):
		bar.custom_minimum_size.x = bar_wide
		bar.size_flags_horizontal = Control.SIZE_FILL if _columns else Control.SIZE_EXPAND_FILL


func _slot(under: Node, slot: String) -> Array:
	return under.find_children("*", "Label", true, false).filter(func(l) -> bool: return l.get_meta("slot", "") == slot)  # i18n: ok a class name
