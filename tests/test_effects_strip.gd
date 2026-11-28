extends SceneTree

## Headless test: godot --headless --script res://tests/test_effects_strip.gd
## Non-zero exit on any failure.
##
## V5.3 a + b step 1, docs/design/v5.3-ab.md 2.1: the balance effect beside every lever, now on the Books rows (the
## Budget and Tax Code tabs retired with Finances slice 5, and these fixtures moved with their levers).
##
## Band B1 (spec section 9): for every spending line and every tax rate, the change a row prints before the bill
## is tabled equals the difference between Budget.preview() with nothing pending right after the bill is carried
## and right before it, in the same month, to the cent; GOOD only on a balance gain. One fixture per line and per
## rate. The booked figure is computed here from the two previews, never through the strip's own arithmetic, so a
## strip that priced the wrong books fails rather than agreeing with itself. Then two rows at once: the footer's
## totals are what the bill books on each side.
##
## Driven the way the page is: the row opened, the editor's slider moved, the footer's own tabling.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const C = preload("res://src/sim/economy_constants.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Division = preload("res://src/sim/division.gd")
const Strings = preload("res://src/ui/strings.gd")

## Half a cent of a billion: the shown and the booked figure are one computation
## on the same books, so anything past rounding noise is a different number.
const CENT_BN := 0.005

var _failures: Array[String] = []
var _loader
var _state
var _panel
var _frame := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	Strings.set_language("en")
	_panel = FinancesPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_panel.show()
			_panel.size = Vector2(1240, 820)
			_state = GameState.new_game(_loader, "FRA")
			_panel.setup(_state, _loader)
		3:
			_check_a_sum_scales_its_unit()
			_check_untouched()
			_check_the_spending_lines()
			_check_the_tax_rates()
			_check_two_rows()
			_finish()
	return false


## Each snapshot's own deficit in euros, the balance being its negative.
func _balance_gain(before: Dictionary, after: Dictionary) -> float:
	return (float(before["deficit_pct_gdp"]) * float(before["gdp_eur_bn"])
		- float(after["deficit_pct_gdp"]) * float(after["gdp_eur_bn"])) / 100.0


## A figure moved inside its reach, the direction away from the nearer bound.
func _target(value: float, low: float, high: float, step: float) -> float:
	return value + step if value + step <= high else value - step


func _check_tone(label: Label, gain: float, what: String) -> void:
	var want := UiTheme.GOOD_TEXT if gain >= 0.05 else (UiTheme.BAD_TEXT if gain <= -0.05 else "")
	if label.theme_type_variation != want:
		_fail("%s: a balance effect of %.3f bn wears '%s', expected '%s' (GOOD only on a gain)" % [
			what, gain, label.theme_type_variation, want])


func _open(channel: String, key: String) -> void:
	_panel._open_id = FinanceRows.row_id(channel, key)
	_panel._stamp = ""
	_panel._dirty = true
	_panel._process(0.0)


## The author's pick (2026-11-28): a sum's unit scales by itself, bn, m, then k, and a sum that is not zero never
## prints as one (to half a thousand euros).
func _check_a_sum_scales_its_unit() -> void:
	for case in [[-1.26, "-1.3 bn"], [0.1, "+0.1 bn"], [-0.04, "-40 m"], [0.023, "+23 m"], [0.0006, "+1 m"],
			[0.0005, "+500 k"], [0.00001, "+10 k"], [-0.000001, "-1 k"], [-0.0000004, "0 k"], [0.0, "0 k"]]:
		var said := EffectsStrip.sum_text(float(case[0]))
		if said != String(case[1]):
			_fail("%.7f bn reads '%s', want '%s'" % [float(case[0]), said, case[1]])


## Nothing moved, nothing printed: an opened row says no effect and a dragged-back one says none either.
func _check_untouched() -> void:
	for key in C.SPENDING_KEYS:
		_open(FinanceDraft.SPENDING, key)
		var editor = _panel._editor
		if editor.get_node("Effect").text != "":
			_fail("%s shows '%s' with nothing moved" % [key, editor.get_node("Effect").text])
		var live := float(_state.player().spending_pct_gdp[key])
		editor._slider.value = _target(live, editor._lo, editor._hi, 1.0)
		editor._slider.value = live
		if editor.get_node("Effect").text != "":
			_fail("%s shows '%s' after the lever went back" % [key, editor.get_node("Effect").text])
	_panel._draft.revert()


