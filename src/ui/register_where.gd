extends RefCounted

## The register's WHERE sheet -- G3 S4, Register in C (register-in-c.png): the regions are the table. Each row is a
## region on the dot plot's one axis (ring = now, dot = once built), its figure, and its units set on the row itself
## (a stepper where units stand, a "+" where none do). The fills sit over it (by need, by population, or by hand), the
## band's legend and Who it moves under it. Moved out of register_panel.gd (the size ratchet); it reads the panel's
## own state and writes it back through the panel, as the order form always did.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const RegisterLines = preload("res://src/ui/register_lines.gd")
const Units = preload("res://src/sim/units.gd")
const UK = preload("res://src/sim/units_constants.gd")

const ROW := 32.0  ## a row holds a stepper: taller than the plain dot plot's


## The page's head: what the screen is about (the picked region against the nation), the type's summary and what
## stands there now on one line, the type's segments at the right.
static func lede(panel, parent: Control, row: Dictionary, shown: Dictionary, nation: float) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	parent.add_child(line)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(words)
	var unit: String = panel._figure_unit(row)
	var lead := Label.new()
	lead.theme_type_variation = UiTheme.LEAD
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var here: String = panel._region
	if shown.has(here):
		lead.text = Strings.t("%s: %s %s; the nation %s.") % [panel._region_name(here), Num.f(float(shown[here]), 2), unit, Num.f(nation, 2)]
	else:
		lead.text = Strings.t("The nation: %s %s.") % [Num.f(nation, 2), unit]
	words.add_child(lead)
	var said := Strings.row_summary("units", row)
	# What stands there now, as the stock counts it: a count of establishments only where the source publishes one.
	if shown.has(here):
		var ns = panel._state.player()
		var units := Units.start_units(panel._loader, ns.id, panel._type, here)
		var capacity := PanelKit.pop_text(Units.start_capacity(panel._loader, ns.id, panel._type, here))
		said += " " + (Strings.tn("Standing there now: %d establishment, a capacity of %s.", "Standing there now: %d establishments, a capacity of %s.", units) % [units, capacity] if units > 0 \
			else Strings.t("Standing there now: a capacity of %s; no count of establishments is published.") % capacity)
	var summary := PanelKit.plain_line(words, said, PanelKit.Tone.DIM)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.set_meta("stock", true)
	var types := HBoxContainer.new()
	types.add_theme_constant_override("separation", 10)
	types.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(types)
	var build := PanelKit.plain_line(types, Strings.t("Build").to_upper(), PanelKit.Tone.DIM)
	build.theme_type_variation = UiTheme.MICRO
	build.autowrap_mode = TextServer.AUTOWRAP_OFF
	build.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# One choice among the catalogue's types: a new type in data/units/ is a new segment, nothing here names one.
	var options: Array = []
	for type_id in panel._offered():
		options.append({"id": type_id, "label": Strings.row_name("units", Units.row(panel._loader, type_id))})
	var segments := PanelKit.segmented(types, options, panel._type, func(id: String) -> void:
		# A group still emits pressed on the picked segment: re-picking it must not wipe the rows.
		if id == panel._type:
			return
		panel._pick_type(id)
		panel._dirty = true)
	for b in segments.get_children():
		b.set_meta("type_chip", String(b.get_meta("segment")))


## The WHERE sheet: the fills, the table, the legend, then Who it moves on its own ground.
static func build(panel, parent: Control, ns, row: Dictionary, shown: Dictionary, after: Dictionary, nation: float) -> void:
	var body := PanelKit.sheet(parent)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var band: Dictionary = Units.band(ns, panel._loader, panel._type)
	_fills(panel, body)
	var data: Array = []
	for region in panel._loader.regions.get(ns.id, []):
		var id := String(region.id)
		if shown.has(id):
			data.append({"id": id, "label": String(region.region_name), "before": float(shown[id]),
				"after": float(after.get(id, shown[id])), "moved": int(panel._placed.get(id, 0)) > 0, "selected": id == panel._region})
	# Worst first, by the figure's own direction: the regions the sheet exists for lead.
	var lower_better := String((row.get("figure", {}) as Dictionary).get("better", "")) == "lower"
	data.sort_custom(func(a, b): return float(a["before"]) > float(b["before"]) if lower_better else float(a["before"]) < float(b["before"]))
	var table := HBoxContainer.new()
	table.add_theme_constant_override("separation", 8)
	body.add_child(table)
	var box := ChartKit.dots(table, "", data, {"reference": nation, "band": RegisterLines.band_range(band, shown), "row": ROW,
		"head": {"label": Strings.t("Region"), "value": Strings.t("Now → built"), "reference": Strings.t("the nation %s")}})
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.get_child(0).hide()  # the plot's own title: the head row names its columns, and the units column starts level with it
	var dots = box.get_meta("chart")
	dots.set_meta("dots", true)
	dots.picked.connect(func(id: String) -> void:
		panel._region = id
		panel._dirty = true)
	_units(panel, table, data, dots.row_height())
	_legend(body, band)
	if panel.rows().is_empty():
		return  # nothing placed: the programme sheet and the greyed press say so once
	var who := PanelContainer.new()
	who.theme_type_variation = UiTheme.TILE_PANEL
	body.add_child(who)
	var col := VBoxContainer.new()
	who.add_child(col)
	PanelKit.heading(col, Strings.t("Who it moves"))
	_who(panel, col, row, shown, after)


