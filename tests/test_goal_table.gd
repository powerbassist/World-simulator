extends SceneTree

## V5.3 e, the goal read's "can table now" (the parent's rulings of 2026-11-14 on #342):
##   - every row a goal ranks says whether it can be tabled NOW, or the refusal tabling
##     would give: the same checks, run without writing (FinanceBill.refusal() for a
##     budget step, Legislature.refusal() for a law), never a second rule;
##   - one tax step per kind, derived from its rate range (TaxLibrary.step_pct(): about a
##     twentieth of the range, rounded to 1, 2 or 5 on a log scale, decimals to match),
##     which the goal read uses and the Tax Code slider will.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const GoalRead = preload("res://src/sim/goal_read.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Bills = preload("res://src/sim/bills.gd")

## The step every kind of data/taxes/ gets, against its rate_range_pct today. Written out
## rather than re-derived, so a change to the rule or to a range shows up here by name.
const STEPS := {
	"air_passenger_tax": [2.0, 0], "alcohol_duty": [10.0, 0], "bank_levy": [0.05, 2],
	"capital_gains": [2.0, 0], "carbon_tax": [10.0, 0], "corporate": [5.0, 0],
	"digital_services_tax": [0.5, 1], "fuel_duty": [0.02, 2], "high_income_surcharge": [0.5, 1],
	"income": [5.0, 0], "inheritance_tax": [2.0, 0], "plastic_packaging_tax": [0.1, 1],
	"property_tax": [10.0, 0], "retail_tax": [0.2, 1], "sugar_drinks_levy": [0.02, 2],
	"tobacco_duty": [10.0, 0], "transactions_tax": [0.05, 2], "vat": [2.0, 0], "wealth": [0.2, 1],
	"windfall_tax": [5.0, 0],
}

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_every_kind_has_its_step()
	_check_the_goal_read_steps_by_the_kind()
	_check_a_fresh_game_can_table_everything()
	_check_a_queued_finance_text_blocks_the_budget_steps()
	_check_a_law_in_the_slot_blocks_both()
	_check_a_rate_moved_since_the_list_reads_range()
	_check_a_kind_taken_out_of_force_reads_kind()
	_check_the_refusals_are_tablings_own()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_goal_table.gd")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL " + f)
	quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state(nation := "FRA"):
	var state = GameState.new_game(_loader, nation)
	state.year = 2026
	state.month = 3
	return state


func _rows(state, goal := "deficit") -> Array:
	var list = GoalRead.list_for(null, state, _loader)
	while not list.done():
		GoalRead.step(list)
	return GoalRead.rank(list.reads, goal, state, _loader)


func _row(rows: Array, kind: String, key: String = "") -> Dictionary:
	for row in rows:
		var m: Dictionary = row["measure"]
		if String(m["kind"]) == kind and (key == "" or String(m.get("key", m.get("id", ""))) == key):
			return row
	return {}


# --- the step -----------------------------------------------------------------

func _check_every_kind_has_its_step() -> void:
	var ns = _new_state().player()
	if ns.tax_library.size() != STEPS.size():
		_fail("step: the library has %d kinds, the table %d" % [ns.tax_library.size(), STEPS.size()])
	for kind in ns.tax_library:
		if not STEPS.has(kind):
			_fail("step: %s has no expected step" % kind)
			continue
		var step := TaxLibrary.step_pct(ns, kind)
		if not is_equal_approx(step, float(STEPS[kind][0])):
			_fail("step: %s steps by %s, want %s" % [kind, step, STEPS[kind][0]])
		if TaxLibrary.step_decimals(ns, kind) != int(STEPS[kind][1]):
			_fail("step: %s shows %d decimals, want %d" % [kind, TaxLibrary.step_decimals(ns, kind), STEPS[kind][1]])
		# A twentieth of the range to within the 1-2-5 grid's widest gap (x2.5 apart, so
		# never more than sqrt(2.5) off on the log scale).
		var span: Array = ns.tax_library[kind]["rate_range_pct"]
		var ratio := step / ((float(span[1]) - float(span[0])) / 20.0)
		if ratio < 1.0 / sqrt(2.5) - 1e-9 or ratio > sqrt(2.5) + 1e-9:
			_fail("step: %s's step %s is %sx a twentieth of its range" % [kind, step, ratio])


## The ruling's two named cases: a one-point step left France's fuel duty and Britain's
## bank levy with no step at all, their whole ranges being under a point wide.
func _check_the_goal_read_steps_by_the_kind() -> void:
	for pair in [["FRA", "fuel_duty"], ["GBR", "bank_levy"]]:
		var state = _new_state(pair[0])
		var ns = state.player()
		if not ns.tax_rates_pct.has(pair[1]):
			_fail("premise: %s does not levy %s" % pair)
			continue
		var steps := []
		for m in GoalRead.measures(state, _loader):
			if String(m["kind"]) == "rate" and String(m["key"]) == pair[1]:
				steps.append(float(m["step"]))
		if steps.is_empty():
			_fail("step: %s's %s has no step in the goal read" % pair)
		for s in steps:
			if not is_equal_approx(absf(s), TaxLibrary.step_pct(ns, pair[1])):
				_fail("step: %s's %s steps by %s, not its kind's %s" % [pair[0], pair[1], s, TaxLibrary.step_pct(ns, pair[1])])


# --- can table now ------------------------------------------------------------

