extends PanelContainer

## One sector's tab in the Sectors domain -- V5.3 screen 5, the author's pick C ("les
## produits"). Left: the head (verdict, lead sentence, four figures) and the sector's
## programme as a finance-bill row (sector_programme.gd), what waits on the player, what
## the sector makes good by good (sector_goods_view.gd), its majors. Right: the selected
## firm's sheet (firm_sheet.gd) with its file and the State's verbs (slice 2).
##
## A page wide enough lays three columns (W2, the author's pick, 2026-11-27): the lead,
## what waits and the majors | what it makes | the firm. The switch is the page's OWN
## width against its blocks' minimums, read each frame, so it follows the text size, the
## language and the month's figures; the widest of the sector tabs' sets it for all.
##
## A major or a closure's Answer selects its firm on the sheet; a right click on a firm
## opens its verbs with their prices, the call to its chief and the map. A bid, a failing
## major or a process's ask is still answered on the overview (the window "companies"):
## Answer opens it there with the firm opened.
##
## Every figure is a reader's (SectorRead, SectorGoods, SectorNeeds); what the pictures
## staged without one is cut: a major's 12-month change (the sim keeps no series per
## firm) and "smaller firms" as a good's maker (body firms carry no products).

signal go_firm(sector: String, company_id: String)
## (before_snapshot, label): a command acted (firm_commands.gd), main's decision delta.
signal acted(before, label)
signal call_requested(person_id: String)
signal map_requested(lonlat: Vector2)