## By need or by population (each refills the programme's count); by hand, a row's own stepper or "+".
static func _fills(panel, body: Control) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	body.add_child(line)
	var where := PanelKit.plain_line(line, Strings.t("Where").to_upper(), PanelKit.Tone.DIM)
	where.theme_type_variation = UiTheme.MICRO
	where.autowrap_mode = TextServer.AUTOWRAP_OFF
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for pair in [["need", Strings.t("By need")], ["population", Strings.t("By population")]]:
		var b := PanelKit.toggle(PanelKit.sized(Button.new()))
		b.text = String(pair[1])
		var mode := String(pair[0])
		b.button_pressed = panel._fill_mode == mode
		b.set_meta("fill", mode)
		b.pressed.connect(func() -> void:
			panel._fill_mode = mode
			panel._fill(mode == "need")
			panel._dirty = true)
		line.add_child(b)


## The units column beside the table, one control a row in the table's order: a stepper where the programme places
## units, a "+" where it places none.
static func _units(panel, table: Control, data: Array, h: float) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	table.add_child(col)
	var head := PanelKit.plain_line(col, Strings.t("Units").to_upper(), PanelKit.Tone.DIM)
	head.theme_type_variation = UiTheme.MICRO
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.custom_minimum_size.y = h
	for d in data:
		var id := String(d["id"])
		var cell := CenterContainer.new()
		cell.custom_minimum_size = Vector2(96.0 * UiTheme.text_scale(), h)
		col.add_child(cell)
		if int(panel._placed.get(id, 0)) > 0:
			var units := SpinBox.new()
			units.min_value = 0
			units.max_value = panel.COUNT_MAX
			units.value = int(panel._placed[id])
			units.set_meta("region_units", id)
			units.value_changed.connect(func(v: float) -> void:
				# The rows together never pass the count's own ceiling.
				panel._placed[id] = mini(int(v), panel.COUNT_MAX - (panel._sum() - int(panel._placed.get(id, 0))))
				panel._count = maxi(1, panel._sum())
				panel._fill_mode = ""
				panel._dirty = true)
			cell.add_child(units)
		else:
			var add := Button.new()
			add.theme_type_variation = UiTheme.GHOST
			add.text = "+"  # i18n: ok a glyph
			add.tooltip_text = Strings.t("Add a unit in %s") % String(d["label"])  # i18n: row-ok the region's shown name, built above
			add.set_meta("region_add", id)
			add.pressed.connect(func() -> void:
				panel._placed[id] = 1
				panel._region = id
				panel._count = maxi(1, panel._sum())
				panel._fill_mode = ""
				panel._dirty = true)
			cell.add_child(add)


## The band's shade said under the table, as its rule with its glyph (the tone never alone). The plot's two marks
## need no key: the head names the column "Now -> built" and each row prints both figures.
static func _legend(body: Control, band: Dictionary) -> void:
	var line := HBoxContainer.new()
	body.add_child(line)
	RegisterLines.band_chip(line, band)
	for label in line.find_children("*", "Label", true, false):  # i18n: ok a class name
		(label as Label).autowrap_mode = TextServer.AUTOWRAP_OFF  # the rule on one line


## The picked region before and after, and the most any other region gives back.
static func _who(panel, col: VBoxContainer, row: Dictionary, shown: Dictionary, after: Dictionary) -> void:
	var rows: Array = panel.rows()
	var here: String = panel._region if int(panel._placed.get(panel._region, 0)) > 0 else (String(rows[0]["region"]) if not rows.is_empty() else "")
	if here == "" or not shown.has(here):
		PanelKit.plain_line(col, Strings.t("Place at least one unit."), PanelKit.Tone.DIM)
		return
	PanelKit.plain_line(col, Strings.t("%s: %s → %s %s.") % [panel._region_name(here), Num.f(float(shown[here]), 2),
		Num.f(float(after[here]), 2), panel._figure_unit(row)], PanelKit.Tone.PLAIN)
	var back := 0.0
	for id in shown:
		if int(panel._placed.get(id, 0)) <= 0:
			back = maxf(back, absf(float(after[id]) - float(shown[id])))
	PanelKit.plain_line(col, Strings.t("The other regions give back up to %s: the nation's figure moves only with the money on its line.") % Num.f(back, 2), PanelKit.Tone.DIM)
	RegisterLines.blocs(col, panel._state.player(), panel._loader, {"type": panel._type, "op": UK.OP_BUILD, "rows": rows})
