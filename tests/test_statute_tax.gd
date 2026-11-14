extends SceneTree

## The composed tax RATE channel on the authored five, and the closed door
## behind it.
##
## V4.2 T4 let a composed bill BIRTH a tax key through a params register;
## V5.3 e retired that path in favour of the tax library
## (docs/design/finance-bill.md 9.4). What this file pins now:
##   - THE RATE CHANNEL STAYS: a composed bill moving an authored key's rate
##     drafts, composes and lands its rate through the ONE applier;
##   - NO KEY OUTSIDE THE FIVE: a pending rate for any other key is refused
##     loudly at Budget.apply_pending, and the register keeps no trace of it --
##     a rate with no model behind it is the silent half-tax;
##   - THE REVENUE LINES ARE THE FIVE: revenue_lines() returns exactly the
##     authored keys;
##   - THE RESERVED LINE NAMES derive from the writer (the ultra pass-19 pin):
##     COMPUTED_REVENUE_LINES is exactly what Budget.recompute() writes over the
##     modelled dict, so a tax id can never be checked against a stale list.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Law = preload("res://src/core/law.gd")
const Statute = preload("res://src/sim/statute.gd")
const Budget = preload("res://src/sim/budget.gd")
const TaxesLoader = preload("res://src/core/loaders/taxes_loader.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_test_composed_rate_on_an_authored_key()
		_test_key_outside_the_five_refused()
		_test_revenue_lines_are_the_five()
		_test_reserved_names_derive_from_the_writer()
	_finish()


func _fresh():
	var gs = GameState.new_game(_loader, PLAYER)
	return [gs, gs.player()]


func _test_composed_rate_on_an_authored_key() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var before := float(ns.tax_rates_pct["income"])
	var r: Dictionary = Statute.draft(gs, ns, _loader, {
		"name": "The Income Act",
		"position": {"economic": -0.2, "social": 0.0},
		"channels": {"tax_rates_pct": {"income": 1.0}},
	})
	if not bool(r.get("ok", false)):
		_fail("a composed rate on an authored key must draft: %s" % r.get("refusal", ""))
		return
	var draft_id := String(r.get("draft_id", ""))
	for i in range(int(ns.draft_bills[draft_id]["months_left"])):
		Statute.tick_month(gs, _loader)
	if not ns.custom_laws.has(draft_id):
		_fail("the rate bill did not compose at countdown 0")
		return
	var law = Law.composed_from_dict(ns.custom_laws[draft_id])
	if String(law.theme) != "tax":
		_fail("a rate bill must read tax, not '%s'" % law.theme)
	Legislature.apply(gs, ns, law, _loader)
	if not is_equal_approx(float(ns.tax_rates_pct["income"]), before + 1.0):
		_fail("the composed rate must land through the one applier: %s, expected %s"
			% [ns.tax_rates_pct["income"], before + 1.0])


func _test_key_outside_the_five_refused() -> void:
	var pair = _fresh()
	var gs = pair[0]
	var ns = pair[1]
	var rates_before: Dictionary = ns.tax_rates_pct.duplicate(true)
	## expects-error: budget: pending rate for tax key 'carbon', which the tax library does not define
	Budget.commit(gs, {"tax_rates_pct": {"carbon": 5.0}})
	if ns.tax_rates_pct.has("carbon"):
		_fail("a pending rate for a key outside the five must be refused -- the silent half-tax")
	if ns.tax_rates_pct != rates_before:
		_fail("a refused key must leave every live rate untouched: %s vs %s" % [ns.tax_rates_pct, rates_before])


func _test_revenue_lines_are_the_five() -> void:
	var pair = _fresh()
	var ns = pair[1]
	var lines: Dictionary = Budget.revenue_lines(ns.tax_rates_pct, ns.start_tax_rates_pct, ns.tax_library)
	var keys: Array = lines.keys()
	# The kinds the nation has in force, in library order: today's five first, then the
	# researched kinds its data levies (France levies more than the five since the tax rows).
	var expected: Array = []
	for kind in _loader.taxes:
		if ns.tax_rates_pct.has(kind):
			expected.append(kind)
	if keys.slice(0, TaxesLoader.FIRST.size()) != TaxesLoader.FIRST:
		_fail("revenue_lines() must open on the authored five in library order: %s" % [keys])
	if keys != expected:
		_fail("revenue_lines() must return exactly the kinds in force, in library order: %s, not %s" % [keys, expected])


## The re-deriving pin (the ultra pass-19 finding): the reserved names are
## exactly the computed lines Budget.recompute() writes over the modelled
## dict. This file re-derives the set from budget.gd's SOURCE so the constant
## cannot silently drift from the writer -- a fourth computed line added
## without growing COMPUTED_REVENUE_LINES turns this red.
func _test_reserved_names_derive_from_the_writer() -> void:
	var source := FileAccess.get_file_as_string("res://src/sim/budget.gd")
	var regex := RegEx.new()
	regex.compile('ns[.]revenue_pct_gdp[[]"([a-z_]+)"] *=')
	var derived := {}
	for match_ in regex.search_all(source):
		derived[match_.get_string(1)] = true
	for reserved in Budget.COMPUTED_REVENUE_LINES:
		if not derived.has(reserved):
			_fail("COMPUTED_REVENUE_LINES carries '%s', which budget.gd no longer writes" % reserved)
	for written in derived:
		if not Budget.COMPUTED_REVENUE_LINES.has(written):
			_fail("budget.gd writes computed line '%s' that COMPUTED_REVENUE_LINES does not reserve" % written)


func _fail(message: String) -> void:
	_failures.append(message)
	print("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("OK: all statute tax checks passed")
		quit(0)
	else:
		print("%d failures" % _failures.size())
		quit(1)
