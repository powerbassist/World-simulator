extends SceneTree

## Headless test: godot --headless --script res://tests/test_economy_legend.gd
## Non-zero exit on any failure.
##
## V5.3-0 gate G3, the author: "des chiffres ne correspondent pas, solde budgetaire
## different entre la barre du haut et celui du panneau économie ... cest confus
## car il n'y a pas de legende". The top bar's BUDGET BALANCE (-0,99 %) and the
## panel header (-0,09 %) were never the same figure: the header was GROWTH, with
## no caption. And the panel's own balance said "deficit" over a signed balance,
## at one decimal against the bar's two, so even the right figure read different.
##
## Pinned: every figure in the panel's headline carries its caption, and the
## panel's balance prints exactly the top bar's text under the bar's own name.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const EconomyPanel = preload("res://src/ui/economy_panel.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")

var _failures: Array[String] = []
var _panel
var _state
var _loader
var _frame := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_state = GameState.new_game(_loader, "FRA")
	var ns = _state.player()
	# Off the start values, so a growth and a balance cannot coincide by rounding.
	ns.growth_annual_pct = -0.09
	ns.deficit_pct_gdp = 0.987
	_panel = EconomyPanel.new()
	root.add_child(_panel)
	_panel.setup(_state, _loader)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_panel._refresh()
	_run()
	_finish()
	return false


func _run() -> void:
	var ns = _state.player()
	var growth := "%s%%" % Num.fs(ns.growth_annual_pct, 2)
	var growth_box = _figure_box(growth)
	if growth_box == null:
		_fail("the growth figure '%s' is not a captioned figure in the panel" % growth)
	elif _caption(growth_box).is_empty():
		_fail("the growth figure has no caption")

	var bar: String = String(StripReadings.read("deficit", _state, _loader)["text"])
	var balance_box = _figure_box(bar)
	if balance_box == null:
		_fail("the panel's budget balance does not print the top bar's '%s'" % bar)
	elif not _caption(balance_box).to_lower().begins_with(_panel.tr(StripReadings.CAPTIONS["deficit"]).to_lower()):
		_fail("the panel's balance is captioned '%s', not the top bar's name" % _caption(balance_box))

	# No headline figure left bare: every LEAD or FIGURE label holding a digit sits
	# in a box with a caption.
	for label in _labels(_panel):
		if label.theme_type_variation in [UiTheme.FIGURE, UiTheme.LEAD] and _has_digit(label.text):
			if _caption(label.get_parent()).is_empty():
				_fail("the headline figure '%s' has no caption" % label.text)


func _figure_box(value: String):
	for label in _labels(_panel):
		if label.text == value and label.theme_type_variation == UiTheme.FIGURE:
			return label.get_parent()
	return null


func _caption(box) -> String:
	if box == null:
		return ""
	for child in box.get_children():
		if child is Label and child.theme_type_variation == UiTheme.FIGURE_LABEL:
			return String(child.text)
	return ""


func _labels(node: Node) -> Array:
	var out: Array = []
	if node is Label and not node.is_queued_for_deletion():
		out.append(node)
	for child in node.get_children():
		out.append_array(_labels(child))
	return out


func _has_digit(text: String) -> bool:
	for c in text:
		if c >= "0" and c <= "9":
			return true
	return false


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: " + message)


func _finish() -> void:
	for f in _failures:
		print("FAIL: " + f)
	print("test_economy_legend: %d failures" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
