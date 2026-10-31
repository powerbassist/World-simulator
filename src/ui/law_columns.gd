extends RefCounted

## The Legislature catalogue's columns (law_list.gd), split out at V5.3-0 (b): the
## header row that names each column once, the theme as an icon, and the threshold
## as a figure. law_list.gd lays the rows out; this file draws what a row's cells
## and the header say.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Icon = preload("res://src/ui/icon.gd")
const Domains = preload("res://src/ui/domains.gd")
const LK = preload("res://src/sim/legislature_constants.gd")

const ICON_PX := 18
## The theme's icon, beside its word in Labels.LAW_THEME.
const THEME_ICONS := {
	"business": "corporate_fare.svg", "institutional": "account_balance.svg",
	"labour": "groups.svg", "social": "diversity_3.svg", "tax": "payments.svg",
}


## The column words, once: the law, the threshold, the forecast, the second
## chamber by its own name, the court. A blank cell below a header is said on the
## header's hover, so a blank never reads as a gap in the data.
static func header(box: HBoxContainer, ns, columns: Array, name_width: float, bar_width: float) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var law := _cell(Strings.t("Law"), UiTheme.MICRO, 0.0)
	law.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	law.custom_minimum_size.x = (name_width + columns[0]) * UiTheme.text_scale() + 10.0
	box.add_child(law)
	var needs := _cell(Strings.t("Needs"), UiTheme.MICRO, columns[1])
	needs.tooltip_text = Strings.t("The share of the seats the law needs, shown when it is more than half.")
	box.add_child(needs)
	var forecast := _cell(Strings.t("Forecast"), UiTheme.MICRO, 0.0)
	forecast.custom_minimum_size.x = bar_width
	forecast.tooltip_text = Strings.t("For, undecided and against. The line is the majority.")
	box.add_child(forecast)
	var upper := _cell(String(ns.upper_chamber_name), UiTheme.MICRO, columns[2])
	upper.tooltip_text = Strings.t("A blank means it is expected to agree.")
	box.add_child(upper)
	var court := _cell(Strings.t("Court"), UiTheme.MICRO, columns[3])
	court.tooltip_text = Strings.t("A blank means the court would let it stand, or does not review it.")
	box.add_child(court)
	for cell in [needs, forecast, upper, court]:
		cell.mouse_filter = Control.MOUSE_FILTER_PASS


## The theme as its icon, the word on hover: the icon's shape names the theme, so
## the column carries no colour of its own.
static func theme_icon(theme: String, width: float) -> Control:
	var icon := TextureRect.new()
	icon.texture = Icon.load_icon(Domains.ICONS + String(THEME_ICONS.get(theme, "checklist.svg")), UiTheme.TEXT_DIM, ICON_PX)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(width * UiTheme.text_scale(), ICON_PX)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.tooltip_text = PanelKit.Labels.law_theme(theme)
	return icon


## The threshold as a figure, and only when the line sits above half: a law an
## ordinary majority carries shows nothing (its phrase is in the detail).
static func threshold(share: float) -> String:
	if share <= LK.ABSOLUTE_MAJORITY_FRACTION + 1e-9:
		return ""
	for pair in [[2, 3], [3, 5], [3, 4]]:
		if absf(share - float(pair[0]) / float(pair[1])) < 1e-6:
			return "%d/%d" % pair
	return "%s%%" % Num.f(share * 100.0, 0)


static func _cell(text: String, tone: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = tone
	label.custom_minimum_size.x = width * UiTheme.text_scale()
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label
