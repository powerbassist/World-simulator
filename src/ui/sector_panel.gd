extends PanelContainer

## One sector's tab in the Sectors domain -- V5.3 screen 5, the author's pick C ("les
## produits"). Left: the head (verdict, lead sentence, four figures) and the sector's
## programme as a finance-bill row (sector_programme.gd), what waits on the player, what
## the sector makes good by good (sector_goods_view.gd), its majors. Right: the selected
## firm's sheet (firm_sheet.gd) with its file and the State's verbs (slice 2).
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
const IndustryVerbs = preload("res://src/ui/industry_verbs.gd")
const VerbPlate = preload("res://src/ui/verb_plate.gd")
const Strings = preload("res://src/ui/strings.gd")
const Processes = preload("res://src/sim/processes.gd")

## The sheet's width in px: the picture's right column.
const SHEET_WIDTH := 440

const FACE := Vector2(28, 38)
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
## The good the chips filter the table to, "" for all of them.
var _good_filter := ""
var _sheet: VBoxContainer
## The firm on the sheet, "" for the default (the first waiting, else the first major).
var _firm_id := ""
## firm_commands.gd's state: the focused verb, the card an irreversible verb asks on, the
## last refusal, the programme stop picked on the slider (-1: as it stands).
var _focus_verb := ""
var _confirm
var _last_refusal := ""
var _prog_pick := -1
## The programme's slider is held: a rebuild under the drag would free it (sector_programme.gd).
var _dragging := false


func _init(sector_id := "") -> void:
	sector = sector_id


func _ready() -> void:
	custom_minimum_size = Vector2(560, 560)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	margin.add_child(columns)
	_body = _column(columns, Control.SIZE_EXPAND_FILL)
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
	# The bar draws over the content: the right-aligned figures keep clear of it.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	scroll.add_child(gutter)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	gutter.add_child(box)
	return box


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true
	# A setup() after the first is a load: the discarded game's picks go with it (the retro review's item 7). The confirm
	# card stays: it sits on the screen stack once and is re-armed by each ask (CompanyVerb.ask).
	_good_filter = ""
	_firm_id = ""
	_focus_verb = ""
	_last_refusal = ""
	_prog_pick = -1
	_dragging = false


func mark_dirty() -> void:
	_dirty = true


## A tab hidden under a held slider never sees the release: the hold ends with it, or the tab stays frozen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_dragging = false


func hide_close_button() -> void:
	pass


func _process(_delta: float) -> void:
	if not _dirty or _dragging or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	for child in _body.get_children() + _sheet.get_children():
		child.queue_free()
	_head(ns)
	_needs(ns)
	SectorGoodsView.build(self, _body, ns)
	_majors(ns)
	var company = _selected(ns)
	if company != null:
		FirmSheet.build(self, _sheet, ns, company)


func _head(ns) -> void:
	var reading := SectorRead.head(_state, _loader, ns, sector)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", PanelKit.SECTION_SEPARATION)
	_body.add_child(box)
	var top := PanelKit.buttons(box)
	var name_label := PanelKit.plain_line(top, Labels.sector(sector), PanelKit.Tone.PLAIN)
	name_label.theme_type_variation = UiTheme.HEADING
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var tag := PanelKit.plain_line(top, SectorRead.verdict_words(String(reading["verdict"])), PanelKit.Tone.PLAIN)
	tag.theme_type_variation = String(VERDICT_TONE[reading["verdict"]])
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	var lead := PanelKit.plain_line(box, SectorRead.lead(reading, func(v: float) -> String: return Num.fs(v, 1)), PanelKit.Tone.PLAIN)
	lead.theme_type_variation = UiTheme.LEAD
	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 28)
	box.add_child(figures)
	PanelKit.figure(figures, tr("%s bn") % Num.f(float(reading["output"]), 0), tr("Output"))
	PanelKit.figure(figures, CompanyVerb.thousands(float(reading["jobs"])), tr("Jobs"))
	PanelKit.figure(figures, tr("%s %%") % Num.fs(float(reading["trend"]), 1), tr("Trend a year"))
	PanelKit.figure(figures, tr("%s %%") % Num.f(float(reading["of_gdp"]), 1), tr("Of GDP"))
	SectorProgramme.build(self, box, ns, sector)