## B1 per line: move it, read what the row prints, table and carry the bill, read what booked.
func _check_the_spending_lines() -> void:
	for key in C.SPENDING_KEYS:
		_open(FinanceDraft.SPENDING, key)
		var editor = _panel._editor
		var live := float(_state.player().spending_pct_gdp[key])
		editor._slider.value = _target(live, editor._lo, editor._hi, 1.0)
		_check_booked(editor, "spending %s" % key)


func _check_the_tax_rates() -> void:
	for key in _state.player().tax_rates_pct:
		_open(FinanceDraft.TAX, String(key))
		var editor = _panel._editor
		if editor == null or editor._slider == null:
			continue
		var step: float = editor._slider.step * 2.0
		editor._slider.value = _target(editor._slider.value, editor._lo, editor._hi, step)
		if not _panel._draft.is_moved(FinanceDraft.TAX, String(key)):
			continue  # a kind the grid leaves where it is has no change to price
		_check_booked(editor, "tax %s" % key)
	# The brackets are a lever of the income tax: its own row of the same draft.
	_open(FinanceDraft.TAX, "income")
	var income = _panel._editor
	if income._brackets != null:
		income._brackets.value = _target(income._brackets.value, income._brackets.min_value, income._brackets.max_value,
			(TaxK.PROGRESSIVITY_MAX - TaxK.PROGRESSIVITY_MIN) * 0.1)
		_check_booked(income, "tax brackets")


## What the open row prints against what the footer's own tabling books once the Assembly has divided.
func _check_booked(editor, what: String) -> void:
	var shown: float = _panel._price.balance_bn(_panel._draft.pending())
	var text: String = editor.get_node("Effect").text
	var before := Budget.preview(_state, {})
	_panel._on_table()
	_vote(_state)
	var booked := _balance_gain(before, Budget.preview(_state, {}))
	if is_zero_approx(booked):
		_fail("%s: the fixture moved nothing on the books; pick a bigger step" % what)
	if absf(shown - booked) > CENT_BN:
		_fail("%s: shown %.4f bn, booked %.4f bn" % [what, shown, booked])
	if not text.contains(EffectsStrip.money_text(booked)):
		_fail("%s: the row reads '%s', the booked change prints '%s'" % [what, text, EffectsStrip.money_text(booked)])
	_check_tone(editor.get_node("Effect"), booked, what)
	_panel.mark_dirty()
	_panel._process(0.0)


## Two rows at once: the footer's totals are what the bill books on each side of the books.
func _check_two_rows() -> void:
	var ns = _state.player()
	_panel._draft.revert()
	_panel._draft.set_value(FinanceDraft.SPENDING, "health", float(ns.spending_pct_gdp["health"]) + 1.0)
	_panel._draft.set_value(FinanceDraft.SPENDING, "education", float(ns.spending_pct_gdp["education"]) - 0.5)
	var whole: Dictionary = _panel._price.whole(_loader, _panel._draft, false)
	var before := Budget.preview(_state, {})
	_panel._on_table()
	_vote(_state)
	var after := Budget.preview(_state, {})
	var spend_bn := (float(after["total_spending_pct_gdp"]) * float(after["gdp_eur_bn"])
		- float(before["total_spending_pct_gdp"]) * float(before["gdp_eur_bn"])) / 100.0
	if absf(float(whole["spending_bn"]) - spend_bn) > CENT_BN:
		_fail("two rows: the footer says spending %.4f bn, the bill booked %.4f bn" % [whole["spending_bn"], spend_bn])
	var revenue_bn := (float(after["total_revenue_pct_gdp"]) * float(after["gdp_eur_bn"])
		- float(before["total_revenue_pct_gdp"]) * float(before["gdp_eur_bn"])) / 100.0
	if absf(float(whole["revenue_bn"]) - revenue_bn) > CENT_BN:
		_fail("two rows: the footer says revenue %.4f bn, the bill booked %.4f bn" % [whole["revenue_bn"], revenue_bn])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_effects_strip: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)


## The bill is voted at the month's end; the books move at its division. The fixture's bills are France's at the
## start, which carry. A month's end is also what tells every window the state moved.
func _vote(state) -> void:
	var result: Dictionary = Division.divide(state, _loader)
	if not result.is_empty() and not bool(result.get("passed", false)):
		_fail("the fixture's finance bill was not carried: %s" % [result])
