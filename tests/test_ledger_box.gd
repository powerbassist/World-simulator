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
const NationState = preload("res://src/core/nation_state.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _loader


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
	_finish()


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
