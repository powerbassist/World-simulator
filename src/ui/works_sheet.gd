extends RefCounted

## The picked work's sheet (G3 S4 PR 2c, works-a-calendar.png): what it is and where, its four
## figures, who a start pleases and angers (the action's bloc_offset, shown nowhere before), what
## it does to the works' bill, and the screen's one filled button -- its Start, which applies at
## once (Projects.execute). A work being built is cancelled from its row (a ghost "Cancel…").

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const AnswerRow = preload("res://src/ui/answer_row.gd")
const WorksRows = preload("res://src/ui/works_rows.gd")

## The sheet's width at text size 100: the picture's 390.
const WIDTH := 390.0


## `go(action)` runs the Start; returns the sheet's body.
static func build(parent: Control, r: Dictionary, rows: Array, now: int, free_slots: int, go: Callable) -> VBoxContainer:
	var body := PanelKit.sheet(parent)
	var plate := body.get_parent() as Control
	plate.size_flags_horizontal = Control.SIZE_FILL
	plate.custom_minimum_size.x = roundf(WIDTH * UiTheme.text_scale())
	body.set_meta("works_sheet", String(r["id"]))
	var kind := String(r["state"])
	var kicker: String = {WorksRows.OFFER: Strings.t("On offer"), WorksRows.BUILDING: Strings.t("Being built")}.get(kind, Strings.t("Finished"))
	if String(r["region"]) != "":
		kicker = Strings.t("%s · %s") % [kicker, String(r["region"])]
	PanelKit.heading(body, kicker)
	var title := PanelKit.plain_line(body, String(r["name"]), PanelKit.Tone.PLAIN)  # i18n: row-ok translated in WorksRows (Strings.noun)
	title.theme_type_variation = UiTheme.LEAD
	if String(r["summary"]) != "":  # i18n: row-ok translated in WorksRows (Strings.row_summary)
		PanelKit.plain_line(body, String(r["summary"]))  # i18n: row-ok translated in WorksRows (Strings.row_summary)
	var tiles := GridContainer.new()
	tiles.columns = 2
	tiles.add_theme_constant_override("h_separation", 8)
	tiles.add_theme_constant_override("v_separation", 8)
	body.add_child(tiles)
	var opens := int(r["opens"])
	if kind != WorksRows.DONE:
		var months := int(r["left"]) if kind == WorksRows.BUILDING else int(r["months"])
		_figure(tiles, Strings.tn("%d month", "%d months", months) % months, Strings.t("opens %s") % _mon(opens))
		_figure(tiles, Strings.t("%s bn") % Num.f(float(r["cost_bn"]), 1), Strings.t("a year · %s %% of GDP") % Num.f(float(r["cost_pct"]), 3))
	_figure(tiles, Strings.t("+%s %%") % Num.f(float(r["growth_pct"]), 3), Strings.t("growth a year, once open"))
	if kind != WorksRows.DONE:
		_figure(tiles, Strings.t("%s bn") % Num.f(float(r["all_bn"]), 1), Strings.t("in all, over the build"))
	if kind == WorksRows.OFFER:
		_if_started(body, r, rows, now, free_slots)
	if kind == WorksRows.OFFER and r["start"] != null:
		var start := PanelKit.button(Strings.row_name("project-actions", r["start"]), PanelKit.Size.XL, PanelKit.BTN_H_MAIN)
		start.theme_type_variation = UiTheme.PRIMARY
		start.set_meta("works_go", String(r["id"]))
		start.pressed.connect(func() -> void: go.call(r["start"]))
		body.add_child(start)
		PanelKit.plain_line(body, Strings.t("At once; cancelling recovers nothing."))
	return body


## Who a start pleases and angers, and what it does to the bill and the slots.
static func _if_started(body: Control, r: Dictionary, rows: Array, now: int, free_slots: int) -> void:
	PanelKit.heading(body, Strings.t("If you start it"))
	AnswerRow.fill_who(AnswerRow.who_box(body), r["blocs"])
	PanelKit.plain_line(body, Strings.t("Works' bill: %s %% of GDP. No vote.") % Num.f(WorksRows.bill_at(rows, now, String(r["id"])), 2),
		PanelKit.Tone.PLAIN)
	PanelKit.plain_line(body, Strings.t("It takes the last free slot.") if free_slots == 1 else Strings.t("It takes a free slot."))
	PanelKit.plain_line(body, Strings.t("Its growth arrives over five years."))


static func _figure(parent: Control, value: String, caption: String) -> void:
	var tile := PanelKit.figure_tile(parent, value, caption)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func _mon(month: int) -> String:
	return DateText.mon_year((month - 1) % 12 + 1, (month - 1) / 12)
