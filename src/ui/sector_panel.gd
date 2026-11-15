extends PanelContainer

## One sector's tab in the Sectors domain -- V5.3 screen 5, slice 1, the author's pick
## C ("les produits"). Read only: the head (verdict, lead sentence, four figures), what
## waits on the player in this sector, what the sector makes good by good, its majors.
## The verbs (the programme through the finance bill, the firm sheet, a right click)
## are slice 2; until then a Needs you row's Go opens the overview (the window
## "companies") with the firm opened, where today's answers live.
##
## Every figure is a reader's (SectorRead, SectorGoods, SectorNeeds); what the pictures
## staged without one is cut: a major's 12-month change (the sim keeps no series per
## firm) and "smaller firms" as a good's maker (body firms carry no products).

signal go_firm(sector: String, company_id: String)

const SectorRead = preload("res://src/ui/sector_read.gd")
const SectorGoods = preload("res://src/ui/sector_goods.gd")
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


func _init(sector_id := "") -> void:
	sector = sector_id


func _ready() -> void:
	custom_minimum_size = Vector2(560, 560)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)
	var scroll := ScrollContainer.new()
	# EXPAND: the page then fills the dock (tab_page._scrolls_inside), lists scroll inside.
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	# The bar draws over the content: the right-aligned figures keep clear of it.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	scroll.add_child(gutter)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	gutter.add_child(_body)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func hide_close_button() -> void:
	pass


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	for child in _body.get_children():
		child.queue_free()
	_head(ns)
	_needs(ns)
	_goods(ns)
	_majors(ns)


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
		go.pressed.connect(func() -> void: go_firm.emit(sector, company_id))
		row.add_child(go)


func _need_line(ns, item: Dictionary) -> String:
	if String(item["kind"]) != "closure":
		return tr(String(NEED_WORDS[item["kind"]]))  # i18n: row-ok the table's msgids
	var row: Dictionary = (ns.companies.get(String(item["company_id"]), {}) as Dictionary).get("closure", {})
	var city = Region.find_city(_loader.regions.get(ns.id, []), String(row.get("city_id", "")))
	var jobs := CompanyVerb.thousands(float(row.get("jobs", 0.0)))
	if city == null:
		return tr("Closes a plant · %s jobs") % jobs
	return tr("Closes its %s plant · %s jobs") % [String(city.city_name), jobs]


func _goods(ns) -> void:
	var all: Array = SectorGoods.rows_all(_state, _loader, ns, sector)
	var section := PanelKit.section(_body, tr("What it makes"))
	if all.is_empty():
		PanelKit.plain_line(section, tr("Nothing in the goods register is made here yet."))
		return
	var shown: Array = all.slice(0, SectorGoods.MAX_ROWS)
	var chips := PanelKit.buttons(section)
	_chip(chips, "", tr("All · %d") % shown.size())
	for row in shown:
		_chip(chips, String(row["good_id"]), String(row["name"]))  # i18n: row-ok a good's name: the goods register has no translation table yet
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", PanelKit.COLUMN_SEPARATION)
	section.add_child(grid)
	var months := int(shown[0]["months"])
	for caption in ["", tr("Price, %d months") % months if months >= 2 else tr("Price"), tr("Trade, this month"), tr("Made by")]:
		var head := Label.new()
		head.text = caption
		head.theme_type_variation = UiTheme.CAPTION
		grid.add_child(head)
	for row in shown:
		if _good_filter != "" and _good_filter != String(row["good_id"]):
			continue
		_good_row(grid, row)
	if all.size() > shown.size():
		PanelKit.plain_line(section, tr_n("and %d more good", "and %d more goods", all.size() - shown.size()) % (all.size() - shown.size()))


func _chip(parent: Control, good_id: String, text: String) -> void:
	var chip := PanelKit.sized(Button.new())
	chip.text = text
	chip.toggle_mode = true
	chip.button_pressed = _good_filter == good_id
	chip.set_meta("good", good_id)
	chip.pressed.connect(func() -> void:
		_good_filter = good_id
		_dirty = true)
	parent.add_child(chip)


func _good_row(grid: GridContainer, row: Dictionary) -> void:
	var name_box := PanelKit.buttons(grid)
	PanelKit.plain_line(name_box, String(row["name"]), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF  # i18n: row-ok a good's name, as above
	if bool(row["short"]):
		var short := PanelKit.plain_line(name_box, tr("short"), PanelKit.Tone.PLAIN)
		short.theme_type_variation = UiTheme.WARN_TEXT
	var change := float(row["change"])
	var price := Label.new()
	price.text = PanelKit.MISSING if is_nan(change) else tr("%s %%") % Num.fs(change, 1)
	grid.add_child(price)
	var trade := float(row["trade_eur_bn_year"])
	var trade_label := Label.new()
	if absf(trade) < 0.05:
		trade_label.text = PanelKit.MISSING
	else:
		trade_label.text = (tr("surplus %s bn") if trade > 0.0 else tr("deficit %s bn")) % Num.f(absf(trade), 1)
		trade_label.theme_type_variation = UiTheme.GOOD_TEXT if trade > 0.0 else UiTheme.BAD_TEXT
	grid.add_child(trade_label)
	var makers := PackedStringArray()
	for company in row["makers"]:
		makers.append(company.company_name)
	var made_by := Label.new()
	made_by.text = ", ".join(makers) if not makers.is_empty() else PanelKit.MISSING
	grid.add_child(made_by)


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
		PanelKit.plain_line(words, company.company_name, PanelKit.Tone.PLAIN)
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