const SectorRead = preload("res://src/ui/sector_read.gd")
const SectorNeeds = preload("res://src/ui/sector_needs.gd")
const Companies = preload("res://src/sim/companies.gd")
const Closures = preload("res://src/sim/closures.gd")
const Region = preload("res://src/core/region.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const FirmCommands = preload("res://src/ui/firm_commands.gd")
const FirmSheet = preload("res://src/ui/firm_sheet.gd")
const SectorProgramme = preload("res://src/ui/sector_programme.gd")
const SectorGoodsView = preload("res://src/ui/sector_goods_view.gd")
const VerbBlock = preload("res://src/ui/verb_block.gd")
const FinanceColumns = preload("res://src/ui/finance_columns.gd")

## The sheet's width in px: the picture's right column.
const SHEET_WIDTH := 440
## Both times the text size: the widest the lead stands in three (the picture's), and the narrowest, four major tiles
## in a row, which the switch counts.
const LEFT_WIDTH := 788.0
const LEFT_FLOOR := 648.0

const FACE := Vector2(28, 38)
## A major's tile (G3 S3): its width and its face, in px at text size 100.
const MAJOR_W := 150.0
const MAJOR_GAP := 8
const MAJOR_FACE := Vector2(44, 58)
## The verdict's tag tone: a status, so a fixed tone and its words, never the accent.
const VERDICT_TONE := {"behind": UiTheme.BAD_TEXT, "slower": UiTheme.WARN_TEXT, "pace": UiTheme.CAPTION, "ahead": UiTheme.GOOD_TEXT}
## The line a Needs you row says under the firm's name, by kind.
const NEED_WORDS := {
	"bid": "A foreign takeover bid waits on your answer",  # i18n: msgid
	"failing": "Failing: the rescue window is open",  # i18n: msgid
	"ask": "A process waits on your answer",  # i18n: msgid
}

## The sector this tab shows (nations/*.json `sectors`).
var sector := ""
var _state
var _loader
var _dirty := true
var _body: VBoxContainer
## The middle column, hidden while there are two; what the sector makes moves between it and _body.
var _middle: VBoxContainer
var _goods: VBoxContainer
## The majors' tiles: in three the lead is as wide as they ask in one row.
var _majors_row: HFlowContainer
## The widest the unfiltered goods table asked: a chip narrows the table and must not move the switch.
var _goods_wide := 0.0
## The page's width from which three columns read whole, on this tab and on the others.
var _need := INF
## The sector tabs, this one among them (sectors_shell.gd hands main's table): none for a panel on its own.
var tabs := {}
## The size caches may be stale for a measure taken hidden: set at a rebuild or a new theme (the text size), spent
## by the next measure.
var _stale := false
## The good the chips filter the table to, "" for all of them.
var _good_filter := ""
var _sheet: VBoxContainer
## The firm on the sheet, "" for the default (the first waiting, else the first major).
var _firm_id := ""
## A right click asked to light the selected firm's verbs once the sheet is rebuilt.
var _light := false
## firm_commands.gd's state: the focused verb, the card an irreversible verb asks on, the
## last refusal, the programme stop picked on the slider (-1: as it stands).
var _focus_verb := ""
var _confirm
var _last_refusal := ""
var _prog_pick := -1
## The programme's slider is held: a rebuild under the drag would free it (sector_programme.gd).
var _dragging := false
## The programme's control a keyboard step left focused, "slider" or "box": its rebuild hands the focus on.
var _prog_focus := ""


func _init(sector_id := "") -> void:
	sector = sector_id


func _ready() -> void:
	custom_minimum_size = Vector2(560, 0)  # the dock sets the height (tab_page.gd wanted_height)
	# No margin round the sheets: they sit on the header sheet's grid, 12 apart (window_manager
	# OWN_SHEETS; Design's T14 on #441, the Diary's rule).
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", UiTheme.GAP_PANE)
	add_child(columns)
	_body = _column(columns, Control.SIZE_EXPAND_FILL)
	_middle = _column(columns, Control.SIZE_FILL)
	(_middle.get_parent() as Control).hide()
	_sheet = _column(columns, Control.SIZE_FILL)
	_sheet.custom_minimum_size.x = SHEET_WIDTH


## A scrolling column: EXPAND vertically, so the page fills the dock (tab_page.
## _scrolls_inside) and each list scrolls inside its own pane.
func _column(parent: Control, horizontal: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = horizontal
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	# No gutter for the bar: the sheets' edges meet the header's (T14); a sheet's own padding keeps
	# its right-aligned figures clear of a bar drawn over it.
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", UiTheme.GAP_PANE)
	scroll.add_child(box)
	return box


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true
	# A setup() after the first is a load: the discarded game's picks go with it (the retro review's item 7). The confirm
	# card stays: it sits on the screen stack once and is re-armed by each ask (CompanyVerb.ask).
	_good_filter = ""
	_firm_id = ""
	_light = false
	_focus_verb = ""
	_last_refusal = ""
	_prog_pick = -1
	_dragging = false
	_prog_focus = ""


func mark_dirty() -> void:
	_dirty = true


## A tab hidden under a held slider never sees the release: the hold ends with it, or the tab stays frozen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_dragging = false
	if what == NOTIFICATION_THEME_CHANGED:
		_stale = true


func hide_close_button() -> void:
	pass


func _process(_delta: float) -> void:
	# A held slider holds the arrangement too: a track that changed length under it would jump its value.
	if _dragging or not is_visible_in_tree() or _state == null:
		return
	if _dirty:
		_dirty = false
		_refresh()
	_arrange()


## The width the page stops at in columns (window_manager.gd reads it); INF as two.
func page_cap() -> float:
	# A px over the switch, as Books' (finance_columns.gd cap()).
	return maxf(FinanceColumns.CEILING * UiTheme.text_scale(), _need + 1.0) if (_middle.get_parent() as Control).visible else INF


## What three columns ask of this tab now. A tab not shown since the last change is built first, hidden, to say it.
func _asks() -> Dictionary:
	if _dirty and _state != null:
		_dirty = false
		_refresh()
		_stale = true
	if _goods == null:
		return {}
	# Measured: a tab built hidden read its goods names as 1 px (the switch 127 px short), and a new text size left its
	# goods table at the old width.
	if _stale and not is_visible_in_tree():
		_drop_sizes(self)
	_stale = false
	var text := UiTheme.text_scale()
	var asked := _goods.get_combined_minimum_size().x
	_goods_wide = asked if _good_filter == "" else maxf(_goods_wide, asked)
	var goods := ceilf(maxf(_goods_wide, SHEET_WIDTH * text))
	var left := LEFT_FLOOR * text
	for child in _body.get_children():
		if child != _goods:
			left = maxf(left, (child as Control).get_combined_minimum_size().x)
	left = ceilf(left)
	var firm := ceilf(maxf(SHEET_WIDTH, _sheet.get_combined_minimum_size().x))
	# A px over the narrowest three: the columns' minimums stay under the switch, so a page they hold wide falls to two.
	return {"left": left, "goods": goods, "firm": firm, "need": left + goods + firm + 1.0 + 2.0 * UiTheme.GAP_PANE}


static func _drop_sizes(node: Node) -> void:
	for child in node.get_children():
		_drop_sizes(child)
	if node is Control:
		(node as Control).update_minimum_size()


## Two columns or three, by the page's width against what the widest sector tab asks: a tab press never changes it.
func _arrange() -> void:
	var mine := _asks()
	if mine.is_empty():
		return
	_need = mine["need"]
	for tab in tabs.values():
		if tab != self:
			_need = maxf(_need, tab._asks().get("need", 0.0))
	var text := UiTheme.text_scale()
	var left: float = mine["left"]
	var goods: float = mine["goods"]
	var firm: float = mine["firm"]
	var gaps := 2.0 * UiTheme.GAP_PANE
	var three := size.x >= _need
	var home := _middle if three else _body
	if _goods.get_parent() != home:
		# Leaving the tree drops the focus: a chip that held it takes it back, its ring shown or hidden as it was.
		var held := get_viewport().gui_get_focus_owner()
		if held != null and not _goods.is_ancestor_of(held):
			held = null
		var ring := held != null and held.has_focus(true)
		_goods.get_parent().remove_child(_goods)
		home.add_child(_goods)
		if not three:
			_body.move_child(_goods, _body.get_child_count() - 2)  # above the majors
		if held != null:
			held.grab_focus(not ring)
	# In three every column hugs its content; the page's leftover stays empty at its right (the author on 2K).
	var lead := _body.get_parent() as ScrollContainer
	lead.size_flags_horizontal = Control.SIZE_FILL if three else Control.SIZE_EXPAND_FILL
	var row := (_majors_row.get_parent().get_parent() as Control).get_theme_stylebox("panel").get_minimum_size().x - MAJOR_GAP
	for cell in _majors_row.get_children():
		row += ceilf((cell as Control).get_combined_minimum_size().x) + MAJOR_GAP
	var hug := maxf(left, floorf(minf(row, LEFT_WIDTH * text)))
	# The majors wrap where the page has no room for their one row, with the same px to spare as the switch.
	if hug + goods + firm + gaps + 1.0 > size.x:
		hug = left
	# Widths on the scrolls: SHOW_NEVER passes no minimum up.
	lead.custom_minimum_size.x = hug if three else 0.0
	(_middle.get_parent() as Control).custom_minimum_size.x = goods
	(_middle.get_parent() as Control).visible = three
	(_sheet.get_parent() as Control).custom_minimum_size.x = firm if three else 0.0
	# Never DISABLED in three: the columns' minimums would hold the page wide, and it could not come back.
	for box in [_body, _middle, _sheet]:
		(box.get_parent() as ScrollContainer).horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if three else ScrollContainer.SCROLL_MODE_DISABLED


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	# Out of the tree at once: freed only at the frame's end, the old sheet doubled the content a lit block's scroll
	# measured (pass 2 T6).
	for child in _body.get_children() + _middle.get_children() + _sheet.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	_head(ns)
	_needs(ns)
	_goods = VBoxContainer.new()
	_body.add_child(_goods)  # _arrange() moves it to the middle column the same frame
	SectorGoodsView.build(self, _goods, ns)
	_majors(ns)
	var company = _selected(ns)
	if company != null:
		FirmSheet.build(self, PanelKit.sheet(_sheet), ns, company)
	if _light:
		_light = false
		VerbBlock.light(_sheet)


func _head(ns) -> void:
	var reading := SectorRead.head(_state, _loader, ns, sector)
	# G3 S3: the head is a sheet -- the verdict over the lead on the left, the figures on tiles at its right.
	var box := PanelKit.sheet(_body)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	box.add_child(split)
	var said := VBoxContainer.new()
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(said)
	var top := PanelKit.buttons(said)
	var name_label := PanelKit.plain_line(top, Labels.sector(sector), PanelKit.Tone.PLAIN)
	name_label.theme_type_variation = UiTheme.HEADING
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var tag := PanelKit.plain_line(top, SectorRead.verdict_words(String(reading["verdict"])), PanelKit.Tone.PLAIN)
	tag.theme_type_variation = String(VERDICT_TONE[reading["verdict"]])
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	var lead := PanelKit.plain_line(said, SectorRead.lead(reading, func(v: float) -> String: return Num.fs(v, 1)), PanelKit.Tone.PLAIN)
	lead.theme_type_variation = UiTheme.LEAD
	# Two by two: four tiles in one row left the tab past its dock under +35 % (test_i18n_fit).
	var figures := GridContainer.new()
	figures.columns = 2
	figures.add_theme_constant_override("h_separation", 8)
	figures.add_theme_constant_override("v_separation", 8)
	figures.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	split.add_child(figures)
	PanelKit.figure_tile(figures, tr("%s bn") % Num.f(float(reading["output"]), 0), tr("Output"))
	PanelKit.figure_tile(figures, CompanyVerb.thousands(float(reading["jobs"])), tr("Jobs"))
	PanelKit.figure_tile(figures, tr("%s %%") % Num.fs(float(reading["trend"]), 1), tr("Trend a year"))
	PanelKit.figure_tile(figures, tr("%s %%") % Num.f(float(reading["of_gdp"]), 1), tr("Of GDP"))
	SectorProgramme.build(self, box, ns, sector)


func _needs(ns) -> void:
	var mine: Array = []
	for item in SectorNeeds.items(_state, _loader, ns):
		if String(item["sector"]) == sector:
			mine.append(item)
	# Nothing waiting, no section: the tab's hourglass already says so (the text diet).
	if mine.is_empty():
		return
	var section := PanelKit.sheet(_body, tr("Needs you · %d") % mine.size())
	for item in mine:
		var company = _firm(String(item["company_id"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", PanelKit.COLUMN_SEPARATION)
		section.add_child(row)
		row.add_child(Portrait.control_for(String(company.chief_id), FACE))
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		PanelKit.plain_line(words, company.company_name, PanelKit.Tone.PLAIN)
		PanelKit.plain_line(words, _need_line(ns, item))
		var months := int(item["months_left"])
		if months >= 0:
			var chip := PanelKit.plain_line(row, tr_n("%d month left", "%d months left", months) % months, PanelKit.Tone.PLAIN)
			chip.theme_type_variation = UiTheme.WARN_TEXT
			chip.autowrap_mode = TextServer.AUTOWRAP_OFF
		var go := PanelKit.sized(Button.new())
		go.text = tr("Answer")
		go.set_meta("go_firm", String(item["company_id"]))
		var company_id := String(item["company_id"])
		# A closure is answered on the sheet; the rest on the overview, until they move here.
		if String(item["kind"]) == "closure":
			go.pressed.connect(_select.bind(company_id))
		else:
			go.pressed.connect(func() -> void: go_firm.emit(sector, company_id))
		row.add_child(go)
		row.gui_input.connect(_right_click.bind(company))


func _need_line(ns, item: Dictionary) -> String:
	if String(item["kind"]) != "closure":
		return tr(String(NEED_WORDS[item["kind"]]))  # i18n: row-ok the table's msgids
	var row: Dictionary = (ns.companies.get(String(item["company_id"]), {}) as Dictionary).get("closure", {})
	var city = Region.find_city(_loader.regions.get(ns.id, []), String(row.get("city_id", "")))
	var jobs := CompanyVerb.thousands(float(row.get("jobs", 0.0)))
	if city == null:
		return tr("Closes a plant · %s jobs") % jobs
	return tr("Closes its %s plant · %s jobs") % [String(city.city_name), jobs]


func _majors(ns) -> void:
	var majors: Array = []
	for company in Companies.firms_in_sector(_loader, ns.id, sector):
		if Companies.is_major(company):
			majors.append(company)
	# G3 S3: a sheet of firm tiles (the kit's majors): the face above the name, the picked one on a tile.
	var section := PanelKit.sheet(_body, tr("The majors · %d") % majors.size())
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", MAJOR_GAP)
	grid.add_theme_constant_override("v_separation", MAJOR_GAP)
	section.add_child(grid)
	_majors_row = grid
	var picked = _selected(ns)
	for company in majors:
		var cell: Container = PanelContainer.new() if picked == company else MarginContainer.new()
		if picked == company:
			cell.theme_type_variation = UiTheme.TILE_PANEL
		cell.custom_minimum_size.x = roundf(MAJOR_W * UiTheme.text_scale())
		grid.add_child(cell)
		var words := VBoxContainer.new()
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.add_theme_constant_override("separation", 2)
		cell.add_child(words)
		var face := Portrait.control_for(String(company.chief_id), MAJOR_FACE)
		face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		words.add_child(face)
		var pick := PanelKit.sized(Button.new())
		# Not a toggle: the picked tile carries the ground, the name inside stays bare (Design's T15).
		pick.flat = true
		pick.text = company.company_name
		pick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pick.set_meta("firm", String(company.id))
		pick.pressed.connect(_select.bind(String(company.id)))
		pick.gui_input.connect(_right_click.bind(company))
		words.add_child(pick)
		cell.gui_input.connect(_right_click.bind(company))
		var city = Region.find_city(_loader.regions.get(ns.id, []), Companies.live_city_of(ns, company))
		var jobs := tr("%s jobs") % CompanyVerb.thousands(Companies.headcount(ns, company))
		var where := PanelKit.plain_line(words, jobs if city == null else "%s · %s" % [String(city.city_name), jobs])
		where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if not Closures.announced(ns, String(company.id)).is_empty():
			var tag := PanelKit.plain_line(words, tr("closing a plant"), PanelKit.Tone.PLAIN)
			tag.theme_type_variation = UiTheme.BAD_TEXT
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _firm(company_id: String):
	for company in _loader.companies.get(_state.player().id, []):
		if String(company.id) == company_id:
			return company
	return null


## The firm on the sheet: the one picked, else the first waiting in this sector, else
## the first major.
func _selected(ns):
	# A firm picked and since gone (failed, broken up) falls back to the default.
	if _firm_id != "" and _firm(_firm_id) != null:
		return _firm(_firm_id)
	for item in SectorNeeds.items(_state, _loader, ns):
		if String(item["sector"]) == sector:
			return _firm(String(item["company_id"]))
	for company in Companies.firms_in_sector(_loader, ns.id, sector):
		if Companies.is_major(company):
			return company
	return null


func _select(company_id: String) -> void:
	_firm_id = company_id
	_focus_verb = ""
	_last_refusal = ""
	_dirty = true


## The right click on a firm (the rework pass's C, no plate): the firm is selected and its sheet's verbs lit.
func _right_click(event: InputEvent, company) -> void:
	if not VerbBlock.is_right_press(event):
		return
	_select(String(company.id))
	_light = true


# The commands, shared with the overview (firm_commands.gd).
func _on_act(ns, company, action) -> void:
	FirmCommands.act(self, ns, company, action)


func _on_closure(closure_id: String, answer_id: String, what: String) -> void:
	FirmCommands.closure(self, closure_id, answer_id, what)


func _on_invest(_ns, action) -> void:
	FirmCommands.invest(self, action)
