extends RefCounted

## The Bills catalogue's bloc filter -- the laws a bloc likes, V5.3-0 (2.4): set by the briefing's
## bloc Go and the Society panel's "what calms it" row, cleared by this row's own button. Split from
## law_list.gd, which holds the list's rows; the filter is what it applies and the row that says so.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Labels = preload("res://src/ui/labels.gd")
const Strings = preload("res://src/ui/strings.gd")


## The laws a bloc likes -- a positive authored price for it -- the most liked first (ties keep the
## list's own order). The authored price is what the briefing's preview reads too (briefing.gd), so
## the filter and the bill's own page cannot disagree.
static func liked_by(laws: Array, bloc: String) -> Array:
	var liked := laws.filter(func(law) -> bool: return _offset(law, bloc) > 0.0)
	var order := range(liked.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return _offset(liked[a], bloc) > _offset(liked[b], bloc) or (_offset(liked[a], bloc) == _offset(liked[b], bloc) and a < b))
	return order.map(func(i: int): return liked[i])


static func _offset(law, bloc: String) -> float:
	return float((law.effects.get("bloc_offset", {}) as Dictionary).get(bloc, 0.0))


## The row above the list while the filter is on: which bloc, and the button that ends it.
static func row(list) -> void:
	var line := PanelKit.buttons(list._rows)
	var label := Label.new()
	label.text = Strings.t("Laws %s like") % Labels.bloc(list.bloc_filter)
	label.theme_type_variation = UiTheme.HEADING
	line.add_child(label)
	var clear := PanelKit.sized(Button.new())
	clear.text = Strings.t("Show every law")
	clear.pressed.connect(func() -> void:
		list.bloc_filter = ""
		list._panel.mark_dirty())
	line.add_child(clear)
