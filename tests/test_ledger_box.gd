extends SceneTree

## Headless test: godot --headless --script res://tests/test_ledger_box.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4, PR 3: the typed box beside a ledger slider (ledger_box.gd). The slider steps by
## the SIM's one step per kind (TaxLibrary.step_pct); the box takes the exact rate, so the figure
## a nation starts with prints back whole -- France's fuel duty is 0.67 on a slider that steps by
## 0.02. Pinned here: every nation's every starting rate prints and parses back exactly; the comma
## reads and writes in French; a typed rate reaches the draft exactly and alone; an untouched row
## never enters a bill, whatever it was focused and left over.

const GameState = preload("res://src/core/game_state.gd")
const LedgerBox = preload("res://src/ui/ledger_box.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const TaxPanel = preload("res://src/ui/tax_panel.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Strings = preload("res://src/ui/strings.gd")

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
	_check_every_start_rate_prints_back()
	_check_parse()
	_check_french()
	_state = GameState.new_game(_loader, "FRA")
	_panel = TaxPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_panel.setup(_state, _loader)
			_panel.show()
			_panel._refresh()
		2:
			_check_the_slider_steps_by_the_sims_step()
			_check_a_focused_untouched_row_stays_out_of_the_bill()
			_check_a_typed_rate_is_exact()
			_check_a_refused_entry_puts_the_figure_back()
			_finish()
	return false


## Every kind a nation carries, at the rate it starts with: print it at the kind's step decimals,
## read it back, and it is the same number.
func _check_every_start_rate_prints_back() -> void:
	var checked := 0
	for id in _loader.nations:
		var ns := NationState.new()
		ns.tax_library = TaxLibrary.for_nation(_loader.taxes, _loader.nations[id].tax_base_share)
		for kind in _loader.nations[id].tax_rates_pct:
			var rate := float(_loader.nations[id].tax_rates_pct[kind])
			var shown := LedgerBox.text(rate, TaxLibrary.step_decimals(ns, String(kind)))
			if absf(LedgerBox.parse(shown) - rate) > 1e-9:
				_fail("%s's %s starts at %s and its box prints '%s'" % [id, kind, rate, shown])
			checked += 1
	if checked < 100:
		_fail("premise: only %d starting rates were checked" % checked)


func _check_parse() -> void:
	for bad in ["", "abc", "1.2.3", "--4", "%"]:
		if not is_nan(LedgerBox.parse(bad)):
			_fail("'%s' parsed as a number" % bad)
	if LedgerBox.parse(" 0,67 ") != 0.67 or LedgerBox.parse("0.67") != 0.67 or LedgerBox.parse("22") != 22.0:
		_fail("the box does not read a comma, a point or a whole figure")
	# Four decimals at most: past that a figure is rounding noise, and it prints so.
	if LedgerBox.text(0.123456, 1) != "0.1235":
		_fail("a figure with noise past three decimals prints '%s'" % LedgerBox.text(0.123456, 1))
	if LedgerBox.text(8.1, 0) != "8.1" or LedgerBox.text(20.0, 0) != "20":
		_fail("the shortest exact decimals are not shown: '%s' / '%s'" % [LedgerBox.text(8.1, 0), LedgerBox.text(20.0, 0)])


func _check_french() -> void:
	if not Strings.set_language("fr"):
		_fail("premise: French is not offered")
		return
	if LedgerBox.text(0.67, 2) != "0,67" or LedgerBox.parse(LedgerBox.text(0.67, 2)) != 0.67:
		_fail("French does not write and read the comma: '%s'" % LedgerBox.text(0.67, 2))
	Strings.set_language("en")


## The sim's step is the slider's step: a kind's own grid, not 0.1 for every row.
func _check_the_slider_steps_by_the_sims_step() -> void:
	var ns = _state.player()
	for kind in ns.tax_rates_pct:
		var slider: HSlider = _panel._sliders[kind]
		if not is_equal_approx(slider.step, TaxLibrary.step_pct(ns, String(kind))):
			_fail("%s's slider steps by %s, the sim's step is %s" % [kind, slider.step, TaxLibrary.step_pct(ns, String(kind))])


## Focus in and out of a row whose figure the box rounds must not rewrite the rate nor draft it.
func _check_a_focused_untouched_row_stays_out_of_the_bill() -> void:
	var ns = _state.player()
	ns.tax_rates_pct["income"] = 21.4567
	_panel.mark_dirty()
	_panel._refresh()
	var box: LineEdit = _panel._lever_values["income"]
	box.focus_exited.emit()
	if _panel._edited_keys.has("income") or not _panel.draft().is_empty():
		_fail("leaving a row it did not touch drafted it")
	if not FinanceBill.from_pending(ns, _panel._pending).is_empty():
		_fail("an untouched ledger tables a bill: %s" % [FinanceBill.from_pending(ns, _panel._pending)])
	ns.tax_rates_pct["income"] = 20.0
	_panel.mark_dirty()
	_panel._refresh()


## Enter on a typed figure: the draft carries it exactly (not rounded to the slider's grid), alone.
func _check_a_typed_rate_is_exact() -> void:
	var ns = _state.player()
	var box: LineEdit = _panel._lever_values["income"]
	box.text = "22,35"
	box.text_submitted.emit(box.text)
	var pending := float(_panel._pending["tax_rates_pct"]["income"])
	if absf(pending - 22.35) > 1e-9:
		_fail("a typed 22,35 drafts %s" % pending)
	var bill := FinanceBill.from_pending(ns, _panel._pending)
	if bill.get("tax_rates_pct", {}).keys() != ["income"]:
		_fail("a typed rate tables more than its own row: %s" % [bill])
	# Past the range it stops at the range, like the slider.
	box.text = "9999"
	box.text_submitted.emit(box.text)
	if float(_panel._pending["tax_rates_pct"]["income"]) != float(ns.tax_library["income"]["rate_range_pct"][1]):
		_fail("a typed rate past the ceiling drafts %s" % _panel._pending["tax_rates_pct"]["income"])


func _check_a_refused_entry_puts_the_figure_back() -> void:
	var box: LineEdit = _panel._lever_values["vat"]
	var shown := box.text
	box.text = "lots"
	box.text_submitted.emit(box.text)
	if box.text != shown or _panel._edited_keys.has("vat"):
		_fail("a word in the box drafted VAT or left '%s' for '%s'" % [box.text, shown])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_ledger_box: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
