extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_draft.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4, Finances slice 2: the ONE draft behind the row editor. Pinned: an untouched page
## drafts nothing (an off-grid rate is never snapped into a bill), a moved row is a delta of the bill, a
## row dragged back to its live value is no row, a row the player has not touched follows the register
## while one they moved stays theirs, the brackets ride as the bill's own scalar, and the bill the draft
## writes is the one FinanceBill.table accepts.

const GameState = preload("res://src/core/game_state.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return
	for nation in ["FRA", "GBR", "DEU", "POL"]:
		_check_untouched_drafts_nothing(loader, nation)
	var state = GameState.new_game(loader, "FRA")
	var draft := FinanceDraft.new()
	draft.setup(state)
	_check_a_moved_row_is_a_delta(state, draft)
	_check_back_to_live_is_no_row(state, draft)
	_check_untouched_follows_live_edited_stays(state, draft)
	_check_the_brackets_ride_as_a_scalar(state, draft)
	_check_the_bill_tables(state, loader, draft)
	_finish()


## Every row of every playable nation, read: the draft holds nothing and its bill is empty. A slider
## that wrote its init value into the draft would make 0.6545 into 0.7 here.
func _check_untouched_drafts_nothing(loader, nation: String) -> void:
	var state = GameState.new_game(loader, nation)
	var draft := FinanceDraft.new()
	draft.setup(state)
	var ns = state.player()
	for kind in ns.tax_rates_pct:
		if draft.value(FinanceDraft.TAX, String(kind)) != float(ns.tax_rates_pct[kind]):
			_fail("%s: the draft reads %s differently from the register" % [nation, kind])
	for key in ns.spending_pct_gdp:
		if draft.value(FinanceDraft.SPENDING, String(key)) != float(ns.spending_pct_gdp[key]):
			_fail("%s: the draft reads %s differently from the register" % [nation, key])
	if not draft.is_empty() or draft.bill() != {} or draft.pending() != {}:
		_fail("%s: an untouched draft is not empty: bill %s" % [nation, draft.bill()])


func _check_a_moved_row_is_a_delta(state, draft) -> void:
	var ns = state.player()
	var vat := float(ns.tax_rates_pct["vat"])
	var health := float(ns.spending_pct_gdp["health"])
	draft.set_value(FinanceDraft.TAX, "vat", vat + 2.0)
	draft.set_value(FinanceDraft.SPENDING, "health", health + 1.5)
	if draft.count() != 2:
		_fail("two moved rows count %d" % draft.count())
	var bill: Dictionary = draft.bill()
	if not is_equal_approx(float(bill.get("tax_rates_pct", {}).get("vat", 0.0)), 2.0):
		_fail("the VAT row is not +2.0 in the bill: %s" % [bill])
	if not is_equal_approx(float(bill.get("spending_pct_gdp", {}).get("health", 0.0)), 1.5):
		_fail("the health row is not +1.5 in the bill: %s" % [bill])
	if draft.rows()[0]["channel"] != FinanceDraft.SPENDING:
		_fail("rows are not spending first")
	draft.revert()
	if not draft.is_empty():
		_fail("revert left rows behind")


func _check_back_to_live_is_no_row(state, draft) -> void:
	var live := float(state.player().tax_rates_pct["income"])
	draft.set_value(FinanceDraft.TAX, "income", live + 1.0)
	draft.set_value(FinanceDraft.TAX, "income", live)
	if not draft.is_empty() or draft.bill() != {}:
		_fail("a rate dragged back to its live value is still a row: %s" % [draft.rows()])


func _check_untouched_follows_live_edited_stays(state, draft) -> void:
	var ns = state.player()
	var vat := float(ns.tax_rates_pct["vat"])
	var income := float(ns.tax_rates_pct["income"])
	draft.set_value(FinanceDraft.TAX, "income", income + 3.0)
	ns.tax_rates_pct["vat"] = vat + 1.0
	if draft.value(FinanceDraft.TAX, "vat") != vat + 1.0:
		_fail("an untouched row did not follow the register")
	if draft.is_moved(FinanceDraft.TAX, "vat"):
		_fail("a rate the register moved shows as the player's row")
	ns.tax_rates_pct["income"] = income + 1.0
	if not is_equal_approx(draft.value(FinanceDraft.TAX, "income"), income + 3.0):
		_fail("a moved row did not stay the player's when the register moved")
	if not is_equal_approx(float(draft.bill()["tax_rates_pct"]["income"]), 2.0):
		_fail("the delta is not read against the live register now: %s" % [draft.bill()])
	ns.tax_rates_pct["vat"] = vat
	ns.tax_rates_pct["income"] = income
	draft.revert()


func _check_the_brackets_ride_as_a_scalar(state, draft) -> void:
	var live := float(state.player().tax_progressivity)
	draft.set_brackets(live + 0.2)
	var bill: Dictionary = draft.bill()
	if not is_equal_approx(float(bill.get(FinanceDraft.BRACKETS, 0.0)), 0.2):
		_fail("the brackets are not the bill's scalar: %s" % [bill])
	if draft.rows()[0]["channel"] != FinanceDraft.BRACKETS:
		_fail("the brackets are not a row")
	draft.revert()
	if draft.value(FinanceDraft.BRACKETS, "") != live:
		_fail("revert did not put the brackets back")


func _check_the_bill_tables(state, loader, draft) -> void:
	var ns = state.player()
	draft.set_value(FinanceDraft.TAX, "vat", float(ns.tax_rates_pct["vat"]) + 1.0)
	var tabling: Dictionary = FinanceBill.table(state, loader, draft.bill())
	if not bool(tabling.get("tabled", false)):
		_fail("the draft's bill was refused: %s" % [tabling])
	draft.revert()


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_finance_draft: all checks passed")
		quit(0)
	else:
		print("test_finance_draft: %d failure(s)" % _failures.size())
		quit(1)