func _check_a_fresh_game_can_table_everything() -> void:
	var state = _new_state()
	var rows := _rows(state, "approval")
	for kind in ["law", "rate", "line"]:
		var row := _row(rows, kind)
		if row.is_empty():
			_fail("premise: no %s ranks on approval" % kind)
		elif String(row["table"]) != "":
			_fail("fresh: a %s row reads '%s', not tableable" % [kind, row["table"]])


## One budget text at a time: a finance text in the queue refuses every budget step, and
## no law (a law's slot is free).
func _check_a_queued_finance_text_blocks_the_budget_steps() -> void:
	var state = _new_state()
	var list = GoalRead.list_for(null, state, _loader)
	while not list.done():
		GoalRead.step(list)
	state.player().bill_queue = [{"finance": {"spending_pct_gdp": {"health": 0.5}}, "force": false}]
	var rows: Array = GoalRead.rank(list.reads, "approval", state, _loader)
	for row in rows:
		var kind := String(row["measure"]["kind"])
		var want := "" if kind == "law" else "finance_queued"
		if String(row["table"]) != want:
			_fail("queued: a %s row reads '%s', want '%s'" % [kind, row["table"], want])
			return


## A law in the slot: no second law, and no finance bill beside it (table()'s rule).
func _check_a_law_in_the_slot_blocks_both() -> void:
	var state = _new_state()
	var ns = state.player()
	var list = GoalRead.list_for(null, state, _loader)
	while not list.done():
		GoalRead.step(list)
	var law_id := String(list.measures[0]["id"])
	ns.tabled_bill = {"law_id": law_id, "referendum": false, "vote_year": 2026, "vote_month": 3, "vote_day": 31}
	var seen := {}
	for row in GoalRead.rank(list.reads, "approval", state, _loader):
		seen[String(row["measure"]["kind"])] = true
		if String(row["table"]) != "already_tabled":
			_fail("slot: a %s row reads '%s' with a law tabled" % [row["measure"]["kind"], row["table"]])
			return
	if not (seen.has("law") and seen.has("rate")):
		_fail("premise: the slot case saw only %s" % [seen.keys()])


## The list is kept for the month: a rate a law moved since can leave its step outside
## the kind's band, and the row says so rather than offering a bill tabling would refuse.
func _check_a_rate_moved_since_the_list_reads_range() -> void:
	var state = _new_state()
	var ns = state.player()
	var list = GoalRead.list_for(null, state, _loader)
	while not list.done():
		GoalRead.step(list)
	ns.tax_rates_pct["vat"] = float(ns.tax_library["vat"]["rate_range_pct"][1])
	var row := {}
	for r in GoalRead.rank(list.reads, "deficit", state, _loader):
		if String(r["measure"]["kind"]) == "rate" and String(r["measure"]["key"]) == "vat" and float(r["measure"]["step"]) > 0.0:
			row = r
	if row.is_empty():
		_fail("premise: the VAT rise does not rank on the deficit")
	elif String(row["table"]) != "range":
		_fail("range: a VAT rise past the band's top reads '%s'" % row["table"])


## A kind taken out of force since the list (an autumn abolition): its steps read `kind`.
func _check_a_kind_taken_out_of_force_reads_kind() -> void:
	var state = _new_state()
	var ns = state.player()
	var list = GoalRead.list_for(null, state, _loader)
	while not list.done():
		GoalRead.step(list)
	ns.tax_rates_pct.erase("vat")
	var found := false
	for r in GoalRead.rank(list.reads, "deficit", state, _loader):
		if String(r["measure"]["kind"]) == "rate" and String(r["measure"]["key"]) == "vat":
			found = true
			if String(r["table"]) != "kind":
				_fail("kind: a step on a kind out of force reads '%s'" % r["table"])
	if not found:
		_fail("premise: no VAT step ranks on the deficit")


## The checks are tabling's: table() and propose() refuse with the very flag the pure
## checks return, and the pure checks write nothing.
func _check_the_refusals_are_tablings_own() -> void:
	var state = _new_state()
	var ns = state.player()
	ns.bill_queue = [{"finance": {"spending_pct_gdp": {"health": 0.5}}, "force": false}]
	var bill := {"tax_rates_pct": {"vat": 1.0}}
	var before := JSON.stringify(state.to_dict())
	var pure := FinanceBill.refusal(state, _loader, bill)
	if JSON.stringify(state.to_dict()) != before:
		_fail("parity: FinanceBill.refusal() wrote the game")
	var real := FinanceBill.table(state, _loader, bill)
	if pure != real or not bool(real.get("finance_queued", false)):
		_fail("parity: refusal() says %s, table() %s" % [pure, real])
	ns.bill_queue = []
	var law = Legislature.available(ns, Bills.open(state, ns, _loader))[0]
	ns.tabled_bill = {"law_id": "x", "referendum": false, "vote_year": 2026, "vote_month": 3, "vote_day": 31}
	before = JSON.stringify(state.to_dict())
	var why := Legislature.refusal(state, ns, _loader, law)
	if JSON.stringify(state.to_dict()) != before:
		_fail("parity: Legislature.refusal() wrote the game")
	var res := Legislature.propose(state, _loader, law)
	if why != "already_tabled" or not bool(res.get(why, false)):
		_fail("parity: refusal() says '%s', propose() %s" % [why, res.keys()])
