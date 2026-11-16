extends RefCounted

## What a sector makes, drawn on its tab -- V5.3 screen 5 (the author's C, "les produits").
## The rows are SectorGoods' (which goods, in which order, the shortage line); this file
## only draws them: chips that filter the table to one good, then per good its price over
## the months the ring holds, its trade a year at this month's pace, which major makes it and a "short" mark.
## Moved out of sector_panel.gd at slice 2, when the firm sheet joined the tab.

const SectorGoods = preload("res://src/ui/sector_goods.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")


static func build(panel, parent: Control, ns) -> void:
	var state = panel._state
	var loader = panel._loader
	var sector: String = panel.sector
	var all: Array = SectorGoods.rows_all(state, loader, ns, sector)
	var section := PanelKit.section(parent, Strings.t("What it makes"))
	if all.is_empty():
		PanelKit.plain_line(section, Strings.t("Nothing in the goods register is made here yet."))
		return
	var shown: Array = all.slice(0, SectorGoods.MAX_ROWS)
	# A good filtered on that left the rows since (a month on) would empty the table under its headings, no chip pressed.
	if not shown.any(func(row: Dictionary) -> bool: return String(row["good_id"]) == panel._good_filter):
		panel._good_filter = ""
	var chips := PanelKit.buttons(section)
	_chip(panel, chips, "", Strings.t("All · %d") % shown.size())
	for row in shown:
		_chip(panel, chips, String(row["good_id"]), String(row["name"]))  # i18n: row-ok a good's name, translated in SectorGoods.rows()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", PanelKit.COLUMN_SEPARATION)
	section.add_child(grid)
	var months := int(shown[0]["months"])
	for caption in ["", Strings.t("Price, %d months") % months if months >= 2 else Strings.t("Price"), Strings.t("Trade, a year at this pace"), Strings.t("Made by")]:
		var head := Label.new()
		head.text = caption
		head.theme_type_variation = UiTheme.CAPTION
		grid.add_child(head)
	for row in shown:
		if panel._good_filter != "" and panel._good_filter != String(row["good_id"]):
			continue
		_good_row(grid, row)
	if all.size() > shown.size():
		PanelKit.plain_line(section, Strings.tn("and %d more good", "and %d more goods", all.size() - shown.size()) % (all.size() - shown.size()))


static func _chip(panel, parent: Control, good_id: String, text: String) -> void:
	var chip := PanelKit.sized(Button.new())
	chip.text = text
	chip.toggle_mode = true
	chip.button_pressed = panel._good_filter == good_id
	chip.set_meta("good", good_id)
	chip.pressed.connect(func() -> void:
		panel._good_filter = good_id
		panel._dirty = true)
	parent.add_child(chip)


static func _good_row(grid: GridContainer, row: Dictionary) -> void:
	var name_box := PanelKit.buttons(grid)
	PanelKit.plain_line(name_box, String(row["name"]), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF  # i18n: row-ok a good's name, translated in SectorGoods.rows()
	if bool(row["short"]):
		var short := PanelKit.plain_line(name_box, Strings.t("short"), PanelKit.Tone.PLAIN)
		short.theme_type_variation = UiTheme.WARN_TEXT
	var change := float(row["change"])
	var price := Label.new()
	price.text = PanelKit.MISSING if is_nan(change) else Strings.t("%s %%") % Num.fs(change, 1)
	grid.add_child(price)
	var trade := float(row["trade_eur_bn_year"])
	var trade_label := Label.new()
	if absf(trade) < 0.05:
		trade_label.text = PanelKit.MISSING
	else:
		trade_label.text = (Strings.t("surplus %s bn") if trade > 0.0 else Strings.t("deficit %s bn")) % Num.f(absf(trade), 1)
		trade_label.theme_type_variation = UiTheme.GOOD_TEXT if trade > 0.0 else UiTheme.BAD_TEXT
	grid.add_child(trade_label)
	var makers := PackedStringArray()
	for company in row["makers"]:
		makers.append(company.company_name)
	var made_by := Label.new()
	made_by.text = ", ".join(makers) if not makers.is_empty() else PanelKit.MISSING
	grid.add_child(made_by)