func _needs(ns) -> void:
	var mine: Array = []
	for item in SectorNeeds.items(_state, _loader, ns):
		if String(item["sector"]) == sector:
			mine.append(item)
	# Nothing waiting, no section: the tab's hourglass already says so (the text diet).
	if mine.is_empty():
		return
	var section := PanelKit.section(_body, tr("Needs you · %d") % mine.size())
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
	var section := PanelKit.section(_body, tr("The majors · %d") % majors.size())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", PanelKit.SECTION_SEPARATION)
	section.add_child(grid)
	for company in majors:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", PanelKit.COLUMN_SEPARATION)
		grid.add_child(cell)
		cell.add_child(Portrait.control_for(String(company.chief_id), FACE))
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(words)
		var pick := PanelKit.sized(Button.new())
		pick.flat = true
		pick.toggle_mode = true
		pick.text = company.company_name
		pick.button_pressed = _selected(ns) == company
		pick.set_meta("firm", String(company.id))
		pick.pressed.connect(_select.bind(String(company.id)))
		# The name is the largest target and stops the event before the cell: it answers
		# the right click itself (QA's play of #381).
		pick.gui_input.connect(_right_click.bind(company))
		words.add_child(pick)
		cell.gui_input.connect(_right_click.bind(company))
		var city = Region.find_city(_loader.regions.get(ns.id, []), Companies.live_city_of(ns, company))
		var jobs := tr("%s jobs") % CompanyVerb.thousands(Companies.headcount(ns, company))
		PanelKit.plain_line(words, jobs if city == null else "%s · %s" % [String(city.city_name), jobs])
		if not Closures.announced(ns, String(company.id)).is_empty():
			var tag := PanelKit.plain_line(words, tr("closing a plant"), PanelKit.Tone.PLAIN)
			tag.theme_type_variation = UiTheme.BAD_TEXT


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


## The right click on a firm (H14): its verbs with their prices (a press selects the firm
## and focuses the verb on the sheet), the call to its chief, the map.
func _right_click(event: InputEvent, company) -> void:
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_RIGHT:
		return
	var plate = VerbPlate.of(self)
	if plate != null:
		plate.open(self, menu_items(company))


func menu_items(company) -> Array:
	var ns = _state.player()
	var id := String(company.id)
	var items: Array = []
	for action in Companies.available(_state, ns, _loader.company_actions, id, _loader):
		var est: Dictionary = Processes.estimate(_state, ns, _loader, action, id) if Processes.is_process(action) else {}
		var money: Array = IndustryVerbs.money_line(_state, _loader, ns, company, action, est)
		var why := CompanyVerb.refusal(_state, _loader, ns, company, action)
		var verb := String(action.id)
		items.append({"text": "%s · %s" % [Strings.row_name("company-actions", action), String(money[1])],
			"enabled": why == "", "reason": Strings.t(why) if why != "" else "",  # i18n: row-ok the sim's reason, its English the msgid
			"call": func() -> void:
				_select(id)
				_focus_verb = verb})
	var chief: String = _loader.person_name(String(company.chief_id))
	if chief != "":
		items.append({"text": tr("Call %s") % chief, "enabled": true, "call": func() -> void: call_requested.emit(String(company.chief_id))})
	var city = Region.find_city(_loader.regions.get(ns.id, []), Companies.live_city_of(ns, company))
	if city != null:
		items.append({"text": tr("Show on the map"), "enabled": true, "call": func() -> void: map_requested.emit(city.lonlat)})
	return items


# The commands, shared with the overview (firm_commands.gd).
func _on_act(ns, company, action) -> void:
	FirmCommands.act(self, ns, company, action)


func _on_closure(closure_id: String, answer_id: String, what: String) -> void:
	FirmCommands.closure(self, closure_id, answer_id, what)


func _on_invest(_ns, action) -> void:
	FirmCommands.invest(self, action)
