extends SceneTree

## Headless test: godot --headless --script res://tests/test_effects_strip.gd
## Non-zero exit on any failure.
##
## V5.3 a + b step 1, docs/design/v5.3-ab.md 2.1 and 4.1: the balance effect beside
## every lever of the Budget and every rate of the Tax Code, the Budget's change
## column, the Tax Code's yields, and the strip that says what Commit books.
##
## Band B1 (spec section 9): for every lever and every rate, the change printed
## before Commit equals the difference between Budget.preview() with nothing
## pending right after the commit and right before it, in the same month, to the
## cent; GOOD only on a balance gain. One fixture per lever and per rate, a born
## key included. The booked figure is computed here from the two previews, never
## through the strip's own arithmetic, so a strip that priced the wrong books
## fails rather than agreeing with itself.
##
## Driven a frame at a time: a Range outside the tree emits nothing (AGENTS.md).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const C = preload("res://src/sim/economy_constants.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")
const TaxPanel = preload("res://src/ui/tax_panel.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Half a cent of a billion: the shown and the booked figure are one computation
## on the same books, so anything past rounding noise is a different number.
const CENT_BN := 0.005

var _failures: Array[String] = []
var _loader
var _frame := 0
var _budget
var _tax
var _state_b
var _state_t


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_state_b = GameState.new_game(_loader, "FRA")
	_state_t = GameState.new_game(_loader, "FRA")
	_budget = BudgetPanel.new()
	root.add_child(_budget)
	_tax = TaxPanel.new()
	root.add_child(_tax)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_budget.setup(_state_b, _loader)
			_budget.show()
			_tax.setup(_state_t, _loader)
			_tax.show()
		2:
			_check_budget_untouched()
			_check_tax_untouched()
		3:
			_check_budget_levers()
			_check_budget_two_levers()
		4:
			_stage_born_key()
		5:
			_check_tax_yields()
			_check_tax_rates()
			_finish()
	return false


## Each snapshot's own deficit in euros, the balance being its negative.
func _balance_gain(before: Dictionary, after: Dictionary) -> float:
	return (float(before["deficit_pct_gdp"]) * float(before["gdp_eur_bn"])
		- float(after["deficit_pct_gdp"]) * float(after["gdp_eur_bn"])) / 100.0


## A lever moved inside its span, the direction away from the nearer bound.
func _target(value: float, low: float, high: float, step: float) -> float:
	return value + step if value + step <= high else value - step


func _check_tone(label: Label, gain: float, what: String) -> void:
	var want := UiTheme.GOOD_TEXT if gain >= 0.05 else (UiTheme.BAD_TEXT if gain <= -0.05 else "")
	if label.theme_type_variation != want:
		_fail("%s: a balance effect of %.3f bn wears '%s', expected '%s' (GOOD only on a gain)" % [
			what, gain, label.theme_type_variation, want])


func _check_budget_untouched() -> void:
	_budget._refresh()
	for key in C.SPENDING_KEYS:
		if _budget._effect_labels[key].text != "":
			_fail("budget: %s shows '%s' with nothing moved" % [key, _budget._effect_labels[key].text])
	if _budget._strip.visible:
		_fail("budget: the strip shows with nothing to commit")
	for key in ["revenue", "spending", "deficit"]:
		if String(_budget._figures[key][2][0]) != "—":
			_fail("budget: the %s change reads '%s' with nothing pending" % [key, _budget._figures[key][2][0]])


func _check_tax_untouched() -> void:
	_tax._refresh()
	for key in _tax._lever_keys():
		if _tax._effect_labels[key].text != "":
			_fail("tax: %s shows '%s' with nothing moved" % [key, _tax._effect_labels[key].text])
	if _tax._strip.visible:
		_fail("tax: the strip shows with nothing to commit")


## B1 per lever: move one, read what the panel prints, commit, read what booked.
func _check_budget_levers() -> void:
	for key in C.SPENDING_KEYS:
		var ns = _state_b.player()
		var live := float(ns.spending_pct_gdp[key])
		var span: Vector2 = _budget.lever_span(key)
		_budget._sliders[key].value = _target(live, span.x, span.y, 1.0)
		_budget._refresh()
		var shown: float = float(_budget._effects.get(key, NAN))
		var text: String = _budget._effect_labels[key].text
		var strip_bn: float = _budget._strip.money_bn
		var before := Budget.preview(_state_b, {})
		_budget._on_commit()
		var booked := _balance_gain(before, Budget.preview(_state_b, {}))
		if is_nan(shown) or absf(shown - booked) > CENT_BN:
			_fail("budget %s: shown %s bn, booked %.4f bn" % [key, shown, booked])
		if text != EffectsStrip.money_text(booked):
			_fail("budget %s: the cell reads '%s', the booked change prints '%s'" % [key, text, EffectsStrip.money_text(booked)])
		if absf(strip_bn - booked) > CENT_BN:
			_fail("budget %s: the strip says %.4f bn, Commit booked %.4f bn" % [key, strip_bn, booked])
		_check_tone(_budget._effect_labels[key], booked, "budget %s" % key)
		_budget._refresh()
		if _budget._effect_labels[key].text != "":
			_fail("budget %s: the cell still reads '%s' after the commit" % [key, _budget._effect_labels[key].text])


## Two levers at once: each prints its own effect, the strip and the deficit's
## change print what the commit of both books, and the change column is signed
## per row and toned on the balance.
func _check_budget_two_levers() -> void:
	var ns = _state_b.player()
	var singles := {}
	var moves := {"health": 1.0, "education": -0.5}
	for key in moves:
		var target := float(ns.spending_pct_gdp[key]) + float(moves[key])
		var alone := Budget.preview(_state_b, {"spending_pct_gdp": {key: target}})
		singles[key] = _balance_gain(Budget.preview(_state_b, {}), alone)
		_budget._sliders[key].value = target
	_budget._refresh()
	for key in moves:
		if absf(float(_budget._effects.get(key, NAN)) - float(singles[key])) > CENT_BN:
			_fail("budget two levers: %s prints %s bn, alone it books %.4f bn" % [key, _budget._effects.get(key), singles[key]])
	var before := Budget.preview(_state_b, {})
	var strip_bn: float = _budget._strip.money_bn
	var spending_cell: Array = _budget._figures["spending"][2]
	var deficit_cell: Array = _budget._figures["deficit"][2]
	_budget._on_commit()
	var after := Budget.preview(_state_b, {})
	var booked := _balance_gain(before, after)
	if absf(strip_bn - booked) > CENT_BN:
		_fail("budget two levers: the strip says %.4f bn, Commit booked %.4f bn" % [strip_bn, booked])
	var spend_bn := (float(after["total_spending_pct_gdp"]) * float(after["gdp_eur_bn"])
		- float(before["total_spending_pct_gdp"]) * float(before["gdp_eur_bn"])) / 100.0
	if spending_cell[0] != EffectsStrip.money_text(spend_bn):
		_fail("budget: the spending change reads '%s', the books moved %s" % [spending_cell[0], EffectsStrip.money_text(spend_bn)])
	if deficit_cell[0] != EffectsStrip.money_text(-booked):
		_fail("budget: the deficit change reads '%s', the books moved %s" % [deficit_cell[0], EffectsStrip.money_text(-booked)])
	# Health +1 point of GDP against education -0.5: spending rose by half a point
	# and the deficit with it, so both cells are BAD.
	var want: int = EffectsStrip.money_tone(-spend_bn)
	if spending_cell[1] != want or deficit_cell[1] != EffectsStrip.money_tone(booked):
		_fail("budget: the change cells are toned %s / %s, not on the balance's sign" % [spending_cell[1], deficit_cell[1]])


## A key the composition machine has born, staged on the register the way
## Legislature._register_new_tax writes it, so the scan gives it a row.
func _stage_born_key() -> void:
	var ns = _state_t.player()
	ns.custom_taxes["carbon"] = {"name": "Carbon levy", "base_share": 0.5, "erosion": 0.4, "ref_pct": 4.0}
	ns.tax_rates_pct["carbon"] = 4.0
	Budget.recompute(_state_t, ns)
	_tax.mark_dirty()
	_tax._refresh()


## Each row's yield now: its own revenue line on the books as they stand this
## instant (a copy committed with nothing pending -- preview's own body).
func _check_tax_yields() -> void:
	var sim = _state_t.duplicate_state()
	Budget.commit(sim, {})
	var books = sim.player()
	for key in books.tax_rates_pct:
		var want := "%.0f" % (float(books.revenue_pct_gdp[key]) / 100.0 * float(books.gdp_eur_bn))
		if _tax._yield_labels[key].text != want:
			_fail("tax %s: the yield reads '%s', the books say %s" % [key, _tax._yield_labels[key].text, want])
	if _tax._yield_labels[TaxPanel.PROGRESSIVITY_KEY].text != "—":
		_fail("tax: the brackets row has no base and should yield an em dash")


func _check_tax_rates() -> void:
	for key in _tax._lever_keys():
		var ns = _state_t.player()
		var slider: HSlider = _tax._sliders[key]
		var step := 2.0
		if key == "wealth":
			step = 0.2
		elif key == TaxPanel.PROGRESSIVITY_KEY:
			step = (TaxK.PROGRESSIVITY_MAX - TaxK.PROGRESSIVITY_MIN) * 0.1
		slider.value = _target(slider.value, slider.min_value, slider.max_value, step)
		_tax._refresh()
		var shown: float = float(_tax._effects.get(key, NAN))
		var text: String = _tax._effect_labels[key].text
		var strip_bn: float = _tax._strip.money_bn
		var before := Budget.preview(_state_t, {})
		_tax._on_commit()
		var booked := _balance_gain(before, Budget.preview(_state_t, {}))
		if is_zero_approx(booked):
			_fail("tax %s: the fixture moved nothing on the books; pick a bigger step" % key)
		if is_nan(shown) or absf(shown - booked) > CENT_BN:
			_fail("tax %s: shown %s bn, booked %.4f bn" % [key, shown, booked])
		if text != EffectsStrip.money_text(booked):
			_fail("tax %s: the cell reads '%s', the booked change prints '%s'" % [key, text, EffectsStrip.money_text(booked)])
		if absf(strip_bn - booked) > CENT_BN:
			_fail("tax %s: the strip says %.4f bn, Commit booked %.4f bn" % [key, strip_bn, booked])
		_check_tone(_tax._effect_labels[key], booked, "tax %s" % key)
		_tax._refresh()


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
